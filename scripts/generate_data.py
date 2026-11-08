# ====================================================================
# FILE: generate_data.py
# SCRIPT SINH 10.000 BƯU KIỆN & 100.000 SỰ KIỆN CHO 2 SCHEMA pa_a VÀ pa_b
# BẢN ĐÃ RÀ SOÁT - ĐỒNG BỘ NGUYÊN BẢN VỚI LƯỢC ĐỒ CHUẨN
# ====================================================================

import psycopg2
from psycopg2.extras import execute_values
import random
from datetime import datetime, timedelta
import uuid

DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "database": "CSDLNC_DeTai13",
    "user": "postgres",
    "password": "your_password"
}

def seed_data():
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    now = datetime.now()

    print("⏳ 1. Sinh dữ liệu danh mục ban đầu (DiemGiaoNhan, KhachHang, Tuyen)...")
    
    # Nạp Điểm giao nhận mồi
    diem_list = [('DGN01', 'Bưu cục Quận 1', '12 Nguyễn Huệ, Q1, TP.HCM'),
                 ('DGN02', 'Kho Trung chuyển Tân Bình', '45 Trường Chinh, Tân Bình'),
                 ('DGN03', 'Bưu cục Hoàn Kiếm', '88 Đinh Tiên Hoàng, Hà Nội')]
    
    execute_values(cur, "INSERT INTO pa_a.DiemGiaoNhan VALUES %s ON CONFLICT DO NOTHING;", diem_list)
    execute_values(cur, "INSERT INTO pa_b.DiemGiaoNhan VALUES %s ON CONFLICT DO NOTHING;", diem_list)

    # Nạp Khách hàng mồi
    kh_list = [(f"KH{i:04d}", f"Khách hàng {i}", f"090{i:07d}", f"Địa chỉ {i}") for i in range(1, 101)]
    execute_values(cur, "INSERT INTO pa_a.KhachHang VALUES %s ON CONFLICT DO NOTHING;", kh_list)
    execute_values(cur, "INSERT INTO pa_b.KhachHang VALUES %s ON CONFLICT DO NOTHING;", kh_list)

    # Nạp Tuyến vận chuyển mồi (CHỈ CÓ 4 CỘT)
    tuyen_list = [('T01', 'Tuyến Sài Gòn - Hà Nội', 'DGN01', 'DGN03'),
                  ('T02', 'Tuyến Tân Bình - Q1', 'DGN02', 'DGN01')]
    execute_values(cur, "INSERT INTO pa_a.TuyenVanChuyen VALUES %s ON CONFLICT DO NOTHING;", tuyen_list)
    execute_values(cur, "INSERT INTO pa_b.TuyenVanChuyen VALUES %s ON CONFLICT DO NOTHING;", tuyen_list)
    conn.commit()

    print("⏳ 2. Đang sinh 10.000 bưu kiện dùng chung...")
    data_pa_a_buukien = []
    data_pa_b_buukien = []

    for i in range(1, 10001):
        ma_pk = f"PK{i:08d}"
        kh_gui = f"KH{random.randint(1, 50):04d}"
        kh_nhan = f"KH{random.randint(51, 100):04d}"
        trong_luong = round(random.uniform(0.5, 10.0), 2)
        dai = round(random.uniform(10.0, 40.0), 1)
        rong = round(random.uniform(10.0, 30.0), 1)
        cao = round(random.uniform(5.0, 20.0), 1)
        gia_khai = random.choice([0, 500000, 1000000, 2000000])
        tien_cod = random.choice([0, 100000, 250000, 500000])

        # pa_a: KHÔNG CÓ cột trang_thai_hien_tai
        data_pa_a_buukien.append((ma_pk, kh_gui, kh_nhan, trong_luong, dai, rong, cao, gia_khai, tien_cod))
        
        # pa_b: CÓ THÊM 2 cột trạng thái
        data_pa_b_buukien.append((ma_pk, kh_gui, kh_nhan, trong_luong, dai, rong, cao, gia_khai, tien_cod, 'TIEP_NHAN', now))

    print("👉 Nạp BuuKien vào pa_a...")
    execute_values(cur, """
        INSERT INTO pa_a.BuuKien (ma_buu_kien, ma_khach_hang_gui, ma_khach_hang_nhan, trong_luong, dai, rong, cao, gia_khai, tien_COD)
        VALUES %s ON CONFLICT DO NOTHING;
    """, data_pa_a_buukien, page_size=2000)

    print("👉 Nạp BuuKien vào pa_b...")
    execute_values(cur, """
        INSERT INTO pa_b.BuuKien (ma_buu_kien, ma_khach_hang_gui, ma_khach_hang_nhan, trong_luong, dai, rong, cao, gia_khai, tien_COD, trang_thai_hien_tai, thoi_gian_cap_nhat_cuoi)
        VALUES %s ON CONFLICT DO NOTHING;
    """, data_pa_b_buukien, page_size=2000)
    conn.commit()

    print("⏳ 3. Đang sinh 100.000 sự kiện hành trình...")
    data_events = []
    list_trang_thai = ['TIEP_NHAN', 'NHAP_KHO', 'XUAT_KHO', 'DANG_VAN_CHUYEN', 'DANG_GIAO', 'GIAO_THANH_CONG']

    for i in range(1, 100001):
        ma_sk = f"SK{i:08d}"
        ma_pk = f"PK{random.randint(1, 10000):08d}"
        trang_thai = random.choice(list_trang_thai)
        ma_diem = random.choice(['DGN01', 'DGN02', 'DGN03'])
        loai_sk = f"SỰ KIỆN {trang_thai}"
        thoi_gian_xay_ra = now - timedelta(days=random.randint(1, 20), hours=random.randint(0, 23))
        thoi_gian_ghi_nhan = thoi_gian_xay_ra + timedelta(seconds=random.randint(5, 30))
        idempotency_key = f"KEY-{uuid.uuid4()}"

        data_events.append((ma_sk, ma_pk, trang_thai, ma_diem, loai_sk, thoi_gian_xay_ra, thoi_gian_ghi_nhan, idempotency_key))

    sql_event = """
        INSERT INTO {schema}.SuKienTrangThai (
            ma_su_kien, ma_buu_kien, ma_trang_thai, ma_diem, loai_su_kien,
            thoi_gian_xay_ra, thoi_gian_ghi_nhan, idempotency_key
        ) VALUES %s ON CONFLICT (idempotency_key) DO NOTHING;
    """

    print("👉 Nạp Sự kiện vào pa_a...")
    execute_values(cur, sql_event.format(schema='pa_a'), data_events, page_size=5000)
    conn.commit()

    print("👉 Nạp Sự kiện vào pa_b...")
    execute_values(cur, sql_event.format(schema='pa_b'), data_events, page_size=5000)
    conn.commit()

    cur.close()
    conn.close()
    print("🚀 THÀNH CÔNG: Đã sinh dữ liệu hoàn chỉnh và đồng bộ 100%!")

if __name__ == "__main__":
    seed_data()