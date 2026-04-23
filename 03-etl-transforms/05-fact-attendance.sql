-- ============================================================
-- ETL Step 5: fact_attendance
-- Incremental load: only new records since last run
-- Dependencies: dim_date, dim_member, dim_congregation
-- ============================================================
-- Use a watermark table to track last_run_timestamp.
-- For first run, set to '1970-01-01 00:00:00' to load all history.

INSERT INTO analytics.fact_attendance
SELECT
    ar.attendance_id,
    CAST(DATE_FORMAT(c.congregation_date, '%Y%m%d') AS UNSIGNED) AS date_key,
    ar.member_id              AS member_key,
    c.congregation_id         AS congregation_key,
    c.congregation_type,
    c.language,
    c.campus,
    ar.check_in_method,
    1                         AS attendance_count
FROM raw.attendance_records ar
JOIN raw.congregations c ON ar.congregation_id = c.congregation_id
WHERE ar.created_at > @last_run_timestamp
  AND ar.attendance_id NOT IN (SELECT attendance_id FROM analytics.fact_attendance);
