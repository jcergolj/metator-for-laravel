#!/usr/bin/env bash

step_prerequisites() {
    for command in php composer caddy git systemctl sudo sed grep; do
        if ! command -v "$command" >/dev/null 2>&1; then
            die "$command is not installed"
            return 1
        fi
    done

    ensure_deploy_user_exists
    getent group www-data | grep -qE "(^|,)${DEPLOY_USER}(,|$)" ||
        sudo usermod -aG www-data "$DEPLOY_USER"
    if [[ ! -S "$PHP_FPM_SOCKET" ]]; then
        die "PHP-FPM socket does not exist: $PHP_FPM_SOCKET"
        return 1
    fi
    ok 'Deployment user and required software are ready'
}
