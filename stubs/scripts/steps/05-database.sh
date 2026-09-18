#!/usr/bin/env bash
# @id: database
# @title: Prepare the selected database
# @group: none
# @required: true
# @default: true
# @order: 50

step_database() {
    ensure_database_config || return 1

    if [[ "$DATABASE_DRIVER" == sqlite ]]; then
        sudo apt-get install -y sqlite3 "${PHP_PACKAGE_PREFIX}-sqlite3" || {
            die 'SQLite packages could not be installed'
            return 1
        }
        sudo install -d -m 2775 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER/shared/database"
        if ! sudo test -e "$APP_FOLDER/shared/database/database.sqlite"; then
            sudo install -m 664 -o "$DEPLOY_USER" -g www-data /dev/null \
                "$APP_FOLDER/shared/database/database.sqlite"
        fi
        ok 'SQLite database is ready'
        return
    fi

    local metadata_database metadata_user existing_database existing_user existing_grants=''
    metadata_database="$(site_metadata_value database_name)"
    metadata_user="$(site_metadata_value database_user)"
    if [[ -n "$metadata_database" && "$metadata_database" != "$MYSQL_DATABASE" ]] ||
        [[ -n "$metadata_user" && "$metadata_user" != "$MYSQL_USERNAME" ]]; then
        die 'MariaDB ownership metadata does not match this site'
        return 1
    fi
    existing_database="$(sudo mariadb --batch --skip-column-names -e \
        "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '${MYSQL_DATABASE}'")" || return 1
    existing_user="$(sudo mariadb --batch --skip-column-names -e \
        "SELECT User FROM mysql.user WHERE User = '${MYSQL_USERNAME}' AND Host = '${MYSQL_HOST}'")" || return 1
    if [[ -z "$metadata_database" && ( -n "$existing_database" || -n "$existing_user" ) ]]; then
        die 'Existing MariaDB resources are not owned by this site'
        return 1
    fi
    if [[ -n "$metadata_database" ]]; then
        existing_grants="$(sudo mariadb --batch --skip-column-names -e \
            "SHOW GRANTS FOR '${MYSQL_USERNAME}'@'${MYSQL_HOST}'")" || return 1
    fi
    record_site_database || return 1
    local sql_password
    sql_password="${MYSQL_PASSWORD//\\/\\\\}"
    sql_password="${sql_password//\'/\'\'}"
    local statements=()
    [[ -n "$existing_database" ]] || statements+=("CREATE DATABASE \`${MYSQL_DATABASE}\`;")
    if [[ -z "$existing_user" ]]; then
        statements+=("CREATE USER '${MYSQL_USERNAME}'@'${MYSQL_HOST}' IDENTIFIED BY '${sql_password}';")
    fi
    if [[ -z "$existing_grants" || "$existing_grants" != *"ON \`${MYSQL_DATABASE}\`.*"* ]]; then
        statements+=("GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USERNAME}'@'${MYSQL_HOST}';")
    fi
    if [[ "${#statements[@]}" -gt 0 ]]; then
        printf '%s\n' "${statements[@]}" | sudo mariadb || return 1
    fi
    if ! sudo -u "$DEPLOY_USER" env MYSQL_USER="$MYSQL_USERNAME" MYSQL_PWD="$MYSQL_PASSWORD" \
        MYSQL_DATABASE="$MYSQL_DATABASE" "$PHP_PACKAGE_PREFIX" \
        -r 'new PDO("mysql:host=127.0.0.1;dbname=".getenv("MYSQL_DATABASE"), getenv("MYSQL_USER"), getenv("MYSQL_PWD"));'; then
        die 'MariaDB connection verification failed'
        return 1
    fi
    ok 'MariaDB database and scoped credentials are ready'
}
