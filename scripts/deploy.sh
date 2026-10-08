#!/usr/bin/env bash
set -euo pipefail

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
deploy_canvas=false
deploy_pl=false
[[ $services == prairielearn ]] || deploy_canvas=true
[[ $services == canvas ]] || deploy_pl=true

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ $# -eq 2 ]]; then
  target=$2
else
  ip=$(tofu -chdir="$repo_root" output -raw lms_public_ip) || die 'could not read lms_public_ip; pass admin@server explicitly'
  target="admin@$ip"
fi

remote_root=/opt/uni-in-a-box
canvas_dir="$repo_root/deployment/canvas"
pl_dir="$repo_root/deployment/prairielearn"

remote() { ssh -o BatchMode=yes "$target" "$@"; }
copy() { scp -q -o BatchMode=yes "$@"; }
install_site() {
  printf '%s {\n\treverse_proxy 127.0.0.1:%s\n}\n' "$2" "$3" \
    | remote "sudo tee /etc/caddy/sites/$1.caddy >/dev/null"
}
check_config() {
  [[ -f $1 ]] || die "create $1 from its example file first"
  ! grep -q replace-with "$1" || die "replace the placeholder values in $1"
}

if $deploy_canvas; then
  env_file="$canvas_dir/.env.canvas"
  check_config "$env_file"
  env_value() { sed -n "s/^$1=//p" "$env_file"; }
  canvas_domain=$(env_value CANVAS_DOMAIN)
  [[ -n $canvas_domain ]] || die "set CANVAS_DOMAIN in $env_file"
  encryption_key=$(env_value ENCRYPTION_KEY)
  (( ${#encryption_key} >= 20 )) || die 'ENCRYPTION_KEY must be at least 20 characters'
fi

if $deploy_pl; then
  config_file="$pl_dir/config.json"
  check_config "$config_file"
  json_value() { sed -n "s/.*\"$1\": *\"\([^\"]*\)\".*/\1/p" "$config_file"; }
  for key in secretKey databaseEncryptionKey; do
    [[ $(json_value "$key") =~ ^[0-9a-fA-F]{64}$ ]] || die "$key must be 64 hexadecimal characters"
  done
  pl_domain=$(json_value serverCanonicalHost)
  pl_domain=${pl_domain#https://}
  pl_domain=${pl_domain%%/*}
  [[ -n $pl_domain ]] || die "set serverCanonicalHost in $config_file"
fi

printf 'Checking %s...\n' "$target"
remote 'grep -qs "import /etc/caddy/sites/" /etc/caddy/Caddyfile' \
  || die 'cannot reach the server, or scripts/install-docker-caddy.sh has not been run on it'
remote "sudo mkdir -p $remote_root/deployment/canvas $remote_root/deployment/prairielearn/courses && sudo chown -R \$(id -u):\$(id -g) $remote_root"

if $deploy_canvas; then
  printf 'Copying Canvas files...\n'
  copy -r "$canvas_dir/compose.yml" "$canvas_dir/start.sh" "$canvas_dir/.env.canvas" "$canvas_dir/config" "$target:$remote_root/deployment/canvas/"
  remote "chmod 600 $remote_root/deployment/canvas/.env.canvas"
  install_site canvas "$canvas_domain" 3000
fi

if $deploy_pl; then
  printf 'Copying PrairieLearn files...\n'
  copy "$pl_dir/compose.yml" "$pl_dir/config.json" "$target:$remote_root/deployment/prairielearn/"
  remote "chmod 600 $remote_root/deployment/prairielearn/config.json"
  install_site prairielearn "$pl_domain" 3001
fi

printf 'Reloading Caddy...\n'
remote 'sudo systemctl reload caddy'

if $deploy_canvas; then
  remote "$remote_root/deployment/canvas/start.sh"
fi
if $deploy_pl; then
  printf 'Pulling PrairieLearn image (the first pull takes a few minutes)...\n'
  remote "cd $remote_root/deployment/prairielearn && docker compose pull --quiet && docker compose up -d"
fi

printf 'Deployment complete:\n'
if $deploy_canvas; then printf '  Canvas:       https://%s\n' "$canvas_domain"; fi
if $deploy_pl; then printf '  PrairieLearn: https://%s\n' "$pl_domain"; fi
