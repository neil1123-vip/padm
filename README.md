<h1 align="center">padm</h1>

<p align="center"><strong>✨ 面向 Xray-core / sing-box 的一站式安装与长期运维脚本</strong></p>
<p align="center">🚀 节点安装 · 🔗 订阅发布 · 🌐 多服务器协同 · 🧭 路由控制 · 🔐 证书维护 · ⚙️ 核心升级</p>
<p align="center"><a href="documents/en/README_EN.md">🌍 English</a></p>

<p align="center">
  <a href="#快速选择">🚀 快速选择</a> ·
  <a href="#安装">📦 安装</a> ·
  <a href="#docker-版">🐳 Docker 版</a> ·
  <a href="#协议选择">🧭 协议选择</a> ·
  <a href="#订阅与用户">🔗 订阅与用户</a>
  <br>
  <a href="#路由与访问控制">🧱 路由控制</a> ·
  <a href="#核心与服务">⚙️ 核心服务</a> ·
  <a href="#参数参考">📋 参数参考</a> ·
  <a href="#验收与回归">✅ 验收回归</a>
</p>

---

> **✨ 一句话选协议**
>
> 🧭 直连/有域名 `Reality Vision` · 🌐 CDN/反代 `Reality XHTTP`
>
> 📍 无域名 `Reality` · 🛡️ TLS 指纹抗性 `NaiveProxy`

## 快速选择

第一次使用时，不需要先理解全部协议。运行脚本后按这个路径走：

| 场景 | 菜单入口 | 说明 |
| --- | --- | --- |
| 🧭 不知道选什么 | `安装与重装` -> `推荐直连 Reality Vision` | 新手首选，配置少，适合直连或自有域名入口。 |
| 🌐 需要 CDN / 反代 | `安装与重装` -> `推荐 CDN Reality XHTTP` | 新建 CDN 场景优先选它，使用 XHTTP 与 XMUX。 |
| 📍 没有域名 | `安装与重装` -> `无域名 Reality` | 使用服务器 IP 或自定义 entry-host，不需要本机证书。 |
| 🛡️ 需要 TLS 指纹抗性 | `安装与重装` -> `TLS 指纹抗性 NaiveProxy` | 需要真实域名和可信证书，不是无域名 Reality 的替代品。 |
| 🧰 已有旧客户端或迁移需求 | `安装与重装` -> `传统 TLS 兼容安装` | 仅在明确需要 WS/TLS、VMess、Trojan 等旧形态时使用。 |
| 🔗 安装完成后拿订阅 | `订阅与用户` | 未初始化时可选择本机单独使用、这台作为主控或这台作为被控。 |

> [!TIP]
> **第一次使用：** 优先走上面的推荐路径。只有明确了解客户端、网络和运维目标时，再进入自定义协议组合、CDN 入口细调、多服务器同步或危险实验开关。

## 安装

### 交互式安装

```bash
wget -O /root/install.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

首次运行时，如果入口脚本检测到本地缺少 `shell/`、`documents/`、`assets/` 或模块 manifest 不匹配，会自动下载完整仓库归档并补齐模块。

怀疑本地模块仍是旧版本时，可以强制刷新模块：

```bash
wget -O /root/install.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/install.sh" && chmod 700 /root/install.sh && PADM_FORCE_SCRIPT_MODULE_REFRESH=1 /root/install.sh
```

安装后再次打开管理面板：

```bash
padm
```

### 非交互安装

查看脚本当前支持的参数和示例：

```bash
bash install.sh --help
```

推荐直连 Reality Vision：

```bash
bash install.sh --install-type custom --core xray --protocols 1 --entry-host node.example.com --reality-target www.ibm.com:443 --reality-server-name www.ibm.com --reuse-last no
```

推荐 CDN Reality XHTTP：

```bash
bash install.sh --install-type custom --core xray --protocols 2 --entry-host cdn.example.com --reality-target www.ibm.com:443 --reality-server-name www.ibm.com --reuse-last no
```

无域名 Reality：

```bash
bash install.sh --install-type reality --core xray --reality-target www.ibm.com:443 --reuse-last no --clean-acme no
```

NaiveProxy：

```bash
bash install.sh --install-type custom --core sing-box --protocols 5 --domain naive.example.com --port 443 --reuse-last no
```

多个协议可以逗号分隔，例如 `--protocols 1,2,21`。当前公开 ID 是唯一安装入口，旧版 `0..13/20` 编号已废弃；已有旧配置需要重新选择当前公开 ID 后重装或调整。

传统 TLS 兼容安装，Cloudflare DNS-01 可全程非交互：

```bash
bash install.sh --install-type install --core xray --domain example.com --port 443 --tls-ca letsencrypt --dns-api yes --dns-api-type cloudflare --dns-api-wildcard yes --cloudflare-api-token <token> --cloudflare-zone-id <zone_id> --reuse-last no
```

Cloudflare 建议使用限制到目标 Zone 的 API Token，至少具备 `Zone:DNS:Edit`。为避免 token 出现在命令历史中，也可以用环境变量：

```bash
PADM_CLOUDFLARE_API_TOKEN=<token> PADM_CLOUDFLARE_ZONE_ID=<zone_id> bash install.sh --install-type install --core xray --domain example.com --dns-api yes --dns-api-type cloudflare
```

已有节点只补装或刷新 HTTPS 订阅发布服务：

```bash
bash install.sh InstallSubscription --domain subscribe.example.com --subscribe-port 39778 --install-nginx yes
```

订阅发布独立管理自己的 TLS 域名和证书，不会自动使用 Reality entry 或传统 TLS 域名。已有匹配且可用的证书会直接复用；缺少证书时可继续传入上面的 `--tls-ca`、`--dns-api` 和服务商凭据参数完成签发。自定义证书可复用，但需自行续期。

## Docker 版

Docker 版用于把核心、Nginx、订阅和运维任务与宿主系统隔离。它和原生版是两条独立且互斥的入口：原生版使用 `install.sh` / `padm`，Docker 版使用 `install-docker.sh` / `padm-docker`；不会自动混装、迁移或接管另一种部署。

### 安装

Docker 入口会安装并校验 Docker 控制 bundle；缺少 Docker 时，`install` 会在明确确认后引导安装 Docker Engine 和 Compose v2。它不在生产机执行 `docker build`，也不会把 Xray、sing-box、Nginx 或其它业务依赖安装到宿主机。镜像由本仓库 CI 预构建并发布，首次部署需要再用配置规格生成 Compose 状态：

```bash
wget -O /root/install-docker.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/install-docker.sh" && chmod 700 /root/install-docker.sh && /root/install-docker.sh install

# 以 docker/configure.example.json 为字段模板，替换域名、密钥、UUID、token、
# release manifest 摘要和五个 CI 镜像的 tag@sha256 引用后再执行：
padm-docker configure --spec /root/padm-docker-config.json
padm-docker validate
padm-docker status
```

需要固定控制脚本版本时，把 `install` 改为 `install --ref <40 位 commit SHA>`；不要把 `latest` 当作生产版本锁。CI Release 同时提供 `release-manifest.json`、Cosign 签发的 Sigstore bundle v0.3（`release-manifest.sigstore.json`，签名内嵌）和 `padm-docker-bundle.tar.gz`，更新时会校验 bundle 签名和摘要。

示例文件中的 digest、密钥和 token 是占位值，不能直接用于生产。生产镜像引用必须使用 CI Release 提供的版本标签和 digest，例如 `ghcr.io/neil1123-vip/padm-xray:3.1.9@sha256:<digest>`；不要使用 `latest`，也不要在主机上手工改成未发布的 tag。

### 五个镜像

五个镜像都由仓库中的 Dockerfile 定义，当前统一以锁定的 Alpine 3.24.1 基础镜像构建；基础 digest、上游版本和架构校验值由 `versions.lock` 锁定，再由 CI 构建 `amd64/arm64` 多架构镜像。一个镜像可以被多个 Compose service 复用，但不同长期职责仍是独立容器。

| 镜像 | 职责 | 宿主集成 |
| --- | --- | --- |
| `padm-xray`（`xray`） | Xray-core、Geo 数据和核心配置校验。 | 普通 bridge 容器。 |
| `padm-sing-box`（`sing-box`） | sing-box、核心配置校验和对应协议运行时。 | 普通 bridge 容器。 |
| `padm-nginx`（`nginx`） | TLS、WebSocket、反向代理和静态入口。 | 只发布被选中的入口端口。 |
| `padm-ops`（`ops`） | ACME、订阅控制、Geo/同步等运维任务，按 Compose service 作为长期或一次性进程运行。 | 不持有 Docker Socket。 |
| `padm-net`（`net`） | WireGuard、Fail2ban、TUN/TProxy 和端口/防火墙集成工具。 | 仅在显式 `net-*` profile 下使用 `NET_ADMIN`、host network 或 `/dev/net/tun`。 |

`net` 的业务工具放在镜像中，但真正的 WireGuard、转发、TUN 和防火墙对象仍属于宿主内核；默认安装不启用这些高权限 profile。普通服务不使用 `privileged`、`SYS_ADMIN` 或 Docker Socket。

### 状态与日常控制

Docker 状态根固定为 `/etc/padm-docker`，原生状态根 `/etc/padm` 不会被 Docker 入口读取或覆盖。常用命令如下：

```bash
padm-docker status
padm-docker up
padm-docker down
padm-docker restart
padm-docker logs
padm-docker validate
```

证书和 ACME 任务也由同一个宿主控制命令分发到 `ops` 镜像：

```bash
padm-docker tls install --domain example.com --cert /path/fullchain.pem --key /path/privkey.pem
padm-docker acme <issue|renew> --domain example.com --email admin@example.com --dns <dns_provider> --credentials /path/credentials
```

配置变更先生成候选文件、校验端口和 Compose，再备份当前状态并执行健康检查；失败时保留旧配置。Docker 入口安装的控制命令是 `/usr/local/bin/padm-docker`，实际 bundle、配置、数据、密钥、日志和备份分别位于状态根下的 `bundle/`、`config/`、`data/`、`secrets/`、`logs/` 和 `backups/`。

### 更新

更新只接受已签名的 CI Release manifest。默认命令读取最新 Release 的 manifest、Cosign 签发的 Sigstore bundle v0.3 和控制 bundle；也可以显式指定本地或 HTTPS 资产：

```bash
padm-docker update
padm-docker update \
  --manifest <URL|文件> \
  --bundle <URL|文件> \
  [--control-bundle <URL|文件>]
```

更新事务依次验签 manifest、预拉取五个固定 digest 镜像、校验当前配置、保存 `backups/update.*` 快照、原子切换镜像引用并运行 Compose health check。拉取、校验、启动或健康检查任一步失败，都会恢复旧配置和旧镜像引用；生产机不会在线编译镜像。需要新版本时，先由 CI 根据新的锁文件构建并发布，再在生产机执行 `padm-docker update`。

### 回滚

```bash
padm-docker rollback
```

回滚只使用受管的最近一次 `update.*` 快照，默认退回一个版本；没有有效快照时直接失败，不猜测或拼接任意历史版本。回滚失败会尝试恢复当前版本，并保留备份路径供排障。

### 卸载

```bash
# 停止并移除 Docker 控制命令；保留配置、数据、备份和镜像
padm-docker uninstall

# 在保留状态根的前提下，仅删除 deployment 记录中五个精确 digest 镜像
padm-docker uninstall --remove-images

# 生成最后备份后删除 /etc/padm-docker（不可逆，必须显式确认）
padm-docker uninstall --purge --confirm PADM-DOCKER-PURGE
```

普通卸载只清理本项目的 Compose 容器、网络和 CLI 链接，不执行全局 `docker prune`，也不删除其它 Compose project 或用户卷；脚本自动安装的 Docker Engine、Compose 插件和软件源不会由 `padm-docker uninstall` 卸载。`--purge` 仅删除带有效 Docker 模式标记的受管状态根；需要保留数据时不要使用它。

## 系统要求

padm 面向 Linux 服务器运行。代码会识别 Debian、Ubuntu、RHEL/CentOS/AlmaLinux/Rocky/Oracle Linux、Fedora 和 Alpine，并按系统使用 `apt`、`yum` 或 `apk` 安装必要组件。

| 项目 | 要求 |
| --- | --- |
| 权限 | 需要 root 或等价权限。 |
| 架构 | `x86_64/amd64`、`aarch64/arm64`。 |
| 基础命令 | 入口下载至少需要 `curl` 或 `wget`；完整包刷新需要 `tar`。 |
| 常用依赖 | 脚本会按功能安装或使用 `jq`、`nginx`、`acme.sh`、WireGuard tools、Fail2ban 等组件。 |
| 服务管理 | 核心服务优先使用 systemd；Alpine/OpenRC 路径有专门处理。主控/被控订阅控制服务目前要求 systemd 和 `python3`。 |

### Docker 版要求

| 项目 | 要求 |
| --- | --- |
| 操作系统 | Linux；Docker daemon 必须运行 Linux 容器。Windows、macOS 和 Docker Desktop 不在首发支持范围。 |
| 权限与连接 | root，rootful Docker Engine，本机 rootful Unix socket；不支持 rootless daemon、远程 context 或用户级 socket。 |
| Compose | Docker Compose v2 插件。 |
| 架构 | `amd64` 或 `arm64`，主机和 daemon 架构必须一致。 |
| 主机命令 | `bash` 4+、`jq`、`sha256sum`、`tar`，以及 `curl` 或 `wget`；签名更新还需要支持 Sigstore bundle v0.3 的 `cosign`（CI 当前使用 3.x）。缺少 Docker 时，`install-docker.sh install` 会先询问是否从 Docker 官方软件源安装 Engine、Compose v2 及其宿主前置工具。 |
| 内核能力 | 普通 profile 不需要额外 capability；WireGuard、Fail2ban、TUN/TProxy 等 `net-*` profile 需要按支持矩阵提供 `NET_ADMIN`、host network 或 `/dev/net/tun`。 |

首次执行 `install-docker.sh install` 时，如果检测不到 `docker` 命令，脚本会询问是否从 Docker 官方软件源安装 Docker Engine 和 Compose v2；回答否、未确认或安装失败都会停止，且不会初始化 `/etc/padm-docker`。宿主软件包或软件源已经完成的变更不会由脚本擅自删除。仅在命令缺失时触发询问；已有 Docker 但 daemon 或 Compose 不可用时仍直接报错，不会重装。自动安装目前只覆盖 Debian、Ubuntu、CentOS、Fedora、RHEL 的 rootful systemd 主机；其它发行版请先手动安装 Docker。脚本不会安装 Xray、sing-box、Nginx 等业务宿主依赖，也不会执行 `docker build`。检测到原生版已安装、正在运行或残留状态时会拒绝安装，请先明确清理原生部署；两种模式不提供隐式迁移。

> [!IMPORTANT]
> **CentOS / RHEL：** SELinux 处于 Enforcing 时，脚本会提示先手动关闭后再继续。

## 主菜单

padm 主菜单按任务对象分组，一个功能只放在一个主要入口里：

| 菜单 | 负责什么 |
| --- | --- |
| 🚀 安装与重装 | 新手选择指引；推荐直连、推荐 CDN、无域名 Reality、NaiveProxy、自定义安装、传统 TLS 兼容安装。 |
| 🔗 订阅与用户 | 可本机单独使用，也可初始化主控/被控，再处理发布订阅、多服务器协同、流量限额、同步和备份恢复。 |
| 🧭 协议与入口 | REALITY、XHTTP、Hysteria2、Tuic、入口端口和 CDN 入口地址。 |
| 🔐 站点与证书 | 传统 TLS fallback 站点、302 重定向、ALPN 诊断/修复和本机 TLS 证书。 |
| 🧱 路由与访问控制 | WARP、IPv6、Socks5、DNS/hosts、BT 阻断、域名/IP 阻断、直连例外和区域阻断。 |
| ⚙️ 核心与服务 | Xray-core / sing-box 生命周期、服务运行态、日志诊断和 Xray Geo 数据；首页只读本地状态。 |
| 🧰 系统与脚本 | 更新 padm、查看脚本安装状态、Fail2ban 防护、网络优化 / BBR。 |
| ⚠️ 高级/危险操作 | 卸载脚本和 VLESS Encryption 实验等高风险开关。 |

## 运行模型

padm 不是单个超长 Bash 文件，而是“独立入口 + 分模块运行时”：

1. 原生入口是 `install.sh`，Docker 入口是 `install-docker.sh`；两者分别维护 `/etc/padm` 和 `/etc/padm-docker`，不会互相迁移或混装。
2. 模块刷新会原子替换 `shell/`、`documents/`、`assets/`、`README.md` 和 `.padm-module-manifest`；失败时尽量恢复旧模块。
3. `shell/core/bootstrap.sh` 是运行时装配点，按顺序加载平台、运行时、协议、Reality、服务、路由、TLS、订阅、菜单等模块。
4. 交互菜单和正式子命令共用同一套模块。正式子命令包括 `RenewTLS`、`UpdateGeo`、`SyncSubscriptionGroups`、`SubscriptionControl`、`InstallSubscription`。
5. Docker 控制 bundle 位于 `docker/`，由宿主上的 `padm-docker` 直接调用 Docker CLI 和 Compose；容器不挂载 Docker Socket。
6. 排障时先找实际控制点：入口脚本、模块加载顺序、状态文件、生成配置和校验命令，而不是只看菜单文案。

| 路径 | 作用 |
| --- | --- |
| `install.sh` | 🚪 仓库入口；负责自刷新、参数解析、正式子命令分发和首次模块补齐。 |
| `install-docker.sh` | 🐳 Docker 独立入口；安装并刷新 Docker 控制 bundle，不构建镜像。 |
| `padm-docker` | 🎛️ 安装后的 Docker 宿主控制命令；调用固定的 `padm-docker` Compose project。 |
| `docker/` | 📦 Dockerfile、Compose、manifest、配置合同和生命周期实现。 |
| `shell/core/` | ⚙️ 平台检测、运行时 helper、协议模板、Reality/TLS/路由/服务/菜单等核心逻辑。 |
| `shell/subscription/` | 🔗 订阅发布、订阅组状态、用户账号、WireGuard 控制面、远程同步和流量统计。 |
| `shell/regression/` | 🧪 `framework/` 提供环境、runner 和 registry，`cases/` 单次加载 fixture、stub 与测试函数，`suites/` 只注册 selector、分组和组合。 |
| `shell/subscription_groups_regression.sh` | 🧪 唯一公开回归分发入口；统一分发 suite、aggregate、contract 和 composition selector。 |
| `shell/validate_install.sh` | ✅ 安装后的只读验收脚本。 |
| `documents/` | 📚 示例配置和英文 README。 |
| `assets/` | 🖼️ 传统 TLS fallback 静态站点模板。 |

## 安装后的控制点

这些路径是 padm 真正读写和校验的状态源。排障、备份、迁移或读代码时优先看它们：

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
| `/etc/padm/reality_targets_results.tsv` | 📊 Reality 目标站统一实测结果表。 |

Docker 部署的实际状态源：

| 路径 | 作用 |
| --- | --- |
| `/etc/padm-docker/mode` | 🏷️ 固定为 `docker` 的模式标记，用于互斥和卸载保护。 |
| `/etc/padm-docker/bundle` | 🔗 当前已验证控制 bundle 的原子指针。 |
| `/etc/padm-docker/deployment.json` | 🧾 当前版本、profiles、端口和五个镜像 digest。 |
| `/etc/padm-docker/compose.json`、`images.env` | 🐳 当前 Compose 配置和固定镜像引用。 |
| `/etc/padm-docker/config/`、`data/`、`secrets/`、`backups/` | 💾 配置、运行数据、密钥和更新/卸载备份。 |

公网订阅和服务器间控制面是两套地址体系：

- 🌍 客户端订阅走 `/s/default/...`、`/s/clashMeta/...`、`/s/sing-box...` 等 HTTPS 路径。
- 🔒 主控/被控控制接口走 `/s/control/...`，只通过 WireGuard 内网访问，不提供公网 HTTP/HTTPS 来源回退。

## 协议选择

常规推荐按目标选协议，而不是按“看起来功能更多”选协议：

| 目标 | 推荐协议 | 说明 |
| --- | --- | --- |
| 新手直连、有域名或普通自用 | `1` VLESS Reality Vision | 当前主线推荐；不依赖本机伪装站点。 |
| CDN / 反代 | `2` VLESS Reality XHTTP | 新建 CDN 节点优先；使用 XHTTP 与 XMUX。本项目只用 Xray 生成 XHTTP，sing-box 当前没有 XHTTP transport。 |
| 没有域名 | 无域名 Reality | 菜单会走 Reality 快速路径。 |
| TLS 指纹抗性 | `5` NaiveProxy | 需要真实域名和证书；依赖 sing-box。 |
| UDP、移动网络、弱网 | `3` Hysteria2 | Hysteria2 节点流量不套 CDN/Nginx；需要 UDP 可达，可按需使用端口跳跃。 |
| 明确需要 AnyTLS | `4` AnyTLS | sing-box AnyTLS 场景；确认客户端支持后再用。 |
| 兼容或迁移 | 高级协议 `21..31` | 仅在旧客户端、存量 CDN、传统 TLS 或迁移窗口需要时选择。 |

能力库是协议选择、核心支持、Nginx 拓扑和订阅输出的统一事实源。`category=node` 的公开 ID 才能传给 `--protocols`；旧版公开编号已废弃，不再作为 CLI、菜单或订阅同步输入。

### 推荐公网节点能力

| ID | 能力 | 项目生成核心 | Nginx 模式 | UDP | CDN | 推荐场景 |
| --- | --- | --- | --- | --- | --- | --- |
| `1` | VLESS Reality Vision | Xray / sing-box | `none` | 否 | 否 | 新手直连、有域名或无域名 Reality 首选。 |
| `2` | VLESS Reality XHTTP | Xray | `none` | 否 | 条件支持 | 新建 CDN / 反代首选；XHTTP 在本项目中是 Xray-only。 |
| `3` | Hysteria2 | sing-box | `none` | 是 | 否 | 移动网络、UDP、弱网和端口跳跃场景；节点流量不经过 CDN/Nginx。 |
| `4` | AnyTLS | sing-box | `none` | 否 | 否 | 明确需要 sing-box AnyTLS 且客户端支持时选择。 |
| `5` | NaiveProxy | sing-box | `none` | 否 | 否 | 明确需要 TLS 指纹抗性且有真实域名和可信证书时选择。 |

### 高级公网节点能力

gRPC、WebSocket 和 HTTPUpgrade 是高级协议，不是删除协议。它们仍可显式选择，但新建节点优先使用推荐能力，特别是直连 Reality Vision 或 CDN/反代 Reality XHTTP。

| ID | 能力 | 项目生成核心 | Nginx 模式 | 使用边界 |
| --- | --- | --- | --- | --- |
| `21` | VLESS WS TLS | Xray | `http_front` | WebSocket 属高级兼容方案；新建 CDN 优先选 `2`。 |
| `22` | VMess WS TLS | Xray | `http_front` | VMess 与 WS 均为高级兼容方案；新建优先选 `1` 或 `2`。 |
| `23` | VMess HTTPUpgrade TLS | Xray / sing-box | `http_front` | HTTPUpgrade 属高级兼容方案；新建 CDN 优先选 `2`。 |
| `24` | VLESS gRPC TLS | Xray | `grpc_front` | gRPC 有主动探测与 fallback 限制；新建优先选 `2`。 |
| `25` | Trojan gRPC TLS | Xray | `grpc_front` | 仅在明确需要 Trojan + gRPC 时使用；可考虑 `4` 或 `2`。 |
| `26` | VLESS Reality gRPC | Xray / sing-box | `none` | Reality gRPC 是高级直连方案；新建优先选 `1` 或 `2`。 |
| `27` | VLESS TCP TLS Vision | Xray | `fallback_backend` | 传统 TLS/fallback 迁移路径；新建直连优先选 `1`。 |
| `28` | Trojan TCP TLS direct | Xray / sing-box | `none` | 传统 TLS 协议，仅在旧客户端或明确需求下选择。 |
| `29` | Trojan TCP TLS fallback | Xray | `fallback_backend` | fallback 只适用于 TCP+TLS；新建优先考虑 `4` 或 `1`。 |
| `30` | Shadowsocks | sing-box | `none` | 高级兼容项，不作为默认公网节点推荐。 |
| `31` | TUIC | sing-box | `none` | UDP/弱网高级项；新装优先引导使用 `3`。 |

### 内部服务端能力

内部能力只进入路由、中继、透明代理、访问控制或管理菜单，不能作为公网节点安装输入：`201` Socks 中继、`202` HTTP 中继、`203` WireGuard、`204` TUN、`205` Redirect/TProxy、`206` DNS/Direct/Block、`207` Tunnel/dokodemo-door。

### 上游已知但本项目暂不生成的能力

`301..309` 仅用于 `--list-capabilities` 和文档说明，不生成安装入口，包括 Xray Hysteria2 inbound、Hysteria v1、ShadowTLS、mKCP 组合、Cloudflared inbound、Selector、URLTest、Tor outbound、SSH outbound，以及纯 transport/security 说明项。

### Nginx 拓扑

| `nginx_mode` | 含义 | 适用能力 |
| --- | --- | --- |
| `none` | 核心直接监听公网；节点流量不安装、不启动 Nginx。 | Reality Vision、Reality XHTTP、Hysteria2、AnyTLS、NaiveProxy、Reality gRPC、Trojan direct、Shadowsocks、TUIC。 |
| `http_front` | Nginx HTTP/1.1 反代，显式处理 `Upgrade` / `Connection`。 | WS / HTTPUpgrade 能力 `21..23`。 |
| `grpc_front` | Nginx HTTP/2 + `grpc_pass` 反代。 | gRPC TLS 能力 `24..25`。 |
| `xhttp_front` | 预留给显式 XHTTP TLS/CDN/反代能力；默认不套到 Reality XHTTP。 | 当前无默认公网节点使用。 |
| `fallback_backend` | Xray fallback 后端，只允许 TCP+TLS 能力使用。 | `27`、`29`。 |
| `acme_only` | Nginx 可服务证书申请或订阅发布，不代表节点流量经过 Nginx。 | 证书与订阅服务。 |

sing-box 订阅输出中的 `utls.fingerprint=chrome` 是客户端兼容/模拟选项，不是抗封锁保证。需要抗 TLS 指纹识别时，优先考虑 Reality Vision、Reality XHTTP 或 NaiveProxy。

## Reality 语义

Reality 里有三个容易混淆的概念：

| 概念 | 含义 | 出现位置 |
| --- | --- | --- |
| 📍 entry | 客户端实际连接到你的服务器的地址 | 订阅链接 `@host`、Clash `server`、sing-box `server` |
| 🎭 Reality target | Reality 伪装访问的外部真实 HTTPS 站点 | Xray `realitySettings.target`；sing-box `tls.reality.handshake` |
| 🧾 Reality SNI | Reality 握手使用的 SNI | Xray `serverNames`；sing-box `tls.server_name`；订阅 `sni/servername` |

常见配置是：客户端连接 `node.example.com`，Reality target 使用 `www.ibm.com:443`，Reality SNI 使用 `www.ibm.com`。

Reality Vision、Reality XHTTP 和 Reality gRPC 均不申请本机 TLS 证书；纯 Reality 安装不创建或清理站点，不操作 ACME/Cron，也不停止、启动或重载 Nginx。`--reality-domain yes` 是严格域名模式，只允许单选 Reality Vision `1`，并校验 entry 域名及 DNS；协议 `2`、`26` 或任何多选组合会在安装依赖和写配置前拒绝。

Reality entry 按 `--entry-host`、`--domain`、`/etc/padm/reality_entry_host`、`currentHost`、公网 IP 的顺序选择。普通单选 Reality 端口按显式 `--port`、历史端口、`443` 的顺序选择；多协议继续使用各自端口，不把顶层 `--port` 注入 Reality 子端口。启用 443 共存后，客户端仍连接记录的公网端口，核心继续复用已记录的内部端口。

未传 `--reality-target` 时，脚本会进入目标站选择器。自动选择优先使用已有 A/B 实测结果；没有结果时实测内置候选并选择可用目标；仍无可用结果时回退 `www.ibm.com:443`。Reality 目标站检测结果写入 `/etc/padm/reality_targets_results.tsv`，评分包括 TLS 1.3、`X25519MLKEM768`、证书链长度、网络匹配、CDN 风险和检测时间。

`协议与入口` -> `REALITY 管理` 可查看当前目标、运行 `xray tls ping`、刷新目标库、运行 RealiTLScanner、切换实测结果、查看 PQC/ML-DSA-65 状态和配置 443 共存分流。

> [!WARNING]
> **扫描风险：** RealiTLScanner 是高级功能，云端扫描可能导致 VPS 被标记；脚本会在执行前提示确认。

## XHTTP 与 CDN

安装 `2. VLESS Reality XHTTP` 后，在 `协议与入口` -> `XHTTP 管理` 调整协议参数：

| 层级 | 内容 |
| --- | --- |
| ✅ 普通设置 | 查看当前配置、选择场景预设、切换 `auto` / `packet-up` / `stream-up`。 |
| 🧪 高级设置 | 调整 XMUX、path/host、header、packet、stream 参数。 |
| ⚠️ 实验功能 | 配置或关闭上下行分离 `downloadSettings`。 |

默认推荐值面向日常和 CDN：`mode=auto`，`xmux.maxConcurrency=16-32`，`hMaxRequestTimes=600-900`，`hMaxReusableSecs=1800-3000`。每次修改都会先写临时配置并执行 Xray 校验，失败会自动回滚并提示日志路径。

XHTTP 在本项目中由 Xray 生成；sing-box 当前没有 XHTTP transport，因此不会输出 sing-box XHTTP 客户端配置。

`协议与入口` -> `CDN 入口管理` 只负责订阅里的客户端入口地址覆盖，例如 CDN CNAME、优选 IP 或多个入口地址。XHTTP 的 mode、XMUX、path/host 等协议参数仍在 `XHTTP 管理` 中调整。

## 传统 TLS 与本机站点

`站点与证书` -> `传统 TLS fallback 维护` 只服务于传统 TLS/fallback 协议。当流量没有命中代理协议时，Nginx fallback 可以展示本机静态页面或 302 跳转。

这个入口提供：

- 🖼️ 20 个轻量静态站点模板，并在安装或更换时随机化标题、文案、按钮、卡片和主题色。
- ↪️ 302 重定向维护。
- 🔎 ALPN 诊断/修复，检查 Xray fallback、`fallbacks[].alpn=h2` 和 Nginx h2 fallback 是否匹配。
- ✅ 写入后执行 `xray -test -confdir /etc/padm/xray/conf`，失败自动回滚。

Reality Vision、Reality gRPC 和 Reality XHTTP 不依赖本机静态站点。Reality 的伪装由外部 target 和 SNI 完成。只有你继续使用 VLESS TCP TLS Vision、WS TLS、gRPC TLS、Trojan TLS 等传统 TLS/fallback 协议，或确实要在本机展示网站时，才需要维护这个入口。

## 订阅与用户

订阅系统按服务器角色组织；本机和主控首页只保留 `订阅与用户`、`订阅同步` 以及角色对应的协同/控制入口，低频维护动作放在对应菜单内。

| 状态 | 菜单形态 | 适合做什么 |
| --- | --- | --- |
| 🟡 未初始化 | `本机单独使用` / `这台作为主控` / `这台作为被控` | 单机可直接管理本机订阅；需要多服务器时再选择主控或被控。 |
| 🟢 主控 | 主控首页提供订阅与用户、订阅同步、协同与控制 | 统一查看本机自用与分享订阅，创建分享订阅、添加被控服务器、执行同步和限额治理。 |
| 🔵 被控 | 被控首页直接提供接入、状态、凭据和控制面动作 | 粘贴主控邀请、提供本机节点给主控、查看 WireGuard 与同步状态。 |

主控和本机模式首页都直接提供统一的 `订阅同步` 菜单：立即完整同步、开启/关闭自动同步、设置间隔、状态与排障、状态备份与恢复。自动同步开关同时控制配置变更后的即时同步和 cron；关闭后仍可随时手动完整同步。

首页的 `订阅与用户` 统一处理链接刷新、分享订阅创建/维护和流量限额。管理员自用订阅仍由本机协议配置自动维护，不写入 `user_groups`、不参与额度治理，也不会通过主控同步下发；统一的是管理入口和发布流程。

- 主控会同步所有已启用的被控服务器源，不再另设全局“远程同步”开关；暂停单台服务器请在 `协同与控制` -> `管理被控服务器` -> `启用/停用被控服务器` 中操作。
- 完整同步只有在本机和所有已启用来源都成功返回完整快照后才发布公网订阅。任一来源失败时保留上一版完整订阅，不会用部分节点覆盖客户端结果。
- 修改任一被控的 Reality 目标等节点配置后，自动同步开启时会重新生成本机节点、拉取全部启用来源并发布完整组；外层 HTTPS 订阅地址不变，其他服务器节点仍会保留。
- 被控服务器不提供主动同步菜单，只响应主控的认证同步请求。

本机或主控创建分享订阅推荐流程：

1. 在本机或主控首页进入 `订阅与用户` -> `发布与链接`，安装或更新公网订阅服务。
2. 在同一菜单进入 `分享订阅` -> `新建分享订阅`，使用英文、数字或短横线 ID，例如 `team-a`。
3. 按向导选择可用服务器源和流量上限。
4. 自动同步开启时，保存后立即执行一次完整同步；关闭时可稍后从 `订阅同步` 手动执行。托管账号 `sub_<ID>` 会写入核心配置。
5. 完整同步完成后，在 `订阅与用户` -> `发布与链接` -> `刷新并查看订阅链接` 复制用户订阅链接。

多服务器协同推荐流程：

1. 主控服务器从本机订阅首页进入 `启用主控协同` 完成初始化，再进入 `协同与控制` -> `管理被控服务器` -> `创建被控邀请`，输入一次被控别名。主控会自动预留 WireGuard 地址。
2. 被控服务器进入 `接入主控`，粘贴邀请即可完成初始化和主控 Peer 导入；无需填写地址。成功后复制一次接入回执。
3. 回到主控服务器，从主控首页进入 `协同与控制` -> `管理被控服务器` -> `完成被控接入`，粘贴回执即可按预留别名完成 Peer、服务器源和控制 Token 写入，并自动检查本次来源的健康状态。
4. 需要暂时排除某台被控时，使用 `启用/停用被控服务器`；停用会保留 Peer、Token 和历史状态，下一次完整同步从公网订阅移除该来源节点。
5. 待完成邀请可按别名查看或取消；邀请和回执都是 bearer secret，列表、普通状态和健康结果不会显示完整秘密。丢失邀请时应取消并重建。
6. 旧版 `main` / `controlled` 凭据仅保留在明确命名的维护入口，用于更新已有连接；首次接入只接受邀请/回执。包含长期控制 Token 的回执或旧版被控凭据只通过可信通道传递。
7. WireGuard 使用 UDP，控制 API 只在隧道内使用 HTTP，不需要 TLS 证书；客户端订阅继续单独使用公网 HTTPS。

`订阅同步` -> `状态备份与恢复` 只作用于 `/etc/padm/subscribe_groups/groups.json`。恢复备份或重建状态前会先要求输入 `yes`，确认后才创建当前状态备份；当前结构为精确的 `version: 6` 单组根对象，不再持久化 `groups[]`、`active_group` 或流量汇总字段，并按 Xray / sing-box 核心分别保存流量基线。首次读取旧 `version: 2`、`3`、`4`、`5` 状态时会原子迁移；其中 v5 聚合基线先保存为兼容基线，并在首次新格式采集后替换为按核心基线。旧文件会备份到对应的 `groups-pre-v3-migration-*`、`groups-pre-v4-migration-*`、`groups-pre-v5-migration-*` 或 `groups-pre-v6-migration-*`；多组、其他旧版结构以及含额外、缺失或无效字段的状态会被拒绝。

## 路由与访问控制

`路由与访问控制` 负责服务端出站和访问策略，不是客户端配置教程。

| 功能 | 说明 |
| --- | --- |
| 🧭 分流工具 | WARP WireGuard 出站、IPv6 出站、Socks5 中继、DNS 分流、DNS/hosts 覆盖。 |
| ⛔ BT 下载管理 | 通过协议嗅探阻断已识别的 bittorrent 流量；加密、混淆或部分 uTP 场景无法保证完全覆盖。 |
| 🧱 访问控制 | 域名/IP 阻断、直连例外、区域阻断。 |

Xray 访问控制使用 routing + blackhole/direct；sing-box 使用 remote rule_set、domain_suffix/domain 和 ip_cidr。直连例外会放在阻断规则之前，适合系统更新、证书签发或必须直连的客户端服务。区域阻断属于危险操作，可能影响系统更新、证书申请和应用连接。

> [!NOTE]
> **安全写入：** 修改访问控制前会快照相关规则文件；写入后会执行 Xray 和 sing-box 校验，失败自动回滚并提示日志路径。

## 核心与服务

`核心与服务` 首页只读取本地版本、配置、服务和 Xray Geo 状态，不执行配置检查或访问网络。即使尚未安装核心，也可以进入页面查看状态和执行不依赖本机二进制的只读扫描；远端版本只在明确升级、回退或试跑预发布版时获取。

首页固定为 6 个入口：

1. Xray-core 生命周期
2. sing-box 生命周期
3. 服务运行态
4. 日志与诊断
5. Xray Geo 数据
6. 返回主菜单

`安装与重装` 只在主菜单提供；不再有独立的“配置健康与兼容”页面。两个核心生命周期页使用相同顺序，并统一提供“检查当前配置”“扫描升级风险”“试跑预发布版”。结果显示为“通过”“需关注”“失败”或“无法检查”。前两项只读且不联网；预发布版试跑不会替换二进制或操作服务。

Xray 的“检查当前配置”内部依次执行运行检查和严格检查：运行检查失败显示“失败”，仅严格阶段未通过显示“需关注”。sing-box 会先合并分片配置，再执行 `sing-box check -c /etc/padm/sing-box/conf/config.json`。技术阶段和日志路径只在结果详情中显示。

升级或回退核心时，脚本先下载目标版本到临时目录，用目标二进制校验当前配置；校验通过后才替换 `/etc/padm/xray/xray` 或 `/etc/padm/sing-box/sing-box` 并重启服务。若新核心启动失败，会尝试恢复旧二进制。

Nginx 只在当前协议、站点或订阅配置确实依赖它时可启动、停止、重启或平滑 reload；已安装但不属于 padm 当前依赖的 Nginx 只读。Nginx 配置仍由协议、站点和订阅入口管理，服务页只负责状态与动作。Xray `geosite.dat` / `geoip.dat` 的更新、状态和定时任务统一位于 `Xray Geo 数据`。

## 系统与脚本

`系统与脚本` 负责 padm 自身和宿主机辅助项：

- 🔄 更新 padm 脚本；若订阅控制服务已启用或正在运行，会同步刷新并重启。刷新失败不会回滚脚本更新，界面会提示从控制面维护入口重试。
- 🧾 查看入口校验、版本、ref 和 manifest。
- 🛡️ 管理 Fail2ban 防护，包含 SSH 和 `/s/control/` 的基础防护入口。
- 🚀 查看或启用网络优化 / BBR。

网络优化推荐项只启用当前内核提供的官方 `bbr`，并写入 padm 自己管理的 `/etc/sysctl.d/99-padm-bbr.conf`：

```conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

关闭时只删除 padm 自己写入的 sysctl 文件，并尝试恢复启用前的拥塞控制和 qdisc，不会改动用户其它 sysctl 文件。

## 高级实验

`高级/危险操作` -> `VLESS Encryption 实验` 可为 Xray Reality 节点启用实验加密。脚本调用 `xray vlessenc` 生成参数：

- 🧭 Reality Vision：`VLESS Encryption + XTLS Vision`
- 🌐 Reality XHTTP：`VLESS Encryption + XTLS Vision + XHTTP XMUX`

> [!CAUTION]
> **兼容性提醒：** default VLESS 分享链接和 Mihomo（原 Clash.Meta）订阅会携带 experimental encryption 字段；需 Mihomo v1.19.13+。sing-box 上游尚不支持该字段，因此 sing-box 订阅仍会省略。该功能属于高级实验，不建议新手默认开启。

## 参数参考

| 参数 | 可选值 | 默认/行为 | 说明 |
| --- | --- | --- | --- |
| `--install-type` | `install`、`custom`、`reality` | 无自动参数时进入交互菜单；传其它安装参数但不传本参数时默认 `custom` | 安装类型。 |
| `--core` | `xray`、`sing-box`、`1`、`2` | `xray` | `1` 等同 `xray`，`2` 等同 `sing-box`。 |
| `--protocols` | 当前公开协议编号，逗号分隔 | 无固定默认 | 自定义安装协议，例如 `1` 或 `1,2,21`；旧版 `0..13/20` 编号已废弃。 |
| `--list-protocols` | 无 | 输出后退出 | 列出可安装的公网节点能力。 |
| `--list-capabilities` | 无 | 输出后退出 | 列出公网节点、内部能力和上游已知能力。 |
| `--show-risky-protocols` | 无 | 输出后退出 | 列出带风险提示的高级公网节点能力。 |
| `--domain` | 域名 | TLS 安装时必须提供或交互输入 | TLS 证书域名；也是 Reality entry 的第二优先级，但 Reality 不为其申请证书。 |
| `--entry-host` | 域名或 IP | 优先于 `--domain`、历史 entry、`currentHost` 和公网 IP | Reality 客户端实际连接地址。 |
| `--reality-target` | `host[:port]` | 未传时进入目标站选择器；兜底 `www.ibm.com:443` | Reality 伪装目标站。 |
| `--reality-server-name` | SNI 域名 | 默认等于 target host | Reality SNI。 |
| `--port` | 端口号 | TLS 默认 `443`；单选 Reality 为显式端口 > 历史端口 > `443` | TLS 入口端口或单选 Reality 客户端连接端口；多协议不注入 Reality 子端口。 |
| `--tls-ca` | `letsencrypt`、`zerossl`、`buypass` | `letsencrypt` | 证书 CA。 |
| `--dns-api` | `yes`、`no`、`y`、`n` | `no` | 是否使用 DNS API 申请证书。 |
| `--dns-api-type` | `cloudflare`、`aliyun`、`1`、`2` | `cloudflare` | DNS API 服务商。 |
| `--dns-api-wildcard` | `yes`、`no`、`y`、`n` | `no` | 是否申请 `*.根域名` 通配符证书。 |
| `--cloudflare-api-token` | token | 也可用 `PADM_CLOUDFLARE_API_TOKEN` | Cloudflare DNS API Token。 |
| `--cloudflare-zone-id` | zone id | 可选，也可用 `PADM_CLOUDFLARE_ZONE_ID` | 设置 `CF_Zone_ID`，减少 Zone 查询依赖。 |
| `--aliyun-api-key` | key | 也可用 `PADM_ALIYUN_API_KEY` | 阿里云 AccessKey ID。 |
| `--aliyun-api-secret` | secret | 也可用 `PADM_ALIYUN_API_SECRET` | 阿里云 AccessKey Secret。 |
| `--reuse-last` | `yes`、`no`、`y`、`n` | `no` | 是否复用上次安装配置。 |
| `--clean-acme` | `yes`、`no`、`y`、`n` | `no` | 清空上次配置时是否同时清理 acme。 |
| `--reality-domain` | `yes`、`no`、`y`、`n` | `no` | 严格域名模式，仅支持单选 Reality Vision `1`；优先用 `--entry-host`，其次 `--domain`。 |
| `--subscribe-port` | 端口号 | 无固定默认 | 订阅发布服务端口。 |
| `--install-nginx` | `yes`、`no`、`y`、`n` | `no` | 订阅或反代需要 Nginx 时是否自动安装。 |
| `--uuid` | UUID | 随机生成 | 初始用户 UUID。 |
| `--user` | 用户名 | 随机生成 | 初始用户名。 |

完整参数以 `bash install.sh --help` 为准。

## 验收与回归

安装后只读验收：

```bash
bash shell/validate_install.sh [domain]
```

检查公网 HTTP/HTTPS/TLS 可达性：

```bash
bash shell/validate_install.sh --online example.com
```

回归统一通过 selector dispatcher 运行，按三个层级使用：

| 层级 | 命令 | 用途 |
| --- | --- | --- |
| 快速反馈 | `bash shell/subscription_groups_regression.sh fast` | 日常小改后的代表性检查；完整 fast 集合用 `fast-full`。 |
| 主产品回归 | `bash shell/subscription_groups_regression.sh all` | 较大改动的主验证集；按资源预算编排核心产品 suite，但不是所有公开 selector 的并集。 |
| 按需专项 | `bash shell/subscription_groups_regression.sh <selector>` | 按改动范围补跑协议、深层回滚或 harness 行为检查。 |

`all` 在同一资源预算内并行运行 `subscription`、`ui`、`transaction-core-main`、`transaction-system`、`routing`、`runtime`、`remote-control-smoke`、远程控制服务安装契约和远程控制响应契约。完整 `transaction-core`、`fast-full`、`protocol-capabilities`、`remote-control-deep` 和 harness 契约按改动范围追加。

常用产品专项：

```bash
bash shell/subscription_groups_regression.sh protocol-capabilities
bash shell/subscription_groups_regression.sh platform-hot
bash shell/subscription_groups_regression.sh platform-smoke
bash shell/subscription_groups_regression.sh fast-full
bash shell/subscription_groups_regression.sh subscription-output
bash shell/subscription_groups_regression.sh transaction-core
bash shell/subscription_groups_regression.sh core-safety-rollback
bash shell/subscription_groups_regression.sh routing-safety
bash shell/subscription_groups_regression.sh subscription-safety
bash shell/subscription_groups_regression.sh transaction-system
bash shell/subscription_groups_regression.sh remote-control-smoke
bash shell/subscription_groups_regression.sh remote-control-contract
bash shell/subscription_groups_regression.sh remote-control-deep
bash shell/subscription_groups_regression.sh subscription-state
bash shell/subscription_groups_regression.sh ui-full-core
bash shell/subscription_groups_regression.sh ui-full-core-maintenance
```

harness 专项：

```bash
bash shell/subscription_groups_regression.sh regression-dispatcher-contract
bash shell/subscription_groups_regression.sh regression-case-loader-contract
bash shell/subscription_groups_regression.sh framework-parallel-selector-list-with-jobs
bash shell/subscription_groups_regression.sh targeted-batch-helpers
```

需要压并发或保守跑重型 suite 时，优先用 `PADM_REGRESSION_PARALLEL_JOBS`、`PADM_REGRESSION_CHILD_PARALLEL_JOBS`，以及按 suite 开启 `PADM_REGRESSION_*_RESOURCE_PROFILE=all`。`shell/regression/protocol_capabilities.sh` 仅作为保留原成功标记的兼容转发入口。

主入口按 `framework/`、`cases/load.sh`、`suites/` 的固定顺序装配回归；case 只加载一次，不再保留历史 source-only 分组层。

## 许可证

本项目根据 [AGPL-3.0 许可证](LICENSE) 授权。
