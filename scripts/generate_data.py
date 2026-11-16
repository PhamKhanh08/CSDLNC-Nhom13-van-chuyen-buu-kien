# ====================================================================
# FILE: scripts/generate_data.py
# SCRIPT SINH 10.000 BƯU KIỆN & 100.000 SỰ KIỆN CHO 2 SCHEMA pa_a VÀ pa_b
# ĐẢM BẢO:
#   1. Thống nhất định dạng mã Điểm giao nhận 5 chữ số (DGN00001..DGN00003).
#   2. Mọi lệnh INSERT đều chỉ định danh sách cột tường minh khớp DDL.
#   3. Khởi tạo thoi_gian_cap_nhat_cuoi của pa_b.BuuKien theo mốc TIEP_NHAN thực tế
#      để Trigger trg_cap_nhat_trang_thai đồng bộ chính xác 100% với pa_a.
#   4. Sinh chuỗi sự kiện tuân thủ chặt chẽ Ma trận Chuyển trạng thái (BR-03, BR-05)
#      kèm mô phỏng sự kiện đến muộn (BR-06).
#   5. Có thể chạy lại nhiều lần (Idempotent / Repeatable) không gây lỗi trùng
#      hoặc sai lệch trạng thái.
# ====================================================================

import os
import random
from datetime import datetime, timedelta
import psycopg2
from psycopg2.extras import execute_values

DB_CONFIG = {
    "host": os.getenv("POSTGRES_HOST", "localhost"),
    "port": int(os.getenv("POSTGRES_PORT", "5432")),
    "database": os.getenv("POSTGRES_DB", "CSDLNC_DeTai13"),
    "user": os.getenv("POSTGRES_USER", "postgres"),
    "password": os.getenv("POSTGRES_PASSWORD", "123"),
}


def build_parcel_Templates():
    """
    Trả về các mẫu hành trình hợp lệ theo đúng Ma trận Chuyển trạng thái (BR-03 & BR-05):
      - ('NULL', 'TIEP_NHAN')
      - ('TIEP_NHAN', 'NHAP_KHO'), ('TIEP_NHAN', 'XUAT_KHO')
      - ('NHAP_KHO', 'XUAT_KHO'), ('NHAP_KHO', 'DANG_GIAO')
      - ('XUAT_KHO', 'DANG_VAN_CHUYEN')
      - ('DANG_VAN_CHUYEN', 'NHAP_KHO')
      - ('DANG_GIAO', 'GIAO_THANH_CONG'), ('DANG_GIAO', 'GIAO_THAT_BAI')
      - ('GIAO_THAT_BAI', 'DANG_GIAO'), ('GIAO_THAT_BAI', 'HOAN_TRA')
    Tổng số sự kiện trên 10.000 bưu kiện = đúng 100.000 sự kiện.
    """
    return {
        # Mẫu A (10 bước - 5.000 bưu kiện): Hành trình chuẩn qua 3 điểm DGN00001 -> DGN00002 -> DGN00003, giao thành công
        "A_THANH_CONG_10": [
            ("TIEP_NHAN", "DGN00001"),
            ("NHAP_KHO", "DGN00001"),
            ("XUAT_KHO", "DGN00001"),
            ("DANG_VAN_CHUYEN", "DGN00001"),
            ("NHAP_KHO", "DGN00002"),
            ("XUAT_KHO", "DGN00002"),
            ("DANG_VAN_CHUYEN", "DGN00002"),
            ("NHAP_KHO", "DGN00003"),
            ("DANG_GIAO", "DGN00003"),
            ("GIAO_THANH_CONG", "DGN00003"),
        ],
        # Mẫu B (11 bước - 1.000 bưu kiện): Xuất trực tiếp, giao thất bại 1 lần rồi giao lại thành công
        "B_PHAT_LAI_THANH_CONG_11": [
            ("TIEP_NHAN", "DGN00001"),
            ("XUAT_KHO", "DGN00001"),
            ("DANG_VAN_CHUYEN", "DGN00001"),
            ("NHAP_KHO", "DGN00002"),
            ("XUAT_KHO", "DGN00002"),
            ("DANG_VAN_CHUYEN", "DGN00002"),
            ("NHAP_KHO", "DGN00003"),
            ("DANG_GIAO", "DGN00003"),
            ("GIAO_THAT_BAI", "DGN00003"),
            ("DANG_GIAO", "DGN00003"),
            ("GIAO_THANH_CONG", "DGN00003"),
        ],
        # Mẫu C (9 bước - 1.000 bưu kiện): Đang tạm giữ chờ xử lý sau lần giao thất bại đầu tiên (bù trừ 11 + 9 = 20 với Mẫu B)
        "C_GIAO_THAT_BAI_9": [
            ("TIEP_NHAN", "DGN00001"),
            ("XUAT_KHO", "DGN00001"),
            ("DANG_VAN_CHUYEN", "DGN00001"),
            ("NHAP_KHO", "DGN00002"),
            ("XUAT_KHO", "DGN00002"),
            ("DANG_VAN_CHUYEN", "DGN00002"),
            ("NHAP_KHO", "DGN00003"),
            ("DANG_GIAO", "DGN00003"),
            ("GIAO_THAT_BAI", "DGN00003"),
        ],
        # Mẫu D (10 bước - 1.000 bưu kiện): Giao thất bại 2 lần và kết thúc ở trạng thái HOAN_TRA (BR-05)
        "D_HOAN_TRA_10": [
            ("TIEP_NHAN", "DGN00001"),
            ("NHAP_KHO", "DGN00001"),
            ("XUAT_KHO", "DGN00001"),
            ("DANG_VAN_CHUYEN", "DGN00001"),
            ("NHAP_KHO", "DGN00003"),
            ("DANG_GIAO", "DGN00003"),
            ("GIAO_THAT_BAI", "DGN00003"),
            ("DANG_GIAO", "DGN00003"),
            ("GIAO_THAT_BAI", "DGN00003"),
            ("HOAN_TRA", "DGN00003"),
        ],
        # Mẫu E (10 bước - 1.000 bưu kiện): Đang trong quá trình phát lại (trạng thái hiện tại: DANG_GIAO)
        "E_DANG_GIAO_10": [
            ("TIEP_NHAN", "DGN00001"),
            ("XUAT_KHO", "DGN00001"),
            ("DANG_VAN_CHUYEN", "DGN00001"),
            ("NHAP_KHO", "DGN00002"),
            ("XUAT_KHO", "DGN00002"),
            ("DANG_VAN_CHUYEN", "DGN00002"),
            ("NHAP_KHO", "DGN00003"),
            ("DANG_GIAO", "DGN00003"),
            ("GIAO_THAT_BAI", "DGN00003"),
            ("DANG_GIAO", "DGN00003"),
        ],
        # Mẫu F (10 bước - 1.000 bưu kiện, bao gồm PK00000001): Đang lưu kho tại điểm đích chờ xuất/phát (trạng thái hiện tại: NHAP_KHO)
        "F_NHAP_KHO_10": [
            ("TIEP_NHAN", "DGN00001"),
            ("XUAT_KHO", "DGN00001"),
            ("DANG_VAN_CHUYEN", "DGN00001"),
            ("NHAP_KHO", "DGN00002"),
            ("XUAT_KHO", "DGN00002"),
            ("DANG_VAN_CHUYEN", "DGN00002"),
            ("NHAP_KHO", "DGN00003"),
            ("XUAT_KHO", "DGN00003"),
            ("DANG_VAN_CHUYEN", "DGN00003"),
            ("NHAP_KHO", "DGN00001"),
        ],
    }


def select_template_key(parcel_idx: int) -> str:
    # Đảm bảo PK00000001 thuộc Mẫu F (kết thúc ở NHAP_KHO) để tương thích 100% với:
    # - Kịch bản 3 trong benchmark.explain.sql (INSERT sự kiện DANG_GIAO cho PK00000001)
    # - Kịch bản khóa đồng thời trong transaction_concurrency.sql (PK00000001 ở NHAP_KHO)
    if parcel_idx == 1:
        return "F_NHAP_KHO_10"
    if parcel_idx == 10:
        return "A_THANH_CONG_10"

    mod = parcel_idx % 10
    if mod in (1, 2, 3, 4, 5):
        return "A_THANH_CONG_10"
    elif mod == 6:
        return "B_PHAT_LAI_THANH_CONG_11"
    elif mod == 7:
        return "C_GIAO_THAT_BAI_9"
    elif mod == 8:
        return "D_HOAN_TRA_10"
    elif mod == 9:
        return "E_DANG_GIAO_10"
    else:
        return "F_NHAP_KHO_10"


def seed_data():
    random.seed(42)
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    now = datetime.now().replace(microsecond=0)

    print("⏳ 0. Làm sạch dữ liệu cũ trong 2 schema pa_a và pa_b để đảm bảo tính lặp lại (Idempotent)...")
    for schema in ("pa_a", "pa_b"):
        cur.execute(f"""
            TRUNCATE TABLE
                {schema}.ChiTietChuyenVanChuyen,
                {schema}.SuKienTrangThai,
                {schema}.LanBanGiao,
                {schema}.PhuTrach,
                {schema}.Shipper,
                {schema}.NhanVienKho,
                {schema}.NhanVien,
                {schema}.BuuKien,
                {schema}.KhachHang,
                {schema}.ChuyenVanChuyen,
                {schema}.TuyenVanChuyen,
                {schema}.BuuCuc,
                {schema}.KhoTrungChuyen,
                {schema}.DiemGiaoNhan
            RESTART IDENTITY CASCADE;
        """)
    conn.commit()

    print("⏳ 1. Sinh dữ liệu danh mục ban đầu (DiemGiaoNhan, BuuCuc, KhoTrungChuyen, KhachHang, Tuyen, NhanVien, Chuyen)...")

    # 1.1. Điểm giao nhận chuẩn hóa thống nhất theo định dạng 5 chữ số DGN00001..DGN00003
    diem_list = [
        ("DGN00001", "Bưu cục Trung tâm Quận 1", "12 Nguyễn Huệ, Quận 1, TP.HCM"),
        ("DGN00002", "Kho Trung chuyển Tân Bình", "45 Trường Chinh, Tân Bình, TP.HCM"),
        ("DGN00003", "Bưu cục Hoàn Kiếm", "88 Đinh Tiên Hoàng, Hoàn Kiếm, Hà Nội"),
    ]
    for schema in ("pa_a", "pa_b"):
        execute_values(
            cur,
            f"""
            INSERT INTO {schema}.DiemGiaoNhan (ma_diem_giao_nhan, ten_diem, dia_chi)
            VALUES %s
            ON CONFLICT (ma_diem_giao_nhan) DO NOTHING;
            """,
            diem_list,
        )

    # 1.2. Lớp con Bưu cục & Kho trung chuyển (ISA: TOTAL, DISJOINT)
    buu_cuc_list = [
        ("DGN00001", "BC00001", "02838221111"),
        ("DGN00003", "BC00003", "02438252222"),
    ]
    kho_list = [
        ("DGN00002", "KTC00002", 50000.00),
    ]
    for schema in ("pa_a", "pa_b"):
        execute_values(
            cur,
            f"""
            INSERT INTO {schema}.BuuCuc (ma_diem_giao_nhan, ma_buu_cuc, sdt)
            VALUES %s
            ON CONFLICT (ma_diem_giao_nhan) DO NOTHING;
            """,
            buu_cuc_list,
        )
        execute_values(
            cur,
            f"""
            INSERT INTO {schema}.KhoTrungChuyen (ma_diem_giao_nhan, ma_kho, suc_chua)
            VALUES %s
            ON CONFLICT (ma_diem_giao_nhan) DO NOTHING;
            """,
            kho_list,
        )

    # 1.3. Khách hàng mồi (100 khách hàng)
    kh_list = [
        (f"KH{i:04d}", f"Khách hàng {i}", f"090{i:07d}", f"Địa chỉ số {i}, Việt Nam")
        for i in range(1, 101)
    ]
    for schema in ("pa_a", "pa_b"):
        execute_values(
            cur,
            f"""
            INSERT INTO {schema}.KhachHang (ma_khach_hang, ho_ten, sdt, dia_chi)
            VALUES %s
            ON CONFLICT (ma_khach_hang) DO NOTHING;
            """,
            kh_list,
        )

    # 1.4. Tuyến vận chuyển mồi (tham chiếu mã DGN00001..DGN00003 thống nhất)
    tuyen_list = [
        ("T01", "Tuyến Sài Gòn - Hà Nội", "DGN00001", "DGN00003"),
        ("T02", "Tuyến Tân Bình - Quận 1", "DGN00002", "DGN00001"),
        ("T03", "Tuyến Quận 1 - Tân Bình", "DGN00001", "DGN00002"),
        ("T04", "Tuyến Tân Bình - Hoàn Kiếm", "DGN00002", "DGN00003"),
    ]
    for schema in ("pa_a", "pa_b"):
        execute_values(
            cur,
            f"""
            INSERT INTO {schema}.TuyenVanChuyen (ma_tuyen, ten_tuyen, dau_tuyen, cuoi_tuyen)
            VALUES %s
            ON CONFLICT (ma_tuyen) DO NOTHING;
            """,
            tuyen_list,
        )

    # 1.5. Nhân viên mồi & bảng chuyên biệt hóa Shipper / NhanVienKho
    nv_list = [
        ("NV01", "Nguyễn Văn An", "0912345678", "NHAN_VIEN_KHO"),
        ("NV02", "Trần Thị Bình", "0912345679", "SHIPPER"),
    ]
    nv_kho_list = [("NV01", "Điều phối & Phân loại Kho Tân Bình")]
    shipper_list = [("NV02", "Tuyến phố trung tâm Hoàn Kiếm & Quận 1")]
    for schema in ("pa_a", "pa_b"):
        execute_values(
            cur,
            f"""
            INSERT INTO {schema}.NhanVien (ma_nhan_vien, ho_ten, so_dien_thoai, vai_tro)
            VALUES %s
            ON CONFLICT (ma_nhan_vien) DO NOTHING;
            """,
            nv_list,
        )
        execute_values(
            cur,
            f"""
            INSERT INTO {schema}.NhanVienKho (ma_nhan_vien, vi_tri_cong_viec)
            VALUES %s
            ON CONFLICT (ma_nhan_vien) DO NOTHING;
            """,
            nv_kho_list,
        )
        execute_values(
            cur,
            f"""
            INSERT INTO {schema}.Shipper (ma_nhan_vien, khu_vuc_phu_trach)
            VALUES %s
            ON CONFLICT (ma_nhan_vien) DO NOTHING;
            """,
            shipper_list,
        )

    # 1.6. Chuyến vận chuyển & Phụ trách
    chuyen_list = [
        ("CH01", "T01", now - timedelta(days=10), now - timedelta(days=8), "HOAN_THANH"),
        ("CH02", "T02", now - timedelta(hours=12), now + timedelta(hours=12), "DANG_CHAY"),
    ]
    phu_trach_list = [
        ("NV01", "CH01"),
        ("NV02", "CH02"),
    ]
    for schema in ("pa_a", "pa_b"):
        execute_values(
            cur,
            f"""
            INSERT INTO {schema}.ChuyenVanChuyen (
                ma_chuyen, ma_tuyen, thoi_gian_xuat_phat, thoi_gian_den_du_kien, trang_thai_chuyen
            )
            VALUES %s
            ON CONFLICT (ma_chuyen) DO NOTHING;
            """,
            chuyen_list,
        )
        execute_values(
            cur,
            f"""
            INSERT INTO {schema}.PhuTrach (ma_nhan_vien, ma_chuyen)
            VALUES %s
            ON CONFLICT (ma_nhan_vien, ma_chuyen) DO NOTHING;
            """,
            phu_trach_list,
        )
    conn.commit()

    print("⏳ 2. Đang sinh 10.000 bưu kiện và 100.000 sự kiện tuân thủ vòng đời nghiệp vụ...")
    templates = build_parcel_Templates()
    data_pa_a_buukien = []
    data_pa_b_buukien = []
    data_events = []
    data_lan_ban_giao = []
    data_chi_tiet_chuyen = []

    sk_counter = 1
    lbg_counter = 1

    for i in range(1, 10001):
        ma_pk = f"PK{i:08d}"
        kh_gui = f"KH{random.randint(1, 50):04d}"
        kh_nhan = f"KH{random.randint(51, 100):04d}"
        trong_luong = round(random.uniform(0.5, 10.0), 2)
        dai = round(random.uniform(10.0, 40.0), 1)
        rong = round(random.uniform(10.0, 30.0), 1)
        cao = round(random.uniform(5.0, 20.0), 1)
        gia_khai = random.choice([0, 500000, 1000000, 2000000])
        tien_cod = random.choice([0, 100000, 250000, 500000, 1000000])

        tpl_key = select_template_key(i)
        steps = templates[tpl_key]

        # Thời điểm khởi tạo (TIEP_NHAN) cách hiện tại từ 8 đến 20 ngày
        # (Đảm bảo các bưu kiện chưa kết thúc có sự kiện cuối cách hiện tại > 48h phục vụ Q3)
        start_days_ago = random.randint(8, 20)
        start_hours_offset = random.randint(0, 12)
        t_tiep_nhan = now - timedelta(days=start_days_ago, hours=start_hours_offset, minutes=i % 60)

        # pa_a: Không lưu trạng thái hiện tại trên BuuKien
        data_pa_a_buukien.append(
            (ma_pk, kh_gui, kh_nhan, trong_luong, dai, rong, cao, gia_khai, tien_cod)
        )

        # pa_b: Khởi tạo ở trạng thái đầu tiên ('TIEP_NHAN') với đúng thời điểm t_tiep_nhan.
        # Khi chèn SuKienTrangThai vào pa_b, Trigger trg_cap_nhat_trang_thai sẽ tự động
        # cập nhật trang_thai_hien_tai và thoi_gian_cap_nhat_cuoi lên sự kiện mới nhất.
        data_pa_b_buukien.append(
            (
                ma_pk,
                kh_gui,
                kh_nhan,
                trong_luong,
                dai,
                rong,
                cao,
                gia_khai,
                tien_cod,
                "TIEP_NHAN",
                t_tiep_nhan,
            )
        )

        # Sinh chuỗi sự kiện cho bưu kiện ma_pk với thoi_gian_xay_ra tăng dần chặt chẽ
        parcel_events = []
        t_current = t_tiep_nhan
        for step_idx, (trang_thai, ma_diem) in enumerate(steps):
            ma_sk = f"SK{sk_counter:08d}"
            sk_counter += 1

            if step_idx > 0:
                t_current = t_current + timedelta(hours=random.randint(3, 8), minutes=random.randint(1, 45))

            t_xay_ra = t_current
            t_ghi_nhan = t_xay_ra + timedelta(seconds=random.randint(5, 30))
            loai_sk = f"SU_KIEN_{trang_thai}"
            idempotency_key = f"KEY-{ma_sk}"

            parcel_events.append(
                [ma_sk, ma_pk, trang_thai, ma_diem, loai_sk, t_xay_ra, t_ghi_nhan, idempotency_key]
            )

        # Mô phỏng sự kiện đến muộn (BR-06):
        # Với các bưu kiện có i % 10 == 1 (hoặc PK00000001), sự kiện ở bước thứ 4 (index 3)
        # bị trễ mạng nên được máy chủ ghi nhận (thoi_gian_ghi_nhan) SAU bước thứ 5 (index 4) 45 phút,
        # và được đẩy vào CSDL sau bước thứ 5.
        if i == 1 or i % 10 == 1:
            t_ghi_nhan_step5 = parcel_events[4][6]
            parcel_events[3][6] = t_ghi_nhan_step5 + timedelta(minutes=45)
            # Đổi chỗ thứ tự INSERT giữa bước 4 và bước 5 để kiểm chứng Trigger BR-06 thực tế
            parcel_events[3], parcel_events[4] = parcel_events[4], parcel_events[3]

        # Với các bưu kiện có i % 20 == 0, sự kiện áp chót (index -2) đến muộn sau sự kiện cuối cùng (index -1)
        # để chứng minh Trigger PA_B không bao giờ làm trạng thái hiện tại bị quay lùi về quá khứ
        elif i % 20 == 0:
            t_ghi_nhan_last = parcel_events[-1][6]
            parcel_events[-2][6] = t_ghi_nhan_last + timedelta(minutes=35)
            parcel_events[-2], parcel_events[-1] = parcel_events[-1], parcel_events[-2]

        for ev in parcel_events:
            data_events.append(tuple(ev))

        # Sinh dữ liệu biên bản bàn giao mẫu (LanBanGiao) & ChiTietChuyenVanChuyen cho 200 bưu kiện đầu
        if i <= 200:
            ma_bg = f"LBG{lbg_counter:07d}"
            lbg_counter += 1
            data_lan_ban_giao.append(
                (
                    ma_bg,
                    ma_pk,
                    "NV01",
                    "DGN00001",
                    "CH01",
                    t_tiep_nhan + timedelta(hours=2),
                    "NGUYEN_VEN",
                    "Bàn giao nguyên vẹn lên chuyến CH01",
                )
            )
            data_chi_tiet_chuyen.append(("CH01", ma_pk, t_tiep_nhan + timedelta(hours=2)))

    print("👉 Nạp 10.000 BuuKien vào pa_a...")
    execute_values(
        cur,
        """
        INSERT INTO pa_a.BuuKien (
            ma_buu_kien, ma_khach_hang_gui, ma_khach_hang_nhan,
            trong_luong, dai, rong, cao, gia_khai, tien_COD
        )
        VALUES %s
        ON CONFLICT (ma_buu_kien) DO NOTHING;
        """,
        data_pa_a_buukien,
        page_size=2000,
    )

    print("👉 Nạp 10.000 BuuKien vào pa_b...")
    execute_values(
        cur,
        """
        INSERT INTO pa_b.BuuKien (
            ma_buu_kien, ma_khach_hang_gui, ma_khach_hang_nhan,
            trong_luong, dai, rong, cao, gia_khai, tien_COD,
            trang_thai_hien_tai, thoi_gian_cap_nhat_cuoi
        )
        VALUES %s
        ON CONFLICT (ma_buu_kien) DO NOTHING;
        """,
        data_pa_b_buukien,
        page_size=2000,
    )
    conn.commit()

    sql_event = """
        INSERT INTO {schema}.SuKienTrangThai (
            ma_su_kien, ma_buu_kien, ma_trang_thai, ma_diem, loai_su_kien,
            thoi_gian_xay_ra, thoi_gian_ghi_nhan, idempotency_key
        )
        VALUES %s
        ON CONFLICT (idempotency_key) DO NOTHING;
    """

    print(f"👉 Nạp {len(data_events):,} Sự kiện vào pa_a...")
    execute_values(cur, sql_event.format(schema="pa_a"), data_events, page_size=5000)
    conn.commit()

    print(f"👉 Nạp {len(data_events):,} Sự kiện vào pa_b (kích hoạt Trigger đồng bộ trạng thái)...")
    execute_values(cur, sql_event.format(schema="pa_b"), data_events, page_size=5000)
    conn.commit()

    print("👉 Nạp dữ liệu LanBanGiao và ChiTietChuyenVanChuyen đồng bộ cho pa_a và pa_b...")
    for schema in ("pa_a", "pa_b"):
        execute_values(
            cur,
            f"""
            INSERT INTO {schema}.LanBanGiao (
                ma_ban_giao, ma_buu_kien, ma_nhan_vien, ma_diem_giao_nhan,
                ma_chuyen, thoi_gian_ban_giao, tinh_trang, ghi_chu
            )
            VALUES %s
            ON CONFLICT (ma_ban_giao) DO NOTHING;
            """,
            data_lan_ban_giao,
            page_size=1000,
        )
        execute_values(
            cur,
            f"""
            INSERT INTO {schema}.ChiTietChuyenVanChuyen (
                ma_chuyen, ma_buu_kien, thoi_gian_xep_xe
            )
            VALUES %s
            ON CONFLICT (ma_chuyen, ma_buu_kien) DO NOTHING;
            """,
            data_chi_tiet_chuyen,
            page_size=1000,
        )
    conn.commit()

    cur.close()
    conn.close()
    print("🚀 THÀNH CÔNG: Đã sinh 10.000 bưu kiện & 100.000 sự kiện hợp lệ, đồng bộ 100% giữa pa_a và pa_b!")


if __name__ == "__main__":
    seed_data()
