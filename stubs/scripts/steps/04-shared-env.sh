#!/usr/bin/env bash

step_app_folder() {
    local env_file="$APP_FOLDER/shared/.env"
    ENV_FILE_CREATED=false

    sudo install -d -m 2775 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER"
    sudo install -d -m 2775 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER/shared"
    if ! sudo test -e "$env_file"; then
        warn "Creating shared environment file at $env_file"
        sudo install -m 640 -o "$DEPLOY_USER" -g www-data /dev/null "$env_file"
        ENV_FILE_CREATED=true
    else
        warn "Updating existing shared environment file at $env_file"
    fi
    if [[ ! -f "$ENV_EXAMPLE_FILE" ]]; then
        die "Missing environment example: $ENV_EXAMPLE_FILE"
        return 1
    fi
    merge_env_example "$ENV_EXAMPLE_FILE" "$env_file"
    if [[ "$ENV_FILE_CREATED" == true ]]; then
        # Laravel defaults can share prefixes when every app is named Laravel.
        set_env_value REDIS_PREFIX "metator_${APP_NAME}_"
        set_env_value CACHE_PREFIX "metator_${APP_NAME}_"
        set_env_value HORIZON_PREFIX "metator_${APP_NAME}_"
    fi
    if ! sudo grep -qE '^APP_URL=' "$env_file"; then
        set_env_value APP_URL "https://${DOMAIN}"
    fi
    ensure_database_config || return 1
    configure_database_env
    sudo install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/${DEPLOY_USER}/.local/share/nano"
    if [[ "$ENV_UPDATED" == true ]]; then
        warn "Review $env_file before continuing."
        sudo -u "$DEPLOY_USER" "${EDITOR:-nano}" "$env_file"
        read -r -p 'Press Enter to confirm the .env review and continue: '
    fi
    ok 'Shared production .env exists and database settings were updated'
}
