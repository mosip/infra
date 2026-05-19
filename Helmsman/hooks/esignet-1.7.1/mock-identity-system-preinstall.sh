#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Mock Identity System Pre-install
# =============================================================================
# Prepares esignet namespace for mock identity system deployment:
#   - Copies softhsm-mock-identity-system secret from softhsm ns (secretKeyRef
#     in the chart references it directly by name in the pod namespace)
#   - Creates mockid-postgres-config sourcing values from existing CMs:
#       database-host  → postgres-config.database-host  (esignet ns, internal K8s service)
#       database-port  → db-mockidentitysystem-init-env-config.DB_PORT  (postgres ns)
#       database-name  → db-mockidentitysystem-init-env-config.MOSIP_DB_NAME  (postgres ns)
#       database-username → MOCKID_DB_USER (default: mockidsystemuser)
#   - Verifies softhsm-mock-identity-system-share ConfigMap is present
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet}"
SOFTHSM_NS="softhsm"
POSTGRES_NS="postgres"
POSTGRES_INIT_CM="db-mockidentitysystem-init-env-config"
MOCKID_DB_USER="${MOCKID_DB_USER:-mockidsystemuser}"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - Mock Identity System Pre-install"
echo "================================================"

kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -

# Copy softhsm-mock-identity-system secret to esignet ns
# The chart references it directly via secretKeyRef — pod and secret must be in same namespace
$COPY_UTIL secret softhsm-mock-identity-system "$SOFTHSM_NS" "$ESIGNET_NS"
echo "softhsm-mock-identity-system secret copied to $ESIGNET_NS."

# Read internal service host from postgres-config (already in esignet ns via esignet-preinstall.sh)
# DB_SERVERIP in postgres-init CM is the external domain — not suitable for pod-to-pod connectivity
DB_HOST=$(kubectl -n "$ESIGNET_NS" get configmap postgres-config \
  -o jsonpath='{.data.database-host}' 2>/dev/null || echo "")
if [ -z "$DB_HOST" ]; then
  echo "ERROR: postgres-config not found in $ESIGNET_NS — ensure esignet-preinstall.sh has run." >&2
  exit 1
fi

# Read port and DB name from the CM created by postgres-init-mock-identity (authoritative source)
DB_PORT=$(kubectl -n "$POSTGRES_NS" get configmap "$POSTGRES_INIT_CM" \
  -o jsonpath='{.data.DB_PORT}' 2>/dev/null || echo "")
DB_NAME=$(kubectl -n "$POSTGRES_NS" get configmap "$POSTGRES_INIT_CM" \
  -o jsonpath='{.data.MOSIP_DB_NAME}' 2>/dev/null || echo "")
if [ -z "$DB_PORT" ] || [ -z "$DB_NAME" ]; then
  echo "ERROR: $POSTGRES_INIT_CM not found in $POSTGRES_NS — ensure postgres-init-mock-identity has run." >&2
  exit 1
fi

# Build mockid-postgres-config with keys expected by the mock-identity-system deployment
kubectl -n "$ESIGNET_NS" create configmap mockid-postgres-config \
  --from-literal=database-host="$DB_HOST" \
  --from-literal=database-port="$DB_PORT" \
  --from-literal=database-name="$DB_NAME" \
  --from-literal=database-username="$MOCKID_DB_USER" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "mockid-postgres-config created/updated in $ESIGNET_NS (host=$DB_HOST port=$DB_PORT db=$DB_NAME)."

# Verify SoftHSM mock identity configmap exists in esignet namespace
if kubectl -n "$ESIGNET_NS" get configmap softhsm-mock-identity-system-share &>/dev/null; then
  echo "SoftHSM mock identity system configmap found."
else
  echo "ERROR: softhsm-mock-identity-system-share configmap not found in $ESIGNET_NS namespace."
  echo "Deploy softhsm-mock-identity-system before running mock identity system install."
  exit 1
fi

echo "Mock identity system pre-install completed."
