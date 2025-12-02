variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 30
}

variable "public_key_path" {
  description = "Path to the public SSH key"
  type        = string
}

variable "databricks_host" {
  description = "Databricks workspace URL"
  type        = string
  sensitive   = true
}

variable "databricks_token" {
  description = "Databricks personal access token"
  type        = string
  sensitive   = true
}
