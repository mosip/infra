#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - OIDC UI CRE Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-cre and delegates to base oidc-ui preinstall.
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-cre"
exec "$WORKDIR/hooks/esignet-standalone/oidc-ui-preinstall.sh"
