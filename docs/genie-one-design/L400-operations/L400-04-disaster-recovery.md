# L400-04 — Disaster Recovery & Business Continuity

**Customer:** Volta Industrial  
**Prepared for:** Operations & Advanced Engineers  
**Classification:** Level 400 — Operations  
**Scope:** DR strategy, failover, data integrity, rollback procedures  

---

## 1. Purpose

This document defines disaster recovery and business continuity procedures for the Volta production intelligence platform. The app supports real-time plant floor decisions — downtime of the app itself has operational impact.

---

## 2. Recovery Objectives

| Metric | Target | Rationale |
|--------|--------|-----------|
| **RTO** (Recovery Time Objective) | < 15 minutes | Within-shift decisions can't wait hours |
| **RPO** (Recovery Point Objective) | < 5 minutes | Minimal decision data loss |
| **Availability target** | 99.5% | ~3.6 hours/month allowed downtime |

---

## 3. Failure Scenarios & Response

| Scenario | Impact | Detection | Response | RTO |
|----------|--------|-----------|----------|-----|
| App crash | No new decisions | Health check fails | Auto-restart (AppKit) | < 2 min |
| Lakebase unavailable | No reads/writes | Connection timeout | Failover to read-only mode | < 5 min |
| AI Gateway down | No AI recommendations | Gateway health check | Fallback to rule-based recommendations | < 5 min |
| UC sync stale | Stale risk data | Freshness monitor | Alert + show "data as of" timestamp | < 1 min (graceful) |
| Model endpoint down | No LLM responses | Gateway error rate | Failover to smaller model | < 2 min |
| Full region outage | Everything down | External monitoring | DR region activation | < 15 min |

---

## 4. Graceful Degradation

The app degrades gracefully rather than failing completely:

| Component Down | Degraded Behavior |
|---------------|-------------------|
| LLM unavailable | Show risk scores without AI explanation; rule-based recommendations |
| Lakebase writes fail | Queue decisions locally; sync when restored |
| Search unavailable | Skip historical context; still show current data |
| Reverse sync fails | Decisions still recorded locally; sync backfill when restored |
| Telemetry stale | Show last-known data with "stale" warning + timestamp |

---

## 5. Data Integrity

### 5.1 Decision Data Protection

Decisions are the most critical data — a plant manager's choice must never be lost.

```
Decision recorded in Lakebase (writable Postgres)
       │
       ├── WAL (Write-Ahead Log) ensures durability
       │
       ├── Reverse sync to UC Delta (SCD Type 2) — backup copy
       │
       └── MLFlow trace — independent record of the decision context
```

### 5.2 Sync Integrity Checks

```sql
-- Daily integrity check: decisions in Lakebase vs. UC Delta
SELECT 
  'lakebase_only' as location,
  COUNT(*) as count
FROM app_actions.decisions d
LEFT JOIN volta_industrial.app_actions_history.decisions_scd2 uc
  ON d.decision_id = uc.decision_id
WHERE uc.decision_id IS NULL
  AND d.decided_at < NOW() - INTERVAL '1 hour'

UNION ALL

SELECT 
  'uc_only' as location,
  COUNT(*) as count
FROM volta_industrial.app_actions_history.decisions_scd2 uc
LEFT JOIN app_actions.decisions d
  ON uc.decision_id = d.decision_id
WHERE d.decision_id IS NULL
  AND uc._is_current = TRUE;
```

---

## 6. Backup & Restore

| Component | Backup Method | Frequency | Retention |
|-----------|--------------|-----------|-----------|
| Lakebase (writable tables) | Postgres WAL + snapshots | Continuous + daily | 30 days |
| UC Delta tables | Delta time travel | Continuous | 30 days |
| MLFlow traces | Experiment snapshots | Daily | 90 days |
| AI Gateway config | Git (DABs) | Every commit | Permanent |
| App code | Git | Every commit | Permanent |

### Restore Procedures

```bash
# Restore Lakebase to point-in-time
databricks lakebase restore --instance volta-lakebase --to "2026-08-22T14:00:00Z"

# Restore UC Delta table to previous version
RESTORE TABLE volta_industrial.app_actions_history.decisions_scd2 
TO TIMESTAMP AS OF '2026-08-22T14:00:00Z';

# Rollback app to previous version
databricks apps rollback volta-app-prod --to-version previous
```

---

## 7. Testing

### 7.1 DR Test Schedule

| Test | Frequency | Method |
|------|-----------|--------|
| App failover | Monthly | Kill app instance, verify auto-restart |
| Lakebase failover | Quarterly | Simulate connection failure |
| Gateway failover | Quarterly | Block gateway, verify fallback model |
| Full DR drill | Semi-annually | Simulate region outage |
| Data integrity check | Daily (automated) | Sync comparison query |

### 7.2 Chaos Engineering

```yaml
# Periodic chaos tests (staging only)
chaos_tests:
  - name: "Kill app instance"
    schedule: "monthly"
    action: "terminate random app instance"
    expected: "auto-restart within 2 minutes"
    
  - name: "Block Lakebase"
    schedule: "quarterly"
    action: "firewall Lakebase for 5 minutes"
    expected: "graceful degradation, no data loss"
    
  - name: "Stale sync"
    schedule: "quarterly"
    action: "pause UC sync for 30 minutes"
    expected: "stale data warning shown to users"
```

---

## 8. Execution Checklist

- [ ] Define and document RTO/RPO targets
- [ ] Implement graceful degradation for each failure mode
- [ ] Configure auto-restart for app instances
- [ ] Set up model failover in AI Gateway
- [ ] Implement decision queuing for write failures
- [ ] Create daily data integrity check job
- [ ] Document restore procedures
- [ ] Schedule first DR test
- [ ] Create on-call runbook for each failure scenario
- [ ] Train ops team on restore procedures

---

*Document Level: L400 — Operations*  
*Audience: SRE, platform engineers, on-call staff*  
*This is the final document in the design series.*
