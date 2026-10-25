-- Kịch bản pgbench: ghi sự kiện đồng thời, CÓ trùng và đến muộn.
-- Mỗi giao dịch gọi <schema>.ghi_su_kien() cho cặp (bưu kiện b, bước k):
--   * nội dung sự kiện được xác định hoàn toàn bởi (b, k) => cùng (b, k) là GỬI TRÙNG THẬT
--   * k chọn ngẫu nhiên, nên sự kiện đến sai thứ tự => ĐẾN MUỘN
--   * nhiều client cùng chọn trúng 1 bưu kiện (giảm -D n) => CẬP NHẬT ĐỒNG THỜI
-- Tham số: -D sch=pa_a | pa_b   -D n=<số bưu kiện được chọn, tối đa = n_buu_kien của seed>
\set b random(1, :n)
\set k random(1, 8)
SELECT :sch.ghi_su_kien(
    :b,
    (ARRAY['TIEP_NHAN','DEN_KHO','DANG_VAN_CHUYEN','DEN_KHO',
        'DANG_VAN_CHUYEN','DANG_GIAO','GIAO_THAT_BAI','DA_GIAO'])[:k]::core.trang_thai_buu_kien,
    timestamptz '2026-11-01 00:00:00+07' + :k * interval '1 hour',
    'bench-' || :b || '-' || :k);