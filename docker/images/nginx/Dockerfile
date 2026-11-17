# syntax=docker/dockerfile:1.8

ARG NGINX_BASE
ARG DISTROLESS_STATIC_BASE
FROM ${NGINX_BASE} AS runtime-files

ARG DEBIAN_SNAPSHOT
ARG NGINX_VERSION

RUN set -eux; \
    test "$(nginx -v 2>&1)" = "nginx version: nginx/${NGINX_VERSION}"; \
    nginx -V 2>&1 | grep -Eq -- '(^| )--with-stream( |$)'; \
    rm -f /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list.d/nginx.list; \
    printf 'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/%s/ trixie main\n\
deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/%s/ trixie-security main\n' \
        "${DEBIAN_SNAPSHOT}" "${DEBIAN_SNAPSHOT}" > /etc/apt/sources.list; \
    apt-get update; \
    apt-get install --no-install-recommends -y busybox-static python3

COPY --from=runtime /export-runtime.py /usr/local/bin/export-runtime

RUN set -eux; \
    python3 /usr/local/bin/export-runtime /out/rootfs /bin/busybox /usr/sbin/nginx /etc/nginx/mime.types; \
    install -d /out/rootfs/usr/bin; \
    for applet in sh awk cat; do ln -s busybox "/out/rootfs/bin/${applet}"; done; \
    ln -s /bin/busybox /out/rootfs/usr/bin/wget; \
    install -d -o 10001 -g 10001 /out/rootfs/etc/nginx/http.d /out/rootfs/etc/nginx/stream.d /out/rootfs/srv/padm

FROM ${DISTROLESS_STATIC_BASE}

ARG TARGETARCH
ARG NGINX_VERSION

COPY --from=runtime-files /out/rootfs/ /
COPY --from=runtime /passwd /group /nsswitch.conf /etc/

COPY --chown=10001:10001 --chmod=0644 nginx.conf /etc/nginx/nginx.conf
COPY --chown=10001:10001 --chmod=0644 default.conf /etc/nginx/http.d/default.conf

ARG PADM_VERSION
ARG SOURCE_URL
ARG VCS_REF
LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.version="${PADM_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      io.padm.image="nginx" \
      io.padm.architecture="${TARGETARCH}" \
      io.padm.upstream.version="${NGINX_VERSION}" \
      io.padm.run-as="10001:10001" \
      io.padm.writable-paths="/tmp"

USER 10001:10001
EXPOSE 8080
STOPSIGNAL SIGQUIT
ENTRYPOINT ["/usr/sbin/nginx", "-e", "/dev/stderr"]
CMD ["-g", "daemon off;"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 CMD ["/usr/bin/wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/healthz"]
