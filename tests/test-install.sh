#!/usr/bin/env bash
# shellcheck disable=SC2016
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMAND_FILE="$ROOT_DIR/src/Commands/InstallDeployerScaffoldingCommand.php"
PROMPTS_FILE="$ROOT_DIR/src/Commands/InstallationPrompts.php"
CATALOGUE_FILE="$ROOT_DIR/src/Commands/StepCatalogue.php"
WRITER_FILE="$ROOT_DIR/src/Commands/GeneratedFileWriter.php"

command_text="$(<"$COMMAND_FILE")"
prompts_text="$(<"$PROMPTS_FILE")"
catalogue_text="$(<"$CATALOGUE_FILE")"
writer_text="$(<"$WRITER_FILE")"
deploy_stub="$(<"$ROOT_DIR/stubs/deploy.php.stub")"
instructions_stub="$(<"$ROOT_DIR/stubs/scripts/steps/10-deployer-instructions.sh")"
common_stub="$(<"$ROOT_DIR/stubs/scripts/lib/common.sh")"

[[ "$prompts_text" == *'use function Laravel\Prompts\text;'* ]]
[[ "$prompts_text" == *"'Server IP address'"* ]]
[[ "$prompts_text" == *"default: \$suggestedSiteId ?? ''"* ]]
[[ "$prompts_text" != *"'Git SSH deployer name'"* ]]
[[ "$prompts_text" == *"'__GIT_DEPLOYER_NAME__' => 'git-'.\$siteId"* ]]
[[ "$prompts_text" == *'use function Laravel\Prompts\multiselect;'* ]]
[[ "$prompts_text" == *'use function Laravel\Prompts\select;'* ]]
[[ "$prompts_text" == *'Worker mode'* ]]
[[ "$command_text" == *"metator/steps"* ]]
[[ "$writer_text" == *".metator-manifest.json"* ]]
[[ "$prompts_text" != *github-deployer* ]]
[[ "$deploy_stub" == *"\$site['ssh']['host']"* ]]
[[ "$deploy_stub" == *"'git-'.\$siteId"* ]]
[[ "$deploy_stub" == *"set('worker_type', \$workerType);"* ]]
[[ "$deploy_stub" == *"set('writable_dirs', ['shared/storage']);"* ]]
[[ "$deploy_stub" == *"artisan horizon:terminate"* ]]
[[ "$deploy_stub" == *"supervisorctl restart {{application}}-worker:*"* ]]
[[ "$deploy_stub" == *"function () use (\$workerType)"* ]]
[[ "$deploy_stub" == *"deploy:verify-workers"* ]]
[[ "$instructions_stub" == *'deploy.php already terminates Horizon'* ]]
[[ "$instructions_stub" != *'Deploy with WORKER_TYPE=queue'* ]]
[[ "$common_stub" == *"__GIT_DEPLOYER_NAME__"* ]]
[[ "$(<"$ROOT_DIR/stubs/scripts/steps/03-github-key.sh")" == *'Deployment key already exists'* ]]
[[ "$prompts_text" == *".env.example"* ]]
[[ "$command_text" == *'Missing application .env.example'* ]]
deploy_stub_text="$(<"$ROOT_DIR/stubs/deploy.php.stub")"
workers_stub="$(<"$ROOT_DIR/stubs/scripts/steps/09-workers.sh")"
permissions_stub="$(<"$ROOT_DIR/stubs/scripts/steps/06-permissions.sh")"
[[ "$common_stub" == *'while IFS= read -r line || [[ -n "$line" ]]'* ]]
[[ "$common_stub" != *'sed -i "s|^${key}=.*'* ]]
[[ "$workers_stub" == *'--timeout=60'* ]]
[[ "$workers_stub" == *'autostart=false'* ]]
[[ "$workers_stub" == *'supervisorctl -c /etc/supervisor/supervisord.conf reread'* ]]
[[ "$workers_stub" == *'SUPERVISOR_SUDOERS_FILE'* ]]
[[ "$permissions_stub" == *'mode=2770'* ]]
[[ "$permissions_stub" == *'mode=660'* ]]
[[ "$deploy_stub_text" == *"task('deploy:activate-workers'"* ]]
[[ "$deploy_stub_text" == *"after('deploy:symlink', 'deploy:activate-workers')"* ]]
[[ "$(<"$ROOT_DIR/stubs/scripts/steps/07-caddy.sh")" == *'# @group: web-server'* ]]
[[ "$common_stub" == *'run_selected_steps'* ]]
[[ "$catalogue_text" == *"metadata['required'] === 'true'"* ]]
[[ "$catalogue_text" == *'normalizedIds'* ]]
[[ "$common_stub" == *'validate_step_metadata'* ]]
[[ "$common_stub" == *'validate_step_functions'* ]]
[[ "$(<"$ROOT_DIR/stubs/scripts/steps/02-cloudflare.sh")" == *'step_cloudflare()'* ]]
[[ "$(<"$ROOT_DIR/stubs/scripts/steps/04-shared-env.sh")" == *'step_shared_env()'* ]]
[[ "$(<"$ROOT_DIR/stubs/scripts/steps/01-prerequisites.sh")" != *'php composer caddy git'* ]]
[[ "$(<"$ROOT_DIR/stubs/scripts/steps/01-prerequisites.sh")" == *'require_commands curl jq'* ]]
[[ "$common_stub" == *'prepare_deploy_user'* ]]
[[ "$(<"$ROOT_DIR/stubs/scripts/server-bootstrap.sh")" == *"PHP_VERSION='__PHP_VERSION__'"* ]]

printf '%s\n' 'Install prompt checks passed.'
