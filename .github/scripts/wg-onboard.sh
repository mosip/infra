#!/usr/bin/env bash
#
# wg-onboard.sh - Self-service WireGuard onboarding for a new environment.
#
# Automates the manual jumpserver process:
#   1. SSH into the WireGuard VM.
#   2. cd into the WireGuard env dir (default /home/ubuntu/wireguard_env_2026).
#   3. Allocate the next 3 free peers (assigned.txt is the source of truth) and
#      append them for the new environment - one peer per secret:
#         peerA <env>(TF_WG_CONFIG)
#         peerB <env>(CLUSTER_WIREGUARD_WG0)
#         peerC <env>(CLUSTER_WIREGUARD_WG1)
#   4. For each peer's client conf (config/peerN/peerN.conf):
#         - remove the `DNS = ...` line
#         - set `AllowedIPs = 172.31.0.0/16`
#   5. Publish the 3 transformed confs as GitHub *environment* secrets
#      (TF_WG_CONFIG, CLUSTER_WIREGUARD_WG0, CLUSTER_WIREGUARD_WG1) on the
#      environment whose name == the branch/env name.
#
# Three distinct peers are used because the Helmsman wg0/wg1 matrix jobs run
# concurrently and Terraform uses its own peer too.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLOCATION_FILE="${ALLOCATION_FILE:-$SCRIPT_DIR/wg-peer-allocation.tsv}"

# Defaults (override via flags or env vars)
SSH_USER="${SSH_USER:-ubuntu}"
SSH_KEY="${SSH_KEY:-}"
JUMPSERVER_HOST="${JUMPSERVER_HOST:-}"
ENV_NAME="${ENV_NAME:-}"
REPO="${REPO:-}"
WG_DIR="${WG_DIR:-/home/ubuntu/wireguard_env_2026}"
ALLOWED_IPS="${ALLOWED_IPS:-172.31.0.0/16}"
TICKET="${TICKET:-}"
TF_PEER=""
WG0_PEER=""
WG1_PEER=""
DRY_RUN="false"

# Secret name -> peer variable mapping is fixed in this order.
SECRET_NAMES=(TF_WG_CONFIG CLUSTER_WIREGUARD_WG0 CLUSTER_WIREGUARD_WG1)

usage() {
  cat <<'EOF'
Usage: wg-onboard.sh --env <name> --host <jumpserver_ip> --ssh-key <path> [options]

Required:
  --env <name>          Environment / branch name (also the label in assigned.txt
                        and the GitHub environment to target)
  --host <ip|dns>       Jumpserver public IP or DNS (SSH reachable)
  --ssh-key <path>      Path to the private key for ubuntu@jumpserver

Optional:
  --repo <owner/repo>   GitHub repo (default: inferred from `gh repo view`)
  --ticket <id>         Ticket id to record in assigned.txt, e.g. DSD-10264
  --wg-dir <path>       WireGuard env dir on the VM (default: /home/ubuntu/wireguard_env_2026)
  --allowed-ips <cidr>  AllowedIPs to set in each conf (default: 172.31.0.0/16)
  --tf-peer  <peerN>    Force the TF_WG_CONFIG peer          (default: next free)
  --wg0-peer <peerN>    Force the CLUSTER_WIREGUARD_WG0 peer (default: next free)
  --wg1-peer <peerN>    Force the CLUSTER_WIREGUARD_WG1 peer (default: next free)
  --dry-run             Resolve + transform + print actions without writing anything
  -h, --help            Show this help

Requires: gh (authenticated with a token that can write environment secrets), ssh.
EOF
}

log()  { echo "[wg-onboard] $*"; }
err()  { echo "[wg-onboard][ERROR] $*" >&2; }
die()  { err "$*"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)         ENV_NAME="$2"; shift 2 ;;
    --host)        JUMPSERVER_HOST="$2"; shift 2 ;;
    --ssh-key)     SSH_KEY="$2"; shift 2 ;;
    --repo)        REPO="$2"; shift 2 ;;
    --ticket)      TICKET="$2"; shift 2 ;;
    --wg-dir)      WG_DIR="$2"; shift 2 ;;
    --allowed-ips) ALLOWED_IPS="$2"; shift 2 ;;
    --tf-peer)     TF_PEER="$2"; shift 2 ;;
    --wg0-peer)    WG0_PEER="$2"; shift 2 ;;
    --wg1-peer)    WG1_PEER="$2"; shift 2 ;;
    --dry-run)     DRY_RUN="true"; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "Unknown argument: $1 (use --help)" ;;
  esac
done

[[ -n "$ENV_NAME" ]]        || die "--env is required"
[[ -n "$JUMPSERVER_HOST" ]] || die "--host is required"
[[ -n "$SSH_KEY" ]]         || die "--ssh-key is required"
[[ -f "$SSH_KEY" ]]         || die "ssh key not found: $SSH_KEY"
command -v gh  >/dev/null 2>&1 || die "gh CLI is required"
command -v ssh >/dev/null 2>&1 || die "ssh is required"

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  [[ -n "$REPO" ]] || die "Could not infer repo; pass --repo <owner/repo>"
fi

CONFIG_DIR="$WG_DIR/config"
ASSIGNED_FILE="$WG_DIR/assigned.txt"
LABEL="$ENV_NAME"
[[ -n "$TICKET" ]] && LABEL="${ENV_NAME}(${TICKET})"

log "Target repo: $REPO"
log "Target environment: $ENV_NAME (label: $LABEL)"
log "WireGuard dir: $WG_DIR | AllowedIPs: $ALLOWED_IPS"

ssh_cmd() {
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15 \
    "${SSH_USER}@${JUMPSERVER_HOST}" "$@"
}

# ---- Read current state from the jumpserver --------------------------------
log "Reading assigned.txt and peer inventory from jumpserver ${JUMPSERVER_HOST} ..."
ASSIGNED_CONTENT="$(ssh_cmd "cat '$ASSIGNED_FILE' 2>/dev/null" || true)"
PEER_LISTING="$(ssh_cmd "ls '$CONFIG_DIR'" 2>/dev/null || true)"
[[ -n "$PEER_LISTING" ]] || die "Could not list $CONFIG_DIR on jumpserver (check --wg-dir / connectivity)"

# Peers that physically exist as client configs
mapfile -t EXISTING_PEERS < <(printf '%s\n' "$PEER_LISTING" | grep -E '^peer[0-9]+$' | sort -t r -k2 -n)
[[ ${#EXISTING_PEERS[@]} -gt 0 ]] || die "No peer directories found under $CONFIG_DIR"

# Peers already taken (a peerN line in assigned.txt that has a non-empty label)
declare -A TAKEN=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  peer="$(awk '{print $1}' <<<"$line")"
  [[ "$peer" =~ ^peer[0-9]+$ ]] || continue
  rest="$(awk '{$1=""; sub(/^ +/,""); print}' <<<"$line")"
  [[ -n "$rest" ]] && TAKEN["$peer"]=1
done <<<"$ASSIGNED_CONTENT"

# ---- Reuse existing allocation for this env, if present (idempotent) -------
find_assigned_peer() {
  local secret="$1"
  awk -v env="$ENV_NAME" -v sec="($secret)" '
    $1 ~ /^peer[0-9]+$/ {
      desc=substr($0, index($0,$2))
      if (index(desc, env) && index(desc, sec)) { print $1; exit }
    }' <<<"$ASSIGNED_CONTENT"
}

REUSED="false"
if [[ -z "$TF_PEER" && -z "$WG0_PEER" && -z "$WG1_PEER" ]]; then
  rtf="$(find_assigned_peer TF_WG_CONFIG)"
  rwg0="$(find_assigned_peer CLUSTER_WIREGUARD_WG0)"
  rwg1="$(find_assigned_peer CLUSTER_WIREGUARD_WG1)"
  if [[ -n "$rtf" && -n "$rwg0" && -n "$rwg1" ]]; then
    TF_PEER="$rtf"; WG0_PEER="$rwg0"; WG1_PEER="$rwg1"; REUSED="true"
    log "Reusing existing allocation for $ENV_NAME: TF=$TF_PEER WG0=$WG0_PEER WG1=$WG1_PEER"
  fi
fi

# ---- Allocate next free peers for any not explicitly set / reused ----------
# Build ordered list of free peers (exist in config, not taken, not already chosen here)
declare -A CHOSEN=()
[[ -n "$TF_PEER"  ]] && CHOSEN["$TF_PEER"]=1
[[ -n "$WG0_PEER" ]] && CHOSEN["$WG0_PEER"]=1
[[ -n "$WG1_PEER" ]] && CHOSEN["$WG1_PEER"]=1

next_free_peer() {
  local p
  for p in "${EXISTING_PEERS[@]}"; do
    if [[ -z "${TAKEN[$p]:-}" && -z "${CHOSEN[$p]:-}" ]]; then
      echo "$p"; return 0
    fi
  done
  return 1
}

if [[ "$REUSED" != "true" ]]; then
  if [[ -z "$TF_PEER"  ]]; then TF_PEER="$(next_free_peer)"  || die "No free peers left"; CHOSEN["$TF_PEER"]=1;  fi
  if [[ -z "$WG0_PEER" ]]; then WG0_PEER="$(next_free_peer)" || die "No free peers left"; CHOSEN["$WG0_PEER"]=1; fi
  if [[ -z "$WG1_PEER" ]]; then WG1_PEER="$(next_free_peer)" || die "No free peers left"; CHOSEN["$WG1_PEER"]=1; fi
fi

# sanity: all three distinct and exist
for p in "$TF_PEER" "$WG0_PEER" "$WG1_PEER"; do
  printf '%s\n' "${EXISTING_PEERS[@]}" | grep -qx "$p" || die "Peer $p does not exist under $CONFIG_DIR"
done
[[ "$TF_PEER" != "$WG0_PEER" && "$TF_PEER" != "$WG1_PEER" && "$WG0_PEER" != "$WG1_PEER" ]] \
  || die "Peers must be distinct (TF=$TF_PEER WG0=$WG0_PEER WG1=$WG1_PEER)"

log "Allocation -> TF_WG_CONFIG=$TF_PEER | CLUSTER_WIREGUARD_WG0=$WG0_PEER | CLUSTER_WIREGUARD_WG1=$WG1_PEER"

# ---- Fetch + transform each peer conf --------------------------------------
transform_conf() {
  # stdin: raw peer conf -> stdout: DNS removed, AllowedIPs replaced
  sed -e '/^[[:space:]]*DNS[[:space:]]*=/d' \
      -e "s#^[[:space:]]*AllowedIPs[[:space:]]*=.*#AllowedIPs = ${ALLOWED_IPS}#"
}

fetch_and_transform() {
  local peer="$1" raw
  raw="$(ssh_cmd "cat '$CONFIG_DIR/$peer/$peer.conf' 2>/dev/null || sudo cat '$CONFIG_DIR/$peer/$peer.conf'" 2>/dev/null || true)"
  [[ -n "$raw" ]] || die "Could not read $CONFIG_DIR/$peer/$peer.conf"
  grep -q '^[[:space:]]*AllowedIPs' <<<"$raw" || die "$peer.conf has no AllowedIPs line"
  transform_conf <<<"$raw"
}

log "Fetching and transforming peer configs ..."
TF_CONF="$(fetch_and_transform "$TF_PEER")"
WG0_CONF="$(fetch_and_transform "$WG0_PEER")"
WG1_CONF="$(fetch_and_transform "$WG1_PEER")"
log "Transformed: stripped DNS, set AllowedIPs=${ALLOWED_IPS} on all three confs."

if [[ "$DRY_RUN" == "true" ]]; then
  log "DRY RUN - would append to $ASSIGNED_FILE:"
  log "    $TF_PEER  ${LABEL}(TF_WG_CONFIG)"
  log "    $WG0_PEER ${LABEL}(CLUSTER_WIREGUARD_WG0)"
  log "    $WG1_PEER ${LABEL}(CLUSTER_WIREGUARD_WG1)"
  log "DRY RUN - would create env '$ENV_NAME' and set 3 secrets (values not shown)."
  log "DRY RUN - AllowedIPs in each conf: $(grep -h '^AllowedIPs' <<<"$TF_CONF" | head -1)"
  exit 0
fi

# ---- Append to assigned.txt on the jumpserver (skip if reused) -------------
if [[ "$REUSED" != "true" ]]; then
  log "Recording assignment in $ASSIGNED_FILE on jumpserver ..."
  printf '%s %s(TF_WG_CONFIG)\n%s %s(CLUSTER_WIREGUARD_WG0)\n%s %s(CLUSTER_WIREGUARD_WG1)\n' \
    "$TF_PEER" "$LABEL" "$WG0_PEER" "$LABEL" "$WG1_PEER" "$LABEL" \
    | ssh_cmd "cat >> '$ASSIGNED_FILE'"
fi

# ---- Create the GitHub environment + publish the three secrets -------------
log "Ensuring GitHub environment '$ENV_NAME' exists ..."
gh api --method PUT -H "Accept: application/vnd.github+json" \
  "repos/${REPO}/environments/${ENV_NAME}" >/dev/null

log "Publishing environment secrets ..."
printf '%s' "$TF_CONF"  | gh secret set TF_WG_CONFIG          --env "$ENV_NAME" --repo "$REPO" --body -
printf '%s' "$WG0_CONF" | gh secret set CLUSTER_WIREGUARD_WG0 --env "$ENV_NAME" --repo "$REPO" --body -
printf '%s' "$WG1_CONF" | gh secret set CLUSTER_WIREGUARD_WG1 --env "$ENV_NAME" --repo "$REPO" --body -

# ---- Mirror allocation into the repo tracker (for visibility/PR history) ----
if [[ ! -f "$ALLOCATION_FILE" ]]; then
  printf 'env_name\ttf_peer\twg0_peer\twg1_peer\tallocated_at\n' > "$ALLOCATION_FILE"
fi
TMP="$(mktemp)"
grep -vP "^${ENV_NAME}\t" "$ALLOCATION_FILE" > "$TMP" || true
printf '%s\t%s\t%s\t%s\t%s\n' "$ENV_NAME" "$TF_PEER" "$WG0_PEER" "$WG1_PEER" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$TMP"
mv "$TMP" "$ALLOCATION_FILE"

log "Done. Environment '$ENV_NAME' onboarded with peers TF=$TF_PEER WG0=$WG0_PEER WG1=$WG1_PEER."
log "Server tracker: $ASSIGNED_FILE | repo tracker: $ALLOCATION_FILE (commit it)."
