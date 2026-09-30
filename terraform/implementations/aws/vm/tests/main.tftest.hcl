mock_provider "aws" {
  override_data {
    target = data.aws_subnets.public
    values = { ids = ["subnet-pub2", "subnet-pub1"] }
  }
  override_data {
    target = data.aws_subnets.private
    values = { ids = ["subnet-priv1"] }
  }
}

variables {
  cluster_name        = "dev1"
  aws_provider_region = "ap-south-1"
  vpc_name            = "mosip-boxes"
  ami                 = "ami-0ad21ae1d0696ad58"
  ssh_key_name        = "mosip-aws"
}

run "groups_with_different_shapes_from_tfvars" {
  command = plan

  variables {
    instance_groups = {
      bastion = {
        instance_type           = "t3a.small"
        subnet                  = "public"
        ingress                 = [{ port = 22, cidrs = ["203.0.113.0/24"] }]
        iam_managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
      }
      tools = {
        instance_type = "t3a.medium"
      }
    }
  }

  assert {
    condition     = length(module.vm.security_group_ids) == 2
    error_message = "one security group per group"
  }
  assert {
    condition     = length(module.vm.iam_role_arns) == 1
    error_message = "only the bastion has policies"
  }
}

run "no_groups_is_a_no_op" {
  command = plan

  assert {
    condition     = length(module.vm.instances) == 0
    error_message = "default instance_groups = {} creates nothing"
  }
}
