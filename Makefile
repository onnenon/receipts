.PHONY: help db.start db.stop db.setup db.reset dev

help:
	@echo "Available commands:"
	@echo "  make db.start   - Start the Postgres container"
	@echo "  make db.stop    - Stop the Postgres container"
	@echo "  make db.setup   - Create and migrate the database"
	@echo "  make db.reset   - Drop, recreate, and migrate the database"
	@echo "  make dev        - Start Postgres and the Phoenix server"

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
