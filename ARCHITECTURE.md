# Internal OAuth Service: HAProxy + Consul

## Overview

Internal HAProxy gateway for service-to-service HTTPS communication, replacing the pattern where internal services route through the public URL (`https://musicbrainz.org`).

**What it provides:**
- TLS termination with self-signed internal CA
- Load balancing across multiple OAuth instances
- Active HTTP health checks with automatic failover and retries
- Dynamic backend discovery via consul-template + Consul catalog
- Language-agnostic: any client just makes a standard HTTPS request

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Client container (Perl/LWP, Python/requests, Go, Rust, ...) │
│                                                             │
│  POST https://virtual-internal-gw.service.consul:PORT/oauth2│
│  Trusts the internal CA cert                                │
└────────────────────────────┬────────────────────────────────┘
                             │ HTTPS (internal VLAN)
                             ▼
┌─────────────────────────────────────────────────────────────┐
│ haproxy-internal container                                  │
│                                                             │
│  consul-template: renders haproxy.cfg from Consul catalog   │
│  HAProxy 3.0: TLS frontend → HTTP backend (round-robin)    │
│  Registered in Consul as: internal-gw                       │
└────────────────────────────┬────────────────────────────────┘
                             │ HTTP (to uwsgi http-socket)
                             ▼
┌─────────────────────────────────────────────────────────────┐
│ OAuth/uWSGI instances                                       │
│                                                             │
│  uwsgi binary socket on :13050 (for openresty, unchanged)  │
│  uwsgi http-socket on :13052 (for HAProxy)                 │
│  Registered in Consul as: metabrainz-oauth-http             │
└─────────────────────────────────────────────────────────────┘
```

## Key Design Decisions

- **HAProxy cannot speak uwsgi binary protocol.** uWSGI exposes `http-socket` on port 13052 alongside the existing binary `socket` on 13050. Openresty keeps using `uwsgi_pass` for public traffic.
- **Health check uses `/.well-known/openid-configuration`** — an existing endpoint, no code changes needed.
- **`OAUTH_SERVICE_TAG` env var** controls which backend tag to target (defaults to `prod`). Allows deploying a test gateway pointing at test or prod oauth.
- **Cert management: on-disk (Ansible-managed).** Certs deployed to hosts, bind-mounted into containers. Simple, no Vault dependency. Can migrate to Vault later if needed.

## Repositories

| Repo | What | Key files |
|------|------|-----------|
| [haproxy-internal](https://github.com/metabrainz/haproxy-internal) | Docker image (this repo) | `Dockerfile`, `templates/haproxy.cfg.ctmpl`, `consul-template.hcl` |
| metabrainz-ansible | Cert generation, deployment to hosts | `files/ssl/internal/`, `tasks/internal_ssl.yml` |
| docker-server-configs | `start_haproxy_internal()` function | `scripts/services.sh`, `scripts/constants.sh` |
| metabrainz.org | OAuth Flask app | `docker/oauth/oauth.ini`, `oauth/views.py` |

## Deployment

```bash
# Deploy certs to hosts
ansible-playbook site.yml -t internal-ssl

# Start the gateway (on a node in internal_gw_servers group)
start_haproxy_internal prod                # prod gateway → prod oauth
start_haproxy_internal test edge test      # test gateway → test oauth
start_haproxy_internal test edge prod      # test gateway → prod oauth
```

## Certificate Management

Certs live in `metabrainz-ansible/files/ssl/internal/`. See the README there for regeneration instructions.

| Cert | Lifetime | Purpose |
|------|----------|---------|
| CA | 10 years | Signs gateway certs, installed in client trust stores |
| Gateway | 825 days | TLS frontend cert for HAProxy (DNS + IP SANs) |

**SANs:** `internal-gw.service.consul`, `virtual-internal-gw.service.consul`, plus IPs of gateway nodes.

**Client trust:** Bake `ca.pem` into client container images (`update-ca-certificates`) or bind-mount.

**Expiry monitoring:** Add an NRPE check on gateway nodes to alert before cert expires. Example check:
```bash
check_cert_expiry: "/usr/lib/nagios/plugins/check_file_content -f /etc/ssl/internal/haproxy/internal.pem --check-ssl-expire -w 30 -c 14"
```
Or a simple script using `openssl x509 -checkend` (seconds until expiry). Configure via `nrpe_server_group_commands` in `group_vars/internal_gw_servers.yml`.

## Operations

| Event | What happens |
|-------|-------------|
| OAuth instance crashes | HAProxy health check detects in ~15s, stops routing |
| OAuth instance slow | HAProxy timeout → retry on next backend |
| HAProxy instance crashes | Consul removes from `internal-gw`, clients get another via DNS |
| New OAuth instance deployed | Registers in Consul → consul-template re-renders → reload |
| Cert rotation | Update in Ansible, run playbook, reload HAProxy |

**Stats:** `http://<node-ip>:<stats-port>/stats`

## Migration Plan

1. **Phase 1** (done): Deploy haproxy-internal on one node, verify with test oauth
2. **Phase 2**: Test with one client (e.g. test ListenBrainz)
3. **Phase 3**: Migrate remaining clients (LB, CB, BB, MeB, Synapse)
4. **Phase 4**: Redundancy — deploy on second node, test failover
5. **Phase 5**: Cleanup — remove public oauth URL from internal configs

## Disclaimer

This document was generated collaboratively between a human (zas) and an AI assistant (Claude/Kiro CLI). Code examples and configurations should be verified against actual documentation before use. Final architectural decisions should involve the broader team.

**Last updated:** 2026-07-23
