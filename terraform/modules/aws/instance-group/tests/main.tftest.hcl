# instance-group: one workload = security group + IAM role/profile + EC2,
# created together. Mocked provider, plan only.

mock_provider "aws" {}

variables {
  cluster_name       = "dev1"
  vpc_id             = "vpc-123"
  public_subnet_ids  = ["subnet-pub1", "subnet-pub2"]
  private_subnet_ids = ["subnet-priv1", "subnet-priv2"]
  default_ami        = "ami-0ad21ae1d0696ad58"
  default_key_name   = "mosip-aws"

  groups = {
    bastion = {
      instance_type           = "t3a.small"
      subnet                  = "public"
      ingress                 = [{ port = 22, cidrs = ["203.0.113.0/24"], description = "office SSH" }]
      iam_managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
    }
    reports-db = {
      count         = 2
      instance_type = "t3a.large"
      ingress       = [{ port = 5432, source_groups = ["bastion"] }]
      iam_policy_json = jsonencode({
        Version   = "2012-10-17"
        Statement = [{ Effect = "Allow", Action = ["s3:GetObject"], Resource = "arn:aws:s3:::reports/*" }]
      })
    }
  }
}

run "each_group_gets_its_own_security_group_and_role_tag" {
  command = plan

  assert {
    condition     = aws_security_group.group["bastion"].name == "dev1-bastion" && aws_security_group.group["bastion"].tags["Role"] == "bastion"
    error_message = "security group must be named <cluster>-<group> and tagged Role=<group>"
  }
  assert {
    condition     = aws_security_group.group["reports-db"].tags["Cluster"] == "dev1"
    error_message = "every resource must carry Cluster=<cluster_name>"
  }
}

run "instances_count_subnets_and_hardening" {
  command = plan

  assert {
    condition     = length(aws_instance.vm) == 3
    error_message = "1 bastion + 2 reports-db instances expected"
  }
  assert {
    condition     = aws_instance.vm["bastion-1"].subnet_id == "subnet-pub1" && aws_instance.vm["bastion-1"].associate_public_ip_address == true
    error_message = "public group must land in a public subnet with a public IP"
  }
  assert {
    condition     = aws_instance.vm["reports-db-2"].subnet_id == "subnet-priv2" && aws_instance.vm["reports-db-2"].associate_public_ip_address == false
    error_message = "private group instances round-robin over private subnets, no public IP"
  }
  assert {
    condition     = alltrue([for i in aws_instance.vm : i.metadata_options[0].http_tokens == "required" && i.root_block_device[0].encrypted == true])
    error_message = "every instance must require IMDSv2 and encrypt its root volume"
  }
  assert {
    condition     = aws_instance.vm["bastion-1"].key_name == "mosip-aws" && aws_instance.vm["bastion-1"].ami == "ami-0ad21ae1d0696ad58"
    error_message = "groups without their own ami/key_name use the defaults"
  }
}

run "iam_profile_attached_at_creation" {
  command = plan

  assert {
    condition     = aws_instance.vm["bastion-1"].iam_instance_profile == "dev1-bastion-profile"
    error_message = "the group's instance profile must be set on the instance at creation"
  }
  assert {
    condition     = aws_iam_role_policy_attachment.managed["bastion/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"].role == "dev1-bastion-role"
    error_message = "managed policies attach to the group's role"
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.inline["reports-db"].policy).Statement[0].Action[0] == "s3:GetObject"
    error_message = "inline policy JSON must be applied as-is"
  }
}

run "ingress_by_cidr_and_by_other_group" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.cidr["bastion/0/203.0.113.0/24"].from_port == 22
    error_message = "CIDR rule must open the given port"
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.from_group["reports-db/0/bastion"].from_port == 5432
    error_message = "group-to-group rule must open the given port"
  }
  assert {
    condition     = length(aws_vpc_security_group_egress_rule.all) == 2
    error_message = "egress_all defaults to true for every group"
  }
}

run "group_without_policies_has_no_role" {
  command = plan

  variables {
    groups = { tools = { instance_type = "t3a.medium" } }
  }

  assert {
    condition     = length(aws_iam_role.group) == 0 && length(aws_iam_instance_profile.group) == 0
    error_message = "no IAM resources for a group without policies"
  }
}

run "empty_map_creates_nothing" {
  command = plan

  variables {
    groups = {}
  }

  assert {
    condition     = length(aws_instance.vm) == 0 && length(aws_security_group.group) == 0
    error_message = "no groups, no resources"
  }
}

run "ssh_from_anywhere_is_rejected" {
  command = plan

  variables {
    groups = {
      open = { instance_type = "t3a.small", subnet = "public", ingress = [{ port = 22, cidrs = ["0.0.0.0/0"] }] }
    }
  }

  expect_failures = [aws_vpc_security_group_ingress_rule.cidr]
}

run "ssh_from_anywhere_allowed_when_opted_in" {
  command = plan

  variables {
    allow_ssh_from_anywhere = true
    groups = {
      open = { instance_type = "t3a.small", subnet = "public", ingress = [{ port = 22, cidrs = ["0.0.0.0/0"] }] }
    }
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.cidr) == 1
    error_message = "explicit opt-in must allow the rule"
  }
}

run "reserved_group_names_rejected" {
  command = plan

  variables {
    groups = { nginx = { instance_type = "t3a.small" } }
  }

  expect_failures = [var.groups]
}

run "rule_without_source_rejected" {
  command = plan

  variables {
    groups = { x = { instance_type = "t3a.small", ingress = [{ port = 80 }] } }
  }

  expect_failures = [var.groups]
}

run "invalid_policy_json_rejected" {
  command = plan

  variables {
    groups = { x = { instance_type = "t3a.small", iam_policy_json = "{not json" } }
  }

  expect_failures = [var.groups]
}

run "unknown_source_group_rejected" {
  command = plan

  variables {
    groups = { db = { instance_type = "t3a.small", ingress = [{ port = 5432, source_groups = ["nope"] }] } }
  }

  expect_failures = [aws_vpc_security_group_ingress_rule.from_group]
}
