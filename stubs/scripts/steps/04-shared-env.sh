#!/usr/bin/env bash
# @id: shared-env
# @title: Create the shared Laravel environment file
# @group: none
# @required: true
# @default: true
# @order: 40

step_shared_env() {
    local env_file="$APP_FOLDER/shared/.env" key
    ENV_FILE_CREATED=false
    ENV_UPDATED=false

    if sudo test -L "$APP_FOLDER/shared" || sudo test -L "$env_file"; then
        die 'Shared directory and .env must not be symlinks'
        return 1
    fi
    if ! sudo test -d "$APP_FOLDER/shared"; then
        sudo install -d -m 2770 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER/shared" || return 1
    fi
    if ! sudo test -e "$env_file"; then
        if [[ ! -f "$ENV_SEED_FILE" ]]; then
            die "Missing local environment seed: $ENV_SEED_FILE"
            return 1
        fi
        warn "Creating shared environment file at $env_file"
        sudo install -m 640 -o "$DEPLOY_USER" -g www-data "$ENV_SEED_FILE" "$env_file" || return 1
        ENV_FILE_CREATED=true
        ENV_UPDATED=true
    else
        warn "Updating existing shared environment file at $env_file"
    fi
    ensure_production_env "$env_file" || return 1
    if [[ "$ENV_FILE_CREATED" == true ]]; then
        set_env_value LOG_LEVEL info
        set_env_value SESSION_SECURE_COOKIE true
        set_env_value SESSION_DOMAIN ''
        set_env_value SESSION_COOKIE "metator_${SITE_ID}_session"
        if [[ "$USE_QUEUE" == true || "$USE_HORIZON" == true ]]; then
            set_env_value QUEUE_CONNECTION database
            set_env_value DB_QUEUE_CONNECTION "$DATABASE_DRIVER"
        else
            set_env_value QUEUE_CONNECTION sync
        fi
        if [[ "$USE_REDIS" != true ]]; then
            set_env_value CACHE_STORE file
            set_env_value SESSION_DRIVER file
        fi
        # Connection URLs take precedence over the provisioned database fields.
        set_env_value DB_URL ''
        if [[ "$DATABASE_DRIVER" == mysql ]]; then
            # Laravel prefers a configured Unix socket over the local TCP host.
            set_env_value DB_SOCKET ''
        fi
        # Laravel defaults can share prefixes when every app is named Laravel.
        set_env_value REDIS_PREFIX "metator_${APP_NAME}_"
        set_env_value CACHE_PREFIX "metator_${APP_NAME}_"
        set_env_value HORIZON_PREFIX "metator_${APP_NAME}_"
    fi
    set_env_value APP_URL "https://${DOMAIN}"
    ensure_database_config || return 1
    configure_database_env || return 1
    if [[ "$USE_REDIS" == true ]]; then
        if [[ "$ENV_FILE_CREATED" == true ]]; then
            set_env_value SESSION_CONNECTION default
            set_env_value SESSION_STORE redis
            set_env_value REDIS_CACHE_CONNECTION cache
            set_env_value REDIS_CACHE_LOCK_CONNECTION default
            set_env_value REDIS_QUEUE_CONNECTION default
            # The provisioned local Redis instance does not use local credentials.
            for key in REDIS_URL REDIS_USERNAME REDIS_PASSWORD; do
                set_env_value "$key" ''
            done
        fi
        # Persist safe routing before allocation, so a failed allocation can retry
        # without mistaking copied local connection settings for production ones.
        ensure_redis_config || return 1
        set_env_value REDIS_PREFIX "metator_${APP_NAME}_"
        set_env_value CACHE_PREFIX "metator_${APP_NAME}_"
        set_env_value HORIZON_PREFIX "metator_${APP_NAME}_"
        configure_redis_env || return 1
    fi
    if [[ "$ENV_UPDATED" == true ]]; then
        warn 'Review application-specific production values copied from the local .env before the first deployment.'
        warn 'Use metator:update-env with a Git-ignored local dotenv file to apply intentional changes.'
    fi
    ok 'Shared production .env exists and database settings were updated'
}
