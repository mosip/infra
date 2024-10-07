variable "AWS_PROVIDER_REGION" { type = string }
variable "CLUSTER_NAME" { type = string }
variable "SSH_PRIVATE_KEY" { type = string }
variable "K8S_CONTROL_PLANE_NODE_COUNT" { type = number }
variable "K8S_ETCD_NODE_COUNT" { type = number }
variable "K8S_WORKER_NODE_COUNT" { type = number }
variable "RANCHER_IMPORT_URL" {
  description = "Rancher import URL for kubectl apply"
  type        = string

  validation {
    condition     = can(regex("^\"kubectl apply -f https://rancher\\.mosip\\.net/v3/import/[a-zA-Z0-9_\\-]+\\.yaml\"$", var.RANCHER_IMPORT_URL))
    error_message = "The RANCHER_IMPORT_URL must be in the format: '\"kubectl apply -f https://rancher.mosip.net/v3/import/<ID>.yaml\"'"
  }
}

variable "CLUSTER_ENV_DOMAIN" {
  description = "MOSIP DOMAIN : (ex: sandbox.xyz.net)"
  type        = string
  validation {
    condition     = can(regex("^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9])\\.)+[a-zA-Z]{2,}$", var.CLUSTER_ENV_DOMAIN))
    error_message = "The domain name must be a valid domain name, e.g., sandbox.xyz.net."
  }
}

variable "MOSIP_EMAIL_ID" {
  description = "Email ID used by certbot to generate SSL certs for Nginx node"
  type        = string
  validation {
    condition     = can(regex("^\\S+@\\S+\\.\\S+$", var.MOSIP_EMAIL_ID))
    error_message = "The email address must be a valid email format (e.g., user@example.com)."
  }
}

variable "SSH_KEY_NAME" { type = string }
variable "K8S_INSTANCE_TYPE" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9]+\\..*", var.K8S_INSTANCE_TYPE))
    error_message = "Invalid instance type format. Must be in the form 'series.type'."
  }
}

variable "NGINX_INSTANCE_TYPE" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9]+\\..*", var.NGINX_INSTANCE_TYPE))
    error_message = "Invalid instance type format. Must be in the form 'series.type'."
  }
}
variable "AMI" {
  type = string
  validation {
    condition     = can(regex("^ami-[a-f0-9]{17}$", var.AMI))
    error_message = "Invalid AMI format. It should be in the format 'ami-xxxxxxxxxxxxxxxxx'"
  }
}

variable "ZONE_ID" { type = string }
variable "K8S_INFRA_REPO_URL" {
  description = "The URL of the Kubernetes infrastructure GitHub repository"
  type        = string

  validation {
    condition     = can(regex("^https://github\\.com/.+/.+\\.git$", var.K8S_INFRA_REPO_URL))
    error_message = "The K8S_INFRA_REPO_URL must be a valid GitHub repository URL ending with .git"
  }
}
variable "K8S_INFRA_BRANCH" {
  type    = string
  default = "main"
}

variable "NGINX_NODE_ROOT_VOLUME_SIZE" { type = number }
variable "NGINX_NODE_EBS_VOLUME_SIZE" { type = number }
variable "K8S_INSTANCE_ROOT_VOLUME_SIZE" { type = number }