-- ============================================================
-- Validation Queries
-- Run after ETL to verify data accuracy
-- Compare sem layer against raw layer
-- ============================================================

-- --------------------------
-- 1. Row count checks across layers
-- --------------------------
SELECT 'raw.pco_users' AS source, COUNT(*) AS row_count FROM raw.pco_users
UNION ALL
SELECT 'sem.dim_member', COUNT(*) FROM sem.dim_member
UNION ALL
SELECT 'raw.pco_groups (CG)', COUNT(*) FROM raw.pco_groups WHERE grp_type_key = 137505
UNION ALL
SELECT 'sem.dim_cell_group', COUNT(*) FROM sem.dim_cell_group
UNION ALL
SELECT 'raw.pco_new_decisions', COUNT(*) FROM raw.pco_new_decisions
UNION ALL
SELECT 'sem.fact_decisions', COUNT(*) FROM sem.fact_decisions
UNION ALL
SELECT 'raw.pco_discipleship_completion', COUNT(*) FROM raw.pco_discipleship_completion
UNION ALL
SELECT 'sem.fact_discipleship', COUNT(*) FROM sem.fact_discipleship
UNION ALL
SELECT 'raw.pco_checkin_attendance', COUNT(*) FROM raw.pco_checkin_attendance
UNION ALL
SELECT 'sem.fact_celebration_attendance', COUNT(*) FROM sem.fact_celebration_attendance
UNION ALL
SELECT 'raw.pco_serving_attendance', COUNT(*) FROM raw.pco_serving_attendance
UNION ALL
SELECT 'sem.fact_serving', COUNT(*) FROM sem.fact_serving;


-- --------------------------
-- 2. Orphan detection: fact records missing dimension keys
-- --------------------------
SELECT 'fact_cg_attendance: missing date_key' AS check_name, COUNT(*) AS orphan_count
FROM sem.fact_cg_attendance f
LEFT JOIN sem.dim_date d ON f.date_key = d.date_key
WHERE d.date_key IS NULL
UNION ALL
SELECT 'fact_cg_attendance: missing member_key', COUNT(*)
FROM sem.fact_cg_attendance f
LEFT JOIN sem.dim_member dm ON f.member_key = dm.member_key
WHERE dm.member_key IS NULL
UNION ALL
SELECT 'fact_cg_attendance: missing cg_key', COUNT(*)
FROM sem.fact_cg_attendance f
LEFT JOIN sem.dim_cell_group cg ON f.cg_key = cg.cg_key
WHERE cg.cg_key IS NULL
UNION ALL
SELECT 'fact_decisions: missing member_key', COUNT(*)
FROM sem.fact_decisions f
LEFT JOIN sem.dim_member dm ON f.member_key = dm.member_key
WHERE f.member_key IS NOT NULL AND dm.member_key IS NULL
UNION ALL
SELECT 'fact_celebration_attendance: missing member_key', COUNT(*)
FROM sem.fact_celebration_attendance f
LEFT JOIN sem.dim_member dm ON f.member_key = dm.member_key
WHERE f.member_key IS NOT NULL AND dm.member_key IS NULL
UNION ALL
SELECT 'fact_serving: missing member_key', COUNT(*)
FROM sem.fact_serving f
LEFT JOIN sem.dim_member dm ON f.member_key = dm.member_key
WHERE f.member_key IS NOT NULL AND dm.member_key IS NULL;


-- --------------------------
-- 3. Congregation distribution sanity check
-- --------------------------
SELECT
    dc.congregation_label,
    COUNT(*) AS member_count
FROM sem.dim_member dm
LEFT JOIN sem.dim_congregation dc ON dm.congregation_key = dc.congregation_key
WHERE dm.user_status = 'active'
GROUP BY dc.congregation_label
ORDER BY member_count DESC;


-- --------------------------
-- 4. CG attendance raw vs sem reconciliation
-- --------------------------
SELECT
    'raw CG attendance records' AS source,
    COUNT(*) AS row_count
FROM raw.pco_attendance a
JOIN raw.pco_events e ON a.att_event_key = e.event_id
JOIN raw.pco_groups g ON e.event_group_key = g.grp_id
WHERE g.grp_type_key = 137505
UNION ALL
SELECT
    'sem.fact_cg_attendance',
    COUNT(*)
FROM sem.fact_cg_attendance;
