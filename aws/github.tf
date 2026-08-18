provider "github" {
  owner = local.github_owner
}

data "github_user" "production_deployment_reviewer" {
  username = "lapkritinis"
}

resource "github_repository_environment" "terrahorse-web" {
  for_each = local.github_environments

  repository          = local.github_repository
  environment         = each.key
  can_admins_bypass   = each.key != "aws-prod"
  prevent_self_review = false

  dynamic "reviewers" {
    for_each = each.key == "aws-prod" ? [data.github_user.production_deployment_reviewer.id] : []

    content {
      users = [reviewers.value]
    }
  }
}

resource "github_branch_protection" "terrahorse-web-main" {
  repository_id  = local.github_repository
  pattern        = "main"
  enforce_admins = true

  required_status_checks {
    strict = true
    contexts = [
      "Application",
      "Runtime image",
    ]
  }
}

resource "github_actions_variable" "terrahorse-web" {
  for_each = local.github_repository_variables

  repository    = local.github_repository
  variable_name = each.key
  value         = each.value
}

resource "github_actions_environment_variable" "terrahorse-web" {
  for_each = local.github_variable_keys

  repository    = local.github_repository
  environment   = github_repository_environment.terrahorse-web[each.value.environment].environment
  variable_name = each.value.name
  value         = each.value.value
}

resource "github_actions_environment_secret" "terrahorse-web" {
  for_each = {
    for key, value in local.github_secret_keys : key => value
    if value.name == "CLOUDFLARED_TUNNEL_TOKEN"
  }

  repository  = local.github_repository
  environment = github_repository_environment.terrahorse-web[each.value.environment].environment
  secret_name = each.value.name
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.terrahorse[trimprefix(each.value.environment, "aws-")].token
}
