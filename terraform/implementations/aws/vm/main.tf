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

# VPC: by default the base-infra VPC (Name = vpc_name from common.tfvars).
# vm.tfvars can instead pick the account's default VPC, a VPC by ID, or
# another VPC by name — at most one of them.
locals {
  vpc_by_name = var.vm_vpc_id == null && !var.vm_use_default_vpc
}

data "aws_vpc" "existing_vpc" {
  id      = var.vm_vpc_id
  default = var.vm_use_default_vpc ? true : null
  tags    = local.vpc_by_name ? { Name = coalesce(var.vm_vpc_name, var.vpc_name) } : null

  lifecycle {
    precondition {
      condition     = length(compact([var.vm_vpc_id, var.vm_vpc_name, var.vm_use_default_vpc ? "default" : null])) <= 1
      error_message = "Choose at most one of vm_use_default_vpc, vm_vpc_id and vm_vpc_name."
    }
  }
}

# Public subnets: Type = Public (base-infra convention); in the default VPC
# the default-for-az subnets. vm_public_subnet_ids / vm_private_subnet_ids
# override the lookup (VPCs not created by base-infra).
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing_vpc.id]
  }
  dynamic "filter" {
    for_each = var.vm_use_default_vpc ? [1] : []
    content {
      name   = "default-for-az"
      values = ["true"]
    }
  }
  tags = var.vm_use_default_vpc ? null : {
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
  public_subnet_ids       = var.vm_public_subnet_ids != null ? var.vm_public_subnet_ids : sort(data.aws_subnets.public.ids)
  private_subnet_ids      = var.vm_private_subnet_ids != null ? var.vm_private_subnet_ids : sort(data.aws_subnets.private.ids)
  default_ami             = var.ami
  default_key_name        = var.ssh_key_name
  allow_ssh_from_anywhere = var.allow_ssh_from_anywhere
  groups                  = var.instance_groups
}
