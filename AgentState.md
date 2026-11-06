# Agent State

> 当前快照；详细证据见 Git、验收记录及 `.tmp-*`。

## 当前

- 整体计划未完成；透明代理保持关闭，不以阶段通过替代整体完成。
- `.2` 发布、正式 lock/应用交付、VPS 升级及固定客户端公网 Reality 验收完成。
- 正式 `3.43.3` 的资产/签名/源码和五镜像双架构绑定已独验；VPS 未随本轮升级。
- 独立 sing-box `3.43.3` 固定公网五阶段、认证独验及清场完成；现网未升级。
- VPS：Debian 13 amd64、bridge、公网 IPv4、正式 `3.43.2`/source=`d8bac249`；
  保留 Xray/协议 21，三业务 healthy、无 OOM，透明关闭，两个 timer active/enabled。
- 本机 Docker Linux 可用，复用工具镜像，未跑 full。
- 原生账号 8 阶段及恢复整轮通过，508821 ms/exit 0；
  26 正/5 拒绝、断网独验及 13 项篡改拒绝通过，已恢复清场。
- 4A.4 备份/恢复、健康失败回滚与分享授权 7 阶段通过（616534 ms/exit 0）；
  断网独验及 10 项篡改拒绝通过并清场。

## 最近完成

- 16 个协议管理 supported，14 个 deferred 已对账；明细及早期验收见实施计划。
- 正式 `.2` 与 `3.43.2` 发布物独验、双架构门禁及 VPS 升级通过；
  原 WS 业务与真实恢复点 `update.956SI1` 保持，证据 `.tmp-release-revision2-20261105/`。
- `.2`→Xray 固定公网 IPv4/Reality/gRPC/chrome 两正控及三负例通过；
  客户端超时/false 原件保留，服务端独立关联通过，临时对象已清。
  证据 `.tmp-reality-public-revision2-20261105/`；不外推公网 ML-DSA/hybrid-only。
- `3.43.3`/`bb39c079` 仅更新 Alpine `3.24.4`；run `42209522565` 40 job 全成功，
  三资产/精确验签/306 源码及五镜像双架构绑定通过；证据 `.tmp-release-3433-20261106/`。
- 2026-11-06：独立 sing-box `3.43.3`，固定 amd64/IPv4/Reality/gRPC/chrome：
  正式 CLI 分享一致、两正控严格 TLS/200、三服务端明确拒绝及双向统计独验通过；
  5 项篡改自检通过；错公钥/SID 客户端超时与 false 原件保留，不按超时判拒绝。
  临时容器/网络/私密材料已清、`25444/TCP` 关闭；现网 48 项复核与 19 条累计保持。
  证据 `.tmp-singbox-server-public-20261106/`；断网准备失败及旧 StartedAt 差异原件保留。
  历史 Docker 于北京时间 11-06 02:00:25–30 停启，触发者未知；本轮生命周期未变。

## 未决

- WS 公网旧端口 TCP 拒绝、原生 IPv6 未证明；固定 CONNECT 只证 TLS EOF。
- ICMP 原生启用态收发/arm64/公网/重启、IPv6/traceroute/PMTU；
  真实 TUN 必须启用宿主透明接管，受透明保持关闭约束。
- 原生 arm64 整机、IPv6/双栈、新主机灾备、多机控制/WG、WARP 实账号、
  约 2026-12-17 自然 ACME 续期缺条件；VPS 无全局 IPv6/默认路由。
- 公网 h3/CDN、其它客户端/算法、性能长稳未扩范围；gRPC Cloudflare
  透传缺有效 Zone 授权，不重跑无变化矩阵。
- 透明启用重启按要求不做；SOCKS UDP、Xray 解析后阻断继续拒绝。
- 旧 Vision reset、XHTTP TLS 超时、TUIC 超时缺原现场材料，根因未定。
- 旧 sing-box `1.14.4`→Xray `26.10.31` 失败原件 `d18652f4...` 保留；
  `.2` 正式包/镜像整轮及上述固定公网组合通过，其它指纹/公网组合未验。
  VPS 维持 Xray，不能把本次升级当成活动 sing-box 业务证明。
  配对直接装测试规格，不证明 CLI 自动启用整链或独立 SNI；
  sing-box 拒绝配对及带配对来源的跨核心复制。

## 工作区注意

- 本地 Git 排除并保留 `.tmp-ci-timeout-actionlint.tar.gz`、
  `.tmp-reality-palette-preview*`、`.tmp-remote-xray-config.json`、`NUL`。
