# Providence Health & Services - Predictive Talent Acquisition Analytics

**Snowflake ML Proof-of-Value | IBM + Hakkoda**

## Overview

This POC demonstrates how Snowflake's native ML capabilities can transform Providence Health & Services' talent acquisition from reactive backfill to predictive workforce planning. Using 7,500 rows of synthetic TA data modeled after real healthcare hiring patterns, it delivers:

- **Time-to-Fill Forecasting** by role family with 90% confidence intervals
- **Requisition Volume Prediction** with seasonal decomposition
- **BPO Cost Anomaly Detection** to flag unusual spending patterns
- **Revenue-at-Risk Quantification** ($2,500/day clinical, $800/day non-clinical vacancy cost)
- **Executive Dashboard** with quarterly outlook for 2026

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    SNOWFLAKE ACCOUNT                            │
│  Database: ANALYTICS    Schema: PROVIDENCE_TA_POC              │
│                                                                 │
│  ┌─────────────────┐     ┌─────────────────┐                  │
│  │  TA_HISTORICAL   │     │ TA_ACTUALS_2025 │                  │
│  │  5,000 rows      │     │  2,500 rows     │                  │
│  │  (2023-2024)     │     │  (2025)         │                  │
│  └────────┬─────────┘     └────────┬────────┘                  │
│           │                        │                            │
│           ▼                        ▼                            │
│  ┌─────────────────────────────────────────┐                   │
│  │         Training Views                   │                   │
│  │  V_TTF_TRAINING_SERIES  V_VOL_TRAINING  │                   │
│  │  V_COST_TRAINING        V_2025_ACTUALS  │                   │
│  └────────────────┬────────────────────────┘                   │
│                   │                                             │
│                   ▼                                             │
│  ┌─────────────────────────────────────────┐                   │
│  │      Snowflake Native ML Models           │                   │
│  │  SNOWFLAKE.ML.FORECAST (TTF + Volume)   │                   │
│  │  SNOWFLAKE.ML.ANOMALY_DETECTION (Cost)  │                   │
│  │  T_COST_ANOMALIES (flagged anomalies)   │                   │
│  └────────────────┬────────────────────────┘                   │
│                   │                                             │
│                   ▼                                             │
│  ┌─────────────────────────────────────────┐                   │
│  │      Validation & Output                 │                   │
│  │  T_VALIDATION_TTF (MAPE metrics)        │                   │
│  │  T_VALIDATION_VOL (MAPE metrics)        │                   │
│  │  V_2026_FORECAST (12-month outlook)     │                   │
│  │  Executive Dashboard (KPI query)        │                   │
│  └─────────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

- **Snowflake Account** with ACCOUNTADMIN access
- **Snowflake CLI** (`snow`) v3.x+ installed and configured
- **Warehouse**: COMPUTE_WH (XS is sufficient)
- Connection configured in `~/.snowflake/config.toml`

## Deployment

Run each script in order:

```bash
# 1. Create schema
snow sql -f sql/01_schema_setup.sql

# 2. Generate synthetic data (~7,500 rows)
snow sql -f sql/02_synthetic_data.sql

# 3. Build ML/statistical models
#    Try native ML first; if unavailable, use fallback:
snow sql -f sql/03_ml_models.sql
#    OR (if ML functions not available):
snow sql -f sql/03_ml_models_fallback.sql

# 4. Validate models against 2025 actuals
snow sql -f sql/04_validation.sql

# 5. Create 2026 forecast view
snow sql -f sql/05_2026_forecast_view.sql

# 6. Run executive dashboard
snow sql -f sql/06_exec_dashboard.sql
```

## Demo Script

### Recommended presentation order (15-20 min):

1. **Context Setting** (2 min)
   - Providence Health operates across Pacific NW, CA, TX, AK
   - 5 role families: Nursing, IT, Admin, Clinical Support, Allied Health
   - Current challenge: reactive hiring with limited forecasting

2. **Data Foundation** (3 min)
   - Show `TA_HISTORICAL` table structure and row counts
   - Highlight seasonal patterns: `SELECT role_family, MONTH(open_date), COUNT(*) FROM TA_HISTORICAL GROUP BY 1,2 ORDER BY 1,2;`

3. **Model Training & Validation** (5 min)
   - Walk through Snowflake ML.FORECAST and ML.ANOMALY_DETECTION
   - Show MAPE results: `SELECT * FROM T_VALIDATION_TTF;` (TTF MAPE: 1.7%-8.5%)
   - Key point: model accuracy validated against held-out 2025 data

4. **2026 Forecast** (3 min)
   - Show `V_2026_FORECAST` with confidence intervals
   - Drill into Nursing + Pacific NW (highest volume)

5. **Executive Dashboard** (5 min)
   - Run `sql/06_exec_dashboard.sql` live
   - Highlight revenue-at-risk numbers
   - Show cost anomaly detection results

6. **Next Steps** (2 min)
   - Connect real ATS data (Workday, iCIMS)
   - Add region-level granularity to ML models
   - Build Streamlit dashboard for self-service
   - Integrate with IBM watsonx for NLP on job descriptions

## Key Talking Points

### For Providence Health Leadership
- **Revenue at risk is quantified**: Every day a clinical role sits vacant costs ~$2,500 in lost productivity and overtime coverage
- **Seasonal hiring can be planned proactively**: The model identifies June-August nursing surges 6+ months in advance
- **Cost anomalies are caught early**: BPO cost spikes are flagged automatically before they compound

### For IBM / Hakkoda
- **Snowflake-native ML**: No external tools or data movement required — all analytics run inside Snowflake
- **Production-ready path**: Uses native `SNOWFLAKE.ML.FORECAST` and `SNOWFLAKE.ML.ANOMALY_DETECTION` — no external dependencies. Statistical fallback included for accounts without ML access
- **Extensible architecture**: Same pattern applies to attrition prediction, compensation benchmarking, workforce planning

### Data Patterns Modeled
| Role Family | Avg TTF | Volume Share | Cost Range |
|---|---|---|---|
| Nursing | ~45 days | 35% | $4,500 - $8,500 |
| IT | ~55 days | 20% | $1,500 - $3,500 |
| Admin | ~30 days | 20% | $1,500 - $3,500 |
| Clinical Support | ~40 days | 15% | $4,500 - $8,500 |
| Allied Health | ~50 days | 10% | $4,500 - $8,500 |

## File Structure

```
sql/
├── 01_schema_setup.sql          # Schema creation
├── 02_synthetic_data.sql        # 7,500 rows synthetic data
├── 03_ml_models.sql             # Snowflake ML (primary)
├── 03_ml_models_fallback.sql    # Statistical fallback
├── 04_validation.sql            # Model validation vs 2025 actuals
├── 05_2026_forecast_view.sql    # 2026 prediction view
└── 06_exec_dashboard.sql        # Executive KPI dashboard
README.md
```

---

*Built by IBM + Hakkoda for Providence Health & Services | Snowflake ML POC*
