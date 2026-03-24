# ActiveMQ Configuration Variables
variable "enable_activemq_setup" {
  description = "Enable ActiveMQ EBS volume setup on the NGINX node"
  type        = bool
  default     = false
}

variable "nginx_node_ebs_volume_size_3" {
  description = "EBS volume size (GB) for ActiveMQ data on the NGINX node — set to 0 to disable"
  type        = number
  default     = 0
}

variable "activemq_storage_device" {
  description = "Block device path of the 3rd EBS volume for ActiveMQ"
  type        = string
  default     = "/dev/nvme3n1"
}

variable "activemq_mount_point" {
  description = "Mount point for ActiveMQ persistent storage"
  type        = string
  default     = "/srv/activemq"
}
