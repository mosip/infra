terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
  }
}

provider "aws" {
  region = var.aws_provider_region
}

# Data source to get all availability zones in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# Use specific AZs if provided, otherwise use all available AZs.
locals {
  selected_azs = length(var.specific_availability_zones) > 0 ? var.specific_availability_zones : data.aws_availability_zones.available.names
}

data "aws_vpc" "existing_vpc" {
  tags = {
    Name = var.vpc_name
  }
}

data "aws_subnets" "public_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing_vpc.id]
  }
  filter {
    name   = "availability-zone"
    values = local.selected_azs
  }
  tags = {
    Type = "Public"
  }
}

data "aws_subnets" "private_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing_vpc.id]
  }
  filter {
    name   = "availability-zone"
    values = local.selected_azs
  }
  tags = {
    Type = "Private"
  }
}

# Security group IDs — discovered by tag from observ-infra's own security
# component, not a module-source reference or shared state. security must
# have been applied first.
data "aws_security_group" "nginx" {
  filter {
    name   = "tag:Cluster"
    values = [var.cluster_name]
  }
  filter {
    name   = "tag:Role"
    values = ["nginx"]
  }
}

data "aws_security_group" "k8s_control_plane" {
  filter {
    name   = "tag:Cluster"
    values = [var.cluster_name]
  }
  filter {
    name   = "tag:Role"
    values = ["control-plane"]
  }
}

data "aws_security_group" "k8s_etcd" {
  filter {
    name   = "tag:Cluster"
    values = [var.cluster_name]
  }
  filter {
    name   = "tag:Role"
    values = ["etcd"]
  }
}

data "aws_security_group" "k8s_worker" {
  filter {
    name   = "tag:Cluster"
    values = [var.cluster_name]
  }
  filter {
    name   = "tag:Role"
    values = ["worker"]
  }
}

module "compute" {
  source = "../../../../modules/aws/compute"

  cluster_name                  = var.cluster_name
  ami                           = var.ami
  ssh_key_name                  = var.ssh_key_name
  nginx_instance_type           = var.nginx_instance_type
  k8s_instance_type             = var.k8s_instance_type
  nginx_node_root_volume_size   = var.nginx_node_root_volume_size
  k8s_instance_root_volume_size = var.k8s_instance_root_volume_size

  public_subnet_ids  = data.aws_subnets.public_subnets.ids
  private_subnet_ids = data.aws_subnets.private_subnets.ids

  nginx_sg_id             = data.aws_security_group.nginx.id
  k8s_control_plane_sg_id = data.aws_security_group.k8s_control_plane.id
  k8s_etcd_sg_id          = data.aws_security_group.k8s_etcd.id
  k8s_worker_sg_id        = data.aws_security_group.k8s_worker.id

  k8s_control_plane_node_count = var.k8s_control_plane_node_count
  k8s_etcd_node_count          = var.k8s_etcd_node_count
  k8s_worker_node_count        = var.k8s_worker_node_count
}
