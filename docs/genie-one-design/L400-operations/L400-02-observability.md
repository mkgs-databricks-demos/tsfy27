# L400-02 — Observability & Monitoring

**Customer:** Volta Industrial  
**Prepared for:** Operations & Advanced Engineers  
**Classification:** Level 400 — Operations  
**Scope:** OpenTelemetry, MLFlow 3, alerting, dashboards, runbooks  

---

## 1. Purpose

This document defines the observability stack that ensures the Volta production intelligence app is reliable, performant, and debuggable. It directly supports Jonas's requirement: "When the app gets it wrong, can I find out why before the next shift?"

---

## 2. Observability Stack

```
┌─────────────────────────────────────────────────────┐
│                 ALERTING & DASHBOARDS                 │
│  Databricks SQL Dashboards + PagerDuty/Slack alerts  │
├─────────────────────────────────────────────────────┤
│                 STORAGE & QUERY                       │
│  MLFlow 3 (LLM traces) + UC Delta (OTel exports)    │
├─────────────────────────────────────────────────────┤
│                 COLLECTION                            │
│  OpenTelemetry Collector (logs, metrics, traces)     │
├─────────────────────────────────────────────────────┤
│                 INSTRUMENTATION                       │
│  AppKit auto-instrumentation + custom spans          │
└─────────────────────────────────────────────────────┘
```

---

## 3. OpenTelemetry Configuration

### 3.1 Auto-Instrumentation

```typescript
// otel.config.ts
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-http';

const sdk = new NodeSDK({
  serviceName: 'volta-production-intelligence',
  traceExporter: new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_ENDPOINT + '/v1/traces',
  }),
  metricExporter: new OTLPMetricExporter({
    url: process.env.OTEL_EXPORTER_ENDPOINT + '/v1/metrics',
  }),
  instrumentations: [
    // Auto-instrument HTTP, Postgres, and Express
    getNodeAutoInstrumentations(),
  ],
  resource: {
    attributes: {
      'service.name': 'volta-production-intelligence',
      'deployment.environment': process.env.NODE_ENV,
      'app.version': process.env.APP_VERSION,
    },
  },
});

sdk.start();
```

### 3.2 Custom Spans

```typescript
// Custom spans for business-critical operations
import { trace } from '@opentelemetry/api';

const tracer = trace.getTracer('volta-agent');

async function handleDecision(lineId: string, plantId: string) {
  return tracer.startActiveSpan('decision.hero_question', async (span) => {
    span.setAttribute('plant_id', plantId);
    span.setAttribute('line_id', lineId);
    
    try {
      const result = await processHeroQuestion(lineId, plantId);
      span.setAttribute('risk_score', result.riskScore);
      span.setAttribute('recommendation', result.recommendation);
      span.setStatus({ code: SpanStatusCode.OK });
      return result;
    } catch (error) {
      span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
      throw error;
    } finally {
      span.end();
    }
  });
}
```

---

## 4. MLFlow 3 Tracing

### 4.1 LLM Call Tracing

Every LLM invocation is logged to MLFlow 3 with:

| Field | Content |
|-------|---------|
| Input prompt | Full system + user prompt |
| Output response | Complete model response |
| Token counts | Input tokens, output tokens |
| Cost | Calculated from token usage |
| Latency | End-to-end response time |
| Tool calls | Which tools were invoked, with params |
| Model | Which model served the request |
| Tags | plant_id, session_id, user_id, decision_id |

### 4.2 Trace Search (Jonas's Investigation)

```python
# Jonas's investigation script
import mlflow

# Find traces for a specific decision
traces = mlflow.search_traces(
    experiment_ids=["/volta-industrial/agent-traces"],
    filter_string=f"tags.decision_id = '{decision_id}' AND tags.plant_id = '{plant_id}'",
    order_by=["timestamp ASC"],
)

# Examine the full conversation
for trace in traces:
    print(f"Step: {trace.info.request_id}")
    print(f"  Tool: {trace.data.tags.get('tool_name', 'LLM')}")
    print(f"  Input: {trace.data.request[:200]}...")
    print(f"  Output: {trace.data.response[:200]}...")
    print(f"  Cost: ${trace.data.tags.get('cost_usd', 'N/A')}")
    print(f"  Latency: {trace.info.execution_time_ms}ms")
    print()
```

---

## 5. Key Metrics & Alerts

### 5.1 Application Health

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| Error rate | > 1% | > 5% | Page on-call |
| P95 latency | > 5s | > 15s | Investigate bottleneck |
| Availability | < 99.5% | < 99% | Immediate escalation |
| Active sessions | > 80% capacity | > 95% capacity | Scale up |

### 5.2 AI/Agent Health

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| LLM error rate | > 2% | > 10% | Check gateway/model |
| Guardrail trigger rate | > 5% | > 20% | Review guardrail rules |
| Budget utilization (plant) | > 75% | > 90% | Alert plant manager + Fatima |
| Decision accuracy | < 80% | < 70% | Model review needed |
| Trace storage | > 80% capacity | > 95% | Rotate/archive |

### 5.3 Data Pipeline Health

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| Sync latency (UC → Lakebase) | > 5 min | > 15 min | Check sync job |
| Reverse sync latency | > 10 min | > 30 min | Check reverse sync |
| Data freshness (telemetry) | > 10 min stale | > 30 min stale | Check ingestion |
| Orphan rate (FK integrity) | > 1% | > 5% | Data quality issue |

---

## 6. Alerting Configuration

```yaml
# alerts.yml
alerts:
  - name: "High Error Rate"
    condition: "error_rate > 0.05 for 5 minutes"
    severity: critical
    channels: [pagerduty, slack-#volta-ops]
    runbook: "runbooks/high-error-rate.md"
    
  - name: "Budget 90% Utilized"
    condition: "budget_utilization > 0.90"
    severity: warning
    channels: [slack-#volta-ops, email-fatima]
    runbook: "runbooks/budget-alert.md"
    
  - name: "Sync Stale"
    condition: "sync_latency > 900 seconds"
    severity: critical
    channels: [pagerduty, slack-#volta-ops]
    runbook: "runbooks/sync-stale.md"
    
  - name: "Decision Accuracy Drop"
    condition: "rolling_7d_accuracy < 0.70"
    severity: warning
    channels: [slack-#volta-ops, email-jonas]
    runbook: "runbooks/accuracy-drop.md"
```

---

## 7. Runbooks

### 7.1 High Error Rate

1. Check AI Gateway status (is the model endpoint healthy?)
2. Check Lakebase connectivity (can the app reach the database?)
3. Check recent deployments (was something just promoted?)
4. Check guardrail logs (are legitimate requests being blocked?)
5. If model endpoint down → failover to fallback model
6. If Lakebase down → escalate to platform team
7. If deployment issue → rollback to previous version

### 7.2 Sync Stale

1. Check the sync job status in Databricks
2. Check source table freshness (is upstream data flowing?)
3. Check Lakebase instance health
4. If sync job failed → restart sync job
5. If upstream stale → escalate to data engineering
6. If Lakebase unhealthy → escalate to platform team

---

## 8. Execution Checklist

- [ ] Configure OpenTelemetry SDK in AppKit app
- [ ] Add custom spans for business-critical operations
- [ ] Configure MLFlow 3 experiment for LLM traces
- [ ] Set up alerting rules (application, AI, data pipeline)
- [ ] Configure alert channels (PagerDuty, Slack, email)
- [ ] Build operations dashboard (Jonas)
- [ ] Build cost dashboard (Fatima)
- [ ] Write runbooks for each critical alert
- [ ] Test alert firing (simulate failures)
- [ ] Test investigation workflow (trace a decision end-to-end)
- [ ] Document on-call rotation and escalation paths

---

*Document Level: L400 — Operations*  
*Audience: SRE, on-call engineers, platform team*  
*Next: [L400-03 — Cost Governance](L400-03-cost-governance.md)*
