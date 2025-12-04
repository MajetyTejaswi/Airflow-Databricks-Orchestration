terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "airflow-orchestration"
      ManagedBy   = "terraform"
    }
  }
}

# Create VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "airflow-vpc"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "airflow-igw"
  }
}

# Create Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "airflow-public-subnet"
  }
}

# Create Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "airflow-route-table"
  }
}

# Associate Route Table with Subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Create Security Group
resource "aws_security_group" "airflow" {
  name        = "airflow-sg"
  description = "Security group for Airflow EC2 instance"
  vpc_id      = aws_vpc.main.id

  # Allow HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow Airflow Web UI (8080)
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "airflow-sg"
  }
}

# Create IAM Role for EC2
resource "aws_iam_role" "airflow_ec2_role" {
  name = "airflow-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "airflow-ec2-role"
  }
}

# Create IAM Policy for S3 and CloudWatch access
resource "aws_iam_role_policy" "airflow_ec2_policy" {
  name = "airflow-ec2-policy"
  role = aws_iam_role.airflow_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.airflow_logs.arn,
          "${aws_s3_bucket.airflow_logs.arn}/*",
          aws_s3_bucket.airflow_dags.arn,
          "${aws_s3_bucket.airflow_dags.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/airflow/*"
      }
    ]
  })
}

# Create IAM Instance Profile
resource "aws_iam_instance_profile" "airflow_profile" {
  name = "airflow-instance-profile"
  role = aws_iam_role.airflow_ec2_role.name
}

# Get latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Create EC2 Instance
resource "aws_instance" "airflow" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.airflow.id]
  iam_instance_profile   = aws_iam_instance_profile.airflow_profile.name
  key_name               = aws_key_pair.deployer.key_name

  # Use user_data directly - cloud-init handles bash scripts
  user_data = file("${path.module}/../scripts/bootstrap.sh")

  # Ensure user_data changes trigger instance replacement
  user_data_replace_on_change = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
  }

  monitoring = true

  tags = {
    Name = "airflow-server"
  }

  depends_on = [aws_internet_gateway.main]
}

# Generate SSH key pair
resource "tls_private_key" "airflow_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create Key Pair for SSH access
resource "aws_key_pair" "deployer" {
  key_name   = "airflow-deployer-key"
  public_key = tls_private_key.airflow_ssh.public_key_openssh

  tags = {
    Name = "airflow-key-pair"
  }
}

# Save private key locally
resource "local_file" "private_key" {
  content         = tls_private_key.airflow_ssh.private_key_pem
  filename        = "${path.module}/airflow-key.pem"
  file_permission = "0600"
}

# Create S3 bucket for logs and data
resource "aws_s3_bucket" "airflow_logs" {
  bucket = "airflow-logs-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  tags = {
    Name = "airflow-logs-bucket"
  }
}

# Create S3 bucket for DAGs
resource "aws_s3_bucket" "airflow_dags" {
  bucket = "airflow-dags-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  tags = {
    Name = "airflow-dags-bucket"
  }
}

# Enable versioning on S3 bucket
resource "aws_s3_bucket_versioning" "airflow_logs" {
  bucket = aws_s3_bucket.airflow_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable versioning on DAGs bucket
resource "aws_s3_bucket_versioning" "airflow_dags" {
  bucket = aws_s3_bucket.airflow_dags.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Output information
output "ec2_public_ip" {
  value       = aws_instance.airflow.public_ip
  description = "Public IP of the Airflow EC2 instance"
}

output "ec2_public_dns" {
  value       = aws_instance.airflow.public_dns
  description = "Public DNS of the Airflow EC2 instance"
}

output "airflow_web_ui_url" {
  value       = "http://${aws_instance.airflow.public_ip}:8080"
  description = "Airflow Web UI URL"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.airflow_logs.id
  description = "S3 bucket for Airflow logs"
}

output "s3_dags_bucket_name" {
  value       = aws_s3_bucket.airflow_dags.id
  description = "S3 bucket for Airflow DAGs"
}

output "ssh_command" {
  value       = "ssh -i ${path.module}/airflow-key.pem ubuntu@${aws_instance.airflow.public_ip}"
  description = "SSH command to connect to the instance"
}

output "ec2_instance_id" {
  value       = aws_instance.airflow.id
  description = "EC2 Instance ID"
}

output "airflow_access_info" {
  value       = <<-EOT
    =====================================
    Airflow Web UI: http://${aws_instance.airflow.public_ip}:8080
    Username: admin
    Password: admin123
    
    DAGs S3 Bucket: ${aws_s3_bucket.airflow_dags.id}
    SSH Access: ssh -i terraform/airflow-key.pem ubuntu@${aws_instance.airflow.public_ip}
    =====================================
  EOT
  description = "Airflow access information"
}

output "ssh_private_key" {
  value       = tls_private_key.airflow_ssh.private_key_pem
  description = "Private SSH key for EC2 access"
  sensitive   = true
}
