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
  value     = module.rke2-setup.K8S_TOKEN
  sensitive = true
}

# RKE2 Cloud-Init and deployment outputs
output "rke2_cloud_init_user_data" {
  description = "Base64 encoded user data for EC2 instances with Cloud-Init RKE2 setup"
  value       = module.rke2-setup.rke2_cloud_init_user_data
}

output "setup_instructions" {
  description = "RKE2 deployment setup instructions based on configuration"
  value       = module.rke2-setup.setup_instructions
}

output "control_plane_nodes" {
  description = "Control plane nodes that will have kubeconfig files available"
  value       = module.rke2-setup.control_plane_nodes
}

output "deployment_method" {
  description = "Deployment method being used for RKE2 setup"
  value       = module.rke2-setup.deployment_method
}

output "kubeconfig_files_location" {
  description = "Location where kubeconfig files will be downloaded after terraform apply"
  value       = module.rke2-setup.kubeconfig_files_location
}

output "kubectl_usage" {
  description = "Instructions for using kubectl after deployment"
  value       = module.rke2-setup.kubectl_usage
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

output "k8s_instance_available_azs" {
  description = "AZs where K8s instance type is available (after filtering)"
  value       = local.k8s_filtered_azs
}

output "nginx_instance_available_azs" {
  description = "AZs where NGINX instance type is available (after filtering)"
  value       = local.nginx_filtered_azs
}

output "common_available_azs" {
  description = "AZs available for both instance types"
  value       = local.common_available_azs
}

output "selected_availability_zones" {
  description = "AZs selected for deployment after validation"
  value       = local.selected_azs
}

output "instance_type_availability_check" {
  description = "Instance type availability validation results"
  value = {
    k8s_instance_type   = var.K8S_INSTANCE_TYPE
    nginx_instance_type = var.NGINX_INSTANCE_TYPE
    total_azs           = length(data.aws_availability_zones.available.names)

    # Node count information
    k8s_control_plane_nodes = var.K8S_CONTROL_PLANE_NODE_COUNT
    k8s_etcd_nodes          = var.K8S_ETCD_NODE_COUNT
    k8s_worker_nodes        = var.K8S_WORKER_NODE_COUNT
    total_k8s_nodes         = local.total_k8s_nodes
    min_azs_needed          = local.min_azs_for_k8s

    # Availability information
    k8s_available_azs   = length(local.k8s_filtered_azs)
    nginx_available_azs = length(local.nginx_filtered_azs)
    common_azs          = length(local.common_available_azs)
    using_azs           = length(local.selected_azs)

    # Validation results
    k8s_validation_passed   = length(local.k8s_filtered_azs) >= local.min_azs_for_k8s
    nginx_validation_passed = length(local.nginx_filtered_azs) >= 1
    deployment_feasible     = length(local.selected_azs) >= local.min_azs_for_k8s
  }
}
