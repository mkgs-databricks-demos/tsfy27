# L300-02 — UC Business Semantics Design

**Customer:** Volta Industrial  
**Prepared for:** Engineers & Implementers  
**Classification:** Level 300 — Detailed Design  
**Scope:** UC Domains, Metric Views, Pages, and Genie Agent configuration  

---

## 1. Purpose

This document defines the Unity Catalog Business Semantics layer for Volta Industrial — the governed, queryable business meaning on top of the lakehouse. This layer is what Genie Agents query, what plant managers interact with through natural language, and what ensures every metric has one definition.

**Key Principle:** UC Metric Views are the single source of truth for business metrics. Genie Agents query Metric Views, not raw tables.

---

## 2. Domain Architecture

### 2.1 Domain Design

Based on the data exploration (L300-01), we define UC Domains that map to Volta's business functions:

| Domain | Subdomain(s) | Business Function | Key Persona |
|--------|-------------|-------------------|-------------|
| **Manufacturing Operations** | Production, Quality | "How are we running?" | Annika |
| **Asset Reliability** | Maintenance, Predictive | "What needs fixing?" | Diego, Jonas |
| **Supply & Parts** | Inventory, Procurement | "Do we have what we need?" | Annika |

### 2.2 Domain Boundaries

**Rule:** A table belongs to exactly one domain. Cross-domain queries are handled by Metric View joins in the AI/BI Dashboard, not by duplicating tables across domains.

```
Manufacturing Operations
├── production_runs
├── production_lines
├── oee_metrics
├── shift_schedules
└── quality_inspections

Asset Reliability
├── machines
├── machine_telemetry
├── work_orders
├── predictive_maintenance_scores
├── failure_modes
└── maintenance_history

Supply & Parts
├── parts_inventory
├── parts_consumption
├── suppliers
├── purchase_orders
└── lead_times
```

### 2.3 Genie Code Domain Definition

```yaml
# domains.yml
domains:
  - name: manufacturing_operations
    display_name: "Manufacturing Operations"
    description: "Production performance, quality, and scheduling across all plants and lines"
    owner: "volta_data_team"
    
  - name: asset_reliability
    display_name: "Asset Reliability"
    description: "Machine health, maintenance, predictive scores, and failure analysis"
    owner: "volta_data_team"
    
  - name: supply_and_parts
    display_name: "Supply & Parts"
    description: "Parts inventory, procurement, supplier performance, and availability"
    owner: "volta_data_team"
```

---

## 3. Metric View Design

### 3.1 Design Principles

1. **One metric, one definition** — No ambiguity about how a metric is calculated
2. **Persona-driven** — Every Metric View answers a persona's question (or anticipated follow-up)
3. **Composable** — Metric Views can be joined for cross-domain analysis
4. **Grain-explicit** — Every Metric View documents its grain (what one row represents)
5. **Time-aware** — Metrics support time-range filtering natively

### 3.2 Metric View Catalog

#### Manufacturing Operations Domain

| Metric View | Grain | Key Measures | Answers |
|-------------|-------|--------------|---------|
| `oee_by_line` | Line × Shift | OEE, Availability, Performance, Quality | "How is Line 4 performing this shift?" |
| `production_output` | Line × Shift | Units produced, target, variance | "Are we on target?" |
| `downtime_events` | Event | Duration, type (planned/unplanned), cost | "What stopped us?" |
| `shift_summary` | Plant × Shift | Total output, total downtime, OEE avg | "How did the shift go?" |

#### Asset Reliability Domain

| Metric View | Grain | Key Measures | Answers |
|-------------|-------|--------------|---------|
| `machine_health_current` | Machine | Health score, risk level, last reading | "Which machines are at risk right now?" |
| `line_risk_score` | Line | Composite risk, contributing factors | "Which lines are trending toward a stop?" |
| `mtbf_mttr` | Machine × Period | MTBF, MTTR, failure count | "How reliable is this machine?" |
| `work_order_status` | Work Order | Status, age, priority, assigned tech | "What maintenance is pending?" |
| `predictive_maintenance` | Machine | PdM score, predicted failure window | "When will this machine fail?" |

#### Supply & Parts Domain

| Metric View | Grain | Key Measures | Answers |
|-------------|-------|--------------|---------|
| `parts_availability` | Part × Plant | On-hand, allocated, available, days of supply | "Do we have the parts to fix it?" |
| `critical_parts_risk` | Part | Shortage risk, lead time, consumption rate | "Which parts might run out?" |
| `supplier_performance` | Supplier | On-time %, quality %, lead time avg | "Can we count on this supplier?" |

#### Cross-Domain (Decision Support)

| Metric View | Grain | Key Measures | Answers |
|-------------|-------|--------------|---------|
| `pull_or_run_decision` | Line × Shift | Risk score, cost-to-pull, cost-to-run, recommendation | **THE HERO QUESTION** |
| `decision_outcomes` | Decision | Decision made, actual outcome, cost delta | "Did the call work?" |
| `ai_spend_by_plant` | Plant × Period | Total AI cost, query count, avg cost/query | "What does this cost?" |

### 3.3 Metric View SQL Pattern

```sql
-- Example: line_risk_score Metric View
CREATE OR REPLACE METRIC VIEW volta_industrial.asset_reliability.line_risk_score
AS
SELECT
  l.line_id,
  l.line_name,
  l.plant_id,
  p.plant_name,
  
  -- Composite risk score (0-100, higher = more risk)
  ROUND(
    (0.4 * AVG(mh.health_risk_score)) +          -- Machine health component
    (0.3 * MAX(pdm.failure_probability)) +         -- Predictive maintenance component
    (0.3 * (1 - MIN(pa.days_of_supply) / 7.0))   -- Parts availability component
  * 100, 1) AS composite_risk_score,
  
  -- Contributing factors
  AVG(mh.health_risk_score) AS avg_machine_risk,
  MAX(pdm.failure_probability) AS max_failure_prob,
  MIN(pa.days_of_supply) AS min_parts_days_supply,
  
  -- Context
  COUNT(DISTINCT CASE WHEN mh.health_risk_score > 0.7 THEN mh.machine_id END) AS machines_at_risk,
  CURRENT_TIMESTAMP() AS calculated_at

FROM volta_industrial.silver.production_lines l
JOIN volta_industrial.silver.plants p ON l.plant_id = p.plant_id
JOIN volta_industrial.gold.machine_health_current mh ON mh.line_id = l.line_id
LEFT JOIN volta_industrial.gold.predictive_maintenance_scores pdm ON pdm.machine_id = mh.machine_id
LEFT JOIN volta_industrial.gold.parts_availability pa ON pa.line_id = l.line_id

GROUP BY l.line_id, l.line_name, l.plant_id, p.plant_name;
```

### 3.4 The Hero Metric View: `pull_or_run_decision`

```sql
-- The metric view that answers the hero question
CREATE OR REPLACE METRIC VIEW volta_industrial.asset_reliability.pull_or_run_decision
AS
SELECT
  lr.line_id,
  lr.line_name,
  lr.plant_id,
  lr.plant_name,
  lr.composite_risk_score,
  
  -- Cost to pull now (planned maintenance)
  mc.planned_maintenance_cost AS cost_to_pull_now,
  
  -- Cost to run (risk-weighted unplanned downtime cost)
  ROUND(
    lr.max_failure_prob *                          -- Probability of failure
    (s.hours_remaining_in_shift) *                 -- Hours of exposure
    22000 *                                        -- $/hr downtime cost
    1.3                                            -- Multiplier for expedited freight + SLA
  , 0) AS expected_cost_to_run,
  
  -- Recommendation
  CASE 
    WHEN lr.composite_risk_score > 75 
     AND (lr.max_failure_prob * s.hours_remaining_in_shift * 22000 * 1.3) > mc.planned_maintenance_cost
    THEN 'PULL_NOW'
    WHEN lr.composite_risk_score > 50
    THEN 'MONITOR_CLOSELY'
    ELSE 'RUN_TO_SHIFT_END'
  END AS recommendation,
  
  -- Decision context
  s.hours_remaining_in_shift,
  s.shift_end_time,
  lr.machines_at_risk,
  lr.min_parts_days_supply,
  
  CURRENT_TIMESTAMP() AS calculated_at

FROM volta_industrial.asset_reliability.line_risk_score lr
JOIN volta_industrial.gold.maintenance_costs mc ON mc.line_id = lr.line_id
JOIN volta_industrial.gold.current_shift_context s ON s.plant_id = lr.plant_id;
```

---

## 4. UC Pages Design

### 4.1 Page Categories

| Category | Purpose | Audience |
|----------|---------|----------|
| **Business Glossary** | Define terms unambiguously | All personas |
| **KPI Definitions** | How each metric is calculated | Analysts, engineers |
| **Operational Context** | Plant hierarchy, shift patterns, cost models | Plant managers, engineers |
| **Methodology** | How risk scores and recommendations work | Technical sponsors |

### 4.2 Page Catalog

#### Business Glossary Pages

| Page | Content |
|------|---------|
| `Planned vs. Unplanned Downtime` | Definitions, classification rules, cost implications |
| `OEE Components` | Availability, Performance, Quality — formulas and interpretation |
| `Risk Score Methodology` | How composite risk is calculated, thresholds, contributing factors |
| `Pull Decision Framework` | When to pull, when to run, cost model explanation |

#### KPI Definition Pages

| Page | Content |
|------|---------|
| `OEE` | Formula, target ranges, industry benchmarks |
| `MTBF / MTTR` | Formulas, what drives improvement, Volta targets |
| `Downtime Cost Model` | $22K/hr derivation, plant-specific adjustments |
| `Parts Availability` | Days of supply calculation, critical thresholds |
| `AI Spend Metrics` | Per-plant cost, per-query cost, budget utilization |

#### Operational Context Pages

| Page | Content |
|------|---------|
| `Plant Hierarchy` | Plants → Lines → Machines → Sensors |
| `Shift Patterns` | Shift definitions, handoff times, coverage |
| `Maintenance Types` | Preventive, predictive, corrective, emergency |
| `Parts Classification` | Critical, standard, consumable — lead time implications |

#### Methodology Pages

| Page | Content |
|------|---------|
| `Predictive Maintenance Model` | Model inputs, training data, confidence intervals |
| `Risk Score Composition` | Weights, normalization, update frequency |
| `Decision Cost Model` | How pull-vs-run costs are calculated |
| `AI Gateway Budget Model` | How per-plant budgets are set and enforced |

### 4.3 Page Template (Genie Code)

```yaml
# pages/oee.yml
pages:
  - name: oee
    display_name: "Overall Equipment Effectiveness (OEE)"
    description: "Definition, formula, and interpretation of OEE"
    domain: manufacturing_operations
    content: |
      ## Definition
      OEE measures how effectively a manufacturing line is utilized.
      It is the product of three factors: Availability, Performance, and Quality.
      
      ## Formula
      OEE = Availability × Performance × Quality
      
      - **Availability** = (Planned Production Time - Downtime) / Planned Production Time
      - **Performance** = (Ideal Cycle Time × Total Count) / Run Time
      - **Quality** = Good Count / Total Count
      
      ## Volta Targets
      - World-class OEE: 85%+
      - Volta current average: ~72%
      - Volta target (post-initiative): 78%+
      
      ## Interpretation
      - OEE < 60%: Significant improvement opportunity
      - OEE 60-75%: Typical for discrete manufacturing
      - OEE 75-85%: Good performance
      - OEE > 85%: World-class
      
      ## Related Metrics
      - MTBF (drives Availability)
      - MTTR (drives Availability)
      - First Pass Yield (drives Quality)
```

---

## 5. Genie Agent Configuration

### 5.1 Agent Strategy

**Decision:** One Genie Agent backed by all Metric Views across domains.

**Rationale:**
- Metric Views are the governed interface — the agent never touches raw tables
- Cross-domain questions ("risk score AND parts availability") are natural
- One agent = one place for plant managers to ask questions
- UC Pages provide context the agent uses to explain answers

### 5.2 Genie Agent Definition

```yaml
# genie_agent.yml
genie_agents:
  - name: volta_production_intelligence
    display_name: "Volta Production Intelligence"
    description: |
      Production and supply intelligence for Volta Industrial plant managers.
      Answers questions about line performance, machine health, maintenance needs,
      parts availability, and pull-vs-run decisions.
    
    metric_views:
      # Manufacturing Operations
      - volta_industrial.manufacturing_operations.oee_by_line
      - volta_industrial.manufacturing_operations.production_output
      - volta_industrial.manufacturing_operations.downtime_events
      - volta_industrial.manufacturing_operations.shift_summary
      
      # Asset Reliability
      - volta_industrial.asset_reliability.machine_health_current
      - volta_industrial.asset_reliability.line_risk_score
      - volta_industrial.asset_reliability.mtbf_mttr
      - volta_industrial.asset_reliability.work_order_status
      - volta_industrial.asset_reliability.predictive_maintenance
      
      # Supply & Parts
      - volta_industrial.supply_and_parts.parts_availability
      - volta_industrial.supply_and_parts.critical_parts_risk
      - volta_industrial.supply_and_parts.supplier_performance
      
      # Cross-Domain Decision Support
      - volta_industrial.asset_reliability.pull_or_run_decision
      - volta_industrial.asset_reliability.decision_outcomes
      - volta_industrial.manufacturing_operations.ai_spend_by_plant
    
    pages:
      - volta_industrial.pages.oee
      - volta_industrial.pages.planned_vs_unplanned_downtime
      - volta_industrial.pages.risk_score_methodology
      - volta_industrial.pages.pull_decision_framework
      - volta_industrial.pages.downtime_cost_model
      - volta_industrial.pages.plant_hierarchy
      - volta_industrial.pages.shift_patterns
    
    instructions: |
      You are a production intelligence assistant for Volta Industrial plant managers.
      
      CONTEXT:
      - Volta operates 8 manufacturing plants
      - Unplanned downtime costs ~$22K/hour
      - Plant managers need within-shift decision support
      
      BEHAVIOR:
      - Always scope answers to the plant the user is asking about
      - When showing risk, always include the recommendation (pull/monitor/run)
      - When showing costs, always show both options (pull now vs. run)
      - Reference UC Pages for methodology explanations
      - Never expose raw table names — speak in business terms
      
      HERO QUESTION:
      When asked about a line trending toward a stop, use the pull_or_run_decision
      metric view and present: risk score, cost to pull, expected cost to run,
      recommendation, and hours remaining in shift.
```

### 5.3 AI/BI Dashboard (Cross-Domain)

When Metric Views from different domains need to be joined (e.g., "show me lines at risk that also have parts shortages"), an AI/BI Dashboard provides the cross-domain view:

| Dashboard Panel | Metric Views Joined | Purpose |
|----------------|--------------------|---------| 
| Risk + Parts Matrix | `line_risk_score` × `parts_availability` | Lines at risk with parts shortages |
| Decision History + Outcomes | `pull_or_run_decision` × `decision_outcomes` | Were past decisions correct? |
| Cost Trend + AI Spend | `downtime_events` × `ai_spend_by_plant` | Is AI spend justified by savings? |

---

## 6. Genie Code Repository Structure

```
genie-code/
├── databricks.yml              # Bundle configuration
├── domains/
│   ├── manufacturing_operations.yml
│   ├── asset_reliability.yml
│   └── supply_and_parts.yml
├── metric_views/
│   ├── manufacturing_operations/
│   │   ├── oee_by_line.sql
│   │   ├── production_output.sql
│   │   ├── downtime_events.sql
│   │   └── shift_summary.sql
│   ├── asset_reliability/
│   │   ├── machine_health_current.sql
│   │   ├── line_risk_score.sql
│   │   ├── mtbf_mttr.sql
│   │   ├── work_order_status.sql
│   │   ├── predictive_maintenance.sql
│   │   └── pull_or_run_decision.sql
│   └── supply_and_parts/
│       ├── parts_availability.sql
│       ├── critical_parts_risk.sql
│       └── supplier_performance.sql
├── pages/
│   ├── oee.yml
│   ├── planned_vs_unplanned_downtime.yml
│   ├── risk_score_methodology.yml
│   ├── pull_decision_framework.yml
│   ├── downtime_cost_model.yml
│   ├── plant_hierarchy.yml
│   └── shift_patterns.yml
├── genie_agents/
│   └── volta_production_intelligence.yml
└── dashboards/
    └── cross_domain_analysis.yml
```

---

## 7. Execution Checklist

- [ ] Create UC Domains (3)
- [ ] Assign tables to domains
- [ ] Implement Metric Views — Manufacturing Operations (4)
- [ ] Implement Metric Views — Asset Reliability (6, including hero)
- [ ] Implement Metric Views — Supply & Parts (3)
- [ ] Write UC Pages — Business Glossary (4)
- [ ] Write UC Pages — KPI Definitions (5)
- [ ] Write UC Pages — Operational Context (4)
- [ ] Write UC Pages — Methodology (4)
- [ ] Configure Genie Agent with all Metric Views + Pages
- [ ] Test Genie Agent with persona questions
- [ ] Build AI/BI Dashboard for cross-domain joins
- [ ] Validate hero question flow end-to-end
- [ ] Document in Genie Code repo structure

---

*Document Level: L300 — Detailed Design*  
*Audience: Analytics engineers, data engineers, Genie developers*  
*Prerequisite: Completed data exploration (L300-01)*  
*Next: [L300-03 — Lakebase Design](L300-03-lakebase.md)*
