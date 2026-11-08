# CSDLNC-Nhom13-van-chuyen-buu-kien

Đề tài 13: Hệ thống theo dõi vận chuyển và bàn giao bưu kiện (PostgreSQL).

## Cấu trúc thư mục

- `sql/01_init_schemas.sql`: Khởi tạo 2 schema `pa_a` (History-based) và `pa_b` (Current State) cùng các bảng, ràng buộc và chỉ mục.
- `sql/02_triggers_functions.sql`: Trigger và Function tự động đồng bộ trạng thái hiện tại cho `pa_b`.
- `sql/SqlAdvance.sql`: 5 câu truy vấn SQL nâng cao (Window Functions, CTE, Recursive CTE, ROLLUP).
- `sql/benchmark.explain.sql`: Kịch bản đo hiệu năng đối sánh `pa_a` và `pa_b` (`EXPLAIN ANALYZE`).
- `sql/transaction_concurrency.sql`: Kịch bản thực nghiệm giao dịch (Transaction, Savepoint) và xử lý đồng thời.
- `scripts/generate_data.py`: Script Python sinh dữ liệu mẫu (10.000 bưu kiện & 100.000 sự kiện).
- `requirements.txt`: Thư viện Python cần thiết (`psycopg2-binary`).

## Hướng dẫn cài đặt và chạy

Xem chi tiết từng bước tại: [docs/huong-dan-cai-dat-va-chay.md](docs/huong-dan-cai-dat-va-chay.md).
