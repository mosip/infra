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
# component, not shared state. compute must have been applied first.
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

module "storage" {
  source = "../../../../modules/aws/storage"

  cluster_name      = var.cluster_name
  nginx_instance_id = data.aws_instance.nginx.id
  availability_zone = data.aws_instance.nginx.availability_zone
  nginx_tag_name    = "${var.cluster_name}-NGINX-NODE"

  nginx_node_ebs_volume_size   = var.nginx_node_ebs_volume_size
  nginx_node_ebs_volume_size_2 = var.nginx_node_ebs_volume_size_2
  nginx_node_ebs_volume_size_3 = var.nginx_node_ebs_volume_size_3
  enable_activemq_setup        = var.enable_activemq_setup
}
