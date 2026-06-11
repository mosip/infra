#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - OIDC UI Sunbird Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-sunbird and delegates to base oidc-ui preinstall.
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-sunbird"
exec "$WORKDIR/hooks/esignet-standalone/oidc-ui-preinstall.sh"
