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

remote_quote() {
  local s=${1//\'/\'\\\'\'}
  printf "'%s'" "$s"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)         require_arg --env "${2-}";         ENV_NAME="$2"; shift 2 ;;
    --host)        require_arg --host "${2-}";        JUMPSERVER_HOST="$2"; shift 2 ;;
    --ssh-key)     require_arg --ssh-key "${2-}";     SSH_KEY="$2"; shift 2 ;;
    --repo)        require_arg --repo "${2-}";        REPO="$2"; shift 2 ;;
    --ticket)      require_arg --ticket "${2-}";      TICKET="$2"; shift 2 ;;
    --wg-dir)      require_arg --wg-dir "${2-}";      WG_DIR="$2"; shift 2 ;;
    --allowed-ips) require_arg --allowed-ips "${2-}"; ALLOWED_IPS="$2"; shift 2 ;;
    --tf-peer)     require_arg --tf-peer "${2-}";     TF_PEER="$2"; shift 2 ;;
    --wg0-peer)    require_arg --wg0-peer "${2-}";    WG0_PEER="$2"; shift 2 ;;
    --wg1-peer)    require_arg --wg1-peer "${2-}";    WG1_PEER="$2"; shift 2 ;;
    --max-peers)   require_arg --max-peers "${2-}";   MAX_PEERS="$2"; shift 2 ;;
    --dry-run)     DRY_RUN="true"; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "Unknown argument: $1 (use --help)" ;;
  esac
done

[[ -n "$ENV_NAME" ]]        || die "--env is required"
[[ -n "$JUMPSERVER_HOST" ]] || die "--host is required"
[[ -n "$SSH_KEY" ]]         || die "--ssh-key is required"
[[ -f "$SSH_KEY" ]]         || die "ssh key not found: $SSH_KEY"
[[ "$ALLOWED_IPS" =~ ^[0-9]+(\.[0-9]+){3}/[0-9]+$ ]] \
  || die "--allowed-ips must be an IPv4 CIDR (e.g. 172.31.0.0/16), got: $ALLOWED_IPS"
command -v gh  >/dev/null 2>&1 || die "gh CLI is required"
command -v ssh >/dev/null 2>&1 || die "ssh is required"

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  [[ -n "$REPO" ]] || die "Could not infer repo; pass --repo <owner/repo>"
fi

CONFIG_DIR="$WG_DIR/config"
ASSIGNED_FILE="$WG_DIR/assigned.txt"
ASSIGN_LOCK_FILE="/tmp/wg-onboard-$(printf '%s' "$ASSIGNED_FILE" | cksum | awk '{print $1}').lock"
LABEL="$ENV_NAME"
[[ -n "$TICKET" ]] && LABEL="${ENV_NAME}(${TICKET})"

log "Target repo: $REPO"
log "Target environment: $ENV_NAME (label: $LABEL)"
log "WireGuard dir: $WG_DIR | AllowedIPs: $ALLOWED_IPS"

SSH_KNOWN_HOSTS_IS_TEMP="false"
TRACKER_TMP=""
wg_onboard_exit_cleanup() {
  [[ -n "$TRACKER_TMP" && -f "$TRACKER_TMP" ]] && rm -f "$TRACKER_TMP"
  [[ "$SSH_KNOWN_HOSTS_IS_TEMP" == "true" ]] && rm -f "$SSH_KNOWN_HOSTS"
}
trap wg_onboard_exit_cleanup EXIT

if [[ -n "${SSH_KNOWN_HOSTS:-}" ]]; then
  [[ -f "$SSH_KNOWN_HOSTS" ]] || die "SSH_KNOWN_HOSTS file not found: $SSH_KNOWN_HOSTS"
else
  SSH_KNOWN_HOSTS="$(mktemp /tmp/wg_onboard_known_hosts.XXXXXX)"
  SSH_KNOWN_HOSTS_IS_TEMP="true"
fi

ssh_cmd() {
  ssh -i "$SSH_KEY" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" \
    -o ConnectTimeout=15 \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    "${SSH_USER}@${JUMPSERVER_HOST}" "$@"
}

# Run a remote bash script from stdin with positional args ($1, $2, ...).
# Each "$@" element is sent as a separate SSH argv word; the remote shell does
# not re-parse them, so values with spaces stay intact in $1..$n. Do not wrap
# these args in remote_quote() — that is only for inline remote command strings
# (ls, test, cat) where a single shell line is executed.
ssh_bash_stdin() {
  ssh_cmd bash -s -- "$@"
}

# ---- Preflight: jumpserver connectivity + peer pool sizing -------------------
log "Checking jumpserver connectivity and peer inventory on ${JUMPSERVER_HOST} ..."
PEER_LISTING="$(ssh_cmd "ls -1 $(remote_quote "$CONFIG_DIR")" 2>/dev/null || true)"
[[ -n "$PEER_LISTING" ]] || die "Could not list $CONFIG_DIR on jumpserver (check --wg-dir / connectivity)"

mapfile -t EXISTING_PEERS < <(printf '%s\n' "$PEER_LISTING" | grep -E '^peer[0-9]+$' | sort -t r -k2 -n)

peer_number() {
  local peer="$1"
  [[ "$peer" =~ ^peer([0-9]+)$ ]] || return 1
  echo "${BASH_REMATCH[1]}"
}

highest_config_peer() {
  local max=0 n peer
  for peer in "${EXISTING_PEERS[@]}"; do
    n="$(peer_number "$peer" || true)"
    [[ -n "$n" && "$n" -gt "$max" ]] && max="$n"
  done
  echo "$max"
}

if [[ -z "$MAX_PEERS" ]]; then
  max="$(highest_config_peer)"
  MAX_PEERS=$(( max > 100 ? max : 100 ))
else
  [[ "$MAX_PEERS" =~ ^[0-9]+$ && "$MAX_PEERS" -gt 0 ]] || die "--max-peers must be a positive integer"
  detected_max="$(highest_config_peer)"
  [[ "$detected_max" -eq 0 || "$MAX_PEERS" -ge "$detected_max" ]] \
    || die "--max-peers ($MAX_PEERS) is less than highest peer on jumpserver (peer${detected_max})"
fi
log "Peer pool: peer1..peer${MAX_PEERS} (gap-fill order, create missing peers on demand)"

CAN_CREATE_PEERS="false"
if [[ ${#EXISTING_PEERS[@]} -gt 0 ]] \
  || ssh_cmd "test -f $(remote_quote "$CONFIG_DIR/templates/peer.conf") || test -f $(remote_quote "$CONFIG_DIR/peer1/peer1.conf")" 2>/dev/null; then
  CAN_CREATE_PEERS="true"
else
  die "No peer directories or templates under $CONFIG_DIR (cannot create missing peers)"
fi

peer_config_exists() {
  local peer="$1"
  local conf="$CONFIG_DIR/$peer/$peer.conf"
  ssh_cmd "test -f $(remote_quote "$conf")" 2>/dev/null
}

# ---- Flock-guarded peer allocation/record on the jumpserver ----------------
# Selection and assigned.txt recording happen under one lock to prevent races.
atomic_allocate_peers() {
  # SSH omits empty argv entries; placeholders keep arg positions stable for bash -s.
  local force_tf="${TF_PEER:-__none__}"
  local force_wg0="${WG0_PEER:-__none__}"
  local force_wg1="${WG1_PEER:-__none__}"
  ssh_bash_stdin \
    "$ASSIGNED_FILE" \
    "$ASSIGN_LOCK_FILE" \
    "$CONFIG_DIR" \
    "$ENV_NAME" \
    "$LABEL" \
    "$MAX_PEERS" \
    "$force_tf" \
    "$force_wg0" \
    "$force_wg1" \
    "$DRY_RUN" \
    "$CAN_CREATE_PEERS" \
    <<'REMOTE_ATOMIC_ALLOCATE'
set -euo pipefail

ASSIGNED_FILE="$1"
LOCK_FILE="$2"
CONFIG_DIR="$3"
ENV_NAME="$4"
LABEL="$5"
MAX_PEERS="$6"
FORCE_TF="${7:-}"
FORCE_WG0="${8:-}"
FORCE_WG1="${9:-}"
[[ "$FORCE_TF" == "__none__" ]] && FORCE_TF=""
[[ "$FORCE_WG0" == "__none__" ]] && FORCE_WG0=""
[[ "$FORCE_WG1" == "__none__" ]] && FORCE_WG1=""
DRY_RUN="${10:-false}"
CAN_CREATE="${11:-false}"

PARSED_PEER=""
PARSED_LABEL=""

normalize_peer_token() {
  local token="${1//$'\r'/}"
  token="${token%%:*}"
  printf '%s' "$token"
}

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

peer_label_is_taken() {
  local label="${1//[[:space:]]/}"
  [[ -n "$label" && "${label,,}" != "available" ]]
}

assigned_file_writable() {
  local file="$1" dir
  dir="$(dirname "$file")"
  if [[ -e "$file" ]]; then
    if [[ ! -w "$file" ]]; then
      echo "ERROR: $file is not writable by $(whoami) ($(stat -c '%U:%G %a' "$file" 2>/dev/null || echo 'stat failed'))" >&2
      echo "Fix on jumpserver: sudo chown ubuntu:ubuntu '$file' && sudo chmod u+w '$file'" >&2
      return 1
    fi
  elif [[ ! -w "$dir" ]]; then
    echo "ERROR: cannot create $file (directory $dir not writable by $(whoami))" >&2
    return 1
  fi
}

atomic_replace_file() {
  local src="$1" dest="$2"
  if ! mv -f "$src" "$dest"; then
    rm -f "$src"
    echo "ERROR: cannot update $dest (check ownership/permissions)" >&2
    return 1
  fi
}

record_assignment() {
  local peer="$1" assignment="$2" format="$3" file="$4"
  local safe_assignment="${assignment//\\/\\\\}"
  safe_assignment="${safe_assignment//&/\\&}"
  local dir tmp
  dir="$(dirname "$file")"
  tmp="$(mktemp "$dir/.assigned.XXXXXX")" || {
    echo "ERROR: cannot create temp file in $dir" >&2
    return 1
  }
  if [[ "$format" == "colon" ]]; then
    awk -v peer="$peer" -v assignment="$assignment" '
      BEGIN {
        replaced=0
        new_line=peer ": " assignment
      }
      $1 ~ ("^" peer ":$") || $1 ~ ("^" peer "$") {
        if (!replaced) {
          print new_line
          replaced=1
        }
        next
      }
      { print }
      END {
        if (!replaced) {
          print new_line
        }
      }
    ' "$file" > "$tmp"
  else
    awk -v peer="$peer" -v assignment="$assignment" '
      BEGIN {
        replaced=0
        new_line=peer " " assignment
      }
      $1 ~ ("^" peer ":?$") {
        if (!replaced) {
          print new_line
          replaced=1
        }
        next
      }
      { print }
      END {
        if (!replaced) {
          print new_line
        }
      }
    ' "$file" > "$tmp"
  fi
  atomic_replace_file "$tmp" "$file"
}

ensure_peer_conf() {
  local peer_num="$1"
  local PEER_ID="peer${peer_num}"
  [[ -f "$CONFIG_DIR/$PEER_ID/$PEER_ID.conf" ]] && return 0
  [[ "$CAN_CREATE" == "true" ]] || { echo "ERROR: peer $PEER_ID missing and cannot be created" >&2; return 1; }
  [[ "$DRY_RUN" == "true" ]] && return 0

  mapfile -t REF_DIRS < <(ls -d "$CONFIG_DIR"/peer[0-9]* 2>/dev/null | sort -t r -k2 -n)
  [[ ${#REF_DIRS[@]} -gt 0 ]] || return 1
  local REF_CONF="${REF_DIRS[0]}/$(basename "${REF_DIRS[0]}").conf"
  [[ -f "$REF_CONF" ]] || return 1

  local INTERFACE ENDPOINT SERVER_PUBKEY PEERDNS C CLIENT_IP PRIV PSK PUB WG_CONF
  INTERFACE="$(grep -m1 '^Address' "$REF_CONF" | awk '{print $NF}' | awk -F. '{print $1"."$2"."$3}')"
  ENDPOINT="$(grep -m1 '^Endpoint' "$REF_CONF" | awk '{print $NF}')"
  SERVER_PUBKEY="$(grep -m1 '^PublicKey' "$REF_CONF" | awk '{print $NF}')"
  PEERDNS="$(grep -m1 '^DNS' "$REF_CONF" | awk '{print $NF}')"
  [[ -n "$INTERFACE" && -n "$ENDPOINT" && -n "$SERVER_PUBKEY" ]] || return 1
  [[ -n "$PEERDNS" ]] || PEERDNS="${INTERFACE}.1"

  C="$(docker ps --format '{{.Names}}' | grep -iE 'wireguard|wg' | head -1)"
  [[ -n "$C" ]] || { echo "ERROR: WireGuard docker container not running" >&2; return 1; }

  mkdir -p "$CONFIG_DIR/$PEER_ID"
  umask 077
  docker exec "$C" wg genkey | tee "$CONFIG_DIR/$PEER_ID/privatekey-$PEER_ID" \
    | docker exec -i "$C" wg pubkey > "$CONFIG_DIR/$PEER_ID/publickey-$PEER_ID"
  docker exec "$C" wg genpsk > "$CONFIG_DIR/$PEER_ID/presharedkey-$PEER_ID"

  CLIENT_IP=""
  for idx in $(seq 2 254); do
    if ! grep -qR "${INTERFACE}.${idx}" "$CONFIG_DIR"/peer*/*.conf 2>/dev/null; then
      CLIENT_IP="${INTERFACE}.${idx}"
      break
    fi
  done
  [[ -n "$CLIENT_IP" ]] || return 1

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

  echo "$PSK" | docker exec -i "$C" sh -c 'cat > /tmp/psk.tmp && wg set wg0 peer "'"$PUB"'" preshared-key /tmp/psk.tmp allowed-ips "'"${CLIENT_IP}/32"'" && rm -f /tmp/psk.tmp' \
    || { echo "ERROR: failed updating WireGuard runtime for $PEER_ID" >&2; return 1; }
}

mosip_peer_for_secret() {
  local secret="$1" content="$2"
  awk -v env="$ENV_NAME" -v secret="$secret" '
    $1 ~ /^peer[0-9]+:?$/ {
      peer=$1; sub(/:$/, "", peer)
      desc=$0; sub(/^[[:space:]]*peer[0-9]+[[:space:]]*:?[[:space:]]*/, "", desc)
      suffix="(" secret ")"
      if (length(desc) < length(suffix)) next
      if (substr(desc, length(desc) - length(suffix) + 1) != suffix) next
      label=substr(desc, 1, length(desc) - length(suffix))
      if (label == env || index(label, env "(") == 1) { print peer; exit }
    }' <<<"$content"
}

mark_env_peer() {
  local peer="$1"
  [[ -n "$peer" ]] || return 0
  ENV_PEERS["$peer"]=1
  CHOSEN["$peer"]=1
}

run_allocation() {
  local assigned_content line n peer
  local -A TAKEN=() CHOSEN=() ENV_PEERS=()
  local tf="" wg0="" wg1="" reused="false" format="mosip"
  local record_tf="false" record_wg0="false" record_wg1="false"

  assigned_content="$(cat "$ASSIGNED_FILE" 2>/dev/null || true)"
  assigned_content="${assigned_content//$'\r'/}"

  if grep -qE '^peer[0-9]+[[:space:]]*:' <<<"$assigned_content"; then
    format="colon"
  fi

  while IFS= read -r line; do
    parse_assigned_line "$line" || continue
    peer_label_is_taken "$PARSED_LABEL" && TAKEN["$PARSED_PEER"]=1
  done <<<"$assigned_content"

  if [[ "$format" == "colon" ]]; then
    mapfile -t colon_reused < <(while IFS= read -r line; do
      parse_assigned_line "$line" || continue
      [[ "$PARSED_LABEL" == "$ENV_NAME" ]] && echo "$PARSED_PEER"
    done <<<"$assigned_content" | sort -t r -k2 -n)
    tf="${colon_reused[0]:-}"
    wg0="${colon_reused[1]:-}"
    wg1="${colon_reused[2]:-}"
    mark_env_peer "$tf"
    mark_env_peer "$wg0"
    mark_env_peer "$wg1"
    [[ -n "$tf" && -n "$wg0" && -n "$wg1" ]] && reused="true"
  else
    tf="$(mosip_peer_for_secret TF_WG_CONFIG "$assigned_content")"
    wg0="$(mosip_peer_for_secret CLUSTER_WIREGUARD_WG0 "$assigned_content")"
    wg1="$(mosip_peer_for_secret CLUSTER_WIREGUARD_WG1 "$assigned_content")"
    mark_env_peer "$tf"
    mark_env_peer "$wg0"
    mark_env_peer "$wg1"
    [[ -n "$tf" && -n "$wg0" && -n "$wg1" ]] && reused="true"
  fi

  if [[ -n "$FORCE_TF" ]]; then
    [[ -n "$tf" && "$FORCE_TF" != "$tf" ]] \
      && { echo "ERROR: --tf-peer $FORCE_TF conflicts with existing $tf for $ENV_NAME" >&2; return 1; }
    tf="$FORCE_TF"
    CHOSEN["$tf"]=1
  fi
  if [[ -n "$FORCE_WG0" ]]; then
    [[ -n "$wg0" && "$FORCE_WG0" != "$wg0" ]] \
      && { echo "ERROR: --wg0-peer $FORCE_WG0 conflicts with existing $wg0 for $ENV_NAME" >&2; return 1; }
    wg0="$FORCE_WG0"
    CHOSEN["$wg0"]=1
  fi
  if [[ -n "$FORCE_WG1" ]]; then
    [[ -n "$wg1" && "$FORCE_WG1" != "$wg1" ]] \
      && { echo "ERROR: --wg1-peer $FORCE_WG1 conflicts with existing $wg1 for $ENV_NAME" >&2; return 1; }
    wg1="$FORCE_WG1"
    CHOSEN["$wg1"]=1
  fi

  next_free() {
    local i pnum
    for ((i = 1; i <= MAX_PEERS; i++)); do
      peer="peer${i}"
      if [[ -z "${TAKEN[$peer]:-}" && -z "${CHOSEN[$peer]:-}" ]]; then
        ensure_peer_conf "$i" || return 1
        echo "$peer"
        return 0
      fi
    done
    return 1
  }

  if [[ "$reused" != "true" ]]; then
    if [[ -z "$tf"  ]]; then tf="$(next_free)"  || { echo "ERROR: no free peers in peer1..peer${MAX_PEERS}" >&2; return 1; }; CHOSEN["$tf"]=1;  fi
    if [[ -z "$wg0" ]]; then wg0="$(next_free)" || { echo "ERROR: no free peers in peer1..peer${MAX_PEERS}" >&2; return 1; }; CHOSEN["$wg0"]=1; fi
    if [[ -z "$wg1" ]]; then wg1="$(next_free)" || { echo "ERROR: no free peers in peer1..peer${MAX_PEERS}" >&2; return 1; }; CHOSEN["$wg1"]=1; fi
  fi

  for peer in "$tf" "$wg0" "$wg1"; do
    [[ -n "${TAKEN[$peer]:-}" && -z "${ENV_PEERS[$peer]:-}" ]] \
      && { echo "ERROR: $peer already assigned in $ASSIGNED_FILE" >&2; return 1; }
    [[ "$peer" =~ ^peer[0-9]+$ ]] || { echo "ERROR: invalid peer id $peer" >&2; return 1; }
    n="${peer#peer}"
    (( n >= 1 && n <= MAX_PEERS )) \
      || { echo "ERROR: $peer is outside peer1..peer${MAX_PEERS}" >&2; return 1; }
    ensure_peer_conf "$n" || { echo "ERROR: failed creating $peer" >&2; return 1; }
  done

  [[ "$tf" != "$wg0" && "$tf" != "$wg1" && "$wg0" != "$wg1" ]] \
    || { echo "ERROR: peers must be distinct (tf=$tf wg0=$wg0 wg1=$wg1)" >&2; return 1; }

  [[ -z "${ENV_PEERS[$tf]:-}"  ]] && record_tf="true"
  [[ -z "${ENV_PEERS[$wg0]:-}" ]] && record_wg0="true"
  [[ -z "${ENV_PEERS[$wg1]:-}" ]] && record_wg1="true"

  if [[ "$DRY_RUN" != "true" ]]; then
    assigned_file_writable "$ASSIGNED_FILE" || return 1
    if [[ "$format" == "colon" ]]; then
      [[ "$record_tf" == "true"  ]] && record_assignment "$tf"  "$ENV_NAME" "$format" "$ASSIGNED_FILE"
      [[ "$record_wg0" == "true" ]] && record_assignment "$wg0" "$ENV_NAME" "$format" "$ASSIGNED_FILE"
      [[ "$record_wg1" == "true" ]] && record_assignment "$wg1" "$ENV_NAME" "$format" "$ASSIGNED_FILE"
    else
      [[ "$record_tf" == "true"  ]] && record_assignment "$tf"  "${LABEL}(TF_WG_CONFIG)" "$format" "$ASSIGNED_FILE"
      [[ "$record_wg0" == "true" ]] && record_assignment "$wg0" "${LABEL}(CLUSTER_WIREGUARD_WG0)" "$format" "$ASSIGNED_FILE"
      [[ "$record_wg1" == "true" ]] && record_assignment "$wg1" "${LABEL}(CLUSTER_WIREGUARD_WG1)" "$format" "$ASSIGNED_FILE"
    fi
  fi

  printf 'ASSIGNED_FORMAT=%s\nREUSED=%s\nTF_PEER=%s\nWG0_PEER=%s\nWG1_PEER=%s\nRECORD_TF=%s\nRECORD_WG0=%s\nRECORD_WG1=%s\n' \
    "$format" "$reused" "$tf" "$wg0" "$wg1" "$record_tf" "$record_wg0" "$record_wg1"
}

exec 9>"$LOCK_FILE"
if ! flock -w 120 9; then
  echo "ERROR: timed out waiting for allocation lock ($LOCK_FILE)" >&2
  exit 1
fi
run_allocation
REMOTE_ATOMIC_ALLOCATE
}

atomic_rollback_assignments() {
  local record_tf="$1" record_wg0="$2" record_wg1="$3"
  [[ "$record_tf" == "true" || "$record_wg0" == "true" || "$record_wg1" == "true" ]] || return 0
  ssh_bash_stdin \
    "$ASSIGNED_FILE" \
    "$ASSIGN_LOCK_FILE" \
    "$TF_PEER" \
    "$WG0_PEER" \
    "$WG1_PEER" \
    "$record_tf" \
    "$record_wg0" \
    "$record_wg1" \
    <<'REMOTE_ROLLBACK_ASSIGNMENTS'
set -euo pipefail

ASSIGNED_FILE="$1"
LOCK_FILE="$2"
TF_PEER="$3"
WG0_PEER="$4"
WG1_PEER="$5"
RECORD_TF="$6"
RECORD_WG0="$7"
RECORD_WG1="$8"

exec 9>"$LOCK_FILE" || { echo "ERROR: cannot create allocation lock ($LOCK_FILE)" >&2; exit 1; }
if ! flock -w 120 9; then
  echo "ERROR: timed out waiting for allocation lock ($LOCK_FILE)" >&2
  exit 1
fi
wg_dir="$(dirname "$ASSIGNED_FILE")"
if [[ ! -w "$ASSIGNED_FILE" && ! -w "$wg_dir" ]]; then
  echo "ERROR: cannot write $ASSIGNED_FILE (check ownership/permissions on $wg_dir)" >&2
  exit 1
fi

atomic_replace_file() {
  local src="$1" dest="$2"
  if ! mv -f "$src" "$dest"; then
    rm -f "$src"
    echo "ERROR: cannot update $dest (check ownership/permissions)" >&2
    return 1
  fi
}

remove_peer_line() {
  local peer="$1" file="$2" dir tmp
  dir="$(dirname "$file")"
  tmp="$(mktemp "$dir/.assigned.XXXXXX")" || {
    echo "ERROR: cannot create temp file in $dir" >&2
    return 1
  }
  awk -v p="$peer" '$1 !~ ("^" p ":?$")' "$file" > "$tmp"
  atomic_replace_file "$tmp" "$file"
}

[[ "$RECORD_TF" == "true"  ]] && remove_peer_line "$TF_PEER" "$ASSIGNED_FILE"
[[ "$RECORD_WG0" == "true" ]] && remove_peer_line "$WG0_PEER" "$ASSIGNED_FILE"
[[ "$RECORD_WG1" == "true" ]] && remove_peer_line "$WG1_PEER" "$ASSIGNED_FILE"
REMOTE_ROLLBACK_ASSIGNMENTS
}

rollback_published_secrets() {
  local count="$1" i failed="false"
  [[ "$count" -gt 0 ]] || return 0
  for ((i = 0; i < count; i++)); do
    if gh secret delete "${SECRET_NAMES[$i]}" --env "$ENV_NAME" --repo "$REPO" 2>/dev/null; then
      log "Deleted secret ${SECRET_NAMES[$i]}"
    else
      err "Failed to delete secret ${SECRET_NAMES[$i]}"
      failed="true"
    fi
  done
  [[ "$failed" != "true" ]]
}

rollback_allocation_state() {
  local published_count="$1"
  err "Rolling back published secrets and assignments for $ENV_NAME ..."
  if ! rollback_published_secrets "$published_count"; then
    err "Skipping assignment rollback because at least one GitHub secret could not be deleted; keep $ASSIGNED_FILE reserved and clean up manually."
    return 0
  fi
  atomic_rollback_assignments "$RECORD_TF" "$RECORD_WG0" "$RECORD_WG1" \
    || err "Assignment rollback failed; fix $ASSIGNED_FILE manually for TF=$TF_PEER WG0=$WG0_PEER WG1=$WG1_PEER"
}

if [[ "$DRY_RUN" != "true" ]]; then
  log "Checking assigned.txt is writable on ${JUMPSERVER_HOST} ..."
  if ! ssh_bash_stdin "$ASSIGNED_FILE" <<'REMOTE_WRITABLE_CHECK'; then
set -euo pipefail
ASSIGNED_FILE="$1"
wg_dir="$(dirname "$ASSIGNED_FILE")"
if [[ -e "$ASSIGNED_FILE" ]]; then
  if [[ ! -w "$ASSIGNED_FILE" ]]; then
    echo "ERROR: $ASSIGNED_FILE is not writable by $(whoami) ($(stat -c '%U:%G %a' "$ASSIGNED_FILE" 2>/dev/null || echo 'stat failed'))" >&2
    echo "Fix: sudo chown ubuntu:ubuntu '$ASSIGNED_FILE' && sudo chmod u+w '$ASSIGNED_FILE'" >&2
    exit 1
  fi
elif [[ ! -w "$wg_dir" ]]; then
  echo "ERROR: cannot create $ASSIGNED_FILE (directory $wg_dir not writable by $(whoami))" >&2
  exit 1
fi
REMOTE_WRITABLE_CHECK
    die "assigned.txt is not writable on jumpserver (fix permissions before re-running)"
  fi
fi

log "Allocating peers on jumpserver under flock ($ASSIGN_LOCK_FILE) ..."
ALLOC_RESULT="$(atomic_allocate_peers)" || die "Peer allocation failed on jumpserver"
ASSIGNED_FORMAT="mosip"
REUSED="false"
TF_PEER=""
WG0_PEER=""
WG1_PEER=""
RECORD_TF="false"
RECORD_WG0="false"
RECORD_WG1="false"
while IFS= read -r line; do
  [[ "$line" == *=* ]] || continue
  case "${line%%=*}" in
    ASSIGNED_FORMAT) ASSIGNED_FORMAT="${line#*=}" ;;
    REUSED)          REUSED="${line#*=}" ;;
    TF_PEER)         TF_PEER="${line#*=}" ;;
    WG0_PEER)        WG0_PEER="${line#*=}" ;;
    WG1_PEER)        WG1_PEER="${line#*=}" ;;
    RECORD_TF)       RECORD_TF="${line#*=}" ;;
    RECORD_WG0)      RECORD_WG0="${line#*=}" ;;
    RECORD_WG1)      RECORD_WG1="${line#*=}" ;;
  esac
done <<<"$ALLOC_RESULT"
[[ -n "$TF_PEER" && -n "$WG0_PEER" && -n "$WG1_PEER" ]] \
  || die "Allocation returned incomplete peer set"

if [[ "$REUSED" == "true" ]]; then
  log "Reusing existing allocation for $ENV_NAME: TF=$TF_PEER WG0=$WG0_PEER WG1=$WG1_PEER"
elif [[ "$RECORD_TF" != "true" || "$RECORD_WG0" != "true" || "$RECORD_WG1" != "true" ]]; then
  log "Resuming partial allocation for $ENV_NAME: TF=$TF_PEER WG0=$WG0_PEER WG1=$WG1_PEER"
elif [[ "$ASSIGNED_FORMAT" == "colon" ]]; then
  log "Detected assigned.txt colon format (peerN: username)"
fi

log "Allocation -> TF_WG_CONFIG=$TF_PEER | CLUSTER_WIREGUARD_WG0=$WG0_PEER | CLUSTER_WIREGUARD_WG1=$WG1_PEER"

# ---- Fetch + transform each peer conf --------------------------------------
transform_conf() {
  # stdin: raw peer conf -> stdout: DNS removed, [Peer] AllowedIPs replaced
  awk -v ips="$ALLOWED_IPS" '
    /^\[Peer\]/ { peer=1; print; next }
    peer && /^[[:space:]]*AllowedIPs[[:space:]]*=/ { print "AllowedIPs = " ips; next }
    /^[[:space:]]*DNS[[:space:]]*=/ { next }
    { print }
  '
}

fetch_and_transform() {
  local peer="$1" raw
  local conf="$CONFIG_DIR/$peer/$peer.conf"
  if [[ "$DRY_RUN" == "true" ]] && ! peer_config_exists "$peer"; then
    echo "[DRY RUN] peer config for $peer not present yet"
    return 0
  fi
  raw="$(ssh_cmd "cat $(remote_quote "$conf") 2>/dev/null || sudo cat $(remote_quote "$conf")" 2>/dev/null || true)"
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
  log "DRY RUN - would update $ASSIGNED_FILE under allocation lock:"
  if [[ "$ASSIGNED_FORMAT" == "colon" ]]; then
    [[ "$RECORD_TF" == "true"  ]] && log "    $TF_PEER: $ENV_NAME"
    [[ "$RECORD_WG0" == "true" ]] && log "    $WG0_PEER: $ENV_NAME"
    [[ "$RECORD_WG1" == "true" ]] && log "    $WG1_PEER: $ENV_NAME"
  else
    [[ "$RECORD_TF" == "true"  ]] && log "    $TF_PEER  ${LABEL}(TF_WG_CONFIG)"
    [[ "$RECORD_WG0" == "true" ]] && log "    $WG0_PEER ${LABEL}(CLUSTER_WIREGUARD_WG0)"
    [[ "$RECORD_WG1" == "true" ]] && log "    $WG1_PEER ${LABEL}(CLUSTER_WIREGUARD_WG1)"
  fi
  log "DRY RUN - would create env '$ENV_NAME' and set 3 secrets (values not shown)."
  if grep -q '^AllowedIPs' <<<"$TF_CONF" 2>/dev/null; then
    log "DRY RUN - AllowedIPs in each conf: $(grep -h '^AllowedIPs' <<<"$TF_CONF" | head -1)"
  fi
  exit 0
fi

# ---- Create the GitHub environment + publish the three secrets -------------
log "Ensuring GitHub environment '$ENV_NAME' exists ..."
ENV_NAME_ENC="$(urlencode "$ENV_NAME")"
if ! gh api --method PUT -H "Accept: application/vnd.github+json" \
  "repos/${REPO}/environments/${ENV_NAME_ENC}" >/dev/null; then
  err "Failed creating environment '$ENV_NAME' in $REPO"
  if [[ "$RECORD_TF" == "true" || "$RECORD_WG0" == "true" || "$RECORD_WG1" == "true" ]]; then
    atomic_rollback_assignments "$RECORD_TF" "$RECORD_WG0" "$RECORD_WG1" \
      || err "Rollback failed; fix $ASSIGNED_FILE manually for TF=$TF_PEER WG0=$WG0_PEER WG1=$WG1_PEER"
  fi
  die "Environment creation failed"
fi

log "Publishing environment secrets ..."
PEER_CONFS=("$TF_CONF" "$WG0_CONF" "$WG1_CONF")
PUBLISHED_SECRETS=0
for i in "${!SECRET_NAMES[@]}"; do
  if printf '%s' "${PEER_CONFS[$i]}" \
    | gh secret set "${SECRET_NAMES[$i]}" --env "$ENV_NAME" --repo "$REPO" --body -; then
    PUBLISHED_SECRETS=$((PUBLISHED_SECRETS + 1))
    log "Published ${SECRET_NAMES[$i]}"
  else
    err "Failed to publish ${SECRET_NAMES[$i]} (${PUBLISHED_SECRETS}/3 succeeded)"
    rollback_allocation_state "$PUBLISHED_SECRETS"
    exit 1
  fi
done

# ---- Mirror allocation into the repo tracker (for visibility/PR history) ----
if [[ ! -f "$ALLOCATION_FILE" ]]; then
  printf 'env_name\ttf_peer\twg0_peer\twg1_peer\tallocated_at\n' > "$ALLOCATION_FILE"
fi
exec 8>"${ALLOCATION_FILE}.lock"
if ! flock -w 30 8; then
  die "Timed out waiting to update repo tracker lock ${ALLOCATION_FILE}.lock"
fi
TRACKER_TMP="$(mktemp "$(dirname "$ALLOCATION_FILE")/.wg-peer-allocation.XXXXXX")"
awk -F '\t' -v env="$ENV_NAME" 'NR == 1 || $1 != env' "$ALLOCATION_FILE" > "$TRACKER_TMP"
printf '%s\t%s\t%s\t%s\t%s\n' "$ENV_NAME" "$TF_PEER" "$WG0_PEER" "$WG1_PEER" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$TRACKER_TMP"
chmod --reference="$ALLOCATION_FILE" "$TRACKER_TMP" 2>/dev/null || true
mv "$TRACKER_TMP" "$ALLOCATION_FILE"
TRACKER_TMP=""

log "Done. Environment '$ENV_NAME' onboarded with peers TF=$TF_PEER WG0=$WG0_PEER WG1=$WG1_PEER."
log "Server tracker: $ASSIGNED_FILE | repo tracker: $ALLOCATION_FILE (commit it)."
