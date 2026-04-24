-- ============================================================
-- ETL Step 3: dim_cell_group
-- Full refresh: truncate and reload daily
-- Source: raw.pco_groups (grp_type_key = 137505) + raw.pco_group_membership
-- Dependencies: sem.dim_congregation (seed data)
-- ============================================================

TRUNCATE TABLE sem.dim_cell_group CASCADE;

INSERT INTO sem.dim_cell_group (
    cg_key, cg_name, zone, district, subzone, zone_leader,
    leader_member_key, age_group, frequency, cg_size, status,
    congregation_key
)
SELECT
    g.grp_id AS cg_key,
    g.grp_name AS cg_name,
    g.grp_tag_zone AS zone,
    g.grp_tag_district AS district,
    g.grp_tag_subzone AS subzone,
    g.grp_zone_leader AS zone_leader,
    g.grp_leader_user_key AS leader_member_key,
    g.grp_tag_age_group AS age_group,
    g.grp_tag_freq AS frequency,
    g.grp_size AS cg_size,

    CASE
        WHEN g.grp_status = 'ARCHIEVED' THEN 'Archived'
        WHEN g.grp_status = 'NEW' THEN 'New'
        ELSE 'Active'
    END AS status,

    CASE
        WHEN g.grp_tag_congregation LIKE 'EN%' THEN 1
        WHEN g.grp_tag_congregation LIKE 'BM%' THEN 2
        WHEN g.grp_tag_congregation LIKE 'CN%' THEN 3
        WHEN g.grp_tag_congregation LIKE 'MM%' THEN 4
        WHEN g.grp_tag_congregation LIKE 'NP%' THEN 5
        WHEN g.grp_tag_congregation LIKE 'TM%' THEN 6
        WHEN g.grp_tag_congregation LIKE 'FP%' THEN 7
        ELSE NULL
    END AS congregation_key

FROM raw.pco_groups g
WHERE g.grp_type_key = 137505;
