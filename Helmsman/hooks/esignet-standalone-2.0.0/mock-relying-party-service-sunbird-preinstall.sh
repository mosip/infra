#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Mock Relying Party Service Sunbird Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-sunbird and delegates to base mock-rp-service
# preinstall (creates private key secrets in the target namespace).
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-sunbird-2-0-0"
exec "$WORKDIR/hooks/esignet-standalone-2.0.0/mock-relying-party-service-preinstall.sh"
