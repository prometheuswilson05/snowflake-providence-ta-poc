-- ============================================================
-- Providence Health & Services - Predictive TA Analytics POC
-- 04: Validation - Compare ML Forecasts vs 2025 Actuals
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA ANALYTICS.PROVIDENCE_TA_POC;

-- ============================================================
-- Store ML forecast results for 2025 (12 months out from training)
-- ============================================================

-- TTF Forecast for validation
CREATE OR REPLACE TABLE T_TTF_FORECAST_2025 AS
SELECT * FROM TABLE(
    ttf_forecast!FORECAST(
        FORECASTING_PERIODS => 12,
        CONFIG_OBJECT => {'prediction_interval': 0.9}
    )
);

-- Volume Forecast for validation
CREATE OR REPLACE TABLE T_VOL_FORECAST_2025 AS
SELECT * FROM TABLE(
    vol_forecast!FORECAST(
        FORECASTING_PERIODS => 12,
        CONFIG_OBJECT => {'prediction_interval': 0.9}
    )
);

-- Create 2025 cost view for anomaly detection (must be AFTER training timestamps)
CREATE OR REPLACE VIEW V_COST_2025 AS
SELECT
    DATE_TRUNC('MONTH', open_date) AS ts,
    role_family,
    AVG(bpo_cost_per_hire) AS avg_cost
FROM TA_ACTUALS_2025
WHERE outcome = 'filled'
GROUP BY 1, 2;

-- Anomaly detection on 2025 cost data
CREATE OR REPLACE TABLE T_COST_ANOMALIES AS
SELECT * FROM TABLE(
    cost_anomaly!DETECT_ANOMALIES(
        INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ANALYTICS.PROVIDENCE_TA_POC.V_COST_2025'),
        SERIES_COLNAME => 'ROLE_FAMILY',
        TIMESTAMP_COLNAME => 'TS',
        TARGET_COLNAME => 'AVG_COST',
        CONFIG_OBJECT => {'prediction_interval': 0.95}
    )
);

-- Preview forecast outputs
SELECT 'TTF Forecast Preview' AS section;
SELECT * FROM T_TTF_FORECAST_2025 LIMIT 10;

SELECT 'Volume Forecast Preview' AS section;
SELECT * FROM T_VOL_FORECAST_2025 LIMIT 10;

-- ============================================================
-- 2025 Actuals aggregated
-- ============================================================
CREATE OR REPLACE VIEW V_2025_ACTUALS AS
SELECT
    DATE_TRUNC('MONTH', open_date) AS ts,
    role_family,
    AVG(time_to_fill) AS actual_avg_ttf,
    COUNT(*) AS actual_volume,
    AVG(bpo_cost_per_hire) AS actual_avg_cost
FROM TA_ACTUALS_2025
WHERE outcome = 'filled'
GROUP BY 1, 2;

-- ============================================================
-- TTF Validation: MAPE by role_family
-- ============================================================
CREATE OR REPLACE TABLE T_VALIDATION_TTF AS
WITH comparison AS (
    SELECT
        a.ts,
        a.role_family,
        a.actual_avg_ttf,
        f.FORECAST AS predicted_ttf,
        ABS(a.actual_avg_ttf - f.FORECAST) / NULLIF(a.actual_avg_ttf, 0) * 100 AS abs_pct_error
    FROM V_2025_ACTUALS a
    JOIN T_TTF_FORECAST_2025 f
        ON a.role_family = f.SERIES
        AND a.ts = f.TS
)
SELECT
    role_family,
    ROUND(AVG(abs_pct_error), 2) AS mape_pct,
    ROUND(AVG(actual_avg_ttf), 1) AS avg_actual_ttf,
    ROUND(AVG(predicted_ttf), 1) AS avg_predicted_ttf,
    COUNT(*) AS months_compared
FROM comparison
GROUP BY 1
ORDER BY 1;

-- ============================================================
-- Volume Validation: MAPE by role_family
-- ============================================================
CREATE OR REPLACE TABLE T_VALIDATION_VOL AS
WITH comparison AS (
    SELECT
        a.ts,
        a.role_family,
        a.actual_volume,
        f.FORECAST AS predicted_volume,
        ABS(a.actual_volume - f.FORECAST) / NULLIF(a.actual_volume, 0) * 100 AS abs_pct_error
    FROM V_2025_ACTUALS a
    JOIN T_VOL_FORECAST_2025 f
        ON a.role_family = f.SERIES
        AND a.ts = f.TS
)
SELECT
    role_family,
    ROUND(AVG(abs_pct_error), 2) AS mape_pct,
    ROUND(SUM(actual_volume), 0) AS total_actual_vol,
    ROUND(SUM(predicted_volume), 0) AS total_predicted_vol,
    COUNT(*) AS months_compared
FROM comparison
GROUP BY 1
ORDER BY 1;

-- ============================================================
-- Display Results
-- ============================================================
SELECT '=== TTF VALIDATION (MAPE by Role Family) ===' AS section;
SELECT * FROM T_VALIDATION_TTF;

SELECT '=== VOLUME VALIDATION (MAPE by Role Family) ===' AS section;
SELECT * FROM T_VALIDATION_VOL;

-- Overall model accuracy summary
SELECT
    'TTF Model' AS model,
    ROUND(AVG(mape_pct), 2) AS overall_mape_pct,
    CASE WHEN AVG(mape_pct) < 15 THEN 'GOOD' WHEN AVG(mape_pct) < 25 THEN 'ACCEPTABLE' ELSE 'NEEDS IMPROVEMENT' END AS rating
FROM T_VALIDATION_TTF
UNION ALL
SELECT
    'Volume Model',
    ROUND(AVG(mape_pct), 2),
    CASE WHEN AVG(mape_pct) < 15 THEN 'GOOD' WHEN AVG(mape_pct) < 25 THEN 'ACCEPTABLE' ELSE 'NEEDS IMPROVEMENT' END
FROM T_VALIDATION_VOL;

-- Cost anomalies detected
SELECT '=== COST ANOMALIES ===' AS section;
SELECT * FROM T_COST_ANOMALIES WHERE IS_ANOMALY = TRUE ORDER BY TS;
