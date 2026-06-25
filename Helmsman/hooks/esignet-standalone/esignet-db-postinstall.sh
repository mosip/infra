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

for NS in esignet-mock esignet-mosipid1 esignet-mosipid2 esignet-sunbird; do
  echo "Copying db-common-secrets from $POSTGRES_NS to $NS"
  $COPY_UTIL secret db-common-secrets "$POSTGRES_NS" "$NS"
done

echo "Database init post-install completed."
