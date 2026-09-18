#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2317
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
source "$ROOT_DIR/stubs/scripts/steps/07-caddy.sh"
source "$ROOT_DIR/stubs/scripts/steps/09-workers.sh"

die() { printf '%s\n' "$*" >&2; }
ok() { printf '%s\n' "$*" >> "$TEST_DIR/success"; }
record_site_domain() { :; }
require_commands() { :; }
# supervisorctl is invoked through the mocked sudo wrapper below.

sudo() {
    local executable="$1" argument
    shift
    local arguments=()
    for argument in "$@"; do
        case "$argument" in
            /etc/caddy/*) argument="$TEST_DIR$argument" ;;
        esac
        arguments+=("$argument")
    done
    case "$executable" in
        install|cp|mv|tee)
            if [[ "${arguments[*]}" == *"$TEST_DIR/etc/caddy/"* && "${arguments[-1]}" == "$TEST_DIR/etc/caddy/"* ]]; then
                printf '%s\n' "$executable $*" >> "$TEST_DIR/live-writes"
            fi ;;
    esac
    case "$executable" in
        sed)
            [[ "$FAIL_REWRITE" != true ]] || return 1 ;;
        caddy)
            printf 'validate\n' >> "$TEST_DIR/caddy-actions"
            local line import=''
            while IFS= read -r line; do
                [[ "$line" != 'import '* ]] || import="${line#import }"
            done < "${arguments[2]}"
            [[ "$import" == "${arguments[2]%/*}/sites-enabled/*.caddy" ]] || return 1
            [[ -f "${import%/*}/billing.caddy" ]] || return 1
            return "$CADDY_STATUS" ;;
        systemctl)
            printf '%s\n' "$*" >> "$TEST_DIR/service-actions"
            case "$*" in
                'is-active --quiet caddy') return "${CADDY_ACTIVE_STATUS:-0}" ;;
                'reload caddy') return "${CADDY_RELOAD_STATUS:-0}" ;;
            esac
            return 0 ;;
        supervisorctl)
            printf '%s\n' "$*" >> "$TEST_DIR/supervisor-actions"
            [[ "$*" == '-c /etc/supervisor/supervisord.conf reread' ]] || return 1
            printf '%s\n' "$SUPERVISOR_OUTPUT"
            return "$SUPERVISOR_STATUS" ;;
        supervisord) printf 'Unexpected daemon startup\n' >&2; return 1 ;;
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

# shellcheck disable=SC2032
supervisorctl() { :; }

SITE_ID=billing
APP_NAME=billing
APP_FOLDER="$TEST_DIR/app"
DOMAIN=example.com
PHP_VERSION=8.4
PHP_FPM_SOCKET=/run/php/php8.4-fpm.sock
CADDY_SITE=/etc/caddy/sites-enabled/billing.caddy
FAIL_REWRITE=false
CADDY_STATUS=0
mkdir -p "$APP_FOLDER/current/public"
mkdir -p "$TEST_DIR/etc/caddy/sites-enabled"
printf '# Shared config\nimport /etc/caddy/sites-enabled/*.caddy\n' > "$TEST_DIR/etc/caddy/Caddyfile"
cat > "$TEST_DIR$CADDY_SITE" <<EOF
# Managed by Metator: site_id=${SITE_ID} domain=${DOMAIN}
${DOMAIN} {
    root * ${APP_FOLDER}/current/public
    php_fastcgi unix/${PHP_FPM_SOCKET}
    file_server
    encode zstd gzip
}
EOF
main_before="$(<"$TEST_DIR/etc/caddy/Caddyfile")"
site_before="$(<"$TEST_DIR$CADDY_SITE")"
metadata_before="$(stat -c '%i %y' "$TEST_DIR/etc/caddy/Caddyfile" "$TEST_DIR$CADDY_SITE")"

# An unchanged rerun validates the temporary import, including with positional args.
step_caddy
step_caddy argument
[[ "$(<"$TEST_DIR/etc/caddy/Caddyfile")" == "$main_before" ]]
[[ "$(<"$TEST_DIR$CADDY_SITE")" == "$site_before" ]]
[[ "$(<"$TEST_DIR/service-actions")" == $'is-active --quiet caddy\nis-active --quiet caddy' ]]
grep -Fxq 'Caddy configuration is unchanged and the service is active' "$TEST_DIR/success"
[[ "$(stat -c '%i %y' "$TEST_DIR/etc/caddy/Caddyfile" "$TEST_DIR$CADDY_SITE")" == "$metadata_before" ]]
[[ ! -e "$TEST_DIR/live-writes" ]]

# Inactive services (3) and failed queries (1) both fail without mutations.
for CADDY_ACTIVE_STATUS in 3 1; do
    rm "$TEST_DIR/service-actions"
    : > "$TEST_DIR/success"
    if step_caddy; then exit 1; fi
    [[ "$(<"$TEST_DIR/service-actions")" == 'is-active --quiet caddy' ]]
    [[ ! -s "$TEST_DIR/success" && ! -e "$TEST_DIR/live-writes" ]]
    [[ "$(stat -c '%i %y' "$TEST_DIR/etc/caddy/Caddyfile" "$TEST_DIR$CADDY_SITE")" == "$metadata_before" ]]
    [[ "$(<"$TEST_DIR/etc/caddy/Caddyfile")" == "$main_before" ]]
    [[ "$(<"$TEST_DIR$CADDY_SITE")" == "$site_before" ]]
done
rm "$TEST_DIR/service-actions"
CADDY_ACTIVE_STATUS=0

# A failed rewrite must stop before validation or a false no-op success.
rm "$TEST_DIR/caddy-actions"
FAIL_REWRITE=true
if step_caddy; then exit 1; fi
[[ ! -e "$TEST_DIR/caddy-actions" ]]
FAIL_REWRITE=false

# Candidate rejection preserves the current site and shared configuration.
CADDY_STATUS=1
if step_caddy; then exit 1; fi
[[ "$(<"$TEST_DIR/etc/caddy/Caddyfile")" == "$main_before" ]]
[[ "$(<"$TEST_DIR$CADDY_SITE")" == "$site_before" ]]
[[ ! -e "$TEST_DIR/service-actions" ]]

# Changed configuration still reloads, and failed activation restores both files.
CADDY_STATUS=0
PHP_FPM_SOCKET=/run/php/php8.5-fpm.sock
CADDY_RELOAD_STATUS=1
if step_caddy; then exit 1; fi
[[ "$(<"$TEST_DIR/service-actions")" == 'reload caddy' ]]
[[ "$(<"$TEST_DIR/etc/caddy/Caddyfile")" == "$main_before" ]]
[[ "$(<"$TEST_DIR$CADDY_SITE")" == "$site_before" ]]
rm "$TEST_DIR/service-actions"
CADDY_RELOAD_STATUS=0
step_caddy
[[ "$(<"$TEST_DIR/service-actions")" == 'reload caddy' ]]
grep -Fq 'php8.5-fpm.sock' "$TEST_DIR$CADDY_SITE"

USE_QUEUE=true
USE_HORIZON=false
DEPLOY_USER=deployer
SUPERVISOR_FILE="$TEST_DIR/billing-worker.conf"
SUPERVISOR_SUDOERS_FILE="$TEST_DIR/billing-worker.sudoers"
SUPERVISOR_OUTPUT='billing-worker: available'
SUPERVISOR_STATUS=0

# Successful staging uses the running daemon and never activates workers.
step_workers
grep -Fqx 'autostart=false' "$SUPERVISOR_FILE"
grep -Fqx -- '-c /etc/supervisor/supervisord.conf reread' "$TEST_DIR/supervisor-actions"
worker_before="$(<"$SUPERVISOR_FILE")"
sudoers_before="$(<"$SUPERVISOR_SUDOERS_FILE")"
rm "$TEST_DIR/supervisor-actions"
step_workers
[[ ! -e "$TEST_DIR/supervisor-actions" ]]

# Matching workers must still repair a missing or outdated site sudo policy.
rm "$SUPERVISOR_SUDOERS_FILE"
step_workers
[[ "$(<"$SUPERVISOR_SUDOERS_FILE")" == "$sudoers_before" ]]
rm "$SUPERVISOR_SUDOERS_FILE"
printf '# Managed by Metator: site_id=billing\nobsolete rule\n' > "$SUPERVISOR_SUDOERS_FILE"
step_workers
[[ "$(<"$SUPERVISOR_SUDOERS_FILE")" == "$sudoers_before" ]]
[[ "$(<"$SUPERVISOR_FILE")" == "$worker_before" ]]
[[ ! -e "$TEST_DIR/supervisor-actions" ]]

# Both nonzero failures and zero-exit RPC errors restore the previous file.
USE_HORIZON=true
for SUPERVISOR_STATUS in 0 1; do
    if [[ "$SUPERVISOR_STATUS" == 0 ]]; then
        SUPERVISOR_OUTPUT='ERROR: CANT_REREAD: invalid configuration'
    else
        SUPERVISOR_OUTPUT='Connection refused'
    fi
    if step_workers; then exit 1; fi
    [[ "$(<"$SUPERVISOR_FILE")" == "$worker_before" ]]
    [[ "$(<"$SUPERVISOR_SUDOERS_FILE")" == "$sudoers_before" ]]
done

# A failed first-time staging removes the rejected config and leaves no sudo policy.
rm "$SUPERVISOR_FILE" "$SUPERVISOR_SUDOERS_FILE"
if step_workers; then exit 1; fi
[[ ! -e "$SUPERVISOR_FILE" && ! -e "$SUPERVISOR_SUDOERS_FILE" ]]

printf 'Caddy and Supervisor validation checks passed.\n'
