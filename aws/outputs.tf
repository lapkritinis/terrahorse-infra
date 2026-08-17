output "ecr_repository_url" {
  description = "ECR repository URL used by application pipelines"
  value       = aws_ecr_repository.terrahorse.repository_url
}

output "ecr_release_repository_url" {
  description = "ECR repository URL for immutable TerraHorse release bundles"
  value       = aws_ecr_repository.terrahorse-release.repository_url
}

output "ecs_deploy_targets" {
  description = "ECS names and task template families used by application pipelines"
  value = {
    for environment in keys(local.ecs_environments) : environment => {
      cluster                  = aws_ecs_cluster.main[environment].name
      service                  = aws_ecs_service.main[environment].name
      task_definition_template = aws_ecs_task_definition.template[environment].family
    }
  }
}

output "github_actions_build_role_arn" {
  description = "IAM role used by GitHub Actions to build and publish images"
  value       = aws_iam_role.github-actions.arn
}

output "github_actions_deploy_role_arns" {
  description = "Environment-scoped IAM roles used by GitHub Actions deployments"
  value       = { for environment, role in aws_iam_role.github-actions-deploy : environment => role.arn }
}

output "ec2_autoscaling_group_name" {
  description = "EC2 Auto Scaling Group name"
  value       = { for environment, group in aws_autoscaling_group.ec2 : environment => group.name }
}
