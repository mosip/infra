#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - SoftHSM eSignet QA11 Pre-install Setup
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-qa11 and delegates to base softhsm setup.
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-qa11"
exec "$WORKDIR/hooks/esignet-1.7.1/softhsm-esignet-setup.sh"
