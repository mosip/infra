#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - OIDC UI MOSIPID Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-mosipid and delegates to base oidc-ui preinstall.
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-mosipid"
exec "$WORKDIR/hooks/esignet-standalone/oidc-ui-preinstall.sh"
