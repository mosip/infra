terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
  }
}

# provider "aws" {
# Profile `default` means it will take credentials AWS_SITE_KEY & AWS_SECRET_EKY from ~/.aws/config under `default` section.
# profile = "default"
# region = "ap-south-1"
# }
provider "aws" {
  region = var.AWS_PROVIDER_REGION
}

locals {
  DNS_RECORDS = {
    #     API_DNS = {
    #       name            = "api.${var.MOSIP_DOMAIN}"
    #       type            = "A"
    #       zone_id         = var.ZONE_ID
    #       ttl             = 300
    #       records         = module.aws-resource-creation.aws_instance.NGINX_EC2_INSTANCE.public_ip
    #       allow_overwrite = true
    #     }
    #     API_INTERNAL_DNS = {
    #       name            = "api-internal.${var.MOSIP_DOMAIN}"
    #       type            = "A"
    #       zone_id         = var.ZONE_ID
    #       ttl             = 300
    #       records         = aws_instance.NGINX_EC2_INSTANCE.tags.Name == local.TAG_NAME.NGINX_TAG_NAME ? aws_instance.NGINX_EC2_INSTANCE.private_ip : ""
    #       allow_overwrite = true
    #     }
    MOSIP_HOMEPAGE_DNS = {
      name            = var.MOSIP_DOMAIN
      type            = "CNAME"
      zone_id         = var.ZONE_ID
      ttl             = 300
      records         = "api-internal.${var.MOSIP_DOMAIN}"
      allow_overwrite = true
    }
    ADMIN_DNS = {
      name            = "admin.${var.MOSIP_DOMAIN}"
      type            = "CNAME"
      zone_id         = var.ZONE_ID
      ttl             = 300
      records         = "api-internal.${var.MOSIP_DOMAIN}"
      allow_overwrite = true
    }
    PREREG_DNS = {
      name            = "prereg.${var.MOSIP_DOMAIN}"
      type            = "CNAME"
      zone_id         = var.ZONE_ID
      ttl             = 300
      records         = "api.${var.MOSIP_DOMAIN}"
      allow_overwrite = true
    }
    RESIDENT_DNS = {
      name            = "resident.${var.MOSIP_DOMAIN}"
      type            = "CNAME"
      zone_id         = var.ZONE_ID
      ttl             = 300
      records         = "api.${var.MOSIP_DOMAIN}"
      allow_overwrite = true
    }
    ESIGNET_DNS = {
      name            = "esignet.${var.MOSIP_DOMAIN}"
      type            = "CNAME"
      zone_id         = var.ZONE_ID
      ttl             = 300
      records         = "api.${var.MOSIP_DOMAIN}"
      allow_overwrite = true
    }
  }
}

module "aws-resource-creation" {
  #source = "github.com/syedsalman3753/mosip-infra//deployment/v3/terraform/aws/modules/aws-resource-creation?ref=develop"
  source = "./modules/aws-resource-creation"
  CLUSTER_NAME                  = var.CLUSTER_NAME
  AWS_PROVIDER_REGION           = var.AWS_PROVIDER_REGION
  SSH_KEY_NAME                  = var.SSH_KEY_NAME
  K8S_INSTANCE_TYPE             = var.K8S_INSTANCE_TYPE
  NGINX_INSTANCE_TYPE           = var.NGINX_INSTANCE_TYPE
  MOSIP_DOMAIN                  = var.MOSIP_DOMAIN
  ZONE_ID                       = var.ZONE_ID
  AMI                           = var.AMI
  K8S_INSTANCE_COUNT            = var.K8S_INSTANCE_COUNT
  K8S_INSTANCE_ROOT_VOLUME_SIZE = var.K8S_INSTANCE_ROOT_VOLUME_SIZE

  NGINX_NODE_EBS_VOLUME_SIZE  = var.NGINX_NODE_EBS_VOLUME_SIZE
  NGINX_NODE_ROOT_VOLUME_SIZE = var.NGINX_NODE_ROOT_VOLUME_SIZE

  SECURITY_GROUP = {
    NGINX_SECURITY_GROUP = [
      {
        description : "SSH login port"
        from_port : 22,
        to_port : 22,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "HTTP port"
        from_port : 80,
        to_port : 80,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "HTTPS port"
        from_port : 443,
        to_port : 443,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Minio console port"
        from_port : 9000,
        to_port : 9000,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "Postgres port"
        from_port : 5432,
        to_port : 5432,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      }
    ]
    K8S_SECURITY_GROUP = [
      {
        description : "K8s port"
        from_port : 6443,
        to_port : 6443,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "SSH login port"
        from_port : 22,
        to_port : 22,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "HTTP port"
        from_port : 80,
        to_port : 80,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      },
      {
        description : "HTTPS port"
        from_port : 443,
        to_port : 443,
        protocol : "TCP",
        cidr_blocks      = ["0.0.0.0/0"],
        ipv6_cidr_blocks = ["::/0"]
      }
    ]
  }
  DNS_RECORDS = local.DNS_RECORDS
}

module "nginx-setup" {
  depends_on = [module.aws-resource-creation]
  #source     = "github.com/syedsalman3753/mosip-infra//deployment/v3/terraform/aws/modules/nginx-setup?ref=develop"
  source                                  = "./modules/nginx-setup"
  NGINX_PUBLIC_IP                         = module.aws-resource-creation.NGINX_PUBLIC_IP
  MOSIP_DOMAIN                            = var.MOSIP_DOMAIN
  MOSIP_K8S_CLUSTER_NODES_PRIVATE_IP_LIST = module.aws-resource-creation.MOSIP_K8S_CLUSTER_NODES_PRIVATE_IP_LIST
  MOSIP_PUBLIC_DOMAIN_LIST                = module.aws-resource-creation.MOSIP_PUBLIC_DOMAIN_LIST
  CERTBOT_EMAIL                           = var.MOSIP_EMAIL_ID
  SSH_PRIVATE_KEY                         = var.SSH_PRIVATE_KEY
  K8S_INFRA_BRANCH                        = var.K8S_INFRA_BRANCH
}
