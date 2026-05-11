DEPLOY_HOST ?= 10.0.10.40
DEPLOY_USER ?= sonnen
DEPLOY_APP_USER ?= receipts
DEPLOY_DIR ?= /opt/receipts
DEPLOY_URL ?= https://receipts.onnen.dev

.PHONY: help db.start db.stop db.setup db.reset dev deploy deploy.status deploy.version

help:
	@echo "Available commands:"
	@echo "  make db.start   - Start the Postgres container"
	@echo "  make db.stop    - Stop the Postgres container"
	@echo "  make db.setup   - Create and migrate the database"
	@echo "  make db.reset   - Drop, recreate, and migrate the database"
	@echo "  make dev        - Start Postgres and the Phoenix server"
	@echo "  make deploy     - Deploy on the home server over SSH"
	@echo "  make deploy.status  - Show production Docker Compose status"
	@echo "  make deploy.version - Fetch the production /version endpoint"

db.start:
	docker compose up -d postgres
	@echo "Waiting for Postgres to be ready..."
	@docker compose exec postgres sh -c 'until pg_isready -U postgres; do sleep 1; done'

db.stop:
	docker compose stop postgres

db.setup: db.start
	mix ecto.setup

db.reset: db.start
	mix ecto.reset

dev: db.start
	iex -S mix phx.server

deploy:
	ssh $(DEPLOY_USER)@$(DEPLOY_HOST) 'sudo -u $(DEPLOY_APP_USER) $(DEPLOY_DIR)/deploy/bin/deploy.sh'

deploy.status:
	ssh $(DEPLOY_USER)@$(DEPLOY_HOST) 'sudo -u $(DEPLOY_APP_USER) sh -lc "cd $(DEPLOY_DIR) && docker compose --env-file /etc/receipts/receipts.env -f deploy/docker-compose.prod.yml ps"'

deploy.version:
	curl -fsS $(DEPLOY_URL)/version
	@echo
