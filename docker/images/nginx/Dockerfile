# syntax=docker/dockerfile:1.8

ARG ALPINE_BASE
FROM ${ALPINE_BASE}

ARG TARGETARCH
ARG PADM_VERSION
ARG SOURCE_URL
ARG VCS_REF
ARG NGINX_VERSION
ARG NGINX_PACKAGE_VERSION
ARG CA_CERTIFICATES_VERSION

RUN set -eux; \
    apk add --no-cache \
        "ca-certificates=${CA_CERTIFICATES_VERSION}" \
        "nginx=${NGINX_PACKAGE_VERSION}"; \
    addgroup -S -g 10001 padm; \
    adduser -S -D -H -u 10001 -G padm padm; \
    mkdir -p /etc/nginx/http.d /srv/padm; \
    chown -R 10001:10001 /etc/nginx/http.d /srv/padm

COPY --chown=10001:10001 --chmod=0644 nginx.conf /etc/nginx/nginx.conf
COPY --chown=10001:10001 --chmod=0644 default.conf /etc/nginx/http.d/default.conf

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
ENTRYPOINT ["/usr/sbin/nginx"]
CMD ["-g", "daemon off;"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 CMD ["/usr/bin/wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/healthz"]
