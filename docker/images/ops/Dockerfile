# syntax=docker/dockerfile:1.8

ARG ALPINE_BASE
FROM ${ALPINE_BASE}

ARG TARGETARCH
ARG PADM_VERSION
ARG SOURCE_URL
ARG VCS_REF
ARG ACME_SH_VERSION
ARG ACME_SH_URL
ARG ACME_SH_SHA256
ARG CA_CERTIFICATES_VERSION
ARG OPENSSL_VERSION
ARG PYTHON3_VERSION
ARG SOCAT_VERSION

RUN set -eux; \
    apk add --no-cache \
        "ca-certificates=${CA_CERTIFICATES_VERSION}" \
        "openssl=${OPENSSL_VERSION}" \
        "python3=${PYTHON3_VERSION}" \
        "socat=${SOCAT_VERSION}"; \
    wget -q -O /tmp/acme.tar.gz "${ACME_SH_URL}"; \
    echo "${ACME_SH_SHA256}  /tmp/acme.tar.gz" | sha256sum -c -; \
    mkdir -p "/tmp/acme.sh-${ACME_SH_VERSION}" /opt/acme /opt/padm/subscription /var/lib/padm/acme /var/lib/padm/subscription; \
    tar -xzf /tmp/acme.tar.gz -C /tmp; \
    cp -a "/tmp/acme.sh-${ACME_SH_VERSION}/." /opt/acme/; \
    test -x /opt/acme/acme.sh; \
    /bin/sh -n /opt/acme/acme.sh; \
    addgroup -S -g 10001 padm; \
    adduser -S -D -H -u 10001 -G padm padm; \
    chown -R 10001:10001 /opt/acme /opt/padm /var/lib/padm; \
    rm -rf /tmp/acme.tar.gz "/tmp/acme.sh-${ACME_SH_VERSION}"

COPY --chown=10001:10001 --chmod=0755 entrypoint.sh /usr/local/bin/padm-entrypoint
COPY --chown=10001:10001 --chmod=0755 control_server.py /opt/padm/subscription/control_server.py

LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.version="${PADM_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      io.padm.image="ops" \
      io.padm.architecture="${TARGETARCH}" \
      io.padm.upstream.version="acme.sh-${ACME_SH_VERSION}" \
      io.padm.run-as="10001:10001" \
      io.padm.writable-paths="/tmp,/var/lib/padm"

USER 10001:10001
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/padm-entrypoint"]
CMD ["idle"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 CMD ["/usr/local/bin/padm-entrypoint", "health"]
