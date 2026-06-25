#!/bin/bash
# Post-install hook for esignet-keycloak-init (eSignet 1.7.1 standalone)
# The chart runs in keycloak ns and creates keycloak-host CM and
# keycloak-client-secrets secret there. This hook fans those resources out to
# all esignet namespaces so every esignet instance can reference them without
# cross-namespace lookups.
set -euo pipefail

KEYCLOAK_NS="keycloak"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

# All esignet namespaces that need keycloak resources
ESIGNET_NAMESPACES=(esignet esignet-mosipid1 esignet-mosipid2 esignet-sunbird)

echo "================================================"
echo "eSignet 1.7.1 - Keycloak Init Post-install"
echo "================================================"

echo "Sharing keycloak resources from $KEYCLOAK_NS to all esignet namespaces"
for NS_TARGET in "${ESIGNET_NAMESPACES[@]}"; do
  if ! kubectl get namespace "$NS_TARGET" &>/dev/null; then
    echo "Namespace $NS_TARGET does not exist, skipping"
    continue
  fi
  echo "  → $NS_TARGET"
  $COPY_UTIL configmap keycloak-host        "$KEYCLOAK_NS" "$NS_TARGET"
  $COPY_UTIL configmap keycloak-env-vars    "$KEYCLOAK_NS" "$NS_TARGET"
  $COPY_UTIL secret    keycloak             "$KEYCLOAK_NS" "$NS_TARGET"
  $COPY_UTIL secret    keycloak-client-secrets "$KEYCLOAK_NS" "$NS_TARGET"
done

echo "Post-install setup complete."
