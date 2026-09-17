#!/usr/bin/env bash
# @id: scheduler
# @title: Configure Laravel scheduler
# @group: none
# @required: false
# @default: true
# @order: 80

step_scheduler() {
    if [[ "$USE_SCHEDULER" != true ]]; then
        reconcile_disabled_scheduler
        return
    fi

    local scheduler_file="${SCHEDULER_FILE:-/etc/cron.d/metator-${SITE_ID}}"
    local php_binary="/usr/bin/php${PHP_VERSION}"
    local temporary
    temporary="$(mktemp)"
    cat > "$temporary" <<EOF
# Managed by Metator: site_id=${SITE_ID}
* * * * * www-data if [ -f "${APP_FOLDER}/current/artisan" ]; then cd "${APP_FOLDER}/current" && ${php_binary} artisan schedule:run >> /dev/null 2>&1; fi
EOF

    if ! grep -Eq '^\* \* \* \* \* www-data if \[ -f ".*/current/artisan" \]; then cd ".*/current" && .*/php[0-9]+\.[0-9]+ artisan schedule:run >> /dev/null 2>&1; fi$' "$temporary"; then
        rm -f "$temporary"
        die 'Generated scheduler entry failed validation'
        return 1
    fi
    if sudo test -e "$scheduler_file"; then
        if ! sudo grep -qxF "# Managed by Metator: site_id=${SITE_ID}" "$scheduler_file" ||
            ! sudo cmp -s "$temporary" "$scheduler_file"; then
            rm -f "$temporary"
            die "Scheduler file is not owned by site ${SITE_ID}: ${scheduler_file}"
            return 1
        fi
        rm -f "$temporary"
        record_site_scheduler || return 1
        ok 'Scheduler entry is already current'
        return
    fi

    sudo install -d -m 755 -o root -g root "$(dirname "$scheduler_file")" || {
        rm -f "$temporary"
        return 1
    }
    sudo install -m 644 -o root -g root "$temporary" "$scheduler_file" || {
        rm -f "$temporary"
        return 1
    }
    rm -f "$temporary"
    record_site_scheduler || return 1
    ok "Scheduler entry is configured at ${scheduler_file}"
}

reconcile_disabled_scheduler() {
    local scheduler_file="${SCHEDULER_FILE:-/etc/cron.d/metator-${SITE_ID}}"
    if [[ ! -e "$scheduler_file" ]]; then
        ok 'Scheduler entry is already absent'
        return
    fi
    if ! sudo grep -qxF "# Managed by Metator: site_id=${SITE_ID}" "$scheduler_file"; then
        die "Scheduler file is not owned by site ${SITE_ID}: ${scheduler_file}"
        return 1
    fi
    sudo rm -f "$scheduler_file" || return 1
    ok "Removed scheduler entry for site ${SITE_ID}"
}
