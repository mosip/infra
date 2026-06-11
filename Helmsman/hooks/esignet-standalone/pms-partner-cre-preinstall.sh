#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - PMS Partner CRE Pre-install
# =============================================================================
# Creates the Istio Gateway for pms-partner in esignet-cre namespace.
# =============================================================================
set -euo pipefail

ESIGNET_NS="esignet-cre"

echo "================================================"
echo "eSignet 1.7.1 - PMS Partner CRE Pre-install"
echo "================================================"

kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: pms-partner-cre-gateway
  namespace: ${ESIGNET_NS}
  labels:
    app.kubernetes.io/instance: pms-partner-cre
    app.kubernetes.io/name: pms-partner
spec:
  selector:
    istio: ingressgateway
  servers:
    - hosts:
        - pms-cre.${domain_name}
      port:
        name: https
        number: 443
        protocol: HTTPS
      tls:
        credentialName: pms-partner-cre-tls
        mode: SIMPLE
    - hosts:
        - pms-cre.${domain_name}
      port:
        name: http
        number: 80
        protocol: HTTP
EOF

echo "pms-partner-cre-gateway created/updated in $ESIGNET_NS."
