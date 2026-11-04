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

- 2026-11-04：3D.26 的 16 个协议管理 supported，定向及 daily 34/34 通过。
- 3D.27：Nginx 缺失/损坏真实启动失败回滚和修复、活动 WS 防护下
  未保护入口增删改通过；双栈 16 正/16 错 UUID 拒绝，SQLite/规则保持。
  `docker-fail2ban-source-real` 471430 ms/exit 0/非缓存；
  原件 `.tmp-regression-docker-e0b03ef4a99e46aa8b0746869cca5945/`。
- 14 个 deferred 已逐项对账，合同只改 reason，状态/schema 不变；
  已有原生证据、剩余环境条件和拒绝边界见 2026-11-04 对账表。
- 已签名提交并推送 `4c8ff0c2`；Reality 修订 `1.14.4-padm.1` 已发布。
  CI `41849182833` 原生双架构构建、功能检查及 Alpine smoke 全通过。
  四资产 API/SHA256SUMS、源码补丁与 Cronet 摘要正确；旧版资产未变。
  正式 amd64 与来源包重建候选逐字节相同，材料 `.tmp-publish-sing-box-20261104/`。
  正式下载镜像 Reality 整轮 exit 0/33505 ms，结果 `559f73c0...`；
  真实 lock 已更新，phase2 exit 0/1585 ms，待提交及应用发布。
- 应用 CI `41849182832` 的协议分片超过 10 分钟被取消，其余 21 检查通过。
  该子项旧本机成功耗时 556 秒；仅该分片改 20 分钟，保留原断言，待新 CI。
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
- 旧正式 sing-box `1.14.4`→Xray `26.10.31` 失败原件 `d18652f4...` 保留。
  新修订已保留 Chrome 混合 key share，正式包整轮通过，认证/证书基线不变。
  hybrid-only/其它指纹及 arm64 Reality 整轮未证明；普通本机 selector 仍固定旧镜像。
  应用镜像/控制包发布与正式镜像补验待 CI；不覆盖旧版资产，见 3D.27。
  配对直接装测试规格，不证明 CLI 自动启用整链或独立 SNI；
  sing-box 拒绝配对及带配对来源的跨核心复制。

## 工作区注意

- 本地 Git 排除并保留 `.tmp-ci-timeout-actionlint.tar.gz`、
  `.tmp-reality-palette-preview*`、`.tmp-remote-xray-config.json`、`NUL`。
