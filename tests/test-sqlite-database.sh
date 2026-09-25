#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin"

cat > "$TEST_DIR/bin/php-probe" <<'EOF'
#!/usr/bin/env bash
[[ "$#" == 1 && "$1" == -m ]]
printf '%s\n' '[PHP Modules]' PDO pdo_sqlite
for ((module = 0; module < 20000; module++)); do
    printf 'extension_%s\n' "$module"
done
EOF
cat > "$TEST_DIR/bin/sqlite3" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TEST_DIR/bin/php-probe" "$TEST_DIR/bin/sqlite3"

source "$ROOT_DIR/stubs/scripts/lib/common.sh"
source "$ROOT_DIR/stubs/scripts/steps/05-database.sh"

sudo() {
    local executable="$1"
    shift
    local -a arguments=()
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -o|-g) shift 2 ;;
            *) arguments+=("$1"); shift ;;
        esac
    done
    command "$executable" "${arguments[@]}"
}
ok() { printf '%s\n' "$*"; }
die() { printf '%s\n' "$*" >&2; }
ensure_database_config() { return 0; }

SITE_ID=sqlite-probe
APP_FOLDER="$TEST_DIR/site"
DEPLOY_USER=deployer
DATABASE_DRIVER=sqlite
PHP_VERSION=8.5
PHP_PACKAGE_PREFIX="$TEST_DIR/bin/php-probe"

step_database
[[ -f "$APP_FOLDER/shared/database/database.sqlite" ]]

printf '%s\n' 'SQLite database checks passed.'
