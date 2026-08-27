# Consolidated Build Specifications

These specs merge the grading requirements from `volta-industrial-original/specifications/` with the architecture best practices from `docs/genie-one-design/` (L100-L400). Follow these documents sequentially to build the full solution.

## Documents

| File | Scope |
|------|-------|
| `00-project-overview.md` | Business context, personas, architecture principles, success criteria |
| `01-milestone-data.md` | Data generation, SDP pipeline, metric view, dashboard, Genie space |
| `02-milestone-lakebase.md` | Lakebase instance, synced tables, writable table, search |
| `03-milestone-app.md` | App architecture, agent tools, pages, demo flow |
| `04-milestone-gateway.md` | AI Gateway budgets, guardrails, tracing |

## Sources

- **Grading rubric / exact requirements:** `volta-industrial-original/README.md` + `specifications/`
- **Architecture vision:** `docs/genie-one-design/L100-executive-vision/`
- **Platform design:** `docs/genie-one-design/L200-architecture/`
- **Detailed designs:** `docs/genie-one-design/L300-detailed-design/`
- **Operations:** `docs/genie-one-design/L400-operations/`

## Build Order

1. Generate data (Step 1.1)
2. Build SDP pipeline (Step 1.2-1.3)
3. Create dashboard + Genie (Step 1.4-1.5)
4. Provision Lakebase (Step 2.1-2.4)
5. Implement app tools (Step 3)
6. Configure AI Gateway (Step 4)
