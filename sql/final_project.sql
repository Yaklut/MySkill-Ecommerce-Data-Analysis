-- =====================================================================
-- Final Project SQL - Tokopaedi (Kelompok C1) - versi BigQuery (GoogleSQL)
-- Project : finpro-514510-t3
-- Dataset : dataset
-- Semua tabel ditulis lengkap: `finpro-514510-t3.dataset.nama_tabel`
-- (backtick wajib karena project id mengandung tanda "-").
--
-- Aturan tanggal di file ini: filter pakai EXTRACT(YEAR FROM kolom_tanggal).
-- Cara ini aman untuk kolom bertipe DATE, DATETIME maupun TIMESTAMP, dan
-- tidak membuang transaksi 31 Desember seperti BETWEEN '...-12-31'.
-- Jika kolom tanggalmu bertipe STRING, ubah dulu dengan SAFE_CAST(... AS TIMESTAMP).
-- Jika is_valid terbaca sebagai BOOL (bukan 0/1), ganti "is_valid = 1" jadi "is_valid".
-- =====================================================================


-- =====================================================================
-- SOAL 1 - Total sales per bulan 2024 (transaction_detail.total_paid)
-- =====================================================================
SELECT
  EXTRACT(MONTH FROM t.transaction_date) AS bulan,
  CAST(ROUND(SUM(t.total_paid)) AS INT64) AS total_sales
FROM `finpro-514510-t3.dataset.transaction_detail` AS t
WHERE EXTRACT(YEAR FROM t.transaction_date) = 2024
GROUP BY bulan
ORDER BY bulan;
-- Hasil terverifikasi: Desember = Rp4.116.290.940 (17,7% dari total 2024).


-- =====================================================================
-- SOAL 2 - Volume terjual per kategori per tahun 2020-2024
-- "Terjual" = transaksi sudah dibayar -> is_valid = 1
-- =====================================================================
SELECT
  p.category,
  SUM(IF(EXTRACT(YEAR FROM o.order_date) = 2020, o.quantity, 0)) AS qty_2020,
  SUM(IF(EXTRACT(YEAR FROM o.order_date) = 2021, o.quantity, 0)) AS qty_2021,
  SUM(IF(EXTRACT(YEAR FROM o.order_date) = 2022, o.quantity, 0)) AS qty_2022,
  SUM(IF(EXTRACT(YEAR FROM o.order_date) = 2023, o.quantity, 0)) AS qty_2023,
  SUM(IF(EXTRACT(YEAR FROM o.order_date) = 2024, o.quantity, 0)) AS qty_2024
FROM `finpro-514510-t3.dataset.order_detail`   AS o
JOIN `finpro-514510-t3.dataset.product_detail` AS p
  ON p.sku_id = o.sku_id
WHERE o.is_valid = 1
  AND EXTRACT(YEAR FROM o.order_date) BETWEEN 2020 AND 2024
GROUP BY p.category
ORDER BY qty_2024 DESC;
-- Hasil terverifikasi: Fashion & Footwear 2024 = 5.143, Food & Beverage 2024 = 4.973.
-- Total tahunan: 2023 terendah, naik 18,6% di 2024.


-- =====================================================================
-- SOAL 3 - Orders & revenue per channel per bulan 2024,
--          pertumbuhan revenue vs bulan yang sama di 2023
-- Ini year-over-year per bulan (bukan MoM), maka kolom bernama yoy_growth_pct.
-- SAFE_DIVIDE mengembalikan NULL (bukan error) jika pembagi 0.
-- =====================================================================
WITH monthly AS (
  SELECT
    channel_type,
    EXTRACT(YEAR  FROM order_date) AS yr,
    EXTRACT(MONTH FROM order_date) AS bulan,
    COUNT(DISTINCT order_id)       AS total_orders,
    SUM(after_discount)            AS revenue
  FROM `finpro-514510-t3.dataset.order_detail`
  WHERE is_valid = 1
    AND EXTRACT(YEAR FROM order_date) IN (2023, 2024)
  GROUP BY channel_type, yr, bulan
)
SELECT
  c.channel_type,
  c.bulan,
  c.total_orders AS orders_2024,
  c.revenue      AS revenue_2024,
  p.revenue      AS revenue_2023,
  ROUND(100 * SAFE_DIVIDE(c.revenue - p.revenue, p.revenue), 2) AS yoy_growth_pct
FROM monthly AS c
LEFT JOIN monthly AS p
  ON  p.channel_type = c.channel_type
  AND p.bulan        = c.bulan
  AND p.yr           = 2023
WHERE c.yr = 2024
ORDER BY c.channel_type, c.bulan;
-- Hasil terverifikasi (48 baris), contoh: App Store Januari = 95 order,
-- Rp397.890.503, growth -21,69%.


-- =====================================================================
-- SOAL 4 - Funnel conversion event "Organic" 2024 per channel_source
-- NULLIF(order_id, '') mencegah string kosong ikut dihitung sebagai 1 order.
-- Jika ingin tampil dengan tanda persen seperti di slide, bungkus kolom
-- terakhir dengan CONCAT(CAST(... AS STRING), '%').
-- =====================================================================
SELECT
  channel_source,
  COUNT(*)                             AS total_events,
  COUNT(DISTINCT NULLIF(order_id, '')) AS total_orders,
  ROUND(100 * SAFE_DIVIDE(COUNT(DISTINCT NULLIF(order_id, '')), COUNT(*)), 2) AS conversion_rate_pct
FROM `finpro-514510-t3.dataset.funnel_detail`
WHERE event = 'Organic'
  AND EXTRACT(YEAR FROM funnel_date) = 2024
GROUP BY channel_source
ORDER BY total_events DESC;
-- Hasil pada data penuh (dijalankan di BigQuery): Website 29.062 / 627 / 2,16%;
-- App Store 27.717 / 611 / 2,20%; Play Store 26.165 / 579 / 2,21%.
-- Angka di slide lama (28.976 / 27.676 / 26.128 event) sedikit lebih rendah karena
-- BETWEEN '2024-01-01' AND '2024-12-31' membuang event 31 Desember 2024.


-- =====================================================================
-- SOAL 5 - Pelanggan baru 2024 per bulan & per registration_channel,
--          rata-rata hari dari registrasi ke transaksi pertama
-- Hanya pelanggan yang punya minimal satu transaksi (JOIN, bukan LEFT JOIN).
-- Jika "pembelian" ditafsirkan sebagai transaksi yang sudah dibayar,
-- tambahkan  WHERE is_valid = 1  di CTE first_purchase (total jadi
-- Mobile App 76, Offline Store 42, Website 63; urutan channel tetap sama).
-- Jika di tabelmu kolomnya bernama registered_date, ganti registration_date.
-- =====================================================================
WITH first_purchase AS (
  SELECT
    customer_id,
    MIN(CAST(order_date AS DATE)) AS first_order_date
  FROM `finpro-514510-t3.dataset.order_detail`
  GROUP BY customer_id
)
SELECT
  EXTRACT(MONTH FROM c.registration_date) AS bulan,
  c.registration_channel,
  COUNT(DISTINCT c.customer_id)           AS new_customers,
  ROUND(AVG(DATE_DIFF(f.first_order_date, CAST(c.registration_date AS DATE), DAY)), 1)
                                          AS avg_days_to_first_purchase
FROM `finpro-514510-t3.dataset.customer_detail` AS c
JOIN first_purchase AS f
  ON f.customer_id = c.customer_id
WHERE EXTRACT(YEAR FROM c.registration_date) = 2024
GROUP BY bulan, c.registration_channel
ORDER BY bulan, c.registration_channel;
-- Hasil terverifikasi: total pelanggan baru Mobile App 80, Website 63,
-- Offline Store 44. Offline Mei = 145 hari tetapi dari 1 pelanggan saja.
