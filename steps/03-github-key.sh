#!/usr/bin/env bash

step_github_key() {
    sudo install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/${DEPLOY_USER}/.ssh"
    if [[ ! -f "$GITHUB_KEY" ]]; then
        sudo -u "$DEPLOY_USER" ssh-keygen -t ed25519 -f "$GITHUB_KEY" \
            -C 'shared production deployer key' -N ''
        warn 'Add this key to GitHub before continuing:'
        sudo -u "$DEPLOY_USER" cat "${GITHUB_KEY}.pub"
        read -r -p 'Press Enter after adding the key to GitHub: '
    fi

    local ssh_config="/home/${DEPLOY_USER}/.ssh/config"
    local temporary
    temporary="$(mktemp)"
    if [[ -f "$ssh_config" ]]; then
        sudo sed '/^# BEGIN LARAVEL DEPLOYER GITHUB$/,/^# END LARAVEL DEPLOYER GITHUB$/d' \
            "$ssh_config" > "$temporary"
    fi
    cat >> "$temporary" <<EOF
# BEGIN LARAVEL DEPLOYER GITHUB
Host ${GITHUB_ALIAS}
    HostName github.com
    User git
    IdentityFile ${GITHUB_KEY}
    IdentitiesOnly yes
# END LARAVEL DEPLOYER GITHUB
EOF
    sudo install -m 600 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$temporary" "$ssh_config"
    rm -f "$temporary"
    sudo chown -R "$DEPLOY_USER:$DEPLOY_USER" "/home/${DEPLOY_USER}/.ssh"

    sudo -u "$DEPLOY_USER" git ls-remote "$GITHUB_URL" HEAD >/dev/null ||
        die 'GitHub access failed'
    ok "Reusable GitHub key can read $GITHUB_REPOSITORY"
}
