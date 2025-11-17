terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ============================================================================
# Variables
# ============================================================================

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Name of the App Runner service"
  type        = string
  default     = "rag-qa-app"
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "rag-qa-app"
}

variable "openai_api_key" {
  description = "OpenAI API key (should be set via environment variable or terraform.tfvars)"
  type        = string
  sensitive   = true
}

variable "openai_model" {
  description = "OpenAI model to use for chat"
  type        = string
  default     = "gpt-3.5-turbo"
}

variable "openai_embedding_model" {
  description = "OpenAI embedding model to use"
  type        = string
  default     = "text-embedding-3-small"
}

variable "instance_cpu" {
  description = "CPU units for App Runner instance"
  type        = string
  default     = "1 vCPU"
}

variable "instance_memory" {
  description = "Memory for App Runner instance"
  type        = string
  default     = "2 GB"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Project = "RAG-QA-App"
    ManagedBy = "Terraform"
  }
}

# ============================================================================
# Resources
# ============================================================================

# ECR Repository for Docker images
resource "aws_ecr_repository" "rag_app" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

# IAM role for App Runner service
resource "aws_iam_role" "app_runner_service_role" {
  name = "${var.app_name}-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "build.apprunner.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

# IAM policy for App Runner service role (ECR access)
resource "aws_iam_role_policy" "app_runner_service_policy" {
  name = "${var.app_name}-service-policy"
  role = aws_iam_role.app_runner_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM role for App Runner instance
resource "aws_iam_role" "app_runner_instance_role" {
  name = "${var.app_name}-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "tasks.apprunner.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

# IAM policy for App Runner instance role (minimal permissions)
resource "aws_iam_role_policy" "app_runner_instance_policy" {
  name = "${var.app_name}-instance-policy"
  role = aws_iam_role.app_runner_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# App Runner service
resource "aws_apprunner_service" "rag_app" {
  service_name = var.app_name

  source_configuration {
    image_repository {
      image_identifier      = "${aws_ecr_repository.rag_app.repository_url}:latest"
      image_configuration {
        port = "8000"
        runtime_environment_variables = {
          OPENAI_API_KEY = var.openai_api_key
          OPENAI_MODEL   = var.openai_model
          OPENAI_EMBEDDING_MODEL = var.openai_embedding_model
        }
      }
      image_repository_type = "ECR"
    }
    access_role_arn   = aws_iam_role.app_runner_service_role.arn
    auto_deployments_enabled = false
  }

  instance_configuration {
    cpu               = var.instance_cpu
    memory            = var.instance_memory
    instance_role_arn = aws_iam_role.app_runner_instance_role.arn
  }

  health_check_configuration {
    protocol            = "HTTP"
    path                = "/health"
    healthy_threshold   = 1
    unhealthy_threshold = 5
    interval            = 10
    timeout             = 5
  }

  tags = var.tags
}

# ============================================================================
# Outputs
# ============================================================================

output "app_runner_service_url" {
  description = "URL of the App Runner service"
  value       = aws_apprunner_service.rag_app.service_url
}

output "app_runner_service_arn" {
  description = "ARN of the App Runner service"
  value       = aws_apprunner_service.rag_app.arn
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.rag_app.repository_url
}

output "access_role_arn" {
  description = "ARN of the App Runner access role"
  value       = aws_iam_role.app_runner_service_role.arn
}

output "instance_role_arn" {
  description = "ARN of the App Runner instance role"
  value       = aws_iam_role.app_runner_instance_role.arn
}
