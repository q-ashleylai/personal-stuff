-- ============================================================
-- ETL Step 5: fact_cg_submission
-- Incremental load: watermark on event_startdatetime
-- Source: raw.pco_events + raw.pco_groups
-- Filter: grp_type_key = 137505 (Cell Group events only)
-- Dependencies: dim_date, dim_cell_group
-- ============================================================

INSERT INTO sem.fact_cg_submission (
    cg_key, date_key, event_key, submitted, cancelled
)
SELECT
    e.event_group_key AS cg_key,
    TO_CHAR(e.event_startdatetime::TIMESTAMP, 'YYYYMMDD')::INTEGER AS date_key,
    e.event_id AS event_key,
    CASE WHEN e.event_att_committed_at IS NOT NULL THEN 1 ELSE 0 END AS submitted,
    e.event_canceled::INTEGER AS cancelled
FROM raw.pco_events e
JOIN raw.pco_groups g ON e.event_group_key = g.grp_id
WHERE g.grp_type_key = 137505
ON CONFLICT DO NOTHING;
