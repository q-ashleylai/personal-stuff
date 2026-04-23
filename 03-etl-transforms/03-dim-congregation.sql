-- ============================================================
-- ETL Step 3: dim_congregation
-- Full refresh: truncate and reload daily
-- Dependencies: None (reads from raw only)
-- ============================================================

TRUNCATE TABLE analytics.dim_congregation;

INSERT INTO analytics.dim_congregation
SELECT
    c.congregation_id      AS congregation_key,
    c.congregation_date,
    c.congregation_time,
    c.congregation_type,
    CASE c.congregation_type
        WHEN 'english'  THEN 'English Congregation'
        WHEN 'chinese'  THEN 'Chinese Congregation'
        WHEN 'bm'       THEN 'BM Congregation'
        WHEN 'tamil'    THEN 'Tamil Congregation'
        WHEN 'youth'    THEN 'Youth Congregation'
        WHEN 'special'  THEN 'Special Event'
        ELSE c.congregation_type
    END                    AS congregation_type_label,
    c.language,
    c.campus,
    c.speaker
FROM raw.congregations c;
