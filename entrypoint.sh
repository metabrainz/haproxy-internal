#!/bin/sh
set -e

# For Approach B (Vault): write wrapped token to file if provided
if [ -n "$VAULT_WRAPPED_TOKEN" ]; then
    mkdir -p /run/secrets
    echo "$VAULT_WRAPPED_TOKEN" > /run/secrets/wrapped_token
fi

# Render templates once before starting haproxy
consul-template -once -config /etc/consul-template/config.hcl

# Validate haproxy config
haproxy -c -f /etc/haproxy/haproxy.cfg || exit 1

# Start consul-template in exec mode (it manages the haproxy process)
exec consul-template -config /etc/consul-template/config.hcl
