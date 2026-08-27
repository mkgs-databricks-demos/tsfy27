# PROJECT_MEMORY.md — Volta Industrial (Tech Summit FY27)

Canonical long-term memory for this project. Read at session start.

---

## Folder Structure & Rules

| Folder | Purpose | Editable? |
|--------|---------|----------|
| `volta-industrial-original/` | Original bundle from the Tech Summit FY27 Build Challenge. Reference only. | NO — do not touch |
| `volta-industrial/` | Working copy. All edits, builds, and deployments happen here. | YES |
| `docs/genie-one-design/` | Design documents created from customer requirements + whiteboarding session. Architecture vision (L100-L400). | Reference |
| `docs/build-specs/` | (To be created) Consolidated build specifications merging the design docs with original bundle specs. | YES |

**Rule:** `volta-industrial-original/` is frozen. Use it as a reference — especially the README and `specifications/` folder which contain the grading rubric and full requirements for achieving a perfect score on the build challenge.

---

## Project Context

- **Challenge:** Tech Summit FY27 Live Days AI Customer Challenge
- **Use case:** Volta Industrial — downtime & maintenance rescue for heavy industrial equipment
- **Hero question:** "LINE-04 is trending toward a stop — pull it now or run it to the end of the shift?"
- **Workspace host:** (set per session)
- **Bundle name:** `workshop-volta-industrial`
- **Catalog:** `ncqai` (confirmed available; `dbdemos_templates` does not exist on this workspace)
- **Schema:** `ncqai.volta_industrial` (created)
- **Volume:** `ncqai.volta_industrial.raw_data` (created)

---

## Four Milestones (Grading Criteria)

1. **Data** — SDP pipeline (silver + gold + heuristic recommendations), metric view `mv_line_risk`, AI/BI dashboard + Genie space
2. **Lakebase** — Autoscaling instance, synced gold tables (read-only), writable `work_orders_app`, Lakebase Search on parts
3. **Databricks App** — Node.js + React (AppKit), Visualize/Assist/Act layers, human-in-the-loop approval
4. **Unity AI Gateway** — Spend cap, guardrails, inference logging, per-plant attribution

---

## Key Data Model

### Raw datasets (parquet in UC Volume `raw_data/`)

| Dataset | ~Rows | Key columns |
|---------|-------|-------------|
| `raw_lines` | 1,200 | `line_id`, `plant_id`, `machine_type`, `plant_lat/lng`, `criticality` |
| `raw_parts` | 800 | `part_id`, `machine_type`, `part_type`, `unit_cost_usd`, `local_stock_qty`, `description` |
| `raw_telemetry` | 3.5M | `line_id`, `vibration_rms`, `temperature_c`, `utilization_pct`, per day |
| `raw_work_orders` | 120K | `wo_type`, `opened_date`, `closed_date` (NULL=open), `part_id`, `downtime_hours` |
| `raw_risk_snapshots` | 120K | `failure_risk_score`, `risk_band`, `technician_note_text` |
| `raw_maintenance_events` | 35K | `action_type`, `downtime_cost_avoided_usd`, training data for ML model |

### Gold tables (built by SDP pipeline)

- `gold_line_status` — current per-line position (risk, telemetry, WO backlog, geo)
- `gold_open_atrisk` — at-risk lines + parts context (`part_local`, `candidate_part_id`)
- `gold_maintenance_outcomes` — historical decision outcomes (model training)
- `gold_maintenance_recommendations` — ranked action per line (heuristic or ML)

### Metric View

- `mv_line_risk` — governed KPI definitions (downtime_exposure, open_work_orders, critical_count, etc.)

---

## Architecture Decisions (from design docs)

- **Stack:** Node.js + React + Express (AppKit); Lakebase for OLTP; UC for governance
- **Agent pattern:** Surface -> Prescribe -> Approve -> Act (decision engine, not dashboard)
- **Branching:** Lakebase `main` = prod, `dev` = iteration
- **Genie:** Single Genie space over metric views, not raw tables
- **AI Gateway:** Per-plant $500/mo budget cap, $5 per-request cap, $25 per-session cap
- **Observability:** MLFlow 3 traces + OpenTelemetry
- **IaC:** Declarative Automation Bundles (DABs)

---

## Setup Steps

The Databricks CLI is not available in Genie Code sessions. Use the **web terminal** for bundle commands, or run the data gen notebook manually.

### Option A: Web Terminal (bundle)
```bash
cd /Workspace/Users/matthew.giglia@databricks.com/tsfy27/volta-industrial
databricks bundle deploy -var="catalog=ncqai"
databricks bundle run volta_setup
```

### Option B: Manual (no CLI)
1. Schema + Volume already created (`ncqai.volta_industrial` + `raw_data`)
2. Open `volta-industrial/data_generation/generate_data` as a notebook
3. Set widgets: `catalog=ncqai`, `schema=volta_industrial`
4. Run all cells

### Current state
- Schema `ncqai.volta_industrial`: CREATED
- Volume `ncqai.volta_industrial.raw_data`: CREATED
- Data generation: PENDING (requires notebook execution or web terminal)

---

## Design Docs Summary (docs/genie-one-design/)

| Level | Document | Key content |
|-------|----------|-------------|
| L100 | Executive Vision | Business case ($33M annual downtime, target $3.3M reduction), personas, success criteria |
| L200 | Platform Architecture | 6-layer architecture, data flow diagrams, component decisions |
| L300-01 | Data Exploration | Methodology for profiling, ERD generation, key analysis |
| L300-02 | UC Semantics | Domain architecture, metric view catalog (12+ views), Pages design |
| L300-03 | Lakebase | Schema separation (synced_uc / app_state / app_actions / app_search), extensions, branching |
| L300-04 | AI Agent App | Agent config, tool definitions, memory design, decision flow |
| L300-05 | AI Gateway | Budget hierarchy, guardrails, tracing config, MCP governance |
| L400-01 | Deployment | IaC patterns |
| L400-02 | Observability | Monitoring strategy |
| L400-03 | Cost Governance | Budget enforcement |
| L400-04 | Disaster Recovery | DR strategy |

---

## Open Decisions

- ~~Catalog/schema~~ RESOLVED: using `ncqai.volta_industrial`
- ~~ML model~~ RESOLVED: attempt it (Milestone 1.6 — XGBoost regressor, overwrites gold_maintenance_recommendations)
- ~~Genie vs MAS~~ RESOLVED: Use Genie Space. Rubric requires building ONE Genie Space ("Volta Plant Floor") — it's a graded buildable. App's `ask_data` connects via `GENIE_SPACE_ID`. No MAS endpoint needed, no multiple agents.
- ~~Bundle variable override~~ RESOLVED: `databricks.yml` updated to default catalog = `ncqai`
- Data generation: user will handle via web terminal or manual notebook run
