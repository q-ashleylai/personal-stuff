-- ============================================================
-- ETL Step 2: dim_member
-- Full refresh: truncate and reload daily
-- Dependencies: None (reads from raw only)
-- ============================================================

TRUNCATE TABLE analytics.dim_member;

INSERT INTO analytics.dim_member
SELECT
    m.member_id                        AS member_key,
    m.first_name,
    m.last_name,
    CONCAT(m.first_name, ' ', m.last_name) AS full_name,
    m.gender,
    m.date_of_birth,
    CASE
        WHEN TIMESTAMPDIFF(YEAR, m.date_of_birth, CURDATE()) < 13 THEN 'Child (0-12)'
        WHEN TIMESTAMPDIFF(YEAR, m.date_of_birth, CURDATE()) < 18 THEN 'Teen (13-17)'
        WHEN TIMESTAMPDIFF(YEAR, m.date_of_birth, CURDATE()) < 30 THEN 'Young Adult (18-29)'
        WHEN TIMESTAMPDIFF(YEAR, m.date_of_birth, CURDATE()) < 50 THEN 'Adult (30-49)'
        ELSE 'Senior (50+)'
    END                                AS age_group,
    m.join_date,
    m.membership_status,
    m.campus,
    COALESCE(eng.ministry_count, 0)    AS ministry_count,
    COALESCE(eng.cell_group_count, 0)  AS cell_group_count,
    CASE
        WHEN COALESCE(eng.ministry_count, 0) + COALESCE(eng.cell_group_count, 0) = 0 THEN 'Not Connected'
        WHEN COALESCE(eng.ministry_count, 0) + COALESCE(eng.cell_group_count, 0) = 1 THEN 'Lightly Connected'
        ELSE 'Well Connected'
    END                                AS connection_level
FROM raw.members m
LEFT JOIN (
    SELECT
        mb.member_id,
        COUNT(DISTINCT mm.ministry_id)  AS ministry_count,
        COUNT(DISTINCT cgm.group_id)    AS cell_group_count
    FROM raw.members mb
    LEFT JOIN raw.ministry_members mm
        ON mb.member_id = mm.member_id AND mm.left_date IS NULL
    LEFT JOIN raw.cell_group_members cgm
        ON mb.member_id = cgm.member_id AND cgm.left_date IS NULL
    GROUP BY mb.member_id
) eng ON m.member_id = eng.member_id;
