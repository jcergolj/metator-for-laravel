#!/usr/bin/env bash

step_scheduler() {
    if [[ "$USE_SCHEDULER" != true ]]; then
        return
    fi

    local cron_job="* * * * * cd ${APP_FOLDER}/current && php artisan schedule:run >> /dev/null 2>&1"
    local current_crontab temporary
    current_crontab="$(mktemp)"
    temporary="$(mktemp)"
    sudo crontab -u www-data -l 2>/dev/null > "$current_crontab" || true
    grep -Fv "cd ${APP_FOLDER}/current && php artisan schedule:run" "$current_crontab" > "$temporary" || true
    echo "$cron_job" >> "$temporary"
    if sudo cmp -s "$current_crontab" "$temporary"; then
        rm -f "$current_crontab" "$temporary"
        ok 'Scheduler entry is already current'

        return
    fi
    sudo crontab -u www-data "$temporary"
    rm -f "$current_crontab"
    rm -f "$temporary"
    ok 'Exactly one scheduler entry is configured'
}
