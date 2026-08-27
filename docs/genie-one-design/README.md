# Volta Industrial — Live Production & Supply Intelligence

> Turn a batch lakehouse into a live, governed decision-support application for plant managers.

## The Hero Question

*"Line 4 is trending toward a stop. Pull it now or run it to the end of the shift?"*

## Business Case

| Metric | Value |
|--------|-------|
| Unplanned downtime cost | ~$22K/hour |
| Annual downtime hours | ~1,500 across 8 plants |
| Annual downtime spend | ~$33M |
| Target reduction (Year 1) | ~$3.3M |
| Additional savings | Expedited freight + SLA penalties |

## Personas

| Persona | Role | Core Question |
|---------|------|---------------|
| Annika Sandberg | VP Manufacturing Operations | "Did a plant manager make a different call this shift?" |
| Fatima Zahra Idrissi | Director Manufacturing IT & Finance | "What does this cost at 8 plants, and what share of AI spend is that?" |
| Diego Salazar | Director Plant Systems Engineering | "Will this hold up on the floor when the line is actually going down?" |
| Jonas Weber | Platform Engineering Lead | "When the app gets it wrong, can I find out why before the next shift?" |

## Design Documents

| Level | Audience | Document |
|-------|----------|----------|
| L100 | Executives & Business Sponsors | [Executive Vision](L100-executive-vision/L100-executive-vision.md) |
| L200 | Technical Leadership & Architects | [Platform Architecture](L200-architecture/L200-architecture.md) |
| L300 | Engineers & Implementers | [Detailed Design](L300-detailed-design/) |
| L400 | Operations & Advanced Engineers | [Operations & Governance](L400-operations/) |

## Architecture Principles

1. **Metadata-driven / SDK-like** — Every component reusable across future manufacturing customers
2. **Progressive layering** — Build layer by layer, not one-shot
3. **Governed by default** — Unity Catalog semantics, AI Gateway budgets, full tracing
4. **Branch-based development** — Lakebase long-lived branches (main = prod, dev = iteration)
5. **Decision, not dashboard** — Surface → Prescribe → Approve → Act

## Tech Stack

- **Platform:** Databricks (all public previews & betas enabled)
- **Semantics:** UC Domains, Metric Views, Pages, Genie Code
- **Agent Layer:** Genie Agent(s) as tools
- **App Backend:** Node.js (Databricks AppKit)
- **App Frontend:** React
- **Database:** Lakebase (synced UC tables + writable Postgres)
- **Memory:** Short-term (session) + Long-term (Lakebase AI Search)
- **Observability:** OpenTelemetry (logs, metrics, traces) + MLFlow 3
- **Cost Governance:** Unity AI Gateway (budgets, guardrails, tracing)
- **IaC:** Databricks Asset Bundles / Terraform

## Repo Structure

```
volta-industrial-design/
├── README.md
├── L100-executive-vision/
│   └── L100-executive-vision.md
├── L200-architecture/
│   └── L200-architecture.md
├── L300-detailed-design/
│   ├── L300-01-data-exploration.md
│   ├── L300-02-uc-semantics.md
│   ├── L300-03-lakebase.md
│   ├── L300-04-ai-agent-app.md
│   └── L300-05-ai-gateway.md
├── L400-operations/
│   ├── L400-01-deployment.md
│   ├── L400-02-observability.md
│   ├── L400-03-cost-governance.md
│   └── L400-04-disaster-recovery.md
└── assets/
    ├── erd-silver.md
    ├── erd-gold.md
    └── kpi-reference.md
```
