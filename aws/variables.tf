variable "cloudflare_account_id" {
  description = "Cloudflare account that owns the TerraHorse tunnels"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with tunnel management permissions"
  type        = string
  sensitive   = true
}
