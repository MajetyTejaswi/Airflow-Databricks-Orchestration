.PHONY: help init plan apply destroy validate fmt connect logs status

help:
	@echo "Airflow-Databricks Pipeline Management"
	@echo "====================================="
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  init             - Initialize Terraform"
	@echo "  validate         - Validate Terraform configuration"
	@echo "  fmt              - Format Terraform files"
	@echo "  plan             - Plan infrastructure changes"
	@echo "  apply            - Apply infrastructure changes"
	@echo "  destroy          - Destroy all infrastructure (DANGEROUS!)"
	@echo "  status           - Show infrastructure status"
	@echo "  outputs          - Show Terraform outputs"
	@echo "  connect          - SSH into EC2 instance"
	@echo "  logs             - Tail Airflow logs on EC2"
	@echo "  restart-airflow  - Restart Airflow services"
	@echo "  setup            - Run quick setup script"
	@echo ""

init:
	@echo "Initializing Terraform..."
	@cd terraform && terraform init

validate:
	@echo "Validating Terraform configuration..."
	@cd terraform && terraform validate

fmt:
	@echo "Formatting Terraform files..."
	@cd terraform && terraform fmt -recursive

plan:
	@echo "Planning infrastructure changes..."
	@cd terraform && terraform plan -out=tfplan

apply:
	@echo "Applying infrastructure changes..."
	@cd terraform && terraform apply tfplan
	@rm -f tfplan

destroy:
	@echo "⚠️  WARNING: This will destroy all infrastructure!"
	@read -p "Continue? [y/N] " confirm; \
	if [ "$$confirm" = "y" ]; then \
		cd terraform && terraform destroy; \
	else \
		echo "Aborted"; \
	fi

status:
	@cd terraform && terraform show -no-color

outputs:
	@cd terraform && terraform output

EC2_IP := $(shell cd terraform && terraform output -raw ec2_public_ip 2>/dev/null)
SSH_KEY := ~/.ssh/airflow-key

connect:
	@if [ -z "$(EC2_IP)" ]; then \
		echo "Error: EC2 IP not found. Make sure infrastructure is deployed."; \
		exit 1; \
	fi
	@ssh -i $(SSH_KEY) ubuntu@$(EC2_IP)

logs:
	@if [ -z "$(EC2_IP)" ]; then \
		echo "Error: EC2 IP not found. Make sure infrastructure is deployed."; \
		exit 1; \
	fi
	@ssh -i $(SSH_KEY) ubuntu@$(EC2_IP) "tail -f /home/airflow/airflow/logs/*/latest/*.log"

restart-airflow:
	@if [ -z "$(EC2_IP)" ]; then \
		echo "Error: EC2 IP not found. Make sure infrastructure is deployed."; \
		exit 1; \
	fi
	@ssh -i $(SSH_KEY) ubuntu@$(EC2_IP) "sudo systemctl restart airflow-webserver && sudo systemctl restart airflow-scheduler"
	@echo "✅ Airflow services restarted"

setup:
	@bash scripts/setup.sh

clean:
	@echo "Cleaning up temporary files..."
	@cd terraform && rm -f tfplan *.tfstate.backup
	@find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete
	@echo "✅ Clean complete"
