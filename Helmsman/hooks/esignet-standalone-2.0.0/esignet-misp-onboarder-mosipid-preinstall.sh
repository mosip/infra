#!/bin/bash
# =============================================================================
# eSignet MISP Partner Onboarder - MOSIPID Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-mosipid, then runs the base MISP onboarder
# pre-install (copies keycloak resources, cleans up stale artifacts). Skips
# the shared Keycloak admin/client secrets - this onboarder authenticates
# against mosipid's own dedicated Keycloak instead:
#   - keycloak-host-mosipid / keycloak-client-secrets-mosipid already exist in
#     esignet-mosipid (created by esignet-mosipid-preinstall.sh, which runs
#     earlier), referenced directly via the DSF's extraEnvVarsCM/Secret.
#   - keycloak-mosipid (admin-password) is created here, since no stored
#     secret for mosipid's Keycloak admin password exists yet anywhere.
# =============================================================================
set -euo pipefail

export ESIGNET_NS="esignet-mosipid"
export SKIP_SHARED_KEYCLOAK_SECRETS="true"

MOSIPID_KC_ADMIN_PASS="${MOSIPID_KEYCLOAK_ADMIN_PASSWORD:?ERROR: MOSIPID_KEYCLOAK_ADMIN_PASSWORD must be set}"

"$WORKDIR/hooks/esignet-standalone-2.0.0/esignet-misp-onboarder-preinstall.sh"

echo "Creating keycloak-mosipid secret (admin-password) in $ESIGNET_NS"
kubectl -n "$ESIGNET_NS" create secret generic keycloak-mosipid \
  --from-literal=admin-password="${MOSIPID_KC_ADMIN_PASS}" \
  --dry-run=client -o yaml | kubectl apply -f -
