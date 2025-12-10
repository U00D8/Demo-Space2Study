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

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "cluster_name" {
  description = "MongoDB Atlas Cluster name"
  type        = string
  default     = "space2study-cluster"
}

variable "cluster_tier" {
  description = "MongoDB Atlas Cluster tier (M0 for free tier)"
  type        = string
  default     = "M0"
}


variable "cloud_provider" {
  description = "Cloud provider (AWS, GCP, AZURE)"
  type        = string
  default     = "AWS"
}

variable "region" {
  description = "AWS region for MongoDB Atlas"
  type        = string
  default     = "EU_NORTH_1"
}

variable "database_name" {
  description = "Database name"
  type        = string
  default     = "space2study"
}

variable "database_username" {
  description = "Database admin username"
  type        = string
  default     = "space2study"
}

variable "database_password" {
  description = "Database admin password"
  type        = string
  sensitive   = true
}

variable "ip_allowlist_entries" {
  description = "List of IP CIDR blocks allowed to connect to MongoDB Atlas"
  type = list(object({
    cidr_block  = string
    description = string
  }))
  default = []
}

variable "nat_elastic_ips" {
  description = "List of NAT Gateway Elastic IP addresses to add to allowlist"
  type        = list(string)
  default     = []
}


variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
