#!/bin/bash
# Post-install / post-upgrade hook for keycloak-db-init (KEYCLOAK_DB=external).
# Helm only gets here when the keycloak-db-init Job succeeded, so the copied
# superuser Secret is no longer needed in the keycloak namespace.

set -euo pipefail

kubectl -n keycloak delete secret postgres-postgresql --ignore-not-found
echo "Removed the copied superuser Secret postgres-postgresql from keycloak."
