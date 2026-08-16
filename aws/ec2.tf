data "aws_ami" "amazon-linux-2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-arm64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_security_group" "ec2" {
  name        = "${local.account_name}-ec2"
  description = "TerraHorse EC2 host with outbound HTTPS only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.account_name}-ec2"
  }
}

resource "aws_vpc_security_group_egress_rule" "ec2-https" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTPS egress"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_ebs_volume" "data" {
  availability_zone = local.ec2.availability_zone
  encrypted         = true
  size              = local.ec2.data_volume_size_gib
  type              = local.ec2.data_volume_type

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${local.account_name}-data"
  }
}

resource "aws_launch_template" "ec2" {
  name_prefix   = "${local.ec2.name}-"
  image_id      = data.aws_ami.amazon-linux-2023.id
  instance_type = local.ec2.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      encrypted             = true
      volume_type           = "gp3"
      volume_size           = local.ec2.root_volume_size_gib
      delete_on_termination = true
    }
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2.id]
  }

  user_data = base64encode(templatefile("${path.module}/user_data/ec2.sh.tftpl", {
    compose_file   = local.ec2.compose_file
    data_volume_id = aws_ebs_volume.data.id
  }))

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      {
        Name = local.ec2.name
      },
      length([
        aws_iam_role_policy_attachment.ec2-ssm.id,
        aws_iam_role_policy_attachment.ec2-ecr-read-only.id,
      ]) > 0 ? {} : {}
    )
  }
}

resource "aws_autoscaling_group" "ec2" {
  name                = local.ec2.name
  min_size            = 1
  desired_capacity    = 1
  max_size            = 2
  vpc_zone_identifier = [aws_subnet.dmz[local.ec2.availability_zone].id]

  health_check_type         = "EC2"
  health_check_grace_period = 900

  launch_template {
    id      = aws_launch_template.ec2.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      instance_warmup        = 900
      min_healthy_percentage = 0
    }

  }

  tag {
    key                 = "Name"
    value               = local.ec2.name
    propagate_at_launch = true
  }
}
