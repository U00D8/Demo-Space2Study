# modules/iam/variables.tf

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "terraform_state_bucket_arn" {
  description = "ARN of Terraform state S3 bucket"
  type        = string
}

variable "backup_bucket_arn" {
  description = "ARN of backup S3 bucket"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "ecr_repositories" {
  description = "Optional list of ECR repository names to attach lifecycle policies to (e.g. [\"project-backend\", \"project-frontend\"])."
  type        = list(string)
  default     = []
}

variable "kms_key_arn" {
  description = "KMS Key ARN for Vault Auto Unseal"
  type        = string  
}