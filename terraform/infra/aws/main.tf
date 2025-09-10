terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
  }
}

# AWS Infrastructure Module
module "aws_infrastructure" {
  source = "../../modules/aws"

  # AWS-specific configurations
  AWS_PROVIDER_REGION           = var.aws_provider_region
  SPECIFIC_AVAILABILITY_ZONES   = var.specific_availability_zones
  CLUSTER_NAME                  = var.cluster_name
  SSH_PRIVATE_KEY               = var.ssh_private_key
  K8S_CONTROL_PLANE_NODE_COUNT  = var.k8s_control_plane_node_count
  K8S_ETCD_NODE_COUNT           = var.k8s_etcd_node_count
  K8S_WORKER_NODE_COUNT         = var.k8s_worker_node_count
  ENABLE_RANCHER_IMPORT         = var.enable_rancher_import
  RANCHER_IMPORT_URL            = var.rancher_import_url
  CLUSTER_ENV_DOMAIN            = var.cluster_env_domain
  SUBDOMAIN_PUBLIC              = var.subdomain_public
  SUBDOMAIN_INTERNAL            = var.subdomain_internal
  MOSIP_EMAIL_ID                = var.mosip_email_id
  SSH_KEY_NAME                  = var.ssh_key_name
  K8S_INSTANCE_TYPE             = var.k8s_instance_type
  NGINX_INSTANCE_TYPE           = var.nginx_instance_type
  AMI                           = var.ami
  ZONE_ID                       = var.zone_id
  K8S_INFRA_REPO_URL            = var.k8s_infra_repo_url
  K8S_INFRA_BRANCH              = var.k8s_infra_branch
  RKE2_VERSION                  = var.rke2_version
  vpc_name                      = var.vpc_name
  NGINX_NODE_ROOT_VOLUME_SIZE   = var.nginx_node_root_volume_size
  NGINX_NODE_EBS_VOLUME_SIZE    = var.nginx_node_ebs_volume_size
  nginx_node_ebs_volume_size_2  = var.nginx_node_ebs_volume_size_2
  K8S_INSTANCE_ROOT_VOLUME_SIZE = var.k8s_instance_root_volume_size
  network_cidr                  = var.network_cidr
  WIREGUARD_CIDR                = var.WIREGUARD_CIDR

  # PostgreSQL Configuration
  enable_postgresql_setup = var.enable_postgresql_setup
  postgresql_version      = var.postgresql_version
  storage_device          = var.storage_device
  mount_point             = var.mount_point
  postgresql_port         = var.postgresql_port

  # MOSIP Infrastructure Repository Configuration
  mosip_infra_repo_url = var.mosip_infra_repo_url
  mosip_infra_branch   = var.mosip_infra_branch
}
