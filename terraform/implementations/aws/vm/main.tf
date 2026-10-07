terraform {
  required_version = ">= 1.6"

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

# Standalone EC2 workloads (bastion, tools box, a DB VM, ...), each with its
# own security group and IAM policy, in the base-infra VPC. Independent of
# the cluster components: own state, not part of COMPONENT=all.

data "aws_vpc" "existing_vpc" {
  tags = {
    Name = var.vpc_name
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing_vpc.id]
  }
  tags = {
    Type = "Public"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing_vpc.id]
  }
  tags = {
    Type = "Private"
  }
}

module "vm" {
  source = "../../../modules/aws/instance-group"

  cluster_name            = var.cluster_name
  vpc_id                  = data.aws_vpc.existing_vpc.id
  public_subnet_ids       = sort(data.aws_subnets.public.ids)
  private_subnet_ids      = sort(data.aws_subnets.private.ids)
  default_ami             = var.ami
  default_key_name        = var.ssh_key_name
  allow_ssh_from_anywhere = var.allow_ssh_from_anywhere
  groups                  = var.instance_groups
}
