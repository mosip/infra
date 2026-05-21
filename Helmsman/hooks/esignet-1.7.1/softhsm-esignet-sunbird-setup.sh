#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - SoftHSM eSignet Sunbird Pre-install Setup
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-sunbird and delegates to base softhsm setup.
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-sunbird"
exec "$WORKDIR/hooks/esignet-1.7.1/softhsm-esignet-setup.sh"
