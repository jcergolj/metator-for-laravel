#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMAND_FILE="$ROOT_DIR/src/Commands/InstallDeployerScaffoldingCommand.php"
PROMPTS_FILE="$ROOT_DIR/src/Commands/InstallationPrompts.php"
WRITER_FILE="$ROOT_DIR/src/Commands/GeneratedFileWriter.php"

command_text="$(<"$COMMAND_FILE")"
prompts_text="$(<"$PROMPTS_FILE")"
writer_text="$(<"$WRITER_FILE")"

[[ "$command_text" == *"metator:install"* ]]
[[ "$prompts_text" == *"Site ID"* ]]
[[ "$prompts_text" == *"suggestedSiteId"* ]]
[[ "$prompts_text" == *"default: \$suggestedSiteId"* ]]
[[ "$prompts_text" == *"'__DEPLOY_PATH__' => '/var/www/'.\$siteId"* ]]
[[ "$prompts_text" == *"'__GIT_DEPLOYER_NAME__' => 'git-'.\$siteId"* ]]
[[ "$writer_text" == *"php_version"* ]]
[[ "$writer_text" == *"'database' =>"* ]]
[[ "$writer_text" == *"'cloudflare' =>"* ]]
[[ "$writer_text" == *"'redis' =>"* ]]
[[ "$writer_text" == *"'worker' =>"* ]]
[[ "$writer_text" == *"'scheduler' =>"* ]]
[[ "$prompts_text" == *"metator."* && "$prompts_text" == *"configName"* ]]
[[ "$writer_text" == *"var_export"* ]]
[[ "$writer_text" != *"APP_KEY"* ]]
[[ "$prompts_text" == *"password"* && "$prompts_text" == *".local.php"* ]]

printf '%s\n' 'Local site configuration checks passed.'
