#!/usr/bin/env bash
# Exercise npm and real filesystem permissions with a non-writable deployment home.
# shellcheck disable=SC1091,SC2024,SC2034
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$EUID" != 0 ]]; then
    if sudo -n true 2>/dev/null; then
        exec sudo -n env PATH="$PATH" bash "$0"
    fi
    exec unshare --user --map-auto --map-root-user --mount bash "$0"
fi

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/metator-npm.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
chmod 755 "$TEST_DIR"
# Locally managed Node installations may live below a private operator home.
mkdir -p "$TEST_DIR/bin" "$TEST_DIR/home" "$TEST_DIR/tools"
cp "$(command -v node)" "$TEST_DIR/bin/node"
cp -R "$(dirname "$(dirname "$(readlink -f "$(command -v npm)")")")" "$TEST_DIR/tools/npm"
ln -s ../tools/npm/bin/npm-cli.js "$TEST_DIR/bin/npm"
export PATH="$TEST_DIR/bin:$PATH"
export HOME="$TEST_DIR/home"
chmod 755 "$HOME"
DEPLOY_USER=nobody
deploy_uid="$(id -u "$DEPLOY_USER")"
deploy_gid="$(id -g "$DEPLOY_USER")"
sudo() {
    if [[ "$1" == -u ]]; then
        shift 2
        setpriv --reuid="$deploy_uid" --regid="$deploy_gid" --clear-groups -- "$@"
    else
        command "$@"
    fi
}

source "$ROOT_DIR/stubs/scripts/lib/common.sh"
source "$ROOT_DIR/stubs/scripts/steps/11-node.sh"
DEPLOY_USER=nobody
METATOR_OPERATION=provision
APP_FOLDER="$TEST_DIR/site-one"
mkdir -p "$APP_FOLDER/shared" "$TEST_DIR/package" "$APP_FOLDER/release"
printf '{"name":"cache-fixture","version":"1.0.0"}\n' > "$TEST_DIR/package/package.json"
tar -czf "$TEST_DIR/fixture.tgz" -C "$TEST_DIR" package
printf '{"name":"build-fixture","version":"1.0.0","dependencies":{"cache-fixture":"file:../../fixture.tgz"}}\n' > "$APP_FOLDER/release/package.json"
chown -R "$deploy_uid:$deploy_gid" "$APP_FOLDER"

# Confirm the reported failure, independent of npm's network or registry state.
if sudo -u "$DEPLOY_USER" npm --cache="$HOME/.npm" cache add "$TEST_DIR/fixture.tgz" > "$TEST_DIR/default.log" 2>&1; then
    printf 'FAIL npm unexpectedly used the non-writable home cache\n' >&2
    exit 1
fi
grep -q EACCES "$TEST_DIR/default.log"

step_node
cache="$APP_FOLDER/shared/.npm"
if ! sudo -u "$DEPLOY_USER" test -d "$cache"; then
    printf 'FAIL provisioning did not create a site-scoped npm cache (default cache fails with EACCES)\n' >&2
    exit 1
fi
if ! sudo -u "$DEPLOY_USER" env npm_config_cache="$cache" npm install \
    --prefix "$APP_FOLDER/release" --ignore-scripts --no-audit --no-fund > "$TEST_DIR/install.log" 2>&1; then
    cat "$TEST_DIR/install.log" >&2
    exit 1
fi
[[ ! -e "$HOME/.npm" ]]
[[ "$(stat -c '%u:%a' "$HOME")" == 0:755 ]]

# npm may store immutable content files read-only; writable parent directories
# allow npm to replace/remove them without changing existing file permissions.
sudo -u "$DEPLOY_USER" bash -c 'printf "immutable cache data\n" > "$1/content-fixture"; chmod 444 "$1/content-fixture"' _ "$cache/_cacache"

snapshot() {
    find -P "$1" -printf '%p %U:%G %m %T@ %C@ %l\n' | sort
    find -P "$1" -type f -exec sha256sum {} + | sort
}
cached_before="$(snapshot "$cache/_cacache")"
home_before="$(snapshot "$HOME")"
cache_owner="$(stat -c '%u:%g:%a' "$cache")"
step_node | tee "$TEST_DIR/rerun.log"
grep -q 'Site npm cache is unchanged and ready' "$TEST_DIR/rerun.log"
[[ "$(snapshot "$cache/_cacache")" == "$cached_before" ]]
[[ "$(stat -c '%u:%g:%a' "$cache")" == "$cache_owner" ]]
[[ -z "$(find "$cache" -name '.metator-npm.*' -print)" ]]

# Adding a second site cannot touch the first site's cache or environment.
printf 'APP_KEY=preserved\n' > "$APP_FOLDER/shared/.env"
first_before="$(snapshot "$APP_FOLDER")"
APP_FOLDER="$TEST_DIR/site-two"
mkdir -p "$APP_FOLDER/shared"
chown -R "$deploy_uid:$deploy_gid" "$APP_FOLDER"
step_node
[[ -d "$APP_FOLDER/shared/.npm" ]]
[[ "$(snapshot "$TEST_DIR/site-one")" == "$first_before" ]]

# An unreadable cache entry is a readiness failure, never recursively repaired.
printf 'private\n' > "$cache/_cacache/unusable"
chmod 600 "$cache/_cacache/unusable"
before="$(snapshot "$cache")"
APP_FOLDER="$TEST_DIR/site-one"
if step_node > "$TEST_DIR/failure.log" 2>&1; then
    printf 'FAIL inaccessible cache was reported as ready\n' >&2
    exit 1
fi
grep -q 'Site npm cache is not usable by nobody' "$TEST_DIR/failure.log"
[[ "$(snapshot "$cache")" == "$before" ]]
rm "$cache/_cacache/unusable"

# Do not follow a cache symlink into another site's working cache.
mv "$cache" "$APP_FOLDER/shared/saved-cache"
ln -s "$TEST_DIR/site-two/shared/.npm" "$cache"
other_before="$(snapshot "$TEST_DIR/site-two")"
if step_node > "$TEST_DIR/symlink.log" 2>&1; then
    printf 'FAIL cache symlink was accepted\n' >&2
    exit 1
fi
grep -q 'must be a real directory' "$TEST_DIR/symlink.log"
[[ "$(snapshot "$TEST_DIR/site-two")" == "$other_before" ]]
[[ "$(snapshot "$HOME")" == "$home_before" ]]
printf '%s\n' 'Site-scoped npm cache works with a root-owned deployment home.'
