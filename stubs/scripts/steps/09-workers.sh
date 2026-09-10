#!/usr/bin/env bash

step_workers() {
    if [[ "$USE_QUEUE" != true ]]; then
        return
    fi
    command -v supervisorctl >/dev/null 2>&1 || sudo apt-get install -y supervisor
    if [[ "$USE_HORIZON" == true ]]; then
        command -v redis-server >/dev/null 2>&1 || sudo apt-get install -y redis-server
    fi

    local worker_command log_file temporary changed=false
    if [[ "$USE_HORIZON" == true ]]; then
        worker_command="php ${APP_FOLDER}/current/artisan horizon"
        log_file="${APP_FOLDER}/shared/storage/logs/horizon.log"
    else
        worker_command="php ${APP_FOLDER}/current/artisan queue:work --sleep=3 --tries=3 --timeout=90 --max-time=3600"
        log_file="${APP_FOLDER}/shared/storage/logs/queue-worker.log"
    fi

    temporary="$(mktemp)"
    cat > "$temporary" <<EOF
[program:${APP_NAME}-worker]
process_name=%(program_name)s
command=${worker_command}
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=www-data
redirect_stderr=true
stdout_logfile=${log_file}
stopwaitsecs=3600
EOF
    sudo install -d -m 2775 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER/shared/storage/logs"
    if ! sudo cmp -s "$temporary" "$SUPERVISOR_FILE"; then
        changed=true
        if [[ -f "$SUPERVISOR_FILE" ]]; then
            warn "Updating existing Supervisor config at $SUPERVISOR_FILE"
        else
            warn "Creating Supervisor config at $SUPERVISOR_FILE"
        fi
        sudo install -m 644 -o root -g root "$temporary" "$SUPERVISOR_FILE"
    fi
    rm -f "$temporary"
    if [[ "$changed" == true ]]; then
        warn "Review $SUPERVISOR_FILE before continuing."
        read -r -p 'Press Enter to confirm the Supervisor config review and continue: '
    fi
    if [[ -e "$APP_FOLDER/current/artisan" ]]; then
        sudo supervisorctl reread
        sudo supervisorctl update
    fi
    if [[ "$USE_HORIZON" == true ]]; then
        ok 'Horizon Supervisor configuration is ready'
    else
        ok 'Queue worker Supervisor configuration is ready'
    fi
}
