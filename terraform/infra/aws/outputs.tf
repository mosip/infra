# AWS Infrastructure Outputs
output "k8s_cluster_public_ips" {
  description = "Public IP addresses of K8s cluster nodes"
  value       = module.aws_infrastructure.K8S_CLUSTER_PUBLIC_IPS
}

output "k8s_cluster_private_ips" {
  description = "Private IP addresses of K8s cluster nodes"
  value       = module.aws_infrastructure.K8S_CLUSTER_PRIVATE_IPS
}

output "nginx_public_ip" {
  description = "Public IP address of NGINX instance"
  value       = module.aws_infrastructure.NGINX_PUBLIC_IP
}

output "nginx_private_ip" {
  description = "Private IP address of NGINX instance"
  value       = module.aws_infrastructure.NGINX_PRIVATE_IP
}

output "control_plane_node_1" {
  description = "First control plane node information"
  value       = module.aws_infrastructure.CONTROL_PLANE_NODE_1
}

output "k8s_token" {
  description = "Kubernetes cluster token"
  value       = module.aws_infrastructure.K8S_TOKEN
  sensitive   = true
}

# RKE2 Cloud-Init and deployment outputs
output "rke2_cloud_init_user_data" {
  description = "Base64 encoded user data for EC2 instances with Cloud-Init RKE2 setup"
  value       = module.aws_infrastructure.rke2_cloud_init_user_data
}

output "setup_instructions" {
  description = "RKE2 deployment setup instructions based on configuration"
  value       = module.aws_infrastructure.setup_instructions
}

output "control_plane_nodes" {
  description = "Control plane nodes that will have kubeconfig files available"
  value       = module.aws_infrastructure.control_plane_nodes
}

output "deployment_method" {
  description = "Deployment method being used for RKE2 setup"
  value       = module.aws_infrastructure.deployment_method
}

output "kubeconfig_files_location" {
  description = "Location where kubeconfig files will be downloaded after terraform apply"
  value       = module.aws_infrastructure.kubeconfig_files_location
}

output "kubectl_usage" {
  description = "Instructions for using kubectl after deployment"
  value       = module.aws_infrastructure.kubectl_usage
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.aws_infrastructure.VPC_ID
}
