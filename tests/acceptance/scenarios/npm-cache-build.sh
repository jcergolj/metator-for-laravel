#!/usr/bin/env bash
# Run directly as root on a disposable Ubuntu 24.04 host/root filesystem.
# This tests the Node provisioning step and real Deployer build, not the full VPS gate.
# shellcheck disable=SC1091,SC2024,SC2034
set -Eeuo pipefail

: "${METATOR_ACCEPTANCE_DISPOSABLE:?Set to true only in a disposable Ubuntu environment}"
[[ "$METATOR_ACCEPTANCE_DISPOSABLE" == true && "$EUID" == 0 ]]
source /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 24.04 ]]
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DEPLOYER="${METATOR_TEST_DEPLOYER:-$ROOT_DIR/vendor/bin/dep}"
[[ -x "$DEPLOYER" ]]
WORK_DIR="$(mktemp -d)"
chmod 755 "$WORK_DIR"
source "$ROOT_DIR/stubs/scripts/lib/common.sh"
source "$ROOT_DIR/stubs/scripts/steps/11-node.sh"
DEPLOY_USER="npm-proof-$$"
first_site="npm-first-$$"
second_site="npm-second-$$"
home="/home/$DEPLOY_USER"
cleanup() {
    rm -rf "$WORK_DIR" "/var/www/$first_site" "/var/www/$second_site" "$home"
    userdel "$DEPLOY_USER"
}
useradd --no-create-home --home-dir "$home" --shell /bin/bash "$DEPLOY_USER"
trap cleanup EXIT
install -d -o root -g root -m 755 "$home"
prepare_deploy_user
METATOR_OPERATION=provision
PHP_VERSION=8.5
DATABASE_DRIVER=sqlite
GITHUB_REPOSITORY=example/npm-fixture
SITE_ID="$first_site"
APP_FOLDER="/var/www/$SITE_ID"
claim_application_folder
step_node
cache="$APP_FOLDER/shared/.npm"
release="$APP_FOLDER/releases/1"
install -d -o "$DEPLOY_USER" -g www-data -m 755 "$release"

cat > "$WORK_DIR/package.json" <<'JSON'
{"name":"metator-vite-proof","private":true,"version":"1.0.0","type":"module","scripts":{"build":"vite build"},"devDependencies":{"vite":"5.4.21"}}
JSON
printf '<html><script type="module" src="/main.js"></script></html>\n' > "$WORK_DIR/index.html"
printf 'document.body.append("Metator npm cache proof");\n' > "$WORK_DIR/main.js"
npm install --prefix "$WORK_DIR" --package-lock-only --ignore-scripts --no-audit --no-fund --cache="$WORK_DIR/lock-cache"
cp "$WORK_DIR"/{package.json,package-lock.json,index.html,main.js} "$release/"
chown -R "$DEPLOY_USER:www-data" "$release"
php /dev/stdin "$ROOT_DIR" "$WORK_DIR" "$first_site" <<'PHP'
<?php
[$script, $root, $directory, $siteId] = $argv;
$site = [
    'site_id' => $siteId,
    'php_version' => '8.5',
    'database' => 'sqlite',
    'repository' => 'example/npm-fixture',
    'ssh' => ['host' => '127.0.0.1'],
    'node' => true,
];
file_put_contents($directory.'/site.php', '<?php return '.var_export($site, true).';');
$recipe = str_replace(['__CONFIG_FILE__', '__BRANCH__'], ['site.php', 'main'], file_get_contents($root.'/stubs/deploy.php.stub'));
$recipe .= <<<'RECIPE'

localhost('proof')->setDeployPath('/var/www/'.$siteId)->set('release_path', '/var/www/'.$siteId.'/releases/1');
task('acceptance:build-assets', function (): void {
    run('test "$(npm config get cache)" = "{{deploy_path}}/shared/.npm"');
    run('cd {{release_path}} && npm ci --include=dev --no-audit --no-fund');
    run('cd {{release_path}} && npm run build');
});
RECIPE;
file_put_contents($directory.'/deploy.php', $recipe);
PHP
sudo -u "$DEPLOY_USER" "$DEPLOYER" acceptance:build-assets proof --file="$WORK_DIR/deploy.php" --no-interaction -v
[[ -s "$release/dist/index.html" && ! -e "$home/.npm" ]]
[[ "$(stat -c '%u:%g:%a' "$home")" == 0:0:755 ]]

snapshot() {
    find -P "$1" -mindepth 1 -printf '%p %U:%G %m %T@ %C@ %l\n' | sort
    find -P "$1" -type f -exec sha256sum {} + | sort
}
before="$(snapshot "$cache")"
step_node
[[ "$(snapshot "$cache")" == "$before" ]]
SITE_ID="$second_site"
APP_FOLDER="/var/www/$SITE_ID"
claim_application_folder
step_node
[[ "$(snapshot "$cache")" == "$before" ]]
APP_FOLDER="/var/www/$first_site"
chmod 000 "$cache/_cacache"
if step_node > "$WORK_DIR/failure.log" 2>&1; then
    printf 'FAIL unusable cache passed readiness\n' >&2
    exit 1
fi
grep -q 'Site npm cache is not usable' "$WORK_DIR/failure.log"
printf 'Ubuntu: %s\n' "$PRETTY_NAME"
node --version
npm --version
"$DEPLOYER" --version
printf 'PASS real npm ci/Vite build, root-owned home, unchanged cache rerun, second site, and failed readiness\n'
