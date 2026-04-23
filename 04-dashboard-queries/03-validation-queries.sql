-- ============================================================
-- Validation Queries
-- Run these after ETL to verify data accuracy
-- Compare analytics layer against raw layer
-- ============================================================

-- --------------------------
-- 1. Row count comparison: attendance
-- --------------------------
SELECT 'raw.attendance_records' AS source, COUNT(*) AS row_count
FROM raw.attendance_records
UNION ALL
SELECT 'analytics.fact_attendance', COUNT(*)
FROM analytics.fact_attendance;


-- --------------------------
-- 2. Row count comparison: members
-- --------------------------
SELECT 'raw.members' AS source, COUNT(*) AS row_count
FROM raw.members
UNION ALL
SELECT 'analytics.dim_member', COUNT(*)
FROM analytics.dim_member;


-- --------------------------
-- 3. Attendance totals should match (current month)
-- --------------------------
SELECT 'raw' AS source, COUNT(*) AS attendance_count
FROM raw.attendance_records ar
JOIN raw.congregations c ON ar.congregation_id = c.congregation_id
WHERE c.congregation_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
  AND c.congregation_date <  DATE_ADD(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL 1 MONTH)
UNION ALL
SELECT 'analytics', SUM(attendance_count)
FROM analytics.fact_attendance f
JOIN analytics.dim_date d ON f.date_key = d.date_key
WHERE d.year = YEAR(CURDATE())
  AND d.month = MONTH(CURDATE());


-- --------------------------
-- 4. Check for orphaned fact records (no matching dimension)
-- --------------------------
SELECT 'fact_attendance: missing date_key' AS check_name, COUNT(*) AS orphan_count
FROM analytics.fact_attendance f
LEFT JOIN analytics.dim_date d ON f.date_key = d.date_key
WHERE d.date_key IS NULL
UNION ALL
SELECT 'fact_attendance: missing member_key', COUNT(*)
FROM analytics.fact_attendance f
LEFT JOIN analytics.dim_member d ON f.member_key = d.member_key
WHERE d.member_key IS NULL
UNION ALL
SELECT 'fact_attendance: missing congregation_key', COUNT(*)
FROM analytics.fact_attendance f
LEFT JOIN analytics.dim_congregation d ON f.congregation_key = d.congregation_key
WHERE d.congregation_key IS NULL;


-- --------------------------
-- 5. Engagement score sanity check
-- --------------------------
SELECT
    engagement_tier,
    COUNT(*)            AS member_count,
    MIN(engagement_score) AS min_score,
    MAX(engagement_score) AS max_score,
    AVG(engagement_score) AS avg_score
FROM analytics.fact_member_engagement
WHERE snapshot_month = DATE_FORMAT(CURDATE(), '%Y-%m-01')
GROUP BY engagement_tier;
