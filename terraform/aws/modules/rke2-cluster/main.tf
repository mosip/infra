variable "K8S_CLUSTER_PUBLIC_IPS" { type = map(string) }
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

locals {
  CONTROL_PLANE_NODE_1        = element([for key, value in var.K8S_CLUSTER_PRIVATE_IPS : value if length(regexall(".*CONTROL-PLANE-NODE-1", key)) > 0], 0)
  K8S_CLUSTER_PRIVATE_IPS_STR = join(",", [for key, value in var.K8S_CLUSTER_PRIVATE_IPS : "${key}=${value}"])

  RKE_CONFIG = {
    ENV_VAR_FILE                = "/etc/environment"
    CONTROL_PLANE_NODE_1        = local.CONTROL_PLANE_NODE_1
    WORK_DIR                    = "/home/ubuntu/"
    RKE2_CONFIG_DIR             = "/etc/rancher/rke2"
    INSTALL_RKE2_VERSION        = "v1.28.9+rke2r1"
    K8S_INFRA_REPO_URL          = var.K8S_INFRA_REPO_URL
    K8S_INFRA_BRANCH            = var.K8S_INFRA_BRANCH
    RKE2_LOCATION               = "/home/ubuntu/k8s-infra/rke2"
    K8S_CLUSTER_PRIVATE_IPS_STR = local.K8S_CLUSTER_PRIVATE_IPS_STR
    RANCHER_IMPORT_URL          = var.RANCHER_IMPORT_URL
  }
  # Filter out CONTROL_PLANE_NODE_1 from K8S_CLUSTER_PUBLIC_IPS
  K8S_CLUSTER_PUBLIC_IPS_EXCEPT_CONTROL_PLANE_NODE_1 = {
    for key, value in var.K8S_CLUSTER_PUBLIC_IPS : key => value if value != local.CONTROL_PLANE_NODE_1
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
  triggers = {
    # node_count_or_hash = module.ec2-resource-creation.node_count
    # or if you used hash:
    node_hash = md5(local.K8S_CLUSTER_PRIVATE_IPS_STR)
  }
  connection {
    type        = "ssh"
    host        = local.CONTROL_PLANE_NODE_1
    user        = "ubuntu"            # Change based on the AMI used
    private_key = var.SSH_PRIVATE_KEY # content of your private key

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
  depends_on = [null_resource.rke2-primary-cluster-setup]
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

resource "null_resource" "rancher-import" {
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
        "sleep 180",
        "$RANCHER_IMPORT_URL",
        "kubectl -n cattle-system patch deployment cattle-cluster-agent -p '{\"spec\": {\"template\": {\"spec\": {\"dnsPolicy\": \"Default\"}}}}'",
        "sleep 300",
        "kubectl -n cattle-system rollout status deploy",
        "sleep 100"
      ]
    )
  }
}

output "K8S_CLUSTER_PUBLIC_IPS_EXCEPT_CONTROL_PLANE_NODE_1" {
  value = local.K8S_CLUSTER_PUBLIC_IPS_EXCEPT_CONTROL_PLANE_NODE_1
}
output "CONTROL_PLANE_NODE_1" {
  value = local.CONTROL_PLANE_NODE_1
}
output "K8S_CLUSTER_PRIVATE_IPS_STR" {
  value = local.K8S_CLUSTER_PRIVATE_IPS_STR
}
