# Databricks notebook source
# Sample ETL Notebook for Airflow-Databricks Orchestration

print("=" * 50)
print("Databricks ETL Pipeline - Sample Notebook")
print("=" * 50)

print("\nStep 1: Starting ETL Process...")
print("Hello from Databricks! This notebook is triggered by Airflow.")

print("\nStep 2: Sample Data Processing...")
sample_data = ["Item A", "Item B", "Item C"]
for i, item in enumerate(sample_data, 1):
    print(f"  Processing {i}: {item}")

print("\nStep 3: ETL Complete!")
print("Total items processed:", len(sample_data))
print("\n" + "=" * 50)
print("Notebook execution successful!")
print("=" * 50)
