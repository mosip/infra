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

# ── VPC choice (vm_use_default_vpc / vm_vpc_id / vm_vpc_name) ────────────────

run "vpc_default_is_vpc_name_from_common_tfvars" {
  command = plan

  assert {
    condition     = data.aws_vpc.existing_vpc.tags["Name"] == "mosip-boxes"
    error_message = "Without VPC options the VPC is found by vpc_name (unchanged)"
  }
  assert {
    condition     = data.aws_subnets.public.tags == tomap({ Type = "Public" })
    error_message = "Public subnets still found by Type = Public"
  }
}

run "vpc_by_name_override" {
  command = plan

  variables {
    vm_vpc_name = "shared-tools-vpc"
  }

  assert {
    condition     = data.aws_vpc.existing_vpc.tags["Name"] == "shared-tools-vpc"
    error_message = "vm_vpc_name must override vpc_name"
  }
}

run "vpc_default_vpc_uses_default_for_az_subnets" {
  command = plan

  variables {
    vm_use_default_vpc = true
  }

  assert {
    condition = (
      data.aws_vpc.existing_vpc.default == true &&
      contains([for f in data.aws_subnets.public.filter : f.name], "default-for-az")
    )
    error_message = "default VPC + default-for-az subnets expected"
  }
}

run "vpc_by_id_with_explicit_subnets" {
  command = plan

  variables {
    vm_vpc_id            = "vpc-0123456789abcdef0"
    vm_public_subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"]
    instance_groups      = { tools = { instance_type = "t3a.large", subnet = "public" } }
  }

  assert {
    condition = (
      data.aws_vpc.existing_vpc.id == "vpc-0123456789abcdef0" &&
      module.vm.instances["tools-1"] != null
    )
    error_message = "vm_vpc_id must select that VPC"
  }
}

run "vpc_two_choices_rejected" {
  command = plan

  variables {
    vm_vpc_id   = "vpc-0123456789abcdef0"
    vm_vpc_name = "other"
  }

  expect_failures = [data.aws_vpc.existing_vpc]
}

run "vpc_bad_id_rejected" {
  command = plan

  variables {
    vm_vpc_id = "my-vpc"
  }

  expect_failures = [var.vm_vpc_id]
}
