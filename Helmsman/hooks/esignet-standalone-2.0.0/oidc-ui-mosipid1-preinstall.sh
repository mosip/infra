#!/bin/bash
# =============================================================================
# eSignet Standalone 2.0.0 - OIDC UI MOSIPID1 Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-mosipid1 and delegates to base oidc-ui preinstall.
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-go-mosipid1"
exec "$WORKDIR/hooks/esignet-standalone-2.0.0/oidc-ui-preinstall.sh"
