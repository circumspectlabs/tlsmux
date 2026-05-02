ARG ALPINE_VERSION=3.23

FROM nginx:stable-alpine${ALPINE_VERSION}-slim AS base

RUN apk add --no-cache             \
        bash                       \
        ca-certificates            \
        curl                       \
        file                       \
        libgcc                     \
        openssl                    \
        pcre                       \
        perl                       \
        perl-yaml                  \
        perl-hash-merge            \
        perl-hash-merge-simple     \
        zlib

FROM base AS build

RUN apk add --no-cache             \
        bison                      \
        g++                        \
        gcc                        \
        git                        \
        linux-headers              \
        make                       \
        musl-dev                   \
        openssl-dev                \
        pcre-dev                   \
        perl-dev                   \
        zlib-dev                && \
    git config --global advice.detachedHead false

# Get sources
RUN cd /tmp                     && \
    mkdir -p nginx module lua   && \
    git clone --depth 1 --branch release-${NGINX_VERSION} https://github.com/nginx/nginx nginx

# Get modules
ARG MODULE_VTS_VERSION=0.2.5
ARG MODULE_MORE_VERSION=0.39
ARG MODULE_NDK_VERSION=0.3.3
ARG MODULE_LUA_VERSION=0.10.29R2
ARG MODULE_LUA_STREAM_VERSION=0.0.17R4
ARG MODULE_LUA_UPSTREAM_VERSION=0.07
ARG MODULE_RATELIMIT_VERSION=1.0.0
ARG MODULE_REPLACE_FILTER_VERSION=0.01rc5
ARG MODULE_ECHO_VERSION=0.64

RUN cd /tmp/module              && \
    mkdir -p nginx vts more ndk lua lua-stream lua-upstream opentracing ratelimit replace-filter echo && \
    git clone --depth 1 --branch v${MODULE_VTS_VERSION} https://github.com/vozlt/nginx-module-vts vts && \
    git clone --depth 1 --branch v${MODULE_MORE_VERSION} https://github.com/openresty/headers-more-nginx-module more && \
    git clone --depth 1 --branch v${MODULE_NDK_VERSION} https://github.com/vision5/ngx_devel_kit ndk && \
    git clone --depth 1 --branch v${MODULE_LUA_VERSION} https://github.com/openresty/lua-nginx-module lua && \
    git clone --depth 1 --branch v${MODULE_LUA_STREAM_VERSION} https://github.com/openresty/stream-lua-nginx-module lua-stream && \
    git clone --depth 1 --branch v${MODULE_LUA_UPSTREAM_VERSION} https://github.com/openresty/lua-upstream-nginx-module lua-upstream && \
    git clone --depth 1 --branch v${MODULE_RATELIMIT_VERSION} https://github.com/weserv/rate-limit-nginx-module ratelimit && \
    git clone --depth 1 --branch v${MODULE_REPLACE_FILTER_VERSION} https://github.com/openresty/replace-filter-nginx-module replace-filter && \
    git clone --depth 1 --branch v${MODULE_ECHO_VERSION} https://github.com/openresty/echo-nginx-module echo

# Lua libraries and dependencies
ARG LUA_JIT_VERSION=2.1-20260114
ARG LUA_CORE_VERSION=0.1.32R1
ARG LUA_LRUCACHE_VERSION=0.15
ARG LUA_HMAC_VERSION=0.06-1
ARG LUA_STRING_VERSION=0.16
ARG LUA_WEBSOCKET_VERSION=0.13
ARG LUA_SHDICT_VERSION=0.01rc5
ARG LUA_HC_VERSION=0.08
ARG LUA_MEMCACHED_VERSION=0.17
ARG LUA_DNS_VERSION=0.23
ARG LUA_LOCK_VERSION=0.09
ARG LUA_SHELL_VERSION=0.03
ARG LUA_REDIS_VERSION=0.33
ARG LUA_CJSON_VERSION=2.1.0.16
ARG LUA_SREGEX_VERSION=0.0.1
ARG LUA_JWT_VERSION=0.1.11
ARG LUA_IPMATCHER_VERSION=0.6.1

RUN cd /tmp/lua && \
    mkdir -p jit core lrucache hmac string websocket shdict hc memcached dns lock shell redis cjson sregex jwt ipmatcher && \
    git clone --depth 1 --branch v${LUA_JIT_VERSION} https://github.com/openresty/luajit2 jit && \
    git clone --depth 1 --branch v${LUA_CORE_VERSION} https://github.com/openresty/lua-resty-core core && \
    git clone --depth 1 --branch v${LUA_LRUCACHE_VERSION} https://github.com/openresty/lua-resty-lrucache lrucache && \
    git clone --depth 1 --branch ${LUA_HMAC_VERSION} https://github.com/jkeys089/lua-resty-hmac hmac && \
    git clone --depth 1 --branch v${LUA_STRING_VERSION} https://github.com/openresty/lua-resty-string string && \
    git clone --depth 1 --branch v${LUA_WEBSOCKET_VERSION} https://github.com/openresty/lua-resty-websocket websocket && \
    git clone --depth 1 --branch v${LUA_SHDICT_VERSION} https://github.com/openresty/lua-resty-shdict-simple shdict && \
    git clone --depth 1 --branch v${LUA_HC_VERSION} https://github.com/openresty/lua-resty-upstream-healthcheck hc && \
    git clone --depth 1 --branch v${LUA_MEMCACHED_VERSION} https://github.com/openresty/lua-resty-memcached memcached && \
    git clone --depth 1 --branch v${LUA_DNS_VERSION} https://github.com/openresty/lua-resty-dns dns && \
    git clone --depth 1 --branch v${LUA_LOCK_VERSION} https://github.com/openresty/lua-resty-lock lock && \
    git clone --depth 1 --branch v${LUA_SHELL_VERSION} https://github.com/openresty/lua-resty-shell shell && \
    git clone --depth 1 --branch v${LUA_REDIS_VERSION} https://github.com/openresty/lua-resty-redis redis && \
    git clone --depth 1 --branch ${LUA_CJSON_VERSION} https://github.com/openresty/lua-cjson cjson && \
    git clone --depth 1 --branch v${LUA_SREGEX_VERSION} https://github.com/openresty/sregex sregex && \
    git clone --depth 1 --branch v${LUA_JWT_VERSION} https://github.com/SkyLothar/lua-resty-jwt jwt && \
    git clone --depth 1 --branch v${LUA_IPMATCHER_VERSION} https://github.com/api7/lua-resty-ipmatcher ipmatcher

# Build Lua JIT
RUN cd /tmp/lua/jit               && \
    make -j$(nproc) PREFIX=/usr/local && \
    make install PREFIX=/usr/local

# Build Lua libraries
RUN cd /tmp/lua                   && \
    for i in core lrucache hmac string websocket shdict hc memcached dns lock shell redis cjson sregex ipmatcher; do \
        cd /tmp/lua/$i            && \
        make -j$(nproc) install PREFIX=/usr/local LUA_INCLUDE_DIR=/usr/local/include/luajit-2.1; \
    done                          && \
    mv /usr/local/lualib/resty/*.lua /usr/local/lib/lua/resty/ && \
    rm -r /usr/local/lualib       && \
    cp /tmp/lua/jwt/lib/resty/*.lua /usr/local/lib/lua/resty/ && \
    cp /usr/share/lua/5.1/resty/*.lua /usr/local/lib/lua/resty/

ARG LUAJIT_LIB=/usr/local/lib
ARG LUAJIT_INC=/usr/local/include/luajit-2.1

RUN cd /tmp/nginx                 && \
    ./auto/configure                 \
        --prefix=/etc/nginx          \
        --sbin-path=/usr/sbin/nginx  \
        --modules-path=/usr/lib/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/var/run/nginx.pid \
        --lock-path=/var/run/nginx.lock \
        --http-client-body-temp-path=/var/cache/nginx/client_temp \
        --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
        --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
        --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
        --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
        --with-perl_modules_path=/usr/lib/perl5/vendor_perl \
        --user=nginx \
        --group=nginx \
        --with-compat \
        --with-file-aio \
        --with-threads \
        --with-http_addition_module \
        --with-http_auth_request_module \
        --with-http_dav_module \
        --with-http_flv_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_mp4_module \
        --with-http_random_index_module \
        --with-http_realip_module \
        --with-http_secure_link_module \
        --with-http_slice_module \
        --with-http_ssl_module \
        --with-http_stub_status_module \
        --with-http_sub_module \
        --with-http_v2_module \
        --with-http_v3_module \
        --with-mail \
        --with-mail_ssl_module \
        --with-stream \
        --with-stream_realip_module \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-cc-opt='-Os -fstack-clash-protection -Wformat -Werror=format-security -g' \
        --with-ld-opt='-Wl,-rpath,--as-needed,-O1,--sort-common -Wl,-z,pack-relative-relocs,-lpcre,-E' \
        \
        --add-dynamic-module=/tmp/module/vts \
        --add-dynamic-module=/tmp/module/more \
        --add-dynamic-module=/tmp/module/ndk \
        --add-dynamic-module=/tmp/module/lua \
        --add-dynamic-module=/tmp/module/lua-stream \
        --add-dynamic-module=/tmp/module/lua-upstream \
        --add-dynamic-module=/tmp/module/ratelimit \
        --add-dynamic-module=/tmp/module/replace-filter \
        --add-dynamic-module=/tmp/module/echo && \
        make -j$(nproc) modules

# Composing and dropping debug symbols
RUN mkdir -p /output                 && \
    cd /output                       && \
    mkdir -p                            \
        ./usr/lib/nginx/modules/        \
        ./usr/local/bin                 \
        ./usr/local/lib                 \
        ./usr/local/share/lua/5.1    && \
    cp -r /tmp/nginx/objs/*.so          \
        ./usr/lib/nginx/modules/     && \
    cp -r /usr/local/bin/*              \
        ./usr/local/bin/             && \
    cp -r /usr/local/lib/*              \
        ./usr/local/lib/             && \
    cp -r /usr/local/share/lua          \
        ./usr/local/share/lua        && \
    cp -r /usr/local/share/luajit-2.1   \
        ./usr/local/share/luajit-2.1 && \
    rm -r ./usr/local/lib/pkgconfig  && \
    \
    echo "Lua modules magic"         && \
    ln -s /usr/local/lib/lua/resty      \
        ./usr/local/share/lua/5.1/resty && \
    ln -s /usr/local/lib/lua/ngx        \
        ./usr/local/share/lua/5.1/ngx && \
    \
    echo "Stripping things"          && \
    find ./usr/lib/nginx/modules -type f \
        -exec strip -g -S -d --strip-debug {} \; && \
    strip -g -S -d --strip-debug        \
        ./usr/local/lib/libluajit-5.1.so && \
    strip -g -S -d --strip-debug        \
        ./usr/local/lib/libsregex.so && \
    strip -g -S -d --strip-debug        \
        ./usr/local/bin/luajit       && \
    strip -g -S -d --strip-debug        \
        ./usr/local/bin/sregex-cli

FROM base AS binaries

ARG GOTEMPLATE_VERSION=3.12.0
RUN cd /tmp                                  && \
    apk add --no-cache                          \
        git                                     \
        go                                   && \
    git config --global advice.detachedHead false && \
    git clone --depth 1 --branch v${GOTEMPLATE_VERSION} https://github.com/coveooss/gotemplate && \
    cd gotemplate                            && \
    go build -ldflags "-s -w" .              && \
    strip -g -S -d --strip-debug ./gotemplate

# Compose
RUN mkdir -p /output/usr/local/bin           && \
    cd /output                               && \
    cp /tmp/gotemplate/gotemplate               \
        ./usr/local/bin/

FROM base AS compose

COPY --from=build /output /output
COPY --from=binaries /output /output

COPY ./tlsmux.sh /output/usr/local/bin/tlsmux.sh
COPY ./config /output/etc/config-example
COPY ./template /output/etc/template

RUN cd /output                               && \
    mkdir -p ./etc/template                  && \
    chmod 755 ./usr/local/bin/tlsmux.sh      && \
    ln -s tlsmux.sh ./usr/local/bin/tlsmux   && \
    chmod 755 -R ./etc/template              && \
    find ./etc/template -type f -exec chmod 644 {} \; && \
    find ./etc/template -type d -exec chmod 755 {} \; && \
    mkdir -p ./etc/config

FROM base

# Folder permissions
RUN rm /etc/nginx/conf.d/* || true           && \
    touch /var/run/nginx.pid                 && \
    chown nginx:nginx -R                        \
        /var/cache/nginx                        \
        /etc/nginx                              \
        /var/run/nginx.pid

COPY --from=compose /output /

USER nginx:nginx
ENTRYPOINT [ "tlsmux" ]
CMD ["server"]
