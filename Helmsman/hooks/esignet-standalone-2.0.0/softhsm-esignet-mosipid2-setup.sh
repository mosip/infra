#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - SoftHSM eSignet MOSIPID2 Pre-install Setup
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-mosipid2 and delegates to base softhsm setup.
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-mosipid2-2-0-0"
exec "$WORKDIR/hooks/esignet-standalone-2.0.0/softhsm-esignet-setup.sh"
