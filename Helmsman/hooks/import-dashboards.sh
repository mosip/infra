#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="loki-monitoring"
DASHBOARD_DIR="${WORKDIR:-.}/utils/loki/dashboards"

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=grafana \
  -n "$NAMESPACE" \
  --timeout=120s >/dev/null 2>&1 \
  || echo "WARN: Grafana not ready — dashboards will load when sidecar starts"

if [ ! -d "$DASHBOARD_DIR" ]; then
  echo "WARN: '$DASHBOARD_DIR' not found — skipping dashboard import"
  exit 0
fi

shopt -s nullglob
dashboard_files=( "$DASHBOARD_DIR"/*.json )
shopt -u nullglob

if [ ${#dashboard_files[@]} -eq 0 ]; then
  echo "WARN: No JSON files in $DASHBOARD_DIR/ — skipping"
  exit 0
fi

for f in "${dashboard_files[@]}"; do
  cm_name=$(basename "$f" .json | tr '[:upper:]_.' '[:lower:]--' | sed 's/[^a-z0-9-]//g')
  echo "  → $f as ConfigMap '$cm_name'"
  kubectl create configmap "$cm_name" \
    --namespace "$NAMESPACE" \
    --from-file="$f" \
    --dry-run=client -o yaml \
    | kubectl label --local -f - grafana_dashboard=1 -o yaml \
    | kubectl apply -f -
done

echo "Submitted ${#dashboard_files[@]} dashboard(s)"
