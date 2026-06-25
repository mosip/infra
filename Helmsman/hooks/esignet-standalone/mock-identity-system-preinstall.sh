#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Mock Identity System Pre-install
# =============================================================================
# Prepares esignet namespace for mock identity system deployment:
#   - Copies softhsm-mock-identity-system secret from softhsm ns
#   - Creates mockid-postgres-config with mock identity DB values
#   - Verifies softhsm-mock-identity-system-share ConfigMap is present
#
# Environment Variables:
#   MOCKID_DB_NAME  - Mock identity DB name (default: mosip_mockidentitysystem)
#   MOCKID_DB_USER  - Mock identity DB user (default: mockidsystemuser)
#   MOCKID_DB_PORT  - Postgres port (default: 5432)
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet-mock}"
SOFTHSM_NS="softhsm"
MOCKID_DB_NAME="${MOCKID_DB_NAME:-mosip_mockidentitysystem}"
MOCKID_DB_USER="${MOCKID_DB_USER:-mockidsystemuser}"
MOCKID_DB_PORT="${MOCKID_DB_PORT:-5432}"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - Mock Identity System Pre-install"
echo "================================================"

kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -

# Copy softhsm-mock-identity-system secret to esignet ns
# The chart references it directly via secretKeyRef — pod and secret must be in same namespace
$COPY_UTIL secret softhsm-mock-identity-system "$SOFTHSM_NS" "$ESIGNET_NS"
echo "softhsm-mock-identity-system secret copied to $ESIGNET_NS."

# Read internal host from postgres-config (already present from esignet-preinstall.sh)
DB_HOST=$(kubectl -n "$ESIGNET_NS" get configmap postgres-config \
  -o jsonpath='{.data.database-host}' 2>/dev/null || echo "")
if [ -z "$DB_HOST" ]; then
  echo "ERROR: postgres-config not found in $ESIGNET_NS — ensure esignet-preinstall.sh has run." >&2
  exit 1
fi

# Build mockid-postgres-config — DB name/user/port are fixed for mock identity system
kubectl -n "$ESIGNET_NS" create configmap mockid-postgres-config \
  --from-literal=database-host="$DB_HOST" \
  --from-literal=database-port="$MOCKID_DB_PORT" \
  --from-literal=database-name="$MOCKID_DB_NAME" \
  --from-literal=database-username="$MOCKID_DB_USER" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "mockid-postgres-config created/updated in $ESIGNET_NS (host=$DB_HOST db=$MOCKID_DB_NAME user=$MOCKID_DB_USER)."

# Verify SoftHSM mock identity configmap exists in esignet namespace
if kubectl -n "$ESIGNET_NS" get configmap softhsm-mock-identity-system-share &>/dev/null; then
  echo "SoftHSM mock identity system configmap found."
else
  echo "ERROR: softhsm-mock-identity-system-share configmap not found in $ESIGNET_NS namespace."
  echo "Deploy softhsm-mock-identity-system before running mock identity system install."
  exit 1
fi

echo "Mock identity system pre-install completed."
