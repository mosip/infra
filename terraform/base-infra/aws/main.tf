# AWS Base Infrastructure Implementation

# Create VPC
resource "aws_vpc" "main" {
  cidr_block           = var.network_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = {
    Name        = var.network_name
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.network_name}-igw"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create Public Subnets
resource "aws_subnet" "public" {
  count = length(var.public_subnets)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.availability_zones[count.index % length(var.availability_zones)]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.network_name}-public-subnet-${count.index + 1}"
    Type        = "Public"
    Environment = var.environment
    Project     = var.project_name
    AZ          = var.availability_zones[count.index % length(var.availability_zones)]
  }
}

# Create Private Subnets
resource "aws_subnet" "private" {
  count = length(var.private_subnets)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index % length(var.availability_zones)]

  tags = {
    Name        = "${var.network_name}-private-subnet-${count.index + 1}"
    Type        = "Private"
    Environment = var.environment
    Project     = var.project_name
    AZ          = var.availability_zones[count.index % length(var.availability_zones)]  
  }
}

# Create Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.public_subnets)) : 0

  domain = "vpc"

  tags = {
    Name        = "${var.network_name}-nat-eip-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }

  depends_on = [aws_internet_gateway.main]
}

# Create NAT Gateways
resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.public_subnets)) : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name        = "${var.network_name}-nat-gateway-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }

  depends_on = [aws_internet_gateway.main]
}

# Create Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.network_name}-public-rt"
    Type        = "Public"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Associate Public Subnets with Public Route Table
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Create Private Route Tables
resource "aws_route_table" "private" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.private_subnets)) : 0

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.main[0].id : aws_nat_gateway.main[count.index % length(aws_nat_gateway.main)].id
  }

  tags = {
    Name        = "${var.network_name}-private-rt-${count.index + 1}"
    Type        = "Private"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Associate Private Subnets with Private Route Tables
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = var.single_nat_gateway ? aws_route_table.private[0].id : aws_route_table.private[count.index % length(aws_route_table.private)].id
}

# Create Jump Server Security Group
resource "aws_security_group" "jumpserver" {
  name        = "${var.jumpserver_name}-sg"
  description = "Security group for jump server"
  vpc_id      = aws_vpc.main.id

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # WireGuard VPN access
  ingress {
    from_port   = 51820
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "WireGuard VPN access"
  }

  # HTTP access
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP web traffic"
  }

  # HTTPS access
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS web traffic"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.jumpserver_name}-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}


# Create Jump Server EC2 Instance
resource "aws_instance" "jumpserver" {
  ami                         = var.jumpserver_ami_id
  instance_type               = var.jumpserver_instance_type
  key_name                    = var.ssh_key_name
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.jumpserver.id]
  associate_public_ip_address = true

  # User data script for automated setup
  user_data = templatefile("${path.module}/jumpserver-setup.sh.tpl", {
    k8s_infra_repo_url     = var.k8s_infra_repo_url
    k8s_infra_branch       = var.k8s_infra_branch
    wireguard_peers        = var.wireguard_peers
    enable_wireguard_setup = var.enable_wireguard_setup
    jumpserver_name        = var.jumpserver_name
  })

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 64
    delete_on_termination = true
  }

  tags = {
    Name        = var.jumpserver_name
    Environment = var.environment
    Project     = var.project_name
  }
  
  depends_on = [aws_internet_gateway.main]
}

# Create Elastic IP for Jump Server (conditionally)
resource "aws_eip" "jumpserver" {
  count    = var.create_jumpserver_eip ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.jumpserver.id
  
  tags = {
    Name        = "${var.jumpserver_name}-eip"
    Environment = var.environment
    Project     = var.project_name
  }

  depends_on = [aws_internet_gateway.main]
}
