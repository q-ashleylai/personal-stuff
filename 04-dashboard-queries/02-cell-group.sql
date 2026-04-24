-- ============================================================
-- Dashboard Queries: Pillar 2 — Cell Group
-- Connect to: sem schema
-- ============================================================

-- --------------------------
-- Weekly CG Attendance [All Congregations]
-- --------------------------
SELECT
    d.year,
    d.week_of_year,
    MIN(d.full_date) AS week_start,
    SUM(f.attended) AS total_attended,
    COUNT(*) AS total_records,
    ROUND(SUM(f.attended) * 100.0 / NULLIF(COUNT(*), 0), 1) AS attendance_rate_pct
FROM sem.fact_cg_attendance f
JOIN sem.dim_date d ON f.date_key = d.date_key
GROUP BY d.year, d.week_of_year
ORDER BY d.year, d.week_of_year;


-- --------------------------
-- CG Health Analysis by Congregation
-- --------------------------
SELECT
    dc.congregation_label,
    d.year,
    d.month,
    SUM(f.attended) AS total_attended,
    COUNT(*) AS total_records,
    ROUND(SUM(f.attended) * 100.0 / NULLIF(COUNT(*), 0), 1) AS attendance_rate_pct,
    COUNT(*) FILTER (WHERE f.user_role = 'visitor') AS visitor_count,
    COUNT(*) FILTER (WHERE f.user_role = 'leader') AS leader_visits
FROM sem.fact_cg_attendance f
JOIN sem.dim_cell_group cg ON f.cg_key = cg.cg_key
JOIN sem.dim_congregation dc ON cg.congregation_key = dc.congregation_key
JOIN sem.dim_date d ON f.date_key = d.date_key
GROUP BY dc.congregation_label, d.year, d.month
ORDER BY dc.congregation_label, d.year, d.month;


-- --------------------------
-- Weekly CG Attendance by Zone
-- --------------------------
SELECT
    cg.zone,
    d.year,
    d.week_of_year,
    SUM(f.attended) AS total_attended,
    COUNT(*) AS total_records
FROM sem.fact_cg_attendance f
JOIN sem.dim_cell_group cg ON f.cg_key = cg.cg_key
JOIN sem.dim_date d ON f.date_key = d.date_key
WHERE f.attended = 1
GROUP BY cg.zone, d.year, d.week_of_year
ORDER BY cg.zone, d.year, d.week_of_year;


-- --------------------------
-- Average CG Attendance by Zone
-- --------------------------
SELECT
    cg.zone,
    ROUND(AVG(weekly_attended), 1) AS avg_weekly_attendance
FROM (
    SELECT
        cg.zone,
        d.year,
        d.week_of_year,
        SUM(f.attended) AS weekly_attended
    FROM sem.fact_cg_attendance f
    JOIN sem.dim_cell_group cg ON f.cg_key = cg.cg_key
    JOIN sem.dim_date d ON f.date_key = d.date_key
    GROUP BY cg.zone, d.year, d.week_of_year
) weekly
JOIN sem.dim_cell_group cg ON TRUE
GROUP BY cg.zone
ORDER BY cg.zone;


-- --------------------------
-- Weekly CG Attendance Rate by CG
-- --------------------------
SELECT
    cg.cg_name,
    cg.zone,
    d.year,
    d.week_of_year,
    SUM(f.attended) AS attended,
    COUNT(*) AS total_members,
    ROUND(SUM(f.attended) * 100.0 / NULLIF(COUNT(*), 0), 1) AS attendance_rate_pct
FROM sem.fact_cg_attendance f
JOIN sem.dim_cell_group cg ON f.cg_key = cg.cg_key
JOIN sem.dim_date d ON f.date_key = d.date_key
GROUP BY cg.cg_name, cg.zone, d.year, d.week_of_year
ORDER BY cg.zone, cg.cg_name, d.year, d.week_of_year;


-- --------------------------
-- CG Submission Rate
-- --------------------------
SELECT
    dc.congregation_label,
    d.year,
    d.week_of_year,
    SUM(f.submitted) AS submitted_count,
    COUNT(*) AS total_events,
    ROUND(SUM(f.submitted) * 100.0 / NULLIF(COUNT(*), 0), 1) AS submission_rate_pct
FROM sem.fact_cg_submission f
JOIN sem.dim_cell_group cg ON f.cg_key = cg.cg_key
JOIN sem.dim_congregation dc ON cg.congregation_key = dc.congregation_key
JOIN sem.dim_date d ON f.date_key = d.date_key
WHERE f.cancelled = 0
GROUP BY dc.congregation_label, d.year, d.week_of_year
ORDER BY dc.congregation_label, d.year, d.week_of_year;


-- --------------------------
-- Non-submission of CG Attendance
-- --------------------------
SELECT
    cg.cg_name,
    cg.zone,
    dc.congregation_label,
    d.full_date AS event_date
FROM sem.fact_cg_submission f
JOIN sem.dim_cell_group cg ON f.cg_key = cg.cg_key
JOIN sem.dim_congregation dc ON cg.congregation_key = dc.congregation_key
JOIN sem.dim_date d ON f.date_key = d.date_key
WHERE f.submitted = 0
  AND f.cancelled = 0
ORDER BY d.full_date DESC, cg.zone, cg.cg_name;


-- --------------------------
-- Pastor Attendance Analysis
-- --------------------------
SELECT
    dm.full_name,
    dm.user_role,
    cg.cg_name,
    cg.zone,
    d.year,
    d.week_of_year,
    SUM(f.attended) AS times_attended
FROM sem.fact_cg_attendance f
JOIN sem.dim_member dm ON f.member_key = dm.member_key
JOIN sem.dim_cell_group cg ON f.cg_key = cg.cg_key
JOIN sem.dim_date d ON f.date_key = d.date_key
WHERE f.user_role = 'leader'
  AND dm.user_role LIKE '%Pastor%'
GROUP BY dm.full_name, dm.user_role, cg.cg_name, cg.zone, d.year, d.week_of_year
ORDER BY d.year, d.week_of_year, cg.zone;


-- --------------------------
-- Zone Leader CG Attendance Analysis
-- --------------------------
SELECT
    dm.full_name,
    cg.cg_name,
    cg.zone,
    d.year,
    d.week_of_year,
    SUM(f.attended) AS times_visited
FROM sem.fact_cg_attendance f
JOIN sem.dim_member dm ON f.member_key = dm.member_key
JOIN sem.dim_cell_group cg ON f.cg_key = cg.cg_key
JOIN sem.dim_date d ON f.date_key = d.date_key
WHERE f.user_role = 'visitor'
  AND dm.user_role LIKE '%Zone Leader%'
GROUP BY dm.full_name, cg.cg_name, cg.zone, d.year, d.week_of_year
ORDER BY d.year, d.week_of_year, cg.zone;


-- --------------------------
-- Weekly Count of Active CG Sessions
-- --------------------------
SELECT
    d.year,
    d.week_of_year,
    COUNT(*) FILTER (WHERE f.cancelled = 0) AS active_sessions,
    COUNT(*) FILTER (WHERE f.cancelled = 1) AS cancelled_sessions
FROM sem.fact_cg_submission f
JOIN sem.dim_date d ON f.date_key = d.date_key
GROUP BY d.year, d.week_of_year
ORDER BY d.year, d.week_of_year;
