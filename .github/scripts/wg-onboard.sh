#!/usr/bin/env bash
#
# wg-onboard.sh - Self-service WireGuard onboarding for a new environment.
#
# Automates the manual jumpserver process:
#   1. SSH into the WireGuard VM.
#   2. cd into the WireGuard env dir (default /home/ubuntu/wireguard_env_2026).
#   3. Allocate the next 3 free peers in the pool (peer1..peerN, filling gaps
#      like peer66 before peer101). assigned.txt is the source of truth; if a
#      peer directory or assigned.txt line is missing, create it on the VM first.
#      Append assignments for the new environment - one peer per secret.
#      Supports two assigned.txt layouts:
#         peerN: username          (legacy colon format on /home/ubuntu)
#         peerN env(SECRET_NAME)   (MOSIP per-secret format)
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
MAX_PEERS=""
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
  --max-peers <n>       Peer pool size peer1..peerN (default: max(100, highest seen))
  --dry-run             Resolve + transform + print actions without writing anything
  -h, --help            Show this help

Requires: gh (authenticated with a token that can write environment secrets), ssh.
EOF
}

log()  { echo "[wg-onboard] $*" >&2; }
err()  { echo "[wg-onboard][ERROR] $*" >&2; }
die()  { err "$*"; exit 1; }

require_arg() {
  local flag="$1"
  [[ $# -ge 2 && -n "${2:-}" && "$2" != --* ]] || die "$flag requires a value"
}

urlencode() {
  local input="$1" output="" i c
  local LC_ALL=C
  for ((i = 0; i < ${#input}; i++)); do
    c="${input:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) output+="$c" ;;
      *) printf -v output '%s%%%02X' "$output" "'$c" ;;
    esac
  done
  printf '%s' "$output"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)         require_arg --env "$2";         ENV_NAME="$2"; shift 2 ;;
    --host)        require_arg --host "$2";        JUMPSERVER_HOST="$2"; shift 2 ;;
    --ssh-key)     require_arg --ssh-key "$2";     SSH_KEY="$2"; shift 2 ;;
    --repo)        require_arg --repo "$2";        REPO="$2"; shift 2 ;;
    --ticket)      require_arg --ticket "$2";      TICKET="$2"; shift 2 ;;
    --wg-dir)      require_arg --wg-dir "$2";      WG_DIR="$2"; shift 2 ;;
    --allowed-ips) require_arg --allowed-ips "$2"; ALLOWED_IPS="$2"; shift 2 ;;
    --tf-peer)     require_arg --tf-peer "$2";     TF_PEER="$2"; shift 2 ;;
    --wg0-peer)    require_arg --wg0-peer "$2";    WG0_PEER="$2"; shift 2 ;;
    --wg1-peer)    require_arg --wg1-peer "$2";    WG1_PEER="$2"; shift 2 ;;
    --max-peers)   require_arg --max-peers "$2";   MAX_PEERS="$2"; shift 2 ;;
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

if [[ -n "${SSH_KNOWN_HOSTS:-}" ]]; then
  [[ -f "$SSH_KNOWN_HOSTS" ]] || die "SSH_KNOWN_HOSTS file not found: $SSH_KNOWN_HOSTS"
else
  SSH_KNOWN_HOSTS="$(mktemp /tmp/wg_onboard_known_hosts.XXXXXX)"
  trap 'rm -f "$SSH_KNOWN_HOSTS"' EXIT
fi

ssh_cmd() {
  ssh -i "$SSH_KEY" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" \
    -o ConnectTimeout=15 \
    "${SSH_USER}@${JUMPSERVER_HOST}" "$@"
}

# ---- Read current state from the jumpserver --------------------------------
log "Reading assigned.txt and peer inventory from jumpserver ${JUMPSERVER_HOST} ..."
ASSIGNED_CONTENT="$(ssh_cmd "cat '$ASSIGNED_FILE' 2>/dev/null" || true)"
ASSIGNED_CONTENT="${ASSIGNED_CONTENT//$'\r'/}"
PEER_LISTING="$(ssh_cmd "ls '$CONFIG_DIR'" 2>/dev/null || true)"
[[ -n "$PEER_LISTING" ]] || die "Could not list $CONFIG_DIR on jumpserver (check --wg-dir / connectivity)"

if [[ -z "$ASSIGNED_CONTENT" ]]; then
  log "WARNING: $ASSIGNED_FILE is empty or unreadable over SSH — every peer will look FREE"
else
  assigned_lines="$(printf '%s\n' "$ASSIGNED_CONTENT" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
  log "Loaded $ASSIGNED_FILE ($assigned_lines non-empty lines)"
fi

# Peers that physically exist as client configs
mapfile -t EXISTING_PEERS < <(printf '%s\n' "$PEER_LISTING" | grep -E '^peer[0-9]+$' | sort -t r -k2 -n)

peer_number() {
  local peer="$1"
  [[ "$peer" =~ ^peer([0-9]+)$ ]] || return 1
  echo "${BASH_REMATCH[1]}"
}

# Normalize "peer1" or "peer1:" from assigned.txt first field.
normalize_peer_token() {
  local token="${1//$'\r'/}"
  token="${token%%:*}"
  echo "$token"
}

# Parse one assigned.txt line -> PARSED_PEER / PARSED_LABEL (label empty = free).
parse_assigned_line() {
  local line="${1//$'\r'/}"
  local peer rest
  PARSED_PEER=""
  PARSED_LABEL=""
  [[ -z "${line//[[:space:]]/}" ]] && return 1
  peer="$(normalize_peer_token "$(awk '{print $1}' <<<"$line")")"
  [[ "$peer" =~ ^peer[0-9]+$ ]] || return 1
  if [[ "$line" =~ ^peer[0-9]+[[:space:]]*:[[:space:]]*(.*)$ ]]; then
    rest="${BASH_REMATCH[1]}"
  else
    rest="$(awk '{$1=""; sub(/^ +/,""); print}' <<<"$line")"
  fi
  rest="${rest//$'\r'/}"
  rest="$(awk '{$1=$1; print}' <<<"$rest")"
  PARSED_PEER="$peer"
  PARSED_LABEL="$rest"
  return 0
}

# Blank label or explicit ": available" means the peer is free.
peer_label_is_taken() {
  local label="${1//[[:space:]]/}"
  [[ -n "$label" && "${label,,}" != "available" ]]
}

assigned_line_exists() {
  local peer="$1"
  grep -qE "^${peer}([[:space:]]|:)" <<<"$ASSIGNED_CONTENT"
}

highest_peer_number() {
  local max=0 n peer
  for peer in "${EXISTING_PEERS[@]}"; do
    n="$(peer_number "$peer" || true)"
    [[ -n "$n" && "$n" -gt "$max" ]] && max="$n"
  done
  while IFS= read -r line; do
    parse_assigned_line "$line" || continue
    n="$(peer_number "$PARSED_PEER" || true)"
    [[ -n "$n" && "$n" -gt "$max" ]] && max="$n"
  done <<<"$ASSIGNED_CONTENT"
  echo "$max"
}

if [[ -z "$MAX_PEERS" ]]; then
  detected_max="$(highest_peer_number)"
  MAX_PEERS=$(( detected_max > 100 ? detected_max : 100 ))
else
  [[ "$MAX_PEERS" =~ ^[0-9]+$ && "$MAX_PEERS" -gt 0 ]] || die "--max-peers must be a positive integer"
fi
log "Peer pool: peer1..peer${MAX_PEERS} (gap-fill order, create missing peers on demand)"

CAN_CREATE_PEERS="false"
if [[ ${#EXISTING_PEERS[@]} -gt 0 ]] \
  || ssh_cmd "test -f '$CONFIG_DIR/templates/peer.conf' || test -f '$CONFIG_DIR/peer1/peer1.conf'" 2>/dev/null; then
  CAN_CREATE_PEERS="true"
else
  die "No peer directories or templates under $CONFIG_DIR (cannot create missing peers)"
fi

# Detect assigned.txt layout (colon vs per-secret MOSIP format).
ASSIGNED_FORMAT="mosip"
if grep -qE '^peer[0-9]+[[:space:]]*:' <<<"$ASSIGNED_CONTENT"; then
  ASSIGNED_FORMAT="colon"
  log "Detected assigned.txt colon format (peerN: username)"
fi

# Peers already taken: any peerN line with a non-empty label/username.
declare -A TAKEN=()
while IFS= read -r line; do
  parse_assigned_line "$line" || continue
  peer_label_is_taken "$PARSED_LABEL" && TAKEN["$PARSED_PEER"]=1
done <<<"$ASSIGNED_CONTENT"

if [[ ${#TAKEN[@]} -gt 0 ]]; then
  taken_sample="$(printf '%s\n' "${!TAKEN[@]}" | sort -t r -k2 -n | head -5 | paste -sd, -)"
  log "Marked ${#TAKEN[@]} peers as taken in $ASSIGNED_FILE (e.g. ${taken_sample})"
else
  log "No taken peers parsed from $ASSIGNED_FILE — will start from peer1 unless gaps apply"
fi

peer_config_exists() {
  local peer="$1"
  ssh_cmd "test -f '$CONFIG_DIR/$peer/$peer.conf'" 2>/dev/null
}

ensure_assigned_entry() {
  local peer="$1"
  assigned_line_exists "$peer" && return 0
  if [[ "$DRY_RUN" == "true" ]]; then
    if [[ "$ASSIGNED_FORMAT" == "colon" ]]; then
      log "DRY RUN - would append free slot to $ASSIGNED_FILE: ${peer}:"
    else
      log "DRY RUN - would append free slot to $ASSIGNED_FILE: ${peer}"
    fi
    return 0
  fi
  log "Adding free slot ${peer} to $ASSIGNED_FILE ..."
  if [[ "$ASSIGNED_FORMAT" == "colon" ]]; then
    printf '%s:\n' "$peer" | ssh_cmd "cat >> '$ASSIGNED_FILE'"
    ASSIGNED_CONTENT+=$'\n'"${peer}:"
  else
    printf '%s \n' "$peer" | ssh_cmd "cat >> '$ASSIGNED_FILE'"
    ASSIGNED_CONTENT+=$'\n'"${peer} "
  fi
}

ensure_peer_exists() {
  local peer="$1"
  peer_config_exists "$peer" && return 0
  [[ "$CAN_CREATE_PEERS" == "true" ]] || die "Peer $peer is missing under $CONFIG_DIR and cannot be created"
  local peer_num
  peer_num="$(peer_number "$peer")" || die "Invalid peer id: $peer"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN - would create missing peer $peer on jumpserver"
    ensure_assigned_entry "$peer"
    return 0
  fi

  log "Creating missing peer $peer on jumpserver ..."
  ssh_cmd "bash -s" "$peer_num" "$CONFIG_DIR" <<'REMOTE_CREATE_PEER'
set -euo pipefail
PEER_NUM="$1"
CONFIG_DIR="$2"
PEER_ID="peer${PEER_NUM}"

if [[ -f "$CONFIG_DIR/$PEER_ID/$PEER_ID.conf" ]]; then
  exit 0
fi

mapfile -t REF_DIRS < <(ls -d "$CONFIG_DIR"/peer[0-9]* 2>/dev/null | sort -t r -k2 -n)
[[ ${#REF_DIRS[@]} -gt 0 ]] || { echo "No reference peer under $CONFIG_DIR" >&2; exit 1; }
REF_DIR="${REF_DIRS[0]}"
REF_ID="$(basename "$REF_DIR")"
REF_CONF="$REF_DIR/$REF_ID.conf"
[[ -f "$REF_CONF" ]] || { echo "Missing reference conf: $REF_CONF" >&2; exit 1; }

INTERFACE="$(grep -m1 '^Address' "$REF_CONF" | awk '{print $NF}' | awk -F. '{print $1"."$2"."$3}')"
ENDPOINT="$(grep -m1 '^Endpoint' "$REF_CONF" | awk '{print $NF}')"
SERVER_PUBKEY="$(grep -m1 '^PublicKey' "$REF_CONF" | awk '{print $NF}')"
PEERDNS="$(grep -m1 '^DNS' "$REF_CONF" | awk '{print $NF}')"
[[ -n "$INTERFACE" && -n "$ENDPOINT" && -n "$SERVER_PUBKEY" ]] \
  || { echo "Could not read reference WireGuard settings from $REF_CONF" >&2; exit 1; }
[[ -n "$PEERDNS" ]] || PEERDNS="${INTERFACE}.1"

C="$(docker ps --format '{{.Names}}' | grep -iE 'wireguard|wg' | head -1 || true)"
[[ -n "$C" ]] || { echo "WireGuard docker container not found" >&2; exit 1; }

mkdir -p "$CONFIG_DIR/$PEER_ID"
umask 077
docker exec "$C" wg genkey | tee "$CONFIG_DIR/$PEER_ID/privatekey-$PEER_ID" \
  | docker exec -i "$C" wg pubkey > "$CONFIG_DIR/$PEER_ID/publickey-$PEER_ID"
docker exec "$C" wg genpsk > "$CONFIG_DIR/$PEER_ID/presharedkey-$PEER_ID"

CLIENT_IP=""
for idx in $(seq 2 254); do
  PROPOSED="${INTERFACE}.${idx}"
  if ! grep -qR "${PROPOSED}" "$CONFIG_DIR"/peer*/*.conf 2>/dev/null; then
    CLIENT_IP="$PROPOSED"
    break
  fi
done
[[ -n "$CLIENT_IP" ]] || { echo "No free client IP in ${INTERFACE}.0/24" >&2; exit 1; }

PRIV="$(cat "$CONFIG_DIR/$PEER_ID/privatekey-$PEER_ID")"
PSK="$(cat "$CONFIG_DIR/$PEER_ID/presharedkey-$PEER_ID")"
PUB="$(cat "$CONFIG_DIR/$PEER_ID/publickey-$PEER_ID")"

cat > "$CONFIG_DIR/$PEER_ID/$PEER_ID.conf" <<EOF
[Interface]
Address = ${CLIENT_IP}
PrivateKey = ${PRIV}
ListenPort = 51820
DNS = ${PEERDNS}

[Peer]
PublicKey = ${SERVER_PUBKEY}
PresharedKey = ${PSK}
Endpoint = ${ENDPOINT}
AllowedIPs = 0.0.0.0/0, ::/0
EOF

if [[ -f "$CONFIG_DIR/wg_confs/wg0.conf" ]]; then
  WG_CONF="$CONFIG_DIR/wg_confs/wg0.conf"
else
  WG_CONF="$CONFIG_DIR/wg0.conf"
fi

cat >> "$WG_CONF" <<EOF

[Peer]
# ${PEER_ID}
PublicKey = ${PUB}
PresharedKey = ${PSK}
AllowedIPs = ${CLIENT_IP}/32

EOF

docker exec "$C" wg set wg0 peer "$PUB" preshared-key "$PSK" allowed-ips "${CLIENT_IP}/32" \
  || docker restart "$C" >/dev/null
REMOTE_CREATE_PEER

  ensure_assigned_entry "$peer"
}

record_peer_assignment() {
  local peer="$1"
  local assignment="$2"
  ssh_cmd "bash -s" "$peer" "$assignment" "$ASSIGNED_FILE" "$ASSIGNED_FORMAT" <<'REMOTE_RECORD_ASSIGNMENT'
set -euo pipefail
peer="$1"
assignment="$2"
file="$3"
format="$4"
if [[ "$format" == "colon" ]]; then
  line="${peer}: ${assignment}"
  if grep -qE "^${peer}:" "$file"; then
    sed -i "s|^${peer}:.*|${line}|" "$file"
  elif grep -qE "^${peer}([[:space:]]|$)" "$file"; then
    sed -i "s|^${peer}.*|${line}|" "$file"
  else
    printf '%s\n' "$line" >> "$file"
  fi
else
  line="${peer} ${assignment}"
  if grep -qE "^${peer}([[:space:]]|$)" "$file"; then
    sed -i "s|^${peer}.*|${line}|" "$file"
  else
    printf '%s\n' "$line" >> "$file"
  fi
fi
REMOTE_RECORD_ASSIGNMENT
}

# ---- Reuse existing allocation for this env, if present (idempotent) -------
find_assigned_peer() {
  local secret="$1"
  awk -v env="$ENV_NAME" -v secret="$secret" '
    $1 ~ /^peer[0-9]+:?$/ {
      peer=$1
      sub(/:$/, "", peer)
      desc=$0
      sub(/^[[:space:]]*peer[0-9]+[[:space:]]*:?[[:space:]]*/, "", desc)
      suffix="(" secret ")"
      if (length(desc) < length(suffix)) next
      if (substr(desc, length(desc) - length(suffix) + 1) != suffix) next
      label=substr(desc, 1, length(desc) - length(suffix))
      if (label == env || index(label, env "(") == 1) { print peer; exit }
    }' <<<"$ASSIGNED_CONTENT"
}

find_colon_env_peers() {
  local line
  while IFS= read -r line; do
    parse_assigned_line "$line" || continue
    [[ "$PARSED_LABEL" == "$ENV_NAME" ]] && echo "$PARSED_PEER"
  done <<<"$ASSIGNED_CONTENT"
}

REUSED="false"
if [[ -z "$TF_PEER" && -z "$WG0_PEER" && -z "$WG1_PEER" ]]; then
  if [[ "$ASSIGNED_FORMAT" == "colon" ]]; then
    mapfile -t COLON_REUSED < <(find_colon_env_peers | sort -t r -k2 -n)
    if [[ ${#COLON_REUSED[@]} -ge 3 ]]; then
      TF_PEER="${COLON_REUSED[0]}"; WG0_PEER="${COLON_REUSED[1]}"; WG1_PEER="${COLON_REUSED[2]}"
      REUSED="true"
      log "Reusing existing colon-format allocation for $ENV_NAME: TF=$TF_PEER WG0=$WG0_PEER WG1=$WG1_PEER"
    fi
  else
    rtf="$(find_assigned_peer TF_WG_CONFIG)"
    rwg0="$(find_assigned_peer CLUSTER_WIREGUARD_WG0)"
    rwg1="$(find_assigned_peer CLUSTER_WIREGUARD_WG1)"
    if [[ -n "$rtf" && -n "$rwg0" && -n "$rwg1" ]]; then
      TF_PEER="$rtf"; WG0_PEER="$rwg0"; WG1_PEER="$rwg1"; REUSED="true"
      log "Reusing existing allocation for $ENV_NAME: TF=$TF_PEER WG0=$WG0_PEER WG1=$WG1_PEER"
    fi
  fi
fi

# ---- Allocate next free peers for any not explicitly set / reused ----------
# Walk peer1..peerMAX in numeric order so gaps (e.g. peer66) are reused first.
declare -A CHOSEN=()
[[ -n "$TF_PEER"  ]] && CHOSEN["$TF_PEER"]=1
[[ -n "$WG0_PEER" ]] && CHOSEN["$WG0_PEER"]=1
[[ -n "$WG1_PEER" ]] && CHOSEN["$WG1_PEER"]=1

next_free_peer() {
  local n peer
  for n in $(seq 1 "$MAX_PEERS"); do
    peer="peer${n}"
    if [[ -z "${TAKEN[$peer]:-}" && -z "${CHOSEN[$peer]:-}" ]]; then
      ensure_peer_exists "$peer"
      echo "$peer"
      return 0
    fi
  done
  return 1
}

if [[ "$REUSED" != "true" ]]; then
  if [[ -z "$TF_PEER"  ]]; then TF_PEER="$(next_free_peer)"  || die "No free peers left in peer1..peer${MAX_PEERS}"; CHOSEN["$TF_PEER"]=1;  fi
  if [[ -z "$WG0_PEER" ]]; then WG0_PEER="$(next_free_peer)" || die "No free peers left in peer1..peer${MAX_PEERS}"; CHOSEN["$WG0_PEER"]=1; fi
  if [[ -z "$WG1_PEER" ]]; then WG1_PEER="$(next_free_peer)" || die "No free peers left in peer1..peer${MAX_PEERS}"; CHOSEN["$WG1_PEER"]=1; fi
fi

for p in "$TF_PEER" "$WG0_PEER" "$WG1_PEER"; do
  if [[ "$REUSED" != "true" && -n "${TAKEN[$p]:-}" ]]; then
    die "Refusing to allocate $p — already assigned in $ASSIGNED_FILE (script may have failed to read labels; check file format/permissions)"
  fi
done

# Ensure explicit/reused peers exist before reading their confs
for p in "$TF_PEER" "$WG0_PEER" "$WG1_PEER"; do
  ensure_peer_exists "$p"
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
  if [[ "$DRY_RUN" == "true" ]] && ! peer_config_exists "$peer"; then
    echo "[DRY RUN] peer config for $peer not present yet"
    return 0
  fi
  raw="$(ssh_cmd "cat '$CONFIG_DIR/$peer/$peer.conf' 2>/dev/null || sudo cat '$CONFIG_DIR/$peer/$peer.conf'" 2>/dev/null || true)"
  [[ -n "$raw" ]] || die "Could not read $CONFIG_DIR/$peer/$peer.conf"
  grep -q '^[[:space:]]*AllowedIPs' <<<"$raw" || die "$peer.conf has no AllowedIPs line"
  transform_conf <<<"$raw"
}

log "Fetching and transforming peer configs ..."
TF_CONF="$(fetch_and_transform "$TF_PEER")"
WG0_CONF="$(fetch_and_transform "$WG0_PEER")"
WG1_CONF="$(fetch_and_transform "$WG1_PEER")"
if [[ "$DRY_RUN" != "true" ]]; then
  log "Transformed: stripped DNS, set AllowedIPs=${ALLOWED_IPS} on all three confs."
fi

if [[ "$DRY_RUN" == "true" ]]; then
  log "DRY RUN - would update $ASSIGNED_FILE:"
  if [[ "$ASSIGNED_FORMAT" == "colon" ]]; then
    log "    $TF_PEER: $ENV_NAME"
    log "    $WG0_PEER: $ENV_NAME"
    log "    $WG1_PEER: $ENV_NAME"
  else
    log "    $TF_PEER  ${LABEL}(TF_WG_CONFIG)"
    log "    $WG0_PEER ${LABEL}(CLUSTER_WIREGUARD_WG0)"
    log "    $WG1_PEER ${LABEL}(CLUSTER_WIREGUARD_WG1)"
  fi
  log "DRY RUN - would create env '$ENV_NAME' and set 3 secrets (values not shown)."
  if grep -q '^AllowedIPs' <<<"$TF_CONF" 2>/dev/null; then
    log "DRY RUN - AllowedIPs in each conf: $(grep -h '^AllowedIPs' <<<"$TF_CONF" | head -1)"
  fi
  exit 0
fi

# ---- Update assigned.txt on the jumpserver (skip if reused) ------------------
if [[ "$REUSED" != "true" ]]; then
  log "Recording assignment in $ASSIGNED_FILE on jumpserver ..."
  if [[ "$ASSIGNED_FORMAT" == "colon" ]]; then
    record_peer_assignment "$TF_PEER" "$ENV_NAME"
    record_peer_assignment "$WG0_PEER" "$ENV_NAME"
    record_peer_assignment "$WG1_PEER" "$ENV_NAME"
  else
    record_peer_assignment "$TF_PEER" "${LABEL}(TF_WG_CONFIG)"
    record_peer_assignment "$WG0_PEER" "${LABEL}(CLUSTER_WIREGUARD_WG0)"
    record_peer_assignment "$WG1_PEER" "${LABEL}(CLUSTER_WIREGUARD_WG1)"
  fi
fi

# ---- Create the GitHub environment + publish the three secrets -------------
log "Ensuring GitHub environment '$ENV_NAME' exists ..."
ENV_NAME_ENC="$(urlencode "$ENV_NAME")"
gh api --method PUT -H "Accept: application/vnd.github+json" \
  "repos/${REPO}/environments/${ENV_NAME_ENC}" >/dev/null

log "Publishing environment secrets ..."
printf '%s' "$TF_CONF"  | gh secret set TF_WG_CONFIG          --env "$ENV_NAME" --repo "$REPO" --body -
printf '%s' "$WG0_CONF" | gh secret set CLUSTER_WIREGUARD_WG0 --env "$ENV_NAME" --repo "$REPO" --body -
printf '%s' "$WG1_CONF" | gh secret set CLUSTER_WIREGUARD_WG1 --env "$ENV_NAME" --repo "$REPO" --body -

# ---- Mirror allocation into the repo tracker (for visibility/PR history) ----
if [[ ! -f "$ALLOCATION_FILE" ]]; then
  printf 'env_name\ttf_peer\twg0_peer\twg1_peer\tallocated_at\n' > "$ALLOCATION_FILE"
fi
TMP="$(mktemp)"
awk -F '\t' -v env="$ENV_NAME" 'NR == 1 || $1 != env' "$ALLOCATION_FILE" > "$TMP"
printf '%s\t%s\t%s\t%s\t%s\n' "$ENV_NAME" "$TF_PEER" "$WG0_PEER" "$WG1_PEER" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$TMP"
mv "$TMP" "$ALLOCATION_FILE"

log "Done. Environment '$ENV_NAME' onboarded with peers TF=$TF_PEER WG0=$WG0_PEER WG1=$WG1_PEER."
log "Server tracker: $ASSIGNED_FILE | repo tracker: $ALLOCATION_FILE (commit it)."
