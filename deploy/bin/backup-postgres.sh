#!/usr/bin/env bash
set -euo pipefail

APP_DIR=${APP_DIR:-/opt/receipts}
ENV_FILE=${ENV_FILE:-/etc/receipts/receipts.env}
COMPOSE_FILE=${COMPOSE_FILE:-"$APP_DIR/deploy/docker-compose.prod.yml"}
BACKUP_DIR=${BACKUP_DIR:-/var/backups/receipts}
RETENTION_DAYS=${RETENTION_DAYS:-14}

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

POSTGRES_DB=${POSTGRES_DB:-receipts_prod}
POSTGRES_USER=${POSTGRES_USER:-receipts}

mkdir -p "$BACKUP_DIR"

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_file="$BACKUP_DIR/${POSTGRES_DB}-${timestamp}.sql.gz"
tmp_file="${backup_file}.tmp"

cd "$APP_DIR"

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres \
  pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | gzip -9 > "$tmp_file"

mv "$tmp_file" "$backup_file"
find "$BACKUP_DIR" -type f -name "${POSTGRES_DB}-*.sql.gz" -mtime +"$RETENTION_DAYS" -delete

echo "$backup_file"
