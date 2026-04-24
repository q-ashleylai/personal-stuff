-- ============================================================
-- ETL Step 7: fact_discipleship
-- Full refresh: truncate and reload
-- Source: raw.pco_discipleship_completion
-- Dependencies: dim_date, dim_member
-- ============================================================

TRUNCATE TABLE sem.fact_discipleship;

INSERT INTO sem.fact_discipleship (
    discipleship_key, member_key, started_date_key,
    completed_date_key, status
)
SELECT
    dc.dc_id AS discipleship_key,
    dc.dc_user_key AS member_key,
    TO_CHAR(dc.dc_started_at, 'YYYYMMDD')::INTEGER AS started_date_key,
    CASE
        WHEN dc.dc_completed_at IS NOT NULL
        THEN TO_CHAR(dc.dc_completed_at, 'YYYYMMDD')::INTEGER
        ELSE NULL
    END AS completed_date_key,
    dc.dc_workflow_completion AS status
FROM raw.pco_discipleship_completion dc;
