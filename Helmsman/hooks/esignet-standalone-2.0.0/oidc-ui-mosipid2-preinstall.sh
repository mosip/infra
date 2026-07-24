#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - OIDC UI MOSIPID2 Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-mosipid2 and delegates to base oidc-ui preinstall.
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-go-mosipid2"
exec "$WORKDIR/hooks/esignet-standalone-2.0.0/oidc-ui-preinstall.sh"
