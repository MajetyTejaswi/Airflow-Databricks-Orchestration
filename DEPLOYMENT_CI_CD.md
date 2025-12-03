````markdown
# Deployment & CI/CD — Combined Guide

This single authoritative guide consolidates CI/CD automation, DAG deployment methods, the full GitHub Actions workflow, and step-by-step verification for your Airflow + Terraform deployment.

---

## 📋 Table of Contents

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

If you'd like, I can now:

- Remove the original `CI_CD_AUTOMATION.md` and `DEPLOYMENT_WORKFLOW.md` after your confirmation.
- Open a PR with this new file and propose deleting the originals.
- Tweak the contents further (shorten, add team runbook, or add a table of workflow job timings).

````
