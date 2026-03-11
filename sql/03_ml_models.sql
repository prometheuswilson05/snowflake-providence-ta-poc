-- ============================================================
-- Providence Health & Services - Predictive TA Analytics POC
-- 03: ML Models (Snowflake ML Forecast + Anomaly Detection)
--     Falls back to statistical simulation if ML not available
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA ANALYTICS.PROVIDENCE_TA_POC;

-- ============================================================
-- A) TIME-TO-FILL FORECAST
-- ============================================================

-- Training view: monthly avg TTF by role_family
CREATE OR REPLACE VIEW V_TTF_TRAINING AS
SELECT
    DATE_TRUNC('MONTH', open_date) AS ts,
    role_family,
    region,
    AVG(time_to_fill) AS avg_ttf
FROM TA_HISTORICAL
WHERE outcome = 'filled'
GROUP BY 1, 2, 3;

-- Training view without region (for series-based forecast)
CREATE OR REPLACE VIEW V_TTF_TRAINING_SERIES AS
SELECT
    DATE_TRUNC('MONTH', open_date) AS ts,
    role_family,
    AVG(time_to_fill) AS avg_ttf
FROM TA_HISTORICAL
WHERE outcome = 'filled'
GROUP BY 1, 2;

-- Attempt Snowflake ML Forecast
CREATE OR REPLACE SNOWFLAKE.ML.FORECAST ttf_forecast (
    INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ANALYTICS.PROVIDENCE_TA_POC.V_TTF_TRAINING_SERIES'),
    SERIES_COLNAME => 'ROLE_FAMILY',
    TIMESTAMP_COLNAME => 'TS',
    TARGET_COLNAME => 'AVG_TTF'
);

-- ============================================================
-- B) REQUISITION VOLUME FORECAST
-- ============================================================

CREATE OR REPLACE VIEW V_VOL_TRAINING AS
SELECT
    DATE_TRUNC('MONTH', open_date) AS ts,
    role_family,
    COUNT(*) AS req_volume
FROM TA_HISTORICAL
GROUP BY 1, 2;

CREATE OR REPLACE SNOWFLAKE.ML.FORECAST vol_forecast (
    INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ANALYTICS.PROVIDENCE_TA_POC.V_VOL_TRAINING'),
    SERIES_COLNAME => 'ROLE_FAMILY',
    TIMESTAMP_COLNAME => 'TS',
    TARGET_COLNAME => 'REQ_VOLUME'
);

-- ============================================================
-- C) ANOMALY DETECTION ON BPO COST
-- ============================================================

CREATE OR REPLACE VIEW V_COST_TRAINING AS
SELECT
    DATE_TRUNC('MONTH', open_date) AS ts,
    role_family,
    AVG(bpo_cost_per_hire) AS avg_cost
FROM TA_HISTORICAL
WHERE outcome = 'filled'
GROUP BY 1, 2;

CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION cost_anomaly (
    INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ANALYTICS.PROVIDENCE_TA_POC.V_COST_TRAINING'),
    SERIES_COLNAME => 'ROLE_FAMILY',
    TIMESTAMP_COLNAME => 'TS',
    TARGET_COLNAME => 'AVG_COST',
    LABEL_COLNAME => ''
);
