#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/shared/storage"
touch "$TEST_DIR/shared/.env" \
    "$TEST_DIR/shared/database.sqlite" \
    "$TEST_DIR/shared/storage/log.txt"

source "$ROOT_DIR/stubs/scripts/lib/common.sh"
source "$ROOT_DIR/stubs/scripts/steps/06-permissions.sh"
APP_FOLDER="$TEST_DIR"
DEPLOY_USER="$(id -un)"

sudo() {
    if [[ "$1" == chown ]]; then
        return 0
    fi
    "$@"
}

step_permissions >/dev/null
before_mode="$(stat -c '%a' "$TEST_DIR/shared/storage/log.txt")"
step_permissions >/dev/null
[[ "$(stat -c '%a' "$TEST_DIR/shared/storage/log.txt")" == "$before_mode" ]]

for directory in \
    shared/storage/framework/cache \
    shared/storage/framework/data \
    shared/storage/framework/sessions \
    shared/storage/framework/views \
    shared/storage/logs \
    shared/bootstrap/cache; do
    [[ -d "$TEST_DIR/$directory" ]]
done

assert_mode() {
    local expected="$1" path="$2" actual
    actual="$(stat -c '%a' "$path")"
    [[ "$actual" == "$expected" ]] || {
        printf 'FAIL %s: expected mode %s, got %s\n' "$path" "$expected" "$actual" >&2
        exit 1
    }
}

assert_mode 2770 "$TEST_DIR/shared"
assert_mode 2770 "$TEST_DIR/shared/storage"
assert_mode 660 "$TEST_DIR/shared/database.sqlite"
assert_mode 660 "$TEST_DIR/shared/storage/log.txt"
assert_mode 640 "$TEST_DIR/shared/.env"

if command -v runuser >/dev/null 2>&1 && id nobody >/dev/null 2>&1; then
    if runuser -u nobody -- cat "$TEST_DIR/shared/database.sqlite" >/dev/null 2>&1; then
        printf 'FAIL unrelated user can read the SQLite database\n' >&2
        exit 1
    fi
fi

printf '%s\n' 'Permission checks passed.'
