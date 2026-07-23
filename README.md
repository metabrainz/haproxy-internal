# haproxy-internal

Internal HAProxy gateway for MetaBrainz service-to-service communication.

Provides TLS termination, load balancing, health checks, and dynamic backend discovery via consul-template + Consul catalog.

## What it does

- Terminates TLS on `*:443` with a self-signed internal CA cert
- Routes requests to backend services (currently: OAuth/uWSGI via HTTP)
- Discovers backends dynamically from Consul (no restarts needed when backends change)
- Active HTTP health checks with automatic failover and retries
- Stats endpoint on `:8404/stats`

## Building

The image is built automatically by GitHub Actions:
- Push to `main` → `metabrainz/haproxy-internal:edge`
- Tag `v*` → `metabrainz/haproxy-internal:<version>` + `:latest`

Manual build:
```bash
docker build -t metabrainz/haproxy-internal .
```

## Running

```bash
docker run -d \
    --network host \
    --volume /etc/ssl/internal/haproxy/:/etc/haproxy/ssl/:ro \
    --env CONSUL_HTTP_ADDR="10.10.10.x:8500" \
    metabrainz/haproxy-internal
```

The cert (`internal.pem`) must be a combined cert+key PEM file, bind-mounted into `/etc/haproxy/ssl/`.

See [ARCHITECTURE.md](ARCHITECTURE.md) for full deployment details, cert generation, and client configuration.

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Image build |
| `entrypoint.sh` | Renders config once, validates, then starts consul-template in exec mode |
| `consul-template.hcl` | consul-template config (Approach A: no Vault) |
| `templates/haproxy.cfg.ctmpl` | HAProxy config template with Consul service discovery |
| `ARCHITECTURE.md` | Full architecture document |
