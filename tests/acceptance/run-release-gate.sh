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
RELEASES=(24.04 26.04)
if [[ -n "${METATOR_ACCEPTANCE_UBUNTU_RELEASES:-}" ]]; then
    read -r -a RELEASES <<< "$METATOR_ACCEPTANCE_UBUNTU_RELEASES"
fi
if [[ "${#RELEASES[@]}" -eq 0 ]]; then
    printf 'At least one Ubuntu release is required\n' >&2
    exit 1
fi

run_release() (
    local release="$1"
    local target_id=''
    case "$release" in
        24.04|26.04) ;;
        *) printf 'Unsupported Ubuntu release: %s\n' "$release" >&2; exit 1 ;;
    esac

    local release_evidence="$EVIDENCE_DIR/ubuntu-${release}"
    local target_file
    mkdir -p "$release_evidence"
    target_file="$(mktemp)"
    cleanup() {
        local status=$?
        local destroy_status=0
        if [[ -n "$target_id" ]]; then
            "$METATOR_ACCEPTANCE_DESTROY" "$target_id" || destroy_status=$?
        fi
        rm -f "$target_file"
        if [[ "$status" -eq 0 ]]; then
            status="$destroy_status"
        fi
        exit "$status"
    }
    trap cleanup EXIT

    METATOR_ACCEPTANCE_UBUNTU_RELEASE="$release" \
        "$METATOR_ACCEPTANCE_CREATE" > "$target_file"
    # shellcheck disable=SC1090
    source "$target_file"
    : "${host:?Provider output must define host}"
    : "${user:?Provider output must define user}"
    : "${identity:?Provider output must define identity}"
    : "${target_id:?Provider output must define target_id}"

    ssh_options=(-o BatchMode=yes -o StrictHostKeyChecking=yes -i "$identity")
    ssh "${ssh_options[@]}" "$user@$host" "test \"\$(. /etc/os-release && printf %s \"\$VERSION_ID\")\" = $release"
    ssh "${ssh_options[@]}" "$user@$host" 'command -v php && command -v composer && command -v git && command -v sudo && command -v systemctl'
    {
        printf 'requested_release=%s\n' "$release"
        printf 'target_id=%s\n' "$target_id"
        ssh "${ssh_options[@]}" "$user@$host" 'date -u +%FT%TZ; . /etc/os-release; printf "ubuntu=%s\n" "$PRETTY_NAME"; php -v | sed -n "1p"; systemctl --version | sed -n "1p"'
    } > "$release_evidence/target.txt"

    METATOR_ACCEPTANCE_HOST="$host" \
        METATOR_ACCEPTANCE_USER="$user" \
        METATOR_ACCEPTANCE_IDENTITY="$identity" \
        METATOR_ACCEPTANCE_UBUNTU_RELEASE="$release" \
        METATOR_ACCEPTANCE_EVIDENCE_DIR="$release_evidence" \
        "$METATOR_ACCEPTANCE_SCENARIO"
)

mkdir -p "$EVIDENCE_DIR"
for release in "${RELEASES[@]}"; do
    run_release "$release"
done

printf 'Release-gate evidence: %s\n' "$EVIDENCE_DIR"
