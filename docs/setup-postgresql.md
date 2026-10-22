# Thiết lập PostgreSQL cho Nhóm 13

## Trạng thái đã kiểm tra

Trên máy này đã có PostgreSQL 18 và dịch vụ `postgresql-x64-18` đang chạy tại
`localhost:5432`. Docker Desktop chưa có, vì vậy hướng dẫn chính dùng PostgreSQL cài sẵn.

## Thiết lập lần đầu

Trong PowerShell, tại thư mục dự án, thực hiện:

```powershell
Copy-Item .env.example .env
notepad .env
```

Trong `.env`, chỉ thay `POSTGRES_PASSWORD` bằng mật khẩu bạn đặt khi cài PostgreSQL.
Không đổi thông tin khác nếu bạn dùng cấu hình mặc định. File `.env` đã được bỏ qua bởi Git.

Tiếp theo chạy:

```powershell
.\scripts\setup-database.ps1
.\scripts\test-connection.ps1
```

Kết quả đúng: script đầu tạo database `parcel_tracking` và schema
`parcel_tracking`; script sau in database, tài khoản và phiên bản PostgreSQL.

## Kết nối bằng pgAdmin 4

1. Mở **pgAdmin 4** rồi chọn **Register > Server**.
2. Đặt tên tùy ý, ví dụ `Parcel Tracking Local`.
3. Tại tab **Connection**, nhập Host `localhost`, Port `5432`, Maintenance database `postgres`, Username `postgres` và mật khẩu của bạn.
4. Sau khi kết nối, mở **Databases > parcel_tracking > Schemas > parcel_tracking**.

## Kết nối từ terminal

```powershell
& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -h localhost -p 5432 -U postgres -d parcel_tracking
```

PostgreSQL sẽ hỏi mật khẩu. Để liệt kê các bảng trong schema đề tài:

```sql
\dt parcel_tracking.*
```

## Cách tổ chức script

- `sql/01_schema.sql`: bootstrap schema và bảng lưu phiên bản migration.
- Các file sau đặt tên tăng dần, ví dụ `sql/02_core_tables.sql`, `sql/03_constraints.sql`, `sql/04_seed.sql`.
- Mỗi lần bổ sung hoặc sửa DDL, chạy lại `scripts/setup-database.ps1`.

Không chỉnh sửa các migration đã được cả nhóm chạy trên cùng một database; tạo một file số mới.
Điều này giúp tái lập môi trường và dễ kiểm soát phần lịch sử sự kiện, sự kiện trùng,
sự kiện đến muộn và transaction đồng thời mà đề tài yêu cầu.

## Nếu kết nối thất bại

- Xem dịch vụ: `Get-Service postgresql-x64-18`.
- Khởi động (mở PowerShell với quyền Administrator): `Start-Service postgresql-x64-18`.
- Kiểm tra cổng: `& 'C:\Program Files\PostgreSQL\18\bin\pg_isready.exe' -h localhost -p 5432`.
- Nếu quên mật khẩu `postgres`, không đoán mật khẩu hoặc sửa file dữ liệu; báo người đã cài PostgreSQL để đặt lại theo quy trình quản trị.
