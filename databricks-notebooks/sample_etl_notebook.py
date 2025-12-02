# Databricks notebook source

# COMMAND ----------

# Sample ETL Pipeline in Databricks
# This notebook demonstrates a simple data processing pipeline

# COMMAND ----------

from datetime import datetime
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, when, sum as spark_sum

# COMMAND ----------

# Get parameters passed from Airflow
import sys

execution_date = sys.argv[1] if len(sys.argv) > 1 else "2024-01-01"

print(f"Running ETL pipeline for date: {execution_date}")

# COMMAND ----------

# Create sample data or read from source
data = [
    ("product_a", 100, "2024-01-01"),
    ("product_b", 200, "2024-01-01"),
    ("product_c", 150, "2024-01-01"),
    ("product_a", 120, "2024-01-02"),
    ("product_b", 180, "2024-01-02"),
]

columns = ["product_name", "sales_amount", "date"]
df = spark.createDataFrame(data, schema=columns)

# COMMAND ----------

# Transform data
df_transformed = df.filter(col("sales_amount") > 0) \
    .groupBy("product_name") \
    .agg(
        spark_sum("sales_amount").alias("total_sales"),
        col("date")
    ) \
    .orderBy("total_sales", ascending=False)

# COMMAND ----------

# Display results
display(df_transformed)

# COMMAND ----------

# Save results to Delta Lake
output_path = f"/mnt/airflow-data/etl-output/date={execution_date}"
df_transformed.coalesce(1).write.mode("overwrite").parquet(output_path)

print(f"Data saved to {output_path}")

# COMMAND ----------

# Log completion
print("ETL pipeline completed successfully!")
