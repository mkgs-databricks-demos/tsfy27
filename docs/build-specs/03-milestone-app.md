# Build Spec 03 — Milestone 3: Databricks App

Build the internal tool the plant lead actually uses. Node.js + React (AppKit), iterative Vibe + DAS build.

---

## Three Layers

| Layer | What | Status in Bootstrap |
|-------|------|--------------------|
| **Visualize** | Live line risk scatter + queue makes the important thing obvious (red cluster) | Ships working |
| **Assist** | Agent explains why a line is flagged, ranks the action, offers what-if | Tools registered but throw "Not implemented" |
| **Act** | After human approval, writes chosen action to `work_orders_app`; queue cascades live | Tool registered but throw "Not implemented" |

---

## Pages

| Page | Purpose | Key Capability |
|------|---------|---------------|
| **Home** | Narrative landing — story, persona, journey diagram, starter chips, activity feed | Config-driven |
| **Plant Floor** | At-risk line surface — risk scatter/map + queue, KPI cards, detail drawer + Approve/Override | Lakebase OLTP |
| **Analytics** | Warehouse-backed charts: telemetry trend, worst lines, per-plant risk mix | SQL Warehouse on Delta |
| **Dashboard** | Embedded AI/BI dashboard iframe (from Milestone 1) | AI/BI Dashboards |

---

## Agent Architecture

### System Prompt Behavior
- Always scope to the user's plant
- When showing risk, include the recommendation
- When showing costs, show BOTH options with comparison
- Never execute an action without explicit user approval
- Explain reasoning in business terms

### Decision Framework
- Risk > 75 + cost-to-run > cost-to-pull -> Recommend PULL_NOW
- Risk 50-75 -> Recommend MONITOR_CLOSELY
- Risk < 50 -> Recommend RUN_TO_SHIFT_END

### Human-in-the-Loop: Strict 3-Phase Action Chain
1. **Discover** — Read the at-risk line (failure risk, telemetry, open WO, part_local), look up the ranked recommendation (read-only)
2. **Draft + Confirm** — Present ranked options (each with downtime cost avoided, action cost, net value); recommend top one and explain why; offer what-if; draft the work order -> STOP, wait for approval
3. **Execute** (after "yes") — Write approved action + drafted work order to `work_orders_app`, append audit entry — one atomic write

---

## Agent Tools (to implement)

| Tool | What It Does | Phase |
|------|-------------|-------|
| `ask_data` | Delegates to Genie space — investigates failure risk over governed lakehouse | Investigation (ships working) |
| `find_atrisk_line` | Queries Lakebase: at-risk status for a line_id (or worst open) | Discovery (BUILD) |
| `search_parts` | Lakebase Search over parts catalog — find replacement part + local status | Discovery (BUILD) |
| `rank_maintenance_actions` | Queries `app.maintenance_recommendations` — returns ranked options | Discovery (BUILD) |
| `execute_maintenance_action` | Atomic write to `app.work_orders_app` + audit + emits `dataMutated` | Execution (BUILD) |

### Tool Implementation Details

**`find_atrisk_line({ line_id, plant_id })`:**
- Both null -> return worst at-risk line (ORDER BY downtime_exposure_usd DESC LIMIT 1)
- Returns: `{ line_id, plant_id, line_name, plant_name, failure_risk_score, downtime_exposure_usd, current_status, part_local, candidate_part_id, part_lead_time_days }`
- Lakebase helpers: `worstAtriskLine(db)`, `getLineStatus(db, lineId)`
- Wrap in `mlflow.withSpan`

**`rank_maintenance_actions({ line_id })`:**
- Reads `app.maintenance_recommendations` for the line
- Returns: `{ line_id, recommended_action, predicted_downtime_cost_usd, action_ranking: [...] }`
- If null: return `{ scored: false, note: 'No recommendation yet...' }`
- Wrap in `mlflow.withSpan`

**`search_parts({ query })`:**
- Hybrid full-text + vector search over `app.parts` (name + description indexed by Lakebase Search)
- Helper: `searchParts(db, query)` returns top 5-10 matches by relevance
- Returns: `{ matches_found: true, candidates: [{ part_id, part_name, part_category, part_local, lead_time_days }, ...] }`
- If no matches: `{ matches_found: false, note: 'No matching parts found.' }`
- Agent calls this when exploring the expedite-parts-and-run action (alternative parts)
- SQL pattern: `websearch_to_tsquery` over part_name + description columns; optionally vector similarity if indexed
- Wrap in `mlflow.withSpan`
- Optional UI: part search box in Plant Floor detail drawer for manual exploration

**`execute_maintenance_action({ line_id, action_type, part_id, drafted_work_order, predicted_downtime_cost_avoided_usd })`:**
- Requires prior approval in conversation (approval gate in agent instructions)
- Helper: `recordMaintenanceAction(db, args)` — filter-driven, transactional pattern:
  ```ts
  recordMaintenanceAction(db: AppDb, args: {
    lineId: string;
    actionType: 'pull_now' | 'run_to_shift_end' | 'expedite_parts_and_run';
    partId: string | null;
    draftedWorkOrder: string;
    predictedDowntimeCostAvoidsUsd: number | null;
    userEmail: string;
  }): Promise<{ actionId: string }>
  ```
- Writes one `db.transaction`: INSERT into `app.work_orders_app` with:
  - `status = 'approved'`
  - `approved_by = userEmail` (OBO-stamped)
  - `audit_trail = [{ at: now, by: userEmail, action: 'approved', notes: '...', tool: 'execute_maintenance_action' }]::jsonb`
- Returns: `{ recorded: true, action_id, line_id, action_type, predicted_downtime_cost_avoided_usd }`
- The `dataMutated` cascade is ALREADY WIRED (no client code needed):
  - `client/src/chat/useChatTurn.ts` -> `onTurnEnd` -> `dataMutated.emit()`
  - Plant Floor subscribes and refetches automatically
  - KPIs tick, scatter updates, row flips to "action taken" — all without page reload
- Wrap in `mlflow.withSpan`

---

## Plant Floor Page Details

**KPI Cards (3 across):**
- Downtime exposure ($, red) — from metric view over at-risk lines
- Open work orders (#, amber) — open corrective WOs
- Critical lines (#, neutral) — ticks down live when agent acts

**Risk Scatter/Map:**
- x = vibration, y = failure risk, color = risk_band
- Red = critical, amber = watch/elevated, steel = healthy
- Size by downtime exposure; LINE-04 is zoom target

**At-Risk Queue:**
- Status tabs: All / Critical / Elevated / Watch / Action taken
- Columns: Line (id+plant) | Machine type | Vibration | Failure risk | Part local? | Downtime exposure $ | Recommended action (badge) | Status
- Click row -> detail drawer

**Detail Drawer:**
- Line tab: detail grid + parts context + ranked action options + Approve/Override buttons
- Telemetry tab: vibration/temperature sparkline
- Activity tab: merged timeline (agent audit + work orders + who approved)

---

## Analytics Page

Rewrite `config/queries/` for Volta domain:
- `vibration_trend.sql` — AVG vibration on affected vs fleet, last 8 weeks (from silver_telemetry)
- `highest_exposure_lines.sql` — top at-risk lines by exposure (from gold_line_status)
- `risk_mix_by_plant.sql` — line count by plant x risk_band
- `action_mix.sql` (optional) — recommended action mix + total cost avoided

---

## Scripted Demo Flow (~3 min)

1. **"Why is LINE-04 trending toward a stop, and what are my options?"** -> ask_data investigates, find_atrisk_line reads status
2. **"Rank the action. Use the model."** -> rank_maintenance_actions quotes options, search_parts confirms part non-local. Drafts work order. STOPS.
3. **"Yes — pull the line now."** -> execute_maintenance_action writes, dataMutated fires, KPIs tick, scatter updates

---

## What Ships vs What You Build

| Piece | Ships Working | You Build |
|-------|--------------|----------|
| Routing, OBO auth, MLflow tracing, SSE, chat dock | Yes | — |
| Layer 1 — Visualize (plant floor status + queue + KPIs from Lakebase) | Yes | — |
| Agent loop + `ask_data` (Genie/MAS, config-driven) | Yes | Pick backend (Genie) |
| `find_atrisk_line`, `rank_maintenance_actions` | Stub (throws) | Layer 2 (2a + 2b) |
| `search_parts` (Lakebase Search for alternatives) | Stub (throws) | Layer 2c |
| `execute_maintenance_action` + `recordMaintenanceAction` | Stub (throws) | Layer 3 |
| `dataMutated` -> Plant Floor live cascade | Yes (fires on your write) | — |
| Unity AI Gateway governance | Scope declared in app.yaml | Build 3 (config) |

---

## Reset Demo

`POST /api/admin/reset` — truncates `work_orders_app` + re-syncs read-only mirrors. All agent writes wiped; at-risk lines return to their band, KPIs return to full.

---

## Acceptance Scripts (Exact Test Prompts)

**Layer 2 (Assist):**
1. "Why is LINE-04 trending toward a stop, and what are my options?" -> `ask_data` investigates + `find_atrisk_line` returns at-risk line + part (PLANT-03)
2. "Rank the maintenance action. Use the model." -> `rank_maintenance_actions` returns ranking; agent quotes pull_now/run/expedite with costs, recommends pull_now, drafts work order, STOPS for approval
3. Both tool calls appear in Thinking panel and MLflow trace

**Layer 2c (Search Parts):**
1. During ranking, for the expedite option, agent calls `search_parts` with query like "bearing seal"
2. Returns Coupling Seal Assembly as top match with local/remote flag and lead time
3. Agent quotes: "Expedite the Coupling Seal Assembly (14-day lead time, non-local): cost $12K, recaptures $240K downtime"

**Layer 3 (Act):**
1. "Yes — pull the line now." -> `execute_maintenance_action` writes to `work_orders_app`
2. Plant Floor cascades LIVE without reload: at-risk lines -1, LINE-04 row -> "Maintenance Scheduled - pull_now", drawer gains recorded action

---

## Key Files to Edit

| Concern | File |
|---------|------|
| Agent + tools | `server/agent/plantfloor.ts` |
| Lakebase query helpers | `server/db/queries/maintenance.ts` (CREATE) |
| ask_data tool | `server/agent/tools/mas.ts` or `tools/genie.ts` (ships working) |
| Write-refresh cascade | `client/src/lib/events.ts` (dataMutated) |
| Model endpoint / Gateway | `config/app.json` + `app.yaml` |

**Tool-authoring rules:** Agents SDK ships tool schemas with `strict: true` — use `.nullable()` never `.optional()`. Every field needs `.describe(...)`. Snake_case property names. Use `loggedTool` wrapper.

---

## Validation Checklist

- [ ] App boots and shows Plant Floor with at-risk lines
- [ ] Chat dock answers "Why is LINE-04 trending toward a stop?"
- [ ] `find_atrisk_line` returns LINE-04 with risk >= 0.75, part_local = false
- [ ] `rank_maintenance_actions` returns pull_now as recommended for LINE-04
- [ ] Approve -> work order writes to Lakebase
- [ ] KPIs tick live after approval (At-risk count drops, exposure drops)
- [ ] Activity feed shows the action
- [ ] MLflow traces captured for each tool call
