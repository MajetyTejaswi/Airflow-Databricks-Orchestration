# Airflow-Databricks Orchestration

Automated Apache Airflow deployment on AWS EC2 with Terraform and GitHub Actions CI/CD pipeline for orchestrating Databricks jobs.

## Overview

This project provides:
- **Infrastructure as Code**: Terraform provisions VPC, EC2, S3, IAM resources
- **CI/CD Pipeline**: GitHub Actions automates deployment on every push
- **Airflow on EC2**: Scheduler + Webserver running as systemd services
- **Databricks Integration**: DAGs trigger Databricks jobs via Airflow operators

## Architecture

```
GitHub Repository
       │
       ▼ (push to main)
GitHub Actions CI/CD
       │
       ├── Validate Terraform & DAGs
       ├── Deploy Infrastructure (Terraform)
       ├── Wait for EC2 Bootstrap
       └── Sync DAGs to S3 & EC2
       │
       ▼
AWS Infrastructure
       │
       ├── VPC + Subnet + Security Groups
       ├── EC2 Instance (Airflow)
       │      ├── Webserver (port 8080)
       │      └── Scheduler
       └── S3 Buckets (logs + DAGs)
       │
       ▼
Databricks Workspace
       └── Jobs triggered by Airflow DAGs
```

## Project Structure

```
.
├── .github/workflows/
│   ├── deploy.yml              # Main CI/CD pipeline
│   └── sync-dags.yml           # DAG sync to S3
├── terraform/
│   ├── main.tf                 # AWS infrastructure
│   ├── variables.tf            # Variable definitions
│   ├── backend.tf              # S3 backend config
│   └── terraform.tfvars        # Configuration values
├── scripts/
│   ├── bootstrap.sh            # EC2 user-data (installs Airflow)
│   ├── setup-terraform-backend.sh  # Creates S3 backend
│   └── destroy.sh              # Destroys infrastructure
├── airflow-dags/
│   └── databricks_etl_pipeline.py  # Sample DAG
└── databricks-notebooks/
    └── sample_etl_notebook.py  # Sample notebook
```

## Quick Start

### Prerequisites
- AWS Account with admin permissions
- GitHub repository with Actions enabled
- Databricks workspace (for job orchestration)

### Step 1: Configure GitHub Secrets

Go to **Repository Settings → Secrets → Actions** and add:

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS IAM access key |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM secret key |

### Step 2: Push to Main Branch

```bash
git add .
git commit -m "Deploy Airflow infrastructure"
git push origin main
```

### Step 3: Monitor Deployment

1. Go to **Actions** tab in GitHub
2. Watch the `Deploy Airflow Infrastructure & DAGs` workflow
3. After ~10-15 minutes, deployment completes

### Step 4: Access Airflow

From the workflow output:
```
Airflow Web UI: http://<EC2_PUBLIC_IP>:8080
Username: admin
Password: admin123
```

## Configuration

### Terraform Variables

Edit `terraform/terraform.tfvars`:

```hcl
aws_region         = "us-east-1"
environment        = "dev"
instance_type      = "t3.medium"
root_volume_size   = 30
```

### Databricks Connection (Post-Deployment)

In Airflow UI → **Admin → Connections → Add**:

| Field | Value |
|-------|-------|
| Connection Id | `databricks_default` |
| Connection Type | `Databricks` |
| Host | `https://your-workspace.cloud.databricks.com` |
| Password | Your Databricks PAT token |

### Databricks Job Variable

In Airflow UI → **Admin → Variables → Add**:

| Key | Value |
|-----|-------|
| `databricks_job_id` | Your Databricks Job ID |

## CI/CD Pipeline

The GitHub Actions workflow (`deploy.yml`) runs these jobs:

| Job | Description |
|-----|-------------|
| `validate-terraform` | Format check & validate |
| `validate-dags` | Python syntax validation |
| `setup-terraform-backend` | Creates S3 state bucket |
| `deploy-infrastructure` | Terraform apply |
| `wait-for-ec2` | Waits for instance ready |
| `deploy-dags` | SSH & verify Airflow |
| `sync-dags-s3` | Sync DAGs to S3 bucket |

**Triggers:**
- Push to `main` → Full deployment
- Push to `develop` → Validation only
- Pull Request → Plan & validate
- Manual → Workflow dispatch

## DAG Deployment

DAGs sync automatically via:
1. **S3 Sync**: GitHub Actions uploads to S3
2. **EC2 Cron**: EC2 pulls from S3 every 5 minutes

To deploy a new DAG:
```bash
# Add your DAG
cp my_dag.py airflow-dags/

# Push to trigger deployment
git add airflow-dags/my_dag.py
git commit -m "Add my_dag"
git push origin main
```

## SSH Access

Download the SSH key artifact from GitHub Actions, then:

```bash
chmod 600 airflow-key.pem
ssh -i airflow-key.pem ubuntu@<EC2_IP>
```

Or extract from Terraform locally:
```bash
cd terraform
terraform output -raw ssh_private_key > airflow-key.pem
chmod 600 airflow-key.pem
ssh -i airflow-key.pem ubuntu@$(terraform output -raw ec2_public_ip)
```

## Useful Commands

### On EC2 Instance

```bash
# Check Airflow services
sudo systemctl status airflow-webserver
sudo systemctl status airflow-scheduler

# Restart services
sudo systemctl restart airflow-scheduler
sudo systemctl restart airflow-webserver

# View bootstrap logs
sudo cat /var/log/airflow-bootstrap.log

# Run Airflow commands
sudo -u airflow /home/airflow/airflow/venv/bin/airflow dags list
sudo -u airflow /home/airflow/airflow/venv/bin/airflow version
```

### Local Commands

```bash
# Validate DAG syntax
python -m py_compile airflow-dags/my_dag.py

# Destroy infrastructure
sh scripts/destroy.sh
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Scheduler not running | `sudo systemctl restart airflow-scheduler` |
| SSH connection failed | Check security group allows port 22 |
| DAGs not appearing | Wait 5 min for S3 sync or restart scheduler |
| Terraform state error | Run `terraform init -reconfigure` |

## Cleanup

To destroy all AWS resources:

```bash
sh scripts/destroy.sh
```

Or manually:
```bash
cd terraform
terraform destroy -auto-approve
```

## License

MIT
