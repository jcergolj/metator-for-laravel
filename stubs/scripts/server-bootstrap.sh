#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2034
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
echo "  Supervisor file:    $SUPERVISOR_FILE"
echo "  Database:           $DATABASE_DRIVER"
echo

validate_step_metadata || exit 1
for step_file in "$SCRIPT_DIR"/steps/*.sh; do
    [[ -f "$step_file" ]] || continue
    source "$step_file"
done
validate_step_functions || exit 1

claim_application_folder || exit 1
bootstrap_status=0
run_selected_steps || bootstrap_status=$?
print_step_summary

if [[ "$bootstrap_status" -ne 0 ]]; then
    exit "$bootstrap_status"
fi

echo
ok 'Server setup finished'
echo 'The current symlink has not been created by this script.'
echo 'Perform the first deployment from your local project with:'
echo '  vendor/bin/dep deploy production'
