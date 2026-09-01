#!/usr/bin/env bash

step_app_folder() {
    ensure_database_config || return 1

    sudo install -d -m 2775 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER"
    sudo install -d -m 2775 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER/shared"
    if [[ ! -f "$APP_FOLDER/shared/.env" ]]; then
        sudo install -m 640 -o "$DEPLOY_USER" -g www-data /dev/null "$APP_FOLDER/shared/.env"
    fi
    if ! sudo grep -qE '^APP_URL=' "$APP_FOLDER/shared/.env"; then
        set_env_value APP_URL "https://${DOMAIN}"
    fi
    sudo install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/${DEPLOY_USER}/.local/share/nano"
    sudo -u "$DEPLOY_USER" "${EDITOR:-nano}" "$APP_FOLDER/shared/.env"
    configure_database_env
    ok 'Shared production .env exists and database settings were updated'
}
