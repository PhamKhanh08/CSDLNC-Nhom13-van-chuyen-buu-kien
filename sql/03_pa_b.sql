-- =====================================================================
-- 03_pa_b.sql — PHƯƠNG ÁN B: CURRENT STATE
-- Trạng thái hiện tại được LƯU SẴN trên buu_kien (đúng như EER:
-- trang_thai_hien_tai, thoi_gian_cap_nhat_cuoi) và cập nhật mỗi khi có
-- sự kiện. Bảng sự kiện vẫn giữ làm nhật ký/audit (cùng cấu trúc pa_a).
-- =====================================================================

CREATE SCHEMA pa_b;

CREATE TABLE pa_b.buu_kien (
    ma_buu_kien   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ma_khach_gui  BIGINT NOT NULL REFERENCES core.khach_hang (ma_khach_hang),
    ma_khach_nhan BIGINT NOT NULL REFERENCES core.khach_hang (ma_khach_hang),
    trong_luong   NUMERIC(8,2)  NOT NULL CHECK (trong_luong > 0),
    dai           NUMERIC(8,2)  NOT NULL CHECK (dai > 0),
    rong          NUMERIC(8,2)  NOT NULL CHECK (rong > 0),
    cao           NUMERIC(8,2)  NOT NULL CHECK (cao > 0),
    gia_khai      NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (gia_khai >= 0),
    tien_cod      NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (tien_cod >= 0),
    -- Trạng thái lưu sẵn (NULL cho tới khi có sự kiện đầu tiên)
    trang_thai_hien_tai     core.trang_thai_buu_kien,
    thoi_gian_cap_nhat_cuoi TIMESTAMPTZ,   -- = thoi_gian_xay_ra của sự kiện đang áp dụng
    ma_su_kien_cuoi         BIGINT         -- cột THÊM so với EER: làm tie-break khi trùng giờ
) WITH (fillfactor = 80);                -- chừa chỗ cho HOT update (bảng bị UPDATE nhiều)
CREATE INDEX idx_pa_b_bk_gui   ON pa_b.buu_kien (ma_khach_gui);
CREATE INDEX idx_pa_b_bk_nhan  ON pa_b.buu_kien (ma_khach_nhan);
-- Ưu điểm của pa_b: lọc theo trạng thái là truy vấn index đơn giản.
-- Đánh đổi: index này cản HOT update khi đổi trạng thái -> nên đo cả
-- hai trường hợp có/không có index này trong benchmark.
CREATE INDEX idx_pa_b_bk_trang_thai ON pa_b.buu_kien (trang_thai_hien_tai);

CREATE TABLE pa_b.buu_kien_chuyen (
    ma_buu_kien BIGINT NOT NULL REFERENCES pa_b.buu_kien (ma_buu_kien),
    ma_chuyen   BIGINT NOT NULL REFERENCES core.chuyen_van_chuyen (ma_chuyen),
    PRIMARY KEY (ma_buu_kien, ma_chuyen)
);
CREATE INDEX idx_pa_b_bkc_chuyen ON pa_b.buu_kien_chuyen (ma_chuyen);

CREATE TABLE pa_b.lan_ban_giao (
    ma_ban_giao       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ma_buu_kien       BIGINT NOT NULL REFERENCES pa_b.buu_kien (ma_buu_kien),
    ma_nhan_vien      BIGINT NOT NULL REFERENCES core.nhan_vien (ma_nhan_vien),
    thoi_gian_ban_giao TIMESTAMPTZ NOT NULL,
    tinh_trang        VARCHAR(50) NOT NULL,
    ghi_chu           TEXT
);
CREATE INDEX idx_pa_b_bg_bk ON pa_b.lan_ban_giao (ma_buu_kien, thoi_gian_ban_giao);

CREATE TABLE pa_b.su_kien_trang_thai (
    ma_su_kien         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ma_buu_kien        BIGINT NOT NULL REFERENCES pa_b.buu_kien (ma_buu_kien),
    loai_su_kien       core.trang_thai_buu_kien NOT NULL,
    thoi_gian_xay_ra   TIMESTAMPTZ NOT NULL,
    thoi_gian_ghi_nhan TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    idempotency_key    TEXT NOT NULL UNIQUE
);
-- Giữ cùng index với pa_a cho công bằng (nhật ký vẫn có thể truy vấn lịch sử)
CREATE INDEX idx_pa_b_sk_moi_nhat
    ON pa_b.su_kien_trang_thai (ma_buu_kien, thoi_gian_xay_ra DESC, ma_su_kien DESC)
    INCLUDE (loai_su_kien);

-- View cùng danh sách cột với pa_a.v_buu_kien_hien_tai -> cùng câu truy vấn chạy được trên cả hai
CREATE VIEW pa_b.v_buu_kien_hien_tai AS
SELECT ma_buu_kien, ma_khach_gui, ma_khach_nhan,
        trong_luong, dai, rong, cao, gia_khai, tien_cod,
        trang_thai_hien_tai, thoi_gian_cap_nhat_cuoi
FROM pa_b.buu_kien;

-- Hàm ghi sự kiện: cùng chữ ký với pa_a.ghi_su_kien
-- 1) INSERT nhật ký, bỏ qua nếu trùng idempotency_key (-> trả NULL, KHÔNG đụng trạng thái)
-- 2) UPDATE trạng thái CHỈ KHI sự kiện này "mới hơn" sự kiện đang áp dụng
--    (so sánh theo cặp (thoi_gian_xay_ra, ma_su_kien), giống thứ tự của pa_a)
--    => sự kiện đến muộn vẫn được ghi vào lịch sử nhưng không làm lùi trạng thái.
-- Đồng thời: UPDATE khóa dòng bưu kiện; giao dịch thứ hai chờ rồi đánh giá lại
-- điều kiện WHERE trên bản ghi mới (READ COMMITTED) nên kết quả không phụ thuộc
-- thứ tự commit.
CREATE FUNCTION pa_b.ghi_su_kien(
    p_ma_buu_kien      BIGINT,
    p_loai_su_kien     core.trang_thai_buu_kien,
    p_thoi_gian_xay_ra TIMESTAMPTZ,
    p_idempotency_key  TEXT
) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    v_ma_su_kien BIGINT;
BEGIN
    INSERT INTO pa_b.su_kien_trang_thai (ma_buu_kien, loai_su_kien, thoi_gian_xay_ra, idempotency_key)
    VALUES (p_ma_buu_kien, p_loai_su_kien, p_thoi_gian_xay_ra, p_idempotency_key)
    ON CONFLICT (idempotency_key) DO NOTHING
    RETURNING ma_su_kien INTO v_ma_su_kien;

    IF v_ma_su_kien IS NULL THEN
        RETURN NULL;  -- sự kiện trùng
    END IF;

    UPDATE pa_b.buu_kien
        SET trang_thai_hien_tai     = p_loai_su_kien,
            thoi_gian_cap_nhat_cuoi = p_thoi_gian_xay_ra,
            ma_su_kien_cuoi         = v_ma_su_kien
    WHERE ma_buu_kien = p_ma_buu_kien
        AND (thoi_gian_cap_nhat_cuoi IS NULL
            OR (thoi_gian_cap_nhat_cuoi, ma_su_kien_cuoi) < (p_thoi_gian_xay_ra, v_ma_su_kien));

    RETURN v_ma_su_kien;
END;
$$;

-- Kiểm tra nhất quán: trạng thái lưu sẵn có khớp trạng thái tính từ lịch sử không?
-- Kỳ vọng: view này luôn RỖNG.
CREATE VIEW pa_b.v_lech_trang_thai AS
SELECT b.ma_buu_kien,
        b.trang_thai_hien_tai AS luu_san,
        s.loai_su_kien        AS tinh_tu_lich_su
FROM pa_b.buu_kien b
LEFT JOIN LATERAL (
    SELECT e.loai_su_kien
    FROM pa_b.su_kien_trang_thai e
    WHERE e.ma_buu_kien = b.ma_buu_kien
    ORDER BY e.thoi_gian_xay_ra DESC, e.ma_su_kien DESC
    LIMIT 1
) s ON true
WHERE b.trang_thai_hien_tai IS DISTINCT FROM s.loai_su_kien;