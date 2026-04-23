-- ============================================================
-- ETL Node 1: dim_date
-- Populates date dimension for time-based slicing
-- Schedule: Run once to seed, then daily append for new dates
-- Dependencies: None
-- ============================================================

INSERT IGNORE INTO analytics.dim_date
SELECT
    CAST(DATE_FORMAT(d.date_val, '%Y%m%d') AS UNSIGNED) AS date_key,
    d.date_val                                           AS full_date,
    YEAR(d.date_val)                                     AS year,
    QUARTER(d.date_val)                                  AS quarter,
    MONTH(d.date_val)                                    AS month,
    MONTHNAME(d.date_val)                                AS month_name,
    WEEK(d.date_val, 1)                                  AS week_of_year,
    DAY(d.date_val)                                      AS day_of_month,
    DAYNAME(d.date_val)                                  AS day_name,
    DAYOFWEEK(d.date_val)                                AS day_of_week,
    CASE
        WHEN DAYOFWEEK(d.date_val) IN (1, 7) THEN 'Weekend'
        ELSE 'Weekday'
    END                                                  AS weekend_flag
FROM (
    -- Recursive CTE to generate date range (MySQL 8.0+)
    WITH RECURSIVE date_series AS (
        SELECT DATE('2020-01-01') AS date_val
        UNION ALL
        SELECT DATE_ADD(date_val, INTERVAL 1 DAY)
        FROM date_series
        WHERE date_val < DATE('2030-12-31')
    )
    SELECT date_val FROM date_series
) d;
