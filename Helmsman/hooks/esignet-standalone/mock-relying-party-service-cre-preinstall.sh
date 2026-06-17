#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Mock Relying Party Service CRE Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-cre and delegates to base mock-rp-service
# preinstall (creates private key secrets in the target namespace).
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-cre"
exec "$WORKDIR/hooks/esignet-standalone/mock-relying-party-service-preinstall.sh"
