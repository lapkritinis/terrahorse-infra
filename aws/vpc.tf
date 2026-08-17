resource "aws_vpc" "main" {
  cidr_block           = local.network.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.account_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.account_name}-igw"
  }
}

resource "aws_subnet" "dmz" {
  for_each = local.network.dmz_subnets

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.account_name}-dmz-${each.key}"
    Tier = "dmz"
  }
}

resource "aws_subnet" "app" {
  for_each = local.network.app_subnets

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.account_name}-app-${each.key}"
    Tier = "application"
  }
}

resource "aws_subnet" "database" {
  for_each = local.network.database_subnets

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.account_name}-database-${each.key}"
    Tier = "database"
  }
}

resource "aws_route_table" "dmz" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.account_name}-dmz"
    Tier = "dmz"
  }
}

resource "aws_route" "dmz-internet" {
  route_table_id         = aws_route_table.dmz.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "dmz" {
  for_each = aws_subnet.dmz

  subnet_id      = each.value.id
  route_table_id = aws_route_table.dmz.id
}

resource "aws_eip" "nat" {
  for_each = local.nat_gateway_azs

  domain = "vpc"

  tags = {
    Name = "${local.account_name}-nat-${each.key}"
  }
}

resource "aws_nat_gateway" "main" {
  for_each = local.nat_gateway_azs

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.dmz[each.key].id

  tags = merge(
    {
      Name = "${local.account_name}-nat-${each.key}"
    },
    length([aws_internet_gateway.main.id]) > 0 ? {} : {}
  )
}

resource "aws_route_table" "app" {
  for_each = local.app_route_subnets

  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.account_name}-app-${each.key}"
    Tier = "application"
  }
}

resource "aws_route" "app-internet" {
  for_each = local.app_route_subnets

  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[local.network.nat_gateway_per_az ? each.key : local.network.primary_az].id
}

resource "aws_route_table_association" "app" {
  for_each = local.app_route_subnets

  subnet_id      = aws_subnet.app[each.key].id
  route_table_id = aws_route_table.app[each.key].id
}

resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.account_name}-database-public"
    Tier = "database"
  }
}

# Temporary public route for an RDS instance configured with publicly_accessible = true.
resource "aws_route" "database-internet" {
  route_table_id         = aws_route_table.database.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "database" {
  for_each = aws_subnet.database

  subnet_id      = each.value.id
  route_table_id = aws_route_table.database.id
}
