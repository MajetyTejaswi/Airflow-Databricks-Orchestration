#!/bin/bash
# Script to create IAM user and policy for Terraform CI/CD operations

set -e

TERRAFORM_USER="airflow-terraform-ci"
AWS_REGION="${AWS_REGION:-us-east-1}"
BUCKET_NAME="airflow-terraform-state"
DYNAMODB_TABLE="airflow-terraform-locks"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "🚀 Setting up IAM user for Terraform CI/CD..."
echo "📍 Region: $AWS_REGION"
echo "👤 IAM User: $TERRAFORM_USER"

# Create IAM user
echo "➡️  Creating IAM user..."
if aws iam get-user --user-name "$TERRAFORM_USER" 2>/dev/null; then
  echo "✓ IAM user already exists"
else
  aws iam create-user --user-name "$TERRAFORM_USER"
  echo "✓ IAM user created"
fi

# Create access keys
echo "➡️  Creating access keys..."
ACCESS_KEY_JSON=$(aws iam create-access-key --user-name "$TERRAFORM_USER" 2>/dev/null || echo "")

if [ -z "$ACCESS_KEY_JSON" ]; then
  echo "⚠️  Access key already exists or user has maximum keys"
  echo "📋 To view existing keys:"
  echo "   aws iam list-access-keys --user-name $TERRAFORM_USER"
else
  ACCESS_KEY_ID=$(echo "$ACCESS_KEY_JSON" | grep -o '"AccessKeyId": "[^"]*"' | cut -d'"' -f4)
  SECRET_ACCESS_KEY=$(echo "$ACCESS_KEY_JSON" | grep -o '"SecretAccessKey": "[^"]*"' | cut -d'"' -f4)
  echo "✓ Access keys created"
  echo ""
  echo "⚠️  Save these credentials in GitHub Secrets (use only once!):"
  echo "   AWS_ACCESS_KEY_ID: $ACCESS_KEY_ID"
  echo "   AWS_SECRET_ACCESS_KEY: $SECRET_ACCESS_KEY"
  echo ""
fi

# Create inline policy for Terraform
echo "➡️  Creating IAM policy..."
POLICY_DOCUMENT='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformStateS3",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketVersioning",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::'$BUCKET_NAME'"
    },
    {
      "Sid": "TerraformStateS3Objects",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::'$BUCKET_NAME'/airflow/*"
    },
    {
      "Sid": "TerraformStateLocking",
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
        "dynamodb:GetItem",
        "dynamodb:DescribeTable"
      ],
      "Resource": "arn:aws:dynamodb:'$AWS_REGION':'$AWS_ACCOUNT_ID':table/'$DYNAMODB_TABLE'"
    },
    {
      "Sid": "TerraformAWSResources",
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "iam:*",
        "s3:*",
        "rds:*",
        "ecs:*",
        "elasticache:*",
        "logs:*",
        "secretsmanager:*",
        "vpc:*"
      ],
      "Resource": "*"
    }
  ]
}'

aws iam put-user-policy \
  --user-name "$TERRAFORM_USER" \
  --policy-name "terraform-policy" \
  --policy-document "$POLICY_DOCUMENT"
echo "✓ IAM policy attached"

echo ""
echo "✅ Terraform CI/CD IAM Setup Complete!"
echo ""
echo "📋 Next Steps:"
echo "1. Add GitHub Secrets (if new user):"
echo "   - AWS_ACCESS_KEY_ID"
echo "   - AWS_SECRET_ACCESS_KEY"
echo "2. Verify permissions:"
echo "   aws iam get-user --user-name $TERRAFORM_USER"
echo "   aws iam list-user-policies --user-name $TERRAFORM_USER"
echo ""
