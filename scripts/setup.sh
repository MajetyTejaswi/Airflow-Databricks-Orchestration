#!/bin/bash

# Quick Setup Script for Airflow-Databricks Pipeline
# This script automates the initial setup

set -e

echo "🚀 Airflow-Databricks Pipeline Setup Assistant"
echo "=============================================="
echo ""

# Check prerequisites
echo "📋 Checking prerequisites..."

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform not found. Please install Terraform first."
    echo "   Visit: https://www.terraform.io/downloads"
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install AWS CLI first."
    echo "   Visit: https://aws.amazon.com/cli/"
    exit 1
fi

# Check if SSH key exists
if [ ! -f ~/.ssh/airflow-key ]; then
    echo "🔑 Generating SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/airflow-key -N "" -C "airflow-key"
    echo "✅ SSH key generated at ~/.ssh/airflow-key"
else
    echo "✅ SSH key found at ~/.ssh/airflow-key"
fi

echo ""
echo "📝 Configuration Setup"
echo "====================="
echo ""

# Get user inputs
read -p "Enter AWS region (default: us-east-1): " aws_region
aws_region=${aws_region:-us-east-1}

read -p "Enter Databricks workspace URL (e.g., https://adb-xxxxx.azuredatabricks.net): " databricks_host

read -s -p "Enter Databricks Personal Access Token: " databricks_token
echo ""

read -p "Enter EC2 instance type (default: t3.medium): " instance_type
instance_type=${instance_type:-t3.medium}

echo ""
echo "📝 Updating Terraform configuration..."

# Create terraform.tfvars
cat > terraform/terraform.tfvars << EOF
# AWS Configuration
aws_region = "$aws_region"
environment = "dev"

# VPC Configuration
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidr   = "10.0.1.0/24"

# EC2 Configuration
instance_type     = "$instance_type"
root_volume_size  = 30

# SSH Key Configuration
public_key_path = "~/.ssh/airflow-key.pub"

# Databricks Configuration
databricks_host  = "$databricks_host"
databricks_token = "$databricks_token"
EOF

echo "✅ terraform.tfvars updated"

echo ""
echo "🏗️  Initializing Terraform..."
cd terraform
terraform init

echo ""
echo "📊 Terraform Plan"
echo "================="
terraform plan -out=tfplan

echo ""
read -p "Do you want to apply these changes? (yes/no): " confirm
if [ "$confirm" = "yes" ]; then
    terraform apply tfplan
    
    echo ""
    echo "✅ Infrastructure deployed successfully!"
    echo ""
    echo "📍 Important Information:"
    echo "========================"
    terraform output
    
    echo ""
    echo "🎯 Next Steps:"
    echo "1. Wait 2-3 minutes for EC2 to fully initialize"
    echo "2. SSH into the instance: $(terraform output ssh_command)"
    echo "3. Access Airflow UI at: $(terraform output airflow_web_ui_url)"
    echo "4. Create Databricks connection in Airflow"
    echo "5. Upload DAGs from: ../airflow-dags/"
    
else
    echo "❌ Deployment cancelled"
    rm tfplan
    exit 1
fi

echo ""
echo "✨ Setup complete! Follow the next steps to configure Airflow."
