# L400-03 — Cost Governance & Reporting

**Customer:** Volta Industrial  
**Prepared for:** Operations & Advanced Engineers  
**Classification:** Level 400 — Operations  
**Scope:** Per-plant cost model, budget enforcement, reporting for Fatima  

---

## 1. Purpose

This document defines the operational cost governance model that answers Fatima's question: "If we roll this to all eight plants, what does it cost, and what share of the company AI spend is that?"

---

## 2. Cost Model

### 2.1 Per-Plant Cost Breakdown

| Cost Component | Monthly per Plant | 8 Plants Monthly | Annual |
|---------------|-------------------|------------------|--------|
| AI Gateway (LLM calls) | $400 | $3,200 | $38,400 |
| Lakebase compute | $150 | $1,200 | $14,400 |
| Lakebase storage | $50 | $400 | $4,800 |
| App compute (AppKit) | $100 (shared) | $200 | $2,400 |
| Observability storage | $25 | $200 | $2,400 |
| **Total** | **~$725** | **~$5,200** | **~$62,400** |

### 2.2 ROI Calculation

| Metric | Value |
|--------|-------|
| Annual AI platform cost (8 plants) | ~$62,400 |
| Annual downtime savings target | ~$3,300,000 |
| ROI | ~53:1 |
| Payback period | < 1 week of prevented downtime |

### 2.3 Scaling Model

```
Cost scales LINEARLY with plants:
  1 plant  = ~$725/month
  4 plants = ~$2,900/month
  8 plants = ~$5,200/month (with shared app compute)
  
Cost does NOT scale with:
  - Number of experiments (capped by budget)
  - Number of queries (capped by budget)
  - Model complexity (fixed endpoint)
```

---

## 3. Budget Enforcement Operations

### 3.1 Monthly Budget Cycle

```
Day 1: Budgets reset
Day 1-7: Normal operation, monitoring
Day 7: First utilization check (should be ~25%)
Day 15: Mid-month check (should be ~50%)
Day 22: Alert if any plant > 75%
Day 28: Alert if any plant > 90%
Day 30/31: Month closes, report generated
```

### 3.2 Overage Handling

| Scenario | Action | Escalation |
|----------|--------|-----------|
| Plant at 75% budget | Slack alert to ops | None |
| Plant at 90% budget | Alert to ops + Fatima | Review usage patterns |
| Plant hits 100% | Requests blocked | Fatima decides: increase or wait |
| Single request > $5 | Request blocked | Log for investigation |
| Session > $25 | Session terminated | Alert user + log |

### 3.3 Budget Adjustment Process

```
1. Plant manager reports blocked request
2. Ops reviews usage pattern
3. If legitimate spike → temporary budget increase (requires Fatima approval)
4. If abuse/waste → investigate and remediate
5. Monthly review: adjust base budgets based on actual usage
```

---

## 4. Reporting

### 4.1 Fatima's Monthly Report

```markdown
## Volta Industrial AI Spend Report — {Month} {Year}

### Summary
- Total AI spend: ${total}
- Budget utilization: {pct}%
- Plants active: {n}/8
- Cost per plant (avg): ${avg}

### By Plant
| Plant | Spend | Budget | Utilization | Queries | Avg $/Query |
|-------|-------|--------|-------------|---------|-------------|
| Plant 1 | $380 | $500 | 76% | 2,534 | $0.15 |
| Plant 2 | $420 | $500 | 84% | 2,801 | $0.15 |
| ... | ... | ... | ... | ... | ... |

### Incidents
- {count} budget alerts triggered
- {count} guardrail blocks
- {count} requests > $1

### vs. Downtime Savings
- Downtime hours prevented (estimated): {hours}
- Savings from prevented downtime: ${savings}
- AI cost as % of savings: {pct}%

### Recommendation
{Increase/maintain/decrease budgets based on utilization patterns}
```

### 4.2 Automated Report Generation

```sql
-- Monthly cost report query
SELECT 
  plant_id,
  COUNT(*) as total_queries,
  SUM(cost_usd) as total_spend,
  AVG(cost_usd) as avg_cost_per_query,
  MAX(cost_usd) as max_single_query,
  SUM(cost_usd) / 500.0 * 100 as budget_utilization_pct
FROM volta_industrial.observability.ai_gateway_logs
WHERE request_timestamp >= DATE_TRUNC('month', CURRENT_DATE())
GROUP BY plant_id
ORDER BY total_spend DESC;
```

---

## 5. Execution Checklist

- [ ] Validate cost model assumptions with actual usage data
- [ ] Configure automated monthly report generation
- [ ] Set up Fatima's cost dashboard
- [ ] Configure budget alert escalation paths
- [ ] Document budget adjustment process
- [ ] Create budget increase request template
- [ ] Test budget blocking behavior
- [ ] Present 8-plant cost projection to Fatima

---

*Document Level: L400 — Operations*  
*Audience: FinOps, IT leadership, platform team*  
*Next: [L400-04 — Disaster Recovery](L400-04-disaster-recovery.md)*
