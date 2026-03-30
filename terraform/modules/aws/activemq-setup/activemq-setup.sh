#!/bin/bash

# ActiveMQ EBS Volume Setup - Runs on the Terraform RUNNER machine.
# Ansible SSHes into the NGINX node to format/mount EBS and configure NFS.
# ActiveMQ itself runs inside Kubernetes — this only prepares the storage.

set -euo pipefail

echo "=== ActiveMQ EBS Volume Setup Started at $(date) ==="

# ── Validate required environment variables ────────────────────────────────────
echo "=== Validating Environment Variables ==="
REQUIRED_VARS=(
    "NGINX_PRIVATE_IP"
    "ACTIVEMQ_STORAGE_DEVICE"
    "ACTIVEMQ_MOUNT_POINT"
    "SSH_KEY_FILE"
    "WORK_DIR"
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
echo "  NGINX_PRIVATE_IP=$NGINX_PRIVATE_IP"
echo "  ACTIVEMQ_STORAGE_DEVICE=$ACTIVEMQ_STORAGE_DEVICE"
echo "  ACTIVEMQ_MOUNT_POINT=$ACTIVEMQ_MOUNT_POINT"
echo "  SSH_KEY_FILE=$SSH_KEY_FILE"
echo "  WORK_DIR=$WORK_DIR"

# ── Verify Ansible is available on the runner ──────────────────────────────────
echo "=== Checking Ansible on runner machine ==="
if ! command -v ansible-playbook &>/dev/null; then
    echo "ERROR: ansible-playbook not found on the Terraform runner."
    echo "Please install Ansible on the machine running Terraform:"
    echo "  Ubuntu/Debian : sudo apt-get install -y ansible"
    echo "  RHEL/CentOS   : sudo yum install -y ansible"
    echo "  pip           : pip3 install ansible"
    exit 1
fi
echo "Ansible found: $(ansible --version | head -1)"

# ── Wait for NGINX SSH to be ready ────────────────────────────────────────────
echo "=== Waiting for NGINX SSH to be ready ($NGINX_PRIVATE_IP) ==="
for i in $(seq 1 20); do
    if ssh -i "$SSH_KEY_FILE" \
           -o StrictHostKeyChecking=no \
           -o ConnectTimeout=5 \
           -o BatchMode=yes \
           ubuntu@"$NGINX_PRIVATE_IP" "echo ok" &>/dev/null; then
        echo "SSH ready after $i attempt(s)"
        break
    fi
    echo "  Attempt $i/20: SSH not ready yet, retrying in 10s..."
    sleep 10
    if [ "$i" -eq 20 ]; then
        echo "ERROR: NGINX SSH did not become ready after 200 seconds"
        exit 1
    fi
done

# ── Create Ansible inventory and config ───────────────────────────────────────
echo "=== Creating Ansible inventory ==="
cat > "$WORK_DIR/inventory.ini" <<EOF
[activemq_servers]
$NGINX_PRIVATE_IP ansible_user=ubuntu ansible_become=yes ansible_ssh_private_key_file=$SSH_KEY_FILE
EOF

cat > "$WORK_DIR/ansible.cfg" <<EOF
[defaults]
host_key_checking = False
gathering = explicit
galaxy_disable_gpg_verify = true
[ssh_connection]
pipelining = True
ssh_args = -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
EOF

echo "Inventory:"
cat "$WORK_DIR/inventory.ini"

# ── Test Ansible connectivity ──────────────────────────────────────────────────
echo "=== Testing Ansible SSH connectivity to NGINX ==="
ANSIBLE_CONFIG="$WORK_DIR/ansible.cfg" \
ansible -i "$WORK_DIR/inventory.ini" activemq_servers -m ping || {
    echo "ERROR: Ansible ping to NGINX failed. Check SSH access."
    exit 1
}

# ── Run the Ansible playbook ───────────────────────────────────────────────────
echo "=== Running Ansible Playbook (runner → NGINX via SSH) ==="
echo "  Device : $ACTIVEMQ_STORAGE_DEVICE"
echo "  Mount  : $ACTIVEMQ_MOUNT_POINT"
echo ""

ANSIBLE_LOG="/tmp/activemq-ebs.log"

set +o pipefail   # Temporarily off so PIPESTATUS works correctly
ANSIBLE_CONFIG="$WORK_DIR/ansible.cfg" \
timeout 300 ansible-playbook -v \
    -i "$WORK_DIR/inventory.ini" \
    -e "activemq_storage_device=$ACTIVEMQ_STORAGE_DEVICE" \
    -e "activemq_mount_point=$ACTIVEMQ_MOUNT_POINT" \
    "$WORK_DIR/activemq-setup.yml" 2>&1 | tee "$ANSIBLE_LOG"
ANSIBLE_EXIT=${PIPESTATUS[0]}
set -o pipefail

if [ "$ANSIBLE_EXIT" -ne 0 ]; then
    echo ""
    echo "ERROR: Ansible playbook failed (exit code $ANSIBLE_EXIT)"
    echo "--- Last 30 lines of log ---"
    tail -30 "$ANSIBLE_LOG" || true
    exit 1
fi

if [ ! -s /tmp/activemq-storageclass.yaml ]; then
    echo ""
    echo "ERROR: StorageClass manifest not found or empty at /tmp/activemq-storageclass.yaml"
    echo "--- Last 30 lines of Ansible log ---"
    tail -30 "$ANSIBLE_LOG" || true
    exit 1
fi

echo ""
echo "=== Done at $(date) ==="
echo "EBS volume for ActiveMQ is mounted at $ACTIVEMQ_MOUNT_POINT on $NGINX_PRIVATE_IP"
echo "StorageClass YAML written to /tmp/activemq-storageclass.yaml on this runner"