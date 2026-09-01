#!/usr/bin/env bash

step_database() {
    ensure_database_config || return 1

    if [[ "$DATABASE_DRIVER" == sqlite ]]; then
        sudo apt-get install -y sqlite3 "${PHP_PACKAGE_PREFIX}-sqlite3" || {
            die 'SQLite packages could not be installed'
            return 1
        }
        sudo install -d -m 2775 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER/shared/database"
        if [[ ! -f "$APP_FOLDER/shared/database/database.sqlite" ]]; then
            sudo install -m 664 -o "$DEPLOY_USER" -g www-data /dev/null \
                "$APP_FOLDER/shared/database/database.sqlite"
        fi
        ok 'SQLite database is ready'
        return
    fi

    sudo apt-get install -y "${PHP_PACKAGE_PREFIX}-mysql" || {
        die 'MySQL PHP driver could not be installed'
        return 1
    }
    ok 'PHP MySQL driver is ready; the configured MySQL database will be used'
}
