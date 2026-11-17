# Agent State

> 当前快照；详细证据见 Git、实施计划及 `.tmp-*`。

## 当前

- 整体未收口；16 个协议管理 supported、14 个 deferred，支持状态未变。
- 当前正式 `v3.44.0`/`da790587`，独立上游自动更新发布；41 门禁全过。
- A/B 均 Debian 13 amd64/bridge/IPv4、透明关闭；A `.4`/`51d5f658`，DNS 未改。
- B `.7`/`2f17e6ac` 控制入口从原 `.4` 归档恢复，业务及五镜像保持原版。
  固定 WS 443 公网正反例经 A 临时 SSH TCP 转发通过，已清场，不计 Windows 直连。
- B 单次整机重启及补验通过；隔离先于 Docker 恢复，默认桥阻断保持，未撤防。
- A/B 单 Peer WG 正式 CLI 及原规格恢复通过；密钥已清空，账目保持。
- 本地正式 `.7` 完整内核双机单 Peer 的同步、重启、迁移撤权、
  bind/TERM 及新机角色/WG 恢复通过，均已关机。

## 最近完成

- 6A.69 正式 `.44` ARM64/Xray 29+sing-box 28 的入口/双核心路由/HTTP 与
  严格 CONNECT/站点 ALPN、服务重启及清场通过；run `44112277450`/`7808de09`。
  126 工件/58 检查/六 checkpoint 断网只读独验、31+19 负控通过；
  `.tmp-native-arm64-specialties-20261117/`，旧失败及首稿独验拒绝保持。
  首次编辑只保持 JSON 语义；私密语义依赖现场断言，第二轮中继异常根因未定。
- 6A.68 正式 `.44` ARM64 Engine 安装、纯 sing-box `.8/.44` 七阶段独验通过；
  69 工件/22 客户端/两账目/10 镜像，`.tmp-native-arm64-singbox-20261117/`。
  移除预装包后安装，不称裸 OS；首轮运行通过、两次独验失败保持。
- 6A.67 ARM64/Xray WS `.7/.8` 七阶段及清场独验，56 工件；
  `.tmp-native-arm64-host-20261117/`。6A.66 正式 `.8` 双 KVM 升级/防护/
  全文件恢复独验，1940 工件 `.tmp-formal-control-3438-20261117/`；均已清场。
- Dependabot PR #11/`34649a0b` 闭环，Release `44120778615` 成功。
  合并保留受测树/main 第一父，事件关联及 10 分钟补派去重；62 例、
  docker-phase5/Actionlint 已验；新 PR 线上待验。
- 原生双机证据 `.tmp-native-control-vms-20261116/`；A/B 已清场，
  0 显式账号、各 19 条历史账目；`.7` 资产验签及双架构绑定通过。
- A/B 自然续期阈值：北京时间 2026-12-17 08:03:22，非 timer 时间；未到期未换证。

## 未决

- B 保留恢复部署及续期隔离；nftables 重载会清表，规则变化须核表和探针。
  实际续期、ARM64 其它组合/整机重启、IPv6、公网/多 Peer 新机恢复未验；
  ARM64 origin 仅本地 lo，安装/两核心/专项只覆盖 6A.67–6A.69 固定组合。
- 控制同步/启用态重启/密钥端口迁移仅补固定本地完整内核双机单 Peer；
  bind/TERM 恢复及预热后完整 Peer CLI 见证已补；其它信号/断电、
  公网多机、多 Peer 重启/灾备及长稳仍缺；`.8` 防护不外推生产/公网。
  保留三次采样/即时 clean/30 秒窗口，不重复相同 VM 验收；
  KVM 模块非持久加载，WSL 变化后须核对。
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
