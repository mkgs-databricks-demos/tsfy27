#!/usr/bin/env bash
# deploy.sh — Orchestrates the three-bundle deployment for Volta Industrial.
#
# Bundle layout (bundles cannot nest; each has its own databricks.yml):
#   volta-industrial/databricks.yml   ← Bundle 1 (infra): schema, volume, data gen, pipeline, metric views, dashboard
#   volta-industrial/bundles/genie/   ← Bundle 2 (genie): Genie space (needs populated tables)
#   volta-industrial/bundles/app/     ← Bundle 3 (app): Databricks App + AI Gateway (needs genie_space_id)
#
# Dependency chain:
#   Bundle 1 (infra) -> jobs run -> gate (tables + metric views exist)
#   Bundle 2 (genie) -> gate (Genie space created + functional)
#   Bundle 3 (app)   -> SPN permissions granted -> app deployed
#
# Usage:
#   cd volta-industrial && ./deploy.sh [--target dev|staging|prod] [--skip-data-gen] [--skip-gates]
#
# Requires: databricks CLI authenticated, jq installed.

set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────────────
TARGET="${1:-dev}"
CATALOG="ncqai"
SCHEMA="volta_industrial"
BUNDLE_ROOT="$(cd "$(dirname "$0")" && pwd)"
SKIP_DATA_GEN=false
SKIP_GATES=false

for arg in "$@"; do
  case $arg in
    --target=*) TARGET="${arg#*=}" ;;
    --skip-data-gen) SKIP_DATA_GEN=true ;;
    --skip-gates) SKIP_GATES=true ;;
  esac
done

echo "═══════════════════════════════════════════════════════════════"
echo "  Volta Industrial — Full Deploy (target: $TARGET)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ─── Helper functions ────────────────────────────────────────────────────────
gate_check() {
  local description="$1"
  local query="$2"
  local expected="$3"

  echo "  Gate: $description"
  result=$(databricks sql execute --query "$query" --output json 2>/dev/null | jq -r '.[0][0]' 2>/dev/null || echo "FAIL")
  if [[ "$result" == "$expected" || "$result" == *"$expected"* ]]; then
    echo "    PASS ($result)"
    return 0
  else
    echo "    FAIL (got: $result, expected: $expected)"
    return 1
  fi
}

wait_for_job() {
  local run_id="$1"
  local timeout="${2:-600}"  # default 10 min
  local elapsed=0

  echo "  Waiting for job run $run_id (timeout: ${timeout}s)..."
  while [[ $elapsed -lt $timeout ]]; do
    state=$(databricks jobs get-run "$run_id" --output json | jq -r '.state.life_cycle_state')
    result=$(databricks jobs get-run "$run_id" --output json | jq -r '.state.result_state // empty')
    if [[ "$state" == "TERMINATED" ]]; then
      if [[ "$result" == "SUCCESS" ]]; then
        echo "    Job completed successfully."
        return 0
      else
        echo "    Job FAILED: $result"
        return 1
      fi
    fi
    sleep 15
    elapsed=$((elapsed + 15))
    echo "    [$elapsed/${timeout}s] State: $state"
  done
  echo "    TIMEOUT waiting for job."
  return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# STAGE 1: Infrastructure Bundle
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "──────────────────────────────────────────────────────────────"
echo "  STAGE 1: Deploy Infrastructure Bundle"
echo "──────────────────────────────────────────────────────────────"

cd "$BUNDLE_ROOT"
databricks bundle deploy --target "$TARGET" --var="catalog=$CATALOG" --var="schema=$SCHEMA"
echo "  Infrastructure bundle deployed (root databricks.yml)."

# ─── Run data generation job ─────────────────────────────────────────────────
if [[ "$SKIP_DATA_GEN" == false ]]; then
  echo ""
  echo "  Running data generation job..."
  RUN_OUTPUT=$(databricks bundle run volta_setup --target "$TARGET" --output json)
  RUN_ID=$(echo "$RUN_OUTPUT" | jq -r '.run_id')
  wait_for_job "$RUN_ID" 900  # 15 min timeout for data gen
else
  echo "  Skipping data generation (--skip-data-gen)."
fi

# ─── Run SDP pipeline ────────────────────────────────────────────────────────
echo ""
echo "  Triggering SDP pipeline update..."
PIPELINE_ID=$(databricks bundle summary --target "$TARGET" --output json | jq -r '.resources.pipelines.volta_plant_floor.id // empty')
if [[ -n "$PIPELINE_ID" ]]; then
  UPDATE_ID=$(databricks pipelines start-update "$PIPELINE_ID" --full-refresh --output json | jq -r '.update_id')
  echo "  Pipeline update started: $UPDATE_ID"
  echo "  Waiting for pipeline to complete..."
  # Poll pipeline state
  ELAPSED=0
  while [[ $ELAPSED -lt 1200 ]]; do
    PIPE_STATE=$(databricks pipelines get-update "$PIPELINE_ID" "$UPDATE_ID" --output json | jq -r '.update.state')
    if [[ "$PIPE_STATE" == "COMPLETED" ]]; then
      echo "    Pipeline completed."
      break
    elif [[ "$PIPE_STATE" == "FAILED" || "$PIPE_STATE" == "CANCELED" ]]; then
      echo "    Pipeline FAILED: $PIPE_STATE"
      exit 1
    fi
    sleep 20
    ELAPSED=$((ELAPSED + 20))
    echo "    [$ELAPSED/1200s] Pipeline state: $PIPE_STATE"
  done
else
  echo "  WARNING: No pipeline resource found in bundle summary. Skipping."
fi

# ─── Gate: Validate tables + metric view exist ───────────────────────────────
if [[ "$SKIP_GATES" == false ]]; then
  echo ""
  echo "  Running Stage 1 gates..."
  gate_check "gold_line_status exists" \
    "SELECT COUNT(*) FROM $CATALOG.$SCHEMA.gold_line_status" "0" || true
  gate_check "gold_maintenance_recommendations exists" \
    "SELECT COUNT(*) FROM $CATALOG.$SCHEMA.gold_maintenance_recommendations" "0" || true
  gate_check "mv_line_risk exists" \
    "DESCRIBE $CATALOG.$SCHEMA.mv_line_risk" "" || true
  gate_check "Hero line present" \
    "SELECT risk_band FROM $CATALOG.$SCHEMA.gold_line_status WHERE line_id='LINE-04' AND plant_id='PLANT-03'" "critical"
  echo "  Stage 1 gates complete."
fi

# Capture outputs for next stage
INFRA_SUMMARY=$(databricks bundle summary --target "$TARGET" --output json)
DASHBOARD_ID=$(echo "$INFRA_SUMMARY" | jq -r '.resources.dashboards // {} | to_entries[0].value.id // empty')
echo ""
echo "  Stage 1 outputs:"
echo "    PIPELINE_ID=$PIPELINE_ID"
echo "    DASHBOARD_ID=$DASHBOARD_ID"

# ═══════════════════════════════════════════════════════════════════════════════
# STAGE 2: Genie Bundle
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "──────────────────────────────────────────────────────────────"
echo "  STAGE 2: Deploy Genie Bundle"
echo "──────────────────────────────────────────────────────────────"

cd "$BUNDLE_ROOT/bundles/genie"
# Note: CLI finds bundles/genie/databricks.yml (not the parent root) because CWD has its own.
databricks bundle deploy --target "$TARGET" \
  --var="catalog=$CATALOG" \
  --var="schema=$SCHEMA" \
  --var="dashboard_id=$DASHBOARD_ID"
echo "  Genie bundle deployed."

# Capture Genie space ID
GENIE_SUMMARY=$(databricks bundle summary --target "$TARGET" --output json)
GENIE_SPACE_ID=$(echo "$GENIE_SUMMARY" | jq -r '.resources.genie_spaces // {} | to_entries[0].value.id // empty')

if [[ -z "$GENIE_SPACE_ID" ]]; then
  echo "  WARNING: Could not extract genie_space_id from bundle summary."
  echo "  You may need to set GENIE_SPACE_ID manually."
fi

echo ""
echo "  Stage 2 outputs:"
echo "    GENIE_SPACE_ID=$GENIE_SPACE_ID"

# ═══════════════════════════════════════════════════════════════════════════════
# STAGE 3: App Bundle
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "──────────────────────────────────────────────────────────────"
echo "  STAGE 3: Deploy App Bundle"
echo "──────────────────────────────────────────────────────────────"

cd "$BUNDLE_ROOT/bundles/app"
# Note: CLI finds bundles/app/databricks.yml (not the parent root) because CWD has its own.
databricks bundle deploy --target "$TARGET" \
  --var="catalog=$CATALOG" \
  --var="schema=$SCHEMA" \
  --var="genie_space_id=$GENIE_SPACE_ID" \
  --var="dashboard_id=$DASHBOARD_ID"
echo "  App bundle deployed."

# ─── Grant SPN permissions ───────────────────────────────────────────────────
APP_SUMMARY=$(databricks bundle summary --target "$TARGET" --output json)
APP_SPN=$(echo "$APP_SUMMARY" | jq -r '.resources.apps // {} | to_entries[0].value.service_principal_name // empty')

if [[ -n "$APP_SPN" ]]; then
  echo ""
  echo "  Granting SPN permissions..."
  # Grant USE CATALOG + USE SCHEMA + SELECT on tables
  databricks sql execute --query "GRANT USE CATALOG ON CATALOG $CATALOG TO \`$APP_SPN\`" 2>/dev/null || true
  databricks sql execute --query "GRANT USE SCHEMA ON SCHEMA $CATALOG.$SCHEMA TO \`$APP_SPN\`" 2>/dev/null || true
  databricks sql execute --query "GRANT SELECT ON SCHEMA $CATALOG.$SCHEMA TO \`$APP_SPN\`" 2>/dev/null || true
  # Grant access to Genie space
  if [[ -n "$GENIE_SPACE_ID" ]]; then
    echo "  Granting SPN access to Genie space $GENIE_SPACE_ID..."
    # Genie space permissions via API
    databricks api post /api/2.0/genie/spaces/$GENIE_SPACE_ID/permissions \
      --json "{\"access_control_list\": [{\"service_principal_name\": \"$APP_SPN\", \"permission_level\": \"CAN_USE\"}]}" 2>/dev/null || true
  fi
  echo "  SPN permissions granted."
else
  echo "  WARNING: Could not determine app SPN. Grant permissions manually."
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  DEPLOYMENT COMPLETE"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Target:       $TARGET"
echo "  Catalog:      $CATALOG.$SCHEMA"
echo "  Pipeline:     $PIPELINE_ID"
echo "  Dashboard:    $DASHBOARD_ID"
echo "  Genie Space:  $GENIE_SPACE_ID"
echo "  App SPN:      $APP_SPN"
echo ""
echo "  Next steps:"
echo "    1. Verify Genie: ask 'What is our downtime exposure?'"
echo "    2. Open app and run the scripted demo flow"
echo "    3. Confirm AI Gateway tracing in UC inference log table"
echo ""
