#!/usr/bin/env bash

step_app_folder() {
    sudo install -d -m 2775 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER"
    sudo install -d -m 2775 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER/shared"
    if [[ ! -f "$APP_FOLDER/shared/.env" ]]; then
        sudo install -m 640 -o "$DEPLOY_USER" -g www-data /dev/null "$APP_FOLDER/shared/.env"
    fi
    sudo -u "$DEPLOY_USER" "${EDITOR:-nano}" "$APP_FOLDER/shared/.env"
    configure_database_env
    ok 'Shared production .env exists and database settings were updated'
}
