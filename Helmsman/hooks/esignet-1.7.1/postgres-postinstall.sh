#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Postgres Post-install
# =============================================================================
# Based on: deploy/postgres/generate-secret-cm.py
# Creates postgres secrets (db-common-secrets) and configmap (postgres-config)
# after PostgreSQL helm chart deployment. Replaces interactive Python script
# with environment variable driven approach.
#
# Environment Variables:
#   DB_USER_PASSWORD     - Database user password (REQUIRED)
#   POSTGRES_HOST        - PostgreSQL host (default: postgres-postgresql.postgres)
#   POSTGRES_PORT        - PostgreSQL port (default: 5432)
#   DB_USER              - Database username (default: esignetuser)
#   DB_NAME              - Database name (default: mosip_esignet)
# =============================================================================
set -euo pipefail

POSTGRES_NS="postgres"
DB_USER_PASSWORD="${DB_USER_PASSWORD:?ERROR: DB_USER_PASSWORD environment variable must be set}"
POSTGRES_HOST="${POSTGRES_HOST:-postgres-postgresql.postgres}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
DB_USER="${DB_USER:-esignetuser}"
DB_NAME="${DB_NAME:-mosip_esignet}"

echo "================================================"
echo "eSignet 1.7.1 - Postgres Post-install"
echo "================================================"

# --- Step 1: Create db-common-secrets ---
# Source: deploy/postgres/generate-secret-cm.py -> create_or_update_secret()
echo "Creating db-common-secrets in $POSTGRES_NS namespace"
kubectl -n "$POSTGRES_NS" create secret generic db-common-secrets \
  --from-literal=db-dbuser-password="$DB_USER_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- Step 2: Create postgres-config configmap ---
# Source: deploy/postgres/generate-secret-cm.py -> create_or_update_configmap()
echo "Creating postgres-config configmap in $POSTGRES_NS namespace"
kubectl -n "$POSTGRES_NS" create configmap postgres-config \
  --from-literal=database-host="$POSTGRES_HOST" \
  --from-literal=database-port="$POSTGRES_PORT" \
  --from-literal=database-username="$DB_USER" \
  --from-literal=database-name="$DB_NAME" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Postgres post-install completed. Secrets and configmaps created."
