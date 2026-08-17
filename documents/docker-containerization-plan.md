# Docker 容器化实施计划

## 目标

在同一个仓库中同时维护原生脚本版和 Docker 版：

- 原生版完整保留现有行为和兼容性。
- Docker 版通过独立入口部署，尽可能将运行服务隔离到容器。
- 镜像由 CI 预构建，生产机不执行 `docker build`。
- 使用固定版本和 digest，支持更新、健康检查和回滚。
- `padm-docker` 控制脚本留在宿主机，不向容器暴露 Docker Socket。

## 固定边界

| 项目 | 原生版 | Docker 版 |
| --- | --- | --- |
| 入口 | `install.sh` | `install-docker.sh` |
| 命令 | `padm` | `padm-docker` |
| 状态根目录 | `/etc/padm` | `/etc/padm-docker` |
| 服务管理 | systemd/OpenRC | Docker Compose |
| 核心升级 | 替换本机二进制 | 替换镜像 digest |
| 验收脚本 | `shell/validate_install.sh` | `docker/validate.sh` |
| 运行关系 | 与 Docker 版二选一 | 与原生版二选一 |

检测到另一种部署正在运行、已安装但未清理，或占用所需端口时，安装程序必须拒绝继续。普通安装不自动混装或切换模式。

互斥检查必须区分三种状态：`installed`（部署文件和状态仍存在）、`active`（服务或容器正在运行）和 `port-conflict`（目标监听端口被其他进程占用）。不能用单一目录存在性或一次端口扫描代替这三种判断。

Docker 版首个正式版本只支持 Linux 上的 rootful Docker Engine、Compose v2 和 `amd64/arm64`；不把 rootless、Windows/macOS 主机或没有 Docker daemon 权限的环境列为隐含支持。版本、架构、daemon 可用性和 Compose 能力必须在安装前一次性检查并给出可操作错误。

已安装后的最小命令契约为：`status`、`up`、`down`、`restart`、`logs`、`update`、`rollback`、`validate` 和 `uninstall`。每个命令必须可重复执行、返回稳定的非零错误码，并通过部署锁避免并发修改。

## 仓库结构

```text
install.sh                         # 现有原生版
install-docker.sh                  # Docker 版独立入口
shell/                             # 现有原生代码及可复用业务逻辑
docker/
├─ compose.yaml
├─ lib/
│  ├─ bootstrap.sh                 # 环境、锁和目录初始化
│  ├─ manifest.sh                  # 发布清单读取与校验
│  ├─ lifecycle.sh                 # install/update/rollback/uninstall
│  └─ services.sh                  # Compose 服务操作
├─ images/
│  ├─ xray/Dockerfile
│  ├─ sing-box/Dockerfile
│  ├─ nginx/Dockerfile
│  ├─ ops/Dockerfile
│  └─ net/Dockerfile
├─ tests/smoke.sh
└─ validate.sh
docker-bake.hcl
versions.lock
.github/workflows/build-images.yml
```

不提前重组整个 `shell/`。只有协议定义、配置生成或状态逻辑出现第二个真实调用方时，才提取为共享模块。

## 共享与分离

两种模式共享：

- 协议能力库。
- 配置模板和配置数据格式。
- 配置写入、校验、备份和回滚逻辑。
- 订阅状态格式和数据校验。
- 参数校验和版本规则。

两种模式分别实现：

- 核心安装和升级。
- 服务启动、停止、重启和日志。
- Nginx 管理。
- ACME 和定时任务。
- Fail2ban、WireGuard、TUN/TProxy。
- 原生包管理与 Docker Compose 操作。

不把所有原生函数强行改造成万能运行时适配器。当前直接调用 systemd、Nginx 和核心二进制的代码，应在 Docker 版中使用独立部署模块；只有稳定且确实通用的逻辑才复用。

## 镜像与容器

| 镜像 | 容器用途 | 权限边界 |
| --- | --- | --- |
| `xray` | Xray 数据面和配置校验 | 非 root、只读根文件系统 |
| `sing-box` | sing-box 数据面和配置校验 | 非 root、只读根文件系统 |
| `nginx` | TLS 入口、反代、订阅发布 | 仅挂载配置、证书和日志 |
| `ops` | ACME、订阅控制、定时任务、一次性工具 | 按角色启动多个容器 |
| `net` | Fail2ban、WireGuard、TUN/TProxy | 仅授予必要的内核权限 |

`ops` 和 `net` 是镜像复用，不是进程合并。不同职责使用独立容器、独立重启策略和独立日志。

每个镜像必须有明确的构建和运行契约：固定 base digest、上游版本 label、架构清单、非交互 entrypoint、健康检查命令、运行用户和可写路径。构建上下文只允许来自仓库中的 Docker 定义和公开锁定依赖，不得包含运行时配置、证书、私钥、manifest 或宿主目录。

`ops` 允许包含 Python、JSON、ACME 和订阅控制所需工具，但每个用途仍以独立 Compose service 启动，不能在一个容器内引入 supervisor 来合并多个长期进程。`net` 的普通变体不默认启用特权；需要 `NET_ADMIN`、host network 或 `/dev/net/tun` 的服务必须在 Compose profile 中显式声明。

默认使用 bridge 网络。WireGuard、TUN/TProxy 和 Fail2ban 需要宿主内核能力时，使用独立 profile、明确的 capability 和设备挂载。普通协议服务不得默认获得这些权限。

所有服务容器不得挂载 Docker Socket。宿主机上的 `padm-docker` 直接调用 Docker CLI 控制 Compose。

## Docker 版部署契约

### 状态目录

Docker 版只管理 `/etc/padm-docker`，不读取或覆盖 `/etc/padm` 中的原生配置：

```text
/etc/padm-docker/
├─ mode                         # 固定值 docker，互斥判断标记
├─ bundle/                      # 当前控制脚本、Compose 模板和 schema
├─ deployment.json             # 当前已提交的部署状态
├─ deployment.previous.json    # 最近一次可回滚状态
├─ images.env                  # 由 manifest 生成的 digest 引用
├─ config/                     # Xray、sing-box、Nginx 生成配置
├─ data/                       # 订阅状态、ACME 状态和持久业务数据
├─ secrets/                    # 证书私钥、DNS API 凭据、WireGuard 密钥
├─ logs/                       # 任务日志；容器 stdout/stderr 仍由 Docker 管理
├─ backups/                    # 配置和状态快照
└─ locks/                      # 部署与定时任务锁
```

`bundle/` 和 `images.env` 是可替换部署输入，`config/`、`data/`、`secrets/` 是持久数据。目录默认由 root 创建；普通配置为 `0750/0640`，密钥目录和文件为 `0700/0600`。容器通过固定 UID/GID 获得最小读写权限，禁止为了省事使用 `0777`。

### Desired state 与 Compose 生成

`deployment.json` 是 Docker 部署的唯一 desired state，至少记录：

- schema、padm 版本、manifest 摘要和控制 bundle 版本。
- Compose project name、启用的 profile、核心类型和协议 ID。
- 每个监听器的公网端口、容器端口、TCP/UDP、IPv4/IPv6 和所属服务。
- 镜像 index digest、当前配置格式版本、数据格式版本和前一版本引用。
- 宿主集成项及其拥有的防火墙规则、设备和定时任务。

安装、更新和重配必须先生成候选 `deployment.json`，完成 schema、端口冲突、协议能力和 profile 权限校验后，再生成候选 Compose 配置。`docker compose config` 通过后才允许替换当前状态；不得同时维护一套会与实际协议端口脱节的手写 Compose 真源。

Compose project name 固定为 `padm-docker`，所有容器、网络和一次性任务都带 `io.padm.mode=docker`、`io.padm.project=padm-docker` 和 release label。卸载只处理 label 与状态记录同时匹配的资源。

### 网络模型

- 普通 Xray、sing-box 和 Nginx 使用专用 bridge 网络及显式端口映射。
- `nginx_mode=http_front/grpc_front/fallback_backend` 时，只由 Nginx 或 fallback 入口发布公网端口，后端核心仅监听内部网络地址。
- `nginx_mode=none` 时，核心服务按协议直接发布 TCP 或 UDP 端口；Hysteria2、TUIC 等 UDP 能力不能被误配为 TCP。
- IPv4/IPv6 是否发布由 desired state 明确记录；不能因为 Docker daemon 默认设置而隐式改变可达性。
- 端口跳跃、WireGuard、TUN/TProxy 和需要宿主防火墙的 Fail2ban 使用独立 `net-*` profile。只有这些 profile 可以声明 `network_mode: host`、`NET_ADMIN` 或 `/dev/net/tun`，且不得使用 `privileged: true`。
- 必须用真实外部连接验证客户端源地址是否保留；Fail2ban 未看到真实地址时禁止启用封禁动作。

端口预检同时覆盖 desired state 内部冲突、宿主 TCP/UDP 监听、Docker 已发布端口和本项目已拥有的规则。特殊 profile 修改宿主防火墙前必须记录规则所有权，并使用与原生版同等级的事务回滚。

### 数据、权限与备份边界

配置、订阅状态、ACME 账户和 WireGuard 控制面状态使用宿主 bind mount，避免容器删除时丢失；临时文件、缓存和一次性构建产物使用容器临时目录。私钥、DNS API token、邀请 secret 和 WireGuard 密钥只从 `secrets/` 或受限环境文件读取，不写入镜像、Compose、manifest 或普通日志。

备份由 `padm-docker` 生成带 schema、版本、时间、文件清单和 SHA-256 的归档，至少包含 `config/`、`data/`、`secrets/` 和 `deployment.json`；不默认包含 stdout 日志、镜像层和缓存。恢复先在临时目录校验归档、路径和格式，再停止相关服务、生成当前状态备份并原子替换。恢复失败必须保留原状态，不允许把任意归档路径解压到状态根目录之外。

### 功能支持矩阵

Docker 版维护一份按协议/功能生成的支持矩阵，状态只允许 `supported`、`host-integrated`、`deferred` 或 `unsupported`，并记录所需 profile、端口类型、核心和配置格式版本。首发至少覆盖 Xray、sing-box、普通 Nginx 入口、TLS/ACME、订阅发布和基础路由；Fail2ban、WireGuard、端口跳跃、TUN/TProxy 归入显式 `host-integrated` profile。矩阵由能力库和 Compose contract test 共同校验，未支持项在安装前明确报错，不能偷偷调用原生安装器。

### Nginx、TLS 与定时任务

Nginx 是独立入口容器，证书和站点配置通过只读/读写分离挂载提供。ACME 优先使用 Nginx webroot 或 DNS-01；使用 standalone challenge 时必须先检查 80/443 归属、短暂停机范围和回滚动作。续期流程为“签发到临时目录 → 校验证书/私钥匹配和域名 → 原子替换 → reload Nginx/相关核心 → 健康检查”，失败保留旧证书。

`ops` 镜像按命令拆成 ACME、订阅控制、Geo 更新和同步等一次性 Compose service；长期订阅控制单独运行。宿主 systemd timer（无 systemd 时才使用受控 cron）调用 `padm-docker task`，由宿主控制脚本直接启动一次性容器，不给任何容器 Docker Socket。每项任务使用独立锁、超时和最近一次结果，不能由多个调度器重复执行。

### 宿主内核能力

Fail2ban、WireGuard、端口跳跃和 TUN/TProxy 的业务工具放在 `net` 或对应核心镜像中，但内核对象仍属于宿主。特殊 service 必须显式声明 `NET_ADMIN`、所需设备和 host network，并在启动前检查内核模块、iptables/nft、转发和 IPv4/IPv6 设置；默认安装不启用这些 profile。禁止 `SYS_ADMIN`、`privileged` 和宽泛宿主目录挂载，除非某项能力经过单独的安全评审并成为新的明确版本边界。

### 可复现构建与发布顺序

`versions.lock` 固定每个镜像的 base index digest、上游版本、源码/归档 SHA-256、系统包快照和补丁摘要；Dockerfile 不执行无锁的 `latest`、在线脚本安装或构建时下载运行时配置。Buildx 为 `amd64/arm64` 生成同一 tag 的多架构 index，输出 digest、SBOM 和 provenance；“可复现”定义为输入锁定、构建步骤固定、产物 digest 可验证，不虚假承诺不同时间必然得到相同 digest。

现有 Release 工作流先解析版本，再在本次运行内完成镜像构建、smoke 和签名；所有检查通过后才推送版本 bump commit、镜像和 Release manifest。工作流使用 concurrency 和 release-commit guard，重复运行同一版本只补齐缺失资产，不重复创建 Release；不依赖创建 Release 后触发另一个 `push` 工作流。

### 发布信任与 manifest

固定 digest 只保证内容未变化，不证明发布者身份。`install-docker.sh` 内置受信任的 Cosign 验证镜像 digest、Fulcio issuer 和本仓库 Release workflow identity；下载 `release-manifest.json` 与 Sigstore bundle 后先验证签名身份，再读取任何 URL、bundle hash 或镜像 digest。离线安装可传入本地 manifest、签名 bundle 和镜像归档，但不提供跳过生产验签的隐式开关。

`release-manifest.json` 至少包含以下版本化字段，未知 schema 或缺少必填字段时拒绝安装：

| 字段 | 用途 |
| --- | --- |
| `schema_version` | Release manifest 结构版本。 |
| `release.version/commit/created_at` | padm 版本、唯一源码提交和发布时间。 |
| `control.bundle_url/sha256/min_version` | Docker 控制 bundle 的来源、完整性和最低控制脚本版本。 |
| `images.<name>.index_digest/platforms` | 5 个镜像的多架构 index 及平台 digest。 |
| `formats.compose/config/data` | Compose、生成配置和持久数据格式版本。 |
| `compatibility.host/profiles` | 支持的主机条件、架构和功能矩阵版本。 |
| `migrations` | 本版本需要的迁移 ID、方向和可回滚属性。 |

签名验证成功后，还要校验 release commit、请求版本、当前架构、bundle SHA-256 和每个镜像 digest 的一致性。`deployment.json` 保存已验证 manifest 的 SHA-256 与签名身份，便于状态和回滚审计。

### 更新、迁移与回滚事务

更新在全局部署锁内分为 `prepare` 和 `commit`：

1. 验证签名 manifest、兼容范围、磁盘空间和当前状态 schema。
2. 下载候选 bundle，预拉取 5 个候选 digest，仅为启用的服务生成 Compose。
3. 用候选镜像校验当前配置，并在临时副本上执行声明的向前迁移。
4. 备份当前 deployment、images.env、配置和将被迁移的数据，写入候选状态。
5. 切换 Compose，等待容器 health 和外部协议探针全部通过。
6. 原子提交 deployment；失败则恢复旧状态、旧数据快照和旧 digest 后再次验活。

自动回滚只允许跨可逆迁移。包含不可逆数据迁移的版本必须先生成可恢复备份并要求显式确认；一旦提交，不允许自动用旧镜像读取新格式数据。默认保留当前版和上一版的 bundle/state，`rollback` 只退一版，避免维护任意历史迁移图。

### 卸载与清理

普通 `uninstall` 停止并删除 `padm-docker` label 匹配的容器、一次性任务、项目网络、宿主调度项和 CLI 链接，撤销本项目记录的防火墙/接口状态，但保留 `/etc/padm-docker`、备份和镜像，便于恢复。任何宿主规则撤销失败都使卸载返回非零并保留诊断状态。

`uninstall --purge` 在成功停止服务并生成最后备份后，要求输入明确确认词，随后只删除带有效 `mode` 标记且解析后等于 `/etc/padm-docker` 的状态根。镜像删除是单独的 `--remove-images` 选择，只处理 manifest 记录的精确 digest；不执行全局 prune，也不删除其他 Compose project 或用户卷。

### 运行状态与可观测性

长期服务使用 `unless-stopped`，一次性任务不设自动重启。所有镜像提供进程级和配置/端口级 healthcheck；`padm-docker status` 汇总 release、manifest 摘要、启用 profile、容器状态、健康结果、端口归属、定时任务最近结果和待处理回滚，不把“容器 running”当作服务健康。

Docker 日志使用受限大小和文件数的轮转配置；应用文件日志只保留确实被 Fail2ban、审计或故障分析消费的部分。输出统一过滤 token、私钥、邀请和 DNS API secret。默认设置只读根文件系统、tmpfs、`no-new-privileges`、合理的 `pids_limit` 和 `nofile`；内存/CPU 硬限制作为显式配置，因为服务器规格和启用协议差异过大。首版不引入 Prometheus、日志收集栈或 Web 面板。

## 分阶段实施

### 阶段 0：契约与基线

状态：已完成（2026-08-17）。实现范围和验证结果见
[Docker 容器化阶段 0 基线](docker-phase0-baseline.md)。

冻结两个入口、命令名、状态目录、配置目录、`deployment.json` 字段和互斥规则。

记录原生版当前行为，运行现有 `fast-full`、`all` 和受影响专项回归，作为后续基线。

在原生安装入口增加 Docker 活跃检测，但不改变原生安装、升级和卸载流程。

为原生和 Docker 分别写入可验证的模式标记；对没有新标记的旧原生安装，使用 `/etc/padm/install.sh`、`.padm-ref`、服务单元和运行进程进行兼容识别。Docker 安装前先检查原生 `installed` 状态，再检查实际目标端口；原生安装也必须反向检查有效的 Docker `deployment.json` 和 Compose 项目。发现残留但无法判定归属时采取 fail-closed，要求显式清理或迁移。

验收：原生回归结果与改动前一致；两个入口不会写入对方的状态目录。

### 阶段 1：Docker 控制骨架

实现 `install-docker.sh` 和 Docker 专用模块：

- 检查 Docker Engine、Compose、Bash、下载工具和 JSON 工具。
- 检查 rootful daemon 权限、Compose v2、主机架构和 Linux 内核能力；Docker 版不自动安装 Docker 或修改宿主软件源。
- 创建 `/etc/padm-docker` 及其权限。
- 初始化部署锁、状态文件、日志目录和数据目录。
- 为 `install-docker.sh`、`docker/` 和所需共享模块维护独立的 bundle manifest 与原子刷新流程；不能依赖原生入口当前只覆盖 `shell/`、`documents/`、`assets/` 的自刷新。
- 提供安装、状态、启动、停止、重启、日志和卸载操作。
- 不执行 `docker build`，只接受预构建镜像引用。

验收：空白 Docker 主机可以完成目录初始化；原生版不受影响；重复执行不会破坏已有状态。

### 阶段 2：镜像与 Compose

制作 5 个镜像，所有基础镜像、上游版本和补丁写入 `versions.lock`。

每个 Dockerfile 必须能在隔离构建上下文中单独重建，并通过同一套 label、架构和 smoke 契约；不得把 `ops` 或 `net` 的工具隐式复制进核心镜像。

Compose 使用 profile 控制 Xray、sing-box、Nginx、订阅、ACME 和网络组件。配置和数据使用宿主 bind mount，容器根文件系统尽量只读。

镜像引用统一由 `.env` 或等价部署文件提供：

```dotenv
PADM_XRAY_IMAGE=ghcr.io/example/padm-xray@sha256:...
PADM_SINGBOX_IMAGE=ghcr.io/example/padm-sing-box@sha256:...
PADM_NGINX_IMAGE=ghcr.io/example/padm-nginx@sha256:...
PADM_OPS_IMAGE=ghcr.io/example/padm-ops@sha256:...
PADM_NET_IMAGE=ghcr.io/example/padm-net@sha256:...
```

验收：`docker compose config` 在所有 profile 下通过；5 个镜像分别完成版本、启动和最小健康检查。

### 阶段 3：核心、Nginx、TLS 和订阅

先接入 Xray 和 sing-box 的协议配置、配置校验、启动和健康检查，再接入 Nginx、TLS、ACME、订阅发布与订阅控制服务。

配置写入必须保持临时文件、校验、备份和回滚顺序。Docker 模式暂未支持的功能必须明确报错或隐藏，不能静默回退到宿主机安装。

验收：至少覆盖核心安装、常用协议、Nginx 反代、证书申请、订阅生成、重启恢复和配置失败回滚。

### 阶段 4：宿主内核集成

分别接入 WireGuard、Fail2ban、TUN/TProxy 和其他透明代理能力。

每项能力单独启用 profile，并记录所需端口、设备、网络模式和 capability。Fail2ban 必须验证日志路径、宿主防火墙链和真实客户端地址；WireGuard 必须验证密钥、接口和重启恢复。

验收：普通 Docker 安装不获得特权；启用特殊网络能力时有明确的前置检查和失败提示。

### 阶段 5：CI 构建与发布

新增可复用的 `build-images.yml`，由现有 Release 工作流直接调用，不依赖 `GITHUB_TOKEN` 创建 Release 后再触发另一个工作流。

CI 流程：

1. 读取 `versions.lock` 和脚本版本。
2. 使用 Buildx 构建 `amd64/arm64`。
3. 对每个镜像执行 smoke test。
4. 推送 GHCR 或指定 Registry。
5. 生成 SBOM、provenance、签名和 digest manifest。
6. 所有镜像成功后才创建正式 Release。

需要增加 `packages: write`；使用 keyless 签名时增加 `id-token: write`。生成的 `release-manifest.json` 作为 Release 附件，不回提交到 `main`。

manifest 至少包含：schema 版本、padm 版本、Git commit、5 个镜像 digest、上游版本、配置格式版本和最低控制脚本版本。

### 阶段 6：更新、回滚和卸载

Docker 更新固定为：

```text
下载并验证 manifest
→ 预拉取候选镜像
→ 用候选镜像验证当前配置
→ 保存当前 deployment.json 和 images.env
→ 原子替换镜像引用
→ compose up
→ 健康检查
```

任一步失败，恢复旧 manifest 和旧 `images.env`，再次启动旧版本。更新不使用 `latest`，也不在生产机编译镜像。

普通卸载删除容器、网络和控制脚本，但保留配置、证书和订阅数据；`--purge` 才删除 `/etc/padm-docker`，并要求再次确认。

## CI 与验证

Pull Request 阶段至少执行：

- Bash 语法检查。
- 现有原生回归测试。
- Docker Compose 配置检查。
- Docker 版脚本的 stub/contract 测试。
- 单架构镜像构建和 smoke test。

Release 阶段增加：

- 双架构镜像构建。
- 镜像 digest、SBOM、provenance 和签名校验。
- 干净 Linux 主机上的 Docker 安装、重启、升级、回滚和卸载。
- Xray、sing-box、Nginx、TLS、订阅和网络 profile 的专项验收。

## 完成标准

- 原生版现有命令、目录和回归结果不被破坏。
- Docker 版不安装宿主 Xray、sing-box、Nginx、Fail2ban 或 WireGuard 服务。
- 所有生产镜像均来自 CI，并按固定 digest 部署。
- 宿主机重启后容器、订阅任务和证书任务可恢复。
- 配置校验失败会阻止发布，更新失败可自动回滚。
- 普通容器无 Docker Socket 和多余 capability。
- `amd64` 和 `arm64` 完成安装、更新、回滚和卸载验收。

## 20 轮审计修订

### 第 1 轮：自刷新与发布包闭环

审计证据：`install.sh` 的 `modulePaths` 和 `refreshScriptModules` 当前只枚举、复制和校验 `shell/`、`documents/`、`assets/`、`README.md`；README 也明确将这些目录定义为现有模块包。

计划修订：Docker 入口必须拥有独立的 bundle manifest、ref、锁和原子替换流程，范围至少包括 `install-docker.sh`、`docker/`、选定的共享模块及 Docker 文档。Release 资产必须携带完整 Docker bundle，原生入口刷新不得隐式负责 Docker 文件。

核验标准：在临时安装目录中模拟缺文件、manifest hash 不匹配、下载中断和替换失败，旧 Docker bundle 均应保持可启动；原生模块刷新测试仍只验证原生范围。

### 第 2 轮：双模式互斥与状态判定

审计证据：原生安装状态分散在 `/etc/padm`、`.padm-ref`、systemd/OpenRC 服务、定时任务和监听端口；当前没有统一的 mode marker。Docker 计划只写了“检测另一种部署”，没有定义判定优先级。

计划修订：区分 `installed`、`active`、`port-conflict`；新增原生/Docker 模式标记、旧安装兼容探测、反向检查和 fail-closed 规则。模式切换只能走显式迁移或清理流程。

核验标准：覆盖原生已安装但停止、原生运行中、Docker 容器异常退出、旧目录残留、无关端口占用和并发安装六种场景，结果不得误删或误放行。

### 第 3 轮：主机前置条件与命令契约

审计证据：原生 `checkSystem` 会按发行版选择包管理器并修改系统；`checkRoot` 只验证 root 和原生配置目录；README 只列出入口下载依赖，没有 Docker daemon、Compose、架构和 rootless 边界。原计划的 Docker 前置检查和命令列表仍不够可执行。

计划修订：Docker 首发支持范围固定为 Linux、rootful Docker Engine、Compose v2、`amd64/arm64`；不自动安装 Docker 或改软件源。固定 `status/up/down/restart/logs/update/rollback/validate/uninstall` 命令、稳定错误码和部署锁，所有命令必须幂等。

核验标准：分别模拟 daemon 不可用、无权限、Compose 版本不符、架构不符、非 Linux、重复命令和并发执行，脚本必须在写入任何状态前失败并给出明确原因。

### 第 4 轮：镜像职责与运行契约

审计证据：当前原生依赖由 `adapters.sh`、订阅控制、Fail2ban 和 WireGuard 模块分别安装；订阅控制明确依赖 Python/systemd，Fail2ban 需要宿主防火墙和 Nginx 日志，不能直接等价地塞入一个普通容器。

计划修订：为 5 个镜像增加固定 base digest、上游 label、架构清单、entrypoint、健康检查、用户和可写路径契约。`ops` 和 `net` 只复用镜像，不合并长期进程；核心镜像不得携带运维工具；特权仅在 Compose profile 中声明。

核验标准：每个 Dockerfile 可独立重建；构建上下文不含密钥和运行数据；启动、健康检查、非 root/特权例外和工具边界均由自动检查验证。

### 第 5 轮：Compose 网络、端口与地址模型

审计证据：协议能力库同时包含 TCP、UDP、mixed transport 和多种 `nginx_mode`；`protocol_runtime.sh` 会为 Hysteria2/TUIC 创建 UDP 端口跳跃和 DNAT；`nginx.sh` 还处理 Reality 443 共存、内部端口及 IPv4/IPv6 监听。静态 Compose 不能可靠表达这些运行时组合。

计划修订：以候选 `deployment.json` 作为端口和 profile 真源，再生成 Compose。普通服务使用 bridge 和显式发布，Nginx 模式只发布入口端口；端口跳跃、WireGuard、TUN/TProxy、Fail2ban 使用显式 `net-*` profile。固定 project name/labels，并记录端口、协议、地址族和规则所有权。

核验标准：覆盖直连 TCP、直连 UDP、Nginx 反代、Reality 443 共存、双栈、端口跳跃和端口冲突；外部探针必须确认协议可达且 Fail2ban 能取得真实客户端地址。

### 第 6 轮：持久化、权限与备份边界

审计证据：现有状态分布在核心配置、TLS、订阅、订阅组、WireGuard 和防火墙状态中；当前订阅备份只覆盖 `groups.json`，不能代表整机 Docker 部署备份。私钥和控制面 secret 还需要比普通配置更严格的权限。

计划修订：固定 `bundle/config/data/secrets/logs/backups/locks` 的职责、UID/GID 和文件模式；持久数据全部 bind mount。新增带 schema、清单和 hash 的整机备份/恢复事务，排除日志、缓存和镜像层，恢复前验证路径并自动备份当前状态。

核验标准：容器重建和普通卸载后数据仍在；非授权 UID 不能读密钥；损坏、越界或版本不兼容的归档在停服务前被拒绝；恢复中断不会覆盖当前可用状态。

### 第 7 轮：共享代码与功能支持矩阵

审计证据：`protocols.sh` 已是协议、核心、Nginx 和订阅能力事实源，但 `services.sh`、`adapters.sh`、`tls.sh` 等模块直接调用 systemd、包管理器或宿主路径。直接 source 整套原生 bootstrap 会把宿主副作用带进 Docker 模式。

计划修订：只共享纯能力数据、校验器、模板和原子文件 helper；Docker 服务生命周期和依赖安装独立实现。维护 `supported/host-integrated/deferred/unsupported` 矩阵，安装入口和文档从同一矩阵生成，未支持功能 fail-closed。

核验标准：矩阵中的每个 `supported` 项都有 Compose contract 和端到端用例；`deferred/unsupported` 在改动宿主或生成配置前失败；共享模块测试证明没有 systemd、包管理器或 `/etc/padm` 副作用。

### 第 8 轮：Nginx、TLS、ACME 与续期事务

审计证据：`tls.sh` 同时支持 DNS API 和 standalone 签发，证书写入 `/etc/padm/tls` 并通过 cron 续期；`nginxRuntimeReasons` 表明 Nginx 可能同时服务传统入口、Reality 共存、订阅和 WireGuard 控制面。端口与 reload 所有权不能含糊。

计划修订：Nginx 独占被选中的入口端口；ACME 优先 webroot/DNS-01，standalone 必须显式做端口和停机事务。证书续期在临时目录完成配对、域名和有效期校验，原子替换后再 reload，并在失败时保留旧证书。

核验标准：覆盖首次签发、DNS-01、webroot、standalone 冲突、续期成功、坏证书、reload 失败和重启恢复；任何失败都不能留下半套证书或让健康入口长期中断。

### 第 9 轮：订阅控制与定时任务职责

审计证据：`install.sh` 当前分发 `RenewTLS`、`UpdateGeo`、`SyncSubscriptionGroups`、`SubscriptionControl`、`InstallSubscription` 等 cron 命令；订阅控制服务依赖 Python 和 systemd。若把调度和 Docker 控制都放进容器，就会重新引入 Docker Socket。

计划修订：`ops` 镜像以不同 command 复用为一次性任务，长期订阅控制保持独立 service；宿主 timer/cron 只调用 `padm-docker task`，由宿主 CLI 执行 Compose。每项任务有锁、超时、退出码、日志轮转和 last-result 状态。

核验标准：重复触发只运行一个实例；宿主重启后调度恢复；任务失败可见且不阻塞其他服务；检查所有容器均无 Docker Socket，关闭任务会同步删除对应宿主调度项。

### 第 10 轮：Fail2ban、WireGuard、TUN/TProxy 权限模型

审计证据：`fail2ban.sh` 依赖宿主 SSH/Nginx 日志、服务状态和防火墙；WireGuard 控制面写入 `/etc/wireguard/wg-padm.conf`；透明代理和端口跳跃直接操作 TUN、转发及 iptables/firewalld。普通 bridge 容器无法安全等价替代这些宿主行为。

计划修订：功能代码尽量放入容器，内核操作仅通过 `host-integrated` profile 授予精确的 `NET_ADMIN`、host network 和 `/dev/net/tun`。不授予 `privileged`/`SYS_ADMIN`，不在容器内自动加载内核模块；每条宿主规则必须记录所有权并支持事务撤销。

核验标准：默认 profile 的 capability 集为空；特殊 profile 缺前置条件时无副作用失败；启停、更新、回滚和卸载只修改本项目拥有的接口/规则；Fail2ban 必须通过真实源地址封禁测试。

### 第 11 轮：版本锁、多架构与可复现构建

审计证据：仓库当前没有 Dockerfile 或镜像锁文件；原生适配器会在运行机下载/安装依赖，这一模式不适用于 CI 预构建镜像。只锁应用 tag 仍会被 base image、架构归档和系统包漂移破坏。

计划修订：`versions.lock` 同时锁 base digest、上游版本、每架构 checksum、系统包快照和补丁；`docker-bake.hcl` 是 5 镜像的统一构建入口。CI 输出多架构 index digest、平台 digest、SBOM 和 provenance，生产只使用 index digest。

核验标准：缺锁、checksum 不符、Dockerfile 未消费锁值或发现 `latest` 时构建失败；`amd64/arm64` 分别完成版本检查、启动和配置校验；相同锁文件可重建出可追溯的等价输入集合。

### 第 12 轮：现有 Release 自动 bump/push 的发布顺序

审计证据：`.github/workflows/create_release.yml` 目前在 `main` push 上计算版本，必要时直接 commit/push 版本文件，然后创建 Release；它没有镜像构建门禁，bump commit 还会再次触发工作流。

计划修订：加入 workflow concurrency、release-commit guard 和可复用镜像 job；先完成候选构建/smoke，再发布版本提交、镜像、签名和 manifest，最后创建 Release。所有发布步骤按版本幂等，失败重跑可补齐而不会制造第二个版本。

核验标准：模拟构建失败、推镜像失败、签名失败、Release API 失败和重复触发；正式 Release 只能引用同一 release commit 的 5 个已签名 digest，失败状态不得被 `latest` 或不完整 manifest 消费。

### 第 13 轮：签名、manifest 验证与信任引导

审计证据：原生入口通过 HTTPS 下载归档并检查本地模块 SHA-256 manifest，但没有发布者签名或透明日志信任；Docker 版若只接受 digest，无法区分可信发布和恶意重标记。

计划修订：CI 对镜像和 `release-manifest.json` 生成 Cosign keyless 签名及 Sigstore bundle；Docker 入口内置验证镜像 digest、issuer 和 workflow identity，先验证签名身份，再消费 manifest 中的 URL/digest。离线输入也必须验签。

核验标准：篡改 manifest、签名、identity、bundle hash、镜像 digest 或版本提交均拒绝；验证器本身只使用入口内置的固定 digest，不从未验证 manifest 获取信任根。

### 第 14 轮：manifest schema、兼容性与原子部署状态

审计证据：订阅组状态已经对 `version`、字段集合和额外字段做严格校验；原生模块 manifest 是定长 hash 列表。Docker 计划此前只列出少量 manifest 字段，没有 schema 版本和部署状态兼容规则。

计划修订：定义 `release-manifest.json`、`deployment.json` 和 bundle manifest 的 schema/version、必填字段、未知字段策略、格式版本及迁移声明；已验证 manifest 摘要和签名身份写入 deployment 状态，状态文件原子替换。

核验标准：缺字段、额外字段、错误类型、旧/未来 schema、架构不匹配和 manifest/Compose 不一致均在停服务前失败；崩溃恢复只能看到旧或完整的新状态。

### 第 15 轮：更新、健康检查、失败回滚与状态迁移

审计证据：原生模块和配置操作大量使用临时文件、备份目录和恢复函数，但 Docker 版还没有候选状态、镜像预拉取、配置验证、健康探针和迁移边界。

计划修订：在全局锁内执行 prepare/commit；预拉取并校验候选镜像和配置，健康检查同时覆盖进程、配置、端口和外部协议；只允许可逆迁移自动回滚，默认保留当前/上一版状态。

核验标准：逐步注入下载、拉取、配置校验、启动、探针、迁移和提交失败，旧容器和旧状态可恢复；不可逆迁移没有显式备份/确认时拒绝。

### 第 16 轮：卸载、purge、备份恢复与数据保留

审计证据：原生卸载会停止服务、清理定时任务、回收防火墙/控制面并保留部分 ACME 数据；订阅和路由卸载各自带备份/回滚，不能直接套一个 `docker compose down`。

计划修订：普通卸载只清理 label 匹配的容器、网络、调度项和本项目拥有的宿主规则，保留状态/备份/镜像；`--purge` 单独确认并只删除安全解析到 `/etc/padm-docker` 的路径；镜像删除单独按 digest 选择。

核验标准：卸载中断返回非零且保留诊断；其他 Compose project、宿主服务和用户卷不受影响；备份可在全新 Docker 主机上校验、恢复并重新启动。

### 第 17 轮：PR、Release、E2E 测试矩阵与覆盖证据

审计证据：仓库已有 `fast`、`all`、transaction、subscription、routing、remote-control 等 Bash 回归和只读 `validate_install.sh`，但没有 Docker 构建、Compose profile、双架构和更新回滚门禁。

计划修订：PR 做 Bash/contract、所有 profile 的 Compose config、单架构构建和 smoke；Release 在干净 rootful Linux 上做安装、重启、升级、回滚、卸载和协议矩阵，在真实内核环境单独测试 host-integrated profile。每个矩阵项上传日志、manifest、digest 和失败状态。

核验标准：原生回归结果与基线一致；PR 不能合并未通过 contract；Release 只有双架构、签名、E2E 和安全边界全部通过才创建；测试明确证明无 Docker Socket、无宿主软件安装和无多余 capability。

### 第 18 轮：README、唯一入口说明与中英文文档

审计证据：当前 README 和英文 README 都把 `install.sh` 描述为唯一入口，并详细说明原生依赖、systemd/OpenRC 和 `/etc/padm`；这与 Docker 版独立入口、Linux/Compose v2 限制和双模式互斥不一致。

计划修订：保留原生 `install.sh` 文档，同时新增 `install-docker.sh`、`padm-docker` 命令、Docker 系统要求、5 镜像/host-integrated profile、数据目录、更新/回滚/卸载和支持矩阵。中文/英文入口页保持同一契约，Release 附件列出 bundle manifest、签名、SBOM 和 provenance。

核验标准：从 README 的两条安装路径分别能落到正确入口；文档不再宣称全仓库只有一个入口；示例端口、版本、架构和权限要求与脚本 contract 自动检查一致。

### 第 19 轮：日志、健康状态、资源限制与可观测性

审计证据：原生核心、Nginx、ACME 和 cron 各自写文件日志，`validate_install.sh` 以服务和端口状态为主；Docker 若只检查容器 `running`，无法区分配置失败、端口错误和任务失败。

计划修订：统一 Compose 日志轮转和敏感值过滤；每个长期服务提供进程/配置/端口 healthcheck，状态命令汇总 release、profile、端口、任务和回滚信息。默认只读根、tmpfs、`no-new-privileges`、pids/nofile 限制；不引入额外监控栈。

核验标准：故意制造配置坏、端口冲突、任务超时、容器重启和资源耗尽，`status`/`validate` 返回稳定结果，日志不泄露 secret，轮转后仍保留最近故障证据。

### 第 20 轮：最终一致性、范围收敛与维护成本

审计证据：前 19 轮已固定双入口、同仓库、CI 预构建、5 个镜像、宿主控制脚本、显式 host-integrated profile、无 Docker Socket 和可回滚状态；现有仓库仍是脚本/模块结构，没有要求引入第二套编排平台或数据库。

最终修订：保持 5 个镜像作为最小可维护集合：Xray、sing-box、Nginx、ops、net。Xray 与 sing-box 不合并是因为核心、配置校验和发布节奏独立；Nginx 单独隔离入口；`ops` 与 `net` 不合并是为了不把 ACME/订阅 secret 带进可改宿主网络的高权限容器。一个镜像可由多个 Compose service 复用，但不在单容器中运行多个长期进程。

宿主只保留 `install-docker.sh`/`padm-docker`、Docker CLI、调度入口和确需宿主内核的能力；原生 `install.sh` 不改为共享入口，也不自动迁移或混装。首版明确不做 Kubernetes/Swarm、Web 管理面、数据库、消息队列、Docker Socket、rootless、Windows/macOS 主机和任意历史迁移图。

核验标准：检查计划、目录树、Compose service、CI 产物和文档中的镜像名/入口/状态路径一致；每个新增组件都有真实调用点和测试门禁；普通安装不获得宿主软件安装或多余权限；双模式互斥、更新回滚、备份恢复和卸载路径均能闭环。若某项能力不能满足这些标准，标记为 `deferred` 或 `host-integrated`，不以额外镜像掩盖边界。
