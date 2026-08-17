locals {
  account_name = "terrahorse"

  network = {
    cidr_block          = "10.20.0.0/20"
    primary_az          = "eu-north-1a"
    nat_gateway_enabled = false
    nat_gateway_per_az  = false
    private_zone_name   = "terrahorse.internal"

    dmz_subnets = {
      "eu-north-1a" = "10.20.0.0/24"
      "eu-north-1b" = "10.20.1.0/24"
    }

    app_subnets = {
      "eu-north-1a" = "10.20.4.0/24"
      "eu-north-1b" = "10.20.5.0/24"
    }

    database_subnets = {
      "eu-north-1a" = "10.20.8.0/24"
      "eu-north-1b" = "10.20.9.0/24"
    }
  }

  nat_gateway_azs = !local.network.nat_gateway_enabled || length(local.network.dmz_subnets) == 0 ? toset([]) : (
    local.network.nat_gateway_per_az ? toset(keys(local.network.dmz_subnets)) : toset([local.network.primary_az])
  )

  # App subnets may still be declared when there are no NAT gateways, but
  # their private routing cannot be created without one.
  app_route_subnets = length(local.nat_gateway_azs) == 0 ? {} : local.network.app_subnets
}
