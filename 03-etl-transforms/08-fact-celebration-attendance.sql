-- ============================================================
-- ETL Step 8: fact_celebration_attendance
-- Incremental load: watermark on ca_created_at
-- Source: raw.pco_checkin_attendance + raw.pco_checkin_events
-- Dependencies: dim_date, dim_member, dim_congregation
-- ============================================================

INSERT INTO sem.fact_celebration_attendance (
    checkin_key, member_key, date_key, kind,
    service_name, congregation_key
)
SELECT
    ca.ca_id AS checkin_key,
    ca.ca_user_key AS member_key,
    TO_CHAR(ca.ca_created_at, 'YYYYMMDD')::INTEGER AS date_key,
    ca.ca_kind AS kind,
    ce.ce_name AS service_name,
    -- Derive congregation from service name
    CASE
        WHEN ce.ce_name ILIKE '%english%' OR ce.ce_name ILIKE '% EN %' THEN 1
        WHEN ce.ce_name ILIKE '%bahasa%'  OR ce.ce_name ILIKE '% BM %' THEN 2
        WHEN ce.ce_name ILIKE '%chinese%' OR ce.ce_name ILIKE '% CN %' THEN 3
        WHEN ce.ce_name ILIKE '%myanmar%' OR ce.ce_name ILIKE '% MM %' THEN 4
        WHEN ce.ce_name ILIKE '%nepali%'  OR ce.ce_name ILIKE '% NP %' THEN 5
        WHEN ce.ce_name ILIKE '%tamil%'   OR ce.ce_name ILIKE '% TM %' THEN 6
        WHEN ce.ce_name ILIKE '%filipino%' OR ce.ce_name ILIKE '% FP %' THEN 7
        WHEN ce.ce_name ILIKE '%nextgen%' OR ce.ce_name ILIKE '%NXG%' THEN 8
        ELSE NULL
    END AS congregation_key
FROM raw.pco_checkin_attendance ca
JOIN raw.pco_checkin_events ce ON ca.ca_ce_key = ce.ce_id
WHERE ca.ca_id NOT IN (SELECT checkin_key FROM sem.fact_celebration_attendance);
