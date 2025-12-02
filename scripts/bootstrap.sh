#!/bin/bash
set -e

# Update system packages
apt-get update
apt-get upgrade -y

# Install required packages
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

# Create airflow user
useradd -m -s /bin/bash airflow || true

# Create Airflow home directory
export AIRFLOW_HOME=/home/airflow/airflow
mkdir -p $AIRFLOW_HOME
chown -R airflow:airflow $AIRFLOW_HOME

# Switch to airflow user for Python setup
sudo -u airflow bash << 'EOF'
# Set Airflow environment variables
export AIRFLOW_HOME=/home/airflow/airflow
export PYTHONUNBUFFERED=1

# Create Python virtual environment
python3 -m venv $AIRFLOW_HOME/venv
source $AIRFLOW_HOME/venv/bin/activate

# Upgrade pip
pip install --upgrade pip setuptools wheel

# Install Airflow with Databricks provider
pip install apache-airflow==2.7.3
pip install apache-airflow-providers-databricks==4.3.0
pip install apache-airflow-providers-http==4.4.2
pip install requests

# Initialize Airflow database
airflow db init

# Create Airflow admin user (default credentials - CHANGE IN PRODUCTION)
airflow users create \
    --username admin \
    --firstname Admin \
    --lastname User \
    --role Admin \
    --email admin@example.com \
    --password admin123 || true

# Create DAGs directory
mkdir -p $AIRFLOW_HOME/dags
mkdir -p $AIRFLOW_HOME/logs
mkdir -p $AIRFLOW_HOME/plugins

# Clone the DAGs from GitHub (if using Git integration)
cd $AIRFLOW_HOME/dags

# Try to clone from GitHub repository
# Replace YOUR_USERNAME/YOUR_REPO with your actual repository
if [ ! -z "$GITHUB_REPO_URL" ]; then
  echo "Cloning DAGs from GitHub: $GITHUB_REPO_URL"
  git clone "$GITHUB_REPO_URL" .
elif [ ! -z "$CI_REPOSITORY_URL" ]; then
  # For GitLab CI
  echo "Cloning DAGs from GitLab: $CI_REPOSITORY_URL"
  git clone "$CI_REPOSITORY_URL" .
else
  echo "No Git repo configured - Creating empty dags directory"
  git init
fi

# Set git user for future commits (if needed)
git config --global user.email "airflow@company.com" || true
git config --global user.name "Airflow Bot" || true

# Create a periodic Git sync script
mkdir -p $AIRFLOW_HOME/scripts
cat > $AIRFLOW_HOME/scripts/sync-dags-git.sh << 'GIT_SYNC_SCRIPT'
#!/bin/bash
# Sync DAGs from GitHub every 30 minutes

AIRFLOW_HOME=/home/airflow/airflow
DAGS_FOLDER=$AIRFLOW_HOME/dags
GIT_LOG=$AIRFLOW_HOME/logs/git-sync.log

cd $DAGS_FOLDER

# Check if git is initialized
if [ ! -d .git ]; then
  echo "[$(date)] ERROR: Git not initialized in $DAGS_FOLDER" >> $GIT_LOG
  exit 1
fi

# Pull latest changes
echo "[$(date)] Starting Git sync..." >> $GIT_LOG

git fetch origin 2>&1 | tee -a $GIT_LOG
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
git pull origin $CURRENT_BRANCH 2>&1 | tee -a $GIT_LOG

# Check if there are new DAGs
if git diff --quiet HEAD~1..HEAD airflow-dags/ 2>/dev/null; then
  echo "[$(date)] No DAG changes detected" >> $GIT_LOG
else
  echo "[$(date)] DAG changes detected - Reloading Airflow scheduler" >> $GIT_LOG
  sudo systemctl reload airflow-scheduler 2>&1 | tee -a $GIT_LOG
fi

echo "[$(date)] Git sync completed" >> $GIT_LOG
GIT_SYNC_SCRIPT

chmod +x $AIRFLOW_HOME/scripts/sync-dags-git.sh

# Add cron job for periodic DAG sync
echo "*/30 * * * * airflow $AIRFLOW_HOME/scripts/sync-dags-git.sh" | crontab -

# Update Airflow configuration
cat > $AIRFLOW_HOME/airflow.cfg << 'AIRFLOW_CFG'
[core]
dags_folder = /home/airflow/airflow/dags
base_log_folder = /home/airflow/airflow/logs
load_examples = False
load_default_connections = False
executor = LocalExecutor
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

[databricks]
# Databricks credentials will be loaded from AWS Secrets Manager via environment variables
AIRFLOW_CFG

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
systemctl daemon-reload
systemctl enable airflow-webserver
systemctl enable airflow-scheduler

# Start services
systemctl start airflow-webserver
systemctl start airflow-scheduler

# Log completion
echo "Airflow bootstrap completed at $(date)" > /var/log/airflow-bootstrap.log
