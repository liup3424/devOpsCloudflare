terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# -----------------------------------------------------------------
# 1. OIDC authentication required for GitHub Actions (CI/CD)
# -----------------------------------------------------------------

# Variables: your GitHub username/organization
variable "github_org_or_user" {
  description = "Your GitHub username or organization (e.g., 'my-username')"
  type        = string
}

variable "github_repo_name" {
  description = "Your GitHub repository name (e.g., 'rag-app-demo')"
  type        = string
}

# Register GitHub OIDC as a trusted identity provider
resource "aws_iam_openid_connect_provider" "github_oidc" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d9c60c1c1107f9c7bb06a5e24dd2b17fd"] # Standard GitHub OIDC Thumbprint
}

# IAM policy: Allow GitHub Actions to push to ECR and update App Runner
resource "aws_iam_policy" "github_actions_policy" {
  name = "github-actions-deploy-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ],
        Resource = aws_ecr_repository.rag_app_ecr.arn
      },
      {
        Effect = "Allow",
        Action = [
          "ecr:GetAuthorizationToken"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "apprunner:StartDeployment",
          "apprunner:DescribeService",
          "apprunner:UpdateService",
          "apprunner:ListOperations"
         ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "apprunner:ListServices"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "apprunner:CreateService"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "iam:PassRole"
        ],
        Resource = [
          aws_iam_role.apprunner_instance_role.arn,
          aws_iam_role.apprunner_service_role.arn
        ]
      }
    ]
  })
}

# Role: GitHub Actions will assume this role via OIDC
resource "aws_iam_role" "github_actions_role" {
  name = "github-actions-deploy-role"

  # Trust policy: Only allow requests from your specific repo’s `main` branch
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_oidc.arn
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:sub" : "repo:${var.github_org_or_user}/${var.github_repo_name}:ref:refs/heads/main"
          }
        }
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.github_actions_policy.arn
}

# -----------------------------------------------------------------
# 2. Infrastructure needed for the RAG application
# -----------------------------------------------------------------

variable "openai_api_key" {
  description = "OpenAI API Key (stored in Secrets Manager)"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.openai_api_key) > 0
    error_message = "OpenAI API Key cannot be empty."
  }
}

variable "manage_apprunner_via_terraform" {
  description = "Whether App Runner should be created via Terraform (default false; GitHub Actions deploys instead)"
  type        = bool
  default     = true
}

# Store the API Key securely
resource "aws_secretsmanager_secret" "openai_key" {
  name = "dev-ops-rag-qa-openai-key-secret"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "openai_key_value" {
  count         = var.openai_api_key != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.openai_key.id
  secret_string = var.openai_api_key
}

# ECR repository
resource "aws_ecr_repository" "rag_app_ecr" {
  name = "dev-ops-rag-app"
  force_delete = true
}

# App Runner service role (pull from ECR)
resource "aws_iam_role" "apprunner_service_role" {
  name = "dev-ops-apprunner-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "build.apprunner.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# App Runner instance role (read Secrets Manager)
resource "aws_iam_role" "apprunner_instance_role" {
  name = "dev-ops-apprunner-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "tasks.apprunner.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "apprunner_secrets" {
  name = "apprunner-secrets-policy"
  role = aws_iam_role.apprunner_instance_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow",
      Action   = "secretsmanager:GetSecretValue",
      Resource = aws_secretsmanager_secret.openai_key.arn
    }]
  })
}

# App Runner service
resource "aws_apprunner_service" "rag_app_service" {
  count = var.manage_apprunner_via_terraform ? 1 : 0
  service_name = "dev-ops-rag-service"

  source_configuration {
    authentication_configuration {
      access_role_arn = aws_iam_role.apprunner_service_role.arn
    }
    image_repository {
      image_identifier      = "${aws_ecr_repository.rag_app_ecr.repository_url}:latest"
      image_repository_type = "ECR"
      image_configuration {
        port = "8000"
        runtime_environment_secrets = {
          OPENAI_API_KEY = aws_secretsmanager_secret.openai_key.arn
        }
      }
    }
    auto_deployments_enabled = false # Deployment triggered manually via GitHub Actions
  }

  instance_configuration {
    cpu    = "1024" # 1 vCPU
    memory = "2048" # 2 GB
    instance_role_arn = aws_iam_role.apprunner_instance_role.arn
  }
}

# Grant ECR read permissions to App Runner
resource "aws_iam_role_policy" "apprunner_ecr_access" {
  name = "apprunner-ecr-access-policy"
  role = aws_iam_role.apprunner_service_role.name
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeImages",
          "ecr:GetAuthorizationToken"
        ],
        Resource = aws_ecr_repository.rag_app_ecr.arn
      },
      {
        Effect = "Allow",
        Action = ["ecr:GetAuthorizationToken"],
        Resource = "*"
      }
    ]
  })
}

# --- Outputs ---
output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions_role.arn
  description = "Copy to GitHub Secret: AWS_IAM_ROLE_TO_ASSUME"
}
output "ecr_repository_name" {
  value       = aws_ecr_repository.rag_app_ecr.name
  description = "Copy to GitHub Secret: ECR_REPOSITORY"
}
output "apprunner_service_arn" {
  value       = can(aws_apprunner_service.rag_app_service[0].arn) ? aws_apprunner_service.rag_app_service[0].arn : null
  description = "Copy to GitHub Secret: APP_RUNNER_ARN"
}
output "apprunner_url" {
  value       = can(aws_apprunner_service.rag_app_service[0].service_url) ? "https://portal.aws.amazon.com/goto/object/AppRunner?${aws_apprunner_service.rag_app_service[0].service_url}" : null
  description = "Public URL of the RAG application (AWS login required)"
}
