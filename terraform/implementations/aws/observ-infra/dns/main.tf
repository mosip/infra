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

# nginx instance — discovered by tag from observ-infra's own compute
# component, not shared state.
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

module "dns" {
  source = "../../../../modules/aws/dns"

  cluster_env_domain = var.cluster_env_domain
  zone_id            = var.zone_id
  nginx_public_ip    = data.aws_instance.nginx.public_ip
  nginx_private_ip   = data.aws_instance.nginx.private_ip
  subdomain_public   = var.subdomain_public
  subdomain_internal = var.subdomain_internal
}
