output "network_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "jumpserver_id" {
  description = "ID of the jump server instance"
  value       = aws_instance.jumpserver.id
}

output "jumpserver_public_ip" {
  description = "Public IP address of the jump server"
  value       = var.create_jumpserver_eip ? aws_eip.jumpserver[0].public_ip : aws_instance.jumpserver.public_ip
}
output "jumpserver_private_ip" {
  description = "Private IP address of the jump server"
  value       = aws_instance.jumpserver.private_ip
}

output "jumpserver_security_group_id" {
  description = "ID of the jump server security group"
  value       = aws_security_group.jumpserver.id
}

output "cloud_specific" {
  description = "AWS-specific outputs"
  value = {
    vpc_id                = aws_vpc.main.id
    vpc_cidr              = aws_vpc.main.cidr_block
    internet_gateway_id   = aws_internet_gateway.main.id
    nat_gateway_ids       = var.enable_nat_gateway ? aws_nat_gateway.main[*].id : []
    public_route_table_id = aws_route_table.public.id
    private_route_table_ids = var.enable_nat_gateway ? aws_route_table.private[*].id : []
    jumpserver_id         = aws_instance.jumpserver.id
    jumpserver_public_ip  = var.create_jumpserver_eip ? aws_eip.jumpserver[0].public_ip : aws_instance.jumpserver.public_ip
    jumpserver_private_ip = aws_instance.jumpserver.private_ip
  }
}

output "wireguard_info" {
  description = "WireGuard configuration information"
  value = var.enable_wireguard_setup ? {
    enabled = true
    peers   = var.wireguard_peers
    port    = 51820
    jumpserver_ip = var.create_jumpserver_eip ? aws_eip.jumpserver[0].public_ip : aws_instance.jumpserver.public_ip
    config_location = "/home/ubuntu/wireguard/config"
    setup_log = "/var/log/jumpserver-setup.log"
    status_file = "/home/ubuntu/jumpserver-setup-complete.txt"
    message = "WireGuard setup is enabled and configured"
    helpful_commands = [
      "ssh ubuntu@${var.create_jumpserver_eip ? aws_eip.jumpserver[0].public_ip : aws_instance.jumpserver.public_ip} 'sudo docker logs wireguard'",
      "ssh ubuntu@${var.create_jumpserver_eip ? aws_eip.jumpserver[0].public_ip : aws_instance.jumpserver.public_ip} './get-wireguard-configs.sh'",
      "ssh ubuntu@${var.create_jumpserver_eip ? aws_eip.jumpserver[0].public_ip : aws_instance.jumpserver.public_ip} 'ls /home/ubuntu/wireguard/config/'"
    ]
  } : {
    enabled = false
    peers   = 0
    port    = 0
    jumpserver_ip = ""
    config_location = ""
    setup_log = ""
    status_file = ""
    message = "WireGuard setup is disabled"
    helpful_commands = []
  }
}

