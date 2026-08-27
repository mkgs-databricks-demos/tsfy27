# L100 — Executive Vision: Live Production & Supply Intelligence

**Customer:** Volta Industrial  
**Prepared for:** Executive Leadership & Business Sponsors  
**Classification:** Level 100 — Business Vision & Outcomes  

---

## 1. Executive Summary

Volta Industrial operates 8 manufacturing plants generating ~$1.8B in revenue with ~7,000 employees and a growing connected-machine install base. Today, plant managers learn about downtime *after* it happens — reacting to last shift's report rather than preventing this shift's failure.

This initiative transforms Volta's existing Databricks lakehouse — which already ingests machine telemetry, production runs, and work orders — into a **live, governed decision-support application** that tells plant managers which lines are trending toward a stop, whether to pull now or run to end of shift, and the cost of each choice.

**The Hero Question:**  
> *"Line 4 is trending toward a stop. Pull it now or run it to the end of the shift?"*

---

## 2. The Problem

### Current State

- **Reactive reporting:** OEE dashboards and batch predictive-maintenance models exist, but plant managers see downtime *after the fact*
- **No live floor view:** No consolidated real-time picture of machine health and failure risk
- **Signals exist but aren't surfaced:** Telemetry shows failures hours or days beforehand, but only if someone watches the right signal at the right time
- **Manual coordination:** When risk is identified, managers must switch between systems to issue work orders or reorder parts

### Business Impact

| Impact Area | Annual Cost |
|-------------|-------------|
| Unplanned downtime (1,500 hrs × $22K/hr) | ~$33M |
| Expedited freight (air shipping to meet commitments) | Significant |
| SLA penalties (parts shortages to dealer/service network) | Significant |
| Technician reallocation (pulled off planned work) | Productivity loss |

### Root Cause

Unplanned downtime is a line stopping because something broke or a part ran out. It takes the whole line's output with it, pulls technicians off other work, and often forces air freight to make customer commitments. The failures are usually visible in telemetry hours or days beforehand — the gap is surfacing the right signal to the right person at the right time, with a recommended action.

---

## 3. The Vision

### Mission Statement

> Keep every line running and every machine serviced before it fails, so plant managers are never reacting to last shift's downtime report.

### What We're Building

A **live production and supply intelligence application** that:

1. **Surfaces risk** — Prioritizes lines by failure probability and parts-shortage risk in real time
2. **Prescribes action** — Calculates the trade-off: cost of pulling now (planned maintenance) vs. cost of an unplanned stop later
3. **Enables approval** — Presents the decision with full context so the plant manager can act with confidence
4. **Executes** — Issues work orders and triggers parts reorders directly from the decision interface

This is a **decision engine**, not a dashboard. The pattern is: **Surface → Prescribe → Approve → Act.**

### What Changes for Plant Managers

| Today | Tomorrow |
|-------|----------|
| See downtime in yesterday's report | See risk trending *this shift* |
| Manually correlate telemetry signals | AI surfaces the relevant signal with context |
| Switch between systems to act | Approve and execute from one interface |
| No cost visibility for the decision | See cost of each option before choosing |
| Reactive | Proactive |

---

## 4. Business Outcomes

| Outcome | Target | How |
|---------|--------|-----|
| Reduced unplanned downtime | ~$3.3M/yr savings (10% reduction) | Proactive line-pull decisions before failure |
| Lower expedited freight | Measurable reduction | Fewer emergency shipments when lines fail |
| Reduced SLA penalties | Measurable reduction | Parts availability maintained through early action |
| Capped, auditable AI spend | Fixed per-plant cost | AI Gateway budgets prevent runaway spend |
| Real-time decision-making | Shift-level visibility | Live data replaces after-the-fact reporting |
| Full traceability | Every AI recommendation traceable | When the app is wrong, find out why before next shift |

---

## 5. Stakeholder Alignment

### Business Sponsors

| Persona | Role | Success Metric |
|---------|------|----------------|
| **Annika Sandberg** | VP Manufacturing Operations | Plant managers making proactive pull decisions within-shift; measurable downtime reduction |
| **Fatima Zahra Idrissi** | Director Manufacturing IT & Finance | Predictable AI cost per plant; total AI spend visible and bounded |

### Technical Sponsors

| Persona | Role | Success Metric |
|---------|------|----------------|
| **Diego Salazar** | Director Plant Systems Engineering | App performs under real floor conditions; data latency within-shift |
| **Jonas Weber** | Platform Engineering Lead | Full trace from recommendation to telemetry; investigation scoped per-plant |

---

## 6. Why Now

1. **The lakehouse exists** — Telemetry, production runs, and work orders are already ingested and governed in Unity Catalog
2. **Predictive models exist** — Batch maintenance models are running; the gap is operationalizing them
3. **Connected install base is growing** — More machines coming online means more signal, but also more risk if not surfaced
4. **$33M/yr is quantified** — The cost of inaction is clear and defensible
5. **AI cost incident** — A recent runaway query ($1,200 in 2 hours) created executive urgency for governed AI

---

## 7. Approach

### Build Philosophy

- **Progressive, not big-bang** — Layer by layer, value at each stage
- **Governed by default** — Every AI call budgeted, traced, and auditable
- **Decision, not dashboard** — The app recommends and enables action, not just visualization
- **Reusable** — Architecture designed as a pattern for future plants and future customers

### High-Level Phases

| Phase | Deliverable | Value |
|-------|-------------|-------|
| 1. Semantic Foundation | UC Domains, Metric Views, Pages | Governed, queryable business layer |
| 2. Genie Intelligence | Genie Agent(s) over Metric Views | Natural-language access to production data |
| 3. Live Operational Layer | Lakebase sync + app state | Low-latency floor data + action persistence |
| 4. AI Agent Application | AppKit app with decision engine | The hero question answered, shift by shift |
| 5. Cost Governance | AI Gateway budgets + tracing | Bounded, visible, attributable AI spend |

---

## 8. Investment & ROI

### Target ROI

| Investment | Return |
|------------|--------|
| Platform build (one-time) | $3.3M/yr downtime reduction |
| Per-plant rollout (incremental) | Linear cost, compounding value |
| AI spend (capped) | Bounded per-plant, not per-experiment |

### Cost Model Principle

The AI spend must scale **per plant**, not per experiment. Rolling to all 8 plants must have a predictable, linear cost — not an exponential one. This is enforced architecturally through Unity AI Gateway budgets.

---

## 9. Success Criteria

| Criteria | Measurement |
|----------|-------------|
| Plant manager makes a proactive pull decision | Decision log shows within-shift action |
| Unplanned downtime hours decrease | Baseline vs. post-deployment comparison |
| AI spend stays within budget | AI Gateway reports show no overruns |
| Wrong recommendations are traceable | Jonas can trace to root cause before next shift |
| Cost per plant is predictable | Fatima can forecast 8-plant rollout cost |

---

## 10. What's Next

The next document ([L200 — Platform Architecture](../L200-architecture/L200-architecture.md)) details the technical architecture, data flows, and platform components that deliver this vision.

---

*Document Level: L100 — Executive Vision*  
*Audience: Business sponsors, executive leadership, program managers*  
*Not intended for: Implementation details, code patterns, or operational runbooks*
