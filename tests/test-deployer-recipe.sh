#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMAND_FILE="$ROOT_DIR/src/Commands/InstallDeployerScaffoldingCommand.php"
DEPLOY_STUB="$ROOT_DIR/stubs/deploy.php.stub"
README="$ROOT_DIR/README.md"

command_text="$(<"$COMMAND_FILE")"
deploy_text="$(<"$DEPLOY_STUB")"
readme_text="$(<"$README")"

[[ "$command_text" == *"'__BRANCH__'"* ]]
[[ "$command_text" == *"Deployment branch"* ]]
[[ "$deploy_text" == *"set('branch', '__BRANCH__');"* ]]
[[ "$deploy_text" != *"tailwindcss"* ]]
[[ "$deploy_text" != *"importmap"* ]]
[[ "$deploy_text" != *"deploy:assets"* ]]
[[ "$readme_text" == *"asset build"* ]]
[[ "$readme_text" == *"branch"* ]]

printf '%s\n' 'Minimal Deployer recipe checks passed.'
