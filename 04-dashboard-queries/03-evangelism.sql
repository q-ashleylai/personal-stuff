-- ============================================================
-- Dashboard Queries: Pillar 3 — Evangelism
-- Connect to: sem schema
-- ============================================================

-- --------------------------
-- DUMC Decisions Churchwide
-- --------------------------
SELECT
    d.year,
    d.month,
    d.month_name,
    COUNT(*) AS total_decisions
FROM sem.fact_decisions f
JOIN sem.dim_date d ON f.date_key = d.date_key
GROUP BY d.year, d.month, d.month_name
ORDER BY d.year, d.month;


-- --------------------------
-- Decisions by Congregation
-- --------------------------
SELECT
    dc.congregation_label,
    d.year,
    d.month,
    COUNT(*) AS total_decisions
FROM sem.fact_decisions f
JOIN sem.dim_congregation dc ON f.congregation_key = dc.congregation_key
JOIN sem.dim_date d ON f.date_key = d.date_key
GROUP BY dc.congregation_label, d.year, d.month
ORDER BY dc.congregation_label, d.year, d.month;


-- --------------------------
-- Decision Form Breakdown: Outside (112029) vs Online (117917)
-- --------------------------
SELECT
    d.year,
    f.form_id,
    f.form_title,
    COUNT(*) AS total_decisions
FROM sem.fact_decisions f
JOIN sem.dim_date d ON f.date_key = d.date_key
GROUP BY d.year, f.form_id, f.form_title
ORDER BY d.year, f.form_id;


-- --------------------------
-- Baptisms by Congregation
-- --------------------------
SELECT
    dc.congregation_label,
    COUNT(*) AS baptized_count
FROM sem.dim_member dm
JOIN sem.dim_congregation dc ON dm.congregation_key = dc.congregation_key
WHERE dm.is_baptized = TRUE
  AND dm.user_status = 'active'
GROUP BY dc.congregation_label
ORDER BY dc.congregation_label;


-- --------------------------
-- D101 Completions
-- --------------------------
SELECT
    d.year,
    d.month,
    f.status,
    COUNT(*) AS participant_count
FROM sem.fact_discipleship f
JOIN sem.dim_date d ON f.started_date_key = d.date_key
GROUP BY d.year, d.month, f.status
ORDER BY d.year, d.month, f.status;


-- --------------------------
-- D101 Completed vs In Progress
-- --------------------------
SELECT
    f.status,
    COUNT(*) AS total
FROM sem.fact_discipleship f
GROUP BY f.status;
