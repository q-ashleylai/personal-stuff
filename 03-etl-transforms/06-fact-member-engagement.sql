-- ============================================================
-- ETL Step 6: fact_member_engagement
-- Monthly snapshot: one row per member per month
-- Deletes current month's partition then reloads
-- Dependencies: dim_date, dim_member, dim_ministry
-- ============================================================

-- Remove current month's data before re-inserting
DELETE FROM analytics.fact_member_engagement
WHERE snapshot_month = DATE_FORMAT(CURDATE(), '%Y-%m-01');

INSERT INTO analytics.fact_member_engagement
SELECT
    m.member_id                                         AS member_key,
    CAST(DATE_FORMAT(CURDATE(), '%Y%m01') AS UNSIGNED)  AS date_key,
    DATE_FORMAT(CURDATE(), '%Y-%m-01')                  AS snapshot_month,

    -- Attendance metrics (current month)
    COALESCE(att.congregations_attended, 0)              AS congregations_attended_this_month,
    COALESCE(att.sundays_attended, 0)                    AS sundays_attended_this_month,

    -- Cell group attendance (current month)
    COALESCE(cg.meetings_attended, 0)                   AS cg_meetings_attended_this_month,
    COALESCE(cg.meetings_total, 0)                      AS cg_meetings_total_this_month,

    -- Ministry involvement (current)
    COALESCE(mi.active_ministries, 0)                   AS active_ministry_count,

    -- Engagement score (weighted formula)
    (COALESCE(att.sundays_attended, 0) * 2)
    + (COALESCE(cg.meetings_attended, 0) * 3)
    + (COALESCE(mi.active_ministries, 0) * 5)           AS engagement_score,

    -- Engagement tier
    CASE
        WHEN (COALESCE(att.sundays_attended, 0) * 2
            + COALESCE(cg.meetings_attended, 0) * 3
            + COALESCE(mi.active_ministries, 0) * 5) >= 15 THEN 'Highly Engaged'
        WHEN (COALESCE(att.sundays_attended, 0) * 2
            + COALESCE(cg.meetings_attended, 0) * 3
            + COALESCE(mi.active_ministries, 0) * 5) >= 6  THEN 'Moderately Engaged'
        WHEN (COALESCE(att.sundays_attended, 0) * 2
            + COALESCE(cg.meetings_attended, 0) * 3
            + COALESCE(mi.active_ministries, 0) * 5) >= 1  THEN 'Lightly Engaged'
        ELSE 'Disengaged'
    END                                                 AS engagement_tier

FROM raw.members m

-- Current month congregation attendance
LEFT JOIN (
    SELECT
        ar.member_id,
        COUNT(*)                                                     AS congregations_attended,
        COUNT(CASE WHEN c.congregation_type = 'english' THEN 1 END)  AS sundays_attended
    FROM raw.attendance_records ar
    JOIN raw.congregations c ON ar.congregation_id = c.congregation_id
    WHERE c.congregation_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
      AND c.congregation_date <  DATE_ADD(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL 1 MONTH)
    GROUP BY ar.member_id
) att ON m.member_id = att.member_id

-- Current month cell group attendance
LEFT JOIN (
    SELECT
        member_id,
        COUNT(CASE WHEN attended = TRUE THEN 1 END) AS meetings_attended,
        COUNT(*)                                     AS meetings_total
    FROM raw.cell_group_attendance
    WHERE meeting_date >= DATE_FORMAT(CURDATE(), '%Y-%m-01')
      AND meeting_date <  DATE_ADD(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL 1 MONTH)
    GROUP BY member_id
) cg ON m.member_id = cg.member_id

-- Active ministry involvement
LEFT JOIN (
    SELECT member_id, COUNT(DISTINCT ministry_id) AS active_ministries
    FROM raw.ministry_members
    WHERE left_date IS NULL
    GROUP BY member_id
) mi ON m.member_id = mi.member_id

WHERE m.membership_status IN ('active', 'inactive');
