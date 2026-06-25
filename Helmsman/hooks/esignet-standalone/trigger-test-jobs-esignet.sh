#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Trigger Testrig CronJobs
# =============================================================================
# Immediately triggers testrig CronJobs after deployment:
#   apitestrig  → esignet ns   (cronjob-apitestrig-esignet)
#   signup-apitestrig → signup ns  (if deployed)
#   signup-uitestrig  → signup-uitestrig ns (if deployed)
# =============================================================================
set -euo pipefail

CONTINUE_ON_FAILURE="${CONTINUE_ON_FAILURE:-true}"
JOB_TIMEOUT="${JOB_TIMEOUT:-5400}"
OVERALL_SUCCESS=true

trigger_and_wait() {
  local ns=$1 cronjob=$2

  if ! kubectl get cronjob -n "$ns" "$cronjob" &>/dev/null; then
    echo "⏭  CronJob $cronjob not found in $ns — skipping"
    return 0
  fi

  local job_name="${cronjob}-manual-$(date +%s)"
  echo "▶ Creating $job_name from $cronjob in $ns"
  kubectl create job -n "$ns" "$job_name" --from="cronjob/$cronjob"

  local elapsed=0
  while [[ $elapsed -lt $JOB_TIMEOUT ]]; do
    local complete=$(kubectl get job -n "$ns" "$job_name" \
      -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
    local failed=$(kubectl get job -n "$ns" "$job_name" \
      -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
    [[ "$complete" == "True" ]] && { echo "✓ $job_name completed successfully"; return 0; }
    [[ "$failed"   == "True" ]] && {
      echo "✗ $job_name failed" >&2
      kubectl logs -n "$ns" -l "job-name=$job_name" --tail=50 2>/dev/null || true
      return 1
    }
    echo "  ⏳ $job_name running (${elapsed}s elapsed)..."
    sleep 10
    elapsed=$((elapsed + 10))
  done

  echo "✗ $job_name timed out after ${JOB_TIMEOUT}s" >&2
  return 1
}

trigger_all_in_ns() {
  local ns=$1
  local cronjobs
  cronjobs=$(kubectl get cronjobs -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
  if [[ -z "$cronjobs" ]]; then
    echo "⏭  No CronJobs found in $ns — skipping"
    return 0
  fi
  for cj in $cronjobs; do
    trigger_and_wait "$ns" "$cj" || return 1
  done
}

echo "================================================"
echo "eSignet 1.7.1 - Trigger Testrig CronJobs"
echo "================================================"

echo "=== eSignet API Testrig (esignet ns) ==="
trigger_all_in_ns esignet || OVERALL_SUCCESS=false

echo "=== eSignet-MOSIPID1 API Testrig (esignet-mosipid1 ns) ==="
trigger_all_in_ns esignet-mosipid1 || OVERALL_SUCCESS=false

echo "=== eSignet-MOSIPID2 API Testrig (esignet-mosipid2 ns) ==="
trigger_all_in_ns esignet-mosipid2 || OVERALL_SUCCESS=false

echo "=== eSignet-Sunbird API Testrig (esignet-sunbird ns) ==="
trigger_all_in_ns esignet-sunbird || OVERALL_SUCCESS=false

echo "=== Signup API Testrig (signup ns, if deployed) ==="
trigger_all_in_ns signup || true

echo "=== Signup UI Testrig (signup-uitestrig ns, if deployed) ==="
trigger_all_in_ns signup-uitestrig || true

echo ""
echo "=== Testrig Execution Summary ==="
if [[ "$OVERALL_SUCCESS" == "true" ]]; then
  echo "✓ All testrig jobs completed successfully"
  exit 0
else
  echo "✗ One or more testrig jobs failed"
  exit 1
fi
