# Agent State

> 当前快照；详细证据见 Git、实施计划及 `.tmp-*`。

## 当前

- 整体未收口；16 个协议管理 supported、14 个 deferred，支持状态未变。
- A/B 均 Debian 13 amd64/bridge/IPv4、透明关闭；A `.4`/`51d5f658`，DNS 未改。
- B `.7`/`2f17e6ac` 控制入口从原 `.4` 归档恢复，业务及五镜像保持原版。
  固定 WS 443 公网正反例经 A 临时 SSH TCP 转发通过，已清场，不计 Windows 直连。
- B 单次整机重启及补验通过；隔离先于 Docker 恢复，默认桥阻断保持，未撤防。
- A/B 单 Peer WG 正式 CLI 闭环及原规格恢复通过；两端密钥已清空，账目保持。
- 本地完整独立内核双机正式 `.7` 单 Peer 的同步、角色/WG 启用态重启、
  迁移撤权、真实 bind/TERM 恢复及新机角色/WG 恢复通过，均已关机。

## 最近完成

- 11-17 distroless 合计减 20.7%，保留完整 Geo；审计修复宿主 stream 配置，
  五镜像补验通过；体积及未验边界见 `documents/docker-distroless-baseline.md`。
- 11-17 6A.65 固定 5c16680c 的 KVM 双机单 Peer，防护及完整恢复通过；
  真实封禁/DROP/解封、启停后三业务/账目、终态安全/Peer 清场/源码均已独验。
  仅接受正式生成器已重建的候选版本字节更新，权限及其它文件仍精确比较。
  断网独验 245 份，正常关机、父盘不变；6A.64 三轮失败原件保持。
- jq、health/Peer 合并定向已验；旧 TCG 计时/失败及截止边界见 6A.62。
- 原生证据 `.tmp-native-control-vms-20261116/`。
- 控制角色撤回复演及 A/B WG 恢复通过，材料清场；0 显式账号、各 19 条历史账目。
- `.7` 资产验签及双架构绑定通过。
  A/B 自然续期阈值为北京时间 2026-12-17 08:03:22，非 timer 执行时间；未到期未换证。

## 未决

- B 保留恢复部署及续期隔离；nftables 重载会清表，规则变化须核表和探针。
  实际续期、arm64/IPv6、其它核心及公网/多 Peer 角色/WG 新机恢复未验。
- 控制同步/启用态重启/密钥端口迁移仅补固定本地完整内核双机单 Peer；
  关联改址、真实 bind 失败恢复及预热后完整 peer CLI 来源见证已补。
  TERM 恢复仅补固定本地单 Peer；其它信号/断电、公网多机、多 Peer 重启/灾备
  及长稳仍缺；控制防护仅补固定 KVM 候选单 Peer，不外推正式版/生产。
  保留全部校验/三次采样/即时 clean/30 秒窗口；无须重复相同 VM 验收。
  KVM 模块非持久加载，WSL 变化后须核对。
- 独立 SNI 仅同 IP/同证书别名正式整链，其它组合及旧缺陷失败见证未覆盖。
  A 无全球 IPv6，B 出口仅部分目标通过；本机 IPv6 nonce 命中 A/B=1/0，
  B 443 仅 IPv4；资源非峰值、预算未验。
- ICMP 原生启用态收发/arm64/公网/重启、IPv6/traceroute/PMTU 未验；
  TUN/透明启用重启按要求不做。SOCKS UDP、Xray 解析后阻断继续拒绝。
- WARP 实 Peer、自然换证、公网 h3/CDN 缺条件；gRPC Cloudflare 缺有效 Zone。
  旧 Vision reset/XHTTP/TUIC 超时根因未定；旧 sing-box→Xray 失败原件保持。
  固定公网组合不外推活动 sing-box；拒绝配对及带配对来源的跨核心复制。
- full 67 项/845.194 秒及修复后 phase5/13.359 秒通过；sing-box 双架构通过。
  Release `44055641704` 的 18 合同/10 smoke 通过，ARM64 导入 ID 失败阻止发布。
  已匹配宿主存储并命名导出，原 ID 校验保留；实际 ARM64 待新轮远端。
  ML-DSA 仍限 amd64/IPv4/Reality/gRPC/chrome。

## 工作区注意

- 保留本地排除的 `.tmp-ci-timeout-actionlint.tar.gz`、`.tmp-reality-palette-preview*`、
  `.tmp-remote-xray-config.json`、`NUL` 及未跟踪身份取证 JSON；证据不改判、不覆盖。
