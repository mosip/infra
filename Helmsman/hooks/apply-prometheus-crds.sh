#!/bin/bash
set -e
VERSION=v0.93.1   # match the operator version in the chart
CRD_BASE="https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/${VERSION}/example/prometheus-operator-crd"
for crd in alertmanagers alertmanagerconfigs prometheuses prometheusagents \
           scrapeconfigs podmonitors probes prometheusrules thanosrulers servicemonitors; do
  kubectl apply --server-side --force-conflicts -f "${CRD_BASE}/monitoring.coreos.com_${crd}.yaml"
done
