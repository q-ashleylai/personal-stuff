-- ============================================================
-- Dashboard Queries: Pillar 6 — Training
-- Connect to: sem schema
-- Source: pco_groups (grp_type_key = 147987 for Training groups)
--         + pco_attendance for participation tracking
-- Note: Training queries join back to raw layer for group type filtering
-- ============================================================

-- --------------------------
-- Training Engagement %
-- Members who attended Equip/Training class in past year vs total CG members
-- --------------------------
SELECT
    dc.congregation_label,
    COUNT(DISTINCT a.att_user_key) FILTER (WHERE a.att_status = '1') AS training_attendees,
    total.cg_member_count,
    ROUND(
        COUNT(DISTINCT a.att_user_key) FILTER (WHERE a.att_status = '1') * 100.0
        / NULLIF(total.cg_member_count, 0), 1
    ) AS training_engagement_pct
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
WHERE g.grp_type_key = 147987  -- Training groups
  AND e.event_startdatetime::TIMESTAMP >= CURRENT_DATE - INTERVAL '1 year'
GROUP BY dc.congregation_label, total.cg_member_count
ORDER BY dc.congregation_label;


-- --------------------------
-- Leadership Track (L1/L2/L3) Completion
-- --------------------------
SELECT
    g.grp_name AS training_name,
    g.grp_tag_ministry AS track,
    COUNT(DISTINCT a.att_user_key) FILTER (WHERE a.att_status = '1') AS completed_count
FROM raw.pco_attendance a
JOIN raw.pco_events e ON a.att_event_key = e.event_id
JOIN raw.pco_groups g ON e.event_group_key = g.grp_id
WHERE g.grp_type_key = 147987
  AND (g.grp_tag_ministry ILIKE '%Level%' OR g.grp_tag_ministry ILIKE '%EQ%')
GROUP BY g.grp_name, g.grp_tag_ministry
ORDER BY g.grp_tag_ministry, g.grp_name;


-- --------------------------
-- D&D / Specialized Track Participation
-- --------------------------
SELECT
    g.grp_name AS program_name,
    COUNT(DISTINCT gm.member_user_key) AS participant_count
FROM raw.pco_group_membership gm
JOIN raw.pco_groups g ON gm.member_grp_key = g.grp_id
WHERE g.grp_type_key = 147987
  AND (g.grp_name ILIKE '%D&D%'
       OR g.grp_name ILIKE '%Church Education%'
       OR g.grp_name ILIKE '%Faith Formation%')
GROUP BY g.grp_name
ORDER BY participant_count DESC;
