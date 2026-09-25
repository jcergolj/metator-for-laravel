#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2317
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
source "$ROOT_DIR/stubs/scripts/lib/common.sh"
source "$ROOT_DIR/stubs/scripts/steps/09-workers.sh"
# Satisfy command discovery; the sudo mock below handles Supervisor calls.
# shellcheck disable=SC2032
supervisorctl() { :; }
sudo() {
    printf '%s\n' "$*" >> "$TEST_DIR/commands"
    local executable="$1"
    shift
    case "$executable" in
        systemctl) return 0 ;;
        supervisord) printf 'Must not start another daemon\n' >&2; return 99 ;;
        supervisorctl)
            if [[ "$*" != '-c /etc/supervisor/supervisord.conf reread' ]]; then
                return 0
            fi
            case "$VALIDATION" in
                success) printf 'review-worker: available\n' ;;
                error) printf 'ERROR: CANT_REREAD: invalid worker configuration\n' ;;
                offline) return 1 ;;
            esac
            return 0 ;;
        install)
            local args=()
            while [[ "$#" -gt 0 ]]; do
                case "$1" in
                    -o|-g) shift 2 ;;
                    *) args+=("$1"); shift ;;
                esac
            done
            command install "${args[@]}" ;;
        *) command "$executable" "$@" ;;
    esac
}
APP_FOLDER="$TEST_DIR/site"
APP_NAME=review
SITE_ID=review
PHP_VERSION=8.5
SUPERVISOR_FILE="$TEST_DIR/review.conf"
SUPERVISOR_SUDOERS_FILE="$TEST_DIR/review.sudoers"
USE_QUEUE=true
USE_HORIZON=false
VALIDATION=error
if step_workers; then exit 1; fi
[[ ! -e "$SUPERVISOR_FILE" ]]

printf '# Managed by Metator: site_id=review\nprevious configuration\n' > "$SUPERVISOR_FILE"
previous="$(<"$SUPERVISOR_FILE")"
if step_workers; then exit 1; fi
[[ "$(<"$SUPERVISOR_FILE")" == "$previous" ]]
VALIDATION=offline
if step_workers; then exit 1; fi
[[ "$(<"$SUPERVISOR_FILE")" == "$previous" ]]
VALIDATION=success
step_workers
[[ "$(<"$SUPERVISOR_FILE")" == *autostart=false* ]]
[[ "$(<"$SUPERVISOR_FILE")" == *'/usr/bin/php8.5 '* ]]
[[ -f "$SUPERVISOR_SUDOERS_FILE" ]]
grep -Fq 'restart review-worker\:review-worker' "$SUPERVISOR_SUDOERS_FILE"
grep -Fq 'status review-worker\:review-worker' "$SUPERVISOR_SUDOERS_FILE"
! grep -Fq 'review-worker:*' "$SUPERVISOR_SUDOERS_FILE"
if grep -q '^supervisord ' "$TEST_DIR/commands"; then exit 1; fi
if grep -qE '^supervisorctl .* (update|restart|start)( |$)' "$TEST_DIR/commands"; then exit 1; fi
printf 'Worker validation checks passed.\n'
