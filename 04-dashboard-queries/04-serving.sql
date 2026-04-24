-- ============================================================
-- Dashboard Queries: Pillar 4 — Serving
-- Connect to: sem schema
-- ============================================================

-- --------------------------
-- % Actively Serving by Congregation
-- --------------------------
SELECT
    dc.congregation_label,
    COUNT(DISTINCT f.member_key) AS active_servers,
    total.member_count AS total_members,
    ROUND(
        COUNT(DISTINCT f.member_key) * 100.0
        / NULLIF(total.member_count, 0), 1
    ) AS actively_serving_pct
FROM sem.fact_serving f
JOIN sem.dim_member dm ON f.member_key = dm.member_key
JOIN sem.dim_congregation dc ON dm.congregation_key = dc.congregation_key
JOIN sem.dim_date d ON f.date_key = d.date_key
CROSS JOIN LATERAL (
    SELECT COUNT(*) AS member_count
    FROM sem.dim_member dm2
    WHERE dm2.congregation_key = dc.congregation_key
      AND dm2.user_status = 'active'
) total
WHERE d.full_date >= CURRENT_DATE - INTERVAL '3 months'
GROUP BY dc.congregation_label, total.member_count
ORDER BY dc.congregation_label;


-- --------------------------
-- Serving Frequency Tiers (current month)
-- --------------------------
SELECT
    CASE
        WHEN serve_count >= 4 THEN 'High (4+/month) - burnout risk'
        WHEN serve_count BETWEEN 1 AND 3 THEN 'Moderate (1-3/month) - consistent'
        ELSE 'Low (0/month) - capacity available'
    END AS frequency_tier,
    COUNT(*) AS member_count
FROM (
    SELECT f.member_key, COUNT(*) AS serve_count
    FROM sem.fact_serving f
    JOIN sem.dim_date d ON f.date_key = d.date_key
    WHERE d.year = EXTRACT(YEAR FROM CURRENT_DATE)
      AND d.month = EXTRACT(MONTH FROM CURRENT_DATE)
    GROUP BY f.member_key
) monthly
GROUP BY frequency_tier
ORDER BY frequency_tier;


-- --------------------------
-- Serving by Team / Ministry
-- --------------------------
SELECT
    f.ministry,
    f.team_name,
    d.year,
    d.month,
    COUNT(*) AS total_serves,
    COUNT(DISTINCT f.member_key) AS unique_volunteers
FROM sem.fact_serving f
JOIN sem.dim_date d ON f.date_key = d.date_key
GROUP BY f.ministry, f.team_name, d.year, d.month
ORDER BY f.ministry, f.team_name, d.year, d.month;
