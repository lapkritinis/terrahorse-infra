locals {
  github_repository = "terrahorse-web"

  github_environment_variables = {
    "aws-dev" = {
      NUXT_PUBLIC_SITE_URL                   = "http://localhost:3000"
      SALEOR_API_URL                         = "http://host.docker.internal:8000/graphql/"
      SALEOR_CHANNEL                         = "terrahorse-eur"
      SALEOR_STOCK_AVAILABILITY_MODE         = "channel-aggregate"
      SALEOR_STOCK_COUNTRY_CODE              = "LT"
      LOG_LEVEL                              = "info"
      SALEOR_PAYMENT_GATEWAY_ID              = "terrahorse.local-commerce"
      SALEOR_PAYMENT_APP_ID                  = "QXBwOjI="
      MONTONIO_SHIPPING_API_URL              = "https://sandbox-shipping.montonio.com"
      SALEOR_VENIPAK_PARCEL_LOCKER_METHOD_ID = "U2hpcHBpbmdNZXRob2Q6Mg=="
      SALEOR_VENIPAK_COURIER_METHOD_ID       = "U2hpcHBpbmdNZXRob2Q6Mw=="
    }
  }

  github_environment_secret_names = {
    "aws-dev" = [
      "SALEOR_COMMERCE_APP_TOKEN",
      "COMMERCE_EVENT_HMAC_KEY",
      "MONTONIO_ACCESS_KEY",
      "MONTONIO_SECRET_KEY",
      "CLOUDFLARED_TUNNEL_TOKEN",
      "POSTGRES_PASSWORD",
      "SECRET_KEY",
    ]
    "aws-prod" = [
      "SALEOR_COMMERCE_APP_TOKEN",
      "COMMERCE_EVENT_HMAC_KEY",
      "MONTONIO_ACCESS_KEY",
      "MONTONIO_SECRET_KEY",
      "CLOUDFLARED_TUNNEL_TOKEN",
      "POSTGRES_PASSWORD",
      "SECRET_KEY",
    ]
  }

  github_environments = setunion(
    toset(keys(local.github_environment_variables)),
    toset(keys(local.github_environment_secret_names)),
  )

  github_variable_keys = merge([
    for environment, variables in local.github_environment_variables : {
      for name, value in variables : "${environment}:${name}" => {
        environment = environment
        name        = name
        value       = value
      }
    }
  ]...)

  github_secret_keys = merge([
    for environment, names in local.github_environment_secret_names : {
      for name in names : "${environment}:${name}" => {
        environment = environment
        name        = name
      }
    }
  ]...)
}
