# Docker 菜单与功能对齐实施计划

修订日期：2026-10-09

本计划替代聊天中的六步菜单对齐方案，落实该方案的审计修正。它是
[功能对照表](docker-feature-matrix.md)之后的实施路线，不是重做
[容器化阶段 0–6](docker-containerization-plan.md)，也不把历史计划中的目标当作已实现能力。

## 目标与当前状态

目标是让 Docker 版具有原生菜单版的操作便利性，逐项覆盖公开协议、协议管理、
用户和订阅、站点证书、服务维护、路由及宿主集成。容器不能独立实现的功能，
提供明确的宿主操作入口或保留支持限制，不伪装成纯容器功能。

| 步骤 | 状态 | 交付 |
| --- | --- | --- |
| 1. 功能矩阵 | 已完成，提交 `7fe6a9e` | 协议与功能边界、管理状态、合同回归 |
| 2. 菜单与可信首次配置 | 2A–2C 已实现；本地 PTY、事务和 Linux 权限通过，真实发布/连通待验 | 安装后进入菜单、独立命令生命周期、无需手填镜像的首次配置 |
| 3. 配置编辑、证书与协议管理 | 3A.1–3A.3 已提交，3B.1–3B.3 已通过本地验收，3B.4 部分真实验收通过，3C.1 已交付，3C.2–3C.12 基础入口已通过本地与 amd64 传输验收，3D.1 参数重生成、3D.2 当前目标站菜单已接入，3D.3c 受管共存、3D.3d1 桥接可达宿主网站和 3D.3d2 宿主回环已通过本地/真实 Desktop 验收 | 可恢复的编辑输入、多入口、双核心、TLS 轮换及自动续期底座、协议逐项安装与管理 |
| 4. 用户、订阅与服务维护 | 4A.1–4A.4、4B.1–4B.2 已交付；4C.1–4C.2 已实现，4C.3a–4C.3c 归属、健康与主控事务底座已补，连接与管理入口继续推进 | 稳定分享身份与双核心认证/统计、本机用户业务、多服务器后端、分范围备份恢复、核心运维 |
| 5. 站点、路由与宿主集成 | 5A.1–5A.3b、5B.1–5B.4b 本地合同及双核心双栈出站/解析/域名、IP、明文 BT、CN 预设、IPv6 bridge 与用户态 WARP 本地 Peer 验收已通过；继续 SOCKS/HTTP 入站、5B 其余路由与 5C 宿主集成 | 站点管理、内部能力、规则所有权及可撤销宿主操作 |
| 6. 发布与完整验收 | 未开始 | 迁移文档、真实 Linux 与双架构证据、受门禁保护的 Release |

当前机器可读支持状态以
[`features.json`](../docker/contracts/features.json)为准：协议 `1`、`2`、`3`、`4`、`5`、`21`、`22`、`23`、`24`、`25`、`26`、`27`、`28`、`29`、`30`、`31` 的初始
配置运行已支持，协议管理工作流仍为 `deferred`。发布订阅要求 Xray、协议 `21`
和受管 TLS；不能由“可以生成链接”推断任意核心已经支持 HTTPS 订阅发布。
第一步的回归使用模拟 Docker，不能代替真实容器、SSH 终端和客户端连通验证。
2A 基线为 `a1c6287`、2B 为 `0833d4c`。2C 的模拟服务集成、真实 Linux 权限和
PTY 信号已有定向证据；真实签名发布、镜像运行和客户端连通尚未验收，不升级完整管理状态。

## 固定实施规则

- Docker 只管理 `/etc/padm-docker`；不调用原生安装器，不接管 `/etc/padm`。
- 菜单展示与输入复用现有风格，业务动作复用 Docker CLI 和候选配置事务。
- 不引入第二套编排、Web 面板、数据库或通用运行时适配框架；新增组件必须有实际功能需要。
- 生产机只使用已验证的发布清单和预构建镜像，不现场构建，不允许跳过验签。
- 普通服务使用 bridge；宿主功能显式启用，不默认 `privileged`、`SYS_ADMIN` 或挂载 Docker Socket。
- 每个子步骤独立实现、验证和审阅；用户授权后提交。文档、测试和支持矩阵随实现更新。
- 新能力的合同、实现和证据齐备后，才能升级支持状态及开放菜单；不能先改状态消除测试失败。

## 第一步：功能矩阵

保留已提交的功能对照表、机器可读状态和回归基线，不重复实现。
后续必须分别维护协议运行状态和 `management_status`，不能把协议能启动等同于
目标扫描、参数修改、端口跳跃或用户管理已经迁移。

## 第二步：菜单与可信首次配置

### 2A. 入口和菜单会话

- 在询问安装 Docker、下载模块或初始化状态之前判断无参数与 TTY。
- 已安装 `padm-docker` 无参数且处于交互终端时进入菜单；无参数非 TTY 显示帮助并退出，无副作用。
- 保留显式 CLI 用法及退出码；管道和 cron 不进入菜单、不等待交互输入。
- 显式安装在成功、TTY 可用且没有退出请求时进入菜单；非交互安装保持原命令行为。
- 每个业务动作调用已安装 CLI 子进程，执行完整加锁、信号处理和清理周期。
  不在同一菜单循环中直接串行调用持锁的 Command 函数，也不递归调用 `dockerMain`。
- 入口临时 bundle 由菜单会话退出时清理；子命令从已安装 bundle 读取合同。
  菜单等输入时不持部署锁，日志 Ctrl-C 返回菜单，输入 EOF 退出当前交互。
- 先提供状态、首次配置入口、启动、停止、重启、日志、返回和退出。
  未交付的配置向导或管理项只显示明确的未支持原因，不提供假成功操作。

验收：真实 PTY/SSH 下完成连续 `status → status → restart → status`；
未配置状态进入首次配置再取消后仍为未配置；日志中断、EOF、错误输入及子命令失败均不挂住。
无参数非 TTY 不询问、不下载、不写状态；退出后锁和临时目录按所有权清理。

本地进度：已实现入口、安装后自动菜单、`--no-menu` 和独立 CLI 动作；
日志跟随不持部署锁，INT 返回菜单、父 PID TERM 转发到动作进程组并等待清理。
`docker/tests/menu.sh` 的真实 MSYS2 PTY 回归、入口 `phase1.sh`、控制 bundle
更新/回滚 `phase6.sh`、Bash 语法及 ShellCheck error 通过；菜单回归已接入
`docker-menu` selector 和 Docker CI。日志为 `.tmp-docker-menu-phase2a.log`。
Docker 使用模拟命令，真实 Linux/SSH 及线上容器验收仍待完成。

### 2B. 可信发布与工具引导

- 复用现有 manifest 准备和验签能力，取得受信任的发布资产或用户指定的本地发布资产。
  信任身份、验证器来源和工具摘要不能来自尚未验证的清单。
- 明确 `cosign` 可用性检查及受信工具引导；需要安装宿主工具时先获得安装确认。
  无法满足验证前置条件时停止，不提供跳过验签或伪造元数据的选项。
- 验签和兼容性检查通过后，自动填入发布版本、manifest 摘要、签名身份与 5 个镜像引用。
  不要求普通用户手填 digest，不使用示例文件里的占位值。
- 本步只准备供 2C 使用的可信发布输入，并检查所需工具和镜像可用性；
  不生成协议凭据或完整 spec，不替换已安装 bundle，不提交配置、不启动业务服务。
  UUID、Reality 密钥对、short ID 和订阅 token 的生成与校验归 2C。

验收：正确发布可取得与已验签 manifest 一致的发布元数据及 5 个镜像引用；
坏签名、错误身份、缺工具、未知格式、架构不匹配、下载失败和离线资产损坏均拒绝
输出可信发布输入，已有配置和已安装 bundle 保持不变，临时资产按所有权清理。

本地进度：新增 `padm-docker release`，复用 manifest 验签、控制 bundle 候选校验
和 5 个 digest 镜像拉取，标准输出仅含 `release`、`images` JSON。
缺少 `cosign` 明确停止并说明独立受信安装要求，本步不自动安装宿主验证器。
该输出不是签名证明；2C 必须重新验签原资产并核对输入，不能只读取这份 JSON。
`docker/tests/release.sh` 使用真实已安装 CLI 与候选/清理流程，但 Docker、Cosign
和网络为模拟命令；双架构输入和拒绝路径通过，回归接入 `docker-release` 与 Docker CI。
现有更新/回滚 `phase6.sh` 及 Bash/ShellCheck error 通过。
最终 selector 日志为 `.tmp-docker-release-phase2b.log`，共用事务日志为
`.tmp-docker-release-phase6.log`；生产代码独立复审通过。
Linux 内的模拟服务集成已通过；真实 Cosign 签名发布和发布镜像拉取仍待验收。
2C 首次向导复用这些门禁，不把模拟命令的成功计作真实发布证据。

### 2C. 首次配置及受管输入保存

- 本步只对 `configured=no` 提供首次向导；已有部署可做状态和生命周期操作，
  不从 `deployment.json` 摘要拼出规格并覆盖原配置。
- 首次向导与 `configure` CLI 共用 2B 的验签和一致性门禁：
  spec 中的 `release`、`images` 必须与已验证 manifest 匹配，不能只凭字段格式、
  用户填写的签名身份或 manifest 摘要判定可信；联网和本地资产路径均不得绕过验签。
- 仅开放当前支持的核心与协议组合，先覆盖 `1`、`21`。
  协议 `21` 的流程先选择已有受管证书、导入证书或使用已有 DNS-01 能力申请证书；
  首次没有 `images.env` 时，由已验证 manifest 提供 ops 镜像。
- 收集全部输入后进行最终确认；确认前不提交配置、不申请或替换证书、不启动业务服务。
  确认后准备候选证书与规格，再调用现有校验、备份、健康检查和恢复流程。
  输入辅助函数必须将结果传回调用方，不能被 Bash 同名局部变量遮蔽；
  订阅选择与最终确认分别校验，只有明确肯定答案才进入提交流程。
- 确认后在候选事务内生成和校验 UUID、Reality 密钥对、short ID 和订阅 token；
  需要核心工具时使用 2B 已验证发布指定的镜像。自动组装完整 spec，
  不要求普通用户手工填写凭据或镜像引用。秘密仅经受限文件或标准输入传递，
  不进入普通标准输出、日志、宿主/容器内外部进程 argv 或 Docker 容器命令元数据；
  经标准输入读入后再展开到工具参数也不算通过。
- 将完整输入保存为受管 `config/spec.json`，属主为宿主 root、权限为 `0600`，不挂载给无关容器。
  该文件是配置生成输入；`deployment.json` 保留发布和运行状态职责，不承担可逆输入职责。
- 规格、关联证书和生成结果必须纳入同一次提交或可恢复事务；配置失败不能留下
  已提交的新规格与仍运行的旧配置。更新和回滚同时保留相匹配的规格及格式版本。
  候选证书和 ACME 状态保留未选择的域名、原账户和必要元数据。
  区分 root 私有备份与容器运行文件的属主/权限；备份须通过恢复校验，
  恢复后按实际容器 UID/GID 重建最小读取/写入权限，不能靠放宽私钥权限解决。
- 取消、EOF、INT/TERM 或失败清理候选输入并释放锁，不泄露密钥和 token；
  已切换状态按现有事务恢复。另行确认且已完成的宿主
  Docker/工具安装不由配置取消擅自卸载。

本步按以下检查点收敛现有候选，不再另建一套向导或事务：

| 检查点 | 交付与通过条件 |
| --- | --- |
| 2C.1 输入与秘密传递 | 真实输入辅助函数可传回确认和订阅答案；明确肯定答案进入配置，空输入/否定/`0`/EOF 不提交；凭据生成与派生校验不暴露秘密参数。 |
| 2C.2 规格、证书与恢复 | 受管 spec、TLS、ACME 和生成结果一致提交/恢复；root 私有备份可校验，容器运行权限可用；保留其他域名、账户及旧规格。 |
| 2C.3 菜单/CLI 集成验收 | 首配、伪造发布拒绝、取消、信号和失败恢复通过；受影响的菜单、发布、配置、TLS/ACME、更新/回滚回归通过，再同步说明并交付。 |

验收覆盖 Xray Reality、sing-box Reality、Xray WS TLS 和 Xray `1` + `21`；
真实 PTY 使用已安装 CLI 与实际输入函数，不能仅用桩函数宣称确认流程成功。
伪造发布字段或替换任一镜像引用时，菜单和 CLI 均在提交前拒绝。
坏证书、端口冲突、凭据生成失败、DNS-01 失败、健康失败及提交中断均有恢复断言；
确认前取消无配置变更，事务中 INT/TERM 恢复原状态且无本次秘密候选与锁残留。
检查普通输出、日志、宿主/容器进程参数及 Docker 命令元数据，不能包含秘密值。
真实 rootful Linux 不设置跳过 chown 的测试开关，验证 `0600` spec、容器 UID/GID
持有的 TLS/ACME 文件、root 私有备份以及更新/回滚后的文件内容和权限。
本地模拟 Docker 回归、真实权限检查、真实签名发布和容器/客户端实测分别记录；
缺少真实环境证据继续标为待验，不由 MSYS2 PTY 或模拟命令代替。
本阶段不宣称完整协议管理已经支持。

当前进度：2C.1–2C.3 的实现与本地验收已收敛。真实输入和 RFC 7748 派生向量、
秘密 argv、取消/信号、失败恢复、完整 spec 更新/回滚通过；损坏或漏列规格/部署记录的
快照在停止服务前拒绝。真实 Linux root 权限回归不跳过 chown，覆盖两种恢复分支。
菜单父 PID TERM 在输入及嵌套耗时子命令场景中有真实 Linux PTY 断言；
MSYS2 输入/菜单也通过。最终集成及恢复门禁/权限结果见
`.tmp-docker-linux-results-2c-all/`；真实 Docker CLI 的 Bake/Compose 合同通过。
测试使用 Linux amd64 工具容器，不是 padm 发布镜像；真实签名发布、SSH、
amd64/arm64 业务容器和客户端连接继续待验。协议完整管理状态仍为 `deferred`。

## 第三步：配置编辑、证书与协议管理

### 3A. 可编辑输入和旧部署接入

- 先定义规格格式升级、原子提交及回滚规则，再开放新增、修改和删除协议。
  修改必须保留未选中的账号、token、协议、证书及宿主集成，不能重置为示例配置。
- 旧部署优先导入用户保留的完整原始 spec。缺少原 spec 时，只导入能验证的字段，
  缺失参数要求补齐；禁止把生成配置或 deployment 摘要当作无损还原。
  导入结果先作为未提交草稿，不能提前写入受管 `config/spec.json`。
- 导入先预览差异、验证候选、保留恢复点，确认后才提交。
  无法无损导入的部署继续允许状态和服务操作，但禁止破坏性编辑。
- 取消原有“最多 2 个协议”的硬限制前，定义稳定的协议/监听器身份及数量边界，
  明确多入口、端口冲突和各核心支持组合；不默许跨核心混装。
  原生主/副核心共存另作本步子交付，验收前菜单不开放该组合。

验收：新规格可往返编辑；旧部署导入、缺字段拒绝、迁移失败及回滚有定向检查；
新增一个协议不改变其他协议身份、账号和链接。

本步拆成独立检查点，不能用字段编辑宣称全部 3A 已完成：

| 检查点 | 交付边界 |
| --- | --- |
| 3A.1 现有规格编辑与完整旧输入接入 | `edit` 私有草稿、脱敏差异、候选验证与确认提交；只能修改现有入口字段，不轮换秘密，不新增/删除协议。 |
| 3A.2 格式升级及多入口 | v1/v2 兼容、v2 单核心最多 16 个入口、稳定监听器身份、端口冲突校验及同协议复制/删除；保存其它账号及链接，已通过本地验收。 |
| 3A.3 主/副核心共存 | v3 核心归属、生命周期、端口、统计、更新及回滚已通过本地验收；真实发布和客户端连通待验。 |

3A.1 的原始交付保留 `schema_version: 1`；未知格式和多个 JSON 对象拒绝，不隐式升级。
菜单和 CLI 均仅允许端口、服务器地址、地址族、名称、Reality 目标/SNI、
WS 路径及订阅开关；UUID、密钥、short ID、token、核心/协议集合、证书和
宿主集成保持不变，发布变更走 `update`。
带 Fail2ban 的 WS 入口端口明确拒绝修改，封禁规则联动留给 3D。
旧无 spec 部署只能先导入完整原始输入，匹配运行配置后接入，不能同时改写未知字段。
校验范围包含两个核心目录、完整账号输入及按额度渲染的运行配置、Nginx、订阅、
宿主配置、Compose、监听器和挂载根路径；未知文件、额外账号或手写配置拒绝覆盖。
Reality 密钥沿用首配的标准输入派生校验。
确认前不采集或切换业务服务；确认后刷新统计、重渲染并复验候选，再复用
备份/提交/健康检查/恢复事务。草稿取消或失败即清理，不写受管 spec。
本地工具容器验证仍不等于真实签名发布、业务镜像或客户端连通验收；
完整协议管理继续为 `deferred`。

3A.1 本地验收：真实 Linux root 未跳过 chown，编辑后的 `0600 root:root` spec
与容器组运行配置、超额账号保留、单入口字段修改、旧输入接入、坏字段/发布/
密钥/额外文件/符号链接拒绝、失败恢复及草稿清理均通过。
真实 PTY 覆盖参数编辑后取消、错误输入，以及菜单编辑动作的父 PID TERM
和嵌套子进程清理；默认下载资产固定当前版本而非 latest。
最终 `phase3`、`setup`、`menu`、`phase4` 全为 `rc=0`，证据
`.tmp-docker-linux-results-3a1-final/`；共享更新/回滚与权限恢复首轮也通过，
见 `.tmp-docker-linux-results-3a1/`。Bash、ShellCheck error、JSON、
diff 与独立只读复审通过；真实签名发布和业务连通仍待验。

3A.2 当前进度：格式升级、多入口已实现并通过本地验收，不表示全部 3A 完成。
`configure` 及备份恢复仍接受 v1，保留原有最多 2 个不同协议的限制；
`setup` 输出 v2，`edit` 先严格验证原始部署基线，再只把私有草稿迁到 v2。
确认前不改受管规格；旧入口保留 `vless-reality` / `vless-ws` 的核心 tag，
新入口使用固定的 `entry-*` 身份，不按数组位置重排。

v2 单核心最多 16 个入口；Xray 支持协议 `1` / `21`，sing-box 只支持 `1`，
不允许跨核心混装。公开端口及监听器身份唯一；WS 的 `backend_port` /
`tls_port` 按入口独立保存，既有内部端口不修改，并检查核心、统计 API、
TProxy 及 Nginx 所在网络空间内的监听冲突。
菜单按入口 ID 复制/删除同协议入口，至少保留一个入口；
新增与删除分次确认提交，避免用同凭据入口替换绕过已有身份及内部端口冻结。
复制沿用账号及密钥，同 UUID 共享累计流量与额度，不视作用户 CRUD。
已有受管部署的 `edit --spec` 使用相同预览、确认和候选事务。
删除最后一个 WS 时关闭订阅、将 `tls` 设为 `null`，但保留 TLS/ACME 文件
和订阅 token；Fail2ban 关联 WS 的增删与公开端口变更暂不开放。

规格和生成结果仍在候选提交及失败恢复事务内保存，累计流量不清零。
控制 bundle 的 schema 版本声明是切换、更新和快照恢复门禁；
含 v2 规格的快照不能回滚到仅支持 v1 的旧 bundle。
规格 `schema_version` 与运行格式 `formats.config` 分开版本化，后者仍为 `1`。
编辑验证当前部署版本，其可信发布资产和已安装控制脚本必须支持 v2；
缺少支持时先刷新支持 v2 的已发布控制脚本，不伪造资产或跳过验签。
新协议类型、主/副核心共存和 TLS 轮换仍分别归后续检查点。
本地验收：Linux amd64 工具容器的 `phase3`、`phase6` 最终快照均 `rc=0`；
首配 `setup`、宿主 `phase4`、真实 root `permissions` 和菜单 `menu` 定向回归通过。
覆盖 v1 兼容、真实 PTY 复制/删除、多实例歧义拒绝、16 入口上限、内部端口冲突、
身份冻结、末个 WS 服务清理、v2 更新/失败恢复及合法 v1 回滚，累计流量保留。
Bash、ShellCheck error、schema 编译和 diff 检查通过，独立只读复审无阻断问题。
本轮将工具从 Windows 挂载复制到 Linux 临时盘后运行，最终 `phase3` / `phase6`
并行约 70 秒；测试范围未缩减，工具、候选与日志在验收后清理，不引入项目依赖。
真实签名发布、业务镜像、双架构客户端连通待验，完整协议 `management_status`
保持 `deferred`。

3A.3 当前进度：v3 明确主核心、可选副核心和每个入口的 `core`，两核心合计最多
16 个入口；v1/v2 继续接受，编辑仅迁移私有草稿。主副必须不同且各有入口，公开
端口全局唯一，内部监听和统计 API 按各自网络空间检查。双核心与宿主集成暂不可组合。
生成器分别产出两核配置、端口及校验，WS 仅归 Xray；Xray 为副核心时 Nginx
仍依赖 Xray，订阅可包含两核 Reality。部署 profile 与 spec 不一致时拒绝编辑、
更新和备份恢复，不能漏掉 Nginx/订阅或额外开启服务。

首配菜单支持两种主副顺序，副核心首配 Reality；编辑可跨核心复制已有 Reality，
删除副核心最后入口关闭副核心，主核心必须至少保留一个入口。已有身份、核心归属、
秘密、WS 内部端口保持冻结，复制共享凭据，不开放新协议类型或秘密轮换。
双核流量分全量采样、查询和复验三轮，全部成功才一次写累计；同 UUID 跨核心共享
额度，全部候选验证后统一应用，任一重启失败或中断恢复两核配置，累计流量不回退。
更新及回滚同时保留两核配置、入口和匹配规格；v3 快照不能交给仅支持 v1/v2
的控制 bundle，合法旧单核心快照仍可恢复并移除孤儿核心服务。

本地验收：Linux amd64 工具容器的配置、首配、流量、更新/回滚、宿主集成、
真实 root 权限和菜单 7 组回归通过；真实 PTY 覆盖两种主副首配、跨核复制/删除、
主核心最后入口保护及 INT/TERM 清理。配置回归覆盖主 sing-box/副 Xray WS、
每核候选失败/启动失败恢复、profile 一致性门禁及端口命名空间；流量回归覆盖
共享 UUID、任一采样失败/采样期重启不写累计、额度验证/重启失败及中断恢复。
Bash、ShellCheck error 和 JSON Schema 编译通过。工具容器须使用 `--init`
回收退出的子进程，避免把僵尸进程误判为业务子进程仍存活；测试业务 Docker/Cosign
仍为模拟，不替代真实签名发布、SSH、两架构业务镜像或客户端连通。完整协议管理
继续 `deferred`；临时工具及验证结果在本轮验收后清理。

### 3B. 通用 TLS 与轮换

- 在开放直接终止 TLS 的协议前，完成证书选择、导入、DNS-01 申请和续期的通用合同。
- 按协议明确终止 TLS 的服务、证书路径、只读挂载及重载/重启方式；
  不能把现有 Nginx reload 直接用于核心端 TLS。
- 候选证书校验域名、有效期和私钥匹配后替换，重载相关核心或 Nginx，
  健康检查失败恢复旧证书和配置；调度不得重复执行。
- webroot 与 standalone 在 5A 交付；本阶段未支持的 challenge 明确拒绝。

验收：覆盖核心端与 Nginx 端证书轮换、错误证书、续期失败、重载失败和旧证书恢复。

按以下检查点逐项交付，3B.1 不等于全部 3B 完成：

| 检查点 | 交付边界 |
| --- | --- |
| 3B.1 Nginx 端管理与可恢复轮换 | 菜单第 8 项及 `tls manage/validate/install`、DNS-01 `issue/renew`；候选账户隔离、证书与账户同事务、已部署 ops 一致性、`nginx -t`/重载/健康失败恢复及信号清理。 |
| 3B.2 核心端 TLS 合同 | 明确 Xray/sing-box 的路径、只读挂载、权限、重载/重启和逐核健康门禁；没有对应已验收协议时不得声称业务支持。 |
| 3B.3 续期调度 | 保存私有续期输入、唯一受管调度及部署锁；更新/回滚/卸载保持所有权，失败不替换旧证书或泄露 DNS 凭据。 |
| 3B.4 联合验收 | 覆盖核心端与 Nginx 端、双核及订阅关联、失败/信号恢复；补齐可执行的真实环境证据，再允许后续协议依赖相应 TLS 能力。 |

3B.1 当前实现：交互输入和最终确认前不持锁；后端加锁后复核部署、规格与镜像。
现有 Nginx 端轮换先校验有效期、域名和私钥匹配，再校验 Nginx、重载和健康检查。
DNS-01 只改候选账户，成功后一起提交证书和账户；失败或中断恢复旧状态，
保留未选域名和累计流量。其他域名只保存或校验证书，不更改入口或规格。
自动调度在 3B.3 接入；webroot 和 standalone 均未开放，核心端 TLS 仅交付受管证书底座，完整协议管理仍为 `deferred`。

本地验收：Linux root 的 TLS、菜单真实 PTY、首配、配置与真实权限回归均通过。
正式 `docker-tls` selector 用时约 41 秒，覆盖导入/申请/续期、有效期与私钥/域名检查、
每个 Nginx 失败点、TERM、原始缺失状态、备份损坏与账户备份缺失、临时私钥链接、
部署/规格/镜像不一致拒绝。菜单验证取消、EOF、最终确认、
四动作参数和输入/动作期中断；只读复审发现的两个恢复边界已修正并补反例。
新增 root 回归已接入 Docker CI 与发布门禁；模拟外部 Docker/ACME 的本地证据
不替代真实镜像、DNS 服务商、发布或客户端连通验收。

3B.2 当前进度：核心配置只识别 Xray 服务端 TLS 与 sing-box 非 Reality TLS，
要求同域名 `.crt/.key` 受管路径；相关核心只读挂载 `/etc/padm/secrets/tls`，
候选证书、实际 Compose 挂载、镜像 digest 和配置路径一致性一并检查。
换证时固定消费者列表，先校验全部核心和 Nginx，再逐项强制重建 Xray/sing-box
或 reload Nginx，并执行各服务健康门禁。任一失败或 TERM 恢复旧证书和账户；
恢复不因首个服务失败遗漏其它消费者，失败时保留备份。
核心重建前严格采集流量，恢复前尽力采样，累计流量不回退；无消费者不启停服务。
该合同不新增协议 ID，不把核心 TLS 底座升级为新协议支持或完整协议管理。

本地验收：同一 Linux root 源码快照的 `tls`、`phase3`、`phase6`、`permissions`
和 `traffic` 全部通过，TLS 约 37 秒、配置约 180 秒，其余套件并行完成。
覆盖普通 TLS 多域解析、Reality/出站/验证用途排除、核心独立与双核加 Nginx、
全部先校验、任一核心失败及 TERM 恢复、恢复仍尝试其它消费者、坏备份元数据、
挂载/根路径/镜像漂移、无 spec 旧部署兼容和候选坏证书拒绝。
Bash、ShellCheck error 和最终只读复审通过；外部 Docker/ACME 为模拟，
真实文件、权限和信号检查不代替业务镜像、DNS 服务商或客户端连通证据。

3B.3 当前实现：证书菜单新增自动续期状态、启用、停用，
CLI 使用 `acme schedule enable/disable/status` 与 `acme auto-renew`。
启用前复核域名的受管证书和匹配 DNS provider 的 ACME 账户；RSA/ECC 选择与实际
调用一致，重复账户字段拒绝。私有续期输入保存在宿主 `secrets/renewal/<域名>/`，
目录 `0700 root:root`、文件 `0600 root:root`，不挂载给长期容器，不随配置回滚退回。
DNS 凭据经标准输入注入工具，不出现在调度、argv 或 Docker 环境元数据中。

每个部署只装一个每日任务，systemd/cron 双向互斥并校验 root/CLI/资源归属。
输入与调度同事务，安装、停用或 TERM 失败恢复原任务和 enabled/active 状态。
日常运行持部署锁，未到期返回为正常跳过；逐域失败不替换旧证书和账户，
恢复失败保留恢复点并停止后续域名。停机和卸载先撤销受管任务，启用服务时恢复；
更新/回滚保留最新输入，并在停止服务之前拒绝不兼容的目标控制 bundle。

本地验收：Linux root 的续期、TLS、菜单真实 PTY、权限、发布输入、首配、
更新/回滚和配置回归全部通过；续期约 23 秒，首配 30 秒、更新/回滚 39 秒、
配置 182 秒。受影响套件共享一次源码快照并行执行，失败后只复验改动范围。
覆盖两个调度后端互斥、外部任务归属、精确 enabled/active 恢复、输入/安装/提交期
TERM、锁冲突、多域继续、正常跳过、RSA/ECC、重复账户字段、凭据不进入元数据，
以及最新私有输入跨配置更新/回滚保留。新增 `docker-renewal` selector 接入 Docker
CI 与 Release；Bash、ShellCheck error 和只读复审通过。
外部 ACME、systemd/cron 命令仍为模拟；真实 DNS、宿主重启、业务镜像及客户端
连通继续由 3B.4 验收，不因本地成功开放新协议或完整管理。

3B.4 当前进度：真实 Linux amd64 daemon 上的本仓库 Xray、sing-box、Nginx、ops
镜像已完成双核心 TLS 与 Nginx 联合轮换，arm64 仿真也通过原三路用例。
三个使用测试 CA 正常校验的客户端出站取得实际 HTTP 内容，
覆盖两个核心 TLS 夹具与 VLESS WS TLS；Python 证书及 HTTPS 订阅探测也校验 CA/域名。
最终五路脚本在 amd64 / arm64 仿真均通过，耗时 72.719 / 95.714 秒：
两核心 Reality Vision 经 Debian 公网目标握手，首装、换证、真实健康故障与 TERM
恢复后均重新解析实际 HTTPS 订阅生成 sing-box 客户端，取得 HTTP 内容。
订阅参数独立匹配公开 spec，四个坏 URI 反例拒绝；真实候选校验后才替换/重建。
仅隔离端点映射，不代表公网入口、第三方导入 UI 或原生 arm64 验收。
仿真暴露客户端监听竞态，增加共享 10 秒端口就绪门禁，不重试协议握手。
订阅访问、成功换证、真实 sing-box 健康故障恢复及 TERM 恢复通过，
累计流量不回退。真实测试发现 Compose 会吞掉消费者循环的 stdin，已在共享
管理调用修复并增加删除修复即失败的最小检查。

TLS/续期回归复用既有并行框架，顺序 61 秒、并行 37 秒，范围不减；
Docker CI/Release 使用 `docker-tls-focused`，phase5/phase6 与静态检查通过。
可执行命令、镜像 digest、环境和边界见
[真实 TLS 验收基线](docker-tls-real-baseline.md)。
独立 Debian 容器内的真实 systemd/cron 五阶段验收也通过：唯一任务、外部任务保护、
两域启停、实际 probe 执行、双向后端迁移和两个调度器的容器重启。
重启要求新 PID 1 标识的实际执行事件，不用旧计数替代；不伪装 `systemctl/crontab`。
probe 不执行 ACME 或完整业务 CLI，这些证据不能替代整机重启与真实 DNS。
本轮使用 Docker Desktop 的 Linux daemon，不扩大 Windows/生产支持范围；
内部 TLS 夹具不开放 Trojan；Microsoft 目标的 Xray EOF 仍有未确认原因，见基线。
Nginx 读取配置前的默认日志权限提示已通过镜像入口与容器内校验/reload 的
`-e /dev/stderr` 修复，访问日志及权限合同不变；现有 smoke 拒绝旧镜像反例，
新两架构通过。完整五路联合验收再次在 amd64/arm64 仿真通过，
耗时 71.178/93.993 秒；现有并行 TLS/续期门禁 15.094 秒通过。
本次工具环境不同，不跨环境比较耗时；arm64 平台/io_setup 仿真告警仍保留。
真实 DNS、完整宿主重启、
原生 Linux/SSH、原生 arm64 与可信发布继续待验，3B.4 不能标为完成或升级协议状态。

### 3C. 按协议逐项交付

| 顺序 | 协议 ID | 交付范围 |
| --- | --- | --- |
| 基线完善 | `1`、`21` | 可编辑配置、现有协议完整管理及真实客户端验证 |
| Reality 扩展 | `2`、`26` | XHTTP 与 Reality gRPC，按矩阵列出的核心分别验证 |
| 普通核心协议 | `3`、`4`、`5`、`30`、`31`、`28` | Hysteria2、AnyTLS、NaiveProxy、Shadowsocks、TUIC、direct Trojan |
| Nginx/传统 TLS | `22`、`23`、`24`、`25`、`27`、`29` | WS、HTTPUpgrade、gRPC、Vision/fallback、Trojan fallback |

每项必须同时交付 schema/严格校验、核心配置、Compose profile、TCP/UDP 和双栈端口、
正确客户端输出、候选配置验证、失败恢复及定向回归。fallback 所需最小后端在本步
交付，站点编辑和诊断在 5A 扩展；不得等待第五步才补协议启动必需的依赖。

每个核心路径单独验证，不因另一核心通过就标记全部可用。默认延续单主核心；
3A.3 已验收的 v3 主副核心合同可复用，新增协议组合仍需单独验证生命周期、
端口、统计和更新回滚后才开放。

本步区分“生成本地链接/订阅内容”和“HTTPS 发布订阅”。新增协议不能绕过当前
发布拓扑限制；通用发布由 4A 实现后才升级对应前置条件。

Hysteria2/TUIC 先支持单 UDP 入口并迁移带宽、拥塞和协议参数管理；
宿主 DNAT 端口跳跃归属 5C，在此之前菜单明确显示未开放，不复用原生防火墙 helper。

验收：每个新增核心/协议组合有真实配置检查、容器健康与客户端连接证据；
TCP、UDP、双栈和多入口冲突按适用范围验证。未支持组合在修改状态之前拒绝。

#### 3C.1 当前协议的管理入口

已提供“协议与入口”子菜单与 `protocol list`、`protocol links [入口 ID]`：
列表不含凭据，链接标准输出仅含 URI；菜单复用现有编辑器完成参数修改、复制或删除，
不新增写配置事务。HTTPS 订阅发布关闭时仍可生成本地链接，只在私密临时副本中启用生成，
不会修改发布开关或受管规格。读取复用部署锁、完整规格校验和运行基线检查，
拒绝缺失/不安全规格及运行漂移；v1/v2 迁移仅发生在临时副本，等待菜单输入时不持锁。

本地验收：Docker Desktop Linux daemon `29.8.2`，现有 Alpine net 镜像
`padm-local/padm-net:fail2ban-before-3c1`
（`sha256:f84a3720bebef4035d36346081d68fbf70603aef38c9731200ae8afca4fc9900`），
只读挂载仓库、固定 Linux 源码快照，root 协议回归 `8.60` 秒通过，菜单真实 PTY
`16.28` 秒通过。协议检查覆盖全部/指定链接、IPv6、旧规格、关闭发布、
双核心、权限/所有者/符号链接、核心/订阅/编排漂移和运行状态不变；
INT/TERM 的函数边界信号注入验证退出码、锁和私密目录清理。
菜单覆盖未配置、取消、业务分发、返回及已有信号回归。
逐文件 Bash、生产 ShellCheck error、测试 warning 与 diff check 通过；
协议测试接入 `docker-protocol` selector 和 Docker CI 的 root 合同门槛。

Docker/网络边界使用模拟命令，本项不新增真实客户端、SSH 或发布证据；
不支持无完整规格或手写漂移部署的链接反推。协议范围仍仅 `1`、`21`，
完整 `management_status` 继续 `deferred`：3D 高级管理与 4A 用户/分享订阅尚未交付，
3C 的新协议及完整管理验收不能据此标为完成。

#### 3C.2 Reality XHTTP 与 gRPC

新增协议 `2`（仅 Xray）与 `26`（Xray/sing-box），沿用 v3 和现有候选事务。
首配支持 XHTTP/gRPC，双核心的副核心仍默认 Reality Vision；
已有 Reality 入口可派生其它传输入口，复用 UUID、密钥和 short ID，
不能替换已有入口身份或新造凭据。XHTTP 支持 path、Host、auto/packet-up/stream-up；
gRPC 支持 service name；概览、本地分享链接及 HTTPS 发布内容均复用原生成器，
发布仍要求 Xray WS TLS 和受管证书。新传输不附加 Vision flow。
目标风险校验覆盖三种 Reality，相同目标/SNI 去重检测。

更新、配置切换和备份恢复的 bundle 门槛同时核对规格版本与每个协议/核心组合，
拒绝旧 v3 bundle 中 `deferred`、缺失或核心不匹配的新增协议；不新增规格版本。
功能矩阵的协议 `2`/`26` 为基础配置运行 `supported`，完整管理仍 `deferred`。
高级 XHTTP 参数、目标库/扫描/PQC/参数重生成/443 共存继续归后续管理阶段。

本地验收：Docker Desktop Linux daemon `29.8.2`，固定 Linux 源码快照，
首配/编辑真实 PTY `38.143` 秒通过，新增 Reality 定向回归 `14.340` 秒通过，
配置/编辑/更新回滚与功能矩阵 `phase3` `123.583` 秒通过。
覆盖新首配和取消、三种新双核心首配、派生/编辑、跨核心拒绝、凭据不变、
严格字段反例、旧 v1/v2 拒绝新协议、旧 bundle 拒绝、双栈 TCP 映射、
关闭发布时精确 URI、运行漂移拒绝、各传输共享 UUID 账号/额度、双核心失败事务恢复，
以及新协议组合的实际控制命令更新/回滚后配置、链接和流量状态保持。
Draft 2020-12 JSON Schema 正反例、Bash、ShellCheck 与 diff check 通过。
`docker-reality` selector 已接入；CI root 门槛运行 `reality.sh`，
该套件复用并包含原 `protocol.sh` 回归，不额外重复运行。

真实 amd64 验收 `15.416` 秒通过：唯一 Compose 项目/网络/命名卷，
不发布宿主端口，不改现有部署；两核心服务端及两个客户端配置检查、
生成的服务健康检查均通过。客户端仅从 `protocol links` URI 生成，
Xray auto XHTTP、sing-box gRPC 到 Xray、sing-box gRPC 到 sing-box
三条 SOCKS 实际 HTTP proof 并行通过，Reality 目标为 `www.debian.org`。
测试卷经 tar 流保留 `0:10001` 和 `0750/0640`，未放宽运行权限；
测试项目 `padm-reality-1791265518-73507-25456` 的容器、网络和卷无残留。
复现命令：

```bash
bash docker/tests/reality.sh
bash docker/tests/reality-real.sh \
  padm-local/padm-xray:tls-3b4 \
  padm-local/padm-sing-box:tls-3b4 \
  padm-local/padm-ops:tls-3b4
```

本机镜像固定 ID：

| 镜像 | ID |
| --- | --- |
| Xray | `sha256:edb005cb17f2961596b42cd2266a87ef5adcd3c6601cf529b6a088ac5f37dacd` |
| sing-box | `sha256:5fdff482ad9c65aa0e583a20e27d5f322b2539e673432e2cf78c7f460028fcb3` |
| ops | `sha256:ca6bf4a8b7936718eb9d3633fb8580e6e50de388c93275394f5c3768bb2587f6` |

本项未重建、签名发布或部署镜像，未验公网宿主入口、原生 arm64、
第三方导入 UI、XHTTP packet-up/stream-up 实际传输及其它目标/客户端；
真实脚本直接验生成配置和传输，不冒充生产 DNS/ASN 风险门禁通过。
3B.4 剩余环境条件和 3D 完整管理仍未完成。

#### 3C.3 Hysteria2 基础入口

新增协议 `3`，仅支持 sing-box 的 v3 合同，继续复用配置候选事务、受管 TLS、
同 UUID 流量账号与额度；v1/v2 拒绝新增协议，不另建凭据或统计状态。
共享 UUID 校验与 schema 均限制为 36 字符，拒绝尾换行，避免统计名称失配。
首配的 sing-box 协议选项 `6` 提供单 UDP 入口和 BBR/Brutal，
带宽按服务端方向填写，分享 URI 转为客户端方向。
Salamander 密码随机生成或私密输入，不经 argv 或普通输出；
HTTPS 伪装仅接受受约束的域名/路径，不接受凭据、查询串或控制字符。
参数编辑、同核心复制、删除及完整 `configure` 规格导入均已接入。
已有部署安装新 Hysteria2 类型仍需完整规格，不能从其它协议派生身份；
删除最后一个 WS 后关闭发布，仍有 Hysteria2 时保留 TLS 关系。

生成器按入口发布 IPv4/IPv6 UDP，部署记录与占用检查同样使用 UDP；
单核心及 Hysteria2 作为主/副核心组合均覆盖。包含 Hysteria2 时暂拒绝宿主集成，
HTTPS 订阅发布仍要求 Xray WS TLS；本地链接不依赖发布。
协议 `3` 的配置运行状态为 `supported`，完整管理仍 `deferred`；
端口跳跃、Gecko、独立用户 CRUD 和其它高级管理尚未开放。

本地验收：固定 Linux 源码快照与 `--init` 工具容器；
`hysteria2.sh` 复用 Reality/旧协议基线，审计修复后 `22.417` 秒通过，
覆盖严格合同、旧版本拒绝、UDP 双栈、BBR/Brutal、混淆/伪装、
精确 URI、共享账号额度、端口占用、失败事务及更新/回滚。
首配/编辑 PTY `60.235` 秒通过，覆盖确认前取消、秘密不外泄、
身份冻结、参数编辑/关闭、跨核心拒绝及删除时的 TLS/发布关系。
`phase3` `126.583` 秒、`phase4` `17.636` 秒、TLS `13.122` 秒、
流量 `5.253` 秒、菜单/信号 `17.339` 秒、Linux 权限 `1.730` 秒通过。
测试在插入 mock PATH 前记录真实 `uname/stat`，不再依赖 `/usr/bin` 布局；
缺 PTY 工具或 GNU `find -printf` 时早失败，不跳过快照断言。
Bash、生产 ShellCheck error、测试 warning、JSON、Draft 2020-12 的
10 个正例/22 个反例与 diff check 均通过。
新增 `docker-hysteria2` selector，CI root 协议门槛改为 `hysteria2.sh`，
一次包含 Hysteria2、Reality 与旧协议基线。

真实 Linux amd64 验收 `11.704` 秒通过：使用上节相同的 3 个固定本机 image ID，
不拉取镜像、不发布宿主端口；唯一 Compose 项目/网络/卷保持生产权限与健康检查。
客户端仅从 `protocol links` URI 提取参数并信任测试 CA，
BBR、Brutal、Salamander 各 IPv4/IPv6，共 6 条 SOCKS HTTP proof 并行通过。
复现命令：

```bash
bash docker/tests/hysteria2.sh
bash docker/tests/hysteria2-real.sh \
  padm-local/padm-xray:tls-3b4 \
  padm-local/padm-sing-box:tls-3b4 \
  padm-local/padm-ops:tls-3b4
```

未重建或发布镜像，未验公网 UDP 宿主入口、第三方导入 UI、HTTPS 伪装实际响应、
原生 arm64、真实 DNS 服务商和可信签名发布；隔离传输不代替这些条件。
3B.4 剩余验收、3C 其它协议、3D、4A 与 5C 仍未完成。

#### 3C.4 AnyTLS 基础入口

新增协议 `4`，仅支持 sing-box 的 v3 合同，复用受管 TLS、候选事务及 UUID 流量账号。
UUID 同时作为 AnyTLS 密码与统计名称，不另建账号状态；域名不得包含控制字符。
首配选择 sing-box 后使用协议选项 `7`，支持单核心或主 sing-box、副 Xray Reality。
AnyTLS 单独首配不收集 Reality 参数、Hysteria2 参数或 HTTPS 发布开关。
完整 `configure` 规格导入、通用字段编辑、同核复制与删除均已接入；
既有 UUID、TLS 域名、核心归属和入口身份冻结，不能从其它协议派生新 AnyTLS 类型。
已有部署新增类型须使用完整 v3 spec；跨核心复制在变更前拒绝。

生成 sing-box TCP/TLS 入站、IPv4/IPv6 TCP 映射及 `anytls://` 分享链接，不经过 Nginx。
支持 AnyTLS 作为主/副核心入口，包含 AnyTLS 时暂拒绝宿主集成。
HTTPS 发布仍要求 Xray WS TLS 与同域受管证书；关闭发布时可只读输出本地 URI。
删除最后 WS 关闭发布；只要 Hysteria2 或 AnyTLS 仍在就保留 TLS 关系，
删除最后 TLS 入口才清空规格引用，受管证书文件仍保留。
协议 `4` 的配置运行为 `supported`，完整 `management_status` 继续 `deferred`。

本地验收：Docker Desktop Linux daemon `29.8.2`，固定 Linux 源码快照；
`anytls.sh` `30.853` 秒通过，串接 Hysteria2、Reality 与旧协议基线。
新增检查覆盖严格字段、v1/v2 拒绝、旧 bundle 拒绝、三种主副核心拓扑、
TCP 双栈与占用检查、TLS 挂载、精确 URI、运行漂移、共享额度和失败/更新/回滚恢复。
首配/编辑真实 PTY 在 `--init` 容器中 `73.76` 秒通过，覆盖取消、TLS 失败、
无秘密 argv、通用编辑、身份冻结、同核复制、跨核拒绝及 WS/Hysteria2/AnyTLS 删除关系。
功能矩阵与配置事务 `phase3` 约 `114` 秒通过；Bash、ShellCheck 与 JSON 检查通过，
Draft 2020-12 Schema 的 6 个正例/17 个反例通过，跨字段关系继续由生产校验器验证。
新增 `docker-anytls` selector，CI root 协议门槛改为 `anytls.sh`，一次运行完整既有基线。

真实 Linux amd64 验收 `12.296` 秒通过：复用 3C.2 的 3 个固定本机 image ID，
不拉取镜像、不发布宿主端口；唯一 Compose 项目/网络/卷保持生产权限和健康检查。
客户端只从 `protocol links` URI 解析参数并信任测试 CA，
IPv4/IPv6 两条 AnyTLS SOCKS HTTP proof 通过，验收资源已清理。
复现命令：

```bash
bash docker/tests/anytls.sh
bash docker/tests/anytls-real.sh \
  padm-local/padm-xray:tls-3b4 \
  padm-local/padm-sing-box:tls-3b4 \
  padm-local/padm-ops:tls-3b4
```

未重建、签名发布或部署镜像，未验公网 TCP 宿主入口、第三方导入 UI、原生 arm64、
真实 DNS 服务商和完整宿主重启；这些限制不由隔离连接成功推断完成。
3B.4 剩余验收、3C 其它协议、3D、4A 与 5C 仍未完成。

#### 3C.5 NaiveProxy 基础入口

新增协议 `5`，仅支持 sing-box 的 v3 合同，沿用受管 TLS、候选事务和固定 UUID。
首配选项 `8` 支持单核心或主 sing-box、副 Xray Reality，确认前拒绝异域与双核端口冲突。
入口服务器必须与 `naive.domain` 及 TLS 根域一致，按原生格式输出
`naive+https://username:password@domain:port?padding=true#name`，不添加独立 SNI 覆盖参数。
用户名、密码和统计标识均为 UUID；流量渲染保留 `username/password`，不能添加 `name`。
仅发布 IPv4/IPv6 TCP，明确 `network: tcp`，不隐式开启 UDP/QUIC。
已有证书、导入与 DNS-01 复用原事务；入口端口/地址族/名称编辑、同核复制和删除已接入。
域名、UUID、核心归属及身份冻结；新类型需要完整 `configure` 规格，跨核复制与宿主集成拒绝。
删除其它 TLS 协议时保留 Naive 的 TLS；最后 TLS 入口删除才清空规格引用。
HTTPS 发布仍要求 Xray WS TLS，组合发布可包含 Naive 链接；完整管理仍 `deferred`。

本地验收：固定 Linux 快照和 `--init` 工具容器，
`naive.sh` `39.26` 秒包含 AnyTLS/Hysteria2/Reality/旧协议基线，
首配/编辑 PTY `94.97` 秒、流量 `4.95` 秒、`phase3` `113.31` 秒通过。
覆盖严格合同、v1/v2/旧 bundle 拒绝、三拓扑、双栈 TCP、TLS/URI/运行漂移、
共享额度、失败/更新/回滚及最后 TLS 消费者关系；Schema 6 正例/19 反例、Bash/ShellCheck/JSON 通过。
`docker-naive` selector 与 CI `naive.sh` 入口一次覆盖全部既有协议，不额外重复运行旧套件。

真实 amd64 `11.94` 秒通过：沿用 3C.2 的固定业务镜像、生产权限及健康检查，
客户端仅从 URI 提取认证/TLS 参数并信任临时测试 CA，IPv4/IPv6 两条 SOCKS HTTP proof 通过。
共享服务端网络查询真实 gRPC，UUID 上/下行均为正计数，未修改生产统计监听地址。
第 4 参数为具备 HTTP/2 curl 的本地工具镜像，不允许隐式拉取；本次工具镜像 ID
`sha256:4d65c50b17a9478c1272f88fad4a1dad1127909e8ac293e6d7d625a337d9e5a6`，
仅用于验收，业务端未改镜像或权限；本轮容器、网络、卷和工具镜像已清理。
复现时先准备本地 HTTP/2 curl 工具镜像，再运行：

```bash
bash docker/tests/naive.sh
bash docker/tests/naive-real.sh \
  padm-local/padm-xray:tls-3b4 \
  padm-local/padm-sing-box:tls-3b4 \
  padm-local/padm-ops:tls-3b4 \
  local-http2-curl:test
```

隔离 CA 不证明生产证书、指纹或公网连通；第三方导入 UI、公网入口、原生 arm64、
真实 DNS、整机重启及可信发布仍待验，3B.4/其余 3C/3D/4A/5C 不能标完成。

#### 3C.6 Shadowsocks 基础入口

新增协议 `30`，仅接受 sing-box v3，固定 SS2022 `2022-blake3-aes-128-gcm` 多用户模式。
首配选项 `9` 确认后由可信 sing-box 镜像分别生成 16 字节服务器/用户密钥；
canonical Base64 严格校验，秘密经私密文件传入，不出现在 stdout 或进程参数。
单协议不收集 TLS、订阅或 Reality 参数；副 Xray Reality 复用既有首配输入。
无需 TLS/Nginx，同端口发布 TCP/UDP 双栈；部署以相同入口 ID 的两条传输记录表示，
唯一性按 `(listener_id, transport)` 检查，端口占用与归属分别检查 TCP/UDP。
首配、完整规格导入、通用字段编辑、同核复制与删除、精确 SIP002 链接均已接入。
已有部署新增类型须完整 `configure` 规格；方法、两密钥、UUID、核心和入口身份冻结。
本地 URI 不依赖发布开关；HTTPS 发布仍要求 Xray WS TLS，包含 SS 时暂拒绝宿主集成。
UUID 复用现有流量/额度；超额撤销运行入站，避免空 `users` 回落为服务器密钥单用户认证，
解除额度后从保留的 `users.base` 恢复原密钥和监听，不增加假用户或另一套路由状态。
SS 保留时删除最后 TLS 消费者仍清空规格 TLS 引用，受管证书文件不删除。
配置运行状态为 `supported`，完整 `management_status` 继续 `deferred`。

本地验收：Linux 固定源码快照、`--init` 工具容器，
`shadowsocks.sh` 前台 `51.342` 秒一次包含 Naive/AnyTLS/Hysteria2/Reality/旧协议基线；
首配/编辑 PTY `126.908` 秒、`phase3` `132.945` 秒、流量 `5.139` 秒通过。
覆盖严格合同、canonical 密钥、v1/v2/旧 bundle 拒绝、三拓扑、四端口映射、
双传输监听及漂移、URI/脱敏/无秘密 argv、共享额度、失败事务和更新/回滚。
Bash、ShellCheck、JSON、Draft 2020-12 Schema 的 6 正例/30 反例通过。
固定 sing-box 镜像的 `generate rand --base64 16` 现场校验为 canonical 16 字节；
两项独立只读审阅无可操作发现，真实发布验签仍不是本轮工具命令验收范围。
信号敏感测试须前台执行；后台 shell `&` 会继承忽略 INT，不计为有效信号验收。
CI 改为 `shadowsocks.sh` 根入口，新增 `docker-shadowsocks` selector，不重复跑旧套件。

真实 amd64 `36.975` 秒通过，沿用 3C.2 的固定 Xray/sing-box/ops 镜像。
客户端只从 `protocol links` 解析认证和 authority，IPv4/IPv6 TCP HTTP 与 UDP echo proof 通过；
仅服务器密钥认证均拒绝，UUID 上/下行计数 `196/356` 均为正。
超额后同客户端的新 TCP/UDP 请求全部拒绝且源站计数不增，解除后恢复原密钥与传输；
生产权限、cap drop、只读根、init、健康检查保持，未发布宿主端口。
第 4 参数为本机具备 HTTP/2 curl 的临时工具镜像，本轮 ID
`sha256:3867ffeba00503d755dd5765db41981993b645d83bb9e157f01d4c8ee624b738`。
工具镜像只用于验收，不替换业务镜像；容器、网络、卷和临时工具在验收后清理。
复现时先准备工具镜像，再运行：

```bash
bash docker/tests/shadowsocks.sh
bash docker/tests/shadowsocks-real.sh \
  padm-local/padm-xray:tls-3b4 \
  padm-local/padm-sing-box:tls-3b4 \
  padm-local/padm-ops:tls-3b4 \
  local-http2-curl:test
```

未验公网 TCP/UDP 宿主入口、第三方导入 UI、保持打开的既有会话、原生 arm64、
真实 DNS/整机重启或可信发布；凭据轮换与用户 CRUD 未开放。
3B.4、其余 3C、3D、4A、5C 仍待完成；后续 TUIC 交付见 3C.7。

#### 3C.7 TUIC 基础入口与参数管理

新增协议 `31`，仅接受 sing-box v3，单 UDP 入口支持 IPv4/IPv6。
首配选项 `10`，可选主 sing-box 与副 Xray Reality；UUID 复用为用户 ID、密码与统计账号。
默认拥塞 `cubic`、认证超时 `3s`、心跳 `10s`、关闭 0-RTT；支持 `bbr` 和 `new_reno`，
时长接受 1–6 位正整数及 `ms/s/m/h` 单位，0-RTT 严格布尔值，菜单明确提示重放风险。
复用受管 TLS/ACME、`h3`、生产候选验证和失败恢复；TLS 域名与入口身份冻结。
首配、完整规格导入、通用字段编辑、编辑项 `14` 四项协议参数、同核复制与删除均接入。
本地 `tuic://` 采用百分号编码、原生 UDP 中继和严格 TLS 校验；
认证超时、服务端心跳与服务端 0-RTT 不导出到客户端 URI。
HTTPS 发布仍要求 Xray WS TLS，包含 TUIC 时暂拒绝宿主集成；已有部署安装新类型须完整 v3 spec。
删除最后 WS 时保留 TUIC TLS 关系，删除最后 TLS 消费者清除规格引用但不删除受管证书。
UUID 复用既有流量/额度过滤；完整 `management_status` 仍为 `deferred`，端口跳跃归属 5C。

本地验收：固定 Linux 源码快照、可执行 tmpfs、前台 `--init` 工具容器；
`tuic.sh` `64.369` 秒一次包含 Shadowsocks/Naive/AnyTLS/Hysteria2/Reality/旧协议完整基线；
首配/编辑 PTY `144.002` 秒、`phase3` 合同/矩阵 `135.263` 秒通过，
覆盖单/双核心、取消、参数编辑、复制拒绝、身份冻结、TLS 删除和失败恢复。
严格合同、v1/v2/旧 bundle 拒绝、三拓扑、UDP 占用与归属、漂移、精确 URI、共享额度、更新回滚通过。
Bash、ShellCheck、JSON、嵌入 Python 及 Draft 2020-12 Schema 7 正例/33 反例通过；
独立只读生产审阅无可操作问题。CI 使用 `tuic.sh` 根入口，新增 `docker-tuic` selector，不重复旧基线。

真实 amd64 `52.152` 秒通过，沿用 3C.2 的固定业务镜像；
客户端只从实际链接解析认证/端口/拥塞/SNI，使用隔离 CA 校验 TLS，未开启 insecure。
三个拥塞算法各自 IPv4/IPv6 的 TCP HTTP 与 UDP echo proof 均通过，双栈错误密码拒绝；
UUID 实际上/下行计数 `546/984` 均为正。生产额度事务拒绝请求且源站计数不增，
解除后仍使用同一客户端恢复，新请求精确增加源站 TCP/UDP 各 6 次，`users.base` 哈希不变。
TUIC 客户端缓存 QUIC 连接的失效识别是异步的，允许路径最多等待 60 秒重连；
本次恢复 `cubic` 的 TCP/UDP 各重试 4 次，其余算法 0 次，拒绝路径无重试。
生产非 root、只读根、cap drop、init、健康和权限保持，未发布宿主端口。
第 4 参数的 HTTP/2 curl 临时验收镜像 ID 为
`sha256:fc76205557045809abceda494dd21dfb8c9913e6a579cc46f07cb0ff8ebc01d5`，
工具镜像不替换业务镜像，验收后清理容器、网络、卷、工具镜像与临时文件。
复现时准备 HTTP/2 curl 工具镜像，再运行：

```bash
bash docker/tests/tuic.sh
bash docker/tests/tuic-real.sh \
  padm-local/padm-xray:tls-3b4 \
  padm-local/padm-sing-box:tls-3b4 \
  padm-local/padm-ops:tls-3b4 \
  local-http2-curl:test
```

未验公网 UDP 宿主入口、第三方导入 UI、保持打开的长会话、真实 0-RTT 重放行为、
原生 arm64、真实 DNS/整机重启或可信发布；完整用户管理及端口跳跃尚未开放。
3B.4、其余 3C、3D、4A、5C 仍待完成；direct Trojan 交付见 3C.8。

#### 3C.8 Direct Trojan 基础入口

协议 `28` 仅接受 v3，Xray 与 sing-box 首配均选 `11`；副核心首配仍为 Reality Vision。
TCP/TLS 双栈直连，不需要 Nginx 或 fallback；复用受管 TLS/ACME 和现有候选事务。
UUID 同时作为密码与统计账号，跨核心复制仍共享累计流量和额度。
首配、完整规格导入、通用字段编辑、跨核心复制/删除及 `trojan://` 分享链接接入。
服务器地址与 TLS 域名可不同，URI 使用独立 SNI、百分号编码和 IPv6 authority。
TLS 域名、凭据及已有入口身份冻结；删除最后 TLS 消费者清空规格引用，但保留受管证书。
HTTPS 发布仍要求 Xray WS TLS；包含 Trojan 暂拒绝宿主集成，传统 TLS fallback 基础入口见 3C.12。
完整 `management_status` 仍为 `deferred`。

本地验收：固定 Linux 源码快照、可执行 tmpfs、前台 `--init` 工具容器；
`trojan.sh` `71.021` 秒一次包含 TUIC 及全部旧协议基线，setup PTY `183.191` 秒、
phase3 `135.666` 秒通过。覆盖四首配拓扑、取消、字段编辑、同/跨核心复制、身份冻结、
WS/末个 TLS 删除、精确 URI、运行漂移、端口冲突、共享额度及失败恢复/更新/回滚。
Draft 2020-12 Schema 的 6 正例/21 反例、Bash、ShellCheck、JSON 与嵌入 Python 检查通过，
两项独立只读生产审阅无可操作问题。CI 使用 `trojan.sh` 根入口，新增 `docker-trojan` selector。
首轮末 TLS 删除夹具违反主核心冻结合同，补验保留主核心 Reality 后通过，未放宽生产规则。

真实 amd64 `54.229` 秒通过，沿用 3C.2 的固定业务镜像；客户端从实际 URI 解析凭据、
SNI/ALPN/指纹，隔离 CA 严格校验 TLS，未开启 insecure。
两核心各 IPv4/IPv6 的 TCP HTTP 与 UDP-through-TCP echo proof、错误密码拒绝通过；
Xray/sing-box UUID 实际上/下行计数均为 `186/336`。
生产额度事务撤销两核认证后全部请求拒绝且源站计数不增，解除后同一客户端恢复，
两核 `users.base` 哈希不变，恢复精确增加源站 TCP/UDP 各 4 次。
测试适配初版漏掉生产 `dockerComposeRun` 的 stdin 保护，导致统计循环漏采；
补回 `</dev/null` 并断言两核查询完整后重跑通过，`lifecycle.sh` 既有修复保持不变。
非 root、只读根、cap drop、init、健康检查和权限保持，未发布宿主端口。
第 4 参数的 HTTP/2 curl 临时工具镜像 ID 为
`sha256:1cd9dcda948bceebc8eeca8c959c720ea9bb8e9102471c719970869ab0f0edc0`，
只用于验收，不替换业务镜像，验收后清理容器、网络、卷、工具镜像与临时文件。
复现时准备工具镜像，再运行：

```bash
bash docker/tests/trojan.sh
bash docker/tests/trojan-real.sh \
  padm-local/padm-xray:tls-3b4 \
  padm-local/padm-sing-box:tls-3b4 \
  padm-local/padm-ops:tls-3b4 \
  local-http2-curl:test
```

独立服务器/SNI 仅通过合同与输出检查，真实测试入口与 TLS 同域。
未验公网宿主入口、第三方导入 UI、既有长会话、原生 arm64、真实 DNS/整机重启或可信发布；
3B.4、3D、4A、5C 仍待完成。

#### 3C.9 VMess WS TLS 基础入口

协议 `22` 仅接受 v3 和 Xray，沿用 `websocket` 字段、Nginx 反代、受管 TLS、
UUID 流量账号和每入口内部 `backend_port`/`tls_port`。`alterId` 固定为 `0`，
不接受额外字段；首配选项为 `12`，单核心首配不生成 Reality 密钥，不开放单协议 HTTPS 订阅。
首配、完整 v3 规格导入、入口/WS 路径编辑、同核复制/删除和 `vmess://` 本地分享链接已接入；
复制会重新分配未占用的内部端口，跨核心复制、宿主集成和完整管理仍拒绝。
协议 21 与 22 可共用 Nginx/TLS，订阅发布仍只由 21 触发；删除最后 21 时关闭发布，
删除最后 22 时在没有其它 TLS 协议的情况下清理规格中的 `tls`。

本地 Linux 协议基线 `vmess.sh` `176.837` 秒一次包含全部旧协议，
覆盖合同/生成拓扑、精确 URI、漂移检测、共享额度、混合端口池、TLS 删除和失败恢复。
Draft 2020-12 Schema 的 6 正例/30 反例，Bash、ShellCheck、JSON、内嵌 Python 和 CI 工作流检查通过。
菜单 PTY `395.400` 秒、phase3 `248.473` 秒通过；覆盖单/双核心首配、取消、编辑、
复制/删除、身份冻结、TLS/健康失败恢复、支持矩阵及 bundle 兼容性。
最后定向补验确认合法 VLESS+Fail2ban 基线可用，混合 VMess 宿主集成被拒绝；
混合入口重复内部端口及尾换行也均拒绝。两项独立只读生产审阅无可操作发现。

真实 amd64 `47.838` 秒通过：沿用既有 Xray、sing-box 客户端、ops 和 Nginx 镜像，
客户端从实际 `protocol links` 解析 VMess Base64 字段，严格校验隔离 CA 与 SNI，
双栈 TCP HTTP/UDP-over-WS proof、错误 UUID 拒绝、UUID 实际上/下行计数 `184/332`。
生产额度事务撤销认证后全部请求拒绝、源站计数不增，解除后同客户端恢复，
`users.base` 哈希不变，非 root/只读根/cap drop/init/健康与文件权限保持。
未发布宿主端口，测试容器、网络和卷自动清理；复现：

```bash
bash docker/tests/vmess.sh
bash docker/tests/vmess-real.sh \
  padm-local/padm-xray:tls-3b4 \
  padm-local/padm-sing-box:tls-3b4 \
  padm-local/padm-ops:tls-3b4 \
  padm-local/padm-nginx:tls-3b4
```

验收同时修正共享生成器的 jq 1.6 对象合并括号，以及尾换行绕过 `$` 的公共规格校验；
字符串控制字符统一拒绝，域名/名称/入口 ID/WS 路径的 Schema 使用绝对结尾约束。
真实测试仅调整本地 Compose `pull_policy` 和启动顺序，保持生产验签及配置合同；
`lifecycle.sh` 无本阶段差异，既有 stdin 修复来自代理。
公网入口、第三方导入 UI、既有长会话、原生 arm64、真实 DNS/整机重启、可信发布、
协议 22 独立 HTTPS 发布和完整管理尚未验收；3B.4、其余 3C、3D、4A、5C 仍待完成。

#### 3C.10 VMess HTTPUpgrade TLS 基础入口

协议 `23` 仅接受 v3，Xray 与 sing-box 首配均选 `13`，副核心首配仍为 Reality Vision。
复用 Nginx、受管 TLS/ACME、UUID 流量账号和候选事务；独立 `httpupgrade` 对象只接受
`domain/path/backend_port/tls_port`，路径为 8–64 位安全段，生成 `/path` 不附加 `ws`。
两核心固定 `alterId=0`，Nginx 按入口核心反代、依赖实际后端，HTTPUpgrade Host 固定受管域名，
兼容合法大小写域名；既有 WS 的 `$host` 行为不变。
首配、完整 v3 规格导入、通用字段/路径编辑、同核及跨核心复制/删除和分享链接已接入。
复制按目标核心监听/API 端口避让，TLS 端口在全部 Nginx 入口中全局唯一；
已有 UUID、核心归属、TLS 域名、协议类型和内部端口冻结，同 UUID 共享累计及额度。
单协议 23 不发布 HTTPS 订阅；含协议 21 的混合部署可发布三类链接。
删除最后 21 关闭发布，保留其它 TLS 消费者的规格引用；宿主集成和完整管理仍拒绝。

真实 Linux amd64 两核心依次验收共 `101` 秒，VMess WS 原 4 参数兼容复验 `53` 秒通过。
客户端从实际 `protocol links` 的 Base64 JSON 解析认证、传输、路径、Host 与 SNI，
使用隔离 CA 严格校验 TLS；合法大小写域名、双栈 TCP HTTP/UDP 隧道、错误 UUID 拒绝通过。
两核心实际 UUID 上/下行计数均为 `184/332`；生产额度事务拒绝所有请求且源站计数不增，
解除后同一客户端恢复，两核心 `users.base` 哈希不变，非 root/只读根/cap drop/init/健康与权限保持。
业务镜像沿用 3C.2；第 5 参数 `padm-regression:local` 仅提供 HTTP/2 curl 工具，
sing-box 统计在隔离容器网络查询并复用生产 protobuf 解析，未替换业务镜像或放宽生产门禁。
全部临时业务容器、网络及命名卷自动清理，不发布宿主端口；复现：

```bash
bash docker/tests/httpupgrade.sh
bash docker/tests/httpupgrade-real.sh \
  padm-local/padm-xray:tls-3b4 \
  padm-local/padm-sing-box:tls-3b4 \
  padm-local/padm-ops:tls-3b4 \
  padm-local/padm-nginx:tls-3b4 \
  padm-regression:local
```

本地完整协议基线 `210.345` 秒、菜单 PTY `479.896` 秒、phase3 `268.507` 秒通过；
覆盖两核心合同、旧版/bundle 拒绝、漂移、混合发布、跨核心端口池、TLS 删除及失败事务。
菜单覆盖四种首配拓扑、取消、路径/通用编辑、复制删除、身份冻结和 TLS/健康失败恢复。
首轮混合发布断言漏列正确的 `subscription` 依赖；仅修测试后定向检查和根回归均通过，未放宽生产合同。
Draft 2020-12 Schema `6` 正例/`52` 反例、Bash、ShellCheck、JSON、内嵌 Python AST 和 CI actionlint 通过。
两项独立只读生产交叉审阅无可操作问题；CI 使用 `httpupgrade.sh` 根入口只串接一次旧协议基线，
新增 `docker-httpupgrade` selector，复用缓存 Linux 工具层和源码快照并行验证，不挂 Windows 源码目录。
公网宿主入口、第三方导入 UI、既有长会话、原生 arm64、真实 DNS/整机重启及可信发布未验；
3B.4、其余 3C、3D、4A、5C 仍待完成，`lifecycle.sh` 无本阶段差异。

#### 3C.11 VLESS/Trojan gRPC TLS 基础入口

协议 `24`/`25` 仅接受 v3 和 Xray，首配分别选 `14`/`15`；副核心首配仍为 Reality Vision。
独立 `grpc_tls` 合同固定为 `domain/service_name/backend_port/tls_port`，
服务名只接受 1–64 位字母、数字、下划线或连字符；单核首配不生成 Reality 密钥。
默认后端端口为 `31301`/`31304`，Nginx TLS 监听默认 `8443`，不依赖原生 fallback/PROXY 拓扑。
Nginx 明确启用 `http2 on`，按 `/service_name/` 前缀 `grpc_pass` 到 Xray，不重写 gRPC 方法路径；
Host 固定受管域名，关闭请求体大小限制并将 body/read/send 超时设为 `5d`。
公开双栈入口仅映射到 Nginx，核心 gRPC 后端不暴露宿主端口，TLS 文件只挂载到终止 TLS 的服务。
首配、完整规格导入、通用字段和服务名编辑、同核复制/删除及两类分享 URI 已接入。
链接保留 `type=grpc/serviceName/alpn=h2` 与 TLS SNI，复用 UUID 身份、累计和额度。
复制按 Xray 监听/API 端口避让，TLS 端口与 WS/HTTPUpgrade 共用全局池；已有内部端口和身份冻结。
单协议 24/25 不发布 HTTPS 订阅；含协议 21 的混合部署可发布其链接；
删除最后 21 关闭发布，保留 gRPC TLS 的规格引用；宿主集成、sing-box 和完整管理继续拒绝。

本地根回归 `219.575` 秒通过，只串接一次此前协议基线，覆盖两协议严格合同、旧版/bundle 拒绝、
生成/Nginx HTTP/2/URI/漂移、混合 21–25 与直接入口端口池、共享额度、TLS 删除及失败/更新/回滚。
Draft 2020-12 Schema `6` 正例/`68` 反例、Bash、ShellCheck、JSON、内嵌 Python AST 和 CI actionlint 通过。
Schema 首轮验证脚本遗漏 IPv4/IPv6 `format_checker`，补齐后通过，未改生产合同。
菜单测试首轮发现预期入口 ID/名称漏写 `-tls`，仅修断言并替换源码快照。
phase3 `239.356` 秒、菜单 PTY `503.252` 秒通过。
菜单覆盖两协议各单/双核心首配、取消、通用字段与服务名编辑、同核复制、跨核拒绝、
既有身份和新增异协议冻结、删除副本、独立发布拒绝及 TLS/健康失败恢复。
两项限定范围的只读生产交叉审阅无可操作问题。
真实 Linux amd64 的 24/25 与 VMess WS 原 4 参数兼容顺序验收共 `147.075` 秒通过。
客户端从实际 `protocol links` 解析认证、SNI、`alpn=h2` 和服务名，隔离 CA 严格校验 TLS；
两协议各双栈 TCP HTTP/UDP 隧道、错误凭据拒绝、UUID 上/下行 `184/332` 和同客户端额度拒绝/恢复通过，
额度拒绝期间源站计数不增，`users.base` 哈希保持，业务服务非 root/只读根/cap drop/init/权限/健康不变。
业务镜像沿用 3C.2，无 HTTP/2 curl 额外参数；原 VMess/HTTPUpgrade 参数合同保留。
VLESS 客户端显式 `packet_encoding=xudp` 以最终源码快照定向复验 `47.445` 秒通过；
该两行仅在测试客户端中，未修改协议 URI 或生产生成器。
临时工具容器仅为真实测试挂 Docker socket，所有业务容器、网络及命名卷已按独立标签自动清理，
未发布宿主端口；前两次并行回归容器被误停或回收，结果无效，顺序独立重跑后 phase3 通过，
未据此修改生产合同或回归入口。复现：

```bash
bash docker/tests/grpc-tls.sh
bash docker/tests/grpc-tls-real.sh \
  padm-local/padm-xray:tls-3b4 \
  padm-local/padm-sing-box:tls-3b4 \
  padm-local/padm-ops:tls-3b4 \
  padm-local/padm-nginx:tls-3b4
```

CI 根入口改为 `grpc-tls.sh`，新增 `docker-grpc-tls` selector；复用共享工具镜像和独立源码快照。
公网宿主入口、第三方导入 UI、既有长会话、原生 arm64、真实 DNS/整机重启及可信发布仍未验。
3B.4、3D、4A、5C 仍待完成；传统 TLS fallback 基础入口见 3C.12，`lifecycle.sh` 无本阶段差异。

#### 3C.12 VLESS TCP TLS Vision / Trojan TCP TLS fallback 基础入口

已完成基础入口交付与验收；协议 `27`/`29` 仅接受 v3 和 Xray。
两类入口共享严格 `fallback_tls` 合同：`domain/http_port/http2_port`，
默认后端端口为 `31300`/`31302`，域名必须等于受管 `tls.domain`。
入口由 Xray 直接终止 TLS，公开双栈端口映射到自身 `public_port`；
协议 27 使用 VLESS `xtls-rprx-vision`，协议 29 使用 Trojan TCP TLS，不额外增加 VLESS 前端。
两协议 TLS ALPN 固定为 `h2/http/1.1`，默认 fallback 转到 `nginx:http_port`，
协商 `h2` 时转到 `nginx:http2_port`，两条回落均固定 `xver=1`。
Nginx 通过两个独立监听接收 PROXY v1，只有 HTTP/2 后端启用 `http2 on`；
后端端口、WS/HTTPUpgrade/gRPC 的 TLS 端口和健康端口 `8080` 共用全局冲突检查。
公开端口仍按宿主全局唯一，核心监听和 API 端口按实际核心网络空间避让。
仅 fallback 的 Nginx 不发布宿主端口、不挂载 TLS 私钥，也不依赖核心；
混合 WS/HTTPUpgrade/gRPC 时只依赖实际反代核心，核心不反向依赖 Nginx，避免 Compose 依赖环。
fallback 提供最小静态首页：优先读取已有 `data/static/index.html`，缺失时返回内联默认页，
其余路径只读取受管静态目录；本阶段不写入或替换静态内容，也不宣称站点/302/ALPN 管理完成。

首配、完整规格导入、通用字段编辑、同核复制/删除与分享 URI 同步接入；
既有身份、TLS 域名和内部后端端口冻结，复制共享原完整后端端口对并去重；
完整规格可使用其它端口对，但部分共享或交叉冲突拒绝，UUID 共享额度保持。
协议 27 链接包含 TCP、TLS、Vision flow、SNI 和 ALPN；29 包含 Trojan、TCP、TLS、SNI 和 ALPN。
单独 27/29 不开放 HTTPS 订阅，组合协议 21 后可发布其节点链接；
宿主集成、sing-box、跨核心复制、站点内容管理和完整协议管理仍不接受。

验收已覆盖两类严格合同、旧版/bundle 拒绝、生成/URI/漂移、Nginx PROXY/分监听 HTTP/2、
同域混合 21–29 端口池、共享额度、TLS 删除及配置/更新/回滚失败恢复；
菜单验证单/双核心首配、取消、通用编辑、复制删除、身份冻结和失败事务。
真实 amd64 已以当前锁定业务镜像执行严格 CA/SNI、双栈代理连接、
普通 HTTPS 的 HTTP/1.1 与 HTTP/2 静态回落、错误凭据拒绝、UUID 正统计及同客户端额度拒绝/恢复。
Docker Linux 最终定向回归 `docker-traditional-tls` `109.543` 秒通过，
证据 `.tmp-regression-docker-2d4acdcded4d4b6b8e0ac5f4392e82d0`；
菜单 PTY `252.249` 秒通过，证据 `.tmp-regression-docker-030f446bd92d42d184432cc1b845e9e1`。
phase3 首轮前序事务已执行，末项 profile 断言漏列 27/29；补齐后定向执行原矩阵正反例通过，
不把初次失败计为整套通过。最终 Bash/ShellCheck、Draft 2020-12 Schema `4` 正例/`50` 反例通过，
证据 `.tmp-padm-traditional-verify-9f7936a6163a4dce89f48edb3275bb88`。
共享 TLS 消费者修复拒绝 inline/include、秘密来源别名及 Nginx 主配置覆盖：
明文 fallback 仅接受受管生成配置及三组精确 bind 来源/目标/读写权限，重复或额外挂载拒绝。
目标覆盖、只读改写、重复、volume 类型反例均通过；TLS/续期兼容回归 `11.796` 秒通过，
证据 `.tmp-regression-docker-ab1716f185b6469ebfffd5295810251f`。

真实 amd64 27/29 及旧 24/25、默认 22 的顺序验收共 `277` 秒通过，
证据 `.tmp-padm-traditional-verify-10c57608358c47fc892fcd7b0a330f46`。
各协议严格 CA/SNI、双栈 TCP/UDP 隧道及错误凭据拒绝通过，实际 UUID 上/下行 `184/332`；
27/29 的默认首页、既有静态首页、缺失资源 404、HTTP/1.1/HTTP/2 协商及 PROXY 客户端来源均通过，
额度拒绝/恢复保持同一客户端和 `users.base` 哈希，拒绝时源站计数不增且静态回落仍可用。
业务镜像沿用 3C.2，第 5 参数只提供支持 HTTP/2 的 curl 工具镜像；
夹具初次漏调生产 `dockerEnsureRuntimeDataPermissions` 导致静态目录读取失败，补齐权限收尾后通过，
未改变生产权限。真实快照早于最后挂载守卫收紧；配置生成与真实夹具一致，守卫由上述最终定向验收覆盖。
CI 根入口改为 `traditional-tls.sh`，新增 `docker-traditional-tls` selector，只串接一次旧协议基线。
复现：

```bash
bash docker/tests/traditional-tls.sh
bash docker/tests/traditional-tls-real.sh \
  padm-local/padm-xray:tls-3b4 \
  padm-local/padm-sing-box:tls-3b4 \
  padm-local/padm-ops:tls-3b4 \
  padm-local/padm-nginx:tls-3b4 \
  local-http2-curl:test
```

临时控制容器及隔离业务项目、网络、卷已自动清理，未公开宿主端口；`lifecycle.sh` 无本阶段差异，
既有 stdin 修复来自代理。公开协议基础入口均已接入，但 3B.4、3D、4A、5A、5C 和完整管理仍未完成。
公网宿主入口、第三方导入 UI、既有长会话、原生 arm64、真实 DNS/整机重启及可信发布仍需独立验收。

### 3D. 协议管理与入口维护

- Reality：目标检测/扫描、候选库、黑名单、PQC 状态、参数重生成；
  不把目标可探测直接等同于具备 PQC 能力。
- XHTTP、Hysteria2、TUIC：迁移原生参数管理与链接更新，参数失败可恢复。
- 入口端口追加/移除、核心内部端口以及 Reality 443 共存：明确入口归属，
  原子更新核心和 Nginx，关闭共存时恢复端口，不影响无关监听器。
- 每个协议的管理验收清单包含原生对应工作流；端口跳跃等跨阶段项仍缺失时，
  保持相应 `management_status` 为 `deferred` 并说明已经交付的子能力。

验收：参数修改和链接一致；扫描失败、坏目标、端口占用、核心/Nginx 更新失败可恢复；
共存启用和关闭各有连通验证。完整管理状态只在全部对应工作流通过后升级。

#### 3D.1 Reality 参数重生成

菜单 `协议与入口` 第 4 项及 `edit --regenerate-reality <入口 ID>` 已接入，
只接受受管规格中的已有协议 `1`、`2`、`26`；支持 Xray/sing-box Vision/gRPC 与 Xray XHTTP。
当前部署的可信发布和镜像校验完成后才生成新私钥、公钥及 8 字节 short ID，
公钥须由新私钥经 RFC 8410/OpenSSL 独立派生并匹配，任一参数未更新则拒绝。
秘密经 `0600` 文件和 stdin 传递，不进入进程参数或预览输出。
普通编辑仍冻结密钥；重生成不能和 `--spec` 组合，精确保护指定三字段之外的规格。

复用候选配置、确认、备份、健康检查与恢复事务，保留 UUID、目标/SNI、端口、
其它入口、证书和流量额度；分享 URI 与已启用 HTTPS 发布只更新选中入口。
`--preview` 不启动候选或写入部署，确认后的生成是一次新命令，不沿用预览的秘密。
`edit` 保存 `configure.*` 配置快照，失败恢复使用该快照；公开 `rollback`
只选择 `update.*` 更新快照，不宣称编辑可用该命令撤销。

定向 `docker-reality-parameters` 接入 selector 与 CI；包含原 Reality/protocol 基线，
新增双核心 5 入口、精确规格/核心/URI/发布、额度保持、生成及签名拒绝、手工密钥拒绝、
缺失规格、取消/EOF/INT/TERM 和健康失败恢复断言。
真实 `reality-parameters-real.sh` 调用生产重生成 helper 与生成器，
验证 Xray XHTTP、sing-box gRPC 新凭据可用、旧凭据拒绝，以及未选 Xray gRPC 和账号状态保持；
它不执行完整 CLI 可信发布与切换事务，不能替代真实生产服务器验收。
该子功能升级为 `supported`，完整协议管理继续 `deferred`；目标库/扫描/PQC 见 3D.2，443 共存后续实施。

Docker Linux 定向回归 `54.124` 秒通过，证据 `.tmp-regression-docker-236548ec663440438d77116d6ed304d5`；
菜单 PTY `12.889` 秒、首配/编辑 PTY `198.933` 秒通过。
真实 amd64 `41.540` 秒通过，证据 `.tmp-padm-reality-verify-65ae322c2f5e4fa9990a7c3e7f78c52d`；
新凭据的 3 条 URI 请求获得源站 proof，两个旧凭据客户端先确认 SOCKS 可用后请求被拒绝。
初次定向误用仅选择更新快照的公开回滚命令，改用真实配置恢复函数后通过；
初次真实夹具结果汇总漏局部变量，修正后重跑通过，不把初次失败计作通过。
测试隔离项目、网络、卷及控制容器已清理，无宿主端口发布；`lifecycle.sh` 无本阶段差异。
最终 Bash/ShellCheck、JSON 与矩阵正反例通过，证据 `.tmp-padm-reality-static-cf7374a8e6f34d30bf7fcbf0636610d7`；
phase3 整套 `73.192` 秒通过，新增矩阵状态反例另在最终静态快照中通过，actionlint 通过。
混合工作区 `ci` 的原生核心安装失败场景失败，不覆盖其它任务改动；
`HEAD` 基线加本阶段 14 文件的隔离 `ci` `19.137` 秒通过，证据 `.tmp-reality-stage-ci-e31582fce8654442a49c726be3102476`。

```bash
bash docker/tests/reality-parameters.sh
bash docker/tests/reality-parameters-real.sh \
  padm-local/padm-xray:tls-3b4 \
  padm-local/padm-sing-box:tls-3b4 \
  padm-local/padm-ops:tls-3b4
```

#### 3D.2 按当前原生对齐目标站管理

基础管理已签名提交 `03c18d1c`；本轮重新核对原生实际源码，
8 项管理入口及刷新范围已一致，差异补在首配候选选择和扫描运行流程。
首配默认“检测候选后选择”，先验签并准备发布镜像，在临时库检测全部候选，
仅显示本次 `cdn_risk=no` 的实测 A 级；筛选、分页及候选内手动输入共用原生函数。
另提供 `host[:port]` 手动分支，端口默认 `443`、SNI 默认目标域名。
候选等待不持部署锁，不生成账号或启动 Compose；返回、EOF 和最终取消
删除本次私密快照，不写持久目标库，最终提交前仍在锁内检查未配置并复测目标。
Docker 删除重复扫描批次调度，复用原生进度、部分有效结果导入和无结果失败批次继续；
共享扫描等待先终止并等待本次进程组，再清理临时目录，保留原 trap、作业模式和其它后台任务。
手动安全 B/C 目标显式提示评级与原因，不把手动规则收紧成仅 A。

对齐依据是当前 `manageRealityTarget` 和 `shell/core/reality_targets.sh`，
不再采用旧三项目标菜单。Docker `协议与入口` 第 5 项提供同一套 8 项操作：
检测当前目标、刷新目标库、扫描指定网段、同 ASN 抽样扫描、查看/切换 A 级目标、
手动 `host[:port]` 与独立 SNI、查看黑名单、返回。
刷新子菜单区分“目标库 + 推荐候选”和“推荐候选”；检测后可切换 A 级目标或确认加入黑名单。

直接复用原生候选、16 列结果格式、全部 A/AAAA 最差评分、CDN/CNAME/ASN 风险、
分页筛选、扫描结果二检及 ASN 均衡唯一抽样，不复制评分算法。
普通目标库只保存 `cdn_risk=no` 的 A 级结果；A 要求 TLS 1.3、
X25519MLKEM768 及证书链长度大于 `3500`，安全 B/C 仅允许手动设置。
当次失败复测移除旧 A，未复测旧记录保留；当前内置 25 个候选不是部署网络实时可用保证。
PQC 显示来自实际 TLS 检测；ML-DSA 只读当前 Xray 配置，不声称自动启用。
扫描器复用原生官方发布元数据与摘要下载，容器只挂载本次结果目录和只读二进制，
不挂载部署目录或 Docker Socket，不授予额外 capability。

共享源码在隔离子 shell 载入，检测、刷新和扫描不调用原生安装/配置/订阅写链。
目标库仅写 `/etc/padm-docker/data/reality-targets`，目录 `0700`、文件 `0600`，
写操作持独立 `flock` 并通过临时库原子发布；交互等待不占部署锁。
探测和扫描有时限及私密 CID，Ctrl-C/TERM/超时退出只清理本次容器和目录。
控制包条件携带共享 runtime 与算法，缺失依赖在安装前拒绝，旧无此能力的包仍保留原兼容路径。

切换按入口 ID 调用独立已安装 CLI `edit --reality-target`，重新读取最新受管规格、
验签当前部署发布并在线复测；不把缓存 A 级当成切换授权。
复用候选确认、配置快照、健康检查和中断恢复，只改变目标 host、port、SNI；
其它入口、账号、密钥、TLS、累计流量与额度保持，分享链接及已启用发布同步更新。
`protocol` 同时提供目标状态、检测、库刷新/分页、黑名单和扫描命令。

本地 Linux amd64 定向：目标库/原生算法 `12.816` 秒，
完整目标站/独立 CLI 事务 `87.123` 秒、菜单 PTY `16.156` 秒、首配/编辑 `214.052` 秒通过。
目标站回归覆盖 A/B/C 与最差 AAAA、DNS/CNAME/ASN/Cloudflare 风险拒绝、库只存 A、
缓存选择重新复测、确认前取消及切换后 INT/TERM/健康失败恢复、秘密与逐 CID 清理；
菜单覆盖 8 项操作、刷新范围、前台输入、取消、EOF 和中断。
证据分别为 `.tmp-regression-docker-08197563b50043b8b802b328cf9e7d0b`、
`.tmp-regression-docker-ce6da0175830428fa8177edea74d08a3`、
`.tmp-regression-docker-8b35cd71031a4638acb66cd0a1f30f46`、
`.tmp-regression-docker-7a69597305ae4207bb62974bea12318e`。
Docker/签名/网络边界仍使用桩，不能代替部署网络、真实公网扫描、可信发布或原生 arm64 验收。
该子能力为 `supported`，443 共存和完整协议 `management_status` 继续 `deferred`。

整合收尾：`docker-contracts -Jobs 2` 全套 `342.320` 秒、exit `0`，
包含目标库 `14.103` 秒、目标站事务 `90.200` 秒、菜单 PTY `15.640` 秒、
首配/编辑 `230.044` 秒及 phase3/phase4/更新回滚全部通过；
证据 `.tmp-regression-docker-5acb4ccf091f4fc0ac0041789e7f2902`。
修复旧 schema 1 缺少 `listener_id` 的兼容，旧规格仍执行完整风险检测，
同步配置夹具的 DNS/CNAME 和风险桩，未修改 `lifecycle.sh`。
最终相关生产与测试文件均与上述成功快照一致；其后共享 `fetchUrlToStdout`
失败传播改动已用当前快照补跑目标库 `13.729` 秒和完整 `ci -Jobs 3` `35.814` 秒，
均 exit `0`、`cache_hit=false`，证据 `.tmp-regression-docker-71a69b4d34554bbfa9c07743e75bdd05`、
`.tmp-regression-docker-b5732a28a32540bd9b0bae28ba613c3d`。

#### 3D.3 Reality 443 共存

按当前原生功能分步实施，只支持 Xray Reality Vision/XHTTP 的一个默认后端；
3D.3c 已覆盖容器内受管 TLS 入口的共存菜单与事务，不能把它扩写为宿主网站或完整原生管理。

| 检查点 | 状态与交付 |
| --- | --- |
| 3D.3a 镜像前置 | 已通过本地验收；Nginx 安装同版本锁的 `nginx-mod-stream`，加载模块并提供独立 `stream.d`。发布预检覆盖两种架构的模块缺失，刷新上游拒绝主程序/模块 ABI 版本不一致。 |
| 3D.3b 受管拓扑 | 已实现生成合同并通过本地验收；v3 可选共存绑定保留原入口端口和凭据，生成、规格/部署匹配、端口预检及链接统一使用有效公网 443；b 提交保留部署门禁，c 按明确控制包能力开放受管范围。 |
| 3D.3c 菜单与事务 | 已通过本地验收；协议第 6 项及专项 CLI 提供状态、开启、更换与关闭，复用现有编辑事务。先停止本项目旧 443 拥有者，失败按可信备份恢复；更新检查控制包能力与候选 Nginx/core，证书管理严格识别受管 stream 配置及挂载。 |
| 3D.3d1 桥接可达宿主网站 | 已通过 Desktop Linux VM 本地验收；新增互斥宿主网站绑定、多个 SNI、可路由 IP 或 `host.docker.internal:host-gateway`；网站独立维护证书和内容，受管核心与 Nginx 仍使用 bridge。 |
| 3D.3d2 宿主回环与原生验收 | 已实现显式 host 回环合同、候选 TLS/监听检查和端口交接/恢复；Docker Desktop Linux VM（Engine 29.8.2，amd64）真实实流量六阶段通过，原生 Linux、可信发布与公网仍待验证。独立分流服务使用宿主网络，其它服务保留 bridge；站点内容维护仍归 5A。证据 `.tmp-reality-stream-loopback-20261007/result.md`。 |

受管首段复用现有 TLS 入口域名和内部端口，Nginx stream 将网站 SNI 送到本容器
TLS 后端，其余送到选中的 Xray 容器监听；不默认打开 PROXY protocol。
Reality SNI 与网站域名冲突、第三入口占用 443、内部监听冲突、地址族不一致均拒绝。
启用期间保护绑定入口身份、归属和原端口，关闭恢复原映射，未选入口和流量保持。
共存规格须由控制包的明确能力门禁保护，同属 v3 的旧 bundle 不能仅因版本号匹配而接收；
旧无共存字段的规格保持兼容。来源地址不可见的 Fail2ban 组合在完成相应合同前拒绝，
不能把 loopback 来源用于宿主封禁。

3D.3a 本地 Linux amd64：`docker-phase2` `1.165` 秒、`docker-phase5` `8.876` 秒，
集中 `ci -Jobs 3` `36.333` 秒均 exit `0`；Bash 和 ShellCheck error/warning 通过。
本地 Nginx 镜像 `sha256:2bda4256003d12821792263e0f6acfb08d675e38d616031c60a3b9efa2af330e`
在只读、无 capability、非 root 条件下通过默认与 `stream`/`ssl_preread` 配置检查，
旧镜像被 stream 缺失断言拒绝；不是客户端连接或可信发布验收。
证据 `.tmp-reality-stream-prerequisite-evidence.md`；镜像前置不单独改变功能矩阵状态。

3D.3b 使用 v3 可选字段 `reality_stream: {listener_id, website_listener_id}`，
绑定一个 Xray Vision/XHTTP 与一个受管 TLS 入口 `21`–`25`；显式 `null` 只接受 v3，
旧无字段规格保持兼容，同版旧 schema bundle 拒绝新增字段。
两个绑定入口只由 Nginx 发布 `443:15443`，原内部端口及账号不变；关闭投影恢复原映射，
未选入口保持原样。网站域名、地址族、第三入口占用 443 与 Nginx 内部端口冲突均有反例，
宿主集成暂不可组合。候选 Nginx 检查仅临时解析 Xray 主机名，不改变运行后端。
b 提交仅开放生成合同并保留部署门禁，证据 `.tmp-reality-stream-contract-evidence.md`。
c 按控制包的 `x-padm-reality-stream-deployment` 能力开放受管部署：配置和更新在备份、停服前
校验候选 Nginx/core，恢复只信任已验证备份，损坏的部分安装输入不阻断恢复。
已有部署仅按项目与服务标签停止交接核心，首次部署失败则清理整个候选项目，避免遗留副核心或订阅。
协议回归覆盖状态只读、专项草稿精确变化、绑定冻结、精确停服、开关失败、实际 TERM、
更新早拒绝、回滚及受管 TLS 配置/挂载漂移；最终 `docker-protocol` `20.906` 秒、
`docker-phase3` `83.488` 秒、`docker-phase6` `19.359` 秒、集中 `ci -Jobs 3` `35.011` 秒均 exit `0`。
Bash、ShellCheck、Draft 2020-12 schema 元验证与实例格式检查通过，证据
`.tmp-reality-stream-transaction-evidence.md`。
真实 Linux amd64 的网站严格 CA/SNI TLS 1.3、Vision 与 XHTTP 客户端通过 10 个流量阶段；
随机 loopback 端口实际竞争绑定失败，生产交接 helpers 完成 Xray/Nginx 拥有者交接与失败恢复。
仅运行夹具注入网站测试内容，不计作静态网站交付；证据
`.tmp-reality-stream-real-20261007/result.md`。该证据未包含宿主网站、生产发布和公网连通验收。

3D.3d1 扩展 v3 共存绑定为二选一：旧 `{listener_id, website_listener_id}` 保持兼容，
新 `{listener_id, host_website:{domains, address, port}}` 只改变网站分流目的地。
菜单第 4 项和 `edit --reality-stream-host <RealityID> <域名,域名> <宿主可达地址> <TLS端口>`
复用原有专项编辑/确认/失败恢复；原始 Reality 端口、凭据、其它入口与账号流量保持。
最多 16 个唯一、小写、精确 SNI；域名与 Reality SNI 或已有受管 TLS 域名冲突拒绝。
地址只接受 Docker 宿主别名或规范的可路由 IPv4/IPv6 字面地址，不接受通用 DNS、
回环、未指定、链路本地、组播、IPv4-mapped IPv6；端口拒绝 `443`、`15443` 和现有公开监听冲突。
这些是地址类别校验，不保证宿主网站实际监听或防火墙可达，必须分别实测。
纯 Reality 加宿主网站不要求受管 TLS 证书；Nginx 仅透传 TLS，保留独立健康入口，
不接管宿主网站配置、证书或内容。旧 c 控制包缺少
`x-padm-reality-stream-host-website` 能力时，在备份/停服前拒绝新规格、更新及回滚。
宿主回环、显式 host 网络、原生宿主和公网仍留给 3D.3d2 与后续部署验收。

本地 Linux amd64：最终 `docker-protocol` `31.597` 秒、`docker-phase3` `82.739` 秒、
`docker-phase6` `18.321` 秒、强制 `ci -Jobs 3` `37.352` 秒均 exit `0`；
Bash、ShellCheck error、Draft 2020-12/FormatChecker 和独立只读复审通过。
独立网站只发布到 Desktop Linux VM 随机宿主端口，不加入项目 bridge；
网站双域名严格 CA/SNI TLS 1.3 与 Vision/XHTTP 客户端通过直连、开启、重复、更换、
宿主 IPv4 字面地址、坏 Nginx 后重渲染恢复、关闭 7 阶段；网站不被重启，账号与累计流量保持。
Reality 使用独立本地 TLS 目标消除外部网络依赖；公网目标超时日志保留。
前端只发布随机 loopback 端口，客户端使用 bridge 内 Nginx；此证据不代表宿主 443、
公网、IPv6 实流量或完整生产 Apply/Restore/可信 Release，事务拒绝与恢复另由契约回归证明。
证据 `.tmp-reality-stream-host-evidence.md`、`.tmp-reality-stream-host-20261007/result.md`。

3D.3d2 新增显式 `host_website.network_mode:"host"`，只允许 `127.0.0.1` 或 `::1`；
没有该字段的 d1 规格仍拒绝回环地址。菜单第 5 项和
`edit --reality-stream-loopback <RealityID> <域名,域名> <127.0.0.1|::1> <TLS端口>`
复用已有专项预览、确认、绑定冻结与失败恢复。域名、网站端口及现有公开端口冲突规则保留，
非选中入口不能占中继端口 `15443`；选中 Reality 原端口 `443` 仍可使用。

只有独立 `nginx-stream` 使用 host 网络，按选中 Reality 的地址族直接监听宿主 `443`，
将默认 TLS 转发至 `127.0.0.1:15443`；Xray 仅增加此 loopback 发布映射，
原核心配置、API、账号和其它端口不变。WS、HTTPUpgrade、gRPC、fallback、
原受管 Nginx 与订阅服务继续使用 bridge，不扩大原监听范围。
专用 stream 主配置不加载 HTTP，不监听宿主 `8080`，不挂网站证书或内容；
master 以 root 绑定低端口，worker 降至 `10001:10001`，只增加
`NET_BIND_SERVICE/SETGID/SETUID/KILL`，分别用于低端口、降权和向 worker 发送退出信号。

该拓扑要求 rootful Docker Engine `28+`，用于保证 loopback 发布隔离；
旧受管/可路由网站规格不增加此版本要求。Desktop host 网络必须已可用，
脚本不自动修改其设置，不能把 Desktop VM 的回环视为 Windows 的回环。
候选检查逐个 SNI 验证宿主网站 TLS，采用 ops 镜像系统 CA，不新增跳过证书验证开关；
自签或私有 CA 须先完成受信任运行环境部署，测试专用 CA 不能冒充生产可信发布。
确认及可信备份后才停止本项目 `nginx/xray/nginx-stream`，实测绑定 `443` 与
`127.0.0.1:15443` 后安装候选；端口竞争、失败和 TERM 均沿用完整备份恢复。
旧 d1 控制包缺少 `x-padm-reality-stream-host-network` 时，在备份、停服前拒绝规格、更新和回滚。

## 第四步：用户、订阅与服务维护

### 4A. 本机用户、分享订阅与业务备份

- 先定义稳定账号 ID、凭据、协议关联、启用状态、分享组/发布授权、额度和累计流量语义，
  再扩展单用户规格及核心生成器，最后接用户增删改菜单。
- 复用现有流量采集和额度能力；用户变更保持未修改账号的身份、统计基线与额度。
  明确凭据轮换、删除、重建及恢复时的流量处理，不静默重置。
- 实现分享订阅、格式输出、链接查看与复制，以及 CDN/入口地址覆盖和 H3 设置。
  剪贴板或终端输出只包含所选链接/内容，不连带说明文字或下一项输出。
- 独立完善 HTTPS 订阅发布拓扑，让各核心和协议的内容输出与发布入口分开验证；
  无合适 TLS 发布入口时只允许本地输出，不声称已经发布。
- 业务备份定义身份、token、分享组、额度、累计流量与格式版本；
  恢复先预览冲突，明确替换或合并策略以及恢复前新增账号如何保留。
  分享组备份、订阅业务恢复和版本 rollback 使用不同名称及验收，不能互相冒充。

验收：用户 CRUD、启停、额度、统计、分享发布授权撤销及不同客户端输出一致；
重配/升级不丢账号，损坏备份、并发修改和恢复失败保持可恢复状态。

按以下检查点交付，不把协议入口复制当作创建分享用户：

| 检查点 | 交付边界 |
| --- | --- |
| 4A.1 独立账号底座 | v3 可选账号集合、稳定身份与独立认证、入口关联、双核心投影、启停及额度过滤；只通过完整规格配置，不开放 CRUD 菜单或单分享发布。 |
| 4A.2 账号 CLI/菜单事务 | 已交付：新建、名称/关联编辑、复制、启停、删除及凭据轮换；复用候选提交/恢复，未选账号保持，复制生成新身份与凭据，恢复不回退最新累计。 |
| 4A.3 分享组与内容输出 | 已交付分享组 CRUD、账号/入口筛选、独立 token、启停与 token 轮换、纯订阅内容及 HTTPS 链接输出；CDN/入口地址覆盖和 H3 仍待后续阶段。 |
| 4A.4 业务备份恢复 | 已提交 `99ce706c`：账号、组、发布授权、额度、累计和格式版本的备份、冲突预览及 merge/replace 恢复；不以版本 rollback 冒充业务恢复。 |

4A.1 当前实现：v3 可选 `accounts` 接受 1–256 项，每项精确保存
`id/name/enabled/uuid/password/shadowsocks_password/listeners`；旧无字段规格不新增账号。
稳定 ID 为小写 UUID，与认证 UUID、密码和 SS 用户密钥分离；关联现有入口，追加到原自用
账号而不替换其凭据。身份及同类认证凭据唯一，拒绝与自用身份/凭据或 SS 服务器密钥碰撞。
Naive 使用稳定 ID 作为用户名，TUIC 使用认证 UUID 与独立密码，其它协议按认证类型投影。
原生分享组没有独立 token 字段，后续发布授权不得照搬不存在的原生字段。

两核心 `users.base` 保留停用账号及私有映射，和完整 spec 一样为 `0600 root:root`；
运行配置仍按容器权限生成，启停/额度过滤后剥离所有私有映射。
跨核心累计按稳定 ID 归集，凭据轮换不换账目，配置恢复保留最新累计；
全部 SS/Naive 用户被过滤时撤销入站，防止 SS 退化认证或 Naive 拒绝启动。
控制 bundle 必须声明 `x-padm-accounts`，配置/更新/恢复在停服前拒绝不支持的新规格。
普通订阅输出仍保留部署级发布 token；4A.3 新增独立分享组状态文件和 token，
可按账号/入口筛选，支持启停、删除、token 轮换、纯内容输出和受管 TLS 下的
HTTPS 链接查看。CDN/H3、业务备份恢复和多服务器授权仍未交付。

4A.1 本地 Linux amd64：`docker-contracts-fast -Jobs 2` `25.207` 秒、
`docker-phase3 -Jobs 2` `83.734` 秒和集中 `ci -Jobs 3` `42.268` 秒均 exit `0`；
前一轮 system 集合的 phase4/phase6 通过，phase3 旧权限断言修正后单独通过。
真实 Xray `26.3.27` / sing-box `1.14.2` 对旧规格、追加、跨核心、全停用、
凭据轮换和全额度耗尽共 12 组配置检查通过；Bash、ShellCheck error、
Draft 2020-12/FormatChecker 及独立只读审计通过，13 个提交文件与 CI 快照一致。
证据 `.tmp-docker-accounts-core-repaired-5f3c57d2447b457c980df5b0bbfbb0ae/evidence.md`、
`.tmp-regression-docker-ab259d4b8bb54aaf837186e0d03ec99f/result.json`。
4A.2 本地 Linux amd64：`docker-contracts-fast -Jobs 2 -ForceRun` exit `0`，
覆盖 phase1、release、permissions、phase2、menu、phase5、traffic、accounts CLI
和 accounts，证据目录为
`.tmp-regression-docker-c1abee4e5e49456f8a6a0a1568cd72af`；`docker-menu`
和 `docker-accounts-cli` 定向回归也通过。真实客户端认证、arm64、可信发布
和业务备份恢复仍待验收。
4A.3 定向回归：`docker-subscriptions -Jobs 2 -ForceRun` exit `0`，
覆盖分享组创建/编辑/启停/删除/token 轮换、账号/入口筛选、纯内容和 HTTPS 链接输出，
证据目录为 `.tmp-regression-docker-4fefaaee6b7348f5a8465caf8b0163ad`。
`docker-contracts-fast` 中上述订阅、账号和菜单子项均通过；该总集合另因既有
`docker-release` bundle 准备失败而 exit `1`，不作为 4A.3 失败证据。

### 4B. 日常服务与核心维护

- 菜单整合现有状态、日志、健康检查、启停重启、更新、回滚和卸载；
  更新或卸载后的菜单重新核对已安装 CLI/bundle，不能继续使用失效入口。
- 迁移核心预发布试跑与升级风险扫描，使用已验证的候选镜像和独立测试配置，
  不以普通配置检查代替升级评估，不现场构建核心。
- 实现 Xray Geo 数据更新、校验、定时任务和失败恢复；任务有所有权、锁和结果状态。
- 卸载、purge 和凭据替换保留适用的明确确认，菜单不增加生产跳过保护的开关。

验收：菜单与 CLI 的结果及退出码一致；更新失败可退回匹配规格；
Geo/试跑失败不修改生产配置；卸载不遗留本项目调度、不清理外部资源。

#### 4B.1 核心升级评估

菜单第 13 项和 `padm-docker assess` 接入独立评估流程；发布资产参数与 `update`
一致，验签并校验控制 bundle 后预拉取固定 digest 镜像，复用现有更新候选生成器。
评估要求完整受管 spec，旧部署先通过 `edit --spec` 导入，不把缺少前置条件
的 Compose 静态检查当作完整升级评估。

直接加载已有核心模块的只读兼容扫描函数，规则与菜单版一致，不复制或运行原生
安装器。候选实际执行 Xray/sing-box 版本检查和核心配置试跑、Xray 严格校验，
检查已启用的 TLS、Nginx、订阅和宿主集成；未启用项明确标注，风险警告原样显示。
Xray 严格解析用独立未知字段探针确认；候选核心忽略严格模式时显示“未启用”，
不将普通校验通过冒充严格校验通过。
默认使用最新可信发布，预发布须提供匹配且验签通过的发布资产，不现场构建核心。

评估不采集流量、不创建备份、不安装候选、不切换 bundle、不重建或启停生产服务；
结束或取消清理候选副本。客户端公网连通与宿主内核/权限验收仍单独执行。
`core-upgrade-assessment` 按上述合同交付并完成本地/真实 amd64 候选验收；Geo、剩余维护菜单和完整生命周期仍待推进。
定向选择器 `docker-core-assessment` 复用 phase1、release、菜单 PTY、phase3 和 phase6，
覆盖可信 bundle 依赖、菜单分发、结果输出、失败与生产状态保持。

#### 4B.2 Xray Geo 数据维护

本步已交付菜单第 14 项和 `geo status`、`geo update [--version <固定 tag>]`、
`geo schedule <enable|disable|status>`、`geo auto-update`。
仅部署含 Xray 时开放，包括 Xray 主核心或副核心；纯 sing-box 和未配置部署明确拒绝。
菜单输入时不持部署锁，动作经独立已安装 CLI 派发；更新和开启每日更新先确认，
取消、EOF 不派发更新或开启任务，失败及 INT 返回菜单，TERM 清理子进程后退出。

复用原生 `Loyalsoldier/v2ray-rules-dat` 来源，未指定版本先解析最新发布固定 tag，
一次下载两份 Geo 数据及各自 SHA256 文件。两文件摘要、Xray Geo 解析探针和当前
配置校验全部通过后，才提交到 `config/xray/geo`；复用只读 `config/xray` 挂载，
Compose 明确设置 `XRAY_LOCATION_ASSET=/etc/padm/xray/geo`。
未准备完整受管文件的旧部署仍读取镜像 `/usr/local/share/xray` 内置数据；
已有 `data/xray` 挂载不能充当 Geo 来源，也不在下载前切换到空目录。

更新复用部署锁、候选校验、恢复及调度所有权模式，不调用原生安装器，
不轮换账号、订阅或发布镜像；运行时只定向重建 Xray，不启动原本停止的核心。
下载、损坏、解析/配置校验、取消或重建失败恢复旧数据、Compose 和原运行状态。
每日宿主本地时间 01:35 的唯一任务优先 systemd、cron 后备，记录部署 root 归属、
执行锁和结果状态；重复启用不重复添加，卸载只移除本项目调度。

定向回归覆盖固定 tag、两份摘要和解析拒绝、首次路径切换、重复更新、
运行/停止状态、失败/信号恢复、任务归属/互斥/重复启停及菜单 PTY 门禁。
合同、CLI、菜单与定向证据齐备，`geo-data` 按上述边界标为 `supported`。
Linux amd64 工具容器集中 `docker-geo -Jobs 2` 92.384 秒、
`ci -Jobs 3` 42.009 秒通过，源码快照摘要一致，工具镜像直接复用。
真实固定摘要 Xray `26.3.27` 完成双 Geo 探针、默认 `10001:10001` 用户只读访问、
`confdir` 顶层读取与两个损坏文件拒绝；15 个脚本静态检查和源码摘要全部一致。
证据见 `.tmp-docker-geo-4b2-evidence.md` 和 `.tmp-geo-real-20261008/result.md`。
真实发布、公网、原生 arm64、宿主 systemd/cron 与整机重启不由模拟回归代替。

### 4C. 多服务器控制后端

- 不把现有仅提供 GET 订阅文件的 `control_server.py` 当作用户管理或同步后端。
  先定义主控/被控角色、接口、认证、邀请/撤销、版本兼容、同步和失败恢复合同。
- WireGuard 只提供连接前置，不等于控制系统已经存在；
  扩展其引导前先完成所需接口和规则所有权/撤销合同，复用已有集成而非复制原生状态。
  最小控制连接的预检、资源归属、失败恢复和撤销在本步先验收；
  5C 复用该合同扩展完整管理，不作为本步的未来前置。
- 控制接口只走明确的私有控制网络，订阅发布与控制地址分离；
  不开放公网控制回退，不向容器提供 Docker Socket。
- 在已有 Python/ops 和文件状态基础上实现必需后端，再接角色向导和管理菜单。
  先交付一主一被控，再按真实用例扩展多节点；不预建通用 RPC 或消息队列。
- 明确重试幂等、部分节点失败、认证过期及同步版本冲突；
  失败保留各节点原配置和可诊断状态，备份恢复包含角色及同步元数据。

验收：认证/撤销、初始同步、断网重试、版本冲突、部分失败和恢复均有双节点实测；
单节点业务不依赖多服务器服务才能正常管理。

本步按以下检查点交付；只读接口基座不能代替完整多服务器工作流：

| 检查点 | 交付边界 |
| --- | --- |
| 4C.1 私网只读 API | 独立主控状态合同、认证/撤销、版本检查及账号期望值读取；不接 Compose、CLI 或菜单，不写节点配置。 |
| 4C.2 被控端同步事务 | 角色/来源身份、版本与内容冲突、受管账号归属、入口映射、重试幂等、候选应用与失败恢复；保留本机账号和累计流量。 |
| 4C.3 连接与管理入口 | 最小 WireGuard 预检/资源归属/撤销、独立控制服务健康、邀请和角色管理 CLI/菜单、角色与同步元数据备份恢复。 |
| 4C.4 双节点验收 | 真实私网加密连接、认证过期/撤销、初始与重复同步、断网/冲突/部分失败及恢复通过后再升级支持状态。 |

#### 4C.1 私网只读 API

`ops` 镜像新增独立 `control` 入口，公开订阅 `control_server.py` 不变。
后端只读一个显式绝对路径状态文件，合同为 `docker/contracts/control.schema.json`；
所有祖先目录必须 root 所有且不可被 group/other 写入，文件为 root 所有的普通文件、
至多 `0640`，容器默认 `10001:10001` 仅通过受管组取得读取权限。
符号链接、FIFO、坏权限、超过 1 MiB、重复字段和深层损坏 JSON 均拒绝。
账号密码字符集与已有 v3 账号一致，账号、认证 UUID、密码及非空 SS 凭据分别去重；
接口不输出本地监听器，后续由被控端显式映射。
Schema 负责结构，运行时附加节点自引用、凭据唯一、规范整数及目录权限检查。

一主一被控；主控 `node_id`、被控稳定 ID、控制地址、token SHA256、授权开关、
过期 Unix 秒、非负 `revision` 和完整期望账号集合保存为一个原子状态。
仅接受 RFC 1918 IPv4 的 `wg-padm` 实际接口地址，不监听通配、公网或回环地址。
`GET /v1/health`、`GET /v1/desired` 都要求唯一 `Authorization: Bearer <48 位小写十六进制 token>`
和唯一 `X-Padm-Control-Version: 1`，绑定指定被控源地址；不信任代理转发头。
每个请求重新读取状态，撤销、过期和 token 轮换立即生效；监听配置变化返回 `503`，
要求重启服务，不沿用旧地址。健康输出不含 token、摘要或账号凭据，
期望账号只有通过上述认证后返回；查询参数、写请求及未知端点不开放。
错误与日志不回显请求行或秘密，串行请求有 5 秒整体时限，防止持续慢速发包占住服务。

定向 selector 为 `docker-control-api`，并纳入 Docker CI 的 root 合同分片，
不把要求 root 的状态权限检查塞入普通用户执行的原生 CI。
回归工具镜像及该合同分片从官方软件源提供 `python3-jsonschema`，生产后端只用标准库。
当前工具容器回环测试模拟被控源地址，仅证明接口与文件权限；
`wg-padm` 地址校验不证明密钥、路由和加密连通，通用 ops 镜像 health 仅检查工具可启动。
本检查点不接专用服务健康、Compose/CLI/菜单或角色邀请；被控同步事务见 4C.2，
真实双节点连通尚未验收，`subscription-multiserver` 继续 `deferred`。

Linux amd64 最终 `docker-control-api -Jobs 2` 2.016 秒、
`docker-contracts-fast -Jobs 2` 28.657 秒、集中 `ci -Jobs 3` 39.944 秒均 exit `0`。
合同分片与完整 CI 使用同一源码归档摘要，共享工具镜像直接复用；
默认 `10001:10001` 用户只读、坏权限/FIFO/深层 JSON、Bearer/重复头、
授权过期/撤销/轮换、监听改变和慢请求总时限均有断言。
独立只读复审无阻断项；证据 `.tmp-docker-control-4c1-evidence.md`，
真实 WireGuard 和双节点事务验收仍按后续检查点推进。

#### 4C.2 被控端同步事务

`ops` 镜像中的 `control_sync.py` 复用只读 API 的账号校验，宿主内部
`dockerControlSyncApply` 经 `dockerAccountApplyDraft` 接入既有配置事务；
本阶段不开放文件导入或外部同步 CLI/菜单，不提供公网控制来源回退。
v3 root 私有 `spec.json` 的 `control_sync` 保存被控/主控稳定身份、显式入口映射、
上次 `revision`/内容摘要及完整受管账号快照，与候选配置一同备份、安装和恢复。
普通配置不能改变角色、同步归属或入口映射，普通账号动作拒绝修改受管账号。

同步先确认响应版本和双方身份、上次受管快照及入口映射，再检查版本/内容一致性；
旧版本、同版本不同内容、本机漂移、账号/入口身份或凭据碰撞均拒绝覆盖。
只替换属于主控的账号，保留本机账号和累计流量，未映射 Shadowsocks 时不写入其凭据；
同版本同内容重试不重建服务，本机新增账号或期望账号顺序变化也不触发重建。
新版本复用候选生成、校验、备份、安装及 Compose 健康检查；
失败恢复旧规格、角色元数据、账号和配置，不另建一套同步提交路径。

定向 selector 为 `docker-control-sync`，进入 Docker CI 的 root 合同分片。
定向夹具已覆盖规划冲突、幂等、真实候选生成/安装/恢复和私有权限；
核心与宿主动作使用桩，不代表真实容器重建、私网加密连接或双节点验收。
Linux amd64 最终定向回归 6.016 秒、完整 Docker 合同 470.258 秒、
集中 `ci -Jobs 3` 44.173 秒均通过；合同与 CI 的 238 个源码文件内容摘要一致，
工具镜像直接复用。Bash/Python/JSON 静态检查及已有 ops 镜像规划器导入通过。
完整合同入口因会话中断未写结果，已从退出码为 `0` 的容器恢复日志和终态证据；
记录见 `.tmp-docker-control-4c2-evidence.md`，不把恢复记录冒充入口结果。
下一步 4C.3 接 WireGuard 预检/资源归属/撤销、角色邀请、专用服务健康及 CLI/菜单，
再按 4C.4 完成真实双节点验收；`subscription-multiserver` 仍为 `deferred`。

#### 4C.3a WireGuard 归属与撤销底座

先修复现有 `net-wireguard` 的归属缺口，不把部署声明或状态文件存在当作接口归属。
root 私有 v2 标记记录真实 ifindex、公钥和随机接口 alias，预检、健康与撤销核验同一身份；
同名替换、字段漂移、符号链接和不安全权限均拒绝，保留接口及恢复证据。
正常停止和异常退出后恢复使用 `0700` 目录中的 `0600` 启动配置快照，
不按当前已更新的配置清理旧路由；撤销失败不使用无条件接口删除后备。
新启动失败复用 `wg-quick` 自身回滚；标记写入或 alias 失败仅撤销已证明属于本次启动的接口。
INT/TERM 等待启动子进程退出，长期等待子进程随停止清理。

候选配置仍使用自己的秘密输入，另行只读挂载当前运行态归属目录做预检。
旧式 `interface=wg-padm` 标记遇到活动接口时拒绝自动迁移，升级前先正常停止旧容器；
接口不存在时可清理陈旧标记。即使公钥相同，也不能认领未经证明的外部接口。
`docker-wireguard-runtime` 轻量桩与 `docker-phase4` 集成检查覆盖上述行为，
`wireguard-real.sh` 在无网络、只有 `NET_ADMIN` 的独立命名空间使用真实 `wg-quick` 验证。
本步不创建控制连接、邀请或角色，不代替宿主/双节点验收。
最终 Linux amd64 `docker-wireguard-focused -Jobs 2` 14.679 秒、集中 CI 41.820 秒通过，
两轮 240 个源码文件与归档 SHA256 一致，复用工具镜像。
真实现有 net 镜像隔离网络空间 2.940 秒通过，覆盖正常启停、legacy 拒绝、
异常退出恢复、同名替换保护和错误输入回滚；静态与独立复审收口。
证据为 `.tmp-docker-control-4c3a-evidence.md`，不扩大为宿主网络或双节点结论。

#### 4C.3b 独立控制服务健康

`ops` 新增 `control-health --state PATH`，严格拒绝缺失或额外参数。
它先安全读取控制状态，再核对 `wg-padm` 实际 IPv4，限时直连配置中的私网地址和端口；
不使用代理、重定向或 token，严格验证现有未认证请求的 `401` JSON、长度和 `no-store`。
邀请禁用、过期或轮换不影响进程健康；接口、监听配置、状态或响应漂移及服务退出均失败。
连接和请求各有 2 秒上限，持续慢速响应也按整体请求时限终止。

定向回归覆盖真实 `ControlServer`、默认 `10001:10001` 用户、入口参数拒绝、
实际接口缺失、授权变更、坏状态、坏响应、超量、重定向、chunked 和慢响应。
私网路由及接口结果仍由工具容器回环模拟，不替代真实 WireGuard/双节点验收。
本步不接 Compose、角色或外部 CLI/菜单；`subscription-multiserver` 保持 `deferred`。

#### 4C.3c 主控期望值与恢复事务

v3 私有规格的 `control` 保存主控身份、监听、单 Peer 授权及发布版本/摘要，
与 `control_sync` 互斥；普通配置不得改变该元数据，当前仅内部控制事务可以初始化角色。
复用已有账号候选事务生成 `config/control/state.json`，只投影 API 账号字段，
按稳定 ID 规范化；账号重排和本机监听映射不改变摘要，内容改变才递增版本。
预览和未安装候选不更新在线规格，规范化后的候选规格是后续渲染与校验输入。

独立 Compose `control` 服务只读挂载该目录到 `/etc/padm/control`，不读取整个规格。
目录为 `0750 root:10001`，状态为 `0640 root:10001`，规格继续 `0600 root:root`；
host 网络、UID `10001`、`cap_drop: ALL`、无端口发布，依赖 `net-wireguard` 健康，
使用 4C.3b 的专用检查。`host-control` 监听纳入端口冲突、部署归属及规格一致性核验。
旧控制 bundle 缺少能力声明时，在更新或恢复前拒绝，不能保留字段却丢失服务。

备份、更新和恢复包含控制状态，并验证其与私有规格、账号摘要一致。
失败、INT/TERM、部分安装和显式版本回滚不能直接复制旧发布序号：
先验证备份，综合已验证在线规格、原候选及此前恢复计划的最高版本；
恢复同内容使用最大版本，恢复不同内容再加 `1`，同版本不同内容拒绝，不修改历史备份。
在线规格损坏或版本下限缺失时拒绝覆盖；恢复未完成保留候选和版本计划，
新进程发现残留计划时拒绝再次发布，读状态及停止服务仍可用。

`docker-control-state` 覆盖规划、角色冻结、Compose/权限、端口及旧 bundle 门禁、
预览、失败/信号恢复、部分安装、恢复复制窗口重试、跨进程残留门禁、
显式回滚和临时目录清理；默认合同分片纳入该项。
实际 Linux amd64 隔离网络空间健康 0.755 秒通过：真实 `wg-padm` 地址、
默认 UID、零有效能力、地址移除及服务退出拒绝。该检查不验证 Peer 加密连通。
同时修复 Python HTTPServer 对私网地址做反向 DNS 的启动等待，改用已验证字面地址。
本步不开放角色、邀请或外部同步 CLI/菜单，完整多服务器继续 `deferred`。

#### 4C.3d1 角色状态与主控初始化

`control status [--json]` 仅投影角色、身份、监听、Peer 地址、版本和主控服务健康，
不输出摘要、账号或凭据；未初始化和既有被控角色的服务健康为 `null`。
`control init --address <RFC1918 IPv4> --port <1024..65535> --peer-address <RFC1918 IPv4> [--yes]`
仅接入已运行、归属一致的受管单 Peer WireGuard，核对真实监听地址与唯一 Peer `/32` AllowedIPs。
拒绝覆盖既有主控/被控身份；生成新身份和已关闭、过期的占位授权，随机凭据仅保存摘要。
复用账号候选事务，失败或信号中断保留旧规格及必要的恢复计划。

菜单新增“控制连接”，参数输入可返回；确认只在 CLI 一处。
初始化子进程共用前台进程组，避免后台 `read` 收到 SIGTTIN；
健康/归属探针限时执行，不长期占用部署锁。
不生成 WireGuard 配置、接口、密钥或路由，不开放邀请、被控接入或外部文件导入。

#### 4C.3d2 单 Peer 邀请、轮换与撤销

`control invite --output <绝对路径> [--expires-in <秒>] [--yes]` 同时用于首次授权与轮换；
有效期为 `60–604800` 秒，默认 `86400` 秒，新 token 使旧 token 立即失效。输出必须位于受管部署目录外，
父目录链 root 所有、无符号链接且不可被组/其他用户写入。同目录私有临时文件经原子链接交付，
已有文件、目录与链接均拒绝覆盖，邀请为 `0600 root:root`。
原始 token 只写邀请文件，不进入普通输出、日志、argv 或 spec；spec 只存摘要。
邀请交付后重取部署锁，复核身份、监听、Peer 和原授权，避免并发轮换互相覆盖。
交付后的文件在失败或信号退出时仍保留，但是否生效须查看脱敏状态。

`control revoke [--yes]` 禁用并过期授权，不依赖网络健康；重复撤销不重建服务。
锁内先原子替换 API 状态，再替换私有规格，不进入配置、Compose 或 WireGuard 重建。
写入中断只允许补齐开关与过期时间；身份、token 摘要、账号和版本漂移仍拒绝。
同文件系统门禁避免 `mv` 退化为复制；本步覆盖进程中断，不证明掉电后的持久化顺序。
菜单提供“邀请或轮换凭据”和“撤销授权”，只在 CLI 确认一次；
状态增加授权开关与过期时间，不输出凭据或摘要。
账号版本不能证明授权先后，因此恢复、事务失败回滚与显式版本回滚均强制禁用授权，
完成后重新邀请。恢复复制直接使用禁用后的规格和控制状态，不先安装备份中的旧授权，
避免存活服务在复制窗口内接受已撤销 token；备份不改写，账号版本仍按既有下限规划。

本步不开放被控接入或同步客户端，不以本地合同通过替代双节点加密连通验收。
4C.3 后续接被控接入、私网同步客户端及角色恢复管理；完成后进入 4C.4。

#### 4C.3d3 被控接入与手动私网同步

`control join --invite <私有文件> --listener <入口 ID>... [--yes]` 仅允许未初始化的角色，
先认证取得期望账号，再通过同一账号候选事务初始化被控身份、入口映射并完成首轮同步。
`control sync --invite <私有文件>` 显式执行同步，复用已有版本、内容与账号归属冲突门禁；
同版本同内容无副作用，网络、规划或应用失败保留原角色、账号与累计流量。
菜单提供单入口接入和手动同步，多入口可通过重复 CLI 参数指定，接入只在 CLI 确认一次。

每次读取受管目录外的 root 私有普通邀请文件；所有祖先目录 root 所有、无符号链接且禁止组/其他用户写入。
文件最大 1 MiB，严格解析 JSON、唯一字段、格式、双方身份、RFC1918 字面地址和有效期。
私有只读快照只挂载给本次无能力客户端，关闭 Docker 日志；原始 token 不进入参数、环境、
受管规格、备份或普通输出。`control_sync.connection` 仅保存监听与本机地址，
与身份和入口映射一同冻结；轮换只需传递新邀请，不重绑定角色。

已有 WireGuard 须运行健康且归属一致，唯一 Peer AllowedIPs 恰为主控 `/32`；
检查到主控的指定源地址路由仅使用 `wg-padm`，客户端复核本机接口地址并绑定源地址。
直接使用标准库 HTTP 连接，不经代理、不跟随重定向、不允许公网或失效回退。
响应只接受唯一规范长度、JSON 类型与 `no-store`，拒绝分块、超量、重复字段和版本/身份漂移；
连接与完整请求共用 5 秒总时限，不让持续慢速响应无限占锁。

新连接增加独立 bundle 能力声明；旧无 `connection` 的内部被控规格保持兼容，
但不自动认领网络或开放外部同步。备份和普通事务恢复保留连接元数据而不含访问 token，
显式回滚的角色与版本下限保护见下一检查点，不能把普通备份恢复当作完整角色恢复验收。
自动同步、多 Peer、网络创建和真实双节点验收未交付，`subscription-multiserver` 继续 `deferred`。

Linux amd64 定向客户端 `10.682` 秒、菜单 `21.933` 秒、旧同步 `6.481` 秒、
主控 CLI `8.300` 秒通过；Docker 快速合同 `18` 项 `52.311` 秒、完整 `ci -Jobs 3`
`34.972` 秒通过。信号测试发现客户端中断码被转成规划冲突，已保留 `130/143`；
覆盖连接耗时扣减、权限/身份/路由拒绝、初始与幂等同步、凭据轮换及应用/信号失败恢复。
复用同一工具镜像与源码快照，未删减断言或扩大槽位；证据 `.tmp-docker-control-4c3d3-evidence.md`。

#### 4C.3d4 被控角色回滚保护

显式版本 `rollback` 先检查当前与目标快照，双方身份、角色、入口映射和 connection 必须一致；
目标上游版本不得低于已提交版本，同版本摘要和受管账号必须相同。
缺失/损坏/权限异常的角色输入、删除角色、重绑定或内容冲突均在采集、创建新备份与停服前拒绝。
仍允许同步状态未变的兼容旧发行版快照回滚，不在本机递增或伪造上游版本。

所有被控规格要求控制 bundle 声明 `x-padm-control-sync-rollback`；
仅有旧同步/客户端能力不足以恢复被控规格，防止切换旧脚本后移除降版本保护。
旧无 connection 角色仍支持配置和内部事务；单机及主控不受此额外声明限制。
普通接入/同步失败与 INT/TERM 沿用事务前可信备份，允许未提交候选退回原状态；
回滚实际执行失败也继续恢复当前版本，不把显式版本门禁全局套到事务恢复。

本步不新增历史业务与当前同步账号合并、自动同步、角色重绑定或完整灾备。
后续进入 4C.4 双节点真实连通、认证/撤销、断网、冲突与失败恢复验收；
完整多服务器仍 `deferred`。

Linux amd64 被控定向 `14.390` 秒通过；最终 Docker 快速合同 `18` 项 `54.120` 秒、
更新/回滚 `27.170` 秒通过，普通 join/sync 失败与信号恢复断言保持。
两轮最终集成共用源码摘要与工具镜像，未重复执行无关原生 CI；
详情 `.tmp-docker-control-4c3d4-evidence.md`。

#### 4C.4a 真实双端加密链路验收

`docker-control-two-node-real` 在 `network none` 的 Linux 测试容器内建立两个独立
网络空间，以私有 veth 作为 underlay，各自创建真实 `wg-padm` 和唯一 `/32` Peer。
断言接口路由、网络空间 inode 不同、真实握手、双端收发计数非零及恢复后增长。
专用 selector 才增加 `NET_ADMIN` 和 `SYS_ADMIN`，不使用 privileged、宿主网络、
Docker Socket 或端口发布；不改变生产 Compose 的权限边界。
工具镜像从官方 Debian 源补齐 `iproute2`、`wireguard-tools` 后复用，不逐次构建。

运行未修改的生产 API 和客户端：API 降为 `10001:10001` 且能力为零，
客户端以 root 读取私有邀请但清空所有能力，并核对有效/继承/边界能力。
覆盖接入规划、同版本幂等、版本推进、本机账号保持、token 轮换旧凭据拒绝、
过期/撤销、低版本/同版内容冲突、断网总时限和恢复重试。
检查三入口日志不泄露 token、私钥或账号凭据，结束清理进程、接口和私有文件。

本项明确输出 `scope=api-client-planning-only`，保存规划草稿只为下一轮输入；
不调用生产 Compose Apply/Restore，不把加密链路通过当作双部署生命周期通过。
入口自检验证能力仅授予精确 selector，普通/近似名称均不获得额外权限。
完整 `subscription-multiserver` 继续 `deferred`，后续 4C.4b 验证真实双部署
CLI 初始化/邀请/接入、核心账号及流量、幂等无重建、轮换撤销与生产失败恢复。
原生 Linux 双机、arm64、宿主重启及公网条件仍需适用环境验收。

Linux amd64 最终双端定向 `7.335` 秒、Docker 快速合同 `18` 项 `55.713` 秒、
集中 `ci -Jobs 3` `36.312` 秒均通过，三次使用同一源码归档摘要和工具内容摘要。
入口自检通过能力隔离、双槽队列、取消清理、异常进程恢复与成功结果复用；
工具变化、源码变化、失败和中断不命中旧成功结果。未扩大槽位或删减断言。
详情 `.tmp-docker-control-4c4a-evidence.md`；保留结果与脱敏日志，清理测试夹具和重复归档。

#### 4C.4b 真实双部署事务验收

`docker-control-two-deployment-real` 在 `network none` 的专用测试容器中运行两个
独立 rootful Docker Engine；节点的 socket、data/exec root、PID/mount/net namespace
与真实 cron 均隔离。固定官方 daemon/runtime 工具与实际业务 manifest digest，
离线加载镜像；不挂宿主 Socket、不发布端口、不覆盖生产 Compose。
仅精确 selector 增加 privileged 和独立匿名 Linux 数据卷，结束及异常接管时一起清理。
普通/近似 selector 保持原权限；不把测试容器权限扩展到生产服务。

节点用生产函数建立 `local-test-only-not-release-verified` 已安装夹具，
并执行未修改的 `control init/invite/join/sync` CLI、Compose 应用与恢复。
可信发布首次配置仍须官方身份 Cosign manifest/bundle 验签，本夹具不替代该门禁。
合法拓扑为单 Xray 的 VLESS WS 21 + Nginx TLS + WireGuard；
Trojan 28 不支持同时启用宿主集成，未为测试放宽约束。

验收完整运行账号集合、本机账号及累计流量保持；真实客户端校验 CA 和域名，
经 WS/TLS 传输后采集上传/下载与核心 baseline。
幂等同步核对容器 ID/启动时间及规格不变，版本推进核对受管停用账号从核心移除。
路由/归属漂移、断网、低版本与同版内容冲突均在应用前拒绝；
同版本错误发布通过只改真实 API 输入显式注入，不宣称正常 CLI 会制造该错误。
轮换和撤销核对真实 HTTP 401，旧邀请拒绝，新邀请保留已提交版本。
暂停本次已切换的新核心触发真实健康失败；INT/TERM 发给独立实际事务进程组，
验证原规格、部署文件、健康服务、锁及候选恢复清理。

回归效率使用 Linux volume 上的 `overlayfs`，不再为每次探针复制镜像根目录；
两个节点并行播种，镜像归档按实际内容复用。保持生产探针/健康时限与共享两槽预算。
实测发现普通首次 Nginx 校验依赖未启动核心的 DNS，已独立提交 `76047f88`：
复用临时校验 overlay，正式 Compose 不变；普通候选成功/失败与清理合同通过。

2026-10-09 最终 Linux amd64 双部署定向 `213.672` 秒、`Jobs=2` 通过，
排队等待 `180 ms`；工具与业务镜像按内容复用，源码归档包含当前未提交改动。
两节点初始/同步后账号凭据、token 和私钥的日志断言通过；
清理故障注入验证单项失败不会阻断其它资源回收，原测试失败保持。
Docker 入口自检通过权限隔离、双槽队列、取消/异常接管和完整成功结果复用。
集中快速合同 `18` 项 `54.700` 秒、完整 `ci -Jobs 3` `35.369` 秒通过；
两轮集成使用同一源码摘要，定向后仅更新文档和本地状态。
详情 `.tmp-docker-control-4c4b-evidence.md`；保留结果与脱敏日志，清理重复归档和夹具。

本地完整多服务器仍为 `deferred`；自动同步、多 Peer、网络向导、角色重绑定、
迁移与灾备未交付，原生 Linux 双机、原生 arm64、宿主重启及可信发布验收仍待补。

## 第五步：站点、路由与宿主集成

### 5A. 站点与剩余证书流程

迁移静态站点、302、ALPN 诊断/修复及 fallback 站点维护；
补 webroot 和 standalone ACME 的端口归属、停机范围、续期和失败恢复。
复用 3B 的证书事务，不再维护另一套证书提交逻辑。

验收：站点和证书修改失败可恢复；80/443 冲突在变更前发现；
challenge 后服务恢复，证书和控制凭据不被站点发布。

#### 5A.1 默认页、静态目录与 302

菜单 `16. 站点管理` 和 `edit --site-static/--site-default/--site-redirect`
复用当前编辑、可信发布与配置候选事务。可选 v3 `.site` 只保存模式和 HTTP/HTTPS
跳转 URL，源目录不进入规格；旧无 `.site` 输入保持原行为。
控制 bundle 必须声明 `x-padm-site-content` 才接受新规格，旧无站点规格不受影响。
动作要求已有 Nginx TLS `21–25` 或 fallback `27`/`29`，作用于全部这些入口，
不改 ALPN、端口、TLS 身份、代理及订阅路由，不接管 Reality 外部目标或宿主网站。

发布目录须独立、包含非空 `index.html`，root 所有且不可外部写入；
只接受常见公开资源，拒绝受管及祖先目录、隐藏/秘密路径、链接、硬链接、特殊文件
和可识别 PEM 私钥。内容校验不能证明不存在任意嵌入凭据，不宣称自动脱敏。
复制而非绑定外部源，`data/static` 加入候选、备份、安装、权限与恢复白名单；
切换默认页/302 或无新源编辑保留旧内容，旧快照未列静态目录时不删除现有内容。
健康失败、INT/TERM 通过共用事务恢复规格、站点和服务，候选/锁按所有权清理。
菜单删除最后一个 Nginx 入口时自动移除不再适用的 `.site`，静态文件和其它 TLS 入口保留。

Linux amd64 最终站点定向 `13.723` 秒通过；真实 Debian Nginx `21` 份配置解析、
TLS 静态/默认页/302 与 `27`/`29` PROXY v1 HTTP、代理及订阅路径均通过。
回归使用真实 root 文件权限、锁与事务，Compose/发布/核心/TLS 输入校验为桩；
不宣称完整发布镜像或 HTTP/2 实际流量验收。目录尾斜杠/链接及目录型首页边界已修复。
快速合同 `19` 项 `61.014` 秒、系统合同 `100.407` 秒、完整 `ci -Jobs 3`
`34.586` 秒通过；之后只对最后入口删除的小修复重跑站点，不重复无关全套。
Nginx 工具由 Debian 官方源补入独立缓存层，CI 快速分片复用相同 Linux 工具镜像与
当前源码快照，避免旧 Nginx 不识别生产 `http2 on`；运行无网络、无 Socket/额外能力。
新站点检查提前入队，仍保留全部断言及共享两槽预算；静态语法和 workflow lint 通过。
证据 `.tmp-docker-sites-5a1-evidence.md`；保留结果与脱敏日志，清理重复归档。

webroot/standalone ACME 留给后续检查点；
`site-static-redirect-alpn` 组合能力仍为 `deferred`，不以这次子交付升级完整状态。

#### 5A.2 ALPN 诊断与限定修复

菜单 `16` 增加全部/指定入口诊断、推荐修复与三种手动顺序；CLI 为
`protocol alpn-status [入口 ID]` 和 `edit --alpn <入口 ID> <顺序>`。
只适用于现有 Xray `27`/`29`，可选 v3 `fallback_tls.alpn` 精确接受
`h2,http/1.1`、`http/1.1,h2` 或 `http/1.1`；缺省仍用推荐顺序。
核心与 URI 同读持久化字段，复制、账号操作与更新不重置手动值；
显式字段要求 `x-padm-fallback-alpn`，旧无字段规格及 direct Trojan 不变。

诊断从安全的受管规格与实际 Xray 配置读取 ALPN，分别报告规格、实际和推荐值，
fallback/Nginx 一致性及修复资格。非推荐但符合手动规格不是损坏；
未知 ALPN 值输出 `null`，不回显任意配置内容，也不宣称已完成真实 TLS 协商。
诊断不能先走普通 `protocol` 的严格基线，否则有漂移时无法诊断。
FIFO、链接、特殊 Nginx 文件和坏 JSON 拒绝，输出不含账号、密钥或 token。

专项基线只忽略所选入站的 TLS ALPN 字段，同时核对 `users.base` 与额度渲染配置；
其它入口、账号、路由、TLS 身份、fallback 目标/PROXY、Nginx、Compose 与宿主配置仍严格匹配。
不先改 live 文件，不自动接管手写 fallback/Nginx，复用私有草稿、预览、可信发布、
候选验证、统计刷新、备份、健康检查及 INT/TERM 恢复事务。
预览和取消不写部署；失败恢复原始文件，包括修复前 ALPN 漂移，站点与累计流量保留。

Schema/生产校验同批正反例、能力门禁、三种核心/URI 顺序、双入口限定、
运行/完整账号输入漂移、其它配置漂移拒绝、预览/取消/健康/信号恢复定向通过。
真实 Nginx 在原有 `27`/`29` 启动轮次内用 curl 的 HTTP/2 prior knowledge + PROXY v1
核对 HTTP 版本、首页及 CSS，不增加服务启动轮次，不改 `21` WS 前端行为。
真实 Xray TLS ALPN 协商、公网、原生双架构与可信发布仍待适用验收；
webroot/standalone ACME 归下一检查点，不升级组合完整管理状态。

Linux amd64 最终定向 `30.654` 秒、快速合同 `19` 项 `73.566` 秒、
系统合同 `101.644` 秒、完整 `ci -Jobs 3` `35.664` 秒通过；
Bash、ShellCheck error、Python AST 与 JSON 静态检查通过。
发现并修复额度重渲染覆盖“仅运行文件 ALPN 漂移”的恢复缺口，健康失败与
INT/TERM 现在精确恢复该原始漂移，不改普通事务的流量收敛行为。
复用现有 Nginx 启动轮次和工具层，未增加依赖、启动轮次、槽位或删除断言。
快速合同调整入队顺序从 `72.087` 秒变为 `73.566` 秒，无实际收益，已撤回；
不把排序试验当作提速成果。证据 `.tmp-docker-alpn-5a2-evidence.md`。

原生菜单顺手修复独立提交 `6f234e16`：按实际 TLS fallback 入站判定维护资格，
修复 `29` 及无 `27` 标签的传统前端被误拒绝；缺 Xray/Nginx 工具时先停止，
不跳过配置验证。Nginx 重建另存唯一 `0600` 恢复文件，启动失败恢复旧配置并重试，
原缺则清理本次文件；恢复失败保留证据并明确报错，首装离线分支不变。
对应 Nginx 事务 `1.613` 秒、核心失败传播 `1.004` 秒、UI 冒烟 `0.535` 秒通过。

#### 5A.3a Standalone HTTP-01

首配增加模式 `4`，证书管理菜单在申请/续期/自动续期时选择 DNS 或 standalone；
CLI 为 `acme <issue|renew> --standalone` 及 `acme schedule enable --standalone`，
与 DNS provider/凭据互斥，不生成占位凭据。非 root ops 在容器 `8080` 监听，
挑战期间临时映射宿主双栈 TCP `80`，不授予宿主网络或额外能力，不修改防火墙。

先检查实际运行容器的项目、服务、根目录、Compose 路径、镜像、挂载及绑定端口，
并与受管 spec/部署/生成 Compose 交叉核对。宿主监听仅放行可归属的 Docker proxy，
外部、混合或无法归属的占用在停机前拒绝。所有者停止后再次确认宿主和 Docker
端口释放；仅登记并恢复本次原运行 ID，同容器其它端口的短暂停机明确提示。
原本停止的 TLS 消费者保持停止，恢复检查实际 Running，不自动重建无关服务。

HTTP 续期先在候选账户内临时注入预钩子，让固定 acme.sh 按到期及 ARI 规则判断；
只有进入真正挑战后才准备端口。未到期不暂停、不发布或提交证书；
原钩子在候选内恢复，标记不含秘密，不解析执行宿主账户文件。
仍复用候选账户、证书校验、消费者提交、流量保持和恢复事务。
恢复失败保留私有 `challenge.json`，不清理恢复点或继续下一域名。

DNS 登记继续 schema `1`；HTTP 仅 schema `2` 请求且无凭据文件，旧 DNS 输入兼容。
已启用 HTTP 时拒绝旧 bundle，停用通过原登记/调度事务删除 HTTP 记录，
失败恢复原记录，避免 disabled schema `2` 仍阻塞旧脚本校验。
原生菜单修复 `96976fa5` 补订阅 HTTP-01 的 `80` 参数，webroot 续期不停止前端；
`no` 与 `alpn` 自监听账户仍保留原停服/恢复路径。

本地 Linux amd64 首配、菜单、登记/降级、实际事务合同与信号断言已通过；
Compose/CA/运行状态为精确桩，尚不证明公网 CA、真实宿主端口生命周期或可信发布。
最终 TLS/续期并行定向 `16.846` 秒、首配 `59.171` 秒、快速合同 `19` 项
`77.883` 秒通过；恢复状态漏断言补齐后仅重跑 TLS，`17.508` 秒通过。
系统合同 phase4/phase6 已通过，phase3 的旧 DNS 参数断言更新为显式 ECC 后
定向 `106.687` 秒通过，不重复无改动分支。集中 `ci -Jobs 3` `39.890` 秒通过，
共享槽位等待 `226.853` 秒与执行耗时分开记录，不扩大两槽预算。
固定 acme.sh `3.1.6` 在无公网网络的容器内通过真实 RSA/ECC 到期探针：
未到期返回 `2` 且无挑战标记，到期预钩子才留下标记，原编码钩子恢复；
仅本地模拟 ACME directory，不生成公网证书。Bash/ShellCheck error 与 JSON 通过。
证据 `.tmp-docker-acme-5a3a-evidence.md`；复用工具镜像、保留脱敏日志/result，
清理本轮临时探针及重复源码归档。
完整 `acme-standalone` 仍为 `deferred`，不开放 TLS-ALPN-01。
#### 5A.3b 受管 Nginx Webroot HTTP-01

v3 `.tls.http01=true` 显式 opt-in，删除字段关闭；仅已有受管 Nginx
`21–25`/`27`/`29` 可用，不为旧规格无条件开放 TCP `80`。
证书菜单提供入口开关与第三种 ACME 验证方式，CLI 为
`edit --http01 enable|disable`、`acme <issue|renew> --webroot` 及
`acme schedule enable --webroot`。申请不暗中开启入口。

专用 Nginx HTTP vhost 固定双栈 `80:8088`，deployment 增加 `host-acme-http`，
bundle 要求 `x-padm-acme-webroot`。只服务当前 TLS 域名的标准 token URL，
其它 URL、查询串、编码绕过、符号链接均拒绝；与默认页、静态页和 302 独立。
Nginx 只读挂载稳定 `data/acme-webroot`，root 为 `0750 10001:10001`；
ops 仅读写本次原子创建的 `active/.well-known/acme-challenge`。
不接管已有挑战，不替换父 inode，不暂停 Nginx，不临时发布端口。
父目录归属/可写性、特殊文件、硬链接、token 名称/原始字节及实际端口、
挂载、镜像、规格和生成配置均先核验；清理只删本次 inode 的 `active/`。
首次根与 active 初始化期间先完成权限归属，再重放 INT/TERM，避免遗留半成品。
快照不夹带挑战根，配置安装与恢复保留稳定根。

续期沿用真实 acme.sh 到期/ARI 预钩子探针，skip `2` 不创建 active 或修改服务；
候选账户、证书校验及消费者健康提交复用原事务。
webroot 登记 schema `3`，无凭据文件；DNS `1`、standalone `2` 兼容，
bundle 支持所有已启用登记的最高 schema。
启用 webroot 自动续期时，关闭入口、改域名、删最后 Nginx 和回滚关闭快照
均在变更前拒绝；停用事务删除登记，失败和 INT/TERM 保留恢复点。

本地 Linux amd64 集成合同 `30` 项、真实 UID `10001` Nginx、TLS/续期、
菜单取消与信号断言通过；完整合同 `461.950` 秒，TLS/续期定向 `40.212` 秒，
首次根信号补强后仅 TLS 叶子 `42.629` 秒通过。
真实 Nginx 仍复用原 `9` 次启动，不重复启动旧缺省配置。
独立审查发现并修复 token 字节归一化、回滚关闭、初始化信号与额外挂载遮蔽；
集中 `ci -Jobs 3` `38.184` 秒、旧无 spec 更新/回滚 guard 的 phase6 叶子
`28.731` 秒通过，队列等待与执行分开记录。
证据 `.tmp-docker-acme-5a3b-evidence.md`。
复用工具镜像和原有真实 Nginx 启动轮次，定向失败只重跑变化叶子；
不扩大双槽预算。公网 CA、真实宿主生命周期及原生 arm64 尚未验，
完整 `acme-webroot` 与 `acme-standalone` 状态保持 `deferred`，不开放 TLS-ALPN-01。

### 5B. 核心内路由与内部能力

迁移 WARP、IPv6、DNS/hosts、BT/区域阻断、路由和访问控制；
内部 `201` Socks、`202` HTTP、`206` DNS/Direct/Block、`207` Tunnel/dokodemo-door
按真实核心支持范围分别交付。能用核心配置完成的能力不授予宿主网络权限；
需要接口或规则的部分依赖 5C。

验收：DNS、出口、阻断和中继有真实流量验证；非法规则和更新失败恢复旧配置；
纯容器路径不改变宿主路由或防火墙。

#### 5B.1 认证 SOCKS5 TCP 全局出站

v3 可选 `.routing.socks5` 保存字面 IPv4/IPv6 上游、端口和认证凭据，旧缺省保持原始直连。
首版地址不接通用 DNS、回环、未指定、链路本地、组播或 Docker 宿主别名；
凭据为 `1–255` 个可见 ASCII 字符，不含空格/控制字符。
控制包须声明 `x-padm-routing-socks5`，旧包在配置/更新/回滚前拒绝新规格。

菜单 `17. 路由与出站` 与 `edit --socks5 <私有 JSON>` / `--socks5-off` 共用编辑事务，
输入须 root 所有、`0600`、单链接、最多 `64 KiB`，祖先无链接且不可外部写入。
凭据从私有快照导入，不进入参数或普通输出；受管规格、核心配置和备份仍保留凭据。
只允许专项改变路由，普通规格导入保持原固定字段约束，状态输出严格脱敏。

两核心客户端 TCP 目的流量经认证 SOCKS5，上游失败不得回落直连；
UDP 目的流量显式阻断，统计 API 规则仍优先。
Reality 握手、控制服务、Nginx、ACME 和宿主流量不属于该代理范围，
Hysteria2/TUIC 的 UDP 入口传输仍可承载 TCP。SOCKS5 认证链路本身不加密，
须使用可信上游网络。无新监听/宿主权限/防火墙规则，首版拒绝 TUN/TProxy 组合。

定向合同 `docker-routing-socks5` 与独立 `docker-routing-socks5-real` 验证生成、
两份合同、API 保留、事务恢复与双核心 IPv4/IPv6 真实 CONNECT/失败/UDP 无直连。
2026-10-09 的 Linux amd64 定向合同 `16.176` 秒、双核心双栈真实流量
`11.558` 秒、协议诊断 `50.816` 秒通过；真实核心以 UID/GID `10001`、
无 capabilities 运行，隔离回环上游不发布宿主端口。UDP 先用同一入站直连正对照
证明可达，再检查阻断；认证失败和上游停机均未触达目的地或退出核心。
权限损坏、核心漂移、INT/TERM 清理及回滚秘密权限均有断言。
集中完整 Docker 合同 `31/31`、`178.739` 秒通过，`Jobs=6`、原有双槽不变；
证据 `.tmp-docker-routing-5b1-evidence.md`。
本检查点不等于完整 `201`：公网 SOCKS 入站、域名分流、DNS/WARP 和其它路由策略继续推进，
`routing-tools` 与 `internal-201-socks-relay` 完整状态保持 `deferred`。
原生访问控制同时修复 IPv4 数值、IPv6 组/压缩及 CIDR 上界校验，
保留合法边界、`cn`、小写和去重；独立提交 `12c55621`，`routing-core` `5.175` 秒通过。

#### 5B.2 SOCKS5 域名分流

可选 `.routing.socks5.domains` 为 `1–256` 条唯一小写规则，接受 `full:` 精确域名、
`domain:` 域名/子域、`keyword:` 安全 ASCII 关键字与 `geosite:` 显式分类。
私有 JSON 导入须已规范化，菜单 `17` 增加替换规则及恢复全局；
CLI 为 `edit --socks5-domains <CSV>` 和 `edit --socks5-global`。
CSV trim、小写并按首次出现去重，裸域名补 `domain:`，空项及非法值返回 `2`；
不自动联网猜分类，无已启用上游则拒绝规则动作。
只改域名规则，不轮换上游/凭据；普通 `--spec` 不能绕过路由冻结。

两核心各类匹配保持 OR；匹配 TCP 经认证上游且失败不回退，匹配 UDP 阻断，
未匹配 TCP/UDP 直连。无提供/可嗅探域名的 IP 流量直连，不等于强制全局代理。
Xray 将规范 `keyword:` 转为引擎子串值，所有客户端入站嗅探仅影响路由；
sing-box 将 matcher 分开生成，不把域名和 rule-set 错误组合成 AND。
统计 API 优先，流量渲染不删路由；无新监听、宿主权限、挂载或防火墙变更。
关闭仍删除可选 routing，恢复全局仅删除 domains，旧全局和旧无路由规格兼容。

域名模式要求 `x-padm-routing-domains`，旧 bundle 在配置/更新/恢复前拒绝新规格。
Xray 复用受管或镜像 Geo；sing-box 所选分类从固定 SagerNet URL 经 direct 下载，
不增加任意 URL 输入。缺资产或下载失败应拒绝候选启动并由原事务恢复；
规则词法有效不保证分类存在。状态只输出 `mode`、`domain_rules` 等非秘密字段。

本阶段签名提交 `fb22fee1 feat(docker): add SOCKS5 domain routing workflow`。
最终定向合同 `24.546` 秒、真实双核心双栈 × global/selective `8/8`、
`58.819` 秒通过；覆盖四种单独 matcher、ATYP3 与 IP/Host sniff、未匹配直达、
认证拒绝/上游停机不回退、UDP 直连正对照及晚于 sniff 超时的阻断观察。
Xray 本地 TEST GeoSite 与 sing-box 真实编译 srs 由核心解析，回环 HTTP 下载成功不走
SOCKS，HTTP 404 和缺资产严格匹配真实错误后拒绝启动；不以任意非零退出当作负测成功。
实测修复 sing-box 空 direct 不能作为下载 detour 的生成错误，显式 Go HTTP 客户端
避免隐式客户端弃用依赖。未访问公网分类源，不将回环数据夹具等同于官方分类可用性。
集中完整 Docker 合同 `31/31`、`172.071` 秒，`ci` `35.087` 秒通过；
13 个变更 Shell 文件 Bash/ShellCheck error、Python AST、Schema JSON 与独立复审通过。
证据 `.tmp-docker-routing-5b2-evidence.md`；工具镜像及原有双槽预算不变，
失败分支定向重跑，提交前恢复完整矩阵，临时核心副本和诊断限制已清理。
原生关键字生成/歧义拒绝和写前解析独立签名提交 `77123f9e`，
`routing-core` `5.991` 秒通过，保留 DNS/hosts 原配置和 SOCKS 空项兼容。
公网资源、原生 arm64、可信发布及完整 SOCKS 入站仍待适用验收；
`routing-tools` 与 `internal-201-socks-relay` 完整状态继续 `deferred`。

#### 5B.3a DNS 分流与精确 hosts

v3 `.routing` 可独立包含 `socks5`、`dns`、`hosts`，至少保留一项；
DNS 为 `{server,port,domains}`，仅 UDP 字面 IPv4/IPv6 与 1–256 条四类 OR 规则，
hosts 为 1–256 个小写精确 FQDN 到单个可路由字面 IP 的映射。
hosts 不提供后缀、关键字或分类假支持；本步不扩全局 DNS、DoH/DoT、Direct/Block。
控制包须声明 `x-padm-routing-dns-hosts`，旧包在配置、更新和回滚前拒绝。

菜单 `17` 增加 DNS/hosts 启用和关闭，CLI 为 `edit --dns <私有 JSON>`、
`--dns-off`、`--hosts <私有 JSON>`、`--hosts-off`；
输入文件沿用 SOCKS5 的 root 私有快照要求，确认、候选校验与失败/信号恢复复用原事务。
只更改对应子能力，关闭 SOCKS5 不删除 DNS/hosts，关闭最后一项才删除 `.routing`。
普通 `--spec` 编辑仍冻结 routing，状态只追加无凭据的 DNS/hosts 投影。

只改变客户端直连域名目标的核心内解析，hosts 优先于 DNS 分流，未匹配走容器本地解析；
匹配 DNS 失败不回退本地解析。SOCKS5 匹配在解析前选路，域名仍交上游解析；
嗅探域名不改写 IP 目的地。Xray 使用匹配 resolver 禁回退、精确 hosts 与 direct ForceIP，
内置 DNS 标签单独直连，避免被客户端 UDP 阻断；sing-box 使用显式 resolve server、
hosts 精确解析后终止路由，四类 DNS matcher 分组保持 OR，远程分类去重并直连下载。
不增加宿主端口、挂载、网络权限或防火墙操作；完整 `206` 和路由工具仍为 `deferred`。

功能签名提交 `9dd803e2 feat(docker): add transactional DNS and hosts routing`。
本地 Linux amd64 最终定向合同 `41.673` 秒、菜单真实 PTY `28.206` 秒通过。
真实 Xray/sing-box × IPv4/IPv6 四路径 `31.239` 秒通过，四类 DNS matcher 独立命中，
hosts/DNS 同名零查询且覆盖地址可达、SOCKS5 重叠目标经上游、IP/sniff 不替换目的。
IPv4 两核心另验全局 SOCKS5 与解析共存、全局 UDP 阻断，以及独立解析 UDP 直达正对照。
SERVFAIL 四路径和静默超时每核心一例均触达指定 DNS，实际返回失败且目的接入为零；
仅夹具 deadline 缩到 `250 ms`，生产默认超时不改。

真实反例暴露 Xray `localhost` 自动匹配 `.invalid/.test/.example`，
`disableFallbackIfMatch` 不排除第二个已匹配服务器；指定 resolver 增加 `finalQuery:true`。
保留本地 hosts 可解析诱饵，不通过改域名或吞超时规避失败。
完整 Docker 合同 `31/31`、`193.026` 秒、`Jobs=6`，`ci` `34.418` 秒、
`Jobs=3` 实际运行通过；13 Shell Bash/ShellCheck、
两 Python AST、Schema/features JSON 与 PowerShell AST 通过，原有双槽和工具镜像不变。
证据 `.tmp-docker-routing-5b3-evidence.md`，临时源码归档/核心副本和脚本收尾清理。

原生相邻修复独立提交 `6f097e7e`：sing-box hosts 只接受精确域名，
DNS geosite 与域名保持 OR，DNS/hosts 分别管理并保留自定义和跨分片引用；
开放并修复 sing-box 单核菜单，非法 hosts IP/规则在写入前拒绝。
`routing-core`、DNS 失败返回和 UI 冒烟通过，实际 pinned sing-box 合并配置检查通过。
未更改原生全局 `UseIP` 策略；公网规则源、原生 arm64、可信发布及真实宿主仍待验。

#### 5B.3b Direct 直连例外与 Block 域名阻断

v3 可选 `.routing.direct`、`.routing.block` 各保存 `{domains:[...]}`，
复用 1–256 条唯一小写 `full/domain/keyword/geosite` 合同，四类匹配保持 OR。
单独能力门禁为 `x-padm-routing-direct-block`；不继承隐式域名放行，
不扩 IP/CIDR、区域、BT 或全局阻断策略。

Direct 按原生菜单语义优先于 Block 和 SOCKS5；匹配直连仍使用 hosts/DNS。
Block 拒绝匹配 TCP/UDP，不进行本地目标解析；未匹配保持旧出站选择。
统计 API、内部 DNS 和规则下载不受客户端策略阻断，IP/sniff 不改实际目的地。
sing-box 使用 Direct 的逻辑否定守卫排除 Block/SOCKS，解析后才终止 Direct 路由。
仅域名策略启动路由嗅探，未提供可识别域名的 IP 流量不冒充 IP 策略命中。

菜单 `17` 的 `10–13` 和 CLI `edit --direct/--block <root 私有 JSON>`、
`--direct-off/--block-off` 复用原输入快照、确认、候选检查与失败/信号恢复事务。
关闭仅删除对应子项，普通 `--spec` 仍冻结 routing，状态追加无凭据的策略规则。
不增加宿主端口、挂载、网络权限或防火墙；完整路由工具和 `206` 保持 `deferred`。
功能签名提交 `88806b82 feat(docker): add transactional Direct and Block domain routing`。
本地 Linux amd64 定向合同 `60.586` 秒、双核心双栈真实流量 `75.128` 秒、
菜单真实 PTY `28.496` 秒通过。四类 Direct/Block 独立命中，四个 Block 目的
先由无策略生产模板证明可达，再要求实际拒绝且 DNS/目的/SOCKS 增量为零；
核心继续存活且紧邻未匹配请求成功，客户端超时不视为 TCP 阻断通过。
Direct 同域 Block/选择性 SOCKS 优先，仍使用匹配 DNS/hosts，IP/sniff 不改目的；
IPv4 双核心另验全局 SOCKS 组合和 Direct DNS/hosts UDP 正对照。
完整 Docker 合同 `31/31`、`208.134` 秒、Jobs `6`，ci `34.210` 秒、Jobs `3` 通过；
14 Shell Bash/ShellCheck error、Python AST、Schema/features JSON、PowerShell AST 通过。
工具镜像和双槽预算保持，alias 复用现有合同/夹具，全套不重复执行同一路由合同。
证据 `.tmp-docker-routing-5b3b-evidence.md`；保留 result/log，临时源码与核心副本清理。

原生相邻修复独立签名提交 `a9921985`：空域名/逗号输入写前拒绝，
sing-box 域名与 geosite 保持 OR，历史精确前缀及带下划线分类保留；
单 sing-box 访问控制开放，删除域名策略保留 BT 引用出站，cn 使用真实 GeoIP rule-set。
独立复审发现共享 OR 后 SOCKS inbound 根附加 matcher 的兼容问题，
已改外层来源 AND，二次编辑来源历史保留，普通/空域名格式不变。
最终 routing-core `8.604` 秒、SOCKS UDP 关联 `1.032` 秒、
访问控制事务 `1.205` 秒、失败返回 `0.873` 秒通过；
实际 pinned sing-box 生产合并/check 覆盖 OR/AND、来源历史和 cn/CIDR。
检查用本地编译资产，不将其等同于公网规则源验收；原生 arm64、可信发布和真实宿主待验。

#### 5B.3c IP/CIDR 与 GeoIP 阻断

独立 v3 `.routing.block_ips` 保存 `{ips:[...]}`，支持 1–256 条唯一纯 IPv4/IPv6
字面地址或合法 CIDR，以及固定 `geoip:cn`；不接受主机名、范围、scope 或点分嵌入 IPv4。
该输入为目的 matcher，不继承 SOCKS/DNS 上游的公网地址限制。
能力门禁 `x-padm-routing-block-ips`，旧包在配置、更新与恢复前拒绝。
菜单 `17` 的 `14–15` 与 CLI `--block-ips/--block-ips-off` 共用私有输入及编辑事务；
独立关闭保留域名 Block、Direct、SOCKS 与 DNS/hosts。

Direct 域名例外优先，IP Block 在出站或域名解析前拒绝匹配 TCP/UDP；
Xray 保持 AsIs，sing-box 前置 IP matcher 不触发解析或在 resolve 后复查。
本步对客户端字面目的 IP 生效，不等同于最终拨号 IP 过滤或宿主防火墙。
ATYP3 域名继续既有 SOCKS 上游/DNS/hosts 路径，即使最终地址属于该 IP 集；
IP/sniff 不改变目的地址，内部 API/DNS 与规则下载不受客户端 IP 策略拦截。
Xray 使用受管/镜像 GeoIP；sing-box 固定官方 `geoip-cn` 地址直连下载并复用现有失败事务。
不新增宿主权限、端口、挂载或网络规则。

2026-10-09 的 Linux amd64 定向合同 `75.531` 秒、菜单真实 PTY `28.657` 秒通过。
独立 `docker-routing-block-ips-real` 双核心双栈 `46.569` 秒通过；
三类 literal/CIDR/GeoIP 各用独立生产模板，先证明同 IP/端口 TCP/UDP 可达，
再接受实际拒绝、零目的接入/DNS/SOCKS 增量与核心存活证据。
同一字面 IP 的 Direct HTTP Host 例外可达且不改目的；
ATYP3 域名经 DNS、hosts 或 SOCKS5 解析到同被阻断 IP 仍按原路径成功。
Xray 真正缺失 GeoIP、sing-box 本地缺资源和远端 HTTP `404` 均保留原始失败原因，
未将超时当作拒绝；CN 为明确标注的本地二进制 fixture，不代表公网分类源验收。
第一轮发现夹具将 SOCKS5 CONNECT 和 HTTP 正文提前合并，sing-box 正向对照超时；
修正该核心的标准握手时序后仅重跑真实 selector，不修改生产规则。
完整 Docker 合同 `31/31`、`238.190` 秒，`Jobs=6`，未复用缓存；
12 Shell Bash/ShellCheck error、Python AST、Schema/features JSON、PowerShell AST 通过。
集中 `ci -Jobs 3` `36.744` 秒通过，入口 `37.655` 秒与队列等待 `222.931` 秒分开记录；
本阶段功能签名提交 `cf4fcce1`，已通过且代码无变化的定向场景不重复执行。
原生菜单同时修复写前 IP 校验及精确去重，避免 CIDR 子串误判；
`routing-core` `9.130` 秒通过，独立签名提交 `2c0dbd54`。
本阶段复用 DNS/HTTP/SOCKS 服务及核心程序，只增加 IP 独立场景，
不重复此前四类域名 matcher 和 DNS 失败矩阵；未修改回归队列预算。
证据 `.tmp-docker-routing-5b3c-evidence.md`，源码归档及核心临时副本收尾清理。
区域组合向导、BT、最终目的过滤和完整路由管理仍待后续交付。

#### 5B.3d BT 协议阻断

独立 v3 `.routing.block_bt:true` 和能力门禁 `x-padm-routing-block-bt`；
关闭删除字段，不引入 `false`、端口黑名单或第二套规则编辑器。
菜单 `17` 的 `16–17` 与 CLI `--block-bt/--block-bt-off` 复用现有编辑事务，
关闭仅删除 BT 子项，保留其它路由、凭据和累计流量。
Direct 域名例外优先，BT 规则位于域名/IP Block 后、SOCKS/DNS/hosts 前；
统计 API 与内部 DNS 保持原优先级，sniff 不改变实际目的。
只阻断核心可识别的明文 `bittorrent`，加密、混淆、DHT 与部分 uTP 不保证，
两核心 UDP 识别不同，不将它标记为全面 BT 或宿主防火墙能力。
本阶段功能签名提交 `b792bbae feat(docker): add transactional BitTorrent blocking`。
Linux amd64 定向合同 `18.719` 秒、真实双核心双栈 `14.781` 秒、
菜单真实 PTY `28.849` 秒通过。各核心先对同目的 literal/DNS/SOCKS 发送
标准 `68` 字节 BT 握手，证明目的服务实际收到；开启后要求实际拒绝、
目的接入/DNS/SOCKS 增量为零及核心存活，不把超时当阻断成功。
ATYP3 Direct 域名与相同 BT 握手重叠仍直达，指定 DNS 及普通 HTTP/UDP 保留；
IPv4 另验全局 SOCKS 组合，两个核心的标准 SOCKS 握手时序分别保留。
完整 Docker 合同 `31/31`、`241.342` 秒、Jobs `6`，集中 ci `34.261` 秒、
Jobs `3` 实际运行通过，均未复用缓存；队列等待分别 `364` / `383 ms`。
11 Shell Bash/ShellCheck error、Python AST、Schema/features JSON、
PowerShell AST 及独立只读复审通过；首轮 jq 断言优先级错误仅修测试后定向重验。
复用现有 TCP/UDP/DNS/SOCKS 服务，不重跑 DNS 失败与 IP/CIDR/GeoIP 真实矩阵；
三槽沿用性能任务 `500905dd`，未增加预算或重复构建工具镜像。
原生相邻修复独立签名提交 `ade7cc8b`，保留混合协议规则中的非 BT 协议、
开启全部已有入站 payload sniff 并保留原设置，`routing-core` `8.731` 秒通过。
原生与 Docker 的规则排序不视为完全相同；无入站不新增，非法入站类型写前拒绝。
证据 `.tmp-docker-routing-5b3d-evidence.md`；源码归档和核心临时副本收尾清理，
加密/混淆 BT、DHT、部分 uTP、原生 arm64、可信发布与真实宿主仍待适用验收。
完整路由状态保持 `deferred`。

#### 5B.3e CN 区域策略预设

独立 v3 `.routing.region` 保存 `{mode:"both|domain|ip",allow_domains:[...]}`，
能力门禁 `x-padm-routing-region`；额外例外可为空、最多 256 条唯一规范域名规则。
菜单 `17` 的 `18` 和 CLI `--region <both|domain|ip> [--region-allow <CSV>]`、
`--region-off` 复用现有编辑事务，模式切换替换而非累加，关闭只删除预设所有权。
生成时临时合入现有 Direct/Block/IP Block 并去重，不把展开结果写回手工规则。
固定默认为 8 条域名及子域例外，`gstatic.com` 不使用含糊关键字或动态分类猜测；
额外及默认例外均优先于其它 Block、BT 和 SOCKS，而不只豁免 CN。
域名模式使用显式 `geosite:cn`，IP 模式沿用字面目的 `geoip:cn`，
不为域名提前解析或在解析后复查，不扩宿主权限、端口、挂载及防火墙。
功能签名提交 `898685e4 feat(docker): add owned CN regional routing presets`。
Linux amd64 定向合同 `21.597` 秒、真实核心 `18.743` 秒、菜单 PTY `29.717` 秒通过；
两核心 × 双栈 control/both 加 IPv4 domain/ip/off，共 `14` 次真实核心启动。
独立 CN GeoSite protobuf/编译 SRS 与 GeoIP 回环夹具由真实核心读取，
不误用已有 TEST 分类，也不将本地小型数据等同于官方 CN 全量或公网源可用性。
同目的域名/IP 正对照先实际到达，组合预设分别要求实际拒绝、
目的接入/DNS/SOCKS 增量为零及核心存活；超时为失败而非阻断成功。
默认与自定义例外均在 CN 分类内，ATYP3 和字面 IP/HTTP Host 嗅探分别证明重叠放行；
单模式反向正例防累加，关闭恢复 CN 域名/IP 且 generic Block 仍拒绝。
CLI 精确规格与生成结果比较证明关闭保留手工相同 CN 规则，私有权限和流量累计不变。
完整 Docker 合同 `31/31`、`256.549` 秒、Jobs `6`，ci `37.962` 秒、Jobs `3`，
相同源码内容实际执行通过、均未复用缓存；等待分别 `365` / `82544 ms`，单列排队耗时。
11 Shell Bash/ShellCheck error、Python AST、Schema/features JSON、
PowerShell AST 和 CLI/菜单及真实夹具独立只读复审通过。
复用二进制资源生成和既有服务，不重复四类域名 matcher、DNS 失败和完整 IP 缺资产矩阵；
沿用三槽预算与工具镜像，不重复构建，结果日志保留，临时源码/核心副本收尾清理。
原生区域向导同时修正显式 CN 分类与 `gstatic.com`，独立签名提交 `f9a70508`，
`routing-core` `8.618` 秒通过；DLC 不可用时双核心仍使用显式分类而非退化猜测。
历史累加和共享规则归属不重构，
Docker 的独立所有权不等同于完全复制原生历史编辑语义。
证据 `.tmp-docker-routing-5b3e-evidence.md`；单模式/off 真实验收仅 IPv4，
完整区域管理与 `206` 仍 `deferred`，公网分类源、真实 CN 数据、arm64、
可信发布、真实宿主及最终目的过滤待适用验收。

#### 5B.4a IPv6 域名出站与受管网络

独立 v3 `.routing.ipv6` 保存 `{mode:"selective|global",domains:[...]}`，
能力门禁 `x-padm-routing-ipv6`；selective 为 1–256 条唯一规范四类域名规则，
global 必须为空列表；关闭删除子项而非保存 `off`。
菜单 `17` 的 `19` 和 CLI `--ipv6 <selective|global> [--ipv6-domains <CSV>]`、
`--ipv6-off` 复用现有编辑事务，非法组合在 preflight 和加锁前拒绝。
Direct、域名/IP/BT Block 优先于选择性 IPv6，选择性 IPv6 优先于 SOCKS；
global 仅定义剩余默认出口，显式 SOCKS 规则保持，全局 SOCKS 与 global IPv6 互斥。
Xray 使用 `ForceIPv6`，sing-box 使用 `ipv6_only`，仍沿用原 hosts/DNS 分流来源；
只使用 AAAA 地址、不回退使用 A，系统 local resolver 可以查询 A。
IPv4-only hosts 实际拒绝，IPv6 hosts 成功；字面 IPv4 不转换，也不将此能力视为 IPv4 防火墙。
IP Block 沿用 AsIs，不提前解析或在解析后复查；普通导入仍冻结整个 routing。
功能签名提交 `22a541f3 feat(docker): add owned IPv6 domain egress routing`。

保留原 default 网络，启用时仅核心附着额外 `padm-docker-ipv6` bridge，
启用 IPv6、自动 IPAM、精确项目/组件/Compose 标签，无固定 subnet 或新增 cap/device/端口。
已有异属网络拒绝使用，清理仅删除归属完整匹配且空闲的网络，不强制断开任何容器。
候选、取消、切换、失败恢复、回滚、down 和评估隔离均保留正确网络归属；
普通非 IPv6 操作不增加网络查询。TUN/TProxy host-network 仍拒绝 routing。

Linux amd64 合同定向 `24.725` 秒、菜单 PTY `30.487` 秒通过；
完整 Docker `31/31`、`295.183` 秒、Jobs `6`，ci `39.780` 秒、Jobs `3`，
相同源码内容实际执行、未命中缓存，排队 `358` / `262546 ms` 单列。
随后 Reality 部分服务恢复关闭网络补丁经 IPv6 合同 `28.514` 秒、
phase6 `27.841` 秒补验通过，不把先前完整快照计作该补丁的完整回归。
隔离 nested daemon 真实回归双核心 × control/selective/global/off，共 8 次核心启动；
实际 IPv6 默认路由、非回环核心出站、双 A/AAAA TCP/UDP、A-only 零 IPv4/代理连接、
hosts、字面 IPv4、Direct/Block/IP/BT/SOCKS 优先级、关闭恢复与网络归属清理通过。
外层测试权限仅精确 selector 获取，不挂宿主 Socket、不开 host network 或宿主端口；
核心/夹具 cap_drop ALL、只读、UID 10001，无设备映射。
最后真实回归 `36.963` 秒，SIGTERM 正常退出消除固定 10 秒强杀等待；
相比先前成功轮 `50.248` 秒约降 `26.4%`，断言未减，不将全部差异归因于该优化。
复用工具镜像和离线业务镜像归档；缺失 nftables 已从 Debian 官方源补入工具层。
入口自检、11 Shell Bash/ShellCheck error、Python AST、Schema/features JSON、
PowerShell AST、diff 检查及独立只读复审通过。
原生 IPv6 离线查看/卸载、警告续行与 EOF 修复独立签名提交 `71396daf`，
`ui-full-core` `501 ms` 通过。
证据 `.tmp-docker-routing-5b4a-evidence.md`；重复源码和核心副本清理，日志与结果保留。
公网 IPv6、真实宿主、arm64、可信发布与 WARP 未验收，
完整 routing-tools/internal-206 保持 `deferred`。

#### 5B.4b 用户态 WARP 出站

独立 v3 `.routing.warp` 保存七个字段 `mode`、`family`、`private_key`、
`peer_public_key`、`ipv6_address`、`reserved`、`domains`，门禁为 `x-padm-routing-warp`。
selective 要求 1–256 条唯一规范四类规则，global 的 domains 必须为空；
规范 32 字节 Base64 密钥、三个 u8 reserved 及 global/ULA IPv6 字面地址写前校验。
菜单 `17` 的 `20` 与 CLI `--warp <root 私有 JSON>`、`--warp-off`
复用安全输入快照、确认、候选校验及失败/信号恢复事务。
状态仅投影 mode/family/domains，预览仅字段路径，不暴露密钥。
关闭仅删除 WARP 子项，普通 `--spec` 冻结 routing，旧包在配置/更新/恢复前拒绝。
功能签名提交 `fe2c3b87 feat(docker): add owned userspace WARP egress routing`。

固定 Peer `162.159.192.1:2408`、MTU `1280`；IPv4 隧道为 `172.16.0.2/32`，
IPv6 为导入地址 `/128`。family 同时选择隧道地址及匹配域名的解析族，
不转换字面目的 IP，不承诺公网出口地址族，不注册账号或安装第三方注册器。
Xray 显式 `noKernelTun:true`，sing-box 显式 `system:false`；
不新增生产权限、TUN、宿主接口、端口、网络或 net-wireguard 依赖。
Direct → 域名/IP/BT Block → selective IPv6 → selective WARP → SOCKS；
global WARP 保留显式 IPv6/SOCKS，重复默认出站写前拒绝。
hosts 与指定 DNS 来源保持，匹配 DNS 失败不回退系统解析或直连。

Linux amd64 双核心 × control/selective4/selective6/global4/global6/off 共 12 次真实启动；
隔离 namespace 的真实内核 WireGuard Peer 验证握手、加密传输计数、隧道源地址、
TCP/UDP、字面及双 A/AAAA 目的、非 53 指定 DNS、hosts 零 DNS、策略优先级与关闭恢复。
非零 reserved 先逐包记录，再适配标准内核 Peer 的头部，不能等同 Cloudflare 验收。
业务核心及服务 UID/GID `10001`、capabilities 全零，用户态核心不创建接口；
外层测试权限只给精确 selector，network none，不挂宿主 Socket 或发布端口。
Peer 失联只证明 1 秒观测窗口无直连/代理接入，保持失联到核心退出后再恢复。

集中完整 Docker 合同 `31/31`、`303.869` 秒（Jobs `6`）和 ci `34.466` 秒
（Jobs `3`）实际执行通过；快照先于最终域名 UDP 与 DNS 同源修复，不冒充最终同源码全套。
最终 WARP 合同 `26.169` 秒、IPv6 补验 `27.774` 秒、菜单 `30.738` 秒、
phase6 `26.009` 秒、入口自检与静态检查通过。
真实验收发现 pinned Xray `v26.3.27` WireGuard 域名 UDP 目的保留问题，
用 outbound 顶层 `targetStrategy:ForceIPv4/ForceIPv6` 在拨号前解析；
sing-box `v1.14.2` 的 resolve 会覆盖已有地址，改为同一 matcher 的 resolve 后立即 route，
只给未匹配者 local resolve，保持 IPv6 原输出；最终合同/IPv6/真实定向补验通过。

HTTP 正例精确比较完整固定响应，不等待 EOF，拒绝仍要求实际断开且不接受超时冒充阻断。
相同真实场景 `39.153` → `6.372` 秒，约降 `83.7%`，断言未减；
入口为 `40.061` → `7.327` 秒，队列等待分别 `191` / `5413 ms`，不混入执行加速。
复用工具镜像、固定核心程序和现有 DNS/HTTP/SOCKS 服务，不重复全套或扩大三槽预算。
原生菜单 WARP partial EOF/变量污染同步修复，独立签名提交 `d1142ed5`，
`warp-config-safe-dir` `46 ms` 通过。
证据 `.tmp-docker-routing-5b4b-evidence.md`；日志/result 保留，重复源码/核心副本清理。
Cloudflare 账号、公网 UDP/出口、原生宿主、arm64 与可信发布仍未验；
完整 routing-tools/internal-206 和 5B/5C 保持未完成。

### 5C. 宿主集成与端口跳跃

- 完善 WireGuard、TUN/TProxy、Fail2ban 的管理流程及内部 `203`、`204`、`205`；
  已有 profile 不等于全部原生向导和恢复能力完成。
- 补 Hysteria2/TUIC 端口跳跃：Docker 端口发布与宿主 DNAT 合同共同设计，
  明确 IPv4/IPv6、规则后端、目标地址、范围冲突和规则所有权。
- 所有宿主功能先检查内核、设备、权限、接口及现有规则；
  记录本项目资源，失败、关闭和卸载只撤销本项目拥有的变更。
- Fail2ban 必须验证真实客户端来源可见；不可见时不启用封禁。
  防火墙后端、主机发行版与内核的支持范围以实测记录为准。
- 宿主系统更新、BBR/网络优化作为明确的宿主操作子项，先预览影响并确认；
  若没有可验证的实现，则继续 `unsupported`，不得标记为普通容器能力。
- VLESS Encryption 实验单独评估配置、客户端兼容及回滚；
  评估和测试通过才开放，否则记录具体阻塞及支持限制，不静默漏掉。

验收：真实 Linux 内核下覆盖预检、启停、失败恢复、重启及卸载；
外部接口、规则和其他项目不受影响；5C 完成对应跳跃测试后才能升级协议完整管理状态。

现有 Fail2ban profile 的基线修正（2026-10-06，不计为 5C 完成）：
使用 Fail2ban 原生地址族动作，逐公开端口生成和清理 conntrack hook；
按受保护 WS 的地址族决定 IPv6 预检，禁用 Alpine 默认 SSH jail。
第二端口安装失败会撤销本次新链及 hook；TERM 等待服务退出后清理规则，
旧状态端口清理不覆盖当前启动参数。
`docker/tests/fail2ban-real.sh` 在隔离网络空间验证配置解析、IPv4-only、IPv6 缺链拒绝、
双栈双端口规则、IPv4 解封、部分安装失败后重试、TERM 清理及同容器 SQLite 恢复；
最终耗时 43.449 秒，Linux 源码快照 `phase4` 14.38 秒通过。
实测使用 amd64 本地 net 镜像 `padm-local/padm-net:fail2ban-before-3c1`
（ID `sha256:f84a3720bebef4035d36346081d68fbf70603aef38c9731200ae8afca4fc9900`，
Fail2ban 1.1.0），只读挂载当前生成配置及入口，未重建或发布镜像。
复现：`PADM_TEST_NET_IMAGE=<已有 net 镜像> bash docker/tests/fail2ban-real.sh`。
未验证日志触发、真实来源及网络丢包、IPv6 解封、容器重建、宿主重启或卸载；
因此完整管理仍为 `deferred`，不扩大发行版、防火墙后端或架构支持范围。

## 第六步：发布与完整验收

本步做整体验收，不把前面阶段的 CI 或文档更新拖到这里。

- 每阶段同步中英文使用说明、支持矩阵、权限边界及失败恢复操作。
  旧部署迁移明确要求完整 spec 或安全导入，不允许一条重配命令替代迁移。
- PR 按实际改动运行合同、Compose、菜单 PTY 和定向回归；
  涉及生成器/镜像时增加真实配置检查和对应协议连接。
- Release 在干净的 rootful Linux 上验证 `amd64/arm64` 的安装、首次配置、
  重启、升级、规格迁移、回滚、卸载和客户端连接；需要内核的 profile 单独实测。
- 部署灾备单独定义归档版本、文件清单/摘要和安全恢复事务：
  包含受管规格、部署状态、配置、业务数据、证书、ACME 账户及已启用集成的必要密钥，
  排除镜像层和缓存；校验路径、权限、格式及目标主机兼容性，恢复前保留现状。
  宿主规则按状态重新预检生成，不能把旧主机规则不加判断地覆盖到新主机。
- 在全新主机验证灾备恢复和服务连通，损坏/越界归档或恢复失败不得破坏原状态。
- 记录每项测试的架构、主机条件、镜像 digest、结果和日志位置。
  模拟 Docker、Compose 静态检查、容器健康和真实客户端连接分别报告。
- 复用现有签名与 Release 门禁；未通过所需证据的新增能力不开放，
  最终不宣称尚有管理差距的版本已实现“全部功能对齐”。

## 功能归属与完成门槛

以下分配覆盖第一步矩阵中的功能键，表示后续交付归属，不改变当前支持状态。

| 功能键 | 子步骤 |
| --- | --- |
| `interactive-menu` | 2A–2C，后续管理项随所属阶段增加 |
| `tls-files`、`acme-dns` | 2C 首配；3B 通用轮换 |
| `nginx` | 3C 协议必需入口/fallback；5A 站点管理 |
| `reality-target-management`、`reality-parameter-management`、`reality-coexistence` | 3D |
| `entry-port-management` | 3A、3D |
| `subscription`、`subscription-users`、`subscription-traffic`、`cdn-entry-management` | 4A |
| `core-lifecycle`、`script-update`、`uninstall`、`core-upgrade-assessment`、`geo-data` | 4B |
| `subscription-multiserver` | 4C |
| `wireguard`、`internal-203-wireguard` | 4C 最小控制连接与所有权前置；5C 完整管理 |
| `acme-webroot`、`acme-standalone`、`site-static-redirect-alpn` | 5A |
| `routing-tools`、`internal-201-socks-relay`、`internal-202-http-relay`、`internal-206-routing-rules`、`internal-207-access-control` | 5B |
| `fail2ban`、`tun`、`tproxy`、`internal-204-tun`、`internal-205-redirect-tproxy` | 5C |
| `network-optimization`、`vless-encryption` | 5C 独立宿主/实验子项；未验收仍不支持 |

新增能力提交时同步更新文档、配置合同、生成器/Compose、控制入口及证据。
[`phase3.sh`](../docker/tests/phase3.sh)当前固定 `supported` 协议为 `[1, 2, 3, 4, 5, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]`，
并要求菜单和管理差距为 `deferred`；后续按真实交付更新这些基线断言，
保留协议注册表、核心/profile、网络权限和前置条件的一致性检查。
不得只删除断言或只修改 `features.json` 来宣称完成。

4B.1–4B.2 已完成本地与对应真实 amd64 验收，4C.1 已建立独立只读 API，
4C.2 已实现被控端同步事务，4C.3a–4C.3d4 已补 WireGuard 归属、专用健康、
主控管理、被控接入/手动同步及回滚保护，4C.4a 已完成真实加密链路和规划验收；
4C.4b 的真实双部署事务验证见上；后续进入 5A 站点与剩余证书流程，
完整角色迁移、重绑定与灾备另行定义。
3B.4 的真实 DNS、整机重启及原生 arm64 证据，以及第二步真实发布与连通证据继续待补，
发布门禁不因本地测试通过而放宽。第三步复用 2C 的规格保存和恢复事务，
4A 依赖 3A 的编辑/迁移合同；
4C 可在 4A 和最小 WireGuard 前置通过后独立验收，不阻塞本机日常管理。
端口跳跃明确依赖 5C；所有阶段均执行适用的取消、异常、恢复及真实环境检查。
