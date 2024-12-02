variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "eu-central-1"
}

variable "store_image" {
  description = "Docker image for the Store service"
  type        = string
  default     = "docker-image:latest"
}

variable "store_cpu" {
  description = "CPU units for the Store task"
  type        = string
  default     = "256"
}

variable "store_memory" {
  description = "Memory (in MiB) for the Store task"
  type        = string
  default     = "512"
}

variable "desired_count" {
  description = "Desired number of Store service tasks"
  type        = number
  default     = 1
}

variable "service_name" {
  description = "Name of the Store service"
  type        = string
  default     = "store-service"
}

variable "container_port" {
  description = "Port on which the Store container listens"
  type        = number
  default     = 8000
}

variable "db_password" {
  description = "RDS PostgreSQL DB password"
  type = string
  sensitive = true
}

variable "store_ecr_repository_name" {
  description = "Name of the ECR repository for the Store service"
  type        = string
  default     = "store-repo"
}

variable "image_tag_mutability" {
  description = "Image tag mutability setting"
  type        = string
  default     = "MUTABLE"
}

variable "encryption_configuration" {
  description = "Encryption settings for the ECR repository"
  type = object({
    encryption_type = string
    kms_key         = string
  })
  default = {
    encryption_type = "AES256"
    kms_key         = ""
  }
}