#!/usr/bin/env python3
"""
Validation script to check Terraform and configuration files
Run this before deployment to catch any issues
"""

import os
import json
import sys
import subprocess
from pathlib import Path

class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    END = '\033[0m'

def print_status(message, status="info"):
    """Print colored status messages"""
    if status == "success":
        print(f"{Colors.GREEN}✓{Colors.END} {message}")
    elif status == "error":
        print(f"{Colors.RED}✗{Colors.END} {message}")
    elif status == "warning":
        print(f"{Colors.YELLOW}⚠{Colors.END} {message}")
    elif status == "info":
        print(f"{Colors.BLUE}ℹ{Colors.END} {message}")

def check_prerequisites():
    """Check if required tools are installed"""
    print(f"\n{Colors.BLUE}Checking Prerequisites...{Colors.END}\n")
    
    tools = {
        'terraform': 'terraform --version',
        'aws': 'aws --version',
        'git': 'git --version',
        'ssh': 'ssh -V'
    }
    
    all_ok = True
    for tool, cmd in tools.items():
        result = subprocess.run(cmd, shell=True, capture_output=True)
        if result.returncode == 0:
            print_status(f"{tool} is installed", "success")
        else:
            print_status(f"{tool} is NOT installed", "error")
            all_ok = False
    
    return all_ok

def check_ssh_key():
    """Check if SSH key exists"""
    print(f"\n{Colors.BLUE}Checking SSH Key...{Colors.END}\n")
    
    ssh_key = os.path.expanduser('~/.ssh/airflow-key')
    ssh_pub = os.path.expanduser('~/.ssh/airflow-key.pub')
    
    if os.path.exists(ssh_key) and os.path.exists(ssh_pub):
        print_status("SSH key pair found", "success")
        return True
    else:
        print_status("SSH key pair NOT found at ~/.ssh/airflow-key", "warning")
        print_status("Run: ssh-keygen -t rsa -b 4096 -f ~/.ssh/airflow-key -N ''", "info")
        return False

def check_terraform_config():
    """Check Terraform configuration"""
    print(f"\n{Colors.BLUE}Checking Terraform Configuration...{Colors.END}\n")
    
    terraform_dir = Path('terraform')
    
    # Check if terraform directory exists
    if not terraform_dir.exists():
        print_status("terraform/ directory not found", "error")
        return False
    
    # Check main files
    required_files = ['main.tf', 'variables.tf', 'terraform.tfvars']
    all_ok = True
    
    for file in required_files:
        file_path = terraform_dir / file
        if file_path.exists():
            print_status(f"Found {file}", "success")
        else:
            print_status(f"Missing {file}", "error")
            all_ok = False
    
    # Check terraform.tfvars for required variables
    if (terraform_dir / 'terraform.tfvars').exists():
        with open(terraform_dir / 'terraform.tfvars', 'r') as f:
            content = f.read()
            required_vars = ['databricks_host', 'databricks_token', 'public_key_path']
            for var in required_vars:
                if var in content and 'your-' not in content and 'example' not in content:
                    print_status(f"Variable {var} is configured", "success")
                else:
                    print_status(f"Variable {var} needs to be configured", "warning")
    
    return all_ok

def check_scripts():
    """Check if scripts exist"""
    print(f"\n{Colors.BLUE}Checking Scripts...{Colors.END}\n")
    
    scripts_dir = Path('scripts')
    required_scripts = ['bootstrap.sh', 'setup.sh', 'post-deploy.sh']
    
    all_ok = True
    for script in required_scripts:
        script_path = scripts_dir / script
        if script_path.exists():
            print_status(f"Found {script}", "success")
        else:
            print_status(f"Missing {script}", "error")
            all_ok = False
    
    return all_ok

def check_dags():
    """Check if DAGs exist"""
    print(f"\n{Colors.BLUE}Checking DAGs...{Colors.END}\n")
    
    dags_dir = Path('airflow-dags')
    
    if dags_dir.exists():
        dag_files = list(dags_dir.glob('*.py'))
        if dag_files:
            print_status(f"Found {len(dag_files)} DAG file(s)", "success")
            for dag_file in dag_files:
                print_status(f"  - {dag_file.name}", "info")
            return True
        else:
            print_status("No DAG files found in airflow-dags/", "warning")
            return False
    else:
        print_status("airflow-dags/ directory not found", "error")
        return False

def validate_terraform():
    """Validate Terraform files"""
    print(f"\n{Colors.BLUE}Validating Terraform...{Colors.END}\n")
    
    result = subprocess.run(
        'cd terraform && terraform validate',
        shell=True,
        capture_output=True,
        text=True
    )
    
    if result.returncode == 0:
        print_status("Terraform validation passed", "success")
        return True
    else:
        print_status("Terraform validation failed", "error")
        print(result.stderr)
        return False

def main():
    """Run all checks"""
    print(f"\n{Colors.BLUE}{'='*50}")
    print("Airflow-Databricks Pipeline Validation")
    print(f"{'='*50}{Colors.END}\n")
    
    checks = [
        ("Prerequisites", check_prerequisites()),
        ("SSH Key", check_ssh_key()),
        ("Terraform Config", check_terraform_config()),
        ("Scripts", check_scripts()),
        ("DAGs", check_dags()),
        ("Terraform Validation", validate_terraform()),
    ]
    
    # Summary
    print(f"\n{Colors.BLUE}Summary{Colors.END}\n")
    
    passed = sum(1 for _, result in checks if result)
    total = len(checks)
    
    for name, result in checks:
        status = "success" if result else "warning"
        symbol = "✓" if result else "✗"
        print(f"{Colors.GREEN if result else Colors.YELLOW}{symbol}{Colors.END} {name}")
    
    print(f"\n{Colors.BLUE}Passed: {passed}/{total}{Colors.END}\n")
    
    if passed == total:
        print_status("All checks passed! Ready to deploy.", "success")
        print(f"\n{Colors.GREEN}Next steps:{Colors.END}")
        print("1. Review terraform/terraform.tfvars")
        print("2. Run: cd terraform && terraform plan")
        print("3. Review the plan output")
        print("4. Run: terraform apply")
        return 0
    else:
        print_status("Some checks failed. Please fix the issues above.", "warning")
        return 1

if __name__ == '__main__':
    sys.exit(main())
