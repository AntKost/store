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
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [data.terraform_remote_state.shared.outputs.alb_security_group_id]
    description     = "Allow HTTP traffic from ALB"
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
  port        = var.container_port
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
  port              = var.container_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.store_tg.arn
  }

  tags = {
    Name = "store-listener"
  }
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
      hostPort      = var.container_port
      protocol      = "tcp"
    }]
    environment = [
      {
        name  = "MQTT_BROKER_HOST"
        value = "${data.terraform_remote_state.shared.outputs.mqtt_service_discovery_name}.${data.terraform_remote_state.shared.outputs.ecs_cluster_name}.local" # Adjust as needed
      },
      {
        name  = "MQTT_BROKER_PORT"
        value = "1883"
      },
      {
        name  = "REDIS_HOST"
        value = "${data.terraform_remote_state.shared.outputs.mqtt_service_discovery_name}.${data.terraform_remote_state.shared.outputs.ecs_cluster_name}.local"
      },
      {
        name  = "REDIS_PORT"
        value = "6379"
      },
      {
        name  = "DB_HOST"
        value = data.terraform_remote_state.shared.outputs.rds_endpoint
      },
      {
        name  = "DB_USER"
        value = "postgres"
      },
      {
        name  = "DB_PASSWORD"
        value = var.db_password
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
    assign_public_ip = true
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
