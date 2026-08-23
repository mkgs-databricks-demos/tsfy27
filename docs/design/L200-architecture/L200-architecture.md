# L200 — Platform Architecture: Live Production & Supply Intelligence

**Customer:** Volta Industrial  
**Prepared for:** Technical Leadership & Architects  
**Classification:** Level 200 — Architecture & Platform Design  

---

## 1. Architecture Overview

This document describes the end-to-end platform architecture that transforms Volta Industrial's existing batch lakehouse into a live, governed decision-support application. The architecture is layered progressively — each layer delivers standalone value while enabling the next.

### Architecture Layers

```
┌─────────────────────────────────────────────────────────────────────┐
│                    PRESENTATION LAYER                                 │
│  Databricks App (React + AppKit)                                     │
│  Decision Engine: Surface → Prescribe → Approve → Act               │
├─────────────────────────────────────────────────────────────────────┤
│                    AI AGENT LAYER                                     │
│  AppKit Agent (Node.js) + Genie Agent Tool(s)                        │
│  Short-term Memory (session) + Long-term Memory (Lakebase AI Search) │
│  MLFlow 3 Traces + OpenTelemetry                                     │
├─────────────────────────────────────────────────────────────────────┤
│                    GOVERNANCE LAYER                                   │
│  Unity AI Gateway (budgets, guardrails, tracing)                     │
│  Per-plant cost caps + MCP governance                                │
├─────────────────────────────────────────────────────────────────────┤
│                    SEMANTIC LAYER                                     │
│  UC Domains + Metric Views + Pages                                   │
│  Genie Agent(s) over governed metrics                                │
│  AI/BI Dashboard (cross-domain joins)                                │
├─────────────────────────────────────────────────────────────────────┤
│                    OPERATIONAL DATA LAYER                             │
│  Lakebase (synced UC tables: read-only)                              │
│  Lakebase (writable Postgres: app state + actions)                   │
│  Lakebase Search (hybrid vector + full-text)                         │
│  Reverse Lakehouse Sync → UC Delta (SCD Type 2)                      │
├─────────────────────────────────────────────────────────────────────┤
│                    LAKEHOUSE LAYER (existing)                         │
│  Bronze: Raw telemetry, ERP extracts, work orders                    │
│  Silver: Cleaned, conformed, keyed entities                          │
│  Gold: Aggregated metrics, OEE, predictive scores                    │
│  Unity Catalog governance throughout                                 │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. Data Flow Architecture

### Ingest → Lakehouse (Existing)

```
Machine Telemetry ──┐
                    ├──→ Bronze (raw) ──→ Silver (conformed) ──→ Gold (metrics)
Production Runs ────┤                                              │
                    │                                              ▼
Work Orders ────────┘                              OEE Dashboards + Batch PdM
```

### Lakehouse → Operational Layer (New)

```
Gold Tables ──────────────────→ Lakebase Sync (read-only Postgres)
                                       │
                                       ▼
                              App reads low-latency data
                                       │
                                       ▼
                              App writes decisions/actions
                                       │
                                       ▼
                              Writable Postgres tables
                                       │
                                       ▼
                              Reverse Lakehouse Sync
                                       │
                                       ▼
                              UC Delta Table (SCD Type 2)
                                       │
                                       ▼
                              Decision audit trail in lakehouse
```

### Decision Flow (App)

```
Telemetry Signal ──→ Risk Score ──→ Surface to Plant Manager
                                          │
                                          ▼
                                   Prescribe Options
                                   ├── Pull now: cost = planned maintenance
                                   └── Run to shift end: cost = P(failure) × $22K/hr × remaining hrs
                                          │
                                          ▼
                                   Manager Approves
                                          │
                                          ▼
                                   Execute (work order / parts reorder)
                                          │
                                          ▼
                                   Log decision (reverse sync to lakehouse)
```

---

## 3. Component Architecture

### 3.1 Unity Catalog Business Semantics

| Component | Purpose | Scope |
|-----------|---------|-------|
| **UC Domains** | Logical grouping of related data assets | Production, Maintenance, Supply Chain |
| **UC Metric Views** | Governed metric definitions queryable by Genie | OEE, MTBF, MTTR, downtime cost, risk scores |
| **UC Pages** | Business glossary and KPI documentation | Industry-standard + Volta-specific definitions |

**Design Principle:** Fewer Genie Agents with better Metric Views > many agents with raw tables.

### 3.2 Genie Agent Layer

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Number of agents | 1 (preferred), max 1 per domain | Simplicity; Metric Views handle cross-cutting queries |
| Backing data | UC Metric Views (not raw tables) | Governed, pre-aggregated, business-meaningful |
| Cross-domain queries | AI/BI Dashboard | When joins across domains are needed |
| Integration | Tool within AppKit Agent | Genie answers data questions; AppKit orchestrates decisions |

### 3.3 Lakebase

| Table Type | Access | Purpose | Example |
|------------|--------|---------|---------|
| Synced UC tables | Read-only | Low-latency production data | `machine_health_current`, `line_risk_scores` |
| Writable Postgres | Read-write | App state and actions | `decisions`, `work_orders`, `agent_sessions` |
| Search-enabled | Read (vector + FTS) | Semantic retrieval | `maintenance_notes`, `work_order_descriptions` |

**Branching Strategy:**
- `main` — Production environment (clean, demo-ready)
- `dev` — Development branch (iterate, test, validate)
- Promote validated changes from `dev` → `main`

**Extensions Required:**
1. `CREATE EXTENSION vector` (pgvector — must be first)
2. `CREATE EXTENSION lakebase_vector` (depends on pgvector)
3. `CREATE EXTENSION lakebase_text` (full-text search)

### 3.4 AI Agent Application

| Component | Technology | Notes |
|-----------|-----------|-------|
| Backend | Node.js (Databricks AppKit) | Required stack — no exceptions |
| Frontend | React | Plant manager decision UI |
| Database | Lakebase | Both synced + writable tables |
| Agent framework | AppKit Agent plugin (beta) | Via latest Databricks CLI |
| Tools | Genie Agent, cost calculator, work order API, parts API | Pluggable via AppKit plugins |
| Short-term memory | Session state (Lakebase writable) | Current conversation context |
| Long-term memory | Lakebase AI Search | Historical decisions, patterns, notes |
| Traces | MLFlow 3 experiment | Every LLM call traced |
| Observability | OpenTelemetry | Logs, metrics, traces |

### 3.5 Unity AI Gateway

| Capability | Implementation | Persona Served |
|------------|---------------|----------------|
| Budget enforcement | Per-plant $ cap, blocks on exceed | Fatima (cost control) |
| Guardrails | Prevent full-table reads from LLM | Jonas (prevent runaway queries) |
| Tracing | All LLM calls logged with full context | Jonas (investigation) |
| MCP governance | Coding-agent traffic routed through gateway | Platform team (audit) |
| Attribution | Spend per user / per call / per plant | Fatima (reporting) |

---

## 4. Infrastructure as Code

All infrastructure is defined as code — no UI-only configuration.

| Component | IaC Tool | Artifacts |
|-----------|----------|-----------|
| Lakebase schema + sync | Databricks Asset Bundles (DABs) | `databricks.yml` + SQL migrations |
| Reverse Lakehouse Sync | DABs or Terraform | Sync definition as code |
| AI Gateway configuration | DABs / Terraform | Budget + guardrail definitions |
| App deployment | Databricks Apps (DABs) | App manifest + build config |
| UC Semantics | Genie Code | Domains, Metric Views, Pages as code |

---

## 5. Security & Governance

### Data Access Model

| Layer | Access Pattern | Governance |
|-------|---------------|------------|
| Lakehouse (Bronze/Silver/Gold) | Unity Catalog RBAC | Existing governance |
| Lakebase (synced) | Read-only; inherits UC permissions | No write path from app |
| Lakebase (writable) | App service principal | Scoped to app state tables |
| AI Gateway | Per-plant budgets | Enforced at gateway level |
| Agent traces | MLFlow 3 + OTel | Full audit trail |

### Plant Isolation

Each plant's data is logically isolated:
- Queries scoped to plant context
- Budgets allocated per plant
- Traces filterable by plant
- Investigation scoped to single plant (Jonas's requirement)

---

## 6. Scalability Model

### Per-Plant Cost Structure

| Component | Scaling Model |
|-----------|---------------|
| Lakebase sync | Per-table, linear with data volume |
| AI Gateway budget | Fixed per plant |
| Agent compute | Shared AppKit deployment, per-request cost |
| Genie queries | Per-query, bounded by gateway |
| Storage | Linear with telemetry volume |

**Key Constraint:** Total AI spend for 8 plants must be predictable and linear — not exponential. The AI Gateway budget is the architectural enforcement mechanism.

---

## 7. Integration Points

### Existing Systems (Read)

| System | Data | Integration |
|--------|------|-------------|
| Machine telemetry (SCADA/IoT) | Sensor readings, vibration, temperature | Already in Bronze |
| ERP (production runs) | Schedules, outputs, line assignments | Already in Bronze |
| CMMS (work orders) | Maintenance history, parts, labor | Already in Bronze |

### New Integrations (Write-back)

| System | Action | Integration |
|--------|--------|-------------|
| CMMS | Issue work order | App → writable Postgres → reverse sync |
| Parts system | Reorder parts | App → writable Postgres → reverse sync |
| Decision log | Record plant manager decisions | App → writable Postgres → reverse sync → UC Delta |

---

## 8. Development Workflow

```
Developer workstation
       │
       ▼
Lakebase dev branch ←──── iterate, test, validate
       │
       ▼ (promote)
Lakebase main branch ←── production / demo environment
       │
       ▼
Databricks Apps deployment
```

### Branch Promotion Criteria

1. Schema migrations pass on dev
2. Sync validation (UC → Lakebase) confirmed
3. Reverse sync (Lakebase → UC Delta) confirmed
4. Agent traces show expected behavior
5. AI Gateway budget not exceeded in test scenarios

---

## 9. Observability Architecture

```
App (AppKit) ──→ OpenTelemetry Collector
                      │
                      ├──→ Logs (structured, per-request)
                      ├──→ Metrics (latency, error rate, throughput)
                      └──→ Traces (distributed, end-to-end)

Agent (LLM calls) ──→ MLFlow 3 Experiment
                           │
                           └──→ Full prompt/response traces
                                Input tokens, output tokens, cost
                                Tool calls (Genie, cost calc, etc.)

AI Gateway ──→ Usage logs
                  │
                  └──→ Per-plant spend attribution
                       Budget utilization alerts
                       Guardrail trigger events
```

---

## 10. What's Next

The L300 detailed design documents cover implementation specifics:

- [L300-01: Data Exploration Methodology](../L300-detailed-design/L300-01-data-exploration.md)
- [L300-02: UC Business Semantics](../L300-detailed-design/L300-02-uc-semantics.md)
- [L300-03: Lakebase Design](../L300-detailed-design/L300-03-lakebase.md)
- [L300-04: AI Agent Application](../L300-detailed-design/L300-04-ai-agent-app.md)
- [L300-05: AI Gateway Configuration](../L300-detailed-design/L300-05-ai-gateway.md)

---

*Document Level: L200 — Platform Architecture*  
*Audience: Technical leadership, solution architects, platform engineers*  
*Not intended for: Business stakeholders (see L100) or implementation code (see L300)*
