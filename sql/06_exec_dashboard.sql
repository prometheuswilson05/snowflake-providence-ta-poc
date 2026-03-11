-- ============================================================
-- Providence Health & Services - Predictive TA Analytics POC
-- 06: Executive Dashboard Query
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA ANALYTICS.PROVIDENCE_TA_POC;

-- ============================================================
-- KPI 1: Average Predicted TTF by Role Family (2026)
-- ============================================================
SELECT
    f.role_family AS "Role Family",
    ROUND(AVG(f.predicted_avg_ttf), 1) || ' days' AS "Predicted Avg TTF",
    ROUND(MIN(f.ttf_lower_90), 1) || ' - ' || ROUND(MAX(f.ttf_upper_90), 1) || ' days' AS "90% Confidence Range",
    COALESCE(v.mape_pct || '%', 'N/A') AS "Model MAPE (Validated)"
FROM V_2026_FORECAST f
LEFT JOIN T_VALIDATION_TTF v ON f.role_family = v.role_family
GROUP BY f.role_family, v.mape_pct
ORDER BY AVG(f.predicted_avg_ttf) DESC;

-- ============================================================
-- KPI 2: Forecasted Volume by Quarter
-- ============================================================
SELECT
    CASE
        WHEN MONTH(forecast_month) BETWEEN 1 AND 3 THEN 'Q1 2026'
        WHEN MONTH(forecast_month) BETWEEN 4 AND 6 THEN 'Q2 2026'
        WHEN MONTH(forecast_month) BETWEEN 7 AND 9 THEN 'Q3 2026'
        ELSE 'Q4 2026'
    END AS "Quarter",
    SUM(predicted_volume) AS "Total Forecasted Reqs",
    SUM(volume_lower_90) || ' - ' || SUM(volume_upper_90) AS "90% Confidence Range"
FROM V_2026_FORECAST
GROUP BY 1
ORDER BY 1;

-- ============================================================
-- KPI 3: Volume by Role Family x Quarter
-- ============================================================
SELECT
    CASE
        WHEN MONTH(forecast_month) BETWEEN 1 AND 3 THEN 'Q1 2026'
        WHEN MONTH(forecast_month) BETWEEN 4 AND 6 THEN 'Q2 2026'
        WHEN MONTH(forecast_month) BETWEEN 7 AND 9 THEN 'Q3 2026'
        ELSE 'Q4 2026'
    END AS "Quarter",
    role_family AS "Role Family",
    SUM(predicted_volume) AS "Forecasted Reqs",
    SUM(volume_lower_90) || ' - ' || SUM(volume_upper_90) AS "Range"
FROM V_2026_FORECAST
GROUP BY 1, 2
ORDER BY 1, 2;

-- ============================================================
-- KPI 4: Revenue at Risk Analysis
-- Clinical roles: $2,500/vacancy day; Non-clinical: $800/day
-- ============================================================
WITH revenue_at_risk AS (
    SELECT
        role_family,
        SUM(predicted_volume) AS total_reqs,
        AVG(predicted_avg_ttf) AS avg_ttf,
        CASE
            WHEN role_family IN ('Nursing', 'Clinical Support', 'Allied Health') THEN 2500
            ELSE 800
        END AS daily_vacancy_cost,
        ROUND(
            SUM(predicted_volume) * AVG(predicted_avg_ttf) *
            CASE
                WHEN role_family IN ('Nursing', 'Clinical Support', 'Allied Health') THEN 2500
                ELSE 800
            END, 0
        ) AS estimated_revenue_at_risk
    FROM V_2026_FORECAST
    GROUP BY 1
)
SELECT
    role_family AS "Role Family",
    total_reqs AS "2026 Forecasted Reqs",
    ROUND(avg_ttf, 1) || ' days' AS "Avg Predicted TTF",
    '$' || TO_CHAR(daily_vacancy_cost, '9,999') AS "Daily Vacancy Cost",
    '$' || TO_CHAR(estimated_revenue_at_risk, '999,999,999') AS "Est. Revenue at Risk"
FROM revenue_at_risk
ORDER BY estimated_revenue_at_risk DESC;

-- ============================================================
-- KPI 5: Total Revenue at Risk Summary
-- ============================================================
WITH revenue_at_risk AS (
    SELECT
        role_family,
        ROUND(
            SUM(predicted_volume) * AVG(predicted_avg_ttf) *
            CASE
                WHEN role_family IN ('Nursing', 'Clinical Support', 'Allied Health') THEN 2500
                ELSE 800
            END, 0
        ) AS estimated_revenue_at_risk
    FROM V_2026_FORECAST
    GROUP BY 1
)
SELECT
    '$' || TO_CHAR(SUM(estimated_revenue_at_risk), '999,999,999') AS "TOTAL 2026 Revenue at Risk",
    '$' || TO_CHAR(SUM(CASE WHEN role_family IN ('Nursing', 'Clinical Support', 'Allied Health')
                         THEN estimated_revenue_at_risk ELSE 0 END), '999,999,999') AS "Clinical Revenue at Risk",
    '$' || TO_CHAR(SUM(CASE WHEN role_family IN ('IT', 'Admin')
                         THEN estimated_revenue_at_risk ELSE 0 END), '999,999,999') AS "Non-Clinical Revenue at Risk"
FROM revenue_at_risk;

-- ============================================================
-- KPI 6: Cost Anomalies Detected (from ML model)
-- ============================================================
SELECT
    TS AS "Month",
    SERIES AS "Role Family",
    '$' || TO_CHAR(FORECAST, '999,999.99') AS "Expected Cost",
    '$' || TO_CHAR(LOWER_BOUND, '999,999.99') AS "Lower Bound",
    '$' || TO_CHAR(UPPER_BOUND, '999,999.99') AS "Upper Bound",
    'ANOMALY' AS "Status"
FROM T_COST_ANOMALIES
WHERE IS_ANOMALY = TRUE
ORDER BY TS
LIMIT 20;

-- ============================================================
-- KPI 7: Regional Hotspots
-- ============================================================
SELECT
    region AS "Region",
    role_family AS "Role Family",
    SUM(predicted_volume) AS "2026 Forecasted Reqs",
    ROUND(AVG(predicted_avg_ttf), 1) || ' days' AS "Avg Predicted TTF",
    '$' || TO_CHAR(ROUND(
        SUM(predicted_volume) * AVG(predicted_avg_ttf) *
        CASE WHEN role_family IN ('Nursing', 'Clinical Support', 'Allied Health') THEN 2500 ELSE 800 END
    , 0), '999,999,999') AS "Revenue at Risk"
FROM V_2026_FORECAST
GROUP BY 1, 2
HAVING SUM(predicted_volume) > 0
ORDER BY SUM(predicted_volume) DESC
LIMIT 10;
