#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
common_text="$(<"$ROOT_DIR/stubs/scripts/lib/common.sh")"
step_text="$(<"$ROOT_DIR/stubs/scripts/steps/05-redis.sh")"
install_text="$(<"$ROOT_DIR/src/Commands/InstallDeployerScaffoldingCommand.php")"
bootstrap_text="$(<"$ROOT_DIR/stubs/scripts/server-bootstrap.sh")"

[[ "$common_text" == *'REDIS_ALLOCATION_FILE'* ]]
[[ "$common_text" == *'CONFIG GET databases'* ]]
[[ "$common_text" == *'DBSIZE'* ]]
[[ "$common_text" == *'redis_cache_db='* ]]
[[ "$common_text" == *'CACHE_STORE redis'* ]]
[[ "$common_text" == *'REDIS_CACHE_DB'* ]]
[[ "$step_text" == *'PONG'* || "$step_text" == *'redis-cli'* ]]
[[ "$install_text" == *"\$redisCapability !== 'none'"* ]]
[[ "$bootstrap_text" == *"USE_REDIS='__USE_REDIS__'"* ]]
[[ "$bootstrap_text" == *"REDIS_CAPABILITY='__REDIS_CAPABILITY__'"* ]]
[[ "$install_text" == *"Laravel Horizon requires the Redis queues capability"* ]]

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin" "$TEST_DIR/site/shared"
touch "$TEST_DIR/site/.metator-site"
cat > "$TEST_DIR/bin/redis-cli" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *'CONFIG GET databases'*) printf 'databases\n16\n' ;;
    *'DBSIZE'*) printf '0\n' ;;
    *' PING'*) printf 'PONG\n' ;;
esac
EOF
chmod +x "$TEST_DIR/bin/redis-cli"
PATH="$TEST_DIR/bin:$PATH"
sudo() {
    if [[ "$1" == install ]]; then
        shift
        local arguments=()
        while [[ "$#" -gt 0 ]]; do
            case "$1" in
                -o|-g) shift 2 ;;
                *) arguments+=("$1"); shift ;;
            esac
        done
        command install "${arguments[@]}"
        return
    fi
    "$@"
}
source "$ROOT_DIR/stubs/scripts/lib/common.sh"
APP_FOLDER="$TEST_DIR/site"
SITE_ID=alpha
USE_REDIS=true
REDIS_ALLOCATION_FILE="$TEST_DIR/allocations.tsv"
ensure_redis_config
[[ "$REDIS_CACHE_DB" == 1 && "$REDIS_RUNTIME_DB" == 2 ]]
grep -Fxq 'alpha|1|2' "$REDIS_ALLOCATION_FILE"
[[ "$(grep -c '^redis_cache_db=' "$APP_FOLDER/.metator-site" || true)" == 1 ]]
REDIS_CONFIG_READY=false
ensure_redis_config
[[ "$REDIS_CACHE_DB" == 1 && "$REDIS_RUNTIME_DB" == 2 ]]

printf '%s\n' 'Redis allocation checks passed.'
