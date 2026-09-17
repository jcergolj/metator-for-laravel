#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner_text="$(<"$ROOT_DIR/tests/acceptance/run-release-gate.sh")"
docs_text="$(<"$ROOT_DIR/docs/acceptance-release-gate.md")"

[[ "$runner_text" == *'METATOR_ACCEPTANCE_CREATE'* ]]
[[ "$runner_text" == *'METATOR_ACCEPTANCE_SCENARIO'* ]]
[[ "$runner_text" == *'METATOR_ACCEPTANCE_DESTROY'* ]]
[[ "$runner_text" == *'VERSION_ID")" = 24.04'* ]]
[[ "$runner_text" == *'trap cleanup EXIT'* ]]
[[ "$runner_text" == *'Release-gate evidence'* ]]
[[ "$docs_text" == *'metator:prepare-server'* ]]
[[ "$docs_text" == *'invoke Deployer separately'* ]]
[[ "$docs_text" == *'fifth-site'* ]]

printf '%s\n' 'Release gate checks passed.'
