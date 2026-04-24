-- ============================================================
-- Dashboard Queries: Pillar 5 — Celebration
-- Connect to: sem schema
-- ============================================================

-- --------------------------
-- Celebration Attendance by Kind (Regular/Guest/Volunteer)
-- --------------------------
SELECT
    dc.congregation_label,
    d.year,
    d.week_of_year,
    SUM(CASE WHEN f.kind = 'Regular' THEN 1 ELSE 0 END) AS regular_count,
    SUM(CASE WHEN f.kind = 'Guest' THEN 1 ELSE 0 END) AS guest_count,
    SUM(CASE WHEN f.kind = 'Volunteer' THEN 1 ELSE 0 END) AS volunteer_count,
    COUNT(*) AS total_checkins
FROM sem.fact_celebration_attendance f
JOIN sem.dim_congregation dc ON f.congregation_key = dc.congregation_key
JOIN sem.dim_date d ON f.date_key = d.date_key
GROUP BY dc.congregation_label, d.year, d.week_of_year
ORDER BY dc.congregation_label, d.year, d.week_of_year;


-- --------------------------
-- Celebration Attendance by Congregation
-- --------------------------
SELECT
    dc.congregation_label,
    d.year,
    d.month,
    COUNT(*) AS total_checkins,
    COUNT(DISTINCT f.member_key) AS unique_attendees
FROM sem.fact_celebration_attendance f
JOIN sem.dim_congregation dc ON f.congregation_key = dc.congregation_key
JOIN sem.dim_date d ON f.date_key = d.date_key
GROUP BY dc.congregation_label, d.year, d.month
ORDER BY dc.congregation_label, d.year, d.month;


-- --------------------------
-- Week-over-Week % Change
-- --------------------------
WITH weekly AS (
    SELECT
        d.year,
        d.week_of_year,
        COUNT(*) AS headcount
    FROM sem.fact_celebration_attendance f
    JOIN sem.dim_date d ON f.date_key = d.date_key
    GROUP BY d.year, d.week_of_year
)
SELECT
    curr.year,
    curr.week_of_year,
    curr.headcount AS current_week,
    prev.headcount AS previous_week,
    ROUND(
        (curr.headcount - prev.headcount) * 100.0
        / NULLIF(prev.headcount, 0), 1
    ) AS wow_change_pct
FROM weekly curr
LEFT JOIN weekly prev
    ON (curr.year = prev.year AND curr.week_of_year = prev.week_of_year + 1)
    OR (curr.week_of_year = 1 AND prev.year = curr.year - 1
        AND prev.week_of_year = (SELECT MAX(week_of_year) FROM weekly WHERE year = curr.year - 1))
ORDER BY curr.year, curr.week_of_year;


-- --------------------------
-- NXG / Activities Attendance
-- --------------------------
SELECT
    f.service_name,
    d.year,
    d.month,
    COUNT(*) AS total_checkins,
    COUNT(DISTINCT f.member_key) AS unique_attendees
FROM sem.fact_celebration_attendance f
JOIN sem.dim_date d ON f.date_key = d.date_key
WHERE f.congregation_key = 8  -- NXG
GROUP BY f.service_name, d.year, d.month
ORDER BY d.year, d.month, f.service_name;
