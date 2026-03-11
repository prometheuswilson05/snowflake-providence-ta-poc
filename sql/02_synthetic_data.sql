-- ============================================================
-- Providence Health & Services - Predictive TA Analytics POC
-- 02: Synthetic Data Generation (~5000 historical + ~2500 actuals)
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE SCHEMA ANALYTICS.PROVIDENCE_TA_POC;

-- ============================================================
-- TABLE: TA_HISTORICAL (2023-2024, ~5000 rows)
-- ============================================================
CREATE OR REPLACE TABLE TA_HISTORICAL (
    req_id          VARCHAR(20),
    role_family     VARCHAR(30),
    department      VARCHAR(50),
    region          VARCHAR(20),
    open_date       DATE,
    fill_date       DATE,
    time_to_fill    INT,
    time_to_start   INT,
    fill_type       VARCHAR(10),
    bpo_cost_per_hire FLOAT,
    service_center_tickets INT,
    outcome         VARCHAR(10)
);

INSERT INTO TA_HISTORICAL
WITH base AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        -- Random seed values
        UNIFORM(1, 1000, RANDOM()) AS r1,
        UNIFORM(1, 100, RANDOM()) AS r2,
        UNIFORM(1, 100, RANDOM()) AS r3,
        UNIFORM(1, 100, RANDOM()) AS r4,
        UNIFORM(1, 100, RANDOM()) AS r5,
        UNIFORM(0, 99, RANDOM()) AS r_outcome,
        UNIFORM(1, 100, RANDOM()) AS r_month_weight,
        UNIFORM(1, 1000, RANDOM()) AS r_ttf_var,
        UNIFORM(1, 100, RANDOM()) AS r_cost_var,
        UNIFORM(1, 30, RANDOM()) AS r_day
    FROM TABLE(GENERATOR(ROWCOUNT => 5000))
),
enriched AS (
    SELECT
        rn,
        -- Role family distribution: Nursing 35%, Clinical Support 15%, Allied Health 10%, IT 20%, Admin 20%
        CASE
            WHEN r2 <= 35 THEN 'Nursing'
            WHEN r2 <= 50 THEN 'Clinical Support'
            WHEN r2 <= 60 THEN 'Allied Health'
            WHEN r2 <= 80 THEN 'IT'
            ELSE 'Admin'
        END AS role_family,

        -- Region distribution: Pacific NW 40%, CA 25%, TX 20%, AK 15%
        CASE
            WHEN r3 <= 40 THEN 'Pacific NW'
            WHEN r3 <= 65 THEN 'CA'
            WHEN r3 <= 85 THEN 'TX'
            ELSE 'AK'
        END AS region,

        -- Month distribution with Q1 higher volume + summer nursing spike
        -- Weight months: Jan-Mar higher, Jun-Aug higher for nursing
        CASE
            WHEN r_month_weight <= 12 THEN 1   -- Jan (higher)
            WHEN r_month_weight <= 23 THEN 2   -- Feb (higher)
            WHEN r_month_weight <= 34 THEN 3   -- Mar (higher)
            WHEN r_month_weight <= 42 THEN 4   -- Apr
            WHEN r_month_weight <= 50 THEN 5   -- May
            WHEN r_month_weight <= 60 THEN 6   -- Jun (summer)
            WHEN r_month_weight <= 70 THEN 7   -- Jul (summer)
            WHEN r_month_weight <= 80 THEN 8   -- Aug (summer)
            WHEN r_month_weight <= 86 THEN 9   -- Sep
            WHEN r_month_weight <= 92 THEN 10  -- Oct
            WHEN r_month_weight <= 96 THEN 11  -- Nov
            ELSE 12                             -- Dec (lowest)
        END AS month_num,

        -- Year: roughly 50/50 split 2023/2024
        CASE WHEN r4 <= 50 THEN 2023 ELSE 2024 END AS year_num,

        -- Outcome: 80% filled, 12% cancelled, 8% open
        CASE
            WHEN r_outcome < 80 THEN 'filled'
            WHEN r_outcome < 92 THEN 'cancelled'
            ELSE 'open'
        END AS outcome,

        -- Fill type: 75% external, 25% internal
        CASE WHEN r5 <= 75 THEN 'external' ELSE 'internal' END AS fill_type,

        r_ttf_var,
        r_cost_var,
        r_day,
        r1
    FROM base
)
SELECT
    'REQ-H-' || LPAD(rn::VARCHAR, 5, '0') AS req_id,

    role_family,

    -- Department based on role family
    CASE role_family
        WHEN 'Nursing' THEN
            CASE MOD(rn, 5)
                WHEN 0 THEN 'Emergency Department'
                WHEN 1 THEN 'ICU'
                WHEN 2 THEN 'Medical-Surgical'
                WHEN 3 THEN 'Labor & Delivery'
                ELSE 'Oncology'
            END
        WHEN 'Clinical Support' THEN
            CASE MOD(rn, 4)
                WHEN 0 THEN 'Pharmacy'
                WHEN 1 THEN 'Lab Services'
                WHEN 2 THEN 'Radiology'
                ELSE 'Respiratory Therapy'
            END
        WHEN 'Allied Health' THEN
            CASE MOD(rn, 4)
                WHEN 0 THEN 'Physical Therapy'
                WHEN 1 THEN 'Occupational Therapy'
                WHEN 2 THEN 'Speech Pathology'
                ELSE 'Social Work'
            END
        WHEN 'IT' THEN
            CASE MOD(rn, 4)
                WHEN 0 THEN 'Epic/EHR'
                WHEN 1 THEN 'Infrastructure'
                WHEN 2 THEN 'Cybersecurity'
                ELSE 'Data & Analytics'
            END
        ELSE -- Admin
            CASE MOD(rn, 4)
                WHEN 0 THEN 'Finance'
                WHEN 1 THEN 'Human Resources'
                WHEN 2 THEN 'Supply Chain'
                ELSE 'Patient Access'
            END
    END AS department,

    region,

    -- Open date
    DATE_FROM_PARTS(year_num, month_num, LEAST(r_day, 28)) AS open_date,

    -- Fill date (only for filled outcomes)
    CASE
        WHEN outcome = 'filled' THEN
            DATEADD(DAY,
                CASE role_family
                    WHEN 'Nursing'          THEN 30 + MOD(r_ttf_var, 30)   -- 30-59, avg ~45
                    WHEN 'IT'               THEN 35 + MOD(r_ttf_var, 40)   -- 35-74, avg ~55
                    WHEN 'Admin'            THEN 15 + MOD(r_ttf_var, 30)   -- 15-44, avg ~30
                    WHEN 'Clinical Support' THEN 25 + MOD(r_ttf_var, 30)   -- 25-54, avg ~40
                    WHEN 'Allied Health'    THEN 30 + MOD(r_ttf_var, 40)   -- 30-69, avg ~50
                END,
                DATE_FROM_PARTS(year_num, month_num, LEAST(r_day, 28))
            )
        ELSE NULL
    END AS fill_date,

    -- Time to fill
    CASE
        WHEN outcome = 'filled' THEN
            CASE role_family
                WHEN 'Nursing'          THEN 30 + MOD(r_ttf_var, 30)
                WHEN 'IT'               THEN 35 + MOD(r_ttf_var, 40)
                WHEN 'Admin'            THEN 15 + MOD(r_ttf_var, 30)
                WHEN 'Clinical Support' THEN 25 + MOD(r_ttf_var, 30)
                WHEN 'Allied Health'    THEN 30 + MOD(r_ttf_var, 40)
            END
        ELSE NULL
    END AS time_to_fill,

    -- Time to start (TTF + 7-21 days onboarding)
    CASE
        WHEN outcome = 'filled' THEN
            CASE role_family
                WHEN 'Nursing'          THEN 30 + MOD(r_ttf_var, 30)
                WHEN 'IT'               THEN 35 + MOD(r_ttf_var, 40)
                WHEN 'Admin'            THEN 15 + MOD(r_ttf_var, 30)
                WHEN 'Clinical Support' THEN 25 + MOD(r_ttf_var, 30)
                WHEN 'Allied Health'    THEN 30 + MOD(r_ttf_var, 40)
            END + 7 + MOD(r1, 15)
        ELSE NULL
    END AS time_to_start,

    -- Fill type
    CASE WHEN outcome = 'filled' THEN fill_type ELSE NULL END AS fill_type,

    -- BPO cost per hire
    CASE
        WHEN outcome = 'filled' THEN
            CASE
                WHEN role_family IN ('Nursing', 'Clinical Support', 'Allied Health') THEN
                    4500 + (r_cost_var / 100.0) * 4000  -- $4,500-$8,500
                ELSE
                    1500 + (r_cost_var / 100.0) * 2000  -- $1,500-$3,500
            END
        ELSE NULL
    END AS bpo_cost_per_hire,

    -- Service center tickets (1-8 per req)
    1 + MOD(r1, 8) AS service_center_tickets,

    outcome

FROM enriched;

-- ============================================================
-- TABLE: TA_ACTUALS_2025 (~2500 rows)
-- ============================================================
CREATE OR REPLACE TABLE TA_ACTUALS_2025 (
    req_id          VARCHAR(20),
    role_family     VARCHAR(30),
    department      VARCHAR(50),
    region          VARCHAR(20),
    open_date       DATE,
    fill_date       DATE,
    time_to_fill    INT,
    time_to_start   INT,
    fill_type       VARCHAR(10),
    bpo_cost_per_hire FLOAT,
    service_center_tickets INT,
    outcome         VARCHAR(10)
);

INSERT INTO TA_ACTUALS_2025
WITH base AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        UNIFORM(1, 1000, RANDOM()) AS r1,
        UNIFORM(1, 100, RANDOM()) AS r2,
        UNIFORM(1, 100, RANDOM()) AS r3,
        UNIFORM(1, 100, RANDOM()) AS r4,
        UNIFORM(0, 99, RANDOM()) AS r_outcome,
        UNIFORM(1, 100, RANDOM()) AS r_month_weight,
        UNIFORM(1, 1000, RANDOM()) AS r_ttf_var,
        UNIFORM(1, 100, RANDOM()) AS r_cost_var,
        UNIFORM(1, 30, RANDOM()) AS r_day
    FROM TABLE(GENERATOR(ROWCOUNT => 2500))
),
enriched AS (
    SELECT
        rn,
        CASE
            WHEN r2 <= 35 THEN 'Nursing'
            WHEN r2 <= 50 THEN 'Clinical Support'
            WHEN r2 <= 60 THEN 'Allied Health'
            WHEN r2 <= 80 THEN 'IT'
            ELSE 'Admin'
        END AS role_family,

        CASE
            WHEN r3 <= 40 THEN 'Pacific NW'
            WHEN r3 <= 65 THEN 'CA'
            WHEN r3 <= 85 THEN 'TX'
            ELSE 'AK'
        END AS region,

        -- 2025 data covers Jan-Dec 2025
        CASE
            WHEN r_month_weight <= 12 THEN 1
            WHEN r_month_weight <= 23 THEN 2
            WHEN r_month_weight <= 34 THEN 3
            WHEN r_month_weight <= 42 THEN 4
            WHEN r_month_weight <= 50 THEN 5
            WHEN r_month_weight <= 60 THEN 6
            WHEN r_month_weight <= 70 THEN 7
            WHEN r_month_weight <= 80 THEN 8
            WHEN r_month_weight <= 86 THEN 9
            WHEN r_month_weight <= 92 THEN 10
            WHEN r_month_weight <= 96 THEN 11
            ELSE 12
        END AS month_num,

        -- Slightly different outcome ratios for 2025: 78% filled, 13% cancelled, 9% open
        CASE
            WHEN r_outcome < 78 THEN 'filled'
            WHEN r_outcome < 91 THEN 'cancelled'
            ELSE 'open'
        END AS outcome,

        CASE WHEN r4 <= 72 THEN 'external' ELSE 'internal' END AS fill_type,

        r_ttf_var,
        r_cost_var,
        r_day,
        r1
    FROM base
)
SELECT
    'REQ-A-' || LPAD(rn::VARCHAR, 5, '0') AS req_id,

    role_family,

    CASE role_family
        WHEN 'Nursing' THEN
            CASE MOD(rn, 5)
                WHEN 0 THEN 'Emergency Department'
                WHEN 1 THEN 'ICU'
                WHEN 2 THEN 'Medical-Surgical'
                WHEN 3 THEN 'Labor & Delivery'
                ELSE 'Oncology'
            END
        WHEN 'Clinical Support' THEN
            CASE MOD(rn, 4)
                WHEN 0 THEN 'Pharmacy'
                WHEN 1 THEN 'Lab Services'
                WHEN 2 THEN 'Radiology'
                ELSE 'Respiratory Therapy'
            END
        WHEN 'Allied Health' THEN
            CASE MOD(rn, 4)
                WHEN 0 THEN 'Physical Therapy'
                WHEN 1 THEN 'Occupational Therapy'
                WHEN 2 THEN 'Speech Pathology'
                ELSE 'Social Work'
            END
        WHEN 'IT' THEN
            CASE MOD(rn, 4)
                WHEN 0 THEN 'Epic/EHR'
                WHEN 1 THEN 'Infrastructure'
                WHEN 2 THEN 'Cybersecurity'
                ELSE 'Data & Analytics'
            END
        ELSE
            CASE MOD(rn, 4)
                WHEN 0 THEN 'Finance'
                WHEN 1 THEN 'Human Resources'
                WHEN 2 THEN 'Supply Chain'
                ELSE 'Patient Access'
            END
    END AS department,

    region,

    DATE_FROM_PARTS(2025, month_num, LEAST(r_day, 28)) AS open_date,

    CASE
        WHEN outcome = 'filled' THEN
            DATEADD(DAY,
                CASE role_family
                    -- Slightly higher TTF in 2025 (+2-3 days on average)
                    WHEN 'Nursing'          THEN 32 + MOD(r_ttf_var, 30)
                    WHEN 'IT'               THEN 38 + MOD(r_ttf_var, 40)
                    WHEN 'Admin'            THEN 17 + MOD(r_ttf_var, 30)
                    WHEN 'Clinical Support' THEN 27 + MOD(r_ttf_var, 30)
                    WHEN 'Allied Health'    THEN 33 + MOD(r_ttf_var, 40)
                END,
                DATE_FROM_PARTS(2025, month_num, LEAST(r_day, 28))
            )
        ELSE NULL
    END AS fill_date,

    CASE
        WHEN outcome = 'filled' THEN
            CASE role_family
                WHEN 'Nursing'          THEN 32 + MOD(r_ttf_var, 30)
                WHEN 'IT'               THEN 38 + MOD(r_ttf_var, 40)
                WHEN 'Admin'            THEN 17 + MOD(r_ttf_var, 30)
                WHEN 'Clinical Support' THEN 27 + MOD(r_ttf_var, 30)
                WHEN 'Allied Health'    THEN 33 + MOD(r_ttf_var, 40)
            END
        ELSE NULL
    END AS time_to_fill,

    CASE
        WHEN outcome = 'filled' THEN
            CASE role_family
                WHEN 'Nursing'          THEN 32 + MOD(r_ttf_var, 30)
                WHEN 'IT'               THEN 38 + MOD(r_ttf_var, 40)
                WHEN 'Admin'            THEN 17 + MOD(r_ttf_var, 30)
                WHEN 'Clinical Support' THEN 27 + MOD(r_ttf_var, 30)
                WHEN 'Allied Health'    THEN 33 + MOD(r_ttf_var, 40)
            END + 7 + MOD(r1, 15)
        ELSE NULL
    END AS time_to_start,

    CASE WHEN outcome = 'filled' THEN fill_type ELSE NULL END AS fill_type,

    CASE
        WHEN outcome = 'filled' THEN
            CASE
                WHEN role_family IN ('Nursing', 'Clinical Support', 'Allied Health') THEN
                    4700 + (r_cost_var / 100.0) * 4000  -- Slightly higher in 2025
                ELSE
                    1600 + (r_cost_var / 100.0) * 2000
            END
        ELSE NULL
    END AS bpo_cost_per_hire,

    1 + MOD(r1, 8) AS service_center_tickets,

    outcome

FROM enriched;

-- Validate row counts
SELECT 'TA_HISTORICAL' AS table_name, COUNT(*) AS row_count FROM TA_HISTORICAL
UNION ALL
SELECT 'TA_ACTUALS_2025', COUNT(*) FROM TA_ACTUALS_2025;

-- Sample data check
SELECT role_family, outcome, COUNT(*), AVG(time_to_fill) AS avg_ttf
FROM TA_HISTORICAL
GROUP BY 1, 2
ORDER BY 1, 2;
