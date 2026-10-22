# CSDLNC Nhom 13 Van chuyen buu kien

Môi trường PostgreSQL cho đề tài theo dõi vận chuyển và bàn giao bưu kiện.

## Chạy bằng PostgreSQL cài sẵn trên Windows

1. Sao chép `.env.example` thành `.env`.
2. Điền đúng mật khẩu của tài khoản PostgreSQL vào `POSTGRES_PASSWORD`.
3. Mở PowerShell tại thư mục dự án và chạy:

```powershell
.\scripts\setup-database.ps1
.\scripts\test-connection.ps1
```

Lệnh đầu tạo cơ sở dữ liệu `parcel_tracking` (nếu chưa có) và chạy các file SQL
trong `sql` theo thứ tự. Lệnh thứ hai chỉ kiểm tra kết nối và hiển thị phiên bản PostgreSQL.

## Chạy bằng Docker (tùy chọn)

Nếu đã cài Docker Desktop, sao chép `.env.example` thành `.env`, điền mật khẩu mới
an toàn, rồi chạy:

```powershell
docker compose up -d
docker compose ps
```

Docker chỉ chạy các script trong `sql` ở lần tạo volume đầu tiên. Để áp dụng thay đổi
sau đó, chạy `setup-database.ps1` hoặc một file migration bằng `psql`.

Xem hướng dẫn chi tiết và cách khắc phục lỗi tại `docs/setup-postgresql.md`.
