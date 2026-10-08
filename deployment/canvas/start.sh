#!/bin/sh
# Starts Canvas, running the one-time database setup on first deployment.
set -eu
cd "$(dirname "$0")"

dc() { docker compose --env-file .env.canvas "$@"; }

dc pull
dc up -d --wait postgres redis

# Setup is complete once both root accounts have an administrator.
initialized=$(dc exec -T postgres psql -U postgres -d canvas_production -tAc \
  "SELECT count(DISTINCT au.account_id) >= 2 FROM account_users au JOIN accounts a ON a.id = au.account_id WHERE a.parent_account_id IS NULL" \
  2>/dev/null || true)
if [ "$initialized" = t ]; then
  echo 'Canvas is already initialized; skipping one-time setup.'
else
  echo 'Initializing Canvas database and first administrator...'
  dc --profile init run --rm init
fi

dc up -d web jobs
