# L400-01 — Deployment & CI/CD

**Customer:** Volta Industrial  
**Prepared for:** Operations & Advanced Engineers  
**Classification:** Level 400 — Operations  
**Scope:** Deployment pipelines, DABs configuration, branch promotion, CI/CD  

---

## 1. Purpose

This document defines how the Volta Industrial platform is deployed, promoted between environments, and maintained through CI/CD. Everything is infrastructure as code — no manual UI configuration in production.

---

## 2. Environment Model

| Environment | Lakebase Branch | App Deployment | Purpose |
|-------------|----------------|----------------|---------|
| **Development** | `dev` | `volta-app-dev` | Active development, testing |
| **Staging** | `staging` | `volta-app-staging` | Pre-production validation |
| **Production** | `main` | `volta-app-prod` | Live plant manager use |

### Promotion Flow

```
dev ──→ staging ──→ main (production)
 │         │          │
 │         │          └── Plant managers use this
 │         └── Integration testing, load testing
 └── Engineers iterate here
```

---

## 3. Databricks Asset Bundles (DABs)

### 3.1 Bundle Structure

```
volta-industrial/
├── databricks.yml                    # Root bundle config
├── environments/
│   ├── development.yml               # Dev overrides
│   ├── staging.yml                   # Staging overrides
│   └── production.yml                # Prod overrides
├── resources/
│   ├── lakebase/
│   │   ├── schemas.yml               # Schema definitions
│   │   ├── syncs.yml                 # Forward sync config
│   │   ├── reverse_syncs.yml         # Reverse sync config
│   │   └── migrations/
│   │       ├── 001_create_schemas.sql
│   │       ├── 002_create_extensions.sql
│   │       ├── 003_app_state_tables.sql
│   │       ├── 004_app_actions_tables.sql
│   │       ├── 005_search_tables.sql
│   │       └── 006_search_indexes.sql
│   ├── ai_gateway/
│   │   ├── endpoints.yml
│   │   ├── budgets.yml
│   │   ├── guardrails.yml
│   │   └── tracing.yml
│   ├── genie/
│   │   ├── domains.yml
│   │   ├── metric_views/
│   │   ├── pages/
│   │   └── agents.yml
│   └── app/
│       ├── app.yml                   # Databricks Apps manifest
│       └── Dockerfile
├── src/
│   ├── backend/                      # Node.js AppKit
│   └── frontend/                     # React
└── tests/
    ├── integration/
    ├── load/
    └── e2e/
```

### 3.2 Root Bundle Configuration

```yaml
# databricks.yml
bundle:
  name: volta-industrial

variables:
  workspace_url:
    description: "Target workspace URL"
  lakebase_instance:
    description: "Lakebase instance identifier"
  ai_gateway_endpoint:
    description: "AI Gateway endpoint URL"
  genie_space_id:
    description: "Genie Agent space ID"
  otel_endpoint:
    description: "OpenTelemetry collector endpoint"
  mlflow_experiment:
    description: "MLFlow experiment path"
    default: "/volta-industrial/agent-traces"

environments:
  development:
    default: true
    variables:
      lakebase_branch: "dev"
    resources:
      app:
        mode: "development"
        
  staging:
    variables:
      lakebase_branch: "staging"
    resources:
      app:
        mode: "staging"
        
  production:
    variables:
      lakebase_branch: "main"
    resources:
      app:
        mode: "production"
```

---

## 4. CI/CD Pipeline

### 4.1 Pipeline Stages

```yaml
# .github/workflows/deploy.yml
name: Volta Industrial Deploy

on:
  push:
    branches: [main, staging, dev]
  pull_request:
    branches: [main, staging]

jobs:
  lint-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: npm ci
      - name: Lint
        run: npm run lint
      - name: Unit tests
        run: npm test
      - name: Type check
        run: npm run typecheck

  validate-bundle:
    runs-on: ubuntu-latest
    needs: lint-and-test
    steps:
      - uses: actions/checkout@v4
      - name: Install Databricks CLI
        run: curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh
      - name: Validate bundle
        run: databricks bundle validate
        env:
          DATABRICKS_HOST: ${{ secrets.DATABRICKS_HOST }}
          DATABRICKS_TOKEN: ${{ secrets.DATABRICKS_TOKEN }}

  deploy-dev:
    if: github.ref == 'refs/heads/dev'
    runs-on: ubuntu-latest
    needs: validate-bundle
    environment: development
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to dev
        run: databricks bundle deploy --target development
        env:
          DATABRICKS_HOST: ${{ secrets.DATABRICKS_HOST }}
          DATABRICKS_TOKEN: ${{ secrets.DATABRICKS_TOKEN }}

  integration-tests:
    if: github.ref == 'refs/heads/staging'
    runs-on: ubuntu-latest
    needs: validate-bundle
    steps:
      - name: Run integration tests
        run: npm run test:integration
      - name: Run load tests
        run: npm run test:load

  deploy-staging:
    if: github.ref == 'refs/heads/staging'
    runs-on: ubuntu-latest
    needs: integration-tests
    environment: staging
    steps:
      - name: Deploy to staging
        run: databricks bundle deploy --target staging

  deploy-production:
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    needs: validate-bundle
    environment: production
    steps:
      - name: Deploy to production
        run: databricks bundle deploy --target production
      - name: Promote Lakebase branch
        run: databricks lakebase branches promote --from staging --to main
      - name: Smoke test
        run: npm run test:smoke
```

### 4.2 Branch Promotion Checklist (Automated)

```yaml
# Automated checks before promotion
promotion_checks:
  dev_to_staging:
    - unit_tests_pass: true
    - lint_clean: true
    - bundle_validates: true
    - lakebase_migrations_apply: true
    - sync_validation: true
    
  staging_to_production:
    - integration_tests_pass: true
    - load_tests_pass: true
    - budget_not_exceeded: true
    - guardrails_tested: true
    - trace_retrieval_works: true
    - hero_question_e2e: true
    - rollback_tested: true
```

---

## 5. Rollback Strategy

### 5.1 App Rollback

```bash
# Immediate rollback to previous app version
databricks apps rollback volta-app-prod --to-version previous

# Rollback to specific version
databricks apps rollback volta-app-prod --to-version v2.3.1
```

### 5.2 Lakebase Rollback

```bash
# Lakebase branches are immutable snapshots
# "Rollback" = point app at previous branch state
# Main branch history is preserved

# If a migration breaks production:
# 1. Point app back to previous known-good state
# 2. Fix migration on dev branch
# 3. Re-promote after fix
```

### 5.3 AI Gateway Rollback

```bash
# Revert gateway config to previous version
databricks bundle deploy --target production --rollback
```

---

## 6. Secrets Management

| Secret | Where Stored | Used By |
|--------|-------------|---------|
| `DATABRICKS_TOKEN` | GitHub Secrets | CI/CD pipeline |
| `LAKEBASE_CONNECTION_STRING` | Databricks Secrets | App runtime |
| `AI_GATEWAY_API_KEY` | Databricks Secrets | App runtime |
| `OTEL_AUTH_TOKEN` | Databricks Secrets | App runtime |
| `MLFLOW_TRACKING_TOKEN` | Databricks Secrets | App runtime |

---

## 7. Execution Checklist

- [ ] Set up GitHub repo with branch protection (main, staging)
- [ ] Configure GitHub Actions workflows
- [ ] Set up Databricks CLI authentication for CI/CD
- [ ] Create DABs bundle structure
- [ ] Configure environment-specific variables
- [ ] Test full deploy pipeline (dev → staging → production)
- [ ] Test rollback procedures
- [ ] Document runbook for on-call engineers

---

*Document Level: L400 — Operations*  
*Audience: DevOps engineers, platform engineers, on-call staff*  
*Next: [L400-02 — Observability](L400-02-observability.md)*
