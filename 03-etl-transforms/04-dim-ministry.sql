-- ============================================================
-- ETL Node 4: dim_ministry
-- Full refresh: truncate and reload daily
-- Dependencies: None (reads from raw only)
-- ============================================================

TRUNCATE TABLE analytics.dim_ministry;

INSERT INTO analytics.dim_ministry
SELECT
    mi.ministry_id                                  AS ministry_key,
    mi.ministry_name,
    mi.ministry_type,
    COALESCE(mc.active_members, 0)                  AS active_member_count,
    CONCAT(ldr.first_name, ' ', ldr.last_name)      AS leader_name,
    mi.status
FROM raw.ministries mi
LEFT JOIN raw.members ldr
    ON mi.leader_member_id = ldr.member_id
LEFT JOIN (
    SELECT ministry_id, COUNT(*) AS active_members
    FROM raw.ministry_members
    WHERE left_date IS NULL
    GROUP BY ministry_id
) mc ON mi.ministry_id = mc.ministry_id;
