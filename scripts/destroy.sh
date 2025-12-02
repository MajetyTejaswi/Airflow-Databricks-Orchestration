#!/bin/bash

# This script destroys all AWS resources created by Terraform
# WARNING: This is irreversible!

echo "⚠️  DANGER: This will delete ALL AWS resources!"
echo "============================================="
echo ""

read -p "Are you SURE you want to destroy all resources? Type 'yes' to confirm: " confirm

if [ "$confirm" = "yes" ]; then
    read -p "Type 'destroy' to confirm: " confirm2
    
    if [ "$confirm2" = "destroy" ]; then
        echo ""
        echo "🗑️  Destroying resources..."
        cd terraform
        terraform destroy -auto-approve
        echo ""
        echo "✅ All resources destroyed"
    else
        echo "❌ Cancelled"
    fi
else
    echo "❌ Cancelled"
fi
