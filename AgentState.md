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
  真实重启及业务通过，已正常关机；私密原件保留专用卷，未连接或修改 A/B。

## 最近完成

- 11-16 正式 `.7` 双 QEMU Debian 13/amd64 单 Peer 控制角色/WG 启用态真实重启：
  同 QEMU 进程与 7 个容器 ID 保持，boot/StartedAt 更新，原配置/私密文件权限保持；
  两 boot 双向加密、六组严格 TLS、原日历版本 2→3→4 自主传播及历史累计通过，
  重启后下载差值 278644 覆盖正文 278528 字节。重启就绪 69.864 秒；
  成功 896.679 秒，正常关机 6.672 秒、无强停，驱动 exit 0、无活动 guest。
  断网独验绑定 1029 份原件并复核旧 351 份，首轮 Docker 自动更新中断保持失败。
  证据 `.tmp-native-control-vms-20261116/`；隔离原点不是公网，目录权限未采集。
  合同仅改三个 reason；Linux amd64 定向 Jobs 2、62847 ms、exit 0，无缓存。
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
- 控制同步/启用态重启仅补固定本地完整内核双机单 Peer；公网多机、迁移、
  多 Peer 重启、角色/WG 灾备及长稳仍缺，不扩大生产重启结论。
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
