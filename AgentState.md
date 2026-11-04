# Agent State

> 当前快照；详细证据见 Git、验收记录及 `.tmp-*`。

## 当前

- 整体计划未完成；透明代理保持关闭，不以阶段通过替代整体完成。
- VPS：Debian 13 amd64、bridge、公网 IPv4、正式 `3.42.3`；
  bundle=`36efda04`，三业务 healthy、严格公网 TLS/200、续期 timer active。
- 本机 Docker Linux 可用，复用工具镜像，未跑 full。
- 原生账号 8 阶段及恢复整轮通过，508821 ms/exit 0；
  26 正/5 拒绝、断网独验及 13 项篡改拒绝通过，已恢复清场。
- 4A.4 业务备份/preview/merge/replace、真实健康失败回滚与分享授权恢复
  7 阶段通过，616534 ms/exit 0；断网独验及 10 项篡改拒绝通过并清场。

## 最近完成

- 2026-11-04：3D.26 的 16 个公开协议管理改为 supported；
  补 Reality ML-DSA-65 生成/复用、配对校验、配置/pqv/同身份下行传播，
  以及受管 Nginx 缺失/损坏的窄修复；未保护 WS 管理保持保护来源冻结。
  20 个协议/核心 CLI 闭环 555947 ms，Reality 167987 ms、
  菜单 139362 ms、编辑/矩阵 52509 ms、范围管理 30623 ms 均通过。
  daily 34/34、213505 ms、非缓存；完整谓词 434 差分通过，
  固定 Xray/ops 断网 ML-DSA 配对及错配验证通过。
  详细结果与三次失败原件见实施计划 3D.26；本轮未跑 full。
- 原生 3.42.3 账号与业务恢复已清场并断网独验，失败原件保留；
  `.tmp-native-account-close-20261027/verification.json`、
  `.tmp-native-business-close-20261027/verification.json`。
  正式 run 40406148426 三件套验签及 300 源码核对通过，
  材料权限、timer、boot 和累计保持；未新增生产改动或本版整机重启。

## 未决

- WS 公网旧端口 TCP 拒绝、原生 IPv6 未证明；固定 CONNECT 只证 TLS EOF。
- ICMP 原生启用态收发/arm64/公网/重启、IPv6/traceroute/PMTU；
  真实 TUN 必须启用宿主透明接管，受透明保持关闭约束。
- 原生 arm64、IPv6/双栈、新主机灾备、多机控制/WG、WARP 实账号、
  约 2026-12-17 自然 ACME 续期缺条件；VPS 无全局 IPv6/默认路由。
- 公网 h3/CDN、其它客户端/算法、性能长稳未扩范围；gRPC Cloudflare
  透传缺有效 Zone 授权，不重跑无变化矩阵。
- 透明启用重启按要求不做；SOCKS UDP、Xray 解析后阻断继续拒绝。
- 旧 Vision reset、XHTTP TLS 超时、TUIC 超时缺原现场材料，根因未定。
- 新 ML-DSA 实际客户端连通未补；按原生 target_host 探测，
  不证明独立 SNI；sing-box 拒绝配对及带配对来源的跨核心复制。

## 工作区注意

- 本地 Git 排除并保留 `.tmp-ci-timeout-actionlint.tar.gz`、
  `.tmp-reality-palette-preview*`、`.tmp-remote-xray-config.json`、`NUL`。
