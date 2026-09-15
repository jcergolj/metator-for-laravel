#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMAND_FILE="$ROOT_DIR/src/Commands/InstallDeployerScaffoldingCommand.php"

command_text="$(<"$COMMAND_FILE")"
deploy_stub="$(<"$ROOT_DIR/stubs/deploy.php.stub")"
instructions_stub="$(<"$ROOT_DIR/stubs/scripts/steps/10-deployer-instructions.sh")"
common_stub="$(<"$ROOT_DIR/stubs/scripts/lib/common.sh")"

[[ "$command_text" == *'use function Laravel\Prompts\text;'* ]]
[[ "$command_text" == *"'Server IP address'"* ]]
[[ "$command_text" == *"'Git SSH deployer name'"* ]]
[[ "$command_text" == *"default: 'deployer-github-'.\$project"* ]]
[[ "$command_text" == *'use function Laravel\Prompts\multiselect;'* ]]
[[ "$command_text" == *'use function Laravel\Prompts\select;'* ]]
[[ "$command_text" == *"metator/steps"* ]]
[[ "$command_text" == *".metator-manifest.json"* ]]
[[ "$command_text" != *github-deployer* ]]
[[ "$deploy_stub" == *"__SERVER_IP__"* ]]
[[ "$deploy_stub" == *"__GIT_DEPLOYER_NAME__"* ]]
[[ "$deploy_stub" == *"set('worker_type', getenv('WORKER_TYPE') ?: 'horizon');"* ]]
[[ "$deploy_stub" == *"artisan horizon:terminate"* ]]
[[ "$deploy_stub" == *"artisan queue:restart"* ]]
[[ "$deploy_stub" == *"deploy:verify-workers"* ]]
[[ "$instructions_stub" == *'deploy.php already terminates Horizon'* ]]
[[ "$instructions_stub" == *'Deploy with WORKER_TYPE=queue'* ]]
[[ "$common_stub" == *"__GIT_DEPLOYER_NAME__"* ]]
[[ "$command_text" == *".env.example"* ]]
[[ "$command_text" == *"\$basePath.'/.env.example'"* ]]
[[ "$command_text" == *'Missing application .env.example'* ]]
deploy_stub_text="$(<"$ROOT_DIR/stubs/deploy.php.stub")"
workers_stub="$(<"$ROOT_DIR/stubs/scripts/steps/09-workers.sh")"
permissions_stub="$(<"$ROOT_DIR/stubs/scripts/steps/06-permissions.sh")"
[[ "$common_stub" == *'while IFS= read -r line || [[ -n "$line" ]]'* ]]
[[ "$common_stub" != *'sed -i "s|^${key}=.*'* ]]
[[ "$workers_stub" == *'--timeout=60'* ]]
[[ "$permissions_stub" == *'chmod 2770'* ]]
[[ "$permissions_stub" == *'chmod 660'* ]]
[[ "$deploy_stub_text" == *"task('deploy:activate-workers'"* ]]
[[ "$deploy_stub_text" == *"after('deploy:symlink', 'deploy:activate-workers')"* ]]
[[ "$(<"$ROOT_DIR/stubs/scripts/steps/07-caddy.sh")" == *'# @group: web-server'* ]]
[[ "$common_stub" == *'run_selected_steps'* ]]

printf '%s\n' 'Install prompt checks passed.'
