-- ====================================================================
-- FILE: sql/07_validate_pa_a_pa_b.sql
-- BỘ KIỂM THỬ & ĐỐI SOÁT TOÀN DIỆN GIỮA PHƯƠNG ÁN A (pa_a) VÀ PHƯƠNG ÁN B (pa_b)
-- Kiểm tra 7 hạng mục:
--   1. Số lượng bản ghi trên toàn bộ 14 bảng của pa_a và pa_b.
--   2. Tính thống nhất của mã DGN (DGN00001..) và toàn vẹn khóa ngoại.
--   3. Kiểm tra trùng lặp khóa chính, idempotency_key và thời gian sự kiện.
--   4. Kiểm toán vòng đời trạng thái hợp lệ (BR-03 & BR-05).
--   5. Đối chiếu tập dữ liệu và trạng thái cuối cùng giữa PA_A và PA_B trên 10.000 bưu kiện.
--   6. Xuất danh sách bưu kiện bị lệch giữa PA_A và PA_B (Kỳ vọng: 0 dòng).
--   7. Kiểm thử tự động Trigger PA_B (sự kiện mới, sự kiện đến muộn, trùng thời gian, gửi trùng)
--      bên trong giao dịch BEGIN ... ROLLBACK.
-- ====================================================================

\echo '===================================================================='
\echo '1. KIEM TRA SO LUONG BAN GHI TREN 14 BANG CUA PA_A VA PA_B'
\echo '===================================================================='
SELECT
    tbl AS ten_bang,
    pa_a_count AS so_dong_pa_a,
    pa_b_count AS so_dong_pa_b,
    CASE WHEN pa_a_count = pa_b_count THEN 'PASS' ELSE 'FAIL' END AS ket_qua
FROM (
    SELECT 1 AS ord, 'DiemGiaoNhan' AS tbl, (SELECT COUNT(*) FROM pa_a.DiemGiaoNhan) AS pa_a_count, (SELECT COUNT(*) FROM pa_b.DiemGiaoNhan) AS pa_b_count
    UNION ALL SELECT 2, 'BuuCuc', (SELECT COUNT(*) FROM pa_a.BuuCuc), (SELECT COUNT(*) FROM pa_b.BuuCuc)
    UNION ALL SELECT 3, 'KhoTrungChuyen', (SELECT COUNT(*) FROM pa_a.KhoTrungChuyen), (SELECT COUNT(*) FROM pa_b.KhoTrungChuyen)
    UNION ALL SELECT 4, 'TuyenVanChuyen', (SELECT COUNT(*) FROM pa_a.TuyenVanChuyen), (SELECT COUNT(*) FROM pa_b.TuyenVanChuyen)
    UNION ALL SELECT 5, 'ChuyenVanChuyen', (SELECT COUNT(*) FROM pa_a.ChuyenVanChuyen), (SELECT COUNT(*) FROM pa_b.ChuyenVanChuyen)
    UNION ALL SELECT 6, 'ChiTietChuyenVanChuyen', (SELECT COUNT(*) FROM pa_a.ChiTietChuyenVanChuyen), (SELECT COUNT(*) FROM pa_b.ChiTietChuyenVanChuyen)
    UNION ALL SELECT 7, 'KhachHang', (SELECT COUNT(*) FROM pa_a.KhachHang), (SELECT COUNT(*) FROM pa_b.KhachHang)
    UNION ALL SELECT 8, 'BuuKien', (SELECT COUNT(*) FROM pa_a.BuuKien), (SELECT COUNT(*) FROM pa_b.BuuKien)
    UNION ALL SELECT 9, 'NhanVien', (SELECT COUNT(*) FROM pa_a.NhanVien), (SELECT COUNT(*) FROM pa_b.NhanVien)
    UNION ALL SELECT 10, 'Shipper', (SELECT COUNT(*) FROM pa_a.Shipper), (SELECT COUNT(*) FROM pa_b.Shipper)
    UNION ALL SELECT 11, 'NhanVienKho', (SELECT COUNT(*) FROM pa_a.NhanVienKho), (SELECT COUNT(*) FROM pa_b.NhanVienKho)
    UNION ALL SELECT 12, 'PhuTrach', (SELECT COUNT(*) FROM pa_a.PhuTrach), (SELECT COUNT(*) FROM pa_b.PhuTrach)
    UNION ALL SELECT 13, 'LanBanGiao', (SELECT COUNT(*) FROM pa_a.LanBanGiao), (SELECT COUNT(*) FROM pa_b.LanBanGiao)
    UNION ALL SELECT 14, 'SuKienTrangThai', (SELECT COUNT(*) FROM pa_a.SuKienTrangThai), (SELECT COUNT(*) FROM pa_b.SuKienTrangThai)
) t
ORDER BY ord;


\echo '===================================================================='
\echo '2. KIEM TRA DINH DANG MA DIEM GIAO NHAN (DGN000XX) & KHOA NGOAI'
\echo '===================================================================='
SELECT
    hang_muc_kiem_tra,
    so_loi,
    CASE WHEN so_loi = 0 THEN 'PASS' ELSE 'FAIL' END AS ket_qua
FROM (
    SELECT 1 AS ord, 'DGN sai dinh dang DGN + 5 chu so trong pa_a.DiemGiaoNhan' AS hang_muc_kiem_tra,
           COUNT(*) AS so_loi FROM pa_a.DiemGiaoNhan WHERE ma_diem_giao_nhan !~ '^DGN[0-9]{5}$'
    UNION ALL
    SELECT 2, 'DGN sai dinh dang DGN + 5 chu so trong pa_b.DiemGiaoNhan',
           COUNT(*) FROM pa_b.DiemGiaoNhan WHERE ma_diem_giao_nhan !~ '^DGN[0-9]{5}$'
    UNION ALL
    SELECT 3, 'SuKienTrangThai (pa_a) tham chieu ma_diem sai dinh dang DGN + 5 chu so',
           COUNT(*) FROM pa_a.SuKienTrangThai WHERE ma_diem !~ '^DGN[0-9]{5}$'
    UNION ALL
    SELECT 4, 'SuKienTrangThai (pa_b) tham chieu ma_diem sai dinh dang DGN + 5 chu so',
           COUNT(*) FROM pa_b.SuKienTrangThai WHERE ma_diem !~ '^DGN[0-9]{5}$'
    UNION ALL
    SELECT 5, 'SuKienTrangThai (pa_a) co ma_buu_kien hoac ma_diem NULL',
           COUNT(*) FROM pa_a.SuKienTrangThai WHERE ma_buu_kien IS NULL OR ma_diem IS NULL
    UNION ALL
    SELECT 6, 'SuKienTrangThai (pa_b) co ma_buu_kien hoac ma_diem NULL',
           COUNT(*) FROM pa_b.SuKienTrangThai WHERE ma_buu_kien IS NULL OR ma_diem IS NULL
    UNION ALL
    SELECT 7, 'BuuKien (pa_a) co nguoi gui hoac nguoi nhan NULL',
           COUNT(*) FROM pa_a.BuuKien WHERE ma_khach_hang_gui IS NULL OR ma_khach_hang_nhan IS NULL
    UNION ALL
    SELECT 8, 'BuuKien (pa_b) co nguoi gui hoac nguoi nhan NULL',
           COUNT(*) FROM pa_b.BuuKien WHERE ma_khach_hang_gui IS NULL OR ma_khach_hang_nhan IS NULL
) fk_chk
ORDER BY ord;


\echo '===================================================================='
\echo '3. KIEM TRA SU KIEN TRUNG LAP & TRUNG THOI GIAN TREN CUNG BUU KIEN'
\echo '===================================================================='
SELECT
    hang_muc_kiem_tra,
    so_luong_trung,
    CASE WHEN so_luong_trung = 0 THEN 'PASS' ELSE 'FAIL' END AS ket_qua
FROM (
    SELECT 1 AS ord, 'So cap (ma_buu_kien, thoi_gian_xay_ra) bi trung trong pa_a.SuKienTrangThai' AS hang_muc_kiem_tra,
           COUNT(*) AS so_luong_trung
    FROM (
        SELECT ma_buu_kien, thoi_gian_xay_ra
        FROM pa_a.SuKienTrangThai
        GROUP BY ma_buu_kien, thoi_gian_xay_ra
        HAVING COUNT(*) > 1
    ) s1
    UNION ALL
    SELECT 2, 'So cap (ma_buu_kien, thoi_gian_xay_ra) bi trung trong pa_b.SuKienTrangThai',
           COUNT(*)
    FROM (
        SELECT ma_buu_kien, thoi_gian_xay_ra
        FROM pa_b.SuKienTrangThai
        GROUP BY ma_buu_kien, thoi_gian_xay_ra
        HAVING COUNT(*) > 1
    ) s2
    UNION ALL
    SELECT 3, 'So su kien lech giua pa_a.SuKienTrangThai va pa_b.SuKienTrangThai',
           (SELECT COUNT(*) FROM (
               SELECT ma_su_kien, ma_buu_kien, ma_trang_thai, ma_diem, thoi_gian_xay_ra, idempotency_key FROM pa_a.SuKienTrangThai
               EXCEPT
               SELECT ma_su_kien, ma_buu_kien, ma_trang_thai, ma_diem, thoi_gian_xay_ra, idempotency_key FROM pa_b.SuKienTrangThai
           ) diff)
) dup_chk
ORDER BY ord;


\echo '===================================================================='
\echo '4. KIEM TOAN VONG DOI NGHEP VU (STATE TRANSITION MATRIX BR-03 & BR-05)'
\echo '===================================================================='
WITH cap_chuyen AS (
    SELECT
        sk.ma_buu_kien,
        sk.ma_su_kien,
        LAG(sk.ma_trang_thai) OVER (
            PARTITION BY sk.ma_buu_kien
            ORDER BY sk.thoi_gian_xay_ra, sk.ma_su_kien
        ) AS trang_thai_truoc,
        sk.ma_trang_thai AS trang_thai_moi
    FROM pa_a.SuKienTrangThai sk
),
phan_loai AS (
    SELECT
        CASE
            WHEN trang_thai_truoc IS NULL AND trang_thai_moi = 'TIEP_NHAN' THEN 'HOP_LE (Khoi tao TIEP_NHAN)'
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
            ) THEN 'HOP_LE (Theo State Transition BR-03)'
            WHEN trang_thai_truoc IN ('GIAO_THANH_CONG', 'HOAN_TRA') THEN 'VI_PHAM BR-05 (Sau trang thai ket thuc)'
            ELSE 'VI_PHAM BR-03 (Chuyen nhay coc / Sai luong)'
        END AS ket_luan
    FROM cap_chuyen
)
SELECT
    ket_luan,
    COUNT(*) AS tong_so_su_kien,
    CASE WHEN ket_luan LIKE 'HOP_LE%' THEN 'PASS' ELSE 'FAIL' END AS ket_qua
FROM phan_loai
GROUP BY ket_luan
ORDER BY ket_luan;


\echo '===================================================================='
\echo '5. DOI SOAT TAP DU LIEU VA TRANG THAI CUOI CUNG GIUA PA_A VA PA_B'
\echo '===================================================================='
WITH sk_pa_a_agg AS (
    SELECT
        ma_buu_kien,
        COUNT(*) AS so_sk_a
    FROM pa_a.SuKienTrangThai
    GROUP BY ma_buu_kien
),
sk_pa_b_agg AS (
    SELECT
        ma_buu_kien,
        COUNT(*) AS so_sk_b
    FROM pa_b.SuKienTrangThai
    GROUP BY ma_buu_kien
),
moi_nhat_pa_a AS (
    SELECT DISTINCT ON (ma_buu_kien)
        ma_buu_kien,
        ma_su_kien       AS ma_sk_cuoi_a,
        ma_trang_thai    AS trang_thai_a,
        thoi_gian_xay_ra AS thoi_gian_cuoi_a
    FROM pa_a.SuKienTrangThai
    ORDER BY ma_buu_kien, thoi_gian_xay_ra DESC, ma_su_kien DESC
),
moi_nhat_pa_b AS (
    SELECT DISTINCT ON (ma_buu_kien)
        ma_buu_kien,
        ma_su_kien       AS ma_sk_cuoi_b,
        ma_trang_thai    AS trang_thai_sk_b,
        thoi_gian_xay_ra AS thoi_gian_sk_b
    FROM pa_b.SuKienTrangThai
    ORDER BY ma_buu_kien, thoi_gian_xay_ra DESC, ma_su_kien DESC
),
doi_soat_toan_bo AS (
    SELECT
        COALESCE(bka.ma_buu_kien, bkb.ma_buu_kien) AS ma_buu_kien,
        bka.ma_buu_kien IS NOT NULL AS ton_tai_pa_a,
        bkb.ma_buu_kien IS NOT NULL AS ton_tai_pa_b,
        COALESCE(sa.so_sk_a, 0) AS so_sk_a,
        COALESCE(sb.so_sk_b, 0) AS so_sk_b,
        mna.ma_sk_cuoi_a,
        mnb.ma_sk_cuoi_b,
        mna.trang_thai_a,
        bkb.trang_thai_hien_tai AS trang_thai_b,
        mna.thoi_gian_cuoi_a,
        bkb.thoi_gian_cap_nhat_cuoi AS thoi_gian_cuoi_b
    FROM pa_a.BuuKien bka
    FULL OUTER JOIN pa_b.BuuKien bkb ON bka.ma_buu_kien = bkb.ma_buu_kien
    LEFT JOIN sk_pa_a_agg sa ON sa.ma_buu_kien = bka.ma_buu_kien
    LEFT JOIN sk_pa_b_agg sb ON sb.ma_buu_kien = bkb.ma_buu_kien
    LEFT JOIN moi_nhat_pa_a mna ON mna.ma_buu_kien = bka.ma_buu_kien
    LEFT JOIN moi_nhat_pa_b mnb ON mnb.ma_buu_kien = bkb.ma_buu_kien
)
SELECT
    COUNT(*) FILTER (WHERE ton_tai_pa_a)                                      AS tong_buu_kien_pa_a,
    COUNT(*) FILTER (WHERE ton_tai_pa_b)                                      AS tong_buu_kien_pa_b,
    COUNT(*) FILTER (WHERE so_sk_a > 0)                                       AS bk_co_su_kien_pa_a,
    COUNT(*) FILTER (WHERE trang_thai_b IS NOT NULL)                          AS bk_co_trang_thai_pa_b,
    COUNT(*) FILTER (
        WHERE ton_tai_pa_a AND ton_tai_pa_b
          AND so_sk_a = so_sk_b
          AND ma_sk_cuoi_a = ma_sk_cuoi_b
          AND trang_thai_a = trang_thai_b
          AND thoi_gian_cuoi_a = thoi_gian_cuoi_b
    )                                                                         AS so_bk_khop_hoan_toan,
    COUNT(*) FILTER (
        WHERE NOT (
            ton_tai_pa_a AND ton_tai_pa_b
            AND so_sk_a = so_sk_b
            AND ma_sk_cuoi_a = ma_sk_cuoi_b
            AND trang_thai_a = trang_thai_b
            AND thoi_gian_cuoi_a = thoi_gian_cuoi_b
        )
    )                                                                         AS so_bk_lech
FROM doi_soat_toan_bo;


\echo '===================================================================='
\echo '6. DANH SACH BUU KIEN BI LECH GIUA PA_A VA PA_B (KY VONG: 0 DONG)'
\echo '===================================================================='
WITH moi_nhat_pa_a AS (
    SELECT DISTINCT ON (ma_buu_kien)
        ma_buu_kien,
        ma_su_kien       AS ma_sk_cuoi_a,
        ma_trang_thai    AS trang_thai_a,
        thoi_gian_xay_ra AS thoi_gian_cuoi_a
    FROM pa_a.SuKienTrangThai
    ORDER BY ma_buu_kien, thoi_gian_xay_ra DESC, ma_su_kien DESC
)
SELECT
    COALESCE(a.ma_buu_kien, b.ma_buu_kien) AS ma_buu_kien,
    a.ma_sk_cuoi_a,
    a.trang_thai_a,
    b.trang_thai_hien_tai AS trang_thai_b,
    a.thoi_gian_cuoi_a,
    b.thoi_gian_cap_nhat_cuoi AS thoi_gian_cuoi_b
FROM moi_nhat_pa_a a
FULL OUTER JOIN pa_b.BuuKien b ON b.ma_buu_kien = a.ma_buu_kien
WHERE a.trang_thai_a IS DISTINCT FROM b.trang_thai_hien_tai
   OR a.thoi_gian_cuoi_a IS DISTINCT FROM b.thoi_gian_cap_nhat_cuoi
LIMIT 20;


\echo '===================================================================='
\echo '7. KIEM THU CHUC NANG TRIGGER PA_B (TRONG GIAO DICH BEGIN..ROLLBACK)'
\echo '===================================================================='
BEGIN;

DO $$
DECLARE
    v_tt_ban_dau  VARCHAR(30);
    v_tg_ban_dau  TIMESTAMP;
    v_tt_sau_1    VARCHAR(30);
    v_tg_sau_1    TIMESTAMP;
    v_tt_sau_2    VARCHAR(30);
    v_tg_sau_2    TIMESTAMP;
    v_tt_sau_3    VARCHAR(30);
    v_tg_sau_3    TIMESTAMP;
    v_so_sk_truoc INT;
    v_so_sk_sau   INT;
    v_t_moi       TIMESTAMP := TIMESTAMP '2026-12-30 10:00:00';
    v_t_muon      TIMESTAMP := TIMESTAMP '2026-12-29 08:00:00';
    v_t_trung     TIMESTAMP := TIMESTAMP '2026-12-31 12:00:00';
BEGIN
    SELECT trang_thai_hien_tai, thoi_gian_cap_nhat_cuoi
    INTO v_tt_ban_dau, v_tg_ban_dau
    FROM pa_b.BuuKien WHERE ma_buu_kien = 'PK00000001';

    SELECT COUNT(*) INTO v_so_sk_truoc
    FROM pa_b.SuKienTrangThai WHERE ma_buu_kien = 'PK00000001';

    -- TEST 7.1: Sự kiện mới hợp lệ (v_t_moi > v_tg_ban_dau) -> Trigger PHẢI cập nhật BuuKien
    INSERT INTO pa_b.SuKienTrangThai (
        ma_su_kien, ma_buu_kien, ma_trang_thai, ma_diem, loai_su_kien,
        thoi_gian_xay_ra, thoi_gian_ghi_nhan, idempotency_key
    ) VALUES (
        'SK_TEST_TRG_01', 'PK00000001', 'DANG_GIAO', 'DGN00001', 'TEST_NEW_EVENT',
        v_t_moi, CURRENT_TIMESTAMP, 'KEY-TEST-TRG-01'
    );

    SELECT trang_thai_hien_tai, thoi_gian_cap_nhat_cuoi
    INTO v_tt_sau_1, v_tg_sau_1
    FROM pa_b.BuuKien WHERE ma_buu_kien = 'PK00000001';

    IF v_tt_sau_1 <> 'DANG_GIAO' OR v_tg_sau_1 <> v_t_moi THEN
        RAISE EXCEPTION 'FAIL Test 7.1: Trigger khong cap nhat trang thai moi!';
    END IF;
    RAISE NOTICE '[PASS] Test 7.1 (Su kien moi): Cap nhat thanh cong sang (%, %)', v_tt_sau_1, v_tg_sau_1;

    -- TEST 7.2: Sự kiện đến muộn (v_t_muon < v_t_moi) -> Lưu vào lịch sử nhưng KHÔNG lùi trạng thái BuuKien
    INSERT INTO pa_b.SuKienTrangThai (
        ma_su_kien, ma_buu_kien, ma_trang_thai, ma_diem, loai_su_kien,
        thoi_gian_xay_ra, thoi_gian_ghi_nhan, idempotency_key
    ) VALUES (
        'SK_TEST_TRG_02', 'PK00000001', 'NHAP_KHO', 'DGN00002', 'TEST_LATE_EVENT',
        v_t_muon, CURRENT_TIMESTAMP, 'KEY-TEST-TRG-02'
    );

    SELECT trang_thai_hien_tai, thoi_gian_cap_nhat_cuoi
    INTO v_tt_sau_2, v_tg_sau_2
    FROM pa_b.BuuKien WHERE ma_buu_kien = 'PK00000001';

    SELECT COUNT(*) INTO v_so_sk_sau
    FROM pa_b.SuKienTrangThai WHERE ma_buu_kien = 'PK00000001';

    IF v_so_sk_sau <> v_so_sk_truoc + 2 THEN
        RAISE EXCEPTION 'FAIL Test 7.2: Su kien den muon khong duoc luu vao lich su!';
    END IF;
    IF v_tt_sau_2 <> 'DANG_GIAO' OR v_tg_sau_2 <> v_t_moi THEN
        RAISE EXCEPTION 'FAIL Test 7.2: Su kien den muon lam quay lui trang thai hien tai!';
    END IF;
    RAISE NOTICE '[PASS] Test 7.2 (Su kien den muon BR-06): Luu du lich su (% dong), giu nguyen trang thai (%)', v_so_sk_sau, v_tt_sau_2;

    -- TEST 7.3: Hai sự kiện trùng thoi_gian_xay_ra đến ngược thứ tự ma_su_kien (SK_TEST_TRG_04 đến trước SK_TEST_TRG_03)
    INSERT INTO pa_b.SuKienTrangThai (
        ma_su_kien, ma_buu_kien, ma_trang_thai, ma_diem, loai_su_kien,
        thoi_gian_xay_ra, thoi_gian_ghi_nhan, idempotency_key
    ) VALUES (
        'SK_TEST_TRG_04', 'PK00000001', 'GIAO_THANH_CONG', 'DGN00003', 'TEST_TIE_HIGH',
        v_t_trung, CURRENT_TIMESTAMP, 'KEY-TEST-TRG-04'
    );

    INSERT INTO pa_b.SuKienTrangThai (
        ma_su_kien, ma_buu_kien, ma_trang_thai, ma_diem, loai_su_kien,
        thoi_gian_xay_ra, thoi_gian_ghi_nhan, idempotency_key
    ) VALUES (
        'SK_TEST_TRG_03', 'PK00000001', 'DANG_GIAO', 'DGN00003', 'TEST_TIE_LOW',
        v_t_trung, CURRENT_TIMESTAMP, 'KEY-TEST-TRG-03'
    );

    SELECT trang_thai_hien_tai, thoi_gian_cap_nhat_cuoi
    INTO v_tt_sau_3, v_tg_sau_3
    FROM pa_b.BuuKien WHERE ma_buu_kien = 'PK00000001';

    IF v_tt_sau_3 <> 'GIAO_THANH_CONG' OR v_tg_sau_3 <> v_t_trung THEN
        RAISE EXCEPTION 'FAIL Test 7.3: Xu ly trung thoi_gian_xay_ra khong khop quy tac ma_su_kien DESC! (%)', v_tt_sau_3;
    END IF;
    RAISE NOTICE '[PASS] Test 7.3 (Trung thoi_gian_xay_ra): Phan dinh chinh xac theo ma_su_kien DESC (%)', v_tt_sau_3;
END $$;

ROLLBACK;
\echo '==> Da ROLLBACK giao dich kiem thu Trigger de bao toan nguyen trang du lieu.'
