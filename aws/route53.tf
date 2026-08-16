resource "aws_route53_zone" "private-zone" {
  name    = local.network.private_zone_name
  comment = "Private DNS for the Oculfit VPC"

  vpc {
    vpc_id = aws_vpc.main.id
  }

  tags = {
    Name = local.network.private_zone_name
  }
}
