provider "github" {
  owner = "lapkritinis"
}

resource "github_repository_environment" "terrahorse-web" {
  for_each = local.github_environments

  repository  = local.github_repository
  environment = each.key
}

resource "github_actions_environment_variable" "terrahorse-web" {
  for_each = local.github_variable_keys

  repository    = local.github_repository
  environment   = github_repository_environment.terrahorse-web[each.value.environment].environment
  variable_name = each.value.name
  value         = each.value.value
}

resource "github_actions_environment_secret" "terrahorse-web" {
  for_each = local.github_secret_keys

  repository  = local.github_repository
  environment = github_repository_environment.terrahorse-web[each.value.environment].environment
  secret_name = each.value.name
  value       = each.value.name == "CLOUDFLARED_TUNNEL_TOKEN" ? data.cloudflare_zero_trust_tunnel_cloudflared_token.terrahorse[trimprefix(each.value.environment, "aws-")].token : local.github_environment_secrets[each.value.environment][each.value.name]
}
