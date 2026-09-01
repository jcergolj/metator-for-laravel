#!/usr/bin/env bash

step_cloudflare_dns() {
    ensure_cloudflare_config || return 1
    if [[ "$USE_CLOUDFLARE" != true ]]; then
        ok 'Cloudflare DNS was not selected; DNS was not changed'
        return
    fi

    if ! command -v curl >/dev/null 2>&1; then
        die 'curl is not installed'
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        die 'jq is required for Cloudflare DNS management'
        return 1
    fi

    local existing_json result_count response
    existing_json="$(curl -fsS --max-time 10 \
        "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=A&name=${DOMAIN}&per_page=1" \
        -H "Authorization: Bearer ${CF_TOKEN}" \
        -H 'Content-Type: application/json')" || {
        die 'Cloudflare DNS lookup failed'
        return 1
    }

    if ! echo "$existing_json" | jq -e '.success == true' >/dev/null; then
        die 'Cloudflare rejected the DNS lookup'
        return 1
    fi
    result_count="$(echo "$existing_json" | jq '.result | length')"
    if [[ "$result_count" -gt 0 ]]; then
        ok "DNS A record for ${DOMAIN} already exists; skipping"
        return
    fi

    echo 'Creating Cloudflare DNS A record...'
    response="$(curl -fsS --max-time 10 -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CF_TOKEN}" \
        -H 'Content-Type: application/json' \
        --data "{\"type\":\"A\",\"name\":\"${DOMAIN}\",\"content\":\"${SERVER_IP}\",\"proxied\":true}")" || {
        die 'Cloudflare DNS record creation failed'
        return 1
    }

    if echo "$response" | jq -e '.success == true' >/dev/null; then
        ok 'Cloudflare DNS record created'
    else
        die 'Cloudflare did not create the DNS record'
        return 1
    fi
}
