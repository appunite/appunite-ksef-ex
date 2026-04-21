.PHONY: help setup build test test.integration fmt lint dialyzer precommit \
       server console \
       docker.build docker.run docker.up docker.down \
       db.setup db.migrate db.reset db.rollback \
       deploy \
       models.upload models.restart models.train \
       landing.install landing.dev landing.build landing.preview landing.check

APP_NAME := ksef-hub
DOCKER_TAG := $(APP_NAME):latest
GCS_MODELS_BUCKET := gs://au-ksef-ex-ml-models
GCP_REGION := europe-west1
GCP_PROJECT_ID := au-ksef-ex
IMAGE_NAME := $(GCP_REGION)-docker.pkg.dev/$(GCP_PROJECT_ID)/ksef-hub/ksef-hub
CLASSIFIER_REPO := git@github.com:appunite/au-payroll-model-categories.git

# --- Help ---

help: ## Show this help
	@grep -E '^[a-zA-Z_.-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# --- Development ---

setup: ## Install deps, setup DB, build assets
	mix setup

build: ## Compile the project
	mix compile

server: ## Start Phoenix server
	mix phx.server

console: ## Start Phoenix server with IEx
	iex -S mix phx.server

# --- Quality ---

test: ## Run all tests (excludes @tag :integration)
	mix test

test.integration: ## Run integration tests (requires KSeF credentials)
	mix test --include integration

fmt: ## Format code
	mix format

fmt.check: ## Check code formatting
	mix format --check-formatted

lint: ## Run Credo static analysis
	mix credo --strict

dialyzer: ## Run Dialyzer type checking
	mix dialyzer

precommit: ## Run format + compile warnings + tests (test env)
	mix precommit

# --- Database ---

db.setup: ## Create DB, run migrations, seed
	mix ecto.setup

db.migrate: ## Run pending migrations
	mix ecto.migrate

db.rollback: ## Rollback last migration
	mix ecto.rollback

db.reset: ## Drop, create, migrate, seed
	mix ecto.reset

# --- Docker ---

docker.build: ## Build Docker image
	docker build -t $(DOCKER_TAG) .

docker.run: ## Run Docker container (requires DATABASE_URL, SECRET_KEY_BASE)
	docker run --rm -p 4000:4000 \
		-e DATABASE_URL \
		-e SECRET_KEY_BASE \
		$(DOCKER_TAG)

docker.up: ## Start all services with docker compose
	docker compose up -d

docker.down: ## Stop all services
	docker compose down

# --- Deploy ---

deploy: ## Deploy current service.yaml to Cloud Run (uses latest pushed image)
	@echo "Deploying cloud-run/service.yaml to Cloud Run ($(GCP_REGION))..."
	@echo "Image: $(IMAGE_NAME):latest"
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || (echo "Aborted." && exit 1)
	sed "s|IMAGE_PLACEHOLDER|$(IMAGE_NAME):latest|g" cloud-run/service.yaml | \
		gcloud run services replace - --region $(GCP_REGION) --project $(GCP_PROJECT_ID)

# --- ML Models ---

models.upload: ## Upload ML models from ml-models/ to GCS and restart classifier
	gsutil cp ml-models/invoice_classifier.joblib $(GCS_MODELS_BUCKET)/
	gsutil cp ml-models/invoice_tag_classifier.joblib $(GCS_MODELS_BUCKET)/
	@echo "Models uploaded. Run 'make models.restart' to pick up changes."

models.restart: ## Restart Cloud Run to pick up new models from GCS
	gcloud run services update ksef-hub --region $(GCP_REGION) --project $(GCP_PROJECT_ID) \
		--update-env-vars=MODELS_REV=$$(date +%s)
	@echo "Service restarting — new models will be loaded."

models.train: ## Show instructions for training new models
	@echo "To train new models:"
	@echo "  1. Clone the classifier repo:"
	@echo "     git clone $(CLASSIFIER_REPO) /tmp/au-payroll-model-categories"
	@echo "  2. Follow training instructions in that repo (make train)"
	@echo "  3. Copy trained models here:"
	@echo "     cp /tmp/au-payroll-model-categories/models/*.joblib ml-models/"
	@echo "  4. Upload to GCS and restart:"
	@echo "     make models.upload models.restart"
	@echo "  5. Commit updated models:"
	@echo "     git add ml-models/ && git commit -m 'chore: update ML models'"

# --- Landing ---
# Thin dispatchers for the standalone Astro project in ./landing.
# The landing is deliberately decoupled from Phoenix; these targets exist for
# discoverability only, they do not link the two builds.

landing.install: ## Install landing deps (clean install, lockfile-pinned)
	cd landing && npm ci

landing.dev: ## Start landing dev server (http://localhost:4321/appunite-ksef-ex/)
	cd landing && npm run dev

landing.build: ## Build landing to landing/dist/
	cd landing && npm run build

landing.preview: ## Serve the built landing locally
	cd landing && npm run preview

landing.check: ## Run landing quality gates (i18n parity + typecheck). Mirrors CI.
	cd landing && npm run test:i18n && npm run check

