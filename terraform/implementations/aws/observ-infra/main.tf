terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.aws_provider_region
}

# Call the cloud-agnostic observ-infra module (uses same modules as infra with minimal resources)
module "mosip_observ_infra" {
  source = "../../../observ-infra"

  # Cloud provider selection
  cloud_provider = var.cloud_provider

  # Common configuration (same as infra but different values for minimal resources)
  cluster_name                 = var.cluster_name
  cluster_env_domain           = var.cluster_env_domain
  k8s_control_plane_node_count = var.k8s_control_plane_node_count
  k8s_etcd_node_count          = var.k8s_etcd_node_count
  k8s_worker_node_count        = var.k8s_worker_node_count
  subdomain_public             = var.subdomain_public
  subdomain_internal           = var.subdomain_internal
  mosip_email_id               = var.mosip_email_id
  ssh_private_key              = var.ssh_private_key
  enable_rancher_import        = var.enable_rancher_import
  rancher_import_url           = var.rancher_import_url
  k8s_infra_repo_url           = var.k8s_infra_repo_url
  k8s_infra_branch             = var.k8s_infra_branch

  # AWS-specific configuration (same variables as infra but with smaller instance types)
  aws_provider_region           = var.aws_provider_region
  k8s_instance_type             = var.k8s_instance_type
  nginx_instance_type           = var.nginx_instance_type
  ami                           = var.ami
  ssh_key_name                  = var.ssh_key_name
  zone_id                       = var.zone_id
  vpc_name                      = var.vpc_name
  nginx_node_root_volume_size   = var.nginx_node_root_volume_size
  nginx_node_ebs_volume_size    = var.nginx_node_ebs_volume_size
  k8s_instance_root_volume_size = var.k8s_instance_root_volume_size

  network_cidr                  = var.network_cidr
  WIREGUARD_CIDR                = var.WIREGUARD_CIDR

  # Rancher and Keycloak Configuration (passed through to module)
  enable_rancher_keycloak_integration = var.enable_rancher_keycloak_integration
  rancher_hostname                    = var.rancher_hostname
  keycloak_hostname                   = var.keycloak_hostname
  rancher_bootstrap_password          = var.rancher_bootstrap_password
}
