variable "K8S_CLUSTER_PRIVATE_IPS" { type = map(string) }
variable "SSH_PRIVATE_KEY" { type = string }
variable "CLUSTER_ENV_DOMAIN" { type = string }
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

variable "enable_rancher_import" {
  description = "Set to true to enable Rancher import"
  type        = bool
  default     = false
}

# Production SSH optimization variables
variable "bastion_host" {
  description = "Bastion host IP for SSH tunneling (optional - improves multi-AZ performance)"
  type        = string
  default     = ""
}

variable "use_bastion" {
  description = "Enable bastion host for SSH connections (recommended for multi-AZ)"
  type        = bool
  default     = false
}

variable "use_cloud_init" {
  description = "Use Cloud-Init for RKE2 setup instead of SSH (eliminates SSH issues completely)"
  type        = bool
  default     = false
}

variable "cloud_init_complete_signal" {
  description = "Signal file that indicates cloud-init RKE2 setup is complete"
  type        = string
  default     = "/tmp/rke2-cloud-init-complete"
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
  CONTROL_PLANE_NODE_1        = element([for key, value in var.K8S_CLUSTER_PRIVATE_IPS : value if length(regexall(".*CONTROL-PLANE-NODE-1", key)) > 0], 0)
  K8S_CLUSTER_PRIVATE_IPS_STR = join(",", [for key, value in var.K8S_CLUSTER_PRIVATE_IPS : "${key}=${value}"])

  # Base RKE configuration
  RKE_CONFIG_BASE = {
    ENV_VAR_FILE                = "/etc/environment"
    CONTROL_PLANE_NODE_1        = local.CONTROL_PLANE_NODE_1
    WORK_DIR                    = "/home/ubuntu/"
    RKE2_CONFIG_DIR             = "/etc/rancher/rke2"
    INSTALL_RKE2_VERSION        = "v1.28.9+rke2r1"
    K8S_INFRA_REPO_URL          = var.K8S_INFRA_REPO_URL
    K8S_INFRA_BRANCH            = var.K8S_INFRA_BRANCH
    RKE2_LOCATION               = "/home/ubuntu/k8s-infra/k8-cluster/on-prem/rke2/"
    K8S_CLUSTER_PRIVATE_IPS_STR = local.K8S_CLUSTER_PRIVATE_IPS_STR
    K8S_TOKEN                   = random_string.K8S_TOKEN.result
    CLUSTER_DOMAIN              = var.CLUSTER_ENV_DOMAIN
  }

  # Conditional RKE configuration with Rancher import URL only when enabled
  RKE_CONFIG = var.enable_rancher_import ? merge(local.RKE_CONFIG_BASE, {
    RANCHER_IMPORT_URL = var.RANCHER_IMPORT_URL
  }) : local.RKE_CONFIG_BASE
  # Filter out CONTROL_PLANE_NODE_1 from K8S_CLUSTER_PUBLIC_IPS
  #   K8S_CLUSTER_PRIVATE_IPS_EXCEPT_CONTROL_PLANE_NODE_1 = {
  #     for key, value in var.K8S_CLUSTER_PRIVATE_IPS : key => value if value != local.CONTROL_PLANE_NODE_1
  #   }

  datetime = formatdate("2006-01-02_15-04-05", timestamp())
  backup_command = [
    "sudo cp ${local.RKE_CONFIG.ENV_VAR_FILE} /tmp/environment-bkp-${local.datetime}"
  ]

  update_commands = [
    for key, value in local.RKE_CONFIG :
    "sudo sed -i \"/^${key}=/d\" ${local.RKE_CONFIG.ENV_VAR_FILE} && echo '${key}=${value}' | sudo tee -a ${local.RKE_CONFIG.ENV_VAR_FILE}"
  ]

  k8s_env_vars = concat(local.backup_command, local.update_commands)

  # Production SSH configuration optimizations
  ssh_config_opts = [
    "ServerAliveInterval=60",
    "ServerAliveCountMax=3",
    "TCPKeepAlive=yes",
    "ControlMaster=auto",
    "ControlPath=/tmp/ssh-%h-%p-%r",
    "ControlPersist=300"
  ]

  # Optimized SSH connection configuration based on options
  ssh_connection_base = {
    type            = "ssh"
    user            = "ubuntu"
    private_key     = var.SSH_PRIVATE_KEY
    agent           = false
    host_key        = null
    port            = 22
    target_platform = "unix"
    script_path     = "/tmp/terraform_%RAND%.sh"
  }

  ssh_connection_optimized = var.use_bastion ? merge(local.ssh_connection_base, {
    timeout             = "15m" # Faster with bastion
    bastion_host        = var.bastion_host
    bastion_user        = "ubuntu"
    bastion_private_key = var.SSH_PRIVATE_KEY
    bastion_port        = 22
    }) : merge(local.ssh_connection_base, {
    timeout = "45m" # Extended for direct VPN connections
  })

  # Cloud-Init template for RKE2 setup
  cloud_init_template = var.use_cloud_init ? templatefile("${path.module}/rke2-cloud-init.yml", {
    k8s_infra_repo_url          = var.K8S_INFRA_REPO_URL
    k8s_infra_branch            = var.K8S_INFRA_BRANCH
    k8s_token                   = random_string.K8S_TOKEN.result
    cluster_domain              = var.CLUSTER_ENV_DOMAIN
    control_plane_node_1        = local.CONTROL_PLANE_NODE_1
    k8s_cluster_private_ips_str = local.K8S_CLUSTER_PRIVATE_IPS_STR
    node_name                   = "PLACEHOLDER" # Will be replaced per node
    internal_ip                 = "PLACEHOLDER" # Will be replaced per node
  }) : null
}

# Cloud-Init alternative: Wait for RKE2 setup completion (No SSH required)
resource "null_resource" "rke2-cloud-init-wait" {
  count = var.use_cloud_init ? 1 : 0

  # Use AWS CLI to check if cloud-init completed
  provisioner "local-exec" {
    command = <<EOF
      echo "Waiting for RKE2 Cloud-Init setup to complete on Control Plane Node..."
      INSTANCE_ID=$(aws ec2 describe-instances \
        --filters "Name=private-ip-address,Values=${local.CONTROL_PLANE_NODE_1}" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text)
      
      echo "Instance ID: $INSTANCE_ID"
      
      # Wait for cloud-init to complete (max 30 minutes)
      for i in {1..60}; do
        echo "Check $i/60: Waiting for cloud-init completion..."
        
        # Check if cloud-init is done
        STATUS=$(aws ssm send-command \
          --instance-ids $INSTANCE_ID \
          --document-name "AWS-RunShellScript" \
          --parameters 'commands=["cloud-init status"]' \
          --query "Command.CommandId" \
          --output text 2>/dev/null || echo "failed")
        
        if [ "$STATUS" != "failed" ]; then
          sleep 10
          RESULT=$(aws ssm get-command-invocation \
            --command-id $STATUS \
            --instance-id $INSTANCE_ID \
            --query "StandardOutputContent" \
            --output text 2>/dev/null || echo "running")
          
          if [[ "$RESULT" == *"done"* ]]; then
            echo "✓ Cloud-Init completed successfully"
            
            # Check if RKE2 setup completed
            RKE2_CHECK=$(aws ssm send-command \
              --instance-ids $INSTANCE_ID \
              --document-name "AWS-RunShellScript" \
              --parameters 'commands=["systemctl is-active rke2-server || systemctl is-active rke2-agent"]' \
              --query "Command.CommandId" \
              --output text 2>/dev/null || echo "failed")
            
            if [ "$RKE2_CHECK" != "failed" ]; then
              sleep 5
              RKE2_STATUS=$(aws ssm get-command-invocation \
                --command-id $RKE2_CHECK \
                --instance-id $INSTANCE_ID \
                --query "StandardOutputContent" \
                --output text 2>/dev/null || echo "inactive")
              
              if [[ "$RKE2_STATUS" == *"active"* ]]; then
                echo "✓ RKE2 service is running"
                break
              fi
            fi
          fi
        fi
        
        if [ $i -eq 60 ]; then
          echo "⚠ Timeout waiting for cloud-init completion"
          echo "Check /var/log/rke2-cloud-init.log on the instance for details"
        fi
        
        sleep 30
      done
EOF
  }
}

resource "null_resource" "rke2-primary-cluster-setup" {
  count = var.use_cloud_init ? 0 : 1 # Skip SSH setup if using cloud-init
  #   triggers = {
  #     node_hash = md5(local.K8S_CLUSTER_PRIVATE_IPS_STR)
  #   }

  # Use optimized SSH connection configuration
  connection {
    host                = local.CONTROL_PLANE_NODE_1
    type                = local.ssh_connection_optimized.type
    user                = local.ssh_connection_optimized.user
    private_key         = local.ssh_connection_optimized.private_key
    timeout             = local.ssh_connection_optimized.timeout
    script_path         = local.ssh_connection_optimized.script_path
    agent               = local.ssh_connection_optimized.agent
    host_key            = local.ssh_connection_optimized.host_key
    port                = local.ssh_connection_optimized.port
    target_platform     = local.ssh_connection_optimized.target_platform
    bastion_host        = try(local.ssh_connection_optimized.bastion_host, null)
    bastion_user        = try(local.ssh_connection_optimized.bastion_user, null)
    bastion_private_key = try(local.ssh_connection_optimized.bastion_private_key, null)
    bastion_port        = try(local.ssh_connection_optimized.bastion_port, null)
  }

  # Pre-flight connectivity check
  provisioner "remote-exec" {
    inline = [
      "echo 'SSH connection established to Control Plane Node 1'",
      "echo 'Node: ${local.CONTROL_PLANE_NODE_1}'",
      "echo 'Timestamp: $(date)'",
      "echo 'Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)'",
      "echo 'Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)'",
      "echo 'Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)'",
      "# Test network connectivity",
      "ping -c 3 8.8.8.8 || echo 'External connectivity check failed'",
      "ping -c 3 github.com || echo 'GitHub connectivity check failed'"
    ]

    # Retry mechanism for connection issues
    on_failure = continue
  }

  # Main provisioning with enhanced error handling
  provisioner "file" {
    source      = "${path.module}/rke2-setup.sh"
    destination = "/tmp/rke2-setup.sh"

    connection {
      type            = "ssh"
      host            = local.CONTROL_PLANE_NODE_1
      user            = "ubuntu"
      private_key     = var.SSH_PRIVATE_KEY
      timeout         = "45m"
      script_path     = "/tmp/terraform_%RAND%.sh"
      agent           = false
      host_key        = null
      port            = 22
      target_platform = "unix"
    }
  }

  provisioner "remote-exec" {
    inline = concat(
      local.k8s_env_vars,
      [
        "echo 'Starting RKE2 setup on Control Plane Node 1'",
        "sudo bash /tmp/rke2-setup.sh"
      ]
    )

    connection {
      type            = "ssh"
      host            = local.CONTROL_PLANE_NODE_1
      user            = "ubuntu"
      private_key     = var.SSH_PRIVATE_KEY
      timeout         = "45m"
      script_path     = "/tmp/terraform_%RAND%.sh"
      agent           = false
      host_key        = null
      port            = 22
      target_platform = "unix"
    }
  }
}

resource "null_resource" "rke2-cluster-setup" {
  depends_on = [null_resource.rke2-primary-cluster-setup]
  for_each   = var.K8S_CLUSTER_PRIVATE_IPS
  triggers = {
    # node_count_or_hash = module.ec2-resource-creation.node_count
    # or if you used hash:
    node_hash   = md5(local.K8S_CLUSTER_PRIVATE_IPS_STR)
    script_hash = filemd5("${path.module}/rke2-setup.sh")
  }

  # Pre-flight connectivity check for each node
  provisioner "remote-exec" {
    inline = [
      "echo 'SSH connection established to ${each.key}'",
      "echo 'Node IP: ${each.value}'",
      "echo 'Timestamp: $(date)'",
      "echo 'Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)'",
      "echo 'Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)'",
      "echo 'Private IP: $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)'",
      "# Test network connectivity",
      "ping -c 2 ${local.CONTROL_PLANE_NODE_1} || echo 'Control plane connectivity check failed'",
      "ping -c 2 github.com || echo 'GitHub connectivity check failed'"
    ]

    connection {
      type            = "ssh"
      host            = each.value
      user            = "ubuntu"
      private_key     = var.SSH_PRIVATE_KEY
      timeout         = "45m"
      script_path     = "/tmp/terraform_%RAND%.sh"
      agent           = false
      host_key        = null
      port            = 22
      target_platform = "unix"
    }

    on_failure = continue
  }

  provisioner "file" {
    source      = "${path.module}/rke2-setup.sh"
    destination = "/tmp/rke2-setup.sh"

    connection {
      type            = "ssh"
      host            = each.value
      user            = "ubuntu"
      private_key     = var.SSH_PRIVATE_KEY
      timeout         = "45m"
      script_path     = "/tmp/terraform_%RAND%.sh"
      agent           = false
      host_key        = null
      port            = 22
      target_platform = "unix"
    }
  }

  provisioner "remote-exec" {
    inline = concat(
      local.k8s_env_vars,
      [
        "echo 'Starting RKE2 setup on ${each.key}'",
        "sudo bash /tmp/rke2-setup.sh"
      ]
    )

    connection {
      type            = "ssh"
      host            = each.value
      user            = "ubuntu"
      private_key     = var.SSH_PRIVATE_KEY
      timeout         = "45m"
      script_path     = "/tmp/terraform_%RAND%.sh"
      agent           = false
      host_key        = null
      port            = 22
      target_platform = "unix"
    }
  }
}

resource "null_resource" "rancher-import" {
  count      = var.enable_rancher_import ? 1 : 0
  depends_on = [null_resource.rke2-primary-cluster-setup]
  connection {
    type        = "ssh"
    host        = local.CONTROL_PLANE_NODE_1
    user        = "ubuntu"            # Change based on the AMI used
    private_key = var.SSH_PRIVATE_KEY # content of your private key
  }
  provisioner "remote-exec" {
    inline = concat(
      [
        "mkdir -p ~/.kube/ ",
        "sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config",
        "sudo chown -R $USER:$USER ~/.kube",
        "sudo cp /var/lib/rancher/rke2/bin/kubectl /bin/kubectl",
        "sudo chmod 400 ~/.kube/config && sudo chmod +x /bin/kubectl",
        "$RANCHER_IMPORT_URL",
        "kubectl -n cattle-system patch deployment cattle-cluster-agent -p '{\"spec\": {\"template\": {\"spec\": {\"dnsPolicy\": \"Default\"}}}}'",
        "sleep 420",
        "kubectl -n cattle-system rollout status deploy",
        "sleep 30"
      ]
    )
  }
}

resource "null_resource" "download-k8s-kubeconfig" {
  depends_on = [null_resource.rke2-cluster-setup, null_resource.rke2-cloud-init-wait]
  # Only download kubeconfig from control plane nodes (they're the only ones that have it)
  for_each = {
    for key, value in var.K8S_CLUSTER_PRIVATE_IPS : key => value 
    if length(regexall(".*CONTROL-PLANE-NODE.*", key)) > 0
  }
  triggers = {
    node_hash = md5(local.K8S_CLUSTER_PRIVATE_IPS_STR)
  }

  provisioner "local-exec" {
    command = <<EOF
# Download kubeconfig files to terraform apply directory (Control Plane nodes only)
if [ "${var.use_cloud_init}" = "true" ]; then
  # Cloud-Init approach: Use AWS CLI to download kubeconfig
  echo "Downloading kubeconfig for ${each.key} via AWS CLI..."
  INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=private-ip-address,Values=${each.value}" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text)

  COMMAND_ID=$(aws ssm send-command \
    --instance-ids $INSTANCE_ID \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo cat /home/ubuntu/.kube/${each.key}.yaml 2>/dev/null || sudo cat /etc/rancher/rke2/rke2.yaml"]' \
    --query "Command.CommandId" \
    --output text)

  sleep 10
  aws ssm get-command-invocation \
    --command-id $COMMAND_ID \
    --instance-id $INSTANCE_ID \
    --query "StandardOutputContent" \
    --output text > ${each.key}.yaml

  echo "✓ Downloaded kubeconfig for ${each.key}"
else
  # SSH approach: Direct SCP download
  echo "Downloading kubeconfig for ${each.key} via SSH..."
  echo "${var.SSH_PRIVATE_KEY}" > ${each.key}-sshkey
  chmod 400 ${each.key}-sshkey
  scp -i ${each.key}-sshkey ubuntu@${each.value}:/home/ubuntu/.kube/${each.key}.yaml ${each.key}.yaml 2>/dev/null || \
  scp -i ${each.key}-sshkey ubuntu@${each.value}:/etc/rancher/rke2/rke2.yaml ${each.key}.yaml

  # Clean up the temporary private key file
  rm ${each.key}-sshkey
  echo "✓ Downloaded kubeconfig for ${each.key}"
fi
EOF
  }
}

resource "null_resource" "download-kubectl-file" {
  depends_on = [null_resource.rke2-cluster-setup, null_resource.rke2-cloud-init-wait]

  provisioner "local-exec" {
    command = <<EOF
# Download kubectl binary to terraform apply directory  
if [ "${var.use_cloud_init}" = "true" ]; then
  # Cloud-Init approach: Download kubectl via AWS CLI
  echo "Downloading kubectl binary via AWS CLI..."
  INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=private-ip-address,Values=${local.CONTROL_PLANE_NODE_1}" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text)

  COMMAND_ID=$(aws ssm send-command \
    --instance-ids $INSTANCE_ID \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo cp /var/lib/rancher/rke2/bin/kubectl /tmp/kubectl && sudo chmod 755 /tmp/kubectl"]' \
    --query "Command.CommandId" \
    --output text)

  sleep 5
  COMMAND_ID2=$(aws ssm send-command \
    --instance-ids $INSTANCE_ID \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["base64 /tmp/kubectl"]' \
    --query "Command.CommandId" \
    --output text)

  sleep 10
  aws ssm get-command-invocation \
    --command-id $COMMAND_ID2 \
    --instance-id $INSTANCE_ID \
    --query "StandardOutputContent" \
    --output text | base64 -d > kubectl

  chmod +x kubectl
  echo "✓ Downloaded kubectl binary"
else
  # SSH approach: Direct SCP download
  echo "Downloading kubectl binary via SSH..."
  echo "${var.SSH_PRIVATE_KEY}" > ${local.CONTROL_PLANE_NODE_1}-sshkey
  chmod 400 ${local.CONTROL_PLANE_NODE_1}-sshkey
  scp -i ${local.CONTROL_PLANE_NODE_1}-sshkey ubuntu@${local.CONTROL_PLANE_NODE_1}:/var/lib/rancher/rke2/bin/kubectl kubectl
  chmod +x kubectl

  # Clean up the temporary private key file
  rm ${local.CONTROL_PLANE_NODE_1}-sshkey
  echo "✓ Downloaded kubectl binary"
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

# Cloud-Init user data for EC2 instances (when use_cloud_init = true)
output "rke2_cloud_init_user_data" {
  description = "Base64 encoded user data for EC2 instances with Cloud-Init RKE2 setup"
  value = var.use_cloud_init ? {
    for node_name, node_ip in var.K8S_CLUSTER_PRIVATE_IPS :
    node_name => base64encode(
      replace(
        replace(
          local.cloud_init_template,
          "node_name: PLACEHOLDER",
          "node_name: ${node_name}"
        ),
        "internal_ip: PLACEHOLDER",
        "internal_ip: ${node_ip}"
      )
    )
  } : {}
}

# Usage instructions
output "setup_instructions" {
  value = var.use_cloud_init ? "Cloud-Init enabled: Add the user_data from 'rke2_cloud_init_user_data' output to your EC2 instances." : (
    var.use_bastion ? "Bastion mode: Set bastion_host variable and use_bastion=true for faster connections." :
    "Direct VPN mode: Using extended timeouts and retry mechanisms."
  )
}
