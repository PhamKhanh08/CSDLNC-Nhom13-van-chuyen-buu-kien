-- =====================================================================
-- 04_seed.sql — Sinh dữ liệu thử nghiệm (thuần SQL, không cần Python)
-- Mặc định: 10.000 bưu kiện + 100.000 sự kiện lịch sử, nạp GIỐNG HỆT vào
-- cả pa_a và pa_b (cùng id, cùng thứ tự đến) để so sánh công bằng.
--
-- Đổi quy mô bằng biến psql, ví dụ:
--   psql -d parcel_tracking -v n_buu_kien=50000 -v n_su_kien=500000 -f sql/04_seed.sql
-- Biến (có mặc định): n_buu_kien, n_su_kien, n_khach_hang, ty_le_den_muon
--
-- Chạy lại được nhiều lần: script TRUNCATE toàn bộ dữ liệu trước khi nạp.
-- Dữ liệu tái lập được (setseed) khi dùng cùng phiên bản PostgreSQL.
-- =====================================================================

\if :{?n_buu_kien}
\else
    \set n_buu_kien 10000
\endif
\if :{?n_su_kien}
\else
    \set n_su_kien 100000
\endif
\if :{?n_khach_hang}
\else
    \set n_khach_hang 2000
\endif
\if :{?ty_le_den_muon}
\else
    \set ty_le_den_muon 0.05
\endif

-- Kiểm tra tham số: trung bình 6–20 sự kiện/bưu kiện
SELECT set_config('seed.n_buu_kien', :'n_buu_kien', false) AS a,
    set_config('seed.n_su_kien',  :'n_su_kien',  false) AS b \gset _tmp_
DO $$
DECLARE m NUMERIC := current_setting('seed.n_su_kien')::numeric / current_setting('seed.n_buu_kien')::numeric;
BEGIN
    IF m < 6 OR m > 20 THEN
        RAISE EXCEPTION 'n_su_kien / n_buu_kien phai nam trong [6, 20], hien tai = %', round(m, 2);
    END IF;
END $$;

SELECT setseed(0.2026);

BEGIN;

TRUNCATE core.khach_hang, core.diem_giao_nhan, core.kho_trung_chuyen, core.buu_cuc,
        core.nhan_vien, core.shipper, core.nhan_vien_kho,
        core.tuyen_van_chuyen, core.chuyen_van_chuyen,
        pa_a.buu_kien, pa_a.buu_kien_chuyen, pa_a.lan_ban_giao, pa_a.su_kien_trang_thai,
        pa_b.buu_kien, pa_b.buu_kien_chuyen, pa_b.lan_ban_giao, pa_b.su_kien_trang_thai
    RESTART IDENTITY;

-- ---------------------------------------------------------------------
-- 1) Dữ liệu nền (core)
-- ---------------------------------------------------------------------
INSERT INTO core.khach_hang (ho_ten, so_dien_thoai, dia_chi)
SELECT 'Khach hang ' || g,
        '09' || lpad(g::text, 8, '0'),
        'So ' || (1 + floor(random() * 300))::int || ' duong ' || (1 + floor(random() * 60))::int
         || ', Quan ' || (1 + floor(random() * 12))::int
FROM generate_series(1, :n_khach_hang) g;

-- 40 điểm: 10 kho trung chuyển (id 1–10) + 30 bưu cục (id 11–40)
INSERT INTO core.diem_giao_nhan (ten_diem, dia_chi, loai_diem)
SELECT CASE WHEN g <= 10 THEN 'Kho trung chuyen ' || g ELSE 'Buu cuc ' || (g - 10) END,
       'So ' || (1 + floor(random() * 300))::int || ' duong ' || g
         || ', Quan ' || (1 + floor(random() * 12))::int,
        CASE WHEN g <= 10 THEN 'KHO' ELSE 'BUU_CUC' END
FROM generate_series(1, 40) g;

INSERT INTO core.kho_trung_chuyen (ma_diem, suc_chua)
SELECT ma_diem, 5000 + 1000 * (ma_diem % 6)
FROM core.diem_giao_nhan WHERE loai_diem = 'KHO';

INSERT INTO core.buu_cuc (ma_diem, sdt)
SELECT ma_diem, '028' || lpad(ma_diem::text, 7, '0')
FROM core.diem_giao_nhan WHERE loai_diem = 'BUU_CUC';

-- 100 nhân viên: 60 shipper, 25 nhân viên kho, 10 quản lý, 5 khác
INSERT INTO core.nhan_vien (ho_ten, so_dien_thoai, vai_tro)
SELECT 'Nhan vien ' || g,
       '08' || lpad(g::text, 8, '0'),
       CASE WHEN g <= 60 THEN 'SHIPPER'
            WHEN g <= 85 THEN 'NHAN_VIEN_KHO'
            WHEN g <= 95 THEN 'QUAN_LY'
            ELSE 'KHAC' END
FROM generate_series(1, 100) g;

INSERT INTO core.shipper (ma_nhan_vien, khu_vuc_phu_trach)
SELECT ma_nhan_vien, 'Quan ' || (1 + ma_nhan_vien % 12)
FROM core.nhan_vien WHERE vai_tro = 'SHIPPER';

INSERT INTO core.nhan_vien_kho (ma_nhan_vien, vi_tri_cong_viec)
SELECT ma_nhan_vien, (ARRAY['Nhan hang', 'Phan loai', 'Xuat kho'])[1 + ma_nhan_vien % 3]
FROM core.nhan_vien WHERE vai_tro = 'NHAN_VIEN_KHO';

-- 40 tuyến (đầu tuyến ≠ cuối tuyến)
INSERT INTO core.tuyen_van_chuyen (ten_tuyen, ma_diem_dau, ma_diem_cuoi)
SELECT 'Tuyen ' || g, d, ((d - 1 + 1 + floor(random() * 39)::int) % 40) + 1
FROM (SELECT g, 1 + floor(random() * 40)::int AS d FROM generate_series(1, 40) g) t;

-- 400 chuyến
INSERT INTO core.chuyen_van_chuyen
    (ma_tuyen, ma_nhan_vien_phu_trach, thoi_gian_xuat_phat, thoi_gian_den_du_kien, trang_thai_chuyen)
SELECT 1 + (g - 1) % 40,
       1 + floor(random() * 85)::int,
        t0,
        t0 + (4 + random() * 44) * interval '1 hour',
        CASE WHEN random() < 0.8 THEN 'HOAN_THANH' WHEN random() < 0.5 THEN 'DANG_CHAY' ELSE 'LEN_KE_HOACH' END
FROM (SELECT g, TIMESTAMPTZ '2026-07-01 00:00:00+07' + random() * interval '90 days' AS t0
        FROM generate_series(1, 400) g) t;

-- ---------------------------------------------------------------------
-- 2) Bưu kiện (staging -> nạp giống hệt vào pa_a và pa_b)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE stg_bk0 AS
SELECT g AS ma_buu_kien,
        gui,
        ((gui - 1 + 1 + floor(random() * (:n_khach_hang - 1))::int) % :n_khach_hang) + 1 AS nhan,
        round((0.1 + 30 * power(random(), 2))::numeric, 2) AS trong_luong,
        round((10 + random() * 60)::numeric, 2) AS dai,
        round((10 + random() * 40)::numeric, 2) AS rong,
        round((5 + random() * 30)::numeric, 2)  AS cao,
        (floor(random() * 5000) * 1000)::numeric(14,2) AS gia_khai,
        CASE WHEN random() < 0.5 THEN 0 ELSE (floor(random() * 3000) * 1000)::numeric(14,2) END AS tien_cod,
        -- kết cục: 15% còn đang xử lý, 68% giao được, 8% giao thất bại, 9% hoàn trả
        (SELECT CASE WHEN u < 0.15 THEN 'DANG_XU_LY'
                    WHEN u < 0.83 THEN 'DA_GIAO'
                    WHEN u < 0.91 THEN 'GIAO_THAT_BAI'
                    ELSE 'HOAN_TRA' END) AS ket_qua,
        -- số sự kiện của bưu kiện này (sẽ chỉnh lại để tổng đúng n_su_kien)
       GREATEST(3, round((:n_su_kien::numeric / :n_buu_kien) * (0.6 + 0.8 * random())))::int AS l0,
       TIMESTAMPTZ '2026-07-01 00:00:00+07' + random() * interval '90 days' AS t0
FROM (SELECT g, 1 + floor(random() * :n_khach_hang)::int AS gui, random() AS u
        FROM generate_series(1, :n_buu_kien) g) b;

CREATE TEMP TABLE stg_bk AS
SELECT s.*, s.l0 + CASE WHEN s.rn <= abs(d.diff) THEN sign(d.diff)::int ELSE 0 END AS so_su_kien
FROM (SELECT *, row_number() OVER (ORDER BY ma_buu_kien) AS rn FROM stg_bk0) s
CROSS JOIN (SELECT (:n_su_kien - sum(l0))::int AS diff FROM stg_bk0) d;

INSERT INTO pa_a.buu_kien (ma_khach_gui, ma_khach_nhan, trong_luong, dai, rong, cao, gia_khai, tien_cod)
SELECT gui, nhan, trong_luong, dai, rong, cao, gia_khai, tien_cod FROM stg_bk ORDER BY ma_buu_kien;

INSERT INTO pa_b.buu_kien (ma_khach_gui, ma_khach_nhan, trong_luong, dai, rong, cao, gia_khai, tien_cod)
SELECT gui, nhan, trong_luong, dai, rong, cao, gia_khai, tien_cod FROM stg_bk ORDER BY ma_buu_kien;

-- ---------------------------------------------------------------------
-- 3) Lịch sử sự kiện
-- Vòng đời: TIEP_NHAN -> (DEN_KHO <-> DANG_VAN_CHUYEN)* -> DANG_GIAO -> kết cục.
-- Bưu kiện "đang xử lý" dừng ở giữa hành trình. Khoảng cách giữa 2 sự kiện: 1–12 giờ.
-- ĐẾN MUỘN: ty_le_den_muon sự kiện được ghi nhận trễ 2–48 giờ so với lúc xảy ra,
-- nên nhiều sự kiện đến SAU các sự kiện mới hơn của cùng bưu kiện.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE stg_sk AS
WITH e AS (
    SELECT b.ma_buu_kien, k, b.so_su_kien AS l, b.ket_qua, b.t0,
            CASE WHEN k = 1 THEN interval '0'
                ELSE (1 + random() * 11) * interval '1 hour' END AS gap
    FROM stg_bk b
    CROSS JOIN LATERAL generate_series(1, b.so_su_kien) AS k
), t AS (
    SELECT e.*, e.t0 + sum(gap) OVER (PARTITION BY ma_buu_kien ORDER BY k) AS thoi_gian_xay_ra
    FROM e
)
SELECT ma_buu_kien, k,
        (CASE WHEN k = 1 THEN 'TIEP_NHAN'
            WHEN ket_qua <> 'DANG_XU_LY' AND k = l     THEN ket_qua
            WHEN ket_qua <> 'DANG_XU_LY' AND k = l - 1 THEN 'DANG_GIAO'
            WHEN k % 2 = 0 THEN 'DEN_KHO'
            ELSE 'DANG_VAN_CHUYEN' END)::core.trang_thai_buu_kien AS loai_su_kien,
        thoi_gian_xay_ra,
        thoi_gian_xay_ra + CASE WHEN random() < :ty_le_den_muon THEN (2 + random() * 46) * interval '1 hour'
            ELSE random() * interval '5 seconds' END AS thoi_gian_ghi_nhan,
        'seed-' || ma_buu_kien || '-' || k AS idempotency_key
FROM t;

-- Chèn theo THỨ TỰ ĐẾN (thoi_gian_ghi_nhan) -> ma_su_kien phản ánh thứ tự đến,
-- không phải thứ tự xảy ra. Cả hai schema chèn cùng thứ tự => cùng ma_su_kien.
INSERT INTO pa_a.su_kien_trang_thai
    (ma_buu_kien, loai_su_kien, thoi_gian_xay_ra, thoi_gian_ghi_nhan, idempotency_key)
SELECT ma_buu_kien, loai_su_kien, thoi_gian_xay_ra, thoi_gian_ghi_nhan, idempotency_key
FROM stg_sk ORDER BY thoi_gian_ghi_nhan, ma_buu_kien, k;

INSERT INTO pa_b.su_kien_trang_thai
    (ma_buu_kien, loai_su_kien, thoi_gian_xay_ra, thoi_gian_ghi_nhan, idempotency_key)
SELECT ma_buu_kien, loai_su_kien, thoi_gian_xay_ra, thoi_gian_ghi_nhan, idempotency_key
FROM stg_sk ORDER BY thoi_gian_ghi_nhan, ma_buu_kien, k;

-- pa_b: điền trạng thái lưu sẵn theo ĐÚNG quy tắc của ghi_su_kien()
UPDATE pa_b.buu_kien b
SET trang_thai_hien_tai     = l.loai_su_kien,
    thoi_gian_cap_nhat_cuoi = l.thoi_gian_xay_ra,
    ma_su_kien_cuoi         = l.ma_su_kien
FROM (SELECT DISTINCT ON (ma_buu_kien) ma_buu_kien, ma_su_kien, loai_su_kien, thoi_gian_xay_ra
    FROM pa_b.su_kien_trang_thai
    ORDER BY ma_buu_kien, thoi_gian_xay_ra DESC, ma_su_kien DESC) l
WHERE b.ma_buu_kien = l.ma_buu_kien;

COMMIT;

-- ---------------------------------------------------------------------
-- 4) Kiểm tra: số lượng đúng, pa_b nhất quán, hai phương án cho cùng kết quả
-- ---------------------------------------------------------------------
DO $$
BEGIN
    ASSERT (SELECT count(*) FROM pa_a.buu_kien) = current_setting('seed.n_buu_kien')::int, 'pa_a: sai so buu kien';
    ASSERT (SELECT count(*) FROM pa_b.buu_kien) = current_setting('seed.n_buu_kien')::int, 'pa_b: sai so buu kien';
    ASSERT (SELECT count(*) FROM pa_a.su_kien_trang_thai) = current_setting('seed.n_su_kien')::int, 'pa_a: sai so su kien';
    ASSERT (SELECT count(*) FROM pa_b.su_kien_trang_thai) = current_setting('seed.n_su_kien')::int, 'pa_b: sai so su kien';
    ASSERT NOT EXISTS (SELECT 1 FROM pa_b.v_lech_trang_thai), 'pa_b: trang thai luu san lech voi lich su';
    ASSERT NOT EXISTS (
        SELECT 1 FROM pa_a.v_buu_kien_hien_tai a JOIN pa_b.v_buu_kien_hien_tai b USING (ma_buu_kien)
        WHERE a.trang_thai_hien_tai IS DISTINCT FROM b.trang_thai_hien_tai
            OR a.thoi_gian_cap_nhat_cuoi IS DISTINCT FROM b.thoi_gian_cap_nhat_cuoi
    ), 'pa_a va pa_b cho trang thai hien tai khac nhau';
    RAISE NOTICE 'Seed OK: pa_a va pa_b khop nhau.';
END $$;

VACUUM (ANALYZE);

-- Thống kê nhanh
SELECT trang_thai_hien_tai, count(*) AS so_buu_kien
FROM pa_b.buu_kien GROUP BY 1 ORDER BY 2 DESC;

SELECT count(*)                                                               AS tong_su_kien,
        count(*) FILTER (WHERE thoi_gian_ghi_nhan - thoi_gian_xay_ra > interval '1 hour') AS den_muon,
        (SELECT count(*) FROM pa_a.su_kien_trang_thai e
            WHERE EXISTS (SELECT 1 FROM pa_a.su_kien_trang_thai p
                            WHERE p.ma_buu_kien = e.ma_buu_kien
                                AND p.ma_su_kien < e.ma_su_kien
                                AND p.thoi_gian_xay_ra > e.thoi_gian_xay_ra))        AS den_sai_thu_tu
FROM pa_a.su_kien_trang_thai;