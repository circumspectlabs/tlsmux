# tlsmux — Advanced TLS Router

**tlsmux** is a production-grade TLS multiplexer built on nginx community, OpenResty, and
[gotemplate](https://github.com/coveooss/gotemplate). Its primary purpose is meticulous control
of TLS streams: routing, passthrough, protocol encapsulation, and access enforcement — all driven
by simple YAML configuration that gets rendered into fully arbitrary nginx configs at startup and
on reload.

![Last Commit](https://img.shields.io/github/last-commit/circumspectlabs/tlsmux)
![License](https://img.shields.io/github/license/circumspectlabs/tlsmux)

## Overview

At its core, `tlsmux` sits in front of port 443 and inspects the raw TLS `ClientHello` before any
termination occurs. Based on the SNI hostname and/or ALPN extension, it routes each connection to
the appropriate backend — without touching the encrypted payload. TLS termination happens
downstream (or not at all), keeping end-to-end encryption intact and client certificates working.

On top of that passthrough layer, `tlsmux` includes a full HTTP/HTTPS reverse proxy module, also
template-driven. Both layers share the same YAML context, so a single set of manifests can drive
both stream routing and HTTP server definitions simultaneously.

## Usage

```bash
# just use templates in current `config` directory
docker run -d \
    --name tlsmux-service \
    -v $(pwd)/config:/etc/config:ro \
    -p 443:443 \
    -p 80:80 \
  ghcr.io/circumspectlabs/tlsmux:latest

# copy plain nginx configs into `stream {}` and `http {}` sections and use custom
# YAML configs path (/mnt/custom-config-dir in this example). Also mount your
# certbot certificates storage
docker run -d \
    --name tlsmux-service \
    -e CTX_DIR=/mnt/custom-config-dir \
    -v $(pwd)/config:/mnt/custom-config-dir:ro \
    -e STREAM_SNIPPETS_DIR=/mnt/stream.d \
    -v $(pwd)/stream.d:/mnt/stream.d:ro \
    -e HTTP_SNIPPETS_DIR=/mnt/http.d \
    -v $(pwd)/http.d:/mnt/http.d:ro \
    -v /etc/letsencrypt:/etc/letsencrypt:ro \
    -p 443:443 \
    -p 80:80 \
  ghcr.io/circumspectlabs/tlsmux:latest

# sefely rebuild and reload confuration for running service
docker exec -i tlsmux-service tlsmux reload

# check if the configuration has changes (includes check of automatically updated
# by certbot certificated)
docker exec -i tlsmux-service tlsmux check

# however the current templating system allows to enable literally any configuration
# without changing of templates, you still can customize them
docker run -d \
    --name tlsmux-service \
    -v $(pwd)/config:/etc/config:ro \
    -v $(pwd)/template:/etc/template:ro \
    -p 443:443 \
    -p 80:80 \
  ghcr.io/circumspectlabs/tlsmux:latest
```

## Key Features

### TLS Premux (stream layer)

The centerpiece of `tlsmux`. It operates at the TCP stream level using nginx's `stream_ssl_preread`
module — TLS is never terminated at this stage.

- **SNI + ALPN routing** — match routes by server name, ALPN protocol value, or both combined
- **SSL passthrough** — client certificates are passed through intact; E2EE is preserved
- **Per-route PROXY protocol** — independently enable/disable PROXY protocol toward each backend
- **Per-route whitelists** — IPv4/IPv6 with CIDR, enforced per route; allow-all if omitted
- **Non-TLS route** — a dedicated fallback for raw (non-TLS) connections, e.g. plain SSH
- **Default route** — catch-all for unmatched TLS connections, typically the HTTPS terminator
- **MPTCP support** — optional, for HTTP/3 readiness
- **PROXY protocol** — accept and trust PROXY headers from known upstream ranges

### YAML-Driven "Absolute" Templating

All nginx configuration is generated from Go templates rendered against a deep-merged YAML
context. There is no hard-coded structure — everything is a template snippet:

- Drop any number of `.yaml` files into the config directory; they are deep-merged at startup
- Global, stream, and HTTP blocks each have a `snippet` field that accepts arbitrary nginx config
  with gotemplate-generated content
- The `servers` list under `http` renders each entry as an independent `server {}` block
- Templates have access to the full merged context, including auto-discovered certificate metadata
- Extra snippet directories can be injected via `STREAM_SNIPPETS_DIR` / `HTTP_SNIPPETS_DIR`
  environment variables without rebuilding the image

This means features like complex upstream maps, custom Lua blocks, or additional virtual hosts
can be added purely through YAML — no image rebuild needed.

### SSH over TLS

A reference configuration (`config/ssh.yaml`) demonstrates how to encapsulate SSH inside a TLS
connection by advertising a custom ALPN value (e.g. `sshovertls/0.9`) in the `ClientHello`. The
premux layer sees the ALPN, routes the stream to an internal SSH-over-TLS listener, which then
unwraps it and proxies to the real SSH daemon — with SNI-based per-host routing on top.

Client-side setup is a single `~/.ssh/config` stanza using `openssl s_client` as `ProxyCommand`.
No changes to SSH daemons or server infrastructure are required.

### Automatic Certificate Discovery

On every startup and reload, tlsmux scans `/etc/letsencrypt/live/` for certbot-issued
certificates and injects rich metadata into the template context:

```yaml
ssl-certificates:
  example.com:
    cert_file: /etc/letsencrypt/live/example.com/fullchain.pem
    key_file:  /etc/letsencrypt/live/example.com/privkey.pem
    meta:
      not_before: "..."
      not_after:  "..."
      fingerprint: "..."
      sans: [example.com, www.example.com]
```

Templates can iterate this map to conditionally wire up certificates, insert fallback logic,
or serve a mock certificate until the real one has been issued.

A unique dummy certificate (EC secp521r1, single-use) is generated on first boot as the
`default` entry — safe to reference in templates before any real cert exists.

### Smart Initialization and Careful Reload

- **dhparam** — generated once (2048-bit by default), cached next to the YAML context to survive
  restarts; skip with `DHPARAM_SKIP=true`
- **Change detection** — `tlsmux check` and `tlsmux reload` compute SHA-256 hashes of the merged
  context and all template files; reload is skipped entirely if nothing changed
- **Atomic reload** — new config is rendered into a temp directory, validated with `nginx -t`,
  then atomically swapped in and signaled with `nginx -s reload`
- **Automatic rollback** — if validation fails, the previous config is restored and nginx
  continues running unchanged

### Lua / OpenResty Ecosystem

The image ships a custom nginx build with a comprehensive set of OpenResty modules and Lua
libraries, providing a scripting layer limited only by available resources:

**nginx modules:** `lua-nginx-module`, `stream-lua-nginx-module`, `lua-upstream-nginx-module`,
`headers-more`, `ngx_devel_kit`, `nginx-module-vts`, `rate-limit-nginx-module`,
`replace-filter-nginx-module`, `echo-nginx-module`

**Lua libraries (lua-resty-*):** `core`, `lrucache`, `hmac`, `string`, `websocket`,
`shdict-simple`, `upstream-healthcheck`, `memcached`, `dns`, `lock`, `shell`, `redis`,
`cjson`, `sregex`, `jwt`, `ipmatcher`

Practical use cases enabled by this stack:

- Non-trivial IP whitelisting and graylisting with Redis TTL buckets
- Dynamic HTTP response generation (JSON APIs, health checks, ACME challenge handlers)
- Custom authentication flows with HMAC / JWT validation
- Per-request upstream selection based on Lua logic
- Upstream health checking and circuit breaking

If you need another module, please create issue.

### Other

- Full IPv6 support throughout (listen addresses, whitelists, upstream targets)
- HTTP/2 and HTTP/3 (QUIC) enabled in the HTTP module
- Security-hardened defaults: `server_tokens off`, hidden `X-Powered-*` / `Server` headers,
  TLS 1.2+ only, `ssl_prefer_server_ciphers on`

## Extra Examples

Some very useful configuration examples are available in `use-cases` folder. These
are single-file configurations just to simplify the case. They are also full of
comments.

| File | Purpose |
|------|---------|
| `advanced-logging.yaml` | Disabled TLS mux, it is HTTP-only mode. Using Lua code, we improve JSON logging with the data extracted from JWT tokens, and then push it to syslog interface. In addition, it shows how you can enable a simple templated API gateway configuration. |
| `redis-and-postgres.yaml` | Case with TLS mux and without HTTP service at all. From single port, we just identify and forward connections to Redis or Postgres, or fallback to HTTPS server. |

Feel free to suggest or request other examples via Issues.

## Configuration

Configuration lives in a directory of YAML files (default: `/etc/config`). All files are
deep-merged in lexicographic order before templating. The bundled example configs in
`/etc/config-example` are the authoritative reference — they are extensively commented.

| File | Purpose |
|------|---------|
| `general.yaml` | Global nginx snippet (workers, events, error log, etc.) |
| `premux.yaml` | Stream-layer TLS router: routes, whitelists, defaults |
| `http.yaml` | HTTP/HTTPS layer: global http snippet + server definitions |
| `ssh.yaml` | SSH-over-TLS reference config (optional, self-contained) |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TMPL_DIR` | `/etc/template` | Template source directory |
| `DST_DIR` | `/etc/nginx` | nginx config output directory |
| `CTX_DIR` | `/etc/config` | YAML context directory |
| `STREAM_SNIPPETS_DIR` | _(disabled)_ | Extra stream snippet directory |
| `HTTP_SNIPPETS_DIR` | _(disabled)_ | Extra HTTP snippet directory |
| `DHPARAM_SKIP` | `false` | Skip dhparam generation |
| `DHPARAM_BITS` | `2048` | dhparam key size |
| `DEBUG` | _(unset)_ | Enable `set -x` shell tracing |

## Commands

```sh
tlsmux server   # initialize, template, validate, exec nginx (default)
tlsmux check    # exit 0 if nothing changed, exit 1 if reload needed
tlsmux reload   # re-render, validate, reload nginx; skip if unchanged
```

## References

- gotemplate functions: https://coveooss.github.io/gotemplate/docs/functions_reference/all_functions/
  (razor syntax is disabled to avoid conflicts with Lua code)
- nginx docs: https://nginx.org/en/docs/
- stream_ssl_preread: https://nginx.org/en/docs/stream/ngx_stream_ssl_preread_module.html
- OpenResty Lua modules: see `Dockerfile`, search for `https://github\.com/.*lua`
- Plenty of Lua examples: https://nginx-extras.getpagespeed.com/lua/
