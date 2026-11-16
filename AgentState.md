# Agent State

> 当前快照；详细证据见 Git、实施计划及 `.tmp-*`。

## 当前

- 整体未收口；16 个协议管理 supported、14 个 deferred，支持状态未变。
- A/B 均 Debian 13 amd64/bridge/IPv4、透明关闭；A `.4`/`51d5f658`，DNS 未改。
- B `.7`/`2f17e6ac` 控制入口从原 `.4` 归档恢复，业务及五镜像保持原版。
  固定 WS 443 公网正反例经 A 临时 SSH TCP 转发通过，已清场，不计 Windows 直连。
- B 单次整机重启及补验通过；隔离先于 Docker 恢复，默认桥阻断保持，未撤防。
- A/B 单 Peer WG 正式 CLI 闭环及原规格恢复通过；两端密钥已清空，账目保持。
- 本地可销毁完整独立内核双机正式 `.7` 单 Peer 自主增删、控制角色/WG 启用态
  重启、密钥/端口迁移、关联改址撤权、真实 bind 失败恢复与新邀请/业务通过，均已关机。

## 最近完成

- 11-17 正式 `.7` 新 child 先完整 peer CLI dummy nonce 预热，回执保持；
  新挑战完整 source-probe 及主控 source-check 均 rc 0、唯一回执/verified。
  首次准备失败原件保留：预热 rc 0、锁仍在但 owner 未证，未启动主控挑战。
  新轮有界观察连续清场；规格/文件/服务/WG 身份/限额保持，累计不降、收发增长。
  总 149.230 秒、正常关机 5.131 秒、父盘摘要保持；断网独验 1691 份，
  含重核旧 1490 份。30 秒窗不变，防护及旧失败同因未证，6A.45。
  未改 A/B、源码/合同或重复回归；证据 `.tmp-native-control-vms-20261116/`。
- 6A.42 真实 bind 失败 rc 14 恢复旧址且仅撤权；身份/版本 5/业务/累计保持。
  两次断言失败保留，独验 1634 份；定向 Jobs 2、56363 ms、exit 0。
- 控制角色撤回复演及 A/B WG 原规格恢复通过，材料已清场；
  0 显式账号、各 19 条历史账目，不在生产执行至少 13 次重建。
- `.7` run `43747237740` 30 success/1 skipped；资产验签及双架构绑定通过。
  A/B 自然续期阈值为北京时间 2026-12-17 08:03:22，非 timer 执行时间；未到期未换证。

## 未决

- B 保留恢复部署及续期隔离；nftables 重载会清表，规则变化须核表和探针。
  实际续期、arm64/IPv6、其它核心、控制角色及 WG/多 Peer 新机恢复未验。
- 控制同步/启用态重启/密钥端口迁移仅补固定本地完整内核双机单 Peer；
  关联改址、真实 bind 失败恢复及预热后完整 peer CLI 来源见证已补。
  不计控制面防护通过；信号/断电恢复、公网多机、多 Peer 重启、灾备及长稳仍缺。
- 独立 SNI 仅同 IP/同证书别名正式整链，其它组合及旧缺陷失败见证未覆盖。
  A 无全球 IPv6，B 出口仅部分目标通过；本机 IPv6 nonce 命中 A/B=1/0，
  B 443 仅 IPv4；资源非峰值、预算未验。
- ICMP 原生启用态收发/arm64/公网/重启、IPv6/traceroute/PMTU 未验；
  TUN/透明启用重启按要求不做。SOCKS UDP、Xray 解析后阻断继续拒绝。
- WARP 实 Peer、自然换证、公网 h3/CDN 缺条件；gRPC Cloudflare 缺有效 Zone。
  旧 Vision reset/XHTTP/TUIC 超时根因未定；旧 sing-box→Xray 失败原件保持。
  固定公网组合不外推活动 sing-box；拒绝配对及带配对来源的跨核心复制。
- 未跑 full；ML-DSA 仅固定 amd64/IPv4/Reality/gRPC/chrome，不外推其它组合或长稳。

## 工作区注意

- 保留本地排除的 `.tmp-ci-timeout-actionlint.tar.gz`、`.tmp-reality-palette-preview*`、
  `.tmp-remote-xray-config.json`、`NUL`；证据不改判、不覆盖。
