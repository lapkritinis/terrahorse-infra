locals {
  cloudflare_tunnel_hostnames = {
    dev  = "dev.terrahorse.lt"
    prod = "terrahorse.lt"
  }

  cloudflare_tunnels = {
    for environment in ["dev", "prod"] : environment => {
      name     = "terrahorse-${environment}"
      hostname = local.cloudflare_tunnel_hostnames[environment]
    }
  }
}

resource "random_password" "cloudflare_tunnel_secret" {
  for_each = local.cloudflare_tunnels

  length  = 32
  special = false
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "terrahorse" {
  for_each = local.cloudflare_tunnels

  account_id = var.cloudflare_account_id
  name       = each.value.name
  secret     = base64encode(random_password.cloudflare_tunnel_secret[each.key].result)
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "terrahorse" {
  for_each = local.cloudflare_tunnels

  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.terrahorse[each.key].id

  config {
    ingress_rule {
      hostname = each.value.hostname
      service  = "http://localhost:3000"
    }

    ingress_rule {
      service = "http_status:404"
    }
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "terrahorse" {
  for_each = local.cloudflare_tunnels

  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.terrahorse[each.key].id
}

output "cloudflare_tunnel_ids" {
  description = "Cloudflare tunnel IDs for the TerraHorse environments"
  value = {
    for environment, tunnel in cloudflare_zero_trust_tunnel_cloudflared.terrahorse : environment => tunnel.id
  }
}
