resource "aws_ssm_parameter" "ec2-runtime-config" {
  for_each = local.github_environment_variables

  name        = "/terrahorse/${trimprefix(each.key, "aws-")}/ec2/config"
  description = "Non-secret TerraHorse EC2 runtime configuration for ${each.key}"
  type        = "String"
  value       = jsonencode(each.value)

  tags = {
    Name        = "/terrahorse/${trimprefix(each.key, "aws-")}/ec2/config"
    Environment = trimprefix(each.key, "aws-")
  }
}
