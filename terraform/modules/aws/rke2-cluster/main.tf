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

variable "RKE2_VERSION" {
  description = "RKE2 version to install"
  type        = string
  default     = "v1.32.8+rke2r1"
}

variable "CLUSTER_NAME" {
  description = "Name of the cluster for node naming"
  type        = string
}

variable "ENABLE_RANCHER_IMPORT" {
  description = "Enable Rancher import after cluster setup"
  type        = bool
  default     = false
}

variable "RANCHER_IMPORT_URL" {
  description = "Rancher import URL for kubectl apply"
  type        = string

  validation {
    condition     = can(regex("^\"kubectl apply -f https://rancher\\.mosip\\.net/v3/import/[a-zA-Z0-9_\\-]+\\.yaml\"$", var.RANCHER_IMPORT_URL))
    error_message = "The RANCHER_IMPORT_URL must be in the format: '\"kubectl apply -f https://rancher.mosip.net/v3/import/<ID>.yaml\"'"
  }
}
# Token generation handled by ansible for better security and distribution
# Ansible generates token once on primary node and distributes to all subsequent nodes

locals {
  CONTROL_PLANE_NODE_1        = element([for key, value in var.K8S_CLUSTER_PRIVATE_IPS : value if length(regexall(".*CONTROL-PLANE-NODE-1", key)) > 0], 0)
  K8S_CLUSTER_PRIVATE_IPS_STR = join(",", [for key, value in var.K8S_CLUSTER_PRIVATE_IPS : "${key}=${value}"])

  # Base configuration that's always included
  base_config = {
    ENV_VAR_FILE                = "/etc/environment"
    CONTROL_PLANE_NODE_1        = local.CONTROL_PLANE_NODE_1
    WORK_DIR                    = "/home/ubuntu/"
    RKE2_CONFIG_DIR             = "/etc/rancher/rke2"
    INSTALL_RKE2_VERSION        = var.RKE2_VERSION
    K8S_INFRA_REPO_URL          = var.K8S_INFRA_REPO_URL
    K8S_INFRA_BRANCH            = var.K8S_INFRA_BRANCH
    RKE2_LOCATION               = "/home/ubuntu/k8s-infra/k8-cluster/on-prem/rke2/"
    K8S_CLUSTER_PRIVATE_IPS_STR = local.K8S_CLUSTER_PRIVATE_IPS_STR
    CLUSTER_NAME                = var.CLUSTER_NAME
    ENABLE_RANCHER_IMPORT       = var.ENABLE_RANCHER_IMPORT ? "true" : "false"
  }

  # Conditionally include Rancher URL only if import is enabled
  rancher_config = var.ENABLE_RANCHER_IMPORT ? {
    RANCHER_IMPORT_URL = var.RANCHER_IMPORT_URL
  } : {}

  # Merge base config with conditional rancher config
  RKE_CONFIG = merge(local.base_config, local.rancher_config)

  # Additional configuration variables
  datetime = formatdate("2006-01-02_15-04-05", timestamp())
  backup_command = [
    "sudo cp ${local.RKE_CONFIG.ENV_VAR_FILE} /tmp/environment-bkp-${local.datetime}"
  ]

  update_commands = [
    for key, value in local.RKE_CONFIG :
    "sudo sed -i \"/^${key}=/d\" ${local.RKE_CONFIG.ENV_VAR_FILE} && echo '${key}=${value}' | sudo tee -a ${local.RKE_CONFIG.ENV_VAR_FILE}"
  ]

  k8s_env_vars = concat(local.backup_command, local.update_commands)
}

# Create SSH private key file for Ansible
resource "local_file" "ssh_private_key" {
  content         = var.SSH_PRIVATE_KEY
  filename        = "${path.module}/ansible/ssh_key"
  file_permission = "0600"
}

# Generate Ansible inventory from Terraform data
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/ansible/inventory.yml.tpl", {
    cluster_name         = var.CLUSTER_NAME               # Using actual cluster name
    cluster_env_domain   = "mosip.local"                  # You can make this a variable
    k8s_infra_repo_url   = var.K8S_INFRA_REPO_URL
    k8s_infra_branch     = var.K8S_INFRA_BRANCH
    install_rke2_version = var.RKE2_VERSION
    enable_rancher_import = var.ENABLE_RANCHER_IMPORT
    rancher_import_url   = var.ENABLE_RANCHER_IMPORT ? var.RANCHER_IMPORT_URL : ""
    
    # Separate IPs by node type with explicit primary selection
    # Sort by key name to ensure CONTROL-PLANE-NODE-1 is always primary
    control_plane_ips = [
      for key in sort([
        for k, v in var.K8S_CLUSTER_PRIVATE_IPS : k 
        if length(regexall(".*CONTROL-PLANE-NODE.*", k)) > 0
      ]) : var.K8S_CLUSTER_PRIVATE_IPS[key]
    ]
    etcd_ips = [
      for key, value in var.K8S_CLUSTER_PRIVATE_IPS : value 
      if length(regexall(".*ETCD-NODE.*", key)) > 0
    ]
    worker_ips = [
      for key, value in var.K8S_CLUSTER_PRIVATE_IPS : value 
      if length(regexall(".*WORKER-NODE.*", key)) > 0
    ]
  })
  filename = "${path.module}/ansible/inventory.yml"
}

# Run Ansible playbook to install RKE2 cluster
# Note: Playbook now has built-in idempotency checks - no need for Terraform conditionals
resource "null_resource" "rke2_ansible_installation" {
  depends_on = [
    local_file.ssh_private_key,
    local_file.ansible_inventory
  ]

  # Trigger re-run when cluster composition changes
  triggers = {
    cluster_nodes = join(",", [for k, v in var.K8S_CLUSTER_PRIVATE_IPS : "${k}=${v}"])
    inventory_content = local_file.ansible_inventory.content_sha256
    rke2_version = var.RKE2_VERSION
  }

  # Ensure Ansible script has execute permissions on GitHub Actions runners
  provisioner "local-exec" {
    command = "chmod +x ${path.module}/ansible/run-ansible.sh"
    working_dir = path.module
  }

  provisioner "local-exec" {
    command = "./ansible/run-ansible.sh '${path.module}/ansible' 'inventory.yml' 'ssh_key' 'rke2-playbook.yml'"
    working_dir = path.module
    
    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      ANSIBLE_SSH_RETRIES      = "3"
      ANSIBLE_TIMEOUT          = "30"
      INSTALL_RKE2_VERSION     = var.RKE2_VERSION
      PATH                     = "${pathexpand("~/.local/bin")}:${join(":", ["/usr/local/bin", "/usr/bin", "/bin"])}"
    }
  }

  # Clean up sensitive files after execution
  provisioner "local-exec" {
    when    = destroy
    command = "rm -f ./ansible/ssh_key"
    working_dir = path.module
  }
}

# Download kubeconfig files from cluster nodes using Ansible
resource "null_resource" "download_kubeconfig_files" {
  depends_on = [
    local_file.ssh_private_key,
    local_file.ansible_inventory,
    null_resource.rke2_ansible_installation
  ]
  
  # Download kubeconfig files after cluster installation
  triggers = {
    cluster_ready = null_resource.rke2_ansible_installation.id
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/ansible"
    
    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      PATH                     = "${pathexpand("~/.local/bin")}:${join(":", ["/usr/local/bin", "/usr/bin", "/bin"])}"
    }
    
    command = <<-EOT
      # First ensure kubectl is available and kubeconfig files are created
      echo "Setting up kubectl and kubeconfig files on nodes..."
      
      # Create kubectl symlinks on all nodes
      ansible rke2_cluster -i inventory.yml \
        -u ubuntu \
        --private-key=ssh_key \
        --ssh-common-args='-o StrictHostKeyChecking=no' \
        -b -m file \
        -a "src=/var/lib/rancher/rke2/bin/kubectl dest=/usr/local/bin/kubectl state=link force=yes" \
        || echo "kubectl setup may have failed on some nodes"
      
      # Create .kube directories on control plane nodes
      ansible control_plane -i inventory.yml \
        -u ubuntu \
        --private-key=ssh_key \
        --ssh-common-args='-o StrictHostKeyChecking=no' \
        -b -m file \
        -a "path=/home/ubuntu/.kube state=directory owner=ubuntu group=ubuntu mode=0755" \
        || echo "kube directory creation may have failed"
      
      # Generate kubeconfig files on control plane nodes
      ansible control_plane -i inventory.yml \
        -u ubuntu \
        --private-key=ssh_key \
        --ssh-common-args='-o StrictHostKeyChecking=no' \
        -b -m shell \
        -a "NODE_IP=\$(hostname -I | awk '{print \$1}'); cp /etc/rancher/rke2/rke2.yaml /home/ubuntu/.kube/{{ inventory_hostname }}.yaml && sed -i \"s/127.0.0.1/\$NODE_IP/g\" /home/ubuntu/.kube/{{ inventory_hostname }}.yaml && sed -i 's/default/${var.CLUSTER_NAME}/g' /home/ubuntu/.kube/{{ inventory_hostname }}.yaml && chown ubuntu:ubuntu /home/ubuntu/.kube/{{ inventory_hostname }}.yaml" \
        || echo "kubeconfig generation may have failed"
      
      # Download kubeconfig files from all nodes to current ansible directory
      echo "Downloading kubeconfig files to current directory..."
      
      ansible rke2_cluster -i inventory.yml \
        -u ubuntu \
        --private-key=ssh_key \
        --ssh-common-args='-o StrictHostKeyChecking=no' \
        -m fetch \
        -a "src=/home/ubuntu/.kube/{{ inventory_hostname }}.yaml dest=./ flat=yes" \
        || echo "Some kubeconfig downloads may have failed - this is expected for worker nodes"
    EOT
  }
}

# Copy primary kubeconfig to terraform working directory and user's .kube directory
resource "null_resource" "setup_kubeconfig" {
  depends_on = [null_resource.download_kubeconfig_files]
  
  triggers = {
    kubeconfig_ready = null_resource.download_kubeconfig_files.id
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/ansible"
    
    command = <<-EOT
      # Find the primary control plane kubeconfig file (first in sorted order)
      PRIMARY_CONTROL_PLANE_KEY=$(echo '${jsonencode([
        for key in sort([
          for k, v in var.K8S_CLUSTER_PRIVATE_IPS : k 
          if length(regexall(".*CONTROL-PLANE-NODE.*", k)) > 0
        ]) : key
      ])}' | jq -r '.[0]')
      
      PRIMARY_KUBECONFIG="$PRIMARY_CONTROL_PLANE_KEY.yaml"
      
      if [ -f "$PRIMARY_KUBECONFIG" ]; then
        echo "Setting up kubeconfig for cluster ${var.CLUSTER_NAME}..."
        echo "Primary control plane: $PRIMARY_CONTROL_PLANE_KEY"
        
        # Copy to terraform working directory (where terraform apply was run) - preserve original filename
        # From ansible/ directory, need to go up 4 levels to reach implementations/aws/infra/
        cp "$PRIMARY_KUBECONFIG" "../../../../implementations/aws/infra/$PRIMARY_KUBECONFIG"
        
        # Also create a simplified symlink for convenience
        ln -sf "$PRIMARY_KUBECONFIG" "../../../../implementations/aws/infra/${var.CLUSTER_NAME}.yaml"
        
        # Create user's .kube directory if it doesn't exist
        mkdir -p ~/.kube
        
        # Copy to user's .kube directory - preserve original filename
        cp "$PRIMARY_KUBECONFIG" ~/.kube/$PRIMARY_KUBECONFIG
        
        # Also create a simplified symlink for convenience
        ln -sf "$PRIMARY_KUBECONFIG" ~/.kube/${var.CLUSTER_NAME}.yaml
        
        # Update current kubectl context to the new cluster
        export KUBECONFIG=~/.kube/${var.CLUSTER_NAME}.yaml
        
        echo "Kubeconfig files created:"
        echo "  - Terraform directory: ../../../../implementations/aws/infra/$PRIMARY_KUBECONFIG"
        echo "  - Terraform symlink: ../../../../implementations/aws/infra/${var.CLUSTER_NAME}.yaml"
        echo "  - User kube directory: ~/.kube/$PRIMARY_KUBECONFIG"
        echo "  - User symlink: ~/.kube/${var.CLUSTER_NAME}.yaml"
        echo ""
        echo "To use this cluster, run either:"
        echo "  export KUBECONFIG=~/.kube/$PRIMARY_KUBECONFIG"
        echo "  # OR"
        echo "  export KUBECONFIG=~/.kube/${var.CLUSTER_NAME}.yaml"
        echo "  kubectl get nodes"
      else
        echo "Warning: Primary kubeconfig file not found: $PRIMARY_KUBECONFIG"
        echo "Available files:"
        ls -la *.yaml || echo "No kubeconfig files found"
      fi
    EOT
  }
}

# Removed primary kubeconfig download - keeping only node-specific kubeconfigs

output "CONTROL_PLANE_NODE_1" {
  value = local.CONTROL_PLANE_NODE_1
}

output "K8S_CLUSTER_PRIVATE_IPS_STR" {
  value = local.K8S_CLUSTER_PRIVATE_IPS_STR
}

# Token generation and management handled by ansible
# No terraform output needed as ansible manages token internally

output "ANSIBLE_INVENTORY_PATH" {
  value = "${path.module}/ansible/inventory.yml"
}

output "PRIMARY_KUBECONFIG_PATH" {
  value = "${path.module}/../../../../implementations/aws/infra/${sort([
    for k, v in var.K8S_CLUSTER_PRIVATE_IPS : k 
    if length(regexall(".*CONTROL-PLANE-NODE.*", k)) > 0
  ])[0]}.yaml"
  description = "Path to the primary kubeconfig file in the terraform working directory (original filename)"
}

output "PRIMARY_KUBECONFIG_SYMLINK" {
  value = "${path.module}/../../../../implementations/aws/infra/${var.CLUSTER_NAME}.yaml"
  description = "Path to the kubeconfig symlink in the terraform working directory (simplified name)"
}

output "USER_KUBECONFIG_PATH" {
  value = "~/.kube/${var.CLUSTER_NAME}.yaml"
  description = "Path to the kubeconfig file in user's .kube directory"
}

output "KUBECONFIG_SETUP_COMMAND" {
  value = "export KUBECONFIG=~/.kube/${var.CLUSTER_NAME}.yaml"
  description = "Command to set the kubectl context to this cluster"
}

output "PRIMARY_CONTROL_PLANE_IP" {
  value = length([
    for key in sort([
      for k, v in var.K8S_CLUSTER_PRIVATE_IPS : k 
      if length(regexall(".*CONTROL-PLANE-NODE.*", k)) > 0
    ]) : var.K8S_CLUSTER_PRIVATE_IPS[key]
  ]) > 0 ? [
    for key in sort([
      for k, v in var.K8S_CLUSTER_PRIVATE_IPS : k 
      if length(regexall(".*CONTROL-PLANE-NODE.*", k)) > 0
    ]) : var.K8S_CLUSTER_PRIVATE_IPS[key]
  ][0] : "No control plane nodes found"
  description = "IP address of the primary control plane node (first in sorted order)"
}

output "CONTROL_PLANE_SELECTION_ORDER" {
  value = [
    for key in sort([
      for k, v in var.K8S_CLUSTER_PRIVATE_IPS : k 
      if length(regexall(".*CONTROL-PLANE-NODE.*", k)) > 0
    ]) : "${key} -> ${var.K8S_CLUSTER_PRIVATE_IPS[key]}"
  ]
  description = "Shows the order of control plane node selection (first becomes primary)"
}
