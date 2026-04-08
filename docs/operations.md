# Operations Guide

## Running release tasks on production

This app runs on GCP Cloud Run. Mix is not available in releases, so operational tasks use `KsefHub.Release` functions executed via Cloud Run Jobs.

### How it works

CI already creates a `ksef-hub-migrate` job for database migrations. You can reuse it (or create a new job) to run any `KsefHub.Release` function:

```bash
# Update the job to use the latest deployed image, then execute
gcloud run jobs execute ksef-hub-migrate \
  --region europe-west1 \
  --wait \
  --args 'eval,KsefHub.Release.reparse_ksef_invoices(dry_run: true)'
```

The `--args` flag passes arguments to `bin/ksef_hub`. The format is `eval,<elixir_expression>` (comma-separated, no spaces).

### Prerequisites

1. **Code must be deployed first.** The Cloud Run Job image must contain the function you want to call. Push to `main` and wait for CI to complete.
2. **gcloud CLI** must be authenticated: `gcloud auth login`
3. **Correct project**: `gcloud config set project au-ksef-ex`

## Available release tasks

### Migrate database

```bash
gcloud run jobs execute ksef-hub-migrate \
  --region europe-west1 \
  --wait \
  --args 'eval,KsefHub.Release.migrate()'
```

### Re-parse KSeF invoices from stored XML

Re-runs the FA(3) XML parser on all KSeF invoices that have stored XML files. Useful after parser improvements (new field extraction, bug fixes) to backfill existing invoices without a full KSeF re-sync.

**Always dry-run first:**

```bash
gcloud run jobs execute ksef-hub-migrate \
  --region europe-west1 \
  --wait \
  --args 'eval,KsefHub.Release.reparse_ksef_invoices(dry_run: true)'
```

**Run for real (updates the database):**

```bash
gcloud run jobs execute ksef-hub-migrate \
  --region europe-west1 \
  --wait \
  --args 'eval,KsefHub.Release.reparse_ksef_invoices()'
```

**Scope to a specific company:**

```bash
gcloud run jobs execute ksef-hub-migrate \
  --region europe-west1 \
  --wait \
  --args 'eval,KsefHub.Release.reparse_ksef_invoices(company_id: "bb524c06-b171-4ab0-8b23-9af2443d543f")'
```

**Scope to a single invoice:**

```bash
gcloud run jobs execute ksef-hub-migrate \
  --region europe-west1 \
  --wait \
  --args 'eval,KsefHub.Release.reparse_ksef_invoices(invoice_id: "68cbbea5-b22d-4627-b64c-84857d48706d")'
```

### Local development (mix tasks)

In local dev, you can also use the mix task which has the same functionality:

```bash
mix reparse_ksef_invoices --dry-run
mix reparse_ksef_invoices
mix reparse_ksef_invoices --company-id bb524c06-...
mix reparse_ksef_invoices --invoice-id 68cbbea5-...
```

### Viewing job logs

After executing a job, check the output:

```bash
gcloud run jobs executions list --job ksef-hub-migrate --region europe-west1
gcloud logging read "resource.type=cloud_run_job AND resource.labels.job_name=ksef-hub-migrate" --limit 50 --format "value(textPayload)"
```

Or view in the GCP Console: https://console.cloud.google.com/run/jobs?project=au-ksef-ex
