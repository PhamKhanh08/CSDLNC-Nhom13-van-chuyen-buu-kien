-- ====================================================================
-- FILE: sql/05_sql_advanced.sql
-- BỘ 12 TRUY VẤN & THỦ TỤC SQL NÂNG CAO - ĐỀ TÀI 13
-- (Theo dõi vận chuyển và bàn giao bưu kiện - PostgreSQL 15+)
-- Chạy trên 2 schema: pa_a (History-based / BCNF) và pa_b (Current State)
-- ====================================================================
-- DANH MỤC 12 KỊCH BẢN SQL NÂNG CAO (ĐÁP ỨNG ĐẦY ĐỦ CHUẨN ĐẦU RA):
--   Q1. Hành trình đầy đủ của một bưu kiện & phát hiện sự kiện đến muộn (JOIN + ROW_NUMBER + MAX OVER cửa sổ lũy kế)
--   Q2. Thời gian lưu kho trung bình & cực đại tại từng điểm (CTE + LEAD OVER WINDOW + GROUP BY + HAVING)
--   Q3. Phát hiện bưu kiện chậm quá 48 giờ - Đối sánh PA A vs PA B (DISTINCT ON vs Direct Column Scan)
--   Q4. Tỷ lệ giao hàng thành công theo điểm và toàn hệ thống (COUNT FILTER + NULLIF + GROUP BY ROLLUP)
--   Q5. Tìm mọi điểm có thể đến trong mạng tuyến & chống chu trình (WITH RECURSIVE + Mảng đường đi ARRAY)
--   Q6. Truy vấn con tương quan & EXISTS / NOT EXISTS: Bưu kiện giá trị cao từng giao thất bại nhưng còn nguyên vẹn
--   Q7. Phép chia quan hệ (Relational Division): Tìm bưu kiện đã đi qua tất cả các điểm giao nhận cốt lõi
--   Q8. Hàm cửa sổ xếp hạng & Lũy kế doanh thu COD (DENSE_RANK + PERCENT_RANK + SUM OVER Running Total)
--   Q9. Kiểm toán (Audit) lịch sử chuyển trạng thái hợp lệ bằng hàm LAG() (Kiểm chứng quy tắc BR-03 & BR-05)
--   Q10. Hàm & Thủ tục (Function & Stored Procedure) bàn giao nguyên tử có kiểm tra State Transition & Idempotency
--   Q11. SQL Động (Dynamic SQL) tìm kiếm bưu kiện đa tiêu chí tùy chọn chống SQL Injection (format + USING)
--   Q12. Đối soát toàn vẹn trạng thái giữa PA A và PA B (EXCEPT / FULL JOIN) & Minh họa Con trỏ (CURSOR)
-- ====================================================================


-- ====================================================================
-- Q1. HÀNH TRÌNH CỦA MỘT BƯU KIỆN & PHÁT HIỆN SỰ KIỆN ĐẾN MUỘN
-- Nghiệp vụ: Tra cứu toàn bộ lịch sử trạng thái theo thời điểm XẢY RA,
--            đánh dấu sự kiện đến muộn (ghi nhận sau một sự kiện xảy ra muộn hơn nó - BR-06).
-- Kỹ thuật : LEFT JOIN, ROW_NUMBER(), MAX() OVER (cửa sổ lũy kế ROWS UNBOUNDED PRECEDING)
-- ====================================================================
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
WHERE sk.ma_buu_kien = 'PK00000001'          -- thay mã bưu kiện cần tra
ORDER BY sk.thoi_gian_xay_ra, sk.ma_su_kien;


-- ====================================================================
-- Q2. THỜI GIAN LƯU TẠI TỪNG ĐIỂM GIAO NHẬN
-- Nghiệp vụ: Với mỗi lần NHAP_KHO, thời gian lưu = thời điểm sự kiện kế tiếp
--            của cùng bưu kiện - thời điểm nhập. Sau đó thống kê trung bình theo điểm.
-- Kỹ thuật : CTE, LEAD() OVER (PARTITION BY ... ORDER BY ...), GROUP BY, HAVING
-- ====================================================================
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
      AND t_ra IS NOT NULL                 -- bỏ lần nhập chưa có sự kiện kế tiếp
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


-- ====================================================================
-- Q3. PHÁT HIỆN BƯU KIỆN CHẬM (ĐANG KẸT QUÁ 48 GIỜ)
-- Nghiệp vụ: Bưu kiện chưa ở trạng thái kết thúc (GIAO_THANH_CONG / HOAN_TRA)
--            mà sự kiện xảy ra gần nhất đã cách hiện tại quá 48 giờ.
-- Kỹ thuật : DISTINCT ON (PA A suy trạng thái từ lịch sử) so với đọc cột trực tiếp (PA B)
-- ====================================================================

-- 3a. PA A: trạng thái hiện tại SUY RA từ lịch sử
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

-- 3b. PA B: đọc thẳng cột trạng thái hiện tại (do trigger đồng bộ)
SELECT b.ma_buu_kien,
       b.trang_thai_hien_tai AS ma_trang_thai,
       b.thoi_gian_cap_nhat_cuoi AS su_kien_cuoi,
       ROUND(EXTRACT(EPOCH FROM (NOW() - b.thoi_gian_cap_nhat_cuoi)) / 3600, 1) AS gio_ke_lai
FROM pa_b.BuuKien b
WHERE b.trang_thai_hien_tai NOT IN ('GIAO_THANH_CONG', 'HOAN_TRA')
  AND b.thoi_gian_cap_nhat_cuoi < NOW() - INTERVAL '48 hours'
ORDER BY b.thoi_gian_cap_nhat_cuoi
LIMIT 50;


-- ====================================================================
-- Q4. TỶ LỆ GIAO THÀNH CÔNG THEO ĐIỂM VÀ TOÀN HỆ THỐNG
-- Nghiệp vụ: Trên các lượt giao đã có kết quả (thành công + thất bại), tính tỷ lệ
--            thành công của từng điểm và tổng toàn hệ thống.
-- Kỹ thuật : COUNT(*) FILTER, NULLIF (tránh chia 0), GROUP BY ROLLUP
-- ====================================================================
SELECT
    COALESCE(d.ma_diem_giao_nhan, 'TONG_HE_THONG') AS diem,
    MAX(d.ten_diem)                                 AS ten_diem,
    COUNT(*) FILTER (WHERE sk.ma_trang_thai = 'GIAO_THANH_CONG') AS thanh_cong,
    COUNT(*) FILTER (WHERE sk.ma_trang_thai = 'GIAO_THAT_BAI')   AS that_bai,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE sk.ma_trang_thai = 'GIAO_THANH_CONG')
        / NULLIF(COUNT(*) FILTER (WHERE sk.ma_trang_thai IN ('GIAO_THANH_CONG','GIAO_THAT_BAI')), 0)
    , 2) AS ty_le_thanh_cong_pct
FROM pa_a.SuKienTrangThai sk
JOIN pa_a.DiemGiaoNhan d ON d.ma_diem_giao_nhan = sk.ma_diem
WHERE sk.ma_trang_thai IN ('GIAO_THANH_CONG', 'GIAO_THAT_BAI')
GROUP BY ROLLUP (d.ma_diem_giao_nhan)
ORDER BY (d.ma_diem_giao_nhan IS NULL), ty_le_thanh_cong_pct DESC NULLS LAST;


-- ====================================================================
-- Q5. CÁC ĐIỂM CÓ THỂ ĐẾN TRONG MẠNG TUYẾN (TRUY VẤN ĐỆ QUY)
-- Nghiệp vụ: Từ một điểm xuất phát, tìm mọi điểm đến được qua tối đa N chặng,
--            kèm đường đi; mạng có thể có vòng nên phải chống chu trình.
-- Kỹ thuật : WITH RECURSIVE, mảng đường đi + điều kiện <> ALL(path), giới hạn độ sâu
-- ====================================================================

-- Khởi tạo các điểm nút và tuyến mẫu (có chu trình DGN00015 -> DGN00011) đồng bộ trên cả pa_a và pa_b để kiểm chứng đệ quy:
INSERT INTO pa_a.DiemGiaoNhan (ma_diem_giao_nhan, ten_diem, dia_chi) VALUES
    ('DGN00001', 'Bưu cục Trung tâm Quận 1', '12 Nguyễn Huệ, Quận 1, TP.HCM'),
    ('DGN00002', 'Kho Trung chuyển Tân Bình', '45 Trường Chinh, Tân Bình, TP.HCM'),
    ('DGN00003', 'Bưu cục Hoàn Kiếm', '88 Đinh Tiên Hoàng, Hoàn Kiếm, Hà Nội'),
    ('DGN00005', 'Bưu cục Đà Nẵng', 'Hải Châu, Đà Nẵng'),
    ('DGN00006', 'Bưu cục Cầu Giấy', 'Cầu Giấy, Hà Nội'),
    ('DGN00011', 'Kho Trung chuyển Miền Nam', 'Tân Bình, TP.HCM'),
    ('DGN00012', 'Kho Trung chuyển Miền Trung', 'Liên Chiểu, Đà Nẵng'),
    ('DGN00013', 'Kho Trung chuyển Miền Bắc', 'Gia Lâm, Hà Nội'),
    ('DGN00015', 'Kho Trung chuyển Nội Bài', 'Sóc Sơn, Hà Nội')
ON CONFLICT (ma_diem_giao_nhan) DO NOTHING;

INSERT INTO pa_b.DiemGiaoNhan (ma_diem_giao_nhan, ten_diem, dia_chi) VALUES
    ('DGN00001', 'Bưu cục Trung tâm Quận 1', '12 Nguyễn Huệ, Quận 1, TP.HCM'),
    ('DGN00002', 'Kho Trung chuyển Tân Bình', '45 Trường Chinh, Tân Bình, TP.HCM'),
    ('DGN00003', 'Bưu cục Hoàn Kiếm', '88 Đinh Tiên Hoàng, Hoàn Kiếm, Hà Nội'),
    ('DGN00005', 'Bưu cục Đà Nẵng', 'Hải Châu, Đà Nẵng'),
    ('DGN00006', 'Bưu cục Cầu Giấy', 'Cầu Giấy, Hà Nội'),
    ('DGN00011', 'Kho Trung chuyển Miền Nam', 'Tân Bình, TP.HCM'),
    ('DGN00012', 'Kho Trung chuyển Miền Trung', 'Liên Chiểu, Đà Nẵng'),
    ('DGN00013', 'Kho Trung chuyển Miền Bắc', 'Gia Lâm, Hà Nội'),
    ('DGN00015', 'Kho Trung chuyển Nội Bài', 'Sóc Sơn, Hà Nội')
ON CONFLICT (ma_diem_giao_nhan) DO NOTHING;

INSERT INTO pa_a.TuyenVanChuyen (ma_tuyen, ten_tuyen, dau_tuyen, cuoi_tuyen) VALUES
    ('T05', 'BC1 - Kho11',   'DGN00001', 'DGN00011'),
    ('T06', 'Kho2 - Kho11',  'DGN00002', 'DGN00011'),
    ('T07', 'Kho11 - Kho12', 'DGN00011', 'DGN00012'),
    ('T08', 'Kho12 - Kho13', 'DGN00012', 'DGN00013'),
    ('T09', 'Kho13 - Kho15', 'DGN00013', 'DGN00015'),
    ('T10', 'Kho15 - Kho11', 'DGN00015', 'DGN00011'),   -- tạo chu trình quay vòng
    ('T11', 'Kho12 - BC5',   'DGN00012', 'DGN00005'),
    ('T12', 'Kho13 - BC6',   'DGN00013', 'DGN00006')
ON CONFLICT (ma_tuyen) DO NOTHING;

INSERT INTO pa_b.TuyenVanChuyen (ma_tuyen, ten_tuyen, dau_tuyen, cuoi_tuyen) VALUES
    ('T05', 'BC1 - Kho11',   'DGN00001', 'DGN00011'),
    ('T06', 'Kho2 - Kho11',  'DGN00002', 'DGN00011'),
    ('T07', 'Kho11 - Kho12', 'DGN00011', 'DGN00012'),
    ('T08', 'Kho12 - Kho13', 'DGN00012', 'DGN00013'),
    ('T09', 'Kho13 - Kho15', 'DGN00013', 'DGN00015'),
    ('T10', 'Kho15 - Kho11', 'DGN00015', 'DGN00011'),   -- tạo chu trình quay vòng
    ('T11', 'Kho12 - BC5',   'DGN00012', 'DGN00005'),
    ('T12', 'Kho13 - BC6',   'DGN00013', 'DGN00006')
ON CONFLICT (ma_tuyen) DO NOTHING;

WITH RECURSIVE mang AS (
    -- Neo: các tuyến đi ra từ điểm xuất phát
    SELECT
        t.dau_tuyen,
        t.cuoi_tuyen AS diem_den,
        1            AS so_chang,
        ARRAY[t.dau_tuyen, t.cuoi_tuyen]::VARCHAR[] AS duong_di
    FROM pa_a.TuyenVanChuyen t
    WHERE t.dau_tuyen = 'DGN00001'                -- thay điểm xuất phát

    UNION ALL

    -- Đệ quy: nối thêm một chặng, bỏ qua điểm đã đi qua và giới hạn 4 chặng
    SELECT
        m.dau_tuyen,
        t.cuoi_tuyen,
        m.so_chang + 1,
        m.duong_di || t.cuoi_tuyen
    FROM mang m
    JOIN pa_a.TuyenVanChuyen t ON t.dau_tuyen = m.diem_den
    WHERE t.cuoi_tuyen <> ALL (m.duong_di)       -- chống chu trình
      AND m.so_chang < 4                         -- giới hạn độ sâu
)
SELECT
    m.diem_den,
    d.ten_diem,
    MIN(m.so_chang)                                  AS so_chang_ngan_nhat,
    (ARRAY_AGG(array_to_string(m.duong_di, ' -> ')
               ORDER BY m.so_chang))[1]              AS duong_di_ngan_nhat
FROM mang m
JOIN pa_a.DiemGiaoNhan d ON d.ma_diem_giao_nhan = m.diem_den
GROUP BY m.diem_den, d.ten_diem
ORDER BY so_chang_ngan_nhat, m.diem_den;


-- ====================================================================
-- Q6. TRUY VẤN CON TƯƠNG QUAN (CORRELATED SUBQUERY) & EXISTS / NOT EXISTS
-- Nghiệp vụ: Tìm các bưu kiện có giá trị khai giá >= 1.000.000đ VÀ có trọng lượng
--            lớn hơn trọng lượng trung bình của chính khách hàng gửi đó,
--            đã từng phát sinh sự kiện GIAO_THAT_BAI (dùng EXISTS),
--            nhưng chưa từng bị ghi nhận hư hỏng/móp méo trong các lần bàn giao (NOT EXISTS).
-- Kỹ thuật : Correlated Subquery, EXISTS, NOT EXISTS, INNER JOIN
-- ====================================================================
SELECT
    bk.ma_buu_kien,
    kh.ma_khach_hang AS ma_nguoi_gui,
    kh.ho_ten        AS ten_nguoi_gui,
    bk.trong_luong,
    bk.gia_khai,
    bk.tien_COD
FROM pa_a.BuuKien bk
JOIN pa_a.KhachHang kh ON kh.ma_khach_hang = bk.ma_khach_hang_gui
WHERE bk.gia_khai >= 1000000
  -- 1. Truy vấn con tương quan: Trọng lượng lớn hơn TB các đơn của cùng người gửi
  AND bk.trong_luong > (
      SELECT AVG(bk_sub.trong_luong)
      FROM pa_a.BuuKien bk_sub
      WHERE bk_sub.ma_khach_hang_gui = bk.ma_khach_hang_gui
  )
  -- 2. EXISTS: Đã từng có ít nhất 1 lần giao thất bại trong lịch sử
  AND EXISTS (
      SELECT 1
      FROM pa_a.SuKienTrangThai sk
      WHERE sk.ma_buu_kien = bk.ma_buu_kien
        AND sk.ma_trang_thai = 'GIAO_THAT_BAI'
  )
  -- 3. NOT EXISTS: Chưa từng có biên bản bàn giao nào ghi nhận tình trạng khác NGUYEN_VEN
  AND NOT EXISTS (
      SELECT 1
      FROM pa_a.LanBanGiao lbg
      WHERE lbg.ma_buu_kien = bk.ma_buu_kien
        AND lbg.tinh_trang <> 'NGUYEN_VEN'
  )
ORDER BY bk.gia_khai DESC, bk.trong_luong DESC
LIMIT 30;


-- ====================================================================
-- Q7. PHÉP CHIA QUAN HỆ (RELATIONAL DIVISION)
-- Nghiệp vụ: Tìm các bưu kiện đã đi qua TẤT CẢ các điểm giao nhận cốt lõi
--            trong danh sách ('DGN00001', 'DGN00002', 'DGN00003') trong lịch sử hành trình.
-- Kỹ thuật : Biểu diễn phép chia R ÷ S bằng phủ định kép (NOT EXISTS ... NOT EXISTS)
-- ====================================================================
WITH tap_diem_cot_loi AS (
    SELECT ma_diem_giao_nhan, ten_diem
    FROM pa_a.DiemGiaoNhan
    WHERE ma_diem_giao_nhan IN ('DGN00001', 'DGN00002', 'DGN00003')
)
SELECT
    bk.ma_buu_kien,
    bk.ma_khach_hang_gui,
    bk.ma_khach_hang_nhan,
    bk.trong_luong
FROM pa_a.BuuKien bk
WHERE NOT EXISTS (
    -- Không tồn tại điểm cốt lõi nào mà bưu kiện này chưa từng có sự kiện đi qua
    SELECT 1
    FROM tap_diem_cot_loi d
    WHERE NOT EXISTS (
        SELECT 1
        FROM pa_a.SuKienTrangThai sk
        WHERE sk.ma_buu_kien = bk.ma_buu_kien
          AND sk.ma_diem = d.ma_diem_giao_nhan
    )
)
ORDER BY bk.ma_buu_kien
LIMIT 30;


-- ====================================================================
-- Q8. XẾP HẠNG KHÁCH HÀNG & PHÂN TÍCH LŨY KẾ DOANH THU COD (WINDOW FUNCTIONS)
-- Nghiệp vụ: Thống kê tổng số bưu kiện giao thành công, tổng tiền thu hộ COD
--            và giá trị khai giá theo từng khách hàng gửi; xếp hạng khách hàng
--            (DENSE_RANK), tính phân vị (PERCENT_RANK) và tổng COD lũy kế (Running Total).
-- Kỹ thuật : CTE, DENSE_RANK() OVER, PERCENT_RANK() OVER, SUM() OVER (ROWS UNBOUNDED PRECEDING)
-- ====================================================================
WITH thong_ke_khach_gui AS (
    SELECT
        kh.ma_khach_hang,
        kh.ho_ten,
        COUNT(DISTINCT bk.ma_buu_kien) AS so_don_thanh_cong,
        SUM(bk.tien_COD)               AS tong_tien_cod,
        SUM(bk.gia_khai)               AS tong_gia_khai
    FROM pa_b.KhachHang kh
    JOIN pa_b.BuuKien bk ON bk.ma_khach_hang_gui = kh.ma_khach_hang
    WHERE bk.trang_thai_hien_tai = 'GIAO_THANH_CONG'
    GROUP BY kh.ma_khach_hang, kh.ho_ten
)
SELECT
    DENSE_RANK() OVER (ORDER BY tong_tien_cod DESC, so_don_thanh_cong DESC) AS hang_khach_hang,
    ma_khach_hang,
    ho_ten,
    so_don_thanh_cong,
    tong_tien_cod,
    tong_gia_khai,
    -- Tổng COD lũy kế từ khách hàng hạng 1 đến khách hàng hiện tại
    SUM(tong_tien_cod) OVER (
        ORDER BY tong_tien_cod DESC, ma_khach_hang
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS luy_ke_cod,
    -- Tỷ trọng đóng góp (%) trên tổng tiền COD toàn hệ thống
    ROUND(100.0 * tong_tien_cod / NULLIF(SUM(tong_tien_cod) OVER (), 0), 2) AS ty_trong_cod_pct
FROM thong_ke_khach_gui
ORDER BY hang_khach_hang, ma_khach_hang
LIMIT 20;


-- ====================================================================
-- Q9. KIỂM TOÁN (AUDIT) CHUYỂN TRẠNG THÁI HỢP LỆ THEO MA TRẬN STATE TRANSITION
-- Nghiệp vụ: Dùng hàm cửa sổ LAG() đối chiếu từng cặp trạng thái liên tiếp
--            (trang_thai_truoc -> trang_thai_moi) theo thời gian xảy ra của mọi bưu kiện,
--            phát hiện các bước chuyển trạng thái vi phạm quy tắc BR-03 hoặc BR-05.
-- Kỹ thuật : LAG() OVER, CASE WHEN kiểm tra Ma trận 10 bước chuyển trạng thái chuẩn
-- ====================================================================
WITH cap_chuyen_trang_thai AS (
    SELECT
        sk.ma_buu_kien,
        sk.ma_su_kien,
        LAG(sk.ma_trang_thai) OVER (
            PARTITION BY sk.ma_buu_kien
            ORDER BY sk.thoi_gian_xay_ra, sk.ma_su_kien
        ) AS trang_thai_truoc,
        sk.ma_trang_thai AS trang_thai_moi,
        sk.thoi_gian_xay_ra
    FROM pa_a.SuKienTrangThai sk
)
SELECT
    trang_thai_truoc,
    trang_thai_moi,
    COUNT(*) AS so_luot_chuyen,
    CASE
        WHEN trang_thai_truoc IS NULL AND trang_thai_moi = 'TIEP_NHAN' THEN 'HOP_LE (Khoi tao)'
        WHEN (trang_thai_truoc, trang_thai_moi) IN (
            ('TIEP_NHAN',       'NHAP_KHO'),
            ('TIEP_NHAN',       'XUAT_KHO'),
            ('NHAP_KHO',        'XUAT_KHO'),
            ('NHAP_KHO',        'DANG_GIAO'),
            ('XUAT_KHO',        'DANG_VAN_CHUYEN'),
            ('DANG_VAN_CHUYEN', 'NHAP_KHO'),
            ('DANG_GIAO',       'GIAO_THANH_CONG'),
            ('DANG_GIAO',       'GIAO_THAT_BAI'),
            ('GIAO_THAT_BAI',   'DANG_GIAO'),
            ('GIAO_THAT_BAI',   'HOAN_TRA')
        ) THEN 'HOP_LE (Theo State Transition)'
        WHEN trang_thai_truoc IN ('GIAO_THANH_CONG', 'HOAN_TRA') THEN 'VI_PHAM BR-05 (Sau trang thai ket thuc)'
        ELSE 'VI_PHAM BR-03 (Chuyen nhay coc / Sai luong)'
    END AS ket_luan_kiem_toan
FROM cap_chuyen_trang_thai
GROUP BY trang_thai_truoc, trang_thai_moi
ORDER BY ket_luan_kiem_toan, so_luot_chuyen DESC;


-- ====================================================================
-- Q10. HÀM (FUNCTION) & THỦ TỤC (STORED PROCEDURE) NGHIỆP VỤ BÀN GIAO NGUYÊN TỬ
-- Nghiệp vụ:
--   1. Hàm fn_kiem_tra_chuyen_trang_thai: Kiểm tra cặp (trạng thái cũ, trạng thái mới)
--      có hợp lệ theo BR-03 và BR-05 hay không.
--   2. Thủ tục sp_ban_giao_va_cap_nhat_trang_thai: Thực hiện nguyên tử việc khóa dòng
--      bưu kiện (FOR UPDATE), kiểm tra hợp lệ, ghi biên bản LanBanGiao và chèn
--      SuKienTrangThai có chống gửi trùng (ON CONFLICT (idempotency_key) DO NOTHING).
-- Kỹ thuật : PL/pgSQL FUNCTION, PROCEDURE, SELECT ... FOR UPDATE, EXCEPTION HANDLING
-- ====================================================================

CREATE OR REPLACE FUNCTION pa_b.fn_kiem_tra_chuyen_trang_thai(
    p_trang_thai_cu  VARCHAR,
    p_trang_thai_moi VARCHAR
) RETURNS BOOLEAN AS $$
BEGIN
    IF p_trang_thai_cu IS NULL AND p_trang_thai_moi = 'TIEP_NHAN' THEN
        RETURN TRUE;
    END IF;

    -- Không cho phép chuyển tiếp từ trạng thái kết thúc (BR-05)
    IF p_trang_thai_cu IN ('GIAO_THANH_CONG', 'HOAN_TRA') THEN
        RETURN FALSE;
    END IF;

    -- Kiểm tra 10 bước chuyển trạng thái hợp lệ (BR-03)
    RETURN (p_trang_thai_cu, p_trang_thai_moi) IN (
        ('TIEP_NHAN',       'NHAP_KHO'),
        ('TIEP_NHAN',       'XUAT_KHO'),
        ('NHAP_KHO',        'XUAT_KHO'),
        ('NHAP_KHO',        'DANG_GIAO'),
        ('XUAT_KHO',        'DANG_VAN_CHUYEN'),
        ('DANG_VAN_CHUYEN', 'NHAP_KHO'),
        ('DANG_GIAO',       'GIAO_THANH_CONG'),
        ('DANG_GIAO',       'GIAO_THAT_BAI'),
        ('GIAO_THAT_BAI',   'DANG_GIAO'),
        ('GIAO_THAT_BAI',   'HOAN_TRA')
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;


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
    v_so_dong_chen         INT;
BEGIN
    -- 1. Khóa bi quan dòng bưu kiện để chống cập nhật đồng thời
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


-- ====================================================================
-- Q11. SQL ĐỘNG (DYNAMIC SQL) TÌM KIẾM BƯU KIỆN ĐA TIÊU CHÍ CHỐNG SQL INJECTION
-- Nghiệp vụ: Xây dựng hàm tra cứu bưu kiện với các bộ lọc tùy chọn (trạng thái,
--            người gửi, trọng lượng tối thiểu, tiền COD tối thiểu, cột sắp xếp).
-- Kỹ thuật : PL/pgSQL Dynamic SQL với format('%I') kiểm soát danh sách trắng (whitelist)
--            cho tên cột và mệnh đề EXECUTE ... USING $1, $2, $3, $4 chống SQL Injection.
-- ====================================================================
CREATE OR REPLACE FUNCTION pa_b.fn_tim_kiem_buu_kien_dong(
    p_trang_thai      VARCHAR DEFAULT NULL,
    p_ma_kh_gui       VARCHAR DEFAULT NULL,
    p_trong_luong_min NUMERIC DEFAULT NULL,
    p_cod_min         NUMERIC DEFAULT NULL,
    p_cot_sap_xep     VARCHAR DEFAULT 'thoi_gian_cap_nhat_cuoi',
    p_gioi_han        INT     DEFAULT 20
)
RETURNS TABLE (
    ma_buu_kien             VARCHAR,
    ma_khach_hang_gui       VARCHAR,
    ma_khach_hang_nhan      VARCHAR,
    trong_luong             NUMERIC,
    tien_COD                NUMERIC,
    trang_thai_hien_tai     VARCHAR,
    thoi_gian_cap_nhat_cuoi TIMESTAMP
) AS $$
DECLARE
    v_sql      TEXT;
    v_sort_col VARCHAR;
BEGIN
    -- Kiểm tra Whitelist cho cột sắp xếp (chuẩn hóa chữ thường để khớp định danh PostgreSQL khi dùng %I)
    IF lower(p_cot_sap_xep) IN ('ma_buu_kien', 'trong_luong', 'tien_cod', 'gia_khai', 'thoi_gian_cap_nhat_cuoi') THEN
        v_sort_col := lower(p_cot_sap_xep);
    ELSE
        v_sort_col := 'thoi_gian_cap_nhat_cuoi';
    END IF;

    v_sql := 'SELECT b.ma_buu_kien, b.ma_khach_hang_gui, b.ma_khach_hang_nhan, '
          || '       b.trong_luong, b.tien_COD, b.trang_thai_hien_tai, b.thoi_gian_cap_nhat_cuoi '
          || 'FROM pa_b.BuuKien b '
          || 'WHERE ($1 IS NULL OR b.trang_thai_hien_tai = $1) '
          || '  AND ($2 IS NULL OR b.ma_khach_hang_gui = $2) '
          || '  AND ($3 IS NULL OR b.trong_luong >= $3) '
          || '  AND ($4 IS NULL OR b.tien_COD >= $4) '
          || format('ORDER BY b.%I DESC LIMIT $5', v_sort_col);

    RETURN QUERY EXECUTE v_sql
        USING p_trang_thai, p_ma_kh_gui, p_trong_luong_min, p_cod_min, p_gioi_han;
END;
$$ LANGUAGE plpgsql;

-- Ví dụ gọi hàm SQL động:
SELECT * FROM pa_b.fn_tim_kiem_buu_kien_dong(
    p_trang_thai      => 'DANG_GIAO',
    p_ma_kh_gui       => NULL,
    p_trong_luong_min => 2.0,
    p_cod_min         => 500000,
    p_cot_sap_xep     => 'tien_COD',
    p_gioi_han        => 10
);


-- ====================================================================
-- Q12. ĐỐI SOÁT TOÀN VẸN TRẠNG THÁI PA_A VS PA_B & MINH HỌA CON TRỎ (CURSOR)
-- Nghiệp vụ:
--   12a. Đối soát trên toàn bộ 10.000 bưu kiện xem trạng thái suy diễn từ lịch sử
--        ở pa_a có khớp 100% với cột trang_thai_hien_tai do Trigger cập nhật ở pa_b không.
--   12b. Minh họa sử dụng Con trỏ (CURSOR) duyệt từng dòng bưu kiện có COD cao để
--        kết xuất báo cáo đối soát (phục vụ mục lập trình CSDL / SQL nhúng).
-- Kỹ thuật : CTE + FULL OUTER JOIN, PL/pgSQL Explicit CURSOR (OPEN / FETCH / CLOSE)
-- ====================================================================

-- 12a. Truy vấn đối soát sự nhất quán giữa Phương án A và Phương án B (Kết quả kỳ vọng: so_buu_kien_lech = 0)
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

-- 12b. Khối lệnh minh họa duyệt dữ liệu bằng Con trỏ tường minh (Explicit CURSOR)
DO $$
DECLARE
    cur_cod CURSOR FOR
        SELECT ma_buu_kien, ma_khach_hang_gui, tien_COD, trang_thai_hien_tai
        FROM pa_b.BuuKien
        WHERE tien_COD >= 1000000
          AND trang_thai_hien_tai = 'GIAO_THANH_CONG'
        ORDER BY ma_buu_kien
        LIMIT 5;
    v_rec         RECORD;
    v_tong_thu_ho NUMERIC(14, 2) := 0;
BEGIN
    OPEN cur_cod;
    LOOP
        FETCH cur_cod INTO v_rec;
        EXIT WHEN NOT FOUND;
        v_tong_thu_ho := v_tong_thu_ho + v_rec.tien_COD;
        RAISE NOTICE 'Doi soat COD -> Buu kien: %, Nguoi gui: %, COD: %, Trang thai: %',
            v_rec.ma_buu_kien, v_rec.ma_khach_hang_gui, v_rec.tien_COD, v_rec.trang_thai_hien_tai;
    END LOOP;
    CLOSE cur_cod;
    RAISE NOTICE 'Tong tien COD cua 5 don mau dau tien: % VND', v_tong_thu_ho;
END $$;
