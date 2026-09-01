#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/common.sh"

for step_file in "$SCRIPT_DIR"/steps/*.sh; do
    source "$step_file"
done

PHP_VERSION="$(systemctl list-unit-files --type=service --no-legend 2>/dev/null |
    sed -nE 's/^(php([0-9]+\.[0-9]+)-fpm)\.service.*/\2/p' | sort -V | tail -n 1)"
if [[ -z "$PHP_VERSION" ]]; then
    die 'No PHP-FPM service was found'
    exit 1
fi
PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
PHP_FPM_SOCKET="/run/php/${PHP_FPM_SERVICE}.sock"
PHP_PACKAGE_PREFIX="php${PHP_VERSION}"

prompt_value 'GitHub repository (owner/repository)' GITHUB_REPOSITORY
DEFAULT_APP_NAME="${GITHUB_REPOSITORY##*/}"
prompt_value 'Application folder' APP_FOLDER "/var/www/${DEFAULT_APP_NAME}"
prompt_value 'Domain' DOMAIN
require_safe_inputs
detect_server_ip

APP_NAME="$(basename "$APP_FOLDER")"
GITHUB_ALIAS='github-deployer'
GITHUB_URL="git@${GITHUB_ALIAS}:${GITHUB_REPOSITORY}.git"
CADDY_SITE="/etc/caddy/sites-enabled/${APP_NAME}.caddy"
SUPERVISOR_FILE="/etc/supervisor/conf.d/${APP_NAME}-worker.conf"

echo
echo 'Configuration summary'
echo "  GitHub repository: $GITHUB_REPOSITORY"
echo "  Application folder: $APP_FOLDER"
echo "  Application name:   $APP_NAME"
echo "  Domain:             $DOMAIN"
echo "  Server public IP:   $SERVER_IP"
echo "  PHP version:        $PHP_VERSION"
echo "  PHP-FPM socket:     $PHP_FPM_SOCKET"
echo "  Shared .env file:   $APP_FOLDER/shared/.env"
echo "  Caddy site file:    $CADDY_SITE"
echo "  Supervisor file:    $SUPERVISOR_FILE"
echo '  Cloudflare DNS:     decide in step'
echo '  Database:           choose in step'
echo '  Scheduler:          decide in step'
echo '  Queue workers:      decide in step'
echo '  SSH login key:      decide in step'
echo
read -r -p 'Press Enter to begin or q to quit: ' initial_answer
[[ "$initial_answer" != q && "$initial_answer" != Q ]] || exit 0

run_step 'Verify server prerequisites' \
    'Checks required commands, creates the deployment user when missing, and verifies the PHP-FPM socket.' \
    step_prerequisites

run_step 'Configure deployer SSH login' \
    'Creates the deployer user when missing, installs your public key into authorized_keys, and fixes SSH permissions.' \
    step_deployer_login

run_step 'Configure Cloudflare DNS' \
    'Checks for the selected domain A record and creates it only when missing.' \
    step_cloudflare_dns

run_step 'Configure reusable GitHub SSH access' \
    'Creates the deployer SSH key when missing, configures the GitHub alias, and verifies repository access.' \
    step_github_key

run_step 'Create the shared Laravel environment file' \
    'Creates the persistent .env, writes the selected database settings, then waits for your review confirmation.' \
    step_app_folder

run_step 'Prepare the selected database' \
    'Installs the required PHP database driver and prepares the persistent SQLite file when selected.' \
    step_database

run_step 'Verify shared-file permissions' \
    'Sets deployer ownership and www-data group access on persistent Laravel files.' \
    step_permissions

run_step 'Configure Caddy' \
    "Creates and validates the Caddy site configuration at ${CADDY_SITE}, then waits for your review confirmation." \
    step_caddy

run_step 'Configure Laravel scheduler' \
    'Adds one scheduler entry using the current release symlink when selected.' \
    step_scheduler

run_step 'Configure queue workers' \
    "Creates the Supervisor program at ${SUPERVISOR_FILE} for Horizon or queue:work when selected, then waits for your review confirmation." \
    step_workers

step_deployer_instructions
print_step_summary

echo
ok 'Server setup finished'
echo 'The current symlink has not been created by this script.'
echo 'Perform the first deployment from your local project with:'
echo '  vendor/bin/dep deploy production'
