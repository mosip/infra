#!/bin/bash

# Skip hook execution during Helmsman dry-run - namespaces and releases
# are not actually created in dry-run mode so kubectl/helm calls will fail.
if [ "${HELMSMAN_MODE:-}" = "dry-run" ]; then
  echo "[DRY-RUN] Skipping pre-helmsman-cleanup.sh hook (no real resources exist in dry-run)"
  exit 0
fi
# Pre-Helmsman cleanup script
# This script MUST be run BEFORE helmsman to delete immutable Jobs
# that would otherwise cause diffing failures
#
# Usage: ./pre-helmsman-cleanup.sh [kubeconfig]
#
# Why is this needed?
# Kubernetes Jobs are immutable - their spec.template cannot be updated.
# When Helmsman tries to diff/upgrade, it fails because existing Jobs
# cannot be modified. This script deletes the Jobs so Helm can recreate them.

if [ $# -ge 1 ] ; then
  export KUBECONFIG=$1
fi

NS=esignet

echo "=============================================="
echo "Pre-Helmsman cleanup: Deleting immutable Jobs"
echo "=============================================="

# Delete partner-onboarder jobs that cause immutability errors
echo "Deleting esignet-resident-oidc-partner-onboarder jobs..."
kubectl -n $NS delete job -l app.kubernetes.io/instance=esignet-resident-oidc-partner-onboarder --ignore-not-found=true

echo "Deleting esignet-demo-oidc-partner-onboarder jobs..."
kubectl -n $NS delete job -l app.kubernetes.io/instance=esignet-demo-oidc-partner-onboarder --ignore-not-found=true

# Also delete by job name directly in case labels don't match
echo "Deleting jobs by name..."
kubectl -n $NS delete job esignet-resident-oidc-partner-onboarder-esignet --ignore-not-found=true
kubectl -n $NS delete job esignet-demo-oidc-partner-onboarder-demo-oidc --ignore-not-found=true

# Wait for pods to terminate
echo "Waiting for job pods to terminate..."
sleep 10

# Verify deletion
REMAINING_JOBS=$(kubectl -n $NS get jobs -l "app.kubernetes.io/name=partner-onboarder" -o name 2>/dev/null || echo "")
if [ -n "$REMAINING_JOBS" ]; then
  echo "WARNING: Some jobs still exist:"
  echo "$REMAINING_JOBS"
else
  echo "All partner-onboarder jobs deleted successfully"
fi

echo "Pre-Helmsman cleanup complete"
