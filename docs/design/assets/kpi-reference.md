# Manufacturing KPI Reference

**Purpose:** Industry-standard KPIs for UC Pages and Metric View design  
**Use:** Reference when building Volta's UC Business Semantics layer  

---

## Production KPIs

| KPI | Definition | Formula | Unit | World-Class Target |
|-----|-----------|---------|------|-------------------|
| **OEE** | Overall Equipment Effectiveness | Availability × Performance × Quality | % | > 85% |
| **Availability** | % of planned time the line is running | (Planned Time - Downtime) / Planned Time | % | > 90% |
| **Performance** | Speed relative to ideal cycle time | (Ideal Cycle Time × Total Count) / Run Time | % | > 95% |
| **Quality** | Good parts as % of total | Good Count / Total Count | % | > 99% |
| **TEEP** | Total Effective Equipment Performance | OEE × Planned Production Time / Total Time | % | > 65% |
| **Throughput** | Units produced per time period | Total Units / Time Period | units/hr | Varies |
| **Takt Time** | Required production pace | Available Time / Customer Demand | sec/unit | Varies |
| **Cycle Time** | Actual time to produce one unit | Total Production Time / Units Produced | sec/unit | ≤ Takt |
| **First Pass Yield** | Units passing QC first time | First Pass Good / Total Produced | % | > 95% |
| **Scrap Rate** | Material wasted in production | Scrap Weight / Total Material Input | % | < 2% |
| **Rework Rate** | Units requiring rework | Reworked Units / Total Produced | % | < 3% |

---

## Maintenance KPIs

| KPI | Definition | Formula | Unit | World-Class Target |
|-----|-----------|---------|------|-------------------|
| **MTBF** | Mean Time Between Failures | Total Operating Time / Number of Failures | hours | Varies by equipment |
| **MTTR** | Mean Time To Repair | Total Repair Time / Number of Repairs | hours | < 4 hrs |
| **MTTF** | Mean Time To Failure (non-repairable) | Total Operating Time / Number of Failures | hours | Varies |
| **Availability (Maintenance)** | Equipment available when needed | (MTBF) / (MTBF + MTTR) | % | > 95% |
| **Planned Maintenance %** | Planned vs. total maintenance | Planned Hours / Total Maintenance Hours | % | > 80% |
| **PM Compliance** | Scheduled PMs completed on time | Completed On-Time / Total Scheduled | % | > 95% |
| **Maintenance Cost/Unit** | Maintenance cost per unit produced | Total Maintenance Cost / Units Produced | $/unit | Varies |
| **Maintenance Cost/RAV** | Maintenance as % of asset value | Annual Maintenance Cost / Replacement Asset Value | % | 2-5% |
| **Backlog (weeks)** | Pending work in weeks of capacity | Backlog Hours / Weekly Available Hours | weeks | 2-4 weeks |
| **Emergency Work %** | Unplanned emergency repairs | Emergency Hours / Total Maintenance Hours | % | < 10% |
| **Wrench Time** | Actual hands-on repair time | Hands-on Time / Total Maintenance Time | % | > 55% |

---

## Downtime KPIs

| KPI | Definition | Formula | Unit | Target |
|-----|-----------|---------|------|--------|
| **Unplanned Downtime** | Hours of unplanned stops | Sum of unplanned stop durations | hours | Minimize |
| **Planned Downtime** | Hours of scheduled stops | Sum of planned stop durations | hours | Optimize |
| **Downtime Cost** | Financial impact of stops | Downtime Hours × Hourly Line Cost | $ | Minimize |
| **Downtime Frequency** | How often lines stop | Number of stops / Time Period | stops/week | Minimize |
| **Mean Downtime Duration** | Average length of a stop | Total Downtime / Number of Events | hours | < 2 hrs |
| **Top Downtime Causes** | Pareto of stop reasons | Ranked by duration or frequency | - | Address top 3 |

---

## Supply Chain KPIs

| KPI | Definition | Formula | Unit | Target |
|-----|-----------|---------|------|--------|
| **Parts Availability** | Parts in stock when needed | Parts Available / Parts Requested | % | > 97% |
| **Stockout Frequency** | How often parts run out | Stockout Events / Time Period | events/month | < 2 |
| **Days of Supply** | How long current stock lasts | On-Hand Inventory / Daily Consumption | days | 5-15 days |
| **Inventory Turns** | How fast inventory cycles | Annual COGS / Average Inventory Value | turns/yr | > 6 |
| **Supplier On-Time Delivery** | Supplier reliability | On-Time Deliveries / Total Deliveries | % | > 95% |
| **Supplier Lead Time** | Days from order to receipt | AVG(Receipt Date - Order Date) | days | Varies |
| **Fill Rate** | Orders fulfilled completely | Complete Orders / Total Orders | % | > 98% |
| **Carrying Cost** | Cost to hold inventory | (Storage + Insurance + Depreciation) / Avg Inventory | % | 15-25% |

---

## Financial KPIs

| KPI | Definition | Formula | Unit | Target |
|-----|-----------|---------|------|--------|
| **Cost Per Unit** | Total cost per unit produced | Total Production Cost / Units Produced | $/unit | Minimize |
| **Labor Productivity** | Output per labor hour | Units Produced / Labor Hours | units/hr | Maximize |
| **Energy Cost/Unit** | Energy per unit produced | Total Energy Cost / Units Produced | $/unit | Minimize |
| **Capacity Utilization** | Actual vs. maximum output | Actual Output / Maximum Possible Output | % | 80-90% |
| **Manufacturing Cost Variance** | Actual vs. standard cost | (Actual Cost - Standard Cost) / Standard Cost | % | < 5% |

---

## Volta-Specific KPIs

| KPI | Definition | Formula | Volta Context |
|-----|-----------|---------|---------------|
| **Downtime Cost/Hour** | Revenue impact per hour of downtime | Fixed at ~$22,000/hr | Across all plants |
| **Annual Downtime Spend** | Total annual downtime cost | ~1,500 hrs × $22K | ~$33M baseline |
| **Pull Decision Accuracy** | Correct AI recommendations | Correct Decisions / Total Decisions | Target > 80% |
| **Decision Response Time** | Time from alert to action | Decision Timestamp - Alert Timestamp | Target < 30 min |
| **AI Cost/Decision** | Cost per AI-assisted decision | Total AI Spend / Decisions Made | Target < $2 |
| **Prevented Downtime** | Hours saved by proactive pulls | Estimated hours that would have been lost | Track monthly |

---

## KPI Relationships (for Metric View Design)

```
OEE = Availability × Performance × Quality
  │
  ├── Availability ← MTBF, MTTR, Planned Maintenance %
  │                 ← Downtime Events (planned vs. unplanned)
  │                 ← Parts Availability (stockouts cause downtime)
  │
  ├── Performance ← Cycle Time vs. Takt Time
  │               ← Speed losses, minor stops
  │
  └── Quality ← First Pass Yield, Scrap Rate, Rework Rate

Downtime Cost = Downtime Hours × $22K/hr
  │
  ├── Unplanned Downtime ← MTBF (lower = more failures)
  │                      ← Parts Availability (stockout = stop)
  │                      ← PdM Score (predicted failures)
  │
  └── Recovery Time ← MTTR (repair speed)
                    ← Parts Availability (parts on hand?)
                    ← Technician Availability (wrench time)
```

---

*This reference informs UC Page content and Metric View design.*  
*Update as Volta-specific KPIs are refined during data exploration.*
