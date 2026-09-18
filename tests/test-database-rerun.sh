#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
source "$ROOT_DIR/stubs/scripts/lib/common.sh"
source "$ROOT_DIR/stubs/scripts/steps/05-database.sh"

SITE_ID=site
APP_FOLDER="$TEST_DIR/site"
DEPLOY_USER=deployer
DATABASE_DRIVER=mysql
MYSQL_DATABASE=metator_site
MYSQL_USERNAME=metator_site
MYSQL_PASSWORD=secret
MYSQL_HOST=localhost
PHP_PACKAGE_PREFIX=php8.4
mkdir -p "$APP_FOLDER/shared"
printf '%s\n' 'site_id=site' > "$APP_FOLDER/.metator-site"

database_state="$TEST_DIR/database-state"
user_state="$TEST_DIR/user-state"
grant_state="$TEST_DIR/grant-state"
printf '%s\n' false > "$database_state"
printf '%s\n' false > "$user_state"
: > "$grant_state"
mutation_log="$TEST_DIR/mutations"
: > "$mutation_log"
ensure_database_config() { return 0; }
record_site_database() {
    if ! grep -q '^database_name=' "$APP_FOLDER/.metator-site"; then
        printf '%s\n' "database_name=$MYSQL_DATABASE" "database_user=$MYSQL_USERNAME" >> "$APP_FOLDER/.metator-site"
    fi
}
sudo() {
    if [[ "$1" == -u ]]; then
        return 0
    fi
    if [[ "$1" == mariadb ]]; then
        shift
        mariadb "$@"
    else
        command "$@"
    fi
}
# The sudo function above explicitly dispatches to this mock.
# shellcheck disable=SC2032
mariadb() {
        local query='' line
        if [[ "$#" -gt 0 ]]; then
            [[ "$#" == 4 && "$1" == --batch && "$2" == --skip-column-names && "$3" == -e ]] || return 1
            query="$4"
        else
            while IFS= read -r line; do
                [[ -n "$line" ]] || return 1
                printf '%s\n' "$line" >> "$mutation_log"
                case "$line" in
                    'CREATE DATABASE '*) printf '%s\n' true > "$database_state" ;;
                    'CREATE USER '*) printf '%s\n' true > "$user_state" ;;
                    'GRANT ALL PRIVILEGES '*) printf '%s\n' "$line" > "$grant_state" ;;
                    *) return 1 ;;
                esac
            done
            return 0
        fi
        if [[ "$query" == *'INFORMATION_SCHEMA.SCHEMATA'* ]]; then
            [[ "$(<"$database_state")" == true ]] && printf '%s\n' "$MYSQL_DATABASE"
            return 0
        fi
        if [[ "$query" == *'FROM mysql.user'* ]]; then
            [[ "$(<"$user_state")" == true ]] && printf '%s\n' "$MYSQL_USERNAME"
            return 0
        fi
        if [[ "$query" == *'SHOW GRANTS FOR'* ]]; then
            printf '%s\n' "$(<"$grant_state")"
            return 0
        fi
        printf 'Unexpected inspection SQL: %s\n' "$query" >&2
        return 1
}

step_database
mapfile -t mutations < "$mutation_log"
[[ "${#mutations[@]}" -eq 3 ]]
[[ "${mutations[0]}" == "CREATE DATABASE \`metator_site\`;" ]]
[[ "${mutations[1]}" == "CREATE USER 'metator_site'@'localhost' IDENTIFIED BY 'secret';" ]]
[[ "${mutations[2]}" == "GRANT ALL PRIVILEGES ON \`metator_site\`.* TO 'metator_site'@'localhost';" ]]
[[ "$(<"$database_state")" == true && "$(<"$user_state")" == true ]]

: > "$mutation_log"
step_database
[[ ! -s "$mutation_log" ]]

# A missing grant is repaired without recreating resources.
: > "$grant_state"
step_database
[[ "$(<"$mutation_log")" == "GRANT ALL PRIVILEGES ON \`metator_site\`.* TO 'metator_site'@'localhost';" ]]
: > "$mutation_log"
step_database
[[ ! -s "$mutation_log" ]]

printf '%s\n' 'Database rerun checks passed.'
