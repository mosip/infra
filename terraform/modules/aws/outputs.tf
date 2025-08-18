output "K8S_CLUSTER_PUBLIC_IPS" {
  value = module.aws-resource-creation.K8S_CLUSTER_PUBLIC_IPS
}

output "K8S_CLUSTER_PRIVATE_IPS" {
  value = module.aws-resource-creation.K8S_CLUSTER_PRIVATE_IPS
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

output "CONTROL_PLANE_NODE_1" {
  value = module.rke2-setup.CONTROL_PLANE_NODE_1
}

output "K8S_CLUSTER_PRIVATE_IPS_STR" {
  value = module.rke2-setup.K8S_CLUSTER_PRIVATE_IPS_STR
}

output "K8S_TOKEN" {
  value = module.rke2-setup.K8S_TOKEN
  sensitive = true
}

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

# AZ Validation Information
output "all_availability_zones" {
  description = "All available AZs in the region"
  value       = data.aws_availability_zones.available.names
}

output "instance_type_available_azs" {
  description = "AZs where the specified instance type is available"
  value       = local.available_azs_for_instance_type
}

output "selected_availability_zones" {
  description = "AZs selected for deployment after validation"
  value       = local.selected_azs
}

output "instance_type_availability_check" {
  description = "Instance type availability validation results"
  value = {
    instance_type = var.K8S_INSTANCE_TYPE
    total_azs = length(data.aws_availability_zones.available.names)
    available_azs = length(local.available_azs_for_instance_type)
    using_azs = length(local.selected_azs)
    validation_passed = length(local.available_azs_for_instance_type) >= 2
  }
}
