-- ============================================================
-- Dashboard Queries: Pillar 7 — Mission
-- Connect to: sem schema + raw layer for group type filtering
-- Source: pco_groups (Initiative type 221572) + pco_attendance
-- ============================================================

-- --------------------------
-- MCPP1 Completion % by Congregation
-- --------------------------
SELECT
    dc.congregation_label,
    COUNT(DISTINCT a.att_user_key) FILTER (WHERE a.att_status = '1') AS mcpp1_completed,
    total.cg_member_count,
    ROUND(
        COUNT(DISTINCT a.att_user_key) FILTER (WHERE a.att_status = '1') * 100.0
        / NULLIF(total.cg_member_count, 0), 1
    ) AS mcpp1_completion_pct
FROM raw.pco_attendance a
JOIN raw.pco_events e ON a.att_event_key = e.event_id
JOIN raw.pco_groups g ON e.event_group_key = g.grp_id
LEFT JOIN sem.dim_member dm ON a.att_user_key = dm.member_key
LEFT JOIN sem.dim_congregation dc ON dm.congregation_key = dc.congregation_key
CROSS JOIN LATERAL (
    SELECT COUNT(DISTINCT member_user_key) AS cg_member_count
    FROM raw.pco_group_membership gm
    JOIN raw.pco_groups cg ON gm.member_grp_key = cg.grp_id
    WHERE cg.grp_type_key = 137505
) total
WHERE g.grp_name ILIKE '%MCPP1%'
GROUP BY dc.congregation_label, total.cg_member_count
ORDER BY dc.congregation_label;


-- --------------------------
-- MCPP2 Completion % by Congregation
-- --------------------------
SELECT
    dc.congregation_label,
    COUNT(DISTINCT a.att_user_key) FILTER (WHERE a.att_status = '1') AS mcpp2_completed,
    total.cg_member_count,
    ROUND(
        COUNT(DISTINCT a.att_user_key) FILTER (WHERE a.att_status = '1') * 100.0
        / NULLIF(total.cg_member_count, 0), 1
    ) AS mcpp2_completion_pct
FROM raw.pco_attendance a
JOIN raw.pco_events e ON a.att_event_key = e.event_id
JOIN raw.pco_groups g ON e.event_group_key = g.grp_id
LEFT JOIN sem.dim_member dm ON a.att_user_key = dm.member_key
LEFT JOIN sem.dim_congregation dc ON dm.congregation_key = dc.congregation_key
CROSS JOIN LATERAL (
    SELECT COUNT(DISTINCT member_user_key) AS cg_member_count
    FROM raw.pco_group_membership gm
    JOIN raw.pco_groups cg ON gm.member_grp_key = cg.grp_id
    WHERE cg.grp_type_key = 137505
) total
WHERE g.grp_name ILIKE '%MCPP2%'
GROUP BY dc.congregation_label, total.cg_member_count
ORDER BY dc.congregation_label;


-- --------------------------
-- Mission Trip Participation
-- --------------------------
SELECT
    g.grp_name AS mission_name,
    dc.congregation_label,
    COUNT(DISTINCT a.att_user_key) AS participant_count
FROM raw.pco_attendance a
JOIN raw.pco_events e ON a.att_event_key = e.event_id
JOIN raw.pco_groups g ON e.event_group_key = g.grp_id
LEFT JOIN sem.dim_member dm ON a.att_user_key = dm.member_key
LEFT JOIN sem.dim_congregation dc ON dm.congregation_key = dc.congregation_key
WHERE a.att_status = '1'
  AND (g.grp_name ILIKE '%mission%' OR g.grp_type_key = 221572)
GROUP BY g.grp_name, dc.congregation_label
ORDER BY participant_count DESC;
