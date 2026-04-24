-- ============================================================
-- ETL Step 1: dim_date
-- Populates date dimension for time-based slicing
-- Schedule: Run once to seed, then daily append for new dates
-- Dependencies: None
-- ============================================================

INSERT INTO sem.dim_date
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INTEGER AS date_key,
    d                                AS full_date,
    EXTRACT(YEAR FROM d)::INTEGER    AS year,
    EXTRACT(QUARTER FROM d)::INTEGER AS quarter,
    EXTRACT(MONTH FROM d)::INTEGER   AS month,
    TO_CHAR(d, 'Month')             AS month_name,
    EXTRACT(WEEK FROM d)::INTEGER    AS week_of_year,
    EXTRACT(DAY FROM d)::INTEGER     AS day_of_month,
    TO_CHAR(d, 'Day')               AS day_name,
    EXTRACT(DOW FROM d)::INTEGER     AS day_of_week,
    CASE
        WHEN EXTRACT(DOW FROM d) IN (0, 6) THEN 'Weekend'
        ELSE 'Weekday'
    END                              AS weekend_flag
FROM generate_series('2020-01-01'::DATE, '2030-12-31'::DATE, '1 day') AS d
ON CONFLICT (date_key) DO NOTHING;
