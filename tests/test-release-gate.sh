#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner_text="$(<"$ROOT_DIR/tests/acceptance/run-release-gate.sh")"

[[ "$runner_text" == *'METATOR_ACCEPTANCE_CREATE'* ]]
[[ "$runner_text" == *'METATOR_ACCEPTANCE_SCENARIO'* ]]
[[ "$runner_text" == *'METATOR_ACCEPTANCE_DESTROY'* ]]
[[ "$runner_text" == *'METATOR_ACCEPTANCE_UBUNTU_RELEASES'* ]]
[[ "$runner_text" == *'METATOR_ACCEPTANCE_UBUNTU_RELEASE'* ]]
[[ "$runner_text" == *'24.04|'* ]]
[[ "$runner_text" == *'|26.04)'* ]]
[[ "$runner_text" == *'requested_release='* ]]
[[ "$runner_text" == *"ubuntu-\${release}"* ]]
[[ "$runner_text" == *'trap cleanup EXIT'* ]]
[[ "$runner_text" == *'Release-gate evidence'* ]]

printf '%s\n' 'Release gate checks passed.'
