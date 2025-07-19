terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.48.0"
    }
    # azurerm = {
    #   source  = "hashicorp/azurerm"
    #   version = "~> 3.117.1"
    # }
    # google = {
    #   source  = "hashicorp/google"
    #   version = "~> 5.45.2"
    # }
  }
}

variable "cloud_provider" {
  description = "The cloud provider to use (aws, azure, gcp)"
  type        = string
}

variable "CLUSTER_NAME" {}
variable "AWS_PROVIDER_REGION" {}
variable "SSH_KEY_NAME" {}
variable "K8S_INSTANCE_TYPE" {}
variable "NGINX_INSTANCE_TYPE" {}
variable "CLUSTER_ENV_DOMAIN" {}
variable "ZONE_ID" {}
variable "AMI" {}
variable "K8S_INSTANCE_ROOT_VOLUME_SIZE" {}
variable "SSH_PRIVATE_KEY" {}
variable "K8S_INFRA_BRANCH" {}
variable "K8S_INFRA_REPO_URL" {}
variable "NGINX_NODE_EBS_VOLUME_SIZE" {}
variable "NGINX_NODE_ROOT_VOLUME_SIZE" {}
variable "K8S_CONTROL_PLANE_NODE_COUNT" {}
variable "K8S_ETCD_NODE_COUNT" {}
variable "K8S_WORKER_NODE_COUNT" {}
variable "RANCHER_IMPORT_URL" {}
variable "MOSIP_EMAIL_ID" {}
variable "SUBDOMAIN_PUBLIC" {}
variable "SUBDOMAIN_INTERNAL" {}

# provider "aws" {
#   region = var.AWS_PROVIDER_REGION
# }

provider "aws" {
  region = var.cloud_provider == "aws" ? var.AWS_PROVIDER_REGION : null
}
# provider "azurerm" {
#   features {}
# }

# provider "google" {}

module "aws" {
  source = "./modules/aws"
  count  = var.cloud_provider == "aws" ? 1 : 0

  CLUSTER_NAME                  = var.CLUSTER_NAME
  AWS_PROVIDER_REGION           = var.AWS_PROVIDER_REGION
  SSH_KEY_NAME                  = var.SSH_KEY_NAME
  K8S_INSTANCE_TYPE             = var.K8S_INSTANCE_TYPE
  NGINX_INSTANCE_TYPE           = var.NGINX_INSTANCE_TYPE
  CLUSTER_ENV_DOMAIN            = var.CLUSTER_ENV_DOMAIN
  ZONE_ID                       = var.ZONE_ID
  AMI                           = var.AMI
  K8S_INSTANCE_ROOT_VOLUME_SIZE = var.K8S_INSTANCE_ROOT_VOLUME_SIZE
  SSH_PRIVATE_KEY               = var.SSH_PRIVATE_KEY
  K8S_INFRA_BRANCH              = var.K8S_INFRA_BRANCH
  K8S_INFRA_REPO_URL            = var.K8S_INFRA_REPO_URL
  NGINX_NODE_EBS_VOLUME_SIZE    = var.NGINX_NODE_EBS_VOLUME_SIZE
  NGINX_NODE_ROOT_VOLUME_SIZE   = var.NGINX_NODE_ROOT_VOLUME_SIZE
  K8S_CONTROL_PLANE_NODE_COUNT  = var.K8S_CONTROL_PLANE_NODE_COUNT
  K8S_ETCD_NODE_COUNT           = var.K8S_ETCD_NODE_COUNT
  K8S_WORKER_NODE_COUNT         = var.K8S_WORKER_NODE_COUNT
  RANCHER_IMPORT_URL            = var.RANCHER_IMPORT_URL
  MOSIP_EMAIL_ID                = var.MOSIP_EMAIL_ID
  SUBDOMAIN_PUBLIC              = var.SUBDOMAIN_PUBLIC
  SUBDOMAIN_INTERNAL            = var.SUBDOMAIN_INTERNAL

}

# module "azure" {
#   source = "./modules/azure"
#   count  = var.cloud_provider == "azure" ? 1 : 0

# }

# module "gcp" {
#   source = "./modules/gcp"
#   count  = var.cloud_provider == "gcp" ? 1 : 0
# }
