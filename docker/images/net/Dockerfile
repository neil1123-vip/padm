# syntax=docker/dockerfile:1.8

ARG DEBIAN_BASE
ARG DISTROLESS_STATIC_BASE
FROM ${DEBIAN_BASE} AS build-runtime

ARG DEBIAN_SNAPSHOT

RUN set -eux; \
    rm -f /etc/apt/sources.list.d/debian.sources; \
    printf '%s\n' \
        "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/ trixie main" \
        "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/ trixie-updates main" \
        "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}/ trixie-security main" \
        >/etc/apt/sources.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bash busybox-static ca-certificates diffutils fail2ban iproute2 iptables \
        nftables python3 python3-pyinotify wireguard-tools

COPY --from=runtime /export-runtime.py /usr/local/bin/export-runtime

ENV PYTHONDONTWRITEBYTECODE=1

RUN set -eux; \
    mkdir -p /etc/padm/net /etc/wireguard /var/lib/padm/net /usr/local/lib/padm; \
    chmod 0755 /usr/local/lib/padm; \
    python3 /usr/local/bin/export-runtime /out/rootfs \
        /bin/busybox /bin/sh /bin/bash /usr/bin/env /usr/bin/cmp \
        /usr/bin/python3 /usr/lib/python3 /usr/lib/python3.* \
        /usr/bin/fail2ban-client /usr/bin/fail2ban-server /etc/fail2ban \
        /usr/bin/wg /usr/bin/wg-quick /usr/sbin/ip /usr/sbin/nft \
        /usr/sbin/iptables /usr/sbin/ip6tables \
        /usr/sbin/iptables-save /usr/sbin/ip6tables-save \
        /usr/sbin/iptables-restore /usr/sbin/ip6tables-restore \
        /usr/lib/*-linux-gnu/xtables /etc/ssl/certs \
        /etc/padm /etc/wireguard /var/lib/padm /usr/local/lib/padm; \
    for directory in /etc/iproute2 /usr/lib/iproute2; do \
        [ ! -d "${directory}" ] || python3 /usr/local/bin/export-runtime /out/rootfs "${directory}"; \
    done; \
    mkdir -p /out/rootfs/bin /out/rootfs/run/fail2ban /out/rootfs/tmp; \
    chmod 1777 /out/rootfs/tmp; \
    for applet in $(busybox --list); do \
        case "${applet}" in dpkg|dpkg-deb|rpm|rpm2cpio) continue ;; esac; \
        [ -e "/out/rootfs/bin/${applet}" ] || [ -e "/out/rootfs/sbin/${applet}" ] || \
            ln -s /bin/busybox "/out/rootfs/bin/${applet}"; \
    done; \
    chroot /out/rootfs /usr/bin/python3 -c 'import fail2ban, ssl, sqlite3, systemd, pyinotify'; \
    chroot /out/rootfs /usr/bin/fail2ban-client --version; \
    chroot /out/rootfs /usr/sbin/iptables --version; \
    chroot /out/rootfs /usr/sbin/nft --version; \
    chroot /out/rootfs /usr/bin/wg --version; \
    dpkg-query -W -f='${Package}\t${Version}\n' > /out/rootfs/usr/share/padm/build-packages.txt

FROM ${DISTROLESS_STATIC_BASE}

ARG TARGETARCH
ARG DEBIAN_SNAPSHOT

COPY --from=build-runtime /out/rootfs/ /
COPY --from=runtime /passwd /group /nsswitch.conf /etc/

COPY --chmod=0755 entrypoint.sh /usr/local/bin/padm-entrypoint
COPY --chmod=0644 tun-resources.py /usr/local/lib/padm/tun-resources.py

ARG PADM_VERSION
ARG SOURCE_URL
ARG VCS_REF
LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.version="${PADM_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      io.padm.image="net" \
      io.padm.architecture="${TARGETARCH}" \
      io.padm.upstream.version="debian-snapshot-${DEBIAN_SNAPSHOT}" \
      io.padm.run-as="0:0" \
      io.padm.writable-paths="/run,/tmp,/var/lib/padm/net"

ENV PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    PYTHONDONTWRITEBYTECODE=1
USER 0:0
STOPSIGNAL SIGTERM
ENTRYPOINT ["/usr/local/bin/padm-entrypoint"]
CMD ["idle"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 CMD ["/usr/local/bin/padm-entrypoint", "health"]
