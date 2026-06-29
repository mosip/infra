#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - PMS Partner MOSIPID1 Pre-install
# =============================================================================
# Creates the Istio Gateway for pms-partner in esignet-mosipid1 namespace.
# =============================================================================
set -euo pipefail

ESIGNET_NS="esignet-mosipid1"

echo "================================================"
echo "eSignet 1.7.1 - PMS Partner MOSIPID1 Pre-install"
echo "================================================"

kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: pms-partner-mosipid1-gateway
  namespace: ${ESIGNET_NS}
  labels:
    app.kubernetes.io/instance: pms-partner-mosipid1
    app.kubernetes.io/name: pms-partner
spec:
  selector:
    istio: ingressgateway
  servers:
    - hosts:
        - pms-mosipid1.${domain_name}
      port:
        name: https
        number: 443
        protocol: HTTPS
      tls:
        credentialName: pms-partner-mosipid1-tls
        mode: SIMPLE
    - hosts:
        - pms-mosipid1.${domain_name}
      port:
        name: http
        number: 80
        protocol: HTTP
EOF

echo "pms-partner-mosipid1-gateway created/updated in $ESIGNET_NS."
