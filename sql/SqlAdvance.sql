-- ====================================================================
-- FILE: sql/04_advanced_queries.sql
-- 5 CÂU SQL NÂNG CAO - ĐỀ TÀI 13 (Theo dõi vận chuyển & bàn giao bưu kiện)
-- Chạy trên PostgreSQL 15+, schema pa_a (History-based) và pa_b (Current State)
-- ====================================================================
-- Q1. Hành trình đầy đủ của một bưu kiện      (JOIN + ROW_NUMBER + phát hiện sự kiện đến muộn)
-- Q2. Thời gian lưu tại từng điểm              (LEAD + CTE + GROUP BY)
-- Q3. Bưu kiện chậm (đang kẹt quá ngưỡng)      (DISTINCT ON / CTE, so sánh pa_a vs pa_b)
-- Q4. Tỷ lệ giao thành công theo điểm          (FILTER + NULLIF + ROLLUP)
-- Q5. Các điểm có thể đến trong mạng tuyến     (WITH RECURSIVE + chống chu trình)
-- ====================================================================


-- ====================================================================
-- Q1. HÀNH TRÌNH CỦA MỘT BƯU KIỆN
-- Nghiệp vụ: Tra cứu toàn bộ lịch sử trạng thái theo thời điểm XẢY RA,
--            đánh dấu sự kiện đến muộn (ghi nhận sau một sự kiện xảy ra muộn hơn nó).
-- Kỹ thuật : JOIN, ROW_NUMBER(), MAX() OVER (cửa sổ lũy kế)
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
-- Q2. THỜI GIAN LƯU TẠI TỪNG ĐIỂM
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
-- Q3. BƯU KIỆN CHẬM
-- Nghiệp vụ: Bưu kiện chưa ở trạng thái kết thúc (GIAO_THANH_CONG / HOAN_TRA)
--            mà sự kiện xảy ra gần nhất đã cách hiện tại quá 48 giờ.
-- Kỹ thuật : DISTINCT ON (PA A suy trạng thái từ lịch sử) so với đọc cột trực tiếp (PA B)
--            -> dùng làm cặp truy vấn đối sánh EXPLAIN ANALYZE ở file 05.
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
-- Q4. TỶ LỆ GIAO THÀNH CÔNG THEO ĐIỂM
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
-- Q5. CÁC ĐIỂM CÓ THỂ ĐẾN TRONG MẠNG TUYẾN (ĐỆ QUY)
-- Nghiệp vụ: Từ một điểm xuất phát, tìm mọi điểm đến được qua tối đa N chặng,
--            kèm đường đi; mạng có thể có vòng nên phải chống chu trình.
-- Kỹ thuật : WITH RECURSIVE, mảng đường đi + điều kiện <> ALL(path), giới hạn độ sâu
-- ====================================================================

-- Dữ liệu mạng tuyến mẫu (generate_data.py chưa sinh bảng này). Chạy 1 lần.
-- Có cố ý một tuyến quay vòng (DGN015 -> DGN011) để kiểm chứng chống chu trình.
INSERT INTO pa_a.TuyenVanChuyen (ma_tuyen, ten_tuyen, dau_tuyen, cuoi_tuyen) VALUES
    ('T01', 'BC1 - Kho11',   'DGN001', 'DGN011'),
    ('T02', 'BC2 - Kho11',   'DGN002', 'DGN011'),
    ('T03', 'Kho11 - Kho12', 'DGN011', 'DGN012'),
    ('T04', 'Kho12 - Kho13', 'DGN012', 'DGN013'),
    ('T05', 'Kho13 - Kho15', 'DGN013', 'DGN015'),
    ('T06', 'Kho15 - Kho11', 'DGN015', 'DGN011'),   -- tạo chu trình
    ('T07', 'Kho12 - BC5',   'DGN012', 'DGN005'),
    ('T08', 'Kho13 - BC6',   'DGN013', 'DGN006')
ON CONFLICT (ma_tuyen) DO NOTHING;

WITH RECURSIVE mang AS (
    -- Neo: các tuyến đi ra từ điểm xuất phát
    SELECT
        t.dau_tuyen,
        t.cuoi_tuyen AS diem_den,
        1            AS so_chang,
        ARRAY[t.dau_tuyen, t.cuoi_tuyen]::VARCHAR[] AS duong_di
    FROM pa_a.TuyenVanChuyen t
    WHERE t.dau_tuyen = 'DGN001'                 -- thay điểm xuất phát

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
