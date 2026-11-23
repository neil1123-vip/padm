# ⚙️ 服务与系统运维

[🏠 返回首页](../README.md#文档导航) · [🌍 English](en/operations.md)

管理原生版的流量出口、核心版本、服务状态和宿主机配置。Docker 版的操作见 [Docker 版使用指南](docker-guide.md)。

[路由与访问控制](#路由与访问控制) · [核心与服务](#核心与服务) · [系统与脚本](#系统与脚本) · [安装后的控制点](#安装后的控制点)

## 路由与访问控制

🧱 从 `路由与访问控制` 配置服务端的流量出口和访问规则。

| 功能 | 说明 |
| --- | --- |
| 🧭 分流工具 | WARP WireGuard 出站、IPv6 出站、Socks5 中继、DNS 覆盖和 hosts 覆盖。 |
| ⛔ BT 下载管理 | 通过协议嗅探阻断已识别的 bittorrent 流量；加密、混淆或部分 uTP 场景无法保证完全覆盖。 |
| 🧱 访问控制 | 域名/IP 阻断、直连例外、区域阻断。 |

Xray 使用 routing 与 blackhole / direct 出站，sing-box 使用 remote rule_set、domain_suffix / domain 和 ip_cidr。直连例外优先于阻断规则，可用于系统更新、证书签发或其他需要直连的服务。

> [!WARNING]
> 区域阻断可能影响系统更新、证书申请和应用连接。Xray 切换到 WARP、IPv6 或 Socks5 全局出站时，也会移除现有的 BT 阻断和访问控制规则。

> [!NOTE]
> 修改访问控制会先备份相关规则，写入后校验核心配置。校验失败会回滚，并显示日志路径。

## 核心与服务

⚙️ `核心与服务` 首页展示本地版本、配置、服务和 Xray Geo 状态。需要校验配置时进入「检查与诊断」，需要查远端版本时进入「升级/切换版本」。尚未安装核心时，仍可查看状态并执行不依赖核心二进制的只读扫描。

| 菜单 | 用途 |
| --- | --- |
| `1. Xray-core 生命周期` | 选择版本、校验配置并检查升级风险。 |
| `2. sing-box 生命周期` | 选择版本、校验配置并检查升级风险。 |
| `3. 服务运行态` | 查看、启动、停止或重启核心服务，以及 padm 依赖的 Nginx。 |
| `4. 日志与诊断` | 查看核心日志、检查 Nginx 配置。 |
| `5. Xray Geo 数据` | 查看或更新 `geosite.dat` 和 `geoip.dat`，设置自动更新。 |
| `0. 返回主菜单` | 也可直接回车返回。 |

### Xray 主核心与 sing-box 辅助核心

📶 已装 Xray 时，从 `协议与入口 → Hysteria2 管理` 或 `协议与入口 → Tuic 管理` 增量安装 sing-box。辅助核心会独立生成配置和运行服务，订阅和状态页会读取两套核心。

从 `安装与重装` 完整安装 sing-box 会切换主核心并清理 Xray。`--core` 用于指定一个核心，可选 `xray` 或 `sing-box`。

辅助 Hysteria2/TUIC 重装时，回车一次即可复用本协议全部用户、端口和网络参数；选择 `n` 后逐项调整，仍可保留用户只修改端口或网络参数。取消输入或前置校验失败不会进入安装事务，也不影响主核心及其他协议。

Hysteria2 默认使用 Brutal 固定带宽，按客户端视角填写上行和下行。选择 BBR 时，客户端会自适应带宽。端口跳跃范围会写入 sing-box 订阅的 `server_ports`。

可选混淆支持 `salamander` 和 `gecko`，配置会写入 Clash Meta、sing-box 和 Hysteria2 URI。重装时回车会复用已有模式和混淆配置，输入 `off` 可关闭混淆。

### 🔎 配置检查与版本切换

「检查与诊断」在本机依次执行配置校验和已知升级风险扫描，分别显示「通过」「需关注」「失败」或「无法检查」。配置校验失败或缺少核心二进制时，仍会继续执行能运行的风险检查。

「升级/切换版本」列出最近 20 个正式版和预发布版。输入编号选择版本，回车使用最新正式版，输入 `0` 或结束输入取消。选择预发布版后先用目标二进制预检，通过后再确认是否安装。实际连接可在升级后用只读验收检查。

- **Xray。** 依次运行普通和严格校验。运行检查失败显示「失败」，仅严格阶段未通过时显示「需关注」。
- **sing-box。** 有分片时先合并到临时文件，再执行 `sing-box check -c <临时配置>`。没有分片时校验现有合并配置。

校验以只读方式运行。兼容提示单独显示，技术阶段和日志路径可在结果详情中查看。

sing-box 的兼容提示显示本机版本，优先扫描分片、无分片时扫描合并配置，同类提示只报告一次。旧 WireGuard/special outbound、DNS server 格式和 domain_strategy 等显示为历史兼容提示；1.14 弃用字段提示在 1.16 前迁移，TUN `stack` 提示 1.15 起弃用、1.17 移除。JSON 解析或扫描失败仍显示“失败”；当前配置能否被接受以已安装核心的 `merge + check` 为准。升级和安装预检仍保留严格扫描、迁移拒绝和失败回滚。

升级或回退核心时，脚本先下载目标版本到临时目录，用目标二进制校验当前配置；校验通过后才替换 `/etc/padm/xray/xray` 或 `/etc/padm/sing-box/sing-box` 并重启服务。若新核心启动失败，会尝试恢复旧二进制。

Nginx 的启停、重启和平滑重载适用于当前由 padm 使用的服务。其他用途的 Nginx 仅展示状态。需要调整 Nginx 配置时，从对应的协议、站点或订阅菜单进入。

### sing-box 统计版与流量恢复

原生部署的 sing-box 主核心、副核心及 Docker 的 `padm-sing-box` 镜像默认使用本仓库 CI 从上游源码构建的统计版，保留上游默认构建标签并追加 `with_purego,with_v2ray_api`，具备 Hysteria2、TUIC 等协议的按用户流量统计能力。原生版本菜单还可选择上游尚未发布统计包的版本，确认后在本机编译；Docker 继续下载锁定镜像。

`with_grpc` 控制完整的 gRPC 传输实现；未启用时仍有默认 gRPC lite，本项目的 Reality gRPC 配置可以使用。按用户统计由 `with_v2ray_api` 独立启用，Hysteria2 和 TUIC 也不依赖 `with_grpc`。

Docker 镜像按 `versions.lock` 固定统计包版本和双架构 SHA256；官方包摘要单独保留，用于统计版构建时校验 Cronet 来源。Docker 已接入上述用户采集和额度管理，执行 `padm-docker update` 会同时更新镜像、宿主控制 bundle 并初始化统计。尚不支持自更新的旧版先按 [Docker 更新说明](docker-guide.md#更新) 完成一次过渡刷新，必须使用新下载的入口，避免旧 `padm-docker install` 遗漏新增共享模块。现有协议配置会保留，协议入口仍以 Docker 支持矩阵为准。以下菜单步骤适用于原生部署。

📊 原生 sing-box 提示 `v2ray api is not included in this build`，或此前为了恢复连接而清理过统计配置时，可按下面的步骤恢复统计。

1. 从 `系统与脚本` 更新 padm 脚本。
2. 进入 `核心与服务 → sing-box 生命周期 → 升级/切换版本`，回车选择最新正式版，或输入列表中的版本编号。
3. 在 `核心与服务` 确认 `sing-box 用户统计能力` 为“支持”、服务正常，并执行“检查与诊断”。

升级成功后会根据现有协议用户自动恢复 `14_stats_api.json` 并重载核心，统计 API 仅监听 `127.0.0.1:10087`；已有端口、证书和用户凭据继续保留。统计恢复失败时会尝试回滚核心和配置。复用上次安装配置时，也会将缺少统计能力的旧核心切换为统计版。未采集期间的历史流量无法补算，恢复后的新流量继续按现有账号归集。

升级/切换版本菜单显示上游正式版和预发布版，优先下载本仓库已发布的 `sing-box-v<上游版本>`。明确缺少统计包时，可选择在原生 Linux amd64 / arm64 上编译：解析目标源码提交并下载固定提交的源码，按源码要求下载并校验 Go 工具链，复用与 CI 相同的构建参数，并从该版本官方包提取已校验的 `libcronet.so`。工具链、依赖和编译缓存保留在 `/etc/padm/cache/sing-box-build`，不会替换系统 Go。编译期间旧服务继续运行，版本、统计能力和当前配置校验通过后才进入安装事务，失败或取消不会替换旧核心。网络、限流、摘要或版本校验失败直接停止，不会自动改走编译。旧源码缺少当前构建文件时会拒绝；不承诺所有历史版本可编译或兼容当前配置。

## 系统与脚本

🧰 从 `系统与脚本` 更新 padm、核对安装状态，或配置宿主机防护和网络。

- 🔄 **更新 padm 脚本。** 订阅控制服务已启用或正在运行时，会同时刷新并重启。刷新失败时，脚本更新会保留，按菜单提示从控制面维护入口重试。
- 🧾 **查看脚本安装状态。** 核对入口、版本、ref 和 manifest。
- 🛡️ **Fail2ban 防护。** 原生版提供 SSH、`/s/control/` 和站点扫描防护。Docker 版提供 WS、控制面和专用 SSH service 防护，完整宿主验收仍待补。
- 🚀 **网络优化。** 查看当前网络状态，启用 BBR + fq 或移除 padm 的 BBR 配置。

启用 BBR + fq 时，padm 使用当前内核提供的 BBR，并向 `/etc/sysctl.d/99-padm-bbr.conf` 写入以下配置。

```conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

选择「移除 padm 的 BBR 配置」会删除该文件，并尝试恢复启用前的拥塞控制和队列调度（qdisc）。

## 安装后的控制点

📂 原生版的入口、配置和状态位于以下路径。排障或备份时可按功能定位。

| 路径 | 作用 |
| --- | --- |
| `/etc/padm/install.sh` | 🚪 已安装入口；`padm` 命令最终回到这里。 |
| `/etc/padm/.padm-ref` | 🏷️ 当前已安装模块 ref，用于脚本刷新状态展示。 |
| `/etc/padm/.padm-module-manifest` | 🧾 当前模块 manifest，用于检测模块集是否完整。 |
| `/etc/padm/xray/conf/` | 🧩 Xray 分片配置目录；用 `xray -test -confdir` 校验。 |
| `/etc/padm/sing-box/conf/config/` | 🧩 sing-box 分片配置目录；合并成 `config.json` 后校验。 |
| `/etc/padm/tls/` | 🔐 本机 TLS 证书、密钥和 acme 日志。 |
| `/etc/padm/subscribe/` | 🔗 面向客户端发布的订阅产物。 |
| `/etc/padm/subscribe_local/` | 📦 本机订阅缓存和中间产物。 |
| `/etc/padm/subscribe_groups/groups.json` | 🧭 订阅组状态真源，包含角色、服务器源、用户订阅、额度、同步和流量统计。 |
| `/etc/padm/subscribe_groups/backups/` | 💾 `groups.json` 备份目录。 |
| `/etc/padm/wireguard/` | 🔒 主控/被控 WireGuard 控制面状态、密钥和 peer 信息。 |
| `/etc/wireguard/wg-padm.conf` | 🔒 padm 控制面 WireGuard 配置。 |
| `/etc/padm/reality_entry_host` | 📍 当前 Reality 客户端入口地址。 |
| `/etc/padm/reality_targets_results.tsv` | 📊 Reality 目标库，按目标保留最新实测结果。 |

构建统计版和更新依赖的流程见 [🛠️ 维护者指南](maintenance.md)。
