#!/usr/bin/env bash
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
step_optional() { return 37; }
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
[[ "$(<"$output_file")" == *'after-ran'* ]]

printf '%s\n' 'Step runner checks passed.'
