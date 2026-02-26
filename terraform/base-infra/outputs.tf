# Cloud-agnostic outputs

output "network_id" {
  description = "ID of the network"
  value       = var.cloud_provider == "aws" ? module.aws_network[0].network_id : null
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = var.cloud_provider == "aws" ? module.aws_network[0].public_subnet_ids : null
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = var.cloud_provider == "aws" ? module.aws_network[0].private_subnet_ids : null
}

output "cloud_specific" {
  description = "Cloud provider specific outputs"
  value       = var.cloud_provider == "aws" ? module.aws_network[0].cloud_specific : null
}

output "jumpserver_public_ip" {
  description = "Public IP address of the jump server"
  value       = var.cloud_provider == "aws" ? module.aws_network[0].jumpserver_public_ip : null
}
