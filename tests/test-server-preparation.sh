#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap_text="$(<"$ROOT_DIR/stubs/scripts/server-bootstrap.sh")"
prerequisites_text="$(<"$ROOT_DIR/stubs/scripts/steps/01-prerequisites.sh")"
common_text="$(<"$ROOT_DIR/stubs/scripts/lib/common.sh")"

[[ "$bootstrap_text" == *"PHP_VERSION='__PHP_VERSION__'"* ]]
[[ "$bootstrap_text" == *'PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"'* ]]
[[ "$prerequisites_text" == *'prepare_shared_baseline'* ]]
[[ "$prerequisites_text" == *'requires Ubuntu 24.04'* ]]
[[ "$prerequisites_text" == *'php${PHP_VERSION}-fpm'* ]]
[[ "$prerequisites_text" == *'software-properties-common caddy'* ]]
[[ "$prerequisites_text" == *'add-apt-repository -y ppa:ondrej/php'* ]]
[[ "$common_text" == *'"$METATOR_OPERATION" == prepare-server'* ]]
[[ "$common_text" == *'skip_step "$title"'* ]]

printf '%s\n' 'Server preparation checks passed.'
