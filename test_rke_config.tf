terraform {
  required_providers {
    random = {
      source = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

resource "random_string" "K8S_TOKEN" {
  length  = 32
  special = false
}

locals {
  RKE_CONFIG_BASE = {
    ENV_VAR_FILE                = "/etc/environment"
    CONTROL_PLANE_NODE_1        = "10.0.3.47"
    WORK_DIR                    = "/home/ubuntu/"
    RKE2_CONFIG_DIR             = "/etc/rancher/rke2"
    INSTALL_RKE2_VERSION        = "v1.28.9+rke2r1"
    K8S_INFRA_REPO_URL          = "https://github.com/mosip/k8s-infra.git"
    K8S_INFRA_BRANCH            = "develop"
    RKE2_LOCATION               = "/home/ubuntu/k8s-infra/k8-cluster/on-prem/rke2/"
    K8S_CLUSTER_PRIVATE_IPS_STR = "test=10.0.3.47"
    K8S_TOKEN                   = random_string.K8S_TOKEN.result
  }

  # Test with enable_rancher_import = false and rancher_import_url = ""
  enable_rancher_import = false
  rancher_import_url = ""
  
  RKE_CONFIG = local.enable_rancher_import ? merge(local.RKE_CONFIG_BASE, {
    RANCHER_IMPORT_URL = local.rancher_import_url
  }) : local.RKE_CONFIG_BASE

  datetime = formatdate("2006-01-02_15-04-05", timestamp())
  backup_command = [
    "sudo cp ${local.RKE_CONFIG.ENV_VAR_FILE} /tmp/environment-bkp-${local.datetime} || true"
  ]

  update_commands = [
    for key, value in local.RKE_CONFIG :
    "sudo sed -i \"/^${key}=/d\" ${local.RKE_CONFIG.ENV_VAR_FILE} && echo '${key}=${value}' | sudo tee -a ${local.RKE_CONFIG.ENV_VAR_FILE}"
    if value != null && value != ""
  ]

  k8s_env_vars = [
    for cmd in concat(local.backup_command, local.update_commands) :
    cmd if cmd != null && cmd != ""
  ]
}

output "rke_config" {
  value = local.RKE_CONFIG
}

output "k8s_env_vars_count" {
  value = length(local.k8s_env_vars)
}

output "k8s_env_vars" {
  value = local.k8s_env_vars
}
