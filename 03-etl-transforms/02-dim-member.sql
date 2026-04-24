-- ============================================================
-- ETL Step 2: dim_member
-- Full refresh: truncate and reload daily
-- Source: raw.pco_users + raw.pco_group_membership + raw.pco_groups
-- Dependencies: sem.dim_congregation (seed data)
-- ============================================================

TRUNCATE TABLE sem.dim_member CASCADE;

INSERT INTO sem.dim_member (
    member_key, full_name, first_name, last_name, gender,
    age_group, membership, user_role, is_baptized,
    congregation_key, user_status, created_at
)
SELECT
    u.user_id AS member_key,
    CONCAT(u.user_first_name, ' ', u.user_last_name) AS full_name,
    u.user_first_name AS first_name,
    u.user_last_name AS last_name,
    u.user_gender AS gender,

    CASE
        WHEN u.user_birthdate IS NULL THEN NULL
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, u.user_birthdate::DATE)) < 13 THEN '12 and below'
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, u.user_birthdate::DATE)) < 18 THEN '13 - 17'
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, u.user_birthdate::DATE)) < 24 THEN '18 - 23'
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, u.user_birthdate::DATE)) < 36 THEN '24 - 35'
        WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, u.user_birthdate::DATE)) < 51 THEN '36 - 50'
        ELSE '66 and above'
    END AS age_group,

    u.user_membership AS membership,
    u.user_role AS user_role,

    CASE
        WHEN u.user_baptized IS NOT NULL
             AND u.user_baptized NOT IN ('', ' ')
        THEN TRUE
        ELSE FALSE
    END AS is_baptized,

    -- Derive congregation from the user's primary CG group tag
    CASE
        WHEN cg.grp_tag_congregation LIKE 'EN%' THEN 1
        WHEN cg.grp_tag_congregation LIKE 'BM%' THEN 2
        WHEN cg.grp_tag_congregation LIKE 'CN%' THEN 3
        WHEN cg.grp_tag_congregation LIKE 'MM%' THEN 4
        WHEN cg.grp_tag_congregation LIKE 'NP%' THEN 5
        WHEN cg.grp_tag_congregation LIKE 'TM%' THEN 6
        WHEN cg.grp_tag_congregation LIKE 'FP%' THEN 7
        ELSE NULL
    END AS congregation_key,

    u.user_status,
    u.user_created_at AS created_at

FROM raw.pco_users u
LEFT JOIN (
    -- Get the user's primary CG membership (most recent join)
    SELECT DISTINCT ON (gm.member_user_key)
        gm.member_user_key,
        g.grp_tag_congregation
    FROM raw.pco_group_membership gm
    JOIN raw.pco_groups g ON gm.member_grp_key = g.grp_id
    WHERE g.grp_type_key = 137505  -- Cell Groups only
    ORDER BY gm.member_user_key, gm.member_joined_date DESC
) cg ON u.user_id = cg.member_user_key;
