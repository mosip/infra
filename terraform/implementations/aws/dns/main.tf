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

# Record targets: explicit IPs when given (e.g. a data-centre nginx whose
# domain lives in Route53), otherwise the nginx instance from the compute
# component, found by tag.
data "aws_instance" "nginx" {
  count = var.nginx_public_ip == null ? 1 : 0

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

# Subdomains: profiles/<profile>/profile.yml is the single source (the data
# centre path reads the same file); tfvars can still override either list.
locals {
  manifest_public   = var.profile_manifest != null ? tolist(try(yamldecode(file(var.profile_manifest)).subdomain_public, [])) : []
  manifest_internal = var.profile_manifest != null ? tolist(try(yamldecode(file(var.profile_manifest)).subdomain_internal, [])) : []

  subdomain_public   = var.subdomain_public != null ? var.subdomain_public : local.manifest_public
  subdomain_internal = var.subdomain_internal != null ? var.subdomain_internal : local.manifest_internal

  # With explicit IPs and no private one, api-internal points at the same
  # address (a single-homed data-centre nginx).
  nginx_public_ip  = coalesce(var.nginx_public_ip, try(data.aws_instance.nginx[0].public_ip, null))
  nginx_private_ip = coalesce(var.nginx_private_ip, try(data.aws_instance.nginx[0].private_ip, null), var.nginx_public_ip)
}

module "dns" {
  source = "../../../modules/aws/dns"

  cluster_env_domain = var.cluster_env_domain
  nginx_public_ip    = local.nginx_public_ip
  nginx_private_ip   = local.nginx_private_ip
  subdomain_public   = local.subdomain_public
  subdomain_internal = local.subdomain_internal

  zone_id         = length(var.zones) > 0 ? null : var.zone_id
  zones           = var.zones
  public_zone     = var.public_zone
  internal_zone   = var.internal_zone
  ttl             = var.ttl
  allow_overwrite = var.allow_overwrite
  extra_records   = var.extra_records
}
