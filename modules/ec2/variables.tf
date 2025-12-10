# modules/ec2/variables.tf

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "kms_key_id" {
  description = "KMS Key ID for Vault Auto Unseal"
  type        = string
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "backup_bucket_name" {
  description = "S3 backup bucket name"
  type        = string
}

# Jenkins variables
variable "jenkins_instance_type" {
  description = "Jenkins instance type"
  type        = string
}

variable "jenkins_subnet_id" {
  description = "Subnet ID for Jenkins"
  type        = string
}

variable "jenkins_security_group_id" {
  description = "Security group ID for Jenkins"
  type        = string
}

variable "jenkins_instance_profile" {
  description = "IAM instance profile for Jenkins"
  type        = string
}

variable "jenkins_agent_subnet_id" {
  description = "Subnet ID for Jenkins agents (dynamic EC2 instances)"
  type        = string
}

# Vault variables
variable "vault_instance_type" {
  description = "Vault instance type"
  type        = string
}

variable "vault_subnet_id" {
  description = "Subnet ID for Vault"
  type        = string
}

variable "vault_security_group_id" {
  description = "Security group ID for Vault"
  type        = string
}

variable "vault_instance_profile" {
  description = "IAM instance profile for Vault"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# K3s cluster variables (for Jenkins kubeconfig generation)
variable "k3s_master_ip" {
  description = "K3s master node public IP"
  type        = string
}

variable "k3s_master_private_ip" {
  description = "K3s master node private IP"
  type        = string
}

variable "k3s_token" {
  description = "K3s cluster authentication token"
  type        = string
  sensitive   = true
}