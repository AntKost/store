# Reference Shared Infra State
data "terraform_remote_state" "shared" {
  backend = "s3"
  config = {
    bucket         = "rv-terraform-state-bucket"        # Replace with your S3 bucket name
    key            = "shared-infra/terraform.tfstate"    # Path to the shared infra state file
    region         = "eu-central-1"                      
    dynamodb_table = "terraform-locks"                   # DynamoDB table for state locking
    encrypt        = true
    profile = "rv-terraform"
  }
}

# Service Discovery Service for Store
resource "aws_service_discovery_service" "store" {
  name = "store"

  dns_config {
    namespace_id = data.terraform_remote_state.shared.outputs.service_discovery_namespace_id

    dns_records {
      type = "A"
      ttl  = 60
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# Security Group for Store Service
resource "aws_security_group" "store_sg" {
  name        = "store-sg"
  description = "Allow Store traffic"
  vpc_id      = data.terraform_remote_state.shared.outputs.vpc_id

  ingress {
    from_port       = var.host_port
    to_port         = var.host_port
    protocol        = "tcp"
    security_groups = [data.terraform_remote_state.shared.outputs.alb_security_group_id]
    description     = "Allow HTTP traffic from ALB"
  }

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [data.terraform_remote_state.shared.outputs.db_security_group_id]
    description     = "Allow HTTP traffic from RDS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "store-sg"
  }
}

# ALB Target Group for Store Service
resource "aws_lb_target_group" "store_tg" {
  name        = "store-tg"
  port        = var.host_port
  protocol    = "HTTP"
  vpc_id      = data.terraform_remote_state.shared.outputs.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-299"
  }

  tags = {
    Name = "store-tg"
  }
}

# ALB Listener for Store Service
resource "aws_lb_listener" "store_listener" {
  load_balancer_arn = data.terraform_remote_state.shared.outputs.alb_arn
  port              = var.host_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.store_tg.arn
  }

  tags = {
    Name = "store-listener"
  }
}

# ECR Repository for Store Service
resource "aws_ecr_repository" "store" {
  name                 = var.store_ecr_repository_name
  image_tag_mutability = var.image_tag_mutability

  encryption_configuration {
    encryption_type = var.encryption_configuration.encryption_type
    kms_key         = var.encryption_configuration.kms_key != "" ? var.encryption_configuration.kms_key : null
  }

  tags = {
    Name        = "store-ecr-repository"
  }
}

# IAM Policy for ECR Push/Pull Access
resource "aws_iam_policy" "store_ecr_policy" {
  name        = "store-ecr-policy"
  description = "IAM policy for Store service to access ECR repository"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = aws_ecr_repository.store.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = aws_ecr_repository.store.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach the ECR policy to the ECS Task Execution Role
resource "aws_iam_role_policy_attachment" "store_ecr_attachment" {
  policy_arn = aws_iam_policy.store_ecr_policy.arn
  role       = data.terraform_remote_state.shared.outputs.ecs_task_execution_role_arn
}

# Store Task Definition
resource "aws_ecs_task_definition" "store" {
  family                   = "store"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = var.store_cpu
  memory                   = var.store_memory

  container_definitions = jsonencode([{
    name  = "store"
    image = var.store_image
    portMappings = [{
      containerPort = var.container_port
      hostPort      = var.host_port
      protocol      = "tcp"
    }]
    environment = [
      {
        name  = "POSTGRES_USER"
        value = "postgres"
      },
      {
        name  = "POSTGRES_PASSWORD"
        value = "var.db_password"
      },
      {
        name  = "POSTGRES_DB"
        value = "road_vision"
      },
      {
        name  = "POSTGRES_PORT"
        value = "5432"
      },
      {
        name  = "POSTGRES_HOST"
        value = data.terraform_remote_state.shared.outputs.rds_endpoint
      }
    ]
  }])

  execution_role_arn = data.terraform_remote_state.shared.outputs.ecs_task_execution_role_arn
}

# Store ECS Service
resource "aws_ecs_service" "store" {
  name            = "store-service"
  cluster         = data.terraform_remote_state.shared.outputs.ecs_cluster_id
  task_definition = aws_ecs_task_definition.store.arn
  desired_count   = 1
  launch_type     = "EC2"

  network_configuration {
    subnets         = data.terraform_remote_state.shared.outputs.public_subnet_ids
    security_groups = [aws_security_group.store_sg.id, data.terraform_remote_state.shared.outputs.ecs_instance_security_group_id]
  }

  service_registries {
    registry_arn = aws_service_discovery_service.store.arn
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.store_tg.arn
    container_name   = "store"
    container_port   = var.container_port
  }

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  depends_on = [aws_service_discovery_service.store, aws_ecs_task_definition.store, aws_security_group.store_sg, aws_lb_target_group.store_tg]
}
