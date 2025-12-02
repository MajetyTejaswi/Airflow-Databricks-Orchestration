#!/bin/bash

# Post-deployment configuration script
# Run this after EC2 instance is deployed

echo "🔧 Airflow Post-Deployment Configuration"
echo "========================================"
echo ""

# Get EC2 IP from Terraform output
read -p "Enter EC2 Public IP (or DNS): " ec2_host

# SSH key path
SSH_KEY=~/.ssh/airflow-key

echo ""
echo "📦 Setting up Airflow Databricks connection..."
echo ""

# Create remote commands to setup Databricks connection
REMOTE_COMMANDS='
export AIRFLOW_HOME=/home/airflow/airflow
source $AIRFLOW_HOME/venv/bin/activate

# Get input from user (we\'ll prompt separately)
echo "Setting up Databricks connection..."
'

echo "Please provide Databricks connection details:"
read -p "Databricks Host (e.g., https://adb-xxxxx.azuredatabricks.net): " db_host
read -s -p "Databricks Token: " db_token
echo ""

# Execute on remote server
ssh -i $SSH_KEY ubuntu@$ec2_host << EOF
export AIRFLOW_HOME=/home/airflow/airflow
source \$AIRFLOW_HOME/venv/bin/activate

# Create Databricks connection
python3 << 'PYEOF'
from airflow.models import Connection
from sqlalchemy import create_engine

conn = Connection(
    conn_id='databricks_default',
    conn_type='databricks',
    host='$db_host',
    password='$db_token'
)

# Save connection to Airflow
import os
os.system(f"""
    airflow connections add \\
        --conn-id 'databricks_default' \\
        --conn-type 'databricks' \\
        --conn-host '$db_host' \\
        --conn-password '$db_token'
""")

print("✅ Databricks connection created successfully!")
PYEOF

# Create variables for DAGs
airflow variables set databricks_cluster_id "your-cluster-id"
airflow variables set databricks_job_id "your-job-id"

echo "✅ Variables created. Update them with actual values:"
echo "   - databricks_cluster_id: Your Databricks cluster ID"
echo "   - databricks_job_id: Your Databricks job ID (if using job trigger DAG)"
EOF

echo ""
echo "✅ Post-deployment configuration complete!"
echo ""
echo "📝 Next steps:"
echo "1. Update Airflow variables in the Web UI: Admin → Variables"
echo "2. Upload/sync DAGs from GitHub or local files"
echo "3. Enable DAGs in Airflow Web UI"
echo "4. Verify Databricks connection in Admin → Connections"
