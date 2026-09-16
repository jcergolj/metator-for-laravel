#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016,SC2034
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/shared"
printf '%s\n' 'SECRET="old value"' 'UNCHANGED="keep me"' > "$TEST_DIR/shared/.env"

source "$ROOT_DIR/stubs/scripts/lib/common.sh"
APP_FOLDER="$TEST_DIR"

sudo() {
    "$@"
}

secret='quote" slash\ amp&pipe| dollar$HOME interpolation${APP_NAME} spaces'
set_env_value SECRET "$secret"
set_env_value NEW_SECRET "$secret"

expected='SECRET="quote\" slash\\ amp&pipe| dollar\$HOME interpolation\${APP_NAME} spaces"'
grep -Fxq "$expected" "$TEST_DIR/shared/.env"
grep -Fxq "NEW_$expected" "$TEST_DIR/shared/.env" || {
    printf '%s\n' 'FAIL missing-key value did not round-trip' >&2
    exit 1
}
grep -Fxq 'UNCHANGED="keep me"' "$TEST_DIR/shared/.env"

if grep -qF "$secret" "$TEST_DIR/shared/.env"; then
    printf '%s\n' 'FAIL raw secret appeared in diagnostics check' >&2
    exit 1
fi

printf '%s\n' 'Environment serialization checks passed.'
