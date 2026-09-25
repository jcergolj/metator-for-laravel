#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2034
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/steps"
cat > "$TEST_DIR/steps/10-required.sh" <<'EOF'
# @id: required
# @title: Required step
# @group: none
# @required: true
# @default: true
# @order: 10
step_required() { return 0; }
EOF
cat > "$TEST_DIR/steps/20-optional.sh" <<'EOF'
# @id: optional
# @title: Optional step
# @group: none
# @required: false
# @default: true
# @order: 20
step_optional() {
    if [[ -f "$TEST_DIR/retry" ]]; then
        return 0
    fi
    return 37
}
EOF
cat > "$TEST_DIR/steps/30-after.sh" <<'EOF'
# @id: after
# @title: After step
# @group: none
# @required: false
# @default: true
# @order: 30
step_after() { printf 'after-ran\n'; }
EOF
SCRIPT_DIR="$TEST_DIR"
METATOR_OPERATION=provision
source "$ROOT_DIR/stubs/scripts/lib/common.sh"
for step_file in "$TEST_DIR"/steps/*.sh; do
    source "$step_file"
done
output_file="$TEST_DIR/output"
status=0
run_selected_steps >"$output_file" 2>&1 || status=$?
status="${status:-0}"
[[ "$status" == 37 ]]
[[ "${STEP_FAILED[*]}" == *'Optional step (exit status 37)'* ]]
[[ "$(<"$output_file")" != *'after-ran'* ]]

# Rerun the same selected custom step after correcting its failure condition.
touch "$TEST_DIR/retry"
STEP_SUCCESSFUL=()
STEP_FAILED=()
status=0
run_selected_steps >"$output_file" 2>&1 || status=$?
[[ "$status" == 0 ]]
[[ "${#STEP_FAILED[@]}" == 0 ]]
[[ "$(<"$output_file")" == *'after-ran'* ]]

SCRIPT_DIR="$TEST_DIR"
METATOR_OPERATION=prepare-server
STEP_SUCCESSFUL=()
STEP_FAILED=()
STEP_SKIPPED=()
step_number=0
status=0
run_selected_steps >/dev/null 2>&1 || status=$?
[[ "$status" == 0 ]]
print_step_summary >"$output_file"
[[ "$(<"$output_file")" != *'Skipped:'* ]]

STEP_SUCCESSFUL=('STEP 1 - Required step')
STEP_FAILED=('STEP 3 - Failed step (exit status 1)')
STEP_SKIPPED=('STEP 2 - Optional step')
print_step_summary >"$output_file"
[[ "$(<"$output_file")" == *'Skipped:'* ]]

# Preparation executes its baseline and optional Node capability only.
cat > "$TEST_DIR/steps/01-prerequisites.sh" <<'EOF'
# @id: prerequisites
# @title: Baseline
# @required: true
# @order: 1
EOF
cat > "$TEST_DIR/steps/02-node.sh" <<'EOF'
# @id: node
# @title: Node
# @required: false
# @order: 2
EOF
step_prerequisites() { printf 'baseline-ran\n'; }
step_node() { printf 'node-ran\n'; }
STEP_FAILED=()
STEP_SUCCESSFUL=()
STEP_SKIPPED=()
run_selected_steps >"$output_file"
[[ "$(<"$output_file")" == *baseline-ran* ]]
[[ "$(<"$output_file")" == *node-ran* ]]
[[ "$(<"$output_file")" != *Skipped:* ]]
[[ "${#STEP_SUCCESSFUL[@]}" == 2 ]]

step_registration() { return 75; }
status=0
run_step 'GitHub registration' 'Register key' step_registration >"$output_file" || status=$?
[[ "$status" == 75 ]]
[[ "${#STEP_FAILED[@]}" == 0 ]]
[[ "$(<"$output_file")" == *'Waiting for local confirmation'* ]]

printf '%s\n' 'Step runner checks passed.'
