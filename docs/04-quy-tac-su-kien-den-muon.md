# CHƯƠNG 5 & 7: QUY TẮC XỬ LÝ SỰ KIỆN ĐẾN MUỘN (BR-06), CHỐNG GỬI TRÙNG (BR-07) VÀ GIAO DỊCH ĐỒNG THỜI

Tài liệu này đặc tả chi tiết cơ chế bảo toàn tính nhất quán dữ liệu của **Đề tài 13** trước 3 bài toán cốt lõi trong vận hành logistics thực tế: **Sự kiện đến muộn (*Out-of-order / Late-arriving Events* – `BR-06`)**, **Sự kiện gửi trùng (*Idempotency* – `BR-07`)**, và **Tranh chấp cập nhật đồng thời (*Concurrency Control* – Khóa bi quan `FOR UPDATE`)**.

---

## 1. Bản chất Bài toán Sự kiện Đến muộn (`BR-06`) và Gửi trùng (`BR-07`)

### 1.1. Hiện tượng Sự kiện Đến muộn (*Out-of-order / Late-arriving Events*)
Trong thực tế vận hành kho bãi và giao nhận chặng cuối:
- Lúc **`08:00`**, nhân viên kho quét mã nhập kho (`NHAP_KHO`) cho bưu kiện `PK00000001` bằng thiết bị cầm tay (*handheld scanner*), nhưng thiết bị đang ở góc khuất sóng Wi-Fi/4G nên bản tin được lưu tạm trong hàng đợi ngoại tuyến (*offline queue*) của thiết bị.
- Lúc **`09:00`**, bưu kiện được xuất kho và bàn giao lên xe (`DANG_VAN_CHUYEN`) tại cổng xuất có kết nối mạng ổn định; máy chủ lập tức ghi nhận sự kiện `DANG_VAN_CHUYEN` lúc `09:00:05` (`thoi_gian_xay_ra = 09:00`, `thoi_gian_ghi_nhan = 09:00:05`).
- Lúc **`09:30`**, thiết bị cầm tay của nhân viên kho kết nối mạng trở lại và đồng bộ bù sự kiện `NHAP_KHO` ban đầu về máy chủ (`thoi_gian_xay_ra = 08:00`, `thoi_gian_ghi_nhan = 09:30:00`).

> [!WARNING]
> **Rủi ro nếu cập nhật mù quáng (*Blind Update*):** Nếu hệ thống cứ mỗi lần nhận lệnh `INSERT` sự kiện mới lại ghi đè thẳng `trang_thai_hien_tai` của bưu kiện theo bản tin vừa tới, trạng thái của `PK00000001` lúc `09:30` sẽ bị **đẩy lùi từ `DANG_VAN_CHUYEN` về lại `NHAP_KHO`**, làm sai lệch hoàn toàn thông tin theo dõi đơn hàng.

### 1.2. Phát biểu Quy tắc Nghiệp vụ `BR-06`
1. **Bảo toàn lịch sử tuyệt đối (*Append-only Audit Trail*):** Mọi sự kiện hợp lệ đến muộn **bắt buộc vẫn phải được `INSERT` đầy đủ** vào bảng `SuKienTrangThai` với đúng `thoi_gian_xay_ra` thực tế và `thoi_gian_ghi_nhan` lúc máy chủ tiếp nhận để phục vụ truy vết hành trình và tính thời gian lưu kho.
2. **Bảo vệ trạng thái hiện tại (*Monotonic State Progression*):** Trạng thái hiện tại của bưu kiện (`trang_thai_hien_tai`, `thoi_gian_cap_nhat_cuoi`) **chỉ được cập nhật** khi sự kiện mới có `thoi_gian_xay_ra >= thoi_gian_cap_nhat_cuoi` hiện có. Tuyệt đối không để sự kiện đến muộn làm quay lùi trạng thái hiện tại về quá khứ.

---

## 2. Giải thuật Xử lý Sự kiện Đến muộn trên Hai Phương án (`PA_A` vs `PA_B`)

### 2.1. Trên Phương án A (`pa_a` – History-based)
Vì `pa_a.BuuKien` không lưu cột trạng thái hiện tại mà suy diễn động khi đọc bằng cách sắp xếp theo **`thoi_gian_xay_ra DESC`** (chứ không phải `thoi_gian_ghi_nhan`), nên khi sự kiện đến muộn được chèn thêm vào bảng `pa_a.SuKienTrangThai`, bản ghi đó tự động nằm ở vị trí quá khứ đúng với mốc `thoi_gian_xay_ra` của nó. Do đó, kết quả suy diễn trạng thái hiện tại ở `pa_a` luôn tự động chính xác.

### 2.2. Trên Phương án B (`pa_b` – Current-state): Trigger `trg_cap_nhat_trang_thai`
Trên schema `pa_b`, trạng thái hiện tại được bảo vệ tự động ở tầng CSDL bằng Trigger PL/pgSQL ([sql/02_triggers_functions.sql](file:///c:/CSDLnangcao/CSDLNC-Nhom13-van-chuyen-buu-kien/sql/02_triggers_functions.sql)):

```sql
CREATE OR REPLACE FUNCTION pa_b.fn_cap_nhat_trang_thai_buu_kien()
RETURNS TRIGGER AS $$
DECLARE
    v_thoi_gian_moi_nhat TIMESTAMP;
BEGIN
    -- 1. Tìm mốc thời gian xảy ra sự kiện mới nhất hiện có của bưu kiện
    SELECT thoi_gian_cap_nhat_cuoi INTO v_thoi_gian_moi_nhat
    FROM pa_b.BuuKien
    WHERE ma_buu_kien = NEW.ma_buu_kien;

    -- 2. Xử lý sự kiện đến muộn (Late-arriving Event - BR-06):
    -- Chỉ cập nhật trạng thái hiện tại nếu sự kiện mới có thoi_gian_xay_ra >= thoi_gian_cap_nhat_cuoi.
    -- Nếu sự kiện đến muộn (NEW.thoi_gian_xay_ra < v_thoi_gian_moi_nhat), vẫn giữ dòng INSERT
    -- trong bảng SuKienTrangThai nhưng KHÔNG UPDATE quay lùi bảng BuuKien.
    IF v_thoi_gian_moi_nhat IS NULL OR NEW.thoi_gian_xay_ra >= v_thoi_gian_moi_nhat THEN
        UPDATE pa_b.BuuKien
        SET 
            trang_thai_hien_tai = NEW.ma_trang_thai,
            thoi_gian_cap_nhat_cuoi = NEW.thoi_gian_xay_ra
        WHERE ma_buu_kien = NEW.ma_buu_kien;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cap_nhat_trang_thai ON pa_b.SuKienTrangThai;
CREATE TRIGGER trg_cap_nhat_trang_thai
AFTER INSERT ON pa_b.SuKienTrangThai
FOR EACH ROW
EXECUTE FUNCTION pa_b.fn_cap_nhat_trang_thai_buu_kien();
```

### 2.3. Bảng Mô phỏng Minh chứng Xử lý Sự kiện Đến muộn và Gửi trùng
Xét bưu kiện `PK00000001` với chuỗi 4 thao tác gửi bản tin sự kiện liên tiếp:

| Thứ tự nhận (`thoi_gian_ghi_nhan`) | Sự kiện gửi vào (`ma_trang_thai`) | Thời điểm xảy ra (`thoi_gian_xay_ra`) | Khóa chống trùng (`idempotency_key`) | Phản ứng của CSDL & Trigger `pa_b` | Số dòng lịch sử | `trang_thai_hien_tai` trên `BuuKien` |
| :---: | :---: | :---: | :---: | :--- | :---: | :---: |
| **Bước 1** (`08:00:05`) | `TIEP_NHAN` | `08:00:00` | `KEY-01` | `INSERT` thành công; `08:00 >= NULL` $\rightarrow$ `UPDATE BuuKien` | 1 | **`TIEP_NHAN`** (`08:00:00`) |
| **Bước 2** (`09:00:05`) | `DANG_VAN_CHUYEN` | `09:00:00` | `KEY-02` | `INSERT` thành công; `09:00 >= 08:00` $\rightarrow$ `UPDATE BuuKien` | 2 | **`DANG_VAN_CHUYEN`** (`09:00:00`) |
| **Bước 3** (`09:01:00`) *(Gửi trùng)* | `DANG_VAN_CHUYEN` | `09:00:00` | `KEY-02` *(Trùng)* | Bị chặn bởi `ON CONFLICT (idempotency_key) DO NOTHING` (`BR-07`) | **2** *(Không tăng)* | **`DANG_VAN_CHUYEN`** (`09:00:00`) |
| **Bước 4** (`09:30:00`) *(Đến muộn)* | `NHAP_KHO` | **`08:30:00`** | `KEY-03` | `INSERT` vào lịch sử; Trigger thấy `08:30 < 09:00` $\rightarrow$ **Không `UPDATE` `BuuKien`** (`BR-06`) | **3** *(Đủ lịch sử)* | **`DANG_VAN_CHUYEN`** *(Không bị lùi về `NHAP_KHO`)* |

---

## 3. Truy vấn Phát hiện Sự kiện Đến muộn trên Chuỗi Lịch sử (`Q1`)

Một sự kiện $e_i$ được xác định là **đến muộn** nếu tại thời điểm hệ thống ghi nhận nó (`thoi_gian_ghi_nhan`), trong CSDL **đã tồn tại ít nhất một sự kiện được ghi nhận trước đó** nhưng lại có thời điểm xảy ra thực tế (`thoi_gian_xay_ra`) muộn hơn $e_i$:
$$\text{ Đến muộn } \iff e_i.\text{thoi\_gian\_xay\_ra} < \max_{e_j.\text{thoi\_gian\_ghi\_nhan} < e_i.\text{thoi\_gian\_ghi\_nhan}} \left( e_j.\text{thoi\_gian\_xay\_ra} \right)$$

Câu truy vấn **Q1** trong [sql/05_sql_advanced.sql](file:///c:/CSDLnangcao/CSDLNC-Nhom13-van-chuyen-buu-kien/sql/05_sql_advanced.sql#L29-L46) sử dụng hàm cửa sổ lũy kế `MAX() OVER (ORDER BY thoi_gian_ghi_nhan ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)` để tự động phát hiện và gắn nhãn `'DEN_MUON'`:

```sql
SELECT
    ROW_NUMBER() OVER (ORDER BY sk.thoi_gian_xay_ra, sk.ma_su_kien) AS buoc,
    sk.ma_su_kien,
    sk.ma_trang_thai,
    d.ten_diem,
    sk.thoi_gian_xay_ra,
    sk.thoi_gian_ghi_nhan,
    -- Đến muộn: đã tồn tại sự kiện có thời điểm xảy ra muộn hơn được ghi nhận TRƯỚC nó
    CASE
        WHEN sk.thoi_gian_xay_ra < MAX(sk.thoi_gian_xay_ra) OVER (
                 ORDER BY sk.thoi_gian_ghi_nhan, sk.ma_su_kien
                 ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
        THEN 'DEN_MUON' ELSE 'BINH_THUONG'
    END AS ghi_chu_den_muon
FROM pa_a.SuKienTrangThai sk
LEFT JOIN pa_a.DiemGiaoNhan d ON d.ma_diem_giao_nhan = sk.ma_diem
WHERE sk.ma_buu_kien = 'PK00000001'
ORDER BY sk.thoi_gian_xay_ra, sk.ma_su_kien;
```

---

## 4. Cơ chế Chống Sự kiện Gửi trùng (`BR-07` – Idempotency Key)

Khi thiết bị quét mã hoặc ứng dụng của Shipper gửi bản tin sự kiện qua mạng di động không ổn định, client có thể không nhận được gói tin phản hồi ACK dù máy chủ đã ghi thành công, dẫn đến việc client tự động gửi lại (*retry*) cùng một bản tin.

Hệ thống triệt tiêu 100% sự kiện trùng lặp nhờ kết hợp 2 lớp bảo vệ:
1. **Ràng buộc toàn vẹn mức bảng (`DDL`):** Khai báo `idempotency_key VARCHAR(100) UNIQUE NOT NULL` trên bảng `SuKienTrangThai`, tự động tạo chỉ mục B-Tree duy nhất.
2. **Mệnh đề xử lý xung đột nguyên tử (`DML`):**
   ```sql
   INSERT INTO pa_b.SuKienTrangThai (
       ma_su_kien, ma_buu_kien, ma_trang_thai, ma_diem,
       loai_su_kien, thoi_gian_xay_ra, thoi_gian_ghi_nhan, idempotency_key
   ) VALUES (
       ..., p_idempotency_key
   )
   ON CONFLICT (idempotency_key) DO NOTHING;
   ```
   Khi bản tin retry mang cùng `idempotency_key` đến lần thứ 2, PostgreSQL phát hiện trùng khóa trong chỉ mục B-Tree và bỏ qua thao tác chèn (`ROW_COUNT = 0`), **không ném lỗi làm đứt giao dịch của ứng dụng** và **không kích hoạt lại Trigger `AFTER INSERT`**.

---

## 5. Giao dịch Bàn giao Nguyên tử và Kiểm soát Đồng thời (`Q10` & Khóa bi quan `FOR UPDATE`)

### 5.1. Thủ tục Giao dịch Bàn giao Nguyên tử (`pa_b.sp_ban_giao_va_cap_nhat_trang_thai`)
Để kết hợp trọn vẹn cả 4 quy tắc (`BR-03` chuyển trạng thái hợp lệ, `BR-04` ghi nhận bàn giao, `BR-05` chặn trạng thái kết thúc, `BR-06` sự kiện đến muộn và `BR-07` chống gửi trùng) cùng cơ chế chống cập nhật đồng thời, thủ tục `sp_ban_giao_va_cap_nhat_trang_thai` ([sql/05_sql_advanced.sql](file:///c:/CSDLnangcao/CSDLNC-Nhom13-van-chuyen-buu-kien/sql/05_sql_advanced.sql#L408-L470)) thực hiện:

```sql
CREATE OR REPLACE PROCEDURE pa_b.sp_ban_giao_va_cap_nhat_trang_thai(
    p_ma_ban_giao     VARCHAR,
    p_ma_su_kien      VARCHAR,
    p_ma_buu_kien     VARCHAR,
    p_ma_nhan_vien    VARCHAR,
    p_ma_diem         VARCHAR,
    p_ma_chuyen       VARCHAR,
    p_trang_thai_moi  VARCHAR,
    p_tinh_trang      VARCHAR,
    p_ghi_chu         TEXT,
    p_thoi_gian_xr    TIMESTAMP,
    p_idempotency_key VARCHAR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_trang_thai_hien_tai VARCHAR(30);
    v_thoi_gian_cuoi      TIMESTAMP;
    v_so_dong_chen        INT;
BEGIN
    -- 1. Khóa bi quan dòng bưu kiện (SELECT ... FOR UPDATE) để chống cập nhật đồng thời
    SELECT trang_thai_hien_tai, thoi_gian_cap_nhat_cuoi
    INTO v_trang_thai_hien_tai, v_thoi_gian_cuoi
    FROM pa_b.BuuKien
    WHERE ma_buu_kien = p_ma_buu_kien
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Khong tim thay buu kien: %', p_ma_buu_kien;
    END IF;

    -- 2. Nếu là sự kiện mới (không phải sự kiện đến muộn), kiểm tra quy tắc chuyển trạng thái BR-03 & BR-05
    IF v_thoi_gian_cuoi IS NULL OR p_thoi_gian_xr >= v_thoi_gian_cuoi THEN
        IF NOT pa_b.fn_kiem_tra_chuyen_trang_thai(v_trang_thai_hien_tai, p_trang_thai_moi) THEN
            RAISE EXCEPTION 'Vi pham BR-03/BR-05: Khong the chuyen tu % sang % cho buu kien %',
                v_trang_thai_hien_tai, p_trang_thai_moi, p_ma_buu_kien;
        END IF;
    END IF;

    -- 3. Ghi nhận sự kiện trạng thái (chống gửi trùng bằng idempotency_key theo BR-07)
    INSERT INTO pa_b.SuKienTrangThai (
        ma_su_kien, ma_buu_kien, ma_trang_thai, ma_diem,
        loai_su_kien, thoi_gian_xay_ra, thoi_gian_ghi_nhan, idempotency_key
    ) VALUES (
        p_ma_su_kien, p_ma_buu_kien, p_trang_thai_moi, p_ma_diem,
        'BAN_GIAO_CAP_NHAT', p_thoi_gian_xr, CURRENT_TIMESTAMP, p_idempotency_key
    )
    ON CONFLICT (idempotency_key) DO NOTHING;

    GET DIAGNOSTICS v_so_dong_chen = ROW_COUNT;

    -- 4. Chỉ lập biên bản bàn giao nếu sự kiện không phải là bản tin retry trùng lặp
    IF v_so_dong_chen > 0 THEN
        INSERT INTO pa_b.LanBanGiao (
            ma_ban_giao, ma_buu_kien, ma_nhan_vien, ma_diem_giao_nhan,
            ma_chuyen, thoi_gian_ban_giao, tinh_trang, ghi_chu
        ) VALUES (
            p_ma_ban_giao, p_ma_buu_kien, p_ma_nhan_vien, p_ma_diem,
            p_ma_chuyen, p_thoi_gian_xr, COALESCE(p_tinh_trang, 'NGUYEN_VEN'), p_ghi_chu
        )
        ON CONFLICT (ma_ban_giao) DO NOTHING;
    END IF;
END;
$$;
```

### 5.2. Cơ chế Khóa bi quan (`SELECT ... FOR UPDATE`) và Rào chắn Trạng thái Tiền đề (*State Predicate Guard*)
Khi hai phiên làm việc (Session 1 và Session 2) đồng thời thao tác trên cùng một bưu kiện `PK00000001` đang ở trạng thái `'NHAP_KHO'` ([sql/transaction_concurrency.sql](file:///c:/CSDLnangcao/CSDLNC-Nhom13-van-chuyen-buu-kien/sql/transaction_concurrency.sql)):
1. **Session 1** thực thi `SELECT ... FROM pa_b.buukien WHERE ma_buu_kien = 'PK00000001' FOR UPDATE;`, chiếm khóa độc quyền cấp dòng (*Row-level Exclusive Lock*) trên bản ghi bưu kiện.
2. **Session 2** đồng thời thực thi câu lệnh:
   ```sql
   UPDATE pa_b.buukien
   SET trang_thai_hien_tai = 'DANG_GIAO'
   WHERE ma_buu_kien = 'PK00000001'
     AND trang_thai_hien_tai = 'NHAP_KHO'; -- Rào chắn Kiểm tra Trạng thái Tiền đề!
   ```
   Do Session 1 đang giữ khóa, Session 2 lập tức bị đưa vào trạng thái chờ khóa (`wait_event_type = 'Lock'`, `wait_event = 'transactionid'`).
3. Khi **Session 1** cập nhật trạng thái sang `'XUAT_KHO'` và `COMMIT`, khóa dòng được giải phóng.
4. Ở mức cô lập `READ COMMITTED` mặc định của PostgreSQL, **Session 2** được đánh thức và tự động **đánh giá lại điều kiện `WHERE`** trên phiên bản dữ liệu mới nhất vừa được Session 1 commit. Vì `trang_thai_hien_tai` lúc này đã là `'XUAT_KHO'` (không còn thỏa điều kiện `AND trang_thai_hien_tai = 'NHAP_KHO'`), câu lệnh của Session 2 trả về **`UPDATE 0`**, ngăn chặn triệt để hiện tượng ghi đè mất mát dữ liệu (**Lost Update**).

> Xem chi tiết số liệu đo đạc hiệu năng và bảng kết quả kiểm thử giao dịch tại: [docs/05-so-sanh-hai-phuong-an.md](file:///c:/CSDLnangcao/CSDLNC-Nhom13-van-chuyen-buu-kien/docs/05-so-sanh-hai-phuong-an.md).
