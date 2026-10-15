#!/usr/bin/env bash
#
# instance-power.sh - Show, stop or start EC2 instances by private IP.
#
# Works for any instance in the VPC: cluster nodes, standalone VMs, or
# instances created outside this repo. Every IP must match exactly one
# instance in the named VPC, otherwise nothing is changed.
#
# Order comes from the instance's Role tag when it has one, because etcd runs
# on the control-plane nodes and nginx serves NFS/PostgreSQL to the pods:
#   start: nginx -> control-plane -> etcd -> worker -> other
#   stop:  other -> worker -> etcd -> control-plane -> nginx
# Each group is waited for before the next one.
#
# Without --apply nothing changes (dry run).
#
# Usage:
#   instance-power.sh --action status|stop|start --ips 10.0.3.5,10.0.3.6 \
#                     --vpc-name <vpc Name tag> [--region ap-south-1] [--apply]

set -euo pipefail

MAX_IPS=20

ACTION=""
IPS=""
VPC_NAME=""
REGION="ap-south-1"
APPLY="false"

err() { echo "[instance-power][ERROR] $*" >&2; }
die() { err "$*"; exit 1; }
log() { echo "[instance-power] $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)   ACTION="${2-}"; shift 2 ;;
    --ips)      IPS="${2-}"; shift 2 ;;
    --vpc-name) VPC_NAME="${2-}"; shift 2 ;;
    --region)   REGION="${2-}"; shift 2 ;;
    --apply)    APPLY="true"; shift ;;
    *) die "unknown argument" ;;
  esac
done

# ── validate every input before any AWS call ─────────────────────────────────
[[ "$ACTION" =~ ^(status|stop|start)$ ]] || die "action must be status, stop or start"
[[ "$REGION" =~ ^[a-z]{2}(-gov)?-[a-z]+-[0-9]$ ]] || die "region is not a valid AWS region name"
[[ "$VPC_NAME" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || die "VPC name may only contain letters, digits, '.', '_' and '-' (max 128)"

IPS="${IPS//[[:space:]]/}"
[[ -n "$IPS" ]] || die "at least one instance IP is required"
[[ "$IPS" =~ ^[0-9.,]+$ ]] || die "instance IPs may only contain digits, '.' and ','"
IFS=',' read -r -a ip_list <<<"$IPS"
[[ ${#ip_list[@]} -le $MAX_IPS ]] || die "at most $MAX_IPS IPs per run"
declare -A seen=()
for ip in "${ip_list[@]}"; do
  [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || die "not an IPv4 address: '$ip'"
  for octet in "${BASH_REMATCH[@]:1}"; do
    (( 10#$octet <= 255 )) || die "not an IPv4 address: '$ip'"
  done
  [[ -z "${seen[$ip]+x}" ]] || die "IP listed twice: $ip"
  seen[$ip]=1
done

# ── resolve the VPC (exactly one) ────────────────────────────────────────────
vpc_ids="$(aws ec2 describe-vpcs --region "$REGION" \
  --filters "Name=tag:Name,Values=${VPC_NAME}" \
  --query 'Vpcs[].VpcId' --output text)"
read -r -a vpc_arr <<<"$vpc_ids"
[[ ${#vpc_arr[@]} -eq 1 ]] || die "expected exactly one VPC named '${VPC_NAME}' in ${REGION}, found ${#vpc_arr[@]}"
VPC_ID="${vpc_arr[0]}"

# ── find the instances: IP, id, state, Role, Name (tab-separated) ───────────
# shellcheck disable=SC2016  # backticks are JMESPath literals, not shell
rows="$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
            "Name=private-ip-address,Values=${IPS}" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].[PrivateIpAddress, InstanceId, State.Name, Tags[?Key==`Role`]|[0].Value, Tags[?Key==`Name`]|[0].Value]' \
  --output text)"

for ip in "${ip_list[@]}"; do
  n="$(awk -F'\t' -v ip="$ip" '$1 == ip' <<<"$rows" | grep -c . || true)"
  [[ "$n" -eq 1 ]] || die "IP $ip matches $n instances in VPC ${VPC_NAME} (${VPC_ID}) — expected exactly 1; nothing changed"
done

log "VPC ${VPC_NAME} (${VPC_ID}), ${REGION}:"
printf '%-15s %-21s %-9s %-14s %s\n' PRIVATE_IP INSTANCE STATE ROLE NAME >&2
nginx_selected="false"
while IFS=$'\t' read -r ip id state role name; do
  [[ "$role" == "None" ]] && role="-"
  [[ "$name" == "None" ]] && name="-"
  [[ "$role" == "nginx" ]] && nginx_selected="true"
  printf '%-15s %-21s %-9s %-14s %s\n' "$ip" "$id" "$state" "$role" "$name" >&2
done <<<"$rows"

[[ "$ACTION" == "status" ]] && exit 0

if [[ "$nginx_selected" == "true" ]]; then
  log "WARNING: an nginx node is selected — it holds the public IP, NFS and PostgreSQL for its cluster"
fi

if [[ "$ACTION" == "start" ]]; then
  order=(nginx control-plane etcd worker other); from=" stopped "; verb="start-instances"; waiter="instance-running"
else
  order=(other worker etcd control-plane nginx); from=" running pending "; verb="stop-instances"; waiter="instance-stopped"
fi

changed=0
for group in "${order[@]}"; do
  ids=()
  while IFS=$'\t' read -r _ip id state role _name; do
    case "$role" in nginx|control-plane|etcd|worker) ;; *) role="other" ;; esac
    [[ "$role" == "$group" && "$from" == *" $state "* ]] && ids+=("$id")
  done <<<"$rows"
  [[ ${#ids[@]} -gt 0 ]] || continue
  changed=1
  if [[ "$APPLY" != "true" ]]; then
    log "dry run: would ${ACTION} ${group}: ${ids[*]}"
    continue
  fi
  log "${ACTION} ${group}: ${ids[*]}"
  aws ec2 "$verb" --region "$REGION" --instance-ids "${ids[@]}" >/dev/null
  aws ec2 wait "$waiter" --region "$REGION" --instance-ids "${ids[@]}"
  log "${group}: done"
done

if [[ "$changed" -eq 0 ]]; then
  log "nothing to ${ACTION} — the selected instances are already $([[ "$ACTION" == start ]] && echo running || echo stopped)"
elif [[ "$APPLY" != "true" ]]; then
  log "dry run only — choose MODE=apply to ${ACTION}"
fi
