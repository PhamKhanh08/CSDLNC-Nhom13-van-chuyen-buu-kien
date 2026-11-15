-- ====================================================================
-- TRUONG DAI HOC SAI GON - KHOA CONG NGHE THONG TIN
-- MON HOC: CO SO DU LIEU NANG CAO - DE TAI 13
-- CHUONG 6: MA NGUON THUC NGHIEM BENCHMARK A/B
--            VA THAO TAC GIAO DICH
-- ====================================================================


-- ====================================================================
-- PHAN 1: BENCHMARK HIEU NANG TRUY VAN (MUC 6.2 - 6.4: PA_A VS PA_B)
-- Bo den tung doan lenh va nhan Ctrl + Enter / F5 de xem EXPLAIN
-- ====================================================================


-- --------------------------------------------------------------------
-- 6.2. THUC NGHIEM 1: Truy van trang thai hien tai cua 1 buu kien
-- Ma buu kien: PK00000001
-- --------------------------------------------------------------------

-- Phuong an A (History-based)
-- Quet va loc subquery tren bang 100.000 su kien

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


-- Phuong an B (Current State)
-- Doc truc tiep 1 dong thong qua B-Tree Index

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    ma_buu_kien,
    trang_thai_hien_tai,
    thoi_gian_cap_nhat_cuoi
FROM pa_b.buukien
WHERE ma_buu_kien = 'PK00000001';



-- --------------------------------------------------------------------
-- 6.3. THUC NGHIEM 2: Truy van trang thai hien tai cua toan bo 10.000 buu kien
-- --------------------------------------------------------------------

-- Phuong an A (History-based)
-- DISTINCT ON + Sort tren 100.000 dong

EXPLAIN (ANALYZE, BUFFERS)
SELECT DISTINCT ON (ma_buu_kien)
    ma_buu_kien,
    ma_trang_thai,
    thoi_gian_xay_ra
FROM pa_a.sukientrangthai
ORDER BY
    ma_buu_kien,
    thoi_gian_xay_ra DESC,
    ma_su_kien DESC;


-- Phuong an B (Current State)
-- Scan truc tiep bang buukien voi 10.000 dong

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    ma_buu_kien,
    trang_thai_hien_tai,
    thoi_gian_cap_nhat_cuoi
FROM pa_b.buukien;



-- --------------------------------------------------------------------
-- 6.4. THUC NGHIEM 3: Ghi nhan mot su kien cap nhat trang thai (INSERT)
-- Su dung BEGIN ... ROLLBACK de do chinh xac EXPLAIN (ANALYZE, BUFFERS)
-- nhung khong de lai du lieu thu nghiem lam sai lech tap 100.000 su kien
-- --------------------------------------------------------------------

-- Phuong an A (History-based)
-- Ghi thuan tuy vao bang lich su su kien

BEGIN;

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

ROLLBACK;


-- Phuong an B (Current State)
-- Ghi su kien va kich hoat Trigger PL/pgSQL trg_cap_nhat_trang_thai
-- Dong bo trang thai sang bang buukien

BEGIN;

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

ROLLBACK;



-- ====================================================================
-- PHAN 2: KIEM THU GIAO DICH VA DONG THOI (MUC 6.6)
-- ====================================================================


-- --------------------------------------------------------------------
-- 6.6.1. KIEM THU ROLLBACK KHI VI PHAM KHOA NGOAI (TINH NGUYEN TU - ATOMICITY)
-- --------------------------------------------------------------------

-- RESET TRANSACTION NEU PHIEN LAM VIEC TRUOC BI LOI
ROLLBACK;


-- BAT DAU GIAO DICH
BEGIN;


-- BUOC 1: LENH HOP LE
-- Them bien ban ban giao voi cac ma khoa ngoai co san
INSERT INTO pa_b.lanbangiao (
    ma_ban_giao,
    ma_buu_kien,
    ma_nhan_vien,
    ma_diem_giao_nhan,
    ma_chuyen,
    thoi_gian_ban_giao,
    tinh_trang,
    ghi_chu
)
VALUES (
    'LBG_TEST_ROLLBACK_01',
    (SELECT ma_buu_kien
     FROM pa_b.buukien
     WHERE ma_buu_kien = 'PK00000001'
     LIMIT 1),

    (SELECT ma_nhan_vien
     FROM pa_b.nhanvien
     WHERE ma_nhan_vien = 'NV01'
     LIMIT 1),

    (SELECT ma_diem_giao_nhan
     FROM pa_b.diemgiaonhan
     WHERE ma_diem_giao_nhan = 'DGN00001'
     LIMIT 1),

    (SELECT ma_chuyen
     FROM pa_b.chuyenvanchuyen
     WHERE ma_chuyen = 'CH01'
     LIMIT 1),

    CURRENT_TIMESTAMP,
    'THANH_CONG',
    'Test Atomicity Rollback'
);


-- KIEM TRA TRONG GIAO DICH CHUA COMMIT (Hinh 6.1)
SELECT * FROM pa_b.lanbangiao WHERE ma_ban_giao = 'LBG_TEST_ROLLBACK_01';


-- BUOC 2: LENH CO Y TAO LOI (Hinh 6.2)
-- Chen ma buu kien KHONG TON TAI ('PK_KHONG_TON_TAI') de kich hoat loi FK 23503
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
    'SK_TEST_ROLLBACK_01',
    'PK_KHONG_TON_TAI',
    'DANG_GIAO',
    (SELECT ma_diem_giao_nhan FROM pa_b.diemgiaonhan LIMIT 1),
    'CAP_NHAT_TRANG_THAI',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    'KEY-TEST-ROLLBACK'
);


-- BUOC 3: ROLLBACK DE KET THUC GIAO DICH LOI (Hinh 6.3)
-- Huy toan bo thay doi chua duoc COMMIT
ROLLBACK;


-- BUOC 4: TRUY VAN XAC MINH SAU ROLLBACK (Hinh 6.4)
-- Ket qua mong doi: 0 dong
SELECT * FROM pa_b.lanbangiao WHERE ma_ban_giao = 'LBG_TEST_ROLLBACK_01';



-- --------------------------------------------------------------------
-- 6.6.2 & 6.6.3. KIEM THU DONG THOI VA TRANG THAI CUOI (CONCURRENCY LOCKING)
-- Yeu cau mo 3 Tab Query Editor doc lap:
-- TAB 1: SESSION 1
-- TAB 2: SESSION 2
-- TAB 3: SESSION 3 (Giam sat khoa tren pg_stat_activity)
-- --------------------------------------------------------------------

-- BUOC 0: Dat trang thai ban dau NHAP_KHO cho PK00000001
UPDATE pa_b.buukien
SET trang_thai_hien_tai = 'NHAP_KHO'
WHERE ma_buu_kien = 'PK00000001';


-- ====================================================================
-- [TAB 1 - SESSION 1] (Buoc 1 - Hinh 6.5)
-- Mo giao dich va khoa dong buu kien bang SELECT ... FOR UPDATE
-- ====================================================================
BEGIN;
SELECT ma_buu_kien, trang_thai_hien_tai FROM pa_b.buukien
WHERE ma_buu_kien = 'PK00000001' FOR UPDATE;
-- Tam dung tai day, chuyen sang TAB 2 chay Session 2 va TAB 3 quan sat khoa


-- ====================================================================
-- [TAB 2 - SESSION 2] (Chay khi Session 1 dang giu khoa - Hinh 6.6 & Hinh 6.9)
-- ====================================================================
BEGIN;
UPDATE pa_b.buukien
SET trang_thai_hien_tai = 'DANG_GIAO'
WHERE ma_buu_kien = 'PK00000001'
  AND trang_thai_hien_tai = 'NHAP_KHO';   -- ket qua sau khi Session 1 COMMIT: UPDATE 0
COMMIT;


-- ====================================================================
-- [TAB 3 - SESSION 3] (Chay trong luc Session 2 dang cho khoa - Hinh 6.7)
-- ====================================================================
SELECT pid, state, wait_event_type, wait_event, left(query, 70) AS query
FROM pg_stat_activity
WHERE datname = 'CSDLNC_DeTai13' AND pid <> pg_backend_pid();


-- ====================================================================
-- [TAB 1 - SESSION 1] (Buoc 2: Cap nhat sang XUAT_KHO va COMMIT - Hinh 6.8)
-- ====================================================================
UPDATE pa_b.buukien
SET trang_thai_hien_tai = 'XUAT_KHO'
WHERE ma_buu_kien = 'PK00000001';

COMMIT;


-- ====================================================================
-- 6.6.3. KIEM TRA TRANG THAI CUOI (Hinh 6.10)
-- ====================================================================
SELECT ma_buu_kien, trang_thai_hien_tai, thoi_gian_cap_nhat_cuoi
FROM pa_b.buukien
WHERE ma_buu_kien = 'PK00000001';

-- Khoi phuc trang thai dong bo cua PK00000001 theo lich su su kien sau khi hoan tat kiem thu
UPDATE pa_b.buukien b
SET trang_thai_hien_tai = sub.ma_trang_thai,
    thoi_gian_cap_nhat_cuoi = sub.thoi_gian_xay_ra
FROM (
    SELECT ma_trang_thai, thoi_gian_xay_ra
    FROM pa_b.sukientrangthai
    WHERE ma_buu_kien = 'PK00000001'
    ORDER BY thoi_gian_xay_ra DESC, ma_su_kien DESC
    LIMIT 1
) sub
WHERE b.ma_buu_kien = 'PK00000001';


-- ====================================================================
-- KET THUC CHUONG 6
-- ====================================================================
