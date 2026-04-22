# Scripts

Utility scripts for GCP infrastructure and operations.

## `setup-gcp.sh`

One-time GCP infrastructure provisioning (APIs, service accounts, Artifact Registry, Workload Identity Federation). Requires project-owner permissions.

```bash
scripts/setup-gcp.sh
```

## `cloudrun-metrics.py`

Queries Google Cloud Monitoring API and prints a resource utilization report for the `ksef-hub` Cloud Run service — memory per container, CPU utilization, instance count, billable time, and estimated monthly cost.

**Prerequisites:** `gcloud` CLI authenticated with access to the `au-ksef-ex` project.

```bash
# Last 7 days (default)
python3 scripts/cloudrun-metrics.py

# Last 1 day
python3 scripts/cloudrun-metrics.py 1

# Last 30 days
python3 scripts/cloudrun-metrics.py 30

# Append a row to scripts/metrics-log.csv for trend tracking
python3 scripts/cloudrun-metrics.py 7 --csv

# Raw JSON output
python3 scripts/cloudrun-metrics.py 7 --json
```

The `--csv` flag creates/appends to `scripts/metrics-log.csv`. Run it daily over a week or two to collect utilization trends before resizing containers.
