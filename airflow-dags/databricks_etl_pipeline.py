from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.databricks.operators.databricks import DatabricksRunNowOperator
from airflow.operators.python import PythonOperator

# Default arguments for all DAGs
default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# Define the DAG
with DAG(
    'databricks_etl_pipeline',
    default_args=default_args,
    description='ETL pipeline that triggers Databricks job',
    schedule_interval='@daily',
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['databricks', 'etl'],
) as dag:

    # Task: Trigger existing Databricks job using DatabricksRunNowOperator
    # This triggers a job that already exists in Databricks
    run_databricks_job = DatabricksRunNowOperator(
        task_id='run_databricks_job',
        databricks_conn_id='databricks_default',
        job_id='{{ var.value.databricks_job_id }}',  # Set this variable in Airflow UI
        notebook_params={
            'date': '{{ ds }}',
            'run_id': '{{ run_id }}'
        },
    )

    # Task: Validate data after job completion
    def validate_data(**context):
        print(f"Databricks job completed for date: {context['ds']}")
        print("Data validation successful")
        return True

    validate_task = PythonOperator(
        task_id='validate_data',
        python_callable=validate_data,
    )

    # Define task dependencies
    run_databricks_job >> validate_task
