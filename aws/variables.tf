variable "cloudflare_account_id" {
  description = "Cloudflare account that owns the TerraHorse tunnels"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with tunnel management permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_tunnel_hostnames" {
  description = "Public hostname routed to each environment's EC2 storefront"
  type        = map(string)

  validation {
    condition = (
      length(setsubtract(keys(var.cloudflare_tunnel_hostnames), ["dev", "prod"])) == 0 &&
      length(setsubtract(["dev", "prod"], keys(var.cloudflare_tunnel_hostnames))) == 0
    )
    error_message = "cloudflare_tunnel_hostnames must contain exactly dev and prod keys."
  }
}
