# Agent State

> 当前快照；详细证据见 Git、原生验收记录及 `.tmp-*`。

## 当前

- `main/origin/main=f858bf8a`；8c.4 正式 SSH 原生补验已签名并推送。
- 整体计划仍未完成；透明代理保持关闭，不以阶段通过替代整体完成。
- VPS：Debian 13 amd64、普通 bridge、公网 IPv4、正式 `3.41.8`；
  source=`e671328e`，三业务 healthy，timer/source/材料恢复。
- 3.41.8 release 32 项全成功，修复 CI 24 成功、3 条件跳过、零失败；
  不重复发布。
- 本机回归仅 Docker Linux，复用工具镜像；不重复 daily/full。

## 最近完成

- 8c.4：正式 CLI 零人工 chmod 创建 root `0700`；4 次错密码、2 轮封禁、
  外部超时、解封恢复、管理 22 可达；来源失效后 `jail exit=0`，
  IPv4/IPv6 规则 2102 ms 清理，3 项越界负控通过。
  证据 `.tmp-native-ssh-3418-20261026/verification.json`；
  私密归档 SHA256=`a42db50675a521a0dcc3fa74d1342dc554d201a334ea9fb9fe0d3e1a5eb7a6b8`。
- 当前源码 TUN/ICMP 定向回归通过：`docker-tun-management` 36.366 s、
  `docker-tun-real` 70.779 s、`docker-menu-tun` 2.115 s，均 `exit=0`；
  direct/远端仅过滤 Echo/核心缺权三阶段通过，无伪造回复、TCP/UDP 正常；
  动态计数结构负控、旧模板兼容和只读诊断通过，均 `cache_hit=false`；
  最新实流量证据 `.tmp-regression-docker-75fa27b0f5224516bc34e12780f44bd8/`。
- 6A.24：`3.41.6 → 3.41.8 → 3.41.6 → 3.41.8` 升级/回滚闭环通过；
  WS、严格 TLS、URI/source、权限/timer/累计及 4 项实物负控通过。
- TUN IPv4 Echo、XHTTP CANCEL FIN、Mihomo 固定组合、TLS 七入口、
  3.41.8 三件套/Cosign/五镜像双架构已完成对应验收；证据目录见
  `documents/docker-native-acceptance-2026-10-18.md`。

## 未决

- ICMP 尚缺原生宿主、arm64、公网、重启、IPv6/traceroute/PMTU。
- Mihomo 尚未扩展其它环境/客户端/算法/性能长稳；正式原生 h3/CDN、
  其它客户端、固定 ML-KEM 外算法也未扩范围。
- 24/25 gRPC Cloudflare 公网透传缺有效 Zone 授权；旧 token 无效，
  不重复无变化公网矩阵。
- 原生 arm64、IPv6/双栈、新主机灾备、多机原生控制/WG、WARP 实账号、
  约 2026-12-17 自然续期缺条件；VPS 当前无全局 IPv6/默认路由。
- 透明启用重启按要求不做；SOCKS UDP、Xray 解析后阻断继续拒绝。
- 旧 Vision reset、XHTTP 业务 TLS 超时、TUIC 超时缺原现场材料，根因未定。

## 工作区注意

- TUN/ICMP 源码改动必须保留，不能回滚或混入 SSH 文档阶段提交。
- 既有未跟踪 `.tmp-ci-timeout-actionlint.tar.gz`、`.tmp-reality-palette-preview*`、
  `.tmp-remote-xray-config.json`、`NUL` 不要误删。
