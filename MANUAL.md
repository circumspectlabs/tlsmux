# tlsmux — Operator Manual

## Quickstart

Run tlsmux with a configuration directory mounted at the default path:

```bash
docker run -d \
    --name tlsmux \
    -p 443:443 \
    -p 80:80 \
    -v $(pwd)/config:/etc/config:ro \
    -v /etc/letsencrypt:/etc/letsencrypt:ro \
  ghcr.io/circumspectlabs/tlsmux:latest
```

On startup the container will:

1. Generate a one-time dummy TLS certificate (used as fallback before real certs exist)
2. Generate dhparam (2048-bit by default; cached to survive restarts)
3. Discover certificates from `/etc/letsencrypt/live/`
4. Deep-merge all `*.yaml` files from `CTX_DIR`
5. Render nginx configs from Go templates
6. Validate with `nginx -t` and exec nginx

## Commands

```sh
# Check whether config or certs changed since last start/reload (exit 0 = no change)
docker exec -i tlsmux tlsmux check

# Re-render, validate, and reload nginx; skips if nothing changed; rolls back on failure
docker exec -i tlsmux tlsmux reload
```

`tlsmux reload` is safe to call unconditionally — it computes SHA-256 hashes of the merged
context and all template files, and is a no-op if nothing has changed.

## Configuration Management

Configuration lives in a directory of YAML files (default `/etc/config`). All `*.yaml` files
in that directory are deep-merged in lexicographic order at every start and reload.

### Merge Order

Files are merged alphabetically. To enforce explicit ordering, use numeric prefixes:

```
10-base.yaml
20-premux.yaml
99-overrides.yaml
```

Later files override earlier ones; nested maps are merged recursively rather than replaced.

### Snippet Fields

Every major block (`global`, `premux`, `http`, each server entry) has a `snippet` field
that accepts raw nginx config. Snippets are rendered through Go templates with access to
the full merged YAML context, including auto-discovered certificate metadata.

```yaml
# Example: inject a custom map into the stream block
premux:
  snippet: |-
    map $ssl_server_name $my_var {
      default "";
      "api.example.com" "api";
    }
```

### Extra Snippet Directories

Inject plain nginx config files without touching YAML by mounting extra snippet directories:

```bash
docker run -d \
    -e STREAM_SNIPPETS_DIR=/mnt/stream.d \
    -v $(pwd)/stream.d:/mnt/stream.d:ro \
    -e HTTP_SNIPPETS_DIR=/mnt/http.d \
    -v $(pwd)/http.d:/mnt/http.d:ro \
    ...
```

Files from these directories are copied verbatim into `stream.d/` and `http.d/` respectively.

### Persisting dhparam

To avoid regenerating dhparam on every container restart, place a pre-generated file at
`$CTX_DIR/dhparam.pem` (the config directory). tlsmux will copy it rather than regenerate.

```bash
# leave your just generated dhparam next to YAML manifests
openssl dhparam -out config/dhparam.pem 2048
```

Set `DHPARAM_SKIP=true` to skip dhparam entirely (weaker TLS, not recommended for production).

### Routing Configuration (premux.yaml)

Routes are matched in list order by SNI and/or ALPN:

```yaml
premux:
  routes:
    # Match by both SNI and ALPN
    - sni: api.example.com
      alpn: [h2, http/1.1]
      target:
        - 10.0.0.10:6443
      proxy_protocol: true
      whitelist:
        - 10.0.0.0/8

    # Match by SNI regex
    - sni: "svc-[0-9]+[.]example[.]com"
      regex: true
      target:
        - 10.0.0.20:443

    # Match by ALPN only (e.g. SSH over TLS)
    - alpn: [sshovertls/0.9]
      target:
        - 127.0.0.1:2222
      proxy_protocol: true

  # Non-TLS fallback (e.g. plain SSH)
  no_tls:
    enabled: true
    target:
      - 10.0.0.10:22

  # Catch-all for unmatched TLS (typically your HTTPS terminator)
  default:
    enabled: true
    target:
      - 127.0.0.1:8443
    proxy_protocol: true
```

`proxy_protocol` on a route controls outbound PROXY headers toward the backend;
`premux.proxy_protocol` (top-level) controls whether tlsmux accepts PROXY headers
on its listening socket. These are independent settings.

## Certificate Management

### Automatic Discovery

On every start and reload, tlsmux scans `/etc/letsencrypt/live/` and injects certificate
metadata into the template context under `ssl-certificates`. Templates reference this map
to select the right cert for each server:

```yaml
# In your server snippet (suites all snippets: premux servers and http servers)
{{ $selected_ssl_ceritificate := "default" -}}

# find by regex
{{- range $key, $_ := (. | get "ssl-certificates") -}}
  {{- if regexMatch `^[\d]+\.[\d]+\.[\d]+\.[\d]+$` $key -}}
    {{- $selected_ssl_ceritificate = $key -}}
  {{- end -}}
{{- end -}}

# or just exact match - if exists
{{- range $key, $_ := (. | get "ssl-certificates") -}}
  {{- if eq "my.awesome.certificate.example.tld" $key -}}
    {{- $selected_ssl_ceritificate = $key -}}
  {{- end -}}
{{- end -}}

# fallbacks to "default" mock certificate if not found
ssl_certificate     {{ . | get "ssl-certificates" | get $selected_ssl_ceritificate | get "cert_file" }};
ssl_certificate_key {{ . | get "ssl-certificates" | get $selected_ssl_ceritificate | get "key_file" }};
```

A `default` entry is always present, pointing to the auto-generated dummy certificate.
The dummy cert is a unique EC secp521r1 cert generated once at first boot — safe to reference
in templates before any real cert exists.

### Certbot: Issuing Certificates

Mount the letsencrypt directory into the container. Tlsmux should see `/etc/letsencrypt/live`
folder in there.

```bash
-v /etc/letsencrypt:/etc/letsencrypt:ro
```

Issue a certificate for a domain (with ACME HTTP-01 challenge via `/.well-known/`):

```bash
certbot certonly \
    --non-interactive \
    --no-eff-email \
    --agree-tos \
    --elliptic-curve secp384r1 \
    --reuse-key \
    --hsts \
    --webroot \
    --webroot-path /data \
    -d example.com
```

> Webroot must point to REAL root of the http server. For current YAML examples
> tlsmux has `alias /data/.well-known/;` for `location .well-known {}`, so
> you need to point `--webroot-path` to `/data`, because certbot will allocate
> challage files in `http://example.com/.well-known/acme-challenge/<token_file_name>`

### Certbot: Default (IP-Based) Certificate

`tlsmux` recognizes certificates whose certbot `--cert-name` is an IP address and uses
one of them as the default TLS fallback. To register an IP certificate:

```bash
certbot certonly \
    --non-interactive \
    --no-eff-email \
    --agree-tos \
    --cert-name "0.0.0.0" \
    --elliptic-curve secp384r1 \
    --reuse-key \
    --hsts \
    --webroot \
    --webroot-path /data \
    --preferred-profile shortlived \
    --ip-address 1.1.1.1 \
    --ip-address "2f2f:aa11:aa11:aa11::1"
```

### Certbot: Renewing Certificates

One-time renewal (no-op if far from expiry):

```bash
certbot renew
```

You can also enable certbot deploy hook with `docker exec -i tlsmux tlsmux reload`
to automatically rebuild configuration with the new certificate (updated context)
and load the new version.

However, the exact cron (automatic scheduler run) and deploy hook (reload cert
as renewed) configuration are outside the scope of this manual.

## Debugging

### Enable Debug Logging (HTTP)

Add to the global `http.snippet` in `http.yaml` to enable debug logging for all HTTP traffic:

```nginx
access_log  /var/log/nginx/access.log  debug;
```

Enable per HTTP server (inside a `.servers[].snippet`):

```nginx
listen 127.0.0.1:8443 ssl proxy_protocol;
server_name api.example.com;

access_log  /var/log/nginx/access.log  debug;
```

Silence logging for a specific server or location:

```nginx
location /healthz {
    access_log  off;
    return 200 "ok";
}
```

### Enable Debug Logging (Stream / Premux)

The same directive applies in the stream block via `premux.snippet`:

```yaml
premux:
  snippet: |-
    access_log  /var/log/nginx/access.log  debug;
```

### Check Config Changes

It doesn't even try to reload configuration, only checks if there are changes
of context and/or SSL certificates (for example, renew of certificate).

```bash
docker exec -i tlsmux tlsmux check
```

Exits 0 if nothing changed, 1 if a reload would be needed. Useful in CI or monitoring scripts.

### Shell Tracing

Set `DEBUG=1` to enable `set -x` tracing in the tlsmux shell script:

```bash
docker run -e DEBUG=1 ...
```

This shows every command the startup/reload logic runs — useful for diagnosing template
or merge failures.
