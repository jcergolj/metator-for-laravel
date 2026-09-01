#!/usr/bin/env bash

step_scheduler() {
    if [[ "$USE_SCHEDULER" != true ]]; then
        if ! ask_yes_no 'Does this application use the Laravel scheduler?' y; then
            ok 'Laravel scheduler was not selected; cron was not changed'
            return
        fi

        USE_SCHEDULER=true
    fi

    local cron_job="* * * * * cd ${APP_FOLDER}/current && php artisan schedule:run >> /dev/null 2>&1"
    local temporary
    temporary="$(mktemp)"
    sudo crontab -u www-data -l 2>/dev/null |
        grep -Fv "cd ${APP_FOLDER}/current && php artisan schedule:run" > "$temporary" || true
    echo "$cron_job" >> "$temporary"
    sudo crontab -u www-data "$temporary"
    rm -f "$temporary"
    ok 'Exactly one scheduler entry is configured'
}
