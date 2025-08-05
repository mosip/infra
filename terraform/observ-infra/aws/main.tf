terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
  }
}

# AWS Observation Infrastructure Module (using same modules as infra, with minimal resources)
module "aws_observation_infrastructure" {
  source = "../../modules/aws"
  
  # AWS-specific configurations (same as infra but with minimal resource sizing)
  AWS_PROVIDER_REGION           = var.aws_provider_region
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
  vpc_name                      = var.vpc_name
  NGINX_NODE_ROOT_VOLUME_SIZE   = var.nginx_node_root_volume_size
  NGINX_NODE_EBS_VOLUME_SIZE    = var.nginx_node_ebs_volume_size
  K8S_INSTANCE_ROOT_VOLUME_SIZE = var.k8s_instance_root_volume_size
}

# Rancher and Keycloak Integration (only for observ-infra)
module "rancher_keycloak_setup" {
  count      = var.enable_rancher_keycloak_integration ? 1 : 0
  depends_on = [module.aws_observation_infrastructure]
  source     = "../../modules/aws/rancher-keycloak-setup"

  SSH_PRIVATE_KEY              = var.ssh_private_key
  K8S_INFRA_REPO_URL          = var.k8s_infra_repo_url
  K8S_INFRA_BRANCH            = var.k8s_infra_branch
  CLUSTER_NAME                = var.cluster_name
  CLUSTER_ENV_DOMAIN          = var.cluster_env_domain
  RANCHER_HOSTNAME            = var.rancher_hostname
  KEYCLOAK_HOSTNAME           = var.keycloak_hostname
  RANCHER_BOOTSTRAP_PASSWORD  = var.rancher_bootstrap_password
  ENABLE_RANCHER_KEYCLOAK     = var.enable_rancher_keycloak_integration
  CONTROL_PLANE_IPS           = module.aws_observation_infrastructure.K8S_CLUSTER_PRIVATE_IPS["control_plane"]
  NGINX_PUBLIC_IP             = module.aws_observation_infrastructure.NGINX_PUBLIC_IP
}
