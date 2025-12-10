# modules/route53/variables.tf

variable "domain_name" {
  description = "Public domain name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the private hosted zone"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vault_private_ip" {
  description = "Vault EC2 instance private IP address"
  type        = string
}

variable "jenkins_private_ip" {
  description = "Jenkins EC2 instance private IP address (optional)"
  type        = string
  default     = ""
}

variable "k3s_master_private_ip" {
  description = "K3s Master EC2 instance private IP address (optional)"
  type        = string
  default     = ""
}

variable "k3s_worker_private_ips" {
  description = "K3s Worker EC2 instance private IP addresses (list for multiple workers)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}