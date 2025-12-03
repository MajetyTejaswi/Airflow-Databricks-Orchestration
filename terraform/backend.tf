terraform {
  backend "s3" {
    bucket         = "airflow-terraform-state"
    key            = "airflow/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "airflow-terraform-locks"
  }
}
