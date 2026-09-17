# ============================================================
# Rivermark - GitHub OIDC Provider
# ============================================================

resource "aws_iam_openid_connect_provider" "github_frontend" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  tags = {
    Name      = "rivermark-github-frontend-oidc"
    Project   = "rivermark"
    Component = "frontend"
  }
}


# ============================================================
# Rivermark Frontend - GitHub Actions IAM Role
# ============================================================

resource "aws_iam_role" "github_frontend" {
  name = "rivermark-github-frontend-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = aws_iam_openid_connect_provider.github_frontend.arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }

          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:Himanshu-cyber-alt@155243085/rivermark-canary@1373886533:ref:refs/heads/main"
          }
        }
      }
    ]
  })

  tags = {
    Name      = "rivermark-github-frontend-role"
    Project   = "rivermark"
    Component = "frontend"
  }
}


# ============================================================
# Frontend GitHub Actions Permissions
# ============================================================

resource "aws_iam_role_policy" "github_frontend" {
  name = "rivermark-github-frontend-policy"

  role = aws_iam_role.github_frontend.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [

      # ------------------------------------------------------
      # S3 - List bucket
      # ------------------------------------------------------

      {
        Effect = "Allow"

        Action = [
          "s3:ListBucket"
        ]

        Resource = aws_s3_bucket.frontend.arn
      },


      # ------------------------------------------------------
      # S3 - Upload and delete frontend files
      # ------------------------------------------------------

      {
        Effect = "Allow"

        Action = [
          "s3:PutObject",
          "s3:DeleteObject"
        ]

        Resource = "${aws_s3_bucket.frontend.arn}/*"
      },


      # ------------------------------------------------------
      # CloudFront - Create cache invalidation
      # ------------------------------------------------------

      {
        Effect = "Allow"

        Action = [
          "cloudfront:CreateInvalidation"
        ]

        Resource = aws_cloudfront_distribution.frontend.arn
      }
    ]
  })
}


# ============================================================
# Rivermark Backend - GitHub Actions IAM Role
# ============================================================

resource "aws_iam_role" "github_backend" {
  name = "rivermark-github-backend-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = aws_iam_openid_connect_provider.github_frontend.arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }

        StringLike = {
  "token.actions.githubusercontent.com:sub" = "repo:Himanshu-cyber-alt@155243085/rivermark-canary@1373886533:ref:refs/heads/main"
}
        }
      }
    ]
  })

  tags = {
    Name      = "rivermark-github-backend-role"
    Project   = "rivermark"
    Component = "backend"
  }
}


# ============================================================
# Backend GitHub Actions - ECR Permissions
# ============================================================

resource "aws_iam_role_policy" "github_backend_ecr" {
  name = "rivermark-github-backend-ecr-policy"

  role = aws_iam_role.github_backend.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [

      # ------------------------------------------------------
      # ECR - Authentication
      # ------------------------------------------------------

      {
        Effect = "Allow"

        Action = [
          "ecr:GetAuthorizationToken"
        ]

        Resource = "*"
      },


      # ------------------------------------------------------
      # ECR - Push backend Docker image
      # ------------------------------------------------------

      {
        Effect = "Allow"

        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]

        Resource = aws_ecr_repository.backend.arn
      }
    ]
  })
}


# ============================================================
# Backend GitHub Actions - SSM Permissions
# ============================================================

resource "aws_iam_role_policy" "github_backend_ssm" {
  name = "rivermark-github-backend-ssm-policy"

  role = aws_iam_role.github_backend.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [

      # ------------------------------------------------------
      # SSM - Send deployment command to EC2
      # ------------------------------------------------------

      {
        Effect = "Allow"

        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]

        Resource = "*"
      }
    ]
  })
}


# ============================================================
# Outputs
# ============================================================

output "github_frontend_oidc_provider_arn" {
  description = "GitHub OIDC provider ARN for frontend"

  value = aws_iam_openid_connect_provider.github_frontend.arn
}


output "github_frontend_role_arn" {
  description = "IAM role ARN used by frontend GitHub Actions"

  value = aws_iam_role.github_frontend.arn
}


output "github_backend_role_arn" {
  description = "IAM role ARN used by backend GitHub Actions"

  value = aws_iam_role.github_backend.arn
}