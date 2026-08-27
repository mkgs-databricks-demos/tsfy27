# Build Spec 00 — Project Overview

## Business Context

Volta Industrial is a heavy industrial-equipment maker (~$1.8B revenue, 8 plants, ~7,000 employees). A high-utilization production run ~3 weeks ago wore a cluster of production lines toward failure — rising vibration/temperature telemetry, open corrective work orders, and parts that would need expediting if a line stops unplanned. The platform must answer the hero question:

> "LINE-04 is trending toward a stop — pull it now or run it to the end of the shift?"

Unplanned downtime costs ~$22K/hour. The solution surfaces risk, ranks the maintenance action (pull now / run to shift end / expedite parts and run), and lets a plant lead approve it — writing the decision back to the operational store.

---

## Personas

| Persona | Role | Core Question |
|---------|------|---------------|
| Sam Ortiz | VP Manufacturing Operations (non-technical) | "Which lines are trending to a stop and what should I do?" |
| Annika Sandberg | VP Manufacturing Operations | "Did a plant manager make a different call this shift?" |
| Fatima Zahra Idrissi | Director Manufacturing IT & Finance | "What does this cost at 8 plants, and what share of AI spend is that?" |
| Diego Salazar | Director Plant Systems Engineering | "Will this hold up on the floor when the line is actually going down?" |
| Jonas Weber | Platform Engineering Lead | "When the app gets it wrong, can I find out why before the next shift?" |

---

## Architecture Principles

1. **Decision, not dashboard** — Surface -> Prescribe -> Approve -> Act
2. **Governed by default** — Unity Catalog semantics, AI Gateway budgets, full tracing
3. **Metadata-driven / SDK-like** — Every component reusable across future manufacturing customers
4. **Progressive layering** — Build layer by layer (Data -> Lakebase -> App -> Gateway)
5. **Branch-based development** — Lakebase long-lived branches (main = prod, dev = iteration)

---

## Key Numbers

| Metric | Value |
|--------|-------|
| Plants | 8 (PLANT-01 through PLANT-08) |
| Production lines (sampled) | ~1,200 |
| Hero line | LINE-04 at PLANT-03 (Ohio), failure risk ~0.87, part NOT stocked locally |
| At-risk lines (critical/elevated) | ~95 |
| Watch-list lines | ~65 |
| Unplanned-downtime cost | ~$22K/hour |
| Downtime-at-risk exposure | ~$3.3M |
| Open corrective work orders | ~150 |

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| Data Pipeline | Spark Declarative Pipelines (SDP), medallion model |
| Semantics | UC Metric Views, Genie Space |
| Visualization | AI/BI Dashboard |
| Operational DB | Lakebase (synced UC tables + writable Postgres) |
| App Backend | Node.js (Databricks AppKit) |
| App Frontend | React |
| Agent Framework | AppKit Agent plugin |
| Search | Lakebase Search (hybrid vector + full-text) |
| Observability | MLFlow 3 Traces + OpenTelemetry |
| Cost Governance | Unity AI Gateway |
| IaC | Declarative Automation Bundles |

---

## Milestone Summary

| # | Milestone | Done When |
|---|-----------|----------|
| 1 | Data | Running pipeline produces gold tables + metric view + recommendations, with a dashboard and Genie space |
| 2 | Lakebase | Gold tables queryable from Postgres, writable `work_orders_app` exists, parts search ready |
| 3 | App | Plant lead sees at-risk lines, asks why LINE-04 is trending, gets ranked action, approves — work order writes back, queue updates live |
| 4 | AI Gateway | Every AI call goes through the governed Gateway — capped, guardrailed, logged, attributable per plant |

---

## Workspace Configuration

- **Catalog:** `ncqai`
- **Schema:** `ncqai.volta_industrial`
- **Volume:** `ncqai.volta_industrial.raw_data`
- **Working directory:** `/Workspace/Users/matthew.giglia@databricks.com/tsfy27/volta-industrial/`

---

## Success Criteria (Grading)

From the original challenge README — the build is graded on whether:

1. The SDP pipeline runs and produces the correct gold tables with the hero line in the expected state
2. The metric view correctly exposes governed KPIs
3. The dashboard visually tells the story (red cluster, exposure KPIs, action mix)
4. The Genie space answers the 7-step story arc
5. Lakebase serves the data at low latency with a writable action table
6. The app implements Visualize/Assist/Act with human-in-the-loop
7. The AI Gateway governs all model calls with caps, guardrails, and tracing
