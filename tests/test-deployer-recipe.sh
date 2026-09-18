#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPTS_FILE="$ROOT_DIR/src/Commands/InstallationPrompts.php"
DEPLOY_STUB="$ROOT_DIR/stubs/deploy.php.stub"

prompts_text="$(<"$PROMPTS_FILE")"
deploy_text="$(<"$DEPLOY_STUB")"

[[ "$prompts_text" == *"'__BRANCH__'"* ]]
[[ "$prompts_text" == *"Deployment branch"* ]]
[[ "$deploy_text" == *"set('branch', '__BRANCH__');"* ]]
[[ "$deploy_text" == *"require __DIR__.'/__CONFIG_FILE__';"* ]]
[[ "$deploy_text" == *"metator:verify-runtime"* ]]
[[ "$deploy_text" == *"set('bin/php', \$phpBinary)"* ]]
[[ "$deploy_text" == *"site['database']"* ]]
[[ "$deploy_text" == *"task('deploy:build-tailwind'"* ]]
[[ "$deploy_text" == *"artisan tailwindcss:download --force"* ]]
[[ "$deploy_text" == *"artisan tailwindcss:build --prod --no-tty"* ]]
[[ "$deploy_text" == *"after('deploy:vendors', 'deploy:build-tailwind');"* ]]
[[ "$deploy_text" != *"importmap"* ]]
[[ "$deploy_text" != *"deploy:assets"* ]]

printf '%s\n' 'Minimal Deployer recipe checks passed.'
