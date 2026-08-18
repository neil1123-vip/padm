# Docker 容器化阶段 4 基线

## 状态

阶段 4 已完成（2026-08-18）。本阶段把必须访问宿主内核、设备和 Docker
防火墙链的能力接入 Docker desired state；普通 Docker 配置仍不获得额外
capability。阶段 4 改动未单独提交，等待用户确认提交点。

## 实现范围

- `host_integrations` 合同支持 `wireguard`、`fail2ban`、`tun` 和 `tproxy`，
  每项固定 profile、设备、规则所有权和 settings；TUN 与 TProxy 互斥，透明
  代理不与 Nginx WebSocket 入口混用。
- WireGuard 使用 `net-wireguard`、host network 和 `NET_ADMIN`，只读取 root
  持有且组/其他用户无权限的 `secrets/net/wireguard/wg-padm.conf`。入口拒绝
  `PreUp`、`PostUp`、`PreDown`、`PostDown`、`DNS` 和 `SaveConfig` hook，固定
  接口名 `wg-padm`，并用状态文件保证重启/退出清理只处理本项目接口。
- Fail2ban 使用 `net-fail2ban`，只保护 Docker Nginx。Nginx 写入真实
  `$remote_addr` 访问日志；动作固定进入 `DOCKER-USER`，用
  `--ctorigdstport` 匹配 DNAT 前的公网端口，数据库和日志分别落到持久目录
  与 stdout。启动前检查 `DOCKER-USER`、日志和 Fail2ban 配置。
- TUN 只由 sing-box 核心服务创建：`host network`、`NET_ADMIN`、root 运行
  覆盖和 `/dev/net/tun`；`net-tun-check` 只在候选校验时运行。入口检查设备、
  临时 TUN 创建能力和 nftables。
- TProxy 由 host-network 核心 inbound 加 `net-transparent` 防火墙 helper
  组成；规则只属于 `padm-tproxy`，使用固定 mark、路由表和 IPv4 PREROUTING
  链，退出或启动失败会撤销 rule/route/chain。前置检查转发、TPROXY target、
  mark 冲突和链所有权。
- 配置候选、`config/net`、deployment、Compose、端口预检、宿主输入和启动
  失败均沿用现有备份/恢复事务；deployment 记录 integration settings 和
  WireGuard/TProxy listener（TCP/UDP）。

## 权限边界

普通核心、Nginx、ops 服务继续 `read_only`、`cap_drop: ALL`、
`no-new-privileges`，不挂载 Docker Socket。特殊服务仅声明 `NET_ADMIN`；
只有 TUN profile 声明 `/dev/net/tun`，没有 `privileged`、`SYS_ADMIN` 或宽泛
宿主目录挂载。

## 验证结果

| 验证 | 结果 |
|---|---|
| `bash -n` / `sh -n`、JSON `jq empty`、`git diff --check` | 通过 |
| `docker-phase1` | 通过，224.518 秒 |
| `docker-phase2` | 通过，2.297 秒（Bake/Compose 静态检查） |
| `docker-phase3` | 通过，226.541 秒 |
| `docker-phase4` | 通过，134.035 秒 |
| 四种动态候选的真实 `docker compose config --format json` | 通过 |
| `fast-full` | 通过，121.929 秒 |
| `all` | 通过，782.865 秒 |
| 真实镜像 build/run、宿主内核规则和双架构 smoke | 本机 Docker daemon 未运行，留给阶段 5 CI |

## 已知边界

TProxy/TUN 的真实客户端流量、Fail2ban 实际封禁和宿主重启恢复需要 Linux
rootful Docker 主机验证；本阶段的候选和事务测试使用 Docker CLI 静态解析及
控制层 mock，不把 Windows 主机模拟结果当作内核验收。
