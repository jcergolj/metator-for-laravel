#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../stubs/scripts/lib/common.sh"

DEPLOY_USER='deployer'
APP_NAME='billing-app'
GITHUB_REPOSITORY='acme/billing-app'

configure_github_identity

[[ "$GITHUB_KEY" == '/home/deployer/.ssh/deployer-github-billing-app' ]]
[[ "$GITHUB_ALIAS" == 'github-deployer-billing-app' ]]
[[ "$GITHUB_URL" == 'git@github-deployer-billing-app:acme/billing-app.git' ]]
[[ "$GITHUB_CONFIG_MARKER" == 'LARAVEL DEPLOYER GITHUB billing-app' ]]

first_key="$GITHUB_KEY"
first_alias="$GITHUB_ALIAS"
first_marker="$GITHUB_CONFIG_MARKER"
APP_NAME='admin-app'
GITHUB_REPOSITORY='acme/admin-app'
configure_github_identity

[[ "$GITHUB_KEY" != "$first_key" ]]
[[ "$GITHUB_ALIAS" != "$first_alias" ]]
[[ "$GITHUB_CONFIG_MARKER" != "$first_marker" ]]

echo 'GitHub identity configuration test passed.'
