# syntax=docker/dockerfile:1.8

ARG DEBIAN_BASE
ARG DISTROLESS_STATIC_BASE
FROM ${DEBIAN_BASE} AS fetch

ARG TARGETARCH
ARG DEBIAN_SNAPSHOT
ARG XRAY_VERSION
ARG XRAY_AMD64_ASSET
ARG XRAY_AMD64_SHA256
ARG XRAY_ARM64_ASSET
ARG XRAY_ARM64_SHA256

RUN set -eux; \
    rm -f /etc/apt/sources.list.d/debian.sources; \
    printf 'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/%s/ trixie main\n\
deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/%s/ trixie-security main\n' \
        "${DEBIAN_SNAPSHOT}" "${DEBIAN_SNAPSHOT}" > /etc/apt/sources.list; \
    apt-get update; \
    apt-get install --no-install-recommends -y busybox-static ca-certificates curl python3 unzip

COPY --from=runtime /export-runtime.py /usr/local/bin/export-runtime

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) asset="${XRAY_AMD64_ASSET}"; sha256="${XRAY_AMD64_SHA256}" ;; \
        arm64) asset="${XRAY_ARM64_ASSET}"; sha256="${XRAY_ARM64_SHA256}" ;; \
        *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fLsS --connect-timeout 15 --max-time 300 --retry 3 \
        -o "/tmp/${asset}" "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/${asset}"; \
    echo "${sha256}  /tmp/${asset}" | sha256sum -c -; \
    mkdir /out; \
    unzip -q "/tmp/${asset}" xray geoip.dat geosite.dat -d /out; \
    test -x /out/xray; \
    test -s /out/geoip.dat; \
    test -s /out/geosite.dat; \
    if ldd /out/xray > /tmp/xray.ldd 2>&1; then cat /tmp/xray.ldd >&2; exit 1; fi; \
    grep -Eq 'not a dynamic executable|statically linked' /tmp/xray.ldd; \
    python3 /usr/local/bin/export-runtime /out/rootfs /bin/busybox; \
    install -D -o 10001 -g 10001 -m 0755 /out/xray /out/rootfs/usr/local/bin/xray; \
    install -d -o 10001 -g 10001 -m 0755 /out/rootfs/usr/local/share/xray; \
    install -o 10001 -g 10001 -m 0644 /out/geoip.dat /out/geosite.dat /out/rootfs/usr/local/share/xray/; \
    for applet in sh awk; do ln -s busybox "/out/rootfs/bin/${applet}"; done; \
    install -d -o 10001 -g 10001 /out/rootfs/etc/padm/xray /out/rootfs/var/lib/padm/xray

FROM ${DISTROLESS_STATIC_BASE}

ARG TARGETARCH
ARG XRAY_VERSION

COPY --from=fetch /out/rootfs/ /
COPY --from=runtime /passwd /group /nsswitch.conf /etc/

ARG PADM_VERSION
ARG SOURCE_URL
ARG VCS_REF
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
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 CMD ["/usr/local/bin/xray", "-test", "-confdir", "/etc/padm/xray"]
