#!/usr/bin/env bash
set -euo pipefail

APP_DIR=${APP_DIR:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"}
ENV_FILE=${ENV_FILE:-/etc/receipts/receipts.env}
COMPOSE_FILE=${COMPOSE_FILE:-"$APP_DIR/deploy/docker-compose.prod.yml"}

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  echo "Create it from deploy/receipts.env.example and fill in secrets." >&2
  exit 1
fi

cd "$APP_DIR"

if [[ -z "${RECEIPTS_VERSION:-}" ]]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    RECEIPTS_VERSION=$(git rev-parse --short=12 HEAD)

    if ! git diff --quiet --ignore-submodules HEAD --; then
      RECEIPTS_VERSION="${RECEIPTS_VERSION}-dirty"
    fi
  elif [[ -f .deploy-version ]]; then
    RECEIPTS_VERSION=$(tr -d '[:space:]' < .deploy-version)
  else
    RECEIPTS_VERSION=unknown
  fi
fi

RECEIPTS_BUILT_AT=${RECEIPTS_BUILT_AT:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}

export RECEIPTS_BUILT_AT
export RECEIPTS_VERSION

echo "Deploying receipts version: $RECEIPTS_VERSION"
echo "Build timestamp: $RECEIPTS_BUILT_AT"

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" build web migrate
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d postgres
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" run --rm migrate
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" up -d web cloudflared
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps
