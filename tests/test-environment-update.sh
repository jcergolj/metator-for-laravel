#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script_text="$(<"$ROOT_DIR/stubs/scripts/environment-update.sh")"
common_text="$(<"$ROOT_DIR/stubs/scripts/lib/common.sh")"

[[ "$script_text" == *'protected_keys'* ]]
[[ "$script_text" == *'updated atomically'* ]]
[[ "$script_text" == *'Refresh Laravel configuration'* ]]
[[ "$script_text" == *'Missing local environment input'* ]]
[[ "$common_text" == *"ENV_FILE:-\$APP_FOLDER/shared/.env"* ]]
[[ "$script_text" != *'APP_KEY="'* ]]

printf '%s\n' 'Environment update checks passed.'
