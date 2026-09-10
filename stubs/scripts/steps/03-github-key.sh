#!/usr/bin/env bash

step_github_key() {
    sudo install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/${DEPLOY_USER}/.ssh"
    if [[ ! -f "$GITHUB_KEY" ]]; then
        sudo -u "$DEPLOY_USER" ssh-keygen -t ed25519 -f "$GITHUB_KEY" \
            -C "${APP_NAME} production deployer key" -N ''
        warn "Add this app-specific key to the ${GITHUB_REPOSITORY} GitHub repository before continuing:"
        sudo -u "$DEPLOY_USER" cat "${GITHUB_KEY}.pub"
        read -r -p 'Press Enter after adding the key to GitHub: '
    fi

    local ssh_config="/home/${DEPLOY_USER}/.ssh/config"
    local temporary
    temporary="$(mktemp)"
    if [[ -f "$ssh_config" ]]; then
        sudo sed "/^# BEGIN ${GITHUB_CONFIG_MARKER}$/,/^# END ${GITHUB_CONFIG_MARKER}$/d" \
            "$ssh_config" > "$temporary"
    fi
    cat >> "$temporary" <<EOF
# BEGIN ${GITHUB_CONFIG_MARKER}
Host ${GITHUB_ALIAS}
    HostName github.com
    User git
    IdentityFile ${GITHUB_KEY}
    IdentitiesOnly yes
# END ${GITHUB_CONFIG_MARKER}
EOF
    if ! sudo cmp -s "$temporary" "$ssh_config"; then
        sudo install -m 600 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$temporary" "$ssh_config"
    fi
    rm -f "$temporary"
    sudo chmod 600 "$ssh_config"
    sudo chmod 600 "$GITHUB_KEY"
    sudo chown -R "$DEPLOY_USER:$DEPLOY_USER" "/home/${DEPLOY_USER}/.ssh"

    if ! sudo -u "$DEPLOY_USER" git ls-remote "$GITHUB_URL" HEAD >/dev/null; then
        die 'GitHub access failed'
        return 1
    fi
    ok "App-specific GitHub key can read $GITHUB_REPOSITORY"
}
