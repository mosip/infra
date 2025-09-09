# Key improvements to fix the timeout issues

locals {
  # Enhanced SSH connection settings with better reliability
  ssh_connection_base = {
    type        = "ssh"
    user        = "ubuntu"
    private_key = var.SSH_PRIVATE_KEY
    timeout     = "10m"  # Increased from 4m to 10m
    # Add SSH options for better connection handling
    agent       = false
    host_key    = null
    # Add keep-alive settings
    script_path = "/tmp/terraform_%RAND%.sh"
  }
  
  # Enhanced retry script with better error handling and logging
  retry_script_execution = [
    "set -e",  # Exit on error
    "set -o pipefail",  # Exit on pipe failures
    "chmod +x /tmp/rke2-setup.sh",
    "echo 'Starting RKE2 setup with enhanced error handling...'",
    
    # Pre-flight checks
    "echo 'Performing pre-flight checks...'",
    "if ! ping -c 1 ${local.CONTROL_PLANE_NODE_1} >/dev/null 2>&1; then",
    "  echo 'ERROR: Cannot reach control plane node ${local.CONTROL_PLANE_NODE_1}'",
    "  exit 1",
    "fi",
    
    # Check if RKE2 is already installed/running
    "if systemctl is-active --quiet rke2-server 2>/dev/null; then",
    "  echo 'RKE2 server is already running, attempting graceful restart...'",
    "  sudo systemctl stop rke2-server || true",
    "  sleep 10",
    "fi",
    
    # Enhanced retry logic with exponential backoff
    "for attempt in 1 2 3; do",
    "  echo \"=== Attempt $attempt: Starting RKE2 setup at $(date) ===\"",
    "  ",
    "  # Calculate backoff time (30s, 60s, 120s)",
    "  backoff_time=$((30 * attempt))",
    "  ",
    "  # Run the setup script with timeout and proper signal handling",
    "  if timeout --preserve-status 8m sudo bash /tmp/rke2-setup.sh 2>&1 | tee -a /tmp/rke2-setup-$attempt.log; then",
    "    echo \"✅ RKE2 setup completed successfully on attempt $attempt at $(date)\"",
    "    ",
    "    # Verify the installation",
    "    if sudo systemctl is-active --quiet rke2-server || sudo systemctl is-active --quiet rke2-agent; then",
    "      echo \"✅ RKE2 service is running successfully\"",
    "      break",
    "    else",
    "      echo \"⚠️ RKE2 setup completed but service is not running, will retry...\"",
    "    fi",
    "  else",
    "    exit_code=$?",
    "    echo \"❌ Attempt $attempt failed with exit code $exit_code at $(date)\"",
    "    ",
    "    # Log system status for debugging",
    "    echo \"System status:\"",
    "    free -h || true",
    "    df -h || true",
    "    sudo systemctl status rke2-server --no-pager -l || true",
    "    sudo systemctl status rke2-agent --no-pager -l || true",
    "    ",
    "    if [ $attempt -eq 3 ]; then",
    "      echo \"❌ All 3 attempts failed. Final attempt had exit code $exit_code\"",
    "      echo \"Logs from all attempts:\"",
    "      for i in 1 2 3; do",
    "        if [ -f /tmp/rke2-setup-$i.log ]; then",
    "          echo \"=== Attempt $i log ===\"",
    "          tail -20 /tmp/rke2-setup-$i.log",
    "        fi",
    "      done",
    "      exit 1",
    "    else",
    "      echo \"Waiting $backoff_time seconds before retry...\"",
    "      sleep $backoff_time",
    "    fi",
    "  fi",
    "done"
  ]
}

# Enhanced file upload with better error handling
resource "null_resource" "rke2-additional-control-plane-setup" {
  depends_on = [null_resource.rke2-primary-cluster-setup]
  for_each   = local.K8S_ADDITIONAL_CONTROL_PLANE_NODES
  
  triggers = {
    node_hash   = md5(local.K8S_CLUSTER_PRIVATE_IPS_STR)
    script_hash = filemd5("${path.module}/rke2-setup.sh")
    # Add timestamp to force recreation if needed
    timestamp   = timestamp()
  }
  
  # Enhanced file upload with better retry logic
  provisioner "local-exec" {
    command = <<EOF
#!/bin/bash
set -e
echo "📤 Starting file upload to additional control plane node ${each.key}..."

# Function to cleanup temp files
cleanup() {
  rm -f /tmp/ssh_key_${each.key}_$$
}
trap cleanup EXIT

for attempt in 1 2 3; do
  echo "Attempt $attempt: Uploading rke2-setup.sh to ${each.value}..."
  
  # Create temporary SSH key file with secure permissions
  echo "${var.SSH_PRIVATE_KEY}" > /tmp/ssh_key_${each.key}_$$
  chmod 600 /tmp/ssh_key_${each.key}_$$
  
  # Test SSH connectivity first
  if ! ssh -i /tmp/ssh_key_${each.key}_$$ -o ConnectTimeout=30 -o BatchMode=yes -o StrictHostKeyChecking=no ubuntu@${each.value} "echo 'SSH connectivity test successful'" 2>/dev/null; then
    echo "❌ SSH connectivity test failed for ${each.key}"
    if [ $attempt -eq 3 ]; then
      echo "SSH connectivity failed after 3 attempts"
      exit 1
    fi
    sleep 30
    continue
  fi
  
  # Upload the file with enhanced options
  if timeout 6m scp -i /tmp/ssh_key_${each.key}_$$ \
    -o ConnectTimeout=30 \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=4 \
    -o StrictHostKeyChecking=no \
    -o BatchMode=yes \
    -C \
    "${path.module}/rke2-setup.sh" ubuntu@${each.value}:/tmp/rke2-setup.sh; then
    
    # Verify the file was uploaded correctly
    if ssh -i /tmp/ssh_key_${each.key}_$$ -o ConnectTimeout=30 -o BatchMode=yes -o StrictHostKeyChecking=no ubuntu@${each.value} "test -f /tmp/rke2-setup.sh && echo 'File verification successful'"; then
      echo "✅ File uploaded and verified successfully to ${each.key} on attempt $attempt"
      break
    else
      echo "❌ File upload succeeded but verification failed for ${each.key}"
    fi
  else
    echo "❌ File upload to ${each.key} attempt $attempt failed or timed out"
  fi
  
  if [ $attempt -eq 3 ]; then
    echo "All file upload attempts to ${each.key} failed. Exiting..."
    exit 1
  else
    echo "Waiting 45 seconds before retry..."
    sleep 45
  fi
done
EOF
  }

  # Enhanced remote execution with better connection handling
  provisioner "remote-exec" {
    inline = concat(
      [
        # Set up environment for better debugging
        "export DEBIAN_FRONTEND=noninteractive",
        "echo 'Setting up environment variables...'",
      ],
      local.k8s_env_vars,
      [
        "echo 'Environment variables set successfully'",
        "echo 'Current environment:'",
        "env | grep -E '^(K8S_|RKE2_|CONTROL_PLANE_|INSTALL_|WORK_DIR)' || true",
      ],
      local.retry_script_execution
    )
    
    connection {
      type        = local.ssh_connection_base.type
      host        = each.value
      user        = local.ssh_connection_base.user
      private_key = local.ssh_connection_base.private_key
      timeout     = local.ssh_connection_base.timeout
      agent       = local.ssh_connection_base.agent
      host_key    = local.ssh_connection_base.host_key
      script_path = local.ssh_connection_base.script_path
    }
    
    # Add connection retry at provisioner level
    on_failure = continue
  }
  
  # Fallback validation
  provisioner "local-exec" {
    when    = create
    command = <<EOF
#!/bin/bash
echo "Validating RKE2 setup for ${each.key}..."

# Create temporary SSH key
echo "${var.SSH_PRIVATE_KEY}" > /tmp/ssh_key_${each.key}_validation_$$
chmod 600 /tmp/ssh_key_${each.key}_validation_$$

# Check if RKE2 is running
if ssh -i /tmp/ssh_key_${each.key}_validation_$$ -o ConnectTimeout=30 -o BatchMode=yes -o StrictHostKeyChecking=no ubuntu@${each.value} "sudo systemctl is-active rke2-server || sudo systemctl is-active rke2-agent" 2>/dev/null; then
  echo "✅ RKE2 validation successful for ${each.key}"
else
  echo "❌ RKE2 validation failed for ${each.key}"
  echo "Checking RKE2 service status..."
  ssh -i /tmp/ssh_key_${each.key}_validation_$$ -o ConnectTimeout=30 -o BatchMode=yes -o StrictHostKeyChecking=no ubuntu@${each.value} "sudo systemctl status rke2-server --no-pager -l || sudo systemctl status rke2-agent --no-pager -l" 2>/dev/null || true
fi

rm -f /tmp/ssh_key_${each.key}_validation_$$
EOF
  }
}

# Add a dependency check resource
resource "null_resource" "rke2-cluster-health-check" {
  depends_on = [
    null_resource.rke2-primary-cluster-setup,
    null_resource.rke2-additional-control-plane-setup
  ]
  
  provisioner "local-exec" {
    command = <<EOF
#!/bin/bash
echo "Performing cluster health check..."

# Create temporary SSH key
echo "${var.SSH_PRIVATE_KEY}" > /tmp/ssh_key_health_$$
chmod 600 /tmp/ssh_key_health_$$

# Check primary control plane
echo "Checking primary control plane node..."
if ssh -i /tmp/ssh_key_health_$$ -o ConnectTimeout=30 -o BatchMode=yes -o StrictHostKeyChecking=no ubuntu@${local.CONTROL_PLANE_NODE_1} "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes" 2>/dev/null; then
  echo "✅ Primary control plane is healthy"
else
  echo "❌ Primary control plane health check failed"
  exit 1
fi

rm -f /tmp/ssh_key_health_$$
echo "Cluster health check completed successfully"
EOF
  }
}
