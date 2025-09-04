terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
  }
}

# provider "aws" {
# Profile `default` means it will take credentials AWS_SITE_KEY & AWS_SECRET_EKY from ~/.aws/config under `default` section.
# profile = "default"
# region = "ap-south-1"
# }


resource "aws_security_group" "security-group" {
  for_each = var.SECURITY_GROUP
  vpc_id   = var.VPC_ID
  tags = {
    Name      = "${var.CLUSTER_NAME}-${each.key}"
    Cluster   = var.CLUSTER_NAME
    Component = var.CLUSTER_NAME
  }
  description = "Rules which allow the outgoing traffic from the instances associated with the security group ${each.key}"

  dynamic "ingress" {
    for_each = each.value
    iterator = port
    content {
      description      = port.value.description
      from_port        = port.value.from_port
      to_port          = port.value.to_port
      protocol         = port.value.protocol
      cidr_blocks      = port.value.cidr_blocks
      ipv6_cidr_blocks = port.value.ipv6_cidr_blocks
    }
  }
  egress {
    description      = "Allow HTTP outbound to anywhere (for package downloads)"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  egress {
    description      = "Allow HTTPS outbound to anywhere"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  egress {
    description      = "Allow WireGuard VPN outbound to VPN CIDR"
    from_port        = 51820
    to_port          = 51820
    protocol         = "udp"
    cidr_blocks      = [var.WIREGUARD_CIDR]
    ipv6_cidr_blocks = []
  }
  egress {
    description      = "Allow DNS TCP outbound to anywhere (for public DNS resolution)"
    from_port        = 53
    to_port          = 53
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  egress {
    description      = "Allow DNS UDP outbound to anywhere (for public DNS resolution)"
    from_port        = 53
    to_port          = 53
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  egress {
    description      = "Allow all required internal communication to VPC CIDR"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  # Add more egress blocks for other trusted external IPs/services as needed
}

resource "aws_instance" "NGINX_EC2_INSTANCE" {

  ami                         = local.NGINX_INSTANCE.ami
  instance_type               = local.NGINX_INSTANCE.instance_type
  associate_public_ip_address = true # Always true - NGINX needs public IP in both scenarios
  key_name                    = local.NGINX_INSTANCE.key_name
  user_data                   = lookup(local.NGINX_INSTANCE, "user_data", "")
  vpc_security_group_ids      = local.NGINX_INSTANCE.security_groups
  subnet_id                   = var.PUBLIC_SUBNET_IDS[0]

  ## for ssl certificate generation
  iam_instance_profile = aws_iam_instance_profile.certbot_profile.name


  root_block_device {
    volume_size           = local.NGINX_INSTANCE.root_block_device.volume_size
    volume_type           = local.NGINX_INSTANCE.root_block_device.volume_type
    delete_on_termination = local.NGINX_INSTANCE.root_block_device.delete_on_termination
    encrypted             = local.NGINX_INSTANCE.root_block_device.encrypted
    tags                  = local.NGINX_INSTANCE.root_block_device.tags
  }

  dynamic "ebs_block_device" {
    for_each = local.NGINX_INSTANCE.ebs_block_device
    iterator = ebs_volume
    content {
      device_name           = ebs_volume.value.device_name
      volume_size           = ebs_volume.value.volume_size
      volume_type           = ebs_volume.value.volume_type
      delete_on_termination = ebs_volume.value.delete_on_termination
      encrypted             = ebs_volume.value.encrypted
      tags                  = ebs_volume.value.tags
    }
  }

  tags = {
    Name      = local.NGINX_INSTANCE.tags.Name
    Cluster   = local.NGINX_INSTANCE.tags.Cluster
    Component = var.CLUSTER_NAME
  }
}

# Wait for NGINX instance status checks to pass
resource "aws_ec2_instance_state" "nginx_instance_ready" {
  instance_id = aws_instance.NGINX_EC2_INSTANCE.id
  state       = "running"

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Wait for NGINX instance status checks (both system and instance status checks)
data "aws_instance" "nginx_status_check" {
  depends_on  = [aws_ec2_instance_state.nginx_instance_ready]
  instance_id = aws_instance.NGINX_EC2_INSTANCE.id

  # This will wait until the instance is fully ready
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

# Custom null resource to wait for all status checks
resource "null_resource" "nginx_status_checks" {
  depends_on = [data.aws_instance.nginx_status_check]

  provisioner "local-exec" {
    command = <<-EOF
      # Check if AWS CLI is available
      if ! command -v aws &> /dev/null; then
        echo "❌ AWS CLI is not installed or not in PATH"
        exit 1
      fi
      
      echo "Waiting for NGINX instance ${aws_instance.NGINX_EC2_INSTANCE.id} ALL status checks to pass..."
      echo "Checking: System Status, Instance Status, and Instance Reachability"
      
      # Wait for all 3 types of status checks to pass
      max_attempts=60
      attempt=0
      
      while [ $attempt -lt $max_attempts ]; do
        echo "Checking all status checks (attempt $((attempt + 1))/$max_attempts)..."
        
        # Get system status (Method 1: Direct query)
        system_status=$(aws ec2 describe-instance-status \
          --instance-ids ${aws_instance.NGINX_EC2_INSTANCE.id} \
          --query 'InstanceStatuses[0].SystemStatus.Status' \
          --output text \
          --region ${var.AWS_PROVIDER_REGION} 2>/dev/null || echo "not-available")
        
        # Get instance status (Method 1: Direct query)
        instance_status=$(aws ec2 describe-instance-status \
          --instance-ids ${aws_instance.NGINX_EC2_INSTANCE.id} \
          --query 'InstanceStatuses[0].InstanceStatus.Status' \
          --output text \
          --region ${var.AWS_PROVIDER_REGION} 2>/dev/null || echo "not-available")
        
        # Get instance state 
        instance_state=$(aws ec2 describe-instances \
          --instance-ids ${aws_instance.NGINX_EC2_INSTANCE.id} \
          --query 'Reservations[0].Instances[0].State.Name' \
          --output text \
          --region ${var.AWS_PROVIDER_REGION} 2>/dev/null || echo "unknown")
        
        # Get network interface status (connectivity check)
        network_interfaces=$(aws ec2 describe-instances \
          --instance-ids ${aws_instance.NGINX_EC2_INSTANCE.id} \
          --query 'Reservations[0].Instances[0].NetworkInterfaces[0].Status' \
          --output text \
          --region ${var.AWS_PROVIDER_REGION} 2>/dev/null || echo "unknown")
        
        # Additional reachability check via instance status
        reachability_status=$(aws ec2 describe-instance-status \
          --instance-ids ${aws_instance.NGINX_EC2_INSTANCE.id} \
          --query 'InstanceStatuses[0].InstanceState.Name' \
          --output text \
          --region ${var.AWS_PROVIDER_REGION} 2>/dev/null || echo "unknown")
        
        echo "📊 Status Report:"
        echo "   🖥️  System Status: $system_status"
        echo "   💻 Instance Status: $instance_status"
        echo "   🏃 Instance State: $instance_state"
        echo "   🌐 Network Interface: $network_interfaces"
        echo "   📡 Reachability: $reachability_status"
        
        # Check for any impaired status
        if [ "$system_status" = "impaired" ] || [ "$instance_status" = "impaired" ]; then
          echo "❌ NGINX instance ${aws_instance.NGINX_EC2_INSTANCE.id} has impaired status checks!"
          echo "   System Status: $system_status"
          echo "   Instance Status: $instance_status"
          exit 1
        fi
        
        # Check if instance is not running
        if [ "$instance_state" != "running" ]; then
          echo "❌ NGINX instance ${aws_instance.NGINX_EC2_INSTANCE.id} is not in running state: $instance_state"
          exit 1
        fi
        
        # Check if all status checks are OK (including network connectivity)
        if [ "$system_status" = "ok" ] && [ "$instance_status" = "ok" ] && [ "$instance_state" = "running" ] && [ "$network_interfaces" = "in-use" ]; then
          echo "✅ NGINX instance ${aws_instance.NGINX_EC2_INSTANCE.id} ALL status checks passed!"
          echo "   ✅ System Status: OK"
          echo "   ✅ Instance Status: OK"
          echo "   ✅ Instance State: Running"
          echo "   ✅ Network Interface: In-Use"
          echo "   ✅ Reachability: $reachability_status"
          break
        else
          echo "⏳ Waiting for all status checks to complete..."
          echo "   Current status: System($system_status), Instance($instance_status), State($instance_state), Network($network_interfaces)"
          sleep 30
          attempt=$((attempt + 1))
        fi
      done
      
      if [ $attempt -eq $max_attempts ]; then
        echo "❌ Timeout waiting for NGINX instance ALL status checks"
        echo "Final status: System($system_status), Instance($instance_status), State($instance_state), Network($network_interfaces)"
        exit 1
      fi
    EOF
  }

  triggers = {
    instance_id = aws_instance.NGINX_EC2_INSTANCE.id
  }
}
resource "aws_instance" "K8S_CLUSTER_EC2_INSTANCE" {
  for_each = merge(
    { for idx in range(var.K8S_CONTROL_PLANE_NODE_COUNT) : "CONTROL-PLANE-NODE-${idx + 1}" => idx },
    { for idx in range(var.K8S_ETCD_NODE_COUNT) : "ETCD-NODE-${idx + 1}" => idx },
    { for idx in range(var.K8S_WORKER_NODE_COUNT) : "WORKER-NODE-${idx + 1}" => idx }
  )

  ami                         = local.K8S_EC2_NODE.ami
  instance_type               = local.K8S_EC2_NODE.instance_type
  associate_public_ip_address = false # K8s instances always use private IPs
  key_name                    = local.K8S_EC2_NODE.key_name
  subnet_id                   = var.PRIVATE_SUBNET_IDS[each.value % length(var.PRIVATE_SUBNET_IDS)]
  user_data = templatefile("${path.module}/rke-user-data.sh.tpl", {
    index          = each.value
    role           = each.key
    cluster_domain = var.CLUSTER_NAME
  })

  vpc_security_group_ids = [
    can(regex("CONTROL-PLANE-NODE", each.key)) ? aws_security_group.security-group["K8S_CONTROL_PLANE_SECURITY_GROUP"].id :
    can(regex("ETCD-NODE", each.key)) ? aws_security_group.security-group["K8S_ETCD_SECURITY_GROUP"].id : aws_security_group.security-group["K8S_WORKER_SECURITY_GROUP"].id
  ]

  root_block_device {
    volume_size           = local.K8S_EC2_NODE.root_block_device.volume_size
    volume_type           = local.K8S_EC2_NODE.root_block_device.volume_type
    delete_on_termination = local.K8S_EC2_NODE.root_block_device.delete_on_termination
    encrypted             = local.K8S_EC2_NODE.root_block_device.encrypted
    tags = {
      Name      = "${local.K8S_EC2_NODE.tags.Name}-${each.key}"
      Cluster   = local.K8S_EC2_NODE.tags.Cluster
      Component = var.CLUSTER_NAME
    }
  }

  tags = {
    Name      = "${local.K8S_EC2_NODE.tags.Name}-${each.key}"
    Cluster   = local.K8S_EC2_NODE.tags.Cluster
    Component = var.CLUSTER_NAME
  }
}

# Wait for K8S cluster instances to be in running state
resource "aws_ec2_instance_state" "k8s_instances_ready" {
  for_each = aws_instance.K8S_CLUSTER_EC2_INSTANCE
  
  instance_id = each.value.id
  state       = "running"

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Wait for K8S instances status checks (both system and instance status checks)
data "aws_instance" "k8s_status_check" {
  for_each = aws_instance.K8S_CLUSTER_EC2_INSTANCE
  
  depends_on  = [aws_ec2_instance_state.k8s_instances_ready]
  instance_id = each.value.id

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

# Custom null resource to wait for all K8S instances status checks
resource "null_resource" "k8s_status_checks" {
  depends_on = [data.aws_instance.k8s_status_check]

  provisioner "local-exec" {
    command = <<-EOF
      # Check if AWS CLI is available
      if ! command -v aws &> /dev/null; then
        echo "❌ AWS CLI is not installed or not in PATH"
        exit 1
      fi
      
      echo "Waiting for ALL K8S cluster instances status checks to pass..."
      echo "Checking: System Status, Instance Status, and Instance Reachability for each instance"
      
      # Get all instance IDs
      instance_ids="${join(" ", [for instance in aws_instance.K8S_CLUSTER_EC2_INSTANCE : instance.id])}"
      echo "Monitoring instances: $instance_ids"
      
      max_attempts=60
      attempt=0
      
      while [ $attempt -lt $max_attempts ]; do
        echo "Checking ALL K8S instances status (attempt $((attempt + 1))/$max_attempts)..."
        
        all_passed=true
        failed_instances=""
        detailed_status=""
        
        for instance_id in $instance_ids; do
          # Get system status
          system_status=$(aws ec2 describe-instance-status \
            --instance-ids $instance_id \
            --query 'InstanceStatuses[0].SystemStatus.Status' \
            --output text \
            --region ${var.AWS_PROVIDER_REGION} 2>/dev/null || echo "not-available")
          
          # Get instance status
          instance_status=$(aws ec2 describe-instance-status \
            --instance-ids $instance_id \
            --query 'InstanceStatuses[0].InstanceStatus.Status' \
            --output text \
            --region ${var.AWS_PROVIDER_REGION} 2>/dev/null || echo "not-available")
          
          # Get instance state
          instance_state=$(aws ec2 describe-instances \
            --instance-ids $instance_id \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text \
            --region ${var.AWS_PROVIDER_REGION} 2>/dev/null || echo "unknown")
          
          # Get network interface status (connectivity check)
          network_interfaces=$(aws ec2 describe-instances \
            --instance-ids $instance_id \
            --query 'Reservations[0].Instances[0].NetworkInterfaces[0].Status' \
            --output text \
            --region ${var.AWS_PROVIDER_REGION} 2>/dev/null || echo "unknown")
          
          # Get reachability status 
          reachability_status=$(aws ec2 describe-instance-status \
            --instance-ids $instance_id \
            --query 'InstanceStatuses[0].InstanceState.Name' \
            --output text \
            --region ${var.AWS_PROVIDER_REGION} 2>/dev/null || echo "unknown")
          
          detailed_status="$detailed_status\n   Instance $instance_id: System($system_status), Instance($instance_status), State($instance_state), Network($network_interfaces), Reach($reachability_status)"
          
          # Check for failures
          if [ "$system_status" = "impaired" ] || [ "$instance_status" = "impaired" ]; then
            failed_instances="$failed_instances $instance_id"
            all_passed=false
          elif [ "$instance_state" != "running" ]; then
            failed_instances="$failed_instances $instance_id"
            all_passed=false
          elif [ "$system_status" != "ok" ] || [ "$instance_status" != "ok" ] || [ "$network_interfaces" != "in-use" ]; then
            all_passed=false
          fi
        done
        
        echo "📊 K8S Cluster Status Report:"
        echo -e "$detailed_status"
        
        if [ "$failed_instances" != "" ]; then
          echo "❌ K8S instances failed status checks: $failed_instances"
          exit 1
        fi
        
        if [ "$all_passed" = true ]; then
          echo "✅ ALL K8S instances status checks passed!"
          echo "   ✅ All System Status: OK"
          echo "   ✅ All Instance Status: OK" 
          echo "   ✅ All Instance States: Running"
          echo "   ✅ All Network Interfaces: In-Use"
          break
        else
          echo "⏳ Waiting for all K8S instances status checks to complete..."
          sleep 30
          attempt=$((attempt + 1))
        fi
      done
      
      if [ $attempt -eq $max_attempts ]; then
        echo "❌ Timeout waiting for K8S instances ALL status checks"
        echo -e "Final status:$detailed_status"
        exit 1
      fi
    EOF
  }

  triggers = {
    instance_ids = join(",", [for instance in aws_instance.K8S_CLUSTER_EC2_INSTANCE : instance.id])
  }
}

# DNS records creation - depends on all instances being ready
resource "aws_route53_record" "DNS_RECORDS" {
  depends_on = [
    null_resource.nginx_status_checks,
    null_resource.k8s_status_checks
  ]
  
  for_each = merge(local.MAP_DNS_TO_IP, var.DNS_RECORDS)
  name     = each.value.name
  type     = each.value.type
  zone_id  = each.value.zone_id
  ttl      = each.value.ttl
  records  = [each.value.records]
  # health_check_id = each.value.health_check_id // Uncomment if using health checks
  allow_overwrite = each.value.allow_overwrite
}
