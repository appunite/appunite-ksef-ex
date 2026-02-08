#!/usr/bin/env bash
#
# One-time GCP infrastructure provisioning for KSeF Hub.
#
# Prerequisites:
#   - gcloud CLI authenticated with project-owner permissions
#   - Target project already created
#
# Usage:
#   scripts/setup-gcp.sh
#
set -euo pipefail

PROJECT_ID="au-ksef-ex"
REGION="europe-central2"
REPO_NAME="ksef-hub"
GITHUB_ORG="appunite"
GITHUB_REPO="appunite-ksef-ex"
RUNNER_SA="ksef-hub-runner"
DEPLOY_SA="github-actions-deploy"
WIF_POOL="github-pool"
WIF_PROVIDER="github-provider"

echo "==> Setting project to ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}"

# --- Enable APIs ---
echo "==> Enabling required APIs..."
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com

# --- Artifact Registry ---
echo "==> Creating Artifact Registry repository..."
gcloud artifacts repositories create "${REPO_NAME}" \
  --repository-format=docker \
  --location="${REGION}" \
  --description="KSeF Hub Docker images" \
  --quiet || echo "    (repository may already exist)"

# --- Service Accounts ---
echo "==> Creating Cloud Run runtime service account..."
gcloud iam service-accounts create "${RUNNER_SA}" \
  --display-name="KSeF Hub Cloud Run runtime" \
  --quiet || echo "    (service account may already exist)"

RUNNER_SA_EMAIL="${RUNNER_SA}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "==> Granting Secret Manager access to runtime SA..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${RUNNER_SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" \
  --quiet

echo "==> Creating GitHub Actions deploy service account..."
gcloud iam service-accounts create "${DEPLOY_SA}" \
  --display-name="GitHub Actions deploy for KSeF Hub" \
  --quiet || echo "    (service account may already exist)"

DEPLOY_SA_EMAIL="${DEPLOY_SA}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "==> Granting deploy roles to GitHub Actions SA..."
for role in roles/run.developer roles/artifactregistry.writer roles/iam.serviceAccountUser; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${DEPLOY_SA_EMAIL}" \
    --role="${role}" \
    --quiet
done

# --- Workload Identity Federation ---
echo "==> Creating Workload Identity Pool..."
gcloud iam workload-identity-pools create "${WIF_POOL}" \
  --location="global" \
  --display-name="GitHub Actions Pool" \
  --quiet || echo "    (pool may already exist)"

echo "==> Creating Workload Identity Provider (GitHub OIDC)..."
gcloud iam workload-identity-pools providers create-oidc "${WIF_PROVIDER}" \
  --location="global" \
  --workload-identity-pool="${WIF_POOL}" \
  --display-name="GitHub OIDC Provider" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository_owner == '${GITHUB_ORG}'" \
  --quiet || echo "    (provider may already exist)"

PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
WIF_POOL_ID="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL}"

echo "==> Binding Workload Identity to deploy service account..."
gcloud iam service-accounts add-iam-policy-binding "${DEPLOY_SA_EMAIL}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${WIF_POOL_ID}/attribute.repository_owner/${GITHUB_ORG}" \
  --quiet

# --- Secret Manager secrets ---
echo "==> Creating Secret Manager secrets (empty — populate manually)..."
SECRETS=(
  "database-url"
  "secret-key-base"
  "google-client-id"
  "google-client-secret"
  "allowed-emails"
  "ksef-encryption-key"
)

for secret in "${SECRETS[@]}"; do
  gcloud secrets create "${secret}" \
    --replication-policy="user-managed" \
    --locations="${REGION}" \
    --quiet 2>/dev/null || echo "    ${secret} already exists"
done

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Populate secrets:"
echo "     gcloud secrets versions add database-url --data-file=-"
echo "     gcloud secrets versions add secret-key-base --data-file=-"
echo "     ... (repeat for each secret)"
echo ""
echo "  2. Add GitHub repository secrets (Settings > Secrets > Actions):"
echo "     GCP_PROJECT_ID          = ${PROJECT_ID}"
echo "     GCP_REGION              = ${REGION}"
echo "     GCP_WIF_PROVIDER        = ${WIF_POOL_ID}/providers/${WIF_PROVIDER}"
echo "     GCP_SERVICE_ACCOUNT     = ${DEPLOY_SA_EMAIL}"
echo ""
echo "  3. Push to main to trigger the deploy workflow."
