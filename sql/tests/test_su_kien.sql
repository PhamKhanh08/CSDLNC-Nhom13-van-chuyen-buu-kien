-- Kịch bản kiểm thử: bình thường / trùng / đến muộn — chạy trên cả pa_a và pa_b.
-- Chạy: psql -d <db> -v ON_ERROR_STOP=1 -f sql/tests/test_su_kien.sql
-- Mọi thay đổi bị ROLLBACK ở cuối tránh làm bẩn dữ liệu.
BEGIN;

DO $$
DECLARE
    kg BIGINT; kn BIGINT; a BIGINT; b BIGINT; r BIGINT;
    t0 CONSTANT TIMESTAMPTZ := TIMESTAMPTZ '2026-01-01 08:00:00+07';
BEGIN
    INSERT INTO core.khach_hang (ho_ten, so_dien_thoai, dia_chi)
        VALUES ('Test gui', '0900000001', 'HCM') RETURNING ma_khach_hang INTO kg;
    INSERT INTO core.khach_hang (ho_ten, so_dien_thoai, dia_chi)
        VALUES ('Test nhan', '0900000002', 'HN') RETURNING ma_khach_hang INTO kn;
    INSERT INTO pa_a.buu_kien (ma_khach_gui, ma_khach_nhan, trong_luong, dai, rong, cao)
        VALUES (kg, kn, 1, 10, 10, 10) RETURNING ma_buu_kien INTO a;
    INSERT INTO pa_b.buu_kien (ma_khach_gui, ma_khach_nhan, trong_luong, dai, rong, cao)
        VALUES (kg, kn, 1, 10, 10, 10) RETURNING ma_buu_kien INTO b;

    -- 1) Sự kiện đến đúng thứ tự
    PERFORM pa_a.ghi_su_kien(a, 'TIEP_NHAN',       t0,                      'k1');
    PERFORM pa_b.ghi_su_kien(b, 'TIEP_NHAN',       t0,                      'k1');
    PERFORM pa_a.ghi_su_kien(a, 'DANG_VAN_CHUYEN', t0 + interval '1 hour',  'k2');
    PERFORM pa_b.ghi_su_kien(b, 'DANG_VAN_CHUYEN', t0 + interval '1 hour',  'k2');

    -- 2) Gửi trùng (cùng idempotency_key) -> trả NULL, không thêm dòng
    r := pa_a.ghi_su_kien(a, 'DANG_VAN_CHUYEN', t0 + interval '1 hour', 'k2');
    ASSERT r IS NULL, 'pa_a: su kien trung phai tra NULL';
    r := pa_b.ghi_su_kien(b, 'DANG_VAN_CHUYEN', t0 + interval '1 hour', 'k2');
    ASSERT r IS NULL, 'pa_b: su kien trung phai tra NULL';

    -- 3) Đến muộn: DEN_KHO xảy ra lúc t0+30p nhưng được ghi nhận sau DANG_VAN_CHUYEN
    PERFORM pa_a.ghi_su_kien(a, 'DEN_KHO', t0 + interval '30 minutes', 'k3');
    PERFORM pa_b.ghi_su_kien(b, 'DEN_KHO', t0 + interval '30 minutes', 'k3');

    ASSERT (SELECT count(*) FROM pa_a.su_kien_trang_thai WHERE ma_buu_kien = a) = 3,
        'pa_a: lich su phai co 3 su kien (khong tinh trung)';
    ASSERT (SELECT count(*) FROM pa_b.su_kien_trang_thai WHERE ma_buu_kien = b) = 3,
        'pa_b: lich su phai co 3 su kien (khong tinh trung)';
    ASSERT (SELECT trang_thai_hien_tai FROM pa_a.v_buu_kien_hien_tai WHERE ma_buu_kien = a)
        = 'DANG_VAN_CHUYEN', 'pa_a: su kien den muon khong duoc lam lui trang thai';
    ASSERT (SELECT trang_thai_hien_tai FROM pa_b.v_buu_kien_hien_tai WHERE ma_buu_kien = b)
        = 'DANG_VAN_CHUYEN', 'pa_b: su kien den muon khong duoc lam lui trang thai';

    -- 4) pa_b: trạng thái lưu sẵn phải khớp trạng thái tính từ lịch sử
    ASSERT NOT EXISTS (SELECT 1 FROM pa_b.v_lech_trang_thai WHERE ma_buu_kien = b),
        'pa_b: trang thai luu san lech voi lich su';

    RAISE NOTICE 'TAT CA KIEM THU DAT';
END;
$$;

ROLLBACK;