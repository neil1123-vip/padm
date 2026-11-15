# Agent State

> 当前快照；详细证据见 Git、实施计划及 `.tmp-*`。

## 当前

- 整体未收口；16 个协议管理 supported、14 个 deferred，矩阵未变。
- VPS Debian 13 amd64/bridge/IPv4，正式 `3.43.4`/source `51d5f658`；
  Xray/WS 443、三业务 healthy、无 OOM、透明关闭、两个 timer active/enabled。
- `.6`/`eb3add57` 已发布独验；A 仍 `.4`，B 为 `.6` 空控制骨架。
- B 原 `.4` 归档正式 preview exit0；自动网络清理未过，人工精确回收后空骨架一致。
- 清场修复 `b696696e` 已本地签名提交，两组定向通过；待推送、发布及 B 正式复验。

## 最近完成

- 修复 `9cedb3ea` 与记录 `df82129a` 已授权推送；`.6` run `43736535002`
  30 success/1 skipped、18 合同分片及三资产/精确验签/306 源码/五镜像双架构独验通过。
  五镜像复用 `.5`，无新构建/smoke；证据 `.tmp-release-3436-20261116/`。
- 11-16，B 正式 `.6` 三资产摘要/精确验签/来源及骨架安装通过，发行版 jq 保持 1.7。
  继续固定原 `.4` 归档/清单/签名/控制包，正确 preview exit0；19 保存账目、0 显式账号、
  Geo 3/续期 1/安全重建 ACME 9，五个原版 amd64 镜像匹配。
  默认网络残留使整轮验收 exit1；精确核归属/空载后人工删除，673 项完整快照恢复一致。
  A boot/三业务生命周期/9 份材料权限/两个 timer 保持；34 项证据检查通过，未 apply。
  证据 `.tmp-native-dr-preview-3436-20261116/README.md`；不记为自动净清场或完整灾备通过。
- restore preview 按已登记候选派生隔离项目，拒绝碰撞后原子发布编排；先回收 oneoff、
  默认/IPv6 网络并确认无残留，再删私密暂存；失败保留登记，recover 可重试。
  Docker Linux/amd64、Jobs 2、无结果复用：preview 89 场景，apply 三分片 111/111/72
  均通过，含语法/ShellCheck；Docker 后端为有状态桩。正式网络保留、清理失败、
  IPv6 假成功、INT/TERM、硬杀后 recover、碰撞拒绝及 apply 正式项目名断言通过。
  两次旧 apply 桩接口失败原件保留；证据 `.tmp-restore-preview-cleanup-20261116/README.md`。

## 未决

- 待授权推送本轮两笔提交并自动发布，再在 B 用原 `.4` 归档/原资产正式复验。
  apply 前仍须落实 B 外部 ACME 续期隔离；不需先升级 A，不改写旧归档或改判旧失败。
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
