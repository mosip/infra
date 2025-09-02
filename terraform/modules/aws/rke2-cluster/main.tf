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
  backup_command = [
    "sudo cp ${local.RKE_CONFIG.ENV_VAR_FILE} /tmp/environment-bkp-${local.datetime}"
  ]

  update_commands = [
    for key, value in local.RKE_CONFIG :
    "sudo sed -i \"/^${key}=/d\" ${local.RKE_CONFIG.ENV_VAR_FILE} && echo '${key}=${value}' | sudo tee -a ${local.RKE_CONFIG.ENV_VAR_FILE}"
  ]

  k8s_env_vars = concat(local.backup_command, local.update_commands)
}

resource "null_resource" "rke2-primary-cluster-setup" {
  #   triggers = {
  #     node_hash = md5(local.K8S_CLUSTER_PRIVATE_IPS_STR)
  #   }
  
  connection {
    type        = "ssh"
    host        = local.CONTROL_PLANE_NODE_1
    user        = "ubuntu"            # Change based on the AMI used
    private_key = var.SSH_PRIVATE_KEY # content of your private key
    timeout     = "10m"
  }
  provisioner "file" {
    source      = "${path.module}/rke2-setup.sh"
    destination = "/tmp/rke2-setup.sh"
  }
  provisioner "remote-exec" {
    inline = concat(
      local.k8s_env_vars,
      [
        "chmod +x /tmp/rke2-setup.sh",
        "timeout 10m sudo bash /tmp/rke2-setup.sh || (echo 'First attempt failed, retrying in 30 seconds...' && sleep 30 && timeout 10m sudo bash /tmp/rke2-setup.sh)"
      ]
    )
  }
}

resource "null_resource" "rke2-additional-control-plane-setup" {
  depends_on = [null_resource.rke2-primary-cluster-setup]
  for_each   = local.K8S_ADDITIONAL_CONTROL_PLANE_NODES
  triggers = {
    node_hash   = md5(local.K8S_CLUSTER_PRIVATE_IPS_STR)
    script_hash = filemd5("${path.module}/rke2-setup.sh")
  }
  connection {
    type        = "ssh"
    host        = each.value
    user        = "ubuntu"            # Change based on the AMI used
    private_key = var.SSH_PRIVATE_KEY # content of your private key
    timeout     = "10m"
  }
  provisioner "file" {
    source      = "${path.module}/rke2-setup.sh"
    destination = "/tmp/rke2-setup.sh"
  }
  provisioner "remote-exec" {
    inline = concat(
      local.k8s_env_vars,
      [
        "sudo bash /tmp/rke2-setup.sh"
      ]
    )
  }
}

resource "null_resource" "rke2-cluster-setup" {
  depends_on = [
    null_resource.rke2-primary-cluster-setup,
    null_resource.rke2-additional-control-plane-setup
  ]
  for_each   = local.K8S_CLUSTER_PRIVATE_IPS_EXCEPT_CONTROL_PLANE_NODES
  triggers = {
    # node_count_or_hash = module.ec2-resource-creation.node_count
    # or if you used hash:
    node_hash   = md5(local.K8S_CLUSTER_PRIVATE_IPS_STR)
    script_hash = filemd5("${path.module}/rke2-setup.sh")
  }
  connection {
    type        = "ssh"
    host        = each.value
    user        = "ubuntu"            # Change based on the AMI used
    private_key = var.SSH_PRIVATE_KEY # content of your private key
    timeout     = "10m"
  }
  provisioner "file" {
    source      = "${path.module}/rke2-setup.sh"
    destination = "/tmp/rke2-setup.sh"
  }
  provisioner "remote-exec" {
    inline = concat(
      local.k8s_env_vars,
      [
        "sudo bash /tmp/rke2-setup.sh"
      ]
    )
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
  connection {
    type        = "ssh"
    host        = local.CONTROL_PLANE_NODE_1
    user        = "ubuntu"            # Change based on the AMI used
    private_key = var.SSH_PRIVATE_KEY # content of your private key
    timeout     = "10m"
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
  depends_on = [null_resource.rke2-cluster-setup]
  for_each   = var.K8S_CLUSTER_PRIVATE_IPS
  triggers = {
    # node_count_or_hash = module.ec2-resource-creation.node_count
    # or if you used hash:
    node_hash = md5(local.K8S_CLUSTER_PRIVATE_IPS_STR)
  }
  connection {
    type        = "ssh"
    host        = each.value
    user        = "ubuntu"            # Change based on the AMI used
    private_key = var.SSH_PRIVATE_KEY # content of your private key
    timeout     = "10m"
  }
  provisioner "file" {
    source      = "${path.module}/rke2-setup.sh"
    destination = "/tmp/rke2-setup.sh"
  }
  provisioner "local-exec" {
    command = <<EOF
echo "${var.SSH_PRIVATE_KEY}" > ${each.key}-sshkey
chmod 400 ${each.key}-sshkey
scp -i ${each.key}-sshkey ubuntu@${each.value}:/home/ubuntu/.kube/${each.key}.yaml ${each.key}.yaml

# Clean up the temporary private key file
rm ${each.key}-sshkey

EOF
  }
}

resource "null_resource" "download-kubectl-file" {
  depends_on = [null_resource.rke2-cluster-setup]
  connection {
    type        = "ssh"
    host        = local.CONTROL_PLANE_NODE_1
    user        = "ubuntu"            # Change based on the AMI used
    private_key = var.SSH_PRIVATE_KEY # content of your private key
    timeout     = "10m"
  }
  provisioner "file" {
    source      = "${path.module}/rke2-setup.sh"
    destination = "/tmp/rke2-setup.sh"
  }
  provisioner "local-exec" {
    command = <<EOF
echo "${var.SSH_PRIVATE_KEY}" > ${local.CONTROL_PLANE_NODE_1}-sshkey
chmod 400 ${local.CONTROL_PLANE_NODE_1}-sshkey
scp -i ${local.CONTROL_PLANE_NODE_1}-sshkey ubuntu@${local.CONTROL_PLANE_NODE_1}:/var/lib/rancher/rke2/bin/kubectl kubectl
chmod +x kubectl

# Clean up the temporary private key file
rm ${local.CONTROL_PLANE_NODE_1}-sshkey

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
