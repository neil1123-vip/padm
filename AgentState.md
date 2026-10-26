# Agent State

> 当前快照；详细证据见 Git、验收记录及 `.tmp-*`。

## 当前

- 整体计划未完成；透明代理保持关闭，不以阶段通过替代整体完成。
- VPS：Debian 13 amd64、bridge、公网 IPv4、正式 `3.42.2`；
  bundle=`4aaa9158`，三业务 healthy、严格公网 TLS/200、续期 timer active。
- 本机 Docker Linux 可用；复用工具镜像，按最终快照回归，未跑 full。
- 5C.6d 新轮单 WS IPv4 端口事务整轮通过，456187 ms、exit 0；
  断网独验及 9 项篡改拒绝通过，已恢复清场，旧轮失败不改写。
- 原生账号整轮在额度阶段发现 Xray 26.10.21 候选扩展名缺陷，已恢复清场；
  共享额度函数已修复，定向及日常 34/34 通过，待可信发布后续验。

## 最近完成

- 账号创建/复制/改名、停用/启用原生 4 阶段，13 正/1 拒绝通过；
  quota rc1 原件和 SSH 中断接续保留，整轮不通过。恢复独验通过，
  临时账号/远端暂存/两个容器已清，清场后严格公网 TLS/200（743 ms）。
- 额度候选改独立 0750 子目录/config.json，0640 与组归属保持；
  正式固定 Xray 非 root 断网五项实测通过，避免健康扫描提前合并候选。
  docker-traffic 5014 ms，daily 207118 ms/34 项，均非缓存；
  `.tmp-native-account-workflow-20261027/failure-verification.json`。
- 8c.5：guard 轮换与 cgroup 成员采样竞态已修复并可信发布；
  3.42.2 门禁 30 成功/1 条件跳过，验签与 300 个源码核对通过。
- 正式升级、两轮真实封禁/公网超时、一次正式解封及来源失效清退通过；
  第二轮封禁后 26180 ms/21 次检查健康。管理 22 始终可达，断网独验
  `.tmp-native-ssh-members-close-20261027/verification.json` 通过。
- 复用 3.42.0 真实重启，3.42.2 未新重启；两版失败原件保留。
- 新轮 WS 真实封禁、两类失败回滚、443 → 25443 迁移、正式解封、
  双侧新端口正控及旧端口 TLS EOF 负控通过；6 个 fresh nonce、
  4 份 SQLite、4 次公网受封禁超时，原 inode/封禁保持。
  `.tmp-native-ws-close-20261027/verification.json`；完整归档已核摘要。
- 正式包原生 TUN 关闭态 status/diagnose 3830 ms 通过；13 个文件、
  容器身份、双族路由/规则、调度与 sysctl 不变，ICMP 未发包。
  断网独验及 7 项篡改拒绝通过，正式源码摘要匹配；本轮临时目录清理。
  `.tmp-native-icmp-off-20261027/verification.json`；不抵扣启用态收发缺口。
- 原规格/材料权限/timer/备份均恢复；SSH/WS 暂存和客户端已清理。

## 未决

- WS 公网旧端口 TCP 拒绝、原生 IPv6 未证明；固定 CONNECT 只证 TLS EOF。
- 账号额度/轮换/删除整轮需修复可信发布后重跑；不将前四阶段当完成。
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
