# L300-03 — Lakebase Design

**Customer:** Volta Industrial  
**Prepared for:** Engineers & Implementers  
**Classification:** Level 300 — Detailed Design  
**Scope:** Lakebase schema, sync configuration, branching, and search  

---

## 1. Purpose

Lakebase bridges the gap between Volta's batch lakehouse and the low-latency needs of the floor application. This document defines the operational schema, sync strategy, branching model, and search configuration.

**Key Principle:** Synced UC tables are read-only in Postgres. All app state and actions live in separate writable Postgres tables. Never write to synced tables.

---

## 2. Schema Architecture

### 2.1 Schema Separation

```
Lakebase Instance
├── synced_uc (read-only)          ← Unity Catalog tables synced in
│   ├── machine_health_current
│   ├── line_risk_scores
│   ├── parts_availability
│   └── current_shift_context
│
├── app_state (read-write)         ← Application operational state
│   ├── sessions
│   ├── user_preferences
│   └── agent_conversations
│
├── app_actions (read-write)       ← Decisions and actions taken
│   ├── decisions
│   ├── work_orders_issued
│   └── parts_reorders
│
└── app_search (read + vector)     ← Searchable text for AI retrieval
    ├── maintenance_notes
    ├── work_order_descriptions
    └── decision_rationales
```

### 2.2 Access Rules

| Schema | Read | Write | Sync Direction |
|--------|------|-------|----------------|
| `synced_uc` | ✅ App reads | ❌ Never write | UC → Lakebase (forward sync) |
| `app_state` | ✅ App reads | ✅ App writes | Lakebase → UC (reverse sync) |
| `app_actions` | ✅ App reads | ✅ App writes | Lakebase → UC (reverse sync, SCD2) |
| `app_search` | ✅ Vector + FTS | ✅ App writes | Lakebase → UC (reverse sync) |

---

## 3. Synced UC Tables (Read-Only)

### 3.1 Tables to Sync

| UC Source Table | Lakebase Table | Sync Frequency | Purpose |
|----------------|---------------|----------------|---------|
| `volta_industrial.gold.machine_health_current` | `synced_uc.machine_health_current` | Near real-time (streaming) | Current machine health for floor view |
| `volta_industrial.gold.line_risk_scores` | `synced_uc.line_risk_scores` | Near real-time (streaming) | Line-level risk for hero question |
| `volta_industrial.gold.parts_availability` | `synced_uc.parts_availability` | Every 15 min | Parts status for decision context |
| `volta_industrial.gold.current_shift_context` | `synced_uc.current_shift_context` | Every 5 min | Shift timing for cost calculations |

### 3.2 Sync Configuration (DABs)

```yaml
# databricks.yml - Lakebase sync configuration
resources:
  lakebase_syncs:
    machine_health_sync:
      source_table: "volta_industrial.gold.machine_health_current"
      target_schema: "synced_uc"
      target_table: "machine_health_current"
      sync_mode: "streaming"
      
    line_risk_sync:
      source_table: "volta_industrial.gold.line_risk_scores"
      target_schema: "synced_uc"
      target_table: "line_risk_scores"
      sync_mode: "streaming"
      
    parts_availability_sync:
      source_table: "volta_industrial.gold.parts_availability"
      target_schema: "synced_uc"
      target_table: "parts_availability"
      sync_mode: "incremental"
      schedule: "*/15 * * * *"
      
    shift_context_sync:
      source_table: "volta_industrial.gold.current_shift_context"
      target_schema: "synced_uc"
      target_table: "current_shift_context"
      sync_mode: "incremental"
      schedule: "*/5 * * * *"
```

---

## 4. Writable Postgres Tables (App State & Actions)

### 4.1 App State Schema

```sql
-- Sessions table
CREATE TABLE app_state.sessions (
  session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id VARCHAR(255) NOT NULL,
  plant_id VARCHAR(50) NOT NULL,
  started_at TIMESTAMPTZ DEFAULT NOW(),
  last_active_at TIMESTAMPTZ DEFAULT NOW(),
  context JSONB DEFAULT '{}',
  is_active BOOLEAN DEFAULT TRUE
);

-- User preferences
CREATE TABLE app_state.user_preferences (
  user_id VARCHAR(255) PRIMARY KEY,
  default_plant_id VARCHAR(50),
  notification_settings JSONB DEFAULT '{}',
  display_preferences JSONB DEFAULT '{}',
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Agent conversations (short-term memory)
CREATE TABLE app_state.agent_conversations (
  conversation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID REFERENCES app_state.sessions(session_id),
  messages JSONB[] DEFAULT '{}',
  tool_calls JSONB[] DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### 4.2 App Actions Schema

```sql
-- Decisions made by plant managers
CREATE TABLE app_actions.decisions (
  decision_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID REFERENCES app_state.sessions(session_id),
  plant_id VARCHAR(50) NOT NULL,
  line_id VARCHAR(50) NOT NULL,
  decision_type VARCHAR(50) NOT NULL,  -- 'PULL_NOW', 'RUN_TO_SHIFT_END', 'MONITOR'
  recommendation VARCHAR(50) NOT NULL,  -- What the AI recommended
  risk_score_at_decision DECIMAL(5,2),
  cost_to_pull DECIMAL(12,2),
  expected_cost_to_run DECIMAL(12,2),
  rationale TEXT,
  decided_by VARCHAR(255) NOT NULL,
  decided_at TIMESTAMPTZ DEFAULT NOW(),
  shift_end_time TIMESTAMPTZ,
  outcome VARCHAR(50),  -- Filled later: 'CORRECT', 'INCORRECT', 'PENDING'
  outcome_recorded_at TIMESTAMPTZ,
  actual_downtime_hours DECIMAL(6,2),
  actual_cost DECIMAL(12,2)
);

-- Work orders issued through the app
CREATE TABLE app_actions.work_orders_issued (
  work_order_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  decision_id UUID REFERENCES app_actions.decisions(decision_id),
  machine_id VARCHAR(50) NOT NULL,
  work_type VARCHAR(50) NOT NULL,  -- 'PREVENTIVE', 'CORRECTIVE', 'EMERGENCY'
  priority VARCHAR(20) NOT NULL,
  description TEXT,
  assigned_to VARCHAR(255),
  issued_at TIMESTAMPTZ DEFAULT NOW(),
  target_completion TIMESTAMPTZ,
  status VARCHAR(50) DEFAULT 'OPEN',
  completed_at TIMESTAMPTZ
);

-- Parts reorders triggered through the app
CREATE TABLE app_actions.parts_reorders (
  reorder_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  decision_id UUID REFERENCES app_actions.decisions(decision_id),
  part_id VARCHAR(50) NOT NULL,
  quantity INTEGER NOT NULL,
  urgency VARCHAR(20) NOT NULL,  -- 'STANDARD', 'EXPEDITED', 'EMERGENCY'
  supplier_id VARCHAR(50),
  estimated_arrival TIMESTAMPTZ,
  ordered_at TIMESTAMPTZ DEFAULT NOW(),
  status VARCHAR(50) DEFAULT 'PENDING'
);
```

### 4.3 Search Schema

```sql
-- Maintenance notes (searchable by AI)
CREATE TABLE app_search.maintenance_notes (
  note_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  machine_id VARCHAR(50) NOT NULL,
  plant_id VARCHAR(50) NOT NULL,
  note_text TEXT NOT NULL,  -- Searchable field
  note_type VARCHAR(50),
  created_by VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  embedding vector(1536)  -- For semantic search
);

-- Work order descriptions (searchable)
CREATE TABLE app_search.work_order_descriptions (
  work_order_id VARCHAR(50) PRIMARY KEY,
  description TEXT NOT NULL,  -- Searchable field
  resolution_notes TEXT,
  machine_id VARCHAR(50),
  plant_id VARCHAR(50),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  embedding vector(1536)
);

-- Decision rationales (long-term memory for the agent)
CREATE TABLE app_search.decision_rationales (
  decision_id UUID PRIMARY KEY,
  rationale_text TEXT NOT NULL,  -- Searchable field
  context_summary TEXT,
  plant_id VARCHAR(50),
  line_id VARCHAR(50),
  outcome VARCHAR(50),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  embedding vector(1536)
);
```

---

## 5. Extensions & Search Configuration

### 5.1 Extension Installation Order

```sql
-- IMPORTANT: pgvector must be created FIRST
-- It is NOT created automatically
CREATE EXTENSION IF NOT EXISTS vector;

-- Then Lakebase extensions
CREATE EXTENSION IF NOT EXISTS lakebase_vector;
CREATE EXTENSION IF NOT EXISTS lakebase_text;
```

### 5.2 Lakebase Search Configuration

```sql
-- Create hybrid search index on maintenance notes
-- Combines vector similarity with full-text keyword matching
CREATE INDEX idx_maintenance_notes_embedding 
  ON app_search.maintenance_notes 
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);

CREATE INDEX idx_maintenance_notes_fts 
  ON app_search.maintenance_notes 
  USING GIN (to_tsvector('english', note_text));

-- Similar for work order descriptions
CREATE INDEX idx_work_orders_embedding 
  ON app_search.work_order_descriptions 
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);

CREATE INDEX idx_work_orders_fts 
  ON app_search.work_order_descriptions 
  USING GIN (to_tsvector('english', description || ' ' || COALESCE(resolution_notes, '')));

-- Decision rationales (long-term agent memory)
CREATE INDEX idx_decisions_embedding 
  ON app_search.decision_rationales 
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);

CREATE INDEX idx_decisions_fts 
  ON app_search.decision_rationales 
  USING GIN (to_tsvector('english', rationale_text || ' ' || COALESCE(context_summary, '')));
```

### 5.3 Hybrid Search Query Pattern

```sql
-- Hybrid search: combine vector similarity with keyword relevance
-- Used by the agent for long-term memory retrieval
WITH vector_results AS (
  SELECT 
    decision_id,
    rationale_text,
    1 - (embedding <=> $1::vector) AS vector_score
  FROM app_search.decision_rationales
  WHERE plant_id = $2
  ORDER BY embedding <=> $1::vector
  LIMIT 20
),
text_results AS (
  SELECT 
    decision_id,
    rationale_text,
    ts_rank(to_tsvector('english', rationale_text), plainto_tsquery('english', $3)) AS text_score
  FROM app_search.decision_rationales
  WHERE plant_id = $2
    AND to_tsvector('english', rationale_text) @@ plainto_tsquery('english', $3)
  LIMIT 20
)
SELECT 
  COALESCE(v.decision_id, t.decision_id) AS decision_id,
  COALESCE(v.rationale_text, t.rationale_text) AS rationale_text,
  (COALESCE(v.vector_score, 0) * 0.7 + COALESCE(t.text_score, 0) * 0.3) AS hybrid_score
FROM vector_results v
FULL OUTER JOIN text_results t ON v.decision_id = t.decision_id
ORDER BY hybrid_score DESC
LIMIT 10;
```

---

## 6. Reverse Lakehouse Sync (SCD Type 2)

### 6.1 Sync Configuration

Writable Postgres tables sync back to Unity Catalog as Delta tables with SCD Type 2 history.

```yaml
# databricks.yml - Reverse sync configuration
resources:
  lakebase_reverse_syncs:
    decisions_reverse_sync:
      source_schema: "app_actions"
      source_table: "decisions"
      target_catalog: "volta_industrial"
      target_schema: "app_actions_history"
      target_table: "decisions_scd2"
      sync_mode: "scd_type_2"
      effective_date_column: "decided_at"
      business_key: "decision_id"
      
    work_orders_reverse_sync:
      source_schema: "app_actions"
      source_table: "work_orders_issued"
      target_catalog: "volta_industrial"
      target_schema: "app_actions_history"
      target_table: "work_orders_scd2"
      sync_mode: "scd_type_2"
      effective_date_column: "issued_at"
      business_key: "work_order_id"
```

### 6.2 SCD Type 2 Target Schema

```sql
-- UC Delta table for decision history (reverse-synced)
-- This enables Annika's question: "Did a plant manager make a different call?"
CREATE TABLE volta_industrial.app_actions_history.decisions_scd2 (
  -- Business key
  decision_id STRING,
  
  -- All decision fields
  session_id STRING,
  plant_id STRING,
  line_id STRING,
  decision_type STRING,
  recommendation STRING,
  risk_score_at_decision DECIMAL(5,2),
  cost_to_pull DECIMAL(12,2),
  expected_cost_to_run DECIMAL(12,2),
  rationale STRING,
  decided_by STRING,
  decided_at TIMESTAMP,
  outcome STRING,
  actual_downtime_hours DECIMAL(6,2),
  actual_cost DECIMAL(12,2),
  
  -- SCD Type 2 metadata
  _effective_from TIMESTAMP,
  _effective_to TIMESTAMP,
  _is_current BOOLEAN,
  _sync_timestamp TIMESTAMP
)
USING DELTA
PARTITIONED BY (plant_id)
TBLPROPERTIES ('delta.enableChangeDataFeed' = 'true');
```

---

## 7. Branching Strategy

### 7.1 Branch Model

```
main (production)
  │
  └── dev (development)
        │
        ├── feature/new-metric-view
        ├── feature/search-tuning
        └── fix/sync-latency
```

### 7.2 Branch Rules

| Branch | Purpose | Who Uses | Promotion Path |
|--------|---------|----------|----------------|
| `main` | Production / demo environment | Plant managers, demos | ← promoted from `dev` |
| `dev` | Active development and testing | Engineers | ← feature branches merged in |
| `feature/*` | Individual features | Individual engineer | → merged to `dev` |

### 7.3 Promotion Criteria (dev → main)

1. ✅ All schema migrations apply cleanly
2. ✅ Forward sync (UC → Lakebase) validates
3. ✅ Reverse sync (Lakebase → UC Delta) validates
4. ✅ Search indexes build successfully
5. ✅ App connects and reads/writes correctly
6. ✅ Agent traces show expected behavior
7. ✅ No AI Gateway budget violations in test

### 7.4 Branch Operations

```bash
# Create dev branch from main
databricks lakebase branches create --name dev --from main

# Switch app to dev branch for development
export LAKEBASE_BRANCH=dev

# Promote dev to main (after validation)
databricks lakebase branches promote --from dev --to main
```

---

## 8. Infrastructure as Code

### 8.1 DABs Configuration

```yaml
# databricks.yml
bundle:
  name: volta-lakebase

workspace:
  host: ${var.workspace_url}

variables:
  workspace_url:
    description: "Databricks workspace URL"
  lakebase_instance:
    description: "Lakebase instance name"

resources:
  # Schema definitions
  lakebase_schemas:
    - name: synced_uc
      description: "Read-only synced UC tables"
    - name: app_state
      description: "Writable application state"
    - name: app_actions
      description: "Writable decisions and actions"
    - name: app_search
      description: "Searchable text with vector embeddings"
  
  # Forward syncs (UC → Lakebase)
  lakebase_syncs:
    # ... (defined in section 3.2)
  
  # Reverse syncs (Lakebase → UC)
  lakebase_reverse_syncs:
    # ... (defined in section 6.1)

# Migrations applied in order
migrations:
  - path: migrations/001_create_schemas.sql
  - path: migrations/002_create_extensions.sql
  - path: migrations/003_create_app_state_tables.sql
  - path: migrations/004_create_app_actions_tables.sql
  - path: migrations/005_create_search_tables.sql
  - path: migrations/006_create_search_indexes.sql
```

---

## 9. Execution Checklist

- [ ] Provision Lakebase instance
- [ ] Create `dev` branch from `main`
- [ ] Run migrations on `dev` branch
- [ ] Install extensions (vector → lakebase_vector → lakebase_text)
- [ ] Create synced_uc schema + configure forward syncs
- [ ] Create app_state schema + tables
- [ ] Create app_actions schema + tables
- [ ] Create app_search schema + tables + indexes
- [ ] Configure reverse Lakehouse Sync (SCD Type 2)
- [ ] Validate forward sync (data flowing from UC)
- [ ] Validate reverse sync (decisions flowing back to UC)
- [ ] Test hybrid search (vector + full-text)
- [ ] Validate from app (read synced, write actions, search)
- [ ] Promote `dev` → `main` after validation
- [ ] Document all as DABs configuration

---

*Document Level: L300 — Detailed Design*  
*Audience: Platform engineers, backend developers*  
*Prerequisite: UC Semantics defined (L300-02)*  
*Next: [L300-04 — AI Agent Application](L300-04-ai-agent-app.md)*
