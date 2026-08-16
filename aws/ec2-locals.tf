locals {
  ec2 = {
    name                 = "${local.account_name}-host"
    instance_type        = "t4g.small"
    availability_zone    = local.network.primary_az
    root_volume_size_gib = 20
    data_volume_size_gib = 2
    data_volume_type     = "gp3"
    compose_file         = "/opt/terrahorse/app/compose.ec2.yml"
  }
}
