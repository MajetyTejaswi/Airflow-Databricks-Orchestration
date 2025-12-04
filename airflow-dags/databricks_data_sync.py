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
    'databricks_data_sync',
    default_args=default_args,
    description='Data sync pipeline that triggers Databricks job',
    schedule_interval='@hourly',
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['databricks', 'sync', 'data'],
) as dag:

    # Task: Trigger existing Databricks job using DatabricksRunNowOperator
    run_sync_job = DatabricksRunNowOperator(
        task_id='run_data_sync_job',
        databricks_conn_id='databricks_default',
        job_id='{{ var.value.databricks_sync_job_id }}',  # Set this variable in Airflow UI
        notebook_params={
            'date': '{{ ds }}',
            'run_id': '{{ run_id }}',
            'sync_type': 'incremental'
        },
    )

    # Task: Log sync completion
    def log_sync_status(**context):
        print(f"Data sync job completed for date: {context['ds']}")
        print("Sync completed successfully!")
        return True

    log_task = PythonOperator(
        task_id='log_sync_status',
        python_callable=log_sync_status,
    )

    # Define task dependencies
    run_sync_job >> log_task
