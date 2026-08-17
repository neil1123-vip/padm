# syntax=docker/dockerfile:1.8

ARG ALPINE_BASE
FROM ${ALPINE_BASE} AS fetch

ARG TARGETARCH
ARG UNZIP_VERSION
ARG XRAY_VERSION
ARG XRAY_AMD64_ASSET
ARG XRAY_AMD64_SHA256
ARG XRAY_ARM64_ASSET
ARG XRAY_ARM64_SHA256

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) asset="${XRAY_AMD64_ASSET}"; sha256="${XRAY_AMD64_SHA256}" ;; \
        arm64) asset="${XRAY_ARM64_ASSET}"; sha256="${XRAY_ARM64_SHA256}" ;; \
        *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    apk add --no-cache "unzip=${UNZIP_VERSION}"; \
    wget -q -O "/tmp/${asset}" "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/${asset}"; \
    echo "${sha256}  /tmp/${asset}" | sha256sum -c -; \
    mkdir /out; \
    unzip -q "/tmp/${asset}" xray geoip.dat geosite.dat -d /out; \
    test -x /out/xray; \
    test -s /out/geoip.dat; \
    test -s /out/geosite.dat

FROM ${ALPINE_BASE}

ARG TARGETARCH
ARG PADM_VERSION
ARG SOURCE_URL
ARG VCS_REF
ARG XRAY_VERSION
ARG CA_CERTIFICATES_VERSION

RUN set -eux; \
    apk add --no-cache "ca-certificates=${CA_CERTIFICATES_VERSION}"; \
    addgroup -S -g 10001 padm; \
    adduser -S -D -H -u 10001 -G padm padm; \
    mkdir -p /etc/padm/xray /usr/local/share/xray /var/lib/padm/xray; \
    chown -R 10001:10001 /etc/padm/xray /var/lib/padm/xray

COPY --from=fetch --chown=10001:10001 --chmod=0755 /out/xray /usr/local/bin/xray
COPY --from=fetch --chown=10001:10001 --chmod=0644 /out/geoip.dat /out/geosite.dat /usr/local/share/xray/

LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.version="${PADM_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      io.padm.image="xray" \
      io.padm.architecture="${TARGETARCH}" \
      io.padm.upstream.version="${XRAY_VERSION}" \
      io.padm.run-as="10001:10001" \
      io.padm.writable-paths="/tmp,/var/lib/padm/xray"

ENV XRAY_LOCATION_ASSET=/usr/local/share/xray
USER 10001:10001
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/xray"]
CMD ["run", "-confdir", "/etc/padm/xray"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 CMD ["/usr/local/bin/xray", "--version"]
