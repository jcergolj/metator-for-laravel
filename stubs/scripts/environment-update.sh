#!/usr/bin/env bash
# shellcheck disable=SC1091
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

ENV_INPUT_FILE="$SCRIPT_DIR/.env-input"
temporary=''
trap 'rm -f "$ENV_INPUT_FILE" "${temporary:-}"' EXIT
ENV_FILE="$APP_FOLDER/shared/.env"
[[ -f "$ENV_INPUT_FILE" ]] || { die 'Missing local environment input'; exit 1; }
[[ -f "$ENV_FILE" ]] || { die 'The selected site environment does not exist; provision the site first'; exit 1; }
[[ "$(site_metadata_value site_id)" == "$SITE_ID" ]] || { die 'Selected site metadata does not match the requested site'; exit 1; }

protected_keys='^(APP_KEY|DB_CONNECTION|DB_HOST|DB_PORT|DB_DATABASE|DB_USERNAME|DB_PASSWORD|REDIS_DB|REDIS_CACHE_DB|REDIS_HOST|REDIS_PORT|REDIS_PREFIX|CACHE_PREFIX|HORIZON_PREFIX)$'
temporary="$(mktemp "$(dirname "$ENV_FILE")/.env.update.XXXXXX")"
sudo cp "$ENV_FILE" "$temporary"

while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line//[[:space:]]/}" || "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        [[ ! "$key" =~ $protected_keys ]] || { die "Environment key is managed by Metator: $key"; exit 1; }
        if [[ "$value" == \"*\" && "$value" == *\" ]]; then
            value="${value:1:${#value}-2}"
            value="${value//\\\"/\"}"
            value="${value//\\\\/\\}"
        elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
            value="${value:1:${#value}-2}"
        elif [[ "$value" == *[[:space:]]* ]]; then
            die "Unquoted whitespace is invalid for environment key: $key"
            exit 1
        fi
        ENV_FILE="$temporary" set_env_value "$key" "$value"
    else
        die 'Environment input contains an invalid dotenv line'
        exit 1
    fi
done < "$ENV_INPUT_FILE"

if sudo cmp -s "$temporary" "$ENV_FILE"; then
    ok 'Selected site environment is unchanged'
    exit 0
fi

sudo install -m 640 -o "$DEPLOY_USER" -g www-data "$temporary" "${ENV_FILE}.next"
sudo mv "${ENV_FILE}.next" "$ENV_FILE"
ok 'Selected site environment was updated atomically'
echo 'Refresh Laravel configuration and long-running workers through the application deployment lifecycle.'
