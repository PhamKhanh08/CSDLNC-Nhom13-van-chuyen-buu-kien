-- ====================================================================
-- FILE: 02_triggers_functions.sql
-- TRIGGER XỬ LÝ SỰ KIỆN ĐẾN MUỘN VÀ ĐỒNG BỘ TRẠNG THÁI HIỆN TẠI (CHO pa_b)
-- ====================================================================

CREATE OR REPLACE FUNCTION pa_b.fn_cap_nhat_trang_thai_buu_kien()
RETURNS TRIGGER AS $$
DECLARE
    v_thoi_gian_moi_nhat TIMESTAMP;
BEGIN
    -- 1. Tìm mốc thời gian xảy ra sự kiện mới nhất hiện có của bưu kiện
    SELECT thoi_gian_cap_nhat_cuoi INTO v_thoi_gian_moi_nhat
    FROM pa_b.BuuKien
    WHERE ma_buu_kien = NEW.ma_buu_kien;

    -- 2. Xử lý sự kiện đến muộn (Late-arriving Event):
    -- Chỉ cập nhật trạng thái nếu sự kiện mới có thoi_gian_xay_ra >= thoi_gian_cap_nhat_cuoi
    IF v_thoi_gian_moi_nhat IS NULL OR NEW.thoi_gian_xay_ra >= v_thoi_gian_moi_nhat THEN
        UPDATE pa_b.BuuKien
        SET 
            trang_thai_hien_tai = NEW.ma_trang_thai,
            thoi_gian_cap_nhat_cuoi = NEW.thoi_gian_xay_ra
        WHERE ma_buu_kien = NEW.ma_buu_kien;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Gắn Trigger chạy sau mỗi lệnh INSERT trên bảng SuKienTrangThai của pa_b
DROP TRIGGER IF EXISTS trg_cap_nhat_trang_thai ON pa_b.SuKienTrangThai;
CREATE TRIGGER trg_cap_nhat_trang_thai
AFTER INSERT ON pa_b.SuKienTrangThai
FOR EACH ROW
EXECUTE FUNCTION pa_b.fn_cap_nhat_trang_thai_buu_kien();