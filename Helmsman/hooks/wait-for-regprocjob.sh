#!/bin/bash

# Skip hook execution during Helmsman dry-run - namespaces and releases
# are not actually created in dry-run mode so kubectl/helm calls will fail.
if [ "${HELMSMAN_MODE:-}" = "dry-run" ]; then
  echo "[DRY-RUN] Skipping wait-for-regprocjob.sh hook (no real resources exist in dry-run)"
  exit 0
fi
# wait-for-keygen.sh
until kubectl get job regproc-salt -n regproc -o jsonpath='{.status.succeeded}' | grep 1; do
  echo "Waiting for keygen job to complete..."
  sleep 10
done
