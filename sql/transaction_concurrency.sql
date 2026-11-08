
-- ====================================================================
-- TRUONG DAI HOC SAI GON - KHOA CONG NGHE THONG TIN
-- MON HOC: CO SO DU LIEU NANG CAO - DE TAI 13
-- CHUONG 6: MA NGUON THUC NGHIEM BENCHMARK A/B
--            VA THAO TAC GIAO DICH
-- ====================================================================


-- ====================================================================
-- PHAN 1: BENCHMARK HIEU NANG TRUY VAN (MUC 6.2 - PA_A VS PA_B)
-- Bo den tung doan lenh va nhan Ctrl + Enter / F5 de xem EXPLAIN
-- ====================================================================


-- --------------------------------------------------------------------
-- 6.2.1. KICH BAN 1: Tra cuu trang thai hien tai cua 1 buu kien
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
-- 6.2.2. KICH BAN 2: Lay trang thai cua toan bo 10.000 buu kien
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
    thoi_gian_xay_ra DESC;


-- Phuong an B (Current State)
-- Scan truc tiep bang buukien voi 10.000 dong

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    ma_buu_kien,
    trang_thai_hien_tai,
    thoi_gian_cap_nhat_cuoi
FROM pa_b.buukien;



-- --------------------------------------------------------------------
-- 6.2.3. KICH BAN 3: Do chi phi ghi (INSERT + Trigger dong bo)
-- --------------------------------------------------------------------

-- Phuong an A (History-based)
-- Ghi thuan tuy vao bang lich su su kien

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
    'SK_BM_PAA_' || gen_random_uuid(),
    'PK00000001',
    'DANG_GIAO',
    'DGN01',
    'CAP_NHAT_TRANG_THAI',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    'KEY-BM-PAA-' || gen_random_uuid()
);


-- Phuong an B (Current State)
-- Ghi su kien va kich hoat Trigger PL/pgSQL
-- Dong bo trang thai sang bang buukien

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
    'SK_BM_PAB_' || gen_random_uuid(),
    'PK00000001',
    'DANG_GIAO',
    'DGN01',
    'CAP_NHAT_TRANG_THAI',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    'KEY-BM-PAB-' || gen_random_uuid()
);



-- ====================================================================
-- PHAN 2: KIEM THU GIAO DICH VA DIEU KHIEN DONG THOI (MUC 6.3)
-- ====================================================================


-- --------------------------------------------------------------------
-- 6.3.1. KIEM THU TINH NGUYEN TU (ATOMICITY) - KICH BAN ROLLBACK
-- Bo den chay toan bo khoi lenh ben duoi trong 1 Query Editor
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
     LIMIT 1),

    (SELECT ma_nhan_vien
     FROM pa_b.nhanvien
     LIMIT 1),

    (SELECT ma_diem_giao_nhan
     FROM pa_b.diemgiaonhan
     LIMIT 1),

    (SELECT ma_chuyen
     FROM pa_b.chuyenvanchuyen
     LIMIT 1),

    CURRENT_TIMESTAMP,
    'THANH_CONG',
    'Test Atomicity Rollback'
);


-- BUOC 2: LENH CO Y TAO LOI
-- Chen ma buu kien KHONG TON TAI de kich hoat loi FK 23503

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
    'PK_KHONG_TON_TAI_9999',
    'DANG_GIAO',

    (SELECT ma_diem_giao_nhan
     FROM pa_b.diemgiaonhan
     LIMIT 1),

    'CAP_NHAT_TRANG_THAI',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    'KEY-TEST-ROLLBACK'
);


-- BUOC 3: COMMIT SE BI TU CHOI
-- Do BUOC 2 vi pham rang buoc khoa ngoai
-- PostgreSQL chuyen transaction sang trang thai Aborted

COMMIT;


-- BUOC 4: ROLLBACK DE KET THUC GIAO DICH LOI
-- Huy toan bo thay doi chua duoc COMMIT

ROLLBACK;


-- BUOC 5: KIEM TRA KET QUA
-- Ket qua mong doi: 0 dong

SELECT *
FROM pa_b.lanbangiao
WHERE ma_ban_giao = 'LBG_TEST_ROLLBACK_01';



-- --------------------------------------------------------------------
-- 6.3.2. KIEM THU KHOA DONG DONG THOI (CONCURRENCY LOCKING)
-- Yeu cau mo 2 Tab Query Editor doc lap:
-- TAB 1: SESSION 1
-- TAB 2: SESSION 2
-- --------------------------------------------------------------------


-- ====================================================================
-- [TAB 1 - SESSION 1]
-- Mo giao dich va dat khoa doc quyen tren dong buu kien
-- ====================================================================

BEGIN;


-- BUOC 1: DOC VA KHOA DONG BANG SELECT FOR UPDATE

SELECT
    ma_buu_kien,
    trang_thai_hien_tai
FROM pa_b.buukien
WHERE ma_buu_kien = 'PK00000001'
FOR UPDATE;


-- TAM DUNG TAI DAY
-- Chuyen sang TAB 2 va chay lenh cua SESSION 2
-- De quan sat hien tuong Waiting for Lock


-- BUOC 2: CAP NHAT TRANG THAI
-- Thuc hien sau khi SESSION 2 dang cho khoa

UPDATE pa_b.buukien
SET trang_thai_hien_tai = 'DANG_VAN_CHUYEN'
WHERE ma_buu_kien = 'PK00000001';


-- BUOC 3: COMMIT VA GIAI PHONG KHOA

COMMIT;



-- ====================================================================
-- [TAB 2 - SESSION 2]
-- Co gang cap nhat dong dang bi SESSION 1 khoa
-- ====================================================================

BEGIN;


-- BUOC 1: THUC HIEN UPDATE
-- Lenh se cho SESSION 1 giai phong khoa

UPDATE pa_b.buukien
SET trang_thai_hien_tai = 'DA_GIAO_HANG'
WHERE ma_buu_kien = 'PK00000001';


-- BUOC 2: COMMIT SAU KHI SESSION 1 DA COMMIT

COMMIT;


-- ====================================================================
-- KET THUC CHUONG 6
-- ====================================================================
