#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2034,SC2016
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/stubs/scripts/steps/02-deployer-login.sh"
CONFIGURE_DEPLOY_USER_LOGIN=true
DEPLOY_USER=deployer
SERVER_IP=example.test
CLIENT_PUBLIC_KEY='ssh-ed25519 AAAATEST operator key'
ensure_deploy_user_exists() { :; }
prompt_value() { printf 'Unexpected remote prompt\n' >&2; return 99; }
die() { printf '%s\n' "$*" >&2; return 1; }
ok() { :; }
sudo() {
    case "$1" in
        test|grep) return 1 ;;
        tee) local key; read -r key; [[ "$key" == "$CLIENT_PUBLIC_KEY" ]] ;;
        install|chown|chmod) return 0 ;;
        *) return 99 ;;
    esac
}
step_deployer_login </dev/null
CLIENT_PUBLIC_KEY=''
if step_deployer_login </dev/null >/dev/null 2>&1; then
    exit 1
fi

bootstrap="$(<"$ROOT_DIR/stubs/scripts/server-bootstrap.sh")"
runtime="${bootstrap#*PHP_VERSION=}"
runtime="PHP_VERSION=${runtime%%PHP_FPM_SERVICE=*}"
systemctl() { printf 'php8.4-fpm.service enabled\n'; }
METATOR_OPERATION=provision
for selected in 8.4 8.5; do
    generated="${runtime//__PHP_VERSION__/$selected}"
    eval "$generated"
    [[ "$PHP_VERSION" == "$selected" ]]
done
eval "$runtime"
[[ "$PHP_VERSION" == 8.4 ]]
printf 'Provision input checks passed.\n'
