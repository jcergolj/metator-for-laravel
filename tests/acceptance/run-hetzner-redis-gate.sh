#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${HCLOUD_TOKEN:?Set HCLOUD_TOKEN for the Hetzner API}"

if [[ -z "${GH_TOKEN:-}" ]]; then
    GH_TOKEN="$(gh auth token)"
    export GH_TOKEN
fi

ACCEPTANCE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/metator-redis-home.XXXXXX")"
umask 077
cleanup() {
    local status=$?
    trap - EXIT INT TERM
    if [[ "$status" -eq 0 ]]; then
        rm -rf "$ACCEPTANCE_HOME"
    else
        printf 'Acceptance state and SSH key retained for cleanup: %s\n' "$ACCEPTANCE_HOME" >&2
    fi
    exit "$status"
}
trap cleanup EXIT INT TERM
mkdir -p "$ACCEPTANCE_HOME/.ssh"
mkdir -p "$ACCEPTANCE_HOME/bin"
ssh_binary="$(command -v ssh)"
scp_binary="$(command -v scp)"
cat > "$ACCEPTANCE_HOME/bin/ssh" <<EOF
#!/usr/bin/env bash
exec "$ssh_binary" -F /dev/null -i "\$HOME/.ssh/id_ed25519" -o IdentitiesOnly=yes -o "UserKnownHostsFile=\$HOME/.ssh/known_hosts" -o GlobalKnownHostsFile=/dev/null "\$@"
EOF
cat > "$ACCEPTANCE_HOME/bin/scp" <<EOF
#!/usr/bin/env bash
exec "$scp_binary" -F /dev/null -i "\$HOME/.ssh/id_ed25519" -o IdentitiesOnly=yes -o "UserKnownHostsFile=\$HOME/.ssh/known_hosts" -o GlobalKnownHostsFile=/dev/null "\$@"
EOF
chmod 700 "$ACCEPTANCE_HOME/bin/ssh" "$ACCEPTANCE_HOME/bin/scp"
export HOME="$ACCEPTANCE_HOME"
export PATH="$ACCEPTANCE_HOME/bin:$PATH"
export METATOR_ACCEPTANCE_STATE_DIR="$ACCEPTANCE_HOME/state"
export METATOR_ACCEPTANCE_CREATE="$ROOT_DIR/tests/acceptance/providers/hetzner/create.sh"
export METATOR_ACCEPTANCE_SCENARIO="$ROOT_DIR/tests/acceptance/scenarios/redis-site-isolation.sh"
export METATOR_ACCEPTANCE_DESTROY="$ROOT_DIR/tests/acceptance/providers/hetzner/destroy.sh"
export METATOR_ACCEPTANCE_UBUNTU_RELEASES="${METATOR_ACCEPTANCE_UBUNTU_RELEASES:-24.04}"
export METATOR_ACCEPTANCE_EVIDENCE_DIR="${METATOR_ACCEPTANCE_EVIDENCE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/metator-redis-evidence.XXXXXX")}"

bash "$ROOT_DIR/tests/acceptance/run-release-gate.sh"
