mock_provider "aws" {
  override_data {
    target = data.aws_subnets.public_subnets
    values = {
      ids = ["subnet-0111111111111111", "subnet-0222222222222222"]
    }
  }

  override_data {
    target = data.aws_subnets.private_subnets
    values = {
      ids = ["subnet-0333333333333333", "subnet-0444444444444444"]
    }
  }

  override_resource {
    target = module.aws-resource-creation.aws_iam_policy.certbot_policy
    values = {
      arn = "arn:aws:iam::123456789012:policy/mock-certbot-policy"
    }
  }
}

variables {
  AWS_PROVIDER_REGION = "ap-south-1"
  CLUSTER_NAME        = "test-cluster"
  SSH_PRIVATE_KEY     = "test-private-key"
  SSH_KEY_NAME        = "test-ssh-key"

  K8S_CONTROL_PLANE_NODE_COUNT = 1
  K8S_ETCD_NODE_COUNT          = 0
  K8S_WORKER_NODE_COUNT        = 0

  CLUSTER_ENV_DOMAIN = "test.example.com"
  MOSIP_EMAIL_ID      = "test@example.com"

  K8S_INSTANCE_TYPE   = "t3a.large"
  NGINX_INSTANCE_TYPE = "t3a.large"
  AMI                 = "ami-0ad21ae1d0696ad58"
  ZONE_ID             = "Z1234567890ABC"

  K8S_INFRA_REPO_URL = "https://github.com/mosip/k8s-infra.git"

  NGINX_NODE_ROOT_VOLUME_SIZE   = 24
  NGINX_NODE_EBS_VOLUME_SIZE    = 64
  K8S_INSTANCE_ROOT_VOLUME_SIZE = 32

  network_cidr   = "10.0.0.0/16"
  WIREGUARD_CIDR = "10.0.0.0/16"

  vpc_name = "test-vpc"
}

run "postgresql_setup_created_when_enabled_and_volume_present" {
  command = plan

  variables {
    enable_postgresql_setup     = true
    nginx_node_ebs_volume_size_2 = 100
  }

  assert {
    condition     = length(module.postgresql-setup) == 1
    error_message = "Expected postgresql-setup module to be created when enable_postgresql_setup=true and nginx_node_ebs_volume_size_2>0"
  }
}

run "postgresql_setup_skipped_when_disabled" {
  command = plan

  variables {
    enable_postgresql_setup     = false
    nginx_node_ebs_volume_size_2 = 100
  }

  assert {
    condition     = length(module.postgresql-setup) == 0
    error_message = "Expected postgresql-setup module to be skipped when enable_postgresql_setup=false, even with a volume present"
  }
}

run "postgresql_setup_skipped_when_no_volume" {
  command = plan

  variables {
    enable_postgresql_setup     = true
    nginx_node_ebs_volume_size_2 = 0
  }

  assert {
    condition     = length(module.postgresql-setup) == 0
    error_message = "Expected postgresql-setup module to be skipped when nginx_node_ebs_volume_size_2=0, even with enable_postgresql_setup=true"
  }
}
