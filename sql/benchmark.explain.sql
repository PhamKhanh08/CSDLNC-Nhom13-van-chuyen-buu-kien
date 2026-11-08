-- ====================================================================
-- CHƯƠNG 6: KỊCH BẢN BENCHMARK ĐỐI SÁNH HIỆU NĂNG (PA_A vs PA_B)
-- ====================================================================


-- --------------------------------------------------------------------
-- KỊCH BẢN 1: Truy vấn trạng thái hiện tại của 1 bưu kiện (PK00000001)
-- --------------------------------------------------------------------

-- Phương án A (History-based)
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    bk.ma_buu_kien,
    sk.ma_trang_thai,
    sk.thoi_gian_xay_ra
FROM pa_a.buukien bk
JOIN pa_a.sukientrangthai sk
    ON bk.ma_buu_kien = sk.ma_buu_kien
WHERE
    bk.ma_buu_kien = 'PK00000001'
    AND sk.thoi_gian_xay_ra = (
        SELECT MAX(sub.thoi_gian_xay_ra)
        FROM pa_a.sukientrangthai sub
        WHERE sub.ma_buu_kien = 'PK00000001'
    );


-- Phương án B (Current State)
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    ma_buu_kien,
    trang_thai_hien_tai,
    thoi_gian_cap_nhat_cuoi
FROM pa_b.buukien
WHERE ma_buu_kien = 'PK00000001';


-- --------------------------------------------------------------------
-- KỊCH BẢN 2: Truy vấn trạng thái hiện tại của toàn bộ 10.000 bưu kiện
-- --------------------------------------------------------------------

-- Phương án A (History-based)
EXPLAIN (ANALYZE, BUFFERS)
SELECT DISTINCT ON (ma_buu_kien)
    ma_buu_kien,
    ma_trang_thai,
    thoi_gian_xay_ra
FROM pa_a.sukientrangthai
ORDER BY
    ma_buu_kien,
    thoi_gian_xay_ra DESC;


-- Phương án B (Current State)
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    ma_buu_kien,
    trang_thai_hien_tai,
    thoi_gian_cap_nhat_cuoi
FROM pa_b.buukien;


-- --------------------------------------------------------------------
-- KỊCH BẢN 3: Đo chi phí ghi (INSERT + Trigger đồng bộ)
-- --------------------------------------------------------------------

-- Phương án A (Ghi đơn thuần)
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO pa_a.sukientrangthai (
    ma_su_kien,
    ma_buu_kien,
    ma_trang_thai,
    ma_diem,
    loai_su_kien,
    thoi_gian_xay_ra,
    thoi_gian_ghi_nhan,
    idempotency_key
)
VALUES (
    'SK_BENCHMARK_PA_A',
    'PK00000001',
    'DANG_GIAO',
    'DGN00001',
    'CAP_NHAT_TRANG_THAI',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    'KEY-BM-PAA-01'
);


-- Phương án B (Ghi kèm kích hoạt Trigger PL/pgSQL)
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO pa_b.sukientrangthai (
    ma_su_kien,
    ma_buu_kien,
    ma_trang_thai,
    ma_diem,
    loai_su_kien,
    thoi_gian_xay_ra,
    thoi_gian_ghi_nhan,
    idempotency_key
)
VALUES (
    'SK_BENCHMARK_PA_B',
    'PK00000001',
    'DANG_GIAO',
    'DGN00001',
    'CAP_NHAT_TRANG_THAI',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    'KEY-BM-PAB-01'
);