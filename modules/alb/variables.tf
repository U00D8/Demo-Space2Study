# modules/alb/variables.tf

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID for ALB"
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN"
  type        = string
}

variable "domain_name" {
  description = "Domain name"
  type        = string
}

variable "jenkins_instance_id" {
  description = "Jenkins EC2 instance ID"
  type        = string
}

variable "k3s_worker_instance_ids" {
  description = "Map of K3s worker node instance IDs for ingress target group (keys must be static)"
  type        = map(string)
  default     = {}
}

variable "k3s_ingress_port" {
  description = "Port for nginx-ingress controller (usually 30080/30443)"
  type        = number
  default     = 30080
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for ALB"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}