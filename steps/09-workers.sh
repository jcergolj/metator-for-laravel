#!/usr/bin/env bash

step_workers() {
    if [[ "$USE_QUEUE" != true ]]; then
        ok 'Queue workers were not selected; Supervisor was not changed'
        return
    fi
    command -v supervisorctl >/dev/null 2>&1 || sudo apt-get install -y supervisor
    if [[ "$USE_HORIZON" == true ]]; then
        command -v redis-server >/dev/null 2>&1 || sudo apt-get install -y redis-server
    fi

    local worker_command log_file
    if [[ "$USE_HORIZON" == true ]]; then
        worker_command="php ${APP_FOLDER}/current/artisan horizon"
        log_file="${APP_FOLDER}/shared/storage/logs/horizon.log"
    else
        worker_command="php ${APP_FOLDER}/current/artisan queue:work --sleep=3 --tries=3 --timeout=90 --max-time=3600"
        log_file="${APP_FOLDER}/shared/storage/logs/queue-worker.log"
    fi

    local temporary
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
    sudo install -m 644 -o root -g root "$temporary" "$SUPERVISOR_FILE"
    rm -f "$temporary"
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
