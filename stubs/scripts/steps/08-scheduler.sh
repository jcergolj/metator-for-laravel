#!/usr/bin/env bash
# @id: scheduler
# @title: Configure Laravel scheduler
# @group: none
# @required: false
# @default: true
# @order: 80

step_scheduler() {
    if [[ "$USE_SCHEDULER" != true ]]; then
        return
    fi

    local cron_job="* * * * * cd ${APP_FOLDER}/current && php artisan schedule:run >> /dev/null 2>&1"
    local current_crontab temporary errors
    current_crontab="$(mktemp)"
    temporary="$(mktemp)"
    errors="$(mktemp)"
    if ! LC_ALL=C sudo crontab -u www-data -l 2> "$errors" | tee "$current_crontab" >/dev/null; then
        if ! grep -qxF 'no crontab for www-data' "$errors"; then
            cat "$errors" >&2
            rm -f "$current_crontab" "$temporary" "$errors"
            die 'Cannot read the shared crontab; leaving it unchanged'
            return 1
        fi
    fi
    rm -f "$errors"
    grep -Fxv "$cron_job" "$current_crontab" > "$temporary" || true
    echo "$cron_job" >> "$temporary"
    if sudo cmp -s "$current_crontab" "$temporary"; then
        rm -f "$current_crontab" "$temporary"
        ok 'Scheduler entry is already current'

        return
    fi
    sudo crontab -u www-data "$temporary" || {
        rm -f "$current_crontab" "$temporary"
        return 1
    }
    rm -f "$current_crontab"
    rm -f "$temporary"
    ok 'Exactly one scheduler entry is configured'
}
