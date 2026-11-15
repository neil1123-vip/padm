# Agent State

> 当前快照；详细证据见 Git、实施计划及 `.tmp-*`。

## 当前

- 整体未收口；16 个协议管理 supported、14 个 deferred，矩阵未变。
- VPS Debian 13 amd64/bridge/IPv4，正式 `3.43.4`/source `51d5f658`；
  Xray/WS 443、三业务 healthy、无 OOM、透明关闭、两个 timer active/enabled。
- 11-16 核对远端最新 `.5`/`96764e4a`；本地已同步，jq 修复候选 `.6` 待推送发布。

## 最近完成

- `.4` 资产/306 源码/五镜像独验通过，复用 `.3`、无新增 smoke；
  证据 `.tmp-release-3434-20261107/`。
- 正式 `.4` ML-DSA 公网四阶段及重建、35 项比对和独立终审通过；
  pqv 仅受控 X.509，UUID 有明确拒绝日志。已清场，19 账号累计未倒退，
  证据 `.tmp-mldsa-public-3434-20261107/README.md`；到期自动清理未触发。
- `.2 → .4` 升级/正式 validate exit0；42 项/3 反例及终审通过，恢复点 `update.kQd6Bb`
  保存 `.2`，校验/latest 匹配但未实际回滚。公网 WS 两正控 TLS/200、错 UUID SSLEOF；
  19 账号/材料/权限/timer 保持，累计 +3555/+43868，已清场且未重启。
  证据 `.tmp-vps-upgrade-3434-20261107/`。
- 同 IP 目标 `www.pgxn.org`/SNI `pgxn.org` 隔离整链及终审通过，153290 ms；
  execution0/cleanup0、生产快照一致、已清场，证据 `.tmp-mldsa-sni-3434-20261107/`。
- 11-08 次日只读复核 32 项及 3 反例通过；boot/三容器生命周期、材料/权限、
  timer 保持，19 账号身份/限额及累计与升级后相同，恢复点正式校验/latest 通过。
  证据 `.tmp-vps-post-upgrade-3434-20261108/README.md`；非业务或长稳验收。
- deferred 对齐 `.4` 发布/升级、ML-DSA/SNI；14 个状态及专项未决条件保持。
- 11-15 至 16，B `45.221.113.40` 正式 `.4` 空骨架及官方依赖已装；敏感材料明确授权后
  A→B 归档 SHA 相同，29 文件/19 账目，root/0700/0600、未落 Windows。
  损坏 preview exit15；正确 preview 被 `.4` 的 jq 1.7 对象合并语法阻断、exit15。
  空骨架/容器/端口/调度清场及 A 业务/材料/timer 保持，28 项通过；原归档保留。
  仓库补括号及发行版 jq 检查，红测 1/绿测 0；同步 `.5` 后定向再验 0/203464 ms，
  Jobs 2/无结果复用，未改 B 正式包。证据 `.tmp-native-dr-target-b-20261115/`。
  发布准备 `.tmp-release-jq-fix-20261116/`：新版控制骨架配 `.4` 归档/原清单做 preview，
  不混用新清单、不需先升级 A；正式包预演与 apply 前外部续期隔离仍待执行。

## 未决

- 独立 SNI 仅同 IP/同证书别名整链已证，不证明旧缺陷失败或其它组合。
  11-06 前两轮及 11-07 正则失败见 `.tmp-mldsa-cli-public-20261106/`、
  `.tmp-mldsa-targets-20261107/`；空后快照/cleanup1、非法 IP 草案不改判。
  本机出口按 SNI 改路由；VPS 无全局 IPv6/默认路由。资源采样非峰值，预算未验。
- WS 旧公网端口 TCP 拒绝及原生 IPv6 未证明；固定 CONNECT 只证 TLS EOF。
- ICMP 原生启用态收发/arm64/公网/重启、IPv6/traceroute/PMTU 未验；
  TUN/透明启用重启按要求不做。SOCKS UDP、Xray 解析后阻断继续拒绝。
- 原生 arm64、双栈、新主机灾备、多机控制/WG、WARP 实账号及约 2026-12-17
  自然 ACME 续期缺条件；公网 h3/CDN、其它客户端/算法和性能长稳未扩范围。
  gRPC Cloudflare 透传缺有效 Zone 授权，不重跑无变化矩阵。
- 旧 Vision reset、XHTTP/TUIC 超时缺原材料；旧 sing-box→Xray 失败原件
  `d18652f4...` 保留。固定公网组合不外推其它组合或活动 sing-box 业务。
  sing-box 拒绝配对及带配对来源的跨核心复制；历史 Docker 停启触发者未知。
- 未跑 full；ML-DSA 仅固定 amd64/IPv4/Reality/gRPC/chrome，不外推其它组合或长稳。

## 工作区注意

- 保留本地排除的 `.tmp-ci-timeout-actionlint.tar.gz`、`.tmp-reality-palette-preview*`、
  `.tmp-remote-xray-config.json`、`NUL`；证据不改判、不覆盖。
