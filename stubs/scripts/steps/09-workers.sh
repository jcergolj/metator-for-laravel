#!/usr/bin/env bash
# @id: workers
# @title: Configure queue workers
# @group: none
# @required: false
# @default: false
# @order: 90

step_workers() {
    if [[ "$USE_QUEUE" != true ]]; then
        reconcile_disabled_workers
        return
    fi
    require_commands supervisorctl supervisord || return 1
    sudo systemctl is-active --quiet supervisor || {
        die 'Supervisor is not active; run prepare-server before provisioning workers'
        return 1
    }

    local worker_command log_file temporary changed=false marker
    marker="# Managed by Metator: site_id=${SITE_ID}"
    if sudo test -e "$SUPERVISOR_FILE" && ! sudo grep -Fqx "$marker" "$SUPERVISOR_FILE"; then
        die "Supervisor configuration is not owned by this site: $SUPERVISOR_FILE"
        return 1
    fi
    if sudo test -e "$SUPERVISOR_SUDOERS_FILE" &&
        ! sudo grep -Fqx "# Managed by Metator: site_id=${SITE_ID}" "$SUPERVISOR_SUDOERS_FILE"; then
        die "Supervisor sudo policy is not owned by this site: $SUPERVISOR_SUDOERS_FILE"
        return 1
    fi
    if [[ "$USE_HORIZON" == true ]]; then
        worker_command="/usr/bin/php${PHP_VERSION} ${APP_FOLDER}/current/artisan horizon"
        log_file="${APP_FOLDER}/shared/storage/logs/horizon.log"
    else
        worker_command="/usr/bin/php${PHP_VERSION} ${APP_FOLDER}/current/artisan queue:work --sleep=3 --tries=3 --timeout=60 --max-time=3600"
        log_file="${APP_FOLDER}/shared/storage/logs/queue-worker.log"
    fi

    temporary="$(mktemp)"
    cat > "$temporary" <<EOF
${marker}
[program:${APP_NAME}-worker]
process_name=%(program_name)s
command=${worker_command}
autostart=false
autorestart=true
stopasgroup=true
killasgroup=true
user=www-data
redirect_stderr=true
stdout_logfile=${log_file}
stopwaitsecs=60
EOF
    sudo install -d -m 2775 -o "$DEPLOY_USER" -g www-data "$APP_FOLDER/shared/storage/logs"
    if ! sudo cmp -s "$temporary" "$SUPERVISOR_FILE"; then
        changed=true
    fi
    if [[ "$changed" != true ]]; then
        rm -f "$temporary"
        ok 'Supervisor worker configuration is already current'
        return
    fi

    local backup=''
    if sudo test -f "$SUPERVISOR_FILE"; then
        backup="$(mktemp)"
        sudo cp -p "$SUPERVISOR_FILE" "$backup"
    fi
    sudo install -m 644 -o root -g root "$temporary" "$SUPERVISOR_FILE"
    rm -f "$temporary"
    if ! sudo supervisord -t; then
        if [[ -n "$backup" ]]; then
            sudo cp -p "$backup" "$SUPERVISOR_FILE"
        else
            sudo rm -f "$SUPERVISOR_FILE"
        fi
        [[ -z "$backup" ]] || rm -f "$backup"
        die 'Supervisor validation failed; the previous worker configuration was restored'
        return 1
    fi
    [[ -z "$backup" ]] || rm -f "$backup"

    local supervisorctl_path
    supervisorctl_path="$(command -v supervisorctl)"
    temporary="$(mktemp)"
    cat > "$temporary" <<EOF
# Managed by Metator: site_id=${SITE_ID}
${DEPLOY_USER} ALL=(root) NOPASSWD: ${supervisorctl_path} update ${APP_NAME}-worker, ${supervisorctl_path} restart ${APP_NAME}-worker:*, ${supervisorctl_path} status ${APP_NAME}-worker:*
EOF
    if ! sudo cmp -s "$temporary" "$SUPERVISOR_SUDOERS_FILE"; then
        sudo install -m 440 -o root -g root "$temporary" "$SUPERVISOR_SUDOERS_FILE"
    fi
    rm -f "$temporary"
    if [[ "$USE_HORIZON" == true ]]; then
        ok 'Horizon Supervisor configuration is staged; deploy code before activation'
    else
        ok 'Queue worker Supervisor configuration is staged; deploy code before activation'
    fi
}

reconcile_disabled_workers() {
    local worker_marker="# Managed by Metator: site_id=${SITE_ID}"
    local worker_exists=false sudoers_exists=false

    if [[ -e "$SUPERVISOR_FILE" ]]; then
        worker_exists=true
        if ! sudo grep -Fqx "$worker_marker" "$SUPERVISOR_FILE"; then
            die "Supervisor configuration is not owned by this site: $SUPERVISOR_FILE"
            return 1
        fi
    fi
    if [[ -e "$SUPERVISOR_SUDOERS_FILE" ]]; then
        sudoers_exists=true
        if ! sudo grep -Fqx "$worker_marker" "$SUPERVISOR_SUDOERS_FILE"; then
            die "Supervisor sudo policy is not owned by this site: $SUPERVISOR_SUDOERS_FILE"
            return 1
        fi
    fi
    if [[ "$worker_exists" != true && "$sudoers_exists" != true ]]; then
        ok 'Supervisor worker configuration is already absent'
        return
    fi

    require_commands supervisorctl || return 1
    if [[ "$worker_exists" == true ]]; then
        supervisorctl stop "${APP_NAME}-worker:*" || {
            die "Could not stop workers for site ${SITE_ID}"
            return 1
        }
        sudo rm -f "$SUPERVISOR_FILE" || return 1
        supervisorctl reread || return 1
        supervisorctl update || return 1
    fi
    if [[ "$sudoers_exists" == true ]]; then
        sudo rm -f "$SUPERVISOR_SUDOERS_FILE" || return 1
    fi
    ok "Removed worker configuration for site ${SITE_ID}"
}
