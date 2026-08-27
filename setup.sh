#!/usr/bin/env bash
set -Eeuo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DEPLOY_USER="deployer"
GITHUB_KEY="/home/${DEPLOY_USER}/.ssh/deployer-github"
CADDY_CERT="/etc/caddy/certs/cloudflare-wildcard.crt"
CADDY_KEY="/etc/caddy/certs/cloudflare-wildcard.key"

step_number=0

die() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

prompt_value() {
    local prompt="$1" variable="$2" default="${3:-}" value
    if [[ -n "$default" ]]; then
        read -r -p "$prompt [$default]: " value
        value="${value:-$default}"
    else
        read -r -p "$prompt: " value
    fi
    [[ -n "$value" ]] || die "$prompt is required"
    printf -v "$variable" '%s' "$value"
}

prompt_secret() {
    local prompt="$1" variable="$2" value
    read -r -s -p "$prompt: " value
    echo
    [[ -n "$value" ]] || die "$prompt is required"
    printf -v "$variable" '%s' "$value"
}

ask_yes_no() {
    local prompt="$1" default="${2:-n}" answer suffix
    if [[ "$default" =~ ^[Yy]$ ]]; then
        suffix='Y/n'
    else
        suffix='y/N'
    fi
    read -r -p "$prompt [$suffix]: " answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy]$ ]]
}

run_step() {
    local title="$1" description="$2" function_name="$3" answer
    step_number=$((step_number + 1))
    echo
    echo -e "${GREEN}STEP ${step_number} — ${title}${NC}"
    echo "$description"
    echo
    while true; do
        read -r -p '[c] Continue  [s] Skip  [q] Quit: ' answer
        case "$answer" in
            c|C|'') "$function_name"; return ;;
            s|S) warn "Skipped: $title"; return ;;
            q|Q) echo 'Stopped.'; exit 0 ;;
            *) echo 'Please enter c, s, or q.' ;;
        esac
    done
}

require_safe_inputs() {
    [[ "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
        die 'GitHub repository must look like owner/repository'
    [[ "$APP_FOLDER" =~ ^/var/www/[A-Za-z0-9_.-]+$ ]] ||
        die 'Application folder must be a simple path under /var/www'
    [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || die 'Invalid domain'
}

set_env_value() {
    local key="$1" value="$2" escaped
    escaped="${value//\\/\\\\}"
    escaped="${escaped//&/\\&}"
    escaped="${escaped//|/\\|}"
    escaped="${escaped//\"/\\\"}"

    if sudo grep -qE "^${key}=" "$APP_FOLDER/shared/.env"; then
        sudo sed -i "s|^${key}=.*|${key}=\"${escaped}\"|" "$APP_FOLDER/shared/.env"
    else
        printf '%s\n' "${key}=\"${escaped}\"" |
            sudo tee -a "$APP_FOLDER/shared/.env" >/dev/null
    fi
}

configure_database_env() {
    if [[ "$DATABASE_DRIVER" == sqlite ]]; then
        set_env_value DB_CONNECTION sqlite
        set_env_value DB_DATABASE "$APP_FOLDER/shared/database/database.sqlite"
        set_env_value DB_HOST ''
        set_env_value DB_PORT ''
        set_env_value DB_USERNAME ''
        set_env_value DB_PASSWORD ''
        return
    fi

    set_env_value DB_CONNECTION mysql
    set_env_value DB_HOST "$MYSQL_HOST"
    set_env_value DB_PORT "$MYSQL_PORT"
    set_env_value DB_DATABASE "$MYSQL_DATABASE"
    set_env_value DB_USERNAME "$MYSQL_USERNAME"
    set_env_value DB_PASSWORD "$MYSQL_PASSWORD"
}

prompt_database() {
    local choice
    echo
    echo 'Database driver:'
    echo '  1) SQLite (recommended default)'
    echo '  2) MySQL'
    read -r -p 'Choose database [1]: ' choice
    choice="${choice:-1}"

    case "$choice" in
        1)
            DATABASE_DRIVER='sqlite'
            ;;
        2)
            DATABASE_DRIVER='mysql'
            prompt_value 'MySQL host' MYSQL_HOST '127.0.0.1'
            prompt_value 'MySQL port' MYSQL_PORT '3306'
            prompt_value 'MySQL database' MYSQL_DATABASE
            prompt_value 'MySQL username' MYSQL_USERNAME
            prompt_secret 'MySQL password' MYSQL_PASSWORD
            ;;
        *)
            die 'Invalid database selection'
            ;;
    esac
}

PHP_FPM_SERVICE="$(systemctl list-units --type=service --state=running --no-legend 2>/dev/null |
    sed -nE 's/^[[:space:]]*(php[0-9.]+-fpm)\.service.*/\1/p' | head -n 1)"
[[ -n "$PHP_FPM_SERVICE" ]] || die 'No running PHP-FPM service found'
PHP_FPM_SOCKET="/run/php/${PHP_FPM_SERVICE}.sock"

prompt_value 'GitHub repository (owner/repository)' GITHUB_REPOSITORY
DEFAULT_APP_NAME="${GITHUB_REPOSITORY##*/}"
prompt_value 'Application folder' APP_FOLDER "/var/www/${DEFAULT_APP_NAME}"
prompt_value 'Domain' DOMAIN
require_safe_inputs
prompt_database

APP_NAME="$(basename "$APP_FOLDER")"
GITHUB_ALIAS='github-deployer'
GITHUB_URL="git@${GITHUB_ALIAS}:${GITHUB_REPOSITORY}.git"
CADDY_SITE="/etc/caddy/sites-enabled/${APP_NAME}.caddy"
SUPERVISOR_FILE="/etc/supervisor/conf.d/${APP_NAME}-horizon.conf"
USE_HORIZON=false
ask_yes_no 'Does this application use Horizon?' n && USE_HORIZON=true

echo
echo 'Configuration summary'
echo "  GitHub repository: $GITHUB_REPOSITORY"
echo "  Application folder: $APP_FOLDER"
echo "  Application name:   $APP_NAME"
echo "  Domain:             $DOMAIN"
echo "  PHP-FPM socket:     $PHP_FPM_SOCKET"
echo "  Database:           $DATABASE_DRIVER"
if [[ "$DATABASE_DRIVER" == mysql ]]; then
    echo "  MySQL host:         $MYSQL_HOST"
    echo "  MySQL database:     $MYSQL_DATABASE"
    echo "  MySQL username:     $MYSQL_USERNAME"
fi
echo "  Horizon:            $USE_HORIZON"
echo
read -r -p 'Press Enter to begin or q to quit: ' initial_answer
[[ "$initial_answer" != q && "$initial_answer" != Q ]] || exit 0

step_prerequisites() {
    id "$DEPLOY_USER" >/dev/null 2>&1 || die "User $DEPLOY_USER does not exist"
    for command in php composer caddy git systemctl sudo sed grep; do
        command -v "$command" >/dev/null 2>&1 || die "$command is not installed"
    done
    getent group www-data | grep -qE "(^|,)${DEPLOY_USER}(,|$)" ||
        sudo usermod -aG www-data "$DEPLOY_USER"
    [[ -S "$PHP_FPM_SOCKET" ]] || die "PHP-FPM socket does not exist: $PHP_FPM_SOCKET"
    ok 'Deployment user and required software are ready'
}

run_step 'Verify server prerequisites' \
    'Checks the deployment user, required commands and PHP-FPM socket.' \
    step_prerequisites

step_github_key() {
    sudo install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/${DEPLOY_USER}/.ssh"
    if [[ ! -f "$GITHUB_KEY" ]]; then
        sudo -u "$DEPLOY_USER" ssh-keygen -t ed25519 -f "$GITHUB_KEY" \
            -C 'shared production deployer key' -N ''
        warn 'Add this key to GitHub before continuing:'
        sudo -u "$DEPLOY_USER" cat "${GITHUB_KEY}.pub"
        read -r -p 'Press Enter after adding the key to GitHub: '
    fi

    local ssh_config="/home/${DEPLOY_USER}/.ssh/config"
    local temporary
    temporary="$(mktemp)"
    if [[ -f "$ssh_config" ]]; then
        sudo sed '/^# BEGIN LARAVEL DEPLOYER GITHUB$/,/^# END LARAVEL DEPLOYER GITHUB$/d' \
            "$ssh_config" > "$temporary"
    fi
    cat >> "$temporary" <<EOF
# BEGIN LARAVEL DEPLOYER GITHUB
Host ${GITHUB_ALIAS}
    HostName github.com
    User git
    IdentityFile ${GITHUB_KEY}
    IdentitiesOnly yes
# END LARAVEL DEPLOYER GITHUB
EOF
    sudo install -m 600 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$temporary" "$ssh_config"
    rm -f "$temporary"
    sudo chown -R "$DEPLOY_USER:$DEPLOY_USER" "/home/${DEPLOY_USER}/.ssh"

    sudo -u "$DEPLOY_USER" git ls-remote "$GITHUB_URL" HEAD >/dev/null ||
        die 'GitHub access failed'
    ok "Reusable GitHub key can read $GITHUB_REPOSITORY"
}

run_step 'Configure reusable GitHub SSH access' \
    'Configures the deployer GitHub SSH key and verifies repository access.' \
    step_github_key

step_app_folder() {
    sudo install -d -m 2775 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER"
    sudo install -d -m 2775 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER/shared"
    if [[ ! -f "$APP_FOLDER/shared/.env" ]]; then
        sudo install -m 640 -o "$DEPLOY_USER" -g www-data /dev/null "$APP_FOLDER/shared/.env"
    fi
    sudo -u "$DEPLOY_USER" "${EDITOR:-nano}" "$APP_FOLDER/shared/.env"
    configure_database_env
    ok 'Shared production .env exists and database settings were updated'
}

run_step 'Create the shared Laravel environment file' \
    'Creates the persistent .env, opens it for editing, then writes the selected database settings.' \
    step_app_folder

step_database() {
    if [[ "$DATABASE_DRIVER" == sqlite ]]; then
        sudo apt-get install -y sqlite3 "php$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')-sqlite3"
        sudo install -d -m 2775 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER/shared/database"
        if [[ ! -f "$APP_FOLDER/shared/database/database.sqlite" ]]; then
            sudo install -m 664 -o "$DEPLOY_USER" -g www-data /dev/null \
                "$APP_FOLDER/shared/database/database.sqlite"
        fi
        ok 'SQLite database is ready'
        return
    fi

    sudo apt-get install -y "php$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')-mysql"
    ok 'PHP MySQL driver is ready; the configured MySQL database will be used'
}

run_step 'Prepare the selected database' \
    'Installs the required PHP database driver and prepares the persistent SQLite file when selected.' \
    step_database

step_permissions() {
    sudo chown -R "$DEPLOY_USER:www-data" "$APP_FOLDER/shared"
    sudo find "$APP_FOLDER/shared" -type d -exec chmod 2775 {} +
    sudo find "$APP_FOLDER/shared" -type f -exec chmod 664 {} +
    sudo chmod 640 "$APP_FOLDER/shared/.env"
    ok 'Shared files are writable by deployer and www-data'
}

run_step 'Verify shared-file permissions' \
    'Sets deployer ownership and www-data group access on persistent Laravel files.' \
    step_permissions

step_caddy() {
    [[ -f "$CADDY_CERT" ]] || die "Missing certificate: $CADDY_CERT"
    [[ -f "$CADDY_KEY" ]] || die "Missing private key: $CADDY_KEY"
    sudo install -d -m 755 -o root -g root /etc/caddy/sites-enabled
    if ! sudo grep -Fq 'import /etc/caddy/sites-enabled/*.caddy' /etc/caddy/Caddyfile; then
        printf '\nimport /etc/caddy/sites-enabled/*.caddy\n' |
            sudo tee -a /etc/caddy/Caddyfile >/dev/null
    fi

    local temporary backup=''
    temporary="$(mktemp)"
    cat > "$temporary" <<EOF
${DOMAIN} {
    root * ${APP_FOLDER}/current/public
    php_fastcgi unix/${PHP_FPM_SOCKET}
    file_server
    encode zstd gzip
    tls ${CADDY_CERT} ${CADDY_KEY}
}
EOF
    if sudo test -f "$CADDY_SITE"; then
        backup="${CADDY_SITE}.bak.$(date +%Y%m%d%H%M%S)"
        sudo cp -a "$CADDY_SITE" "$backup"
    fi
    sudo install -m 644 -o root -g root "$temporary" "$CADDY_SITE"
    rm -f "$temporary"
    if ! sudo caddy validate --config /etc/caddy/Caddyfile; then
        [[ -n "$backup" ]] && sudo cp -a "$backup" "$CADDY_SITE" || sudo rm -f "$CADDY_SITE"
        die 'Caddy validation failed; the previous site configuration was restored'
    fi
    sudo systemctl reload caddy
    ok 'Caddy configuration is valid and active'
}

run_step 'Configure Caddy' 'Creates and validates the Caddy site configuration.' step_caddy

step_scheduler() {
    local cron_job="* * * * * cd ${APP_FOLDER}/current && php artisan schedule:run >> /dev/null 2>&1"
    local temporary
    temporary="$(mktemp)"
    sudo crontab -u www-data -l 2>/dev/null |
        grep -Fv "cd ${APP_FOLDER}/current && php artisan schedule:run" > "$temporary" || true
    echo "$cron_job" >> "$temporary"
    sudo crontab -u www-data "$temporary"
    rm -f "$temporary"
    ok 'Exactly one scheduler entry is configured'
}

run_step 'Configure Laravel scheduler' 'Adds one scheduler entry using the current release symlink.' step_scheduler

step_horizon() {
    if [[ "$USE_HORIZON" != true ]]; then
        ok 'Horizon was not selected; nothing to do'
        return
    fi
    command -v supervisorctl >/dev/null 2>&1 || sudo apt-get install -y supervisor
    command -v redis-server >/dev/null 2>&1 || sudo apt-get install -y redis-server
    local temporary
    temporary="$(mktemp)"
    cat > "$temporary" <<EOF
[program:${APP_NAME}-horizon]
process_name=%(program_name)s
command=php ${APP_FOLDER}/current/artisan horizon
stopasgroup=true
killasgroup=true
user=www-data
redirect_stderr=true
stdout_logfile=${APP_FOLDER}/shared/storage/logs/horizon.log
stopwaitsecs=3600
EOF
    sudo install -d -m 2775 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER/shared/storage/logs"
    sudo install -m 644 -o root -g root "$temporary" "$SUPERVISOR_FILE"
    rm -f "$temporary"
    if [[ -e "$APP_FOLDER/current/artisan" ]]; then
        sudo supervisorctl reread
        sudo supervisorctl update
    fi
    ok 'Horizon Supervisor configuration is ready'
}

run_step 'Configure Horizon' 'Creates a Supervisor program only when Horizon was selected.' step_horizon

echo
ok 'Server setup finished'
echo 'The current symlink has not been created by this script.'
echo 'Perform the first deployment from your local project with:'
echo '  vendor/bin/dep deploy production'
