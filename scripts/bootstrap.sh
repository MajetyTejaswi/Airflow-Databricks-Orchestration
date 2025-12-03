#!/bin/bash
# IMPORTANT: This script runs as user_data on EC2 startup
# Content-Type: text/x-shellscript; charset="us-ascii"
set -ex

# Redirect output to log file first
exec > >(tee -a /var/log/airflow-bootstrap.log) 2>&1

# Wait for network to be available (not for cloud-init to finish - that causes deadlock)
echo "Waiting for network..."
while ! ping -c 1 -W 1 8.8.8.8 &> /dev/null; do
    echo "Waiting for network connectivity..."
    sleep 2
done
echo "Network is available"

# Wait for apt locks to be released
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    echo "Waiting for apt lock to be released..."
    sleep 5
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
    libffi-dev

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

# Deploy DAGs from GitHub repository
cd $AIRFLOW_HOME/dags
echo "Downloading DAGs from GitHub..."

# Download DAG files directly from the repository
# Using raw GitHub content URL
GITHUB_REPO="MajetyTejaswi/Airflow-Databricks-Orchestration"
GITHUB_BRANCH="main"

# Download the DAG file
curl -sSL "https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/airflow-dags/databricks_etl_pipeline.py" -o databricks_etl_pipeline.py || {
  echo "Failed to download DAG from GitHub, creating placeholder..."
  cat > databricks_etl_pipeline.py << 'DAGFILE'
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

with DAG(
    'databricks_etl_pipeline',
    default_args=default_args,
    description='Sample ETL Pipeline',
    schedule_interval=timedelta(days=1),
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['etl', 'databricks'],
) as dag:

    def sample_task():
        print("Running sample ETL task")
        return "Task completed successfully"

    task = PythonOperator(
        task_id='sample_etl_task',
        python_callable=sample_task,
    )
DAGFILE
}

echo "✓ DAGs deployed"
ls -la $AIRFLOW_HOME/dags/

# Set proper ownership
chown -R airflow:airflow $AIRFLOW_HOME/dags/

# Create a periodic DAG sync script to pull latest from GitHub
mkdir -p $AIRFLOW_HOME/scripts
cat > $AIRFLOW_HOME/scripts/sync-dags.sh << 'SYNC_SCRIPT'
#!/bin/bash
# Sync DAGs from GitHub every 30 minutes

AIRFLOW_HOME=/home/airflow/airflow
DAGS_FOLDER=$AIRFLOW_HOME/dags
SYNC_LOG=$AIRFLOW_HOME/logs/dag-sync.log

GITHUB_REPO="MajetyTejaswi/Airflow-Databricks-Orchestration"
GITHUB_BRANCH="main"

echo "[$(date)] Starting DAG sync from GitHub..." >> $SYNC_LOG

# Download latest DAG files
cd $DAGS_FOLDER
curl -sSL "https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/airflow-dags/databricks_etl_pipeline.py" -o databricks_etl_pipeline.py.new 2>> $SYNC_LOG

# Check if file changed
if ! cmp -s databricks_etl_pipeline.py databricks_etl_pipeline.py.new 2>/dev/null; then
  mv databricks_etl_pipeline.py.new databricks_etl_pipeline.py
  echo "[$(date)] DAG files updated - Restarting scheduler" >> $SYNC_LOG
  sudo systemctl restart airflow-scheduler 2>&1 | tee -a $SYNC_LOG
else
  rm -f databricks_etl_pipeline.py.new
  echo "[$(date)] No DAG changes detected" >> $SYNC_LOG
fi

echo "[$(date)] DAG sync completed" >> $SYNC_LOG
SYNC_SCRIPT

chmod +x $AIRFLOW_HOME/scripts/sync-dags.sh

# Add cron job for periodic DAG sync
(crontab -l 2>/dev/null || true; echo "*/30 * * * * $AIRFLOW_HOME/scripts/sync-dags.sh") | crontab -

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
