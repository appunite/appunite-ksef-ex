.PHONY: help setup build test test.integration fmt lint dialyzer precommit \
       server console \
       docker.build docker.run docker.up docker.down \
       db.setup db.migrate db.reset db.rollback

APP_NAME := ksef-hub
DOCKER_TAG := $(APP_NAME):latest

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
