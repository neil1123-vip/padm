# Docker 容器化计划审计记录

目标：对 `documents/docker-containerization-plan.md` 进行 20 轮独立审计；每轮记录证据、缺口、计划修订和核验标准。

审计范围：当前仓库源码、README、CI 配置和计划文档。审计只修改计划文档及本记录，不修改业务代码或 CI。

实施状态：阶段 0 已于 2026-08-17 完成，验证记录见
[Docker 容器化阶段 0 基线](docker-phase0-baseline.md)。

## 第 1 轮：自刷新与发布包闭环

- 证据：`install.sh` 的 `modulePaths`、`refreshScriptModules` 和 `writeModuleManifest` 当前只覆盖 `shell/`、`documents/`、`assets/`、`README.md` 及原生 manifest/ref。
- 缺口：原计划新增 `docker/` 和 `install-docker.sh`，但没有定义它们如何随已安装 Docker 版更新。
- 修订：增加独立 Docker bundle manifest、ref、锁和原子刷新流程；Release 资产必须包含完整 Docker bundle。
- 核验：模拟 Docker bundle 缺失、hash 错误、下载中断和替换失败时，旧 bundle 必须保持可用。

## 第 2 轮：双模式互斥与状态判定

- 证据：原生安装状态分散在 `/etc/padm`、`.padm-ref`、systemd/OpenRC 服务、定时任务和监听端口；当前没有统一的 mode marker。Docker 计划只写了“检测另一种部署”，没有定义判定优先级。
- 缺口：目录存在可能只是残留；服务停止也不代表可以安全并装；一次 `ss` 扫描不能说明端口归属。
- 修订：区分 `installed`、`active`、`port-conflict`；新增原生/Docker 模式标记、旧安装兼容探测、反向检查和 fail-closed 规则。
- 核验：覆盖旧安装、运行中服务、异常容器、残留目录、无关端口占用和并发安装，禁止误删和误放行。

## 第 3 轮：主机前置条件与命令契约

- 证据：原生 `checkSystem` 会按发行版选择包管理器并修改系统；`checkRoot` 只检查 root 和原生目录；README 没有 Docker daemon、Compose、架构和 rootless 约束。
- 缺口：Docker 安装前置条件和已安装命令没有稳定契约，可能在半初始化状态下写入文件。
- 修订：首发限定 Linux + rootful Docker Engine + Compose v2 + `amd64/arm64`；不自动安装 Docker；固定九个幂等命令、错误码和部署锁。
- 核验：daemon、权限、Compose、架构、系统类型、重复执行和并发场景均须在写状态前失败或安全返回。

## 第 4 轮：镜像职责与运行契约

- 证据：原生依赖分别由 `adapters.sh`、订阅控制、Fail2ban 和 WireGuard 模块安装；订阅控制需要 Python/systemd，Fail2ban 依赖宿主防火墙和 Nginx 日志。
- 缺口：5 个镜像只有名称和用途，没有可重建的 base、entrypoint、健康检查、用户、可写路径和特权边界。
- 修订：增加镜像运行契约；`ops`/`net` 只复用镜像而不合并进程，核心镜像不带运维工具，特权只在 profile 中声明。
- 核验：独立构建、上下文机密扫描、启动/健康检查、非 root 和特权例外测试全部覆盖。

## 第 5 轮：Compose 网络、端口与地址模型

- 证据：`protocols.sh` 的能力库同时描述 TCP、UDP、mixed transport 与 `nginx_mode`；`protocol_runtime.sh` 使用 firewalld/iptables 为 Hysteria2、TUIC 创建 UDP DNAT；`nginx.sh` 管理 Reality 443 共存和内部监听。
- 缺口：固定 Compose 模板无法自动跟随协议、动态端口、IPv4/IPv6 和宿主防火墙状态，Nginx 与核心也可能重复发布同一入口。
- 修订：由已校验的 `deployment.json` 生成 Compose；普通服务走 bridge，只有宿主内核能力进入 `net-*` profile；固定 project labels 并记录端口及规则所有权。
- 核验：覆盖 TCP/UDP、Nginx 前置、Reality 共存、双栈、端口跳跃、冲突拒绝和真实客户端地址。

## 第 6 轮：持久化、权限与备份边界

- 证据：README 列出的状态横跨核心配置、TLS、订阅、订阅组和 WireGuard；现有维护菜单明确只备份 `groups.json`。
- 缺口：计划只写了 bind mount，没有区分部署输入、持久数据、密钥、日志和完整备份边界。
- 修订：固定状态目录分类和权限；定义带 schema、文件清单、hash、路径校验和恢复前快照的部署备份。
- 核验：重建容器不丢数据，密钥不可越权读取，损坏/越界归档被拒绝，恢复失败保留原状态。

## 第 7 轮：共享代码与功能支持矩阵

- 证据：`protocols.sh` 是能力事实源；`services.sh`、`adapters.sh`、`tls.sh` 等仍包含 systemd、包管理器和宿主绝对路径调用。
- 缺口：笼统写“复用业务逻辑”容易让 Docker 入口 source 原生 bootstrap 并意外修改宿主。
- 修订：只共享纯数据、模板、校验和原子文件 helper；新增四态功能矩阵，Docker lifecycle 独立实现。
- 核验：支持项有 contract/E2E，延后项 fail-closed，共享模块不得产生宿主服务或包管理副作用。

## 第 8 轮：Nginx、TLS、ACME 与续期事务

- 证据：`tls.sh` 支持 DNS API、standalone 和 cron 续期；`nginxRuntimeReasons` 会因传统入口、Reality 共存、订阅和控制面启动 Nginx。
- 缺口：没有定义 80/443 归属、ACME 与 Nginx 冲突、证书原子替换和 reload 失败处理。
- 修订：优先 webroot/DNS-01，standalone 走显式停机事务；候选证书校验后原子替换并 reload，失败保留旧证书。
- 核验：首次签发、三种 challenge、端口冲突、坏证书、reload 失败、续期和重启恢复全部覆盖。

## 第 9 轮：订阅控制与定时任务职责

- 证据：`install.sh` 分发 TLS、Geo、订阅同步和控制等 cron 命令；订阅控制当前依赖 Python/systemd。
- 缺口：调度器若在容器内操作其他 Compose 服务，需要 Docker Socket；全部塞进一个进程又会混淆职责。
- 修订：复用 `ops` 镜像启动独立一次性任务/长期 service；宿主 timer/cron 通过 `padm-docker task` 调用，容器不接触 Docker Socket。
- 核验：锁、超时、重启恢复、失败可见性、调度项清理和全容器 Socket 扫描通过。

## 第 10 轮：Fail2ban、WireGuard、TUN/TProxy 权限模型

- 证据：Fail2ban 读取宿主 SSH/Nginx 状态并操作防火墙；WireGuard 控制面写 `/etc/wireguard`；透明代理和端口跳跃依赖 TUN、转发、iptables/firewalld。
- 缺口：普通 bridge 容器没有目标网络命名空间；直接用 `privileged` 则破坏隔离目标。
- 修订：特殊能力单独标为 `host-integrated`，仅授予精确的 host network、`NET_ADMIN`、`/dev/net/tun`，并记录规则所有权；禁止默认特权。
- 核验：默认无 capability；前置失败无副作用；启停/回滚/卸载不改外部规则；Fail2ban 看到并封禁真实源地址。

## 第 11 轮：版本锁、多架构与可复现构建

- 证据：当前仓库没有 Dockerfile、base digest 或依赖 lock；原生模式允许运行时下载和包安装。
- 缺口：仅固定镜像 tag 不能锁住 base、系统包和不同架构的上游归档。
- 修订：`versions.lock` 锁定完整构建输入，Bake 统一构建 5 镜像，CI 输出 index/platform digest、SBOM 和 provenance。
- 核验：未锁输入、checksum 漂移和 `latest` 均失败；两架构分别完成版本、启动和配置 smoke。

## 第 12 轮：现有 Release 自动 bump/push 的发布顺序

- 证据：`create_release.yml` 在 main push 时可能直接提交并 push 版本 bump，再调用 GitHub API 创建 Release，当前没有镜像门禁。
- 缺口：镜像失败可能留下已 bump 的代码或不完整 Release，版本提交还会递归触发另一次工作流。
- 修订：增加 concurrency/guard；候选构建与 smoke 先行，版本、5 镜像、签名、manifest 和 Release 按同一 commit 幂等发布。
- 核验：逐项注入构建、推送、签名、API 和重复触发失败，消费者始终只能获得完整且同源的正式 manifest。

## 第 13 轮：签名、manifest 验证与信任引导

- 证据：原生入口只做 HTTPS 下载和本地 SHA-256 模块 manifest 校验，没有发布者身份签名；Docker digest 本身也不等于可信发布。
- 缺口：若先解析未验证 manifest 中的镜像/下载地址，攻击者可替换整个更新指向。
- 修订：CI 签名镜像和 release manifest；入口内置固定 Cosign 验证器 digest、issuer 和 workflow identity，签名先于内容消费，支持离线验签但不支持生产跳过。
- 核验：篡改内容、签名、identity、bundle、digest 或 commit 均拒绝，信任根不由待验证 manifest 提供。

## 第 14 轮：manifest schema、兼容性与原子部署状态

- 证据：订阅组 `groups.sh` 已对版本、字段集合和额外字段严格校验；原生模块 manifest 也是固定 hash 列表。
- 缺口：Docker manifest、deployment 状态和 bundle manifest 缺少统一 schema、未知字段策略及迁移声明。
- 修订：定义三个 manifest/state 的版本化 schema、必填字段、格式兼容和签名摘要；状态原子替换并记录验证身份。
- 核验：坏类型、缺字段、额外字段、架构/Compose 不匹配和崩溃中断都只能得到旧或完整的新状态。

## 第 15 轮：更新、健康检查、失败回滚与状态迁移

- 证据：原生配置和包管理流程已有临时文件、备份和恢复 helper，但 Docker 计划没有候选状态、镜像预拉取、外部探针或迁移边界。
- 缺口：仅执行 `compose pull && up` 无法保证配置可读、端口可用或旧数据可回退。
- 修订：prepare/commit 全局锁、候选镜像和配置验证、进程/配置/端口/协议四层健康检查；自动回滚只允许可逆迁移，默认只保留上一版。
- 核验：注入每个阶段失败，旧版本重新健康；不可逆迁移没有备份/确认时拒绝。

## 第 16 轮：卸载、purge、备份恢复与数据保留

- 证据：原生卸载会清理服务、cron、控制面、防火墙并保留部分 ACME；各路由/订阅卸载有自己的备份回滚。
- 缺口：简单 `compose down` 会遗漏宿主调度、规则和数据保留语义，也可能误删其他 Compose project。
- 修订：普通卸载按 label/状态清理容器、网络、调度和本项目规则，保留状态/备份/镜像；`--purge` 安全路径确认后才删状态；镜像按 digest 单独删除。
- 核验：中断可诊断、外部项目不受影响、全新主机可验证并恢复备份后启动。

## 第 17 轮：PR、Release、E2E 测试矩阵与覆盖证据

- 证据：仓库已有 `fast`、`all`、transaction、subscription、routing、remote-control 回归及 `validate_install.sh`，但没有 Docker 构建、profile、双架构和回滚门禁。
- 缺口：只做 Compose 语法检查会漏掉镜像启动、协议可达、权限和宿主隔离问题。
- 修订：PR 增加所有 profile config、单架构 build/smoke/contract；Release 在干净 rootful Linux 做双架构、安装/重启/更新/回滚/卸载及 host-integrated 矩阵，并上传证据。
- 核验：原生基线不变；未通过 contract、签名、E2E 或安全边界不得发布；测试证明无 Socket、宿主软件安装和多余 capability。

## 第 18 轮：README、唯一入口说明与中英文文档

- 证据：中文和英文 README 都将 `install.sh` 描述为唯一入口，并以原生依赖、systemd/OpenRC 和 `/etc/padm` 为主。
- 缺口：这会误导 Docker 用户，也没有说明独立入口、Compose v2、rootful、双模式互斥和 5 镜像职责。
- 修订：保留原生入口说明，新增 Docker 入口、命令、系统要求、支持矩阵、数据目录、更新/回滚/卸载和发布附件；中英文使用同一 contract。
- 核验：两条文档路径都指向正确入口，示例与脚本 contract 的端口、架构、版本和权限要求一致。

## 第 19 轮：日志、健康状态、资源限制与可观测性

- 证据：原生核心、Nginx、ACME 和 cron 分散写日志，现有验收主要看服务/端口；Docker `running` 状态不足以表示配置和协议健康。
- 缺口：缺少日志轮转/脱敏、分层 healthcheck、任务结果和资源边界，故障可能被容器自动重启掩盖。
- 修订：统一日志轮转与 secret 过滤；状态命令汇总 release、profile、端口、任务、健康和回滚；默认只读根、tmpfs、`no-new-privileges`、pids/nofile，跳过监控栈。
- 核验：配置坏、端口冲突、任务超时、重启和资源耗尽均返回稳定状态，日志不泄露 secret 且保留近期诊断。

## 第 20 轮：最终一致性、范围收敛与维护成本

- 证据：前 19 轮已固定双入口、同仓库、CI 预构建、5 镜像、宿主控制面、显式内核 profile、无 Docker Socket 和事务更新；仓库当前没有第二编排平台或数据库依赖。
- 缺口：若继续为每项 service 增加镜像、把 `ops/net` 合并，或把调度/编排塞回容器，都会分别增加维护数量、扩大高权限攻击面或重新需要 Docker Socket。
- 修订：保持 Xray、sing-box、Nginx、ops、net 五镜像，多 service 复用镜像；宿主只保留控制/调度/内核边界。明确不做 Kubernetes/Swarm、Web 面板、数据库、消息队列、rootless、Windows/macOS 和任意历史迁移图。
- 核验：入口、镜像名、状态路径、profile、CI 资产和文档一致；每个组件有真实调用点和测试；未闭环能力标为 `deferred`/`host-integrated`，不新增占位架构。
