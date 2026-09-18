#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

APP_FOLDER="$TEST_DIR/site"
SITE_ID=site-123
DEPLOY_USER=deployer
sudo() {
    if [[ "$1" == install ]]; then
        local source target
        source="${*: -2:1}"
        target="${*: -1}"
        command cp "$source" "$target"
        return
    fi
    command "$@"
}
export -f sudo
mkdir -p "$APP_FOLDER/shared"
printf '%s\n' 'site_id=site-123' > "$APP_FOLDER/.metator-site"
printf '%s\n' 'APP_ENV="production"' 'APP_DEBUG="false"' > "$APP_FOLDER/shared/.env"

run_update() {
    local input="$1"
    printf '%s\n' "$input" > "$ROOT_DIR/stubs/scripts/.env-input"
    APP_FOLDER="$APP_FOLDER" SITE_ID="$SITE_ID" DEPLOY_USER="$DEPLOY_USER" \
        bash "$ROOT_DIR/stubs/scripts/environment-update.sh"
}

before_inode="$(stat -c '%i' "$APP_FOLDER/shared/.env")"
run_update $'APP_DEBUG=false\n'
[[ "$(stat -c '%i' "$APP_FOLDER/shared/.env")" == "$before_inode" ]]
[[ "$(<"$APP_FOLDER/shared/.env")" == *'APP_DEBUG="false"'* ]]

run_update $'APP_DEBUG=true\n'
[[ "$(<"$APP_FOLDER/shared/.env")" == *'APP_DEBUG="true"'* ]]

if run_update $'APP_KEY=forbidden\n'; then
    exit 1
fi

printf '%s\n' 'Environment update checks passed.'
