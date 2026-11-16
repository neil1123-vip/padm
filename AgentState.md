# Agent State

> 当前快照；详细证据见 Git、实施计划及 `.tmp-*`。

## 当前

- 整体未收口；16 个协议管理 supported、14 个 deferred，矩阵未变。
- A、B 业务均 Debian 13 amd64/bridge/IPv4、透明关闭；A 正式 `.4`/`51d5f658`，DNS 未改。
- B 正式 `.7`/`2f17e6ac` 控制入口已从原 `.4` 归档恢复业务；未升级归档或五镜像。
- B 新主机恢复在固定 Xray/WS 443 组合通过；三业务 healthy、无 OOM/重启，两个 timer
  active/enabled。公网验收经 A 临时 SSH TCP 转发，已清场；不计 Windows 直连通过。
- B 单次整机重启及补验通过；隔离先于 Docker 自然恢复，默认桥阻断保持，未撤防。
- 原生双机 WG 前提/源码已核；仅规划补验仍缺正式事务/调度，未增加低收益临时运行夹具。

## 最近完成

- `.7` run `43747237740` 30 success/1 skipped，18 合同、三资产/验签/306 源码/
  五镜像双架构绑定通过；沿用 `.5` 镜像，无新构建。证据 `.tmp-release-3437-20261116/`。
- 11-16，B apply exit 0；规格/分享、19 条账目、TLS/续期/Geo/9 份 ACME 及权限保持，
  公网 WS 两正两拒绝、出口 B；A 稳定、暂存清场及独核通过，旧失败保留。
  证据 `.tmp-native-dr-apply-3437-20261116/README.md`。
- 11-16 13:40:55，授权 B 唯一整机重启；新 boot ffc93e78，原三容器自然 healthy，
  隔离完成 9239761 μs < Docker 启动 9885639 μs；两 timer、材料/权限、五镜像保持。
  默认桥三目标全阻断、业务网对照全通；严格 TLS 公网 WS 两正两拒绝、出口 B。
  19 账号最新身份/额度/累计逐项保持，最终 191447283 字节，比重启前增 11239。
  A 稳定、探针/客户端/listener 清场；独核通过，原检查失败保留。
  证据 `.tmp-native-dr-reboot-3437-20261116/README.md`。
- 11-16，只读确认 B 有三全球 IPv6/默认路由；ipify 严格 TLS/200/出口 B 通过，
  Cloudflare errno 113，整轮 exit 1 保留。B→A 当前 443 TLS/200→25443 TCP 拒绝→443
  TLS/200 通过；不计历史迁移窗或完整双栈。证据 `.tmp-native-wg-public-20261116/`。

## 未决

- B 保留恢复验证部署及续期隔离；nftables 重载会清表，规则变化须核实际表和探针。
  实际续期、arm64/IPv6、其它核心和 WG/多 Peer 新机恢复未验，不扩大固定重启结论。
- 独立 SNI 已在同 IP/同证书别名完成正式整链；其它组合和旧缺陷失败见证未覆盖。
  旧正则失败/修复见证保留，非法 IP 草案不改判；A 无全球 IPv6，B 出口仅部分目标通过。
  本机 IPv6 请求 nonce 命中 A/B=1/0，B 443 仅 IPv4；资源非峰值、预算未验。
- 10-27 WS 迁移窗旧 443 的公网 TCP 拒绝未观测，固定 CONNECT 只证 TLS EOF；
  已回迁正式 443，属历史证据限制，不再作为当前待执行项；公网 IPv6 仍未验。
- ICMP 原生启用态收发/arm64/公网/重启、IPv6/traceroute/PMTU 未验；
  TUN/透明启用重启按要求不做。SOCKS UDP、Xray 解析后阻断继续拒绝。
- 原生 arm64、完整双栈、多机控制/WG、WARP 实账号及约 2026-12-17 自然 ACME 续期
  仍缺实际证据；公网 h3/CDN、其它客户端/算法和性能长稳未扩范围。
  gRPC Cloudflare 透传缺有效 Zone 授权，不重跑无变化矩阵。
- 旧 Vision reset、XHTTP/TUIC 超时缺原材料；旧 sing-box→Xray 失败原件
  `d18652f4...` 保留。固定公网组合不外推其它组合或活动 sing-box 业务。
  sing-box 拒绝配对及带配对来源的跨核心复制；历史 Docker 停启触发者未知。
- 未跑 full；ML-DSA 仅固定 amd64/IPv4/Reality/gRPC/chrome，不外推其它组合或长稳。

## 工作区注意

- 保留本地排除的 `.tmp-ci-timeout-actionlint.tar.gz`、`.tmp-reality-palette-preview*`、
  `.tmp-remote-xray-config.json`、`NUL`；证据不改判、不覆盖。
