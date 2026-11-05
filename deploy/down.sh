#!/bin/sh
# OPTIONAL FALLBACK. Stop the compose container. NixOS uses systemctl stop hugginghub.
set -eu

if [ "$(id -u)" -eq 0 ]; then
    echo "run deploy/down.sh as the login user, not with sudo" >&2
    exit 1
fi

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
export HH_UID=$(id -u)
export HH_GID=$(id -g)
export HH_DATA_DIR=${HH_DATA_DIR:-$HOME/.local/share/hugginghub}
export HH_PORT=${HH_PORT:-8080}
export HH_PUBLISH_ADDR=${HH_PUBLISH_ADDR:-0.0.0.0}
exec docker compose -f "$ROOT/deploy/docker-compose.yml" stop
