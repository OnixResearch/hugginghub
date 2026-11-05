#!/bin/sh
# Copy upstream Hugging Face repos onto this hub without rewriting commits.
# Usage:
#   HH_TOKEN=... HF_ENDPOINT=http://127.0.0.1:8080 \
#     deploy/seed-from-upstream.sh owner/model [owner/model ...]
#
# HH_TOKEN is the mirror token from `create-user`, not a huggingface.co token.
# The clone talks to huggingface.co with your normal git credentials (or none,
# for a public repo). The mirror token is not sent upstream.
set -eu

usage() {
    echo "usage: HH_TOKEN=... HF_ENDPOINT=http://127.0.0.1:8080 $0 owner/model [owner/model ...]" >&2
    exit 2
}

[ $# -ge 1 ] || usage
: "${HF_ENDPOINT:?set HF_ENDPOINT to the mirror, for example http://127.0.0.1:8080}"
: "${HH_TOKEN:?set HH_TOKEN to the token printed by create-user}"
HF_USER=${HF_USER:-admin}
ENDPOINT=${HF_ENDPOINT%/}

command -v git >/dev/null 2>&1 || {
    echo "git is required on the machine that seeds (not inside the hub container)" >&2
    exit 1
}
command -v git-lfs >/dev/null 2>&1 || {
    echo "git-lfs is required on the machine that seeds" >&2
    exit 1
}
command -v curl >/dev/null 2>&1 || {
    echo "curl is required" >&2
    exit 1
}

ASKPASS=$(mktemp)
work=
cleanup() {
    rm -f "$ASKPASS"
    if [ -n "$work" ]; then
        rm -rf "$work"
    fi
}
trap cleanup EXIT

cat >"$ASKPASS" <<'EOF'
#!/bin/sh
case "$1" in
    *sername*) printf '%s\n' "$HF_USER" ;;
    *) printf '%s\n' "$HH_TOKEN" ;;
esac
EOF
chmod 700 "$ASKPASS"

for repo in "$@"; do
    case "$repo" in
        */*/*|*/*.*/*|*[!A-Za-z0-9._/-]*)
            echo "refusing repo id: $repo" >&2
            exit 1
            ;;
        */*) ;;
        *)
            echo "repo id must look like owner/name: $repo" >&2
            exit 1
            ;;
    esac

    echo "creating $repo on $ENDPOINT"
    body=$(mktemp)
    code=$(curl -sS -o "$body" -w '%{http_code}' -X POST "$ENDPOINT/api/repos/create" \
        -H "Authorization: Bearer $HH_TOKEN" \
        -H 'Content-Type: application/json' \
        -d "{\"name\":\"$repo\",\"type\":\"model\"}") || code=000
    cat "$body"
    echo
    rm -f "$body"
    case "$code" in
        200 | 201 | 409) ;;
        *)
            echo "create failed for $repo (HTTP $code)." >&2
            echo "If the namespace does not exist, log in at $ENDPOINT and create an organization with that exact name at /organizations/new, then retry." >&2
            exit 1
            ;;
    esac

    work=$(mktemp -d)
    echo "cloning https://huggingface.co/$repo"
    env -u HF_TOKEN -u HH_TOKEN git clone --mirror "https://huggingface.co/$repo" "$work/src.git"
    (
        cd "$work/src.git"
        env -u HF_TOKEN -u HH_TOKEN git lfs fetch --all
        git remote add hub "$ENDPOINT/$repo"
        export HF_USER HH_TOKEN
        export GIT_ASKPASS="$ASKPASS"
        export GIT_TERMINAL_PROMPT=0
        # Git objects first, so commit SHAs land even if LFS upload is resumed later.
        GIT_LFS_SKIP_PUSH=1 git -c credential.helper= push --mirror hub
        git -c credential.helper= lfs push --all hub
    )
    rm -rf "$work"
    work=
    echo "seeded $repo"
done
