````markdown
# Deployment & CI/CD — Combined Guide

This single authoritative guide consolidates CI/CD automation, DAG deployment methods, the full GitHub Actions workflow, and step-by-step verification for your Airflow + Terraform deployment.

---

## 📋 Table of Contents - Overview

1. [Overview](#overview)
2. [Quick Setup](#quick-setup)
3. [Deployment Methods](#deployment-methods)
4. [How the CI/CD Pipeline Works](#how-the-ci-cd-pipeline-works)
5. [Step-by-step Push-to-Deploy Workflow](#step-by-step-push-to-deploy-workflow)
6. [Verification Checklist](#verification-checklist)
7. [Troubleshooting](#troubleshooting)
8. [Quick Reference Commands](#quick-reference-commands)
9. [Files Touched / Created](#files-touched--created)
10. [Next Steps & Recommendations](#next-steps--recommendations)

---

## Overview

This repository contains automation to deploy Apache Airflow DAGs to an EC2 instance and manage infrastructure with Terraform. There are two primary deployment mechanisms:

- GitHub Actions (recommended): full CI/CD that validates DAGs and Terraform, applies infra changes, deploys DAGs, and verifies the running system.
- Git sync / manual methods: lightweight alternatives for frequent DAG updates or emergency fixes.

Use GitHub Actions for production changes and Git Sync or SCP for quick DAG-only updates.

## Quick Setup

1. **Create AWS IAM User & Access Keys:**
   ```bash
   chmod +x scripts/setup-terraform-iam.sh
   scripts/setup-terraform-iam.sh
   ```

2. **Add GitHub Secrets** (Go to repo Settings → Secrets → Actions):
   - `AWS_ACCESS_KEY_ID` — from IAM user
   - `AWS_SECRET_ACCESS_KEY` — from IAM user
   - `EC2_SSH_PRIVATE_KEY` — (contents of your private key; include BEGIN/END lines)
   - `SLACK_WEBHOOK` — (optional, for notifications)

3. **Generate SSH Key for EC2:**
   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/airflow-key -N "" -C "airflow-deployment-key"
   ```
   Add public key path to `terraform/terraform.tfvars`

4. **Set up Terraform Backend:**
   ```bash
   chmod +x scripts/setup-terraform-backend.sh
   AWS_REGION=us-east-1 scripts/setup-terraform-backend.sh
   ```

5. **Verify AWS Credentials:**
   ```bash
   export AWS_ACCESS_KEY_ID=your_key_id
   export AWS_SECRET_ACCESS_KEY=your_secret
   aws s3 ls
   aws dynamodb list-tables --region us-east-1
   ```

## GitHub Actions IAM Setup

### Automated IAM User Creation

```bash
chmod +x scripts/setup-terraform-iam.sh
scripts/setup-terraform-iam.sh
```

**Output includes:**
- IAM user: `airflow-terraform-ci`
- Access Key ID and Secret (save these!)
- Policy: terraform-policy

### Manual IAM Setup

```bash
# Create user
aws iam create-user --user-name airflow-terraform-ci

# Create access keys
aws iam create-access-key --user-name airflow-terraform-ci

# Attach policy
aws iam put-user-policy --user-name airflow-terraform-ci \
  --policy-name terraform-policy \
  --policy-document file://terraform-policy.json
```

### IAM Permissions Required

Minimum permissions needed:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformStateS3",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketVersioning"],
      "Resource": "arn:aws:s3:::airflow-terraform-state-*"
    },
    {
      "Sid": "TerraformStateS3Objects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::airflow-terraform-state-*/airflow/*"
    },
    {
      "Sid": "TerraformStateLocking",
      "Effect": "Allow",
      "Action": ["dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:GetItem"],
      "Resource": "arn:aws:dynamodb:*:*:table/airflow-terraform-locks"
    },
    {
      "Sid": "TerraformAWSResources",
      "Effect": "Allow",
      "Action": ["ec2:*", "iam:*", "s3:*", "rds:*", "ecs:*", "secretsmanager:*"],
      "Resource": "*"
    }
  ]
}

```

## Quick Setup

## Deployment Methods

Method 1 — GitHub Actions (recommended):
- Full validation of Terraform and DAGs.
- Plans and/or applies infrastructure changes.
- Deploys DAGs to EC2 (SCP) and restarts Airflow services.
- Sends notifications (Slack) if configured.

Triggers: push to `main` (full deploy), push to `develop` (DAG validation only), PRs (plan + validate), manual runs.

Method 2 — Git Sync (cron on EC2):
- EC2 periodically pulls from Git and reloads the scheduler.
- Lightweight, automatic, but does not validate before pulling.

Method 3 — Manual SCP:
- Quick, direct upload of DAGs via scp and restart of Airflow services.

Method 4 — Webhook receiver (advanced):
- A process on EC2 receives webhook and triggers git pull + scheduler reload.

## How the CI/CD Pipeline Works

High-level job sequence in `.github/workflows/deploy.yml`:

1. validate-terraform — terraform fmt/check and terraform validate
2. validate-dags — python syntax check and import checks for DAGs
3. plan-terraform — (PRs) create terraform plan and post as comment
4. deploy-infrastructure — terraform apply (main branch only)
5. deploy-dags — copy DAGs to EC2 via SCP and restart services
6. sync-dags-git — optional git pull on EC2 to ensure repo sync
7. validate-deployment — SSH into EC2 and run `airflow dags validate` / `airflow dags list`
8. notify — send Slack or other notifications on success/failure

Timings: full deploy ~10–15 minutes; DAG-only changes ~2–3 minutes.

## Step-by-step Push-to-Deploy Workflow

1. Prepare DAG locally and run quick checks:

```bash
python -m py_compile airflow-dags/my_dag.py
python3 -c "import sys; sys.path.insert(0, 'airflow-dags'); import my_dag"
```

2. Commit and push to GitHub (push to `main` triggers full deployment):

```bash
git add airflow-dags/my_dag.py
git commit -m "Add: my_dag"
git push origin main
```

3. Observe GitHub Actions — the workflow will run the defined jobs in order. Monitor logs via the Actions tab.

4. After deploy-dags completes, the workflow will SSH to EC2 and restart Airflow services. Verify with `airflow dags list` on the instance.

## Verification Checklist

After the workflow completes, verify:

- GitHub Actions: all jobs green.
- EC2: instance Running and reachable.
- DAG files present in `/home/airflow/airflow/dags`.
- Airflow services (scheduler + webserver) active via `systemctl status`.
- `airflow dags list` shows the new DAG(s).
- Optional: verify UI at `http://EC2_IP:8080`.

## Troubleshooting

Common issues and quick fixes:

- SSH connection failures: verify the `EC2_SSH_PRIVATE_KEY` secret includes the full key (BEGIN/END lines) and the security group allows SSH from the runner.
- DAG validation errors: run `python -m py_compile` and test imports locally before pushing.
- Terraform errors: run `terraform validate` and `terraform plan` locally; check AWS quotas and permissions.
- Services not running: SSH and `sudo journalctl -u airflow-scheduler -n 50` and `sudo systemctl restart airflow-scheduler`.

## Quick Reference Commands

Get EC2 IP from Terraform:

```bash
cd terraform
terraform output -raw ec2_public_ip
```

SSH into EC2:

```bash
ssh -i ~/.ssh/airflow-key ubuntu@$EC2_IP
```

Restart Airflow services on EC2:

```bash
sudo systemctl restart airflow-scheduler
sudo systemctl restart airflow-webserver
```

Validate DAGs on EC2:

```bash
export AIRFLOW_HOME=/home/airflow/airflow
source $AIRFLOW_HOME/venv/bin/activate
airflow dags validate
airflow dags list
```

## Files Touched / Created (reference)

These files are part of the automation and documentation set in this repo:

- `.github/workflows/deploy.yml` — Full deployment pipeline (validate → plan → apply → deploy)
- `.github/workflows/sync-dags.yml` — Scheduled and on-push DAG sync
- `scripts/bootstrap.sh` — EC2 bootstrap (installs Airflow, sets up git-sync)
- `scripts/setup.sh` — Local helper for terraform/ssh setup
- `scripts/post-deploy.sh` — Adds connections/vars on EC2 post-deploy
- `scripts/destroy.sh` — Terraform destroy wrapper
- `scripts/validate.py` — Local preflight check
- `CI_CD_AUTOMATION.md` — Original consolidation (kept for reference)
- `DEPLOYMENT_WORKFLOW.md` — Original step-by-step (kept for reference)

## Next Steps & Recommendations

1. Review this merged file and confirm you want to keep it as the single source of truth.
2. Remove or archive older docs once you confirm this consolidated file is correct.
3. Ensure GitHub Secrets are set and do not include secret values in repo files.
4. Optional improvements:
   - Add a manual approval environment for production deployments.
   - Add automated rollback steps on failure for infra changes.
   - Add unit tests for DAGs where feasible.

---

## GitHub Secrets Configuration

Add these secrets to your GitHub repository for the deployment workflow to work:

### Required Secrets

#### AWS Credentials
- **AWS_ACCESS_KEY_ID**: Your IAM user's access key ID
- **AWS_SECRET_ACCESS_KEY**: Your IAM user's secret access key

#### EC2 SSH Key
- **EC2_SSH_PRIVATE_KEY**: Your private SSH key content (include -----BEGIN RSA PRIVATE KEY----- and -----END RSA PRIVATE KEY-----)

#### Optional - Slack Notifications
- **SLACK_WEBHOOK**: Your Slack webhook URL for deployment notifications

### Note on Databricks

Databricks credentials are **NOT** stored in Terraform or GitHub Secrets. Instead, they are configured directly in Airflow as connections via the Airflow UI after deployment.

To add Databricks connection in Airflow:
1. Access Airflow UI at: `http://<EC2_IP>:8080`
2. Go to **Admin** → **Connections**
3. Create new connection:
   - **Conn Id**: `databricks`
   - **Conn Type**: `Databricks`
   - **Host**: Your Databricks workspace URL
   - **Token**: Your Databricks PAT

### How to Add Secrets

1. Go to your GitHub repository
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add each secret with the exact names above

### Getting Your Credentials

#### AWS IAM Credentials
```bash
# If you ran the setup script locally, use those credentials
# Or run:
aws iam create-access-key --user-name airflow-terraform-ci
```

#### SSH Key
Use the private key you generated:
```bash
cat ~/.ssh/airflow-key
# Copy the entire content including BEGIN/END lines
```

---

## Terraform State Management

This section explains how to set up and manage Terraform state for the Airflow-Databricks infrastructure.

### Overview

Terraform state is stored remotely in AWS S3 with state locking via DynamoDB to prevent concurrent modifications and ensure infrastructure consistency.

### Backend Configuration

**Location**: `terraform/backend.tf`

The backend uses:
- **S3 Bucket**: `airflow-terraform-state-<ACCOUNT_ID>` - Stores the Terraform state file
- **DynamoDB Table**: `airflow-terraform-locks` - Provides state locking mechanism
- **Region**: `us-east-1` (configurable)
- **Encryption**: AES-256 by default

### Setup Instructions

#### Prerequisites

- AWS account with appropriate permissions
- AWS CLI configured with credentials
- Terraform installed (v1.6.0 or higher)

#### Option 1: Automated Setup (Recommended)

Run the automated backend setup script:

```bash
# Make script executable
chmod +x scripts/setup-terraform-backend.sh

# Run setup (requires AWS credentials configured)
AWS_REGION=us-east-1 scripts/setup-terraform-backend.sh
```

This script will:
1. Create S3 bucket for state storage (with account ID suffix for global uniqueness)
2. Enable versioning on the S3 bucket
3. Enable encryption on the S3 bucket
4. Block all public access to the bucket
5. Create DynamoDB table for state locking

#### Option 2: Manual Setup

```bash
# Set variables
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export BUCKET_NAME="airflow-terraform-state-${AWS_ACCOUNT_ID}"
export DYNAMODB_TABLE="airflow-terraform-locks"

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

### Initialize Terraform

After backend setup is complete:

```bash
cd terraform

# Initialize Terraform with backend (GitHub Actions does this automatically)
terraform init

# When prompted, confirm migration of state to S3 by typing 'yes'
```

### Daily Operations

#### Get Current State

```bash
# List all resources in state
terraform state list

# Show specific resource details
terraform state show <resource_type>.<resource_name>

# Show entire state (be cautious with sensitive data)
terraform state show
```

#### View State in S3

```bash
# List state files in S3
aws s3 ls s3://airflow-terraform-state-<ACCOUNT_ID>/

# Download state file (for backup)
aws s3 cp s3://airflow-terraform-state-<ACCOUNT_ID>/airflow/terraform.tfstate ./terraform.tfstate.backup

# View state file size
aws s3api head-object --bucket airflow-terraform-state-<ACCOUNT_ID> --key airflow/terraform.tfstate
```

#### Check State Locks

```bash
# List all locks (usually empty unless Terraform crashed)
aws dynamodb scan --table-name airflow-terraform-locks --region us-east-1

# Force unlock if needed (use with caution!)
terraform force-unlock <LOCK_ID>
```

### State File Protection

The S3 bucket is configured with:

- ✅ **Versioning**: All versions of the state file are retained
- ✅ **Encryption**: AES-256 server-side encryption
- ✅ **Access Control**: Private ACL, only authorized IAM roles can access
- ✅ **Public Access Block**: All public access is blocked
- 🔐 **State Locking**: DynamoDB prevents concurrent modifications

### Disaster Recovery

#### Restore from Backup

```bash
# List available versions
aws s3api list-object-versions \
  --bucket airflow-terraform-state-<ACCOUNT_ID> \
  --prefix airflow/terraform.tfstate

# Restore specific version
aws s3api get-object \
  --bucket airflow-terraform-state-<ACCOUNT_ID> \
  --key airflow/terraform.tfstate \
  --version-id <VERSION_ID> \
  terraform.tfstate.restored

# Use restored state
cp terraform.tfstate.restored terraform.tfstate
```

#### Remove State Lock (Emergency)

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

### Terraform State Troubleshooting

#### State Lock Timeout

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

#### Permission Denied

```
Error: error creating S3 client: AccessDenied
```

**Solution:**
- Verify AWS credentials are configured
- Ensure IAM user has `s3:*` and `dynamodb:*` permissions
- Check region matches configuration

#### Backend Not Found

```
Error: error reading backend.tf
```

**Solution:**
- Ensure `backend.tf` exists in terraform directory
- Run `terraform init` to reconfigure

### CI/CD Integration

The GitHub Actions workflow automatically:

1. Sets up the backend infrastructure (if main branch push)
2. Initializes Terraform with remote backend
3. Plans changes with remote state
4. Applies changes to remote state
5. Artifacts store outputs for subsequent jobs

### Related Documentation

- [Terraform S3 Backend Docs](https://www.terraform.io/language/settings/backends/s3)
- [AWS S3 Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- [Terraform State Security](https://www.terraform.io/language/state#sensitive-data)

---

If you'd like, I can now:

- Remove the original `CI_CD_AUTOMATION.md` and `DEPLOYMENT_WORKFLOW.md` after your confirmation.
- Open a PR with this new file and propose deleting the originals.
- Tweak the contents further (shorten, add team runbook, or add a table of workflow job timings).

````
