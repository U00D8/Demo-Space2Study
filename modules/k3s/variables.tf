# modules/k3s/variables.tf

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
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

variable "master_instance_type" {
  description = "Instance type for master node"
  type        = string
}

variable "master_subnet_id" {
  description = "Subnet ID for master node"
  type        = string  
}

variable "master_security_group_id" {
  description = "Security group ID for master node"
  type        = string  
}

variable "master_instance_profile" {
  description = "Instance profile for master node"
  type        = string
}

variable "worker_instance_type" {
  description = "Instance type for worker nodes"
  type        = string
}

variable "worker_subnet_id" {
  description = "Subnet ID for worker nodes"
  type        = string  
}

variable "worker_security_group_id" {
  description = "Security group ID for worker nodes"
  type        = string  
}

variable "worker_instance_profile" {
  description = "Instance profile for worker nodes"
  type        = string
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
}
