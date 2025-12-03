#!/bin/bash
# Script to create S3 bucket and DynamoDB table for Terraform state management

set -e

AWS_REGION="${AWS_REGION:-us-east-1}"
BUCKET_BASE_NAME="airflow-terraform-state"
DYNAMODB_TABLE="airflow-terraform-locks"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="${BUCKET_BASE_NAME}-${AWS_ACCOUNT_ID}"

echo "🚀 Setting up Terraform Remote State Backend..."
echo "📍 Region: $AWS_REGION"
echo "📦 S3 Bucket: $BUCKET_NAME"
echo "🔐 DynamoDB Table: $DYNAMODB_TABLE"
echo "🆔 AWS Account ID: $AWS_ACCOUNT_ID"

# Create S3 bucket
echo "➡️  Creating S3 bucket for state..."
if aws s3 ls "s3://$BUCKET_NAME" 2>/dev/null; then
  echo "✓ S3 bucket already exists"
else
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$AWS_REGION" \
      --acl private
  else
    aws s3api create-bucket \
      --bucket "$BUCKET_NAME" \
      --region "$AWS_REGION" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION" \
      --acl private
  fi
  echo "✓ S3 bucket created"
fi

# Enable versioning
echo "➡️  Enabling versioning on S3 bucket..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled
echo "✓ Versioning enabled"

# Enable encryption
echo "➡️  Enabling server-side encryption..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }'
echo "✓ Encryption enabled"

# Block public access
echo "➡️  Blocking public access..."
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
echo "✓ Public access blocked"

# Create DynamoDB table for state locking
echo "➡️  Creating DynamoDB table for state locking..."
if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION" 2>/dev/null; then
  echo "✓ DynamoDB table already exists"
else
  aws dynamodb create-table \
    --table-name "$DYNAMODB_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$AWS_REGION" \
    --tags Key=Purpose,Value=TerraformLocking Key=Environment,Value=production
  
  # Wait for table to be created
  echo "⏳ Waiting for DynamoDB table to be active..."
  aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE" --region "$AWS_REGION"
  echo "✓ DynamoDB table created"
fi

echo ""
echo "✅ Terraform Remote State Backend Setup Complete!"
echo ""
echo "📋 Next Steps:"
echo "1. Configure AWS credentials if not already done"
echo "2. Run: terraform init"
echo "3. When prompted about the new S3 backend, type 'yes' to migrate state"
echo ""
echo "📊 Backend Configuration:"
echo "  S3 Bucket: $BUCKET_NAME"
echo "  DynamoDB Table: $DYNAMODB_TABLE"
echo "  Region: $AWS_REGION"
echo ""
