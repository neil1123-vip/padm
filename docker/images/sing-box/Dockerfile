# syntax=docker/dockerfile:1.8

ARG DEBIAN_BASE
ARG DISTROLESS_STATIC_BASE
FROM ${DEBIAN_BASE} AS dependencies

ARG TARGETARCH
ARG DEBIAN_SNAPSHOT
ARG SING_BOX_VERSION
ARG SING_BOX_AMD64_ASSET
ARG SING_BOX_AMD64_SHA256
ARG SING_BOX_ARM64_ASSET
ARG SING_BOX_ARM64_SHA256

RUN set -eux; \
    rm -f /etc/apt/sources.list.d/debian.sources; \
    printf 'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/%s/ trixie main\n\
deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/%s/ trixie-security main\n' \
        "${DEBIAN_SNAPSHOT}" "${DEBIAN_SNAPSHOT}" > /etc/apt/sources.list; \
    apt-get update; \
    apt-get install --no-install-recommends -y binutils busybox-static ca-certificates curl libgcc-s1 libstdc++6 python3

COPY --from=runtime /export-runtime.py /usr/local/bin/export-runtime

FROM dependencies AS package

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) asset="${SING_BOX_AMD64_ASSET}"; sha256="${SING_BOX_AMD64_SHA256}" ;; \
        arm64) asset="${SING_BOX_ARM64_ASSET}"; sha256="${SING_BOX_ARM64_SHA256}" ;; \
        *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fLsS --connect-timeout 15 --max-time 300 --retry 3 \
        -o "/tmp/${asset}" "https://github.com/neil1123-vip/padm/releases/download/sing-box-${SING_BOX_VERSION}/${asset}"; \
    echo "${sha256}  /tmp/${asset}" | sha256sum -c -; \
    mkdir /out; \
    tar -xzf "/tmp/${asset}" --strip-components=1 -C /out; \
    test -x /out/sing-box; \
    test -s /out/libcronet.so; \
    test -s /out/LICENSE; \
    test -s /out/BUILD_INFO.json

FROM dependencies AS fetch

COPY --from=package /out/ /out/

RUN set -eux; \
    test -x /out/sing-box; \
    test -s /out/libcronet.so; \
    test -s /out/LICENSE; \
    test -s /out/BUILD_INFO.json; \
    install -m 0755 /out/sing-box /usr/local/bin/sing-box; \
    install -m 0644 /out/libcronet.so /usr/local/lib/libcronet.so; \
    strip --strip-unneeded /usr/local/lib/libcronet.so; \
    sha256sum /usr/local/lib/libcronet.so > /out/CRONET_RUNTIME_SHA256; \
    install -d -m 0755 /usr/share/doc/sing-box; \
    install -m 0644 /out/LICENSE /out/BUILD_INFO.json /out/CRONET_RUNTIME_SHA256 /usr/share/doc/sing-box/; \
    python3 /usr/local/bin/export-runtime /out/rootfs \
        /bin/busybox /usr/local/bin/sing-box /usr/local/lib/libcronet.so /usr/share/doc/sing-box; \
    chown 10001:10001 /out/rootfs/usr/local/bin/sing-box /out/rootfs/usr/local/lib/libcronet.so; \
    for applet in sh awk tr sed readlink cat grep; do ln -s busybox "/out/rootfs/bin/${applet}"; done; \
    install -d -o 10001 -g 10001 /out/rootfs/etc/padm/sing-box /out/rootfs/var/lib/padm/sing-box

FROM ${DISTROLESS_STATIC_BASE}

ARG TARGETARCH
ARG SING_BOX_VERSION

COPY --from=fetch /out/rootfs/ /
COPY --from=runtime /passwd /group /nsswitch.conf /etc/

ARG PADM_VERSION
ARG SOURCE_URL
ARG VCS_REF
LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.version="${PADM_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      io.padm.image="sing-box" \
      io.padm.architecture="${TARGETARCH}" \
      io.padm.upstream.version="${SING_BOX_VERSION}" \
      io.padm.run-as="10001:10001" \
      io.padm.writable-paths="/tmp,/var/lib/padm/sing-box"

ENV LD_LIBRARY_PATH=/usr/local/lib
ENV LD_PRELOAD=/usr/local/lib/libcronet.so
USER 10001:10001
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/sing-box"]
CMD ["run", "-D", "/var/lib/padm/sing-box", "-c", "/etc/padm/sing-box/config.json"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 CMD ["/usr/local/bin/sing-box", "check", "-D", "/var/lib/padm/sing-box", "-c", "/etc/padm/sing-box/config.json"]
