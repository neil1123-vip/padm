# syntax=docker/dockerfile:1.8

ARG PYTHON_BASE
ARG DISTROLESS_STATIC_BASE
FROM ${PYTHON_BASE} AS build-runtime

ARG DEBIAN_SNAPSHOT

RUN set -eux; \
    rm -f /etc/apt/sources.list.d/debian.sources; \
    printf '%s\n' \
        "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/ trixie main" \
        "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/ trixie-updates main" \
        "deb [check-valid-until=no] https://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}/ trixie-security main" \
        >/etc/apt/sources.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        busybox-static ca-certificates coreutils curl diffutils openssl socat

ARG ACME_SH_VERSION
ARG ACME_SH_URL
ARG ACME_SH_SHA256

COPY --from=runtime /export-runtime.py /usr/local/bin/export-runtime

ENV PYTHONDONTWRITEBYTECODE=1

RUN set -eux; \
    rm -rf /usr/local/lib/python3.14/tkinter /usr/local/lib/python3.14/idlelib \
        /usr/local/lib/python3.14/turtledemo /usr/local/lib/python3.14/lib-dynload/_tkinter.*.so; \
    curl --fail --location --silent --show-error --output /tmp/acme.tar.gz "${ACME_SH_URL}"; \
    echo "${ACME_SH_SHA256}  /tmp/acme.tar.gz" | sha256sum -c -; \
    mkdir -p "/tmp/acme.sh-${ACME_SH_VERSION}" /opt/acme /opt/padm/subscription /var/lib/padm/acme /var/lib/padm/subscription; \
    tar -xzf /tmp/acme.tar.gz -C /tmp; \
    cp -a "/tmp/acme.sh-${ACME_SH_VERSION}/acme.sh" "/tmp/acme.sh-${ACME_SH_VERSION}/dnsapi" \
        "/tmp/acme.sh-${ACME_SH_VERSION}/deploy" "/tmp/acme.sh-${ACME_SH_VERSION}/notify" \
        "/tmp/acme.sh-${ACME_SH_VERSION}/LICENSE.md" /opt/acme/; \
    test -x /opt/acme/acme.sh; \
    /bin/sh -n /opt/acme/acme.sh; \
    python3 /usr/local/bin/export-runtime /out/rootfs \
        /bin/busybox /bin/sh /usr/bin/env /usr/bin/date /usr/bin/cmp \
        /usr/bin/curl /usr/bin/openssl /usr/bin/socat \
        /usr/local/bin/python3 /usr/local/lib/python3.14 \
        /usr/lib/ssl /etc/ssl/openssl.cnf /etc/ssl/certs /usr/share/ca-certificates \
        /opt/acme /opt/padm /var/lib/padm; \
    for directory in /usr/lib/*-linux-gnu/ossl-modules; do \
        [ ! -d "${directory}" ] || python3 /usr/local/bin/export-runtime /out/rootfs "${directory}"; \
    done; \
    ldconfig -r /out/rootfs /usr/local/lib; \
    chown -R 10001:10001 /out/rootfs/opt/acme /out/rootfs/opt/padm /out/rootfs/var/lib/padm; \
    mkdir -p /out/rootfs/bin /out/rootfs/tmp; \
    chmod 1777 /out/rootfs/tmp; \
    for applet in $(busybox --list); do \
        case "${applet}" in dpkg|dpkg-deb|rpm|rpm2cpio) continue ;; esac; \
        [ -e "/out/rootfs/bin/${applet}" ] || [ -e "/out/rootfs/sbin/${applet}" ] || \
            ln -s /bin/busybox "/out/rootfs/bin/${applet}"; \
    done; \
    chroot /out/rootfs /usr/local/bin/python3 -c 'import ssl, sqlite3, urllib.request, http.server'; \
    chroot /out/rootfs /usr/bin/openssl version; \
    chroot /out/rootfs /usr/bin/curl --version; \
    dpkg-query -W -f='${Package}\t${Version}\n' > /out/rootfs/usr/share/padm/build-packages.txt

FROM ${DISTROLESS_STATIC_BASE}

ARG TARGETARCH
ARG ACME_SH_VERSION

COPY --from=build-runtime /out/rootfs/ /
COPY --from=runtime /passwd /group /nsswitch.conf /etc/

COPY --chown=10001:10001 --chmod=0755 entrypoint.sh /usr/local/bin/padm-entrypoint
COPY --chown=10001:10001 --chmod=0755 control_server.py /opt/padm/subscription/control_server.py
COPY --chown=10001:10001 --chmod=0755 control_api.py /opt/padm/control_api.py
COPY --chown=10001:10001 --chmod=0755 control_sync.py /opt/padm/control_sync.py
COPY --chown=10001:10001 --chmod=0755 control_client.py /opt/padm/control_client.py
COPY --chown=10001:10001 --chmod=0755 control_state.py /opt/padm/control_state.py

ARG PADM_VERSION
ARG SOURCE_URL
ARG VCS_REF
LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.version="${PADM_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      io.padm.image="ops" \
      io.padm.architecture="${TARGETARCH}" \
      io.padm.upstream.version="acme.sh-${ACME_SH_VERSION}" \
      io.padm.run-as="10001:10001" \
      io.padm.writable-paths="/tmp,/var/lib/padm"

ENV PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    PYTHONDONTWRITEBYTECODE=1
USER 10001:10001
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/padm-entrypoint"]
CMD ["idle"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 CMD ["/usr/local/bin/padm-entrypoint", "health"]
