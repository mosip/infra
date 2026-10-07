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
    egress_all              = optional(bool, true)
    iam_managed_policy_arns = optional(list(string), [])
    iam_policy_json         = optional(string)
    tags                    = optional(map(string), {})
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
    condition = alltrue(flatten([
      for g in values(var.groups) : [
        for r in g.ingress : length(r.cidrs) + length(r.source_groups) > 0
      ]
    ]))
    error_message = "Every ingress rule needs at least one entry in cidrs or source_groups."
  }
}
