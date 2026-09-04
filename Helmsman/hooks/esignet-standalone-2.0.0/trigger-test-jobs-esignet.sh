#!/bin/bash
# =============================================================================
# eSignet Standalone 2.0.0 - Trigger Testrig CronJobs
# =============================================================================
# Immediately triggers testrig CronJobs after deployment:
#   apitestrig  → esignet-mock ns
#   signup-apitestrig → signup ns  (if deployed)
#   signup-uitestrig  → signup-uitestrig ns (if deployed)
# =============================================================================
set -euo pipefail

CONTINUE_ON_FAILURE="${CONTINUE_ON_FAILURE:-true}"
JOB_TIMEOUT="${JOB_TIMEOUT:-5400}"
OVERALL_SUCCESS=true

# Runs `kubectl "$@"`, printing stdout on success.
# Returns 0 on success, 2 for a genuine NotFound (caller should treat the
# resource as absent), or 1 with the error printed to stderr for any other
# kubectl failure (RBAC, credentials, API errors) so real problems aren't
# silently swallowed alongside the expected "doesn't exist" case.
kubectl_get() {
  local output rc=0
  output=$(kubectl "$@" 2>&1) || rc=$?
  if [[ $rc -eq 0 ]]; then
    printf '%s' "$output"
    return 0
  fi
  if echo "$output" | grep -q '(NotFound)'; then
    return 2
  fi
  echo "✗ kubectl $* failed: $output" >&2
  return 1
}

trigger_and_wait() {
  local ns=$1 cronjob=$2

  local rc=0
  kubectl_get get cronjob -n "$ns" "$cronjob" -o name >/dev/null || rc=$?
  if [[ $rc -eq 2 ]]; then
    echo "⏭  CronJob $cronjob not found in $ns — skipping"
    return 0
  elif [[ $rc -ne 0 ]]; then
    return 1
  fi

  local job_name="${cronjob}-manual-$(date +%s)"
  echo "▶ Creating $job_name from $cronjob in $ns"
  kubectl create job -n "$ns" "$job_name" --from="cronjob/$cronjob"

  local elapsed=0
  while [[ $elapsed -lt $JOB_TIMEOUT ]]; do
    local complete failed
    rc=0
    complete=$(kubectl_get get job -n "$ns" "$job_name" \
      -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}') || rc=$?
    if [[ $rc -eq 2 ]]; then
      echo "  ⏳ $job_name not yet visible in $ns (${elapsed}s elapsed)..."
      sleep 10
      elapsed=$((elapsed + 10))
      continue
    elif [[ $rc -ne 0 ]]; then
      return 1
    fi
    rc=0
    failed=$(kubectl_get get job -n "$ns" "$job_name" \
      -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}') || rc=$?
    if [[ $rc -eq 2 ]]; then
      echo "  ⏳ $job_name not yet visible in $ns (${elapsed}s elapsed)..."
      sleep 10
      elapsed=$((elapsed + 10))
      continue
    elif [[ $rc -ne 0 ]]; then
      return 1
    fi
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
  local cronjobs rc=0
  cronjobs=$(kubectl_get get cronjobs -n "$ns" -o jsonpath='{.items[*].metadata.name}') || rc=$?
  if [[ $rc -eq 2 ]]; then
    echo "⏭  No CronJobs found in $ns — skipping"
    return 0
  elif [[ $rc -ne 0 ]]; then
    return 1
  fi
  if [[ -z "$cronjobs" ]]; then
    echo "⏭  No CronJobs found in $ns — skipping"
    return 0
  fi
  for cj in $cronjobs; do
    trigger_and_wait "$ns" "$cj" || return 1
  done
}

echo "================================================"
echo "eSignet Standalone 2.0.0 - Trigger Testrig CronJobs"
echo "================================================"

echo "=== eSignet API Testrig (esignet-mock ns) ==="
trigger_all_in_ns esignet-mock || OVERALL_SUCCESS=false

echo "=== eSignet-MOSIPID API Testrig (esignet-mosipid ns) ==="
trigger_all_in_ns esignet-mosipid || OVERALL_SUCCESS=false

echo "=== eSignet-Sunbird API Testrig (esignet-sunbird ns) ==="
trigger_all_in_ns esignet-sunbird || OVERALL_SUCCESS=false

echo "=== Signup API Testrig (signup ns, if deployed) ==="
trigger_all_in_ns signup || OVERALL_SUCCESS=false

echo "=== Signup UI Testrig (signup-uitestrig ns, if deployed) ==="
trigger_all_in_ns signup-uitestrig || OVERALL_SUCCESS=false

echo ""
echo "=== Testrig Execution Summary ==="
if [[ "$OVERALL_SUCCESS" == "true" ]]; then
  echo "✓ All testrig jobs completed successfully"
  exit 0
else
  echo "✗ One or more testrig jobs failed"
  exit 1
fi
