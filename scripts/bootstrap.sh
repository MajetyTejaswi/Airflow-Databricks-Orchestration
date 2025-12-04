#!/bin/bash
set -ex

# Redirect output to log file
exec > /var/log/airflow-bootstrap.log 2>&1

echo "==================================="
echo "Bootstrap started: $(date)"
echo "==================================="

# Wait for cloud-init to finish first
sleep 30

# Wait for apt locks to be released
for i in {1..30}; do
    if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && \
       ! fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
        break
    fi
    echo "Waiting for apt lock... attempt $i"
    sleep 10
done

echo "==================================="
echo "Starting Airflow Bootstrap: $(date)"
echo "Host: $(hostname)"
echo "==================================="

# Update system packages
echo "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install required packages
echo "Installing required packages..."
apt-get install -y \
    python3-pip \
    python3-venv \
    git \
    curl \
    wget \
    vim \
    build-essential \
    libssl-dev \
    libffi-dev \
    awscli

echo "✓ Packages installed"

# Create airflow user
echo "Creating airflow user..."
useradd -m -s /bin/bash airflow || true
echo "✓ Airflow user created"

# Create Airflow home directory
echo "Setting up Airflow home directory..."
export AIRFLOW_HOME=/home/airflow/airflow
mkdir -p $AIRFLOW_HOME
chown -R airflow:airflow $AIRFLOW_HOME
echo "✓ Airflow home directory created"

# Switch to airflow user for Python setup
echo "Installing Airflow as airflow user..."
sudo -u airflow bash << 'EOF'
# Set Airflow environment variables
export AIRFLOW_HOME=/home/airflow/airflow
export PYTHONUNBUFFERED=1

echo "Creating Python virtual environment..."

# Create Python virtual environment
python3 -m venv $AIRFLOW_HOME/venv
source $AIRFLOW_HOME/venv/bin/activate

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip setuptools wheel
echo "✓ Pip upgraded"

# Install Airflow with basic providers
echo "Installing Apache Airflow (this may take 5-10 minutes)..."
pip install apache-airflow==2.7.3
echo "✓ Airflow installed"

echo "Installing Airflow providers..."
pip install apache-airflow-providers-http==4.4.2
pip install apache-airflow-providers-databricks==6.0.0
# Fix flask-session compatibility issue
pip install 'flask-session<0.6'
echo "✓ Providers installed"

# Initialize Airflow database
echo "Initializing Airflow database..."
airflow db init
echo "✓ Database initialized"

# Create DAGs directory
mkdir -p $AIRFLOW_HOME/dags
mkdir -p $AIRFLOW_HOME/logs
mkdir -p $AIRFLOW_HOME/plugins

# Get AWS account info for S3 bucket name
INSTANCE_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
AWS_ACCOUNT_ID=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep accountId | awk -F'"' '{print $4}')
S3_DAGS_BUCKET="airflow-dags-${AWS_ACCOUNT_ID}-${INSTANCE_REGION}"

echo "S3 DAGs Bucket: $S3_DAGS_BUCKET"

# Create placeholder DAG initially
cat > $AIRFLOW_HOME/dags/placeholder.py << 'DAGFILE'
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

with DAG(
    'placeholder_dag',
    default_args=default_args,
    description='Placeholder - DAGs will sync from S3',
    schedule_interval=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['placeholder'],
) as dag:

    def info_task():
        print("DAGs are synced from S3 bucket every 5 minutes")
        return "Done"

    task = PythonOperator(
        task_id='info_task',
        python_callable=info_task,
    )
DAGFILE

echo "✓ Placeholder DAG created"
ls -la $AIRFLOW_HOME/dags/

# Set proper ownership
chown -R airflow:airflow $AIRFLOW_HOME/dags/

# Create S3 DAG sync script
mkdir -p $AIRFLOW_HOME/scripts
cat > $AIRFLOW_HOME/scripts/sync-dags-s3.sh << 'SYNC_SCRIPT'
#!/bin/bash
# Sync DAGs from S3 every 5 minutes

AIRFLOW_HOME=/home/airflow/airflow
DAGS_FOLDER=$AIRFLOW_HOME/dags
SYNC_LOG=$AIRFLOW_HOME/logs/dag-sync.log

# Get S3 bucket name from instance metadata
INSTANCE_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
AWS_ACCOUNT_ID=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep accountId | awk -F'"' '{print $4}')
S3_DAGS_BUCKET="airflow-dags-${AWS_ACCOUNT_ID}-${INSTANCE_REGION}"

echo "[$(date)] Starting DAG sync from S3: s3://$S3_DAGS_BUCKET/dags/" >> $SYNC_LOG

# Sync DAGs from S3 (only .py files, delete removed files)
aws s3 sync "s3://${S3_DAGS_BUCKET}/dags/" "$DAGS_FOLDER/" \
    --exclude "*" \
    --include "*.py" \
    --delete \
    2>> $SYNC_LOG

# Set ownership
chown -R airflow:airflow $DAGS_FOLDER/

echo "[$(date)] DAG sync completed" >> $SYNC_LOG
echo "[$(date)] Current DAGs:" >> $SYNC_LOG
ls -la $DAGS_FOLDER/*.py 2>> $SYNC_LOG || echo "No DAGs found" >> $SYNC_LOG
SYNC_SCRIPT

chmod +x $AIRFLOW_HOME/scripts/sync-dags-s3.sh

# Add cron job for periodic S3 DAG sync (every 5 minutes)
(crontab -l 2>/dev/null | grep -v sync-dags || true; echo "*/5 * * * * $AIRFLOW_HOME/scripts/sync-dags-s3.sh") | crontab -

# Run initial sync
echo "Running initial S3 DAG sync..."
$AIRFLOW_HOME/scripts/sync-dags-s3.sh || echo "Initial S3 sync skipped (bucket may be empty)"

# Update Airflow configuration
cat > $AIRFLOW_HOME/airflow.cfg << 'AIRFLOW_CFG'
[core]
dags_folder = /home/airflow/airflow/dags
base_log_folder = /home/airflow/airflow/logs
load_examples = False
load_default_connections = False
executor = SequentialExecutor
database_backend = sqlite
sql_alchemy_conn = sqlite:////home/airflow/airflow/airflow.db

[webserver]
authenticate = False
expose_config = False
rbac = True

[logging]
remote_logging = False

[scheduler]
catchup_by_default = False
AIRFLOW_CFG

# Re-initialize database with correct config
echo "Re-initializing Airflow database with correct executor..."
airflow db init
echo "✓ Database re-initialized"

# Create admin user
echo "Creating admin user..."
airflow users create \
    --username admin \
    --firstname Admin \
    --lastname User \
    --role Admin \
    --email admin@example.com \
    --password admin123 || true
echo "✓ Admin user created"

EOF

# Create systemd service for Airflow Webserver
cat > /etc/systemd/system/airflow-webserver.service << 'SERVICE'
[Unit]
Description=Airflow Webserver
After=network.target
Wants=airflow-scheduler.service

[Service]
Type=simple
User=airflow
Group=airflow
WorkingDirectory=/home/airflow/airflow
Environment="AIRFLOW_HOME=/home/airflow/airflow"
ExecStart=/home/airflow/airflow/venv/bin/airflow webserver --port 8080
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

# Create systemd service for Airflow Scheduler
cat > /etc/systemd/system/airflow-scheduler.service << 'SERVICE'
[Unit]
Description=Airflow Scheduler
After=network.target

[Service]
Type=simple
User=airflow
Group=airflow
WorkingDirectory=/home/airflow/airflow
Environment="AIRFLOW_HOME=/home/airflow/airflow"
ExecStart=/home/airflow/airflow/venv/bin/airflow scheduler
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

# Reload systemd and enable services
echo "Configuring systemd services..."
systemctl daemon-reload
systemctl enable airflow-webserver
systemctl enable airflow-scheduler

# Start services
echo "Starting Airflow services..."
systemctl start airflow-webserver
systemctl start airflow-scheduler

# Wait a bit for services to start
sleep 10

# Verify services are running
echo "Verifying services..."
systemctl status airflow-webserver --no-pager || true
systemctl status airflow-scheduler --no-pager || true

# Create completion marker
touch /var/log/airflow-bootstrap-complete

# Log complete
echo "==================================="
echo "Airflow bootstrap completed: $(date)"
echo "Web UI: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080"
echo "Username: admin | Password: admin123"
echo "==================================="
