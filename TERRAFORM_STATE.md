# Terraform State Management

This guide explains how to set up and manage Terraform state for the Airflow-Databricks infrastructure.

## Overview

Terraform state is stored remotely in AWS S3 with state locking via DynamoDB to prevent concurrent modifications and ensure infrastructure consistency.

## Backend Configuration

**Location**: `terraform/backend.tf`

The backend uses:
- **S3 Bucket**: `airflow-terraform-state` - Stores the Terraform state file
- **DynamoDB Table**: `airflow-terraform-locks` - Provides state locking mechanism
- **Region**: `us-east-1` (configurable)
- **Encryption**: AES-256 by default

## Setup Instructions

### Prerequisites

- AWS account with appropriate permissions
- AWS CLI configured with credentials
- Terraform installed (v1.6.0 or higher)

### Option 1: Automated Setup (Recommended)

Run the automated backend setup script:

```bash
# Make script executable
chmod +x scripts/setup-terraform-backend.sh

# Run setup (requires AWS credentials configured)
AWS_REGION=us-east-1 scripts/setup-terraform-backend.sh
```

This script will:
1. Create S3 bucket for state storage
2. Enable versioning on the S3 bucket
3. Enable encryption on the S3 bucket
4. Block all public access to the bucket
5. Create DynamoDB table for state locking

### Option 2: Manual Setup

```bash
# Set variables
export AWS_REGION=us-east-1
export BUCKET_NAME=airflow-terraform-state
export DYNAMODB_TABLE=airflow-terraform-locks

# Create S3 bucket
aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region $AWS_REGION \
  --acl private

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Create DynamoDB table
aws dynamodb create-table \
  --table-name $DYNAMODB_TABLE \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $AWS_REGION
```

## Initialize Terraform

After backend setup is complete:

```bash
cd terraform

# Initialize Terraform with backend
terraform init

# When prompted, confirm migration of state to S3 by typing 'yes'
```

## Daily Operations

### Get Current State

```bash
# List all resources in state
terraform state list

# Show specific resource details
terraform state show <resource_type>.<resource_name>

# Show entire state (be cautious with sensitive data)
terraform state show
```

### View State in S3

```bash
# List state files in S3
aws s3 ls s3://airflow-terraform-state/

# Download state file (for backup)
aws s3 cp s3://airflow-terraform-state/airflow/terraform.tfstate ./terraform.tfstate.backup

# View state file size
aws s3api head-object --bucket airflow-terraform-state --key airflow/terraform.tfstate
```

### Check State Locks

```bash
# List all locks (usually empty unless Terraform crashed)
aws dynamodb scan --table-name airflow-terraform-locks --region us-east-1

# Force unlock if needed (use with caution!)
terraform force-unlock <LOCK_ID>
```

## State File Protection

The S3 bucket is configured with:

- ✅ **Versioning**: All versions of the state file are retained
- ✅ **Encryption**: AES-256 server-side encryption
- ✅ **Access Control**: Private ACL, only authorized IAM roles can access
- ✅ **Public Access Block**: All public access is blocked
- 🔐 **State Locking**: DynamoDB prevents concurrent modifications

## Disaster Recovery

### Restore from Backup

```bash
# List available versions
aws s3api list-object-versions \
  --bucket airflow-terraform-state \
  --prefix airflow/terraform.tfstate

# Restore specific version
aws s3api get-object \
  --bucket airflow-terraform-state \
  --key airflow/terraform.tfstate \
  --version-id <VERSION_ID> \
  terraform.tfstate.restored

# Use restored state
cp terraform.tfstate.restored terraform.tfstate
```

### Remove State Lock (Emergency)

If Terraform is stuck due to a lock:

```bash
# Find lock ID
aws dynamodb scan --table-name airflow-terraform-locks --region us-east-1

# Delete lock
aws dynamodb delete-item \
  --table-name airflow-terraform-locks \
  --key '{"LockID":{"S":"<LOCK_ID>"}}' \
  --region us-east-1
```

## CI/CD Integration

The GitHub Actions workflow automatically:

1. Sets up the backend infrastructure (if main branch push)
2. Initializes Terraform with remote backend
3. Plans changes with remote state
4. Applies changes to remote state
5. Artifacts store outputs for subsequent jobs

## Troubleshooting

### State Lock Timeout

```
Error: Error acquiring the state lock
```

**Solution:**
```bash
# Check locks
aws dynamodb scan --table-name airflow-terraform-locks

# Force unlock
terraform force-unlock <LOCK_ID>
```

### Permission Denied

```
Error: error creating S3 client: AccessDenied
```

**Solution:**
- Verify AWS credentials are configured
- Ensure IAM user has `s3:*` and `dynamodb:*` permissions
- Check region matches configuration

### Backend Not Found

```
Error: error reading backend.tf
```

**Solution:**
- Ensure `backend.tf` exists in terraform directory
- Run `terraform init` to reconfigure

## Bucket Naming Convention

S3 bucket names must be globally unique. Current naming:
- `airflow-terraform-state` (may need suffix for global uniqueness)

If bucket creation fails, modify in `backend.tf`:
```hcl
bucket = "airflow-terraform-state-${local.account_id}"
```

## Related Documentation

- [Terraform S3 Backend Docs](https://www.terraform.io/language/settings/backends/s3)
- [AWS S3 Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- [Terraform State Security](https://www.terraform.io/language/state#sensitive-data)
