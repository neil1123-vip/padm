# Docker 容器化阶段 4 基线

## 状态

阶段 4 基础实现已完成（2026-08-18），不代表整体菜单对齐计划完成。
本阶段把必须访问宿主内核、设备和 Docker
防火墙链的能力接入 Docker desired state；普通 Docker 配置仍不获得额外
capability。2026-10-19 的透明能力及升级兼容修复已通过定向验证和独立只读审阅，
新增逻辑的 TUN/Phase 6 补验均通过；尚未形成包含当前修复的正式发布。

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
  与 stdout。启动前检查 `DOCKER-USER`、日志和 Fail2ban 配置。已有受管运行
  容器另支持固定 `padm-nginx` jail 状态查看及单个字面 IP 解封，操作前核对
  规格、生成配置正文、容器归属及已加载动作/有效属性缓存，不自动启动服务。
  运行时漂移或审计失败拒绝维护；不保证特权并发修改或恶意 Python 模块安全。
- TUN 只由 sing-box 核心服务创建：`host network`、root 运行覆盖、
  `NET_ADMIN`、`NET_BIND_SERVICE`、`DAC_OVERRIDE` 和 `/dev/net/tun`；
  `NET_BIND_SERVICE` 允许宿主低端口监听与透明 UDP 原目的端口绑定，
  `DAC_OVERRIDE` 使透明核心可以读取属主 `10001` 的受限目录及私钥，
  不放宽文件权限。`net-tun-check` 只在候选
  校验时运行，仍仅有 `NET_ADMIN`。入口检查设备、临时 TUN 创建能力和 nftables。
- TProxy 由 host-network 核心 inbound 加 `net-transparent` 防火墙 helper
  组成；运行态使用 schema 2 私密 state、随机 `padm-tproxy-*` 链及完整 token
  注释。mark 对应独占路由表，策略规则与路由记录 protocol，路由另记录 realm；
  逐条核对身份后精确撤销，不 flush。候选只读挂载当前 owner，验证旧资源
  及新参数冲突；旧两字段 state、固定链、未知随机链和外来漂移拒绝接管。
  空链崩溃窗口需人工核对归属，不能凭 state 或同名链自动删除。
  透明核心以 root 运行并只增加 `NET_ADMIN`、`NET_BIND_SERVICE`、`DAC_OVERRIDE`；
  `net-transparent` helper 仍只增加 `NET_ADMIN`。
- 配置候选、`config/net`、deployment、Compose、端口预检、宿主输入和启动
  失败均沿用现有备份/恢复事务；deployment 记录 integration settings 和
  WireGuard/TProxy listener（TCP/UDP）。

## 权限边界

普通核心、Nginx、ops 服务继续 `read_only`、`cap_drop: ALL`、
`no-new-privileges`，不挂载 Docker Socket。透明核心保留 `cap_drop: ALL`，
只声明 `NET_ADMIN`、`NET_BIND_SERVICE` 与 `DAC_OVERRIDE`；
网络 sidecar 仍仅声明 `NET_ADMIN`。
私钥 `0600`、数据目录 `0750` 及其它服务能力不变。只有 TUN profile 声明
`/dev/net/tun`，没有 `privileged`、`SYS_ADMIN` 或宽泛宿主目录挂载。

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
| 历史阶段的真实镜像 build/run、宿主内核规则和双架构 smoke | 当时本机 Docker daemon 未运行；不将历史静态结果作为真实内核证据 |

2026-10-19 补验：原生 Debian 13 amd64 在低端口门槛 `1024` 下，以正确
PID/FD/socket inode 证明 Xray 已收到 DNS、随后低端口绑定报权限错误。
同镜像/配置/五元组仅增加 `NET_BIND_SERVICE` 后 DNS `NOERROR`、两条答案，
查询 `8 ms`，宿主 sysctl 未改变。Docker Linux amd64 的真实 TProxy 与 Redirect
各六组（双核心 × IPv4/IPv6/双栈）通过，TProxy 包含 TCP/UDP/DNS；
permissions、tproxy-management、tun-management、phase3-edit、phase4-lifecycle
五项定向也通过，七项结果仅覆盖此前权限修复快照，不覆盖随后新增的升级兼容逻辑。
后者以另一同源码快照补验 TUN `25.516` 秒、Phase 6 `57.911` 秒，均 exit `0`。
本批远端 11 个临时文件已精确删除并复核不存在，三项业务 healthy、严格
HTTPS `200`/`verify=0`、IPv4 策略规则只余默认项。证据与精确耗时见
`documents/docker-native-acceptance-2026-10-18.md` 的能力根因收口记录，未重复 full。

## 已知边界

历史阶段的候选和事务测试使用 Docker CLI 静态解析及控制层 mock。
后续已取得限定原生 TUN/TProxy 生命周期、Fail2ban 封禁和 UDP 能力因果证据，
仍缺当前修复的正式 CLI/镜像及原生重启矩阵、原生 arm64 和公网双栈等验收；
普通容器或单包探针不补齐这些边界，支持状态保持既定范围。
