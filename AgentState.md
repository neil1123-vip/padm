# Agent State

> 当前快照；详细证据见 Git、验收记录及 `.tmp-*`。

## 当前

- 整体计划未完成；透明代理保持关闭，不以阶段通过替代整体完成。
- VPS：Debian 13 amd64、bridge、公网 IPv4、正式 `3.42.1`；
  bundle=`e9b24415`，三业务 healthy、严格公网 TLS/200、续期 timer active。
- 本机 Docker Linux 可用；共享工具镜像，未重复 daily/full。
- 待发布：SSH cgroup 成员采样竞态修复；仅对可证明的非 MainPID 加入/退出
  完整重取证一次，固定 unit/master/已见监听，其余安全校验保留。

## 最近完成

- 8c.5：真实错误认证、精确 DROP、外部超时后整机重启；旧 jail exit=0、
  restart=no，collector/guard/规则清退，旧 owner 拒绝复用及正式停用通过。
  重新启用失败：正常 guard 轮换被误拒；未把安全停用当作恢复成功。
  `.tmp-native-ssh-reboot-3420-20261027/verification.json`。
- guard 修复已签名推送 `888b62e4` 并正式发布 3.42.1；32 项发布任务成功，
  三件套验签及 300 个包内源码核对通过，仅 net 镜像重建。
- 正式升级后 guard 连续 25 秒健康、首轮真实封禁/解封通过；第二轮认证
  子进程自然退出使 cgroup 采样变化，collector 安全清退，未记为通过。
  `.tmp-native-ssh-guard-close-20261027/verification.json` 已断网独验。
- 第二故障旧实现 6 项红测；修复 `docker-ssh-preflight` 5569 ms 通过。
  连续变动、主进程/代次/监听变化、权限和 namespace 等负控仍拒绝。
- VPS 原规格字节、材料及权限、timer、备份均恢复；业务健康。
  测试 unit/collector/net 路径、远端暂存、客户端已清理。
- 8c.4 正式 3.41.8 原生 SSH 来源失效清理、TUN/ICMP 当前源码定向矩阵、
  3.41.6/3.41.8 升级回滚及正式 3.42.0 升级重启已完成各自有限范围。

## 未决

- cgroup 修复须进入可信 bundle，再补原生两轮封禁/解封和来源失效清理。
- ICMP 原生宿主/arm64/公网/重启、IPv6/traceroute/PMTU。
- 原生 arm64、IPv6/双栈、新主机灾备、多机控制/WG、WARP 实账号、
  约 2026-12-17 自然 ACME 续期缺条件；VPS 无全局 IPv6/默认路由。
- 公网 h3/CDN、其它客户端/算法、性能长稳未扩范围；gRPC Cloudflare
  透传缺有效 Zone 授权，不重跑无变化矩阵。
- 透明启用重启按要求不做；SOCKS UDP、Xray 解析后阻断继续拒绝。
- 旧 Vision reset、XHTTP TLS 超时、TUIC 超时缺原现场材料，根因未定。

## 工作区注意

- 保留既有未跟踪 `.tmp-ci-timeout-actionlint.tar.gz`、
  `.tmp-reality-palette-preview*`、`.tmp-remote-xray-config.json`、`NUL`。
