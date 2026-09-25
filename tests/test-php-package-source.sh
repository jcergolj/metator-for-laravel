#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

source "$ROOT_DIR/stubs/scripts/lib/common.sh"
source "$ROOT_DIR/stubs/scripts/steps/01-prerequisites.sh"

METATOR_PHP_SURY_SOURCE_FILE="$TEST_DIR/sources.d/metator-php-sury.list"
METATOR_PHP_SURY_KEYRING_PATH="$TEST_DIR/keyrings/debsuryorg-archive-keyring.gpg"
COMMANDS="$TEST_DIR/commands"
mkdir -p "$(dirname "$METATOR_PHP_SURY_SOURCE_FILE")" "$(dirname "$METATOR_PHP_SURY_KEYRING_PATH")"
touch "$COMMANDS"
mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/add-apt-repository" <<'EOF'
#!/usr/bin/env bash
printf 'add-apt-repository %s\n' "$*" >> "$COMMANDS"
EOF
chmod +x "$TEST_DIR/bin/add-apt-repository"
cat > "$TEST_DIR/bin/dpkg" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TEST_DIR/bin/dpkg"
PATH="$TEST_DIR/bin:$PATH"
export COMMANDS PATH

curl() {
    local output=''
    printf 'curl %s\n' "$*" >> "$COMMANDS"
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --output) output="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    [[ -n "$output" ]]
    printf '%s\n' 'test archive keyring package' > "$output"
}

sudo() {
    local executable="$1"
    shift
    case "$executable" in
        test) command test "$@" ;;
        cmp) command cmp "$@" ;;
        dpkg)
            printf 'dpkg %s\n' "$*" >> "$COMMANDS"
            [[ "$1" == -i ]]
            touch "$METATOR_PHP_SURY_KEYRING_PATH" ;;
        add-apt-repository) command add-apt-repository "$@" ;;
        install)
            local arguments=()
            while [[ "$#" -gt 0 ]]; do
                case "$1" in
                    -m|-o|-g) shift 2 ;;
                    *) arguments+=("$1"); shift ;;
                esac
            done
            command install "${arguments[@]}" ;;
        apt-get)
            printf 'apt-get %s\n' "$*" >> "$COMMANDS" ;;
        *) printf 'Unexpected sudo command: %s\n' "$executable" >&2; return 1 ;;
    esac
}

os_release="$TEST_DIR/os-release"
printf 'ID=ubuntu\nVERSION_ID=26.04\nVERSION_CODENAME=resolute\n' > "$os_release"
PHP_VERSION=8.4
configure_php_package_source "$os_release"

expected_source="deb [signed-by=$METATOR_PHP_SURY_KEYRING_PATH] https://packages.sury.org/php/ resolute main"
[[ "$(<"$METATOR_PHP_SURY_SOURCE_FILE")" == "$expected_source" ]]
[[ -f "$METATOR_PHP_SURY_KEYRING_PATH" ]]
[[ "$(<"$COMMANDS")" == *'curl'* ]]
[[ "$(<"$COMMANDS")" == *'https://packages.sury.org/debsuryorg-archive-keyring.deb'* ]]
[[ "$(<"$COMMANDS")" == *'dpkg -i '* ]]
[[ "$(<"$COMMANDS")" == *'apt-get update'* ]]
[[ "$(<"$COMMANDS")" != *'ppa:ondrej/php'* ]]

# A conflicting source file is left untouched instead of being adopted.
printf 'deb https://example.test/php resolute main\n' > "$METATOR_PHP_SURY_SOURCE_FILE"
if configure_php_package_source "$os_release"; then
    printf 'Conflicting PHP source was accepted\n' >&2
    exit 1
fi
[[ "$(<"$METATOR_PHP_SURY_SOURCE_FILE")" == 'deb https://example.test/php resolute main' ]]

# Other Ubuntu releases retain the existing Ondřej PPA setup.
printf 'ID=ubuntu\nVERSION_ID=24.04\nVERSION_CODENAME=noble\n' > "$os_release"
PHP_VERSION=8.4
configure_php_package_source "$os_release"
[[ "$(<"$COMMANDS")" == *'add-apt-repository -y ppa:ondrej/php'* ]]

printf '%s\n' 'PHP package source selection checks passed.'
