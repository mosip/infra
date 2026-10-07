#!/bin/bash

# Renders an Ansible YAML inventory from #273's decoupled Terraform
# components' `terraform output -json`, for the new `configure` job in
# terraform.yml. Replaces the old rke2-cluster module's Terraform-templated
# inventory.yml.tpl (same host-naming/group-naming convention, so
# ansible/{nfs,rke2}'s hardcoded "<cluster_name>-CONTROL-PLANE-NODE-1"
# expectations still resolve correctly) — this is the one shared piece of
# glue code the Ansible unwrap (#282) depends on.
#
# Usage:
#   generate-ansible-inventory.sh \
#     --compute-output <path to `terraform output -json` from the compute component> \
#     --cluster-name <name> \
#     --cluster-env-domain <domain> \
#     --k8s-infra-repo-url <url> \
#     --k8s-infra-branch <branch> \
#     --certbot-email <email> \
#     --nginx-type <mosip|observability> \
#     --subdomain-public <comma-separated list, may be empty> \
#     --deployment-type <infra|observ-infra> \
#     --ssh-key-file <path> \
#     --output <path to write the rendered inventory>

set -euo pipefail

usage() {
    echo "Usage: $0 --compute-output <file> --cluster-name <name> --cluster-env-domain <domain>"
    echo "          --k8s-infra-repo-url <url> --k8s-infra-branch <branch> --certbot-email <email>"
    echo "          --nginx-type <mosip|observability> --subdomain-public <csv> --deployment-type <infra|observ-infra>"
    echo "          --ssh-key-file <path> --output <path>"
}

COMPUTE_OUTPUT=""
CLUSTER_NAME=""
CLUSTER_ENV_DOMAIN=""
K8S_INFRA_REPO_URL=""
K8S_INFRA_BRANCH=""
CERTBOT_EMAIL=""
NGINX_TYPE="mosip"
SUBDOMAIN_PUBLIC=""
DEPLOYMENT_TYPE="infra"
SSH_KEY_FILE=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --compute-output) COMPUTE_OUTPUT="$2"; shift 2 ;;
        --cluster-name) CLUSTER_NAME="$2"; shift 2 ;;
        --cluster-env-domain) CLUSTER_ENV_DOMAIN="$2"; shift 2 ;;
        --k8s-infra-repo-url) K8S_INFRA_REPO_URL="$2"; shift 2 ;;
        --k8s-infra-branch) K8S_INFRA_BRANCH="$2"; shift 2 ;;
        --certbot-email) CERTBOT_EMAIL="$2"; shift 2 ;;
        --nginx-type) NGINX_TYPE="$2"; shift 2 ;;
        --subdomain-public) SUBDOMAIN_PUBLIC="$2"; shift 2 ;;
        --deployment-type) DEPLOYMENT_TYPE="$2"; shift 2 ;;
        --ssh-key-file) SSH_KEY_FILE="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

for req in COMPUTE_OUTPUT CLUSTER_NAME CLUSTER_ENV_DOMAIN K8S_INFRA_REPO_URL K8S_INFRA_BRANCH SSH_KEY_FILE OUTPUT; do
    if [ -z "${!req}" ]; then
        echo "Error: --$(echo "$req" | tr '[:upper:]_' '[:lower:]-') is required"
        usage
        exit 1
    fi
done

if [ ! -f "$COMPUTE_OUTPUT" ]; then
    echo "Error: compute output file not found: $COMPUTE_OUTPUT"
    echo "Has the compute component actually been applied yet?"
    exit 1
fi

NGINX_PUBLIC_IP=$(jq -r '.nginx_public_ip.value' "$COMPUTE_OUTPUT")
NGINX_PRIVATE_IP=$(jq -r '.nginx_private_ip.value' "$COMPUTE_OUTPUT")

if [ -z "$NGINX_PUBLIC_IP" ] || [ "$NGINX_PUBLIC_IP" = "null" ]; then
    echo "Error: nginx_public_ip missing from compute output — has compute been applied?"
    exit 1
fi

# public_domain_list — same pattern as the dns module's own locals
# (sub.cluster_env_domain for each subdomain_public entry), reconstructed
# here rather than adding a new Terraform output for it.
PUBLIC_DOMAINS="api.${CLUSTER_ENV_DOMAIN}"
if [ -n "$SUBDOMAIN_PUBLIC" ]; then
    IFS=',' read -ra SUBS <<< "$SUBDOMAIN_PUBLIC"
    for sub in "${SUBS[@]}"; do
        sub_trimmed="$(echo "$sub" | xargs)"
        [ -n "$sub_trimmed" ] && PUBLIC_DOMAINS="${PUBLIC_DOMAINS},${sub_trimmed}.${CLUSTER_ENV_DOMAIN}"
    done
fi

# k8s_node_ips is a map keyed "CONTROL-PLANE-NODE-1"/"ETCD-NODE-1"/"WORKER-NODE-1"
# (see terraform/modules/aws/compute/outputs.tf) — role is derived from the
# key prefix, matching #275's Role tag convention exactly.
NODE_KEYS=$(jq -r '.k8s_node_ips.value | keys[]' "$COMPUTE_OUTPUT")

{
    echo "---"
    echo "all:"
    echo "  vars:"
    echo "    cluster_name: \"${CLUSTER_NAME}\""
    echo "    cluster_env_domain: \"${CLUSTER_ENV_DOMAIN}\""
    echo "    k8s_infra_repo_url: \"${K8S_INFRA_REPO_URL}\""
    echo "    k8s_infra_branch: \"${K8S_INFRA_BRANCH}\""
    echo "    certbot_email: \"${CERTBOT_EMAIL}\""
    echo "    nginx_type: \"${NGINX_TYPE}\""
    echo "    deployment_type: \"${DEPLOYMENT_TYPE}\""
    echo "    nginx_public_ip: \"${NGINX_PUBLIC_IP}\""
    echo "    k8s_node_ips_joined: \"$(jq -r '.k8s_node_ips.value | to_entries | map(.value) | join(",")' "$COMPUTE_OUTPUT")\""
    echo "    public_domain_list: \"${PUBLIC_DOMAINS}\""
    echo "    k8s_primary_control_plane_ip: \"$(jq -r '.k8s_primary_control_plane_ip.value' "$COMPUTE_OUTPUT")\""
    echo "    ansible_user: ubuntu"
    echo "    ansible_ssh_private_key_file: \"${SSH_KEY_FILE}\""
    echo "    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'"
    echo "  children:"
    echo "    nginx:"
    echo "      hosts:"
    echo "        ${CLUSTER_NAME}-NGINX-NODE:"
    echo "          ansible_host: \"${NGINX_PRIVATE_IP}\""
    echo "          nginx_public_ip: \"${NGINX_PUBLIC_IP}\""

    for group in control_plane etcd workers; do
        prefix=""
        role=""
        case "$group" in
            control_plane) prefix="CONTROL-PLANE-NODE"; role="control-plane" ;;
            etcd) prefix="ETCD-NODE"; role="etcd" ;;
            workers) prefix="WORKER-NODE"; role="worker" ;;
        esac

        matches=$(echo "$NODE_KEYS" | grep "^${prefix}-" || true)
        if [ -z "$matches" ]; then
            continue
        fi

        echo "    ${group}:"
        echo "      hosts:"
        while IFS= read -r key; do
            [ -z "$key" ] && continue
            ip=$(jq -r --arg k "$key" '.k8s_node_ips.value[$k]' "$COMPUTE_OUTPUT")
            echo "        ${CLUSTER_NAME}-${key}:"
            echo "          ansible_host: \"${ip}\""
            echo "          node_role: \"${role}\""
        done <<< "$matches"
    done

    echo "    rke2_cluster:"
    echo "      children:"
    echo "        control_plane:"
    if echo "$NODE_KEYS" | grep -q "^ETCD-NODE-"; then
        echo "        etcd:"
    fi
    if echo "$NODE_KEYS" | grep -q "^WORKER-NODE-"; then
        echo "        workers:"
    fi
} > "$OUTPUT"

echo "Rendered Ansible inventory: $OUTPUT"
cat "$OUTPUT"
