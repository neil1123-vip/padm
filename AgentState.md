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
  重启、密钥/端口迁移、关联改址撤权与新邀请恢复及业务通过，均已正常关机，未改 A/B。

## 最近完成

- 11-16 正式 `.7` 双 QEMU 单 Peer 关联改址、自动撤权、旧凭据拒绝通过。
  首轮 source-check rc 15 失败，probe/回执命中不计见证；正常关机后从新 child
  接续新邀请，同身份/同版无变化同步、原日历 4→5 自主传播及六组严格 TLS 通过。
  下载增量 254068 覆盖正文 253952，累计/限额保持；接续 552.616 秒，
  两次正常关机 6.774/6.011 秒，无强停；两段驱动 exit 1/0 分别保留。
  断网独验共绑定 1222 份原件，含前轮 837 份；仅接续两父盘始末摘要保持。
  证据 `.tmp-native-control-vms-20261116/`；隔离原点不是公网，未采目录权限。
  6A.39/6A.40 证据保持；仅改三个 reason，Linux amd64 定向 Jobs 2、
  55873 ms、exit 0、无缓存，状态不变。
- 控制角色撤回隔离复演通过：正式 purge/原无角色归档恢复/最新业务合并，
  原身份、逐 ID 累计与最新 2 GiB 保持，cron 清场和真实 WS 通过；469063 ms。
  证据 `.tmp-control-standalone-recovery-20261116/`；不作为正式发布包验收。
- A/B WG 的 20 阶段、4 轮加密、8 WS、6 隔离证据绑定及原规格恢复通过；
  0 显式账号、各 19 条历史账目；不在生产执行至少 13 次重建。
  证据 `.tmp-native-wg-cli-20261116/`、`.tmp-native-control-readiness-20261116/`。
- `.7` 发布 run `43747237740` 30 success/1 skipped；资产验签及双架构绑定通过。
  A/B 自然续期阈值为北京时间 2026-12-17 08:03:22，非 timer 执行时间；未到期未换证。

## 未决

- B 保留恢复部署及续期隔离；nftables 重载会清表，规则变化须核表和探针。
  实际续期、arm64/IPv6、其它核心、控制角色及 WG/多 Peer 新机恢复未验。
- 控制同步/启用态重启/密钥端口迁移仅补固定本地完整内核双机单 Peer；
  关联改址已补；fresh 来源见证 rc 15 原因未定，不计控制面防护通过。
  公网多机、完整内核迁移失败恢复、多 Peer 重启、角色/WG 灾备及长稳仍缺。
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
