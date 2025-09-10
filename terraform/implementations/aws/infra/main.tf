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

# Call the cloud-agnostic infra module
module "mosip_infra" {
  network_cidr   = var.network_cidr
  WIREGUARD_CIDR = var.WIREGUARD_CIDR
  source         = "../../../infra"

  # Cloud provider selection
  cloud_provider = "aws"

  # Common configuration
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
  rke2_version                 = var.rke2_version

  # PostgreSQL Configuration
  enable_postgresql_setup = var.enable_postgresql_setup
  postgresql_version      = var.postgresql_version
  storage_device          = var.storage_device
  mount_point             = var.mount_point
  postgresql_port         = var.postgresql_port

  # MOSIP Infrastructure Repository Configuration
  mosip_infra_repo_url = var.mosip_infra_repo_url
  mosip_infra_branch   = var.mosip_infra_branch

  # AWS-specific configuration
  aws_provider_region           = var.aws_provider_region
  specific_availability_zones   = var.specific_availability_zones
  k8s_instance_type             = var.k8s_instance_type
  nginx_instance_type           = var.nginx_instance_type
  ami                           = var.ami
  ssh_key_name                  = var.ssh_key_name
  zone_id                       = var.zone_id
  vpc_name                      = var.vpc_name
  nginx_node_root_volume_size   = var.nginx_node_root_volume_size
  nginx_node_ebs_volume_size    = var.nginx_node_ebs_volume_size
  nginx_node_ebs_volume_size_2  = var.nginx_node_ebs_volume_size_2
  k8s_instance_root_volume_size = var.k8s_instance_root_volume_size

}
