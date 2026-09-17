#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMAND_FILE="$ROOT_DIR/src/Commands/InstallDeployerScaffoldingCommand.php"

command_text="$(<"$COMMAND_FILE")"

[[ "$command_text" == *"metator:install"* ]]
[[ "$command_text" == *"Site ID"* ]]
[[ "$command_text" == *"suggestedSiteId"* ]]
[[ "$command_text" == *"default: \$suggestedSiteId"* ]]
[[ "$command_text" == *"'__DEPLOY_PATH__' => '/var/www/'.\$siteId"* ]]
[[ "$command_text" == *"'__GIT_DEPLOYER_NAME__' => 'git-'.\$siteId"* ]]
[[ "$command_text" == *"php_version"* ]]
[[ "$command_text" == *"'database' =>"* ]]
[[ "$command_text" == *"'redis' =>"* ]]
[[ "$command_text" == *"'worker' =>"* ]]
[[ "$command_text" == *"'scheduler' =>"* ]]
[[ "$command_text" == *"metator."* && "$command_text" == *"configName"* ]]
[[ "$command_text" == *"var_export"* ]]
[[ "$command_text" != *"APP_KEY"* ]]
[[ "$command_text" != *"password"* ]]

printf '%s\n' 'Local site configuration checks passed.'
