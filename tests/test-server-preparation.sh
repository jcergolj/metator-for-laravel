#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap_text="$(<"$ROOT_DIR/stubs/scripts/server-bootstrap.sh")"
prerequisites_text="$(<"$ROOT_DIR/stubs/scripts/steps/01-prerequisites.sh")"
common_text="$(<"$ROOT_DIR/stubs/scripts/lib/common.sh")"

[[ "$bootstrap_text" == *"PHP_VERSION='__PHP_VERSION__'"* ]]
[[ "$bootstrap_text" == *"SITE_ID='__SITE_ID__'"* ]]
[[ "$bootstrap_text" == *'require_commands ssh-keyscan'* ]]
[[ "$bootstrap_text" == *"CLIENT_PUBLIC_KEY=\"\${CLIENT_PUBLIC_KEY:-}\""* ]]
[[ "$bootstrap_text" == *'.client-public-key'* ]]
[[ "$bootstrap_text" == *"PHP_FPM_SERVICE=\"php\${PHP_VERSION}-fpm\""* ]]
[[ "$bootstrap_text" == *'METATOR_OPERATION" != prepare-server'* ]]
[[ "$bootstrap_text" == *"PHP_VERSION='8.4'"* ]]
[[ "$bootstrap_text" == *'php artisan metator:provision --config=__CONFIG_FILE__'* ]]
[[ "$bootstrap_text" != *'vendor/bin/dep deploy production'* ]]
[[ "$prerequisites_text" == *'prepare_shared_baseline'* ]]
[[ "$prerequisites_text" == *'requires Ubuntu 24.04 or 26.04'* ]]
[[ "$prerequisites_text" == *'VERSION_ID:-}" != 24.04'* ]]
[[ "$prerequisites_text" == *'VERSION_ID:-}" != 26.04'* ]]
[[ "$prerequisites_text" == *"php\${PHP_VERSION}-fpm"* ]]
[[ "$prerequisites_text" == *'software-properties-common caddy'* ]]
[[ "$prerequisites_text" == *'openssh-client'* ]]
[[ "$prerequisites_text" == *'curl jq unzip'* ]]
[[ "$prerequisites_text" == *'curl jq unzip'* ]]
[[ "$prerequisites_text" == *'mariadb-server'* ]]
[[ "$prerequisites_text" == *"php\${PHP_VERSION}-mysql"* ]]
[[ "$prerequisites_text" == *'redis-server'* ]]
[[ "$prerequisites_text" == *"php\${PHP_VERSION}-redis"* ]]
[[ "$prerequisites_text" == *'Redis is not active'* ]]
[[ "$prerequisites_text" == *'cron is active'* || "$prerequisites_text" == *'Cron is not active'* ]]
[[ "$prerequisites_text" == *'shared_packages+=(cron)'* ]]
[[ "$prerequisites_text" == *'add-apt-repository -y ppa:ondrej/php'* ]]
[[ "$prerequisites_text" == *'add-apt-repository is required'* ]]
[[ "$prerequisites_text" == *'Composer installation did not provide the composer command'* ]]
[[ "$prerequisites_text" == *'Caddy installation did not provide the caddy command'* ]]
[[ "$prerequisites_text" == *'systemctl enable --now caddy'* ]]
node_text="$(<"$ROOT_DIR/stubs/scripts/steps/11-node.sh")"
[[ "$node_text" == *'# @id: node'* ]]
[[ "$node_text" == *'# @default: false'* ]]
[[ "$node_text" == *'apt-get install -y nodejs npm'* ]]
[[ "$node_text" == *'require_commands node npm'* ]]
[[ "$common_text" == *"\"\$METATOR_OPERATION\" == prepare-server"* ]]
[[ "$common_text" == *'prerequisites|node)'* ]]

printf '%s\n' 'Server preparation checks passed.'
