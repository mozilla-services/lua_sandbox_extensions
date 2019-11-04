from google.cloud import bigquery
from google.cloud import storage


CONFIG = {
    'bucket_name': 'mozilla-mach-data',
    'project': 'moz-fx-data-taskclu-prod-8fbf',
    'dataset_id': 'taskclusteretl',
    'tables': {
        'task_duration_estimates': 'task_duration_history.json',
        'calculated_machtry_quantiles': 'machtry_quantiles.csv',
    }
}


def export_all_files(request, payload):
    for table, blob_name in CONFIG['tables'].items():
        if blob_name.endswith('.csv'):
            export_format = bigquery.job.DestinationFormat().CSV
        else:
            export_format = bigquery.job.DestinationFormat().NEWLINE_DELIMITED_JSON
        export_table(table, blob_name, export_format)


def export_table(table, blob_name, export_format):
    storage_client = storage.Client()
    client = bigquery.Client()

    temporary_blob_name = blob_name + ".temp"
    destination_uri = "gs://{}/{}".format(CONFIG['bucket_name'], temporary_blob_name)
    dataset_ref = client.dataset(CONFIG['dataset_id'], project=CONFIG['project'])
    table_ref = dataset_ref.table(table)
    job_config = bigquery.job.ExtractJobConfig(
        destination_format=export_format
    )

    extract_job = client.extract_table(
        table_ref,
        destination_uri,
        # Location must match that of the source table.
        location="US",
        job_config=job_config,
    )  # API request
    extract_job.result()  # Waits for job to complete.

    bucket = storage_client.get_bucket(CONFIG['bucket_name'])
    blob = bucket.blob(temporary_blob_name)
    bucket.rename_blob(blob, blob_name)

    blob = bucket.blob(blob_name)
    blob.make_public()
