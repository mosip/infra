terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

# AWS Infrastructure
module "aws_infra" {
  count  = var.cloud_provider == "aws" ? 1 : 0
  source = "./aws"
  
  # Pass all variables to the AWS module
  cluster_name                  = var.cluster_name
  cluster_env_domain           = var.cluster_env_domain
  aws_provider_region          = var.aws_provider_region
  k8s_control_plane_node_count = var.k8s_control_plane_node_count
  k8s_etcd_node_count          = var.k8s_etcd_node_count
  k8s_worker_node_count        = var.k8s_worker_node_count
  k8s_instance_type            = var.k8s_instance_type
  nginx_instance_type          = var.nginx_instance_type
  ami                          = var.ami
  ssh_key_name                 = var.ssh_key_name
  ssh_private_key              = var.ssh_private_key
  zone_id                      = var.zone_id
  vpc_name                     = var.vpc_name
  mosip_email_id               = var.mosip_email_id
  subdomain_public             = var.subdomain_public
  subdomain_internal           = var.subdomain_internal
  enable_rancher_import        = var.enable_rancher_import
  rancher_import_url           = var.rancher_import_url
  k8s_infra_repo_url           = var.k8s_infra_repo_url
  k8s_infra_branch             = var.k8s_infra_branch
  nginx_node_root_volume_size  = var.nginx_node_root_volume_size
  nginx_node_ebs_volume_size   = var.nginx_node_ebs_volume_size
  k8s_instance_root_volume_size = var.k8s_instance_root_volume_size
}

# Azure Infrastructure
module "azure_infra" {
  count  = var.cloud_provider == "azure" ? 1 : 0
  source = "./azure"
  
  # Pass all variables to the Azure module
  cluster_name                  = var.cluster_name
  cluster_env_domain           = var.cluster_env_domain
  k8s_control_plane_node_count = var.k8s_control_plane_node_count
  k8s_etcd_node_count          = var.k8s_etcd_node_count
  k8s_worker_node_count        = var.k8s_worker_node_count
  subdomain_public             = var.subdomain_public
  subdomain_internal           = var.subdomain_internal
  mosip_email_id               = var.mosip_email_id
  ssh_private_key              = var.ssh_private_key
  rancher_import_url           = var.rancher_import_url
  k8s_infra_repo_url           = var.k8s_infra_repo_url
  k8s_infra_branch             = var.k8s_infra_branch
  
  # Azure-specific variables
  azure_provider_region           = var.azure_provider_region
  k8s_instance_type               = var.k8s_instance_type
  nginx_instance_type             = var.nginx_instance_type
  azure_image                     = var.azure_image
  ssh_key_name                    = var.ssh_key_name
  azure_dns_zone                  = var.azure_dns_zone
  vpc_name                        = var.vpc_name
  nginx_node_root_volume_size     = var.nginx_node_root_volume_size
  nginx_node_additional_volume_size = var.nginx_node_additional_volume_size
  k8s_instance_root_volume_size   = var.k8s_instance_root_volume_size
}

# GCP Infrastructure
module "gcp_infra" {
  count  = var.cloud_provider == "gcp" ? 1 : 0
  source = "./gcp"
  
  # Pass all variables to the GCP module
  cluster_name                  = var.cluster_name
  cluster_env_domain           = var.cluster_env_domain
  k8s_control_plane_node_count = var.k8s_control_plane_node_count
  k8s_etcd_node_count          = var.k8s_etcd_node_count
  k8s_worker_node_count        = var.k8s_worker_node_count
  subdomain_public             = var.subdomain_public
  subdomain_internal           = var.subdomain_internal
  mosip_email_id               = var.mosip_email_id
  ssh_private_key              = var.ssh_private_key
  rancher_import_url           = var.rancher_import_url
  k8s_infra_repo_url           = var.k8s_infra_repo_url
  k8s_infra_branch             = var.k8s_infra_branch
  
  # GCP-specific variables
  gcp_project_id                  = var.gcp_project_id
  gcp_provider_region             = var.gcp_provider_region
  k8s_instance_type               = var.k8s_instance_type
  nginx_instance_type             = var.nginx_instance_type
  gcp_image                       = var.gcp_image
  ssh_key_name                    = var.ssh_key_name
  gcp_dns_zone                    = var.gcp_dns_zone
  vpc_name                        = var.vpc_name
  nginx_node_root_volume_size     = var.nginx_node_root_volume_size
  nginx_node_additional_volume_size = var.nginx_node_additional_volume_size
  k8s_instance_root_volume_size   = var.k8s_instance_root_volume_size
}
