#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Database Init Post-install (postgres-init-esignet)
# =============================================================================
# postgres-init-esignet runs in the postgres namespace and creates
# db-common-secrets there. This hook copies it to the esignet namespace
# so the eSignet service can use it for DB connections.
#
# Environment Variables:
#   ESIGNET_NS   - eSignet namespace (default: esignet)
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet}"
POSTGRES_NS="postgres"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - Database Init Post-install"
echo "================================================"

echo "Copying db-common-secrets from $POSTGRES_NS to $ESIGNET_NS namespace"
$COPY_UTIL secret db-common-secrets "$POSTGRES_NS" "$ESIGNET_NS"

echo "Database init post-install completed."
