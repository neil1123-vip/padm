# Agent State

> 当前快照；详细证据见 Git、验收记录及 `.tmp-*`。

## 当前

- 整体计划未完成；透明代理保持关闭，不以阶段通过替代整体完成。
- VPS：Debian 13 amd64、bridge、公网 IPv4、正式 `3.42.2`；
  bundle=`4aaa9158`，三业务 healthy、严格公网 TLS/200、续期 timer active。
- 本机 Docker Linux 可用；共享工具镜像，未重复 daily/full。
- 5C.6d 新轮单 WS IPv4 端口事务整轮通过，456187 ms、exit 0；
  断网独验及 9 项篡改拒绝通过，已恢复清场，旧轮失败不改写。
- 原生账号与额度整轮验收进行中：`.tmp-native-account-workflow-20261027/`；
  远端同名 account-workflow 暂存，native.py restore 可独立恢复。

## 最近完成

- 8c.5：guard 轮换与 cgroup 成员采样竞态分别修复并可信发布。
  第二修复签名推送 `ef5194eb`；正式 3.42.2 发布门禁 30 成功/1 条件跳过，
  三件套验签及 300 个源码核对通过，五组镜像复用。
- 正式升级、两轮真实封禁/公网超时、一次正式解封及来源失效清退通过；
  第二轮封禁后 26180 ms/21 次检查健康。管理 22 始终可达，断网独验
  `.tmp-native-ssh-members-close-20261027/verification.json` 通过。
- 复用 3.42.0 已发生的真实重启，3.42.2 未新重启；两版失败原件保留。
  第二故障 6 项红测及修复定向 5569 ms，全部安全负控保持。
- 新轮 WS 真实封禁、两类失败回滚、443 → 25443 迁移、正式解封、
  双侧新端口正控及旧端口 TLS EOF 负控通过；6 个 fresh nonce、
  4 份 SQLite、4 次公网受封禁超时，原 inode/封禁保持。
  `.tmp-native-ws-close-20261027/verification.json`；完整归档已核摘要。
- 正式包原生 TUN 关闭态 status/diagnose 3830 ms 通过；13 个文件、
  容器身份、双族路由/规则、调度与 sysctl 不变，ICMP 未发包。
  断网独验及 7 项篡改拒绝通过，正式源码摘要匹配；本轮临时目录清理。
  `.tmp-native-icmp-off-20261027/verification.json`；不抵扣启用态收发缺口。
- VPS 原规格字节、材料及权限、timer、备份均恢复；业务健康。
  SSH/WS 测试路径、远端暂存、客户端已清理；清场后严格 TLS/443/200。
- 8c.4 正式 3.41.8 原生 SSH 来源失效清理、TUN/ICMP 当前源码定向矩阵、
  3.41.6/3.41.8 升级回滚及正式 3.42.0 升级重启已完成各自有限范围。

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

## 工作区注意

- 保留既有未跟踪 `.tmp-ci-timeout-actionlint.tar.gz`、
  `.tmp-reality-palette-preview*`、`.tmp-remote-xray-config.json`、`NUL`。
