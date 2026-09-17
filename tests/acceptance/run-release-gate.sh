#!/usr/bin/env bash
set -Eeuo pipefail

# The provider creates a disposable Ubuntu VM/VPS and prints shell assignments:
# host, user, identity, and target_id. The scenario command owns the Laravel
# fixture and must exercise provisioning and a separate Deployer invocation.
: "${METATOR_ACCEPTANCE_CREATE:?Set METATOR_ACCEPTANCE_CREATE to a provider command}"
: "${METATOR_ACCEPTANCE_SCENARIO:?Set METATOR_ACCEPTANCE_SCENARIO to the release-gate scenario command}"
: "${METATOR_ACCEPTANCE_DESTROY:?Set METATOR_ACCEPTANCE_DESTROY to the provider cleanup command}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE_DIR="${METATOR_ACCEPTANCE_EVIDENCE_DIR:-$ROOT_DIR/artifacts/release-gate}"
mkdir -p "$EVIDENCE_DIR"
target_file="$(mktemp)"
cleanup() {
    local status=$?
    if [[ -s "$target_file" ]]; then
        # shellcheck disable=SC1090
        source "$target_file"
        "$METATOR_ACCEPTANCE_DESTROY" "${target_id:?}" || status=$?
    fi
    rm -f "$target_file"
    return "$status"
}
trap cleanup EXIT

"$METATOR_ACCEPTANCE_CREATE" > "$target_file"
# shellcheck disable=SC1090
source "$target_file"
: "${host:?Provider output must define host}"
: "${user:?Provider output must define user}"
: "${identity:?Provider output must define identity}"
: "${target_id:?Provider output must define target_id}"

ssh_options=(-o BatchMode=yes -o StrictHostKeyChecking=yes -i "$identity")
ssh "${ssh_options[@]}" "$user@$host" 'test "$(. /etc/os-release && printf %s "$VERSION_ID")" = 24.04'
ssh "${ssh_options[@]}" "$user@$host" 'command -v php && command -v composer && command -v git && command -v sudo && command -v systemctl'
{
    printf 'target_id=%s\n' "$target_id"
    ssh "${ssh_options[@]}" "$user@$host" 'date -u +%FT%TZ; . /etc/os-release; printf "ubuntu=%s\n" "$PRETTY_NAME"; php -v | sed -n "1p"; systemctl --version | sed -n "1p"'
} > "$EVIDENCE_DIR/target.txt"

METATOR_ACCEPTANCE_HOST="$host" \
METATOR_ACCEPTANCE_USER="$user" \
METATOR_ACCEPTANCE_IDENTITY="$identity" \
METATOR_ACCEPTANCE_EVIDENCE_DIR="$EVIDENCE_DIR" \
    "$METATOR_ACCEPTANCE_SCENARIO"

printf 'Release-gate evidence: %s\n' "$EVIDENCE_DIR"
