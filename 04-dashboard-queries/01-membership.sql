-- ============================================================
-- Dashboard Queries: Pillar 1 — Membership
-- Connect to: sem schema
-- ============================================================

-- --------------------------
-- DUMC CG Size by Year
-- --------------------------
SELECT
    d.year,
    dc.congregation_label,
    COUNT(DISTINCT cg.cg_key) AS cg_count,
    SUM(cg.cg_size) AS total_cg_members
FROM sem.dim_cell_group cg
JOIN sem.dim_congregation dc ON cg.congregation_key = dc.congregation_key
CROSS JOIN (SELECT DISTINCT year FROM sem.dim_date) d
WHERE cg.status != 'Archived'
GROUP BY d.year, dc.congregation_label
ORDER BY d.year, dc.congregation_label;


-- --------------------------
-- Staff Demographics (Pastors/Elders)
-- --------------------------
SELECT
    dm.user_role,
    dm.gender,
    dm.age_group,
    dc.congregation_label,
    COUNT(*) AS staff_count
FROM sem.dim_member dm
LEFT JOIN sem.dim_congregation dc ON dm.congregation_key = dc.congregation_key
WHERE dm.user_role IN ('Pastor', 'Zone Pastor', 'Elder',
                       'Zone Leader | Pastor', 'Zone Leader | Elder',
                       'Pastor | Elder')
  AND dm.user_status = 'active'
GROUP BY dm.user_role, dm.gender, dm.age_group, dc.congregation_label
ORDER BY dm.user_role, dc.congregation_label;


-- --------------------------
-- CG Leader Demographics
-- --------------------------
SELECT
    dm.gender,
    dm.age_group,
    dc.congregation_label,
    COUNT(*) AS leader_count
FROM sem.dim_member dm
LEFT JOIN sem.dim_congregation dc ON dm.congregation_key = dc.congregation_key
WHERE dm.user_role IN ('Cell Group Leader', 'Assistant Cell Group Leader')
  AND dm.user_status = 'active'
GROUP BY dm.gender, dm.age_group, dc.congregation_label
ORDER BY dc.congregation_label, dm.age_group;


-- --------------------------
-- Membership Ratio: Church Member % / CG Member % / Lost Sheep %
-- --------------------------
SELECT
    dc.congregation_label,
    COUNT(*) FILTER (WHERE dm.membership = 'Church Member')
        AS church_members,
    COUNT(*) FILTER (WHERE dm.membership = 'Cell Member')
        AS cell_members,
    COUNT(*) FILTER (WHERE dm.membership = 'Visitor')
        AS visitors,
    COUNT(*) AS total_people,
    ROUND(
        COUNT(*) FILTER (WHERE dm.membership = 'Church Member') * 100.0
        / NULLIF(COUNT(*), 0), 1
    ) AS church_member_pct,
    ROUND(
        COUNT(*) FILTER (WHERE dm.membership = 'Cell Member') * 100.0
        / NULLIF(COUNT(*), 0), 1
    ) AS cell_member_pct
FROM sem.dim_member dm
LEFT JOIN sem.dim_congregation dc ON dm.congregation_key = dc.congregation_key
WHERE dm.user_status = 'active'
  AND dm.membership IN ('Church Member', 'Cell Member', 'Visitor')
GROUP BY dc.congregation_label
ORDER BY dc.congregation_label;
