# environments/prod/variables.tf

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

variable "kms_key_id" {
  description = "KMS Key ID for Vault Auto Unseal"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["eu-north-1a", "eu-north-1b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "enable_nat_gateway" {
  description = "Enable NAT gateway"
  type        = bool
  default     = true
}

variable "admin_cidr_blocks" {
  description = "Admin CIDR blocks for SSH"
  type        = list(string)
  default     = []
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default = {
    Project     = "Space2Study"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}

# DNS Configuration
variable "domain_name" {
  description = "Domain name (authoritative DNS is in Cloudflare)"
  type        = string
}

# Cloudflare Configuration
variable "cloudflare_api_token" {
  description = "Cloudflare API token for DNS management"
  type        = string
  sensitive   = true
}

variable "create_api_record" {
  description = "Create API subdomain DNS record in Cloudflare"
  type        = bool
}

variable "enable_rate_limiting" {
  description = "Enable Cloudflare rate limiting"
  type        = bool
}

# EC2 Instance Variables
variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "jenkins_instance_type" {
  description = "Jenkins instance type"
  type        = string
  default     = "t3.small"
}

variable "vault_instance_type" {
  description = "Vault instance type"
  type        = string
  default     = "t3.micro"
}

variable "master_instance_type" {
  description = "K3s master node instance type"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "K3s worker node instance type"
  type        = string
  default     = "t3.small"
}

variable "worker_count" {
  description = "Number of K3s worker nodes"
  type        = number
  default     = 2
}

variable "vault_addr" {
  description = "Vault server address"
  type        = string
  sensitive   = true
}

# MongoDB Atlas Configuration
variable "mongodb_atlas_organization_id" {
  description = "MongoDB Atlas Organization ID"
  type        = string
  sensitive   = true
}

variable "mongodb_atlas_public_key" {
  description = "MongoDB Atlas API Public Key"
  type        = string
  sensitive   = true
}

variable "mongodb_atlas_private_key" {
  description = "MongoDB Atlas API Private Key"
  type        = string
  sensitive   = true
}

variable "mongodb_cluster_name" {
  description = "MongoDB Atlas Cluster name"
  type        = string
  default     = "space2study-cluster"
}

variable "mongodb_admin_username" {
  description = "MongoDB admin username"
  type        = string
  default     = "space2study"
}

variable "mongodb_admin_password" {
  description = "MongoDB admin password"
  type        = string
  sensitive   = true
}

