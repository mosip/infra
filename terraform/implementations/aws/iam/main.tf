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

# Runs before compute: the compute root looks the instance profile up by
# name (<cluster_name>-certbot-instance-profile) and sets it on nginx.
module "iam" {
  source = "../../../modules/aws/iam"

  cluster_name     = var.cluster_name
  route53_zone_ids = coalesce(var.certbot_zone_ids, [var.zone_id])
}
