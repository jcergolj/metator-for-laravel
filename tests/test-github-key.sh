#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_FILE="$(mktemp)"
trap 'rm -f "$COMMON_FILE"' EXIT
sed 's/__GIT_DEPLOYER_NAME__/git-origin/g' \
    "$SCRIPT_DIR/../stubs/scripts/lib/common.sh" > "$COMMON_FILE"
source "$COMMON_FILE"

DEPLOY_USER='deployer'
APP_NAME='billing-app'
GITHUB_REPOSITORY='acme/billing-app'

configure_github_identity

[[ "$GITHUB_KEY" == '/home/deployer/.ssh/git-origin' ]]
[[ "$GITHUB_ALIAS" == 'git-origin' ]]
[[ "$GITHUB_URL" == 'git@git-origin:acme/billing-app.git' ]]
[[ "$GITHUB_CONFIG_MARKER" == 'LARAVEL DEPLOYER GITHUB billing-app' ]]

first_key="$GITHUB_KEY"
first_alias="$GITHUB_ALIAS"
first_url="$GITHUB_URL"
first_marker="$GITHUB_CONFIG_MARKER"
APP_NAME='admin-app'
GITHUB_REPOSITORY='acme/admin-app'
configure_github_identity

[[ "$GITHUB_KEY" == "$first_key" ]]
[[ "$GITHUB_ALIAS" == "$first_alias" ]]
[[ "$GITHUB_URL" != "$first_url" ]]
[[ "$GITHUB_CONFIG_MARKER" != "$first_marker" ]]

echo 'GitHub identity configuration test passed.'
