terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

# Configure the GCP Provider
provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

# Call the cloud-agnostic infra module
module "mosip_infra" {
  source = "../../../infra"
  
  # Cloud provider selection
  cloud_provider = "gcp"
  
  # Common configuration
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
  
  # Placeholder for GCP-specific configuration
  # TODO: Add GCP-specific variables when implementing GCP module
  aws_provider_region           = ""
  k8s_instance_type             = ""
  nginx_instance_type           = ""
  ami                           = ""
  ssh_key_name                  = ""
  zone_id                       = ""
  vpc_name                      = ""
  nginx_node_root_volume_size   = 0
  nginx_node_ebs_volume_size    = 0
  k8s_instance_root_volume_size = 0
}
