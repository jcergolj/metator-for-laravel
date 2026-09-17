#!/usr/bin/env bash
# @id: permissions
# @title: Verify shared-file permissions
# @group: none
# @required: true
# @default: true
# @order: 60

step_permissions() {
    sudo install -d -m 2770 \
        "$APP_FOLDER/shared/storage/framework/cache" \
        "$APP_FOLDER/shared/storage/framework/data" \
        "$APP_FOLDER/shared/storage/framework/sessions" \
        "$APP_FOLDER/shared/storage/framework/views" \
        "$APP_FOLDER/shared/storage/logs" \
        "$APP_FOLDER/shared/bootstrap/cache"
    sudo chown -R "$DEPLOY_USER:www-data" "$APP_FOLDER/shared"
    sudo find "$APP_FOLDER/shared" -type d -exec chmod 2770 {} +
    sudo find "$APP_FOLDER/shared" -type f -exec chmod 660 {} +
    sudo chmod 640 "$APP_FOLDER/shared/.env"
    ok 'Shared files are restricted to deployer and www-data'
}
