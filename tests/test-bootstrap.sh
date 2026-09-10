#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_FILE="$ROOT_DIR/stubs/scripts/lib/common.sh"
BOOTSTRAP_FILE="$ROOT_DIR/stubs/scripts/server-bootstrap.sh"

bootstrap_text="$(<"$BOOTSTRAP_FILE")"
common_text="$(<"$COMMON_FILE")"
[[ "$bootstrap_text" != *"prompt_value 'GitHub repository'"* ]]
[[ "$bootstrap_text" != *"prompt_value 'Application folder'"* ]]
[[ "$bootstrap_text" != *"prompt_value 'Domain'"* ]]
[[ "$common_text" != *'configure_optional_steps'* ]]
[[ "$(<"$COMMON_FILE")" != *'[c] Continue  [s] Skip  [q] Quit'* ]]

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

ENV_EXAMPLE="$TEST_DIR/.env.example"
ENV_FILE="$TEST_DIR/.env"
cat > "$ENV_EXAMPLE" <<'EOF'
APP_NAME=Example
APP_KEY=
DB_CONNECTION=sqlite
EOF
cat > "$ENV_FILE" <<'EOF'
APP_NAME=Existing
EOF

sudo() { command "$@"; }
source "$COMMON_FILE"

ENV_UPDATED=false
merge_env_example "$ENV_EXAMPLE" "$ENV_FILE"

[[ "$(grep -c '^APP_NAME=' "$ENV_FILE")" == 1 ]]
[[ "$(grep '^APP_NAME=' "$ENV_FILE")" == 'APP_NAME=Existing' ]]
[[ "$(grep '^APP_KEY=' "$ENV_FILE")" == 'APP_KEY=' ]]
[[ "$(grep '^DB_CONNECTION=' "$ENV_FILE")" == 'DB_CONNECTION=sqlite' ]]
[[ "$ENV_UPDATED" == true ]]

before="$(<"$ENV_FILE")"
ENV_UPDATED=false
merge_env_example "$ENV_EXAMPLE" "$ENV_FILE"
[[ "$(<"$ENV_FILE")" == "$before" ]]
[[ "$ENV_UPDATED" == false ]]

printf '%s\n' 'Bootstrap checks passed.'
