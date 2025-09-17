# K8s cluster private IPs (recommended)
output "K8S_CLUSTER_IPS" {
  description = "Private IP addresses of K8s cluster nodes"
  value       = module.aws-resource-creation.K8S_CLUSTER_IPS
}

# Deprecated: Use K8S_CLUSTER_IPS instead
output "K8S_CLUSTER_PRIVATE_IPS" {
  description = "Private IP addresses of K8s cluster nodes (deprecated)"
  value       = module.aws-resource-creation.K8S_CLUSTER_PRIVATE_IPS
}

output "NGINX_PUBLIC_IP" {
  value = module.aws-resource-creation.NGINX_PUBLIC_IP
}

output "NGINX_PRIVATE_IP" {
  value = module.aws-resource-creation.NGINX_PRIVATE_IP
}

output "MOSIP_NGINX_SG_ID" {
  value = module.aws-resource-creation.MOSIP_NGINX_SG_ID
}

output "MOSIP_K8S_SG_ID" {
  value = module.aws-resource-creation.MOSIP_K8S_SG_ID
}

output "MOSIP_K8S_CLUSTER_NODES_PRIVATE_IP_LIST" {
  value = module.aws-resource-creation.MOSIP_K8S_CLUSTER_NODES_PRIVATE_IP_LIST
}

output "MOSIP_PUBLIC_DOMAIN_LIST" {
  value = module.aws-resource-creation.MOSIP_PUBLIC_DOMAIN_LIST
}


# Token generation handled by ansible - no output needed
# K8S_TOKEN removed as ansible manages token internally

# VPC Information
output "VPC_ID" {
  description = "ID of the VPC"
  value       = data.aws_vpc.existing_vpc.id
}

output "PUBLIC_SUBNET_IDS" {
  description = "List of public subnet IDs"
  value       = data.aws_subnets.public_subnets.ids
}

# Infrastructure Status
output "vpc_with_subnets" {
  description = "Always true - using existing VPC with tagged subnets"
  value       = true
}

# Basic availability zone information
output "all_availability_zones" {
  description = "All available AZs in the region"
  value       = data.aws_availability_zones.available.names
}

output "selected_availability_zones" {
  description = "AZs selected for deployment"
  value       = local.selected_azs
}
