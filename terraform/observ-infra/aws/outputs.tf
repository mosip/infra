# Pass through outputs from the AWS main module
output "K8S_CLUSTER_IPS" {
  description = "Private IPs of the K8s cluster nodes"
  value       = module.aws_observation_infrastructure.K8S_CLUSTER_IPS
}

output "K8S_CLUSTER_PRIVATE_IPS" {
  description = "Private IPs of the K8s cluster nodes (deprecated - use K8S_CLUSTER_IPS)"
  value       = module.aws_observation_infrastructure.K8S_CLUSTER_PRIVATE_IPS
}

output "NGINX_PUBLIC_IP" {
  description = "Public IP of the NGINX load balancer"
  value       = module.aws_observation_infrastructure.NGINX_PUBLIC_IP
}

output "NGINX_PRIVATE_IP" {
  description = "Private IP of the NGINX load balancer"
  value       = module.aws_observation_infrastructure.NGINX_PRIVATE_IP
}

# CONTROL_PLANE_NODE_1 output removed - not available with AWS resource creation only
# output "CONTROL_PLANE_NODE_1" {
#   description = "First control plane node information"
#   value       = module.aws_observation_infrastructure.CONTROL_PLANE_NODE_1
# }

# Token generation handled by ansible - no terraform output needed
# K8S_TOKEN removed as ansible manages token internally

# Add missing outputs for compatibility
# CONTROL_PLANE_NODE_1 output removed - not available with AWS resource creation only
# output "control_plane_node_1" {
#   description = "First control plane node information (lowercase alias)"
#   value       = module.aws_observation_infrastructure.CONTROL_PLANE_NODE_1
# }

# Token generation handled by ansible - no terraform output needed
# k8s_token removed as ansible manages token internally

output "vpc_id" {
  description = "VPC ID (lowercase alias)"
  value       = module.aws_observation_infrastructure.VPC_ID
}

# Rancher and Keycloak outputs - disabled since modules are commented out
# output "rancher_url" {
#   description = "URL for accessing Rancher UI"
#   value       = "Rancher integration disabled - only AWS resource creation enabled"
# }

# output "keycloak_url" {
#   description = "URL for accessing Keycloak"
#   value       = "Keycloak integration disabled - only AWS resource creation enabled"
# }

# output "rancher_bootstrap_password" {
#   description = "Bootstrap password for Rancher UI"
#   value       = "N/A - Rancher integration disabled"
#   sensitive   = true
# }

# output "rancher_keycloak_status" {
#   description = "Status of Rancher and Keycloak installation"
#   value       = "Rancher and Keycloak integration disabled - only AWS resource creation enabled"
# }

# output "rancher_keycloak_next_steps" {
#   description = "Next steps after Rancher and Keycloak installation"
#   value       = ["Rancher and Keycloak integration disabled - only AWS resource creation enabled"]
#   sensitive   = true
# }

# Infrastructure outputs
output "cluster_ready" {
  description = "Indicates when the cluster is ready"
  value       = true
  depends_on  = [module.aws_observation_infrastructure]
}

output "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  value       = "/home/ubuntu/.kube/config"
}
