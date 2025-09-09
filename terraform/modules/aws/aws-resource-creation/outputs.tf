# K8s instances only have private IPs for security
output "K8S_CLUSTER_IPS" {
  description = "Private IP addresses of K8s cluster nodes"
  value       = { for key, instance in aws_instance.K8S_CLUSTER_EC2_INSTANCE : "${local.K8S_EC2_NODE.tags.Name}-${key}" => instance.private_ip }
}
output "K8S_CLUSTER_PRIVATE_IPS" {
  description = "Private IP addresses of K8s cluster nodes (deprecated - use K8S_CLUSTER_IPS)"
  value       = { for key, instance in aws_instance.K8S_CLUSTER_EC2_INSTANCE : "${local.K8S_EC2_NODE.tags.Name}-${key}" => instance.private_ip }
}
output "NGINX_PUBLIC_IP" {
  value = aws_instance.NGINX_EC2_INSTANCE.public_ip
}
output "NGINX_PRIVATE_IP" {
  value = aws_instance.NGINX_EC2_INSTANCE.private_ip
}
output "MOSIP_NGINX_SG_ID" {
  value = aws_security_group.security-group["NGINX_SECURITY_GROUP"].id
}
output "MOSIP_K8S_SG_ID" {
  value = { for key, value in aws_security_group.security-group : key => value.id }
}
output "MOSIP_K8S_CLUSTER_NODES_PRIVATE_IP_LIST" {
  value = join(",", [for instance in aws_instance.K8S_CLUSTER_EC2_INSTANCE : instance.private_ip])
}
output "MOSIP_PUBLIC_DOMAIN_LIST" {
  value = join(",", concat(
    [local.MAP_DNS_TO_IP.API_DNS.name],
    [for cname in var.DNS_RECORDS : cname.name if contains([cname.records], local.MAP_DNS_TO_IP.API_DNS.name)]
  ))
}

# Output to signal that all instances are ready and status checks passed
output "INSTANCES_READY" {
  depends_on = [
    null_resource.nginx_status_checks,
    null_resource.k8s_status_checks
  ]
  value = {
    nginx_instance_ready     = true
    k8s_instances_ready      = true
    all_status_checks_passed = true
    nginx_instance_id        = aws_instance.NGINX_EC2_INSTANCE.id
    k8s_instance_ids         = [for instance in aws_instance.K8S_CLUSTER_EC2_INSTANCE : instance.id]
    ready_timestamp          = timestamp()
  }
  description = "Indicates that all EC2 instances are running and have passed their status checks"
}
