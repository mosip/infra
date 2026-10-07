variable "cluster_name" { type = string }

variable "nginx_instance_id" {
  description = "Instance to attach the certbot IAM profile to — looked up by tag from #275's compute component"
  type        = string
}
