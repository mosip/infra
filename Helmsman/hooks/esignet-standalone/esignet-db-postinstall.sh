#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Database Init Post-install (postgres-init-esignet-mock)
# =============================================================================
# postgres-init-esignet-mock runs in the postgres namespace and creates
# db-common-secrets there. This hook copies it to all esignet-mock namespaces
# so each eSignet instance can use it for DB connections.
# =============================================================================
set -euo pipefail

POSTGRES_NS="postgres"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - Database Init Post-install"
echo "================================================"

for NS in esignet-mock esignet-mosipid esignet-sunbird; do
  echo "Copying db-common-secrets from $POSTGRES_NS to $NS"
  $COPY_UTIL secret db-common-secrets "$POSTGRES_NS" "$NS"
done

# esignet-standalone-2.0.0 namespaces - refresh only if that profile is deployed
# (its own esignet preinstall hooks copy the secret on first install).
for NS in esignet-go-mock esignet-go-mosipid esignet-go-sunbird; do
  if ! kubectl get namespace "$NS" &>/dev/null; then
    echo "Namespace $NS does not exist, skipping"
    continue
  fi
  echo "Copying db-common-secrets from $POSTGRES_NS to $NS"
  $COPY_UTIL secret db-common-secrets "$POSTGRES_NS" "$NS"
done

echo "Database init post-install completed."
