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
  迁移撤权、真实 bind 失败恢复及新机角色/WG 恢复通过，均已关机。

## 最近完成

- 11-17 6A.47 正式 `.7` 控制防护 enable rc 14，Peer 当前 nonce CLI rc 0，
  无 source-verified；恢复后读到唯一窗口内回执，具体拒绝分支与旧失败同因未证。
  首轮恢复审计遇部署锁断言失败；仅改为最长 110 秒只读观察、连续两次稳定。
  新 child 断网审计通过：规格/文件/WG/额度保持、累计不降、双向加密增长，
  无 jail/owner/控制规则/挑战/临时探测残留；严格 TLS 错 UUID 拒绝，
  managed/core 正文 303104/278528 字节及 managed 计量增量通过。
  审计 144.083 秒、正常关机 5.288 秒、QEMU exit 0/0、父盘摘要保持；
  断网独验 1994 份（重核旧 1691 份），原 enable/审计/独验首稿失败保持。
  未重复 enable，防护未通过；五容器已退出、无 OOM，私密卷无活动容器。
- 6A.46 单 Peer 新机角色/WG 恢复、rebind、自主传播及 TLS/计量通过；
  恢复联网、事后断网独验 3002 份，旧失败保持。
  未改 A/B、源码/合同或重复回归；证据 `.tmp-native-control-vms-20261116/`。
- 6A.45 预热后完整 Peer CLI/主控来源见证通过；30 秒窗不变，防护和旧失败同因未证。
- 控制角色撤回复演及 A/B WG 原规格恢复通过，材料已清场；
  0 显式账号、各 19 条历史账目，不在生产执行至少 13 次重建。
- `.7` run `43747237740` 30 success/1 skipped；资产验签及双架构绑定通过。
  A/B 自然续期阈值为北京时间 2026-12-17 08:03:22，非 timer 执行时间；未到期未换证。

## 未决

- B 保留恢复部署及续期隔离；nftables 重载会清表，规则变化须核表和探针。
  实际续期、arm64/IPv6、其它核心及公网/多 Peer 角色/WG 新机恢复未验。
- 控制同步/启用态重启/密钥端口迁移仅补固定本地完整内核双机单 Peer；
  关联改址、真实 bind 失败恢复及预热后完整 peer CLI 来源见证已补。
  不计控制面防护通过；信号/断电恢复、公网多机、多 Peer 重启/灾备及长稳仍缺。
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
