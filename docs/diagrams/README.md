# Volta Industrial — Architecture Diagrams

Mermaid diagrams for import into Lucid Spark. Each file contains a single Mermaid diagram that can be imported directly.

## How to Import into Lucid Spark

1. Open Lucid Spark
2. Click **Insert** → **Import** → **Mermaid**
3. Paste the content between the ` ```mermaid ` and ` ``` ` fences
4. The diagram will render and can be styled/arranged in Lucid

---

## Diagram Index

| # | Diagram | Level | Description |
|---|---------|-------|-------------|
| 01 | [High-Level Architecture](01-high-level-architecture.md) | L200 | Full platform stack — all layers from sources to presentation |
| 02 | [Data Flow](02-data-flow.md) | L200 | End-to-end data movement: sources → bronze → silver → gold → Lakebase → app → audit |
| 03 | [Decision Flow](03-decision-flow.md) | L300 | Hero question flow: Surface → Prescribe → Approve → Act → Outcome |
| 04 | [UC Semantics](04-uc-semantics.md) | L300 | Domains, Metric Views, Pages, and Genie Agent relationships |
| 05 | [Lakebase Architecture](05-lakebase-architecture.md) | L300 | Schemas, sync directions, extensions, branching |
| 06 | [AI Agent App](06-ai-agent-app.md) | L300 | AppKit components: frontend, backend, tools, memory, observability |
| 07 | [AI Gateway & Governance](07-ai-gateway-governance.md) | L300 | Budgets, guardrails, tracing, model routing |
| 08 | [CI/CD & Deployment](08-cicd-deployment.md) | L400 | Pipeline stages: dev → staging → production + rollback |
| 09 | [Persona → Capability Map](09-persona-capability-map.md) | L100 | How each persona's question maps to platform capabilities |
| 10 | [Observability & Investigation](10-observability-investigation.md) | L400 | Sequence diagram: normal flow + Jonas's investigation |
| 11 | [Delivery Timeline](11-delivery-timeline.md) | L100 | Gantt chart of all build phases |
| 12 | [Silver ERD Template](12-silver-erd-template.md) | L300 | Expected entity-relationship diagram for Silver model |

---

## Diagram Types Used

| Mermaid Type | Diagrams | Best For |
|-------------|----------|----------|
| `graph TB/LR` | 01, 04, 05, 06, 07, 09 | Component architecture, relationships |
| `flowchart` | 02, 03, 08 | Data flows, decision trees, pipelines |
| `sequenceDiagram` | 10 | Request/response flows, investigation |
| `gantt` | 11 | Timeline, phased delivery |
| `erDiagram` | 12 | Entity relationships, data model |

---

## Color Legend (consistent across diagrams)

| Color | Meaning |
|-------|---------|
| Blue (#1a73e8) | Presentation / Consumer layer |
| Purple (#7c4dff) | AI / Agent layer |
| Orange (#e65100) | Governance / Cost control |
| Teal (#00897b) | Semantic / Search layer |
| Green (#2e7d32) | Operational / Production |
| Brown (#5d4037) | Data / Lakehouse layer |
| Gray (#37474f) | Infrastructure / Observability |
| Red (#c62828) | Critical / Alert / Block |
