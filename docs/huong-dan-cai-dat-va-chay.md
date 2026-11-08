# Hướng dẫn cài đặt và chạy dự án

Tài liệu này dành cho thành viên mới vừa `pull` mã nguồn dự án. Các bước dưới đây
thiết lập PostgreSQL trên Windows, tạo cơ sở dữ liệu, chạy lược đồ SQL và sinh dữ liệu mẫu.

## 1. Yêu cầu

- Windows 10/11.
- [PostgreSQL](https://www.postgresql.org/download/windows/) 16 trở lên, cài kèm **pgAdmin 4**.
- Python 3.10 trở lên (chọn **Add Python to PATH** khi cài).
- Mã nguồn dự án đã được clone/pull về máy.

Trong lúc cài PostgreSQL, hãy nhớ mật khẩu đặt cho tài khoản `postgres`. Ví dụ trong
tài liệu dùng PostgreSQL 18; nếu bạn cài phiên bản khác, thay `18` trong đường dẫn lệnh
bằng phiên bản của bạn.

## 2. Mở terminal tại thư mục dự án

Có thể dùng **Command Prompt (cmd)** hoặc **PowerShell**. Mở terminal rồi đi đến thư
mục dự án (đổi đường dẫn nếu bạn clone ở nơi khác):

```cmd
cd /d C:\CSDLnangcao\CSDLNC-Nhom13-van-chuyen-buu-kien
```

Nếu dòng lệnh có dạng `C:\...>` thì đó là cmd. Nếu có dạng `PS C:\...>` thì đó là PowerShell.

> Các lệnh bên dưới dùng đường dẫn đầy đủ đến `psql.exe`, nên chạy được trong cả cmd và PowerShell.

## 3. Tạo database

Mở PostgreSQL command line và nhập mật khẩu của tài khoản `postgres` khi được hỏi:

```cmd
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -h localhost -p 5432 -U postgres -d postgres
```

Khi thấy dấu nhắc `postgres=#`, chạy:

```sql
CREATE DATABASE "CSDLNC_DeTai13";
\q
```

Lệnh `\q` sẽ thoát khỏi PostgreSQL command line.

Nếu database đã tồn tại, PostgreSQL sẽ báo lỗi `database ... already exists`; đây không phải lỗi nghiêm trọng, hãy bỏ qua phần tạo database và chạy tiếp phần sau.

## 4. Chạy lược đồ và trigger

Ở terminal, tại thư mục gốc của dự án, chạy **đúng thứ tự**:

```cmd
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -h localhost -p 5432 -U postgres -d CSDLNC_DeTai13 -f sql\01_init_schemas.sql

"C:\Program Files\PostgreSQL\18\bin\psql.exe" -h localhost -p 5432 -U postgres -d CSDLNC_DeTai13 -f sql\02_triggers_functions.sql
```

- `01_init_schemas.sql` tạo hai schema `pa_a`, `pa_b`, bảng và các ràng buộc.
- `02_triggers_functions.sql` tạo function/trigger tự đồng bộ trạng thái hiện tại cho `pa_b`.

`01_init_schemas.sql` chỉ chạy trên database mới. Nếu chạy lại, lỗi dạng `relation already exists` nghĩa là bảng đã có sẵn. Muốn làm lại từ đầu, xóa database trong pgAdmin rồi tạo lại database và thực hiện lại từ bước 3.

## 5. Cấu hình và chạy chương trình sinh dữ liệu

Mở file `scripts\generate_data.py` và thay giá trị `your_password` trong `DB_CONFIG` bằng mật khẩu PostgreSQL của bạn:

```python
DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "database": "CSDLNC_DeTai13",
    "user": "postgres",
    "password": "MAT_KHAU_POSTGRES_CUA_BAN"
}
```

Cài thư viện cần thiết và chạy chương trình:

```cmd
python -m pip install -r requirements.txt
python scripts\generate_data.py
```

Chương trình sẽ tạo dữ liệu mồi, 10.000 bưu kiện và 100.000 sự kiện cho cả `pa_a` và `pa_b`.

> Không commit mật khẩu thật lên Git. Trước khi commit, hãy đổi lại mật khẩu trong file về `your_password`, hoặc dùng cấu hình biến môi trường ở một thay đổi riêng sau này.

## 6. Kiểm tra kết quả

Kết nối vào database:

```cmd
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -h localhost -p 5432 -U postgres -d CSDLNC_DeTai13
```

Sau đó chạy các câu lệnh SQL sau:

```sql
\dn
\dt pa_a.*
\dt pa_b.*

SELECT COUNT(*) AS so_buu_kien FROM pa_a.BuuKien;
SELECT COUNT(*) AS so_su_kien FROM pa_a.SuKienTrangThai;
\q
```

Kết quả mong đợi sau khi sinh dữ liệu: `so_buu_kien` là 10000 và `so_su_kien` là 100000.

## 7. Chạy các truy vấn nâng cao, Benchmark và Giao dịch

Sau khi đã sinh dữ liệu ở bước 5, có thể chạy tiếp các kịch bản thực nghiệm trong thư mục `sql\`:

- `sql\SqlAdvance.sql`: 5 câu truy vấn SQL nâng cao (Window Functions, CTE, `WITH RECURSIVE`, `ROLLUP`).
- `sql\benchmark.explain.sql`: Kịch bản đo hiệu năng đối sánh `pa_a` và `pa_b` bằng `EXPLAIN (ANALYZE, BUFFERS)`.
- `sql\transaction_concurrency.sql`: Kịch bản benchmark đầy đủ kèm kiểm thử giao dịch (Transaction, Savepoint, xử lý đồng thời / khóa bi quan `FOR UPDATE`).

Chạy bằng terminal:

```cmd
"C:\Program Files\PostgreSQL\18\bin\psql.exe" -h localhost -p 5432 -U postgres -d CSDLNC_DeTai13 -f sql\SqlAdvance.sql

"C:\Program Files\PostgreSQL\18\bin\psql.exe" -h localhost -p 5432 -U postgres -d CSDLNC_DeTai13 -f sql\benchmark.explain.sql
```

> Với `sql\transaction_concurrency.sql`, khuyến khích mở trong **pgAdmin 4 Query Tool** và bôi đen chạy từng phân đoạn (đặc biệt ở phần mô phỏng 2 phiên giao dịch đồng thời Session A và Session B).

## 8. Dùng pgAdmin 4 thay cho terminal

1. Mở **pgAdmin 4** và nhập mật khẩu master password nếu ứng dụng yêu cầu.
2. Chuột phải **Servers** > **Register** > **Server**.
3. Tab **General**: đặt tên tùy ý, ví dụ `PostgreSQL Local`.
4. Tab **Connection**: Host `localhost`, Port `5432`, Maintenance database `postgres`, Username `postgres`, Password là mật khẩu lúc cài PostgreSQL.
5. Chuột phải **Databases** > **Create** > **Database**, đặt tên `CSDLNC_DeTai13`.
6. Chọn database vừa tạo > **Tools** > **Query Tool**. Mở lần lượt `sql/01_init_schemas.sql` rồi `sql/02_triggers_functions.sql`; nhấn nút Execute (hình tam giác) cho từng file.

Phần sinh dữ liệu vẫn chạy bằng lệnh Python ở bước 5.

## 9. Lỗi thường gặp

| Hiện tượng | Cách xử lý |
| --- | --- |
| `'psql' is not recognized` | Dùng nguyên đường dẫn đầy đủ `"C:\Program Files\PostgreSQL\18\bin\psql.exe"` như các lệnh trên. |
| `connection refused` | Mở **Services** trên Windows và khởi động dịch vụ có tên `postgresql-x64-18` (hoặc phiên bản tương ứng). |
| `password authentication failed` | Kiểm tra lại mật khẩu của tài khoản `postgres`; không phải mật khẩu pgAdmin master password. |
| `database "CSDLNC_DeTai13" does not exist` | Làm lại bước 3 để tạo database. |
| `ModuleNotFoundError: No module named 'psycopg2'` | Chạy `python -m pip install psycopg2-binary`. |
| `relation already exists` khi chạy file 01 | Database đã có bảng. Không chạy lại file 01 trên cùng database. |

