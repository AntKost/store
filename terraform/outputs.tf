output "store_service_name" {
  description = "Name of the Store ECS service"
  value       = aws_ecs_service.store.name
}

output "store_service_discovery_arn" {
  description = "ARN of the Store Service Discovery service"
  value       = aws_service_discovery_service.store.arn
}

output "store_service_discovery_name" {
  value = aws_service_discovery_service.store.name
}

output "store_task_definition_arn" {
  description = "ARN of the Store task definition"
  value       = aws_ecs_task_definition.store.arn
}

output "store_security_group_id" {
  description = "Security Group ID for Store service"
  value       = aws_security_group.store_sg.id
}

output "store_target_group_arn" {
  description = "ARN of the Store ALB Target Group"
  value       = aws_lb_target_group.store_tg_blue.arn
}

output "store_listener_arn" {
  description = "ARN of the Store ALB Listener"
  value       = aws_lb_listener.store_listener.arn
}

output "store_ecr_repository_url" {
  description = "URL of the Store ECR repository"
  value       = aws_ecr_repository.store.repository_url
}

output "store_ecr_repository_arn" {
  description = "ARN of the Store ECR repository"
  value       = aws_ecr_repository.store.arn
}

output "store_ecr_policy_arn" {
  description = "ARN of the Store ECR IAM policy"
  value       = aws_iam_policy.store_ecr_policy.arn
}

output "codedeploy_store_app_name" {
  value = aws_codedeploy_app.store.name
}

output "codedeploy_store_deployment_group_name" {
  value = aws_codedeploy_deployment_group.store.deployment_group_name
}