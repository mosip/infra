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

output "vpc_id" {
  description = "VPC ID"
  value       = module.aws_infrastructure.VPC_ID
}
