#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMAND_FILE="$ROOT_DIR/src/Commands/InstallDeployerScaffoldingCommand.php"

command_text="$(<"$COMMAND_FILE")"
deploy_stub="$(<"$ROOT_DIR/stubs/deploy.php.stub")"
common_stub="$(<"$ROOT_DIR/stubs/scripts/lib/common.sh")"

[[ "$command_text" == *'use function Laravel\Prompts\text;'* ]]
[[ "$command_text" == *"'Server IP address'"* ]]
[[ "$command_text" == *"'Git SSH deployer name'"* ]]
[[ "$command_text" == *"default: 'deployer-github-'.\$project"* ]]
[[ "$command_text" == *'use function Laravel\Prompts\confirm;'* ]]
[[ "$command_text" == *'use function Laravel\Prompts\select;'* ]]
[[ "$command_text" != *github-deployer* ]]
[[ "$deploy_stub" == *"__SERVER_IP__"* ]]
[[ "$deploy_stub" == *"__GIT_DEPLOYER_NAME__"* ]]
[[ "$common_stub" == *"__GIT_DEPLOYER_NAME__"* ]]
[[ "$command_text" == *".env.example"* ]]

printf '%s\n' 'Install prompt checks passed.'
