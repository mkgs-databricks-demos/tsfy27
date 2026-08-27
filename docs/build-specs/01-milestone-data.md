# Build Spec 01 — Milestone 1: Data Layer

Build the governed data layer the entire solution runs on: SDP pipeline, metric view, AI/BI dashboard, and Genie space.

---

## Step 1.1 — Generate Raw Data

Run `data_generation/generate_data` with `catalog=ncqai`, `schema=volta_industrial`. This writes 6 parquet datasets to `/Volumes/ncqai/volta_industrial/raw_data/<dataset>/`.

| Dataset | ~Rows | Key Columns |
|---------|-------|-------------|
| `lines` | 1,200 | `line_id` (PK), `plant_id`, `line_name`, `machine_type`, `plant_lat/lng`, `install_date`, `criticality` |
| `parts` | 800 | `part_id` (PK), `part_name`, `part_type`, `machine_type`, `unit_cost_usd`, `lead_time_days`, `local_stock_qty` (0=must expedite), `description` |
| `telemetry` | 3.5M | `line_id` (FK), `telemetry_date`, `vibration_rms`, `temperature_c`, `utilization_pct`, `error_count` |
| `work_orders` | 120K | `wo_id` (PK), `line_id` (FK), `wo_type`, `part_id` (FK), `opened_date`, `closed_date` (NULL=open), `downtime_hours`, `status` |
| `risk_snapshots` | 120K | `line_id` (FK), `snapshot_date`, `failure_risk_score` (0-1), `open_wo_count`, `technician_note_text` |
| `maintenance_events` | 35K | `event_id` (PK), `line_id` (FK), `action_type`, `risk_at_action`, `part_local`, `action_cost_usd`, `downtime_cost_avoided_usd` |

ID formats: `LINE-NNNN`, `PLANT-NN`, `PART-NNNNN`, `WO-NNNNNNNN`, `MEV-NNNNNNNN`.

---

## Step 1.2 — SDP Pipeline

Create pipeline `volta_plant_floor` under `transformation/`. Configure with `configuration: {catalog, schema}`. Read Volume via `read_files('/Volumes/${catalog}/${schema}/raw_data/...')`.

### Silver Layer (Raw -> Silver: joins + expectations + ai_classify)

**`note_risk_flags`** (deduped ai_classify showcase):
- `SELECT DISTINCT technician_note_text` from risk snapshots
- `ai_classify(note, ARRAY('failing','degrading','healthy'))` -> `risk_signal_score` (1.0/0.6/0.1)
- One LLM call per distinct string; silver_risk joins back on the note

**`silver_telemetry`** — per line x day denormalized:
- `raw_telemetry` JOIN `raw_lines`
- Cluster by `telemetry_date`

**`silver_risk`** — current + recent risk position:
- `raw_risk_snapshots` JOIN `raw_lines` JOIN `note_risk_flags`
- Cluster by `snapshot_date`

**`silver_work_orders`** — per-line WO rollup:
- `open_wo_count`, `has_open_corrective`, latest part needed

**`silver_maintenance`** — maintenance-decision history denormalized:
- Powers the model training table

### Gold Layer (Silver -> Gold: aggregations)

Every gold aggregate MUST carry `plant_id`, `machine_type`, and `risk_band` (dashboard-filter contract).

**`gold_line_status`** (the coherence spine — dashboard, metric view, Genie, app all read it):
- One row per line reflecting CURRENT position (snapshot_date = SNAPSHOT_DATE)
- Built from `silver_risk` (current) JOIN latest `silver_telemetry` + `silver_work_orders`
- Key fields: `line_id`, `plant_id`, `line_name`, `machine_type`, `criticality`, `plant_lat/lng`, `vibration_rms`, `temperature_c`, `utilization_pct`, `failure_risk_score`, `open_wo_count`, `has_open_corrective`, `part_local`, `risk_signal_score`
- Derived:
  - `downtime_exposure_usd` = `failure_risk_score x expected_hours x 22000` when score >= 0.6 else 0
  - `risk_band`: `critical` (>= 0.75 AND has_open_corrective), `elevated` (>= 0.6), `watch` (>= 0.4), `healthy` (else)

**`gold_open_atrisk`** — gold_line_status WHERE risk_band IN ('critical','elevated','watch'):
- Enriched with `part_local`, `candidate_part_id`, `part_lead_time_days`, `part_unit_cost_usd`, `criticality`

**`gold_maintenance_outcomes`** — pass-through from silver_maintenance:
- Features: `action_type`, `risk_at_action`, `part_local`, `action_cost_usd`, `downtime_hours`, `avoided_unplanned_stop`, `downtime_cost_avoided_usd`
- Used by: heuristic coefficients + optional ML training

**`gold_maintenance_recommendations`** (the ranked action per at-risk line):
- Built by pipeline HEURISTIC (ML optional)
- For each row in gold_open_atrisk, construct 3 candidate actions and rank by net_value = downtime_cost_avoided - action_cost
- Let `stop = 4h x 22000`:
  - **pull_now**: avoided = `failure_risk_score x stop`, cost = ~40000. Best when risk high AND part not local.
  - **run_to_shift_end**: avoided = ~8000, cost = `failure_risk_score x stop x (0.6 if part_local else 1.0)`. The "defer" baseline that loses on at-risk lines.
  - **expedite_parts_and_run**: avoided = `failure_risk_score x stop x (0.6 if part_local else 0.3)`, cost = `part_unit_cost x 2 + 400` (local) or `part_unit_cost x 3 + lead_time_days x stop_rate` (non-local). Wins on moderate-risk lines with local parts.
- Output columns: `line_id`, `recommended_action`, `predicted_downtime_cost_avoided_usd`, `predicted_net_value_usd`, `action_ranking` (JSON array of all three), `scored_at`
- The mix should be ~50/50 pull_now vs expedite (not 100% one type)

### Consumer Routing (which downstream reads which table)

| Consumer | Needs | From Table |
|----------|-------|------------|
| Dashboard KPIs (exposure $, WOs #, at-risk #) | Risk/downtime by plant + machine_type + risk band | `mv_line_risk` (over `gold_line_status`) |
| Dashboard scatter/map + at-risk widgets | Per-line current position with geo + telemetry + risk + band | `gold_line_status` |
| Genie "which lines are trending to a stop" | Per-line fact with denormalized telemetry + WO + note | `gold_line_status` |
| Failure model training | One row per historical maintenance decision + features + outcome | `gold_maintenance_outcomes` |
| Failure model scoring input | One row per OPEN at-risk line + candidate-action + parts context | `gold_open_atrisk` |
| App floor queue (at-risk + ranked action) | Current at-risk with ranked action + expected downtime cost | `gold_open_atrisk` JOIN `gold_maintenance_recommendations` |
| App analytics drill-downs | Telemetry trend, worst lines, per-plant rollups | `silver_telemetry`, `gold_line_status` |

---

## Step 1.3 — Metric View `mv_line_risk`

Source: `gold_line_status`. Single governed definition of Volta's downtime-exposure metrics.

**Dimensions:** `plant_id`, `machine_type`, `risk_band`, `criticality`, `line_id`

**Measures:**

| Name | Expression |
|------|------------|
| `downtime_exposure` | `SUM(downtime_exposure_usd)` |
| `open_work_orders` | `SUM(open_wo_count)` |
| `line_count` | `COUNT(1)` |
| `critical_count` | `SUM(CASE WHEN risk_band = 'critical' THEN 1 ELSE 0 END)` |
| `elevated_count` | `SUM(CASE WHEN risk_band = 'elevated' THEN 1 ELSE 0 END)` |
| `atrisk_count` | `SUM(CASE WHEN risk_band IN ('critical','elevated') THEN 1 ELSE 0 END)` |
| `avg_failure_risk` | `AVG(failure_risk_score)` |
| `avg_vibration` | `AVG(vibration_rms)` |

**Materialization:** aggregated on `(plant_id, machine_type, risk_band, criticality) x all measures`, refresh every 6h.

**Validation:** `MEASURE(downtime_exposure)` across at-risk ~ $3.3M; `MEASURE(critical_count)` ~ 90.

---

## Step 1.4 — AI/BI Dashboard

Create `Volta Plant Floor` dashboard, saved at project root as `./dashboard.lvdash.json`.

**Theme:**
- Canvas: #F5F7FB (light) / #0F1419 (dark)
- Widget bg: #FFFFFF / #161B22, no borders
- Colors: critical = #E5484D, elevated/watch = #FFB020, healthy = #3C6997

**3 Datasets:**
- `ds_exposure` — from `mv_line_risk` with MEASURE() aggregations
- `ds_lines` — from `gold_line_status` (scatter, rollups)
- `ds_maintenance` — from `gold_maintenance_recommendations` (action mix)

**Global Filters:** Plant, Machine type, Risk band (bind to ds_exposure + ds_lines only, NOT ds_maintenance)

**Page 1 — Plant Floor (the glance):**
- Row 1: Title markdown (story context)
- Row 2: 4 KPI counters (Downtime exposure $, Open WOs #, Critical lines #, At-risk lines #)
- Row 3: Full-width scatter (x=vibration_rms, y=failure_risk_score, color=risk_band, size=open_wo_count)
- Row 4: At-risk lines by plant bar + Downtime exposure by machine type bar

**Page 2 — Maintenance (the deep-dive):**
- Row 1: Title markdown
- Row 2: Highest-exposure table + Rising-risk watch list table
- Row 3: Recommended action mix bar + Total predicted cost avoided counter
- Row 4: Full maintenance recommendations table

---

## Step 1.5 — Genie Space

Create `Volta Plant Floor` Genie Space.

**Tables:** `mv_line_risk`, `gold_line_status`, `gold_open_atrisk`, `gold_maintenance_recommendations`, `raw_parts`, `raw_lines`

**Instructions (full text for the space):**
```
You analyze Volta Industrial plant-floor data for Sam Ortiz (VP Manufacturing Operations, non-technical).

CONTEXT: A high-utilization run ~3 weeks ago wore a cluster of production lines toward failure —
rising vibration/temperature telemetry, open corrective work orders, and parts that would need
expediting if a line stops unplanned. ~90 critical lines across 8 plants, while the rest of the
~1,200-line fleet runs to plan. Unplanned downtime costs ~$22K/hour.

BASELINES: A healthy line sits at failure_risk_score ~0.03-0.2 with vibration in-band. risk_band is
the single signal: 'critical' (risk >= 0.75 with an open corrective WO), 'elevated' (>= 0.6),
'watch' (>= 0.4), 'healthy'. The part_local flag matters: a non-local part makes an unplanned stop
far costlier, which shifts the pull-now-vs-run math.

HEADLINE NUMBERS — always answer from mv_line_risk:
- "What's our downtime exposure?" -> MEASURE(downtime_exposure)
- "How many open work orders?" -> MEASURE(open_work_orders)
- "How many lines are critical?" -> MEASURE(critical_count)

INVESTIGATION FLOW for "which lines are trending to a stop and why?":
1. mv_line_risk -> MEASURE(critical_count) + MEASURE(atrisk_count) by plant_id -> where the risk is
2. gold_line_status -> the at-risk cluster on rising vibration/temperature with open corrective WOs
3. gold_open_atrisk WHERE line_id='LINE-04' -> the hero: high risk, part not local
4. gold_maintenance_recommendations -> the recommended action + predicted downtime cost avoided
Conclude + suggest: "Want me to rank the action for LINE-04?"

ACTION FOLLOW-UP:
- "What should we do about LINE-04?" -> gold_maintenance_recommendations for that line
- "How much downtime cost could we avoid across all at-risk lines?" -> SUM(predicted_downtime_cost_avoided_usd)
- "How many lines should we pull now vs expedite?" -> GROUP BY recommended_action
```

**7-step sample questions (story arc):**
1. "What's our downtime exposure right now, and how many open work orders?"
2. "Which plants is the failure risk concentrated in?"
3. "What do these at-risk lines have in common?"
4. "LINE-04 is trending toward a stop — how bad is it and is the part in stock?"
5. "Should we pull LINE-04 now or run it to the end of the shift?"
6. "Across all at-risk lines, how much downtime cost could we avoid?"
7. "Which lines are best served by expediting the part instead of pulling?"

---

## Step 1.6 (Optional) — ML Failure-Risk Model

Train an XGBoost regressor predicting `downtime_cost_avoided_usd` per (line, action) pair. Trains on `gold_maintenance_outcomes`, scores all lines in `gold_open_atrisk`, overwrites `gold_maintenance_recommendations`. Register to UC as `ncqai.volta_industrial.failure_recommender`. Batch only — no serving endpoint.

---

## Validation Checklist

### Load-Bearing (must pass for full score)

- [ ] **Hero line exists:** `gold_line_status WHERE line_id='LINE-04' AND plant_id='PLANT-03'` -> `failure_risk_score >= 0.75`, `risk_band = 'critical'`, `has_open_corrective = true`, `part_local = false`, `downtime_exposure_usd > 0`
- [ ] **Hero has non-local part:** `gold_open_atrisk WHERE line_id='LINE-04'` -> `part_local = false`, `candidate_part_id` present, `part_lead_time_days > 0`
- [ ] **High-risk cluster:** ~90 critical/elevated lines spread across plants; rest healthy
- [ ] **Anomaly confined:** vast majority of lines are `healthy`
- [ ] **Exposure KPIs land:** `SUM(downtime_exposure_usd)` ~ $3.3M; open corrective WOs ~ 150 (+-20% OK)
- [ ] **risk_signal_score separates:** affected at-risk >= 0.6; healthy <= 0.2
- [ ] **note_risk_flags dedup works:** `COUNT(DISTINCT technician_note_text)` << `COUNT(*)` in risk_snapshots
- [ ] **Maintenance outcomes learnable:** `gold_maintenance_outcomes` GROUP BY `action_type` shows pull_now on high-risk/non-local has best `downtime_cost_avoided` per `action_cost`; run_to_shift_end on low-risk; expedite on moderate
- [ ] **Risk ramp in the past:** daily `AVG(failure_risk_score)` on affected lines shows build ~2.5 weeks ago
- [ ] **Action mix plausible:** ~50/50 pull_now vs expedite (not 100% one type); run_to_shift_end loses on at-risk lines (correct)
- [ ] **LINE-04 recommended_action = 'pull_now'** with action_ranking showing pull_now above others

### Dashboard + Genie

- [ ] Dashboard scatter shows red high-vibration/high-risk cluster
- [ ] KPI tiles match metric view (`MEASURE(downtime_exposure)` ~ $3.3M)
- [ ] LINE-04 appears in highest-exposure table
- [ ] Recommended-action mix is a plausible blend
- [ ] Global filters update every widget
- [ ] Genie "what's our downtime exposure?" matches dashboard tile
- [ ] Genie "which lines are at risk?" returns lines with rising telemetry + open corrective WOs
- [ ] Genie "LINE-04?" -> pull_now with downtime-cost-avoided figure

### Smoke Checks

- [ ] `plant_id` values in PLANT-01..PLANT-08
- [ ] Line geo non-null and in earth-bounds
- [ ] `risk_band` enum is exactly 4 values (critical/elevated/watch/healthy)
- [ ] `gold_open_atrisk` has ~90-200 rows
- [ ] `failure_risk_score` in [0, 1]
- [ ] `vibration_rms` / `temperature_c` never negative

### resources.json Updates

- [ ] `pipeline_id` added after SDP pipeline created
- [ ] `metric_view_name` added after mv_line_risk created
- [ ] `dashboard_id` added after dashboard created
- [ ] `genie_space_id` added after Genie space created
