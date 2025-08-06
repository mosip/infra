# AWS-specific variables passed from the main infra module

variable "aws_provider_region" {
  description = "AWS region for resource creation"
  type        = string
}

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "ssh_private_key" {
  description = "SSH private key for instance access"
  type        = string
  sensitive   = true
}

variable "k8s_control_plane_node_count" {
  description = "Number of K8s control plane nodes"
  type        = number
}

variable "k8s_etcd_node_count" {
  description = "Number of K8s ETCD nodes"
  type        = number
}

variable "k8s_worker_node_count" {
  description = "Number of K8s worker nodes"
  type        = number
}

variable "enable_rancher_import" {
  description = "Set to true to enable Rancher import"
  type        = bool
}

variable "rancher_import_url" {
  description = "Rancher import URL for kubectl apply"
  type        = string
}

variable "cluster_env_domain" {
  description = "MOSIP DOMAIN : (ex: sandbox.xyz.net)"
  type        = string
}

variable "subdomain_public" {
  description = "List of public subdomains to create CNAME records for"
  type        = list(string)
}

variable "subdomain_internal" {
  description = "List of internal subdomains to create CNAME records for"
  type        = list(string)
}

variable "mosip_email_id" {
  description = "Email ID used by certbot to generate SSL certs for Nginx node"
  type        = string
}

variable "ssh_key_name" {
  description = "Name of the SSH key pair in AWS"
  type        = string
}

variable "k8s_instance_type" {
  description = "Instance type for K8s nodes"
  type        = string
}

variable "nginx_instance_type" {
  description = "Instance type for NGINX server"
  type        = string
}

variable "ami" {
  description = "AMI ID for AWS instances"
  type        = string
}

variable "zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "k8s_infra_repo_url" {
  description = "The URL of the Kubernetes infrastructure GitHub repository"
  type        = string
}

variable "k8s_infra_branch" {
  description = "Branch of the K8s infrastructure repository"
  type        = string
}

variable "vpc_name" {
  description = "Name of the existing VPC (will be discovered by tag:Name)"
  type        = string
}

variable "nginx_node_root_volume_size" {
  description = "Root volume size for NGINX node"
  type        = number
}

variable "nginx_node_ebs_volume_size" {
  description = "EBS volume size for NGINX node"
  type        = number
}

variable "k8s_instance_root_volume_size" {
  description = "Root volume size for K8s instances"
  type        = number
}
