-- =====================================================================
-- 02_pa_a.sql — PHƯƠNG ÁN A: HISTORY-BASED
-- Nguồn sự thật duy nhất = bảng sự kiện append-only (su_kien_trang_thai).
-- Trạng thái hiện tại KHÔNG được lưu: luôn tính từ lịch sử (view bên dưới).
-- => Bảng buu_kien KHÔNG có trang_thai_hien_tai / thoi_gian_cap_nhat_cuoi.
-- =====================================================================

CREATE SCHEMA pa_a;

CREATE TABLE pa_a.buu_kien (
    ma_buu_kien   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ma_khach_gui  BIGINT NOT NULL REFERENCES core.khach_hang (ma_khach_hang),  -- GUI
    ma_khach_nhan BIGINT NOT NULL REFERENCES core.khach_hang (ma_khach_hang),  -- NHAN
    trong_luong   NUMERIC(8,2)  NOT NULL CHECK (trong_luong > 0),
    dai           NUMERIC(8,2)  NOT NULL CHECK (dai > 0),
    rong          NUMERIC(8,2)  NOT NULL CHECK (rong > 0),
    cao           NUMERIC(8,2)  NOT NULL CHECK (cao > 0),
    gia_khai      NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (gia_khai >= 0),
    tien_cod      NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (tien_cod >= 0)
);
CREATE INDEX idx_pa_a_bk_gui  ON pa_a.buu_kien (ma_khach_gui);
CREATE INDEX idx_pa_a_bk_nhan ON pa_a.buu_kien (ma_khach_nhan);

-- THAM_GIA (M:N): bưu kiện đi trên những chuyến nào
CREATE TABLE pa_a.buu_kien_chuyen (
    ma_buu_kien BIGINT NOT NULL REFERENCES pa_a.buu_kien (ma_buu_kien),
    ma_chuyen   BIGINT NOT NULL REFERENCES core.chuyen_van_chuyen (ma_chuyen),
    PRIMARY KEY (ma_buu_kien, ma_chuyen)
);
CREATE INDEX idx_pa_a_bkc_chuyen ON pa_a.buu_kien_chuyen (ma_chuyen);

-- CO_BAN_GIAO (1:N) + THUC_HIEN (nhân viên thực hiện; giả định N:1)
CREATE TABLE pa_a.lan_ban_giao (
    ma_ban_giao       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ma_buu_kien       BIGINT NOT NULL REFERENCES pa_a.buu_kien (ma_buu_kien),
    ma_nhan_vien      BIGINT NOT NULL REFERENCES core.nhan_vien (ma_nhan_vien),
    thoi_gian_ban_giao TIMESTAMPTZ NOT NULL,
    tinh_trang        VARCHAR(50) NOT NULL,
    ghi_chu           TEXT
);
CREATE INDEX idx_pa_a_bg_bk ON pa_a.lan_ban_giao (ma_buu_kien, thoi_gian_ban_giao);

-- CO_SU_KIEN (1:N): LỊCH SỬ — chỉ INSERT, không UPDATE/DELETE
CREATE TABLE pa_a.su_kien_trang_thai (
    ma_su_kien         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ma_buu_kien        BIGINT NOT NULL REFERENCES pa_a.buu_kien (ma_buu_kien),
    loai_su_kien       core.trang_thai_buu_kien NOT NULL,
    thoi_gian_xay_ra   TIMESTAMPTZ NOT NULL,                          -- giờ sự kiện thật sự xảy ra
    thoi_gian_ghi_nhan TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(), -- giờ hệ thống nhận được
    idempotency_key    TEXT NOT NULL UNIQUE                            -- chống gửi trùng
);
-- Index phục vụ "sự kiện mới nhất của 1 bưu kiện" (index-only scan nhờ INCLUDE)
CREATE INDEX idx_pa_a_sk_moi_nhat
    ON pa_a.su_kien_trang_thai (ma_buu_kien, thoi_gian_xay_ra DESC, ma_su_kien DESC)
    INCLUDE (loai_su_kien);

-- Trạng thái hiện tại = sự kiện có (thoi_gian_xay_ra, ma_su_kien) lớn nhất
CREATE VIEW pa_a.v_buu_kien_hien_tai AS
SELECT b.ma_buu_kien, b.ma_khach_gui, b.ma_khach_nhan,
        b.trong_luong, b.dai, b.rong, b.cao, b.gia_khai, b.tien_cod,
        s.loai_su_kien     AS trang_thai_hien_tai,
        s.thoi_gian_xay_ra AS thoi_gian_cap_nhat_cuoi
FROM pa_a.buu_kien b
LEFT JOIN LATERAL (
    SELECT e.loai_su_kien, e.thoi_gian_xay_ra
    FROM pa_a.su_kien_trang_thai e
    WHERE e.ma_buu_kien = b.ma_buu_kien
    ORDER BY e.thoi_gian_xay_ra DESC, e.ma_su_kien DESC
    LIMIT 1
) s ON true;

-- Hàm ghi sự kiện (CÙNG chữ ký với pa_b.ghi_su_kien để benchmark gọi như nhau)
-- Trả về ma_su_kien; trả NULL nếu idempotency_key đã tồn tại (sự kiện trùng).
CREATE FUNCTION pa_a.ghi_su_kien(
    p_ma_buu_kien      BIGINT,
    p_loai_su_kien     core.trang_thai_buu_kien,
    p_thoi_gian_xay_ra TIMESTAMPTZ,
    p_idempotency_key  TEXT
) RETURNS BIGINT
LANGUAGE sql AS $$
    INSERT INTO pa_a.su_kien_trang_thai (ma_buu_kien, loai_su_kien, thoi_gian_xay_ra, idempotency_key)
    VALUES (p_ma_buu_kien, p_loai_su_kien, p_thoi_gian_xay_ra, p_idempotency_key)
    ON CONFLICT (idempotency_key) DO NOTHING
    RETURNING ma_su_kien;
$$;