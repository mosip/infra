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

# nginx instance — discovered by tag from #275 (compute), not shared state.
data "aws_instance" "nginx" {
  filter {
    name   = "tag:Cluster"
    values = [var.cluster_name]
  }
  filter {
    name   = "tag:Role"
    values = ["nginx"]
  }
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

module "iam" {
  source = "../../../../modules/aws/iam"

  cluster_name      = var.cluster_name
  nginx_instance_id = data.aws_instance.nginx.id
}
