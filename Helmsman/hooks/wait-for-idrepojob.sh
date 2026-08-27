#!/bin/bash
# Wait for the idrepo salt generator Job to succeed before installing id-repository.
# If the Job is already gone (previous successful run), continue.
set -euo pipefail

NS=idrepo
JOB=idrepo-saltgen
TIMEOUT_SECONDS="${IDREPO_SALTGEN_WAIT_TIMEOUT:-600}"
elapsed=0

if ! kubectl get job "$JOB" -n "$NS" >/dev/null 2>&1; then
  echo "Job $JOB not found in namespace $NS; assuming saltgen already completed."
  exit 0
fi

until kubectl get job "$JOB" -n "$NS" -o jsonpath='{.status.succeeded}' 2>/dev/null | grep -q '^1$'; do
  if [ "$elapsed" -ge "$TIMEOUT_SECONDS" ]; then
    echo "Timed out waiting for job $JOB in namespace $NS"
    kubectl describe job "$JOB" -n "$NS" || true
    exit 1
  fi
  echo "Waiting for $JOB job to complete..."
  sleep 10
  elapsed=$((elapsed + 10))
done

echo "Job $JOB completed successfully."
