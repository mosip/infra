#!/bin/bash
# Waits until Istio is fully deployed before an Istio-dependent release is
# installed (preInstall of activemq / istio-addons-* in the external DSFs).
#
# prereq-dsf and external-dsf run in parallel; Istio is installed by the
# prereq DSF (install-istio-and-httpbin.sh, after kube-prometheus-stack or
# rancher-monitoring-crd). Only the Istio-dependent releases wait here — every
# other external release keeps deploying in parallel — and on a cluster where
# Istio is already up the check returns immediately.
#
# Ready = the VirtualService and Gateway CRDs exist AND istiod and both
# ingress gateways are Available (same deployments the Istio hook waits for;
# istiod also serves the validation webhook used when Istio objects are created).
#
# Env: ISTIO_WAIT_TIMEOUT (seconds, default 300), ISTIO_WAIT_INTERVAL (default 15).
#
# Usage: wait-for-istio-crds.sh            wait until ready (or time out)
#        wait-for-istio-crds.sh --check    exit 0 if ready now, 1 if not (no wait)
set -euo pipefail

TIMEOUT="${ISTIO_WAIT_TIMEOUT:-300}"
INTERVAL="${ISTIO_WAIT_INTERVAL:-15}"
ISTIO_NS="istio-system"
CRDS=(virtualservices.networking.istio.io gateways.networking.istio.io)
DEPLOYMENTS=(istiod istio-ingressgateway istio-ingressgateway-internal)

missing() {
  local out=() crd dep status
  for crd in "${CRDS[@]}"; do
    kubectl get crd "$crd" >/dev/null 2>&1 || out+=("crd/$crd")
  done
  for dep in "${DEPLOYMENTS[@]}"; do
    status=$(kubectl -n "$ISTIO_NS" get deploy "$dep" \
      -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)
    [ "$status" = "True" ] || out+=("deploy/$dep")
  done
  echo "${out[*]:-}"
}

elapsed=0
todo=$(missing)
if [ "${1:-}" = "--check" ]; then
  [ -z "$todo" ] && { echo "Istio is ready."; exit 0; }
  echo "Istio not ready: ${todo}"
  exit 1
fi
if [ -z "$todo" ]; then
  echo "Istio is ready (CRDs + istiod + ingress gateways)."
  exit 0
fi

echo "Waiting for Istio (installed by the prereq DSF in parallel), up to ${TIMEOUT}s..."
while [ -n "$todo" ]; do
  if [ "$elapsed" -ge "$TIMEOUT" ]; then
    echo "ERROR: Istio not ready after ${TIMEOUT}s — still missing: ${todo}" >&2
    echo "Istio is installed by the prereq DSF (install-istio-and-httpbin.sh); check that job, or: kubectl get pods -n ${ISTIO_NS}" >&2
    exit 1
  fi
  echo "  not ready yet (${elapsed}s): ${todo}"
  sleep "$INTERVAL"
  elapsed=$((elapsed + INTERVAL))
  todo=$(missing)
done

echo "Istio is ready after ${elapsed}s. Proceeding."
