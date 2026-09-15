#!/usr/bin/env bash
# @id: prerequisites
# @title: Verify server prerequisites
# @group: none
# @required: true
# @default: true
# @order: 10

step_prerequisites() {
    for command in php composer git systemctl sudo sed grep cmp getent id; do
        if ! command -v "$command" >/dev/null 2>&1; then
            die "$command is not installed"
            return 1
        fi
    done

    prepare_deploy_user
    local step_file step_id
    for step_file in "$SCRIPT_DIR"/steps/*.sh; do
        step_id="$(step_metadata "$step_file" id)"
        case "$step_id" in
            caddy) require_commands caddy || return 1 ;;
            cloudflare) require_commands curl jq || return 1 ;;
        esac
    done
    if [[ ! -S "$PHP_FPM_SOCKET" ]]; then
        die "PHP-FPM socket does not exist: $PHP_FPM_SOCKET"
        return 1
    fi
    ok 'Deployment user and required software are ready'
}
