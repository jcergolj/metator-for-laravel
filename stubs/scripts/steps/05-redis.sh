#!/usr/bin/env bash
# @id: redis
# @title: Allocate isolated Redis databases
# @group: none
# @required: false
# @default: false
# @order: 55

step_redis() {
    [[ "$USE_REDIS" == true ]] || return
    ensure_redis_config || return 1
    if ! sudo redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -n "$REDIS_CACHE_DB" PING >/dev/null; then
        die 'Redis cache database connection verification failed'
        return 1
    fi
    if ! sudo redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -n "$REDIS_RUNTIME_DB" PING >/dev/null; then
        die 'Redis runtime database connection verification failed'
        return 1
    fi
    ok "Redis databases are ready (cache ${REDIS_CACHE_DB}, runtime ${REDIS_RUNTIME_DB})"
}
