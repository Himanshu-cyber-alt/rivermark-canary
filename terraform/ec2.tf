# ============================================================
# Amazon Linux 2023 AMI
# ============================================================

data "aws_ssm_parameter" "amazon_linux_2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}


# ============================================================
# VPC
# ============================================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Project     = var.project_name
    Environment = var.environment
  }
}


# ============================================================
# Public Subnet
# ============================================================

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet"
    Project     = var.project_name
    Environment = var.environment
  }
}


# ============================================================
# Internet Gateway
# ============================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Project     = var.project_name
    Environment = var.environment
  }
}


# ============================================================
# Public Route Table
# ============================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project_name}-public-route-table"
    Project     = var.project_name
    Environment = var.environment
  }
}


resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}


# ============================================================
# Security Group
# ============================================================

resource "aws_security_group" "backend" {
  name        = "${var.project_name}-backend-sg"
  description = "Security group for Rivermark backend EC2"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-backend-sg"
    Project     = var.project_name
    Environment = var.environment
  }
}


# ============================================================
# EC2 IAM Role
# ============================================================

resource "aws_iam_role" "backend_ec2" {
  name = "${var.project_name}-backend-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-backend-ec2-role"
    Project     = var.project_name
    Environment = var.environment
  }
}


# ============================================================
# SSM Permission
# ============================================================

resource "aws_iam_role_policy_attachment" "backend_ssm" {
  role       = aws_iam_role.backend_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# ============================================================
# EC2 Instance Profile
# ============================================================

resource "aws_iam_instance_profile" "backend_ec2" {
  name = "${var.project_name}-backend-ec2-profile"
  role = aws_iam_role.backend_ec2.name
}


# ============================================================
# EC2 ECR Pull Permissions
# ============================================================

resource "aws_iam_role_policy" "backend_ecr" {
  name = "${var.project_name}-backend-ecr-policy"
  role = aws_iam_role.backend_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "ecr:GetAuthorizationToken"
        ]

        Resource = "*"
      },
      {
        Effect = "Allow"

        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]

        Resource = aws_ecr_repository.backend.arn
      }
    ]
  })
}


# ============================================================
# EC2 Instance
# ============================================================

resource "aws_instance" "backend" {

  depends_on = [
    aws_iam_role_policy.backend_ecr,
    aws_iam_role_policy_attachment.backend_ssm
  ]

  ami           = data.aws_ssm_parameter.amazon_linux_2023_ami.value
  instance_type = "t3.micro"

  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.backend.id]

  iam_instance_profile = aws_iam_instance_profile.backend_ec2.name

  associate_public_ip_address = true


  # ==========================================================
  # EC2 User Data
  # ==========================================================

  user_data = <<-EOF
#!/bin/bash

set -e

# ============================================================
# System Update
# ============================================================

dnf update -y


# ============================================================
# Install Required Packages
# ============================================================

dnf install -y docker nginx awscli


# ============================================================
# Start Docker
# ============================================================

systemctl enable docker
systemctl start docker

usermod -aG docker ec2-user


# ============================================================
# Create Rivermark Directory
# ============================================================

mkdir -p /opt/rivermark

chmod 755 /opt/rivermark


# ============================================================
# Remove Default Nginx Configuration
# ============================================================

rm -f /etc/nginx/conf.d/default.conf


# ============================================================
# Rivermark Nginx Configuration
# ============================================================

cat > /etc/nginx/conf.d/rivermark.conf <<'NGINX'
upstream rivermark_backend {
    server 127.0.0.1:5000 weight=90;
    server 127.0.0.1:5001 weight=10;
}

server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://rivermark_backend;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX


# ============================================================
# Validate Nginx Configuration
# ============================================================

nginx -t


# ============================================================
# Enable and Start Nginx
# ============================================================

systemctl enable nginx
systemctl restart nginx


# ============================================================
# Bootstrap Complete
# ============================================================

echo "============================================"
echo "Rivermark EC2 bootstrap completed"
echo "============================================"

EOF


  # ============================================================
  # EC2 Tags
  # ============================================================

  tags = {
    Name        = "${var.project_name}-backend"
    Project     = var.project_name
    Environment = var.environment
    Component   = "backend"
  }
}