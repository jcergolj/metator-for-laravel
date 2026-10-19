#!/usr/bin/env bash
# Real filesystem permissions, not mocked chmod/ACL/identity checks.
# shellcheck disable=SC1091,SC2034
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$EUID" != 0 ]]; then
    if sudo -n true 2>/dev/null; then
        exec sudo -n bash "$0"
    fi
    exec unshare --user --map-auto --map-root-user --mount bash "$0" --namespace
fi

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/metator-permissions.XXXXXX")"
cleanup() {
    if [[ "${1:-}" == namespace ]]; then
        umount /etc/passwd /etc/group
    fi
    rm -rf "$TEST_DIR"
}
trap 'cleanup "${namespace:-}"' EXIT
if [[ "${1:-}" == --namespace ]]; then
    # NSS changes exist only in this private mount namespace, never on the host.
    namespace=namespace
    cp /etc/passwd "$TEST_DIR/passwd"
    cp /etc/group "$TEST_DIR/group"
    if ! id www-data >/dev/null 2>&1; then
        printf 'www-data:x:60001:60001::/:/bin/false\n' >> "$TEST_DIR/passwd"
    fi
    if ! getent group www-data >/dev/null; then
        printf 'www-data:x:60001:\n' >> "$TEST_DIR/group"
    fi
    mount --bind "$TEST_DIR/passwd" /etc/passwd
    mount --bind "$TEST_DIR/group" /etc/group
fi
chmod 755 "$TEST_DIR"

source "$ROOT_DIR/stubs/scripts/lib/common.sh"
source "$ROOT_DIR/stubs/scripts/steps/06-permissions.sh"
APP_FOLDER="$TEST_DIR/site-one"
DEPLOY_USER=nobody
runtime_uid="$(id -u www-data)"
runtime_gid="$(getent group www-data | cut -d: -f3)"
deploy_uid="$(id -u "$DEPLOY_USER")"
real_sudo() {
    if [[ "$1" == -u ]]; then
        local uid
        uid="$(id -u "$2")"
        shift 2
        # Both identities have the shared group, as prepare_deploy_user ensures.
        setpriv --reuid="$uid" --regid="$runtime_gid" --groups="$runtime_gid" -- "$@"
    else
        command "$@"
    fi
}
sudo() {
    if [[ "$1" == -u && "$2" == www-data ]]; then
        if [[ "${fail_runtime_probe:-false}" == true && "$3" == bash ]]; then return 1; fi
        if [[ "${fail_runtime_readiness:-false}" == true && "$3" == test ]]; then return 1; fi
    fi
    real_sudo "$@"
}

mkdir -p "$APP_FOLDER/shared/storage/logs" "$APP_FOLDER/shared/database" "$TEST_DIR/site-two/storage"
printf 'existing log contents\n' > "$APP_FOLDER/shared/storage/logs/laravel.log"
printf 'APP_KEY=preserved\n' > "$APP_FOLDER/shared/.env"
printf 'private secret\n' > "$APP_FOLDER/shared/private.key"
chmod 600 "$APP_FOLDER/shared/private.key"
printf 'database contents\n' > "$APP_FOLDER/shared/database/database.sqlite"
printf 'other site\n' > "$TEST_DIR/site-two/storage/other.log"
ln -s "$TEST_DIR/site-two/storage" "$APP_FOLDER/shared/storage/external-directory"
ln -s "$TEST_DIR/site-two/storage/other.log" "$APP_FOLDER/shared/storage/external-file"
chown "$runtime_uid:$runtime_gid" "$APP_FOLDER/shared/storage/logs/laravel.log"
chmod 644 "$APP_FOLDER/shared/storage/logs/laravel.log"
setfacl -d -m u::rwx,g::rwx,o::--- "$APP_FOLDER/shared"

snapshot() {
    find -P "$1" -printf '%p %U:%G %m %T@ %C@ %l\n' | sort
    getfacl -RcpP "$1"
    find -P "$1" -type f -exec sha256sum {} + | sort
}
other_before="$(snapshot "$TEST_DIR/site-two")"
secret_before="$(snapshot "$APP_FOLDER/shared/private.key")"
step_permissions
[[ "$(cat "$APP_FOLDER/shared/storage/logs/laravel.log")" == 'existing log contents' ]]
[[ "$(stat -c %u "$APP_FOLDER/shared/storage/logs/laravel.log")" == "$runtime_uid" ]]
for user in "$DEPLOY_USER" www-data; do
    sudo -u "$user" bash -c 'printf "repaired\n" >> "$1"' _ "$APP_FOLDER/shared/storage/logs/laravel.log"
done
[[ "$(stat -c %a "$APP_FOLDER/shared/.env")" == 640 ]]
sudo -u www-data test -r "$APP_FOLDER/shared/.env"
if sudo -u www-data test -w "$APP_FOLDER/shared/.env"; then
    printf 'FAIL runtime identity can write shared .env\n' >&2
    exit 1
fi
[[ "$(snapshot "$APP_FOLDER/shared/private.key")" == "$secret_before" ]]
[[ "$(snapshot "$TEST_DIR/site-two")" == "$other_before" ]]

sudo -u www-data bash -c 'umask 0022; printf "runtime\n" > "$1/new.log"' _ "$APP_FOLDER/shared/storage/logs"
if ! sudo -u "$DEPLOY_USER" bash -c 'printf "deployment\n" >> "$1/new.log"' _ "$APP_FOLDER/shared/storage/logs"; then
    printf 'FAIL deployment user cannot append to runtime-created log (umask 0022)\n' >&2
    exit 1
fi
for root in storage/logs bootstrap/cache database; do
    for creator in "$DEPLOY_USER" www-data; do
        if [[ "$creator" == "$DEPLOY_USER" ]]; then writer=www-data; else writer="$DEPLOY_USER"; fi
        sudo -u "$creator" bash -c '
            umask 0022
            mkdir -p "$1/$2/new/nested"
            printf "created\n" > "$1/$2/new/nested/rotated.log"
        ' _ "$APP_FOLDER/shared/$root" "$creator"
        sudo -u "$writer" bash -c 'printf "appended\n" >> "$1/$2/new/nested/rotated.log"' _ "$APP_FOLDER/shared/$root" "$creator"
        sudo -u "$creator" rm "$APP_FOLDER/shared/$root/$creator/new/nested/rotated.log"
        sudo -u "$writer" bash -c 'umask 0022; printf "recreated\n" > "$1/$2/new/nested/rotated.log"' _ "$APP_FOLDER/shared/$root" "$creator"
        sudo -u "$creator" bash -c 'printf "appended again\n" >> "$1/$2/new/nested/rotated.log"' _ "$APP_FOLDER/shared/$root" "$creator"
    done
done
before="$(snapshot "$APP_FOLDER/shared")"
step_permissions | tee "$TEST_DIR/rerun.log"
grep -q 'unchanged and ready' "$TEST_DIR/rerun.log"
[[ "$(snapshot "$APP_FOLDER/shared")" == "$before" ]]
[[ "$(snapshot "$TEST_DIR/site-two")" == "$other_before" ]]
[[ -z "$(find "$APP_FOLDER/shared" -name '.metator-permissions.*' -print)" ]]

# Even a failed create/append probe only removes its own unique directory.
mkdir "$APP_FOLDER/shared/storage/.metator-permissions.application"
printf 'preserved\n' > "$APP_FOLDER/shared/storage/.metator-permissions.application/log"
fail_runtime_probe=true
if verify_shared_runtime_writes "$APP_FOLDER/shared/storage" > "$TEST_DIR/probe-failure.log" 2>&1; then
    printf 'FAIL write probe failure was reported as success\n' >&2
    exit 1
fi
grep -q 'create/append verification failed' "$TEST_DIR/probe-failure.log"
[[ "$(cat "$APP_FOLDER/shared/storage/.metator-permissions.application/log")" == preserved ]]
[[ "$(find "$APP_FOLDER/shared/storage" -maxdepth 1 -name '.metator-permissions.*' | wc -l)" == 1 ]]
rm "$APP_FOLDER/shared/storage/.metator-permissions.application/log"
rmdir "$APP_FOLDER/shared/storage/.metator-permissions.application"
fail_runtime_probe=false
before="$(snapshot "$APP_FOLDER/shared")"

# Matching metadata cannot hide an identity/readiness failure.
fail_runtime_readiness=true
if step_permissions > "$TEST_DIR/failure.log" 2>&1; then
    printf 'FAIL readiness failure was reported as success\n' >&2
    exit 1
fi
grep -q 'Shared runtime access failed for www-data:' "$TEST_DIR/failure.log"
[[ "$(snapshot "$APP_FOLDER/shared")" == "$before" ]]

# Never follow a managed root symlink, even before creating required subpaths.
mv "$APP_FOLDER/shared/storage" "$APP_FOLDER/shared/old-storage"
ln -s "$TEST_DIR/site-two/storage" "$APP_FOLDER/shared/storage"
if step_permissions > "$TEST_DIR/symlink.log" 2>&1; then
    printf 'FAIL managed storage symlink was accepted\n' >&2
    exit 1
fi
grep -q 'must be a real directory' "$TEST_DIR/symlink.log"
[[ "$(snapshot "$TEST_DIR/site-two")" == "$other_before" ]]
printf '%s\n' 'Real cross-identity runtime permission checks passed.'
