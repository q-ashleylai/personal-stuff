-- ============================================================
-- ETL Step 9: fact_serving
-- Incremental load: watermark on sa_service_date
-- Source: raw.pco_serving_attendance + raw.pco_serving_teams
-- Dependencies: dim_date, dim_member
-- ============================================================

INSERT INTO sem.fact_serving (
    serving_key, member_key, date_key, team_name, ministry, position
)
SELECT
    sa.sa_id AS serving_key,
    sa.sa_user_key AS member_key,
    TO_CHAR(sa.sa_service_date, 'YYYYMMDD')::INTEGER AS date_key,
    sa.sa_team_name AS team_name,
    sa.sa_service_type AS ministry,
    sa.sa_position AS position
FROM raw.pco_serving_attendance sa
WHERE sa.sa_id NOT IN (SELECT serving_key FROM sem.fact_serving);
