#!/bin/sh
# OPTIONAL FALLBACK. Not the Spark path. NixOS hosts enable services.hugginghub.
# Start HuggingHub as the login user, without sudo, on a host that is not
# using the NixOS module. The first run builds the image. Pass --build to rebuild.
set -eu

if [ "$(id -u)" -eq 0 ]; then
    echo "run deploy/up.sh as the login user, not with sudo" >&2
    exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required, and the login user must be able to run it without sudo" >&2
    exit 1
fi

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

export HH_UID=$(id -u)
export HH_GID=$(id -g)
export HH_PORT=${HH_PORT:-8080}
export HH_PUBLISH_ADDR=${HH_PUBLISH_ADDR:-0.0.0.0}
export HH_OPEN_SIGNUP=${HH_OPEN_SIGNUP:-0}
if [ -z "${HH_DATA_DIR:-}" ]; then
    HH_DATA_DIR=$HOME/.local/share/hugginghub
    export HH_DATA_DIR
fi

mkdir -p "$HH_DATA_DIR"
exec docker compose -f "$ROOT/deploy/docker-compose.yml" up -d "$@"
