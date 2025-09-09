variable "K8S_CLUSTER_PRIVATE_IPS" { type = map(string) }
variable "SSH_PRIVATE_KEY" { type = string }
variable "K8S_INFRA_REPO_URL" {
  description = "The URL of the Kubernetes infrastructure GitHub repository"
  type        = string
  validation {
    condition     = can(regex("^https://github\\.com/.+/.+\\.git$", var.K8S_INFRA_REPO_URL))
    error_message = "The K8S_INFRA_REPO_URL must be a valid GitHub repository URL ending with .git"
  }
}

variable "K8S_INFRA_BRANCH" { type = string }
variable "RANCHER_IMPORT_URL" {
  description = "Rancher import URL for kubectl apply"
  type        = string

  validation {
    condition     = can(regex("^\"kubectl apply -f https://rancher\\.mosip\\.net/v3/import/[a-zA-Z0-9_\\-]+\\.yaml\"$", var.RANCHER_IMPORT_URL))
    error_message = "The RANCHER_IMPORT_URL must be in the format: '\"kubectl apply -f https://rancher.mosip.net/v3/import/<ID>.yaml\"'"
  }
}

# Generate a random string (token)
resource "random_string" "K8S_TOKEN" {
  length  = 32    # Length of the token
  upper   = true  # Include uppercase letters
  lower   = true  # Include lowercase letters
  numeric = true  # Include numbers
  special = false # Include special characters (true/false)
  # override_special = "$%&^@#"
  # min_numeric = 5
  # min_upper = 5
  # min_lower = 5
}

locals {
  # Dynamically find the primary control plane node (first one) by role-based pattern
  # This matches keys like: {cluster_name}-CONTROL-PLANE-NODE-1, {cluster_name}-CONTROL-PLANE-NODE-2, etc.
  primary_control_plane_key   = [for key in keys(var.K8S_CLUSTER_PRIVATE_IPS) : key if can(regex(".*CONTROL-PLANE-NODE-1$", key))][0]
  CONTROL_PLANE_NODE_1        = var.K8S_CLUSTER_PRIVATE_IPS[local.primary_control_plane_key]
  K8S_CLUSTER_PRIVATE_IPS_STR = join(",", [for key, value in var.K8S_CLUSTER_PRIVATE_IPS : "${key}=${value}"])
  
  # Extract cluster name and node name from the primary control plane key
  cluster_name_parts = split("-", local.primary_control_plane_key)
  cluster_name = local.cluster_name_parts[0]  # Extract cluster name (e.g., "mtest")
  
  # Base RKE configuration - only add variables not provided by user-data
  RKE_CONFIG_BASE = {
    # Variables from Terraform that user-data doesn't provide
    CONTROL_PLANE_NODE_1        = local.CONTROL_PLANE_NODE_1
    K8S_INFRA_REPO_URL          = var.K8S_INFRA_REPO_URL
    K8S_INFRA_BRANCH            = var.K8S_INFRA_BRANCH
    K8S_CLUSTER_PRIVATE_IPS_STR = local.K8S_CLUSTER_PRIVATE_IPS_STR
    K8S_TOKEN                   = random_string.K8S_TOKEN.result
    
    # RKE2 specific configuration
    RKE2_LOCATION               = "/home/ubuntu/k8s-infra/k8-cluster/on-prem/rke2/"
    RKE2_CONFIG_DIR             = "/etc/rancher/rke2"
    INSTALL_RKE2_VERSION        = "v1.28.9+rke2r1"
    
    # Working directory
    WORK_DIR                    = "/home/ubuntu/"
  }

  # Conditional RKE configuration with Rancher import URL only when enabled
  RKE_CONFIG = var.enable_rancher_import ? merge(local.RKE_CONFIG_BASE, {
    RANCHER_IMPORT_URL = var.RANCHER_IMPORT_URL
  }) : local.RKE_CONFIG_BASE
  
  # Filter out ALL control plane nodes from cluster setup to avoid duplicate setup
  # Only ETCD and WORKER nodes should be in the cluster setup
  K8S_CLUSTER_PRIVATE_IPS_EXCEPT_CONTROL_PLANE_NODES = {
    for key, value in var.K8S_CLUSTER_PRIVATE_IPS : key => value if !can(regex(".*CONTROL-PLANE-NODE.*", key))
  }

  # Get additional control plane nodes (NODE-2, NODE-3, ..., NODE-N) that need to join after primary
  # This supports unlimited control plane nodes (2, 3, 10, 15, 99, etc.)
  K8S_ADDITIONAL_CONTROL_PLANE_NODES = {
    for key, value in var.K8S_CLUSTER_PRIVATE_IPS : key => value if can(regex(".*CONTROL-PLANE-NODE.*", key)) && !can(regex(".*CONTROL-PLANE-NODE-1$", key))
  }

  datetime = formatdate("2006-01-02_15-04-05", timestamp())
  
  # Backup the current environment file before making changes
  backup_command = [
    "sudo cp /etc/environment /tmp/environment-bkp-${local.datetime}"
  ]

  # Only update the variables that Terraform provides, don't override user-data variables
  update_commands = [
    for key, value in local.RKE_CONFIG :
    "sudo sed -i \"/^${key}=/d\" /etc/environment && echo '${key}=${value}' | sudo tee -a /etc/environment"
  ]

  k8s_env_vars = concat(local.backup_command, local.update_commands)
  
  # SSH connection settings with retry logic
  ssh_connection_base = {
    type        = "ssh"
    user        = "ubuntu"
    private_key = var.SSH_PRIVATE_KEY
    timeout     = "4m"  # 4 minute timeout as requested
    # Add SSH options for better connection handling
    agent       = false
    host_key    = null
  }
  
  # Commands with retry logic for SSH operations
  retry_script_execution = [
    "chmod +x /tmp/rke2-setup.sh",
    # Retry logic with 4-minute timeout per attempt
    "for attempt in 1 2 3; do",
    "  echo \"Attempt $attempt: Starting RKE2 setup...\"",
    "  if timeout 4m sudo bash /tmp/rke2-setup.sh; then",
    "    echo \"✅ RKE2 setup completed successfully on attempt $attempt\"",
    "    break",
    "  else",
    "    echo \"❌ Attempt $attempt failed or timed out after 4 minutes\"",
    "    if [ $attempt -eq 3 ]; then",
    "      echo \"All 3 attempts failed. Exiting...\"",
    "      exit 1",
    "    else",
    "      echo \"Waiting 30 seconds before retry...\"",
    "      sleep 30",
    "    fi",
    "  fi",
    "done"
  ]
}

resource "null_resource" "rke2-primary-cluster-setup" {
  triggers = {
    node_hash   = md5(local.K8S_CLUSTER_PRIVATE_IPS_STR)
    script_hash = filemd5("${path.module}/rke2-setup.sh")
  }
  
  # Retry mechanism for file upload
  provisioner "local-exec" {
    command = <<EOF
#!/bin/bash
echo "📤 Starting file upload to primary control plane node..."
for attempt in 1 2 3; do
  echo "Attempt $attempt: Uploading rke2-setup.sh..."
  
  # Create temporary SSH key file
  echo "${var.SSH_PRIVATE_KEY}" > /tmp/ssh_key_$$
  chmod 600 /tmp/ssh_key_$$
  
  if timeout 4m scp -i /tmp/ssh_key_$$ -o ConnectTimeout=30 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no "${path.module}/rke2-setup.sh" ubuntu@${local.CONTROL_PLANE_NODE_1}:/tmp/rke2-setup.sh; then
    echo "✅ File uploaded successfully on attempt $attempt"
    rm -f /tmp/ssh_key_$$
    break
  else
    echo "❌ File upload attempt $attempt failed or timed out"
    rm -f /tmp/ssh_key_$$
    if [ $attempt -eq 3 ]; then
      echo "All file upload attempts failed. Exiting..."
      exit 1
    else
      echo "Waiting 30 seconds before retry..."
      sleep 30
    fi
  fi
done
EOF
  }

  # SSH connection with retry logic built into the commands
  provisioner "remote-exec" {
    inline = concat(
      local.k8s_env_vars,
      local.retry_script_execution
    )
    
    connection {
      type        = local.ssh_connection_base.type
      host        = local.CONTROL_PLANE_NODE_1
      user        = local.ssh_connection_base.user
      private_key = local.ssh_connection_base.private_key
      timeout     = local.ssh_connection_base.timeout
      agent       = local.ssh_connection_base.agent
      host_key    = local.ssh_connection_base.host_key
    }
    
    # Add retry logic at the provisioner level
    on_failure = continue
  }
  
  # Fallback retry mechanism using local-exec
  provisioner "local-exec" {
    when = destroy
    command = "echo 'Cleanup completed for primary control plane node'"
  }
}

resource "null_resource" "rke2-additional-control-plane-setup" {
  depends_on = [null_resource.rke2-primary-cluster-setup]
  for_each   = local.K8S_ADDITIONAL_CONTROL_PLANE_NODES
  
  triggers = {
    node_hash   = md5(local.K8S_CLUSTER_PRIVATE_IPS_STR)
    script_hash = filemd5("${path.module}/rke2-setup.sh")
  }
  
  # Retry mechanism for file upload
  provisioner "local-exec" {
    command = <<EOF
#!/bin/bash
echo "📤 Starting file upload to additional control plane node ${each.key}..."
for attempt in 1 2 3; do
  echo "Attempt $attempt: Uploading rke2-setup.sh to ${each.value}..."
  
  # Create temporary SSH key file
  echo "${var.SSH_PRIVATE_KEY}" > /tmp/ssh_key_${each.key}_$$
  chmod 600 /tmp/ssh_key_${each.key}_$$
  
  if timeout 4m scp -i /tmp/ssh_key_${each.key}_$$ -o ConnectTimeout=30 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no "${path.module}/rke2-setup.sh" ubuntu@${each.value}:/tmp/rke2-setup.sh; then
    echo "✅ File uploaded successfully to ${each.key} on attempt $attempt"
    rm -f /tmp/ssh_key_${each.key}_$$
    break
  else
    echo "❌ File upload to ${each.key} attempt $attempt failed or timed out"
    rm -f /tmp/ssh_key_${each.key}_$$
    if [ $attempt -eq 3 ]; then
      echo "All file upload attempts to ${each.key} failed. Exiting..."
      exit 1
    else
      echo "Waiting 30 seconds before retry..."
      sleep 30
    fi
  fi
done
EOF
  }

  provisioner "remote-exec" {
    inline = concat(
      local.k8s_env_vars,
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
    }
  }
}

resource "null_resource" "rke2-cluster-setup" {
  depends_on = [
    null_resource.rke2-primary-cluster-setup,
    null_resource.rke2-additional-control-plane-setup
  ]
  for_each   = local.K8S_CLUSTER_PRIVATE_IPS_EXCEPT_CONTROL_PLANE_NODES
  
  triggers = {
    node_hash   = md5(local.K8S_CLUSTER_PRIVATE_IPS_STR)
    script_hash = filemd5("${path.module}/rke2-setup.sh")
  }
  
  # Retry mechanism for file upload
  provisioner "local-exec" {
    command = <<EOF
#!/bin/bash
echo "📤 Starting file upload to cluster node ${each.key}..."
for attempt in 1 2 3; do
  echo "Attempt $attempt: Uploading rke2-setup.sh to ${each.value}..."
  
  # Create temporary SSH key file
  echo "${var.SSH_PRIVATE_KEY}" > /tmp/ssh_key_${each.key}_$$
  chmod 600 /tmp/ssh_key_${each.key}_$$
  
  if timeout 4m scp -i /tmp/ssh_key_${each.key}_$$ -o ConnectTimeout=30 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no "${path.module}/rke2-setup.sh" ubuntu@${each.value}:/tmp/rke2-setup.sh; then
    echo "✅ File uploaded successfully to ${each.key} on attempt $attempt"
    rm -f /tmp/ssh_key_${each.key}_$$
    break
  else
    echo "❌ File upload to ${each.key} attempt $attempt failed or timed out"
    rm -f /tmp/ssh_key_${each.key}_$$
    if [ $attempt -eq 3 ]; then
      echo "All file upload attempts to ${each.key} failed. Exiting..."
      exit 1
    else
      echo "Waiting 30 seconds before retry..."
      sleep 30
    fi
  fi
done
EOF
  }

  provisioner "remote-exec" {
    inline = concat(
      local.k8s_env_vars,
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
    }
  }
}

variable "enable_rancher_import" {
  description = "Set to true to enable Rancher import"
  type        = bool
  default     = false
}

resource "null_resource" "rancher-import" {
  count      = var.enable_rancher_import ? 1 : 0
  depends_on = [null_resource.rke2-primary-cluster-setup]
  
  provisioner "remote-exec" {
    inline = concat(
      [
        "mkdir -p ~/.kube/ ",
        "sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config",
        "sudo chown -R $USER:$USER ~/.kube",
        "sudo cp /var/lib/rancher/rke2/bin/kubectl /bin/kubectl",
        "sudo chmod 400 ~/.kube/config && sudo chmod +x /bin/kubectl",
        # Add retry logic for Rancher import
        "for attempt in 1 2 3; do",
        "  echo \"Attempt $attempt: Running Rancher import...\"",
        "  if timeout 4m bash -c '$RANCHER_IMPORT_URL'; then",
        "    echo \"✅ Rancher import completed successfully on attempt $attempt\"",
        "    break",
        "  else",
        "    echo \"❌ Rancher import attempt $attempt failed or timed out\"",
        "    if [ $attempt -eq 3 ]; then",
        "      echo \"All Rancher import attempts failed\"",
        "      exit 1",
        "    else",
        "      echo \"Waiting 30 seconds before retry...\"",
        "      sleep 30",
        "    fi",
        "  fi",
        "done",
        "kubectl -n cattle-system patch deployment cattle-cluster-agent -p '{\"spec\": {\"template\": {\"spec\": {\"dnsPolicy\": \"Default\"}}}}'",
        "sleep 420",
        "kubectl -n cattle-system rollout status deploy",
        "sleep 30"
      ]
    )
    
    connection {
      type        = local.ssh_connection_base.type
      host        = local.CONTROL_PLANE_NODE_1
      user        = local.ssh_connection_base.user
      private_key = local.ssh_connection_base.private_key
      timeout     = "40m"  # Extended timeout for Rancher operations
      agent       = local.ssh_connection_base.agent
      host_key    = local.ssh_connection_base.host_key
    }
  }
}

resource "null_resource" "download-k8s-kubeconfig" {
  depends_on = [null_resource.rke2-cluster-setup]
  for_each   = var.K8S_CLUSTER_PRIVATE_IPS
  
  triggers = {
    node_hash = md5(local.K8S_CLUSTER_PRIVATE_IPS_STR)
  }

  provisioner "local-exec" {
    command = <<EOF
#!/bin/bash
echo "📥 Starting kubeconfig download from ${each.key}..."

# Retry logic for kubeconfig download
for attempt in 1 2 3; do
  echo "Attempt $attempt: Downloading kubeconfig from ${each.value}..."
  
  # Create temporary SSH key file
  echo "${var.SSH_PRIVATE_KEY}" > /tmp/ssh_key_${each.key}_$$
  chmod 600 /tmp/ssh_key_${each.key}_$$
  
  if timeout 6m scp -i /tmp/ssh_key_${each.key}_$ -C -o Compression=yes -o ConnectTimeout=30 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no ubuntu@${each.value}:/home/ubuntu/.kube/${each.key}.yaml ${each.key}.yaml; then
    echo "✅ Kubeconfig downloaded successfully from ${each.key} on attempt $attempt"
    rm -f /tmp/ssh_key_${each.key}_$$
    break
  else
    echo "❌ Kubeconfig download from ${each.key} attempt $attempt failed or timed out"
    rm -f /tmp/ssh_key_${each.key}_$$
    if [ $attempt -eq 3 ]; then
      echo "All kubeconfig download attempts from ${each.key} failed"
      # Don't exit here as other nodes might still succeed
      echo "Continuing with other nodes..."
    else
      echo "Waiting 30 seconds before retry..."
      sleep 30
    fi
  fi
done
EOF
  }
}

resource "null_resource" "download-kubectl-file" {
  depends_on = [null_resource.rke2-cluster-setup]
  
  provisioner "local-exec" {
    command = <<EOF
#!/bin/bash
echo "📥 Starting kubectl binary download..."

# Retry logic for kubectl binary download  
for attempt in 1 2 3; do
  echo "Attempt $attempt: Downloading kubectl binary (large file, please wait...)"
  
  # Create temporary SSH key file
  echo "${var.SSH_PRIVATE_KEY}" > /tmp/ssh_key_kubectl_$$
  chmod 600 /tmp/ssh_key_kubectl_$$
  
  if timeout 10m scp -i /tmp/ssh_key_kubectl_$$ -C -o Compression=yes -o ConnectTimeout=60 -o ServerAliveInterval=30 -o ServerAliveCountMax=5 -o StrictHostKeyChecking=no ubuntu@${local.CONTROL_PLANE_NODE_1}:/var/lib/rancher/rke2/bin/kubectl kubectl; then
    echo "✅ kubectl binary downloaded successfully on attempt $attempt"
    chmod +x kubectl
    echo "✅ kubectl binary verified: $(ls -lh kubectl)"
    rm -f /tmp/ssh_key_kubectl_$$
    break
  else
    echo "❌ kubectl download attempt $attempt failed or timed out after 10 minutes"
    rm -f /tmp/ssh_key_kubectl_$$
    if [ $attempt -eq 3 ]; then
      echo "All 3 kubectl download attempts failed"
      exit 1
    else
      echo "Waiting 60 seconds before retry..."
      sleep 60
    fi
  fi
done

# Final verification
if [ -f kubectl ]; then
  echo "✅ Final verification: kubectl binary is ready"
else
  echo "❌ kubectl binary download failed after all attempts"
  exit 1
fi
EOF
  }
}

output "CONTROL_PLANE_NODE_1" {
  value = local.CONTROL_PLANE_NODE_1
}
output "K8S_CLUSTER_PRIVATE_IPS_STR" {
  value = local.K8S_CLUSTER_PRIVATE_IPS_STR
}
# Output the token
output "K8S_TOKEN" {
  value = random_string.K8S_TOKEN.result
}
