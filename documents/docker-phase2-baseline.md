# Docker 容器化阶段 2 基线

日期：2026-08-17

## 结论

阶段 2 已实现 5 个由本仓库定义、后续由本仓库 CI 构建的应用镜像。生产机只消费
CI 发布的 digest，不执行 `docker build`，也不直接部署 Xray、sing-box 或 Nginx
的上游应用镜像。

本地已完成锁文件、Bake、Compose 和权限合同验证。本机 Docker daemon 未运行，
因此没有声称镜像已经完成真实 build/run；双架构镜像 smoke 是阶段 5 CI 的发布门禁。

## 系统与版本策略

5 个镜像统一从 `alpine:3.24.1` 的 multi-arch digest 构建。统一基础系统可以让
`amd64/arm64`、漏洞修复和软件包升级只维护一条链；任何升级都先修改
`versions.lock`，再由 CI 重建并产生新的最终镜像 digest。

`versions.lock` 固定以下输入：

- Alpine tag 和 manifest digest。
- Xray、sing-box 的版本、两种架构资产名和 SHA-256。
- acme.sh 的版本、归档 URL 和 SHA-256。
- Nginx、Python、OpenSSL、socat、WireGuard、Fail2ban、iptables、nftables、
  iproute2、bash、CA 和 unzip 的 APK 版本。
- 当前补丁集合；本阶段为 `none`。

锁文件是 shell 兼容的只读键值文件。CI/Bake 的加载方式固定为：

```bash
set -a
. ./versions.lock
set +a
GIT_REVISION="$(git rev-parse HEAD)" IMAGE_TAG=v3.1.8 docker buildx bake --push
```

## 镜像职责

| 镜像 | 内容 | 运行用户 | 可写路径 |
|---|---|---|---|
| `padm-xray` | Xray、geoip/geosite、CA | `10001:10001` | `/tmp`、`/var/lib/padm/xray` |
| `padm-sing-box` | sing-box、libcronet、CA | `10001:10001` | `/tmp`、`/var/lib/padm/sing-box` |
| `padm-nginx` | Alpine Nginx、PADM 非 root 配置 | `10001:10001` | `/tmp` |
| `padm-ops` | Python、OpenSSL、socat、acme.sh | `10001:10001` | `/tmp`、`/var/lib/padm` |
| `padm-net` | WireGuard、Fail2ban、iproute2、iptables/nftables | `0:0` | `/run`、`/tmp`、`/var/lib/padm/net` |

`ops` 复用给订阅控制和 ACME 任务，`net` 复用给宿主网络集成；它们没有被复制进
核心镜像。每个 Dockerfile 都有独立构建上下文、OCI/PADM label、entrypoint、
healthcheck、架构、用户和可写路径合同。

## Compose 合同

固定 project 和 network 名均为 `padm-docker`。Compose 提供以下显式 profiles：

- `core-xray`、`core-sing-box`
- `nginx`
- `subscription`、`acme`
- `net-wireguard`、`net-fail2ban`、`net-transparent`

所有镜像引用必须由外部环境文件提供，格式为 `tag@sha256:digest`；模板位于
`docker/images.env.example`。Compose 没有 tag 默认值，缺少任何镜像引用都会
直接失败。

普通服务统一启用只读根、`cap_drop: ALL`、`no-new-privileges`、PID/文件句柄限制
和受限 tmpfs。只有 `net-*` profile 使用 `NET_ADMIN` 和 host network；仅
`net-transparent` 映射 `/dev/net/tun`。任何服务都没有 `privileged`、
`SYS_ADMIN` 或 Docker Socket。

## 验证结果

| 验证 | 结果 |
|---|---|
| `docker buildx bake --print`，5 目标、双架构、锁参数 | 通过 |
| 全 profiles `docker compose config --format json` | 通过 |
| `docker-phase2` selector | 通过，11.615 秒 |
| `docker-phase1` 专项回归 | 通过 |
| 原生 `fast-full` | 通过，104.153 秒 |
| 原生 `all` | 通过，637.577 秒 |
| Bash/POSIX shell 语法、`git diff --check` | 通过 |
| `shellcheck`、`hadolint` | 本机未安装，未运行 |
| 真实镜像 build/run 与 `amd64/arm64` smoke | Docker daemon 未运行，待阶段 5 CI |

## 后续边界

阶段 2 只建立可构建、可编排和可审计的镜像基础，不把原生业务脚本直接 source
进容器。阶段 3 接入核心配置、Nginx/TLS、订阅控制与 ACME 事务；阶段 4 接入
WireGuard、Fail2ban 和透明代理；阶段 5 才修改 CI/Release、推送 GHCR、生成
SBOM/provenance/签名并执行双架构 smoke。
