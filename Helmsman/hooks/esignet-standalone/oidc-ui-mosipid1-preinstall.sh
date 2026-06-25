#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - OIDC UI MOSIPID1 Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-mosipid1 and delegates to base oidc-ui preinstall.
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-mosipid1"
exec "$WORKDIR/hooks/esignet-standalone/oidc-ui-preinstall.sh"
