#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/deploy.sh <canvas|prairielearn|both> [admin@server]

If admin@server is omitted, the script uses `tofu output -raw lms_public_ip`.
The target must be set up with scripts/install-docker-caddy.sh and have
passwordless sudo.
USAGE
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || { usage >&2; exit 2; }
services=$1
case "$services" in
  canvas|prairielearn|both) ;;
  *) usage >&2; exit 2 ;;
esac

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ $# -eq 2 ]]; then
  target=$2
else
  command -v tofu >/dev/null || die 'tofu is required when no SSH target is provided'
  ip=$(tofu -chdir="$repo_root" output -raw lms_public_ip) || die 'could not read lms_public_ip; pass admin@server explicitly'
  target="admin@$ip"
fi

command -v ssh >/dev/null || die 'ssh is required'
command -v python3 >/dev/null || die 'python3 is required'

ssh_args=(-o BatchMode=yes)
remote_root=/opt/uni-in-a-box

remote() { ssh "${ssh_args[@]}" "$target" "$@"; }
copy() { scp -q "${ssh_args[@]}" "$@"; }
install_site() {
  printf '%s {\n\treverse_proxy 127.0.0.1:%s\n}\n' "$2" "$3" \
    | remote "sudo tee /etc/caddy/sites/$1.caddy >/dev/null"
}

canvas_domain=
pl_domain=

if [[ $services == canvas || $services == both ]]; then
  canvas_dir="$repo_root/deployment/canvas"
  env_file="$canvas_dir/.env.canvas"
  [[ -f $env_file ]] || die "create $env_file from .env.canvas.example first"
  chmod 600 "$env_file"
  canvas_domain=$(python3 - "$env_file" <<'PY'
import sys

path = sys.argv[1]
values = {}
for line in open(path, encoding="utf-8"):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    if "=" not in line:
        raise SystemExit(f"invalid line in {path}: expected KEY=value")
    key, value = line.split("=", 1)
    values[key.strip()] = value.strip()

required = [
    "POSTGRES_PASSWORD", "CANVAS_LMS_ADMIN_EMAIL", "CANVAS_LMS_ADMIN_PASSWORD",
    "CANVAS_LMS_ACCOUNT_NAME", "ENCRYPTION_KEY", "JWT_ENCRYPTION_KEY", "CANVAS_DOMAIN",
]
missing = [key for key in required if not values.get(key)]
placeholders = [key for key in required if "replace-with" in values.get(key, "")]
if missing or placeholders:
    problems = []
    if missing:
        problems.append("missing values: " + ", ".join(missing))
    if placeholders:
        problems.append("replace template values for: " + ", ".join(placeholders))
    raise SystemExit("Canvas config is incomplete (" + "; ".join(problems) + ")")
if len(values["ENCRYPTION_KEY"]) < 20:
    raise SystemExit("ENCRYPTION_KEY must be at least 20 characters")
print(values["CANVAS_DOMAIN"])
PY
) || die 'Canvas configuration check failed'
  [[ $canvas_domain =~ ^[A-Za-z0-9.-]+$ ]] || die 'CANVAS_DOMAIN must be a DNS hostname'
fi

if [[ $services == prairielearn || $services == both ]]; then
  pl_dir="$repo_root/deployment/prairielearn"
  config_file="$pl_dir/config.json"
  [[ -f $config_file ]] || die "create $config_file from config.example.json first"
  chmod 600 "$config_file"
  pl_domain=$(python3 - "$config_file" <<'PY'
import json
import sys
from urllib.parse import urlparse

path = sys.argv[1]
try:
    config = json.load(open(path, encoding="utf-8"))
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"cannot read {path}: {error}")

required = ["serverCanonicalHost", "secretKey", "databaseEncryptionKey", "googleClientId", "googleClientSecret", "googleRedirectUrl"]
missing = [key for key in required if not config.get(key)]
wrong_type = [key for key in required if config.get(key) and not isinstance(config[key], str)]
placeholders = [key for key in required if isinstance(config.get(key), str) and "replace-with" in config[key]]
if missing or wrong_type or placeholders:
    problems = []
    if missing:
        problems.append("missing values: " + ", ".join(missing))
    if wrong_type:
        problems.append("values must be strings: " + ", ".join(wrong_type))
    if placeholders:
        problems.append("replace template values for: " + ", ".join(placeholders))
    raise SystemExit("PrairieLearn config is incomplete (" + "; ".join(problems) + ")")
for key in ("secretKey", "databaseEncryptionKey"):
    value = config[key]
    if len(value) != 64 or any(char not in "0123456789abcdefABCDEF" for char in value):
        raise SystemExit(f"{key} must be 64 hexadecimal characters")
if config["secretKey"] == config["databaseEncryptionKey"]:
    raise SystemExit("secretKey and databaseEncryptionKey must be different")

host = urlparse(config["serverCanonicalHost"]).hostname
if urlparse(config["serverCanonicalHost"]).scheme != "https" or not host:
    raise SystemExit("serverCanonicalHost must be an https URL")
if config["googleRedirectUrl"] != f"https://{host}/pl/oauth2callback":
    raise SystemExit("googleRedirectUrl must be https://<serverCanonicalHost>/pl/oauth2callback")
print(host)
PY
) || die 'PrairieLearn configuration check failed'
  [[ $pl_domain =~ ^[A-Za-z0-9.-]+$ ]] || die 'PrairieLearn hostname must be a DNS hostname'
fi

printf 'Checking SSH access to %s...\n' "$target"
remote 'sudo -n true && docker compose version >/dev/null && grep -qs "import /etc/caddy/sites/" /etc/caddy/Caddyfile' \
  || die 'SSH check failed, or the server needs passwordless sudo and a run of scripts/install-docker-caddy.sh'

remote "sudo mkdir -p '$remote_root/deployment' && sudo chown -R \$(id -u):\$(id -g) '$remote_root'"

if [[ $services == canvas || $services == both ]]; then
  printf 'Copying Canvas deployment files...\n'
  canvas_remote="$remote_root/deployment/canvas"
  remote "mkdir -p '$canvas_remote'"
  copy "$repo_root/deployment/canvas/compose.yml" "$repo_root/deployment/canvas/.env.canvas" "$target:$canvas_remote/"
  copy -r "$repo_root/deployment/canvas/config" "$target:$canvas_remote/"
  remote "chmod 600 '$canvas_remote/.env.canvas'"
  install_site canvas "$canvas_domain" 3000
fi

if [[ $services == prairielearn || $services == both ]]; then
  printf 'Copying PrairieLearn deployment files...\n'
  pl_remote="$remote_root/deployment/prairielearn"
  remote "mkdir -p '$pl_remote/courses'"
  copy "$repo_root/deployment/prairielearn/compose.yml" "$repo_root/deployment/prairielearn/config.json" "$target:$pl_remote/"
  remote "chmod 600 '$pl_remote/config.json'"
  install_site prairielearn "$pl_domain" 3001
fi

printf 'Reloading Caddy...\n'
remote 'sudo caddy validate --config /etc/caddy/Caddyfile && sudo systemctl reload caddy'

remote "set -eu
if [ '$services' = canvas ] || [ '$services' = both ]; then
  cd '$remote_root/deployment/canvas'
  docker compose --env-file .env.canvas pull
  docker compose --env-file .env.canvas up -d postgres redis
  ready=
  for attempt in \$(seq 1 60); do
    if docker compose --env-file .env.canvas exec -T postgres pg_isready -U postgres -d canvas_production >/dev/null 2>&1; then ready=1; break; fi
    sleep 2
  done
  [ -n \"\${ready:-}\" ] || { echo 'Canvas PostgreSQL did not become ready' >&2; exit 1; }
  has_account_users=\$(docker compose --env-file .env.canvas exec -T postgres psql -U postgres -d canvas_production -tAc \"SELECT to_regclass('public.account_users') IS NOT NULL AND to_regclass('public.accounts') IS NOT NULL\")
  initialized=false
  if [ \"\$has_account_users\" = t ]; then
    initialized=\$(docker compose --env-file .env.canvas exec -T postgres psql -U postgres -d canvas_production -tAc \"SELECT count(DISTINCT au.account_id) >= 2 FROM account_users au JOIN accounts a ON a.id = au.account_id WHERE a.parent_account_id IS NULL\")
  fi
  if [ \"\$initialized\" != t ]; then
    echo 'Initializing Canvas database and first administrator (first deployment)...'
    docker compose --env-file .env.canvas --profile init run --rm init
  else
    echo 'Canvas database is already initialized; skipping one-time setup.'
  fi
  docker compose --env-file .env.canvas up -d web jobs
fi
if [ '$services' = prairielearn ] || [ '$services' = both ]; then
  cd '$remote_root/deployment/prairielearn'
  docker compose pull
  docker compose up -d
fi
"

printf 'Deployment complete. Caddy routes:\n'
[[ -n $canvas_domain ]] && printf '  Canvas:       https://%s\n' "$canvas_domain"
[[ -n $pl_domain ]] && printf '  PrairieLearn: https://%s\n' "$pl_domain"
