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
resource "null_resource" "rke2_ansible_installation" {
  depends_on = [
    local_file.ssh_private_key,
    local_file.ansible_inventory
  ]
  
  triggers = {
    cluster_ips_hash  = md5(local.K8S_CLUSTER_PRIVATE_IPS_STR)
    inventory_hash    = local_file.ansible_inventory.content_md5
    ssh_key_hash     = local_file.ssh_private_key.content_md5
  }

  provisioner "local-exec" {
    command = "${path.module}/ansible/run-ansible.sh '${path.module}/ansible' 'inventory.yml' 'ssh_key' 'rke2-playbook.yml'"
    
    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "False"
      ANSIBLE_SSH_RETRIES      = "3"
      ANSIBLE_TIMEOUT          = "30"
      INSTALL_RKE2_VERSION     = var.RKE2_VERSION
    }
  }

  # Clean up sensitive files after execution
  provisioner "local-exec" {
    when    = destroy
    command = "rm -f ${path.module}/ansible/ssh_key"
  }
}

# Download kubeconfig files from cluster nodes using Ansible
resource "null_resource" "download_kubeconfig_files" {
  depends_on = [null_resource.rke2_ansible_installation]
  
  triggers = {
    cluster_ready = null_resource.rke2_ansible_installation.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      cd ${path.module}/ansible
      
      # Download kubeconfig files from all nodes to terraform implementations directory
      # Use absolute path resolution to find the terraform working directory
      KUBECONFIG_DEST="$(cd ../../../../implementations/aws/infra && pwd)"
      echo "Downloading kubeconfig files to: $KUBECONFIG_DEST"
      
      ansible rke2_cluster -i inventory.yml \
        -u ubuntu \
        --private-key=ssh_key \
        --ssh-common-args='-o StrictHostKeyChecking=no' \
        -m fetch \
        -a "src=/home/ubuntu/.kube/{{ inventory_hostname }}.yaml dest=$KUBECONFIG_DEST/ flat=yes" \
        || echo "Some kubeconfig downloads may have failed - this is expected for worker nodes"
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
  value = "${path.module}/ansible/primary-kubeconfig.yaml"
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
