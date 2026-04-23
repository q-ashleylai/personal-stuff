-- ============================================================
-- Dashboard Query: Attendance Trends
-- For use in Power BI / QuickBI / other BI tool
-- Connect to: analytics schema
-- ============================================================

-- --------------------------
-- Weekly attendance trend (last 12 weeks) — English congregation
-- --------------------------
SELECT
    d.year,
    d.week_of_year,
    MIN(d.full_date)   AS week_start,
    COUNT(*)           AS total_attendance
FROM analytics.fact_attendance f
JOIN analytics.dim_date d ON f.date_key = d.date_key
WHERE d.full_date >= DATE_SUB(CURDATE(), INTERVAL 12 WEEK)
  AND f.congregation_type = 'english'
GROUP BY d.year, d.week_of_year
ORDER BY d.year, d.week_of_year;


-- --------------------------
-- Monthly attendance trend (last 12 months) — all congregations
-- --------------------------
SELECT
    d.year,
    d.month,
    d.month_name,
    COUNT(*)           AS total_attendance,
    COUNT(DISTINCT f.member_key) AS unique_attendees
FROM analytics.fact_attendance f
JOIN analytics.dim_date d ON f.date_key = d.date_key
WHERE d.full_date >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
GROUP BY d.year, d.month, d.month_name
ORDER BY d.year, d.month;


-- --------------------------
-- Attendance by congregation type / language (current month)
-- --------------------------
SELECT
    f.congregation_type,
    f.language,
    dc.congregation_type_label,
    COUNT(*)                       AS total_attendance,
    COUNT(DISTINCT f.member_key)   AS unique_attendees
FROM analytics.fact_attendance f
JOIN analytics.dim_date d ON f.date_key = d.date_key
JOIN analytics.dim_congregation dc ON f.congregation_key = dc.congregation_key
WHERE d.year = YEAR(CURDATE())
  AND d.month = MONTH(CURDATE())
GROUP BY f.congregation_type, f.language, dc.congregation_type_label
ORDER BY total_attendance DESC;


-- --------------------------
-- Attendance by campus (current month)
-- --------------------------
SELECT
    f.campus,
    COUNT(*)                       AS total_attendance,
    COUNT(DISTINCT f.member_key)   AS unique_attendees
FROM analytics.fact_attendance f
JOIN analytics.dim_date d ON f.date_key = d.date_key
WHERE d.year = YEAR(CURDATE())
  AND d.month = MONTH(CURDATE())
GROUP BY f.campus
ORDER BY total_attendance DESC;


-- --------------------------
-- Year-over-year comparison (English congregation, by month)
-- --------------------------
SELECT
    d.month,
    d.month_name,
    SUM(CASE WHEN d.year = YEAR(CURDATE())     THEN 1 ELSE 0 END) AS this_year,
    SUM(CASE WHEN d.year = YEAR(CURDATE()) - 1 THEN 1 ELSE 0 END) AS last_year
FROM analytics.fact_attendance f
JOIN analytics.dim_date d ON f.date_key = d.date_key
WHERE f.congregation_type = 'english'
  AND d.year IN (YEAR(CURDATE()), YEAR(CURDATE()) - 1)
GROUP BY d.month, d.month_name
ORDER BY d.month;
