-- ============================================================
-- Dashboard Query: Member Engagement
-- For use in Power BI / QuickBI / other BI tool
-- Connect to: analytics schema
-- ============================================================

-- --------------------------
-- Engagement tier distribution (current month)
-- --------------------------
SELECT
    engagement_tier,
    COUNT(*)       AS member_count
FROM analytics.fact_member_engagement
WHERE snapshot_month = DATE_FORMAT(CURDATE(), '%Y-%m-01')
GROUP BY engagement_tier
ORDER BY FIELD(engagement_tier,
    'Highly Engaged', 'Moderately Engaged', 'Lightly Engaged', 'Disengaged');


-- --------------------------
-- Disengaged members list (for pastoral follow-up)
-- --------------------------
SELECT
    dm.full_name,
    dm.phone,
    dm.campus,
    dm.join_date,
    dm.connection_level,
    e.engagement_score,
    e.congregations_attended_this_month,
    e.cg_meetings_attended_this_month
FROM analytics.fact_member_engagement e
JOIN analytics.dim_member dm ON e.member_key = dm.member_key
WHERE e.snapshot_month = DATE_FORMAT(CURDATE(), '%Y-%m-01')
  AND e.engagement_tier = 'Disengaged'
  AND dm.membership_status = 'active'
ORDER BY dm.full_name;


-- --------------------------
-- New member retention (joined in last 6 months)
-- --------------------------
SELECT
    dm.full_name,
    dm.join_date,
    dm.campus,
    dm.connection_level,
    COALESCE(e.congregations_attended_this_month, 0) AS recent_attendance,
    COALESCE(e.engagement_tier, 'No Data')           AS engagement_tier
FROM analytics.dim_member dm
LEFT JOIN analytics.fact_member_engagement e
    ON dm.member_key = e.member_key
    AND e.snapshot_month = DATE_FORMAT(CURDATE(), '%Y-%m-01')
WHERE dm.join_date >= DATE_SUB(CURDATE(), INTERVAL 6 MONTH)
ORDER BY dm.join_date;


-- --------------------------
-- Engagement trend over time (month-over-month)
-- --------------------------
SELECT
    snapshot_month,
    engagement_tier,
    COUNT(*) AS member_count
FROM analytics.fact_member_engagement
WHERE snapshot_month >= DATE_SUB(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL 6 MONTH)
GROUP BY snapshot_month, engagement_tier
ORDER BY snapshot_month, FIELD(engagement_tier,
    'Highly Engaged', 'Moderately Engaged', 'Lightly Engaged', 'Disengaged');


-- --------------------------
-- Connection level breakdown
-- --------------------------
SELECT
    dm.connection_level,
    dm.membership_status,
    COUNT(*) AS member_count
FROM analytics.dim_member dm
WHERE dm.membership_status IN ('active', 'inactive')
GROUP BY dm.connection_level, dm.membership_status
ORDER BY dm.membership_status, FIELD(dm.connection_level,
    'Well Connected', 'Lightly Connected', 'Not Connected');


-- --------------------------
-- Ministry participation summary
-- --------------------------
SELECT
    dmi.ministry_name,
    dmi.ministry_type,
    dmi.active_member_count,
    dmi.leader_name,
    dmi.status
FROM analytics.dim_ministry dmi
WHERE dmi.status = 'active'
ORDER BY dmi.active_member_count DESC;
