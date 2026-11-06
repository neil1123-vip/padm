# Agent State

> 当前快照；详细证据见 Git、实施计划及 `.tmp-*`。

## 当前

- 整体未收口；16 个协议管理 supported、14 个 deferred，矩阵未变。
- VPS Debian 13 amd64/bridge/IPv4，正式 `3.43.2`/source `d8bac249`；
  Xray/WS 443、三业务 healthy、无 OOM、透明关闭、两个 timer active/enabled。
- ML-DSA 正式 CLI 整链未通过；VPS 三轮隔离均结束并清场，生产未变。
- 独立 SNI 与长公钥正则兼容修复、本机验证通过，正在按本轮授权提交及发布。
- 本轮推送含已签名 `6462a616` sing-box 验收记录及两项修复；现网升级不在范围。

## 最近完成

- `.2`/`3.43.2` 发布、升级及固定公网 Reality 通过，真实恢复点保持；
  证据 `.tmp-release-revision2-20261105/`、`.tmp-reality-public-revision2-20261105/`。
- `3.43.3`/`bb39c079` 资产、签名、源码及五镜像双架构绑定通过；
  run `42209522565` 的 40 job 成功，证据 `.tmp-release-3433-20261106/`。
- 独立 sing-box `3.43.3` 固定 amd64/IPv4/Reality/gRPC/chrome：
  CLI 分享、两正控 TLS/200、三服务端拒绝及双向统计独验通过，5 项篡改拒绝；
  超时/false 原件保留；已清场、25444 关闭，现网 48 项及 19 条累计保持。
  证据 `.tmp-singbox-server-public-20261106/`；历史 Docker 停启触发者未知。
- 前两轮 ML-DSA 失败原件见 `.tmp-mldsa-cli-public-20261106/README.md`；
  首轮空后快照/cleanup1 不改判，独立复核一致；第二轮 configure 被 AAAA 拒绝。
- 2026-11-07：25 个内置候选仅 pgxn.org 为 IPv4-only；两次 SNI/PQ/4307 字节链、
  独立 OpenSSL h2 通过。第三轮正式 3.43.3 configure exit0，重生成 exit15：
  Alpine Bash/musl 拒绝公钥正则 `{2602}`。未进入分享、握手或重建。
  cleanup0/生产前后快照一致；最终健康/生命周期/部署/timer 与临时对象清场通过。
  证据 `.tmp-mldsa-targets-20261107/README.md`；旧正式输入未改、无端口发布。
- 本地修复独立 SNI 及长重复正则：保持长度 2603、字符集、规范末位和配对校验；
  真 Alpine 原函数失败/新函数有效值与四负例通过，密码学工具边界为 stub。
  标准 `docker-reality-parameters -Jobs 2` 通过，203353 ms/exit0；
  证据 `.tmp-regression-docker-c8a2456cb4614c63a5c53cd97c8a92aa/`。

## 未决

- ML-DSA 候选 pgxn.org 已通过正式安全门；待含修复的新正式包复跑自动启用、
  配置/分享、正负例和重建；独立 SNI 整链仍未证明，格式 stub 不证明密码学握手。
  11-06 非法固定 IP 草案及失败检查原件保留，11-07 清单与远端输入已核对。
  本机出口按 SNI 改路由；VPS 无全局 IPv6/默认路由，安全门保持严格。
  资源采样非峰值、完整业务预算未验；公网客户端验收另需授权。
- WS 旧公网端口 TCP 拒绝及原生 IPv6 未证明；固定 CONNECT 只证 TLS EOF。
- ICMP 原生启用态收发/arm64/公网/重启、IPv6/traceroute/PMTU 未验；
  TUN/透明启用重启按要求不做。SOCKS UDP、Xray 解析后阻断继续拒绝。
- 原生 arm64、双栈、新主机灾备、多机控制/WG、WARP 实账号及约 2026-12-17
  自然 ACME 续期缺条件；公网 h3/CDN、其它客户端/算法和性能长稳未扩范围。
  gRPC Cloudflare 透传缺有效 Zone 授权，不重跑无变化矩阵。
- 旧 Vision reset、XHTTP/TUIC 超时缺原材料；旧 sing-box→Xray 失败原件
  `d18652f4...` 保留。固定公网组合不外推其它组合或活动 sing-box 业务。
  手填配对不证明 CLI 自动启用；sing-box 拒绝配对及带配对来源的跨核心复制。
- 本轮未跑 full；已授权修复提交、推送及下一版本发布，待新正式包隔离复验。

## 工作区注意

- 保留本地排除的 `.tmp-ci-timeout-actionlint.tar.gz`、`.tmp-reality-palette-preview*`、
  `.tmp-remote-xray-config.json`、`NUL`；证据不改判、不覆盖。
