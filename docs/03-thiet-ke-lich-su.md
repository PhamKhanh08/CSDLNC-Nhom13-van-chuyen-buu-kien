# CHƯƠNG 5: THIẾT KẾ LỊCH SỬ DỮ LIỆU (EVENT TIME vs INGEST TIME) VÀ KIẾN TRÚC PA_A vs PA_B

Tài liệu này trình bày thiết kế lưu trữ lịch sử sự kiện theo hai mốc thời gian (**Event Time** và **Ingest Time**), kiến trúc vật lý đối sánh giữa **Phương án A (`pa_a` - History-based)** và **Phương án B (`pa_b` - Current-state)** trên PostgreSQL 18, chiến lược chỉ mục – phân vùng bảng vật lý, cùng bộ truy vấn phân tích lịch sử hành trình.

---

## 1. Phân biệt Thời điểm Xảy ra (`thoi_gian_xay_ra`) và Thời điểm Ghi nhận (`thoi_gian_ghi_nhan`)

Trong hệ thống theo dõi vận chuyển bưu kiện, mỗi bản ghi trong bảng `SuKienTrangThai` lưu trữ **2 cột thời gian độc lập**:

```sql
CREATE TABLE pa_a.SuKienTrangThai (
    ma_su_kien         VARCHAR(20) PRIMARY KEY,
    ma_buu_kien        VARCHAR(20) REFERENCES pa_a.BuuKien(ma_buu_kien),
    ma_trang_thai      VARCHAR(30) NOT NULL,
    ma_diem            VARCHAR(20) REFERENCES pa_a.DiemGiaoNhan(ma_diem_giao_nhan),
    loai_su_kien       VARCHAR(50),
    thoi_gian_xay_ra   TIMESTAMP NOT NULL,                  -- Event Time (Valid Time)
    thoi_gian_ghi_nhan TIMESTAMP DEFAULT CURRENT_TIMESTAMP, -- Ingest Time (Transaction Time)
    idempotency_key    VARCHAR(100) UNIQUE NOT NULL
);
```

### 1.1. Ý nghĩa Ngữ nghĩa và Kỹ thuật của Hai Mốc Thời gian
| Thuộc tính | Thuật ngữ Khoa học | Ý nghĩa Nghiệp vụ | Vai trò trong Hệ thống CSDL |
| :--- | :--- | :--- | :--- |
| **`thoi_gian_xay_ra`** | **Event Time** *(Valid Time)* | Thời điểm sự kiện vật lý **thực sự diễn ra ngoài thực tế** (lúc nhân viên kho quét mã vạch nhập/xuất kho hoặc lúc Shipper giao hàng cho khách). | Dùng để **sắp xếp đúng thứ tự hành trình thực tế**, tính thời gian lưu kho (`LEAD`), và **xác định trạng thái hiện tại** của bưu kiện (`BR-06`). |
| **`thoi_gian_ghi_nhan`** | **Ingest Time** *(Transaction Time)* | Thời điểm máy chủ CSDL PostgreSQL **thực sự nhận và ghi dòng dữ liệu** vào bảng (`DEFAULT CURRENT_TIMESTAMP`). | Dùng để **kiểm toán hệ thống (audit log)**, đo độ trễ đồng bộ thiết bị (`thoi_gian_ghi_nhan - thoi_gian_xay_ra`) và phát hiện sự kiện đến muộn. |

### 1.2. Tại sao bắt buộc phải tách riêng hai mốc thời gian?
- Trong điều kiện vận hành thực tế tại kho bãi hoặc khi Shipper di chuyển ở khu vực sóng yếu/mất kết nối mạng, thiết bị cầm tay (*handheld scanner* / ứng dụng di động) ghi nhận thao tác quét mã kèm đồng hồ thời gian thực tại thời điểm quét (`thoi_gian_xay_ra`), lưu tạm vào bộ nhớ cục bộ và chỉ đồng bộ về máy chủ khi có mạng trở lại (`thoi_gian_ghi_nhan`).
- Nếu hệ thống chỉ dùng một cột thời gian duy nhất (mặc định lấy giờ máy chủ lúc `INSERT`), thứ tự các sự kiện sẽ bị đảo lộn hoàn toàn khi thiết bị đồng bộ bù dữ liệu offline, dẫn đến sai lệch trạng thái hiện tại và tính sai thời gian lưu kho.

---

## 2. Hai Phương án Tổ chức Lịch sử và Trạng thái Hiện tại (`PA_A` vs `PA_B`)

Dự án triển khai song song 2 schema riêng biệt trong PostgreSQL 18 ([sql/01_init_schemas.sql](file:///c:/CSDLnangcao/CSDLNC-Nhom13-van-chuyen-buu-kien/sql/01_init_schemas.sql)) để đối sánh:

### 2.1. Phương án A (`pa_a` – History-based / Thuần BCNF)
- **Nguyên lý:** Bảng `pa_a.BuuKien` chỉ lưu các thuộc tính bất biến/gốc của bưu kiện, **không chứa cột trạng thái hiện tại**.
- **Cách xác định trạng thái hiện tại:** Mỗi khi cần biết trạng thái hiện tại của một hoặc nhiều bưu kiện, hệ thống phải truy vấn trên bảng lịch sử `pa_a.SuKienTrangThai` để tìm bản ghi có `(thoi_gian_xay_ra, ma_su_kien)` lớn nhất:

```sql
-- Suy diễn trạng thái hiện tại từ lịch sử trong Phương án A (pa_a)
SELECT DISTINCT ON (ma_buu_kien)
       ma_buu_kien,
       ma_trang_thai AS trang_thai_hien_tai,
       thoi_gian_xay_ra AS thoi_gian_cap_nhat_cuoi
FROM pa_a.SuKienTrangThai
ORDER BY ma_buu_kien, thoi_gian_xay_ra DESC, ma_su_kien DESC;
```

### 2.2. Phương án B (`pa_b` – Current-state / Phi chuẩn hóa có kiểm soát)
- **Nguyên lý:** Bảng `pa_b.BuuKien` được bổ sung 2 cột thuộc tính suy diễn `trang_thai_hien_tai` và `thoi_gian_cap_nhat_cuoi`:

```sql
CREATE TABLE pa_b.BuuKien (
    ma_buu_kien             VARCHAR(20) PRIMARY KEY,
    ma_khach_hang_gui       VARCHAR(20) REFERENCES pa_b.KhachHang(ma_khach_hang),
    ma_khach_hang_nhan      VARCHAR(20) REFERENCES pa_b.KhachHang(ma_khach_hang),
    trong_luong             NUMERIC(8, 2) NOT NULL,
    dai                     NUMERIC(6, 1),
    rong                    NUMERIC(6, 1),
    cao                     NUMERIC(6, 1),
    gia_khai                NUMERIC(12, 2) DEFAULT 0,
    tien_COD                NUMERIC(12, 2) DEFAULT 0,
    trang_thai_hien_tai     VARCHAR(30) DEFAULT 'TIEP_NHAN',
    thoi_gian_cap_nhat_cuoi TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

- **Bản chất và Biện minh Kỹ thuật:** Vì trạng thái hiện tại phụ thuộc hàm vào chuỗi sự kiện lịch sử trong `SuKienTrangThai` ($\text{ma\_buu\_kien} \rightarrow \text{trang\_thai\_hien\_tai} \notin F_c$), nên bảng `BuuKien` trong `pa_b` cố ý vi phạm chuẩn 3NF/BCNF. Tuy nhiên, sự vi phạm này được **kiểm soát chặt chẽ bằng Trigger PL/pgSQL tự động** ([sql/02_triggers_functions.sql](file:///c:/CSDLnangcao/CSDLNC-Nhom13-van-chuyen-buu-kien/sql/02_triggers_functions.sql)) nhằm tối ưu hóa cho tải công việc đọc cao (>90% thao tác là tra cứu trạng thái).

### 2.3. Bảng So sánh Định tính và Định lượng giữa Phương án A và Phương án B

| Tiêu chí So sánh | Phương án A (`pa_a` - History-based / BCNF) | Phương án B (`pa_b` - Current-State / Phi chuẩn hóa) |
| :--- | :--- | :--- |
| **Dạng chuẩn Đạt được** | Đạt chuẩn **BCNF tuyệt đối** | Bảng `BuuKien` vi phạm 3NF/BCNF (chứa 2 cột suy diễn) |
| **Dư thừa Dữ liệu** | Không có dư thừa dữ liệu | Dư thừa 2 cột `trang_thai_hien_tai` và `thoi_gian_cap_nhat_cuoi` |
| **Độ phức tạp Tra cứu Trạng thái** | Chậm: Phải quét & sắp xếp bảng lịch sử lớn $\mathcal{O}(N \log N)$ | **Cực nhanh:** Đọc trực tiếp 1 dòng theo khóa chính $\mathcal{O}(1)$ |
| **Thực nghiệm Đọc 1 bưu kiện** | `14,664 ms` (3.925 buffer hits) | **`0,058 ms`** (3 buffer hits – **nhanh hơn ~252,83 lần**) |
| **Thực nghiệm Đọc 10.000 bưu kiện** | `855,795 ms` (External Merge Sort 4.376 kB đĩa) | **`9,678 ms`** (0 kB đĩa – **nhanh hơn ~88,43 lần**) |
| **Thực nghiệm Ghi 1 sự kiện (`INSERT`)** | **`0,462 ms`** (Chỉ `INSERT` 1 bảng, nhanh hơn ~272,84 lần) | `126,050 ms` (Tốn 86,648 ms chạy Trigger `UPDATE` đồng bộ) |
| **Cơ chế Đồng bộ** | Tự đồng bộ khi đọc (không cần Trigger bảo vệ) | Bắt buộc kiểm soát bằng Trigger PL/pgSQL chống sự kiện muộn |
| **Tải công việc Phù hợp** | Hệ thống ghi nhận nhật ký kiểm toán, luồng IoT ghi dồn dập | **Hệ thống Logistics tải đọc cao (High Read-heavy > 90%)** |

*Bảng 4.5: So sánh toàn diện giữa Phương án A (BCNF) và Phương án B (Phi chuẩn hóa có kiểm soát).*

---

## 3. Thủ tục Ghi nhận Sự kiện Đối sánh `PA_A` vs `PA_B`

Để đối sánh đường đi thực thi giữa hai kiến trúc, các hàm PL/pgSQL được xây dựng riêng biệt cho từng schema:

### 3.1. Hàm ghi nhận sự kiện cho Phương án A (`pa_a.ghi_nhan_su_kien`)
```sql
CREATE OR REPLACE FUNCTION pa_a.ghi_nhan_su_kien(
    p_ma_su_kien       VARCHAR(20),
    p_ma_buu_kien      VARCHAR(20),
    p_ma_trang_thai    VARCHAR(30),
    p_ma_diem          VARCHAR(20),
    p_loai_su_kien     VARCHAR(50),
    p_thoi_gian_xay_ra TIMESTAMP,
    p_idempotency_key  VARCHAR(100)
) RETURNS VOID AS $$
BEGIN
    -- Thao tác INSERT thuần túy O(1) vào bảng lịch sử sự kiện BCNF
    -- Không kích hoạt bất kỳ Trigger update hoặc khóa dòng nào trên bảng BuuKien
    INSERT INTO pa_a.SuKienTrangThai (
        ma_su_kien, ma_buu_kien, ma_trang_thai, ma_diem, 
        loai_su_kien, thoi_gian_xay_ra, thoi_gian_ghi_nhan, idempotency_key
    ) VALUES (
        p_ma_su_kien, p_ma_buu_kien, p_ma_trang_thai, p_ma_diem, 
        p_loai_su_kien, p_thoi_gian_xay_ra, CURRENT_TIMESTAMP, p_idempotency_key
    )
    ON CONFLICT (idempotency_key) DO NOTHING;
END;
$$ LANGUAGE plpgsql;
```

### 3.2. Hàm ghi nhận sự kiện cho Phương án B (`pa_b.ghi_nhan_su_kien`)
```sql
CREATE OR REPLACE FUNCTION pa_b.ghi_nhan_su_kien(
    p_ma_su_kien       VARCHAR(20),
    p_ma_buu_kien      VARCHAR(20),
    p_ma_trang_thai    VARCHAR(30),
    p_ma_diem          VARCHAR(20),
    p_loai_su_kien     VARCHAR(50),
    p_thoi_gian_xay_ra TIMESTAMP,
    p_idempotency_key  VARCHAR(100)
) RETURNS VOID AS $$
BEGIN
    -- INSERT vào SuKienTrangThai sẽ tự động kích hoạt Trigger AFTER INSERT:
    -- trg_cap_nhat_trang_thai -> fn_cap_nhat_trang_thai_buu_kien()
    -- Thực hiện kiểm tra thời gian và UPDATE đồng thời lên bảng pa_b.BuuKien
    INSERT INTO pa_b.SuKienTrangThai (
        ma_su_kien, ma_buu_kien, ma_trang_thai, ma_diem, 
        loai_su_kien, thoi_gian_xay_ra, thoi_gian_ghi_nhan, idempotency_key
    ) VALUES (
        p_ma_su_kien, p_ma_buu_kien, p_ma_trang_thai, p_ma_diem, 
        p_loai_su_kien, p_thoi_gian_xay_ra, CURRENT_TIMESTAMP, p_idempotency_key
    )
    ON CONFLICT (idempotency_key) DO NOTHING;
END;
$$ LANGUAGE plpgsql;
```

---

## 4. Thiết kế Chỉ mục Vật lý và Phân vùng Bảng Lịch sử (Partitioning)

### 4.1. Chiến lược Chỉ mục Vật lý B-Tree
Để tối ưu hóa hiệu năng truy vấn lịch sử và kiểm tra ràng buộc:
1. **Chỉ mục phức hợp phục vụ tìm sự kiện mới nhất theo thời gian xảy ra:**
   ```sql
   CREATE INDEX idx_pa_a_sktt_bk_time
   ON pa_a.SuKienTrangThai (ma_buu_kien, thoi_gian_xay_ra DESC);
   ```
   Giúp tăng tốc độ truy vấn lịch sử hành trình của 1 bưu kiện và truy vấn `DISTINCT ON (ma_buu_kien)` tìm trạng thái mới nhất ở `pa_a`.
2. **Chỉ mục duy nhất kiểm soát khóa chống gửi trùng (`BR-07`):**
   ```sql
   CREATE UNIQUE INDEX idx_pa_b_sktt_idempotency
   ON pa_b.SuKienTrangThai (idempotency_key);
   ```
   Đảm bảo kiểm tra xung đột `ON CONFLICT (idempotency_key) DO NOTHING` trong thời gian $\mathcal{O}(\log N)$.

### 4.2. Giải pháp Phân vùng Bảng Vật lý theo Thời gian xảy ra (Declarative Range Partitioning)
Khi bảng `SuKienTrangThai` tăng trưởng lên hàng chục triệu dòng, chỉ mục B-Tree trên một bảng đơn sẽ bị phình to (*Index Bloat*). Giải pháp nâng cấp vật lý trên PostgreSQL 18 là phân vùng bảng theo khoảng thời gian `thoi_gian_xay_ra` (**Range Partitioning**):

```sql
-- 1. Tạo bảng cha khai báo phân vùng theo khoảng thời gian (Range Partitioning)
CREATE TABLE pa_b.sukientrangthai_partitioned (
    ma_su_kien         VARCHAR(20) NOT NULL,
    ma_buu_kien        VARCHAR(20) NOT NULL,
    ma_trang_thai      VARCHAR(30) NOT NULL,
    ma_diem            VARCHAR(20) NOT NULL,
    loai_su_kien       VARCHAR(50) NOT NULL,
    thoi_gian_xay_ra   TIMESTAMP NOT NULL,
    thoi_gian_ghi_nhan TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    idempotency_key    VARCHAR(100) NOT NULL,
    CONSTRAINT pk_sktt_part PRIMARY KEY (ma_su_kien, thoi_gian_xay_ra)
) PARTITION BY RANGE (thoi_gian_xay_ra);

-- 2. Tạo các bảng con phân vùng theo từng tháng trong năm 2026
CREATE TABLE pa_b.sukientrangthai_y2026m01 PARTITION OF pa_b.sukientrangthai_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00') TO ('2026-02-01 00:00:00');

CREATE TABLE pa_b.sukientrangthai_y2026m02 PARTITION OF pa_b.sukientrangthai_partitioned
    FOR VALUES FROM ('2026-02-01 00:00:00') TO ('2026-03-01 00:00:00');

-- 3. Đánh chỉ mục B-Tree cục bộ trên từng phân vùng con
CREATE INDEX idx_sktt_2026m01_bk ON pa_b.sukientrangthai_y2026m01(ma_buu_kien, thoi_gian_xay_ra DESC);
CREATE INDEX idx_sktt_2026m02_bk ON pa_b.sukientrangthai_y2026m02(ma_buu_kien, thoi_gian_xay_ra DESC);
```
Nhờ cơ chế **Partition Pruning**, PostgreSQL tự động bỏ qua các phân vùng tháng không nằm trong khoảng thời gian truy vấn, giữ tốc độ tra cứu ổn định bất chấp quy mô lịch sử toàn cục.

---

## 5. Các Truy vấn Phân tích Lịch sử Hành trình và Đối soát Trạng thái ([sql/05_sql_advanced.sql](file:///c:/CSDLnangcao/CSDLNC-Nhom13-van-chuyen-buu-kien/sql/05_sql_advanced.sql))

### 5.1. Tính Thời gian Lưu kho tại từng Điểm giao nhận (`Q2` – `CTE` + `LEAD() OVER WINDOW`)
Với mỗi sự kiện `NHAP_KHO`, thời gian lưu tại điểm được tính bằng hiệu số giữa `thoi_gian_xay_ra` của sự kiện kế tiếp trên cùng bưu kiện (`LEAD`) và `thoi_gian_xay_ra` của lần nhập kho đó:

```sql
WITH chuoi AS (
    SELECT
        sk.ma_buu_kien,
        sk.ma_diem,
        sk.ma_trang_thai,
        sk.thoi_gian_xay_ra AS t_vao,
        LEAD(sk.thoi_gian_xay_ra) OVER w AS t_ra,
        LEAD(sk.ma_trang_thai)    OVER w AS tt_ke_tiep
    FROM pa_a.SuKienTrangThai sk
    WINDOW w AS (PARTITION BY sk.ma_buu_kien ORDER BY sk.thoi_gian_xay_ra, sk.ma_su_kien)
),
luu_kho AS (
    SELECT ma_buu_kien, ma_diem, t_vao, t_ra,
           t_ra - t_vao AS thoi_gian_luu
    FROM chuoi
    WHERE ma_trang_thai = 'NHAP_KHO'
      AND t_ra IS NOT NULL
)
SELECT
    d.ma_diem_giao_nhan,
    d.ten_diem,
    COUNT(*)                                                    AS so_luot,
    ROUND(AVG(EXTRACT(EPOCH FROM l.thoi_gian_luu)) / 3600, 2)   AS luu_tb_gio,
    ROUND(MAX(EXTRACT(EPOCH FROM l.thoi_gian_luu)) / 3600, 2)   AS luu_max_gio
FROM luu_kho l
JOIN pa_a.DiemGiaoNhan d ON d.ma_diem_giao_nhan = l.ma_diem
GROUP BY d.ma_diem_giao_nhan, d.ten_diem
HAVING COUNT(*) >= 10
ORDER BY luu_tb_gio DESC;
```

### 5.2. Phát hiện Bưu kiện Chậm quá 48 giờ – Đối sánh `PA_A` vs `PA_B` (`Q3`)
```sql
-- 3a. Phương án A (pa_a): Trạng thái hiện tại suy ra từ bảng lịch sử
WITH hien_tai AS (
    SELECT DISTINCT ON (ma_buu_kien)
           ma_buu_kien, ma_trang_thai, thoi_gian_xay_ra
    FROM pa_a.SuKienTrangThai
    ORDER BY ma_buu_kien, thoi_gian_xay_ra DESC, ma_su_kien DESC
)
SELECT h.ma_buu_kien,
       h.ma_trang_thai,
       h.thoi_gian_xay_ra AS su_kien_cuoi,
       ROUND(EXTRACT(EPOCH FROM (NOW() - h.thoi_gian_xay_ra)) / 3600, 1) AS gio_ke_lai
FROM hien_tai h
WHERE h.ma_trang_thai NOT IN ('GIAO_THANH_CONG', 'HOAN_TRA')
  AND h.thoi_gian_xay_ra < NOW() - INTERVAL '48 hours'
ORDER BY h.thoi_gian_xay_ra
LIMIT 50;

-- 3b. Phương án B (pa_b): Đọc thẳng cột trạng thái hiện tại trên bảng BuuKien
SELECT b.ma_buu_kien,
       b.trang_thai_hien_tai AS ma_trang_thai,
       b.thoi_gian_cap_nhat_cuoi AS su_kien_cuoi,
       ROUND(EXTRACT(EPOCH FROM (NOW() - b.thoi_gian_cap_nhat_cuoi)) / 3600, 1) AS gio_ke_lai
FROM pa_b.BuuKien b
WHERE b.trang_thai_hien_tai NOT IN ('GIAO_THANH_CONG', 'HOAN_TRA')
  AND b.thoi_gian_cap_nhat_cuoi < NOW() - INTERVAL '48 hours'
ORDER BY b.thoi_gian_cap_nhat_cuoi
LIMIT 50;
```

### 5.3. Đối soát Toàn vẹn Trạng thái giữa `PA_A` và `PA_B` trên 10.000 Bưu kiện (`Q12a`)
Truy vấn kiểm chứng xem cột `trang_thai_hien_tai` và `thoi_gian_cap_nhat_cuoi` do Trigger duy trì ở `pa_b` có khớp 100% với trạng thái suy diễn từ lịch sử ở `pa_a` hay không (kết quả kỳ vọng: `so_buu_kien_lech = 0`):

```sql
WITH trang_thai_pa_a AS (
    SELECT DISTINCT ON (ma_buu_kien)
        ma_buu_kien,
        ma_trang_thai    AS tt_pa_a,
        thoi_gian_xay_ra AS tg_pa_a
    FROM pa_a.SuKienTrangThai
    ORDER BY ma_buu_kien, thoi_gian_xay_ra DESC, ma_su_kien DESC
)
SELECT
    COUNT(*)                                                                  AS tong_so_buu_kien_doi_soat,
    COUNT(*) FILTER (WHERE a.tt_pa_a = b.trang_thai_hien_tai
                       AND a.tg_pa_a = b.thoi_gian_cap_nhat_cuoi)             AS so_buu_kien_khop_100_pct,
    COUNT(*) FILTER (WHERE a.tt_pa_a IS DISTINCT FROM b.trang_thai_hien_tai
                        OR a.tg_pa_a IS DISTINCT FROM b.thoi_gian_cap_nhat_cuoi) AS so_buu_kien_lech
FROM trang_thai_pa_a a
FULL OUTER JOIN pa_b.BuuKien b ON b.ma_buu_kien = a.ma_buu_kien;
```
