variable "cluster_name" {
  description = "Tags every resource (Cluster=<cluster_name>) and prefixes names"
  type        = string
}

variable "vpc_id" { type = string }

variable "public_subnet_ids" {
  type    = list(string)
  default = []
}

variable "private_subnet_ids" {
  type    = list(string)
  default = []
}

variable "default_ami" {
  description = "AMI for groups that don't set their own"
  type        = string
}

variable "default_key_name" {
  description = "EC2 key pair for groups that don't set their own"
  type        = string
  default     = null
}

variable "allow_ssh_from_anywhere" {
  description = "Permit ingress on port 22 from 0.0.0.0/0 (off by default)"
  type        = bool
  default     = false
}

variable "groups" {
  description = <<-EOT
    One entry per workload. Each gets its own security group, IAM role +
    instance profile (when it has policies) and `count` EC2 instances.
    Ingress sources: CIDRs and/or other groups in this map by name.
  EOT
  type = map(object({
    count          = optional(number, 1)
    instance_type  = string
    ami            = optional(string)
    key_name       = optional(string)
    subnet         = optional(string, "private") # public | private
    public_ip      = optional(bool)              # default: true for public subnets
    root_volume_gb = optional(number, 20)
    user_data      = optional(string)
    ingress = optional(list(object({
      port          = number
      to_port       = optional(number)
      protocol      = optional(string, "tcp")
      cidrs         = optional(list(string), [])
      source_groups = optional(list(string), [])
      description   = optional(string, "")
    })), [])
    egress_all = optional(bool, true)
    # Specific outbound rules (use with egress_all = false to restrict outbound).
    egress = optional(list(object({
      port        = number
      to_port     = optional(number)
      protocol    = optional(string, "tcp")
      cidrs       = list(string)
      description = optional(string, "")
    })), [])
    iam_managed_policy_arns = optional(list(string), [])
    iam_policy_json         = optional(string)
    tags                    = optional(map(string), {})
    state                   = optional(string) # running | stopped; unset = not managed after creation
    # AMI lookup (optional): newest image of this owner matching the name
    # pattern, for the instance type's CPU architecture. Unset = ami or
    # default_ami as before.
    ami_owner = optional(string)
    ami_name  = optional(string)
    # Extra EBS data disks (optional), attached at /dev/sdf, /dev/sdg, ...
    data_volumes = optional(list(object({
      size_gb    = number
      type       = optional(string, "gp3")
      iops       = optional(number)
      throughput = optional(number)
    })), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for name in keys(var.groups) :
      !contains(["nginx", "control-plane", "etcd", "worker"], name) && can(regex("^[a-z0-9][a-z0-9-]{0,30}$", name))
    ])
    error_message = "Group names must be lowercase [a-z0-9-] (max 31 chars) and not nginx/control-plane/etcd/worker, which the cluster components use as Role tags."
  }

  validation {
    condition     = alltrue([for g in values(var.groups) : contains(["public", "private"], g.subnet)])
    error_message = "subnet must be \"public\" or \"private\"."
  }

  validation {
    condition     = alltrue([for g in values(var.groups) : g.count >= 0 && g.count <= 20])
    error_message = "count must be between 0 and 20."
  }

  validation {
    condition     = alltrue([for g in values(var.groups) : g.iam_policy_json == null || can(jsondecode(g.iam_policy_json))])
    error_message = "iam_policy_json must be valid JSON."
  }

  validation {
    condition     = alltrue([for g in values(var.groups) : g.state == null || contains(["running", "stopped"], coalesce(g.state, "running"))])
    error_message = "state must be \"running\", \"stopped\" or unset."
  }

  validation {
    condition = alltrue(flatten([
      for g in values(var.groups) : [
        for r in g.ingress : length(r.cidrs) + length(r.source_groups) > 0
      ]
    ]))
    error_message = "Every ingress rule needs at least one entry in cidrs or source_groups."
  }

  validation {
    condition = alltrue(flatten([
      for g in values(var.groups) : [for r in g.egress : length(r.cidrs) > 0]
    ]))
    error_message = "Every egress rule needs at least one entry in cidrs."
  }

  validation {
    condition     = alltrue([for g in values(var.groups) : !(g.ami != null && g.ami_name != null)])
    error_message = "Set either ami (an AMI ID) or ami_name (+ ami_owner) for a group, not both."
  }

  validation {
    # An image name alone is not trusted: anyone can publish a matching name.
    condition = alltrue([for g in values(var.groups) :
      g.ami_name == null || (g.ami_owner != null && can(regex("^([0-9]{12}|amazon|aws-marketplace|self)$", coalesce(g.ami_owner, "x"))))
    ])
    error_message = "ami_name needs ami_owner: a 12-digit AWS account ID (e.g. 099720109477 Canonical, 309956199498 Red Hat) or amazon / aws-marketplace / self."
  }

  validation {
    condition = alltrue(flatten([for g in values(var.groups) : [
      length(g.data_volumes) <= 11,
      [for d in g.data_volumes : d.size_gb >= 1 && contains(["gp3", "gp2", "io1", "io2", "st1", "sc1"], d.type)],
    ]]))
    error_message = "data_volumes: at most 11 per instance (/dev/sdf-/dev/sdp), size_gb >= 1, type gp3 / gp2 / io1 / io2 / st1 / sc1."
  }
}
