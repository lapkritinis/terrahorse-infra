provider "aws" {
  region = "eu-north-1"

  allowed_account_ids = ["462432303731"]
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
