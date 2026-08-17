#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - SoftHSM eSignet MOSIPID Pre-install Setup
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-mosipid and delegates to base softhsm setup.
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-mosipid"
exec "$WORKDIR/hooks/esignet-standalone-2.0.0/softhsm-esignet-setup.sh"
