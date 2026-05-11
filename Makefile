DEPLOY_HOST ?= 10.0.10.40
DEPLOY_USER ?= sonnen
DEPLOY_APP_USER ?= receipts
DEPLOY_DIR ?= /opt/receipts
DEPLOY_URL ?= https://receipts.onnen.dev

.PHONY: help db.start db.stop db.setup db.reset dev deploy deploy.remote deploy.status deploy.version

help:
	@echo "Available commands:"
	@echo "  make db.start   - Start the Postgres container"
	@echo "  make db.stop    - Stop the Postgres container"
	@echo "  make db.setup   - Create and migrate the database"
	@echo "  make db.reset   - Drop, recreate, and migrate the database"
	@echo "  make dev        - Start Postgres and the Phoenix server"
	@echo "  make deploy     - Sync local checkout and deploy on the home server"
	@echo "  make deploy.remote - Redeploy the checkout already on the home server"
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
	@version=$$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown); \
	if test -n "$$(git status --porcelain --untracked-files=normal 2>/dev/null)"; then \
		version="$${version}-dirty"; \
	fi; \
	echo "Syncing receipts version: $${version}"; \
	COPYFILE_DISABLE=1 tar \
		--exclude='./_build' \
		--exclude='./deps' \
		--exclude='./assets/node_modules' \
		--exclude='./.elixir_ls' \
		--exclude='./tmp' \
		--exclude='./.git' \
		--exclude='./.env' \
		--exclude='./.env.*' \
		-czf - . | \
	ssh $(DEPLOY_USER)@$(DEPLOY_HOST) "set -eu; \
		rm -rf /tmp/receipts-deploy; \
		mkdir -p /tmp/receipts-deploy; \
		tar -xzf - -C /tmp/receipts-deploy; \
		printf '%s\n' '$${version}' > /tmp/receipts-deploy/.deploy-version; \
		sudo mkdir -p $(DEPLOY_DIR); \
		sudo find $(DEPLOY_DIR) -mindepth 1 -maxdepth 1 -exec rm -rf {} +; \
		sudo cp -a /tmp/receipts-deploy/. $(DEPLOY_DIR)/; \
		sudo chown -R $(DEPLOY_APP_USER):$(DEPLOY_APP_USER) $(DEPLOY_DIR); \
		sudo chmod +x $(DEPLOY_DIR)/deploy/bin/*.sh"
	$(MAKE) deploy.remote

deploy.remote:
	ssh $(DEPLOY_USER)@$(DEPLOY_HOST) 'sudo -u $(DEPLOY_APP_USER) $(DEPLOY_DIR)/deploy/bin/deploy.sh'

deploy.status:
	ssh $(DEPLOY_USER)@$(DEPLOY_HOST) 'sudo -u $(DEPLOY_APP_USER) sh -lc "cd $(DEPLOY_DIR) && docker compose --env-file /etc/receipts/receipts.env -f deploy/docker-compose.prod.yml ps"'

deploy.version:
	curl -fsS $(DEPLOY_URL)/version
	@echo
