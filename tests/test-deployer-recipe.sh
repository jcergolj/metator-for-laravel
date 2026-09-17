#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPTS_FILE="$ROOT_DIR/src/Commands/InstallationPrompts.php"
DEPLOY_STUB="$ROOT_DIR/stubs/deploy.php.stub"
README="$ROOT_DIR/README.md"

prompts_text="$(<"$PROMPTS_FILE")"
deploy_text="$(<"$DEPLOY_STUB")"
readme_text="$(<"$README")"

[[ "$prompts_text" == *"'__BRANCH__'"* ]]
[[ "$prompts_text" == *"Deployment branch"* ]]
[[ "$deploy_text" == *"set('branch', '__BRANCH__');"* ]]
[[ "$deploy_text" == *"require __DIR__.'/__CONFIG_FILE__';"* ]]
[[ "$deploy_text" == *"metator:verify-runtime"* ]]
[[ "$deploy_text" == *"set('bin/php', \$phpBinary)"* ]]
[[ "$deploy_text" == *"site['database']"* ]]
[[ "$deploy_text" != *"tailwindcss"* ]]
[[ "$deploy_text" != *"importmap"* ]]
[[ "$deploy_text" != *"deploy:assets"* ]]
[[ "$readme_text" == *"asset build"* ]]
[[ "$readme_text" == *"branch"* ]]

printf '%s\n' 'Minimal Deployer recipe checks passed.'
