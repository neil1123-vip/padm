FROM joohoi/acme-dns:v2.0.1@sha256:aadaff68accfb1a301ff581f9140dd1e20bb4a4a6a2eb779079faf4705be89c4 AS upstream

FROM debian:bookworm-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587

# 官方二进制的 SQLite 运行需要原生 glibc，隔离验收复用固定 Debian 运行时。
COPY --from=upstream /usr/local/bin/acme-dns /usr/local/bin/acme-dns
RUN acme-dns -h \
    && apt-get update \
    && apt-get install -y --no-install-recommends unbound \
    && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["acme-dns"]
