# L300-04 — AI Agent Application Design

**Customer:** Volta Industrial  
**Prepared for:** Engineers & Implementers  
**Classification:** Level 300 — Detailed Design  
**Scope:** Databricks AppKit agent, tools, memory, decision flow  

---

## 1. Purpose

This document defines the AI Agent application that answers the hero question for plant managers. The agent orchestrates multiple tools — including the Genie Agent — to surface risk, prescribe action, enable approval, and execute decisions.

**Key Principle:** This is a decision engine, not a dashboard. The pattern is Surface → Prescribe → Approve → Act.

---

## 2. Application Architecture

### 2.1 Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| Frontend | React | Plant manager decision UI |
| Backend | Node.js (Databricks AppKit) | Required — no exceptions |
| Agent Framework | AppKit Agent plugin (beta) | Latest Databricks CLI |
| Database | Lakebase | Synced + writable tables |
| LLM Routing | Unity AI Gateway | Budget + guardrails + tracing |
| Observability | OpenTelemetry + MLFlow 3 | Logs, metrics, traces, LLM traces |

### 2.2 Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     REACT FRONTEND                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ Line Risk │  │ Decision │  │  Action  │  │  History │   │
│  │   View   │  │  Panel   │  │ Executor │  │   View   │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
├─────────────────────────────────────────────────────────────┤
│                   NODE.JS BACKEND (AppKit)                    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              AGENT ORCHESTRATOR                       │    │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐  │    │
│  │  │  Genie  │ │  Cost   │ │  Work   │ │  Parts  │  │    │
│  │  │  Tool   │ │  Calc   │ │  Order  │ │ Reorder │  │    │
│  │  │         │ │  Tool   │ │  Tool   │ │  Tool   │  │    │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘  │    │
│  └─────────────────────────────────────────────────────┘    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  Short-term  │  │  Long-term   │  │   Tracing    │      │
│  │   Memory     │  │   Memory     │  │  (MLFlow 3)  │      │
│  │  (Session)   │  │ (AI Search)  │  │              │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
├─────────────────────────────────────────────────────────────┤
│                      LAKEBASE                                │
│  [synced_uc]  [app_state]  [app_actions]  [app_search]      │
├─────────────────────────────────────────────────────────────┤
│                  UNITY AI GATEWAY                             │
│  [Budget: $X/plant/month]  [Guardrails]  [Trace logging]    │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Agent Design

### 3.1 Agent Configuration

```typescript
// agent.config.ts
import { Agent, Tool } from '@databricks/appkit-agent';

export const voltaAgent = new Agent({
  name: 'volta-production-intelligence',
  description: 'Production intelligence assistant for Volta Industrial plant managers',
  
  systemPrompt: `You are a production intelligence assistant for Volta Industrial.
    
    YOUR ROLE:
    Help plant managers make within-shift decisions about production lines.
    You answer the hero question: "Should I pull this line now or run it to shift end?"
    
    YOUR TOOLS:
    - genie: Query production data (OEE, risk scores, machine health, parts)
    - cost_calculator: Compare pull-now vs. run-to-end costs
    - work_order: Issue maintenance work orders
    - parts_reorder: Trigger parts reorders
    - memory_search: Search past decisions and outcomes
    
    YOUR BEHAVIOR:
    1. Always scope to the user's plant
    2. When showing risk, always include the recommendation
    3. When showing costs, show BOTH options with clear comparison
    4. Reference past similar decisions when available
    5. Never execute an action without explicit user approval
    6. Explain your reasoning in business terms, not technical ones
    
    DECISION FRAMEWORK:
    - Risk > 75 + cost-to-run > cost-to-pull → Recommend PULL_NOW
    - Risk 50-75 → Recommend MONITOR_CLOSELY
    - Risk < 50 → Recommend RUN_TO_SHIFT_END
    
    CONSTRAINTS:
    - Never read all data from any table (guardrail enforced)
    - Always filter by plant_id
    - Keep responses concise for floor use
  `,
  
  gateway: {
    endpoint: process.env.AI_GATEWAY_ENDPOINT,
    budget_tag: 'volta-production-intelligence',
  },
  
  tracing: {
    mlflow_experiment: '/volta-industrial/agent-traces',
    otel_enabled: true,
  },
});
```

### 3.2 Tool Definitions

```typescript
// tools/genie-tool.ts
import { Tool } from '@databricks/appkit-agent';

export const genieTool = new Tool({
  name: 'genie',
  description: 'Query Volta production data using natural language. Use for questions about OEE, machine health, risk scores, parts availability, downtime, and shift performance.',
  parameters: {
    question: {
      type: 'string',
      description: 'Natural language question about production data',
      required: true,
    },
  },
  execute: async ({ question }, context) => {
    // Route to Genie Agent via AppKit plugin
    const response = await context.genie.ask({
      spaceId: process.env.GENIE_SPACE_ID,
      question,
      // Automatically scoped to user's plant via context
      filters: { plant_id: context.user.plantId },
    });
    return response;
  },
});

// tools/cost-calculator-tool.ts
export const costCalculatorTool = new Tool({
  name: 'cost_calculator',
  description: 'Calculate and compare the cost of pulling a line now (planned maintenance) versus running it to shift end (risk of unplanned downtime).',
  parameters: {
    line_id: { type: 'string', required: true },
    plant_id: { type: 'string', required: true },
  },
  execute: async ({ line_id, plant_id }, context) => {
    // Read from synced UC tables in Lakebase
    const riskData = await context.db.query(`
      SELECT * FROM synced_uc.line_risk_scores 
      WHERE line_id = $1 AND plant_id = $2
    `, [line_id, plant_id]);
    
    const shiftData = await context.db.query(`
      SELECT * FROM synced_uc.current_shift_context 
      WHERE plant_id = $1
    `, [plant_id]);
    
    const costToPull = riskData.planned_maintenance_cost;
    const costToRun = riskData.max_failure_prob 
      * shiftData.hours_remaining 
      * 22000 
      * 1.3; // expedited freight multiplier
    
    return {
      line_id,
      cost_to_pull: costToPull,
      expected_cost_to_run: Math.round(costToRun),
      recommendation: costToRun > costToPull ? 'PULL_NOW' : 'RUN_TO_SHIFT_END',
      risk_score: riskData.composite_risk_score,
      hours_remaining: shiftData.hours_remaining,
      shift_ends_at: shiftData.shift_end_time,
    };
  },
});

// tools/work-order-tool.ts
export const workOrderTool = new Tool({
  name: 'work_order',
  description: 'Issue a maintenance work order for a machine. Requires explicit user approval before execution.',
  parameters: {
    machine_id: { type: 'string', required: true },
    work_type: { type: 'string', enum: ['PREVENTIVE', 'CORRECTIVE', 'EMERGENCY'], required: true },
    priority: { type: 'string', enum: ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'], required: true },
    description: { type: 'string', required: true },
  },
  requiresApproval: true, // Agent must get user confirmation
  execute: async (params, context) => {
    // Write to writable Postgres table
    const result = await context.db.query(`
      INSERT INTO app_actions.work_orders_issued 
        (decision_id, machine_id, work_type, priority, description, assigned_to, target_completion)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING work_order_id
    `, [context.currentDecisionId, params.machine_id, params.work_type, 
        params.priority, params.description, params.assigned_to, params.target_completion]);
    
    return { work_order_id: result.work_order_id, status: 'ISSUED' };
  },
});

// tools/parts-reorder-tool.ts
export const partsReorderTool = new Tool({
  name: 'parts_reorder',
  description: 'Trigger a parts reorder. Requires explicit user approval before execution.',
  parameters: {
    part_id: { type: 'string', required: true },
    quantity: { type: 'number', required: true },
    urgency: { type: 'string', enum: ['STANDARD', 'EXPEDITED', 'EMERGENCY'], required: true },
  },
  requiresApproval: true,
  execute: async (params, context) => {
    const result = await context.db.query(`
      INSERT INTO app_actions.parts_reorders 
        (decision_id, part_id, quantity, urgency, supplier_id)
      VALUES ($1, $2, $3, $4, $5)
      RETURNING reorder_id
    `, [context.currentDecisionId, params.part_id, params.quantity, 
        params.urgency, params.supplier_id]);
    
    return { reorder_id: result.reorder_id, status: 'PENDING' };
  },
});

// tools/memory-search-tool.ts
export const memorySearchTool = new Tool({
  name: 'memory_search',
  description: 'Search past decisions and their outcomes for similar situations. Use to provide context like "last time Line 4 had this risk level, we pulled and it saved $X".',
  parameters: {
    query: { type: 'string', required: true },
    plant_id: { type: 'string', required: true },
  },
  execute: async ({ query, plant_id }, context) => {
    // Hybrid search using Lakebase AI Search
    const embedding = await context.embed(query);
    const results = await context.db.query(`
      WITH vector_results AS (
        SELECT decision_id, rationale_text, outcome, actual_cost,
               1 - (embedding <=> $1::vector) AS score
        FROM app_search.decision_rationales
        WHERE plant_id = $2
        ORDER BY embedding <=> $1::vector
        LIMIT 5
      )
      SELECT * FROM vector_results WHERE score > 0.7
      ORDER BY score DESC
    `, [embedding, plant_id]);
    
    return results;
  },
});
```

---

## 4. Memory Architecture

### 4.1 Short-Term Memory (Session)

| What | Where | Lifetime | Purpose |
|------|-------|----------|---------|
| Current conversation | `app_state.agent_conversations` | Session duration | Context for multi-turn dialogue |
| Active decision context | In-memory + session table | Until decision made | Track which line/risk is being discussed |
| User's plant context | `app_state.sessions` | Session duration | Scope all queries to correct plant |

### 4.2 Long-Term Memory (Lakebase AI Search)

| What | Where | Lifetime | Purpose |
|------|-------|----------|---------|
| Past decisions + outcomes | `app_search.decision_rationales` | Permanent | "Last time we saw this, we did X and it worked" |
| Maintenance notes | `app_search.maintenance_notes` | Permanent | Historical context about machines |
| Work order resolutions | `app_search.work_order_descriptions` | Permanent | What fixed similar problems before |

### 4.3 Memory Flow

```
User asks about Line 4
       │
       ▼
Agent checks short-term memory (current session context)
       │
       ▼
Agent queries Genie (current risk data)
       │
       ▼
Agent searches long-term memory ("similar past decisions for Line 4")
       │
       ▼
Agent synthesizes: current risk + past outcomes + cost comparison
       │
       ▼
Agent presents recommendation with historical context
       │
       ▼
User approves → Agent executes → Decision stored in long-term memory
```

---

## 5. Decision Flow Implementation

### 5.1 The Hero Question Flow

```typescript
// flows/hero-question.ts
export async function handleHeroQuestion(
  lineId: string, 
  plantId: string, 
  context: AgentContext
): Promise<DecisionRecommendation> {
  
  // 1. SURFACE — Get current risk
  const riskData = await context.tools.genie.execute({
    question: `What is the current risk score and status for line ${lineId}?`
  });
  
  // 2. PRESCRIBE — Calculate costs
  const costComparison = await context.tools.cost_calculator.execute({
    line_id: lineId,
    plant_id: plantId,
  });
  
  // 3. CONTEXT — Search past similar decisions
  const pastDecisions = await context.tools.memory_search.execute({
    query: `Line ${lineId} risk score above ${riskData.risk_score} decision outcome`,
    plant_id: plantId,
  });
  
  // 4. RECOMMEND — Synthesize
  return {
    line_id: lineId,
    risk_score: riskData.risk_score,
    recommendation: costComparison.recommendation,
    cost_to_pull: costComparison.cost_to_pull,
    expected_cost_to_run: costComparison.expected_cost_to_run,
    hours_remaining: costComparison.hours_remaining,
    past_context: pastDecisions,
    // Agent will present this and await approval
    awaiting_approval: true,
  };
}
```

### 5.2 Approval & Execution

```typescript
// flows/execute-decision.ts
export async function executeDecision(
  decision: DecisionRecommendation,
  userChoice: 'PULL_NOW' | 'RUN_TO_SHIFT_END' | 'MONITOR',
  context: AgentContext
): Promise<ExecutionResult> {
  
  // 1. Record the decision
  const decisionRecord = await context.db.query(`
    INSERT INTO app_actions.decisions 
      (plant_id, line_id, decision_type, recommendation, 
       risk_score_at_decision, cost_to_pull, expected_cost_to_run,
       rationale, decided_by, shift_end_time)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
    RETURNING decision_id
  `, [decision.plant_id, decision.line_id, userChoice, 
      decision.recommendation, decision.risk_score,
      decision.cost_to_pull, decision.expected_cost_to_run,
      context.conversationSummary, context.user.id,
      decision.shift_ends_at]);
  
  // 2. Execute actions based on choice
  if (userChoice === 'PULL_NOW') {
    // Issue work order
    await context.tools.work_order.execute({
      machine_id: decision.at_risk_machine_id,
      work_type: 'PREVENTIVE',
      priority: 'HIGH',
      description: `Proactive pull - risk score ${decision.risk_score}`,
    });
    
    // Check parts availability and reorder if needed
    if (decision.parts_at_risk) {
      await context.tools.parts_reorder.execute({
        part_id: decision.critical_part_id,
        quantity: decision.recommended_quantity,
        urgency: 'EXPEDITED',
      });
    }
  }
  
  // 3. Store in long-term memory
  const rationale = await context.summarizeDecision(decision, userChoice);
  await context.db.query(`
    INSERT INTO app_search.decision_rationales 
      (decision_id, rationale_text, context_summary, plant_id, line_id, embedding)
    VALUES ($1, $2, $3, $4, $5, $6)
  `, [decisionRecord.decision_id, rationale, 
      context.conversationSummary, decision.plant_id, 
      decision.line_id, await context.embed(rationale)]);
  
  return { decision_id: decisionRecord.decision_id, status: 'EXECUTED' };
}
```

---

## 6. Frontend Design

### 6.1 Key Views

| View | Purpose | Data Source |
|------|---------|-------------|
| **Plant Overview** | All lines ranked by risk | `synced_uc.line_risk_scores` |
| **Line Detail** | Single line deep-dive with risk factors | Genie query + synced tables |
| **Decision Panel** | Pull-vs-run comparison with recommendation | Cost calculator tool |
| **Action Executor** | Approve and execute work orders / reorders | Agent tools |
| **History** | Past decisions and outcomes | `app_actions.decisions` |
| **Chat** | Natural language interaction with agent | Agent orchestrator |

### 6.2 Real-Time Updates

```typescript
// Frontend subscribes to Lakebase changes for live updates
// When synced_uc tables update, UI refreshes automatically
const subscription = useLakebaseSubscription({
  table: 'synced_uc.line_risk_scores',
  filter: { plant_id: currentPlant },
  onUpdate: (newData) => {
    setLineRisks(newData);
    // Highlight lines that crossed risk thresholds
    highlightChanges(newData);
  },
});
```

---

## 7. Deployment Configuration

### 7.1 App Manifest

```yaml
# app.yml (Databricks Apps)
name: volta-production-intelligence
description: "Live production intelligence for Volta Industrial plant managers"

runtime:
  framework: appkit
  node_version: "20"

environment:
  LAKEBASE_BRANCH: "${var.lakebase_branch}"  # 'main' for prod, 'dev' for development
  AI_GATEWAY_ENDPOINT: "${var.ai_gateway_endpoint}"
  GENIE_SPACE_ID: "${var.genie_space_id}"
  MLFLOW_EXPERIMENT: "/volta-industrial/agent-traces"
  OTEL_EXPORTER_ENDPOINT: "${var.otel_endpoint}"

plugins:
  - lakebase
  - agent  # AppKit Agent beta
  - genie  # Genie integration

resources:
  compute:
    min_instances: 1
    max_instances: 4
    instance_type: "Standard_DS3_v2"
```

### 7.2 Development Workflow

```bash
# Build against dev branch
export LAKEBASE_BRANCH=dev
databricks apps deploy --env development

# Test and validate
databricks apps logs --env development

# Promote to production (main branch)
export LAKEBASE_BRANCH=main
databricks apps deploy --env production
```

---

## 8. Execution Checklist

- [ ] Initialize AppKit project (Node.js + React)
- [ ] Configure Lakebase plugin (connect to dev branch)
- [ ] Implement agent with system prompt
- [ ] Implement Genie tool (connect to Genie space)
- [ ] Implement cost calculator tool
- [ ] Implement work order tool (with approval gate)
- [ ] Implement parts reorder tool (with approval gate)
- [ ] Implement memory search tool (Lakebase AI Search)
- [ ] Build React frontend — Plant Overview view
- [ ] Build React frontend — Decision Panel
- [ ] Build React frontend — Chat interface
- [ ] Configure AI Gateway routing
- [ ] Configure MLFlow 3 tracing
- [ ] Configure OpenTelemetry
- [ ] Test hero question flow end-to-end on dev
- [ ] Deploy to production (main branch)
- [ ] Validate with plant manager persona walkthrough

---

*Document Level: L300 — Detailed Design*  
*Audience: Full-stack engineers, agent developers*  
*Prerequisite: Lakebase provisioned (L300-03)*  
*Next: [L300-05 — AI Gateway Configuration](L300-05-ai-gateway.md)*
