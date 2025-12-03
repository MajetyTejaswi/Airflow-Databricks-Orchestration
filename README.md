# Airflow Orchestration Pipeline

Complete end-to-end data pipeline using EC2 and Apache Airflow with Terraform for Infrastructure as Code.

## 📋 Overview

This project deploys a fully automated Airflow environment on AWS EC2 using GitHub Actions for CI/CD. The infrastructure is managed by Terraform and automatically provisions all necessary AWS resources.

## Prerequisites

- AWS Account with appropriate permissions
- GitHub repository with Actions enabled
- No local Terraform installation required (runs in GitHub Actions)

## Deployment via GitHub Actions

### Step 1: Configure GitHub Secrets

Add these secrets to your GitHub repository (Settings → Secrets and variables → Actions):

```
AWS_ACCESS_KEY_ID=your_aws_access_key
AWS_SECRET_ACCESS_KEY=your_aws_secret_key
```

### Step 2: Push to Main Branch

The deployment workflow automatically triggers when you push to the `main` branch:

```bash
git add .
git commit -m "Deploy Airflow infrastructure"
git push origin main
```

### Step 3: Monitor Deployment

1. Go to GitHub Actions tab in your repository
2. Watch the `Deploy Airflow Infrastructure & DAGs` workflow
3. Once complete, check the workflow output for the Airflow Web UI URL

### What Gets Deployed

- VPC with public subnet and internet gateway
- EC2 instance (t3.medium) with Airflow installed
- S3 bucket for logs
- IAM roles and security groups
- Airflow webserver on port 8080
- Airflow scheduler running as systemd service

## Accessing Airflow

After deployment completes, check the GitHub Actions output for:

```
Airflow Web UI: http://<EC2_PUBLIC_IP>:8080
Username: admin
Password: admin123
```

## Architecture

```
GitHub Actions (CI/CD)
    ↓
Terraform (Infrastructure)
    ↓
AWS EC2 (Airflow)
    ↓
DAGs Execution
```

## Project Structure

```
.
├── .github/workflows/
│   ├── deploy.yml           # Main deployment workflow
│   └── sync-dags.yml        # DAG sync workflow
├── terraform/
│   ├── main.tf              # AWS infrastructure
│   ├── variables.tf         # Variable definitions
│   └── terraform.tfvars     # Configuration values
├── scripts/
│   ├── bootstrap.sh         # EC2 initialization
│   └── setup-terraform-backend.sh
├── airflow-dags/            # Your Airflow DAGs
└── databricks-notebooks/    # Optional notebooks
```

## Configuration

The Terraform configuration uses the following defaults:
- **Region**: us-east-1
- **Instance Type**: t3.medium
- **VPC CIDR**: 10.0.0.0/16
- **Airflow Version**: 2.7.3

Modify `terraform/terraform.tfvars` to customize these values.

## SSH Access

After deployment, the private SSH key is automatically generated and stored as a GitHub Actions artifact. To access the EC2 instance:

1. Download the `ssh-key` artifact from the GitHub Actions run
2. Use the command shown in the workflow output:
   ```bash
   ssh -i airflow-key.pem ubuntu@<EC2_IP>
   ```

## Customizing DAGs

Add your DAGs to the `airflow-dags/` directory. They will automatically be deployed when you push to the main branch.

## Cleanup

To destroy the infrastructure, run the destroy script or manually delete resources via AWS Console.

#### Update Terraform Variables

```bash
cd terraform
nano terraform.tfvars
```

Update these values:

```hcl
aws_region          = "us-east-1"
environment         = "dev"
vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
instance_type       = "t3.medium"
root_volume_size    = 30
public_key_path     = "~/.ssh/airflow-key.pub"

# Databricks Configuration (UPDATE THESE!)
databricks_host     = "[your-workspace-url]"
databricks_token    = "[your-databricks-token]"
```

#### Validate Configuration

```bash
python3 scripts/validate.py
# Should output: "All checks passed!"
```

---

### Phase 3: Infrastructure Deployment (20-30 minutes)

#### Initialize Terraform

```bash
terraform init
# Downloads required providers
```

#### Review Deployment Plan

```bash
terraform plan
# Shows what will be created
```

#### Deploy Infrastructure

```bash
terraform apply
# Confirm by typing: yes
# Wait 5-10 minutes for deployment

# Output will show:
# - ec2_public_ip
# - airflow_web_ui_url
# - s3_bucket_name
```

**Save the EC2 Public IP!**

---

### Phase 4: Airflow Configuration (15 minutes)

#### Access Airflow

```
Open: http://<EC2_PUBLIC_IP>:8080
Username: admin
Password: admin123
```

**⚠️ Change password in production!**

#### Create Databricks Connection

In Airflow Web UI:

1. Go to **Admin** → **Connections**
2. Click **+ Create**
3. Fill in:
   - **Connection ID**: `databricks_default`
   - **Connection Type**: `Databricks`
   - **Host**: `[your-workspace-url]`
   - **Password**: Your Databricks token
4. Click **Test** to verify

#### Create Variables

In Airflow Web UI, go to **Admin** → **Variables**:

1. **Variable 1**
   - Key: `databricks_cluster_id`
   - Value: Your cluster ID

2. **Variable 2**
   - Key: `databricks_job_id`
   - Value: Your job ID (optional)

#### Upload Databricks Notebook

1. In Databricks, create new notebook
2. Copy content from `databricks-notebooks/sample_etl_notebook.py`
3. Note the notebook path (e.g., `/Users/your-email@company.com/sample_etl_notebook`)

#### Upload DAGs to EC2

```bash
scp -i ~/.ssh/airflow-key -r airflow-dags/* ubuntu@<EC2_IP>:/home/airflow/airflow/dags/

# Or SSH and copy manually
ssh -i ~/.ssh/airflow-key ubuntu@<EC2_IP>
cd /home/airflow/airflow/dags
# Copy your DAG files here
```

#### Update DAG Notebook Path

Edit `airflow-dags/databricks_etl_pipeline.py` and update:

```python
'notebook_path': '/Users/your-email@company.com/sample_etl_notebook',
```

#### Restart Airflow

```bash
ssh -i ~/.ssh/airflow-key ubuntu@<EC2_IP>

sudo systemctl restart airflow-scheduler
sudo systemctl restart airflow-webserver

# Wait 30 seconds, then check Web UI
```

---

### Phase 5: Testing (10 minutes)

#### Verify DAGs

In Airflow Web UI, go to **DAGs**. You should see:
- `databricks_etl_pipeline`
- `databricks_job_trigger`

If not visible, refresh browser and restart scheduler.

#### Test Databricks Connection

1. Go to **Admin** → **Connections**
2. Click test icon on `databricks_default`
3. Should show "Connection test successful"

#### Trigger Test Run

1. Go to **DAGs**
2. Click on `databricks_etl_pipeline`
3. Click the play button
4. Go to **Graph** to see execution
5. Check logs for results

#### Verify Databricks Execution

In Databricks, go to **Workflows** → **Jobs** to verify the job ran.

---

## Complete Setup Instructions

### Step-by-Step with Details

#### 1. Get Databricks Credentials

In Databricks Workspace:

1. Click your profile icon (top-right)
2. Select "User Settings"
3. Click "Generate new token"
4. Copy the token value
5. Note your workspace URL (from address bar)

#### 2. SSH Configuration

```bash
# Create SSH key
ssh-keygen -t rsa -b 4096 -f ~/.ssh/airflow-key -N ""

# Check permissions (should show -rw-------)
ls -la ~/.ssh/airflow-key
```

#### 3. Terraform Configuration

Create/edit `terraform/terraform.tfvars`:

```hcl
# AWS
aws_region              = "us-east-1"
environment             = "dev"
vpc_cidr                = "10.0.0.0/16"
public_subnet_cidr      = "10.0.1.0/24"

# EC2
instance_type           = "t3.medium"
root_volume_size        = 30

# SSH
public_key_path         = "~/.ssh/airflow-key.pub"

# Databricks
databricks_host         = "[your-workspace-url]"
databricks_token        = "[your-databricks-token]"
```

#### 4. Infrastructure Deployment

```bash
cd terraform

# Initialize
terraform init

# Review
terraform plan > plan.txt
# Review plan.txt for changes

# Deploy
terraform apply
# Type: yes when prompted
# Wait 10-15 minutes
```

#### 5. Airflow Setup (After EC2 is running)

SSH into EC2:

```bash
ssh -i ~/.ssh/airflow-key ubuntu@<EC2_IP>

# Check Airflow is running
sudo systemctl status airflow-webserver
sudo systemctl status airflow-scheduler

# View bootstrap log
tail -f /var/log/airflow-bootstrap.log
```

---

## Advanced Configuration

### Custom Airflow Settings

#### Change Executor Type

For production, use Celery or Kubernetes:

```bash
ssh -i ~/.ssh/airflow-key ubuntu@<EC2_IP>
sudo -u airflow bash

pip install apache-airflow[celery]
pip install redis

# Update /home/airflow/airflow/airflow.cfg
executor = CeleryExecutor
broker_url = redis://localhost:6379/0
```

#### Enable Authentication

```python
# In airflow.cfg
[webserver]
authenticate = True
auth_backend = airflow.contrib.auth.backends.password_auth
rbac = True
```

#### Remote Logging to S3

```python
# airflow.cfg
[logging]
remote_logging = True
remote_log_conn_id = aws_default
remote_base_log_folder = s3://your-bucket/airflow-logs
```

### Adding Custom DAGs

Create new file `airflow-dags/my_dag.py`:

```python
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.databricks.operators.databricks import DatabricksSubmitRunOperator

default_args = {
    'owner': 'airflow',
    'start_date': datetime(2024, 1, 1),
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'my_custom_dag',
    default_args=default_args,
    schedule_interval='0 2 * * *',  # 2 AM daily
    catchup=False,
)

def print_hello():
    return 'Hello from Airflow!'

task1 = PythonOperator(
    task_id='hello',
    python_callable=print_hello,
    dag=dag,
)

# Databricks task
task2 = DatabricksSubmitRunOperator(
    task_id='databricks_run',
    databricks_conn_id='databricks_default',
    new_cluster_config={...},
    notebook_task={...},
    dag=dag,
)

task1 >> task2
```

### Schedule Patterns

```python
schedule_interval='0 2 * * *'        # Daily at 2 AM
schedule_interval='0 2 * * MON'      # Monday at 2 AM
schedule_interval='0 2 1 * *'        # First of month at 2 AM
schedule_interval='*/15 * * * *'     # Every 15 minutes
schedule_interval='@daily'           # Daily
schedule_interval='@weekly'          # Weekly
schedule_interval='@monthly'         # Monthly
schedule_interval=None               # Manual trigger only
```

### Using Airflow Variables

Set in Web UI or CLI:

```bash
airflow variables set my_variable my_value
```

Use in DAG:

```python
from airflow.models import Variable
my_var = Variable.get("my_variable")
```

### Email Alerts

```python
from airflow.utils.email import send_email

def send_failure_email(context):
    send_email(
        to='admin@company.com',
        subject=f"DAG {context['dag'].dag_id} failed",
        html_content=f"Task {context['task'].task_id} failed"
    )

dag = DAG(
    'my_dag',
    email=['admin@company.com'],
    email_on_failure=True,
    email_on_retry=True,
    on_failure_callback=send_failure_email,
)
```

### Slack Notifications

```bash
pip install apache-airflow-providers-slack
```

In Airflow Web UI, create connection:
- Conn ID: `slack_default`
- Conn Type: `Slack`
- Password: Your Slack webhook URL

In DAG:

```python
from airflow.providers.slack.operators.slack_webhook import SlackWebhookOperator

notify = SlackWebhookOperator(
    task_id='slack_notification',
    http_conn_id='slack_default',
    message='Pipeline completed!',
)
```

### Database Configuration

#### Use PostgreSQL Instead of SQLite

```bash
sudo apt-get install -y postgresql postgresql-contrib

# Create database
sudo -u postgres createdb airflow_db
sudo -u postgres createuser airflow_user
sudo -u postgres psql -c "ALTER USER airflow_user WITH PASSWORD 'password';"

# Update airflow.cfg
sql_alchemy_conn = postgresql://airflow_user:password@localhost:5432/airflow_db
```

### Scaling Configuration

#### Upgrade EC2 Instance

Edit `terraform/terraform.tfvars`:

```hcl
instance_type = "t3.large"   # More CPU/RAM
# or
instance_type = "m5.xlarge"  # For high-load
```

Then run:

```bash
terraform plan
terraform apply
```

#### Use Spot Instances (70% cheaper)

Edit `terraform/main.tf`:

```hcl
resource "aws_instance" "airflow" {
  instance_market_options {
    market_type = "spot"
  }
}
```

### Security Hardening

#### Change Airflow Password

```bash
ssh -i ~/.ssh/airflow-key ubuntu@<EC2_IP>

export AIRFLOW_HOME=/home/airflow/airflow
source $AIRFLOW_HOME/venv/bin/activate

airflow users delete --username admin

airflow users create \
  --username admin \
  --firstname Admin \
  --lastname User \
  --role Admin \
  --email admin@company.com \
  --password your-secure-password
```

#### Enable HTTPS/SSL

```bash
sudo apt-get install certbot

sudo certbot certonly --standalone -d yourdomain.com

# Update airflow.cfg
[webserver]
web_server_ssl_cert = /etc/letsencrypt/live/yourdomain.com/fullchain.pem
web_server_ssl_key = /etc/letsencrypt/live/yourdomain.com/privkey.pem
```

#### Restrict SSH Access

In `terraform/main.tf`, update security group:

```hcl
ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["YOUR_IP/32"]  # Your office IP only
}

ingress {
  from_port   = 8080
  to_port     = 8080
  protocol    = "tcp"
  cidr_blocks = ["YOUR_IP/32"]  # Restrict Airflow UI
}
```

### Monitoring & Logging

#### CloudWatch Integration

```bash
pip install watchtower

# airflow.cfg
[logging]
remote_logging = True
remote_log_conn_id = aws_default
```

#### View Logs

```bash
# Airflow logs on EC2
tail -f /home/airflow/airflow/logs/*/latest/*.log

# Specific DAG logs
tail -f /home/airflow/airflow/logs/my_dag/

# Webserver logs
sudo tail -f /home/airflow/airflow/logs/webserver.log
```

### Cost Optimization

#### Stop EC2 When Not Used

```bash
aws ec2 stop-instances --instance-ids <instance-id>
aws ec2 start-instances --instance-ids <instance-id>
```

#### Estimate Costs

```bash
# AWS Cost Explorer
aws ce get-cost-and-usage \
  --time-period StartDate=2024-01-01,EndDate=2024-01-31 \
  --granularity DAILY \
  --metrics "BlendedCost"
```

**Cost Estimate:**
- EC2 t3.medium: ~$30/month
- S3 & Data Transfer: ~$10/month
- Secrets Manager: ~$0.40/month
- Databricks: Separate (varies by tier)

**Total: ~$40-50/month + Databricks**

---

## Troubleshooting

### Issue: Can't Connect to Airflow Web UI

**Solution:**

```bash
# Check service status
ssh -i ~/.ssh/airflow-key ubuntu@<EC2_IP>
sudo systemctl status airflow-webserver

# If not running, restart
sudo systemctl restart airflow-webserver

# Check logs
sudo tail -f /home/airflow/airflow/logs/webserver.log

# Check security group allows port 8080
# In AWS Console: EC2 → Security Groups
```

### Issue: Databricks Connection Fails

**Solution:**

```bash
# Verify credentials
ssh -i ~/.ssh/airflow-key ubuntu@<EC2_IP>

# Test connection manually
python3 << 'EOF'
import requests
host = "[your-workspace-url]"
token = "[your-databricks-token]"
headers = {"Authorization": f"Bearer {token}"}
response = requests.get(f"{host}/api/2.0/workspace/get-status", headers=headers)
print(f"Status: {response.status_code}")
print(f"Response: {response.text}")
EOF
```

### Issue: DAGs Not Showing in Airflow

**Solution:**

```bash
ssh -i ~/.ssh/airflow-key ubuntu@<EC2_IP>

# Check DAG syntax
airflow dags validate

# List DAGs
airflow dags list

# Restart scheduler
sudo systemctl restart airflow-scheduler

# Refresh browser (Ctrl+Shift+R)
```

### Issue: Task Fails in Airflow

**Solution:**

```bash
# Check Airflow logs in Web UI
# Go to DAG → Task Instance → Logs

# Or view on EC2
tail -f /home/airflow/airflow/logs/<dag_name>/<task_id>/latest.log

# Test task manually
airflow tasks test my_dag my_task 2024-01-01
```

### Issue: EC2 Bootstrap Script Failed

**Solution:**

```bash
# View bootstrap log
ssh -i ~/.ssh/airflow-key ubuntu@<EC2_IP>
tail -f /var/log/airflow-bootstrap.log

# Check services
sudo systemctl status airflow-webserver
sudo systemctl status airflow-scheduler

# If services didn't start, check system logs
sudo journalctl -xe
```

### Issue: Terraform Apply Fails

**Solution:**

```bash
# Verify AWS credentials
aws sts get-caller-identity

# Check Terraform syntax
terraform validate

# Increase verbosity
TF_LOG=DEBUG terraform apply

# Check state file
terraform show

# If stuck, re-initialize
terraform init
```

---

## Useful Commands

### Terraform Commands

```bash
terraform init                 # Initialize
terraform validate             # Check syntax
terraform plan                 # Review changes
terraform apply                # Deploy
terraform destroy              # Delete all resources
terraform show                 # Show current state
terraform output               # Show outputs
terraform output -json         # Output as JSON
```

### Airflow Commands (on EC2)

```bash
# Access Airflow CLI
export AIRFLOW_HOME=/home/airflow/airflow
source $AIRFLOW_HOME/venv/bin/activate

airflow dags list              # List DAGs
airflow tasks list <dag_id>    # List tasks
airflow dags test <dag_id>     # Test DAG
airflow tasks test <dag> <task> <date>  # Test task
airflow variables list         # List variables
airflow variables set <key> <value>     # Create variable
airflow connections list       # List connections
airflow users list             # List users
airflow users create --username <user> --role <role> --email <email> --password <pwd>
```

### AWS Commands

```bash
aws sts get-caller-identity    # Verify credentials
aws ec2 describe-instances     # List EC2 instances
aws ec2 describe-security-groups  # List security groups
aws s3 ls                       # List S3 buckets
aws secretsmanager get-secret-value --secret-id <name>  # Get secret
```

### EC2 System Commands

```bash
ssh -i ~/.ssh/airflow-key ubuntu@<EC2_IP>  # SSH into EC2

# Service management
sudo systemctl status airflow-webserver
sudo systemctl status airflow-scheduler
sudo systemctl restart airflow-webserver
sudo systemctl restart airflow-scheduler

# Check logs
tail -f /home/airflow/airflow/logs/webserver.log
tail -f /home/airflow/airflow/logs/scheduler.log
df -h                           # Disk space
free -h                         # Memory
```

---

## Pre-Deployment Checklist

- [ ] AWS credentials configured (`aws configure`)
- [ ] SSH key pair generated (`~/.ssh/airflow-key`)
- [ ] Databricks URL obtained
- [ ] Databricks token generated
- [ ] `terraform/terraform.tfvars` updated with all values
- [ ] `python3 scripts/validate.py` passed
- [ ] Terraform initialized (`terraform init`)
- [ ] `terraform plan` reviewed
- [ ] Ready to run `terraform apply`

---

## Post-Deployment Checklist

- [ ] EC2 instance is running
- [ ] Airflow Web UI accessible at `http://<EC2_IP>:8080`
- [ ] Can login with admin/admin123
- [ ] Databricks connection created and tested
- [ ] Airflow variables created
- [ ] DAGs uploaded to EC2
- [ ] DAGs visible in Airflow UI
- [ ] Test DAG triggered successfully
- [ ] Databricks notebook executed
- [ ] **Changed Airflow password** (in production)
- [ ] **Restricted security group access** (in production)

---

## Cost Breakdown

| Service | Cost | Notes |
|---------|------|-------|
| EC2 t3.medium | $30/month | 1 compute unit |
| VPC & Networking | Free | Minimal data transfer |
| IAM | Free | Permission management |
| S3 (100GB) | $2.30/month | Logs + data |
| S3 Data Transfer | $5/month | Out-of-region transfers |
| Secrets Manager | $0.40/month | Credential storage |
| CloudWatch | ~$2/month | Basic monitoring |
| **AWS Subtotal** | **$40/month** | |
| **Databricks** | **$50-500+/month** | Varies by tier |
| **TOTAL** | **$90-540+/month** | Depends on Databricks |

### Cost Optimization Tips

1. **Use Spot Instances**: 70% discount on EC2
2. **Stop EC2 when not needed**: Don't run 24/7
3. **Keep resources in same region**: Avoid data transfer costs
4. **Use Reserved Instances**: 30% discount for 1-3 years
5. **Monitor with AWS Cost Explorer**: Set budget alerts

---

## Security Best Practices

✅ **Implemented by default:**
- VPC isolation
- Security groups with restricted access
- IAM roles with least privilege
- AWS Secrets Manager for credentials
- SSH key-based authentication
- Encrypted data transfer

**Additional recommendations:**

- [ ] Change default Airflow password
- [ ] Restrict SSH access to your IP only
- [ ] Enable HTTPS/SSL certificate
- [ ] Rotate Databricks token regularly
- [ ] Configure CloudTrail for auditing
- [ ] Implement backup/disaster recovery
- [ ] Setup IP whitelisting
- [ ] Enable VPC Flow Logs

---

## Next Steps

1. **Deploy infrastructure** with Terraform
2. **Access Airflow Web UI** and verify it's running
3. **Create Databricks connection** in Airflow
4. **Upload your first DAG** and test it
5. **Create custom DAGs** for your use case
6. **Setup monitoring** and alerts
7. **Configure security** for production
8. **Document** your pipelines

---

## Cleanup

To delete all AWS resources and stop incurring costs:

```bash
cd terraform
terraform destroy
# Confirm by typing: yes
# Wait for all resources to be deleted
```

**⚠️ WARNING:** This is irreversible. All data will be deleted.

---

## Support

1. **Check documentation**: Start here for most answers
2. **Run validation**: `python3 scripts/validate.py`
3. **Check logs**: View EC2 and Airflow logs
4. **Test connections**: Use Airflow Web UI test buttons
5. **Ask community**: Stack Overflow, Slack, forums

---

## Additional Resources

### Official Documentation

- [Apache Airflow](https://airflow.apache.org/docs/)
- [Databricks](https://docs.databricks.com/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS Documentation](https://aws.amazon.com/documentation/)

### Community

- [Airflow Slack](https://apache-airflow.slack.com)
- [Databricks Community](https://www.databricks.com/community)
- [Terraform Forums](https://discuss.hashicorp.com/c/terraform/)
- [Stack Overflow](https://stackoverflow.com) - Tag: `airflow`, `databricks`, `terraform`

---

## Version Information

- **Created**: November 26, 2024
- **Last Updated**: November 26, 2025
- **Version**: 1.0
- **Status**: ✅ Production Ready

---

**Ready to deploy? Start with the [Quick Start](#quick-start) section above!** 🚀
