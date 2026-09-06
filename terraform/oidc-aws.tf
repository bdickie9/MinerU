provider "aws" {
  region = var.aws_region
}

# OIDC provider for GitHub Actions (token.actions.githubusercontent.com)
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = ["6938FD4D98BAB03FAADB97B34396831E3780AEA1"]
}

data "aws_caller_identity" "current" {}

# Role that GitHub Actions will assume; restrict by repo and branch pattern
resource "aws_iam_role" "github_actions_perf" {
  name = "github-actions-perf-role-${replace(var.repo, "/", "-")}" 

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Accept only perf/* branches for the given repository
            "token.actions.githubusercontent.com:sub" = "repo:${var.repo}:ref:refs/heads/perf/*"
          }
        }
      }
    ]
  })
}

# Inline policy for secrets read and optional S3 artifact write (least privilege)
resource "aws_iam_role_policy" "perf_policy" {
  name = "perf-role-policy-${replace(var.repo, "/", "-")}" 
  role = aws_iam_role.github_actions_perf.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:/ci/${var.repo}/*"
        ]
      },
      {
        Sid = "OptionalS3PerfArtifacts"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.perf_artifacts_bucket}",
          "arn:aws:s3:::${var.perf_artifacts_bucket}/*"
        ]
      }
    ]
  })
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "repo" {
  type = string
  description = "GitHub repo in form owner/name, e.g. bdickie9/OmniRoute"
}

variable "perf_artifacts_bucket" {
  type = string
  default = "" # set to your S3 bucket name or leave empty to skip S3 permissions
}
