-- ============================================================
-- Providence Health & Services - Predictive TA Analytics POC
-- 01: Schema Setup
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

CREATE DATABASE IF NOT EXISTS ANALYTICS;
CREATE SCHEMA IF NOT EXISTS ANALYTICS.PROVIDENCE_TA_POC;

USE SCHEMA ANALYTICS.PROVIDENCE_TA_POC;

-- Confirm schema is ready
SELECT CURRENT_DATABASE(), CURRENT_SCHEMA();
