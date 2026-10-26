# Agent State

> 当前快照；详细证据见 Git、验收记录及 `.tmp-*`。

## 当前

- 整体计划未完成；透明代理保持关闭，不以阶段通过替代整体完成。
- VPS：Debian 13 amd64、bridge、公网 IPv4、正式 `3.42.0`；
  bundle=`489d16c9`，三业务 healthy、严格公网 TLS/200、续期 timer active。
- 本机 Docker Linux 可用；共享工具镜像，未重复 daily/full。
- 待发布：SSH guard 原子轮换竞态修复，涉及 net 与 runtime 两个读取端。
  仅对确认已换 inode 的旧 fd 重读一次，全部安全校验保留。

## 最近完成

- 8c.5：真实错误认证、精确 DROP、外部超时后整机重启；旧 jail exit=0、
  restart=no，collector/guard/规则清退，旧 owner 拒绝复用及正式停用通过。
  重新启用失败：正常 guard 轮换被误拒；未把安全停用当作恢复成功。
  `.tmp-native-ssh-reboot-3420-20261027/verification.json`。
- 旧实现 runtime/net 均已确定性复现；修复定向回归通过：
  `docker-ssh-preflight` 5744 ms、`docker-fail2ban-ownership` 31785 ms。
  双读取窗口、连续轮换、同 inode 修改、权限和硬链接负控均覆盖。
- VPS 原规格字节、材料及权限、timer、备份均恢复；业务健康。
  测试 unit/collector/net 路径、远端暂存、客户端已清理。
- 8c.4 正式 3.41.8 原生 SSH 来源失效清理、TUN/ICMP 当前源码定向矩阵、
  3.41.6/3.41.8 升级回滚及正式 3.42.0 升级重启已完成各自有限范围。

## 未决

- guard 修复须进入可信 net 镜像与 bundle，再补原生重新启用、封禁/解封。
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
