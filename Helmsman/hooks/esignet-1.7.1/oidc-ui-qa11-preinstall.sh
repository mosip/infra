#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - OIDC UI QA11 Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-qa11 and delegates to base oidc-ui preinstall.
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-qa11"
exec "$WORKDIR/hooks/esignet-1.7.1/oidc-ui-preinstall.sh"
