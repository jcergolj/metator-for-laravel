#!/usr/bin/env bash

step_permissions() {
    sudo chown -R "$DEPLOY_USER:www-data" "$APP_FOLDER/shared"
    sudo find "$APP_FOLDER/shared" -type d -exec chmod 2775 {} +
    sudo find "$APP_FOLDER/shared" -type f -exec chmod 664 {} +
    sudo chmod 640 "$APP_FOLDER/shared/.env"
    ok 'Shared files are writable by deployer and www-data'
}
