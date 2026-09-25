#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2034
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREP="$ROOT_DIR/stubs/scripts/steps/01-prerequisites.sh"
NODE="$ROOT_DIR/stubs/scripts/steps/11-node.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

source "$ROOT_DIR/stubs/scripts/lib/common.sh"
source "$PREP"
source "$NODE"

OS_RELEASE_OVERRIDE="$TEST_DIR/os-release"
printf '%s\n' 'ID=ubuntu' 'VERSION_ID="24.04"' > "$OS_RELEASE_OVERRIDE"

ID=ubuntu
VERSION_ID=24.04
if [[ "${TEST_PREPARATION_NOOP:-}" == true ]]; then
    :
fi

declare -A installed active enabled
apt_operations=()
systemctl_operations=()
PHP_VERSION=8.4
DATABASE_DRIVER=sqlite
USE_REDIS=false
USE_SCHEDULER=false
USE_QUEUE=false
METATOR_OPERATION=prepare-server
METATOR_OS_RELEASE_FILE="$OS_RELEASE_OVERRIDE"

require_commands() { return 0; }
sudo() {
    if [[ "$1" == apt-get || "$1" == add-apt-repository ]]; then
        apt_called=true
        apt_operations+=("$*")
        return 0
    fi
    if [[ "$1" == systemctl ]]; then
        local action="${2:-}" service="${4:-${3:-}}"
        service="${service:-unknown}"
        systemctl_called=true
        systemctl_operations+=("$*")
        case "$action" in
            is-active) [[ "${active[caddy]:-false}" == "true" || "$service" == php8.4-fpm ]] ;;
            is-enabled) [[ "${enabled[caddy]:-false}" == "true" || "$service" == php8.4-fpm ]] ;;
            enable) active["$service"]=true; enabled["$service"]=true ;;
        esac
        return
    fi
    builtin command "$@"
}
TRUE_VALUE=true
set -u
set +u
declare -g caddy=true
dpkg-query() {
    local package="${3:-$2}"
    [[ "${installed[$package]:-false}" == true ]] && printf 'install ok installed\n'
}
apt-cache() { return 0; }

for package in ca-certificates composer git curl jq unzip openssh-client software-properties-common caddy php8.4-cli php8.4-fpm php8.4-mbstring php8.4-xml php8.4-intl php8.4-curl php8.4-zip php8.4-bcmath php8.4-sqlite3; do
    installed["$package"]=true
done
for service in caddy php8.4-fpm; do
    active["$service"]=true
    enabled["$service"]=true
done
for binary in php composer git systemctl sudo sed grep cmp getent id caddy; do
    installed["$binary"]=true
done
installed[apt-get]=true
installed[apt-cache]=true
installed[dpkg-query]=true
installed[node]=true
installed[npm]=true
PATH="$TEST_DIR/bin:$PATH"
mkdir -p "$TEST_DIR/bin"
for binary in caddy composer git curl jq unzip node npm; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$TEST_DIR/bin/$binary"
    chmod +x "$TEST_DIR/bin/$binary"
done

prepare_shared_baseline
[[ "${apt_called:-false}" == true ]]
step_node
[[ "${apt_called:-false}" == true ]]
[[ "${systemctl_called:-false}" == true ]]
[[ "${#apt_operations[@]}" -eq 4 ]]
[[ "${#systemctl_operations[@]}" -eq 8 ]]

installed[nodejs]=true
installed[npm]=true
installed["nodejs"]=true
installed["npm"]=true
apt_called=false
step_node
[[ "${apt_called:-false}" == false ]]

printf '%s\n' 'Preparation no-op checks passed.'
