# Agent State

> 当前快照；详细证据见 Git、实施计划及 `.tmp-*`。

## 当前

- 整体未收口；16 个协议管理 supported、14 个 deferred。
- 当前正式 `v3.44.0`/`da790587`，独立上游自动更新发布；41 门禁全过。
- A/B 均 Debian 13 amd64/bridge/IPv4、透明关闭；A `.4`/`51d5f658`，DNS 未改。
- B `.7`/`2f17e6ac` 控制入口从原 `.4` 归档恢复，业务及五镜像保持原版。
  WS 443 公网正反例经 A 临时 SSH 转发通过并清场，不计 Windows 直连。
- B 单次整机重启及补验通过；隔离先于 Docker 恢复，默认桥阻断保持，未撤防。
- A/B 单 Peer WG 正式 CLI 及原规格恢复通过；密钥已清空，账目保持。
- 本地正式 `.7` 完整内核双机单 Peer 的同步、重启、迁移撤权、
  bind/TERM 及新机角色/WG 恢复通过，均已关机。

## 最近完成

- 6A.72 正式 `.44` 本地 amd64 双 Peer 主控新机灾备通过：旧邀请 401、
  双重绑、原 timer 自主同步、TLS/累计；1697 原件断网独验，四机正常关机。
  首轮漏停同步的 `rc 11` 保留。仅固定本地拓扑，不计公网、灾后重启或长稳。
- 6A.71 正式 `.44` 本地三 KVM 的双 Peer 自主传播、业务、整机重启及单 Peer
  撤权隔离独验通过；3986 原件，三机正常关机且父盘保持。
- ICMP 四轮仅到准备，均关机；原样保留。空盘复现正式 `.44` 的
  Debian jq 1.7 渲染错误；`226ceb2f` 修复，1.7/1.8.2 TUN 合同和
  1.7 DNS 解析后阻断合同通过；下一签名正式包再补实际 Echo。
- 6A.70 正式 `.44` ARM64 Reality 六拓扑/双入口 Encryption 及清场独验通过；
  run `44146178086`/`261048c4`，292 工件、41+46 负控。旧失败保持；
  Mihomo 限显式 hybrid 投影；spec 恢复限语义。
- 6A.69 `.44` ARM64/Xray 29+sing-box 28 入口/双核心路由/HTTP/严格 CONNECT/
  ALPN、服务重启及清场独验通过，126 工件、31+19 负控；旧失败保持。
- 6A.68 正式 `.44` ARM64 Engine 安装、纯 sing-box `.8/.44` 七阶段独验通过；
  69 工件；移除预装包后安装，不称裸 OS，旧独验失败保持。
- Dependabot #11/`34649a0b` 闭环，Release `44120778615` 成功；
  去重修复已验，新 PR 待验。
- A/B 单 Peer 验收已清场，0 显式账号、各 19 条历史账目。
- A/B 自然续期阈值：北京时间 2026-12-17 08:03:22，非 timer 时间；未到期未换证。

## 未决

- B 保留恢复部署及续期隔离；nftables 重载会清表，规则变化须核表和探针。
  实际续期、ARM64 其它组合/整机重启、IPv6、公网新机恢复未验；
  ARM64 origin 仅本地 lo，安装/两核心/专项只覆盖 6A.67–6A.70 固定组合。
  Reality 公网入站/整机重启/长稳、其它拓扑加密生命周期及 Mihomo 原 URI 导入未验。
- 密钥/端口迁移限双机单 Peer；其它信号/断电、公网多机、其它灾备拓扑及长稳仍缺。
  `.8` 防护不外推生产/公网；保留 30 秒窗口。WSL 变化后须核对 KVM 模块。
- 独立 SNI 仅同 IP/同证书别名正式整链，其它组合及旧缺陷失败见证未覆盖。
  A 无全球 IPv6，B 出口仅部分目标通过；本机 IPv6 nonce 命中 A/B=1/0，
  B 443 仅 IPv4；资源非峰值、预算未验。
- ICMP 原生启用态收发/arm64/公网/重启、IPv6/traceroute/PMTU 未验；
  TUN/透明启用重启按要求不做。SOCKS UDP、Xray 解析后阻断继续拒绝。
- WARP 实 Peer、自然换证、公网 h3/CDN 缺条件；gRPC Cloudflare 缺有效 Zone。
  旧 Vision reset/XHTTP/TUIC 超时根因未定；旧 sing-box→Xray 失败原件保持。
  固定公网组合不外推活动 sing-box；拒绝配对及带配对来源的跨核心复制。
- ML-DSA 仍限 amd64/IPv4/Reality/gRPC/chrome。

## 工作区注意

- 保留本地排除的 `.tmp-ci-timeout-actionlint.tar.gz`、`.tmp-reality-palette-preview*`、
  `.tmp-remote-xray-config.json`、`NUL` 及未跟踪身份取证 JSON；证据不改判、不覆盖。
