#!/bin/bash
# Quick setup script to prepare for first GitHub Actions deployment

set -e

echo "🚀 Airflow-Databricks Orchestration - First Run Setup"
echo ""

# Step 1: Check AWS credentials
echo "📋 Step 1: Checking AWS credentials..."
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "❌ AWS credentials not configured"
  echo "   Run: aws configure"
  exit 1
fi
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "✓ AWS configured - Account ID: $AWS_ACCOUNT_ID"

# Step 2: Create Terraform backend
echo ""
echo "📋 Step 2: Setting up Terraform backend (S3 + DynamoDB)..."
if [ -f "scripts/setup-terraform-backend.sh" ]; then
  chmod +x scripts/setup-terraform-backend.sh
  scripts/setup-terraform-backend.sh
else
  echo "⚠️  setup-terraform-backend.sh not found"
fi

# Step 3: Create IAM user for GitHub Actions
echo ""
echo "📋 Step 3: Creating IAM user for GitHub Actions..."
if [ -f "scripts/setup-terraform-iam.sh" ]; then
  chmod +x scripts/setup-terraform-iam.sh
  scripts/setup-terraform-iam.sh
else
  echo "⚠️  setup-terraform-iam.sh not found"
fi

echo ""
echo "✅ Setup Complete!"
echo ""
echo "📝 Next Steps:"
echo "1. Save the AWS Access Keys from the IAM setup above"
echo "2. Go to GitHub repository settings → Secrets and variables → Actions"
echo "3. Add GitHub Secrets:"
echo "   - AWS_ACCESS_KEY_ID"
echo "   - AWS_SECRET_ACCESS_KEY"
echo "4. Generate SSH key and add:"
echo "   - EC2_SSH_PRIVATE_KEY"
echo ""
echo "5. Verify Terraform:"
cd terraform
terraform init -backend=false
terraform validate
echo "✓ Terraform validated"
echo ""
echo "6. Ready to push to GitHub!"
