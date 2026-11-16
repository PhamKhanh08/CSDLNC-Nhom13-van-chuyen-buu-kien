# CHƯƠNG 6: ĐÁNH GIÁ, SO SÁNH HIỆU NĂNG (PA_A vs PA_B) VÀ KIỂM THỬ GIAO DỊCH

## 6.1. Mục tiêu và phương pháp thực nghiệm

Chương này trình bày việc đo đạc, so sánh hiệu năng và kiểm chứng tính toàn vẹn giữa hai phương án thiết kế cơ sở dữ liệu:
- **`PA_A` (History-based):** Lưu trữ thuần lịch sử sự kiện (đạt BCNF tuyệt đối), bảng `BuuKien` không lưu trạng thái hiện tại; trạng thái được suy diễn động từ bản ghi sự kiện mới nhất.
- **`PA_B` (Current-state):** Lưu trạng thái hiện tại trực tiếp trên bản ghi bưu kiện (`trang_thai_hien_tai`, `thoi_gian_cap_nhat_cuoi`) kết hợp Trigger PL/pgSQL tự động đồng bộ khi có sự kiện mới.

Các phép thử tập trung vào 3 kịch bản vận hành cốt lõi:
1. **Kịch bản 1:** Truy vấn trạng thái hiện tại của một bưu kiện cụ thể (`PK00000001`).
2. **Kịch bản 2:** Truy vấn trạng thái hiện tại của toàn bộ 10.000 bưu kiện trong hệ thống.
3. **Kịch bản 3:** Ghi nhận một sự kiện cập nhật trạng thái mới (`INSERT` kèm kích hoạt Trigger).

### 6.1.1. Quy mô dữ liệu thực nghiệm

| Thành phần dữ liệu | Bảng lưu trữ | Quy mô dữ liệu | Mục đích kiểm thử |
| :--- | :--- | :---: | :--- |
| **Bưu kiện** | `pa_a.buukien` / `pa_b.buukien` | **10.000 bản ghi** | Đo tốc độ truy xuất và quét toàn bộ danh mục |
| **Sự kiện trạng thái** | `pa_a.sukientrangthai` / `pa_b.sukientrangthai` | **100.000 bản ghi** | Đo tốc độ lọc, sắp xếp và độ trễ của Trigger đồng bộ |

*Bảng 6.1. Quy mô dữ liệu thực nghiệm.*

### 6.1.2. Các chỉ số đánh giá
- **Execution Time (ms):** Thời gian thực thi thực tế của truy vấn tại engine PostgreSQL (chỉ số so sánh chính).
- **Planning Time (ms):** Thời gian PostgreSQL Optimizer phân tích và lập cây kế hoạch truy vấn.
- **Buffers (Shared Hit / Read / Dirtied):** Số trang đệm bộ nhớ (8KB/block) mà câu lệnh truy cập; phản ánh mức độ chiếm dụng RAM và I/O đĩa.
- **Temp Read / Written (blocks):** Hoạt động đọc/ghi dữ liệu tạm trên đĩa khi bộ nhớ RAM (`work_mem`) không đủ để sắp xếp.
- **Kế hoạch thực thi (Execution Nodes):** Cơ chế quét (`Seq Scan`, `Index Scan`), phép nối (`Nested Loop`), phép sắp xếp (`Sort External Merge`), và chi phí kích hoạt Trigger.

---

## 6.2. Thực nghiệm 1 – Truy vấn trạng thái hiện tại của một bưu kiện (`PK00000001`)

### 6.2.1. Câu lệnh truy vấn
- **Phương án A (`PA_A` - History-based):**
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT bk.ma_buu_kien, sk.ma_trang_thai, sk.thoi_gian_xay_ra
FROM pa_a.buukien bk
JOIN pa_a.sukientrangthai sk ON bk.ma_buu_kien = sk.ma_buu_kien
WHERE bk.ma_buu_kien = 'PK00000001'
  AND sk.thoi_gian_xay_ra = (
      SELECT MAX(sub.thoi_gian_xay_ra)
      FROM pa_a.sukientrangthai sub
      WHERE sub.ma_buu_kien = 'PK00000001'
  );
```

- **Phương án B (`PA_B` - Current-state):**
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT ma_buu_kien, trang_thai_hien_tai, thoi_gian_cap_nhat_cuoi
FROM pa_b.buukien
WHERE ma_buu_kien = 'PK00000001';
```

---

### 6.2.2. Bảng bóc tách Kế hoạch thực thi chi tiết (Execution Plan Breakdown)

#### Bảng 6.2a. Bóc tách kế hoạch thực thi của Phương án A (`PA_A`)
| STT | Node thực thi (Plan Node) | Quan hệ / Đối tượng | Phép quét / Phép toán | Điều kiện lọc (Filter / Cond) | Số dòng duyệt (Loại bỏ) | Buffers (Shared Hit) | Thời gian chạy (ms) | Nhận xét kỹ thuật |
| :---: | :--- | :--- | :---: | :--- | :---: | :---: | :---: | :--- |
| **1** | `InitPlan 1 (Aggregate)` | `sukientrangthai sub` | `Seq Scan` | `ma_buu_kien = 'PK00000001'` | Duyệt 100.000 dòng<br>*(Loại 99.989 dòng)* | **1.961 blocks** | **7,208 ms** | ⚠️ **Điểm nghẽn:** Quét toàn bảng để tìm `MAX(thoi_gian)` do thiếu Index trên `ma_buu_kien`. |
| **2** | Quét bưu kiện | `buukien bk` | `Index Only Scan` | `Index Cond: ma_buu_kien = 'PK00000001'` | 1 dòng | **3 blocks** | **0,038 ms** | ✅ Tối ưu nhờ khóa chính `buukien_pkey`. |
| **3** | Lọc sự kiện mới nhất | `sukientrangthai sk` | `Seq Scan` | `ma_buu_kien = 'PK00000001' AND thoi_gian = (InitPlan 1)` | Duyệt 100.000 dòng<br>*(Loại 99.999 dòng)* | **1.961 blocks** | **14,590 ms** | ⚠️ **Điểm nghẽn:** Phải quét toàn bộ 100.000 dòng lần thứ 2 để lấy chi tiết sự kiện. |
| **4** | Nối dữ liệu | Ghép bước 2 và 3 | `Nested Loop` | — | 1 dòng kết quả | — | — | Nối kết quả đầu ra. |
| **Tổng** | **Kế hoạch tổng thể** | — | — | **Planning Time: 0,400 ms** | **1 dòng** | **3.925 blocks** | **14,664 ms** | **Tốn 31.4 MB bộ nhớ đệm duyệt qua RAM.** |

#### Bảng 6.2b. Bóc tách kế hoạch thực thi của Phương án B (`PA_B`)
| STT | Node thực thi (Plan Node) | Quan hệ / Đối tượng | Phép quét / Phép toán | Điều kiện lọc (Filter / Cond) | Số dòng duyệt | Buffers (Shared Hit) | Thời gian chạy (ms) | Nhận xét kỹ thuật |
| :---: | :--- | :--- | :---: | :--- | :---: | :---: | :---: | :--- |
| **1** | Truy xuất bưu kiện | `buukien` | `Index Scan` | `Index Cond: ma_buu_kien = 'PK00000001'` | 1 dòng | **3 blocks** | **0,042 ms** | ✅ Truy xuất trực tiếp qua chỉ mục B-Tree `buukien_pkey`. Không cần đọc bảng sự kiện. |
| **Tổng** | **Kế hoạch tổng thể** | — | — | **Planning Time: 6,173 ms** | **1 dòng** | **3 blocks** | **0,058 ms** | **Hiệu năng tức thì, không tốn I/O.** |

---

### 6.2.3. Bảng so sánh và đánh giá kết quả Kịch bản 1

| Tiêu chí so sánh | Phương án A (`PA_A`) | Phương án B (`PA_B`) | Mức độ chênh lệch / Ưu thế |
| :--- | :---: | :---: | :--- |
| **Thời gian thực thi (Execution Time)** | **14,664 ms** | **0,058 ms** | **PA_B nhanh hơn ~252,83 lần (giảm 99,60% thời gian)** |
| **Thời gian lập kế hoạch (Planning Time)** | 0,400 ms | 6,173 ms | PA_A lập kế hoạch đơn giản hơn trong lần đo |
| **Truy cập bộ đệm (Shared Buffer Hit)** | **3.925 blocks** (~31,4 MB) | **3 blocks** (~24 KB) | **PA_B giảm 99,92% số lượt truy cập bộ đệm** |
| **Phương thức quét dữ liệu** | 2 lần `Seq Scan` bảng 100.000 dòng | 1 lần `Index Scan` trên PK | PA_B giải phóng hoàn toàn chi phí quét bảng lịch sử |

*Bảng 6.2c. So sánh tổng hợp truy vấn trạng thái 1 bưu kiện.*

---

## 6.3. Thực nghiệm 2 – Truy vấn trạng thái hiện tại của toàn bộ 10.000 bưu kiện

### 6.3.1. Câu lệnh truy vấn
- **Phương án A (`PA_A`):**
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT DISTINCT ON (ma_buu_kien)
       ma_buu_kien, ma_trang_thai, thoi_gian_xay_ra
FROM pa_a.sukientrangthai
ORDER BY ma_buu_kien, thoi_gian_xay_ra DESC;
```

- **Phương án B (`PA_B`):**
```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT ma_buu_kien, trang_thai_hien_tai, thoi_gian_cap_nhat_cuoi
FROM pa_b.buukien;
```

---

### 6.3.2. Bảng bóc tách Kế hoạch thực thi chi tiết

#### Bảng 6.3a. Bóc tách kế hoạch thực thi của Phương án A (`PA_A`)
| STT | Node thực thi | Đối tượng | Phép toán / Thuật toán | Số dòng xử lý | Buffers / Disk | Thời gian (ms) | Nhận xét kỹ thuật |
| :---: | :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| **1** | `Seq Scan` | `sukientrangthai` | Quét tuần tự toàn bộ bảng sự kiện | 100.000 dòng | Shared hit: 1.961 | 15,159 ms | Đọc toàn bộ 100.000 dòng vào bộ nhớ. |
| **2** | `Sort` | Dữ liệu từ bước 1 | `external merge` trên ổ đĩa<br>*(Sort Key: ma_buu_kien, thoi_gian DESC)* | 100.000 dòng | **Dùng đĩa: 4.376 kB**<br>Temp read: 547<br>Temp write: 548 | **835,321 ms** | ⚠️ **Điểm nghẽn lớn nhất:** Vượt quá `work_mem` RAM, phải ghi ra file tạm trên ổ đĩa để sắp xếp. |
| **3** | `Unique` | Dữ liệu đã sắp xếp | Lọc lấy bản ghi đầu tiên của mỗi `ma_buu_kien` | Giữ lại 10.000 dòng<br>*(Bỏ 90.000 dòng cũ)* | — | **855,795 ms** | Loại bỏ các sự kiện cũ trong quá khứ. |
| **Tổng** | **Kế hoạch tổng thể** | — | — | **10.000 dòng** | **1.967 buffers + 4.376 kB Disk** | **855,795 ms** | **Chi phí I/O đĩa và CPU rất nặng.** |

#### Bảng 6.3b. Bóc tách kế hoạch thực thi của Phương án B (`PA_B`)
| STT | Node thực thi | Đối tượng | Phép toán / Thuật toán | Số dòng xử lý | Buffers (Shared Hit) | Thời gian (ms) | Nhận xét kỹ thuật |
| :---: | :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| **1** | `Seq Scan` | `buukien` | Quét tuần tự bảng bưu kiện | 10.000 dòng | **137 blocks** | **8,984 ms** | ✅ Chỉ đọc đúng 10.000 dòng đã chứa sẵn trạng thái hiện tại. Hoàn toàn trong RAM. |
| **Tổng** | **Kế hoạch tổng thể** | — | **Planning Time: 0,097 ms** | **10.000 dòng** | **137 blocks** | **9,678 ms** | **Nhanh, không phát sinh I/O đĩa hay Sort.** |

---

### 6.3.3. Bảng so sánh và đánh giá kết quả Kịch bản 2

| Tiêu chí so sánh | Phương án A (`PA_A`) | Phương án B (`PA_B`) | Mức độ chênh lệch / Ưu thế |
| :--- | :---: | :---: | :--- |
| **Thời gian thực thi (Execution Time)** | **855,795 ms** | **9,678 ms** | **PA_B nhanh hơn ~88,43 lần (giảm 98,87% thời gian)** |
| **Dung lượng đĩa tạm (Temp Disk)** | **4.376 kB (External Merge)** | **0 kB (Không dùng đĩa)** | **PA_B loại bỏ hoàn toàn việc tràn bộ nhớ ra đĩa** |
| **Thao tác I/O đọc/ghi tạm** | 547 read / 548 written blocks | 0 / 0 | PA_B không gây quá tải I/O đĩa |
| **Số dòng dữ liệu phải duyệt** | 100.000 dòng sự kiện | 10.000 dòng bưu kiện | PA_B giảm 10 lần khối lượng dữ liệu xử lý |
| **Truy cập bộ đệm (Shared Hit)** | 1.967 blocks | 137 blocks | Giảm 93,03% số lượt truy cập bộ đệm |

*Bảng 6.3c. So sánh tổng hợp truy vấn trạng thái toàn bộ 10.000 bưu kiện.*

---

## 6.4. Thực nghiệm 3 – Ghi nhận một sự kiện cập nhật trạng thái (`INSERT`)

### 6.4.1. Câu lệnh thực thi
- **Phương án A (`PA_A` - Ghi thuần túy):**
```sql
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO pa_a.sukientrangthai (
    ma_su_kien, ma_buu_kien, ma_trang_thai, ma_diem, loai_su_kien,
    thoi_gian_xay_ra, thoi_gian_ghi_nhan, idempotency_key
)
VALUES (
    'SK_BENCHMARK_PA_A', 'PK00000001', 'DANG_GIAO', 'DGN00001',
    'CAP_NHAT_TRANG_THAI', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'KEY-BM-PAA-01'
);
```

- **Phương án B (`PA_B` - Ghi kèm kích hoạt Trigger PL/pgSQL):**
```sql
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO pa_b.sukientrangthai (
    ma_su_kien, ma_buu_kien, ma_trang_thai, ma_diem, loai_su_kien,
    thoi_gian_xay_ra, thoi_gian_ghi_nhan, idempotency_key
)
VALUES (
    'SK_BENCHMARK_PA_B', 'PK00000001', 'DANG_GIAO', 'DGN00001',
    'CAP_NHAT_TRANG_THAI', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'KEY-BM-PAB-01'
);
```

---

### 6.4.2. Bảng bóc tách Kế hoạch thực thi chi tiết

#### Bảng 6.4a. Bóc tách chi phí thao tác INSERT của Phương án A và Phương án B
| Thành phần thực thi trong câu lệnh | Phương án A (`PA_A`) | Phương án B (`PA_B`) | Bản chất kỹ thuật & Nguyên nhân chênh lệch |
| :--- | :---: | :---: | :--- |
| **Ghi bản ghi vào bảng sự kiện (`Insert`)** | 0,159 ms | 23,643 ms | PA_B phát sinh I/O ghi đĩa nhiều hơn (`read=13, dirtied=4`). |
| **Trigger kiểm tra FK `ma_buu_kien`** | 0,191 ms | 9,658 ms | Kiểm tra ràng buộc khóa ngoại tới bảng `buukien`. |
| **Trigger kiểm tra FK `ma_diem`** | 0,085 ms | 6,067 ms | Kiểm tra ràng buộc khóa ngoại tới bảng `diemgiaonhan`. |
| **Trigger PL/pgSQL `trg_cap_nhat_trang_thai`** | **Không có** | **86,648 ms** | ⚠️ **Chi phí cốt lõi của PA_B:** Trigger phải đọc dòng bưu kiện, so sánh `thoi_gian_xay_ra` và thực hiện thêm 1 lệnh `UPDATE` đồng bộ sang bảng `buukien`. |
| **TỔNG THỜI GIAN THỰC THI (Execution Time)** | **0,462 ms** | **126,050 ms** | **PA_A nhanh hơn ~272,84 lần ở thao tác ghi.** |

---

### 6.4.3. Bảng so sánh và nhận xét Kịch bản 3

| Tiêu chí so sánh | Phương án A (`PA_A`) | Phương án B (`PA_B`) | Đánh giá kiến trúc |
| :--- | :---: | :---: | :--- |
| **Execution Time** | **0,462 ms** | **126,050 ms** | **PA_A vượt trội về tốc độ ghi** |
| **Tỷ trọng thời gian của Trigger đồng bộ** | 0% | **68,74%** (86,648 ms) | Trigger PL/pgSQL chiếm phần lớn chi phí câu lệnh ở PA_B |
| **Tác động lên bộ nhớ đệm** | Shared hit: 12, dirtied: 2 | Shared hit: 24, read: 13, dirtied: 4 | PA_B tốn tài nguyên bộ nhớ và I/O đĩa gấp đôi khi ghi |

*Bảng 6.4b. So sánh thao tác INSERT sự kiện.*

---

## 6.5. Bảng tổng hợp đối sánh toàn diện hai phương án

| Kịch bản kiểm thử | Phương án A (`PA_A`) | Phương án B (`PA_B`) | Phương án chiếm ưu thế | Kết luận kiến trúc |
| :--- | :---: | :---: | :---: | :--- |
| **1. Đọc trạng thái 1 bưu kiện** | 14,664 ms | **0,058 ms** | 🏆 **PA_B (Nhanh hơn ~252,83 lần)** | PA_B tối ưu tuyệt đối cho màn hình tra cứu của người dùng cuối |
| **2. Đọc trạng thái 10.000 bưu kiện** | 855,795 ms | **9,678 ms** | 🏆 **PA_B (Nhanh hơn ~88,43 lần)** | PA_B giải phóng tài nguyên CPU/RAM khi xuất báo cáo dashboard |
| **3. Ghi nhận 1 sự kiện (`INSERT`)** | **0,462 ms** | 126,050 ms | 🏆 **PA_A (Nhanh hơn ~272,84 lần)** | PA_A tối ưu cho các cổng tiếp nhận dữ liệu IoT/GPS dồn dập |

*Bảng 6.5. Tổng hợp thời gian thực thi theo ba kịch bản.*

> **Đánh giá đánh đổi kiến trúc (Trade-off):**
> - **Hệ thống theo dõi bưu kiện** thực tế có tỷ lệ **Đọc : Ghi khoảng 90% : 10%** (khách hàng, tài xế và nhân viên kho liên tục tra cứu hành trình bưu kiện nhiều hơn gấp nhiều lần so với số lần cập nhật trạng thái mới).
> - Do đó, mức đánh đổi chi phí ghi ở PA_B (126 ms) để đổi lại tốc độ truy vấn đọc tức thì (0,058 ms, nhanh hơn 252 lần) là **hoàn toàn xứng đáng và mang lại trải nghiệm người dùng vượt trội**.

---

## 6.6. Bảng kiểm chứng Giao dịch & Xử lý đồng thời (ACID & Locking)

Thay cho các hình ảnh màn hình chụp rời rạc, toàn bộ tiến trình kiểm thử tính nguyên tử (`Atomicity`) và điều khiển đồng thời (`Concurrency Control`) được chuẩn hóa thành các bảng quan sát khoa học dưới đây:

### 6.6.1. Bảng tiến trình kiểm thử Tính nguyên tử (Atomicity & ROLLBACK khi lỗi FK)

#### Bảng 6.6. Tiến trình kiểm thử Rollback khi vi phạm khóa ngoại
| Bước | Thao tác thực hiện | Mã lệnh SQL | Trạng thái hệ thống | Dữ liệu quan sát thực tế | Kết luận thuộc tính ACID |
| :---: | :--- | :--- | :---: | :--- | :--- |
| **1** | Mở Transaction & Chèn hợp lệ | `BEGIN;`<br>`INSERT INTO pa_b.lanbangiao VALUES ('LBG_TEST_ROLLBACK_01', 'PK00000001', 'NV01', 'DGN01', 'CH01', ...);` | Giao dịch đang mở (chưa `COMMIT`) | `SELECT * FROM pa_b.lanbangiao` $\rightarrow$ **Trả về 1 dòng** bản ghi tạm thời. | Dữ liệu mới chỉ tồn tại cục bộ trong transaction hiện tại. |
| **2** | Cố ý chèn sự kiện lỗi FK | `INSERT INTO pa_b.sukientrangthai (..., ma_buu_kien, ...) VALUES (..., 'PK_KHONG_TON_TAI', ...);` | Transaction bị lỗi vi phạm ràng buộc | Báo lỗi: `ERROR: insert or update violates foreign key constraint "sukientrangthai_ma_buu_kien_fkey"`<br>**SQLSTATE: 23503** | PostgreSQL lập tức chuyển Transaction sang trạng thái **Aborted**. |
| **3** | Hoàn tác giao dịch lỗi | `ROLLBACK;` | Kết thúc giao dịch lỗi | Thông báo: `Query returned successfully in 59 msec.` | Toàn bộ các câu lệnh trước đó trong Transaction đều bị hủy. |
| **4** | **Xác minh tính nguyên tử** | `SELECT * FROM pa_b.lanbangiao WHERE ma_ban_giao = 'LBG_TEST_ROLLBACK_01';` | Database ở trạng thái nhất quán | **Total rows: 0** *(Không còn bản ghi nào tồn tại)* | ✅ **Chứng minh Tính nguyên tử (Atomicity):** Nguyên tắc "Tất cả hoặc không gì cả" được bảo đảm tuyệt đối. |

---

### 6.6.2. Bảng tiến trình kiểm thử Khóa dòng chống Lost Update (Concurrency Locking)

Thực nghiệm trên bưu kiện `PK00000001` có trạng thái ban đầu là `NHAP_KHO`:

#### Bảng 6.7. Ma trận tương tác đồng thời giữa Session 1, Session 2 và Session 3
| Thời điểm | [Tab 1 - Session 1] | [Tab 2 - Session 2] | [Tab 3 - Session 3] (Giám sát khóa `pg_stat_activity`) | Cơ chế bảo vệ của PostgreSQL |
| :---: | :--- | :--- | :--- | :--- |
| **T0** | Khởi tạo bưu kiện về trạng thái ban đầu: `trang_thai_hien_tai = 'NHAP_KHO'`. | — | — | Dữ liệu cơ sở sẵn sàng. |
| **T1** | `BEGIN;`<br>`SELECT ... FOR UPDATE;`<br>*(Khóa độc quyền bản ghi)* | — | `pid = 22796, state = idle in transaction` | Session 1 giữ khóa `ExclusiveLock` trên Tuple của bưu kiện. |
| **T2** | *Đang tạm dừng (chưa COMMIT)* | `BEGIN;`<br>`UPDATE pa_b.buukien SET trang_thai_hien_tai = 'DANG_GIAO' WHERE ma_buu_kien = 'PK00000001' AND trang_thai_hien_tai = 'NHAP_KHO';` | **`pid = 8132, state = active, wait_event_type = Lock, wait_event = transactionid`** | 🔒 **Session 2 bị treo:** Trình quản lý khóa (Lock Manager) đưa Session 2 vào hàng đợi chờ khóa. |
| **T3** | `UPDATE ... SET trang_thai_hien_tai = 'XUAT_KHO';`<br>`COMMIT;` | — | Khóa được giải phóng ngay khi Session 1 kết thúc. | Bản ghi được cập nhật sang `XUAT_KHO` và giải phóng khóa. |
| **T4** | — | Session 2 được đánh thức, tự động đánh giá lại điều kiện `AND trang_thai_hien_tai = 'NHAP_KHO'`.<br>`COMMIT;` | — | 🎯 **Kết quả trả về: `UPDATE 0`**.<br>Do trạng thái đã là `XUAT_KHO`, điều kiện `WHERE` không còn khớp $\rightarrow$ Không cập nhật. |
| **T5** | **Trạng thái cuối cùng của bưu kiện:** `SELECT ma_buu_kien, trang_thai_hien_tai FROM pa_b.buukien WHERE ma_buu_kien = 'PK00000001';`<br>$\rightarrow$ **Kết quả: `XUAT_KHO`** | | | ✅ **Ngăn chặn hoàn toàn hiện tượng Lost Update** (Session 2 không ghi đè dữ liệu cũ lên kết quả của Session 1). |

---

## 6.7. Kết luận chương thực nghiệm

1. **Về mặt hiệu năng:** Phương án B (`PA_B`) thể hiện ưu thế vượt trội ở cả hai kịch bản đọc trạng thái (nhanh hơn từ **88 lần đến 252 lần**), giải phóng gần như triệt để chi phí I/O đĩa và bộ nhớ đệm RAM. Dù chi phí ghi chậm hơn do Trigger đồng bộ, nhưng với đặc thù tỷ lệ Đọc/Ghi 9:1 của ngành chuyển phát, `PA_B` là phương án kiến trúc tối ưu.
2. **Về tính toàn vẹn dữ liệu:** Cơ chế Transaction bảo đảm tính nguyên tử `ROLLBACK` tuyệt đối khi vi phạm khóa ngoại; kỹ thuật khóa bi quan `SELECT ... FOR UPDATE` kết hợp điều kiện trạng thái loại trừ hoàn toàn nguy cơ xung đột mất mát dữ liệu (*Lost Update*) khi nhiều tài xế/nhân viên cùng thao tác đồng thời.
