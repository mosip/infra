#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - SoftHSM eSignet CRE Pre-install Setup
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-cre and delegates to base softhsm setup.
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-cre"
exec "$WORKDIR/hooks/esignet-1.7.1/softhsm-esignet-setup.sh"
