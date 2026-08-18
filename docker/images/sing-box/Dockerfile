# syntax=docker/dockerfile:1.8

ARG ALPINE_BASE
FROM ${ALPINE_BASE} AS fetch

ARG TARGETARCH
ARG SING_BOX_VERSION
ARG SING_BOX_AMD64_ASSET
ARG SING_BOX_AMD64_SHA256
ARG SING_BOX_ARM64_ASSET
ARG SING_BOX_ARM64_SHA256

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) asset="${SING_BOX_AMD64_ASSET}"; sha256="${SING_BOX_AMD64_SHA256}" ;; \
        arm64) asset="${SING_BOX_ARM64_ASSET}"; sha256="${SING_BOX_ARM64_SHA256}" ;; \
        *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    wget -q -O "/tmp/${asset}" "https://github.com/SagerNet/sing-box/releases/download/${SING_BOX_VERSION}/${asset}"; \
    echo "${sha256}  /tmp/${asset}" | sha256sum -c -; \
    mkdir /out; \
    tar -xzf "/tmp/${asset}" --strip-components=1 -C /out; \
    test -x /out/sing-box; \
    test -s /out/libcronet.so

FROM ${ALPINE_BASE}

ARG TARGETARCH
ARG PADM_VERSION
ARG SOURCE_URL
ARG VCS_REF
ARG SING_BOX_VERSION
ARG CA_CERTIFICATES_VERSION
ARG GCOMPAT_VERSION

RUN set -eux; \
    apk add --no-cache \
        "ca-certificates=${CA_CERTIFICATES_VERSION}" \
        "gcompat=${GCOMPAT_VERSION}"; \
    addgroup -S -g 10001 padm; \
    adduser -S -D -H -u 10001 -G padm padm; \
    mkdir -p /etc/padm/sing-box /var/lib/padm/sing-box; \
    chown -R 10001:10001 /etc/padm/sing-box /var/lib/padm/sing-box

COPY --from=fetch --chown=10001:10001 --chmod=0755 /out/sing-box /usr/local/bin/sing-box
COPY --from=fetch --chown=10001:10001 --chmod=0644 /out/libcronet.so /usr/local/lib/libcronet.so

LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.version="${PADM_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      io.padm.image="sing-box" \
      io.padm.architecture="${TARGETARCH}" \
      io.padm.upstream.version="${SING_BOX_VERSION}" \
      io.padm.run-as="10001:10001" \
      io.padm.writable-paths="/tmp,/var/lib/padm/sing-box"

ENV LD_LIBRARY_PATH=/usr/local/lib
USER 10001:10001
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/sing-box"]
CMD ["run", "-D", "/var/lib/padm/sing-box", "-c", "/etc/padm/sing-box/config.json"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 CMD ["/usr/local/bin/sing-box", "check", "-D", "/var/lib/padm/sing-box", "-c", "/etc/padm/sing-box/config.json"]
