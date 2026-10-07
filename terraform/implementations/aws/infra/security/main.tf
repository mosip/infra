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

# Existing VPC, discovered by Name tag — same convention as the pre-#273 monolith.
# base-infra creates this VPC once; every decoupled component looks it up the same way.
data "aws_vpc" "existing_vpc" {
  tags = {
    Name = var.vpc_name
  }
}

module "security" {
  source = "../../../../modules/aws/security"

  cluster_name   = var.cluster_name
  vpc_id         = data.aws_vpc.existing_vpc.id
  network_cidr   = var.network_cidr
  wireguard_cidr = var.WIREGUARD_CIDR
}
