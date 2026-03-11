-- ============================================================
-- Providence Health & Services - Predictive TA Analytics POC
-- 03 FALLBACK: Statistical Simulation Models
-- (Used if SNOWFLAKE.ML.FORECAST is not available on account)
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA ANALYTICS.PROVIDENCE_TA_POC;

-- ============================================================
-- Training Views (same as ML version)
-- ============================================================

CREATE OR REPLACE VIEW V_TTF_TRAINING AS
SELECT
    DATE_TRUNC('MONTH', open_date) AS ts,
    role_family,
    region,
    AVG(time_to_fill) AS avg_ttf
FROM TA_HISTORICAL
WHERE outcome = 'filled'
GROUP BY 1, 2, 3;

CREATE OR REPLACE VIEW V_TTF_TRAINING_SERIES AS
SELECT
    DATE_TRUNC('MONTH', open_date) AS ts,
    role_family,
    AVG(time_to_fill) AS avg_ttf
FROM TA_HISTORICAL
WHERE outcome = 'filled'
GROUP BY 1, 2;

CREATE OR REPLACE VIEW V_VOL_TRAINING AS
SELECT
    DATE_TRUNC('MONTH', open_date) AS ts,
    role_family,
    COUNT(*) AS req_volume
FROM TA_HISTORICAL
GROUP BY 1, 2;

CREATE OR REPLACE VIEW V_COST_TRAINING AS
SELECT
    DATE_TRUNC('MONTH', open_date) AS ts,
    role_family,
    AVG(bpo_cost_per_hire) AS avg_cost
FROM TA_HISTORICAL
WHERE outcome = 'filled'
GROUP BY 1, 2;

-- ============================================================
-- A) TTF STATISTICAL FORECAST
-- Uses rolling avg + seasonality index + confidence intervals
-- ============================================================

CREATE OR REPLACE TABLE T_TTF_STATS AS
WITH monthly_stats AS (
    SELECT
        role_family,
        MONTH(ts) AS month_num,
        AVG(avg_ttf) AS month_avg_ttf,
        STDDEV(avg_ttf) AS month_std_ttf
    FROM V_TTF_TRAINING_SERIES
    GROUP BY 1, 2
),
overall_stats AS (
    SELECT
        role_family,
        AVG(avg_ttf) AS overall_avg,
        STDDEV(avg_ttf) AS overall_std
    FROM V_TTF_TRAINING_SERIES
    GROUP BY 1
),
seasonal_index AS (
    SELECT
        m.role_family,
        m.month_num,
        m.month_avg_ttf / NULLIF(o.overall_avg, 0) AS seasonality_factor,
        m.month_std_ttf,
        o.overall_avg,
        o.overall_std
    FROM monthly_stats m
    JOIN overall_stats o ON m.role_family = o.role_family
)
SELECT
    role_family,
    month_num,
    ROUND(overall_avg * seasonality_factor, 1) AS forecast_ttf,
    ROUND(overall_avg * seasonality_factor - 1.645 * COALESCE(month_std_ttf, overall_std), 1) AS lower_bound,
    ROUND(overall_avg * seasonality_factor + 1.645 * COALESCE(month_std_ttf, overall_std), 1) AS upper_bound,
    ROUND(seasonality_factor, 3) AS seasonality_factor
FROM seasonal_index;

-- ============================================================
-- B) VOLUME STATISTICAL FORECAST
-- ============================================================

CREATE OR REPLACE TABLE T_VOL_STATS AS
WITH monthly_stats AS (
    SELECT
        role_family,
        MONTH(ts) AS month_num,
        AVG(req_volume) AS month_avg_vol,
        STDDEV(req_volume) AS month_std_vol
    FROM V_VOL_TRAINING
    GROUP BY 1, 2
),
overall_stats AS (
    SELECT
        role_family,
        AVG(req_volume) AS overall_avg,
        STDDEV(req_volume) AS overall_std
    FROM V_VOL_TRAINING
    GROUP BY 1
),
seasonal_index AS (
    SELECT
        m.role_family,
        m.month_num,
        m.month_avg_vol / NULLIF(o.overall_avg, 0) AS seasonality_factor,
        m.month_std_vol,
        o.overall_avg,
        o.overall_std
    FROM monthly_stats m
    JOIN overall_stats o ON m.role_family = o.role_family
)
SELECT
    role_family,
    month_num,
    ROUND(overall_avg * seasonality_factor, 0) AS forecast_volume,
    GREATEST(0, ROUND(overall_avg * seasonality_factor - 1.645 * COALESCE(month_std_vol, overall_std), 0)) AS lower_bound,
    ROUND(overall_avg * seasonality_factor + 1.645 * COALESCE(month_std_vol, overall_std), 0) AS upper_bound,
    ROUND(seasonality_factor, 3) AS seasonality_factor
FROM seasonal_index;

-- ============================================================
-- C) COST ANOMALY DETECTION (Statistical)
-- Flag months where avg cost > mean + 2*stddev
-- ============================================================

CREATE OR REPLACE TABLE T_COST_ANOMALIES AS
WITH stats AS (
    SELECT
        role_family,
        AVG(avg_cost) AS mean_cost,
        STDDEV(avg_cost) AS std_cost
    FROM V_COST_TRAINING
    GROUP BY 1
)
SELECT
    c.ts,
    c.role_family,
    ROUND(c.avg_cost, 2) AS avg_cost,
    ROUND(s.mean_cost, 2) AS mean_cost,
    ROUND(s.std_cost, 2) AS std_cost,
    ROUND(s.mean_cost + 2 * s.std_cost, 2) AS upper_threshold,
    ROUND(s.mean_cost - 2 * s.std_cost, 2) AS lower_threshold,
    CASE
        WHEN c.avg_cost > s.mean_cost + 2 * s.std_cost THEN TRUE
        WHEN c.avg_cost < s.mean_cost - 2 * s.std_cost THEN TRUE
        ELSE FALSE
    END AS is_anomaly
FROM V_COST_TRAINING c
JOIN stats s ON c.role_family = s.role_family;

-- Summary
SELECT 'TTF Stats' AS model, COUNT(*) AS rows FROM T_TTF_STATS
UNION ALL SELECT 'Volume Stats', COUNT(*) FROM T_VOL_STATS
UNION ALL SELECT 'Cost Anomalies', COUNT(*) FROM T_COST_ANOMALIES;

SELECT * FROM T_COST_ANOMALIES WHERE is_anomaly = TRUE ORDER BY ts;
