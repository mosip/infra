#!/bin/bash
# Pre-install / pre-upgrade hook for the standalone Grafana (logging namespace).
#
# Creates the `grafana-admin` secret read by grafana-values.yaml
# (admin.existingSecret), so no admin password is committed to the repo.
#
# Env: GRAFANA_ADMIN_PASSWORD (from secrets.GRAFANA_ADMIN_PASSWORD), optional.
#  - set:     the secret is created/updated with it (supports rotation).
#  - not set: an existing secret is left as-is; otherwise a random password is
#             generated. Read it with:
#             kubectl -n logging get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d

set -euo pipefail

NAMESPACE="logging"
SECRET="grafana-admin"
ADMIN_USER="admin"

if [ -n "${GRAFANA_ADMIN_PASSWORD:-}" ]; then
  PASSWORD="$GRAFANA_ADMIN_PASSWORD"
  echo "Creating/updating ${SECRET} from secrets.GRAFANA_ADMIN_PASSWORD..."
elif kubectl -n "$NAMESPACE" get secret "$SECRET" >/dev/null 2>&1; then
  echo "${SECRET} already exists and GRAFANA_ADMIN_PASSWORD is not set — leaving it unchanged."
  exit 0
else
  PASSWORD="$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)"
  echo "GRAFANA_ADMIN_PASSWORD is not set — generated a random admin password into ${SECRET}."
fi

kubectl create secret generic "$SECRET" -n "$NAMESPACE" \
  --from-literal=admin-user="$ADMIN_USER" \
  --from-literal=admin-password="$PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
