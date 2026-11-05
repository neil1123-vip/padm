# Agent State

> 当前快照；详细证据见 Git、验收记录及 `.tmp-*`。

## 当前

- 整体计划未完成；透明代理保持关闭，不以阶段通过替代整体完成。
- 已授权 `.2` 独立发布、正式 lock/应用交付及 VPS 升级，当前执行中。
- VPS 实时基线：Debian 13 amd64、bridge、公网 IPv4、正式 `3.42.5`；
  source=`813fd481`，三业务 healthy、透明关闭，流量/续期 timer active。
- 本机 Docker Linux 可用，复用工具镜像，未跑 full。
- 原生账号 8 阶段及恢复整轮通过，508821 ms/exit 0；
  26 正/5 拒绝、断网独验及 13 项篡改拒绝通过，已恢复清场。
- 4A.4 备份/恢复、健康失败回滚与分享授权 7 阶段通过（616534 ms/exit 0）；
  断网独验及 10 项篡改拒绝通过并清场。

## 最近完成

- 2026-11-04：3D.26 的 16 个协议管理 supported，定向及 daily 34/34 通过。
- 3D.27 Nginx/WS/双栈 UUID 回滚与拒绝验收通过，原件见实施计划。
- 14 个 deferred 已对账；合同只改 reason，状态/schema 不变，详见 2026-11-04 对账表。
- 2026-11-05：`.2` 正式发布，CI `42008070777` 双原生架构构建、Alpine、
  Reality/ML-DSA、固定 share 全通过；四资产与已验候选一致，旧 `.1` 不变。
- 正式 lock 已切 `.2`；phase2 1666 ms、daily 34/34/259710 ms 均 exit 0、
  非缓存；应用 CI 与 VPS 升级待执行，证据 `.tmp-release-revision2-20261105/`。
- 测试限时改为 10 秒覆盖 REALITY 5 秒启动轮询；定向 36715 ms/exit 0，
  受控 20 轮通过，含 5.15 秒等待；候选与证据 `.tmp-reality-ci-41950689348/`。
- 协议矩阵按核心拆分，公共断言、2 worker、20 分钟限额保留；本机定向
  4/4、489663 ms/exit 0，调度合同 3492 ms；已签名推送 `a7604399`。
- Release `42003075411` 成功，18 分片全通过；协议 job 14 分 25 秒、
  内部 841407 ms，原超时阻塞关闭；单轮通过不代表长期稳定性。
- 应用 `3.43.1`/`fb140662` 已自动发布；三资产摘要、独立签名及 306 源码
  核对通过，5 个双架构镜像复用 `3.43.0`；正式 sing-box 仍 `.1`。
  证据 `.tmp-protocol-shard-close-20261105/verification.json`。
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
- 旧正式 sing-box `1.14.4`→Xray `26.10.31` 失败原件 `d18652f4...` 保留。
  新修订已保留 Chrome 混合 key share，正式包整轮通过，认证/证书基线不变。
  `.2` 交付二进制 hybrid-only、其它指纹未验。
  配对直接装测试规格，不证明 CLI 自动启用整链或独立 SNI；
  sing-box 拒绝配对及带配对来源的跨核心复制。

## 工作区注意

- 本地 Git 排除并保留 `.tmp-ci-timeout-actionlint.tar.gz`、
  `.tmp-reality-palette-preview*`、`.tmp-remote-xray-config.json`、`NUL`。
