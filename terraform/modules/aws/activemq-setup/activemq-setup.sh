#!/bin/bash

# ActiveMQ EBS Volume Setup - Ansible Runner Script
# PURPOSE: Install Ansible and run the activemq-setup.yml playbook to
# format and mount the 3rd EBS volume on this NGINX node.
# ActiveMQ itself runs inside Kubernetes — this only prepares the storage.

set -euo pipefail

echo "=== ActiveMQ EBS Volume Setup Started at $(date) ==="

# ── Non-interactive environment ────────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none
export UCF_FORCE_CONFFOLD=1
export DEBCONF_NONINTERACTIVE_SEEN=true
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections 2>/dev/null || true
echo 'debconf debconf/priority select critical'       | debconf-set-selections 2>/dev/null || true

# ── Validate required environment variables ────────────────────────────────────
echo "=== Validating Environment Variables ==="
REQUIRED_VARS=(
    "ACTIVEMQ_STORAGE_DEVICE"
    "ACTIVEMQ_MOUNT_POINT"
)
MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    [ -z "${!var:-}" ] && MISSING_VARS+=("$var")
done
if [ ${#MISSING_VARS[@]} -ne 0 ]; then
    echo "ERROR: Missing required environment variables:"
    printf '  - %s\n' "${MISSING_VARS[@]}"
    exit 1
fi
echo "  ACTIVEMQ_STORAGE_DEVICE=$ACTIVEMQ_STORAGE_DEVICE"
echo "  ACTIVEMQ_MOUNT_POINT=$ACTIVEMQ_MOUNT_POINT"

# ── Install prerequisites ──────────────────────────────────────────────────────
echo "=== Installing Prerequisites (Ansible) ==="
sudo apt-get update -qq || { sleep 5; sudo apt-get update -qq; }

# Try package-based Ansible first, fall back to pip
if ! dpkg -l ansible 2>/dev/null | grep -q "^ii"; then
    sudo apt-get install -y ansible \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" || {
        echo "Package install failed, installing via pip..."
        sudo apt-get install -y python3-pip \
            -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold"
        python3 -m pip install --user --quiet ansible
        export PATH="$HOME/.local/bin:$PATH"
    }
fi
ansible --version | head -1

# ── Detect local node IP ───────────────────────────────────────────────────────
echo "=== Detecting local node IP ==="
LOCAL_IP=""
LOCAL_IP=$(timeout 5 curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo "")
[ -z "$LOCAL_IP" ] && LOCAL_IP=$(hostname -I | awk '{print $1}')
[ -z "$LOCAL_IP" ] && { echo "ERROR: Could not detect local IP"; exit 1; }
echo "Local IP: $LOCAL_IP"

# ── Create Ansible working directory ──────────────────────────────────────────
WORK_DIR="/tmp/activemq-ebs-$$"
mkdir -p "$WORK_DIR"

cat >"$WORK_DIR/inventory.ini" <<EOF
[activemq_servers]
$LOCAL_IP ansible_connection=local ansible_user=ubuntu ansible_become=yes
EOF

cat >"$WORK_DIR/ansible.cfg" <<'EOF'
[defaults]
gathering = explicit
galaxy_disable_gpg_verify = true
[ssh_connection]
pipelining = True
EOF

cp /tmp/activemq-setup.yml "$WORK_DIR/activemq-setup.yml"

# ── Run the Ansible playbook ───────────────────────────────────────────────────
echo "=== Running Ansible Playbook: EBS Volume Setup ==="
echo "  Device : $ACTIVEMQ_STORAGE_DEVICE"
echo "  Mount  : $ACTIVEMQ_MOUNT_POINT"
echo ""

ANSIBLE_CONFIG="$WORK_DIR/ansible.cfg" \
timeout 300 ansible-playbook -v \
    -i "$WORK_DIR/inventory.ini" \
    -e "activemq_storage_device=$ACTIVEMQ_STORAGE_DEVICE" \
    -e "activemq_mount_point=$ACTIVEMQ_MOUNT_POINT" \
    "$WORK_DIR/activemq-setup.yml" 2>&1 | tee /tmp/activemq-ebs.log
ANSIBLE_EXIT=$?

if [ $ANSIBLE_EXIT -ne 0 ]; then
    echo ""
    echo "ERROR: Ansible playbook failed (exit code $ANSIBLE_EXIT)"
    tail -30 /tmp/activemq-ebs.log || true
    exit 1
fi

echo ""
echo "EBS volume for ActiveMQ is mounted at $ACTIVEMQ_MOUNT_POINT"
echo "=== Done at $(date) ==="
