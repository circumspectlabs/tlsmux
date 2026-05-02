#!/bin/bash
set -e

if [ -n "$DEBUG" ]; then
    set -x
fi

TMPL_DIR="${TMPL_DIR:-/etc/template}"
DST_DIR="${DST_DIR:-/etc/nginx}"
CTX_DIR="${CTX_DIR:-/etc/config}"
TCTX="${DST_DIR}/_context.yaml"

STREAM_SNIPPETS_DIR="${STREAM_SNIPPETS_DIR:-"/does/not/exist"}"
HTTP_SNIPPETS_DIR="${HTTP_SNIPPETS_DIR:-"/does/not/exist"}"

DHPARAM_SKIP="${DHPARAM_SKIP:-false}"
DHPARAM_BITS="${DHPARAM_BITS:-2048}"

###
### Always generate dummy TLS certificate and key to make it impossible
### to reuse anywhere else (making it only mock certificate for initial
### boot purpose, not a real one). Required for the first boot stage.
###
function create_dummy_tls_cert() {
    cat <<-EOF > "${DST_DIR}/private/dummy-tls.x509v3"
basicConstraints = critical, CA:TRUE, pathlen:1
keyUsage = critical, digitalSignature, keyCertSign, cRLSign
extendedKeyUsage = critical, OCSPSigning, serverAuth
authorityKeyIdentifier = keyid, issuer:always
subjectAltName = DNS:dummy-tls.local
EOF

    if [ ! -f "${DST_DIR}/private/dummy-tls.key" ]; then
        openssl ecparam -name secp521r1 -genkey \
            -out "${DST_DIR}/private/dummy-tls.key"
        chmod 600 "${DST_DIR}/private/dummy-tls.key"
    fi

    if [ ! -f "${DST_DIR}/private/dummy-tls.crt" ]; then
        openssl req -new \
            -key "${DST_DIR}/private/dummy-tls.key" \
            -subj "/CN=dummy-tls.local" \
            -out "${DST_DIR}/private/dummy-tls.csr"
        openssl x509 -req \
            -in "${DST_DIR}/private/dummy-tls.csr" \
            -sha256 -extfile "${DST_DIR}/private/dummy-tls.x509v3" \
            -days $((365*10)) \
            -key "${DST_DIR}/private/dummy-tls.key" \
            -out "${DST_DIR}/private/dummy-tls.crt"
        chmod 644 "${DST_DIR}/private/dummy-tls.crt"
    fi
}

function create_dhparam() {
    if [ "${DHPARAM_SKIP}" == "false" ]; then
        if [ -f "${CTX_DIR}/dhparam.pem" ]; then
            cp -f "${CTX_DIR}/dhparam.pem" "${DST_DIR}/private/dhparam.pem"
        fi
        if [ ! -f "${CTX_DIR}/dhparam.pem" ] && [ ! -f "${DST_DIR}/private/dhparam.pem" ]; then
            openssl dhparam -out "${DST_DIR}/private/dhparam.pem" ${DHPARAM_BITS}
        fi
    fi
}

###
### Discover SSL/TLS certificates and keys
###
function discover_ssl_certs() {
    local out="${1}"
    echo '"ssl-ceritificates":' > "${out}"

    SSL_CERTS_DISCOVERY_ROOT="/etc/letsencrypt"
    if [ -d "${SSL_CERTS_DISCOVERY_ROOT}/live" ] && [ "$(ls -1 "${SSL_CERTS_DISCOVERY_ROOT}/live" | wc -l || true)" != "0" ]; then
        __SSL_CERTS=($(ls -1 "${SSL_CERTS_DISCOVERY_ROOT}"/live/*/privkey.pem | cut -d '/' -f 5))
        if [[ -n "${__SSL_CERTS[@]}" ]]; then
            for cert in "${__SSL_CERTS[@]}"; do
                cert_file="${SSL_CERTS_DISCOVERY_ROOT}/live/${cert}/fullchain.pem"
                key_file="${SSL_CERTS_DISCOVERY_ROOT}/live/${cert}/privkey.pem"
                not_before="$(openssl x509 -noout -text -in "${cert_file}" | grep -F 'Not Before' | cut -d ':' -f 2- | xargs echo)"
                not_after="$(openssl x509 -noout -text -in "${cert_file}" | grep -F 'Not After' | cut -d ':' -f 2- | xargs echo)"
                fingerprint="$(openssl x509 -noout -fingerprint -in "${cert_file}" | cut -d '=' -f 2- | xargs echo | tr 'a-z' 'A-Z')"
                sans=($(openssl x509 -noout -in "${cert_file}" -ext subjectAltName | grep -vF 'X509v3 Subject Alternative Name' | xargs echo | tr ' ' '\n' | grep -E '^(DNS|IP):' | sed 's/^DNS://g; s/^IP://g' | sort | xargs echo))
                cat <<-EOF >> "${out}"
  "${cert}":
    cert_file: "${cert_file}"
    key_file: "${key_file}"
    meta:
      not_before: "${not_before}"
      not_after: "${not_after}"
      fingerprint: "${fingerprint}"
      sans:$(if [[ "${#sans[@]}" -gt 0 ]]; then echo -n; else echo -n " []"; fi)
$(for i in "${sans[@]}"; do echo "        - \"${i}\""; done)
EOF
            done
        fi
    fi

    sans_default=($(openssl x509 -noout -in "${DST_DIR}/private/dummy-tls.crt" -ext subjectAltName | grep -vF 'X509v3 Subject Alternative Name' | xargs echo | tr ' ' '\n' | grep -E '^(DNS|IP):' | sed 's/^DNS://g; s/^IP://g' | sort | xargs echo))
    cat <<-EOF >> "${out}"
  default:
    cert_file: "${DST_DIR}/private/dummy-tls.crt"
    key_file: "${DST_DIR}/private/dummy-tls.key"
    meta:
      not_before: "$(openssl x509 -noout -text -in "${DST_DIR}/private/dummy-tls.crt" | grep -F 'Not Before' | cut -d ':' -f 2- | xargs echo)"
      not_after: "$(openssl x509 -noout -text -in "${DST_DIR}/private/dummy-tls.crt" | grep -F 'Not After' | cut -d ':' -f 2- | xargs echo)"
      fingerprint: "$(openssl x509 -noout -fingerprint -in "${DST_DIR}/private/dummy-tls.crt" | cut -d '=' -f 2- | xargs echo | tr 'a-z' 'A-Z' | tr -d ':')"
      sans:$(if [[ "${#sans_default[@]}" -gt 0 ]]; then echo -n; else echo -n " []"; fi)
$(for i in "${sans_default[@]}"; do echo "        - \"${i}\""; done)
EOF

    if [ -f "${DST_DIR}/private/dhparam.pem" ]; then
        echo 'dhparams:' >> "${out}"
        echo '  found: true' >> "${out}"
        echo "  file: \"${DST_DIR}/private/dhparam.pem\"" >> "${out}"
        echo "  hashsum: \"$(sha256sum "${DST_DIR}/private/dhparam.pem" | awk '{print $1}' | tr 'a-z' 'A-Z')\"" >> "${out}"
    else
        echo 'dhparams:' >> "${out}"
        echo '  found: false' >> "${out}"
    fi
}

###
### Generate context file by deep merging all YAML files into one
###
function deep_merge_context() {
    local discovered="${1}"
    local out="${2}"
    perl \
        -MYAML=LoadFile,Dump \
        -MHash::Merge::Simple=merge \
        -E 'say Dump(merge(map{LoadFile($_)}@ARGV))' \
        $((ls -1 ${CTX_DIR}/*.yaml ${discovered}/*.yaml 2>/dev/null || true) | sort) \
        > "${out}"
}

###
### Perform templating
###
function template_nginx_configs() {
    local context="${1}"
    local target="${2}"
    for template in $(find ${TMPL_DIR} -type f | sed 's@^'${TMPL_DIR}'/@@g'); do
        if [[ "$(file -b ${TMPL_DIR}/$template)" == "ASCII text" ]] && [[ "$(head -1 ${TMPL_DIR}/$template | grep -F "directive: gotemplate" | wc -l)" == "1" ]]; then
            cat "${TMPL_DIR}/$template" | gotemplate --no-razor -i "${context}" > "${target}/$template"
        else
            cp -f "${TMPL_DIR}/$template" "${target}/$template"
        fi
    done

    if [ "${STREAM_SNIPPETS_DIR}" != "/does/not/exist" ] && [ -d "${STREAM_SNIPPETS_DIR}" ] && [ "$(ls -1 "${STREAM_SNIPPETS_DIR}" | wc -l || true)" != "0" ]; then
        cp -r "${STREAM_SNIPPETS_DIR}"/* "${target}/stream.d/"
    fi

    if [ "${HTTP_SNIPPETS_DIR}" != "/does/not/exist" ] && [ -d "${HTTP_SNIPPETS_DIR}" ] && [ "$(ls -1 "${HTTP_SNIPPETS_DIR}" | wc -l || true)" != "0" ]; then
        cp -r "${HTTP_SNIPPETS_DIR}"/* "${target}/http.d/"
    fi
}

###
### Validate configuration
###
function validate_nginx_configs() {
    set +e
    nginx -t &>/dev/null
    if [[ "$?" != "0" ]]; then
        nginx -T
        return $?
    fi
    set -e
}

###
### Compute hashsums of current TCTX and all template directories into a given file
###
function compute_hashsums_into() {
    local context="$1"
    local out="$2"
    (cd "$(dirname "${context}")"; sha256sum "$(basename "${context}")") > "${out}.tmp"
    for item in "${TMPL_DIR}" "${STREAM_SNIPPETS_DIR}" "${HTTP_SNIPPETS_DIR}"; do
        (cd "${item}" 2>/dev/null && sha256sum $(find . -type f | sed 's@^\./@@g') >> "${out}.tmp") || true
    done
    sort -k 2 "${out}.tmp" > "${out}"
    rm -f "${out}.tmp"
}

###
### Check whether stored hashsums match what would be computed from current state.
### Runs discover+merge to get a fresh TCTX before comparing.
### Returns 0 if same (no changes), 1 if different (changes detected).
###
function hashsums_are_same() {
    [ -f "${DST_DIR}/_hashsum.txt" ] || return 1
    local tmp_discovered
    local tmp_context
    local tmp_hashmap
    tmp_discovered="$(mktemp -d)"
    tmp_context="$(mktemp -d)"
    tmp_hashmap="$(mktemp)"
    discover_ssl_certs "${tmp_discovered}/tls.yaml"
    deep_merge_context "${tmp_discovered}" "${tmp_context}/_context.yaml"
    rm -rf "${tmp_discovered}"

    compute_hashsums_into "${tmp_context}/_context.yaml" "${tmp_hashmap}"
    local rc=0
    diff -q "${DST_DIR}/_hashsum.txt" "${tmp_hashmap}" >/dev/null 2>&1 || rc=1
    rm -rf "${tmp_hashmap}" "${tmp_context}"
    return ${rc}
}

###
### Build full configuration into an arbitrary target directory.
### Mirrors DST_DIR structure, copies private/ for cert references,
### then temporarily overrides DST_DIR/TCTX to run the full pipeline there.
###
function build_config_into() {
    local target="$1"

    local tmp_discovered
    tmp_discovered="$(mktemp -d)"

    find "${TMPL_DIR}/" -type d | sed 's@^'"${TMPL_DIR}"'/@@g' | xargs -r -I {} mkdir -p "${target}/{}"
    mkdir -p "${target}/private"
    cp -r "${DST_DIR}/private/." "${target}/private/"

    discover_ssl_certs "${tmp_discovered}/tls.yaml"
    deep_merge_context "${tmp_discovered}" "${target}/_context.yaml"
    rm -rf "${tmp_discovered}"

    template_nginx_configs "${target}/_context.yaml" "${target}"
}

###
### server: initial setup — create dirs, certs, dhparam, full templating, validate, then exec
###
function cmd_server() {
    find "${TMPL_DIR}/" -type d | sed 's@^'"${TMPL_DIR}"'/@@g' | xargs -r -I {} mkdir -p "${DST_DIR}/{}"
    mkdir -p "${DST_DIR}/private"

    local tmp_discovered
    tmp_discovered="$(mktemp -d)"

    create_dummy_tls_cert
    create_dhparam
    discover_ssl_certs "${tmp_discovered}/tls.yaml"
    deep_merge_context "${tmp_discovered}" "${TCTX}"
    rm -rf "${tmp_discovered}"

    template_nginx_configs "${TCTX}" "${DST_DIR}"
    validate_nginx_configs || exit 1
    compute_hashsums_into "${TCTX}" "${DST_DIR}/_hashsum.txt"

    exec nginx "$@"
}

###
### check: rebuild hashsum map and compare with stored; exit 0 if no changes
###
function cmd_check() {
    if hashsums_are_same; then
        echo "check: no changes detected"
        exit 0
    else
        echo "check: changes detected"
        exit 1
    fi
}

###
### reload: full templating into temp dir, validate, replace config, signal nginx, rebuild hashsums.
### Skips entirely if context and templates have not changed.
###
function cmd_reload() {
    if hashsums_are_same; then
        echo "reload: no changes detected, skipping"
        exit 0
    fi

    local reload_tmp backup_tmp
    reload_tmp="$(mktemp -d)"
    backup_tmp="$(mktemp -d)"
    trap "rm -rf ${reload_tmp} ${backup_tmp}" EXIT

    build_config_into "${reload_tmp}"

    # Back up current config (private/ excluded — certs managed separately)
    cp -r "${DST_DIR}"/* "${backup_tmp}/"

    # Install new config so nginx -t validates what will actually run
    cp -r "${reload_tmp}/"* "${DST_DIR}/"

    # Validate; restore backup on failure
    if ! validate_nginx_configs; then
        echo "reload: config validation failed, restoring previous config" >&2
        cp -r "${backup_tmp}/"* "${DST_DIR}/"
        exit 1
    fi

    nginx -s reload

    compute_hashsums_into "${TCTX}" "${DST_DIR}/_hashsum.txt"

    trap - EXIT
    rm -rf "${reload_tmp}" "${backup_tmp}"
}

###
### Argument parsing and dispatch
###
function show_help() {
    if [[ -n "$@" ]]; then
        echo "error: $@" >&2
    fi
    cat <<-EOF
Usage: $(basename "$0") [COMMAND] [ARGS...]

TLS multiplexer — nginx wrapper with dynamic config templating and certificate management.

Commands:
  server   Generate dummy cert, render templates, validate, and exec nginx.
           Any extra ARGS are forwarded to nginx.
  check    Compare current config/context hashsums against stored ones.
           Exits 0 if nothing changed, 1 if changes are detected.
  reload   Re-render config into a temp dir, validate, deploy, and send nginx
           a reload signal. No-ops if nothing changed. Reverts to previous config
           if validation fails.
  help     Show this help message.

Environment variables:
  TMPL_DIR              Directory with nginx config templates (default: /etc/template)
  DST_DIR               Directory where rendered configs are written (default: /etc/nginx)
  CTX_DIR               Directory with YAML context files to merge (default: /etc/config)
  STREAM_SNIPPETS_DIR   Optional directory with extra stream.d snippets
  HTTP_SNIPPETS_DIR     Optional directory with extra http.d snippets
  DHPARAM_SKIP          Skip DH param generation if "true" (default: false)
  DHPARAM_BITS          DH param bit size (default: 2048)
  DEBUG                 Set to any non-empty value to enable debug output

Examples:
  $(basename "$0") server
  $(basename "$0") server -g "daemon off;"
  $(basename "$0") check
  $(basename "$0") reload
EOF
    if [[ -n "$@" ]]; then
        exit 1
    fi
}

MODE=""
while [[ -n "${1:-}" ]]; do
    case "$1" in
        serve|server|nginx|check|reload)
            if [[ -n "${MODE}" ]]; then
                show_help "error: unexpected argument '$1' after mode '${MODE}'"
                exit 1
            fi
            MODE="$1"
            shift
            ;;
        -h|--help|help)
            show_help
            exit 0
            ;;
        *)
            if [[ -z "${MODE}" ]]; then
                show_help "error: unknown command '$1'"
                exit 1
            fi
            break
            ;;
    esac
done

case "${MODE:-server}" in
    serve|server|nginx)
        cmd_server "$@"
        ;;
    check)
        cmd_check
        ;;
    reload)
        cmd_reload
        ;;
esac
