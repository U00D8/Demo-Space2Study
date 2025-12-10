# environments/dev/variables.tf

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
  default     = ["10.0.1.0/24", "10.0.2.0/24"]  # Two subnets for ALB across AZs
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = [] # No private subnets in dev
}

variable "enable_nat_gateway" {
  description = "Enable NAT gateway"
  type        = bool
  default     = false # NAT disabled for dev
}

variable "admin_cidr_blocks" {
  description = "Admin CIDR blocks for SSH"
  type        = list(string)
  default     = []  # Add your IP: ["1.2.3.4/32"]
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default = {
    Project     = "Space2Study"
    Environment = "dev"
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