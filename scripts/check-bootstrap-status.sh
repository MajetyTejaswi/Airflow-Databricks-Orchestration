#!/bin/bash
# Script to check bootstrap status on EC2 instance
# Usage: ./check-bootstrap-status.sh <EC2_IP> <path-to-ssh-key>

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <EC2_IP> <path-to-ssh-key>"
    echo "Example: $0 52.23.45.67 ./terraform/airflow-key.pem"
    exit 1
fi

EC2_IP=$1
SSH_KEY=$2

echo "=================================="
echo "Checking Airflow Bootstrap Status"
echo "=================================="
echo ""

echo "1. Checking if bootstrap log exists..."
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ubuntu@$EC2_IP "test -f /var/log/airflow-bootstrap.log && echo '✓ Bootstrap log found' || echo '✗ Bootstrap log not found'"
echo ""

echo "2. Checking bootstrap progress..."
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ubuntu@$EC2_IP "tail -30 /var/log/airflow-bootstrap.log 2>/dev/null || echo 'Log not available yet'"
echo ""

echo "3. Checking Airflow installation..."
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ubuntu@$EC2_IP "sudo -u airflow /home/airflow/airflow/venv/bin/airflow version 2>/dev/null || echo 'Airflow not installed yet'"
echo ""

echo "4. Checking Airflow services..."
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ubuntu@$EC2_IP "sudo systemctl status airflow-webserver --no-pager | grep Active" 2>/dev/null || echo "Webserver not running"
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ubuntu@$EC2_IP "sudo systemctl status airflow-scheduler --no-pager | grep Active" 2>/dev/null || echo "Scheduler not running"
echo ""

echo "5. Checking cloud-init status..."
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ubuntu@$EC2_IP "cloud-init status"
echo ""

echo "=================================="
echo "For detailed cloud-init logs, run:"
echo "ssh -i $SSH_KEY ubuntu@$EC2_IP 'sudo tail -100 /var/log/cloud-init-output.log'"
echo "=================================="
