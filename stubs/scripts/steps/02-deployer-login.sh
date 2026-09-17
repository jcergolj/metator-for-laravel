#!/usr/bin/env bash
# @id: deployer-login
# @title: Configure deployer SSH login
# @group: none
# @required: false
# @default: true
# @order: 20

step_deployer_login() {
    if [[ "$CONFIGURE_DEPLOY_USER_LOGIN" != true ]]; then
        return
    fi

    ensure_deploy_user_exists || return 1
    local ssh_dir="/home/${DEPLOY_USER}/.ssh"
    local authorized_keys="${ssh_dir}/authorized_keys"
    if sudo test -f "$authorized_keys" &&
        sudo grep -qE '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp)' "$authorized_keys"; then
        ok "SSH login key is already configured for $DEPLOY_USER"

        return
    fi

    if [[ -z "${CLIENT_PUBLIC_KEY:-}" ]]; then
        if [[ ! -t 0 ]]; then
            die 'No public SSH key was transferred. Refresh the generated scripts and retry provisioning.'
            return 1
        fi
        prompt_value 'Paste your public SSH key' CLIENT_PUBLIC_KEY || return 1
    fi

    if [[ ! "$CLIENT_PUBLIC_KEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)[[:space:]]+ ]]; then
        die 'Public SSH key must start with ssh-ed25519, ssh-rsa, or ecdsa-sha2-*'
        return 1
    fi

    sudo install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$ssh_dir" || return 1
    if ! sudo test -f "$authorized_keys"; then
        sudo install -m 600 -o "$DEPLOY_USER" -g "$DEPLOY_USER" /dev/null "$authorized_keys" || return 1
    fi

    if ! sudo grep -qxF "$CLIENT_PUBLIC_KEY" "$authorized_keys"; then
        printf '%s\n' "$CLIENT_PUBLIC_KEY" | sudo tee -a "$authorized_keys" >/dev/null || return 1
    fi

    sudo chown "$DEPLOY_USER:$DEPLOY_USER" "$ssh_dir" "$authorized_keys" || return 1
    sudo chmod 700 "$ssh_dir" || return 1
    sudo chmod 600 "$authorized_keys" || return 1

    ok "SSH login key configured for $DEPLOY_USER"
    echo "Test from your computer with: ssh ${DEPLOY_USER}@${SERVER_IP}"
}
