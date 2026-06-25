#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - SoftHSM eSignet MOSIPID1 Pre-install Setup
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-mosipid1 and delegates to base softhsm setup.
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-mosipid1"
exec "$WORKDIR/hooks/esignet-standalone/softhsm-esignet-setup.sh"
