#!/bin/bash
# Pre-install / pre-upgrade hook for kube-prometheus-stack.
#
# Usage: monitoring-preinstall.sh <kube-prometheus-stack chart version>
# Env:   SMTP_PASSWORD (from secrets.SMTP_PASSWORD) — read from the environment,
#        not passed as an argument, so it never appears in the hook command line.
#
# 1. Applies the prometheus-operator CRDs shipped with that exact chart version
#    (server-side). Helm only installs CRDs on first install and never upgrades
#    them, so this runs on every install AND upgrade and always matches the chart.
# 2. Creates or updates the alertmanager-smtp secret, so a rotated SMTP password
#    is picked up on the next run.

set -euo pipefail

CHART_VERSION="${1:?usage: $0 <kube-prometheus-stack chart version>}"
CHART_REPO="https://prometheus-community.github.io/helm-charts"
NAMESPACE="monitoring"

[ -n "${SMTP_PASSWORD:-}" ]    || { echo "ERROR: secrets.SMTP_PASSWORD is not set (needed for Alertmanager email)."; exit 1; }
[ -n "${smtp_from:-}" ]        || { echo "ERROR: SMTP sender is empty — set vars.SMTP_FROM (or legacy vars.MAIL_ID)."; exit 1; }
[ -n "${alert_recipients:-}" ] || { echo "ERROR: alert recipients are empty — set vars.ALERT_RECIPIENTS (or legacy vars.MAIL_ID)."; exit 1; }

echo "Applying prometheus-operator CRDs from kube-prometheus-stack ${CHART_VERSION}..."
helm show crds kube-prometheus-stack --repo "$CHART_REPO" --version "$CHART_VERSION" \
  | kubectl apply --server-side --force-conflicts -f -

echo "Creating/updating alertmanager-smtp secret in ${NAMESPACE}..."
kubectl create secret generic alertmanager-smtp -n "$NAMESPACE" \
  --from-literal=password="$SMTP_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
