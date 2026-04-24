-- ============================================================
-- ETL Step 6: fact_decisions
-- Incremental load: watermark on nd_submitted_at
-- Source: raw.pco_new_decisions + raw.pco_users
-- Dependencies: dim_date, dim_member, dim_congregation
-- ============================================================

INSERT INTO sem.fact_decisions (
    decision_key, member_key, date_key, form_id, form_title,
    congregation_key, reason
)
SELECT
    nd.nd_id AS decision_key,
    nd.nd_user_key AS member_key,
    TO_CHAR(nd.nd_submitted_at, 'YYYYMMDD')::INTEGER AS date_key,
    nd.nd_form_submitted AS form_id,
    nd.nd_form_title AS form_title,
    dm.congregation_key,
    nd.nd_reason AS reason
FROM raw.pco_new_decisions nd
LEFT JOIN sem.dim_member dm ON nd.nd_user_key = dm.member_key
WHERE nd.nd_id NOT IN (SELECT decision_key FROM sem.fact_decisions);
