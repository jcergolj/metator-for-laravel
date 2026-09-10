#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# All applications modify the same SSH config, crontab, and Caddyfile.
# Keep the lock for the complete bootstrap, including interactive reviews.
if [[ "$EUID" -ne 0 ]]; then
    exec sudo bash "$SCRIPT_DIR/server-bootstrap.sh" "$@"
fi
exec 9>/var/lock/metator-bootstrap.lock
if ! flock -n 9; then
    printf 'Another application bootstrap is running on this server. Try again when it finishes.\n' >&2
    exit 1
fi

source "$SCRIPT_DIR/lib/common.sh"

GITHUB_REPOSITORY='__GITHUB_REPOSITORY__'
APP_FOLDER='__DEPLOY_PATH__'
DOMAIN='__DOMAIN__'
SERVER_IP='__SERVER_IP__'
CONFIGURE_DEPLOY_USER_LOGIN='__CONFIGURE_DEPLOY_USER_LOGIN__'
USE_CLOUDFLARE='__USE_CLOUDFLARE__'
USE_SCHEDULER='__USE_SCHEDULER__'
USE_QUEUE='__USE_QUEUE__'
USE_HORIZON='__USE_HORIZON__'
DATABASE_DRIVER='__DATABASE_DRIVER__'
ENV_EXAMPLE_FILE="$SCRIPT_DIR/.env.example"

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

require_safe_inputs

APP_NAME="$(basename "$APP_FOLDER")"
configure_github_identity
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
echo "  Cloudflare DNS:     $USE_CLOUDFLARE"
echo "  Database:           $DATABASE_DRIVER"
echo "  Scheduler:          $USE_SCHEDULER"
echo "  Queue workers:      $USE_QUEUE"
echo "  SSH login key:      $CONFIGURE_DEPLOY_USER_LOGIN"
echo

run_step 'Verify server prerequisites' \
    'Checks required commands, creates the deployment user when missing, and verifies the PHP-FPM socket.' \
    step_prerequisites

if [[ "${#STEP_FAILED[@]}" -gt 0 ]]; then
    print_step_summary
    exit 1
fi
claim_application_folder || exit 1

if [[ "$CONFIGURE_DEPLOY_USER_LOGIN" == true ]]; then
    run_step 'Configure deployer SSH login' \
        'Creates the deployer user when missing, installs your public key into authorized_keys, and fixes SSH permissions.' \
        step_deployer_login
else
    skip_step 'Configure deployer SSH login'
fi

if [[ "$USE_CLOUDFLARE" == true ]]; then
    run_step 'Configure Cloudflare DNS' \
        'Checks for the selected domain A record and creates it only when missing.' \
        step_cloudflare_dns
else
    skip_step 'Configure Cloudflare DNS'
fi

run_step 'Configure reusable GitHub SSH access' \
    'Creates an app-specific deployer SSH key when missing, configures its GitHub alias, and verifies repository access.' \
    step_github_key

if [[ "${STEP_FAILED[*]}" == *'Configure reusable GitHub SSH access'* ]]; then
    print_step_summary
    exit 1
fi

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

if [[ "$USE_SCHEDULER" == true ]]; then
    run_step 'Configure Laravel scheduler' \
        'Adds one scheduler entry using the current release symlink when selected.' \
        step_scheduler
else
    skip_step 'Configure Laravel scheduler'
fi

if [[ "$USE_QUEUE" == true ]]; then
    run_step 'Configure queue workers' \
        "Creates the Supervisor program at ${SUPERVISOR_FILE} for Horizon or queue:work when selected, then waits for your review confirmation." \
        step_workers
else
    skip_step 'Configure queue workers'
fi

step_deployer_instructions
print_step_summary

echo
ok 'Server setup finished'
echo 'The current symlink has not been created by this script.'
echo 'Perform the first deployment from your local project with:'
echo '  vendor/bin/dep deploy production'
