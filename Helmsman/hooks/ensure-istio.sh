#!/bin/bash
# preInstall of the prereq DSF's Istio addons (istio-addons-loki /
# istio-addons-logging). Makes the Istio install self-healing.
#
# Istio is normally installed by the postInstall/postUpgrade hook of
# kube-prometheus-stack (or rancher-monitoring-crd). Helmsman runs hooks only
# when it installs or upgrades that release, so if that hook was interrupted
# (e.g. a cancelled run) a re-run never retries it and Istio stays missing.
#
# Istio ready  -> returns at once (normal runs: no extra time).
# Istio missing -> runs install-istio-and-httpbin.sh with the same arguments,
#                  then waits until istiod and both ingress gateways are up.
#
# Usage: ensure-istio.sh <domain_name> <env_name>   (same args as the Istio hook)
set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"

if "$HOOKS_DIR/wait-for-istio-crds.sh" --check; then
  exit 0
fi

echo "Istio is missing or incomplete — (re)installing it now (install-istio-and-httpbin.sh)."
bash "$HOOKS_DIR/install-istio-and-httpbin.sh" "$@"
"$HOOKS_DIR/wait-for-istio-crds.sh"
