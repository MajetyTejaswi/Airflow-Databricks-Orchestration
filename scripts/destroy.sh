#!/bin/bash

# This script destroys all AWS resources created by Terraform
# WARNING: This is irreversible!

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

echo "⚠️  DANGER: This will delete ALL AWS resources!"
echo "============================================="
echo ""

# Check if terraform directory exists
if [ ! -d "$TERRAFORM_DIR" ]; then
    echo "❌ Error: Terraform directory not found at $TERRAFORM_DIR"
    exit 1
fi

read -p "Are you SURE you want to destroy all resources? Type 'yes' to confirm: " confirm

if [ "$confirm" = "yes" ]; then
    read -p "Type 'destroy' to confirm: " confirm2
    
    if [ "$confirm2" = "destroy" ]; then
        echo ""
        echo "🗑️  Destroying resources..."
        cd "$TERRAFORM_DIR"
        terraform destroy -auto-approve
        echo ""
        echo "✅ All resources destroyed"
    else
        echo "❌ Cancelled"
    fi
else
    echo "❌ Cancelled"
fi
