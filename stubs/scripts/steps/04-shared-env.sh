#!/usr/bin/env bash

step_app_folder() {
    ensure_database_config || return 1

    local env_file="$APP_FOLDER/shared/.env"

    sudo install -d -m 2775 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER"
    sudo install -d -m 2775 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER/shared"
    if [[ ! -f "$env_file" ]]; then
        warn "Creating shared environment file at $env_file"
        sudo install -m 640 -o "$DEPLOY_USER" -g www-data /dev/null "$env_file"
    else
        warn "Updating existing shared environment file at $env_file"
    fi
    if ! sudo grep -qE '^APP_URL=' "$env_file"; then
        set_env_value APP_URL "https://${DOMAIN}"
    fi
    configure_database_env
    sudo install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/${DEPLOY_USER}/.local/share/nano"
    warn "Review $env_file before continuing."
    sudo -u "$DEPLOY_USER" "${EDITOR:-nano}" "$env_file"
    read -r -p 'Press Enter to confirm the .env review and continue: '
    ok 'Shared production .env exists and database settings were updated'
}
