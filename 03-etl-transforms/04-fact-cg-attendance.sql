-- ============================================================
-- ETL Step 4: fact_cg_attendance
-- Incremental load: watermark on att_job_date
-- Source: raw.pco_attendance + raw.pco_events + raw.pco_groups
-- Filter: grp_type_key = 137505 (Cell Group events only)
-- Dependencies: dim_date, dim_member, dim_cell_group
-- ============================================================

INSERT INTO sem.fact_cg_attendance (
    member_key, cg_key, date_key, event_key, attended, user_role
)
SELECT
    a.att_user_key AS member_key,
    e.event_group_key AS cg_key,
    TO_CHAR(e.event_startdatetime::TIMESTAMP, 'YYYYMMDD')::INTEGER AS date_key,
    e.event_id AS event_key,
    a.att_status::INTEGER AS attended,
    a.att_user_role AS user_role
FROM raw.pco_attendance a
JOIN raw.pco_events e ON a.att_event_key = e.event_id
JOIN raw.pco_groups g ON e.event_group_key = g.grp_id
WHERE g.grp_type_key = 137505
  AND a.att_job_date > COALESCE(
      (SELECT MAX(att_job_date) FROM raw.pco_attendance
       WHERE att_event_key IN (
           SELECT event_id FROM raw.pco_events
           JOIN raw.pco_groups ON event_group_key = grp_id
           WHERE grp_type_key = 137505
       )),
      '1970-01-01'
  )
ON CONFLICT DO NOTHING;
