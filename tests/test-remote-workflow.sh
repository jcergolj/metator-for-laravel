#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command_text="$(<"$ROOT_DIR/src/Commands/RunRemoteProvisioningCommand.php")"
prepare_text="$(<"$ROOT_DIR/src/Commands/PrepareServerCommand.php")"
runner_text="$(<"$ROOT_DIR/src/Remote/RemoteScriptRunner.php")"
provider_text="$(<"$ROOT_DIR/src/MetatorServiceProvider.php")"
bootstrap_text="$(<"$ROOT_DIR/stubs/scripts/server-bootstrap.sh")"
readme_text="$(<"$ROOT_DIR/README.md")"

[[ "$command_text" == *"metator:provision"* ]]
[[ "$command_text" == *"--config="* ]]
[[ "$command_text" == *'Choose exactly one site configuration'* ]]
[[ "$command_text" == *'Inspect the server before retrying'* ]]
[[ "$prepare_text" == *"metator:prepare-server"* ]]
[[ "$runner_text" == *"scp -q -o BatchMode=yes"* ]]
[[ "$runner_text" == *"sudo rm -rf"* ]]
[[ "$runner_text" == *"METATOR_OPERATION"* ]]
[[ "$runner_text" == *"proc_open"* ]]
[[ "$provider_text" == *'PrepareServerCommand::class'* ]]
[[ "$provider_text" == *'RunRemoteProvisioningCommand::class'* ]]
[[ "$bootstrap_text" == *"METATOR_OPERATION=\"\${METATOR_OPERATION:-provision}\""* ]]
[[ "$bootstrap_text" == *'prepare-server|provision)'* ]]
[[ "$bootstrap_text" == *"METATOR_OPERATION"* ]]
[[ "$readme_text" == *'metator:prepare-server --config=metator.production.php'* ]]
[[ "$readme_text" == *'Provisioning does not run Deployer'* ]]

printf '%s\n' 'Remote workflow checks passed.'
