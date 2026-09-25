#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Signup Keycloak Init Post-install
# =============================================================================
# Based on: esignet-signup/deploy/keycloak/keycloak-init.sh
# Syncs mosip_signup_client_secret from signup namespace back to
# keycloak namespace so it can be shared with other services.
#
# Environment Variables:
#   SIGNUP_NS - Signup namespace (default: signup)
# =============================================================================
set -euo pipefail

SIGNUP_NS="${SIGNUP_NS:-signup}"
KEYCLOAK_NS="keycloak"
SECRET_KEY="mosip_signup_client_secret"

echo "================================================"
echo "eSignet 1.7.1 - Signup Keycloak Init Post-install"
echo "================================================"

# Sync mosip_signup_client_secret from signup ns back to keycloak ns
if kubectl -n "$SIGNUP_NS" get secret keycloak-client-secrets &>/dev/null; then
  SECRET_B64=$(kubectl -n "$SIGNUP_NS" get secret keycloak-client-secrets \
    -o jsonpath="{.data.$SECRET_KEY}" 2>/dev/null || echo "")
  if [[ -n "$SECRET_B64" ]]; then
    echo "Syncing $SECRET_KEY back to $KEYCLOAK_NS namespace"
    if kubectl -n "$KEYCLOAK_NS" get secret keycloak-client-secrets &>/dev/null; then
      kubectl -n "$KEYCLOAK_NS" patch secret keycloak-client-secrets \
        --type=merge \
        -p "{\"data\":{\"$SECRET_KEY\":\"$SECRET_B64\"}}" || true
    else
      kubectl -n "$KEYCLOAK_NS" create secret generic keycloak-client-secrets \
        --from-literal=dummy=placeholder \
        --dry-run=client -o yaml | kubectl apply -f -
      kubectl -n "$KEYCLOAK_NS" patch secret keycloak-client-secrets \
        --type=merge \
        -p "{\"data\":{\"$SECRET_KEY\":\"$SECRET_B64\"}}" || true
    fi
    echo "$SECRET_KEY synced to $KEYCLOAK_NS namespace."
  fi
fi

echo "Signup keycloak init post-install completed."
