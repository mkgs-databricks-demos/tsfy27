# Build Spec 02 — Milestone 2: Lakebase

Serve the data at low latency + add the operational store the app writes to.

---

## Step 2.1 — Create Lakebase Instance

- Create a Lakebase Postgres project (autoscaling)
- Create a `dev` branch to iterate safely (main = prod, dev = iteration)
- Extensions to install (in order):
  1. `CREATE EXTENSION IF NOT EXISTS vector;` (pgvector — must be first)
  2. `CREATE EXTENSION IF NOT EXISTS lakebase_vector;`
  3. `CREATE EXTENSION IF NOT EXISTS lakebase_text;`

---

## Step 2.2 — Sync Gold Tables (Read-Only)

Sync the following UC tables into Lakebase as read-only mirrors in the `app` schema:

| Lakebase Table | Source Delta Table | Key Columns |
|----------------|-------------------|-------------|
| `app.line_status` | `gold_line_status` | lineId, plantId, lineName, machineType, criticality, plantLat/Lng, vibrationRms, temperatureC, failureRiskScore, openWoCount, hasOpenCorrective, partLocal, downtimeExposureUsd, riskBand |
| `app.open_atrisk` | `gold_open_atrisk` | lineId (PK), failureRiskScore, downtimeExposureUsd, partLocal, candidatePartId, partLeadTimeDays |
| `app.maintenance_recommendations` | `gold_maintenance_recommendations` | lineId (PK), recommendedAction, predictedDowntimeCostAvoidedUsd, predictedNetValueUsd, actionRanking (JSONB) |
| `app.parts` | `raw_parts` | partId (PK), partName, partType, machineType, unitCostUsd, leadTimeDays, localStockQty, description |

These are **never written by the app** — they are the governed lakehouse served at low latency.

---

## Step 2.3 — Writable Table `work_orders_app`

The only table the app writes to. Records approved maintenance decisions.

```sql
CREATE TABLE app.work_orders_app (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  line_id VARCHAR(50) NOT NULL,
  action_type VARCHAR(50) NOT NULL,  -- 'pull_now' / 'run_to_shift_end' / 'expedite_parts_and_run'
  part_id VARCHAR(50),               -- nullable (only for expedite)
  drafted_wo TEXT,                    -- the work order text the agent wrote
  predicted_downtime_cost_avoided_usd DECIMAL(12,2),
  status VARCHAR(50) DEFAULT 'proposed',  -- proposed/approved/executed/overridden
  approved_by VARCHAR(255),           -- OBO-stamped user email
  audit_trail JSONB DEFAULT '[]',     -- append-only timeline
  created_at TIMESTAMPTZ DEFAULT NOW(),
  decided_at TIMESTAMPTZ
);
```

The Plant Floor derives a line's live state by LEFT JOIN-ing `line_status` -> its latest `work_orders_app` row. KPIs recompute as lines gain an action.

---

## Step 2.4 — Lakebase Search (Parts Catalog)

Enable hybrid search (vector + full-text) on the `parts` table over `(part_name, description)`. This powers the app's **expedite-parts** play — matching a line's failing machine to a replacement part and checking whether it's stocked locally.

```sql
-- Full-text search index
CREATE INDEX idx_parts_search ON app.parts USING GIN (to_tsvector('english', part_name || ' ' || description));

-- Vector similarity index (if embeddings are populated)
CREATE INDEX idx_parts_embedding ON app.parts USING ivfflat (embedding vector_cosine_ops) WITH (lists = 50);
```

---

## Schema Architecture (from design docs)

The design docs recommend separating into logical schemas:

```
Lakebase Instance
├── app (the build challenge scope)
│   ├── line_status          (synced, read-only)
│   ├── open_atrisk          (synced, read-only)
│   ├── maintenance_recommendations (synced, read-only)
│   ├── parts                (synced, read-only, search-indexed)
│   ├── work_orders_app      (writable)
│   ├── conversations        (writable, chat state)
│   ├── messages             (writable, chat state)
│   └── feedback             (writable, thumbs up/down)
```

For production scale-out (from L300-03), consider additional schemas: `app_state` (sessions, preferences), `app_actions` (decisions, work orders, parts reorders), `app_search` (searchable text with embeddings, decision rationales as long-term memory). For the build challenge, a single `app` schema suffices.

---

## Sync Strategy

For production: **Lakebase Synced Tables** (managed, continuous). For the demo build: the app's `server/db/sync.ts` pulls via the Databricks SQL Statements API at boot (chunked inserts, 2000/batch, skip on conflict).

"Reset demo" -> truncate `work_orders_app` + re-sync read-only mirrors.

---

## Branching Strategy (from design docs)

- `main` — Production / demo-ready (clean)
- `dev` — Development branch (iterate, test, validate)
- Promote validated changes from `dev` -> `main`

---

## Validation Checklist

- [ ] Lakebase instance created and accessible
- [ ] `dev` branch created
- [ ] Extensions installed (vector, lakebase_vector, lakebase_text)
- [ ] All 4 synced tables populated with correct data
- [ ] `work_orders_app` table exists and is writable
- [ ] Parts search returns relevant results for "bearing CNC_Mill" or similar
- [ ] Query latency < 50ms for single-line lookups
