# syntax=docker/dockerfile:1.8

ARG ALPINE_BASE
FROM ${ALPINE_BASE}

ARG TARGETARCH
ARG PADM_VERSION
ARG SOURCE_URL
ARG VCS_REF
ARG BASH_VERSION
ARG CA_CERTIFICATES_VERSION
ARG FAIL2BAN_VERSION
ARG IPROUTE2_VERSION
ARG IPTABLES_VERSION
ARG NFTABLES_VERSION
ARG WIREGUARD_TOOLS_VERSION

RUN set -eux; \
    apk add --no-cache \
        "bash=${BASH_VERSION}" \
        "ca-certificates=${CA_CERTIFICATES_VERSION}" \
        "fail2ban=${FAIL2BAN_VERSION}" \
        "iproute2=${IPROUTE2_VERSION}" \
        "iptables=${IPTABLES_VERSION}" \
        "nftables=${NFTABLES_VERSION}" \
        "wireguard-tools=${WIREGUARD_TOOLS_VERSION}"; \
    mkdir -p /etc/padm/net /var/lib/padm/net

COPY --chmod=0755 entrypoint.sh /usr/local/bin/padm-entrypoint

LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.version="${PADM_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      io.padm.image="net" \
      io.padm.architecture="${TARGETARCH}" \
      io.padm.upstream.version="wireguard-tools-${WIREGUARD_TOOLS_VERSION},fail2ban-${FAIL2BAN_VERSION}" \
      io.padm.run-as="0:0" \
      io.padm.writable-paths="/run,/tmp,/var/lib/padm/net"

USER 0:0
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/padm-entrypoint"]
CMD ["idle"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 CMD ["/usr/local/bin/padm-entrypoint", "health"]
