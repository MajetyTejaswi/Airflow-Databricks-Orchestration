#!/bin/bash

# Script to check Airflow status on EC2 instance
# Usage: ./check-airflow-status.sh <ec2-ip>

EC2_IP=${1:-44.222.68.141}
SSH_KEY=~/.ssh/airflow-key

echo "🔍 Checking Airflow status on $EC2_IP..."
echo ""

# SSH into instance and check status
ssh -i $SSH_KEY ubuntu@$EC2_IP << 'EOF'

echo "📋 Bootstrap Script Status:"
echo "================================"
if [ -f /var/log/airflow-bootstrap.log ]; then
    echo "✅ Bootstrap completed:"
    cat /var/log/airflow-bootstrap.log
else
    echo "⏳ Bootstrap still running... Checking cloud-init log:"
    tail -20 /var/log/cloud-init-output.log
fi

echo ""
echo "📋 Airflow Services Status:"
echo "================================"
systemctl status airflow-webserver --no-pager
echo ""
systemctl status airflow-scheduler --no-pager

echo ""
echo "📋 Python Virtual Environment:"
echo "================================"
source /home/airflow/airflow/venv/bin/activate
which airflow
airflow version

echo ""
echo "📋 Airflow Database:"
echo "================================"
airflow db check

echo ""
echo "📋 Airflow DAGs:"
echo "================================"
airflow dags list

echo ""
echo "🌐 Airflow Web UI URL: http://$EC2_IP:8080"
echo "👤 Login: admin / admin123"

EOF

