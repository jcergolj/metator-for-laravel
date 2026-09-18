#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
source "$ROOT_DIR/stubs/scripts/lib/common.sh"
sudo() { "$@"; }

printf '# Application\nAPP_NAME=Laravel\n\n\n# Database\nDB_CONNECTION=sqlite\n\n' > "$TEST_DIR/example"
ENV_FILE_CREATED=true
touch "$TEST_DIR/env"
merge_env_example "$TEST_DIR/example" "$TEST_DIR/env"
cmp "$TEST_DIR/example" "$TEST_DIR/env"
[[ "$ENV_UPDATED" == true ]]

DOMAIN=example.test
APP_FOLDER="$TEST_DIR"
mkdir -p "$TEST_DIR/shared"
ENV_FILE="$TEST_DIR/env"
set_env_value APP_URL "https://${DOMAIN}"
grep -Fxq 'APP_URL="https://example.test"' "$TEST_DIR/env"

# Existing environments keep their values and layout on subsequent merges.
ENV_FILE_CREATED=false
printf '# Custom\nAPP_NAME=Production\n\nDB_CONNECTION=mysql\n' > "$TEST_DIR/env"
cp "$TEST_DIR/env" "$TEST_DIR/before"
merge_env_example "$TEST_DIR/example" "$TEST_DIR/env"
cmp "$TEST_DIR/before" "$TEST_DIR/env"
[[ "$ENV_UPDATED" == false ]]
printf 'Environment layout checks passed.\n'
