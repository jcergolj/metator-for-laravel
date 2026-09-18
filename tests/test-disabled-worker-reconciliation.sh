#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2032
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
source "$ROOT_DIR/stubs/scripts/lib/common.sh"
source "$ROOT_DIR/stubs/scripts/steps/09-workers.sh"

APP_NAME=target
SITE_ID=target
APP_FOLDER="$TEST_DIR/site"
SUPERVISOR_FILE="$TEST_DIR/target.conf"
SUPERVISOR_SUDOERS_FILE="$TEST_DIR/target.sudoers"
USE_QUEUE=false
USE_HORIZON=false
SUPERVISOR_STATE=running
SUPERVISOR_GROUP_LOADED=true
COMMANDS="$TEST_DIR/commands"
touch "$COMMANDS"

supervisorctl() {
    printf '%s\n' "$*" >> "$COMMANDS"
    case "$1" in
        status) [[ "$SUPERVISOR_GROUP_LOADED" == true ]] ;;
        stop) SUPERVISOR_STATE=stopped ;;
        reread) [[ "${FAIL_REREAD:-false}" != true ]] ;;
        update) [[ "${FAIL_UPDATE:-false}" != true && "$2" == target-worker ]] && SUPERVISOR_GROUP_LOADED=false ;;
    esac
}
require_commands() { return 0; }
sudo() {
    case "$1" in
        test) command test "${@:2}" ;;
        grep) command grep "${@:2}" ;;
        rm) command rm "${@:2}" ;;
        cmp) command cmp "${@:2}" ;;
        *) command "$@" ;;
    esac
}

printf '# Managed by Metator: site_id=target\n' > "$SUPERVISOR_FILE"
printf '# Managed by Metator: site_id=target\n' > "$SUPERVISOR_SUDOERS_FILE"
FAIL_REREAD=true
if reconcile_disabled_workers; then exit 1; fi
[[ ! -e "$SUPERVISOR_FILE" ]]
[[ "$SUPERVISOR_STATE" == stopped ]]

FAIL_REREAD=false
SUPERVISOR_FILE="$TEST_DIR/target.conf"
printf '# Managed by Metator: site_id=target\n' > "$SUPERVISOR_FILE"
reconcile_disabled_workers
[[ ! -e "$SUPERVISOR_FILE" ]]
[[ ! -e "$SUPERVISOR_SUDOERS_FILE" ]]
grep -q '^update target-worker$' "$COMMANDS" || {
    printf 'Expected scoped update was not recorded:\n%s\n' "$(<"$COMMANDS")" >&2
    exit 1
}

before="$(<"$COMMANDS")"
reconcile_disabled_workers
[[ "$(<"$COMMANDS")" == "$before" ]]

printf '%s\n' 'Disabled worker reconciliation checks passed.'
