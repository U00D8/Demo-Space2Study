# modules/cloudflare/variables.tf

variable "domain_name" {
  description = "Domain name managed in Cloudflare"
  type        = string
}

variable "alb_dns_name" {
  description = "AWS ALB DNS name to point records to"
  type        = string
}

variable "create_api_record" {
  description = "Create API subdomain record"
  type        = bool
  default     = false
}

variable "enable_rate_limiting" {
  description = "Enable Cloudflare rate limiting rules"
  type        = bool
  default     = false
}
