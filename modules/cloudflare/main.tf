# modules/cloudflare/main.tf

# Get the Cloudflare zone
data "cloudflare_zone" "main" {
  name = var.domain_name
}

# Root domain → ALB
resource "cloudflare_record" "root" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  type    = "CNAME"
  content = var.alb_dns_name
  proxied = true  # Enable Cloudflare proxy (orange cloud)
  ttl     = 1     # Auto TTL when proxied
  comment = "Managed by Terraform - Root domain to ALB"
}

# WWW subdomain → ALB
resource "cloudflare_record" "www" {
  zone_id = data.cloudflare_zone.main.id
  name    = "www"
  type    = "CNAME"
  content = var.alb_dns_name
  proxied = true
  ttl     = 1
  comment = "Managed by Terraform - WWW to ALB"
}

# API subdomain → ALB
resource "cloudflare_record" "api" {
  count   = var.create_api_record ? 1 : 0
  zone_id = data.cloudflare_zone.main.id
  name    = "api"
  type    = "CNAME"
  content = var.alb_dns_name
  proxied = true
  ttl     = 1
  comment = "Managed by Terraform - API to ALB"
}

# Jenkins subdomain → ALB
resource "cloudflare_record" "jenkins" {
  zone_id = data.cloudflare_zone.main.id
  name    = "jenkins"
  type    = "CNAME"
  content = var.alb_dns_name
  proxied = true
  ttl     = 1
  comment = "Managed by Terraform - Jenkins to ALB"
}

# ========================================
# CLOUDFLARE CACHE RULES (Modern Rulesets)
# ========================================
# Note: Requires these API token permissions:
#   - Zone > Cache Rules > Edit
#   - Account Rulesets > Edit
#   - Account Filter Lists > Edit

# Bypass cache for Jenkins (webhooks need fresh responses)
resource "cloudflare_ruleset" "cache_bypass_jenkins" {
  zone_id     = data.cloudflare_zone.main.id
  name        = "Cache Bypass - Jenkins"
  description = "Bypass cache for Jenkins webhooks"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules {
    ref         = "jenkins_bypass_cache"
    description = "Bypass cache for Jenkins webhook endpoints"
    expression  = "(http.host eq \"jenkins.${var.domain_name}\")"
    action      = "set_cache_settings"
    action_parameters {
      cache = false
    }
  }
}
