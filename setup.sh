#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/common.sh"

for step_file in "$SCRIPT_DIR"/steps/*.sh; do
    source "$step_file"
done

PHP_FPM_SERVICE="$(systemctl list-units --type=service --state=running --no-legend 2>/dev/null |
    sed -nE 's/^[[:space:]]*(php[0-9.]+-fpm)\.service.*/\1/p' | head -n 1)"
[[ -n "$PHP_FPM_SERVICE" ]] || die 'No running PHP-FPM service found'
PHP_FPM_SOCKET="/run/php/${PHP_FPM_SERVICE}.sock"

prompt_value 'GitHub repository (owner/repository)' GITHUB_REPOSITORY
DEFAULT_APP_NAME="${GITHUB_REPOSITORY##*/}"
prompt_value 'Application folder' APP_FOLDER "/var/www/${DEFAULT_APP_NAME}"
prompt_value 'Domain' DOMAIN
require_safe_inputs
detect_server_ip
prompt_cloudflare
prompt_database

APP_NAME="$(basename "$APP_FOLDER")"
GITHUB_ALIAS='github-deployer'
GITHUB_URL="git@${GITHUB_ALIAS}:${GITHUB_REPOSITORY}.git"
CADDY_SITE="/etc/caddy/sites-enabled/${APP_NAME}.caddy"
SUPERVISOR_FILE="/etc/supervisor/conf.d/${APP_NAME}-worker.conf"
USE_SCHEDULER=false
USE_QUEUE=false
USE_HORIZON=false
ask_yes_no 'Does this application use the Laravel scheduler?' y && USE_SCHEDULER=true
ask_yes_no 'Does this application run queued jobs on this server?' n && USE_QUEUE=true
if [[ "$USE_QUEUE" == true ]]; then
    ask_yes_no 'Should queued jobs be managed by Horizon?' n && USE_HORIZON=true
fi

echo
echo 'Configuration summary'
echo "  GitHub repository: $GITHUB_REPOSITORY"
echo "  Application folder: $APP_FOLDER"
echo "  Application name:   $APP_NAME"
echo "  Domain:             $DOMAIN"
echo "  Server public IP:   $SERVER_IP"
echo "  PHP-FPM socket:     $PHP_FPM_SOCKET"
echo "  Cloudflare DNS:     $USE_CLOUDFLARE"
echo "  Database:           $DATABASE_DRIVER"
if [[ "$DATABASE_DRIVER" == mysql ]]; then
    echo "  MySQL host:         $MYSQL_HOST"
    echo "  MySQL database:     $MYSQL_DATABASE"
    echo "  MySQL username:     $MYSQL_USERNAME"
fi
echo "  Scheduler:          $USE_SCHEDULER"
echo "  Queue workers:      $USE_QUEUE"
echo "  Horizon:            $USE_HORIZON"
echo
read -r -p 'Press Enter to begin or q to quit: ' initial_answer
[[ "$initial_answer" != q && "$initial_answer" != Q ]] || exit 0

run_step 'Verify server prerequisites' \
    'Checks the deployment user, required commands and PHP-FPM socket.' \
    step_prerequisites

run_step 'Configure Cloudflare DNS' \
    'Checks for the selected domain A record and creates it only when missing.' \
    step_cloudflare_dns

run_step 'Configure reusable GitHub SSH access' \
    'Configures the deployer GitHub SSH key and verifies repository access.' \
    step_github_key

run_step 'Create the shared Laravel environment file' \
    'Creates the persistent .env, opens it for editing, then writes the selected database settings.' \
    step_app_folder

run_step 'Prepare the selected database' \
    'Installs the required PHP database driver and prepares the persistent SQLite file when selected.' \
    step_database

run_step 'Verify shared-file permissions' \
    'Sets deployer ownership and www-data group access on persistent Laravel files.' \
    step_permissions

run_step 'Configure Caddy' \
    'Creates and validates the Caddy site configuration.' \
    step_caddy

if [[ "$USE_SCHEDULER" == true ]]; then
    run_step 'Configure Laravel scheduler' \
        'Adds one scheduler entry using the current release symlink.' \
        step_scheduler
else
    ok 'Laravel scheduler was not selected; cron was not changed'
fi

run_step 'Configure queue workers' \
    'Creates a Supervisor program for Horizon or queue:work when selected.' \
    step_workers

step_deployer_instructions

echo
ok 'Server setup finished'
echo 'The current symlink has not been created by this script.'
echo 'Perform the first deployment from your local project with:'
echo '  vendor/bin/dep deploy production'
