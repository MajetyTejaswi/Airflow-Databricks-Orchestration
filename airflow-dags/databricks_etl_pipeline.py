from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.databricks.operators.databricks import DatabricksSubmitRunOperator
from airflow.operators.python import PythonOperator
from airflow.utils.decorators import apply_defaults

# Default arguments for all DAGs
default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'email': ['admin@example.com'],
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
    'start_date': datetime(2024, 1, 1),
}

# Define the DAG
dag = DAG(
    'databricks_etl_pipeline',
    default_args=default_args,
    description='ETL pipeline that runs on Databricks',
    schedule_interval='@daily',
    catchup=False,
    tags=['databricks', 'etl'],
)

# Define Databricks job configuration
notebook_task = {
    'notebook_path': '/Users/your-email@company.com/sample_notebook',
    'base_parameters': {
        'date': '{{ ds }}'
    }
}

# Task: Run Databricks notebook
run_databricks_job = DatabricksSubmitRunOperator(
    task_id='run_etl_notebook',
    databricks_conn_id='databricks_default',
    existing_cluster_id='{{ var.value.databricks_cluster_id }}',
    notebook_task=notebook_task,
    dag=dag,
)

# Task: Validate data
def validate_data():
    print("Validating data from Databricks job")
    return True

validate_task = PythonOperator(
    task_id='validate_data',
    python_callable=validate_data,
    dag=dag,
)

# Define task dependencies
run_databricks_job >> validate_task
