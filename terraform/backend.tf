terraform {
  backend "s3" {
    bucket         = "airflow-terraform-state"
    key            = "airflow/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "airflow-terraform-locks"
  }
}

# Data source for account ID
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

