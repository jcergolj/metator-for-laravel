#!/usr/bin/env bash

step_prerequisites() {
    id "$DEPLOY_USER" >/dev/null 2>&1 || die "User $DEPLOY_USER does not exist"
    for command in php composer caddy git systemctl sudo sed grep; do
        command -v "$command" >/dev/null 2>&1 || die "$command is not installed"
    done
    getent group www-data | grep -qE "(^|,)${DEPLOY_USER}(,|$)" ||
        sudo usermod -aG www-data "$DEPLOY_USER"
    [[ -S "$PHP_FPM_SOCKET" ]] || die "PHP-FPM socket does not exist: $PHP_FPM_SOCKET"
    ok 'Deployment user and required software are ready'
}
