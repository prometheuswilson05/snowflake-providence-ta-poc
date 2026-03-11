-- ============================================================
-- Providence Health & Services - Predictive TA Analytics POC
-- 05: 2026 Forecast View (using Snowflake ML models)
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA ANALYTICS.PROVIDENCE_TA_POC;

-- ============================================================
-- Generate 2026 forecasts from ML models (24 months out to cover 2026)
-- Training data ends Dec 2024, so months 13-24 = Jan-Dec 2026
-- ============================================================

-- TTF 2026 forecast
CREATE OR REPLACE TABLE T_TTF_FORECAST_2026 AS
SELECT * FROM TABLE(
    ttf_forecast!FORECAST(
        FORECASTING_PERIODS => 24,
        CONFIG_OBJECT => {'prediction_interval': 0.9}
    )
)
WHERE YEAR(TS) = 2026;

-- Volume 2026 forecast
CREATE OR REPLACE TABLE T_VOL_FORECAST_2026 AS
SELECT * FROM TABLE(
    vol_forecast!FORECAST(
        FORECASTING_PERIODS => 24,
        CONFIG_OBJECT => {'prediction_interval': 0.9}
    )
)
WHERE YEAR(TS) = 2026;

-- ============================================================
-- Comprehensive 2026 Forecast View
-- ============================================================

CREATE OR REPLACE VIEW V_2026_FORECAST AS
WITH
-- Region distribution weights from historical data
region_weights AS (
    SELECT
        role_family,
        region,
        COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY role_family) AS region_weight
    FROM TA_HISTORICAL
    GROUP BY 1, 2
),
-- Historical avg cost by role_family (for cost forecast baseline)
cost_baseline AS (
    SELECT
        role_family,
        AVG(bpo_cost_per_hire) AS avg_cost,
        STDDEV(bpo_cost_per_hire) AS std_cost
    FROM TA_HISTORICAL
    WHERE outcome = 'filled'
    GROUP BY 1
),
-- Cross join forecast months with region weights
forecast_grid AS (
    SELECT
        t.TS AS forecast_month,
        t.SERIES AS role_family,
        rw.region,
        rw.region_weight,
        t.FORECAST AS ttf_forecast,
        t.LOWER_BOUND AS ttf_lower,
        t.UPPER_BOUND AS ttf_upper
    FROM T_TTF_FORECAST_2026 t
    JOIN region_weights rw ON t.SERIES = rw.role_family
)
SELECT
    fg.forecast_month,
    fg.role_family,
    fg.region,

    -- TTF forecast from ML model
    ROUND(fg.ttf_forecast, 1) AS predicted_avg_ttf,
    ROUND(fg.ttf_lower, 1) AS ttf_lower_90,
    ROUND(fg.ttf_upper, 1) AS ttf_upper_90,

    -- Volume forecast (distributed by region weight)
    ROUND(v.FORECAST * fg.region_weight, 0) AS predicted_volume,
    ROUND(v.LOWER_BOUND * fg.region_weight, 0) AS volume_lower_90,
    ROUND(v.UPPER_BOUND * fg.region_weight, 0) AS volume_upper_90,

    -- Cost forecast (baseline + 3% inflation)
    ROUND(c.avg_cost * 1.03, 2) AS predicted_avg_cost,
    ROUND(GREATEST(0, (c.avg_cost - 1.645 * c.std_cost)) * 1.03, 2) AS cost_lower_90,
    ROUND((c.avg_cost + 1.645 * c.std_cost) * 1.03, 2) AS cost_upper_90

FROM forecast_grid fg
JOIN T_VOL_FORECAST_2026 v
    ON fg.role_family = v.SERIES AND fg.forecast_month = v.TS
JOIN cost_baseline c
    ON fg.role_family = c.role_family
ORDER BY fg.forecast_month, fg.role_family, fg.region;

-- Verify
SELECT COUNT(*) AS total_forecast_rows FROM V_2026_FORECAST;
SELECT * FROM V_2026_FORECAST LIMIT 20;
