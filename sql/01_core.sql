-- =====================================================================
-- 01_core.sql — Dữ liệu danh mục DÙNG CHUNG cho cả hai phương án.
-- =====================================================================

CREATE SCHEMA core;

-- Tập trạng thái bưu kiện (1 sự kiện = 1 lần chuyển sang trạng thái này)
CREATE TYPE core.trang_thai_buu_kien AS ENUM (
    'TIEP_NHAN', 'DEN_KHO', 'DANG_VAN_CHUYEN',
    'DANG_GIAO', 'GIAO_THAT_BAI', 'DA_GIAO', 'HOAN_TRA'
);

-- ---------- KhachHang ----------
CREATE TABLE core.khach_hang (
    ma_khach_hang BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ho_ten        VARCHAR(100) NOT NULL,
    so_dien_thoai VARCHAR(20)  NOT NULL,
    dia_chi       TEXT         NOT NULL
);

-- ---------- DiemGiaoNhan  ISA(TOTAL, DISJOINT)  KhoTrungChuyen | BuuCuc ----------.
CREATE TABLE core.diem_giao_nhan (
    ma_diem   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ten_diem  VARCHAR(100) NOT NULL,
    dia_chi   TEXT         NOT NULL,
    loai_diem VARCHAR(10)  NOT NULL CHECK (loai_diem IN ('KHO', 'BUU_CUC')),
    UNIQUE (ma_diem, loai_diem)
);

CREATE TABLE core.kho_trung_chuyen (
    ma_diem   BIGINT PRIMARY KEY,
    loai_diem VARCHAR(10) NOT NULL DEFAULT 'KHO' CHECK (loai_diem = 'KHO'),
    suc_chua  INT NOT NULL CHECK (suc_chua > 0),
    FOREIGN KEY (ma_diem, loai_diem) REFERENCES core.diem_giao_nhan (ma_diem, loai_diem)
);

CREATE TABLE core.buu_cuc (
    ma_diem   BIGINT PRIMARY KEY,
    loai_diem VARCHAR(10) NOT NULL DEFAULT 'BUU_CUC' CHECK (loai_diem = 'BUU_CUC'),
    sdt       VARCHAR(20) NOT NULL,
    FOREIGN KEY (ma_diem, loai_diem) REFERENCES core.diem_giao_nhan (ma_diem, loai_diem)
);

-- ---------- NhanVien  ISA(PARTIAL, DISJOINT)  Shipper | NhanVienKho ----------
-- Dùng luôn thuộc tính `vai_tro` của EER làm cột phân biệt.
-- PARTIAL: vai_tro 'QUAN_LY'/'KHAC' không có lớp con.
CREATE TABLE core.nhan_vien (
    ma_nhan_vien  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ho_ten        VARCHAR(100) NOT NULL,
    so_dien_thoai VARCHAR(20)  NOT NULL,
    vai_tro       VARCHAR(20)  NOT NULL
                    CHECK (vai_tro IN ('SHIPPER', 'NHAN_VIEN_KHO', 'QUAN_LY', 'KHAC')),
    UNIQUE (ma_nhan_vien, vai_tro)
);

CREATE TABLE core.shipper (
    ma_nhan_vien      BIGINT PRIMARY KEY,
    vai_tro           VARCHAR(20) NOT NULL DEFAULT 'SHIPPER' CHECK (vai_tro = 'SHIPPER'),
    khu_vuc_phu_trach VARCHAR(100) NOT NULL,
    FOREIGN KEY (ma_nhan_vien, vai_tro) REFERENCES core.nhan_vien (ma_nhan_vien, vai_tro)
);

CREATE TABLE core.nhan_vien_kho (
    ma_nhan_vien    BIGINT PRIMARY KEY,
    vai_tro         VARCHAR(20) NOT NULL DEFAULT 'NHAN_VIEN_KHO' CHECK (vai_tro = 'NHAN_VIEN_KHO'),
    vi_tri_cong_viec VARCHAR(100) NOT NULL,
    FOREIGN KEY (ma_nhan_vien, vai_tro) REFERENCES core.nhan_vien (ma_nhan_vien, vai_tro)
);

-- ---------- TuyenVanChuyen (DAU_TUYEN, CUOI_TUYEN -> DiemGiaoNhan) ----------
CREATE TABLE core.tuyen_van_chuyen (
    ma_tuyen    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ten_tuyen   VARCHAR(100) NOT NULL,
    ma_diem_dau  BIGINT NOT NULL REFERENCES core.diem_giao_nhan (ma_diem),
    ma_diem_cuoi BIGINT NOT NULL REFERENCES core.diem_giao_nhan (ma_diem),
    CHECK (ma_diem_dau <> ma_diem_cuoi)
);

-- ---------- ChuyenVanChuyen (CO_CHUYEN 1:N, PHU_TRACH) ----------
-- Giả định: PHU_TRACH là N:1 (mỗi chuyến có tối đa 1 nhân viên phụ trách).
CREATE TABLE core.chuyen_van_chuyen (
    ma_chuyen              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ma_tuyen               BIGINT NOT NULL REFERENCES core.tuyen_van_chuyen (ma_tuyen),
    ma_nhan_vien_phu_trach BIGINT REFERENCES core.nhan_vien (ma_nhan_vien),
    thoi_gian_xuat_phat    TIMESTAMPTZ NOT NULL,
    thoi_gian_den_du_kien  TIMESTAMPTZ NOT NULL,
    trang_thai_chuyen      VARCHAR(20) NOT NULL DEFAULT 'LEN_KE_HOACH'
                            CHECK (trang_thai_chuyen IN ('LEN_KE_HOACH', 'DANG_CHAY', 'HOAN_THANH', 'HUY')),
    CHECK (thoi_gian_den_du_kien > thoi_gian_xuat_phat)
);
CREATE INDEX idx_core_chuyen_tuyen ON core.chuyen_van_chuyen (ma_tuyen);