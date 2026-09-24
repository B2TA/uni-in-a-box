#!/bin/sh
set -eu

docker_user=${1:?usage: install-docker-caddy.sh USER}
if ! id "$docker_user" >/dev/null 2>&1; then
  echo "user does not exist: $docker_user" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  debian-archive-keyring \
  debian-keyring \
  gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
  -o /run/caddy-stable.gpg
gpg --dearmor --yes \
  -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg \
  /run/caddy-stable.gpg
curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt \
  -o /etc/apt/sources.list.d/caddy-stable.list
chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
chmod o+r /etc/apt/sources.list.d/caddy-stable.list

apt-get update
apt-get install -y \
  caddy \
  containerd.io \
  docker-buildx-plugin \
  docker-ce \
  docker-ce-cli \
  docker-compose-plugin

systemctl enable --now docker
systemctl enable --now caddy
usermod -aG docker "$docker_user"
