#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Kafka Post-install
# =============================================================================
# Based on: deploy/install-prereq.sh (kafka section)
# Creates kafka-config configmap in esignet namespace after Kafka deployment.
#
# Environment Variables:
#   KAFKA_URL    - Kafka bootstrap servers URL (default: internal kafka cluster)
#   ESIGNET_NS   - eSignet namespace (default: esignet)
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet}"
KAFKA_URL="${KAFKA_URL:-kafka-0.kafka-headless.kafka.svc.cluster.local:9092,kafka-1.kafka-headless.kafka.svc.cluster.local:9092,kafka-2.kafka-headless.kafka.svc.cluster.local:9092}"

echo "================================================"
echo "eSignet 1.7.1 - Kafka Post-install"
echo "================================================"

# --- Create kafka-config configmap in esignet namespace ---
# Source: deploy/install-prereq.sh - kafka configmap creation
echo "Creating kafka-config configmap in $ESIGNET_NS namespace"
kubectl -n "$ESIGNET_NS" create configmap kafka-config \
  --from-literal=SPRING_KAFKA_BOOTSTRAP-SERVERS="$KAFKA_URL" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Kafka post-install completed."
