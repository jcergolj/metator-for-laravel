#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/home/deployer/.ssh" "$TEST_DIR/var/www/billing.app/shared/database"
source "$ROOT_DIR/stubs/scripts/lib/common.sh"
for step in "$ROOT_DIR"/stubs/scripts/steps/*.sh; do source "$step"; done

# Model files visible only through sudo, without touching the real server.
sandbox_sudo() {
    [[ "${1:-}" != -u ]] || shift 2
    local executable="$1" argument
    shift
    local arguments=()
    for argument in "$@"; do
        case "$argument" in
            /home/deployer/*|/var/www/*|/etc/caddy/*) argument="$TEST_DIR$argument" ;;
        esac
        arguments+=("$argument")
    done
    case "$executable" in
        chmod|chown|apt-get|git) return 0 ;;
        ssh-keygen) printf 'Unexpected key generation\n' >&2; return 1 ;;
        install)
            set -- "${arguments[@]}"
            arguments=()
            while [[ "$#" -gt 0 ]]; do
                case "$1" in
                    -o|-g) shift 2 ;;
                    *) arguments+=("$1"); shift ;;
                esac
            done ;;
    esac
    command "$executable" "${arguments[@]}"
}

sudo() {
    case "$1" in
        caddy) return 1 ;;
        crontab) shift; crontab "$@" ;;
        *) sandbox_sudo "$@" ;;
    esac
}

APP_NAME=billing.app
APP_FOLDER=/var/www/billing.app
GITHUB_ALIAS=billing-github
GITHUB_REPOSITORY=acme/billing
configure_github_identity
ssh_dir="$TEST_DIR/home/deployer/.ssh"
printf 'existing-private-key\n' > "$ssh_dir/$GITHUB_ALIAS"
printf 'existing-public-key\n' > "$ssh_dir/$GITHUB_ALIAS.pub"
cat > "$ssh_dir/config" <<'EOF'
# BEGIN LARAVEL DEPLOYER GITHUB billingXapp
Host another-app
    HostName github.com
    IdentityFile /home/deployer/.ssh/another-app
# END LARAVEL DEPLOYER GITHUB billingXapp
Host *
    ServerAliveInterval 30
EOF
original="$(<"$ssh_dir/config")"
step_github_key </dev/null
[[ "$(<"$ssh_dir/config")" == *"$original"* ]]
[[ "$(<"$ssh_dir/$GITHUB_ALIAS")" == existing-private-key ]]
first="$(<"$ssh_dir/config")"
step_github_key </dev/null
[[ "$(<"$ssh_dir/config")" == "$first" ]]
GITHUB_REPOSITORY=acme/unrelated
configure_github_identity
if step_github_key </dev/null; then exit 1; fi
[[ "$(<"$ssh_dir/config")" == "$first" ]]
GITHUB_REPOSITORY=acme/billing

# Global SSH options must stay global when inserting an application block.
printf 'ServerAliveInterval 45\n%s\n' "$first" > "$ssh_dir/config"
step_github_key </dev/null
[[ "$(sed -n '1p' "$ssh_dir/config")" == 'ServerAliveInterval 45' ]]
first="$(<"$ssh_dir/config")"

# A second app cannot claim an existing alias, even with different casing.
APP_NAME=other-app
GITHUB_ALIAS=BILLING-GITHUB
configure_github_identity
if step_github_key </dev/null; then
    printf 'Duplicate SSH alias was accepted\n' >&2
    exit 1
fi
[[ "$(<"$ssh_dir/config")" == "$first" ]]

# Unmanaged aliases must also survive untouched.
printf '\nHost unmanaged alias-two\n    HostName github.com\n' >> "$ssh_dir/config"
GITHUB_ALIAS=alias-two
configure_github_identity
before="$(<"$ssh_dir/config")"
if step_github_key </dev/null; then exit 1; fi
[[ "$(<"$ssh_dir/config")" == "$before" ]]

# Reserved SSH filenames may never be used as private-key filenames.
GITHUB_REPOSITORY=acme/billing
DOMAIN=example.com
SERVER_IP=192.0.2.1
for GITHUB_ALIAS in config authorized_keys known_hosts known_hosts.old billing-github.pub; do
    if require_safe_inputs; then exit 1; fi
done
GITHUB_ALIAS=billing-github
for APP_FOLDER in /var/www/. /var/www/..; do
    if require_safe_inputs; then exit 1; fi
done
APP_FOLDER=/var/www/billing.app
require_safe_inputs

# A deployment folder belongs to one repository, even across different aliases.
claim_application_folder
claim_application_folder
GITHUB_REPOSITORY=acme/another-repository
if claim_application_folder; then exit 1; fi
GITHUB_REPOSITORY=acme/billing

# Existing protected environment/database files must not be truncated.
printf 'APP_KEY=keep-me\nDB_CONNECTION=sqlite\n' > "$TEST_DIR$APP_FOLDER/shared/.env"
printf 'existing database bytes\n' > "$TEST_DIR$APP_FOLDER/shared/database/database.sqlite"
ENV_EXAMPLE_FILE="$TEST_DIR/example"
printf 'APP_KEY=\nDB_CONNECTION=sqlite\n' > "$ENV_EXAMPLE_FILE"
DATABASE_DRIVER=sqlite
PHP_PACKAGE_PREFIX=php8.4
EDITOR=true
step_app_folder <<< ''
[[ "$(<"$TEST_DIR$APP_FOLDER/shared/.env")" == *APP_KEY=keep-me* ]]
step_database
[[ "$(<"$TEST_DIR$APP_FOLDER/shared/database/database.sqlite")" == 'existing database bytes' ]]

# Failed Caddy validation restores both shared and application configuration.
mkdir -p "$TEST_DIR/etc/caddy/sites-enabled"
printf '# Existing shared configuration\n' > "$TEST_DIR/etc/caddy/Caddyfile"
printf 'previous app configuration\n' > "$TEST_DIR/etc/caddy/sites-enabled/billing.app.caddy"
printf 'another site\n' > "$TEST_DIR/etc/caddy/sites-enabled/other.caddy"
CADDY_CERT="$TEST_DIR/cert"
CADDY_KEY="$TEST_DIR/key"
CADDY_SITE=/etc/caddy/sites-enabled/billing.app.caddy
PHP_FPM_SOCKET=/run/php/php8.4-fpm.sock
touch "$CADDY_CERT" "$CADDY_KEY"
if step_caddy </dev/null; then exit 1; fi
[[ "$(<"$TEST_DIR/etc/caddy/Caddyfile")" == '# Existing shared configuration' ]]
[[ "$(<"$TEST_DIR/etc/caddy/sites-enabled/billing.app.caddy")" == 'previous app configuration' ]]
[[ "$(<"$TEST_DIR/etc/caddy/sites-enabled/other.caddy")" == 'another site' ]]

# New applications receive distinct shared Redis/cache/Horizon namespaces.
APP_FOLDER=/var/www/new-app
APP_NAME=new-app
ENV_EXAMPLE_FILE="$TEST_DIR/example"
printf 'APP_NAME=Laravel\nREDIS_PREFIX=laravel_\n' > "$ENV_EXAMPLE_FILE"
step_app_folder <<< ''
for prefix in REDIS_PREFIX CACHE_PREFIX HORIZON_PREFIX; do
    grep -qx "${prefix}=\"metator_new-app_\"" "$TEST_DIR$APP_FOLDER/shared/.env"
done
APP_FOLDER=/var/www/billing.app
APP_NAME=billing.app

# Scheduler updates preserve other jobs and comments, and abort on read errors.
USE_SCHEDULER=true
cat > "$TEST_DIR/crontab" <<'EOF'
MAILTO=ops@example.com
* * * * * cd /var/www/other/current && php artisan schedule:run >> /dev/null 2>&1
# Keep cd /var/www/billing.app/current && php artisan schedule:run documented
EOF
cron_before="$(<"$TEST_DIR/crontab")"
crontab() {
    if [[ "$3" == -l ]]; then
        if [[ "${CRON_READ_FAIL:-false}" == true ]]; then
            printf 'permission denied\n' >&2
            return 1
        fi
        cat "$TEST_DIR/crontab"
    else
        cp "$3" "$TEST_DIR/crontab"
    fi
}
step_scheduler
[[ "$(<"$TEST_DIR/crontab")" == *"$cron_before"* ]]
cron_after="$(<"$TEST_DIR/crontab")"
step_scheduler
[[ "$(<"$TEST_DIR/crontab")" == "$cron_after" ]]
CRON_READ_FAIL=true
if step_scheduler; then exit 1; fi
[[ "$(<"$TEST_DIR/crontab")" == "$cron_after" ]]

# The complete bootstrap must serialize shared-file updates across applications.
bootstrap="$(<"$ROOT_DIR/stubs/scripts/server-bootstrap.sh")"
[[ "$bootstrap" == *'flock -n'* ]]
[[ "$bootstrap" == *'/var/lock/metator-bootstrap.lock'* ]]

# Only this application's pending Supervisor changes should be applied.
supervisorctl() { :; }
sudo() { printf '%s\n' "$*" >> "$TEST_DIR/commands"; }
APP_FOLDER="$TEST_DIR/app"
APP_NAME=billing
SUPERVISOR_FILE="$TEST_DIR/billing-worker.conf"
USE_QUEUE=true
USE_HORIZON=false
mkdir -p "$APP_FOLDER/current"
touch "$APP_FOLDER/current/artisan"
step_workers <<< ''
grep -qx 'supervisorctl update billing-worker' "$TEST_DIR/commands"
if grep -qx 'supervisorctl update' "$TEST_DIR/commands"; then exit 1; fi

printf 'Shared-server collision checks passed.\n'
