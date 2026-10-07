# Docker 菜单与功能对齐实施计划

修订日期：2026-10-07

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
| 3. 配置编辑、证书与协议管理 | 3A.1–3A.3 已提交，3B.1–3B.3 已通过本地验收，3B.4 部分真实验收通过，3C.1 已交付，3C.2–3C.12 基础入口已通过本地与 amd64 传输验收，3D.1 参数重生成、3D.2 当前目标站菜单已接入 | 可恢复的编辑输入、多入口、双核心、TLS 轮换及自动续期底座、协议逐项安装与管理 |
| 4. 用户、订阅与服务维护 | 未开始 | 本机用户业务、多服务器后端、分范围备份恢复、核心运维 |
| 5. 站点、路由与宿主集成 | 未开始 | 站点管理、内部能力、规则所有权及可撤销宿主操作 |
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
不能用目标站检测或镜像支持 stream 宣称共存菜单已经可用。

| 检查点 | 状态与交付 |
| --- | --- |
| 3D.3a 镜像前置 | 已通过本地验收；Nginx 安装同版本锁的 `nginx-mod-stream`，加载模块并提供独立 `stream.d`。发布预检覆盖两种架构的模块缺失，刷新上游拒绝主程序/模块 ABI 版本不一致。 |
| 3D.3b 受管拓扑 | 待实施；沿用 v3 可选共存绑定，保留原入口端口作为关闭后的映射，不重建账号或密钥。共存生成、规格/部署匹配、端口预检及链接必须使用同一有效公网端口。 |
| 3D.3c 菜单与事务 | 待实施；配置、状态、关闭与更换默认入口走现有编辑事务。明确停止旧 443 拥有者再交接，失败恢复旧映射；真实验证两类流量及端口交接。 |
| 3D.3d 同机真实网站 | 待实施；区分容器内受管 TLS 后端与宿主网站。宿主 loopback 不可用 bridge 内 `127.0.0.1` 冒充，按可路由地址或显式宿主网络分别验收；站点内容维护仍归 5A。 |

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
证据 `.tmp-reality-stream-prerequisite-evidence.md`；`reality-coexistence` 和协议完整
`management_status` 仍为 `deferred`，本检查点不开放菜单。

## 第四步：用户、订阅与服务维护

### 4A. 本机用户、分享订阅与业务备份

- 先定义稳定账号 ID、凭据、协议关联、启用状态、分享组/token、额度和累计流量语义，
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

验收：用户 CRUD、启停、额度、统计、token 撤销及不同客户端输出一致；
重配/升级不丢账号，损坏备份、并发修改和恢复失败保持可恢复状态。

### 4B. 日常服务与核心维护

- 菜单整合现有状态、日志、健康检查、启停重启、更新、回滚和卸载；
  更新或卸载后的菜单重新核对已安装 CLI/bundle，不能继续使用失效入口。
- 迁移核心预发布试跑与升级风险扫描，使用已验证的候选镜像和独立测试配置，
  不以普通配置检查代替升级评估，不现场构建核心。
- 实现 Xray Geo 数据更新、校验、定时任务和失败恢复；任务有所有权、锁和结果状态。
- 卸载、purge 和凭据替换保留适用的明确确认，菜单不增加生产跳过保护的开关。

验收：菜单与 CLI 的结果及退出码一致；更新失败可退回匹配规格；
Geo/试跑失败不修改生产配置；卸载不遗留本项目调度、不清理外部资源。

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

## 第五步：站点、路由与宿主集成

### 5A. 站点与剩余证书流程

迁移静态站点、302、ALPN 诊断/修复及 fallback 站点维护；
补 webroot 和 standalone ACME 的端口归属、停机范围、续期和失败恢复。
复用 3B 的证书事务，不再维护另一套证书提交逻辑。

验收：站点和证书修改失败可恢复；80/443 冲突在变更前发现；
challenge 后服务恢复，证书和控制凭据不被站点发布。

### 5B. 核心内路由与内部能力

迁移 WARP、IPv6、DNS/hosts、BT/区域阻断、路由和访问控制；
内部 `201` Socks、`202` HTTP、`206` DNS/Direct/Block、`207` Tunnel/dokodemo-door
按真实核心支持范围分别交付。能用核心配置完成的能力不授予宿主网络权限；
需要接口或规则的部分依赖 5C。

验收：DNS、出口、阻断和中继有真实流量验证；非法规则和更新失败恢复旧配置；
纯容器路径不改变宿主路由或防火墙。

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

下一验收项仍是 **3B.4：补齐真实 DNS、整机重启及原生 arm64 证据**；
第二步的真实发布与连通证据继续待补，
发布门禁不因本地测试通过而放宽。第三步复用 2C 的规格保存和恢复事务，
4A 依赖 3A 的编辑/迁移合同；
4C 可在 4A 和最小 WireGuard 前置通过后独立验收，不阻塞本机日常管理。
端口跳跃明确依赖 5C；所有阶段均执行适用的取消、异常、恢复及真实环境检查。
