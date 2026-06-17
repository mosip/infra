#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - PMS Partner QA11 Pre-install
# =============================================================================
# Creates the Istio Gateway for pms-partner in esignet-qa11 namespace.
# =============================================================================
set -euo pipefail

ESIGNET_NS="esignet-qa11"

echo "================================================"
echo "eSignet 1.7.1 - PMS Partner QA11 Pre-install"
echo "================================================"

kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: pms-partner-qa11-gateway
  namespace: ${ESIGNET_NS}
  labels:
    app.kubernetes.io/instance: pms-partner-qa11
    app.kubernetes.io/name: pms-partner
spec:
  selector:
    istio: ingressgateway
  servers:
    - hosts:
        - pms-qa11.${domain_name}
      port:
        name: https
        number: 443
        protocol: HTTPS
      tls:
        credentialName: pms-partner-qa11-tls
        mode: SIMPLE
    - hosts:
        - pms-qa11.${domain_name}
      port:
        name: http
        number: 80
        protocol: HTTP
EOF

echo "pms-partner-qa11-gateway created/updated in $ESIGNET_NS."
