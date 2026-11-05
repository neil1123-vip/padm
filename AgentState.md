# Agent State

> 当前快照；详细证据见 Git、验收记录及 `.tmp-*`。

## 当前

- 整体计划未完成；透明代理保持关闭，不以阶段通过替代整体完成。
- `.2` 独立发布、正式 lock/应用交付及已授权 VPS 升级完成。
- VPS：Debian 13 amd64、bridge、公网 IPv4、正式 `3.43.2`/source=`d8bac249`；
  保留 Xray/协议 21，三业务 healthy、无 OOM，透明关闭，两个 timer active/enabled。
- 本机 Docker Linux 可用，复用工具镜像，未跑 full。
- 原生账号 8 阶段及恢复整轮通过，508821 ms/exit 0；
  26 正/5 拒绝、断网独验及 13 项篡改拒绝通过，已恢复清场。
- 4A.4 备份/恢复、健康失败回滚与分享授权 7 阶段通过（616534 ms/exit 0）；
  断网独验及 10 项篡改拒绝通过并清场。

## 最近完成

- 3D.26 的 16 个协议管理 supported；3D.27 Nginx/WS/双栈 UUID 通过；
  14 个 deferred 已对账，合同仅改 reason，原件见实施计划。
- 2026-11-05：`.2` 正式发布，CI `42008070777` 双原生架构构建、Alpine、
  Reality/ML-DSA、固定 share 全通过；四资产与已验候选一致，旧 `.1` 不变。
- lock `.2`/`8b71c705`：phase2 1666 ms、daily 34/34/259710 ms 均 exit 0、
  非缓存；正式镜像 Reality/ML-DSA 整轮 34504 ms/exit 0、非缓存。
- 应用 `3.43.2`/`d8bac249` 发布：CI `42010549859` 32 job 成功、零跳过，
  18 分片、双架构 smoke 通过；协议 job 12 分 34 秒，保留 2 worker/20 分钟限额。
  三资产摘要、独立 Sigstore 验签及 306 源码核对通过。
- VPS `3.42.5`→`3.43.2` 成功，正式 validate、镜像绑定、配置/材料权限保持；
  公网严格 TLS/200→错 UUID 拒绝→TLS/200；19 条身份/限额/逐账号累计保持，
  自然采集新增上传 3555、下载 43868 字节；客户端夹具与容器已清理。
- 本轮恢复点 `update.956SI1` 保存真实旧版 `3.42.5`，正式只读校验器通过，
  且为最新有效 update 快照；未额外执行生产回滚或整机重启。
  证据 `.tmp-release-revision2-20261105/`、`.tmp-revision2-vps-prep-20261105/`。
- 原生 3.42.3 账号与业务恢复已清场并断网独验，失败原件保留；
  `.tmp-native-account-close-20261027/verification.json`、
  `.tmp-native-business-close-20261027/verification.json`。
  正式 run 40406148426 三件套验签及 300 源码核对通过，
  材料权限、timer、boot 和累计保持；未新增生产改动或本版整机重启。

## 未决

- WS 公网旧端口 TCP 拒绝、原生 IPv6 未证明；固定 CONNECT 只证 TLS EOF。
- ICMP 原生启用态收发/arm64/公网/重启、IPv6/traceroute/PMTU；
  真实 TUN 必须启用宿主透明接管，受透明保持关闭约束。
- 原生 arm64 整机、IPv6/双栈、新主机灾备、多机控制/WG、WARP 实账号、
  约 2026-12-17 自然 ACME 续期缺条件；VPS 无全局 IPv6/默认路由。
- 公网 h3/CDN、其它客户端/算法、性能长稳未扩范围；gRPC Cloudflare
  透传缺有效 Zone 授权，不重跑无变化矩阵。
- 透明启用重启按要求不做；SOCKS UDP、Xray 解析后阻断继续拒绝。
- 旧 Vision reset、XHTTP TLS 超时、TUIC 超时缺原现场材料，根因未定。
- 旧 sing-box `1.14.4`→Xray `26.10.31` 失败原件 `d18652f4...` 保留；
  `.2` 正式包/镜像整轮通过，交付二进制 hybrid-only、其它指纹/公网组合未验。
  VPS 维持 Xray，不能把本次升级当成活动 sing-box 业务证明。
  配对直接装测试规格，不证明 CLI 自动启用整链或独立 SNI；
  sing-box 拒绝配对及带配对来源的跨核心复制。

## 工作区注意

- 本地 Git 排除并保留 `.tmp-ci-timeout-actionlint.tar.gz`、
  `.tmp-reality-palette-preview*`、`.tmp-remote-xray-config.json`、`NUL`。
