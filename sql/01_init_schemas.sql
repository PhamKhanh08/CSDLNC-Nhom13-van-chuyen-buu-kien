-- ====================================================================
-- FILE: 01_init_schemas.sql - KHỞI TẠO ĐẦY ĐỦ 2 SCHEMA
-- ====================================================================
-- Khởi tạo 2 SCHEMA cho 2 phương án A và B 
-- PA_A :(History Based) Đạt dạng chuẩn BCNF tuyệt đối. Bảng `BuuKien` không lưu trữ trạng thái hiện tại. Trạng thái bưu kiện được suy diễn hoàn toàn từ lịch sử các dòng sự kiện trong `SuKienTrangThai`.
-- PA_B :( Current State ) Phi chuẩn hóa có kiểm soát. Bảng `BuuKien` được bổ sung 2 cột `trang_thai_hien_tai` và `thoi_gian_cap_nhat_cuoi`, đồng thời gắn Trigger PL/pgSQL để tự động đồng bộ khi chèn sự kiện mới.
CREATE SCHEMA IF NOT EXISTS pa_a;
CREATE SCHEMA IF NOT EXISTS pa_b;

-- ====================================================================
-- PHẦN I: SCHEMA pa_a (PHƯƠNG ÁN A - HISTORY-BASED / THUẦN BCNF)
-- ====================================================================

CREATE TABLE pa_a.DiemGiaoNhan (
    ma_diem_giao_nhan VARCHAR(20) PRIMARY KEY,
    ten_diem VARCHAR(100) NOT NULL,
    dia_chi TEXT NOT NULL
);

CREATE TABLE pa_a.BuuCuc (
    ma_diem_giao_nhan VARCHAR(20) PRIMARY KEY REFERENCES pa_a.DiemGiaoNhan(ma_diem_giao_nhan) ON DELETE CASCADE,
    ma_buu_cuc VARCHAR(20) UNIQUE NOT NULL,
    sdt VARCHAR(15)
);

CREATE TABLE pa_a.KhoTrungChuyen (
    ma_diem_giao_nhan VARCHAR(20) PRIMARY KEY REFERENCES pa_a.DiemGiaoNhan(ma_diem_giao_nhan) ON DELETE CASCADE,
    ma_kho VARCHAR(20) UNIQUE NOT NULL,
    suc_chua NUMERIC(10, 2)
);

CREATE TABLE pa_a.TuyenVanChuyen (
    ma_tuyen VARCHAR(20) PRIMARY KEY,
    ten_tuyen VARCHAR(100) NOT NULL,
    dau_tuyen VARCHAR(20) REFERENCES pa_a.DiemGiaoNhan(ma_diem_giao_nhan),
    cuoi_tuyen VARCHAR(20) REFERENCES pa_a.DiemGiaoNhan(ma_diem_giao_nhan)
);

CREATE TABLE pa_a.ChuyenVanChuyen (
    ma_chuyen VARCHAR(20) PRIMARY KEY,
    ma_tuyen VARCHAR(20) REFERENCES pa_a.TuyenVanChuyen(ma_tuyen),
    thoi_gian_xuat_phat TIMESTAMP,
    thoi_gian_den_du_kien TIMESTAMP,
    trang_thai_chuyen VARCHAR(30) DEFAULT 'LEN_KE_HOACH'
);

CREATE TABLE pa_a.KhachHang (
    ma_khach_hang VARCHAR(20) PRIMARY KEY,
    ho_ten VARCHAR(100) NOT NULL,
    sdt VARCHAR(15) NOT NULL,
    dia_chi TEXT
);

CREATE TABLE pa_a.BuuKien (
    ma_buu_kien VARCHAR(20) PRIMARY KEY,
    ma_khach_hang_gui VARCHAR(20) REFERENCES pa_a.KhachHang(ma_khach_hang),
    ma_khach_hang_nhan VARCHAR(20) REFERENCES pa_a.KhachHang(ma_khach_hang),
    trong_luong NUMERIC(8, 2) NOT NULL,
    dai NUMERIC(6, 1),
    rong NUMERIC(6, 1),
    cao NUMERIC(6, 1),
    gia_khai NUMERIC(12, 2) DEFAULT 0,
    tien_COD NUMERIC(12, 2) DEFAULT 0
);

CREATE TABLE pa_a.NhanVien (
    ma_nhan_vien VARCHAR(20) PRIMARY KEY,
    ho_ten VARCHAR(100) NOT NULL,
    so_dien_thoai VARCHAR(15) NOT NULL,
    vai_tro VARCHAR(30)
);

CREATE TABLE pa_a.Shipper (
    ma_nhan_vien VARCHAR(20) PRIMARY KEY REFERENCES pa_a.NhanVien(ma_nhan_vien) ON DELETE CASCADE,
    khu_vuc_phu_trach VARCHAR(100)
);

CREATE TABLE pa_a.NhanVienKho (
    ma_nhan_vien VARCHAR(20) PRIMARY KEY REFERENCES pa_a.NhanVien(ma_nhan_vien) ON DELETE CASCADE,
    vi_tri_cong_viec VARCHAR(100)
);

CREATE TABLE pa_a.PhuTrach (
    ma_nhan_vien VARCHAR(20) REFERENCES pa_a.NhanVien(ma_nhan_vien),
    ma_chuyen VARCHAR(20) REFERENCES pa_a.ChuyenVanChuyen(ma_chuyen),
    PRIMARY KEY (ma_nhan_vien, ma_chuyen)
);

CREATE TABLE pa_a.LanBanGiao (
    ma_ban_giao VARCHAR(20) PRIMARY KEY,
    ma_buu_kien VARCHAR(20) REFERENCES pa_a.BuuKien(ma_buu_kien),
    ma_nhan_vien VARCHAR(20) REFERENCES pa_a.NhanVien(ma_nhan_vien),
    ma_diem_giao_nhan VARCHAR(20) REFERENCES pa_a.DiemGiaoNhan(ma_diem_giao_nhan),
    ma_chuyen VARCHAR(20) REFERENCES pa_a.ChuyenVanChuyen(ma_chuyen),
    thoi_gian_ban_giao TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    tinh_trang VARCHAR(50) DEFAULT 'NGUYEN_VEN',
    ghi_chu TEXT
);

CREATE TABLE pa_a.SuKienTrangThai (
    ma_su_kien VARCHAR(20) PRIMARY KEY,
    ma_buu_kien VARCHAR(20) REFERENCES pa_a.BuuKien(ma_buu_kien),
    ma_trang_thai VARCHAR(30) NOT NULL,
    ma_diem VARCHAR(20) REFERENCES pa_a.DiemGiaoNhan(ma_diem_giao_nhan),
    loai_su_kien VARCHAR(50),
    thoi_gian_xay_ra TIMESTAMP NOT NULL,
    thoi_gian_ghi_nhan TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    idempotency_key VARCHAR(100) UNIQUE NOT NULL
);

CREATE TABLE pa_a.ChiTietChuyenVanChuyen (
    ma_chuyen VARCHAR(20) REFERENCES pa_a.ChuyenVanChuyen(ma_chuyen),
    ma_buu_kien VARCHAR(20) REFERENCES pa_a.BuuKien(ma_buu_kien),
    thoi_gian_xep_xe TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ma_chuyen, ma_buu_kien)
);

-- ====================================================================
-- PHẦN II: SCHEMA pa_b (PHƯƠNG ÁN B - CURRENT STATE / PHI CHUẨN HÓA)
-- ====================================================================

CREATE TABLE pa_b.DiemGiaoNhan (
    ma_diem_giao_nhan VARCHAR(20) PRIMARY KEY,
    ten_diem VARCHAR(100) NOT NULL,
    dia_chi TEXT NOT NULL
);

CREATE TABLE pa_b.BuuCuc (
    ma_diem_giao_nhan VARCHAR(20) PRIMARY KEY REFERENCES pa_b.DiemGiaoNhan(ma_diem_giao_nhan) ON DELETE CASCADE,
    ma_buu_cuc VARCHAR(20) UNIQUE NOT NULL,
    sdt VARCHAR(15)
);

CREATE TABLE pa_b.KhoTrungChuyen (
    ma_diem_giao_nhan VARCHAR(20) PRIMARY KEY REFERENCES pa_b.DiemGiaoNhan(ma_diem_giao_nhan) ON DELETE CASCADE,
    ma_kho VARCHAR(20) UNIQUE NOT NULL,
    suc_chua NUMERIC(10, 2)
);

CREATE TABLE pa_b.TuyenVanChuyen (
    ma_tuyen VARCHAR(20) PRIMARY KEY,
    ten_tuyen VARCHAR(100) NOT NULL,
    dau_tuyen VARCHAR(20) REFERENCES pa_b.DiemGiaoNhan(ma_diem_giao_nhan),
    cuoi_tuyen VARCHAR(20) REFERENCES pa_b.DiemGiaoNhan(ma_diem_giao_nhan)
);

CREATE TABLE pa_b.ChuyenVanChuyen (
    ma_chuyen VARCHAR(20) PRIMARY KEY,
    ma_tuyen VARCHAR(20) REFERENCES pa_b.TuyenVanChuyen(ma_tuyen),
    thoi_gian_xuat_phat TIMESTAMP,
    thoi_gian_den_du_kien TIMESTAMP,
    trang_thai_chuyen VARCHAR(30) DEFAULT 'LEN_KE_HOACH'
);

CREATE TABLE pa_b.KhachHang (
    ma_khach_hang VARCHAR(20) PRIMARY KEY,
    ho_ten VARCHAR(100) NOT NULL,
    sdt VARCHAR(15) NOT NULL,
    dia_chi TEXT
);

CREATE TABLE pa_b.BuuKien (
    ma_buu_kien VARCHAR(20) PRIMARY KEY,
    ma_khach_hang_gui VARCHAR(20) REFERENCES pa_b.KhachHang(ma_khach_hang),
    ma_khach_hang_nhan VARCHAR(20) REFERENCES pa_b.KhachHang(ma_khach_hang),
    trong_luong NUMERIC(8, 2) NOT NULL,
    dai NUMERIC(6, 1),
    rong NUMERIC(6, 1),
    cao NUMERIC(6, 1),
    gia_khai NUMERIC(12, 2) DEFAULT 0,
    tien_COD NUMERIC(12, 2) DEFAULT 0,
    trang_thai_hien_tai VARCHAR(30) DEFAULT 'TIEP_NHAN',
    thoi_gian_cap_nhat_cuoi TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE pa_b.NhanVien (
    ma_nhan_vien VARCHAR(20) PRIMARY KEY,
    ho_ten VARCHAR(100) NOT NULL,
    so_dien_thoai VARCHAR(15) NOT NULL,
    vai_tro VARCHAR(30)
);

CREATE TABLE pa_b.Shipper (
    ma_nhan_vien VARCHAR(20) PRIMARY KEY REFERENCES pa_b.NhanVien(ma_nhan_vien) ON DELETE CASCADE,
    khu_vuc_phu_trach VARCHAR(100)
);

CREATE TABLE pa_b.NhanVienKho (
    ma_nhan_vien VARCHAR(20) PRIMARY KEY REFERENCES pa_b.NhanVien(ma_nhan_vien) ON DELETE CASCADE,
    vi_tri_cong_viec VARCHAR(100)
);

CREATE TABLE pa_b.PhuTrach (
    ma_nhan_vien VARCHAR(20) REFERENCES pa_b.NhanVien(ma_nhan_vien),
    ma_chuyen VARCHAR(20) REFERENCES pa_b.ChuyenVanChuyen(ma_chuyen),
    PRIMARY KEY (ma_nhan_vien, ma_chuyen)
);

CREATE TABLE pa_b.LanBanGiao (
    ma_ban_giao VARCHAR(20) PRIMARY KEY,
    ma_buu_kien VARCHAR(20) REFERENCES pa_b.BuuKien(ma_buu_kien),
    ma_nhan_vien VARCHAR(20) REFERENCES pa_b.NhanVien(ma_nhan_vien),
    ma_diem_giao_nhan VARCHAR(20) REFERENCES pa_b.DiemGiaoNhan(ma_diem_giao_nhan),
    ma_chuyen VARCHAR(20) REFERENCES pa_b.ChuyenVanChuyen(ma_chuyen),
    thoi_gian_ban_giao TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    tinh_trang VARCHAR(50) DEFAULT 'NGUYEN_VEN',
    ghi_chu TEXT
);

CREATE TABLE pa_b.SuKienTrangThai (
    ma_su_kien VARCHAR(20) PRIMARY KEY,
    ma_buu_kien VARCHAR(20) REFERENCES pa_b.BuuKien(ma_buu_kien),
    ma_trang_thai VARCHAR(30) NOT NULL,
    ma_diem VARCHAR(20) REFERENCES pa_b.DiemGiaoNhan(ma_diem_giao_nhan),
    loai_su_kien VARCHAR(50),
    thoi_gian_xay_ra TIMESTAMP NOT NULL,
    thoi_gian_ghi_nhan TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    idempotency_key VARCHAR(100) UNIQUE NOT NULL
);

CREATE TABLE pa_b.ChiTietChuyenVanChuyen (
    ma_chuyen VARCHAR(20) REFERENCES pa_b.ChuyenVanChuyen(ma_chuyen),
    ma_buu_kien VARCHAR(20) REFERENCES pa_b.BuuKien(ma_buu_kien),
    thoi_gian_xep_xe TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (ma_chuyen, ma_buu_kien)
);