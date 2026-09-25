#!/usr/bin/env bash
# shellcheck disable=SC2329
# shellcheck disable=SC1090,SC1091,SC2034,SC2317
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
        chmod|chown|apt-get) return 0 ;;
        git) return "${GIT_STATUS:-0}" ;;
        ssh-keyscan)
            printf '# github.com:22 SSH-2.0-test-banner\n'
            printf 'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl\n'
            return 0 ;;
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
SITE_ID=billing
PHP_VERSION=8.4
DATABASE_DRIVER=sqlite
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
grep -qx 'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl' "$ssh_dir/known_hosts"
first="$(<"$ssh_dir/config")"
GIT_STATUS=1
status=0
step_github_key </dev/null >"$TEST_DIR/registration" 2>&1 || status=$?
[[ "$status" == 75 ]]
[[ "$(<"$TEST_DIR/registration")" == *'https://github.com/acme/billing/settings/keys'* ]]
[[ "$(<"$TEST_DIR/registration")" == *existing-public-key* ]]
[[ "$(<"$ssh_dir/$GITHUB_ALIAS")" == existing-private-key ]]
GIT_STATUS=0
step_github_key </dev/null
printf 'github.com ssh-ed25519 conflicting-key\n' > "$ssh_dir/known_hosts"
if step_github_key </dev/null; then exit 1; fi
printf 'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl\n' > "$ssh_dir/known_hosts"
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
APP_FOLDER=/var/www/billing
require_safe_inputs
APP_FOLDER=/var/www/billing.app

# An unmarked deployment folder cannot be adopted.
APP_FOLDER=/var/www/unmarked
mkdir -p "$TEST_DIR$APP_FOLDER"
if claim_application_folder; then exit 1; fi
APP_FOLDER=/var/www/billing.app
printf 'site_id=%s\nrepository=%s\nphp_version=%s\ndatabase=%s\n' \
    "$SITE_ID" "$GITHUB_REPOSITORY" "$PHP_VERSION" "$DATABASE_DRIVER" \
    > "$TEST_DIR$APP_FOLDER/.metator-site"

# A deployment folder belongs to one site, even across different aliases.
claim_application_folder
claim_application_folder
GITHUB_REPOSITORY=acme/another-repository
if claim_application_folder; then exit 1; fi
GITHUB_REPOSITORY=acme/billing
PHP_VERSION=8.5
if claim_application_folder; then exit 1; fi
PHP_VERSION=8.4

# Existing protected environment/database files must not be truncated.
printf 'APP_KEY=keep-me\nDB_CONNECTION=sqlite\n' > "$TEST_DIR$APP_FOLDER/shared/.env"
printf 'existing database bytes\n' > "$TEST_DIR$APP_FOLDER/shared/database/database.sqlite"
ENV_EXAMPLE_FILE="$TEST_DIR/example"
printf 'APP_KEY=\nDB_CONNECTION=sqlite\n' > "$ENV_EXAMPLE_FILE"
DATABASE_DRIVER=sqlite
PHP_PACKAGE_PREFIX=php8.4
sqlite3() { :; }
php8.4() { printf 'pdo_sqlite\n'; }
EDITOR=true
 step_shared_env <<< ''
[[ "$(<"$TEST_DIR$APP_FOLDER/shared/.env")" == *APP_KEY=keep-me* ]]
step_database
[[ "$(<"$TEST_DIR$APP_FOLDER/shared/database/database.sqlite")" == 'existing database bytes' ]]
environment_before="$(<"$TEST_DIR$APP_FOLDER/shared/.env")"
step_shared_env <<< ''
[[ "$(<"$TEST_DIR$APP_FOLDER/shared/.env")" == "$environment_before" ]]

# Failed Caddy validation restores both shared and application configuration.
mkdir -p "$TEST_DIR/etc/caddy/sites-enabled"
printf '# Existing shared configuration\n' > "$TEST_DIR/etc/caddy/Caddyfile"
printf '# Managed by Metator: site_id=billing domain=example.com\nprevious app configuration\n' > "$TEST_DIR/etc/caddy/sites-enabled/billing.app.caddy"
printf 'another site\n' > "$TEST_DIR/etc/caddy/sites-enabled/other.caddy"
CADDY_CERT="$TEST_DIR/cert"
CADDY_KEY="$TEST_DIR/key"
CADDY_SITE=/etc/caddy/sites-enabled/billing.app.caddy
PHP_FPM_SOCKET=/run/php/php8.4-fpm.sock
touch "$CADDY_CERT" "$CADDY_KEY"
if step_caddy </dev/null; then exit 1; fi
[[ "$(<"$TEST_DIR/etc/caddy/Caddyfile")" == '# Existing shared configuration' ]]
[[ "$(<"$TEST_DIR/etc/caddy/sites-enabled/billing.app.caddy")" == $'# Managed by Metator: site_id=billing domain=example.com\nprevious app configuration' ]]
[[ "$(<"$TEST_DIR/etc/caddy/sites-enabled/other.caddy")" == 'another site' ]]

# New applications receive distinct shared Redis/cache/Horizon namespaces.
APP_FOLDER=/var/www/new-app
APP_NAME=new-app
ENV_EXAMPLE_FILE="$TEST_DIR/example"
printf 'APP_NAME=Laravel\nAPP_ENV=local\nAPP_DEBUG=true\nREDIS_PREFIX=laravel_\n' > "$ENV_EXAMPLE_FILE"
step_shared_env <<< ''
grep -qx 'APP_ENV="production"' "$TEST_DIR$APP_FOLDER/shared/.env"
grep -qx 'APP_DEBUG="false"' "$TEST_DIR$APP_FOLDER/shared/.env"
for prefix in REDIS_PREFIX CACHE_PREFIX HORIZON_PREFIX; do
    grep -qx "${prefix}=\"metator_new-app_\"" "$TEST_DIR$APP_FOLDER/shared/.env"
done
APP_FOLDER=/var/www/billing.app
APP_NAME=billing.app

# Scheduler files are site-owned, explicit-versioned, and no-op safe.
USE_SCHEDULER=true
SCHEDULER_FILE="$TEST_DIR/cron.d/metator-billing.app"
mkdir -p "$(dirname "$SCHEDULER_FILE")"
step_scheduler
grep -Fqx '# Managed by Metator: site_id=billing' "$SCHEDULER_FILE"
grep -Fq '/usr/bin/php8.4 artisan schedule:run' "$SCHEDULER_FILE"
grep -Fq 'if [ -f "/var/www/billing.app/current/artisan" ]' "$SCHEDULER_FILE"
cron_after="$(<"$SCHEDULER_FILE")"
step_scheduler
[[ "$(<"$SCHEDULER_FILE")" == "$cron_after" ]]
printf '%s\n' '# Managed by Metator: site_id=other' > "$SCHEDULER_FILE"
if step_scheduler; then exit 1; fi
[[ "$(<"$SCHEDULER_FILE")" == '# Managed by Metator: site_id=other' ]]

# Disabling removes only this site's owned scheduler entry and is a no-op when absent.
printf '%s\n' '# Managed by Metator: site_id=billing' > "$SCHEDULER_FILE"
USE_SCHEDULER=false
step_scheduler
[[ ! -e "$SCHEDULER_FILE" ]]
step_scheduler
printf '%s\n' '# Managed by Metator: site_id=other' > "$SCHEDULER_FILE"
if step_scheduler; then exit 1; fi
[[ "$(<"$SCHEDULER_FILE")" == '# Managed by Metator: site_id=other' ]]

# The complete bootstrap must serialize shared-file updates across applications.
bootstrap="$(<"$ROOT_DIR/stubs/scripts/server-bootstrap.sh")"
[[ "$bootstrap" == *'flock -n'* ]]
[[ "$bootstrap" == *'/var/lock/metator-bootstrap.lock'* ]]

# Only this application's pending Supervisor changes should be applied.
supervisorctl() { :; }
supervisord() { :; }
sudo() {
    [[ "${1:-}" != cmp ]] || return 1
    printf '%s\n' "$*" >> "$TEST_DIR/commands"
    case "${1:-}" in
        grep|test|rm) command "$@" ;;
    esac
}
APP_FOLDER="$TEST_DIR/app"
APP_NAME=billing
SUPERVISOR_FILE="$TEST_DIR/billing-worker.conf"
SUPERVISOR_SUDOERS_FILE="$TEST_DIR/billing-worker.sudoers"
USE_QUEUE=true
USE_HORIZON=false
mkdir -p "$APP_FOLDER/current"
touch "$APP_FOLDER/current/artisan"
step_workers <<< ''
if grep -q '^supervisord \|supervisorctl.*update\|supervisorctl.*restart' "$TEST_DIR/commands"; then exit 1; fi
grep -q 'supervisorctl -c /etc/supervisor/supervisord.conf reread' "$TEST_DIR/commands"

# Disabling stops and removes only this site's owned worker configuration.
SUPERVISOR_FILE="$TEST_DIR/billing-worker.conf"
SUPERVISOR_SUDOERS_FILE="$TEST_DIR/billing-worker.sudoers"
other_worker_file="$TEST_DIR/other-worker.conf"
printf '%s\n' '# Managed by Metator: site_id=other' > "$other_worker_file"
printf '%s\n' '# Managed by Metator: site_id=billing' > "$SUPERVISOR_FILE"
printf '%s\n' '# Managed by Metator: site_id=billing' > "$SUPERVISOR_SUDOERS_FILE"
supervisorctl() { printf '%s\n' "$*" >> "$TEST_DIR/supervisor"; }
USE_QUEUE=false
step_workers
[[ ! -e "$SUPERVISOR_FILE" && ! -e "$SUPERVISOR_SUDOERS_FILE" ]]
grep -Fqx 'stop billing-worker:*' "$TEST_DIR/supervisor"
grep -qx 'reread' "$TEST_DIR/supervisor"
grep -qx 'update billing-worker' "$TEST_DIR/supervisor"
[[ "$(<"$other_worker_file")" == '# Managed by Metator: site_id=other' ]]
step_workers
printf '%s\n' '# Managed by Metator: site_id=other' > "$SUPERVISOR_FILE"
if step_workers; then exit 1; fi
[[ -e "$SUPERVISOR_FILE" ]]

printf 'Shared-server collision checks passed.\n'
