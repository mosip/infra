terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
  }
}

# A group is one workload: security group + IAM role/profile + instances,
# created together in one apply. Everything is tagged Cluster=<cluster_name>,
# Role=<group>, so other components (dns extra_records, the inventory) can
# find the instances the same way they find the cluster's.

locals {
  common_tags = { Cluster = var.cluster_name, Component = var.cluster_name }

  # Flattened ingress rules: one resource per (group, rule, source).
  ingress_cidr_rules = merge([
    for g, cfg in var.groups : merge([
      for i, rule in cfg.ingress : {
        for cidr in rule.cidrs :
        "${g}/${i}/${cidr}" => merge(rule, { group = g, cidr = cidr })
      }
    ]...)
  ]...)

  # Flattened egress rules: one resource per (group, rule, destination).
  egress_cidr_rules = merge([
    for g, cfg in var.groups : merge([
      for i, rule in cfg.egress : {
        for cidr in rule.cidrs :
        "${g}/${i}/${cidr}" => merge(rule, { group = g, cidr = cidr })
      }
    ]...)
  ]...)

  ingress_group_rules = merge([
    for g, cfg in var.groups : merge([
      for i, rule in cfg.ingress : {
        for src in rule.source_groups :
        "${g}/${i}/${src}" => merge(rule, { group = g, source = src })
      }
    ]...)
  ]...)

  # Groups that look their AMI up by owner + name (none by default).
  ami_lookup_groups = { for g, cfg in var.groups : g => cfg if cfg.ami_name != null }

  # Extra data disks: one volume per (instance, entry), at /dev/sdf, /dev/sdg, ...
  # (Ubuntu AMIs reserve sdb/sdc). None by default.
  data_devices = ["/dev/sdf", "/dev/sdg", "/dev/sdh", "/dev/sdi", "/dev/sdj", "/dev/sdk", "/dev/sdl", "/dev/sdm", "/dev/sdn", "/dev/sdo", "/dev/sdp"]
  data_volumes = merge([
    for k, inst in local.instances : {
      for i, d in inst.data_volumes : "${k}/${i}" => merge(d, { instance = k, index = i, group = inst.group })
    }
  ]...)

  with_iam = {
    for g, cfg in var.groups : g => cfg
    if length(cfg.iam_managed_policy_arns) > 0 || cfg.iam_policy_json != null
  }

  instances = merge([
    for g, cfg in var.groups : {
      for i in range(cfg.count) : "${g}-${i + 1}" => merge(cfg, { group = g, index = i })
    }
  ]...)
}

# ── security groups ────────────────────────────────────────────────────────

resource "aws_security_group" "group" {
  for_each    = var.groups
  name        = "${var.cluster_name}-${each.key}"
  description = "${var.cluster_name} ${each.key} (instance-group)"
  vpc_id      = var.vpc_id
  tags        = merge(local.common_tags, each.value.tags, { Name = "${var.cluster_name}-${each.key}", Role = each.key })
}

resource "aws_vpc_security_group_ingress_rule" "cidr" {
  for_each          = local.ingress_cidr_rules
  security_group_id = aws_security_group.group[each.value.group].id
  cidr_ipv4         = each.value.cidr
  ip_protocol       = each.value.protocol
  from_port         = each.value.protocol == "-1" ? null : each.value.port
  to_port           = each.value.protocol == "-1" ? null : coalesce(each.value.to_port, each.value.port)
  description       = each.value.description

  lifecycle {
    precondition {
      condition     = var.allow_ssh_from_anywhere || !(each.value.cidr == "0.0.0.0/0" && each.value.port <= 22 && coalesce(each.value.to_port, each.value.port) >= 22)
      error_message = "Group ${each.value.group} opens SSH (22) to 0.0.0.0/0. Restrict the CIDR or set allow_ssh_from_anywhere = true."
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_group" {
  for_each                     = local.ingress_group_rules
  security_group_id            = aws_security_group.group[each.value.group].id
  referenced_security_group_id = aws_security_group.group[each.value.source].id
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.protocol == "-1" ? null : each.value.port
  to_port                      = each.value.protocol == "-1" ? null : coalesce(each.value.to_port, each.value.port)
  description                  = each.value.description

  lifecycle {
    precondition {
      condition     = contains(keys(var.groups), each.value.source)
      error_message = "Group ${each.value.group} allows traffic from '${each.value.source}', which isn't a group in this map."
    }
  }
}

# Specific outbound rules per group (vm.tfvars: egress = [...]).
resource "aws_vpc_security_group_egress_rule" "cidr" {
  for_each          = local.egress_cidr_rules
  security_group_id = aws_security_group.group[each.value.group].id
  cidr_ipv4         = each.value.cidr
  ip_protocol       = each.value.protocol
  from_port         = each.value.protocol == "-1" ? null : each.value.port
  to_port           = each.value.protocol == "-1" ? null : coalesce(each.value.to_port, each.value.port)
  description       = each.value.description
}

resource "aws_vpc_security_group_egress_rule" "all" {
  for_each          = { for g, cfg in var.groups : g => cfg if cfg.egress_all }
  security_group_id = aws_security_group.group[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "all outbound"
}

# ── IAM (only for groups with policies) ───────────────────────────────────

resource "aws_iam_role" "group" {
  for_each = local.with_iam
  name     = "${var.cluster_name}-${each.key}-role"
  tags     = merge(local.common_tags, each.value.tags, { Role = each.key })
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = merge([
    for g, cfg in local.with_iam : { for arn in cfg.iam_managed_policy_arns : "${g}/${arn}" => { group = g, arn = arn } }
  ]...)
  role       = aws_iam_role.group[each.value.group].name
  policy_arn = each.value.arn
}

resource "aws_iam_role_policy" "inline" {
  for_each = { for g, cfg in local.with_iam : g => cfg if cfg.iam_policy_json != null }
  name     = "${var.cluster_name}-${each.key}-inline"
  role     = aws_iam_role.group[each.key].id
  policy   = each.value.iam_policy_json
}

resource "aws_iam_instance_profile" "group" {
  for_each = local.with_iam
  name     = "${var.cluster_name}-${each.key}-profile"
  role     = aws_iam_role.group[each.key].name
  tags     = merge(local.common_tags, { Role = each.key })
}

# ── instances ─────────────────────────────────────────────────────────────

# ── AMI lookup (only for groups with ami_name) ───────────────────────────────
data "aws_ec2_instance_type" "lookup" {
  for_each      = toset([for g, cfg in local.ami_lookup_groups : cfg.instance_type])
  instance_type = each.key
}

data "aws_ami" "lookup" {
  for_each    = local.ami_lookup_groups
  most_recent = true
  owners      = [each.value.ami_owner]

  filter {
    name   = "name"
    values = [each.value.ami_name]
  }
  filter {
    name   = "architecture"
    values = [contains(data.aws_ec2_instance_type.lookup[each.value.instance_type].supported_architectures, "arm64") ? "arm64" : "x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_instance" "vm" {
  for_each = local.instances

  # Explicit ami > owner + name lookup > default_ami (common.tfvars).
  ami                         = coalesce(each.value.ami, try(data.aws_ami.lookup[each.value.group].id, null), var.default_ami)
  instance_type               = each.value.instance_type
  key_name                    = each.value.key_name != null ? each.value.key_name : var.default_key_name
  subnet_id                   = each.value.subnet == "public" ? var.public_subnet_ids[each.value.index % length(var.public_subnet_ids)] : var.private_subnet_ids[each.value.index % length(var.private_subnet_ids)]
  associate_public_ip_address = coalesce(each.value.public_ip, each.value.subnet == "public")
  vpc_security_group_ids      = [aws_security_group.group[each.value.group].id]
  iam_instance_profile        = contains(keys(local.with_iam), each.value.group) ? aws_iam_instance_profile.group[each.value.group].name : null
  user_data                   = each.value.user_data

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size           = each.value.root_volume_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
    tags                  = merge(local.common_tags, { Name = "${var.cluster_name}-${each.key}", Role = each.value.group })
  }

  tags = merge(local.common_tags, each.value.tags, {
    Name = "${var.cluster_name}-${each.key}"
    Role = each.value.group
  })

  lifecycle {
    ignore_changes = [user_data, ami]

    precondition {
      condition     = length(each.value.subnet == "public" ? var.public_subnet_ids : var.private_subnet_ids) > 0
      error_message = "Group ${each.value.group} wants a ${each.value.subnet} subnet but none were found in the VPC."
    }
  }
}

# Optional desired power state per group (vm.tfvars: state = "running" |
# "stopped"). Unset = not managed after creation (instance-power workflow).
resource "aws_ec2_instance_state" "vm" {
  for_each    = { for k, inst in local.instances : k => inst if inst.state != null }
  instance_id = aws_instance.vm[each.key].id
  state       = each.value.state

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# ── extra data disks (vm.tfvars: data_volumes) ───────────────────────────────
resource "aws_ebs_volume" "data" {
  for_each          = local.data_volumes
  availability_zone = aws_instance.vm[each.value.instance].availability_zone
  size              = each.value.size_gb
  type              = each.value.type
  iops              = each.value.iops
  throughput        = each.value.throughput
  encrypted         = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-${each.value.instance}-data-${each.value.index + 1}"
    Role = each.value.group
  })
}

resource "aws_volume_attachment" "data" {
  for_each    = local.data_volumes
  device_name = local.data_devices[each.value.index]
  volume_id   = aws_ebs_volume.data[each.key].id
  instance_id = aws_instance.vm[each.value.instance].id
}
