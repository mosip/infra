#!/bin/bash
# Waits for Istio CRDs to be available before deploying Istio-dependent resources.
# Used as preInstall for istio-addons charts when prereq-dsf and external-dsf
# run in parallel — Istio CRDs are installed by prereq-dsf and must exist
# before any VirtualService/Gateway can be created.
set -euo pipefail

TIMEOUT=600
INTERVAL=15
ELAPSED=0

echo "Waiting for Istio CRDs (VirtualService, Gateway) to be available..."
until kubectl get crd virtualservices.networking.istio.io &>/dev/null && \
      kubectl get crd gateways.networking.istio.io &>/dev/null; do
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "ERROR: Timed out waiting for Istio CRDs after ${TIMEOUT}s" >&2
    exit 1
  fi
  echo "Istio CRDs not yet available, retrying in ${INTERVAL}s... (${ELAPSED}s elapsed)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

echo "Istio CRDs available. Proceeding with istio-addons deployment."
