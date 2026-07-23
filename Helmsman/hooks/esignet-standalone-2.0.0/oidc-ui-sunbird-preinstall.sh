#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - OIDC UI Sunbird Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-sunbird and delegates to base oidc-ui preinstall.
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-sunbird-2-0-0"
exec "$WORKDIR/hooks/esignet-standalone-2.0.0/oidc-ui-preinstall.sh"
