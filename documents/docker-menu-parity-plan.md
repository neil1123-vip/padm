# Docker 菜单与功能对齐实施计划

修订日期：2026-10-15

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
| 4. 用户、订阅与服务维护 | 4A.1–4A.6、4B.1–4B.2 已交付；4C.1–4C.5 私网 API、主控/被控管理、手动同步与已有单 Peer 被控自动同步、归属/健康及事务/回滚保护已交付；隔离 amd64 双部署生产 CLI/Compose、业务流量、真实 cron 自主更新及失败/信号恢复整套验收通过；多 Peer、角色迁移/重绑定与完整灾备仍未交付 | 稳定分享身份与双核心认证/统计、本机用户业务、单 Peer 手动/自动同步、分范围备份恢复、核心运维 |
| 5. 站点、路由与宿主集成 | 5A.1–5A.3b、5B.1–5B.4b 本地合同及双核心双栈出站/解析/域名、IP、明文 BT、CN 预设、IPv6 bridge 与用户态 WARP 本地 Peer 验收已通过；5B.5a HTTP 中继和 5B.5c–5B.5d 额外端口/默认分享已通过适用本地真实验收；5C 已交付受管网络归属及 WS/控制面 Fail2ban，8c.3 专用 SSH collector/jail、菜单启停/解封与隔离 amd64 实际封禁/DROP/来源失效清理已验；继续 SOCKS UDP 发布、其余路由与宿主管理，原生宿主/arm64/公网/整机重启/完整卸载仍待验 | 站点管理、内部能力、规则所有权及可撤销宿主操作 |
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
- 相关子步骤合批实现和审阅，先做必要定向验证，再集中完整回归与阶段签名提交；
  不重复无变化矩阵，文档、测试和支持矩阵随实现更新。
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
带 Fail2ban 的 WS 入口端口在通用编辑中明确拒绝修改；
单入口专项端口联动见后续 5C.6d，不放宽本路径门禁。
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
和订阅 token；Fail2ban 关联 WS 的增删不开放，公开端口仅开放后续
5C.6d 的单入口专项迁移，通用协议管理仍拒绝。

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
Gecko 后续由 3C.3a 开放，端口跳跃范围以 5C.9c 为准；完整管理仍待补。

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

#### 3C.3a Gecko 混淆合批

v3 Hy2 的 `hy2.obfs.type` 接受 `salamander` / `gecko`，密码继续私密输入或确认后
随机生成，范围为 16–128 位字母/数字/_/-；不增加账号、配置生成器或秘密通道。
首配保留 y/n，新增 gecko；已有入口可切类型、空输入保留类型和密码，
复制沿用全部参数，关闭清除混淆，取消不写入。`local` 继续要求无混淆。
Gecko 规格要求 `x-padm-hy2-gecko`，旧 bundle 拒绝更新/回滚到不支持的 Gecko 规格，
无混淆和 Salamander 不要求新标记；包长等高级参数不开放。

定向 `docker-hysteria2` 入口 `81.748` 秒、`docker-setup-encrypted-udp` `66.163` 秒通过，
覆盖 BBR/Brutal、精确 URI、旧 bundle、秘密输入、取消、切换、复制与关闭；
集中完整 `docker-contracts` 一次通过，入口 `391.578` 秒、排队 `0.360` 秒，
Jobs 6、工具镜像复用、cache=false；共同祖先校验的 304 项差分含 Gecko/local 拒绝。
固定本机 sing-box image `d873efd0…` 的实际配置检查与 URI 派生客户端传输通过，
BBR/Brutal/Salamander/Gecko 各双族共 8 条 HTTP proof；复用现有真实节点，
保留三主题 H3、只读挂载、CA/SNI、关闭 404 和全部认证，入口 `62.064` 秒。
证据分别在 `.tmp-regression-docker-f256ddffabce4e21bd105128ddc0b90e/`、
`b5ed349021c04e6a8701f4e40e84bc7e`、`a775ec4d716d400bb98e8a860c24d5f3`。
完整合同证据为 `.tmp-regression-docker-8e8da4e6e28d46d995833a6e6a8fada0/`，
成功输入已由入口自动清理；未重复无变化的实际传输矩阵。
首轮真实脚本漏改旧链接数断言，在实际启动前退出；修为 4 并补失败行号后重跑通过。
未重建/发布镜像，未验公网/原生 arm64/第三方客户端 UI 或混淆抗识别收益；
协议 `management_status` 与总体计划继续 `deferred`，不能以本批完成关闭总目标。

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

#### 3D.4 XHTTP 预设与客户端 XMUX

本阶段收敛到已有 v3、Xray、协议 `2`、显式选中的单入口，不增加协议或传输原型。
协议菜单第 `10` 项支持状态、日常/兼容/流式/单并发、自定义和恢复缺省；CLI 为
`protocol xhttp-status [入口 ID]`、`edit --xhttp-preset <入口 ID> <daily|compatible|stream|single>`、
`edit --xhttp-xmux <入口 ID> <并发> <请求> <秒数>` 与
`edit --xhttp-xmux-clear <入口 ID>`，沿用发布资产、预览、确认与失败恢复。

日常 `auto`、兼容 `packet-up`、流式 `stream-up`，三者客户端 XMUX 为
`maxConcurrency:"16-32"`、`hMaxRequestTimes:"600-900"`、
`hMaxReusableSecs:"1800-3000"`；单并发为 `auto`、`maxConcurrency:1`，其余相同。
可选 `xhttp.xmux` 仅接受完整三键，值为规范十进制整数或范围；上界 `2147483647`，
并发下界 `1`、其余下界 `0`。拒绝缺键/未知键、负数、浮点、倒序、零并发和溢出。
Schema 检查字段形状，生产 jq 同时检查字符串范围顺序和数值上界。

XMUX 仅为客户端参数，服务端固定 XMUX 生成器保持；没有显式对象的旧规格和 URI 不变。
显式对象通过百分号编码的 `extra={"xmux":...}` 分享，并要求控制包能力
`x-padm-xhttp-xmux`；清除对象恢复旧链接格式。预设只豁免选中 mode/XMUX，
自定义与清除只豁免选中 XMUX，其余规格精确冻结；普通导入与新入口派生不得绕过 XMUX 冻结。
主订阅、分享组和本地链接统一刷新，认证、端口别名、账号和累计流量保持。

本地 Linux amd64 功能合同 `56.986` 秒、菜单 PTY `75.866` 秒、
真实链路 `20.886` 秒、分发合同 `1.683` 秒及完整 `docker-contracts -Jobs 6`
`376.685` 秒均 exit `0`，完整 `49/49` 且未命中缓存；最终合同与完整源码归档一致。
真实客户端只从生产 URI 解码参数，本地目标严格 TLS 1.3/h2 就绪，五组实际链路完成
`15` 次占用期请求及 `5` 次后续请求，原点精确 `20` 次；日志确认运行模式、
HTTP/2、五组 XMUX 创建及单并发/自定义的并发上限分支。服务端固定 XMUX 不变。
事务、预览、健康失败恢复、取消/信号、无入口拒绝和已有显式 XMUX 的同协议菜单派生，
以及认证、其它入口、端口别名、额度、主订阅和分享组保持由生产 CLI 合同验证。
真实脚本的 jq 作用域/必需字段错误和独审发现的派生丢 XMUX 回归均已修复；
失败日志保留，重复源码归档在验收后清理，证据 `.tmp-xhttp-close/acceptance.md`。
不据此宣称长时复用或吞吐收益；有限 Padding 见 3D.5，首部开关见 3D.6，四项 packet/stream limits 见 3D.7。
其它 sc*、自定义 headers、downloadSettings、H3/CDN、
上下行分离和完整协议管理仍 `deferred`，公网、原生宿主、arm64 和可信发布仍待验。

#### 3D.5 有限 XHTTP Padding

沿用已有 v3、Xray、协议 `2`、显式选中单入口的事务。
`edit --xhttp-padding <入口 ID> <值>` 设置可选 `xhttp.xPaddingBytes`，
`edit --xhttp-padding-clear <入口 ID>` 删除显式值；菜单第 `8` 项设置、第 `9` 项恢复缺省。
仅接受规范整数或正序范围，端点 `1..4096`，`4096` 是本阶段产品支持边界，
不宣称为 Xray 官方上限。`0`/`0-0` 在 Xray 会恢复缺省，不能关闭 Padding；
Docker 明确拒绝零，恢复缺省使用 clear，状态显示缺省 `100-1000`。
拒绝 null、浮点、负数、倒序、非规范数字、溢出及未知字段。

服务端与客户端 URI `extra` 使用同一个显式值，与现有客户端 XMUX 合并。
两字段都缺省时保留旧 URI；清除 Padding 保留 XMUX，预设和 XMUX 编辑保留 Padding。
`protocol xhttp-status` 的 `explicit` 仍表示 XMUX，新增 `xPaddingBytes` 与
`padding_explicit`；显式 Padding 要求 bundle 能力 `x-padm-xhttp-padding`，
旧无显式字段的规格不增加门禁。
专项只豁免选中入口的 Padding，普通导入和新增入口不能绕过冻结；
同协议复制/派生继承，认证、其它入口、端口别名、额度及累计流量保持。
主订阅、分享组和本地链接沿原发布事务刷新，预览、确认及失败/信号恢复保持。

Linux amd64 定向合同 `105007 ms`、菜单 PTY `72544 ms`、
真实客户端/服务端 `24198 ms` 均 exit `0`；集成完整合同 `49/49`、
Jobs `6`、`416875 ms`、exit `0`，未命中缓存。
菜单、真实与完整快照各 `10` 个关键生产/测试文件逐项 SHA256 一致。
独审补回复制/派生的路径断言，由完整合同实际验证；首轮 copy PTY 多余空行已修。
真实客户端仅从生产 URI 构造，三入口显式 `1`、`100-1000`、`4096`，两入口缺省；
服务端逐入口等于 spec，原五组 `15` 次初始和 `5` 次恢复请求、精确 `20` 次原点请求，
TLS 1.3/h2、模式及 XMUX 运行分支断言保持。
证据 `.tmp-xhttp-padding-close/acceptance.md`，失败日志保留，重复归档清理。
不证明填充字节分布、抗识别、长时复用或吞吐收益；有限首部开关见 3D.6，四项 packet/stream limits 见 3D.7。
其它 sc*、自定义 headers、downloadSettings、
H3/CDN、上下行分离和完整管理仍未开放，公网、原生宿主、arm64 与可信发布仍待验。

#### 3D.6 有限 XHTTP 首部开关

范围保持已有 v3 Xray 协议 `2` 单入口，不开放自定义 headers。
CLI `edit --xhttp-headers <入口 ID> <true|false> <true|false>` 按
`noGRPCHeader`、`noSSEHeader` 顺序设置，`--xhttp-headers-clear <入口 ID>`
删除两字段恢复缺省；菜单第 `10` 项设置、第 `11` 项恢复缺省。
规格仅接受可选 boolean，拒绝 null、数值、字符串、数组和未知高级字段。
显式 `false` 与缺省分开：配置与 URI 保留前者，缺省不补字段或 `extra`；
任一字段存在都要求 `x-padm-xhttp-headers`，旧包只兼容无显式字段的规格。

固定 Xray `26.3.27` 中，`noGRPCHeader=true` 取消客户端 stream-up/stream-one
POST 的 `Content-Type: application/grpc`；`packet-up` POST 和分流 GET
本来没有该首部，开关不改变它们。Reality 的 `auto` 实际选用 `stream-one`。
`noSSEHeader=true` 取消服务端 stream-one POST 或分流 GET 下载响应的
`Content-Type: text/event-stream`，不影响上传响应。缺省和 `false` 保持原行为。
第一门直接运行固定镜像二进制，在独立 `--network none` Linux 容器的回环 TLS/h2
记录 HTTP/2 HEADERS；三模式、三取值、客户端与服务端共 `18/18` 对照通过，
另核对上传 POST 非 SSE 控制。客户端固定自签证书摘要，不使用跳过校验开关。

专项只豁免所选入口两字段，保留 mode/XMUX/Padding、其它入口、认证与累计；
复制、同协议派生继承显式值，普通规格导入或新入口不能绕过冻结。
服务端生成和客户端 `extra` 同步，同一链接生成器刷新主订阅、分享组和 CLI；
沿用预览、确认、备份及失败/信号恢复，不增加发布或恢复分支。
2026-10-12 定向 `docker-xhttp`、菜单 PTY 均 exit 0，入口分别
204487 / 82124 ms，Jobs 2，同源码快照 `6E303D5C...C22076`。
正式 `docker-xhttp-real` exit 0、26281 ms；18 组外层首部观察、
五组 Reality 双端 TT/TF/FT/FF/缺省、严格 URI boolean/存在性、
原 20 条业务请求、h2/mode/XMUX 命中断言均通过。
首部观察的 TLS 使用证书固定摘要或受信 CA/主机名校验；
新增 cid 字节串解码修复后通过，首轮失败日志保留。
工具层通过 Debian 官方源补 `python3-h2` / `python3-yaml`，复用原镜像大层；
独立只读生产审查无阻断，容器、卷及临时私钥已清理。
证据 `.tmp-regression-docker-01ce9bf2a2754806b0eac6ff76712f76/`、
`.tmp-regression-docker-982c1bb4b8504e2b89a9a6401a1d24d9/`、
`.tmp-regression-docker-c711111f21064b4a81774a7e5f2e3c70/`。
集中 `docker-contracts -Jobs 6` 49/49、exit 0，入口 642923 ms、
排队 3898 ms、cache_hit=false；复用同一工具镜像，不重复完整矩阵。
证据 `.tmp-regression-docker-f5f002d9b7dc41d798f7d2c7eb94b197/`；
17 个变更文件与该完整快照逐字节匹配，之后仅补验收文字。
Bash/ShellCheck error、JSON、Python AST 与 workflow YAML 检查通过。
四项 packet/stream limits 见 3D.7；其它 sc*、自定义 headers、downloadSettings、H3/CDN、
上下行分离与完整管理仍 `deferred`；
首部变化不证明抗识别、长时复用或吞吐收益，公网/原生宿主/arm64/可信发布待验。

#### 3D.7 原生 XHTTP packet/stream limits

本轮实施已有 v3 Xray 协议 `2`、显式选中单入口的四项原生 limits，
不开放自定义 headers 或其它 `sc*` 字段。
CLI `edit --xhttp-limits <入口 ID> <post> <interval> <buffered> <secs>` 设置
`scMaxEachPostBytes`、`scMinPostsIntervalMs`、`scMaxBufferedPosts`、
`scStreamUpServerSecs`，`edit --xhttp-limits-clear <入口 ID>` 清除四字段；
菜单第 `12` 项设置、第 `13` 项恢复缺省。
前三项仅接受规范整数 `0..2147483647`；最后一项接受同范围整数或正序范围，
拒绝负数、浮点、倒序、非规范数字、溢出，前三项不接受范围。
空输入采用 `1000000/30/30/20-80`，前三项输入 `default` 保存 `0`。

`0`/`0-0` 使用核心缺省，但作为显式值保留在 spec、服务端及客户端 URI `extra`；
状态的 `limits` 显示核心生效值，默认分别为 `1000000`、`30`、`30`、`20-80`，
`limits_explicit` 区分任一显式字段与缺省。
清除删除字段，缺省不补 spec、server 或 URI；任一字段存在要求
`x-padm-xhttp-limits`，旧包只兼容没有显式四字段的规格。
专项操作与其它编辑专项互斥，只豁免所选入口的四字段；普通导入不能绕过冻结。
预设、XMUX、Padding、首部编辑保留 limits，复制和同协议派生继承，
服务端与 URI 的高级字段采用统一投影，主订阅、分享组及本地链接同事务刷新。
认证、其它入口、端口别名、累计流量和额度沿用原冻结与失败恢复。

2026-10-15 本地 Linux `amd64` 容器的定向、真实、菜单与 dispatcher 均 exit `0`：

| 验收 | 入口耗时 | 证据目录 |
| --- | ---: | --- |
| `docker-xhttp-limits` | `30079 ms` | `.tmp-regression-docker-98a95f28b7a147d7902acfd40724d06a/` |
| `docker-xhttp-real` | `25743 ms` | `.tmp-regression-docker-bd8dca2ab5c84146a4a6c20b39e7c3eb/` |
| `docker-menu` | `55976 ms` | `.tmp-regression-docker-8d876cda131a45f6a0143a80f324ddc7/` |
| `regression-dispatcher-contract` | `2217 ms` | `.tmp-regression-docker-2a9d8c618eff42cdbd9b8b5471cdb0ce/` |

真实链路保持 5 个入口、20 条业务请求，覆盖 `32768 > 16384` 字节的 packet POST；
服务端与 URI limits 等于 spec，缺省兼容，原 h2/模式/XMUX 分支断言保持。
菜单首轮因新入口标签不匹配失败，校正后通过；原失败目录
`.tmp-regression-docker-e0e9c631948840cf8297cc5afb036758/` 保留。
集中 `docker-contracts -Jobs 6` 仅运行一次，exit `0`、入口 `383362 ms`、
内部 `381215 ms`、排队 `320 ms`、`cache_hit=false`，345 项规格差分通过；
证据 `.tmp-regression-docker-94698fa5854848aa852850ad4ba398f2/`。
复用工具镜像，完整工作区为容器内 tmpfs；完整与成功菜单 source 摘要一致，
之后仅补文档，不以容器验收推断公网、原生宿主、arm64 或性能收益。

`management_status` 保持 `deferred`；其它 `sc*`、自定义 headers、
downloadSettings、H3/CDN、上下行分离、完整管理及公网/原生宿主/arm64/可信发布
仍待实施或验收，不宣称吞吐、填充分布、长时复用或抗识别收益。

#### 3D.8 Hy2 带宽与 TUIC 参数专项合批

复用已有 v3 sing-box 规格、生成器、URI 和编辑事务，协议菜单新增 `12`
Hysteria2 管理、`13` TUIC 管理。`protocol hy2-status/tuic-status [入口 ID]`
先核验在线基线，状态不输出密码。
`edit --hy2-bandwidth <入口 ID> bbr` 仅修改模式并保留速率；
`brutal <up> <down>` 一次设置模式和服务端上下行整数 `1..1000000` Mbps，
菜单默认 `100/50`，URI 转换为客户端方向。
TUIC 提供 `--tuic-congestion`、`--tuic-connection`、`--tuic-zero-rtt`、
`--tuic-defaults`，推荐恢复 `cubic/3s/10s/false`；时长沿用 1–6 位
正整数加 `ms/s/m/h`。CLI 沿用 `--preview/--confirm PADM-DOCKER-EDIT`，
开启 0-RTT 菜单保留默认否与重放风险确认。

每次只改已有单入口的选中字段，不能组合规格导入或其它专项；
其它入口、身份/认证、TLS、Hy2 混淆和伪装、统计与额度保持冻结。
菜单 `0`、EOF、INT 和 0-RTT 拒绝不调用编辑；状态失败不进入写入。
候选、链接发布、健康失败及信号恢复复用现有事务，不新增依赖或能力标记。
定向合同复用 `docker-tuic` 已串接的 Hy2 基线，菜单合并验证，
集成后集中一次 `docker-contracts`，不重复既有真实客户端参数矩阵。

2026-10-15 本地 Linux `amd64` 定向验收 exit `0`，复用工具镜像：

| 验收 | 入口耗时 | 证据目录 |
| --- | ---: | --- |
| `docker-tuic`（串接 Hy2） | `152468 ms` | `.tmp-regression-docker-f2d3d4f340714d28a7d74dac15dc3631/` |
| `docker-menu` | `59860 ms` | `.tmp-regression-docker-2a19e6e644c54892b91f911179b20c48/` |
| `regression-dispatcher-contract` | `1630 ms` | `.tmp-regression-docker-3d01499056d648a8b4bb476c1e654402/` |

新增合同覆盖 BBR 保留速率、Brutal 客户端方向、TUIC 四专项/default、
私密状态、非法/互斥、字段篡改拒绝、预览/交互取消和健康失败恢复；
菜单合并覆盖成功、返回/EOF 和失败继续诊断，原信号合同保持。
首次 TUIC 测试误用 `users.base` 作为 `config.json` 基线；改为各自保存原文件，
其它字段精确冻结未放松，补跑通过。失败证据
`.tmp-regression-docker-c01b0c570b8a4eda8e84dbb99bd2e0df/` 保留日志/result。
当前源码复制到容器 Linux 文件系统后的 Bash/ShellCheck error/JSON 检查通过，
独立只读复核通过，无新依赖。
完整 `docker-contracts -Jobs 6` 一次通过，入口 `393961 ms`、内部
`391886 ms`、排队 `363 ms`、`cache_hit=false`，345 项规格差分通过；
证据 `.tmp-regression-docker-e9356036913948ecb3db54dd2a4d684d/`。
完整与修正后的 TUIC 定向源码摘要一致，随后仅补验收文字；
成功输入归档由入口清理，本轮静态脚本与失败输入已清，保留日志/result。

完整协议管理、TUIC 跳跃、自动恢复、重装/卸载、宿主集成组合、
原生宿主/arm64/公网仍 deferred，整体计划保持 active。

#### 3D.9 Hy2 混淆与伪装专项合批

沿用菜单 `12` 与单入口事务，`--hy2-obfs` 提供 `salamander/gecko/off`，
`--hy2-masquerade` 提供 `off/local/HTTPS_URL`，不扩规格或依赖。
非交互开启混淆仅接受 root 0600 单链接私密 JSON 的唯一 `password` 字段，
16–128 位字母/数字/下划线/连字符；交互复用通用编辑的静默输入，
空输入保留旧值、无旧值才随机，`0`/EOF 取消不写入。
密码补丁只经候选私密文件进入 jq，公开冻结比较仅使用字段键。
每次只豁免选中入口的 `obfs` 或 `masquerade`，其它参数、入口、TLS、
账号及累计额度冻结；发布、健康失败和信号恢复沿用原事务。
local 先验证已发布受管 static 网页且混淆已关闭，不自动创建站点或关闭混淆；
Gecko/local 复用既有 bundle 门禁，不重复未改变的真实客户端参数矩阵。
2026-10-15 Linux amd64 定向 Hy2 `106702 ms`、菜单 `57549 ms` 通过，
复用工具镜像，容器内 Bash/ShellCheck error/JSON 及独立复核通过。
Hy2 首次新增静默读取断言受 `IFS=` 拼接影响，改逐参数检查 `-s` 后补跑；
菜单已通过且未再修改，不重复单跑。集中完整首轮仅跳跃监督 stop 夹具失败：
夹具停止预算 50 ms、故意延迟 100 ms 清理，原测试过早检查进程消失。
仅该故障案例加 1 秒有界观察，不延长生产时限或放松锁/owner/清理断言；
监督定向 128 项、`29755 ms` 通过，随后重跑集中完整合同。
证据分别在 `.tmp-regression-docker-db18b429da1a4585b51ee643c78e1757/`、
`.tmp-regression-docker-55e1433551634fb98ef1ef0f2cb72f94/`、
`.tmp-regression-docker-8c0dece3a51e420cbb14d666aa99e399/`。
失败输入归档清理，日志/result 保留，不把失败结果计为通过。
修正后完整 `docker-contracts -Jobs 6` exit `0`，57/57 顶层检查通过，
入口 `375917 ms`、内部 `373947 ms`、排队 `332 ms`、cache=false，
证据 `.tmp-regression-docker-be0a079fc9204172afd4bb9a3d27f238/`。
源码与修正后的监督定向摘要一致，之后仅补验收文字；
成功输入由入口清理，失败输入已清，无新增依赖或本机临时脚本。
完整协议管理及剩余宿主/arm64/公网验收仍 deferred，整体计划 active。

#### 3D.10 XHTTP 常规与高级管理合批

菜单 `14`–`17` 和 CLI 一批接入已有 v3 Xray 协议 `2`：
`--xhttp-mode` 仅改模式，`--xhttp-path-host` 成对改安全路径和非空域名 Host，
`--xhttp-advanced` 一次设置 Padding、POST 字节数、间隔毫秒、缓冲 POST 数、
流式秒数、noGRPCHeader、noSSEHeader，保留 mode/XMUX。
`--xhttp-defaults` 恢复 `auto`、XMUX `16-32/600-900/1800-3000`、
Padding `100-1000`、首部 `false/false`、limits `1000000/30/30/20-80`，
保留 path/host；区别于只改 mode/XMUX 的日常预设。
状态增加 path/host，七项高级参数复用既有数值/范围/布尔校验；
每个专项精确豁免相应字段，其余入口、认证、端口、TLS、额度及累计冻结。
复用既有能力标记、生成器、URI、发布与失败恢复，不扩规格或引入依赖。
2026-10-15 Linux amd64、工具镜像复用，XHTTP 定向 `80355 ms`、菜单 `57575 ms`
通过，Jobs 2；集中 `docker-contracts -Jobs 6` 一次通过，57/57 顶层检查，
入口 `380824 ms`、内部 `378845 ms`、排队 `324 ms`、cache=false。
证据分别在 `.tmp-regression-docker-1d65c8defa05486faa7a1af614663a9f/`、
`.tmp-regression-docker-25bd30ff63b74b7e9300166050ff5be9/`、
`.tmp-regression-docker-bc9bb6dbe82246868c300bca5b5fe841/`。
三份结果的源码 SHA-256 相同，之后仅补验收文字；成功输入归档已清，
日志/result 保留，无新增宿主依赖或临时脚本，不重复未改变的真实客户端矩阵。
downloadSettings、H3/CDN、上下行分离、完整管理及宿主/arm64/公网继续 deferred；
整体计划保持 active。

#### 3D.11 已有部署的协议增删与保身份重建合批

协议菜单 `14/15/16` 与 `edit --protocol-add/--protocol-remove/--protocol-rebuild`
复用现有候选、预览、确认、流量采集及失败恢复事务，不新增规格或依赖。
专项要求已有 v3 规格和唯一入口 ID，不能与外部规格导入或其它专项组合。
新增只追加一个同核心入口，沿用 UUID、服务器、地址族及受管 TLS；
Reality 只从已有 Reality 派生，Naive 的服务器固定为已有证书域名。
不启用新核心、申请证书或创建 Shadowsocks 服务端密钥，不扩已有账号授权。
从原规格重新生成唯一允许结果并完整比较，不能借专项修改其它字段。
删除清理入口关联账号、alias/CDN，继续拒绝账号最后关联、主核心最后入口、
Reality 共存绑定及受 Fail2ban 保护的入口；证书、订阅身份和累计沿用原规则。
重建要求完整规格全等，重新验证并按现有事务统一重建核心，不声称只重启指定入口。
复制、Reality 派生及删除复用共享 helper，fallback 同协议复制保持共享后端，
不同协议新增分配内部监听；已有入口端口和参数冻结不变。

合同合并覆盖 Reality→XHTTP、Hy2→TUIC 的候选与实际生成配置、预览/PTY 取消、
成功和失败恢复、删除与账号最后关联、订阅/累计保持；
小型草稿检查补 Naive 域名、HTTPUpgrade/fallback 端口分配和 TLS/核心/SS 边界。
菜单同一 PTY 批次验证取消、成功分发、失败与列表失败后继续操作。
2026-10-15 Linux amd64 定向 entries `86814 ms`、菜单 `57252 ms` 通过，Jobs 2。
初轮发现新 WS/HTTPUpgrade 路径不足 8 位，生成改为 `entry-*path`；
随后修正 fallback 夹具的旧 WS 身份，未放宽路径或身份验证。
完整首轮发现错误地重分配同协议 fallback 后端，已恢复原共享行为与冻结比较，
仅不同协议新增分配内部端口；补充对应断言，setup TLS 定向 `45111 ms` 通过。
修正后完整 `docker-contracts -Jobs 6` 57/57 通过，入口 `354626 ms`、
内部 `352685 ms`、排队 `322 ms`、cache=false，347 项规格差分通过。
证据 `.tmp-regression-docker-2da92b453763499a9d0b9e347132d492/`；
完整已重验修正后的 entries、菜单与 setup，不重复单跑这些已通过分片。
工具镜像复用，成功输入由入口清理，失败输入合计清理 `41,420,010 bytes`；
日志/result 与输入摘要保留，回归后仅补验收说明。
完整协议管理和原生宿主/arm64/公网仍 `deferred`，整体计划保持 active。

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
| 4A.3 分享组与内容输出 | 已交付分享组 CRUD、账号/入口筛选、独立 token、启停与 token 轮换、纯订阅内容及 HTTPS 链接输出；CDN 连接地址见 4A.5，H3 仍待后续阶段。 |
| 4A.4 业务备份恢复 | 已提交 `99ce706c`：账号、组、发布授权、额度、累计和格式版本的备份、冲突预览及 merge/replace 恢复；不以版本 rollback 冒充业务恢复。 |
| 4A.5–4A.5b CDN 连接地址 | 已实现协议 21/22/23/24/25 的多连接地址覆盖、CLI/菜单、统一链接输出与事务恢复；本地六组合实链路、严格拒绝探针、旧包兼容及完整合同通过；拒绝其余协议，完整 CDN 管理保持 deferred。 |
| 4A.6 流量与额度菜单 | 已交付账号菜单 `10 → 9`，复用已有 show/collect/limit/reset；查看不采集，额度 `0` 不限额，设置/重置各确认一次，重置保留额度。 |

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

#### 4A.5 WS/HTTPUpgrade TLS 的 CDN 连接地址

v3 可选 `cdn_entries:[{listener_id,addresses:[...]}]` 只接受已有协议 `21/22/23`，
最多 16 个唯一入口记录，每项 1–16 个唯一域名、严格 IPv4 或 IPv6；
空数组、空项、URL、端口、空白、错误引用和未知键拒绝。
无覆盖或清除字段后回退原 `.server`，不改核心、Compose、deployment 或 TLS 配置。
旧控制 bundle 须同时暴露字段和 `x-padm-cdn-entry-addresses`，配置、更新和回滚在停服前拒绝旧包。

CLI `protocol cdn-status [入口 ID]`、`edit --cdn-entry <入口 ID> <地址 CSV>`、
`--cdn-entry-clear <入口 ID>` 与协议菜单 `9 → 9` 复用部署锁、
完整规格基线、候选预览、确认和失败恢复；提交按现有事务重建服务。
专项冻结其它入口覆盖及全部非 CDN 字段；普通 `--spec` 不能新增或更换覆盖，
删除入口清理其覆盖，复制不继承。

同步修复菜单删除入口后账号关联残留：只裁剪已删除入口的关联，账号其它字段冻结，
删除账号最后一个关联入口明确拒绝。新生成的 `21/22/23` TLS 前端在 HTTPUpgrade
重写 Host 前拒绝错误 Host。更新保留完整旧 Nginx 正文的原语义；
无 CDN 字段时只接受完整新版或完整旧版正文，不能逐入口混合或放宽其它配置。
旧 HTTP-01 Host gate 保留，带 CDN 字段必须为新版；下一次确认配置编辑会生成新版。

统一生成器先展开原入口/账号与有效默认分享端口，再按地址顺序替换临时 `.server`。
多个地址名称追加 `-1`、`-2`，单地址保留原名；无覆盖输出字节不变。
本地 URI、主订阅及分享组共用实现，保留身份、SNI、Host、path 和端口，
组 token 与 HTTPS 订阅 URL 不变。
本阶段明确拒绝 Reality XHTTP/gRPC、gRPC TLS 及其它 TCP/UDP 协议，
不增加 H3 开关；原生 CDN 的完整协议范围和公网验收仍待补，
`cdn-entry-management` 保持 `deferred`。

Linux amd64 定向 `docker-cdn-entries -Jobs 2` 29222 ms、loader 1212 ms 通过；
集中 `docker-contracts -Jobs 6` 为 48/48、356003 ms。真实客户端
`21:xray`、`22:xray`、`23:xray`、`23:sing-box` 四组合 143126 ms 通过：
生产链接直接连接 IPv4/IPv6/域名和有效默认分享别名，覆盖/清除、TCP/UDP、
错误 UUID/SNI/Host/path 拒绝、源站计数与服务身份及非订阅文件保持均有断言。
隔离 daemon 使用离线业务镜像，不挂宿主 Socket，不重复额度验收。
证据分别为 `.tmp-regression-docker-09323614949542309e3186f27052406c/`、
`.tmp-regression-docker-1ed1448283d54269974f19ba05dfa18a/`、
`.tmp-regression-docker-dc58b03b386d439e9d92f4c3ae886c3c/` 和
`.tmp-regression-docker-7f5f265afa5b41e5b8950037c50ec0c1/`。
旧正文兼容补丁另经定向 `docker-cdn-entries -Jobs 2` 35961 ms 与完整
`docker-contracts -Jobs 6` 48/48、326698 ms 复验，入口总耗时 327687 ms，
排队 380 ms，`cache_hit=false`；精确旧夹具保留 HTTP-01 gate，逐入口混合、
其它漂移及带 CDN 的旧正文均拒绝，首次 CDN 提交整体升级至新正文。
补验分别见 `.tmp-regression-docker-cb9c3ef82c914e2baa7c675ade8d9da2/`
和 `.tmp-regression-docker-422c31fd76a041829d4fb5529d9171da/`。
公网 CDN、原生宿主、arm64 与可信发布不计为已验，总目标 active。

#### 4A.5b gRPC TLS 的 CDN 连接地址

沿用 v3 `cdn_entries` 和既有地址展开、候选事务及冻结边界，只追加已有
Xray 协议 `24/25`、受管 Nginx TLS 的连接地址覆盖；Reality gRPC/XHTTP、
fallback、其它协议与 H3 参数仍拒绝。状态/设置/清除菜单和 CLI 统一五种入口。
只替换链接连接地址，原账号认证、有效分享端口、TLS SNI、serviceName 与
`alpn=h2` 保持，本地链接、主订阅与分享组共用输出。
新增 `x-padm-cdn-grpc-tls` 能力门禁，仅规格有 24/25 CDN 映射时需要；
原三协议覆盖和无 CDN 映射的 gRPC TLS 可继续处理旧子集，不放宽旧包其它门禁。
Nginx 仍走既有 HTTP/2 `grpc_pass`，不把 WS Host/path 校验套到 gRPC。
合同复用原三协议事务和旧正文证据，补 24/25 身份、状态、链接、分享及旧包拒绝。
真实验收复用双栈边缘域名/IP、生产分享端口和现有认证客户端，
补 gRPC 错误认证/SNI/serviceName 与有效连接恢复、HTTP/2 协商及服务存活。
收紧已有探针的超时误判：TCP 拒绝须明确 SOCKS 失败或远端 EOF/reset，
客户端连接失败或超时直接失败；UDP 无应答仅作为关联 TCP 拒绝的补充观测。
gRPC 错误 SNI 单独从实际客户端 outbound 读取端点、公开端口、CA 与 SNI，
严格 TLS 握手须明确返回证书主机名不匹配；该证据不冒充 SOCKS 拒绝、
客户端内部重试或服务器 SNI 门禁，错误认证/serviceName 仍走实际 gRPC 流量。
公网 CDN 供应商透传、真实宿主、arm64 与可信发布继续待验，完整状态保持 deferred。

Linux amd64 定向 CDN 合同 49699 ms、菜单 PTY 67510 ms，通过；
完整合同 48/48、Jobs 6、438536 ms，与六组合真实链路 239769 ms
使用相同源码归档及工具镜像，均 exit 0、未复用缓存。独立复审无确定缺陷。
真实链路为 Xray `21/22/23/24/25` 与 sing-box `23`；覆盖 IPv4/IPv6/域名、
实际分享端口、设置/清除、严格 TLS 与 HTTP/2、明确拒绝和有效连接恢复。
首轮 gRPC 错误 SNI 的 SOCKS 超时使验收失败，修正后按上述独立 TLS 证据重跑全套。
未以客户端超时或 UDP 静默替代明确拒绝。
证据保留在 `.tmp-regression-docker-e3c52196c1f8480a8f072e101b7a927f/`、
`.tmp-regression-docker-8fd0325ea64d4c369d8b93288dd0689b/` 与
`.tmp-grpc-cdn-close/`，重复归档在核对输入后清理。
回归调度将 network-lifecycle 提前到第 7，并补已有 CDN 的顺序合同漏项；
本次与实链路混跑，完整耗时不作为孤立调度收益证据，不扩大三槽或 Jobs 6。

#### 4A.6 Docker 菜单流量与额度入口

账号菜单第 `9` 项复用已有 `traffic show|collect|limit|reset`，不新增流量后端、
状态文件或采集逻辑。查看显示已保存计数且不隐式采集；立即采集执行现有快照与额度检查；
设置额度和重置累计各做一次明确确认。额度 `0` 透传为不限额，空值或 `r/R` 返回；
重置只清上传/下载累计并保留额度。账号 ID 使用 `show` 输出原文，不 trim、不改大小写。

状态失败不读取账号或额度；未知账号、非法额度和后端失败保留既有退出码并返回子菜单，
失败后可继续查看诊断。采集、额度应用、核心重启、锁、权限和恢复边界沿用 CLI，
不声称失败时状态文件或采样基线会回滚。

Linux amd64 菜单 PTY 覆盖四动作、原样传参、`0`/小数额度、取消/EOF、状态失败、
非法额度、未知账号和后端失败；`docker-traffic` 后端合同保持独立。
菜单定向 exit 0，内部 113183 ms、入口 114344 ms、排队 210 ms、Jobs 2、
cache_hit=false，证据 `.tmp-regression-docker-61916ad038724df1855b8a5dcdbc575b/`；
流量后端定向 exit 0，内部 3766 ms、入口 4796 ms、排队 194 ms、Jobs 2、
cache_hit=false，证据 `.tmp-regression-docker-662aef3ba0b640f68944889c7340c9b4/`。
Bash、ShellCheck error 与独立只读复审通过，未改后端。
集中完整 `docker-contracts -Jobs 6` 53/53、exit 0，内部 565088 ms、
入口 566127 ms、排队 392 ms、cache_hit=false，直接复用工具镜像；
证据 `.tmp-regression-docker-684faed656f144fdb5dcdc00f543ec90/`。
7 个暂存文件与完整源码快照逐字节一致，回归后只补验收记录；
4A 其它真实宿主、arm64、重启和公网边界继续按原状态，总目标 active。

### 4B. 日常服务与核心维护

- 菜单整合现有状态、日志、健康检查、启停重启、更新、回滚和卸载；
  更新或卸载后的菜单重新核对已安装 CLI/bundle，不能继续使用失效入口。
- 迁移核心预发布试跑与升级风险扫描，使用已验证的候选镜像和独立测试配置，
  不以普通配置检查代替升级评估，不现场构建核心。
- 实现 Xray Geo 数据更新、校验、定时任务和失败恢复；任务有所有权、锁和结果状态。
- 卸载、purge 和凭据替换保留适用的明确确认，菜单不增加生产跳过保护的开关。

验收：菜单与 CLI 的结果及退出码一致；更新失败可退回匹配规格；
Geo/试跑失败不修改生产配置；卸载不遗留本项目调度、不清理外部资源。

本阶段菜单补齐提交 `b856ff61`：主菜单新增 `18. 服务维护`，复用既有
`validate`、`update`、`rollback`、普通 `uninstall` CLI。更新和卸载在菜单内先做
`y/N` 确认，不开放 `purge` 或 `--remove-images`；校验成功留在菜单，更新/回滚/
卸载成功结束旧菜单会话，避免继续使用已切换或已移除的 bundle，失败保留原退出码
并回到维护子菜单。8 组真实 PTY 覆盖成功、失败、取消、EOF 和维护动作分发。
Docker Linux amd64 `docker-menu` Jobs 2 测试 `31.822` 秒、入口 `32.751` 秒、
排队 `5740` ms 通过；容器内 Bash `-n`、ShellCheck error 级检查和 `git diff --check`
通过。未重复 phase6/完整回归；生产宿主真实生命周期仍待验。

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

本地完整多服务器仍为 `deferred`；4C.4b 不含自动同步，后续实现见 4C.5。
多 Peer、网络向导、角色重绑定、迁移与灾备未交付，原生 Linux 双机、
原生 arm64、宿主重启及可信发布验收仍待补。

### 4C.5 已有单 Peer 被控角色自动同步

范围收敛为已接入的 `controlled`、健康且归属一致的单 Peer WireGuard；
不自动 join、不建密钥/网络、不迁移角色。固定每 5 分钟，默认关闭。
新增 `control sync-schedule enable --invite <外部私有邀请> [--yes]`、
`disable [--yes]`、`status` 与无参 `control auto-sync`，菜单追加状态、
启用或更新邀请、停用。同一 enable 更新凭据；菜单路径取消/空/EOF 不分发，
启停仅由 CLI 确认一次。

本机 `secrets/control-sync/` 仅保存 root 私有 `request.json`、`invite.json`，
身份、连接和入口映射固定，不锚定上游 revision 或账号；token 不进 argv/env、
spec、配置/业务备份和普通日志，停用清除持久凭据。过期、撤销、断网不妨碍停用。
启用只做认证和规划，自动入口持同锁、试锁一次，竞争退出 12；正常 down 跳过，
半套、外来或停止容器拒绝。复用 ClientBuildDraft → AccountApplyDraft，
同版本不重建，新版本仍保留本机账号和累计；认证或候选失败保留原版本。

调度完整核验模板、root、FragmentPath、DropIn 和 cron 后幂等安装，
成功配置与失败恢复不能停止正在同步的自身 service。更新、恢复和回滚保留本机
登记；能力及候选身份在采集/停服前核对，旧 bundle 和无规格恢复点明确拒绝。
需要现场来源证明的 WS/SSH 防护组合不支持，不保存旧来源输入绕过门禁。
Linux amd64 定向、生命周期和菜单独审通过；集中完整合同 48/48，
328156 ms、Jobs 6、排队 373 ms、未命中缓存。319 个冻结源码输入哈希一致；
完整合同后的变化限真实夹具 PATH/诊断、文档与下一独立 WARP 阶段，不冒充同源码全套。
真实双部署的一轮由固定 cron 自主提交 revision 1，等待 338772 ms，保留每分钟流量调度；
同版不重建、锁竞争、网络/版本拒绝、轮换/撤销、健康失败/INT/TERM 恢复、
down/disable 零网络及私有凭据清理已通过，但尾部 up 立即检查健康导致整套退出 1，
不计为完整通过。夹具已补限时健康等待；后续 805d 重跑在 cron 等待 360 秒未推进，
私有执行记录在 b8f45 证明同一个五分钟边界 auto-sync 返回 12、traffic 返回 0：
两任务固定同秒争用同一部署锁，存在反复跳过风险。定时任务现改为边界后 15 秒执行，
systemd 使用秒级日历，cron 使用绝对 sleep 路径；直接 auto-sync 的立即试锁合同保持。
精确旧 timer/cron 可迁移或停用清除，同 backend 迁移和失败恢复不停止正在执行的 service，
陌生 root、时间、sleep、DropIn 或命令仍拒绝。长事务仍可能跳过单次任务。
真实夹具增加无凭据 CMD/END/rc 记录，首个实际 12 才允许下一固定边界的一次重试，
第二次 12 或其它失败立即拒绝，无任务记录不延时；移除没有必要证据的 HUP。
错峰定向 23012 ms、实际生成命令/精确旧模板迁移/恢复及独审通过，
证据 `.tmp-regression-docker-add4b5e5b0c747379a839eb0b0840215/`。
错峰集成后真实双部署整套 exit 0，入口 739235 ms、Jobs 2、排队 198 ms；
`.tmp-regression-docker-52a0ce95b489439a9051546e343e329c/`。
首个真实边界 traffic 两秒内完成，包含 15 秒延迟的 auto-sync 返回 0，
自主提交 revision 1，等待 272.878 秒，未使用 retry；健康失败/INT/TERM 恢复、
累计流量、轮换撤销、down/disable 零网络、up 健康及实际封禁/解封/恢复/停用通过。
同冻结源码的集中合同 48/48、exit 0，入口 362931 ms、Jobs 6、排队 378 ms；
`.tmp-regression-docker-6c7a7779ec8a4bf4b036de74522bd916/`。
两份归档 SHA256 相同，319 输入核对仅后续独立 WS 端口阶段五文件已变化；
错峰代码、测试和其余输入匹配，流式摘要保存在完整结果目录。
工具镜像的静态 Docker/jq
要求测试 cron 显式 PATH；测试主动 HUP 重载不证明生产需要 HUP，短空任务已验证普通重载正常。
已有单 Peer 被控的本地自动同步子集收口；手动入口和合同桩不作为定时证据。
证据 `.tmp-regression-docker-cf575296a33541e59025635a32f9adf5/`、
`.tmp-regression-docker-7cdfadd72fe448afa0c5c3d1c8b46a73/` 和 `.tmp-control-sync-close/`。
原生 systemd 实际调度、双架构及宿主重启等边界仍待验。

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

#### 5A.1b 受管内置静态站点

复用原生 `notes/photos/docs` 和共享 renderer，不增加网站生成器。
CLI `edit --site-template <notes|photos|docs>`，菜单 `16 → 8` 提供三主题；
限定已有 v3 Xray Nginx TLS `21–25` 或 fallback `27/29`，拒绝包含 sing-box `23`
或 Hysteria2 的部署，无网站的 Reality 入口可共存。未知、重复和互斥参数退出 `2`；
不适用部署、缺能力或模板资源损坏退出 `15`。

当前执行包和验签后的候选包都要求 `x-padm-site-templates`，随包
`sites.sha256`、renderer 和全部登记资源进入外层 bundle 摘要及路径完整性合同。
清单不得在运行时从目录重生成；当前三主题为 `43` 个资源，资源数量不是独立
版本门禁。缺页、缺图、篡改、额外/重复/越界清单项、私有目录、链接、硬链接
及特殊文件拒绝。Windows checkout 的主题 HTML/CSS 和清单固定 LF。
正式 release 工作流及安装、发布、菜单、配置与升级夹具均携带同一资源集合。

主题从受管 staged bundle 复制到候选 `data/static`，复用原生默认站名/配色与
占位符转义；只持久化普通 `site.mode=static`，不增加主题配置或安装状态。
沿用预览、确认、锁、站点备份、健康失败与信号恢复，保留认证、额度累计、
其它入口、主订阅/分享组、WS 和 ACME 路径；后续编辑及业务恢复继续保留静态内容。
旧无能力包仅拒绝显式主题请求，原默认页、目录发布和 302 不增加能力门禁。

本地 Linux amd64 定向 `static-sites`、`docker-sites`、`docker-phase1` 和
`docker-phase5` 均通过；三主题各 `11` 页及当前 `43` 个资源完成真实 Nginx
逐字节验收，包含 h1/h2、404、WS/订阅/ACME 保持、失败/INT/TERM 与业务恢复。
正式 workflow 的实际 tar 命令经装包合同验证。集成 `docker-contracts -Jobs 6`
通过 `49/49`，耗时 `523136 ms`、排队 `4662 ms`、`cache_hit=false`；
最终快照的全部 `29` 个改动或新增文件与工作区逐字节 SHA256 一致。
证据在 `.tmp-static-templates-close/acceptance.md` 及相应回归目录。

`site-static-redirect-alpn` 完整状态保持 `deferred`；公网、原生宿主、arm64、
可信发布与整机生命周期仍待验，不以网页内容或外观证明抗识别。

#### 5A.1c Hysteria2 受管本地网页

已有 v3 sing-box Hysteria2 先用站点菜单或 `--site-template` / `--site-static`
发布受管网页，再在已有入口参数中关闭混淆、将伪装设置为精确 `local`；
完整私有规格 `edit --spec` 使用相同编辑事务。首配不开放 local，
不接受用户 file URL 或任意宿主目录挂载，所有 local 入口与 Nginx 共用受管网页。
生成器只输出固定 `file:///srv/padm/`，仅 local 存在时给 sing-box 增加
`data/static` 只读挂载；沿用原目录权限、首页/资源校验、随包清单和 renderer。

local 要求 `site.mode=static`、`obfs=null`；启用期间默认页/302/混淆拒绝。
纯 Hy2 仅开放静态模式，可先准备网页而不启用 local，此时无静态目录挂载。
关闭 local 改为 off/HTTPS 后移除该挂载，文件保留。删除最后一个 Nginx
仍有 Hy2 时保留静态模式，没有站点消费者时清模式并保留内容。
模板允许已有 Xray Nginx/Hy2 混合，sing-box 23 模板继续拒绝。
`x-padm-hy2-local-site` 门禁 local 与无 Nginx 的纯 Hy2 静态准备规格，
防止目标旧包接受其无法校验的新形状；旧无 site 默认/HTTPS 与 Nginx
静态混合且无 local 的规格保持兼容。内容、规格、挂载纳入原候选与恢复事务。

Linux amd64 的 sites/menu/hysteria2/setup-tls 定向 exit 0，Jobs 2；
当前锁定 sing-box 1.14.3 的真实生产候选三主题及关闭场景共 160 次 H3、
30 次双栈认证业务请求、12 次 CA/hostname 拒绝通过。实际只读挂载、
字节内容、首页跳转、敏感路径/错误认证及关闭后的 404 均符合合同。
独审补齐 configure 的已有受管 static 部署及旧 Hy2 listener 门禁，
拒绝在流量处理和候选生成前发生；无部署残留网页和 Nginx/static 新增
local 拒绝、已有 Hy2 正例补验 123759 ms 通过，二次独审无阻断。

完整 `docker-contracts -Jobs 6` 49/49 exit 0，628572 ms，queue 394 ms，
cache_hit=false；18 文件逐字节匹配快照
`826B2AB590D98C283F12322E05C07B3B8FFDD4A9B20FDC1D4FC7C4E623208AAD`。
Bash/ShellCheck error、JSON、Python/PowerShell AST 通过，之后仅补本验收文字。
完整证据 `.tmp-regression-docker-e6b3055354444157ad585d69917277f2/`，
真实证据 `.tmp-regression-docker-4976f013ff5349168abfcd7452d02dd5/`，
汇总 `.tmp-hy2-local-sites-close/`。测试容器、卷和临时私钥已清理。
完整管理、公网、原生宿主、arm64、可信发布与整机生命周期仍 deferred；
网页外观不证明抗识别。

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
真实 Xray TLS ALPN 协商已在隔离 Linux amd64 Docker Desktop 对 `27/29` 实测；
公网、原生双架构与可信发布仍待适用验收；
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

`docker-alpn-real -Jobs 2` 在当前源码快照上完成 `27:xray` 与 `29:xray`
的反向 `http/1.1,h2`、仅 `http/1.1`、恢复推荐 `h2,http/1.1` 三阶段，
181139 ms，入口 182105 ms，排队 189 ms，`cache_hit=false`。
生产规格、核心完整账号输入和 URI 同步读取当前顺序；除 ALPN 与正常记录
提交来源的 `previous_manifest_sha256` 外，其它核心、认证、fallback 目标、
Compose、Nginx、证书与站点保持。实际双栈 TLS 校验私有 CA/SNI，
记录 h1、h2+h1、h2-only 及配置顺序的 selected ALPN，不预设反向优先级。
实测反向组合选 h1，h2-only 仍可通过 HTTP/2 fallback；仅 h1 拒绝 h2-only。
各阶段的首页、404、唯一 PROXY 来源、真实链接 TCP/UDP 和错误认证均有断言。
复用现有 daemon、命名卷、离线业务镜像与 HTTP/2 curl，普通回归不增加 SSL 探针，
不重复额度矩阵。Bash/ShellCheck error 与 PowerShell 解析通过；真实发布编辑事务、
公网、原生宿主和 arm64 不计为已验。证据
`.tmp-regression-docker-a3516c363c1c4f20ac3c38e143546d39/`。

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

#### 5B.3c.1 手工 IP 阻断名单增量管理

复用 `.routing.block_ips` 和私有 `{"ips":[...]}` 文件，CLI 增加
`--block-ips-add/--block-ips-remove`，路由菜单追加第 26/27 项。
输入先完整校验，再进行稳定去重追加或全成员精确删除，合并后最多 256 项；
空数组、重复项、非法 IP/CIDR 和缺失待删项均拒绝。规则身份沿用完整字符串，
不推断网络包含或合并 IPv6 写法，删空只清手工子项/空 routing。
区域合成的 `geoip:cn` 仍归区域策略，不作为手工名单中的可删成员。
既有私有文件权限、专项互斥、候选预览/确认、备份、健康和信号恢复均复用；
不改 schema、核心生成器、依赖、公开端口或宿主能力。
功能签名提交 `9aa11a60`。两个定向同归档，路由工作流入口 111328 ms、
菜单 PTY 64977 ms、Jobs 2；新增 IP 合同 marker 确认实际执行。
集中完整合同 48/48、exit 0，内部 372610 ms、入口 373599 ms、
Jobs 6、排队 495 ms、cache_hit=false；证据
`.tmp-regression-docker-2c233610617c4f13bf0cea6cba6955b9/`。
三次归档同为 `10ECC131...E13FAD63`，定向时 319 输入全部匹配；
运行期间外部静态站点改动保留，未混入功能提交，完整结果仅证明启动时快照。
独立审阅未发现确定缺陷，复用工具镜像和三槽预算。
未改生成器，不重复已有双核心真实流量；本次合同不新增 IPv6 写法/CIDR 主机位
的真实网络证明，完整 `206`、区域策略与宿主/公网/arm64 边界保持。
小证据 `.tmp-ip-block-incremental/`，定向重复归档/清单已清，日志/result 保留。

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

#### 5B.3f Direct/Block CSV 管理入口

功能签名提交 `93fce518`。补齐菜单直接输入规则的便利性，CLI `--direct-domains <CSV>` 与
`--block-domains <CSV>` 复用 `dockerSocks5DomainsNormalize` 和现有专项事务，
只创建或替换 `.routing.direct/block.domains`，不改 Schema、marker 或核心生成器。
去首尾空白、转小写、按首次出现去重，裸域名补 `domain:`；
四类 matcher、1–256 条唯一规则和写前校验沿用已有合同，不联网推断分类。
输入空项、非法 matcher 或去重后超过上限返回 `2`，不进入 preflight 或部署锁。

菜单 `17` 的 `10/12` 明确为整组替换，接受 CSV、`0` 返回，
取消、EOF 与空输入不派发编辑，非法输入失败后留在菜单。
原 `--direct/--block <root 私有 JSON>` 和关闭动作保留；
CSV、JSON、关闭、其它专项互斥，普通 `--spec` 仍冻结 routing。
Docker 不累加原生历史规则，不把这一便利性项宣称为完整逐条编辑或冲突检测。

Linux amd64 定向路由合同 `163.872` 秒、入口 `164.826` 秒通过，证据
`.tmp-regression-docker-11215270948e42db9bf8a9bdc4457674/`；
菜单真实 PTY `35.816` 秒、入口 `36.714` 秒通过，证据
`.tmp-regression-docker-752d7e8633834556a2126635e508e019/`。
同一最终源码快照完整 Docker 合同 `33/33`、`233.843` 秒通过
（入口 `234.689` 秒、Jobs `6`、排队 `384 ms`），证据
`.tmp-regression-docker-e5279434d10d4a9dad3f5631a5035800/`；
ci `36.505` 秒、入口 `37.412` 秒、Jobs `3`、排队 `210391 ms` 通过，证据
`.tmp-regression-docker-8f80f8afe25a4c3ea70ef42629ef9056/`，均实际执行、未命中缓存。
复用同一工具镜像与长任务优先调度，三槽预算未扩大；此次 case 时长有正常波动，
不将相对前轮 `243.989` 秒的差异另宣称为代码优化收益。

合同覆盖四类 matcher、大小写/空白/首次出现顺序、去重后的 `256/257` 边界，
非法组合、普通 import 冻结、整组替换与其它子项保护、健康失败和 INT/TERM 完整恢复。
独立生产只读复审无 P1/P2，嵌入 Python AST、JSON、PowerShell AST、
diff 及原有 Shell 门槛通过。之后仅更新验收文字，不重复已通过完整回归。
核心流量、优先级和四类 matcher 不变，不重复已覆盖的双核心真实路由全矩阵。
合同使用非空本地 links 对照，
其已发布订阅目录为空，不宣称新增非空 token 验收。
完成目录源码副本清理，日志/result 和共享索引保留；其它任务临时文件不动。
完整 `206`、区域策略、公网分类资源、arm64 和真实宿主仍待验。

#### 5B.3g Direct/Block 增量追加

功能签名提交 `392a131f`。CLI `--direct-domains-add/--block-domains-add <CSV>` 与菜单
`17` 的 `22/23` 复用同一规范化及专项事务；原 `10/12` 整组替换、JSON 导入与关闭保留。
读取既有规则作为合并初值，只追加首次未出现的新项，保持旧顺序及新输入顺序；
对应组缺失时创建。单次输入非法或超过 256 条返回 `2`，
联合超过 256 条返回 `15`，均不提交配置；其它专项和普通 `--spec` 冻结不放宽。
重复追加不重复规则，确认仍可能更新原事务的回滚元数据，不承诺整部署无操作。
本项对齐原生已有增量管理，不声称与 sing-box 的历史存储次序完全相同；
不新增逐条删除、冲突推断、Schema、marker、核心生成器或路由优先级。

Linux amd64 路由定向 `177.375` 秒、入口 `178.305` 秒通过，排队 `204 ms`，证据
`.tmp-regression-docker-fd8e4ff586634a459093535f32f67122/`；
菜单真实 PTY `36.146` 秒、入口 `37.088` 秒通过，排队 `212 ms`，证据
`.tmp-regression-docker-7c1fd92776d94dc4a82c02e5c1ef2ea1/`。
两次源码摘要相同，Jobs `2`，复用工具镜像，实际执行、未命中缓存。
合同覆盖缺项创建、四类规则、历史保留/稳定去重、重复追加、联合 `256/257` 上限、
互斥、导入冻结、预览/取消以及健康失败和 INT/TERM 的完整部署快照恢复。
菜单覆盖双方取消、空输入、EOF、非法输入和状态失败后继续操作。
独立生产增量只读复审无 P1/P2；完整集成回归与定向耗时优化已通过。
本地非空 links、核心身份与累计流量保持；发布订阅目录为空，不新增非空 token 验收。
完整 `206`、公网、arm64、原生宿主及发布验收仍待补，不升级支持状态。

为缩短后续 Direct/Block 迭代反馈，新增 `docker-routing-domains-workflow` 定向选择器；
它只跳过路由脚本中与域名工作流无关的独立矩阵和生命周期段，保留同一份
夹具、候选事务、DNS/hosts/SOCKS/IP 子项保护、追加/替换/冻结/取消/失败/信号断言，
不加入 `docker-contracts` 清单，也不改变原 `docker-routing-socks5` 路径。
性能签名提交 `0001a7d8`，仅增加两处条件包裹、一个 leaf 与对应回归说明。

新选择器 Linux amd64 实测 `92.128` 秒、入口 `93.225` 秒，排队 `4548 ms`，
与完整路由定向 `177.375` 秒相比减少约 `48%`；两次并发负载不同，
只作为后续日常定向的参考，不把差异全部归因于条件包裹。
同一冻结源码的完整 Docker 合同 `33/33`、`254.098` 秒通过
（入口 `254.984` 秒、Jobs `6`、排队 `401 ms`），证据
`.tmp-regression-docker-c34273315fd74ba89a5a101ef3493a5c/`；
`ci` `37.963` 秒通过（入口 `39.018` 秒、Jobs `3`、排队 `233075 ms`），证据
`.tmp-regression-docker-cc53034049d1454b81760e0a744312f2/`。
两者与 focused 使用相同源码摘要，均实际执行、未命中缓存；完整合同输出仍逐项
包含 `docker-routing-socks5`。同一源码快照的隔离 Docker 静态检查通过
6 个 Shell 文件的 Bash 语法及 ShellCheck error、2 段嵌入 Python AST 和功能 JSON；
证据 `.tmp-regression-docker-1d684d760bf94f0c87116e7db3ef6abf/static.log`。
性能增量独立只读复审无 P1/P2；静态检查不替代完整合同。
完成目录只清理 `source.tar/files.list`，保留日志/result、静态证据与共享索引；
临时检查容器均已删除，不动其它任务原有 8 个临时文件。本任务只本地提交，不推送。

#### 5B.3i Direct/Block 精确删除与重叠诊断

CLI `--direct-domains-remove/--block-domains-remove` 与菜单
`17` 的 `24/25` 只删除对应手工列表中已存在的完整规范化规则；输入含任一缺项时整组拒绝，
保留剩余顺序，最后一条删除后清理空子项，不影响区域、IP/CIDR、DNS、hosts、BT 或 WARP。
`routing-status` 增加只读 `direct_block_overlaps`，按 Direct 原顺序返回手工 Direct 与
手工 Block 的完整字符串交集；不推断 `full:`/`domain:` 包含关系，不把区域策略合成规则混入，
不自动拒绝已有重叠，Direct 既有优先级保持不变。

Linux amd64 `docker-routing-domains-workflow` 入口 `115.538` 秒通过，证据
`.tmp-regression-docker-27d02dc5f0f54337bcc6b82ca745e2b8/`。
合同覆盖四类规则、整批缺项拒绝、顺序、重复删除、区域排除、状态读取不改快照，
以及预览、取消、健康失败和信号恢复；随后与 202/207 双栈发布集中完成完整 Docker 合同。
菜单 PTY 入口 `56.120` 秒通过，证据
`.tmp-regression-docker-e57712952e884b4fb99784b4f42d6aea/`；生产增量独立复审无 P1/P2 阻断。
完整区域策略、逐条语义编辑、分类冲突诊断和适用公网验收仍待补。

2026-10-12 集成冻结快照的完整 Docker 合同 `48/48`、exit `0`，
入口 `316331 ms`、内部 `316826 ms`、Jobs `6`、排队 `368 ms`、占 `2` 槽，
`cache_hit=false`；证据
`.tmp-regression-docker-114ec2de759648689555bf86122f0be4/`。
归档 `316` 个输入流式哈希与当前工作区全部一致；随后只补写本段验收文字。
202 双栈 HTTP 来源/认证/伪造头和 207 双栈 TCP/UDP on/selected/off 的实链路
证据沿用对应段落，不重复未变探针。重复归档/清单清理，日志/result 和
`.tmp-5b-routing-publishing-close/snapshot-inputs.json` 保留；不升级完整能力状态。

#### 5B.3j 已有 CN 预设自定义直连例外增删

CLI `--region-allow-add/remove <CSV>` 和区域菜单追加两个管理入口；
仅接受已有合法 `.routing.region`，只修改自定义 `allow_domains`。
追加复用四类规则规范化，按首次出现稳定去重，总量最多 256；
删除要求每条完整规范化规则都在自定义列表中，任一缺项整组拒绝。
最后一项删除后仍保留 `mode` 和 `allow_domains:[]`，固定八条例外不受影响，
不删除手工 Direct/Block、修改其它路由或凭据，也不新增 schema 或渲染合同。
动作互斥、预览/确认及失败恢复沿用现有专项编辑事务。
Linux amd64 `docker-routing-region` 入口 51760 ms、内部 50806 ms，
`docker-menu` 入口 60345 ms、内部 59404 ms；Jobs 2、排队 200/201 ms，
均实际执行、未命中缓存，两个源码快照摘要一致。
覆盖未启用拒绝、参数互斥、四类规则、默认同名规则的自定义归属、
完整字段保持、256/257 上界、整批缺项拒绝、末项空列表、
预览/取消及 health/TERM 恢复；PTY 覆盖空/0/EOF、非法输入和失败后继续。
源码复核无确定 P1/P2，证据
`.tmp-regression-docker-a265f71f3457447aa23397dc1c590e10/`、
`.tmp-regression-docker-e38058e96b384fba82a27fdf6bd37cd8/`。
集中完整合同 48/48、exit 0，入口 362931 ms，证据见 4C.5；
本阶段不改核心渲染，
不重复未变真实路由矩阵，完整区域策略和适用公网/宿主/arm64 仍 deferred。

#### 5B.3h DNS 分流直接录入

功能签名提交 `5c7e1961`。菜单 `17` 的 `6` 改为依次输入字面服务器 IP、
端口（留空默认 `53`）和域名规则 CSV；原 `--dns <root 私有 JSON>`、关闭和 hosts 保留。
CLI `--dns-rules <IP> <端口> <CSV>` 复用原规范化与专项编辑事务，
只创建或整组替换既有 `.routing.dns={server,port,domains}`，不生成中间 JSON 文件。
字面 IP 原样保留，端口只接受 1–5 位十进制数字并转为 `1–65535` 的 JSON 整数，
CSV 去空白、转小写、按首次出现去重，裸域名补 `domain:`，1–256 条四类规则沿用。
缺参、非法端口/CSV 或专项冲突返回 `2`；非法服务器由原候选校验拒绝，返回 `15`。
菜单每层 `0` 或 EOF、空 IP/CSV 均不派发，非法输入和事务失败后仍可继续操作。
本项只补菜单录入差距，不扩 Schema、marker、生成器、全局 DNS、DoH/DoT、
地址支持或解析优先级；普通 `--spec` 冻结、锁、JSON 安全输入与事务恢复保持。

2026-10-10 Linux amd64 `docker-routing-domains-workflow` `92.080` 秒、
入口 `92.967` 秒、排队 `204 ms` 通过，证据
`.tmp-regression-docker-f6cd5a637d1643afaf377475370df26a/`；
菜单真实 PTY `37.359` 秒、入口 `38.274` 秒、排队 `208 ms` 通过，证据
`.tmp-regression-docker-40c43937b07b443d834b861682256040/`。
两次源码摘要相同，Jobs `2`，实际执行、未命中缓存。
合同覆盖 IPv4 创建、IPv6 整组替换、端口/CSV 规范化、输入和互斥边界、
其它子项保护、预览/取消/普通导入冻结、健康失败和 INT/TERM 完整恢复，
并用原 JSON 接口恢复旧 DNS。独立只读复审无 P1/P2；
同一源码快照的 5 个 Shell Bash/ShellCheck error 与 2 段嵌入 Python AST 通过。
同一最终源码快照完整 Docker 合同 `33/33`、`273.771` 秒通过
（入口 `274.677` 秒、Jobs `6`、排队 `406 ms`），证据
`.tmp-regression-docker-bb0b5488236d4eef991db6e931090218/`；
`ci` `41.392` 秒通过（入口 `42.379` 秒、Jobs `3`、排队 `251929 ms`），证据
`.tmp-regression-docker-4746eca7a0994e1c8d6d007b948002c8/`。
四次回归源码摘要一致，均实际执行、未命中缓存；三槽预算、完整清单不变。
真实解析引擎、优先级未改变，不重复真实路由矩阵；之后仅更新验收文字，
不重复已通过全套。完成目录源码归档/清单与临时检查容器已清理，日志/result/
静态证据和共享索引保留，不动其它任务原有临时文件；本任务未推送。
公网、arm64、宿主和可信发布仍待验，不升级完整 `206` 支持状态。

#### 5B.3h.1 已有 DNS 分流域名增删

路由菜单第 28/29 项与 `--dns-domains-add/--dns-domains-remove <CSV>`
复用域名规范化和 Direct/Block 增删事务，仅操作已有 `.routing.dns.domains`，
保留服务器、端口、hosts、其它路由和累计流量；未启用 DNS 返回 `15`。
追加保持历史次序并稳定去重，合并后最多 256 条。删除按完整规范化规则匹配，
任一缺项整组拒绝，`full:` 与裸域名不等同；删空清除完整 DNS 子项及空 routing。
缺参、空值、非法 CSV 和专项冲突返回 `2`，不调用 Compose。
菜单覆盖成功、0/空/EOF、非法输入和失败后继续状态操作。
不改 schema、能力标记、生成器或解析优先级，不增加全局 DNS、DoH/DoT。
定向使用 `docker-routing-dns-hosts-workflow` 与 `docker-menu`，再集中完整合同；
本阶段不重复未变生成器的真实流量矩阵，完整 `206` 状态与宿主/公网/arm64 待验边界保持。
2026-10-12 Linux amd64 DNS 定向内部 70886 ms、入口 71862 ms，
菜单 PTY 内部 62611 ms、入口 63624 ms，Jobs 2、exit 0；
新增 DNS 增量 marker 确认实际执行，独立静态复审无确定缺陷。
完整合同 48/48、内部 375249 ms、入口 376257 ms，Jobs 6，
排队 376 ms、cache_hit=false；证据
`.tmp-regression-docker-d4fa9af616834368b5cdfb8d60ca3559/`。
两个定向归档同 `6ECC10E4...6539D094`；完整 `6318C7B4...6A94F23B`
只多 5 个外部新增静态页面，本阶段 10 个代码/合同/文档输入逐文件一致。
回归后仅更新验收文字与陈旧自动同步说明，保持对应 deferred 状态；
源码归档/清单清理，日志/result 和 `.tmp-dns-domain-incremental/` 小证据保留。

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

#### 5B.4c 已有 WARP 的日常分流管理

沿用原七字段合同和两核心渲染，新增 `edit --warp-domains <CSV>`、
`--warp-global`、`--warp-family <ipv4|ipv6>`。仅接受已有合法 WARP；
域名替换规范化并切 selective，global 清空 domains，family 只修改地址族。
冻结比较只放行对应字段，密钥、Peer、隧道地址、reserved、其它路由和账号保持；
不新增 schema、账号注册器或新默认出口，继续拒绝竞争的全局出站。
菜单原 1–3 保留，追加 4–7，确认仍由原编辑事务执行一次。

WARP 定向 46272 ms、菜单 PTY 59749 ms，通过未启用/参数/组合拒绝、
模式与地址族往返、规范化、完整字段保持、预览/取消、health/TERM 恢复，
原导入/off 的 health/INT/TERM 断言保留；PTY 覆盖 0/空/EOF、确认取消及失败后继续。
证据 `.tmp-regression-docker-6803b1f7e53949258434fb4987e83645/`、
`.tmp-regression-docker-b19f94e23243461487a3675c7427b981/`。
集中合同 48/48、329613 ms、Jobs 6、排队 386 ms，未命中缓存；
319 输入核对除后续真实双部署夹具外全部匹配，WARP 实现和测试均冻结一致。
证据 `.tmp-regression-docker-e1fca7291ab2411290c3501faf3f60e7/`、
`.tmp-warp-daily-close/snapshot-inputs.json`。独立复核无确定 P1/P2；
未修改渲染或私有 Peer 合同，不重复已有真实两核心出站矩阵。
域名增量删除、完整区域策略、Cloudflare 公网出口、原生宿主和 arm64 仍 deferred。

#### 5B.4d 已有 selective WARP/IPv6 域名增删

复用共享域名增删分支，新增 `--warp-domains-add/remove <CSV>` 与
`--ipv6-domains-add/remove <CSV>`；WARP 子菜单追加 8/9、IPv6 子菜单追加 5/6。
仅已有合法 selective 分流可操作，缺失或 global 模式返回 `15` 且不调用 Compose。
输入沿用四类域名规则、规范化与稳定去重；追加保留历史顺序，合并最多 256 条，
删除须所有完整规范化规则都存在，否则整组拒绝；full 与 domain 不能混删。
非空时仅改 domains，WARP 模式、地址族和所有私有字段及其它规格保持。
删空关闭对应分流并清空 routing，不自动变全局；WARP 私有配置随子项移除，
以后启用需重新导入，删除前菜单明确说明。
缺参、空值、非法 CSV 和专项冲突返回 `2`；预览/取消、健康失败和 INT/TERM
沿用原候选事务及累计保护，不新增 schema、能力标记、生成器、依赖或网络权限。
WARP 与 IPv6 各跑自己的定向 selector，菜单和完整合同集中各一次；
保持三槽预算并复用工具镜像，不重复未变生成器的真实出站矩阵。
完整区域策略、Cloudflare 公网、真实宿主、arm64 和可信发布仍 deferred。
2026-10-12 Linux amd64 WARP 定向内部 77408 ms、入口 78406 ms，
IPv6 定向内部 65313 ms、入口 66341 ms，菜单内部 67316 ms、入口 68294 ms，
均 Jobs 2、exit 0；两个新增 marker 均实际执行，三次归档同
`A7D89300...5056E1`。完整合同 48/48、内部 402637 ms、入口 403615 ms，
Jobs 6、排队 384 ms、cache_hit=false；证据
`.tmp-regression-docker-7c688448b08c4470a10bfead844d3406/`。
本阶段 10 个代码/合同/文档输入与完整快照一致；未重复真实 WARP/IPv6
出站矩阵，公网、宿主、arm64、可信发布与完整区域策略继续 deferred。

#### 5B.4e 已有域名单条替换

`edit --dns-domains-replace`、`--direct-domains-replace`、
`--block-domains-replace`、`--warp-domains-replace`、
`--ipv6-domains-replace` 接收旧规则、新规则两个单项参数；
先拒绝任何逗号，再复用既有规范化，各项必须恰为一条。
只编辑已有非空手工名单，WARP/IPv6 必须为 selective；
缺失/global、旧规则不存在、重复新值或新旧相同均明确拒绝。
匹配完整规范化规则，full 与 domain 不互换，原位替换且保留其它次序。

菜单 `17` 追加 30/31/32，IPv6 子菜单追加 7、WARP 子菜单追加 10；
先显示当前脱敏路由状态，再输入旧/新规则。状态失败不进入编辑，
两步均支持空输入、0 和 EOF 取消，业务动作仍经独立 CLI 确认。
只豁免所选 `.routing[kind].domains`，DNS 上游/端口、WARP 模式/地址族/
密钥/Peer/地址/reserved 及其它配置全部冻结。复用原候选、预览、确认、
累计流量保护、健康失败与 INT/TERM 恢复，不新建 schema、marker 或生成器。

四定向 exit 0：DNS 78018 ms、Direct/Block 121428 ms、
WARP/IPv6 124565 ms、菜单 91943 ms，Jobs 2，均未命中缓存。
五类组合夹具覆盖原位顺序、规范化、其它完整规格冻结、非法拒绝、
预览/取消及累计数据保持；五次故障合计覆盖健康失败和 INT/TERM 恢复。
菜单 8 组 PTY 覆盖五类分发、两步取消及失败后继续，生产独审无阻断。
Bash、ShellCheck error 和 JSON 检查通过；完整合同 49/49、exit 0，
609649 ms、Jobs 6、排队 376 ms、cache_hit=false，复用工具镜像。
证据 `.tmp-regression-docker-be71bb46a1f54b7da7dd19bcac6cb174/`；
源码 SHA256 `2C44564870084BEE9F73C40E742F729F6161E5526072AF366694070D7EE47964`，
10 个交付文件逐字节匹配完整快照，随后仅补本段验收文字。
生成器及真实出站行为未变，不重复原矩阵；完整区域策略、其它规则编辑、
完整冲突检测、公网、宿主/arm64 与可信发布仍 deferred，总目标继续 active。

#### 5B.4f 已有手工 IP/CIDR 单条替换

`edit --block-ips-replace <旧字面规则> <新字面规则>` 只编辑已有非空
`.routing.block_ips.ips` 手工名单。两值不规范化，保留大小写、IPv6
展开/压缩形式和 CIDR 宿主位；旧完整字符串必须恰好存在一次，
新值不得与任何现有项重复，包括旧值。原位替换保留其它规则和次序。

空值、CSV、GeoIP、域名、非法地址或前缀以及专项组合明确拒绝。
已有手工 `geoip:cn` 保留但不由本命令替换；区域合成规则保持独立。
一次临时完整 spec 校验复用现有双地址族/前缀合同，临时去重仅用于
同值语法校验，最终名单不排序或去重。freeze 只豁免所选 ips 数组，
不改 schema、marker、生成器、宿主权限或网络。

路由菜单追加 33，先显示脱敏状态，再输入旧/新两值；状态失败
不进入编辑，空输入、0 和 EOF 均取消，独立 CLI 确认及原事务恢复。
Direct/Block 定向 142088 ms、菜单 94528 ms，Jobs 2、exit 0；
IPv6 原文/CIDR 宿主位两组替换与反替换、完整规格及数据冻结、双侧非法、
预览/取消、一次健康失败和区域保留通过。菜单 7 组 IP PTY 共用模板。
生产独审无确定阻断；尾 LF 疑点经实际完整规格校验拒绝，无额外代码修改。
Bash、ShellCheck error、JSON 检查通过，完整合同 49/49、exit 0，
633700 ms、Jobs 6、排队 390 ms、cache_hit=false，工具镜像复用。
证据 `.tmp-regression-docker-329308a0e10e45c6be0c88bb7452dba7/`；
源码 SHA256 `D26D37603B9F56012FC8CCCEF4BCBC35CEE76C550701929881DEF670D559BC11`，
10 个交付文件匹配完整快照，随后只补本段验收文字。不重复未变真实矩阵；
完整区域策略、其它规则编辑、完整冲突检测、公网、宿主/arm64
和可信发布仍 deferred，总目标继续 active。

#### 5B.4g 已有区域自定义直连例外单条替换

`edit --region-allow-replace <旧规则> <新规则>` 复用域名单条替换与冻结合同，
只豁免 `.routing.region.allow_domains`；已有非空自定义名单才能操作。
旧值必须恰好存在一次，新值不得重复，包括同值；输入规范化后保留原位置，
CSV、非法格式、缺旧项、未启用及空名单拒绝。区域 mode、固定八条例外、
其它路由、认证、流量及部署数据保持；同名自定义项可改，默认项不参与匹配。

CLI 与区域定向已在 `8b89435f` 交付；本阶段补区域菜单 `7` 和状态 `8`，
替换前状态失败不读输入，空值、0/EOF 取消，独立 CLI 只确认一次。
PTY 复用六类域名替换模板，覆盖成功、双侧取消/EOF、非法格式/CSV/同值、
状态/前置失败、确认取消/EOF 和提交失败后继续诊断。
区域定向已通过，入口 63359 ms；本轮菜单 PTY exit 0，内部 96512 ms、
入口 97762 ms、排队 4728 ms、Jobs 2，复用工具镜像、cache_hit=false；
证据 `.tmp-regression-docker-8a929fa1f2c14bafad161ca5548127be/`。
待办调度器合同 exit 0，内部 536 ms、入口 1674 ms、Jobs 2。
本阶段已随 5B.4h 集成完成集中完整回归，49/49 通过，证据和耗时见下节；
完整区域策略、其它规则编辑、完整冲突检测、
公网、原生宿主/arm64 和可信发布仍 deferred，总目标 active。

#### 5B.4h 已有 SOCKS5 域名名单增删与单条替换

`edit --socks5-domains-add/remove <CSV>` 和
`--socks5-domains-replace <旧规则> <新规则>` 仅管理已有非空 selective
`.routing.socks5.domains`；未启用、global 或空名单拒绝。追加复用四类
域名规范化与稳定去重，合并最多 256 条；删除按完整规范化规则匹配，
任一缺项整批拒绝，保留剩余次序。单条替换拒绝 CSV、缺旧、重复新与
同值，完整匹配旧项并保留原位置。非空动作只改 domains，
server/port/username/password 和其它路由、完整配置冻结。

删空只允许 remove 关闭整个 SOCKS5，清理空 routing，保留其它策略；
重新启用须导入私有凭据，不自动转为 global。原整组替换/global 入口保持。
菜单 `17` 追加 `34/35/36`，先显示状态，状态失败不读输入，
空输入、0/EOF 取消，独立 CLI 只确认一次；删除提示明确删空关闭和重新导入。
复用双核心生成器、既有候选/预览/确认、累计数据保护及健康/信号恢复事务，
不新增 schema、marker、依赖、监听端口或宿主权限。
Linux amd64 定向 `docker-routing-core-policy-lifecycle` exit 0，内部 130186 ms、
入口 131295 ms；最新菜单 PTY exit 0，内部 103186 ms、入口 104558 ms；
两项均 Jobs 2、cache_hit=false，复用工具镜像，源码快照 SHA256 一致。
证据 `.tmp-regression-docker-caa4daf16cea43119063cde4f0c56e9d/` 与
`.tmp-regression-docker-ac45b05ab0804d179f9c69a2a880d525/`；
Bash、ShellCheck error 与 JSON 静态检查通过。
首轮合同误断言删空后总 routing enabled=false；共存 DNS 仍启用，故应断言
mode=direct、server/port=null、domain_rules=[]。仅修测试后重跑通过，
生产代码未改，失败证据 `.tmp-regression-docker-76ef844f6cd74f459c4a31a5a1227deb/` 保留。
集中 `docker-contracts` 49/49 exit 0，内部 616610 ms、入口 617738 ms，
queue 62338 ms、Jobs 6、cache_hit=false；工具内容 SHA256 与定向相同。
证据 `.tmp-regression-docker-ba35b528fd874ecb9c28e01e667a60e1/`；
本阶段 10 个暂存文件逐字节匹配完整回归快照，之后仅补验收文字。
完整区域策略、其它规则编辑、完整冲突检测、
公网、原生宿主/arm64 和可信发布仍 deferred，总目标 active。

#### 5B.4i 已有 hosts 单键地址替换

菜单 `17 → 37` 与 `edit --hosts-replace <已有精确 FQDN> <新单字面 IP>` 只管理
已有 `.routing.hosts` 键的一个值，不新增、删除或批量编辑映射。key 只将 ASCII 字母
转小写，不去空白；IP 保留原文，包括 IPv6 大小写和写法。空白、末尾 LF、CSV、
域名规则前缀和坏地址返回 `2`；缺键、未启用 hosts 和新旧地址原文同值返回 `15`。
复用完整规格的精确域名/可路由字面 IPv4/IPv6 校验，只豁免目标键的值，
其它 hosts 键、路由、完整配置、分享 URI、订阅与非空累计流量冻结。

菜单先显示状态，状态失败不读输入，两个输入的空值、0/EOF 均取消；
独立 CLI 只确认一次。原 `--hosts <root 私有 JSON>` 整组入口保持，
复用候选/预览/确认、双核心生成器及健康失败、INT/TERM 恢复事务；
不扩 hosts 解析语义，不新增 schema、marker、权限、监听或状态。
这是有限管理增强，不能当作原生 hosts 完整迁移或提升整体 `deferred` 状态。

Linux amd64 DNS/hosts 定向 `docker-routing-dns-hosts-workflow` exit 0，
内部 108214 ms、入口 109337 ms；菜单 PTY exit 0，内部 102772 ms、入口 103950 ms。
两项均 Jobs 2、cache_hit=false，复用工具镜像，源码 SHA256 `92BAF66F...24523` 相同。
证据 `.tmp-regression-docker-a8c4290954224618901647866f10f961/` 与
`.tmp-regression-docker-d3013608ffa24ed281843d9728e324dc/`。
复审发现 Bash Unicode 小写会把 Kelvin 符号变成 ASCII `k`，已改用
`jq ascii_downcase` 并补非 ASCII 域名拒绝断言。修正版 DNS/hosts 定向 exit 0，
内部 124086 ms、入口 125425 ms、排队 241 ms、Jobs 2、cache_hit=false；
证据 `.tmp-regression-docker-a8bbdb43044d40159434203edcbb4b49/`。
合同覆盖参数/互斥和精确拒绝码、IPv4/IPv6 原文替换、两核心仅目标值变更、
完整配置/URI/非空累计保持、预览不写和健康失败/INT/TERM 恢复；
PTY 覆盖分发、双侧取消/EOF、非法输入、状态/前置失败、确认取消/EOF 与提交失败后继续诊断。
集中 `docker-contracts` 49/49 exit 0，内部 560303 ms、入口 561363 ms，
排队 182560 ms、Jobs 6、cache_hit=false，工具内容摘要与定向一致；
证据 `.tmp-regression-docker-a000fe9083874c6fa74e723ab3b08f87/`。
该快照早于外来 CI 拆分提交 `218dde98`；生产文件与 hosts 专项断言匹配，
新测试调度随下一阶段集中验证，不把旧快照当作新调度证据。
其余名单管理、完整区域/冲突检测、
公网、原生宿主/arm64 和可信发布仍 deferred，总目标 active。

#### 5B.4j hosts 精确新增与删除

菜单 `17 → 38/39` 与 `edit --hosts-add <精确 FQDN> <单字面 IP>` /
`--hosts-remove <已有精确 FQDN>` 只管理一个键。新增可创建缺省 hosts，
但已有键无论地址是否相同均返回 `15`，不能覆盖；合并最多 256 项，第 257 项
返回 `15`。删除要求已有键，缺键/未启用返回 `15`；删掉最后一项移除 hosts，
只有 routing 也为空才移除 routing，不影响共存 DNS 或其它策略。

沿用 `jq ascii_downcase`、不去空白、IP 原文与精确 FQDN/可路由字面 IP 边界；
空白、末尾 LF、CSV、规则前缀、Kelvin 符号和坏地址返回 `2`。
只接受旧完整规格的精确单键新增/删除及必要空容器清理，冻结其它 hosts、路由、
认证、完整配置、URI/订阅与非空累计。复用已有 schema、marker、生成器、
候选/预览/确认及恢复事务，不新增状态、依赖、监听或宿主权限。

菜单先显示状态，失败不读输入，各字段空值、0/EOF 取消，CLI 单次确认；
删除提示最后一项关闭 hosts。Linux amd64 增删定向内部 128739 ms、入口 129847 ms，
排队 6687 ms、Jobs 2、cache_hit=false；增删、DNS 增量与既有 SOCKS 合同通过，
证据 `.tmp-regression-docker-3d573a87e20c49a0a0db757750322066/`。
菜单 PTY 内部 105619 ms、入口 106636 ms、排队 197 ms、Jobs 2、cache_hit=false，
证据 `.tmp-regression-docker-4f6698384451472aabe33491524924bc/`。
Bash、ShellCheck error 与 JSON 静态检查通过，临时检查容器已清理。
集中 `docker-contracts` 53/53 exit 0，内部 554325 ms、入口 555341 ms，
排队 389 ms、Jobs 6、cache_hit=false，复用相同工具镜像；
证据 `.tmp-regression-docker-d5e54a5429fb43088d82f1901b86d84d/`。
10 个暂存文件逐字节匹配该快照，之后仅补验收文字；
包含 `218dde98` 合入后的全部新调度，5 分钟 CI 目标仍须线上实测。
此为有限管理增强，完整区域/冲突检测、原生宿主/arm64、公网与可信发布
仍 deferred，总目标 active。

#### 5B.4k 有限精确域名规则重叠诊断

现有 `protocol routing-status` 与路由菜单状态入口追加 `domain_rule_overlaps`；
按完整规范化规则字符串排序，列出 `rule`、按 Direct/Block/IPv6/WARP/SOCKS5
优先级排列的 `policies` 与首个 `winner`。原 `direct_block_overlaps` 继续只计算手工
Direct/Block 交集并保留 Direct 次序，现有字段保持兼容。

有效 Direct 包含区域固定八条例外和自定义例外；有效 Block 仅在 region
domain/both 时补 `geosite:cn`，同一策略重复来源去重。global 无域名选择器，
不进入该列表。`winner` 只表示同一完整规则的候选策略中优先者，
不承诺最终流量路径；其它 Block 包含规则、IP/BT 和独立 HTTP 中继仍可能先匹配。
SOCKS5 策略对 TCP 代理、UDP 拒绝，不推断包含关系或 GeoSite 成员，
不拒绝已有重叠，不新增编辑入口、状态、schema 或权限。

复用核心合同组合夹具、生产只读命令和快照验证五策略重叠、四种候选优先者、
区域默认/自定义/两种模式、同策略去重、不同 selector 不误报、关闭和全局空列表；
保留凭据脱敏、锁/候选清理与完整部署/流量冻结断言。
Linux amd64 定向核心合同内部/入口 20093/21218 ms、排队 194 ms；
策略生命周期 118503/119602 ms，菜单 PTY 108865/109884 ms，均 exit 0、Jobs 2、
cache_hit=false，工具镜像直接复用。证据
`.tmp-regression-docker-1cae904234b943c39930a46cbe6da2fa/`、
`.tmp-regression-docker-e9daa52d76f44744ae14451864d62b97/`、
`.tmp-regression-docker-9349be99e374477eb7d02cb3b7beff40/`。
Bash、ShellCheck error、JSON 与独立只读复审通过；集中完整合同 53/53 通过，
内部/入口 547183/548198 ms、排队 382 ms、Jobs 6、cache_hit=false，镜像直接复用；
证据 `.tmp-regression-docker-45161d143dea43e49ccedad75f79a2cf/`。
6 个行为/说明文件与 full 快照一致，protocol 仅修正祖先合同的中文注释，
计划仅追加验收记录；成功输入清理后保留日志与结果。
完整冲突检测、区域管理、公网、原生宿主/arm64 与可信发布仍 deferred，总目标 active。

本轮回归精简另签名提交 `0d8a8ed9`：Reality 参数/目标 helper 只在 unchanged
捕获部署快照，省去 full 中 10 份未消费扫描，成功与失败恢复的全部独立断言保持。
两独立定向内部/入口 227359/228622 与 204676/205769 ms、Jobs 2、exit 0，
证据 `.tmp-regression-docker-85d80761bcac48f68c07f87100287f00/`、
`.tmp-regression-docker-0e99c372088c4e65b1e7d47fa173231f/`；
独立入口包含祖先合同，不能与 full 分项直接比较或据此宣称节省秒数。

#### 5B.4l 已有区域模式保留例外切换与菜单文案修复

新增 CLI `edit --region-mode <both|domain|ip>` 和区域菜单 `9`，
只改已有 `.routing.region.mode`；保留自定义例外顺序、固定八条例外、
其它路由与完整规格，复用字段冻结、预览/确认、健康失败和信号恢复。
同模式或未启用返回 `15`；非法模式或与其它专项动作组合返回 `2`。
空自定义名单仍可切换，不借此启用区域策略。

修复区域菜单 `1`–`3` 提示“追加、留空无追加”却重建名单的误导：
改为“替换自定义例外、留空清空”，原 `--region` CLI 整组替换语义保持。
本步不修改生成器、schema、marker、权限或分类语义，完整区域策略、
完整冲突检测、公网、原生宿主/arm64 与可信发布仍 deferred，总目标 active。
Linux amd64 区域合同内部/入口 69785/70890 ms、排队 5123 ms，菜单 PTY
109495/110510 ms、排队 289 ms，均 exit 0、Jobs 2、cache_hit=false。
证据 `.tmp-regression-docker-e2c8aaa8b5a844298d41d8a964968364/`、
`.tmp-regression-docker-9b5181a4238b43578f60fb3920d39cdc/`。
Bash、ShellCheck error、diff 和独立只读复审通过；集中完整合同 53/53
通过，内部/入口 614914/615925 ms、排队 388 ms、Jobs 6、cache_hit=false，
证据 `.tmp-regression-docker-028a4b683ac04ef79037eb4e688c5999/`。
工具镜像直接复用；完整耗时含独立定向检查混跑，不能据此归因于本次代码。
行为文件与 full 输入一致，验收后只补说明，日志与结果保留、重复源码输入清理。

回归精简单独提交：`runStatus` 对 stdout/stderr 的四个固定敏感值从
8 次 `grep` 合为一次 `grep -Fq`，仍为任一文件出现任一值就拒绝。
容器内 1 个干净场景和 4 值 × 2 文件的 8 个泄漏场景等价性检查通过；
`docker-routing-core-contracts -Jobs 2` 的真实只读/脱敏合同内部/入口
25004/26263 ms、排队 245 ms、exit 0、cache_hit=false，证据
`.tmp-regression-docker-0fbc12b87e8c4a50a8c762abce47c21e/`。
生产路径与断言范围保持，完整集中回归沿用本节证据，不以单次耗时推断收益。

#### 5B.4m 一次移除访问控制

路由菜单 `17 → 40` 与 `edit --access-control-off` 在一次候选事务中删除手工
Direct、域名/IP Block 与区域预设，清理空 routing；保留 BT、DNS/hosts、
IPv6、WARP、SOCKS5、认证、分享和累计。不存在可删除项返回 `15`，
非法组合返回 `2`；复用单次确认、字段冻结、预览及健康失败/INT/TERM 恢复。
本阶段不扩 schema、生成器、权限或支持状态，完整区域策略与冲突检测仍 deferred。

Linux amd64 定向路由入口 47352 ms、排队 150 ms；菜单 PTY 49747 ms，
均 Jobs 2、exit 0、cache_hit=false，复用工具镜像。证据分别为
`.tmp-regression-docker-4b999e940bb64d58a6ab0990c1c11d14/`、
`.tmp-regression-docker-fc3144cd60e8456ebf3599e2bb619740/`。
首次测试把候选校验误判为部署，改为检查 live 调用及受管文件不变；
非法组合仍要求完全不调用 Compose，失败输入保留。
集中合同 54/54 通过，Jobs 6、入口 283077 ms、排队 309 ms、cache_hit=false：
`.tmp-regression-docker-619e8fc5687f4692a4c38e77aca81bd1/`。
定向与完整回归源码归档相同，5 份阶段代码和测试匹配当前工作区；
核验见完整结果目录 `verification.json`。清理成功输入与核验临时目录，
保留结果、日志、核验及失败输入；文档更新不重复回归。
本阶段交付不等于整体完成，总目标保持 active。

#### 5B.4n 已有 DNS/SOCKS5 上游编辑

同阶段交付 `edit --dns-upstream <IP> <端口>` 与
`--socks5-upstream <IP> <端口>`，菜单 `17 → 41/42` 先展示状态再录入。
共用一个候选分支，仅豁免对应 server/port；域名顺序、SOCKS5 认证、
WARP 私有字段、其它路由、业务配置与累计保留，不增加 schema 或生成器。
要求已有合法配置，SOCKS5 选择性/全局均可用；同原文字面地址与端口返回 `15`。
地址复用现有可路由 IPv4/IPv6 校验并保留原文，端口 `1–65535` 显式填写，
CLI 前导零按十进制规范化。菜单空值/0/EOF 取消，状态失败停止读取，
提交只确认一次，失败或信号恢复沿用原事务。

共享合同合并检查双上游的缺失/无变化、参数与非法组合拒绝、
IPv6 与非默认端口、预览、失败恢复、名单/凭据/累计保持及原值往返；
PTY 合并覆盖正确派发、取消、状态失败和提交失败后继续诊断。
Linux amd64 定向 `docker-routing-core-policy-lifecycle` 通过，入口 38629 ms、
排队 3844 ms、Jobs 2、cache=false：`.tmp-regression-docker-a567650b82e84f49a118a6fbfab3932d/`。
集中 Docker 合同 54/54 通过，入口 297679 ms、排队 305 ms、Jobs 6、
cache=false：`.tmp-regression-docker-31040289f61b47ac9e99139d9ece3708/`；
其中菜单入口通过并保留 `docker-routing-upstreams-regression-ok` 证据。
完整区域策略、SOCKS UDP 会话撤销、TUIC 跳跃及原生宿主/arm64/公网仍 deferred，
总目标 active。

#### 5B.4o 域名层级覆盖诊断

现有 CLI/菜单 `routing-status` 同批增加 `domain_rule_coverages`，保留原精确
重叠字段。使用规则索引逐层查域名后缀，避免所有规则两两比较；报告跨策略
`full/domain` 与 `domain/domain` 覆盖、参与策略和优先者，复用区域有效规则。
按标签边界匹配，同策略去重与 global 排除；不联网，不更改配置或写入门禁。
共用组合夹具检查五策略、区域固定例外、多层后缀、相似域名边界、
同策略覆盖不误报、旧字段及部署/凭据/累计不变。
Linux amd64 定向 `docker-routing-core-contracts` 通过，入口 14481 ms、排队
3861 ms、Jobs 2：`.tmp-regression-docker-b5e1cdeb2d82410494bdfc3e8079b785/`。
集中 Docker 合同 54/54 通过，入口 283386 ms、排队 294 ms、Jobs 6、
cache=false：`.tmp-regression-docker-e51561f3975f43658e2a995117b10d9f/`。
keyword/GeoSite 语义、IP/BT、完整区域与冲突检测仍 deferred，总目标 active。

#### 5B.4p 域名解析后 IP 阻断的真实门槛

复用两核心双栈字面 IP/CIDR/GeoIP 实测，在固定 Xray `26.3.27 d2758a0`
上增加 `IPOnDemand` 候选策略对照，不修改生产生成器或开放菜单。
指定 DNS 返回被禁 IP 的正对照实际拒绝，DNS 有请求、目的和代理零接入；
本地 DNS 返回未禁 `127.0.0.2`、上游系统解析为被禁 `127.0.0.1` 时，
代理及目的各接入一次。指定 DNS 返回 SERVFAIL 后，同域名仍经代理连到被禁 IP。
两项均完成真实 HTTP 回包，不能以路由诊断、失败 DNS 或客户端超时代替。

直接开启本地解析不能完成迁移；生产合同须绑定经过 IP 判定的实际连接地址，
解析失败明确拒绝，并保持 Direct 例外、hosts/指定 DNS 来源和双族 TCP/UDP 语义。
本轮将固定核心的已知行为留作探针，核心变化后重新评估门槛。
最终 `docker-routing-block-ips-real` 通过，入口 50003 ms、排队 167 ms、Jobs 2、
cache=false：`.tmp-regression-docker-c2bee5386ade42dba1108c67e27efd04/`；
与集中合同使用相同源码归档，6 份阶段文件与工作区逐文件匹配。
已通过证据复用，不因验收文字更新重跑；本轮重复源码归档、清单及核验副本清理，
日志和 result 保留，工具镜像沿用上一阶段。
未开放解析后 IP 阻断，不将字面 IP 阻断、域名覆盖诊断或局部探针当作完整 5B；
原生宿主/arm64/公网仍未验，总目标 active。

#### 5B.4q keyword 覆盖诊断与路由菜单回归提速

现有只读 `routing-status` 同批追加 `domain_rule_keyword_coverages`：
规范 `full/domain/keyword` 正文包含另一个策略的 `keyword` 正文时，
报告 `narrow_rule/broad_rule/policies/winner`，沿用现有五策略优先级及区域有效规则。
同规则由原精确重叠处理，同策略包含不报告；不查询 GeoSite/DNS，不预测最终路径，
不改变配置拒绝条件、schema、生成器、权限或支持状态。
共用原核心合同夹具检查字符串包含、多策略优先级、同策略排除、关闭/global
空列表，以及凭据、完整部署和累计保持。

新增 `docker-menu-routing` 定向 selector，复用原菜单脚本与全部路由 PTY 断言；
原 `docker-menu` 和完整合同继续执行原集合，信号检查保留在完整入口。
默认/定向参数派发和环境变量不泄漏纳入现有 dispatcher 合同。
WARP 菜单 `6/7` 改为“隧道地址族”，与实际 family 语义一致，不承诺公网出口族。
Linux amd64、复用工具镜像：核心合同 15311 ms，路由菜单定向 14979 ms，
dispatcher 合同 1565 ms，均 Jobs 2、exit 0。集中合同 54/54 通过，
Jobs 6、入口 298695 ms、排队 308 ms、cache=false：
`.tmp-regression-docker-9b02eb0f1bdb4a1a849c5599bec1d816/`。
其中完整菜单内部 58560 ms；与定向范围、并发负载不同，不据此宣称全套缩短比例。
10 份交付文件与 full 快照匹配，随后只补验收文字；同快照 Bash、ShellCheck error
及非法 scope 拒绝通过。定向结果分别在
`.tmp-regression-docker-1089dec106e641ec9445f07c98c4382f/`、
`.tmp-regression-docker-78a32bf10e2044f4997692e0acc99fc7/`、
`.tmp-regression-docker-2afbfd578c27452fa03cfa871b9af9ba/`。
清理本轮成功输入归档、清单和核验临时文件，保留日志/result；
未改渲染或真实出站，不重复既有客户端矩阵。GeoSite、解析后 IP 门槛、SOCKS UDP、
TUIC/自动恢复及原生宿主/arm64/公网仍 deferred，整体目标 active。

#### 5B.4r sing-box 解析后 IP 阻断

菜单 `17 → 45/46` 与 `edit --block-ips-resolve/--block-ips-literal` 切换已有手工
IP 名单的解析模式。仅单 sing-box、无副核心，拒绝 WARP/IPv6 出站策略组合；
目的 IP 支持双族。缺省保持字面模式，新字段只接受 `resolve_domains:true`，
独立 `x-padm-routing-block-ips-resolve` marker 阻止旧包接受新配置。
hosts/指定 DNS/local 选择来源，选路前统一解析并重查 IP，代理必须使用经判定的
字面地址，解析失败拒绝；Direct 例外保持优先。模式同值/未名单返回 `15`，
只允许模式字段漂移，名单编辑保持模式，复用候选、预览及健康失败/INT/TERM 恢复。
状态仅新模式追加 flag，不增权限、监听或依赖。Xray 5B.4p 门槛继续 deferred。

复用原路由测试夹具建立轻 scope，跳过旧双核心大矩阵；菜单只跑新增两个 PTY 场景。
真实 sing-box 定向通过，入口 10140 ms：
`.tmp-regression-docker-ec06c8fb26df44f397a25b4cd44516e3/`。
覆盖 IPv4 字面/CIDR/GeoIP、IPv6 字面、DNS/hosts/local、Direct TCP/UDP 和 SERVFAIL；
split DNS 正例的 SOCKS CONNECT 使用 `127.0.0.2` 字面地址，诱饵禁目的零接入。
轻合同及新增菜单 PTY 通过，入口 8049 ms：
`.tmp-regression-docker-926996ba41914e8985a95e0051f86d01/`。
集中合同 55/56、292843 ms，唯一失败为旧规格谓词摘要；同步摘要及新样本后
规格差分 199 例通过（15011 ms），不重复已通过的 55 个叶子。
证据 `f059cc788c9a46a489b8673647e6886e` 与 `1eeb6a85555b43a6a2d68e1172d5cb59`。
`docker-reality` 补验通过（64252 ms）：
`.tmp-regression-docker-5ec54ddaedca458fa3eebd5899121871/`。
19 个批次文件匹配集中快照；真实 scope 的生成器/schema/夹具 5 文件匹配。
Bash、ShellCheck error、Python/JSON 和 PowerShell AST 静态检查通过。
完整区域/冲突检测、SOCKS UDP 会话撤销及原生宿主/arm64/公网仍未完成，总目标 active。

#### 5B.4s 解析后 IP 阻断与 IPv6/WARP 组合

单 sing-box、无副核心的解析模式支持已有 selective/global IPv6 和双族 WARP。
Direct 优先，沿用 IPv6 selective、WARP selective、显式 SOCKS、global 出站顺序；
各路径按出站地址族从 hosts/指定 DNS/local 解析，重查 IP 后立即选路，
代理使用经检查的字面地址，DNS/Peer 失败不回退。字面模式保持旧生成路径。
组合另需 `x-padm-routing-block-ips-resolve-egress`，仅支持基础解析的旧包拒绝组合。
复用原菜单及健康/INT/TERM 事务，不扩权限、监听或依赖，Xray 继续 deferred。

轻合同与菜单通过（8697 ms），证据 `416a8c2df9644e1ca5c16e1e921901a8`；
一次本地 Peer 覆盖 6 种组合、DNS/hosts/local、Direct、双族 TCP/UDP、
SOCKS split DNS 字面绑定与失败拒绝，通过（8049 ms），证据 `dbdf3475292e42e19b62aea9158b5faa`。
首轮夹具混入前次 TCP ACK，改为负例前等待事件稳定；保留实际拒绝日志、
目的零接入和隧道零有效载荷断言。集中合同 56/56 通过（315608 ms），
证据 `2a723926a22e4858b55adad738964958`，15 个批次文件与完整快照一致；
Bash/ShellCheck/Python/JSON/PowerShell AST 检查通过。清理源码归档、清单和核心副本，
保留日志/result。Cloudflare 账号/公网及原生宿主/arm64 仍未验，
完整区域、SOCKS UDP 会话撤销等剩余项继续 deferred，整体目标 active。

#### 5B.5 SOCKS/HTTP 入站前置核对与原生来源修复

原生 `201` 安装路径实际使用 sing-box SOCKS 入站，支持 TCP CONNECT 与 UDP
ASSOCIATE；注册表不能作为 Xray 入站已实现的证据。`source_ip_cidr` 为来源允许名单，
域名为分流匹配，不擅自改成目的白名单。`202` 尚未发现原生 HTTP 入站工作流，
后续需独立合同，不能用 HTTPUpgrade 或 NaiveProxy 替代。

核对发现原生只生成来源匹配的 direct 规则，未匹配来源仍可走默认或更早的全局放行。
新增独占 `00_00_socks5_source_route.json`，早于全局 allow，以
`inbound=socks5_inbound AND NOT source_ip_cidr` 拒绝非白名单来源；
其它入站、域名分流、地址族和 UDP 语义不变。规则更新补齐旧部署缺失的分片，
备份、失败回滚及入站/全部卸载覆盖该分片，单独出站卸载保留它。
原生修复签名提交 `d9cbd163 fix(routing): enforce SOCKS inbound source allowlists`；
前置 partial EOF 修复为 `fbe499f0`。

Linux amd64 `routing-core` `15.075` 秒、`routing-socks5-udp-associate` `309 ms`，
独立 `routing-socks5-source-real` 最终 `2.654` 秒通过。真实 sing-box merge 后
检查顺序，三个模式（全部目的分流、域名分流、仅 IPv4 来源）分别运行旧/修复对照：
旧规则下 `127.0.0.2` 的 TCP/UDP 实际触达目的服务；修复后实际拒绝且目的零接入。
允许来源、双栈、错误认证及其它入站均验证；UDP 按连接 ID 关联实际 reject 日志，
不以超时或前一个 TCP 拒绝日志冒充成功。核心以 UID/GID `10001`、无 capabilities
运行，复用固定 sing-box 镜像程序，不发布宿主端口或挂载 Docker Socket。
Shell 语法/ShellCheck error、Python AST、PowerShell AST 与独立只读复审通过。
集中 ci `35.163` 秒、入口 `36.045` 秒（Jobs `3`、未缓存）通过；
最后仅减少该真实 selector 的 Xray 程序复制，经真实 selector 补验，不重复全套。
证据 `.tmp-regression-docker-0042a4a282a14d45858b5e470ab1f62b/` 与
`.tmp-regression-docker-fd6237a62cdd4c219a9fc1c52cd4bcb8/`；日志/result 保留，
重复源码及程序副本收尾清理。

Docker 入站需独立受管合同、私有认证输入、来源前置拒绝、专项编辑及取消/回滚、
端口与部署一致性、统计身份边界和真实流量验收。SOCKS UDP 尤须验证
`BND.ADDR/BND.PORT` 在 Docker 发布/NAT 下可达，不能仅用容器内回环通过代替。
本前置修复不等于 Docker 入站交付，`internal-201`、`internal-202` 仍 `deferred`。

#### 5B.5a 已有 Xray 的 HTTP 中继入站

功能签名提交 `922fef7d`。v3 独立 `.relay.http` 保存
`core`、`port`、`address_families`、`username`、`password`、`source_ips` 六键；
只接受部署中已有的受管 Xray，不加装辅助核心，不生成公开节点/订阅链接。
sing-box `v1.14.2` 实测用伪造 `X-Forwarded-For` 覆盖路由来源并触达 origin，
固定版本源码也无禁用选项，因此校验和生成器明确拒绝，不删除攻击断言。

导入复用 root 私有 `0600` 单链接 JSON、安全祖先和 `64 KiB` 上限。
可见 ASCII 凭据为 `1–255` 字符，用户名不含 `:`，密码允许；
来源要求 `1–256` 条唯一字面 IP/CIDR，拒绝域名、GeoIP、zone 及额外键。
菜单 `17 → 21` 和 CLI `--http-relay`、`--http-relay-off` 走现有候选/确认/回滚；
普通 `--spec` 冻结中继，专项互斥，关闭保留其它配置。
预览仅字段路径，`routing-status` 固定追加脱敏 `http_relay`，关闭为 `{enabled:false}`；
同步旧 SOCKS5 六处精确状态断言，原有字段检查不放宽。

来源 allow 到专属 `padm-relay-http-direct`，随后 catch-all blocked，
先于 DNS、全局 Direct/Block、SOCKS、IPv6、WARP；系统解析不继承全局 hosts/DNS，
不改变原首出站或默认出站。只发布独立 TCP，端口冲突、deployment `relay-http`
和 `x-padm-relay-http` 旧 bundle 门禁同步，不与 TUN/TProxy 宿主网络共存。
Xray 专属 `userLevel:1` 关闭用户计数；真实同名业务 level 0 产生 counter 后，
relay 不创建或增加该 counter，不参与业务账号/订阅额度，`traffic.sh` 无改动。

Linux amd64 定向合同 `10.106` 秒、真实 Xray `296 ms`、发布专项 `6.312` 秒通过。
真实矩阵包含 HTTP/CONNECT、双栈来源、认证、独立解析、同名统计正对照；
发布专项使用隔离 Linux daemon、生产 Compose ports、外部 veth 客户端，
验证实际 DNAT 来源/CIDR、伪造 XFF/Forwarded、无/错认证和 origin 零接入，
维持 UID `10001`、只读根及零 capabilities，不使用宿主 Docker Socket。
最终 SOCKS5 定向 `136.439` 秒、完整 Docker 合同 `303.860` 秒、
ci `38.508` 秒通过；Bash/ShellCheck error、Python/PowerShell AST、
JSON、diff 检查与独立只读复审通过。
CI 快照早于 SOCKS5 六处测试断言修正；之后仅改测试/文档，
最终完整 Docker 合同使用新快照补验，不将二者视为同源码 CI。
relay 与 IPv6/WARP 隔离核对生产前置规则，未做组合真实流量对照。
完整合同 Jobs 6、ci Jobs 3，未扩大三槽预算；ci 排队 `218372 ms`，
不计作执行耗时。HTTP 真实入口只复制 Xray，复用工具/核心镜像，不重复全套。

证据 `.tmp-docker-http-relay-5b5a-evidence.md`，最终完整合同目录
`.tmp-regression-docker-856e589c6b244f6497a6029a93a14b93/`；
日志/result/失败证据保留，本轮归档、核心副本与临时脚本清理。
HTTP Basic 不加密；新增隔离 amd64 Linux daemon 的 IPv4/IPv6 端口发布、
真实 veth 来源和来源白名单验收，入口 `8.024` 秒，证据
`.tmp-regression-docker-6c2144e85faa488f9e4da3a520e6b198/`。
IPv6 relay 只把 Xray 接入受管 `padm-docker-ipv6` bridge，普通 IPv4 relay
不启用该网络；plain bridge 的旧双栈备份在停服前拒绝，避免来源折叠。
原生宿主、公网、arm64 与可信发布仍未验，
`internal-202` 和完整 routing-tools/206 保持 `deferred`。
SOCKS UDP 探针确认私网动态 `BND.ADDR/BND.PORT` 不能靠固定同端口发布解决，
同 bridge 原始 BND 正对照成功；下一步先解决发布可达与真实来源，
不能降为 TCP-only 或将 `internal-201` 标为完成。

#### 5B.5a.1 HTTP 中继日常管理

菜单 `17 → 21` 追加端口修改和来源允许名单替换、追加、精确删除，
CLI 对应 `--http-relay-port`、`--http-relay-sources`、
`--http-relay-sources-add`、`--http-relay-sources-remove`。
只操作已有中继，复用原规格校验、候选、一次确认及失败/信号恢复；
端口只豁免 `.relay.http.port`，名单只豁免 `.relay.http.source_ips`，
冻结认证、核心、地址族及其余完整规格，不扩 schema、核心或宿主权限。

CSV 去项首尾空白、按首次出现去重，保留字面值和顺序；追加在原列表后添加新项，
删除须每项精确存在。拒绝空项、非法 IP/CIDR、无变化、删空、缺项、
合并后超过 256 项和冲突端口；清空应显式关闭中继。
菜单先查看状态，失败、空输入、`0`、EOF 返回。支持范围保持 5B.5a，
完整 `internal-202` 和整体计划仍 deferred/active。

Linux amd64 定向合同 16447 ms、路由菜单 PTY 14547 ms（Jobs 2）通过；
合同覆盖字段冻结、非法/无变化/缺项/删空/256 项、双族端口同步、累计及健康/INT/TERM 恢复。
发布专项 10715 ms，复用同一隔离 daemon、veth 和真实 Xray，验证端口/来源切换、
新来源成功、旧端口/来源拒绝以及 HTTP/CONNECT、认证和原安全限制保持。
集中完整合同 54/54、302674 ms（入口 304754 ms，Jobs 6、排队 314 ms、cache=false）；
默认完整菜单 56744 ms。发布专项与 full 源码摘要一致，12 份交付文件核对匹配，
Bash/ShellCheck error 和 Python AST 通过；未重复无变化的真实路由矩阵或 ci。
证据 `.tmp-regression-docker-2385d043d40b4595802aeea0edf5afaa/`、
`.tmp-regression-docker-86b06b58041441f4b403739130348be4/`、
`.tmp-regression-docker-25db59c96ac44295ae4a847b4153ac79/` 与
`.tmp-regression-docker-6d0cbc496f794a1689909b51e2437d71/`。
后续仅补验收文字；成功源码归档/清单和临时检查脚本/容器清理，保留日志/result。

#### 5B.5b SOCKS UDP 发布与会话鉴权前置验证

未修改生产合同或开放 `201` 菜单。sing-box `v1.14.2` 的动态私网 BND 发布阻塞之外，
继续验证已有 Xray `26.3.27 d2758a0`，固定源码 commit
`d2758a023cd7f4174a5a5fa4ff66e487d4342ba0`。
Agent Reach GitHub CLI 只读核对 `infra/conf/socks.go`、
`proxy/socks/protocol.go`、`server.go` 和 `udpfilter.go`；
`settings.ip` 可指定 UDP 回应地址，BND 端口固定为入站端口，但 UDPFilter
只保留已认证 TCP 来源 IP，不绑定 UDP 端口，也不随控制连接关闭清除。
此许可保留于该固定版本当前核心进程，不是跨重启持久化状态。

Linux amd64 容器探针使用已有镜像、UID `10001`、只读根和零 capabilities，
独立服务/客户端 bridge，经 Docker Desktop 宿主同端口 TCP/UDP 发布。
显式回应地址与固定端口的 TCP CONNECT、三次 UDP ASSOCIATE/echo 均成功。
安全负例同时证实：首次无认证 UDP 被核心明确拒绝；认证后关闭所有 TCP，
同客户端新进程/新 UDP socket 不建立控制或认证，仍触达 origin 并收到真实回包。
第二独立未认证客户端也回包，但此处 hairpin 将来源折叠为同一网关，
只说明共享 NAT 场景，不外推公网不同 IP 绕过或来源保留。

固定发布连通不等于会话鉴权成立；现有 Xray 不能直接替代 sing-box 交付完整 `201`。
不降为 TCP-only、不用永久来源许可伪装 UDP 会话认证，不加自编辅助中继。
后续受管或显式宿主方案都须具备会话绑定和控制关闭后撤销；
宿主网络仅改善可达/来源，不能修复 Xray 的进程内来源许可。
证据 `.tmp-socks-xray-probe-fixed/result.md` 与 `.tmp-relay-udp-nat/result.md`；
探针所属容器/网络按 label 清理，程序/config 副本删除，日志和环境证据保留。
本阶段仅文档，不重复完整回归；公网、IPv6、原生宿主和 arm64 未验，
`internal-201` 仍 `deferred`，此前 HTTP `5B.5a` 交付不受影响。

#### 5B.5b.1 sing-box 活动 UDP 关联的来源鉴权阻塞

2026-10-14 最小真实探针复用固定 `sing-box v1.14.2` 程序及现有工具镜像。
独立 Linux amd64 容器内用原生来源拒绝规则，由 `127.0.0.1` 认证并创建动态 BND 后，
新的 `127.0.0.1`、`127.0.0.2` UDP socket 不建立 TCP 控制、不认证，
仍实际触达 echo 目的并收到回包。`127.0.0.2` 明确不在规则来源名单；
核心将真实数据报来源替换为认证 TCP 的 IP。
TCP 关闭后动态 UDP socket 撤销，原 BND 新 socket 不再触达目的。
因此关闭撤销成立不等于活动会话来源绑定成立，host-network 只改变可达性，
不能让该固定核心满足完整 `201` 鉴权要求；本轮停止该方案，不增加辅助核心、
生成器、Compose 或菜单，也不把同容器回环当作公网/宿主网络验收。

现有 `routing-socks5-source-real` 增加一条真实关联边界检查：认证正例、
被来源规则拒绝的 IP 借用活动 BND、实际 `/proc` socket 撤销、关闭后目的零增量。
它记录固定版本的已知阻塞，不是通过安全支持验收；原独立 TCP/UDP 认证控制、
三模式来源规则和其它入站检查保留。原生 5B.5 的来源修复只约束新控制连接，
不能阻止借用已有动态 UDP socket；该限制同步机器矩阵及对照表。
Docker Linux amd64 定向通过，内部 3197 ms、入口 4214 ms、Jobs 2，
证据 `.tmp-regression-docker-bb88dc57419449a2bcb195e752a34f33/`。
一次性探针、下载核心与 Python 缓存已清理，回归日志和结果保留。
`internal-201` 继续 deferred，总目标 active；公网/host-network/arm64 未验。

#### 5B.5c 受管业务入口的额外公开端口

功能签名提交 `dacc8417`。本地实现复用原生 `207` 工作流中的
“额外端口到已有业务入口”语义，
不是任意目的地址的 Tunnel/dokodemo-door，也不新增无认证转发入站。
v3 可选顶层 `port_aliases` 保存 `1–16` 条 `{listener_id, public_port}`，
缺省表示关闭，空数组拒绝；目标必须为已有受管业务入口。
`x-padm-port-aliases` 是配置、更新和快照恢复的旧 bundle 兼容门禁，
不靠升级支持矩阵绕过旧控制脚本。

Compose 将别名映射到原入口的容器监听，继承核心归属、TCP/UDP 和地址族；
Shadowsocks 同时发布 TCP/UDP，TCP 与 Hysteria2 的 UDP 可使用同一公开端口数字，
同 transport 冲突保守按 `port|transport` 拒绝。
WS/HTTPUpgrade/gRPC TLS 别名指向 Nginx `tls_port`；
bridge Reality 共存别名指向同一 Nginx `15443` SNI 前端，
不是绕过前端直连私有后端，也不按目标 ID 宣称来源或访问隔离。
别名不占用容器内新监听，私有 backend 的相同数字不构成宿主发布冲突。
Deployment 使用派生 `alias-<port>-<transport>` 资源和 `target_listener_id`，
精确匹配规格；目标基础端口改变后，别名容器端口随之重生成。
业务 listener ID、账号、凭据及统计身份保持原样，共享原业务流量额度。

CLI `edit --port-alias <入口 ID> <公开端口>`、
`--port-alias-remove`、独立 `protocol port-alias-status` 及协议菜单 `9 → 8`
复用现有候选、预览、确认、部署锁和失败恢复事务。
专项动作互斥，普通 `--spec` 冻结别名集合；
删除目标入口时清理其别名，复制入口不继承别名。
分享 URI 和主订阅仍使用原基础公开端口，不新增订阅身份；
默认分享端口切换留给 `5B.5d`，本轮不以原生默认入口已对齐交付。
Fail2ban、TUN/TProxy 与 host-network Reality stream 明确拒绝别名，
避免封禁规则遗漏或已被 host network 删除的 Compose ports；已有 WireGuard 可共存。

Linux amd64 最终定向合同、事务、Bash/ShellCheck error 和 Python AST
`18.945` 秒通过，证据
`.tmp-regression-docker-6e4fdf5804b540a999428a97aa3460b6/`；
菜单真实 PTY `33.994` 秒通过，证据
`.tmp-regression-docker-3a37c6e371474577b9e2d08400c8c281/`；
ci `37.529` 秒、入口 `38.437` 秒通过，证据
`.tmp-regression-docker-5039c4a8c55d44aabceee843d90d1259/`。
完整 Docker 合同修正普通 listener 的 `target_listener_id` 负例后，
`337.515` 秒通过（入口 `338.513` 秒，Jobs `6`，排队 `399 ms`），证据
`.tmp-regression-docker-2e8e99ee43784f9f91eee7b7b2644e62/`。
ci 快照早于最后 deployment validator 负例修正，最终完整合同包含该修补；
之后仅改真实夹具和文档，按对应真实及合同 selector 补验，不重复全套。
PowerShell AST、JSON、diff 检查与独立增量只读复审通过。

真实专项最终 `10.470` 秒通过（入口 `11.356` 秒，Linux `amd64`）；
Xray Reality TCP 和 sing-box Shadowsocks TCP/UDP 的原入口与别名入口均完成
正确/错误认证、新 socket 及关闭 alias 拒绝，生产容器维持
UID `10001`、零 capability、只读根，origin 事件按 transport 精确计数。
证据 `.tmp-regression-docker-b08b75992b4c41bf863a8df6ab39fb04/`。
生成的核心配置、统计渲染及分享 URI 在 alias 开关前后逐字相同，
事务保留已有业务累计值；未另做真实 counter 累计采样。
测试目标的 TLS 握手已改在线程内执行，避免裸 TCP 探测阻塞监听器；
该修复只属于真实测试夹具，不改变生产服务。
复用工具/核心镜像和三槽队列，不扩大并发预算；本轮源码归档副本清理，
日志、result、失败证据与共享成功索引保留，不删除其它任务的临时文件。
新增隔离 amd64 Linux daemon 的双栈 TCP/UDP 发布和来源族连接验收，入口
`10.695` 秒，证据 `.tmp-regression-docker-932f701374a840a780febfea975fa8eb/`；
公网、原生宿主、arm64、可信发布及默认分享切换仍待验。
本阶段只交付本地验收通过的局部能力，`internal-207-access-control` 仍 `deferred`，
不等于完整 `207`、routing-tools/206 或 `5B` 完成。

#### 5B.5d 逐入口默认分享端口

功能签名提交 `185362ad`。在已有 `port_aliases` 项上增加可选 `share_default: true`，不建立第二份
端口或账号状态。每个业务入口最多一项，`false`、`null`、未知键和同入口
多项默认拒绝；带标记的规格须通过 `x-padm-port-alias-default` 旧 bundle 门禁。
默认选择不改变核心配置、Compose、deployment、认证、入口 ID、统计或证书。

CLI `edit --port-alias-default <入口 ID> <已有额外端口|base>` 与额外端口菜单
走现有预览、确认、锁和失败回滚。数字只接受该入口已发布的别名，不自动添加；
`base` 清除该入口的默认标记，删除被选别名自然回退，复制不继承，删除目标联动清理。
普通 `--spec` 不得借导入更换标记；专项与其它动作互斥。

统一分享生成器在 Reality 共存公开 `443` 投影之后应用选择，
使本地 URI、主订阅和按账号/入口筛选的分享组使用相同端口；
其它身份、参数及节点数量保持不变，不把私有后端当作恢复默认端口。
原生默认额外 TCP 端口只覆盖匹配后端的分享，不联动 Hy2 UDP；
Docker 按稳定入口 ID 分别选择，UDP 入口是显式扩展，不因同端口数字自动切换。

本地定向合同 `34.798` 秒、入口 `35.637` 秒通过，覆盖全部 16 个支持协议的
URI 解析、账号身份、IPv6 authority 与参数不变，主订阅和分享组 token 内容、
stream 两入口独立选择/恢复 `443`、非法组合、普通导入冻结、删除/复制和失败回滚。
证据 `.tmp-regression-docker-f297d8f9aef14ba99488ee70d5c50e12/`。
菜单真实 PTY `34.373` 秒、入口 `35.244` 秒通过，证据
`.tmp-regression-docker-9b8d92324eae4f4cb63a116ab7005dcb/`。
真实 `on → selected → off` `11.278` 秒、入口 `12.095` 秒通过；
客户端从生成 URI 读取端口，保留 Xray Reality TCP、sing-box Shadowsocks TCP/UDP
正确/错误认证、新 socket、原/别名入口及关闭拒绝矩阵和 origin 精确计数。
证据 `.tmp-regression-docker-aff5d825621f4277b73acf89151ebb1b/`。

合同发现并修复编辑基线未重建分享组 token 的已有缺陷：
共享 baseline 复用 `dockerSubscriptionPrepareCandidate`，只写临时目录，
继续完整比较订阅目录；手改 group token 的 links/edit 拒绝负例通过。
重复确认沿用现有事务，会更新回滚元数据，不承诺整部署无操作；
合同验证业务规格、账号、订阅与累计流量不重复改变，预览和失败仍核对完整快照。
新增 stream CLI 子块因要求宿主探测不放进普通无 Socket 合同；
保留四种生成对照，不替代既有真实 stream 专项。
诊断容器、脚本与已完成回归的源码副本已清理，脱敏日志保留
`.tmp-alias-return-evidence/`，其它任务临时文件不动。

相同源码快照的完整 Docker 合同 `33/33`、`243.989` 秒通过
（入口 `244.909` 秒、Jobs `6`、排队 `385 ms`），证据
`.tmp-regression-docker-3247a6ebe62345c9bd4bed5ab620077f/`；
ci `38.855` 秒、入口 `39.761` 秒、Jobs `3`、排队 `221963 ms` 通过，证据
`.tmp-regression-docker-0dc1d202707742839693db9b435f7a11/`，两者实际执行、未命中缓存。
性能签名提交 `035c7535` 仅把历史长任务 `docker-routing-socks5` 提前到第 2 项，
33 个 selector、Jobs `6`、三槽预算、断言与缓存边界均不变。
完整合同相比前轮 `337.515` 秒减少 `93.526` 秒，约 `27.7%`；
新 alias 合同在完整并发内为 `35.878` 秒，覆盖未减，case 时长亦有波动，
不把全部差异归因于调度，也不将排队时间算入执行收益。
独立生产增量只读复审无 P1/P2；Bash/ShellCheck error、嵌入 Python AST、
Schema 正负例、JSON、PowerShell AST 和 diff 检查通过。
之后仅更新验收文档，不重复已通过的完整回归；完成目录源码归档副本清理，
日志/result 和共享成功索引保留。
公网、IPv6 发布、arm64、原生宿主及完整 `207` 验收未补，不升级支持状态。

#### 5B.5e 额外入口端口原位修改

CLI `edit --port-alias-replace LISTENER OLDPORT NEWPORT` 和协议菜单 `9 → 8 → 6`
复用已有规格校验、预览、一次确认与候选回滚。旧别名必须存在，新端口必须不同、
合法且没有发布冲突；与规格导入及其它专项编辑互斥。
只原位修改选中项的 `public_port`，完整规格必须等于这一项精确变换；
保留别名顺序、`share_default`、其它入口、认证、账号及累计流量。
已选默认别名的 URI、主订阅与分享组随事务切换，不先删除再新增。

范围仍为已有受管 bridge 入口，不增加 schema、核心、权限或任意目的转发。
本批定向核对 Compose/deployment/链接投影和菜单取消/EOF/失败恢复；
`docker-menu-port-alias` 复用原菜单脚本的全部别名 PTY 断言，
完整菜单和完整合同的集合保持不变，避免定向重复其它菜单与信号长集合。
发布生成器未变，复用 5B.5c–5B.5d 的本地真实双栈证据，不重复相同矩阵。
公网、原生宿主、arm64 与完整 207 仍待验，支持状态保持 `deferred`，总目标继续 active。

2026-10-14 Docker Desktop Linux amd64 验收，全部实际执行、cache=false：

| 检查 | 内部 / 入口毫秒 | 证据目录 |
| --- | --- | --- |
| `docker-entry-port-alias`，Jobs 2 | 38597 / 39701 | `.tmp-regression-docker-ee44495ec9654668845f030464b2dd01` |
| `docker-menu-port-alias`，Jobs 2，14 个 PTY 场景 | 1669 / 2695 | `.tmp-regression-docker-8a750f1be1334631823a361173380382` |
| `regression-dispatcher-contract`，Jobs 2 | 577 / 1582 | `.tmp-regression-docker-b0d150f191e44d928567f462479e68b0` |
| 集中 `docker-contracts`，Jobs 6，54/54 | 307208 / 309253 | `.tmp-regression-docker-70f4eb4d2b0e4068a7d519b96b58ed64` |

四次源码归档摘要相同：
`141C525932D0AD20B19D5568B162C8355EB18F9E332C5222E1F7DBB50DAC2C58`。
7 份代码/测试/派发文件逐文件匹配完整快照，Bash/ShellCheck error 和 diff 检查通过；
之后仅补验收文字，不重复回归。预览/缺旧/同值/新冲突/非法组合均不改部署，
健康失败、INT、TERM 恢复完整快照；成功仅改目标端口，核心/账号/流量/私有材料保持，
Compose 双栈旧端口消失、新端口发布，deployment 与 URI/主订阅/分享组一致切换。
完整集合内菜单为 57067 ms，定向为 1669 ms；覆盖范围和负载不同，不推算全套提速比例。
成功源码归档和清单清理，保留日志/result；下一批继续 TUN 归属与日常管理。

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

#### 5C.1 已有 Fail2ban 维护子集

新增 `fail2ban status` 和 `fail2ban unban <单个 IPv4/IPv6>`，
菜单 18“服务维护”第 5 项提供状态查看及确认后的单 IP 解封。
只访问固定 `padm-nginx` jail，不提供任意 jail、批量解封或新建封禁，
不自动启动服务，不使用临时 host 网络容器或宿主全局 Fail2ban。

入口核对受管 spec/deployment/images.env、生成 Compose、四个 Fail2ban
配置正文、路径及唯一运行容器的镜像、标签、命令、用户、能力和挂载；
然后只 `exec` 已核验的容器 ID。非法参数/字面 IP 返回 `2`，
未配置、停机、归属或配置漂移返回 `15`，底层执行失败保留非零返回码。
IPv4、IPv6 及 IPv4 嵌入 IPv6 保留输入原文；拒绝前导零 IPv4、CIDR、zone 和选项。
取消、EOF、后端失败及信号沿用现有菜单清理。
初版入口不读取 Fail2ban 进程已加载的运行时 action；后续 5C.3 已补命令、
公开参数与有效属性缓存审计，任意特权篡改和完整宿主管理仍不在保证范围。

新增 `docker-fail2ban-real` 定向入口复用原隔离 action 夹具与当前源码快照，
只离线传入已有 net 镜像，不重建镜像或挂载宿主 Socket；
补状态中的地址列表、IPv6 单 IP 解封及保留 IPv4 封禁断言。
它不进入普通合同清单，真实内核动作必须显式执行。
本项不解决旧状态资源归属、真实客户端来源及新启用流程，
不把维护子集作为完整 5C 或宿主重启/卸载验收。

本地验收（2026-10-10，Linux amd64）：

| 检查 | 结果 / 秒 | 证据目录 |
| --- | --- | --- |
| `docker-menu`，Jobs 2 | 39.271 / 入口 40.248 | `.tmp-regression-docker-9fba0d8a91c9430090c114da50e5173d` |
| `docker-phase4`，Jobs 2 | 30.118 / 入口 31.124 | `.tmp-regression-docker-ae0ec3d9ea4b46a6905d98e87ebc0a48` |
| `docker-fail2ban-real`，Jobs 2 | 43.274 / 入口 44.177 | `.tmp-regression-docker-b7ba712951aa452bbebacd26a2130cf5` |
| 架构保护后的隔离实测，Jobs 2 | 45.052 / 入口 45.971 | `.tmp-regression-docker-3fa3d5f5fc084eb1a598a1e219ee7ad1` |
| `docker-contracts`，Jobs 6 | 33/33，264.100 / 入口 265.000 | `.tmp-regression-docker-76d0002baab04aa6b8c78381070fc51c` |
| 原生 `core-safety-rollback`，Jobs 2 | 7.855 / 入口 8.731 | `.tmp-regression-docker-5930cc0812f349ea8dd29df5f1dad7df` |
| 原生 `core-install-signal-rollback`，Jobs 2 | 26.419 / 入口 27.406 | `.tmp-regression-docker-09ddb6383a104a9aa346b7ffe1487acc` |
| 修复后的 `ci`，Jobs 3 | 44.653 / 入口 45.573 | `.tmp-regression-docker-fb30399ca65a40ac9873c5702681a632` |

复用工具镜像 `sha256:3a790074c74a19bd40e6c5fdeeebcdba5ae230548f057ca4ca1d40f49435ce55`；
net 实测镜像 `padm-local/padm-net:control-4c4b`，
ID/digest `sha256:69103244783b8f89bca22cdd2f65bb06d3dec15858b2d218ed8ced0029e9a9e8`，
已核对为 `linux/amd64`。完整合同源码内容摘要
`4EBD8379D62D55CAA8B345C33B6A61B602371E9F0D016F66930F00141BA045B9`，
之后只补架构 guard 和并行原生修复，最终 CI 内容摘要
`A33AB195D4A39380F35CC4ADCF3F6F31633C0D044604A087C3919E5D7B8EA02A`；
不把不同源码快照宣称为相同输入，全部未命中缓存。

初次 phase4 夹具缺新增安全字段、实测 wrapper 换行语法错误均已修正并重跑，
失败证据分别保留在 `.tmp-regression-docker-5cd24be89770491393dba6427878cc13`
和 `.tmp-regression-docker-87085d1bdb79469e912c2e34942ba586`。
集中 CI 首次在并行原生新调用路径遇到未初始化 `release`，
Geo 故障夹具又误匹配备份阶段；证据
`.tmp-regression-docker-a30abcacf8ad43199dbe32a23a473529` 保留。
顺手修复共享启动注册 get/set/restore 的空值访问，并把 Geo 注入限制在真实目标，
保留正常恢复、恢复失败和信号断言；未回退其它任务已提交的改动。
8 个 Docker Shell 加 2 个原生 Shell 的 Linux Bash/ShellCheck error、
PowerShell AST、实际 AST guard 的 6/6 平台判断及 diff 检查通过。
独立复审的 P2 镜像架构缺口已补拒绝保护，不放宽原生架构约定。
本次未增加并发预算；完成回归的源码归档/清单和检查脚本已清理，
日志/result/共享镜像缓存保留，不动其它任务临时文件。
功能 `c66875c1`、架构保护 `05af2d4a`、原生顺手修复 `3257d230`
均为本地 SSH 签名提交，签名 `G`，未推送。

#### 5C.2 TProxy 运行时所有权前置

运行时 state 升为 schema 2，固定 11 字段，root/0600/单硬链接/非符号链接，
逐字核验格式，不 source 或 eval。随机 `padm-tproxy-<12 hex>` 链的全部规则和
PREROUTING hook 带完整 32 hex token；路由表等于 mark，策略优先级 `30000`，
rule/route protocol `186`，local route 另绑定 token 派生 realm。
旧两字段 state、固定链、孤立随机链、同表外来路由、同优先级、mask 重叠或
反向 fwmark 规则拒绝接管，保留资源及原 state。

新增 JSON 内核审计，复用 net 镜像已有 Python 3，不新增宿主工具。
启动逐条失败短路，hook 最后挂入；INT/TERM 由 EXIT 统一精确回滚。
撤销前核对全部现存资源，只接受可证明归属的子集，逐条 `iptables -D/-X`、
精确 `ip rule del` 和 `ip route del`，不使用 chain/table flush。
清理失败保留 state；路由或规则删除失败可重试。
`-N` 到首个 marker、最后 `-D` 到 `-X` 的 SIGKILL 空链窗口无法跨进程证明归属，
会保守拒绝自动清理，必须在原生主机上人工核对，不能仅删 state 强制重试。

候选预检只读挂载当前 `data/net/transparent` 到独立 owner 路径，核对旧资源
后检查新参数冲突，不把旧 state 复制到候选。未配置 TProxy 不挂 owner；
部署校验使用当前 state。spec/deployment 的 `firewall_rules=["padm-tproxy"]`
保持逻辑合同兼容，随机内核资源只存 runtime state。

新增 `docker-tproxy-ownership`，并入普通完整合同；`docker-tproxy-focused`
并行运行 ownership 和 phase4。新增显式 `docker-tproxy-real` 复用离线 net 镜像
及隔离 daemon，实际入口只读挂载本次源码快照，摘要核验一致，不执行镜像旧源码，
不挂宿主 Socket。覆盖真实启动/健康/重配预检/TERM、外来资源保留、
同表漂移拒绝、旧 state 拒绝及缺 TCP 规则的健康失败与精确撤销。

本项仅为资源安全前置，不增加 TProxy 菜单或升级功能状态。
真实客户端透明流量、宿主 systemd/重启/卸载、原生 arm64 和生产防火墙矩阵
尚未验收，5C 与总目标继续 active。

本地验收（2026-10-10，Linux amd64）：

| 检查 | 结果 / 秒 | 证据目录 |
| --- | --- | --- |
| `docker-tproxy-ownership`，Jobs 2 | 18.060 / 入口 18.965 | `.tmp-regression-docker-f31d7b6534f643e79e6f9a0c432b733b` |
| 外部 goto 引用补验，Jobs 2 | 18.018 / 入口 18.884 | `.tmp-regression-docker-41cdcf43513f47c28b33f673847b268d` |
| `docker-tproxy-real`，Jobs 2 | 8.594 / 入口 9.518 | `.tmp-regression-docker-75dc87c8c91c453a8ce7153539f75fa1` |
| `docker-tproxy-focused`，Jobs 2 | 2/2，33.615 / 入口 34.604 | `.tmp-regression-docker-0459cf67c97a41f5a9995c16d9aa08af` |
| `docker-contracts`，Jobs 6 | 34/34，263.263 / 入口 264.122 | `.tmp-regression-docker-0463ad7eeaca40b48b06bfa471e4b0a2` |
| `regression-dispatcher-contract`，Jobs 2 | 0.455 / 入口 1.443 | `.tmp-regression-docker-7f0d0d8737cb40efb9b69942e1aa17c8` |

复用既有原生架构工具及 net 镜像，不扩大三槽预算，不重建依赖镜像。
完整合同快照先于最后 5 行规则顺序约束及对应测试，之后只对这个新分支补验
ownership 与真实内核；不把不同输入摘要声称相同，也不重复执行已通过的其它模块。
之后补外部 `iptables -g` 引用的拒绝检查，ownership 和 Linux 静态检查通过；
此更严格的拒绝分支未重跑完整合同，不把先前快照视作最终源码的全量证明。
完整合同内容摘要为 `207AD58D189684BF9888D2F84E4E2AC4D372A9735737682D8B01594E06B0F949`。
最终 6 个 Shell 的 Linux sh/Bash 语法、ShellCheck error、PowerShell AST 与
diff 检查通过。独立复审的掩码、反向规则及顺序问题均已补最小拒绝断言。
dispatcher 初次暴露既有长任务调度顺序与预期夹具不一致，已修预期并复验。
失败的 mock 输出及错误 PID 注入、真实夹具 cp/tmpfs 的日志保留；
正常/失败回归的源码归档和清单清理，日志/result/共享缓存保留。
候选 `d4087c20`、运行时 `1fea324c`、goto 防护 `5d73f28e` 均为本地 SSH 签名
阶段提交，签名 `G`；未推送、发布或构建新业务镜像。

#### 5C.2b TProxy 日常管理与事务切换

菜单 `17 → 43` 接入 `protocol tproxy-status`、`edit --tproxy-enable PORT MARK`、
`--tproxy-settings PORT MARK` 和 `--tproxy-off`。复用完整规格、候选预检、
一次确认、配置备份及失败/INT/TERM 恢复；专项只豁免 TProxy 对应字段，
认证、入口、发布版本、核心和其余规格冻结。预览及取消不停止在线服务。
启用或修改限定单 Xray/sing-box Reality，无其它宿主集成；端口冲突、
保留 mark `253/254/255`、重复启用、未启用修改/关闭和无变化均拒绝。

切换前核对旧规格、部署、编排与唯一容器归属，停止刚审计的 CID，
只接受正常退出并证明旧 state/规则/路由清空后移除该容器。
失败或漂移保留原现场；配置恢复、更新和普通启停共用该协调路径。
仅支持 IPv4 `PREROUTING` TCP/UDP，核心使用 host 网络/root/`NET_ADMIN`；
状态是规格状态，不能代替内核健康。TUN、OUTPUT、IPv6、原生宿主、
arm64、公网、整机重启与完整卸载仍待验，5C 与总目标继续 active。

本地验收（2026-10-14，Docker Desktop Linux amd64，复用工具及业务镜像）：

| 检查 | 结果 / 入口秒 | 证据目录 |
| --- | --- | --- |
| 菜单 PTY，Jobs 2 | routing 分支通过 / 16.661；同次管理夹具失败另行修复 | `.tmp-regression-docker-bf9b7f4e1d6b429b9aa8161bfe8608bd` |
| 最终管理、归属、生命周期及停止 INT，Jobs 2 | 通过 / 22.049 | `.tmp-regression-docker-c2e5765741cd41c2900f5edb3c5191df` |
| 隔离真实转发及生产 Compose 停止门禁，Jobs 2 | 通过 / 25.566 | `.tmp-regression-docker-e3a8a5d5ed2d4b088acb7e77e93ac6f8` |
| 集中 `docker-contracts`，Jobs 6 | 51/54 / 299.710；3 个旧夹具失败 | `.tmp-regression-docker-b4e1837947904e19860a7d3d2cd45c2d` |
| 修复后 `docker-reality`，Jobs 2 | 通过 / 65.997；190 个校验差分场景 | `.tmp-regression-docker-181affdb8836401eb3cf497134e99a88` |
| 修复后 `docker-control-cli`，Jobs 2 | 通过 / 14.716 | `.tmp-regression-docker-fa0373d654b34570bf22b47a1057d667` |
| 修复后完整 `docker-phase4`，Jobs 2 | 通过 / 149.352 | `.tmp-regression-docker-604420535bc44df8b34718abc0520537` |

真实流量使用 client/router/origin 独立网络空间，两核心各测试
`31298/129 → 31299/131`。TCP/UDP 回包、TPROXY 计数、核心目的日志及
目标所见核心出口地址共同证明转发；重配换 token、旧链消失，关闭恢复外来
规则/路由基线。真实 Compose 场景沿生产配置生成器与归属检查执行
`running → stop → exited(0) → unowned preflight → rm`；
host 指外层隔离回归容器，未借用宿主 Docker Socket。
业务 net 镜像入口旧时只在本次私有 daemon 构建替换当前入口的薄测试层，
不能计作可信发布镜像净构建验收。

完整合同快照内容摘要
`138413701240736C77B46AB7F5F4479C5ECE1D037E69A5C9BB0360869100B092`。
随后只修无 TProxy 时的 Fail2ban 定向路径、混合规格重启后的规则容器重建
及对应夹具；规格固定摘要新增保留 mark/单核心约束，控制生命周期夹具显式
声明无集成，phase4 提供真实编排对应的 CID/inspect/停止数据。
新增混合启动失败断言不审计未启动服务；临时复制保留原权限，避免污染 INT 夹具。
最终定向和完整快照不是相同输入，不宣称最终源码一次性 54/54；
只补失败项及新分支，不重复已过 51 项或扩充双核心矩阵。
最终 24 个代码、测试及回归入口文件与 phase4 快照逐文件 SHA256 一致，
最后只更新文档与状态。Bash/ShellCheck error、PowerShell AST 及 diff 检查通过。
所有本次回归未命中缓存，未扩大共享三槽预算；成功/失败输入归档在核验后清理，
日志/result 保留。普通重启会精确撤销并重建规则容器，主核心定向启动同样补建。
完整 5C、发布与总体计划继续 active。

#### 5C.2b.1 TProxy IPv6 与双栈

菜单 `17 → 43` 增加族选择，CLI `--tproxy-family ipv4|ipv6|dual` 仅与
启用/参数修改组合。启用默认 IPv4；修改省略族时保留原值，不给旧输入补字段。
两核心非 IPv4 监听 `::`，Compose、健康、预检及部署监听同步族信息。
非 IPv4 要求 bundle marker `x-padm-tproxy-ipv6`；旧 IPv4 参数格式保持。

IPv4 state 保留 schema 2 原格式，IPv6/双栈使用 schema 3 并追加 family。
同一随机 token 绑定各族 chain/rule/route；IPv6 内核不回显 realm，
改用 token 派生 metric 精确核验/删除。候选只读核验旧族与新族资源并集，
启动失败或 INT/TERM 撤销两族；任一族漂移在清理前拒绝，全部保留。
旧 schema 2 可正常撤销后切换族；更旧两字段 state 继续拒绝自动接管。
各族须已开启宿主转发并支持对应 TPROXY target，不改宿主 sysctl。

本地验收（2026-10-14，Docker Desktop Linux amd64，Jobs 2）：

| 检查 | 入口秒 | 证据目录 |
| --- | --- | --- |
| 管理事务 | 24.804 | `.tmp-regression-docker-be955e32fb0a426a8de6e3ef8ab68ad2` |
| 菜单路由 | 16.303 | `.tmp-regression-docker-add59d30c83b4c20ac90d7747364a929` |
| 规格校验，215 个差分场景 | 13.679 | `.tmp-regression-docker-2a63fa59c2054fc3be25ba23008d12b9` |
| 两族所有权/失败恢复及管理 | 53.114 | `.tmp-regression-docker-5b50cb746cd54f869f64099651ad2beb` |
| 两核心三族真实 TCP/UDP 转发/停止 | 35.570 | `.tmp-regression-docker-995cee1578494dcfb2c10e6154cd0389` |
| 集中 `docker-contracts`，Jobs 6，56/56 | 341.136 | `.tmp-regression-docker-37d74d5812734e8da12a9a170d7397bc` |
| 派发合同 | 1.648 | `.tmp-regression-docker-8be1df07eefd4fab91fa2c5bf0be34d8` |

真实 client/router/origin 分离，回包、TPROXY 计数、核心目的日志及目标所见
源地址共同证明转发，停止恢复两族外来规则/路由基线。夹具等待 IPv6 DAD
稳定后取基线，并修复 Bash 关联数组的族索引计数，不放松断言。
完整合同后将耗时 53 秒的所有权回归提前调度，只调整同一 56 项集合顺序，
不扩并发，派发合同补验通过；未重跑全套，不宣称已测得提速比例。
14 份生产、合同和功能测试文件逐文件匹配完整快照，后续仅改派发顺序与文档；
输入归档/清单清理，日志/result 保留。
OUTPUT/Redirect、原生宿主/arm64/公网/重启和完整卸载继续 deferred；
本项只完成 TProxy PREROUTING 双栈，5C 与整体目标继续 active。

#### 5C.2b.2 指定 UID 的本机 TProxy 转发

菜单 `17 → 43 → 5/6` 和 CLI `--tproxy-output-uid UID` / `--tproxy-output-off`
管理单 UID 的本机主动 TCP/UDP，启用或参数编辑复用原候选、确认和恢复事务。
UID 为 `1–2147483647`、排除 `10001`，默认关闭；修改省略时保留旧值，
关闭 OUTPUT 保留 PREROUTING。owner + conntrack ORIGINAL 避免捕获服务回包，
LOCAL 绕过；root 核心自身拨号及 DNS 不进入捕获。两核心、三族范围保持。

新模式使用 schema 4 绑定 UID、family、两条随机 token 链及 route/rule，
旧 schema 2/3 不补字段。候选只读核验旧资源，两族两链审计成功才清理；
漂移保留全部资源，第二族失败及 INT/TERM 精确撤销，清理失败保留可恢复 state。
bundle 必须有 `x-padm-tproxy-output-uid`；不改宿主 sysctl 或增加依赖。
顺手修复 DNS 菜单非法端口仍追问域名的问题，立即提示并返回。

定向 Linux amd64：管理/菜单 32.803 秒、228 个规格差分 15.741 秒、
所有权与恢复 72.088 秒、两核心三族真实转发及 Compose 停止 55.441 秒通过。
同轮验证 PREROUTING、OUTPUT TCP/UDP/DNS、未选 UID、LOCAL、服务 REPLY、
关闭恢复外来基线；严格 all/lo rp_filter=1 及其余常见过滤 sysctl=0 通过，
未据推断增加不必要的预检门禁。集中 `docker-contracts` 同快照 56/56 通过，
入口 340.748 秒、排队 314 ms、Jobs 6、cache_hit=false，证据
`.tmp-regression-docker-52a6329bd9d14a28ad6996f96643c0b8/`。
源码摘要 `020854D213EF96D23FB9BFE6C695C21363FDF6E42B450E24650955CEC2848AE4`；
14 份生产/合同/功能测试与完整归档逐文件一致，随后只改派发和文档。
派发合同补验入口 1.938 秒；本轮 12 个归档/清单清理，日志/result 保留。

focused 入口改为所有权（已包含管理）+ 菜单，避免另跑管理；完整集合和并发不变。
全主机 OUTPUT、Redirect、原生宿主/arm64/公网/重启与完整卸载继续 deferred，
5C 与总体计划保持 active。

#### 5C.2c TUN 管理与资源生命周期

菜单 `17 → 44`、`protocol tun-status`、`edit --tun-enable/--tun-off` 复用
完整规格和候选事务；只开放单 sing-box、单 Reality、IPv4、无其它宿主集成。
固定 `padm-tun`、`198.18.0.1/30`，全局 IPv4 TCP/UDP，IPv6 拒绝；
host/root/NET_ADMIN/设备显式启用，核心不自动重启。旧 bundle 缺少
`x-padm-tun-owned-management` 拒绝启用和恢复，不扩大其它组合支持。

`tun.state` 绑定随机 intent、CID/StartedAt、netns/boot、ifindex、动态表/端口
及 sing-box 完整 nft/rule/route 闭包。候选只读核对在线归属；
启停、更新和恢复先审计再正常停止核心，基线清净才删 state/容器。
helper 不删除内核资源；漂移、SIGKILL、残留及失败启动不能证明清净时保留现场。
首次启用只交接刚核验的旧 sing-box，预览/取消不停止旧服务。

Docker Linux amd64 定向菜单、资源、管理/信号恢复通过，入口 19.077 秒：
`.tmp-regression-docker-88c1882e6eef4144a0894872fe6af1f5/`。
隔离 daemon 使用生产生成器/Compose/身份检查，验证归属绑定、漂移拒绝、
重启新 owner、正常关闭基线恢复与外来资源保全、异常退出保留证据，
入口 33.713 秒：`.tmp-regression-docker-e4c937f859d14fe0a8b037401dd07949/`。
真实 TCP/UDP 和 TERM 清理沿用 `.tmp-tun-probe-20261014/`，不重复流量矩阵。
最终 NFQUEUE 门禁拒绝外来 queue 100、覆盖区间和未知动态选择器，
避免消费外来排队流量。真实只读候选、冲突拒绝及完整启停最终补验
35.443 秒：`.tmp-regression-docker-050ef39d8dd5497cb451df659aa098c4/`。
管理/资源最终合同 18.154 秒：
`.tmp-regression-docker-daadf25918494c3ca9edc4fbf8a6a56f/`。
集中合同 53/55、311.900 秒：
`.tmp-regression-docker-60060ddc7b8947b3a3ab31bcbc7aef34/`；
两个旧夹具为谓词摘要和旧双栈 TUN 成功预期，修后定向均通过：
`docker-reality` 194 个差分场景、70.542 秒（`57dc509251d24896a37cb8998b87c316`），
`docker-phase4-lifecycle` 45.955 秒（`e54b9fa5e602421aa786be6c494848c3`）。
20 个实现/测试与对应输入逐文件一致；不声称同一快照 55/55，不重复通过项。
Bash/ShellCheck error、PowerShell AST 和 diff 检查通过。
复用工具/离线镜像，未扩大三槽预算；本轮输入清理，日志/result 保留。
原生宿主、arm64、公网、整机重启和完整卸载仍待验，5C 及总目标保持 active。

#### 5C.2d Redirect TCP 菜单、事务与真实转发

菜单 `17 → 47` 与 `protocol redirect-status`、
`edit --redirect-enable/--redirect-settings/--redirect-off` 提供完整日常入口，
参数复用 family 与可选 OUTPUT UID/全主机 OUTPUT。限单 Xray/sing-box、已有 Reality `1/2/26`，
允许同核心多入口，无副核心或其它宿主集成；与 TUN/TProxy 互斥。
Redirect 仅捕获 TCP，UDP 保持原路由；透明 TCP/UDP 另选 TProxy。
默认 IPv4、OUTPUT 关闭；修改省略保留旧族/模式，UID `1–2147483647` 排除 `10001`。
指定 UID 模式下 LOCAL、服务 REPLY、root 核心拨号绕过；全主机模式捕获 root
与其它 GID 主动 TCP，核心专用 GID `10001`、LOCAL 与 REPLY 绕过。

schema 1 私密 `redirect.state` 固定字节、单硬链接、完整随机 token，
绑定两族 PREROUTING/OUTPUT 链。候选只读审计，整体核验后精确撤销；
任一漂移保留全部资源与 state，第二族失败及 INT/TERM 恢复，
不 flush、不删 conntrack、不改 sysctl。旧包须有独立 `x-padm-redirect`。
复用原配置事务、参数化菜单及已核验 Compose 的健康/启动参数，减少重复实现。

Docker Linux amd64、复用工具/离线镜像，定向 Jobs 2、合同 Jobs 6：

| 验证 | 入口耗时 | 证据目录 |
| --- | --- | --- |
| 所有权、管理/信号恢复和菜单 | 55.240 秒 | `.tmp-regression-docker-b31c423f1eca4ee99b1949f678cc87d3` |
| 两核心、三族真实流量及生产 Compose 撤销 | 39.237 秒 | `.tmp-regression-docker-65194074a71947c9b290578d5e3e7dbc` |
| 274 个 schema/jq 差分 | 16.931 秒 | `.tmp-regression-docker-4c418b4bd5114f1b8fc9ce382e0a5110` |
| 集中合同 56/57 | 323.993 秒 | `.tmp-regression-docker-5bc0855411d0429fb02a31abef2efac4` |
| 唯一失败的旧矩阵断言修复后定向补验 | 46.463 秒 | `.tmp-regression-docker-bc303e91dabe4c519df91bab983ece15` |
| 派发与 CI 18 分片集合一致性 | 1.628 秒 | `.tmp-regression-docker-c71eaa5785964797927c2efa2fd67204` |

真实流量证明 TCP PREROUTING/选中 UID OUTPUT、UDP 原路由、未选 UID、
LOCAL/REPLY 绕过及停止外来基线恢复，生产 Compose 归属和精确关闭通过。
集中回归的唯一失败是 phase3 仍要求旧功能键集合，已增加 Redirect 元数据和
缺项/错误网络的拒绝断言后补验；不声称最终同快照 57/57，也不重复已通过的 56 项。
本轮原始夹具错误已修正，日志/result 和快照核对证据保留，输入归档及清单清理。
原生宿主/arm64/公网/重启/完整卸载和完整 205 管理继续 deferred；
剩余 SOCKS UDP、Xray 解析后阻断、TUIC/自动恢复等继续推进，总目标保持 active。

#### 5C.2e TProxy/Redirect 全主机 OUTPUT

菜单复用 `17 → 43/47` 的第 7 项，CLI 提供
`--tproxy-output-all` / `--redirect-output-all`。全主机模式与指定 UID 互斥，
状态分别使用 TProxy schema 5、Redirect schema 2 的 `output_all=true`，
共享 bundle marker `x-padm-transparent-output-all`；旧无 OUTPUT/指定 UID 状态继续兼容。

全主机模式要求单核心 Reality `1/2/26`、无其它宿主集成，核心 Compose 实际运行身份
固定为 `0:10001`。TProxy 捕获主动 TCP/UDP，Redirect 捕获主动 TCP；两者均保留
LOCAL 与 conntrack `REPLY` 绕过，GID `10001` 在捕获前返回。管理路径同时核验
核心容器的镜像、命令、host 网络、Compose 归属与实际进程四列 UID/GID；身份或规则
漂移、缺少关键绕过、顺序变化和外来引用均保留 state 与现场，不先撤销另一族。

本批次按一个冻结源码快照复用工具镜像集中验证：

| 验证 | 入口耗时 | 证据目录 |
| --- | ---: | --- |
| schema/jq 302 差分 | 19.503 秒 | `.tmp-regression-docker-cfc8e398349743f2be57b69222087f96` |
| TProxy 所有权、事务、菜单及核心身份 | 91.219 秒 | `.tmp-regression-docker-3a6f958b067147e6945ba822599b3cd0` |
| Redirect 所有权、事务、菜单及核心身份 | 90.093 秒 | `.tmp-regression-docker-e08c50b2f37c4e0190a1ad578a8156f5` |
| TProxy 两核心三族真实流量/Compose 撤销 | 97.779 秒 | `.tmp-regression-docker-c50d710f05564be4bf89618a71ee4754` |
| Redirect 两核心三族真实流量/Compose 撤销 | 76.885 秒 | `.tmp-regression-docker-1146b55f538242b5b7562ae9a12d567b` |
| 集中 `docker-contracts`，Jobs 6，57/57 | 371.871 秒 | `.tmp-regression-docker-e1832c2518864ba0982064e1dc7679df` |

真实矩阵已确认 root/普通 GID 主动流量、专用 GID 绕过、LOCAL/REPLY 绕过、
Redirect UDP 原路由、停止后的规则/路由基线恢复，以及生产 Compose 核心实际身份。
六次回归源码摘要均为
`D154877D1C1ACB7208DA5555682921AC9A087602E9B3152A802168F4C9DB3F73`；
16 个代码文件逐字节匹配，随后只补计划和状态。定向 Jobs 2、集中 Jobs 6，
复用工具/离线镜像和同一核心节点，不为新模式重建流量矩阵；完整回归仅一次。
成功输入归档/清单及核验脚本清理，日志/result/verification 保留。
原生宿主、arm64、公网、整机重启和完整卸载仍未验收；总目标保持 active。

#### 5C.3 Fail2ban 已加载动作维护门禁

在既有磁盘配置/容器身份核验之后、输出唯一容器 ID 之前，复用 net 镜像内
Fail2ban `Configurator`、`CommandAction` 和 `CSocket` 做只读 runtime 审计。
不新增 helper、镜像层或宿主依赖，维护 client 的固定 jail/字面地址 argv 不变。
仅允许一个 `padm-docker-user` 标准 `CommandAction`；公开属性集合、
动作命令、iptables/端口/地址族参数和有效 `_properties` 缓存逐项匹配规范配置。
额外缓存键拒绝；三个原生派生缓存键按当前 IPv6 设置重算，`banEpoch` 不作固定值比较。
动作、额外 action 或缓存漂移，以及查询/解析失败，都返回既有状态码 `15`，
不执行维护 client、不启动容器、不改部署文件或防火墙规则。

审计与维护不是特权并发修改的原子事务；Fail2ban 的原生反射/pickle 协议
不作为抵御恶意 Python getter、程序修改或任意私有执行缓存篡改的安全边界。
本项不改变固定链/旧 state 的规则归属，也不代替真实客户端来源和宿主重启/卸载验收。
Fail2ban 完整管理与 5C 仍未完成。

本地验收（2026-10-10，Linux amd64）：

| 检查 | 结果 / 秒 | 证据目录 |
| --- | --- | --- |
| `docker-phase4`，Jobs 2 | 32.060 / 入口 32.943 | `.tmp-regression-docker-e07ddf3cdf0f4d09bd2bec7ae728871f` |
| 最终 `docker-fail2ban-real`，Jobs 2 | 45.241 / 入口 46.151 | `.tmp-regression-docker-11b9b79416474b72adf9fba8125f7fb2` |
| `docker-contracts`，Jobs 6 | 36/36，236.539 / 入口 237.424 | `.tmp-regression-docker-fb6e84217a1541baa886489fb245a7fe` |

真实夹具提取同一生产脚本，不复制审计算法；验证标准启动/封禁/恢复后审计通过，
公开动作与双栈参数、额外 action、私有命令/family/派生缓存污染均拒绝，
规则正文与封禁列表不变，污染命令标记未执行；恢复后原有 IPv4/IPv6 解封和 TERM 通过。
phase4 验证审计严格先于维护、失败返回码及不启动服务；最后类型门禁更严格的改动
由真实测试及完整合同覆盖，不把较早定向快照视作同一输入。
最终真实与完整合同的源码归档摘要均为
`C6B54778CBEF0C2363E52B0D1D9DF75D7701F07D4950B9AB36B40209F7FA7919`；
完整内容摘要 `7D005CC2C7275F17DA2B10BF3B7B6FD1F45ED55CBF74A67B06A8D9CB2D6FF704`。
三个生产/测试文件与两个归档逐文件一致；之后仅补本节证据和状态快照。
工具及 net 镜像复用 5C.1 的 digest，未重建，未命中缓存；完整排队 386 ms，
真实排队 215 ms，保留三槽预算。三个 Shell 的 Linux 语法/ShellCheck error、
生产 inline Python 编译、PowerShell AST 与 diff 检查通过，独立复审无未决 P1/P2。
早期夹具的 shell 换行、原参数恢复、动态时间戳、空缓存与 lazy 派生期望误判已修复；
失败日志保留，源码归档/清单清理，不动其它任务临时文件，不推送或发布。

#### 5C.4 Fail2ban 运行时所有权与真实双栈来源

state 升为 schema 2，固定 `schema_version/token/chain/ports/ipv6` 五字段，
root/0600/单硬链接/非符号链接、逐字 canonical 核验，不执行 state。
每次启动生成 32 hex token 与 `padm-f2b-<前 12 hex>` 链；
hook、单 IP DROP 和链尾 RETURN sentinel 均带完整 token。
所有 start/stop/flush/check/ban/unban 共用生产 owner helper，绑定本次启动 token，
每次写入前核对当前 state 和受保护的全部地址族，只逐条 `-D/-X`，不使用链 flush。
拒绝旧 ports-only state、固定链、无标记空链、外来 jump/goto、未知规则、
重复 hook、sentinel 顺序与 hook 被前置 RETURN 遮蔽；失败保留 state。
候选只读挂载当前 owner；installed validate 传 owned，cleanup 绑定初读 token。
IPv6 输入解析后规范化，保留映射 IPv6 支持并拒 zone/跨族输入。

维护在 loaded-action 审计之后增加 live owner/内核只读门禁，
防止 action 拒绝而 Fail2ban 票据已被 client 删除；失败返回 `15` 且不执行维护 client。
容器 capability 比对接受 Docker 的 `CAP_` 前缀，仍核对严格能力集合。
真实来源夹具发现原双栈发布经 IPv4 bridge proxy，Nginx 首字段变为 `172.17.0.1`，
因此仅在受保护 WS 21 需要 IPv6 时，让 Nginx 接入已有受管 IPv6 辅助网。
默认网络、业务核心范围、端口和 capability 不扩大，网络清理按当前 Compose 判断。
旧双栈 Compose 需标准配置/升级事务更新；旧 state/同名资源不自动迁移，
必须先停止原拥有者并在原生主机核对，不能通过删除 state 绕过归属门禁。

新增 `docker-fail2ban-ownership` 并入普通合同，focused 并行 ownership/phase4；
`docker-fail2ban-source-real` 仅显式运行，离线只传 xray/nginx/net，
独立 dockerd、双客户端 veth netns，不挂宿主 Socket，保持生产端口和网络。
真实 Nginx 日志首字段须为客户端，伪造 XFF/Forwarded 不改变封禁地址；
三个实际 `/.env` 404 自动触发封禁，不手工 banip。
两族分别证明 DNAT 后 DROP counter 增加、被封连接超时且日志不增加、
第二客户端和另一地址族可用、单 IP 解封恢复、健康与停止清理。
测试仅给离线容器补自身名称本地解析，保留 ignoreself 检测；
故障注入 tmpfs 显式 exec 只限真实 action 夹具，不放宽生产配置。

本地验收（2026-10-10，Linux amd64，工具与业务镜像复用）：

| 检查 | 结果 / 秒 | 证据目录 |
| --- | --- | --- |
| 最终 ownership + phase4 focused | 2/2，33.891 / 入口 34.853 | `.tmp-regression-docker-75df4ade260948c7b3958b5c0a41c139` |
| 最终真实 action 双栈 | 47.859 / 入口 48.776 | `.tmp-regression-docker-b9cb76fa8fa44dcc946b1b587278bf2c` |
| 严格真实来源三项 | 25.903 / 入口 26.856 | `.tmp-regression-docker-ce82122f2e8142709570fa0b8475ee08` |
| 网络清理/installed validate 补验 phase4 | 33.138 / 入口 34.082 | `.tmp-regression-docker-9ea5ea3f19124b38b55159c50a0800c2` |
| 完整 Docker 合同，Jobs 6 | 37/37，239.963 / 入口 240.835 | `.tmp-regression-docker-58c461e7628c40cf94847a77f46f8a61` |
| dispatcher 注册/集合合同 | 0.484 / 入口 1.530 | `.tmp-regression-docker-b3e7d7fd295442ccb9d0d53332f9e665` |

各实测仅证明对应快照与路径，不把早期快照声称为最终同输入全套。
完整合同未命中缓存，排队 383 ms，最终 10 个生产/测试/入口文件与完整归档逐文件一致。
完整源码归档 SHA256 `70228153EA531872BAD51A8DA261F394A3605AF4E50E85DB09CDAAC41079B8F8`，
内容摘要 `365D3DFB729E87C4D1F3BDADF93F9B41C6D76375D298F7E307366ADC526ED087`。
8 个 Shell 的 Linux 语法/ShellCheck error、4 段生产 inline Python 编译、
真实来源 Python AST、PowerShell AST 与 diff 检查通过；独立复审无未决 P1/P2。
初期 fixture capability 表示、自名 DNS 阻塞、noexec 故障注入和静态站点配置
均按实际错误修复，失败日志保留；最终代码验证结束后仅更新本节及说明文档。
不扩大三槽预算、不重建镜像；清理本轮源码归档/清单和检查脚本，日志/result/缓存保留。
主任务已核对并清理本轮 23 个归档/清单/检查脚本，不动用户既有临时文件；
实现与测试 `8d0fc2f0 fix(docker): bind Fail2ban actions to verified owners` 为本地 SSH 签名，
签名 `G`，未推送或发布。
特权并发修改非原子、SIGKILL 无标记空链需人工核对；大量 bans 的逐条审计删除
尚未量测优化。真实宿主、systemd/重启/卸载、公网和原生 arm64 未验收，
Fail2ban 完整管理、5C 及总目标继续 active。

#### 5C.5 Fail2ban 受管站点扫描安全停用

服务维护的 Fail2ban 子菜单新增停用，CLI 为
`fail2ban disable [--preview | --confirm PADM-DOCKER-EDIT]`，
内部复用 `edit --fail2ban-off` 的私有草稿、既有规格迁移、字段差异门禁和配置事务。
只移除 Fail2ban integration，保留其它宿主集成、核心、账号和持久 SQLite。
未启用返回状态错误；本项不新增启用或参数编辑入口。

停用门禁放在共享候选安装路径，标准 configure/update 也不能通过新编排
删除孤儿容器来绕过。旧规格、deployment 和 Compose 需保持集成一致，
即使三者均未启用，也核对运行时无该项目的 Fail2ban 孤儿容器；查询失败
或发现容器均拒绝；已知 owner state 或断链符号链接也须不存在，
不猜测拥有者或自动清理。
确认后核对唯一受管 CID、配置正文、已加载动作及 live owner。
只停止刚审计的容器，不移除退出证据；正常退出后重新核对同一 CID，
再用旧编排运行不启动 jail 的 `preflight fail2ban <oldports> unowned`，
证明 state 与旧受保护地址族的规则均无残留，才登记配置切换并安装新文件。

预览及取消不停止容器。外来规则、容器替换、异常退出、超时或清理证明失败
拒绝提交，保留旧配置、state 和容器；服务可能已停止，需要人工核对原 owner，
不能删除 state 强制继续。清理证明成功后的信号先登记可恢复事务再转交，
后续安装/启动失败沿既有快照恢复旧部署，SQLite 保留以重载未过期 bans；
不恢复旧 token/state 或复制内核规则。未完成清理证明时不强行执行通用恢复。
旧版无原始 spec 的更新保留兼容路径：仅已校验的候选 deployment 与 Compose
均明确未启用 Fail2ban 时采用 deployment 输入，之后仍核对旧状态、CID 与 state。
候选 spec 存在但损坏不能回退；缺 spec 的 Fail2ban 候选直接拒绝。

本项仅补站点扫描停用。新启用仍需逐受保护端口/地址族的当前部署来源见证，
不能用一次隔离夹具或历史日志替代；SSH 的宿主日志/INPUT 合同、
Docker 控制服务的来源日志和 jail 合同仍独立待办。
本地验收（2026-10-10，Linux amd64，复用工具与 net 镜像）：

| 检查 | 结果 / 秒 | 证据目录 |
| --- | --- | --- |
| 菜单 PTY，含停用确认/取消/EOF/信号 | 37.999 / 入口 38.976 | `.tmp-regression-docker-703a7544292e417c860b703672fecca0` |
| 真实双栈清理、拒绝残留与 SQLite 恢复 | 49.041 / 入口 49.902 | `.tmp-regression-docker-21cafa4eba514a2fae2ddc61705c10c8` |
| 最终停用事务 phase4 | 67.002 / 入口 67.963 | `.tmp-regression-docker-a320aa3ea2674bf19a799ea12d925e7d` |
| 旧版更新与拒绝合同 phase6 | 27.057 / 入口 27.988 | `.tmp-regression-docker-d90a999812e84aab9d729f89f3569d3a` |
| 路由域名工作流补验 | 88.697 / 入口 89.616 | `.tmp-regression-docker-6a19637428b54a6eb1372dd1dc4aa74a` |
| Reality 共存补验 | 61.436 / 入口 62.343 | `.tmp-regression-docker-0e7eb621bb3d45139f95acc04d35fbf9` |
| 最终完整 Docker 合同，Jobs 6 | 37/37，245.975 / 入口 246.858 | `.tmp-regression-docker-f98db2388a9040f8ae7f051e05005793` |

上述实测对应各自快照；真实双栈项只证明 owner 清理与 SQLite 恢复，
不冒充完整 CLI 的真实宿主停用验收。最终完整合同未命中缓存，排队 389 ms，
复用工具镜像，不扩大三槽预算、不重建依赖镜像。
最终 14 个代码/测试文件与完整归档逐文件一致，此后只更新文档和状态快照。
完整源码归档 SHA256 `11467CC7A8BD13EEF24EB6BC49C27E7ADD6650A2DF1CE8CB09B4F72F192E4ABF`，
内容摘要 `57B12574C163398112B57C568E34065DEC5032202DD4DACB905EA96EAC26A9F5`。
已完成的 Bash 语法/ShellCheck error 检查按改动补验，不重复稳定文件，
最后 8 个变动 Shell 的 16 项检查通过；独立限定复审无未决确定 P1/P2。
初期夹具候选/旧编排区分、规则时间戳、重写 state 的 mtime 基准与规格迁移
期望已修；共享安装路径新增只读查询的夹具同步补齐，生产门禁不放宽。
失败日志保留，不把较早或失败快照声明为最终源码的完整证明。
本轮清理 24 个源码归档/清单，共 99,172,392 字节；日志、result、镜像记录和共享缓存保留，
不动用户既有 8 个临时文件。实现和验收说明分开本地签名提交，不推送或发布。
实现 `60feabb7 fix(docker): verify Fail2ban cleanup before disabling protection`
已本地 SSH 签名提交，签名 `G`。
新启用、SSH/控制面、真实宿主/arm64/重启卸载未验收，5C 与总目标继续 active。

#### 5C.6a WS 只读现场来源见证

服务维护的 Fail2ban 菜单新增“核对 WS 真实来源”，CLI 为
`fail2ban verify-source <WS 入口 ID> <外部客户端 IPv4/IPv6>`。
这是安全新启用的必要诊断底座，不启用 jail、不修改配置或防火墙，
不保存 token 或可以复用的启用凭证，不宣称已完成新启用流程。

WS 21 的受管 Nginx 仅为 `/.well-known/padm-source/<48 hex>` 返回 204，
以 escape=json 输出真实 remote_addr、内部 server_port、Host、方法和原始 URI。
普通 combined 日志与封禁 filter 保留，不在其它协议新增挑战端点。
每次诊断新建随机 nonce，提示外部客户端使用对应 `curl -4/-6`，不跳过证书验证。
读取新挑战之后的受管容器日志，逐条核对同 nonce 的全部字段；
历史 URI、转发头及另一内部端口不能作为来源证明，任何同 nonce 错来源立即拒绝。
本机、容器、网关、特殊范围及 IPv4 映射 IPv6 拒绝；
IPv6 值规范化，族和 listener 地址族必须一致。

诊断核对完整 spec/deployment/images.env、生成 Compose 与 Nginx 正文，
唯一运行容器的镜像、标签、挂载、安全属性、日志驱动、公开端口和受管 bridge 网络。
整个采集窗口及成功输出前，CID、StartedAt、RestartCount、
按名称排序的网络 ID 和宿主地址快照保持一致。
共享内部端口的别名及 Reality 共存会造成公开端口证据歧义，因此本项明确拒绝。
日志采集窗口为 30 秒；底层 Docker 或地址查询阻塞不保证 CLI 的硬截止时间。
磁盘与 inspect 一致不证明 worker 内存中已加载的全部配置，也不抵御特权篡改。

真实夹具复用现有隔离 daemon、离线 Xray/Nginx/net 镜像及独立客户端 netns，
扩为 24444/24445 两个公开入口和 8443/8444 独立内部端口。
它实际调用生产 Witness，新 nonce 来自生产逻辑，日志由真实 Docker 读取；
只有被离线改写镜像身份的容器审计边界采用真实 inspect 夹具，不伪称完整 CLI 宿主验收。
每地址族、每端口独立见证；旧挑战重放不得提前成功，伪造 XFF/Forwarded
不改变真实来源；错端口与错来源使用独立新挑战并验证失败。
既有自动日志封禁、DNAT DROP counter、第二客户端隔离、解封和 TERM 清理继续验证。

本地验收（2026-10-10，Docker Desktop Linux amd64，复用工具镜像）：

| 检查 | 结果 / 秒 | 证据目录 |
| --- | --- | --- |
| 菜单 PTY，含取消/EOF/失败/信号 | 通过，入口 40.670 | `.tmp-regression-docker-12f0a634ae0a4d31af1f330e7ef27693` |
| dispatcher 注册/集合合同 | 通过，入口 1.354 | `.tmp-regression-docker-e4ed068e861c46fa9f61a7dab7e3111a` |
| 补验前完整 Docker 合同，Jobs 6 | 37/38，站点夹具失败，入口 241.108 | `.tmp-regression-docker-3fd6eba9f80a42b4a72673c9d0432f20` |
| 站点真实 Nginx 降权夹具（含独占 stdout 日志目标） | 通过，入口 49.530 | `.tmp-regression-docker-f3276c732abc405994c489694d5c7592` |
| 来源合同、NetworkID 漂移拒绝 | 通过，入口 2.734 | `.tmp-regression-docker-9924116745424532aa91a21f68bee5ac` |
| 真实来源双端口双栈、错误端口/来源拒绝 | 通过，入口 37.354 | `.tmp-regression-docker-64f385b36cb645938777e5a97055ba61` |

各项均使用工具镜像 `sha256:3a790074c74a19bd40e6c5fdeeebcdba5ae230548f057ca4ca1d40f49435ce55`；
真实来源使用独立 daemon、离线业务镜像和双客户端 netns，未挂宿主 Docker Socket。
来源合同另外覆盖同地址下 NetworkID 改变必须拒绝；生产 Shell、合同 Shell 及真实来源
Python AST 补验通过。此前完整合同唯一失败项是站点夹具把降权 Nginx 的 stdout
接到 root 管道，已用独占 UID 10001 日志目标修复并完成定向补验；未重复稳定的完整合同。
完整回归之后仅变动来源快照/合同/真实来源边界和站点 stdout 夹具，均有对应补验；
不把这些组合证据声称为最终快照的单次 38/38 完整回归。
最终 10 个代码/测试文件与来源合同及真实来源归档逐文件一致，此后只更新验收文档与状态。
最终归档 SHA256 `C512B43002C4BCD10EBDC718474C68AF18D00DBE8D3E69C9BFF354FF9E6D1FE5`；
静态补验及逐文件摘要分别保留在 `.tmp-source-final-static.log`、`.tmp-source-final-snapshot.log`。
限定复审发现的 NetworkID 一致性缺口已修复并复核，无未决确定 P1/P2。
清理 26 个本轮源码归档/清单，共 108,031,990 字节，并删除两个空测试目录；
日志、失败证据、result、镜像记录和共享缓存保留，不动用户既有 8 个临时文件。
实现提交为 `9c39f063 feat(docker): verify live WS client sources before protection`，
本地 SSH 签名 `G`。本阶段仍不宣称已接入新启用事务，SSH/控制面、真实宿主、
arm64、重启卸载及完整 Fail2ban 管理继续未决。

下一步仍须把逐端口/地址族现场见证接入同一次启用事务：
先运行候选 Nginx 而不启动 jail，全部证明齐备才允许封禁；
configure/update 与直接 restore/rollback 均需覆盖，旧来源日志不能解锁新镜像。
SSH 宿主日志/INPUT、控制服务日志/jail、原生双架构及重启卸载独立未决，
5C 与总目标继续 active。

#### 5C.6b 前置：停止失败时拒绝继续恢复

核对新启用调用链时发现共享恢复路径吞掉 Compose `down` 错误后仍替换配置。
非 Reality 分支现在停止失败立即返回，保留切换标记及备份，停止错误输出不再隐藏；
不会继续删除/复制配置、切换 bundle 或启动服务。Reality 分支已有同样的失败门禁。
控制恢复准备和最新流量合并仍在停止之前执行，不把本项描述成完全零副作用。
当前编排缺失、损坏或无法确认停止时，自动恢复可能失败，需依据保留备份人工核对，
不能为了“恢复成功”无证据覆盖仍被在线容器使用的文件。

实现 `51872cf2 fix(docker): stop configuration restore when shutdown fails`，
本地 SSH 签名 `G`。Docker Desktop Linux amd64、Jobs 2，固定工具镜像复用：
完整规格及私密配置/备份摘要的 phase6 定向回归入口 27.128 秒通过，
证据 `.tmp-regression-docker-5ee6dc3732da4245bd0cb2fb4410e1c1`；
共享 Fail2ban 停用自动恢复/信号路径 phase4 入口 66.809 秒通过，
证据 `.tmp-regression-docker-9da811ec7d98408db7d5cf94abfb9721`。
两个最终代码/测试文件与这两次快照逐文件一致，Shell 语法/ShellCheck error
和限定复审通过，不重复完整合同；清理本轮 6 个源码归档/清单，共 24,953,578 字节，
日志、result 和 `.tmp-restore-stop-static.log` 保留。
本项不开放 Fail2ban 新启用，不解决 configure/update/历史回滚缺现场来源见证的问题；
5C.6b 启用事务门禁、SSH/控制面和原生宿主验收继续待办。

#### 5C.6b WS 同事务来源门禁与独立 jail 启动

configure、update、up/restart、rollback、共享 restore 与 TLS reload 已接入同一启用门禁。
本次预期外部 IPv4/IPv6 输入仅在调用栈中共享，失败恢复复用输入但重新生成挑战；
非交互入口使用 `PADM_DOCKER_FAIL2BAN_SOURCE_IPV4/IPV6`，不读取成功票据或历史日志。
配置确认后才收集输入，取消、EOF、缺族或非法地址在停止旧 jail 之前拒绝。
菜单来源输入动作共用前台进程组，避免后台 read 被 SIGTTIN 停止。

先审计旧 owner、精确停止 CID、核对正常退出与两族规则/state 清理，再移除旧容器。
候选长期服务先启动，不启动 jail、acme 或一次性 net-check。
逐保护端口及其全部地址族调用生产 Witness；全部挑战完成后统一复核最初的每份
容器/网络快照、规格摘要、生成配置和无 owner/state 前置，再以 `--no-deps` 单独启动 jail。
最后审计 jail 容器与健康；任一失败不保存可复用证明，保留备份或恢复标记。
核心独立 `--no-deps` 维护不重启 Nginx，不借未知 Compose 参数绕过门禁。

`net-fail2ban` 使用 `restart: no`，daemon 重启不自动复用旧来源证明。
旧 `unless-stopped` 仅在 owner 审计中兼容；普通启动/reload 要求先通过标准更新规范化。
已验证旧备份恢复时只重生成恢复后的 Compose，备份原文不改，并重新执行来源挑战。
首启只创建缺失的 Nginx access.log，不截断既有证据。
Fail2ban 保护的 Nginx 拒绝 standalone HTTP-01 停启，使用 webroot；
TLS reload 和恢复同样需要当前来源响应，未配置输入的无人值守轮换拒绝提交。

集成补修保留 Reality 的原规格前置门禁和错误消息。
损坏当前规格只在显式 restore 模式、当前 deployment/Compose 均明确 disabled、
无 jail CID/state 且路径安全时允许从合法备份恢复；enabled、未知元数据或查询失败拒绝。
同次恢复已完成 owner 门禁后直接停止当前编排，停止失败仍不覆盖配置或切换 bundle。
旧模拟夹具补齐明确 disabled 状态、精确 owner 查询及恢复 down 执行边界；
保留健康失败、信号、权限、订阅 token 和最新流量恢复断言，不放宽生产检查。

本地验收（2026-10-10，Docker Desktop Linux amd64，复用工具镜像）：

| 检查 | 结果 / 入口秒数 | 证据目录 |
| --- | --- | --- |
| 来源与启用批次合同 | 通过，4.179 | `.tmp-regression-docker-e2b291047e0143c79959810981efcaee` |
| 真实双端口双栈启用、封禁/解封/DROP counter | 通过，63.928 | `.tmp-regression-docker-e5d2c1116ec348919e2eb32f2cd30ebd` |
| Reality 损坏规格恢复与拒绝合同 | 通过，75.186 | `.tmp-regression-docker-3543a3179860485db1c21b6eccd4776b` |
| 权限恢复与 owner 查询失败 | 通过，2.578 | `.tmp-regression-docker-125e0ea57cf84d6296e13e2cf3f678fd` |
| 菜单 PTY 与前台来源输入 | 通过，41.335 | `.tmp-regression-docker-ef4d6123803945028946f51c07790a6f` |
| 完整 Docker 合同，Jobs 6 | 32/38，274.720 | `.tmp-regression-docker-0c67ebc14e2e464a8c7e39b908dcfcfa` |
| 路由核心/域名恢复补验，Jobs 2 | 两项通过，107.596 | `.tmp-regression-docker-68e916e6bed545be9f5922b6afc8afad` |
| 站点恢复及真实 Nginx 补验 | 通过，56.479 | `.tmp-regression-docker-3a5b3b75f80c4b4e8b1427972c03af2f` |
| 账号累计恢复补验 | 通过，5.049 | `.tmp-regression-docker-a5258c1f96a743ce94cef696237a775e` |
| HTTP relay 恢复补验 | 通过，11.847 | `.tmp-regression-docker-ffd7defdf58e401eb7121c2b1900fe20` |
| 端口别名与订阅恢复补验 | 通过，40.663 | `.tmp-regression-docker-2e4dc811f5c248d8b58b93743fa03aac` |

各项使用工具镜像 `sha256:3a790074c74a19bd40e6c5fdeeebcdba5ae230548f057ca4ca1d40f49435ce55`。
完整合同中的 phase4/phase6、所有权、来源、控制、菜单与其它 32 项通过；
仅六个旧 mock 夹具未覆盖恢复的 ComposeExecute，均已修复并完成上述定向补验。
该完整合同之后生产代码未变，不重复稳定全套，不把组合证据声称为最终快照单次 38/38。
首次完整合同失败记录及安装/Geo 的定向修复证据仍保留在本轮结果目录。
最终 19 个代码/测试文件与账号补验归档逐文件一致，Shell 语法、ShellCheck error、
相对 HEAD 无新增 warning 及 Python AST 通过，摘要在 `.tmp-fail2ban-start-final-static.log`。
限定复审无未决确定 P1/P2；清理本轮 49 个源码归档/清单，共 209,360,440 字节，
保留日志、result、共享缓存及用户原有 8 个临时文件，记录在 `.tmp-fail2ban-start-cleanup.log`。
实现 `ad48ef80 feat(docker): require fresh source proof for Fail2ban startup`，
本地 SSH 签名 `G`，未推送或发布。
真实来源夹具实际调用生产 Start/Witness，离线业务镜像身份适配不冒充完整可信发布 CLI。
SSH/控制面日志与独立 jail、原生宿主 systemd/重启卸载、公网及 arm64 继续未决，
Fail2ban 完整管理、5C 与总目标继续 active。

#### 5C.6c WS 站点扫描启用与参数管理

服务维护的 Fail2ban 子菜单保留现有 1–4 项，新增 5 启用、6 参数管理：

```bash
padm-docker fail2ban enable 443,8443 6 600 3600 --preview
padm-docker fail2ban enable 443,8443 6 600 3600 --confirm PADM-DOCKER-EDIT
padm-docker fail2ban settings 443,8443 8 900 7200 --confirm PADM-DOCKER-EDIT
```

四项依次为保护端口、失败阈值、检测窗口秒数、封禁秒数。
保护端口显式输入，限 1–16 个已有协议 21 直连 WS；数字边界沿既有 schema，
分别为 1–20、60–86400、60–604800。重复端口、缺值、多值、错误确认、
规格导入与其它专项混用均拒绝；重复启用不重置参数，未启用不能修改参数。
启用菜单显示 `6 / 600 / 3600` 默认值，参数修改不提供默认值。

内部复用 `edit --fail2ban-enable` / `--fail2ban-settings` 的私有草稿、规格迁移、
窄字段对照与 `dockerConfigureApply`。只新增该集成或修改四项 settings，
固定 profile、日志和防火墙边界，保留其它集成、账号及持久数据。
专项预览先执行现有 SourcePlan，带端口别名或 Reality stream 的不可证明组合提前拒绝。
预览、字段取消、EOF 或确认取消不提交，也不停止旧 jail；
缺本次来源输入在旧拥有者停止之前拒绝。
确认后的参数更新同样经过 5C.6b 的 owner 清理、逐端口/族 fresh witness、
整批快照复核和独立 jail `--no-deps` 启动；失败恢复重新挑战，不复用 nonce。
菜单两项使用前台动作组，来源 `read` 与 INT/TERM 保持有效。

本轮集中回归复用 `padm-regression:local`，未重建镜像、未安装宿主依赖，
不扩大现有三槽预算；子智能体只做限定实现与复审，不分别重复完整合同。
公共 CLI 精确转发检查、参数边界、WireGuard 集成保留、SQLite 保留、
双端口启用、参数端口子集及末项来源失败后 fresh witness 恢复均在 phase4 通过。
菜单 PTY 覆盖启用默认值、显式参数、四项输入及确认取消/EOF、后端失败、INT/TERM、
入口列表失败和前台来源输入；限定静态复审无未决确定 P1/P2。

| 检查 | 容器 / 入口秒数 | 证据 |
| --- | --- | --- |
| 最终 `docker-phase4`，Jobs 2 | 142.774 / 144.204 | `.tmp-regression-docker-c7377abe43de4da4af38607ff532585d` |
| 最终 `docker-menu`，Jobs 2 | 45.882 / 46.984 | `.tmp-regression-docker-3a8a2fda08424f50a08738420f1db94e` |
| 最终 `docker-contracts`，Jobs 6，38/38 | 332.776 / 333.670 | `.tmp-regression-docker-3a940641f9e34d69957baf4f2a273aa9` |

菜单排队 152.353 秒，独立于 46.984 秒入口运行耗时；不以队列等待冒充测试变慢。
完整合同排队 73.545 秒，最终快照单次 38/38 通过，`cache_hit: false`；
通过后没有代码或测试改动，仅记录本次结果，不重复已稳定的完整回归。
最终 9 个代码/测试/说明文件与完整合同快照逐文件一致，
SHA256 证据在 `.tmp-fail2ban-manage-snapshot-check.log`；
六个 Shell 文件语法及 ShellCheck error 通过，证据 `.tmp-fail2ban-manage-static.log`。
实现 `b08247ec feat(docker): add transactional WS Fail2ban management`，
本地 SSH 签名 `G`，本任务未推送或发布。清理本轮 17 个归档/清单/快照文件，
共 34,738,595 字节；保留日志、result、SHA256 摘要、共享缓存及用户原有 8 个临时文件，
记录在 `.tmp-fail2ban-manage-cleanup.log`。
本步未改来源验证器或封禁 action，不重复 5C.6b 的双栈实流量矩阵。
SSH/控制面日志与独立 jail、原生宿主 systemd/重启卸载、公网及 arm64 仍未验收；
Fail2ban 完整管理、5C 与总目标继续 active。

#### 5C.6d 单 WS 保护端口事务迁移

CLI 新增 `edit --fail2ban-port <listener_id> <新公开端口>`，
Fail2ban 子菜单第 20 项接入同一入口。支持范围仅已有单直接 WS 21、
单公开端口和单 Fail2ban 集成/jail，新端口必须不同；别名、Reality stream、
SSH/control 或其它宿主集成以及额外编辑组合明确拒绝。
只豁免所选入口 `public_port` 和唯一 `settings.ports` 的联动变更，
其余规格严格冻结，不改 schema、渲染器或普通导入/通用编辑拒绝门禁。

复用生产 `dockerConfigureApply`：新旧来源输入在停服前准备，
旧 owner 正常停 jail 并证明清洁后安装候选，再按新端口逐族生成 fresh nonce，
最终复核来源和运行代次才单独启动 jail。失败恢复旧端口也重新见证，
不保存或复用成功票据；账号、内部端口、证书和 SQLite 保留。
预览、取消或缺来源不切换服务，未知 owner 或清理不明保留恢复证据。

定向合同覆盖参数/互斥、支持范围、精确字段冻结、零写入预览、
来源失败/健康失败/TERM 的新旧 nonce 与恢复启动顺序；
菜单覆盖成功、取消/空/EOF、输入/后端失败与前台来源输入。
首定向生命周期 exit 0、104073 ms，菜单 62424/62482 ms；
生产入口与菜单哈希一致，仅前两轮测试基线 schema 与集成过滤修正。
独立源码复审未发现确定 P1/P2。真实首轮 00a29 在 enable 候选预检
暴露原 WS jail 缺日志组权限：候选日志属 `10001:10001`、`0750/0640`，
旧镜像默认 `0:0` 且 `cap_drop=ALL` 无法读取。修复新 WS Compose 为
显式 `0:10001`，运行审计同步；日志权限、只读挂载和 `NET_ADMIN` 保持。
只允许精确旧无 user 编排参与归属清理/迁移，正常启动要求新编排；
显式旧 user 或其它正文改写仍拒绝。原真实夹具同步生产日志权限，
不再用宽松权限遮蔽此错误。
未扩大 control/SSH 的兼容审计；旧 WS/control 共存须先由旧受管入口
停用 WS 再升级，本专项仍只支持单 WS 集成。
第二轮 19838 在普通未防护日志文件等待时超时，未进入 enable；
夹具已删该误判等待，保留正常双栈业务请求和真实 CLI enable 基线。
另外修复仅监测切换期间的缺 spec 轮询竞态，最终断言仍严格，
客户端 namespace 由 finally 精确结束，避免旧 360 秒 holder 提前过期。
生产权限修复后的生命周期定向通过，入口 117917 ms；
集中完整合同 48/48、exit 0，入口 392194 ms、Jobs 6、排队 405 ms，
证据 `.tmp-regression-docker-071251ddd93242f8bc886dc5d194b655/`。
真实 0e28 已通过启用、双栈日志封禁、SQLite 和错误来源恢复，但健康
注入探针在 Compose 重建期间把两个容器 ID 当成一个，保留 exit 1 原日志。
仅修探针逐 ID 核对：允许明确已移除的旧 ID，新容器必须唯一、运行中且
双栈发布新端口；生产归属审计和最终断言不放宽。
此前无 Found 的原因已由原生 `DNSUtils.getSelfIPs()` 短探针确认：
隔离宿主缺自身机名映射时 20.029 秒，补回环映射后 0.007 秒，
返回值均不含外部客户端。仅修离线夹具，不关闭生产 `ignoreSelf`。
最终真实 d05d 全通过，内部 248956 ms、入口 250208 ms、Jobs 2、
排队 249 ms；证据 `.tmp-regression-docker-d05db137ab9546edacd27074a8850876/`。
实际已安装 CLI 完成启用、错误来源回滚、真实暂停新 Nginx 后的健康失败恢复、
`24444 → 25444` 迁移，各次新旧端口均取得全新双栈来源证明。
真实日志触发双栈封禁、SQLite 原 inode/封禁保留、DROP 计数增加、
第二客户端可达、旧公开端口拒绝连接、旧规则和最终 down 清理全部通过。
完整合同与最终真实回归的生产输入相同；差异仅真实健康注入夹具。
后续只补说明与证据，不因该未被合同加载的夹具变更重复完整回归。
真实夹具明确使用本地发布信任和固定摘要离线拉取适配，
不证明 Cosign 发布、首次安装或公网；实际 CLI、候选、Compose、
owner/runtime/SQLite/双栈防火墙与失败恢复不替换为桩。

#### 5C.7a 控制 API 可信来源日志底座

生产 `control_api.py` 的标准输出改为固定记录：

```text
2026-10-10T01:23:45.678Z control-request status=401 source=10.231.0.2 target=10.231.0.1 port=39778
```

UTC 毫秒时间和数字状态使用标准库；来源、目标及端口仅从本次实际 socket
捕获并规范化，不使用可变的 `client_address`、受管规格或转发头作为日志来源。
拒绝非规范 IPv4、端口及不可信状态；保留旧 `control-request status=` 子串。
401 在写响应头前记录，后续断连仍保留已捕获来源，不回显路径、请求行、
账号、请求头、token、正文及异常原文。零字节 EOF、读取超时及外层断连
单独记录 `connection_closed`，不计为认证失败。

回环合同新增真实 socket 与模拟鉴权来源的区分、HTTPStatus/bool 边界、
注入与畸形请求、关闭后来源以及 zero/partial/slow 三种关闭断言。
真实双节点夹具新增伪造 Forwarded/XFF/X-Real-IP 和 URL/header 凭据标记，
要求生产日志的 source/target/port、UTC 时间、Peer 401/200 与自身健康 401
均匹配；原有同步、轮换、撤销和断网恢复断言保留。
中英文说明同步标明 stdout 日志边界，不宣称已启用控制面防护。

2026-10-10 的限定只读复审与 `git diff --check` 通过，无确定 P1/P2。
首次沙箱 Docker 管道访问被拒绝，两次提权审核超时；续接后审核成功，
以下回归均在 Linux amd64 快照执行，复用工具镜像，无宿主依赖安装：

| 检查 | 容器 / 入口秒数 | 证据 |
| --- | --- | --- |
| `docker-control-api`，Jobs 2 | 1.639 / 2.547 | `.tmp-regression-docker-c3c073aa52cf4d84aba95e6987548b17` |
| `docker-control-two-node-real`，Jobs 2 | 6.533 / 7.465 | `.tmp-regression-docker-6ed3a12f201a4878a1710f87e6c10f3a` |
| `docker-contracts`，Jobs 6，38/38 | 319.126 / 320.070 | `.tmp-regression-docker-7f8289ed1f8d4865929dbddeb675c0bd` |

三次源码摘要一致，`cache_hit: false`；完整排队 406 ms，不扩大三槽预算。
5 个实现/测试/双语说明文件逐文件匹配完整快照，摘要与固定镜像 ID 留在
`.tmp-control-source-stage-evidence.md`。真实 API 为 `10001:10001`、无能力，
来源仅有实际 Peer 与本机健康地址，伪造代理头和秘密标记未进入日志。
通过后无代码或断言改动，不重复已成功合同。
实现 `ebdbc9f9 feat(docker): log trusted control API socket sources` 为本地签名提交；
本任务未推送。清理本轮 6 个归档/清单，25,513,287 字节，保留 result/log、
SHA256 摘要、共享缓存及用户原有 8 个临时文件；未改其它任务文件。
可信持久文件、权限/轮转、fresh witness、独立 INPUT jail、事务菜单管理
以及 SSH/原生宿主验收仍未交付；5C 与总目标继续 active。

#### 5C.7b 控制 API 持久可信日志

新生成的主控编排显式传入 `--access-log /var/log/padm/control/auth.log`，
挂载受管 `logs/control`。目录固定 root:10001 / 0750，文件固定
10001:10001 / 0640、普通单链接；API 没有目录写权限，不创建或截断文件。
每条记录重新核验 root 祖先、安全打开并单次追加，完整写入、`fsync` 与关闭
完成后才输出 stdout、发送 HTTP 响应。日志或可信 socket 失效时只输出固定
诊断并退出 78，不交给 socketserver 吞错后继续服务。`--check` 只验证状态和
参数能力，不以其成功代替真实写入及健康证明。

配置、真实更新及恢复在事务入口准备日志，已有内容不变；日志不进候选、
配置备份或恢复目标。评估共用的候选创建不得给旧 stdout 部署创建生产日志，
新增断言同时覆盖生成及参数拒绝后仍无生产写入。
旧受管恢复精确保留 stdout-only 的命令与挂载，不把不认识新参数的旧 ops
镜像强行切成新格式；未知或混合编排拒绝。沿用既有编辑合同，仅兼容历史
`io.padm.release` 元数据滞后，其余字段精确核验；新升级生成当前标签。

2026-10-10 的定向、限定独审、静态检查和集成结果：

| 检查 | 容器 / 入口秒数 | 证据 |
| --- | --- | --- |
| `docker-control-api`，Jobs 2 | 1.660 / 2.576 | `.tmp-regression-docker-64ee4433b4ad49f0b86d295087a5fbf1` |
| `docker-control-two-node-real`，Jobs 2 | 6.703 / 7.609 | `.tmp-regression-docker-76048a2b0fa549e3b93875f36abd7679` |
| `docker-permissions`，Jobs 2 | 2.081 / 3.179 | `.tmp-regression-docker-5bf7d43d4b5f4e96b0119f575572b392` |
| 最终 `docker-control-state`，Jobs 2 | 25.599 / 26.586 | `.tmp-regression-docker-276287cca01246e0b94391536a9318ab` |
| `docker-control-two-deployment-real`，Jobs 2 | 235.006 / 236.773 | `.tmp-regression-docker-ad10805a72b64ee3b6bc3c4c63c64a7e` |
| `docker-contracts`，Jobs 6，38/38 | 341.384 / 342.365 | `.tmp-regression-docker-cbefdf73fc8a47838c96fad3a408f750` |

首次控制状态检查因 Shell 换行及引号错误失败，修复后通过；
兼容断言补强后只重跑受影响 selector，再集中一次完整合同。
全部复用工具镜像，`cache_hit: false`；完整排队 4982 ms，不扩大三槽预算。
最终状态、真实部署和完整合同源码摘要相同，9 个本阶段文件逐一匹配完整快照。
真 WG 验证文件与 stdout 逐字相同，运行时改坏权限后无响应、无继续写入、
API 退出 78；真实 Compose 的两个独立 daemon/netns 使用生产 CLI，健康、
接入、幂等、真实流量、断网/冲突恢复、信号回滚、凭据轮换及撤销均通过。

本地旧 ops 缺新参数；离线复用依赖层，将当前 6 个生产文件构建进测试镜像，
逐文件核验一致，不用旧源码冒充当前输入。固定 ops 为
`sha256:2b53d30542e08f535731f4975f658e2b3789b049db2ab88493920aabd3c2534d`；
只更新测试代码层，未发布镜像、未重建工具镜像。
实现 `127b20f2 feat(docker): persist trusted control API access logs` 为本地 G 签名提交。
清理本轮 16 个归档/清单共 68,399,976 字节及两个构建/核验临时目录；
保留 result/log、摘要、共享缓存和用户原有 8 个临时文件。
详细证据 `.tmp-control-persist-stage-evidence.md`。

日志轮转、严格关联随机挑战的 fresh witness、独立 INPUT jail 和事务菜单
仍未交付；普通新 401 不等于 nonce 证明，不得用历史日志或健康结果代替
现场来源证明。SSH、原生双架构/宿主 systemd/重启卸载及公网验收继续未决，
本阶段不宣称控制面防护、5C 或总目标完成。

#### 5C.7c 控制 API 严格随机挑战来源见证

新增 `control source-check` 与 `control source-probe`。主控在部署锁下生成
64 hex 随机 nonce，root:10001 / 0640 登记在 `data/control-source/challenge.json`，
最多 30 秒后失效；API 只读挂载。Peer 固定受管唯一 WireGuard /32、
目标源路由和真实源地址，不读取邀请、不发送 token、不使用代理或重定向。

只有精确 `/v1/health`、没有任何 Authorization、唯一合法 nonce header，
登记与当前主控 state、实际 socket 的 source/target/port 完全匹配时，
API 才将 401 写入独立 `logs/control/source.receipt`。普通 auth.log 格式不变，
不记录 nonce；先同步访问日志，再同步并关闭回执，最后发 HTTP。
登记、日志或回执不安全时固定诊断并退出 78，不吞错后继续服务。

主控只读新偏移后完整回执，绑定 inode、唯一 nonce、三元组及当前时限；
成功前复核配置摘要、运行容器代次、登记身份与摘要、回执和到期时间。
结束或 INT/TERM 仅删除本次未变化登记；陌生/变化登记保留并拒绝，
probe 临时目录删除失败返回 15、释放锁失败返回 12。
配置候选与恢复不复制或覆盖登记/回执，旧回执不能成为未来启用凭证。
三代 Compose（stdout-only、持久日志、随机挑战）精确兼容，
旧恢复保留原参数与挂载；来源见证只接受最新完整受管编排。

限定独审修复摘要命令与管道错误传播、登记发布信号清理及 probe 清理错误。
真实验收又发现 Docker capability 的 `CAP_` 前缀和 WireGuard 的
`${PADM_NET_ROOT}` 挂载前缀误拒，按既有模式规范化，不降低路径/权限比较；
最小合同使用生产 Compose 派生 inspect，正常通过，额外能力、错误挂载及摘要失败拒绝。

| 检查，Jobs 2（合同为 6） | 容器 / 入口秒数 | 证据 |
| --- | --- | --- |
| `docker-control-api` | 1.909 / 2.853 | `.tmp-regression-docker-3bf0fa46978644c19f1def470015d2eb` |
| `docker-control-client` | 20.485 / 22.111 | `.tmp-regression-docker-a04456741c0a451a9e7ad65993b50f94` |
| `docker-control-two-node-real` | 6.992 / 7.878 | `.tmp-regression-docker-4a32a7f6a9094cfb80468fdb572a93ba` |
| `docker-permissions` | 2.609 / 3.604 | `.tmp-regression-docker-ddf00f82a16043ac8971707ea8692adc` |
| `docker-control-state` | 26.213 / 27.187 | `.tmp-regression-docker-3c4df50ad4654d56b29cd72a38d0a45c` |
| 最终 `docker-control-cli` | 9.798 / 11.339 | `.tmp-regression-docker-ba2e85de88bd4833969ab1a5e8da4245` |
| `docker-control-two-deployment-real` | 257.354 / 258.568 | `.tmp-regression-docker-79560cf8930742dd887da94c0b9883b9` |
| 最终 `docker-contracts`，44/44 | 303.394 / 304.342 | `.tmp-regression-docker-e4693adbbb904efd8728064350d59303` |

全部 Linux amd64、`cache_hit: false`，复用工具镜像，不扩大三槽预算；
最终完整排队 390 ms，44 分片按实际调度日志计数，不沿用续接时的 40 项预估。
最终 CLI 与完整合同归档摘要相同，14 个本阶段文件逐一匹配完整快照；
成功定向及真实部署的对应文件也逐一匹配。真实两个独立 daemon/netns 使用
生产 CLI，随机挑战/登记清理、接入/幂等、实际流量、断网/冲突、
健康/INT/TERM 恢复、凭据轮换和撤销全部通过。
真实首次失败未有细分诊断，第二次确认 net-wireguard 误拒，修复后通过；
旧合同快照主动结束 exit 137 不计成功，最终完整合同实际执行通过。

本地 ops 离线复用依赖层，当前 6 文件镜像内摘要匹配，
固定 `sha256:cb43e9f122f88eca1638364c971ec60db678362429f76752abc4b9902d4d9b43`；
没有旧源码冒充当前输入。实现
`4b3647f4 feat(docker): verify control sources with fresh nonce challenges`，
本地 SSH 签名 G，未推送/发布；证据 `.tmp-control-challenge-stage-evidence.md`。
清理本轮 34 个归档/清单共 146,990,909 字节、临时核验脚本与构建目录，
保留 result/log、摘要、共享缓存及用户原有 8 个临时文件。
日志轮转、独立 INPUT action/jail、事务菜单、SSH 和原生双架构/宿主验收
仍待交付；本阶段命令不启用防护，5C 与总目标继续 active。

#### 5C.7d 控制认证日志在线手动轮转

新增 `control log-rotate [--yes]` 和控制菜单“手动轮转认证日志”，菜单同时
接入已有“验证 Peer 来源”；直接调用后端，只确认一次，取消/EOF/失败以及
INT 返回、TERM 退出由现有 PTY/信号合同覆盖。新增固定 root:10001 / 0640
普通单链接 `auth.lock`，API 只读打开；共享锁覆盖安全重开、追加、同步和关闭，
root 排他锁进行轮转。锁等待最多 10 秒，取得后重核父目录及锁 inode。

`auth.log` 达到 10 MiB 时才轮转，固定保留 `.1`、`.2` 两份历史；
不重启 API、不用 copytruncate、不更换或轮转 `source.receipt`。
私有准备目录保存新 leaf 和旧 `.2`，INT/TERM 屏蔽覆盖移名、同步、逆序恢复及
清理；失败按实际 inode 回滚，陌生文件或残留保留并拒绝接管。
四代完整受管编排精确兼容；旧恢复保留参数，不给无协作锁部署开放轮转。
活动或陌生来源登记拒绝轮转，操作前后复核代次、配置和 receipt inode/hash。
生产 helper 为 root:10001、只读根、仅 CHOWN、无网络、日志驱动 none。
CLI 后台启动并等待 terminal；非 force 移除成功或确认已不存在后才释放部署锁。
复审修复不受支持的 `docker start --sig-proxy` 参数及 inspect 被中断时提前释锁。
daemon 不可用时持锁等待恢复，不强杀根端事务。

| 检查，Jobs 2（合同为 6） | 容器 / 入口秒数 | 证据 |
| --- | --- | --- |
| `docker-control-api` | 2.334 / 3.295 | `.tmp-regression-docker-b229f9130c014e26a2193e21cce2fe27` |
| `docker-permissions` | 3.623 / 4.551 | `.tmp-regression-docker-1103646899ac4a4bb1e1719ed2ef601c` |
| `docker-control-state` | 39.096 / 40.040 | `.tmp-regression-docker-3fdf3ed7ae7a4a819fef0d04a97a0c03` |
| 最终 `docker-control-cli` | 9.746 / 10.655 | `.tmp-regression-docker-0e7fc7757d0b45ecb434195f857161de` |
| `docker-menu`（含 PTY） | 48.496 / 49.524 | `.tmp-regression-docker-3200f06b2f074ee88a64d5206d595773` |
| `docker-control-two-node-real` | 7.269 / 8.222 | `.tmp-regression-docker-44c9b81621d6452580c1a9fc25681481` |
| 最终 `docker-control-two-deployment-real` | 240.047 / 240.999 | `.tmp-regression-docker-53af9774fdc34a8e807e835964311933` |
| `docker-contracts`，44/44 | 285.346 / 288.409 | `.tmp-regression-docker-577a826204a8418097d022457c0fdabc` |

全部 Linux amd64、`cache_hit: false`，复用工具镜像，三槽预算不变；
合同排队 407 ms，入口比 7c 少 15.933 秒，不据单次结果扩大并发。
真实 WG 让 30 次 Peer 请求与轮转并行，持久日志和 stdout 逐字一致；
真实双 Compose 使用生产 CLI，锁内确证等待、helper 最小权限、归档完整、
receipt 不变、服务 CID/StartedAt 不变、续写及轮转后新 nonce 见证均通过。
首次真实失败为观察短命 helper 的 ps/inspect 竞态；只忽略已消失对象，
其它错误仍拒绝，修正后真实 selector 通过。该夹具不在合同 44 个子项内，
不重复已稳定合同；14 文件匹配合同快照，最终真实夹具及 4 个生产文件匹配
真实快照，其余成功定向相关文件也逐一核验。

ops 离线复用依赖，当前 6 文件镜像内摘要匹配，固定
`sha256:34d48510ed0d080590b72c40e55e958d02453b7fcc9858d9718171c57f95c9a1`。
实现 `6c5755f6 feat(docker): rotate control access logs safely online`，
本地 SSH 签名 G，未推送/发布；详细证据 `.tmp-control-rotation-stage-evidence.md`。
提交后摘要再次匹配；清理 22 个归档/清单共 96,418,991 字节及临时核验/构建文件，
保留 result/log、摘要、共享缓存和用户原有 8 个临时文件。
自动调度未实现，10 MiB 为手动触发阈值而非实时大小上限；SIGKILL/断电残留
仍须人工核对。独立 INPUT action/jail、事务菜单、SSH、原生宿主与双架构
验收仍待交付，5C 和总目标 active，本阶段不启用控制面防护。

#### 5C.7d1 控制认证日志每小时自动轮转检查

复用 7d 的线上轮转，新增 `control log-schedule enable|disable|status` 和
`control auto-log-rotate`，控制菜单追加状态/启用/停用。默认关闭，固定每小时
第 19 分检查 10 MiB 阈值，仍只保留两份历史；systemd 加至多 300 秒随机延迟，
cron 使用同一固定时间。登记为本机 root 私有 `data/control-log/schedule.json`，
不进入业务或配置备份，不跟随角色数据迁移。

登记和任务复用既有 maintenance schedule 恢复窗口；来源、完整 unit 模板、
root 标记、FragmentPath、DropInPaths、cron 行和权限核对后才操作。
自动入口取得同一部署锁后再读开关、受管角色与实际容器集合；竞争立即退出 `12`，
systemd 将其作为正常跳过，下轮重试。正常停服或已验证非主控不写日志；
半套、停止、陌生容器及坏登记仍拒绝。writer 清理保持原 7d 门禁，
新任务不使用强杀超时，daemon 不可用时继续持锁等待恢复。

up/restart 重新同步任务，down/uninstall 移除任务并保留登记；配置提交、
更新、恢复同步本机开关。启用期间目标 bundle 必须声明调度能力，旧包在切换前拒绝。
定向 `docker-control-log-schedule`（含 lifecycle）退出 0，入口 4801 ms；
`.tmp-regression-docker-83368bc0a512498cadba4f828f17bf38/`。
菜单 PTY 退出 0，入口 56992 ms；
`.tmp-regression-docker-073562ccfb264295b160686e4b3e02be/`。
真实隔离 amd64 双部署自动入口完成协作锁等待、锁竞争退出 12、无丢字节轮转、
receipt 与服务代次不变、停用后零写入，入口 394100 ms；
`.tmp-regression-docker-89333dafa7844e50ba38536d7c6de874/`。
该真实快照早于最后孤立状态门禁；差异仅为无部署四件套时的拒绝分支及其合同，
已由最新定向覆盖，不影响真实主控分支。
最终完整 Docker 合同 48/48，Jobs 6，入口 321053 ms，排队 366 ms，退出 0；
`.tmp-regression-docker-2cbdaad253ed4f43b24df7a600fa7cac/`。
318 个冻结快照输入逐文件哈希一致；证据在 `.tmp-control-log-close/`。
新增 `docker-control-log-cron-real` 窄验收，复用真实双部署、私有 daemon/cron、
WireGuard 和生产 CLI；先写入超过 10 MiB 的日志再启用调度，不修改墙钟、
`19 * * * *` 或每分钟流量任务，也不手动调用 auto 入口代替定时触发。
2026-10-12 12:19（UTC+08:00）真实 cron 在 `:19:01` 自主启动，退出 `0`，
无丢字节归档、原日志 inode 转移、权限、receipt、协作锁完整属性、API 续写、
服务 ID/StartedAt 保持和 helper 清理均通过；停用后的 auto 入口保持零写入。
环境清理后才输出成功证明，入口 `2039357 ms`，未命中缓存；
`.tmp-regression-docker-6136fb698573409d908bd532cbd3d355/`。
首轮若实际退出 `12`，只允许下一小时原始边界重试一次；本次首轮成功。
回归入口同时修复 Windows tar 报警却返回成功时的漏文件风险：通过二进制 stdout
生成源码归档，再严格核对数量和区分大小写的文件集合，新快照 `339/339`。
原成功 cron 快照漏掉不在其调用路径的 IPv6 DNS 真实测试文件，关键调用文件已核对；
不以该快照证明其它 selector。分发合同通过，集成完整合同 `49/49`、
Jobs `6`、`416875 ms`、exit `0` 且未命中缓存。
入口自检覆盖真实源码/二进制、精确 selector 能力、三槽队列、废弃容器回收、
成功结果复用和失败/中断拒绝复用；优化后完整自检退出 `0`。
工具变化测试继承已验证镜像，用本次独立标签实际构建并核对不同镜像 ID，
不再重装整套依赖，结束后清理独立标签，共享工具镜像保持。
证据 `.tmp-control-log-cron-close/acceptance.md`。
未新增阈值/频率选项或扩大完整支持状态。systemd 实际定时触发、
原生宿主、arm64、整机重启和 SIGKILL/断电仍未验。

#### 5C.7e 控制面独立 INPUT action/jail 后端

实现 `73499313 feat(docker): add isolated control INPUT Fail2ban backend`，
本地 SSH 签名 G，未推送。复用既有所有权审计，只参数化范围、state、父链和 hook；
原 WS schema 2 字节、双栈 DOCKER-USER 行为保持。控制范围固定独立 schema 1、
随机 token、`padm-f2bc-*` 链与 comment、`padm-control` jail 和
`control-fail2ban.sqlite3`，不读写 WS 数据库或状态。
只接受实际 WireGuard 类型的 `wg-padm` 和规范 RFC 1918 IPv4，
INPUT hook 精确为单目标 /32、TCP、单目的端口和 `conntrack NEW`。
新增严格资源漂移、双范围故障不串清理、启动失败/删除失败保留恢复 state 合同。

生成器拒绝角色、接口、地址、端口、类型和数值边界污染，认证 filter 只接受该目标端口
的普通 401，200、连接关闭、其它目标/端口及来源回执不匹配。
`actionstart_on_demand = false` 确保 jail 启动即建立可健康检查的 hook；
Fail2ban 原生配置解析和真实 retry 封禁通过，不用手工 action 掩盖启动行为。
防护进程为 `0:10001`、drop ALL、仅 `NET_ADMIN`、只读根和只读日志，
可信日志祖先、单链接、uid/gid/mode、无符号链接及打开前后 inode 均核对。

本地验收（2026-10-10，Docker Desktop Linux amd64）：

| 检查，Jobs 2（合同为 6） | 容器 / 入口秒数 | 证据 |
| --- | --- | --- |
| 修正初始化后的 ownership/生成器 | 25.770 / 26.730 | `.tmp-regression-docker-cb9b0e531dc94830b5f5f64b3f3037a0` |
| 原 WS IPv4/双栈真实 action | 50.308 / 51.400 | `.tmp-regression-docker-27d4cab3f1a74bc0bff047b3915b22df` |
| 独立控制面真实 INPUT/jail | 21.170 / 22.059 | `.tmp-regression-docker-d1edb8256646401880ab2cc6a4393dca` |
| 最终完整 Docker 合同，44/44 | 312.508 / 313.516 | `.tmp-regression-docker-8a3c352f375a4c999ea68eb9822c3e64` |

各项实际执行、`cache_hit: false`，完整排队 412 ms；三槽预算不变，工具内容未变。
真实控制验收与完整合同归档 SHA256 同为
`7FA1926A1F63BF62BC327E67320DA9B81B4EA59F4BBC089C830A8FF9F72C9EB1`；
工具镜像固定 `sha256:dbdfde081d3763df53ff13e5a79a9f2fbd7a98ef8660fed9ee02681a96abc2de`，
与先前镜像工具内容摘要一致，入口自检重建缓存后复用，不为任务重复构建依赖。
10 个交付文件提交后逐项匹配冻结快照；Linux Shell/ShellCheck error、嵌入 Python
AST、PowerShell AST、精确/近似 selector 权限及入口/队列自检、独立复审通过。

真实夹具使用独立 netns、WireGuard Peer 与嵌套 daemon，不挂宿主 Socket：
生产 API 的真实 401 达到 maxretry 后命中 INPUT DROP counter，未进入 API 日志；
异端口仍使用生产 API，异目标仅为标准库 HTTP 负例，明确不作为启用授权。
独立 SQLite 停启恢复、token 变化、解封、TERM 清理、owner 替换拒绝与 WS 原资源保持通过。
首轮新合同漏安装入口初始化、真实夹具试图在 WG 第二地址启动单主地址 API 均失败，
分别修正 source 初始化和异目标负例布局后补验，不改生产单地址校验，不把失败计作通过。

本阶段仅交付独立后端与真实封禁底座，尚未接入配置事务、Compose 或菜单，
不能手工启动绕过门禁。7f 继续 fresh nonce 同事务启用/停用/维护；
普通 401、旧日志、历史回执不作授权。SSH、原生宿主 systemd/重启卸载、
公网及 arm64 仍未验收，5C 与总目标 active。详细证据 `.tmp-control-fail2ban-stage-evidence.md`。
清理本轮 12 个源码归档/清单及入口自检目录共 314,848,320 字节和两个临时检查脚本；
保留日志、result、摘要、自检结果、共享缓存及用户原有 8 个临时文件。

#### 5C.7f 控制防护同锁事务与菜单管理

实现 `9f48cfee feat(docker): manage control Fail2ban with fresh source challenges`，
本地 SSH 签名 G，未推送。新增独立 `fail2ban-control` 规格、Compose profile
和 bundle 能力门禁；设置仅保存 retry/find-time/ban-time，目标和端口从
主控 `control.listen` 派生，要求受管 WireGuard，不要求 Peer API 授权启用。
菜单及 `fail2ban control` 提供状态、IPv4 解封、启用、参数修改和停用；
预览、取消和 EOF 不启动 jail，命令帮助及中英文说明同步。

配置、更新、回滚、普通启动/重启和恢复共用同父部署锁：
先审计并正常停止两个范围的旧 jail、证明各自资源为空，再启普通来源服务。
WS 按各保护入口和地址族证明，控制最后取得本次 fresh nonce；
双方配置和清洁检查完成后，最终复核全部 WS 代次、规格摘要、
控制登记/回执/来源代次及期限，再一次 `--no-deps` 启 jail 并审计运行归属。
两个 jail 不进入普通服务启动列表，禁止自动重启及来源服务的 no-deps 快捷绕过。
内部见证不取得或释放父锁；callback TERM 只清理本次登记。
恢复必须重新挑战，失败保留备份和版本计划；两个运行数据库不被配置恢复覆盖。

独审及真实运行修复三处：停服清洁证明原先误要求尚未启动的 WireGuard，
现仅读本范围 state/INPUT 空资源，完整 WG 检查仍在来源就绪后；
恢复静默启动吞掉挑战输出，现内部挑战/证明走 stderr，公开 `source-check`
stdout 约定不变；双方最终清洁期间的 WS 代次漂移现被最后复核拒绝。
相邻合同夹具只接受精确的两个范围空资源查询，不放宽生产 owner 门禁。

2026-10-10，Docker Desktop Linux amd64，定向 Jobs 2、完整合同 Jobs 6：

| 最终检查 | 入口秒数 | 证据 |
| --- | --- | --- |
| 生命周期及最后清洁期间漂移拒绝 | 80.580 | `.tmp-regression-docker-aa4c6d9e87554ce884e111c39d49a3b5` |
| 同锁 CLI、callback TERM | 11.702 | `.tmp-regression-docker-b49c94ef22ea4aaf97c4297246f3ec5c` |
| 真实双部署事务 | 390.780 | `.tmp-regression-docker-c46625548c1947c4b92f78deac503943` |
| 路由 / 站点 / REALITY 夹具修正 | 44.118 / 57.800 / 77.182 | `.tmp-control-fail2ban-7f-evidence.md` |
| 完整 Docker 合同，44/44 | 295.474 | `.tmp-regression-docker-77ea509ea88f4d73a59c42d4e1d4676a` |

全部实际执行、`cache_hit: false`，工具镜像复用
`sha256:dbdfde081d3763df53ff13e5a79a9f2fbd7a98ef8660fed9ee02681a96abc2de`；
完整排队 396 ms，三槽预算不变。没有新增依赖、重建工具镜像或扩大并发。
31 个阶段文件逐项匹配最终完整快照；真实归档中的生产文件也逐项匹配。
ops `sha256:34d48510ed0d080590b72c40e55e958d02453b7fcc9858d9718171c57f95c9a1`、
net `sha256:7aabb6e5e336161497e8f47e643771d5c914a6a7d12d4536465756c942ba964c`，
镜像内 7 个生产文件 SHA256 均与当前源码一致，net 仅更新本地测试代码层。
生产 Shell/Sh 语法、ShellCheck error、Python AST、JSON 及限定独审通过；
附加测试 ShellCheck 保留 `control-state.sh` 既有 SC2218/SC2199 诊断。

真实夹具复用两个独立 daemon/netns、生产 API、WireGuard Peer 和已安装管理链，
完成启用、真实 401 封禁、INPUT DROP counter、状态、解封、错端口拒绝、
新 nonce 恢复及停用，WS 资源和受控节点规格保持。
播种发布输入无正式签名，夹具仅适配当前 release/images 读取并核一致性；
该证据不代替真实签名发布验收。前两次真实夹具发布输入及输出计数失败、
首轮完整合同夹具失败后主动退出 137 均保留日志，不计成功。

清理 40 个归档/清单和构建目录共 178,819,095 字节，提取容器及核验目录已清理；
保留 20 份回归 result/log、摘要、共享缓存及其它任务文件。
详细证据 `.tmp-control-fail2ban-7f-evidence.md`。SSH、自动轮转调度、
原生宿主 systemd/重启卸载、公网及 arm64 仍未验收；
受管锁不保证抵御外部特权 daemon 并发，5C 和总目标继续 active。

#### 5C.8a SSH 宿主只读预检

实现 `a5f9c17b feat(docker): add read-only SSH host preflight`，本地 SSH 签名 G。
Fail2ban 菜单第 12 项与 `fail2ban ssh preflight [--json]` 沿用 Linux/root、
本机 rootful Docker 环境门禁，不要求已安装部署，也不取得部署锁。
从默认 `sshd -T` 提取有效去重端口，与 `ss -H -ltnp` 的精确 sshd/PID
监听集合一致才继续；同端口外来/混合 owner、漏端口及额外端口拒绝。
两个解析管道局部启用 `pipefail`，真实 CLI 未开启该选项时也不会吞掉错误。

只报告本次 boot 的一条 sshd journal 或固定 auth.log/secure 候选；
文件必须 root 所有、普通可读、路径无软链接且不可被组/其他用户写入。
认证消息、账号、来源 IP 和原始 stderr 不进入输出。JSON 明确
`scope=host-preflight-only` 与 `source_verified/runtime_configuration_verified/jail_ready=false`；
文本只说明本次预检不启用 SSH 防护，不推断宿主已有防护状态。
默认配置不证明运行实例的 `-f/-p/-o`、socket activation、绑定地址/地址族；
日志候选不作为 fresh 来源授权。其余 ssh action 先 usage 拒绝。
没有新增 SSH schema、jail、规则、日志挂载或凭证，也不升级完整支持状态。

2026-10-10，Docker Desktop Linux amd64，工具镜像复用
`sha256:dbdfde081d3763df53ff13e5a79a9f2fbd7a98ef8660fed9ee02681a96abc2de`：

| 最终检查 | 入口秒数 | 证据 |
| --- | --- | --- |
| SSH 正反例及空事务 CLI | 1.379 | `.tmp-regression-docker-6339bf67f8844d1c94269b95489b24e9` |
| 菜单 PTY 成功/失败后返回 | 52.746 | `.tmp-regression-docker-e0bcb655a5d348469dfaee6699d85e5e` |
| 注册/完整集合/CI 分片合同 | 1.403 | `.tmp-regression-docker-47650ee788df43a2935c627cc3f2a447` |
| 完整 Docker 合同，45/45 | 280.448 | `.tmp-regression-docker-615d4ec957d54b6b98c64f18d154252c` |
| 真实 OpenSSH/ss 格式、语法及 ShellCheck error | 通过 | `.tmp-ssh-preflight-8a/real.log` |

全部回归实际执行、`cache_hit=false`；完整排队 360 ms，三槽预算和 Jobs 6 保持。
10 个交付文件 SHA256 与最终完整快照逐一匹配，独立只读复审通过。
真实格式检查仅在临时容器从 Debian 官方源补 OpenSSH 10.0p1，
生产 `sshd -T` 与真实双栈 TCP listener 解析通过，环境门禁使用桩；
这不是宿主 SSH/systemd、真实失败来源或封禁验收。首次安装因未初始化容器
TMPDIR 失败，修正目录后通过，原始日志保留。只修改容器，无宿主工具安装。
定向/完整共享依赖镜像，没有重建工具镜像或重复全套原生回归。
详细证据 `.tmp-ssh-preflight-8a/evidence.md`；未推送或发布。
清理本轮 5 套源码归档/清单及一次性脚本，保留结果/日志/摘要，其它任务文件未动。
fresh SSH 来源、独立 INPUT owner/jail、原生宿主/arm64/重启卸载继续待办，
5C 和总目标 active。

#### 5C.8b SSH journal 与实时连接来源绑定

实现 `d0146a14 feat(docker): verify SSH sources with fresh journal and live sockets`，
本地 SSH 签名 G。新增 `fail2ban ssh verify-source <本机 IP> <端口> <外部 IP>`，
Fail2ban 菜单第 13 项直接接入；不要求已安装部署、不取得部署锁。
地址同族且为明确本机端点，拒绝本机及 Docker 内部来源、loopback、映射、
未指定、组播与无 scope 的 link-local 地址。宿主使用标准库 Python 与
`ip/ss/journalctl`，客户端单独使用 Paramiko；未增加宿主第三方 Python 包。

挑战前固定唯一 sshd listener 的 boot、PID/starttime、root UID、exe
身份/摘要、exec 映射地址、netns 和 socket inode/fd，并取得本 boot journal cursor。
仅接受游标后精确随机用户名的 `Invalid user` 记录，可信 `_TRANSPORT=syslog`、
`_UID/_PID/_EXE/_BOOT_ID` 与实时进程一致；日志 tag 与文件权限不作为 emitter 证明。
真实事件中的端口是客户端临时端口，目标地址/端口由 live accepted socket 绑定。
emitter 必须直接为同 master 的子进程且持有该 socket，进程启动 tick 不晚于
journal 单调时间；最终两次完整复核的稳定进程/socket 证据必须相等。
只读命令有时间及输出上限，游标失效/溢出、连接关闭、未核验 owner 或身份漂移拒绝。
合法 privsep 共享 socket 的逐一身份核验见 5C.8c.2a。

独立客户端核对已可信登记的 known_hosts 主机公钥后仅执行一次 `auth_none`，
保持未认证连接 25 秒；不传密码/私钥，不绕过主机密钥检查。
JSON 成功仅 `scope=ssh-source-only/source_verified=true`，
`runtime_configuration_verified/jail_ready=false`，不保存跨事务票据。
未新增 SSH schema、jail、日志挂载、INPUT action 或规则，支持矩阵保持原边界。
顺手修复只读预检漏识别 OpenSSH 10 `sshd-session` 候选，并区分文档中的
原生 SSH 防护与 Docker 只读检查。

2026-10-10，Docker Desktop Linux amd64，复用工具镜像
`sha256:dbdfde081d3763df53ff13e5a79a9f2fbd7a98ef8660fed9ee02681a96abc2de`：

| 最终检查 | 入口秒数 | 证据 |
| --- | --- | --- |
| SSH CLI、16 项来源合同、客户端合同，Jobs 2 | 1.516 | `.tmp-regression-docker-aeb793c867e348c987eb9fae88c0bfc6` |
| 菜单 PTY 成功/失败/取消，Jobs 2 | 53.606 | `.tmp-regression-docker-01ab46f43baf4d00a7d48c25dacb1f77` |
| 分发/完整集合/CI 分片，Jobs 2 | 1.383 | `.tmp-regression-docker-60c27fcd1f264ac087748f29f7ed9b0b` |
| 首配夹具补验，Jobs 2 | 50.299 | `.tmp-regression-docker-d827eaa8c4f549949643f1668db16934` |
| 系统/升级夹具补验，Jobs 2 | 66.063 | `.tmp-regression-docker-eb8f992119354e40be1b70f920eadca1` |
| 完整 Docker 合同，45/45，Jobs 6 | 287.327 | `.tmp-regression-docker-a456c3ab3a124de2a69e3f63c9cd1ddb` |
| 实际双栈/双端口 core、witness、客户端，4/4 | 通过 | `.tmp-ssh-source-8b-probe/evidence.md` |
| 12 脚本语法/ShellCheck error、4 Python AST | 通过 | 最终完整容器源码快照 |

全部回归实际执行、`cache_hit=false`；完整排队 428 ms，保持三槽预算。
首配/系统/完整归档 SHA256 相同，18 个交付文件与最终完整快照逐一匹配；
源码内容摘要 `88C901B24F7487B247BB3C9924D5C29E24073EF502E63DCAD32F202458394A67`。
首次完整因三个显式 bundle 夹具漏复制 Python helper 失败，主动停止 exit 137；
补齐 setup/release/phase6 夹具及缺模块断言后，定向再集中完整通过。
误写分发 selector 的一次 exit 2 为入口拒绝，修正名称后通过，原日志保留。
独审补 `_TRANSPORT` 与最终两次证据一致性，未删除失败合同规避问题。

真实实验仅容器内非 loopback、独立双栈 client/server netns；
Docker inventory 门禁用空清单桩，其余 `ip/ss/journal/proc` 全真，
生产仍拒绝该 bridge 客户端，不冒充原生宿主外部来源验收。
core/witness/client 四组通过、错误目的端口四组拒绝；容器内两个 helper
SHA256 与工作区一致。实际 Fail2ban 1.1.0 上游 `sshd.conf` 对 OpenSSH 10
前缀为 0/4，Alpine 实际 sshd jail 的 `alpine-sshd` 为 4/4；
后续 SSH jail 必须明确过滤器兼容，不直接沿用上游默认值宣称可用。
详细证据 `.tmp-ssh-source-8b-integration/evidence.md` 与实验报告。
本轮三个实验容器和内部网络已清理，依赖镜像保留；
清理本轮回归归档/清单及核验副本，保留结果、日志、摘要和他人临时文件。
未推送或发布；独立 INPUT owner/jail、原生宿主/arm64/systemd/重启卸载
仍待验收，5C 和总目标 active。

#### 5C.8c.1 SSH 独立 INPUT 所有权后端

实现 `c60e77d8 feat(docker): add isolated SSH INPUT ownership backend`，
本地 SSH 签名 G；真实 control 夹具诊断独立提交 `4f981767`，签名 G。
SSH 内部 preflight/health/clean/action 复用既有 owner、随机链、sentinel
与精确清理机制，使用独立 schema 1 `fail2ban-ssh.state`、
`padm-f2bs-*` 链和 token comment；只接受规范单目标地址、单端口与单地址族。
每次写入前复核 state/kernel，SSH 审计扫描末尾再次复核 owner，发现替换拒绝。
health 仅证明后端资源，clean 仅证明停止后 state/规则为空，不负责撤销。

未开放 SSH run/menu、jail、原始 journal 挂载或跨事务来源票据。
两个 INPUT 范围仍要求链首，本阶段在两族扫描中拒绝任何 control 资源，
不宣称 SSH/control 可并存；WS 原审计不放宽，SSH/WS 共存保持原 state、
SQLite、jail tickets 和规则不变。state 地址族错配、另一族残留、外来引用、
INPUT 插队、token/rule 漂移、半失败与 owner 竞态均有拒绝和保留证据合同。

2026-10-10 至 2026-10-11，Docker Desktop Linux amd64，复用工具镜像
`sha256:dbdfde081d3763df53ff13e5a79a9f2fbd7a98ef8660fed9ee02681a96abc2de`：

| 最终检查 | 入口秒数 | 证据 |
| --- | --- | --- |
| ownership 正反例，Jobs 2 | 39.404 | `.tmp-regression-docker-22c9a617d77c4e5885d44ad7d5b9d21b` |
| 真实 WS/SSH 双族 owner/action，Jobs 2 | 55.238 | `.tmp-regression-docker-a5f56ee9546c460aad977c04b992215c` |
| 真实 control/WireGuard/封禁计数补验，Jobs 2 | 17.136 | `.tmp-regression-docker-f001408493124e4e84f31d56f170e67c` |
| 完整 Docker 合同，45/45，Jobs 6 | 332.031 | `.tmp-regression-docker-38db0609c3844ffe8e1a383478c74744` |
| 三个 Shell 语法/ShellCheck error、6 块嵌入 Python AST、新夹具 AST | 通过 | Docker 当前源码快照 |

全部实际执行、`cache_hit=false`；完整排队 382 ms，保持三槽预算。
四个交付源码与最终完整归档逐一 SHA256 匹配，源码内容摘要
`DC3C8376AC130D30896FF4BB79A275E2D09F8EDACEFC05650665ABD752AA429A`。
真实夹具复用原两个隔离 net 容器，在 WS jail 运行时验证 SSH IPv4/IPv6
内部 action 与精确清理，不冒充 SSH 认证日志、真实封禁流量或宿主验收。

首次真实 WS/SSH 失败于旧 loaded-action 审计调用漏传 `ws`，四处统一显式传参
后补验通过。control 补验两次在 jail 启动前发生 HTTP 初始化 timeout；
新增有限状态/网络诊断，以及始终核对路由 dev/prefsrc 和 API PID netns，
保持原等待与成功断言。随后两次真实回归通过，间歇超时根因仍未确认，
不将诊断补丁写成已修复生产故障。

详细证据 `.tmp-ssh-input-8c1/evidence.md`；清理本轮 18 个归档/清单文件，
共 81,886,484 bytes，
保留结果、日志、摘要、共享镜像索引与其他任务临时文件。
后续 collector 必须绑定 fresh master 与 systemd MainPID/invocation/cgroup，
核对完整唯一显式 listener，短命 child 不能靠已消失的 socket 猜测目的端口。
连续来源、jail/启停事务、INPUT 共存、原生宿主/arm64/systemd/重启卸载
仍未验收；未推送或发布，5C 与总目标 active。

#### 5C.8c.2a SSH 当次活连接的 systemd unit 来源前置

实现 `23b690d1 feat(docker): bind live SSH sources to systemd unit generations`，
本地 SSH 签名；未推送或发布。

内部 `ssh-journal.py` 复用同进程 `witness_evidence`，保留原公开来源结果，
不接受跨事务 `source_verified` JSON 作为授权。所选 service 必须 loaded/active/running，
有明确 MainPID、非零 InvocationID、规范 cgroup v2 与启动单调时间，拒绝 socket activation。
fresh master 必须等于 MainPID；前后核对 unit 属性、主进程和完整两族 TCP listener。
当前 cgroup 子树有遍历/进程上限，成员必须稳定且属于同 netns；
只接受唯一显式 listener，拒绝 wildcard、额外 master/listener 与不可读 owner。

当次挑战记录要求可信 `_SYSTEMD_UNIT/_SYSTEMD_INVOCATION_ID/_SYSTEMD_CGROUP`、
boot、root emitter、exe 与新游标/单调时间逐项一致；末尾再次核对 live socket，
完整进程代次及 emitter cgroup。结果仅 `scope=ssh-unit-source-only`，
`source_verified/unit_verified=true`、`runtime_configuration_verified/jail_ready=false`。
该模块没有公开菜单/CLI、日志挂载、collector、jail 或事务写入；
unit 字段不能把已退出 child 的历史日志直接归因到目标端口。

真实 privileged systemd 原型暴露原 8b 对合法 privsep shared socket 的误拒：
同一唯一 ESTAB/inode 由 root `sshd-session` 与专用低权 `sshd-auth` child 持有。
修复保留唯一 tuple 和 root emitter，最多 4 个唯一 PID owner，
逐一核对专用非 root `sshd` UID 四值、安全 canonical exe、直接父子关系、
boot/netns、启动 tick、同 inode/fd 及两次完整身份。owner 排序避免 `ss` 输出次序误报，
额外 child 快照纳入 source 两次与 unit 末尾比较，PID/fd 未变但代次漂移仍拒绝。
只增加本次实证的 `/usr/lib/openssh/sshd-auth` 与既有 `/usr/sbin/sshd` 路径，
没有泛化其它发行版或远程 NSS；专用账号仍沿用 `pwd.getpwnam`。

回归复用既有 `docker-ssh-preflight` selector，无新分片或重复全套；
完整合同将较慢 ownership 提前调度，保持 45 项集合、18 分片及 Jobs 6。
8c.1 实测单项耗时模拟由 331.065 降至 324.853 秒，仅为调度预测，
不将它写成实际性能提升。

2026-10-11，Docker Desktop Linux amd64，复用工具镜像
`sha256:dbdfde081d3763df53ff13e5a79a9f2fbd7a98ef8660fed9ee02681a96abc2de`：

| 最终检查 | 入口秒数 | 证据 |
| --- | --- | --- |
| SSH source/unit/preflight/client 定向，Jobs 2 | 1.600 | `.tmp-regression-docker-bfbd3bacc6e2463798ece5a31c172b92` |
| 回归分发合同，Jobs 2 | 1.836 | `.tmp-regression-docker-7b1add768ac44b389ff496edeb87a937` |
| 完整 Docker 合同，45/45，Jobs 6 | 338.768 | `.tmp-regression-docker-6f6f53a434fe4a79acd58f23f1a3fa7a` |
| 双栈 systemd unit 正例，客户端各保持 25 秒 | 通过 | `.tmp-ssh-unit-probe-8c2/positive-results/summary.json` |

三项 Docker 回归均实际执行，`cache_hit=false`；完整合同排队 22.569 秒，
占用 2 个槽位，未扩展三槽预算。完整快照中的 10 个阶段文件与工作区逐一
SHA256 匹配，四份 Python 文件和两份 Shell 回归入口已在容器内通过 AST、
语法及 ShellCheck error 级别检查。完整合同仍包含 45 项，SSH 定向为
source 18、unit 9、客户端合同及既有预检。

双栈正例在真实 privileged systemd 原型中看到 root `sshd-session` 与 UID 996
`sshd-auth` 共享同一 ESTAB inode；IPv4 `172.30.8.3 -> 172.30.8.2`、IPv6
`fd08:cc:8c2::3 -> fd08:cc:8c2::2` 均返回
`scope=ssh-unit-source-only`、`source_verified=true`、`unit_verified=true`，
`runtime_configuration_verified=false`、`jail_ready=false`。错误 unit 和同 unit
第二 master/额外端口原型仍 4/4 拒绝；旧误拒日志、现场进程和完整 journal 均保留。
测试 units、veth、client 和 probe 容器已清理，仅保留依赖镜像与 `.tmp-*` 证据。
清理本轮 6 套回归源码归档/清单及 2 份重复模块副本，共 14 文件、
54,915,921 bytes，保留结果、日志、摘要与其它任务文件。
本阶段不启用 collector、封禁 action、jail 或菜单/CLI 新入口；原生宿主、
公网、arm64、重启卸载和连续短连接仍未验收。

#### 5C.8c.2b SSH NSS 查询期限与生命周期证据

本地签名提交 `9176eec2 fix(docker): bound SSH privsep NSS lookups`，
`2217ce7e perf(regression): prioritize measured Docker contract workloads`，签名 `G`；
未推送或发布，5C 与总目标继续 active。

shared socket 的专用 UID 原来在父进程同步调用 NSS，远程 NSS 失联时可绕过既有
总期限。现在通过固定 Python `-I` 子进程调用标准库 `pwd.getpwnam("sshd")`，
复用现有 `run_command` 的每次 3 秒上限和总 deadline，输出最多 32 字节；
专用账号名必须精确匹配，UID 只接受规范十进制 `1..4294967294`。
两次 UID 查询均使用原 deadline 并拒绝漂移，root-only 连接不查询 NSS；
owner、exe、父链、netns、socket 和完整代次核验保留。
真实 subprocess 检查覆盖非零退出和已启动后的期限耗尽，并确认 kill/wait 回收、
stdout 关闭；不新增运行依赖或放宽专用账号来源。

完整合同按 8c.2a 的实测单项耗时优先调度长任务，集合与断言不变。
原 45 项、Jobs 6 的独立 FIFO 模拟由 337690 降至 326562 ms，仅为预测。
本轮 45/45 实测入口 302.946 秒；之后其它任务合入 `520a4309`，
phase3 拆成独立 edit/entries，完整变为 46 叶，仍为 18 个 CI 分片。
保留该提交的快速子集和状态隔离，独审确认当前 46 项唯一、集合一致、
分发预期与生产同序；源码变化后重新集中验收，旧 45 项结果不替代新输入。

2026-10-11，Docker Desktop Linux amd64，复用工具镜像
`sha256:dbdfde081d3763df53ff13e5a79a9f2fbd7a98ef8660fed9ee02681a96abc2de`：

| 最终检查 | 入口秒数 | 证据 |
| --- | --- | --- |
| SSH source 20/unit 9/preflight/client，Jobs 2 | 1.910 | `.tmp-regression-docker-5522274aea594beebe2c857bdf3e9188` |
| 整合后分发合同，Jobs 2 | 1.457 | `.tmp-regression-docker-587d573a9f3c4ac6a8262da5edaee1a6` |
| 整合后完整 Docker 合同，46/46，Jobs 6 | 291.860 | `.tmp-regression-docker-ee31dc5f64674a4aa65709b356813b4f` |
| 真实 NSS helper 与过期 deadline | 通过 | `.tmp-ssh-nss-8c2b/result.json` |

表中三项回归均 `exit_code=0`、`cache_hit=false`；SSH 定向在 phase3 拆分前，
NSS 两文件未变，最终完整合同也再次执行 source 20/unit 9/client。
完整内部 290.912 秒、
排队 0.374 秒，仍占三槽预算中的 2 个槽位。292 个输入文件在启动后及提交前
逐一 SHA256 与工作区相同；同一完整容器内通过 Shell 语法、
ShellCheck error 和 Python AST 检查。真实 NSS helper 在既有 SSH 依赖镜像
返回 UID 996，与标准库同值；过期 deadline 拒绝，探针容器及脚本已清理。

用最终相同的 46 项单项耗时固定输入重算，旧排序预测 301774 ms、
新排序 290857 ms，预计减少 10917 ms；这是模拟，没有再运行旧排序对照。
不同轮次的宿主负载和源码变化不完全相同，实际入口下降不能全部归因排序。
旧 45 项运行的 12 个离散资源样本看到 CPU 688.54%、内存 474.1 MiB、
PIDs 53；初始阶段有采样间隔，不宣称绝对峰值或新的并发预算。

生命周期隔离原型在当前 `6.6.87.2-microsoft-standard-WSL2` 内核中
确认 pidfd 可观察已知进程退出、受控 ptrace 子树可观察 fork/exec/exit；
私有容器的 proc connector LISTEN 返回 `ECONNREFUSED 111`，
不能推断内核禁用，也未切换宿主 namespace 绕过。
单个无网络、私有 PID、无特权、零挂载 receiver 原型 5 个场景符合预期：
`SO_PASSCRED/SO_PASSPIDFD` 可取得活 sender 的同消息 pidfd；
sender 已回收时返回 `-EINVAL`，正文和控制数据截断必须拒绝。
发送后 exec 的反例保留同 PID、starttime 与有效 pidfd，当前 exe 已改变；
pidfd 不固定发送时 exe、父链或已关闭 accepted socket。
ptrace EXIT 停点也不能恢复此前用户态已关闭的 socket。
这些能力证据不授权历史日志或连续 collector，未修改宿主 SSH、全局 `/dev/log`、
权限规则或 unit namespace，未启用 jail。

详细证据 `.tmp-ssh-bounded-8c2b/evidence.md`、
`.tmp-ssh-lifecycle-8c2b/receiver-design.md` 和 `.tmp-ssh-pidfd-8c2b/evidence.md`。
原型进程、socket、收到的 FD 与容器均已清理；本轮删除 6 套成功回归的
源码归档/清单，共 12 文件、55,109,628 bytes，保留日志、结果、哈希及复用镜像。
后续需同消息进程代次、exec 与真实连接生命周期的完整证据；原生宿主、
LSM、systemd 服务切换、arm64、公网、重启卸载与完整防护仍未验收。

#### 5C.8c.2c 私有 syslog 与真实 OpenSSH 生命周期前置

2026-10-11，本阶段只运行隔离原型，未修改来源模块、菜单、collector 或 jail。
复用既有依赖镜像，不安装宿主工具，不重复已通过的完整 Docker 合同。
所有子智能体禁用内置联网搜索；需要联网时仅用 Agent Reach。

真实 libc `openlog/syslog/closelog` 在 sender 私有 mount namespace 中访问
测试 `/dev/log`，receiver 使用 `SO_PASSCRED/SO_PASSPIDFD`。活 sender 的同条
消息取得 credentials 和有效 pidfd；sender 完全回收后附件为 `-EINVAL`，
必须拒绝。全局 `/dev/log` 未被替换。

复用固定 SSH 依赖镜像
`sha256:0698b0ffcad3c265ab623b5bce0fcb9ef6cf9ed038811ba6b34162eee5d76f00`，
实际 `OpenSSH_10.0p2 Debian-7+deb13u4`、glibc 2.41、Paramiko 3.5.1；
独立无网络、私有 PID、零宿主挂载的临时容器内，新建 sshd 私有 mount namespace、
临时 host key 和回环监听 `127.0.0.1:45139`。privileged 仅用于该原型的
namespace/mount 操作；未附加现有 SSH，也未切入宿主 namespace。
关闭 root/password/keyboard-interactive 登录，客户端验证临时 host key。

真实 OpenSSH 原消息正反例耗时 1780 ms、退出码 0：

- 保持连接时，`Connection from` 和 `Invalid user` 的实际 sender 是 root
  `/usr/lib/openssh/sshd-session`，同消息 pidfd 前后存活；UID 996 的
  `/usr/lib/openssh/sshd-auth` 与它共享唯一 accepted inode/tuple。
- 关闭后立即接收的 `Connection closed … [preauth]` 捕获真实退出竞态：
  pidfd 非负且首次 poll 存活，读取 `/proc` 时进程已消失，末次 poll 为 POLLIN。
  该消息不能因为首次存活检查成功就取得来源授权。
- 另一短连接完全回收后，三条原日志正文仍排队，但 sender 的 pidfd 均为
  `-22`、`/proc` 不存在、accepted socket 消失，必须拒绝。

实际 sender 符合 root session 输出路径，但未截获内部 monitor IPC 或调用栈，
不把具体日志转发实现写成独立实证；也未观察到额外 `Failed publickey` 行。
接收时 exe/父链/accepted socket 快照仍不固定发送时 exec epoch。

另用既有回归工具镜像在非 privileged、无网络、私有 PID、零挂载容器中
验证受控普通 fork 子树：9 项连接/代次断言与 tracer 正常退出恢复通过，
内部 16.038 ms。父 fork、child 初停和 exec 停点读到同一真实 accepted
FD/inode/tuple；用户态 close 后和 EXIT 停点均无法补回该 socket。
exec 前排队消息在新 exe 停点收到同代 pidfd，仍不授权套用新 exe 身份。
未验证 tracer 崩溃/SIGKILL、未知 clone 参数、线程或既有服务接入。

最小顺序要求是 EXEC/EXIT 实际停点期间先 drain receiver 到 EAGAIN，
按旧 epoch 处理队列，再更新 exe/epoch 或终结连接记录，最后 CONT；
close 后仅允许输出已有 fork anchor 的历史连接事实，不能声称 live socket。
该顺序的受控 self-exec 原型已通过：11 项生命周期断言、9 个拒绝场景，
内部 36.819 ms，独立审查及主代理复核一致。EXEC 旧消息归 epoch 0，
排空到 EAGAIN 后才更新；EXIT 新消息归 epoch 1，排空后才终结。
close 后当前 owned TCP 为空，只保留 fork 初停的历史 tuple，
`live_socket_verified=false`。原型修复正文解码失败时漏关已交付 FD；
全部 9 个负例的接收端 FD 数未增加，非 ASCII 场景为 6 -> 6。
这里只验证同可执行文件 self-exec、自建普通 fork 和实际停止的 task，
不外推不同 exe、运行中 sender 竞态或生产 observer。
首次真实 OpenSSH ptrace 原型进一步取得 partial 证据，内部耗时 355 ms、
客户端退出码 0、18 个 wait 事件、6 条原始日志，完整结果 `passed=false`：
`/usr/sbin/sshd` 的 child 首停同时继承同一 LISTEN inode 和唯一 accepted
inode/tuple；connection child 从 sshd EXEC 到 `/usr/lib/openssh/sshd-session`，
其 child 再 EXEC 到 `/usr/lib/openssh/sshd-auth`，实际不同 exe 切换；
每个已处理 EXEC/EXIT 停点都先 drain 到真实 EAGAIN，再更新或终结 epoch。
但是 auth child 的首次 SIGSTOP 早于父进程收到 FORK event，探针把该未知停点
继续后才登记第二次 SIGSTOP，不能把该快照宣称为严格 child-first-stop。
由于多个 sender 的日志在同一 receiver 队列中，短连接 close 日志最终被
`sender_epoch_not_stopped` 拒绝，历史连接授权断言失败；不能把 5/6 partial
结果包装成 collector 可用。此轮 EXIT 快照的 accepted inode 仍由 FD 持有，
TCP 状态为 CLOSE_WAIT；`accepted_matches=[]` 仅表示不再 ESTABLISHED，
不能写成该 FD 已关闭。四条消息实际因非当前停点 sender 拒绝，
未额外注入 unknown sender，也未走到 child 正例的 held pidfd 比对。
证据保留在
`.tmp-ssh-syslog-8c2c/openssh-trace/first-attempt/`，保留四个原文件及指纹。

随后有实质差异的最小原型仅实际执行一次：9/9 通过，内部 366 ms，
16 条 trace、3 个 EXEC、3 个 EXIT、2 个真实 child anchor，独审及主代理复核一致。
auth child 首次 SIGSTOP 早于父 FORK event 的分支实际出现一次：
先保持 stopped，父 FORK event 确认后才登记并 CONT(0)，两 child 均在首次
CONT 前登记。不同 sender 消息放入总量最多 32 条的有界 pending，
冻结旧 epoch/exe/anchor 并持续持有同消息 pidfd；在 sender 自身 EXEC/EXIT
停点先 drain 到真实 EAGAIN，提交旧 epoch并关闭消息 FD，再更新/终结与 CONT。
每个实际停点均保存该顺序、双 pidfd 前后活性与末尾 task generation 复核。

真实 root session 的 `Connection from`、`Invalid user`、
`Connection closed … [preauth]` 三条原消息在 auth child 停点入队，
在 session 自身 EXIT 提交，均绑定 epoch 1 的
`/usr/lib/openssh/sshd-session`，不会套用 auth 的当前 exe。
fork 初停的唯一 accepted inode/tuple 保留；提交时
`owns_anchor_fd=true`、`established_tuple_live=false`、TCP CLOSE_WAIT，
不声称 FD 已关闭。三条 master 日志因没有 accepted anchor 拒绝。
所有待处理消息解决，tracee、未登记停点和已接收 FD 的终局清单均为空，
客户端拒认证后退出 0，私有 `/dev/log` 路由随自有树释放。
首轮失败原文件及指纹继续保留；最终证据
`.tmp-ssh-syslog-8c2c/openssh-trace/evidence.md`，没有再次重复该方案。

真实 OpenSSH fork 初停继承 LISTEN FD 的窗口在本受控实例已验证，
不能直接复用现有严格单 owner witness，也不能泛化放宽生产 owner 检查。
没有 syscall 创建参数审计时，仅限受控普通单线程 fork 假设。
本轮 cgroup 只记录，不认证宿主 unit；unknown sender 未注入，
超限/超时、异常 tracer、多线程/de-thread/共享 clone，以及跨不同 exe 的
积压旧消息场景未完成实测。未知、回收、负 pidfd、超限或无法在期限内
归属仍要求拒绝，原型成功不替代这些生产门槛。
生产 observer 故障恢复、LSM、原生 systemd、arm64、公网、重启卸载仍未验收。

证据 `.tmp-ssh-syslog-8c2c/evidence.md`、
`.tmp-ssh-syslog-8c2c/openssh/evidence.md`、
`.tmp-ssh-lifecycle-8c2c/evidence.md`、
`.tmp-ssh-lifecycle-drain-8c2c/evidence.md` 与 `.tmp-ssh-epoch-8c2c/design.md`。
本轮原型容器、进程、非负 FD、socket、临时 key/config 均已清理；
保留可复现探针与原始结果，不删除其它任务文件。
`runtime_configuration_verified=false`、`jail_ready=false` 保持；
未推送或发布，5C 与总目标 active。

#### 5C.8c.2d 内部 Ledger 与跨不同 exe 积压消息

2026-10-11，新增内部 `docker/lib/ssh-ledger.py`，并接入既有
`docker-ssh-preflight` selector；未新增分片或生产 CLI。
`Ledger(deadline)` 固定总窗口和 32 条消息上限，提供 register、drain、
finish_stop 和幂等 close。它复用现有来源异常类型，保留 source/journal
的 live witness 语义；cgroup 只记录，不认证宿主 unit。
真实首停、父 FORK 关系和完整 ptrace 事件观察由可信 driver 提供，
外部 JSON 或 `state=t` 不取得停点证明。

收到的 FD 先登记再解析，credentials 精确 12 bytes、同消息 pidfd 精确
4 bytes 且各唯一；非法 UTF-8、截断、SCM_RIGHTS、unknown、terminal、
负 pidfd 和缺 accepted anchor 均拒绝，合法正文不授予来源身份。
排空到真实 EAGAIN 后 pending 冻结 sender generation、旧 epoch/exe 和
fork accepted anchor，并保留消息 pidfd。sender 自身 EXEC/EXIT 停点
先提交旧 pending，双 pidfd 前后活性和末尾 generation 复核通过后，
关闭消息 FD，再更新 epoch/终结；driver 仅成功返回后 CONT。
超限、总 deadline、代次变化或资源读取异常毒化整个账本，关闭全部
held/pending FD，后续调用拒绝。当前持 FD 与 TCP ESTAB 分开记录，
历史锚点不能冒充当前 live socket；始终 `authoritative=false`、
`jail_ready=false`。

新增 5 组内部合同使用真实 Linux ancillary/pidfd、accepted TCP inode 和
受控 SIGSTOP 子进程。覆盖快照冻结、CLOEXEC、未知/回收/截断/非法 UTF-8/
额外 FD 拒绝、代次/epoch/deadline/重复 PID 毒化和关闭幂等。
32/33 边界先保存真实 sender 的 pending，再补到 32；第 33 条同时证明
held/message FD 全关、pending/accepted 取消。合同中的 event 4/6 是
直接 API 调用，真实 EXEC/EXIT 停点由下述独立 driver 实证。

跨不同 exe 原型直接导入同一冻结模块，一次 10/10、18.236 ms：
普通 fork child 首停与父 FORK 停点继承同一 accepted inode；
Python libc 旧日志在 SIGSTOP barrier 入 pending，真实 EXEC 到 C helper
后仍归 epoch 0、`epoch_exe=/usr/bin/python3.13`，不套用当前 helper 身份。
helper 新日志和关闭 accepted FD 后的日志归 epoch 1。
EXIT 当前 `socket_fds=[]`、owned TCP 为空、`owns_anchor_fd=false`、
`live_socket_verified=false`，仍保留历史连接事实。
另一个真实 unknown libc sender 明确拒绝，FD 计数不增。
9 条 trace 含 1 次 EXEC、2 次 EXIT，终局 FD 6 -> 6，
tracee、未登记停点和消息 FD 均为空，主代理及独审复核一致。
基础 SSH 镜像缺 GCC 时，仅在独立联网容器从 Debian 官方源补齐
gcc/libc6-dev，缓存工具镜像后回到无网络、私有 PID、零宿主挂载的
实测容器；privileged 仅用于私有 mount/syslog 原型。
工具镜像 `sha256:bd610ac50a49c93807285e1d8d8ef620d268563aa8ddcbb691708017bf7acb1e`
保留复用，容器、binary、socket 和私有 `/dev/log` 已清理。

最终定向 source 20、journal 9、Ledger 5、client 通过，入口 1910 ms，
内部 956 ms；完整合同首轮 45/46，唯一失败是既有 released-lock
测试的 1 秒时钟竞争。同源码单跑 phase1 通过，确定性红绿检查强制
首轮 mkdir 竞争等待 1.1 秒，旧时钟失败、固定测试时钟通过。
`0352508a` 仅固定该 fixture 的 SECONDS 和 sleep，并用外层真实
timeout 3 防止死循环，增加竞争触发/锁已释放断言；生产锁校验和
真实超时负例未改。修复后 phase1 定向 48934 ms 通过，
集中完整合同 46/46、入口 315950 ms、内部 314817 ms、排队 394 ms。
各次 `exit_code=0` 的成功结果均 `cache_hit=false`，复用工具镜像，
保持完整 Jobs 6、三槽预算中的 2 槽，没有扩大并发。
两轮负载不同，最终耗时不作为整体回归提速证明。

最终完整快照启动时 294 个文件逐一 SHA256 与工作区一致；
提交前本阶段 4 个代码/测试输入仍相同，两个并行订阅菜单文件随后
变化，未计入本阶段验收或提交。证据：
`.tmp-ssh-ledger-8c2d/evidence.md`、
`.tmp-ssh-epoch-cross-exec-8c2d/evidence.md`、
`.tmp-phase1-clock-8c2d/evidence.md`、
`.tmp-regression-docker-a47c9f94875144a3891415fb6a3f768e/`、
`.tmp-regression-docker-abc5db0079e3435eb92107c18198a79e/`。
本轮清理 6 套回归的归档/清单共 12 文件、55,512,372 bytes，
保留结果、日志、复现源及哈希；未删除其它任务临时文件。

8c.2e 故障拒绝证据见下一节。8c.2d 原始探针的未支持事件仍可能落入
普通信号继续分支；本轮未覆盖或修改它，不能用于生产 observer。
多线程、共享 clone/创建 flags、unit、故障恢复、LSM、arm64、原生
systemd、公网、重启卸载仍未验收；collector/jail 与 5C 保持未完成，
不放宽现有 owner 或 live witness，不宣称完成菜单功能对齐。

#### 5C.8c.2e Ledger 故障拒绝与 tracer 消失证据

独立故障原型直接导入 8c.2d 的冻结 Ledger/source，不修改生产模块或
原始 cross-exec 探针。Docker Desktop Linux amd64、WSL2 内核
`6.6.87.2-microsoft-standard-WSL2`、glibc 2.41，复用前阶段 GCC
工具镜像；独立容器 `network=none`、`SYS_PTRACE`、无宿主挂载，
源码复制到 Linux 文件系统。最终 5/5、6088.581 ms，主代理与独审一致。

| 故障 | 实际注入与首次拒绝 | 拒绝后的资源与控制 |
| --- | --- | --- |
| drain deadline | 真实 recvmsg 附件先进入 `_fds`，跨未修改的总期限；首次 `_receive:150` | 全部 held/received FD 为 EBADF，FD 7 -> 7 |
| received pidfd deadline | 真实 pidfd 读取成功后跨总期限；首次 `_pidfd:60` | 同上，FD 7 -> 7 |
| EXEC commit deadline | 真实 EXEC 停点提交读取 received pidfd 后跨总期限；首次 `_pidfd:60` | 同上，FD 7 -> 7 |
| 未支持 event | SEIZE/INTERRUPT 产生真实 event 128；首次登记并 CONT 后，第二次 128 在普通信号分支前拒绝 | held pidfd 为 EBADF，FD 5 -> 5 |
| tracer SIGKILL | 独立 subreaper 先杀已设置 EXITKILL 的 tracer | tracer/首停 tracee 均 -9，FD 4 -> 4 |

三个 deadline 场景均保留真实 monotonic 时钟，原绝对期限不变；
约 2019 ms 的等待发生在真实系统调用成功以后，不伪造 recvmsg、pidfd
或停点。账本 poison/closed，pending/accepted 全取消，epoch 保持 0，
后续调用拒绝；故障后实际普通 CONT 为 0，tracee SIGKILL 回收且
`/proc` 消失。ptrace 成功调用单独记载，正常 CONT 与清理动作分开。

未知 event guard 仅在本轮临时 fixture 中；原始 driver 未修。
EXITKILL 由 tracee pidfd 从未就绪变为 POLLIN、回收后 `Pid:-1`、
两个 `/proc` 消失及 subreaper `ECHILD` 共同证明，supervisor 未先杀
tracee。该场景只覆盖首停，不能外推运行态 tracer 故障恢复。
顶层保持 `authoritative=false`、`jail_ready=false`。

首轮同样 5/5、6092.046 ms，但首次拒绝位置被后续“关闭后再次调用”
覆盖；保留 `first-attempt/`，修正 instrumentation 后只复跑本套
6 秒检查。另一次启动因镜像 `/bin/sh` ENTRYPOINT 把 sleep 当脚本，
退出 2 且未执行探针；保留原始原因，改 `--entrypoint sleep` 后执行。
生产输入未变，不重复已通过的完整合同。

证据 `.tmp-ssh-faults-8c2e/evidence.md`、`probe.py`、`result.json`：
probe SHA256 `AEA78CBA75AAABFBEA0293CFB16EB03A2DC9898E5695138A97E56533D01CD042`，
result `4ACBFE78329BDF1FC3A0E7A991B281927FF3E4B95283D03FE5A724812732C6C4`，
evidence `BBC9076904D42A282B37522834BAFB136D96ADE63D41122F28424A5A0F8EA6BA`。
Ledger/source 及 8c.2d 原始证据哈希不变。实验容器、socket、binary、
pidfd 和缓存已清理，只留 5 个复现源/证据文件。

8c.2f 受控单线程内部 driver 见下一节，直接调用 Ledger 并拒绝未知
event，补运行态 EXITKILL；限定自身创建的已知普通 fork 测试子树。
event 1 或 Threads=1 快照不能单独证明创建 flags 安全；共享 clone、
多线程、创建参数、unit 前置与任意 OpenSSH 接入仍是后续门槛。
本轮不接菜单、collector 或 jail，不修改宿主 SSH。

#### 5C.8c.2f 受控单线程内部 lifecycle driver

新增 `docker/lib/ssh-driver.py` 的 `ControlledDriver.run(child_main)`，
仅由自身 fork/TRACEME 创建可信测试子树，不提供外部 PID attach 或
生产 CLI。复用 Ledger，真实首停登记前核验父链、代次、单线程、
独立进程组、namespace 和 accepted tuple/inode 继承；早到 child
首停保持冻结，父 FORK 事件确认后才登记和继续。
event 2/3 或其它非 allowlist event 在普通信号分支前拒绝；
创建事件先 GETEVENTMSG 纳入 child 清理范围，再检查期限和事件类别。
EXEC/EXIT 的 Ledger 提交成功后才 CONT，实际 CONT 前再检查总期限。
停点、pending 和返回证据深拷贝，不随后续账本改写。

异常毒化并关闭账本，正常 CONT 与 cleanup CONT/SIGKILL 分开；
清理按自有进程组发现尚未消费的创建停点，再按已知 PID/TID 回收。
wait 已消费或尚未消费创建状态时超时都不能丢失新 child；
线程 ECHILD 仅在 `/proc` 确认消失后移除，剩余 task 明确失败。
设置 `PTRACE_O_EXITKILL`，仍保持 `authoritative=false`、
`jail_ready=false`；可信 callback 是前提，event 1/Threads=1 本身
不证明创建 flags 安全，不能把本 driver 接到任意 OpenSSH。

新增 6 个真实 Linux 合同与 C helper，无私有 `/dev/log` mount：

| 合同 | 实际检查 |
| --- | --- |
| Python 到 C exec | old pending 快照仍 epoch 0；新/关闭 FD 消息 epoch 1，关闭后仅历史锚点 |
| pthread clone | 真 event 3 拒绝，后续正常 CONT 为 0，child/TID 回收 |
| finish 后 deadline | 成功提交后、实际 CONT 前跨未改期限，全关并取消 accepted/pending |
| 已消费 FORK wait deadline | 取得创建状态后跨期限，新 child 仍进入回收范围 |
| 未消费 FORK wait deadline | 真父创建停点和 `/proc` child 已出现后跨期限，清理发现并回收 child |
| 运行态 EXITKILL | master/child 均非 t/T/Z、同 TracerPid 后真杀 tracer，两个 tracee SIGKILL/POLLIN/回收 |

EXITKILL 由独立 subreaper 的原始 `/proc`、pidfd、SIGKILL wait 状态、
proc 消失、ECHILD 和 FD 基线共同断言；supervisor 在观察前未杀 tracee，
测试结束恢复 subreaper 原状态。未知新 child 回收和 CONT 最终期限
是独审发现后新增的实际安全断言，没有伪造时钟、期限或 ptrace 事件。

首跑 driver 6 项过早失败，根因自身 `/proc/fd` 枚举的 scandir FD
在逐项 readlink 前关闭；只跳过该处 `FileNotFoundError`，其余读取
异常仍严格失败。原始日志保留，修订后定向 6/6、3.154 秒，
入口 4121 ms、内部 3204 ms。调度聚合入口 1440 ms/内部 490 ms，
完整与 CI 分片 leaf 集合断言通过。

新增独立 `docker-ssh-driver` leaf，加入完整合同与 CI fast-rest；
仅包含该 leaf 的回归 selector/CI 分片增加 SYS_PTRACE，
无 host PID/network、宿主 Socket 或 privileged。工具 GCC/libc6-dev
从 Debian 官方 HTTPS 源安装在独立末层，复用原 1–8 层缓存。
首次误改原安装层触发 131 MB/137 包重下载，约 443 秒后停止本任务
构建；末层修订仅下载 56.4 MB/34 包、构建 560.4 秒，随后回归复用
`sha256:d9a9a7ad6ad5a945ab85ee757ed8e32c55e06dd2f9efccf871d0d9a57e895f98`。
构建和下载耗时不计入回归 elapsed，不称补工具仅花回归入口的 2 秒。

集中完整合同 47/47、exit 0、cache_hit=false，入口 289480 ms、
内部 288570 ms、排队 375 ms、Jobs 6/占 2 槽，未扩大三槽预算；
driver 在完整并发中 6/6、3.166 秒。最终 297 个快照文件与当前工作区
逐一 SHA256 一致，本阶段 8 个新增/修改代码与配置输入及既有
Ledger/source 哈希均匹配成功快照；后续只补文档，不重复全套。
未使用不同负载两轮的 elapsed 宣称整体回归提速。

证据 `.tmp-ssh-driver-8c2f/evidence.md`、`input-hashes.json`、
`snapshot-workspace-differences.json`，
定向 `.tmp-regression-docker-d06da66b0fa449c08189533d27a7a3d6/`，
调度 `.tmp-regression-docker-e885dcde2d7244ae8a55497b8e76ca01/`，
完整 `.tmp-regression-docker-8c8d7176454e42b3912c3c891d72a162/`。
本阶段清理 6 套入口的 12 个归档/清单共 55,819,461 bytes，
每项哈希留 `cleanup.json`，日志/result/复现源保留；本任务容器已清理，
未删除其它任务临时资源。

早到 child 首停分支有源码支持，本新 driver 尚未强制实测该分支。
下一步先补真实创建 syscall/flags 与 FORK 事件关联，保守授权已证明
普通 fork，拒绝共享 clone/UNTRACED/未知参数；再接 8c.2a 的 unit 前置。
unit 归属不能补创建模型缺口；多线程、任意 OpenSSH、故障恢复、
LSM/arm64/宿主 systemd、公网和重启卸载仍待验收，collector/jail、
菜单启停与 5C 不因本内部 driver 通过而开放。

#### 5C.8c.2g 创建 syscall、FORK 与真实回收关联

受控 driver 正常恢复改用 `PTRACE_SYSCALL` 与 `TRACESYSGOOD`，
通过 `PTRACE_GET_SYSCALL_INFO` 的实际 op 区分 entry/exit，不猜停点奇偶。
逐 syscall 停点核验 native `AUDIT_ARCH_X86_64`，拒绝 x32、i386、
未知 ABI 或不完整信息。仅允许 fork 57 或保守 clone 56 模型：
clone flags 只能为 SIGCHLD 与 CHILD_SETTID/CHILD_CLEARTID 的子集，
stack、parent_tid、tls 必须为 0，child_tid 与 childtid flags 对应。
vfork、clone3、共享状态、UNTRACED、未知 flags/参数在 entry 恢复前拒绝。

创建 entry 冻结父代次、epoch、exe、nr/args 和 live accepted 锚点，
与真实 FORK event 的 child PID、父 syscall exit 的正返回 PID、
child 首停逐项关联后才登记和放行 child；父返回停点缺 child 首停时也冻结。
创建失败只在负返回且没有 FORK event 时清证明；无对应 entry 的首 exit 0
仅给初始 master 与新登记 child 一次资格。普通 syscall 只保留停点总数和
最后恢复时间，不逐项保存事件或读取完整 proc；创建及生命周期证据仍深拷贝。

整合 CI `38117132117` 的同步修正：driver 执行期保存/启用 subreaper，
结束恢复原值；cleanup 的 ptrace 退出通知不再直接充当真正回收证明，
EXITKILL 测试对 pidfd 退出后尚未转交的 ECHILD 作有限等待。
Ledger 测试接受内核交付差异下的 invalid_pidfd/unknown_sender 两种拒绝原因，
仍断言 accepted/pending 为 false、FD 数不变及附件关闭；生产 Ledger 未改。

独审进一步发现正常退出路径也可能丢失未回收 child，新增真实合同先取得红证据：
父进程不回收 child 就退出，10 项中仅该项失败，返回后 `/proc/567` 仍在。
修复在已登记终局通知时复制原 held pidfd，live 调度继续运行；
统一清理通过 `waitid(P_PIDFD)` 真回收，或 fdinfo `Pid=-1` 确认原 task
已由真实父进程回收，绝不向 retired 数字 PID 发信号或等待复用后的 task。
pidfd 跨 Ledger 关闭独立持有，最终关闭；未登记终局纳入清理后拒绝。
异常进程组发现仍等待真实 ECHILD，保持原 2 秒 cleanup 期限。
成功与失败终局核验创建、syscall、首 exit、父确认和 FD 等全部内部状态。
正例用父 `WNOWAIT` 仅观察终止而不回收，替代固定 sleep 保证负载下顺序稳定。

最终 driver 为 10 个真实合同，包含早到 child 首停先于父 FORK 被消费、
缺 entry/错配 PID 拒绝、共享 clone/UNTRACED/clone3 entry 拒绝、
真实 x32 syscall 与 `int $0x80` i386 ABI、三类 deadline、跨 exec、
父未回收 child 和运行态 EXITKILL。拒绝后核最后正常恢复时间不晚于拒绝，
所有合同核 tracee/retired 清空、FD 基线和 subreaper 恢复。
本机实际正例为 clone 56，arch `0xC000003E`、flags `0x1200011`；
raw fork 57 尚未单独实测。原始共享 clone 对照为 flags `0x111`、
event 1/status 66943，证明 FORK event 1 本身无法排除 CLONE_VM。

2026-10-11，Docker Desktop Linux amd64，复用工具镜像
`sha256:0e727d5230441005929d896a73b9dd140360045e3d5dc8850de0e6ab7b2ff0f5`。
最终定向 10/10、3.265 秒，入口 4280 ms、内部 3316 ms、排队 198 ms，
exit 0、cache_hit=false、Jobs 2；
`.tmp-regression-docker-1fa13814a52546d9b1018bc64fb42cf5/`。
集中完整合同 47/47、exit 0、cache_hit=false，入口 293360 ms、
内部 292378 ms、排队 380 ms、Jobs 6/占 2 槽，未扩大三槽预算；
driver 在完整并发中 10/10、3.270 秒，preflight 同时通过。
完整证据 `.tmp-regression-docker-43285496efd2432eab2af0a583877913/`，
未复用此前不同源码的成功结果，不据不同负载 elapsed 宣称整体提速。
证据 `.tmp-ssh-driver-flags-8c2g/evidence.md`，失败输入保留
`before-reap-fix/` 及哈希；完整快照初核 297 个文件与工作区逐项 SHA256 一致，
最终只有本实施文档补写结果，全部运行输入保持匹配。
清理本轮 4 套入口的 8 个归档/清单共 37,381,872 bytes，
及 297 个已核验解包文件 9,111,863 bytes；日志、result、哈希与失败源码保留，
本阶段回归容器无残留，不清理其它任务临时文件或 worktree。

仍只接受可信自建 amd64 callback，`authoritative/jail_ready=false`；
当前进程组模型不证明真实 sshd 在 setsid/setpgid 后仍被完整收容。
下一阶段先在自有受控 systemd/sshd 实例证明所选 unit MainPID 与完整子树，
同一 deadline 复用 8c.2a 的 pre/post unit、invocation、cgroup 和 listener 锚点；
现有 Python master 不能直接套 unit JSON 冒充真实 SSH 来源。
任意 OpenSSH、collector/jail、菜单启停、arm64、原生宿主和公网仍未开放或验收。

#### 5C.8c.2h1 自有 systemd/sshd MainPID 移交原型

先独立验证真实 sshd 的启动归属，不把已有 Python callback master 套 unit JSON
当作 SSH 来源。临时可信 tracer 是自有 `Type=notify` unit 的 ExecStart，
自行 fork/TRACEME、首停设置独立 PGID，再 exec `/usr/sbin/sshd -D`
与专属 loopback `127.0.0.1:22218` 配置；实际 LISTEN 出现后由原 tracer
使用 `NotifyAccess=main` 发送 READY/MAINPID。只有 manager 的实际
`read_unit` 返回 active/running、MainPID 等于该已知 child，才认定移交成功。
客户端之前复用原 `unit_snapshot` 两次，unit、invocation、cgroup、
主进程安全 exe 身份/代次及两族完整唯一 listener 必须全部相同。

2026-10-11，复用原生 amd64 镜像
`sha256:0698b0ffcad3c265ab623b5bce0fcb9ef6cf9ed038811ba6b34162eee5d76f00`，
已有 systemd `257.13-1~deb13u1`、OpenSSH `10.0p2 Debian-7+deb13u4`、
Paramiko 与 ss，无新工具安装。低权限 systemd 原型 exit 255 且无日志，
随后只在私有 cgroup、network none、无宿主挂载/Socket 的隔离 privileged
实例验收，不代替原生宿主验收。首轮 MainPID 已成功，但镜像默认 22/80
服务触发停止后全实例无 LISTEN 断言；原失败证据保留。
第二轮以 `systemd --unit=basic.target` 避免这些默认服务，保持原断言后通过。

最终 tracer 99 自建 child 101，初停到真实 sshd EXEC、LISTEN 和通知时
start tick 47401、pgrp 101、sid 99 保持一致；systemd 实际 MainPID 101、
InvocationID `848c02c7d9004edaab648e5d3679a13c`、unit active/running。
唯一 LISTEN inode 26972/fd 6，原严格 snapshot 首尾相同；未放宽 single-owner。
停止返回 0、inactive/dead、全实例监听为空，trace 记录 SIGKILL/-9 真回收、
child proc 消失与 ECHILD。本次启动未观察到 setsid/setpgid syscall，
只证明该启动窗口的 pgrp/sid 未变，不把它当作连接子树不会脱组的证明。

证据和小复现源 `.tmp-ssh-unit-driver-8c2h/`，保留首轮和最终
evidence/trace、输入哈希与隔离条件；本任务 unit、进程、容器完成清理。
本阶段仅补文档，不重复 8c.2g 的完整回归，也不宣称 driver 已接真实 sshd。
下一步仍需真实失败认证连接的创建 nr/flags、accepted/LISTEN 继承、
短命 sender 与 setsid/setpgid 后完整收容及回收；不将观察工具当生产 driver。
`authoritative/jail_ready=false`，任意 PID attach、collector/jail、
菜单、arm64、公网和原生宿主验收继续未开放或未完成。

#### 5C.8c.2h2 自有 unit 的真实失败认证子树

2026-10-11，复用 h1 同一原生 amd64 工具镜像和隔离条件，仅运行一个
固定临时 host key、随机无效用户名的真实 publickey 认证连接。
首次实测退出 0，客户端取得 `AuthenticationException`、`authenticated=false`；
Docker exec 耗时 1.457 秒，不作为容器建立或完整阶段耗时。
自有 observer 97 创建 sshd MainPID 101，InvocationID
`37a512aa079b4cd286eea4dbe201f68b`，连接前后原严格 `unit_snapshot` 相同。

两个创建均为实际 amd64 clone 56、flags `0x1200011`、FORK event 1：
101 -> 116、116 -> 123 的 entry、父事件、返回 child PID 与 child 首停关联完成，
首停保持到父返回获证后才恢复；第二个 child 首停实际早于父 FORK 消费。
本次无 `initial-syscall-exit` 记录，不宣称 child 初始 exit 0 已实测。
首个 child 116 继承 LISTEN inode 55836/fd 6 与 accepted inode 55839/fd 7，
后者四元组为 `127.0.0.1:22219 <- 127.0.0.1:38714`。
冻结窗口实际 LISTEN owners 为 101 与 116，原 `unit_snapshot` 拒绝
“SSH unit 必须只有一个唯一显式 TCP 监听”；未放宽生产 single-owner gate。

child 116 恢复后实际调用 `setsid` syscall 112，返回 116、非错误，
PGID 从 101 变为 116，SID 从 97 变为 116，然后 EXEC 到 `sshd-session`；
其 child 123 再 EXEC 到 `sshd-auth`。这直接确认现 driver 的
`waitpid(-master)` 与 `pgrp == master` 模型不能接入该真实连接子树。
临时 observer 的 `waitpid(-1)` 仅用于自己创建且不含客户端的诊断树，
不作为生产独立身份收容或 Ledger 授权实现。

两条真实日志是 root session PID 116 的 `Invalid user` 与
`Connection closed ... [preauth]`，unit/invocation 字段与自有树停点交叉一致；
未观察到 `Failed publickey` 文本。journald 的 PID/exe/时间只作诊断，
没有同消息 credentials/pidfd、发送时 epoch 或 Ledger 历史端口授权。
两个后代实际 exit 255，EXIT 时仍持 accepted FD、TCP 为 CLOSE_WAIT；
最终原 pidfd 全部确认原 task 回收，`/proc` 消失、ECHILD、FD 4 -> 4、
subreaper 恢复，unit inactive/dead、全实例 LISTEN 空。
证据和小复现源保留在 `.tmp-ssh-unit-driver-8c2h2/`；临时容器完成清理。
本阶段仅文档，不重复完整回归；IPv6、原生宿主、异常 tracer 和生产
collector/jail 未验收，`authoritative/jail_ready=false` 保持。

#### 5C.8c.2i 受控 driver 的进程组边界保护

针对 h2 的真实脱组证据，保持现有单进程组 fixture 范围：
native amd64 的 `setpgid` 109、`setsid` 112 在实际 syscall entry、
正常恢复执行前明确拒绝。停点保存真实 nr/args、PGID/SID，并核对已登记代次；
不把临时 observer 的 `waitpid(-1)` 移入生产，不改变等待、Ledger 授权、
live 清理或 retired task 的独立 pidfd 回收路径。
driver 初始化的 setpgid 位于 TRACEME 首停前，原正例继续使用。
两个 syscall 当前包括不改变组的调用也保守拒绝，不代表支持真实 SSH 子树。

新增两个 raw syscall 场景。裸 baseline 的非组长进程均实际脱组且执行 marker；
受控场景在已登记、继承唯一 accepted socket 的 fork child 中尝试同一 syscall。
原实现红合同 11 项中两个子场景因总窗口超时失败，内部 7.396 秒；
其错误断言先失败，后续清理断言未执行，不宣称红完整终局已独立验收。
修改后定向 11/11、3.310 秒，入口 4308 ms、排队 206 ms、cache_hit=false。
两种拒绝均停在 entry，PGID 仍为 master、SID 与首停相同，
最后正常恢复早于拒绝、marker 不可达、Ledger poisoned；
集合/FD/subreaper、child/master proc 消失及逐 PID/全局 ECHILD 断言通过。
原创建、跨 exe、retired pidfd 和运行中 EXITKILL 合同继续通过。

证据 `.tmp-ssh-group-guard-8c2i/` 保留红源、哈希、原始日志和清理记录。
红/绿两个快照的 3 个目标文件逐项匹配；清理重复归档与清单 18730616 bytes，
两个定向回归容器无残留。集成后集中完整 Docker 合同 47/47、退出 0，
内部 304599 ms、入口 305522 ms、排队 393 ms、Jobs 6、cache_hit=false，
driver 在完整并发中 11/11、3.334 秒，preflight 同时通过。
297 个输入文件核对后，仅计划与并行任务 README 文档变化，执行源码保持一致；
完整输入哈希与结果保留在阶段证据中。另清理完整归档/清单及 297 个解包文件
18495697 bytes，完整回归容器无残留。不据本次耗时宣称整体提速。
真实 OpenSSH 的独立身份等待/收容、collector/jail 和宿主验收仍未完成，
`authoritative/jail_ready=false` 保持。

#### 5C.8c.2j 原 pidfd 等待与清理屏障

driver 为自建 master 和父创建事件确认的 child 独立持有 pidfd，正常停点改为
`waitid(P_PIDFD, WSTOPPED|WEXITED|WNOHANG|__WALL)` 精确消费。
`CLD_TRAPPED` 保留内核 `si_status` 的 ptrace event 位，终局按真实 si_code
转换；未知类型拒绝。每次数字 ptrace 前核对原 fd、已消费停点和真实 `t` 状态，
采样不再以 `pgrp == master` 作为身份条件；等待轮转已知 fd，避免父 syscall
饿死 child。正常和异常路径均不使用负 PGID、全局 wait 或裸 PID 信号。

child 的内核首停即使先到，也保留到已知父的真实 FORK 停点被消费后；
GETEVENTMSG 取得 child PID 后立即固定原 fd，再验证首末代次、父链、
TracerPid、namespace 与 exe。创建 entry/FORK/父 exit/child 首停四段和
accepted 继承闭合后才正常恢复。独审补正固定 fd 后校验失败的路径：
先把原 child 绑定到父创建停点，后续校验失败只供 cleanup 复用，不能重复登记或放行。

清理在原 2 秒期限内先形成停止屏障：仍运行的已知 task 收到原 pidfd SIGSTOP，
精确消费创建事件并固定全部新 child，所有 live task 保持真实停点后才
pidfd SIGKILL。SIGKILL 可异步唤醒旧停点，故丢弃旧状态，只对重新消费的新
EXIT 停点 CONT(SIGKILL)。原 fd 跨 Ledger 关闭独立持有；terminal 移入
retired 后由 P_PIDFD 真回收或 fdinfo `Pid=-1` 确认原 task 已回收，
不操作复用的数字 PID。成功与失败均核 owned/stopped/retired、FD 与 subreaper 终局。

独立 Linux amd64 探针逐项核对 255 个真实停点，含 243 个 syscall：
FORK `261 -> 66943`、EXEC `1029 -> 263551`、EXIT `1541 -> 394623`。
child setsid 后再 fork，grandchild setpgid 后 exec，原 P_PIDFD 均可消费；
无关 child 的退出 37 留给原 caller。两次故障探针分别覆盖未消费 FORK，
以及创建 entry 恢复后父为 R、尚无 wait 结果的窗口：
SIGSTOP 后精确父 FORK -> 固定 childfd -> SIGKILL -> EXIT/真正 terminal，
原 pidfd `Pid=-1`、proc 消失、ECHILD、FD 4 -> 4 和 subreaper 恢复。
探针仅单次真实时序，不宣称 SIGSTOP 总先返回 FORK；其它停点仍由状态机处理。
复用现有工具镜像、network none、SYS_PTRACE；源码在容器 Linux 文件系统执行，
HOME/TMPDIR 同在容器内，实验容器清理后留 `.tmp-ssh-task-wait-8c2j/` 小证据。

定向合同新增同 PGID caller 的正常/失败 × 停住/已退出 4 个隔离场景，
保留创建、跨 exe、ABI/flags 拒绝、deadline、retired 和 EXITKILL 断言，
并新增 child 已固定后父链校验失败的原身份清理合同。
最终定向 13/13、3.497 秒；入口 4521 ms、内部 3584 ms、Jobs 2、
cache_hit=false，证据 `.tmp-regression-docker-c798692947da4bab81a93a0a93cd1a8d/`。
初轮 12/12 不作为后来新增故障合同的验证。集中完整 Docker 合同 47/47、
exit 0、内部 284284 ms、入口 285291 ms、排队 5500 ms、Jobs 6/占 2 槽、
cache_hit=false；driver 在完整并发中 13/13、3.641 秒，preflight 同时通过。
证据 `.tmp-regression-docker-d276a18e5b564226899cba6ead3e744f/`。
完整快照的 297 个输入文件与工作区逐项 SHA-256 一致；结果补写后仅本计划变化，
执行源码保持匹配。复用工具镜像与三槽队列，不据单轮 elapsed 宣称整体提速。

本阶段 109/112 仍在正常执行 entry 拒绝；跨 PGID 正例只属于独立观察器。
未成功取得 pidfd 的工具/资源错误（EMFILE/EPERM 等）尚无完整收容合同，
不能把已固定后的校验失败合同写成所有 pin 失败均能清理。
真实 OpenSSH/unit 子树、raw fork 57、vfork、arm64、多线程、collector/jail、
菜单启停及宿主验收仍未完成，`authoritative/jail_ready=false`。

#### 5C.8c.2k 首次 pidfd 失败的启动闸门

在直接 fork 前创建专用 socketpair，child 先关闭父端并等待精确许可字节；
父复用 `_pin(master)`，取得并登记原 pidfd 后才以 `MSG_NOSIGNAL` 放行，
发送结果必须完整 1 byte。child 在此之前不进入 setpgid、TRACEME、
SIGSTOP 或 callback；父固定身份失败先关闭闸门，child 从 EOF 自退 113。
已持有 pidfd 后的校验失败沿原身份清理，不重复固定或数字等待。

未取得 pidfd 时只对本次直接 fork 返回的 master 使用
`waitpid(master, WNOHANG)`，独立 2 秒期限，核真实 terminal 后才确认回收。
不消费全局、负 PGID 或其它 child 的等待状态，不以裸 PID 信号补救。
ECHILD、未知终局或超时保留 `remaining_bootstrap_tasks/cleanup_error`，
仍保留最初失败原因，不能写成清理成功；所有 gate FD 在 Ledger 关闭前释放。
Python 可见非默认 SIGCHLD 策略在 fork 前拒绝。

新增首次失败 3 个 errno 子场景：EMFILE 由临时降低父 RLIMIT_NOFILE、
填满 FD 后真实 `pidfd_open` 触发，EPERM/ENOMEM 为首次定点注入。
核 child 的 TracerPid 0、callback 未执行、真实退出 113、精确回收、
FD/limit/subreaper 恢复，并保留无关 caller child 的 SIGSTOP 与退出 29。
另一个合同仅隐藏 bootstrap wait 返回，2 秒后明确报告未回收和原 errno，
补丁外真实回收已自退 child；不以此代替外部 SIGSTOP 验收。
定向 15/15、5.672 秒，入口 7101 ms、内部 5807 ms、排队 5076 ms，
Jobs 2、cache_hit=false；`.tmp-regression-docker-d6800c309f5449e2b1db30a5e6d95ce1/`。
集中完整 Docker 合同 47/47、exit 0、内部 327220 ms、入口 328169 ms，
排队 454 ms、Jobs 6/占 2 槽、cache_hit=false；driver 15/15、5.583 秒，
preflight 同时通过，`.tmp-regression-docker-d0b5e24662d945ba8b06c351c1ff7168/`。
完整归档 297 个输入最初逐项匹配；完成时仅其它任务的 UI 测试变化，
本阶段执行源码保持冻结；随后只补写本计划的结果。
清理自有重复归档、清单及核对脚本 18837025 bytes，日志/结果/哈希保留在
`.tmp-ssh-bootstrap-8c2k/`；复用工具镜像，无重复解包，不据单轮耗时宣称提速。

本阶段仍限可信单线程 fixture；Python SIGCHLD 检查不能证明原生
SA_NOCLDWAIT flags，atfork child 钩子早于闸门，异步 reaper、继承的异常
信号处理器和外部 SIGSTOP 未覆盖。该实现不等同 `CLONE_PIDFD` 原子创建，
不宣称无条件消除未持有 pidfd 的窗口。
创建事件 child 的首次 pidfd 固定失败仍未闭合；
109/112 正常执行、真实 OpenSSH/unit 子树、collector/jail 和宿主验收仍待推进，
`authoritative/jail_ready=false` 保持。

#### 5C.8c.2l 自身进程组与会话合同

本阶段仅验证可信 task 的 `setpgid(0,0)` 与 `setsid()`；109 指定其它
target 或 group 的参数继续在 entry 拒绝，112 的无意义寄存器参数不作零值要求。
启动 master 的独立 PGID 前置保留，不把 PGID/SID 提升为 Ledger 身份。
真实 entry/exit 配对并核原 pidfd、停点、generation、exe、epoch 和 accepted 锚点；
109 成功须返回 0、PGID 为自身 PID、SID 不变，112 成功须返回自身 PID、
PGID/SID 均为自身 PID。真实 errno 返回须保留原 PGID/SID，不改变授权或 epoch。
未闭合的组变化 entry 必须拒绝正常完成，失败清理后保留被丢弃的证明记录。

正例复用 Python fork、已有消息与 C cross-exec：child 自身变组后再创建
grandchild，继续验证四段创建、accepted 继承、跨 exe、FD 关闭及三代真正回收。
另验组长 setsid 的真实 EPERM 后继续、109 非自身参数拒绝，以及脱组后
grandchild 已固定但父尚未恢复时的故障收容。
新增真实 setsid exit 基础上的损坏 rval 负例，拒绝后无正常恢复或新后代，
未闭合证明留给 `discarded_group_proofs`。原跨 exec 消息/epoch/FD/finish-stop
断言提为共享检查，保留全部关键断言并增加 sender 身份，不重复消息 fixture。

定向 19/19、5.822 秒，内部 5945 ms、入口 7005 ms、排队 197 ms，
Jobs 2、cache_hit=false；`.tmp-regression-docker-bd1f53a810fc4ff8a2e8debb195033dd/`。
集中完整 Docker 合同 47/47、exit 0，内部 344334 ms、入口 345322 ms，
排队 390 ms、Jobs 6/占 2 槽、cache_hit=false；driver 19/19、5.770 秒，
preflight 同时通过，`.tmp-regression-docker-9d8637b06b0a4dffbb24ec4bad59168d/`。
两个归档各 298 输入，本阶段 driver/tests/计划冻结匹配；最终差异仅其它任务的
原生事务 case/suite 和 Docker 回归入口，不能把归档结论扩展到这些后来改动。
结果补写后仅本计划更新；流式核对不重复解包，清理重复归档、清单、核对脚本
18931291 bytes，两个回归容器无残留，小证据在 `.tmp-ssh-self-group-8c2l/`。
本轮复用工具镜像和三槽队列，不据两轮完整 elapsed 宣称整体提速。

本阶段不开放任意 OpenSSH/unit、collector/jail，创建事件 child 的首次
pidfd 固定失败仍待闭合；`authoritative/jail_ready=false`。

#### 5C.8c.2m 创建事件 child 首次 pidfd 失败

真实父创建停点的 GETEVENTMSG 先保存 cleanup-only child 身份，
绑定原父 pidfd、已消费停点、generation 和发现时间，再尝试 child pidfd。
首次失败保持父/child 停止，保留原 errno/cause；cleanup 在同一停止屏障复核并重试。
成功后纳入既有 owned、P_PIDFD 信号及真实回收路径。

持续失败的探针已在原生 amd64 Docker Linux 中通过默认与 SIGCHLD IGN 两例：
child 首停只消费 exact P_PID 的 WSTOPPED，GETSIGINFO 确认自动 SIGSTOP 后注入
SIGKILL，EXIT 停点只 CONT0；终局 WNOWAIT 保留，原父 pidfd 终止并回收后确认
child 被 subreaper 收养，再一次 exact WEXITED 真 reap，立即撤销数字等待权限。
stop-only ECHILD、ptrace ESRCH 或 /proc 消失均不能单独证明成功。
无关 caller 终局未消费，child marker 未执行，FD 与 subreaper 恢复。

driver 已接入该收容路径，仅实际 pidfd_open 两次失败才进入 cleanup-only。
新增两个合同方法，瞬态/持续 EMFILE、EPERM、ENOMEM 共 6 个 subtests 共享 caller，
验证三代脱组子树、IGN 自然父、终局保留顺序和真实回收；EMFILE 真实耗尽 FD，
EPERM/ENOMEM 为错误注入。GETEVENTMSG 损坏负例保留原 EPERM cause、
remaining_unfixed_children 与 cleanup_error，无终止信号或正常恢复；解除故障后
仅测试使用备用原父 pidfd 走真实 cleanup 救场。首个 child pidfd 尝试时不假定已
调度到 t，首停由实际内核结果核验。单条失败摘要保存首次/末次错误、次数与解决时间。

最终定向 21/21、5.856 秒，内部 5943 ms、入口 7056 ms、排队 202 ms，
Jobs 2、cache_hit=false；`.tmp-regression-docker-47da71708ce64f49afc479ae5da1412b/`。
集中完整 Docker 合同 47/47、exit 0，内部 312826 ms、入口 313767 ms，
排队 396 ms、Jobs 6、cache_hit=false；SSH 21/21、5.904 秒，preflight 同时通过，
`.tmp-regression-docker-1104d7af452047c7b20eb98dc48db095/`。
两个最终归档各 298 输入全部冻结匹配；随后本计划仅补结果。复用原工具镜像和三槽队列，
不因这一轮 elapsed 下降宣称普遍提速；没有重复完整回归。
已清理本阶段重复归档、清单和核对脚本 28632735 bytes，测试容器无残留；
结果、日志、输入核对和小探针保留在 `.tmp-ssh-unfixed-child-8c2m/`。

持续全进程 EMFILE 连身份读取也可能失败，未实测；此时保留未闭合 child 与
cleanup_error，不放宽身份检查。外部 SIGKILL/ESRCH 竞态仅主源及代码审查，
不宣称已实测；raw fork 57 正例、vfork 58 entry 负例继续下一阶段。
本步不开放任意 OpenSSH/unit、collector/jail 或菜单启停；5C 与总目标仍 active。

#### 5C.8c.2n 真实 fork 与 vfork 创建 ABI 合同

本阶段仅补真实 amd64 syscall 57 正例和 syscall 58 entry 拒绝负例，
driver 源码与创建授权不变。helper 新增 20 行、合同新增两个方法，共 23 方法。
raw fork 用 6 个显式零参数，在 exec 后 parent epoch 1 核实际 entry、FORK
事件、父返回与 child 首停的四段关联；accepted FD 同锚继承，master 0 /
child 23 均真实回收，不假设 child 首停的调度次序。
vfork 使用平台 libc 的安全入口，child 仅 _exit(23)，父 wait 后才写 marker；
baseline marker 为真，受控 nr58 entry 拒绝后 marker 为假，
无新 child event/pin 或拒绝后的正常恢复，原 master 真实回收。

独审、静态 C 编译、Python AST 与 diff 检查通过。定向 23/23、5.915 秒，
内部 6041 ms、入口 7010 ms、排队 200 ms、Jobs 2、cache_hit=false；
`.tmp-regression-docker-3a21c57f68a3417590403d97dfbf0a27/`。
集中完整 Docker 合同 47/47、exit 0，内部 302450 ms、入口 303396 ms，
排队 381 ms、Jobs 6、cache_hit=false；SSH 23/23、5.950 秒，preflight 同时通过，
`.tmp-regression-docker-169d5fe88acb43e7918b901bc8cdf8f5/`。
两个归档各 298 输入全部冻结匹配；结果补写后仅本计划更新。
复用原工具镜像与三槽队列，没有重复完整回归，不据单轮耗时宣称普遍提速。
已清理重复归档、清单与核对脚本 19037718 bytes，测试容器无残留；
日志、结果、输入核对与清理哈希保留在 `.tmp-ssh-creation-abi-8c2n/`。

本步不开放 vfork、任意 OpenSSH/unit 或 collector/jail；arm64、持续全进程
EMFILE、外部 SIGKILL/ESRCH 竞态、公网及宿主启停仍待验收，5C 与总目标 active。

#### 5C.8c.2o 真实 sshd 子树与受控 driver 兼容探针

本阶段只做固定隔离 fixture，不改生产 driver、source、ledger 或 journal。
复用原生 amd64 工具镜像
`sha256:0698b0ffcad3c265ab623b5bce0fcb9ef6cf9ed038811ba6b34162eee5d76f00`，
私有 cgroup、`network none`、无宿主挂载/Socket/PID；systemd unit 使用
`NotifyAccess=main` 将真实 `/usr/sbin/sshd` child 作为 MainPID，客户端先
绑定并保留源端口，认证失败后保持同一连接到 probe 完成创建和组改变核验。

2026-10-11 attempt1 通过，入口 16199 ms，linux/amd64；OpenSSH
`10.0p1-7+deb13u4`、systemd `257.13-1~deb13u1`、Paramiko `3.5.1-3`、
iproute2 `6.15.0-1`。真实 MainPID 109、tracer 108；unit invocation
`ae6f6fce230949898bd4eda965eaa122`，稳定 `unit_snapshot` 前后严格相同。
首代 shared LISTEN 冻结窗口仍被原 `unit_snapshot` 以唯一 owner 门禁拒绝，
没有放宽双 owner 或端口来源规则。

受控 driver 记录两个真实 `clone(56)`，flags `0x1200011`，entry/FORK/
返回 child PID/child 首停四段关联和 accepted FD 继承均通过；首代 child
实际执行 `setsid(112)`，随后进入 `/usr/lib/openssh/sshd-session` 与
`/usr/lib/openssh/sshd-auth`。session 保持 UID 0，auth 在退出停点降为
UID 996/GID 65534；两个后代 EXIT 时连接为 CLOSE_WAIT。真实失败认证产生
`Invalid user` 与 `Connection closed ... [preauth]` 诊断日志，均绑定同一
unit/invocation；日志不进入专用 Ledger，也不授权 collector/jail。

测试在两个后代真实退出且原 pidfd 确认回收后，才通过一次原 master pidfd
`SIGCONT` 取得稳定停点，再注入明确测试异常进入现有 cleanup。driver
`syscall_stop_count=2655`、FD `5 -> 5`、remaining 集合全空、
subreaper 恢复、ledger 消息为空；master、session、auth 均按原 pidfd 真回收，
前后 unit 清理终局为 inactive/dead 且无监听。probe 结果为
`verified=true`、`authoritative=false`、`jail_ready=false`。

小证据和复现源保留在 `.tmp-ssh-unit-driver-8c2o/attempt1/`，
9 个输入哈希全部匹配；阶段 runner 元数据中的 `changed_inputs` 已修正为空数组。
本探针不宣称任意 OpenSSH、多线程、arm64、collector/jail、公网或原生宿主
验收；下一步仍需按真实拒绝边界推进，不接入生产入口。

#### 5C.8c.2p 真实私有 syslog 与当前 Ledger 交接

本阶段继续保持四个生产模块冻结，在 8c.2o 的固定自建 unit/sshd fixture
中，仅由原 driver callback 新建 child 私有 mount namespace、私有 tmpfs
`/dev` 并将 `/dev/log` bind 到专用 receiver；receiver 权限 0600，开启
`SO_PASSCRED/SO_PASSPIDFD`，全局 `/dev/log` 不替换。原始 bytes 仅在导出
证据时编码为显式 hex，不改变正文验证或原 Ledger receive/drain/finish_stop。

2026-10-11 attempt1 首次通过，入口 16246 ms；复用 8c.2o 固定镜像，
linux/amd64、私有 cgroup、network none、无宿主挂载/Socket/PID。
真实 tracer 108、sshd MainPID 109、session 117、auth 124，
invocation `e9691d08dd21455480b4d68dcced7d52`；
`127.0.0.1:22220 <- 127.0.0.1:46823`，accepted inode 22707。
两次真实 clone、accepted 继承、setsid 和 session/auth EXEC 保持通过，
稳定 unit 前后严格相同，首代共享 LISTEN 原唯一 owner gate 仍拒绝。

6 条真实 OpenSSH syslog 中，3 条 session 原消息为 `Connection from`、
`Invalid user`、`Connection closed ... [preauth]`；同条 credentials 为
`[117,0,0]`，message/held pidfd 在入队和提交前后均指向原活 task，
绑定冻结 epoch 1、`/usr/lib/openssh/sshd-session` 与 fork accepted anchor。
3 条 master 消息全部以 `missing_accepted_anchor` 拒绝。session 原消息
在自身 EXIT 停点提交，原 drain 达 EAGAIN 后才 commit、terminal 与 CONT；
TCP 已为 CLOSE_WAIT，`owns_anchor_fd=true`、`live_socket_verified=false`，
不把历史 tuple 当当前 ESTABLISHED。本次没有实际跨 EXEC 的 pending 原消息，
该场景已有 8c.2d 证据，不将本次空 EXEC 提交扩展为新的跨 exe 实测。

两个后代自然退出 255，原 pidfd 确认真回收后取稳定 checkpoint；
外部使用启动后持续持有的原 master pidfd 发送 SIGTERM，driver 处理实际
signal-delivery/EXIT，master 自然退出 0、run 正常返回。Ledger closed 且
未 poisoned，3 条提交结果保留；2737 个 syscall 停点，FD `5 -> 5`，
subreaper 恢复，所有 remaining/open_received_fds 空，unit inactive/dead、
无 TCP LISTEN，容器按本阶段 label 查询无残留。

9 个源输入全部冻结匹配；小证据、raw-log 与复现源保留在
`.tmp-ssh-unit-driver-8c2p/`，没有重复未变生产源码的完整回归。
本步只验证固定单连接的可信原 driver/账本交接，持续保持
`authoritative=false`、`jail_ready=false`；不接生产入口、任意 PID、
collector/jail，不宣称 Failed publickey 文案、多线程、未知创建模型、
arm64、公网或原生宿主验收已完成。

#### 5C.8c.2q 真实运行态 tracer 异常退出与子树收养

本阶段保持 driver/source/ledger/journal 四源冻结，复用 8c.2p 工具镜像；
仅在固定私有 unit fixture 增加真实祖先 supervisor/subreaper。supervisor
自身 fork tracer，原 driver 自建 sshd master，再由真实 SSH 创建 session/auth。
unit 的 `NotifyAccess=main` 通知来自实际 ExecStart supervisor，
真实 MainPID 移交给 master；不修改生产授权、不 attach 外部 PID。

2026-10-11 attempt1 首次通过，入口 11890 ms，linux/amd64；
supervisor 107、tracer 108、master 109、session 116、auth 122，
invocation `909163e9b53246cca487ac8c196a34ae`。原 unit 两次稳定快照相同，
首代共享 LISTEN 仍被既有唯一 owner gate 拒绝。原 accepted
`127.0.0.1:22221 <- 127.0.0.1:36647`、inode 17489，
故障前 session/auth 为同一 ESTAB socket 的两个实际 owner。

supervisor 持续持有四个原 pidfd，在真实 auth EXEC 停点固定原代次，
释放后完成失败认证并保持客户端。两轮实际运行态采样中，三 tracee 均为
`S`、单线程、`TracerPid=108`、原 PID/net namespace 与 exe；session 已
`setsid`，auth UID 996/GID 65534。仅向 tracer 原 pidfd 发送一次 SIGKILL，
不先杀 tracee，不把 POLLIN 或 `systemctl stop` 当作回收证明。

依次对 tracer/auth/session/master 使用原 `P_PIDFD` 的 WEXITED|WNOWAIT，
终局均为 CLD_KILLED/SIGKILL；先保存实际 `Z`、PPid 107、TracerPid 0、
原 starttime 和可读 PID namespace，再精确消费同一终局。僵尸阶段 net/mnt
已释放，保留实际 ENOENT；回收后四个 pidfd 均 `Pid=-1`、原 `/proc` 消失。
最后一个原 task 回收距离发信号约 1.582 ms，外层无剩余 child，
FD `4 -> 4`、subreaper 恢复。tracer SIGKILL 未执行 Python finally，
仅保存真实 crash 前 checkpoint，不伪造正常 driver/Ledger 关闭证据；
checkpoint 中 1 条 session 消息仍 pending，不宣称崩溃后提交。

systemd 在后续 stop 前已为 inactive/dead、MainPID 0、invocation 清空，
原空 cgroup 已移除且无 TCP LISTEN；据实保存 ENOENT，不冒充读到空清单。
后续 stop 只清临时 unit，不计入原 task 回收。容器已删除，
manager 两条对原 MainPID 的 SIGKILL 日志均晚于四次真实回收，
首次晚约 5.017 ms，不能替代 EXITKILL/收养证明。
10 个源输入全部冻结匹配，小证据与复现源保留在
`.tmp-ssh-unit-driver-8c2q/`；没有重复未变生产源码的完整回归。

本阶段只证明固定自建 SSH 子树的运行态 EXITKILL 收容，不实现默认 SSH
服务恢复、持续 collector/jail 或任意 OpenSSH 兼容；运行态采样不是原子冻结。
公网、原生宿主、arm64、多线程及恢复仍待验收，5C 与总目标 active。

#### 5C.8c.2r 菜单与 CLI 的明确 unit 来源核验

将既有 `unit_witness` 接入只读生产入口：
`fail2ban ssh verify-unit <service> <本机 IP> <端口> <外部 IP>`，
Fail2ban 子菜单第 14 项与帮助同步，旧 `verify-source` 保持三参数入口。
两者复用地址/端口、Linux/root、宿主工具、随机 nonce 与 helper 门禁；
unit 名称在宿主前置前按既有正则和 255 字节上限拒绝，unit 模式额外需要
`systemctl`，薄 Python CLI 保留 Failure 返回码和取消/读取失败 15。

成功仅返回 `scope=ssh-unit-source-only`、`source_verified/unit_verified=true`，
`runtime_configuration_verified/jail_ready=false`。沿用 fresh challenge，
完整核对 MainPID、invocation/cgroup、两族唯一显式监听及 live accepted
代次，不保存证明、不取得部署锁，不启停宿主 sshd 或启用防护。
alias、socket activation、wildcard、额外监听、不可读 owner/cgroup、
服务代次变化仍按原 gate 拒绝，不接任意 PID 或持续 collector。

bundle 的安装入口与运行期两套完整性门禁都增加条件 journal 依赖；
缺模块矩阵逐项验证两套 gate，setup/release/phase6 的手工复制清单同步。
CLI 合同覆盖参数/长度/字符、缺工具、返回码、安装状态不变；菜单覆盖
成功、失败与四个字段取消，Python CLI 复用原 unit 合同并补输出/失败断言。
中英文说明与功能矩阵同步，SSH 完整防护与宿主验收状态不升级。

定向 `docker-ssh-preflight` 通过，source 20/20、journal 11/11、
Ledger 5/5 与客户端合同通过；内部 1132 ms、入口 2058 ms、排队 209 ms，
Jobs 2；`.tmp-regression-docker-30b8e8649c6b4e64b3ed3d6b0b800cbb/`。
菜单 PTY 定向通过，内部 53040 ms、入口 54015 ms、排队 198 ms、Jobs 2；
`.tmp-regression-docker-d9693f690bdb4c50b2bafec578b57c2e/`。
集中完整 Docker 合同 47/47、exit 0，内部 288681 ms、入口 289658 ms，
排队 384 ms、Jobs 6/占 2 槽、cache_hit=false；
`.tmp-regression-docker-d7ea2b3b6c864b88bf030f3c8d004192/`。

三个归档各 298 输入流式核对；定向归档仅缺随后补写的计划段落，
完整归档与当前实现全部匹配，结果补写后仅本计划更新。
复用工具镜像与三槽队列，无重复完整回归，不据单轮耗时宣称普遍提速。
重复归档/清单和核对脚本已清，小证据留 `.tmp-ssh-unit-cli-8c2r/`。
本次只验证菜单、CLI 与已有 unit 合同接入，未新做公网/原生宿主/arm64
的外部挑战；SSH 服务恢复、持续 collector/jail 仍待推进，总目标 active。

#### 5C.8c.2s 正常运行期已回收 task 的身份退役

本阶段处理短连接结束后两份 pidfd 与 Ledger registry 一直积累到 run
finally 的问题。仅在正常事件处理之后、下一次正常等待之前与空闲等待中
扫描，清理回收流程和创建事件首次固定 child 的屏障保持原合同。
扫描间隔 10 ms，真实 terminal wait 后立即扫描；不新增 wait 或数字 PID
回收，不以 EXIT 通知、POLLIN、ECHILD 或 proc 路径消失代替真正回收。

必须同时满足原 driver pidfd 与 Ledger held pidfd 明确 `Pid=-1`、
Ledger 已处理 EXIT、pending 为空，并且没有自身或父子方向未闭合的
creation、group、early、pending、unfixed 关联，才关闭两份原 FD，
移除 retired/registered/registry。历史消息、epoch、32 条总消息上限、
原 deadline 与 poison 对历史 accepted 的撤销保持原语义。

已退役身份不再占用数值 PID 登记位置；晚到旧消息仍须原 SCM_PIDFD
匹配当前代次，不能绑定新 task。扫描窗口内若新 FORK child 撞到尚未
释放的旧 retired 数值 PID，仍安全拒绝；不在首次 pin 前增加可能失败的
退役操作。该碰撞窗口的完整收容/回收未实测，可能留下 cleanup_error，
不能以本阶段声明任意 PID 复用时序均可继续。

一个集中合同覆盖 8 轮真实子代：原父 WNOWAIT 保留 zombie 时双原 FD
仍为原 PID，真 wait 后才退役；逐次核两 FD EBADF、registry/registered
删除、恒定 FD 数、退役早于下轮创建。terminal/pending、父子双向关系、
held 仍活与缺 Pid 字段均拒绝；晚到真实旧 SCM_PIDFD 在退役后拒绝，
模拟数值 PID 映射重新登记新代次后，旧真实 pidfd 触发 poison 并撤销
8 条既有 accepted 历史。该映射不是实际内核数值 PID 复用。

首轮 driver 合同暴露测试旧 event 字段过滤与限频扫描注入问题，已修复
测试，未放宽生产门禁或原 8 秒期限。重跑 `docker-ssh-driver` 24/24，
内部 6100 ms、入口 7044 ms；`.tmp-regression-docker-5b2cff61746d4d1bbc676fb789ddb175/`。
`docker-ssh-preflight` source 20/20、journal 11/11、Ledger 5/5 与客户端
合同通过，内部 1143 ms、入口 2107 ms；
`.tmp-regression-docker-82b0a620cd96477985201f741a409e68/`。均 Jobs 2，
复用工具镜像，失败原日志保留，不跳过原创建/ABI/故障合同。

真实固定 systemd/OpenSSH 3 轮短连接 attempt1 通过，入口 22485 ms；
复用镜像 `sha256:0698b0ffcad3c265ab623b5bce0fcb9ef6cf9ed038811ba6b34162eee5d76f00`，
Linux/amd64、断网、私有 cgroup、无宿主挂载，10 个输入容器内哈希匹配。
每轮两个子代真回收/退役，FD 完整清单均回到 6、registry/registered/owned
仅剩 live master，关联与附件为空。9 条 session 原消息保持原 epoch/锚点，
3 条无 accepted 锚点的 master 消息拒绝，总 12 条未重置 32 条预算。
轮间 expected_tuple 只在可信夹具的 master 真实停点切换到预绑定客户端，
不把该更新接口加入生产 driver 或扩大来源授权。
最后 master 原 pidfd SIGTERM 自然退出 0，六子代各 255；
最终 FD `5 → 5`、Ledger closed/unpoisoned、所有 remaining 为空，
systemd stop 后 inactive/dead、监听空，容器已删除。
复现源与小证据保留 `.tmp-ssh-unit-driver-8c2s/`。

首套集中完整合同 47/47 通过，内部 287207 ms、入口 288119 ms；
`.tmp-regression-docker-4093bd0eb439402ea734666da7d854d8/`。运行期间另一工作
拉入发布提交 `2a06a940`，仅 `shell/core/version.sh` 和 `versions.lock`
从 3.27.0 更新到 3.28.0；保留该提交，不把旧版本快照作为最终输入证明。
本阶段三个实现/测试文件未变，按输入变化规则在当前版本集中重跑，
复用工具镜像，不重复定向或真实探针。当前 3.28.0 快照完整合同仍为
47/47、exit 0，内部 296922 ms、入口 297854 ms、排队 388 ms，
Jobs 6/占 2 槽、cache_hit=false；
`.tmp-regression-docker-c8471d4f40b54864a2ed766c126a17ad/`。
回归前 298 文件流式哈希与工作区全匹配，结果补写后仅本计划更新；
实现/source/journal 和真实探针冻结输入未变。独审生产、测试及真实夹具
均无阻断，临时容器无残留；保留失败原日志、回归结果、哈希及真实探针
的小证据。本轮删除 10 个归档/清单，共 47789496 bytes。
本阶段不新增持续 collector/jail、宿主 SSH 服务恢复或任意 OpenSSH 兼容承诺。

#### 5C.8c.2t 保留旧身份的数字 PID 碰撞拒绝后收容

本阶段补齐 8c.2s 扫描窗口内的拒绝收容：首次固定 child 遇到仍保留的
retired 数字索引时抛专属 `RetiredIdentityCollision`，保存旧原 FD、
registry 对象、generation 与 terminal 快照。碰撞后只能进入 cleanup，
不尝试登记新代或继续正常运行；碰撞次数与真实 pidfd_open OSError 分开。
不扩大所有 Failure 的捕获范围，不改变 Ledger、消息预算、deadline 或 poison。

仅在旧对象/代次未变、terminal 为真、pending 为空、旧 driver 原 pidfd
明确 `Pid=-1`，且原父创建停止屏障仍完整时，复用未固定 child 的真实
首停、SIGKILL、WNOWAIT、父回收、收养 zombie 与精确 reap 流程。
旧 FD 仍活或证据变化立即拒绝并保留 cleanup_error/未决身份。
终局证据记录可用的最早清理身份，不把外部 SIGKILL 导致的首停失效
冒充已验证首停，也不因缺少 first_identity 字段中断终局清理。

集中合同使用真实连续两 child：旧 child 真回收并保留原 pidfd，
下一次真实 FORK 时仅把旧数字索引映射到新 child。两代 task、pidfd、
ptrace、wait、SIGKILL 与收养回收均真实；索引映射不是实际内核 PID 复用。
覆盖成功收容和旧 FD 尚指向活原 task 的拒绝；两者均保留无关 caller
的真实 SIGSTOP 等待状态，拒绝数字 PID/进程组发信号与泛化等待。
独立只读审查通过；`docker-ssh-driver` 25/25、exit 0，内部 6381 ms、
入口 7493 ms、Jobs 2、排队 5728 ms、cache_hit=false，复用原工具镜像；
`.tmp-regression-docker-5b07edca452349918b3d18f46cf72a45/`。
集中完整 Docker 合同 47/47、exit 0，内部 315492 ms、入口 316478 ms，
Jobs 6/占 2 槽、排队 482 ms、cache_hit=false；
`.tmp-regression-docker-6f393dbedac14cb88a79cada68cbaf69/`。
两个快照各 298 输入流式哈希核对，定向仅计划补写有差异，完整全匹配；
结果补写后只更新本计划。生产两文件保持独审冻结哈希。
本轮清理两个快照的重复归档/清单，共 19168944 bytes，小证据保留
`.tmp-ssh-collision-8c2t/`；未重跑未修改的真实 OpenSSH 探针。
真实内核数值 PID 复用、任意 OpenSSH、arm64、原生宿主和服务恢复
仍未验收，总目标 active。

后续按 collector/jail 接入、菜单管理、实际启停与封禁验收推进。
先定义一个可验收的有限支持合同，未支持的实例或日志来源明确拒绝，
复用已有 INPUT 所有权后端与 Fail2ban 管理流程；不再扩展原型枚举。

### 8c.3：有限 SSH collector/jail 与菜单管理

支持合同收敛到原生 Linux root、systemd/cgroup v2 下无存量会话且禁止 reload
的专用 OpenSSH service，MainPID 与唯一显式 TCP listener 固定。初始化
checkpoint 前后拒绝任何已有 child，防旧连接认证被归到新监听。只消费本次
启动后的可信密码失败；额外认证格式、socket activation、wildcard、多监听、
SSH/control INPUT 共存、历史日志和旧封禁数据库均不支持。

collector 每批前后复核 unit/监听及可信 journald 身份，规范 IP 单行输出；
root 0700 目录/0600 原子 guard、1 秒轮询、10 秒 TTL。runtime 通过随机
transient notify unit 启动，独立管理锁、执行路径权限、unit invocation、
Environment、实际 stdout 与日志路径核验；未知 owner 拒绝接管。
菜单 15–19 和 CLI 提供状态、解封、启用、停用与六参数编辑；普通服务和 jail
启动分离，spec/deployment/compose 摘要复核后 no-deps 启 jail。SSH 监督失效
正常停止 server、精确回收监督和睡眠子进程，按 token 清理 INPUT；
失败保留证据。未接的 update/rollback/业务恢复明确拒绝，先受管停用。

定向 `docker-ssh-preflight` 通过：来源 20、unit 11、Ledger 5、collector 7、
runtime 4，加配置合同、菜单 pipe/PTY 和监督失效/TERM/自然退出；
  最新入口 6182 ms，复用含 Fail2ban 的工具镜像。ownership 真实私有只读挂载
通过，入口 40873 ms；仅测试容器增加 SYS_ADMIN，不增加生产 capability。
隔离 amd64 systemd 257/OpenSSH 10.0p2/Fail2ban 1.1.0 实际启停、
真实失败认证到封禁、外部命名空间连接 DROP、解封、正常清理、新 token
重启及来源失效清理通过；证据 `.tmp-ssh-managed-8c3/`。
  集成后 `docker-contracts -Jobs 6` 的 47/47 通过，入口 353130 ms；
  证据 `.tmp-regression-docker-ce7d154952b8408fabf781d57e865f06/`。
  修复严格 Docker 夹具的第三 jail 查询与回滚当前部署夹具，保留原审计断言；
  之后裸安装入口补齐 runtime 模块门，`docker-phase1` 69197 ms 通过；
  Shell 语法及新增脚本 ShellCheck 通过，菜单与监督脚本修正后定向复验通过。
  本轮隔离验收容器已删除，日志与摘要保留，重复源码归档清理后不影响取证。
这是 Docker Desktop 内隔离 systemd/内核验收，不替代原生宿主、
arm64、公网、整机重启或完整卸载验收，总目标仍 active。

#### 5C.9a Hy2/TUIC 固定客户端与现有 UDP alias 前置

复用 `docker-entry-port-alias-real` 的唯一隔离 daemon、离线固定镜像、
客户端 netns、TCP/UDP origin；没有新增 selector、生产字段、菜单或宿主权限。
sing-box 1.14.2（amd64，image ID
`sha256:5fdff482ad9c65aa0e583a20e27d5f322b2539e673432e2cf78c7f460028fcb3`）
两协议单 `server_port` 基线均 check 成功；Hy2 的
`server_ports:["36461:36462"]` 成功，TUIC 明确拒绝 `unknown field "server_ports"`。
保留退出码、版本、镜像身份与原始诊断；不从 TUIC 原生 URI 范围推断 sing-box 支持。

生产生成 Hy2 单 inbound、双栈基础 UDP 端口 `35461`，两个已有 alias
`36461/36462` 发布到同一 inbound；核心按原 UID 10001、cap0、
只读根和只读证书挂载运行。固定两 alias 分别在 IPv4/IPv6 完成新 SOCKS
TCP/UDP 回显（4 TCP、4 UDP），正确 SAN/信任证书/SNI 均严格核验。
错误密码、错误 SNI、未信任 CA 在两族分别核对对应错误诊断，
12 个失败请求的 origin 新事件为 0。

范围客户端保持同一进程，首次成功回显后等待 5.1 秒，再完成一轮新 TCP/UDP
请求（两轮合计 4 TCP、4 UDP）。客户端 netns 的专有 mangle OUTPUT
链只计精确目的地址和两个 UDP 端口，输出整数包数与 `observed_both_ports`。
最终 IPv4 `20/4` 包、IPv6 `4/22` 包，两族均观察到两个目的端口；
前一快照 IPv4 `24/4`、IPv6 `26/0`，IPv6 未观察到第二端口，业务均成功。
计数不证明每次尝试成功、新 QUIC 握手或重新认证，
新 SOCKS socket 仍可能复用原 QUIC 会话；完整自动切换继续待验。

前置两次失败保留原始日志：check 接受 `hop_interval:"1s"`，
真正拨号要求至少 5 秒，实流量改用 `5s`；
随后 12 秒双端口硬断言中 IPv4 `73/73`、IPv6 `143/0`，
业务 24 轮仍全部成功，因此不再把短窗口未观察作为随机失败条件。
确定性检查精简为跨最小间隔的两轮请求，不延长采样或新增依赖。
失败证据 `.tmp-regression-docker-c5663ef9e3b44b7ba3500bcccebe88bd/`、
`.tmp-regression-docker-63d3e89045b94ff29d7ae2e6e8aab897/`。

最终 Linux amd64 定向内部/入口 18566/19633 ms、排队 193 ms、Jobs 2、
cache_hit=false，工具镜像及离线镜像归档直接复用；旧三阶段 alias 断言全部保持。
证据 `.tmp-regression-docker-fb123c3fdeea404095ccc90d3b920374/`；
前一快照 `.tmp-regression-docker-010eb8b51dfa42f3a555945cb82dade6/`。
两测试文件与最终快照一致，随后仅补验收文档。
Bash、ShellCheck error、Python AST 与独立只读复审通过；本次只扩展独立真实 selector 的测试，
生产代码及完整 53 项合同执行路径未变，沿用 5B.4k 集中完整证据。
成功重复输入清理后保留日志/结果及失败证据。
宿主 DNAT 双族归属、范围冲突、撤销/重建/重启/卸载、真实自动切换、
其它客户端、TUIC 范围能力、原生宿主/arm64/公网仍待验；
完整端口跳跃和协议管理保持 deferred，5C 与总目标 active。

#### 5C.9b Hy2 双栈 DNAT 到既有发布端口的启停前置

复用 5C.9a 唯一 daemon、固定 sing-box 1.14.2、受管 TLS/Hy2 服务、
已有双客户端 netns 和 TCP/UDP origin，不增加 selector 或工具。
仅在外层隔离 netns 的 iptables-nft/ip6tables-nft NAT 中，
按精确目的地址、两个 veth 的限定前缀和 UDP 范围 `36561:36562`
转发到已有宿主发布端口 `35461`。没有修改生产字段、菜单、schema 或权限。

随机 token/短链只用于本轮夹具，新增命令成功后记录精确逆序撤销项；
不 flush 共享链，注入独立外来 NAT 规则后保存两族完整 `-S` 正文。
启用和重建各要求严格 TLS 的 `4 TCP + 4 UDP` 回显及单业务容器来源；
撤销要求新客户端 origin 事件为 0，之后同一第二来源重建恢复 8 事件。
撤销使用此前无范围流量的第二来源，避免启用期旧 UDP tuple 干扰；
每阶段重启客户端避免 QUIC 会话复用。关闭与最后清理两次比较完整 NAT
规则正文，Docker 发布规则及模拟外来规则均保持。

DNAT 目标是已有宿主发布地址/端口，路径保留 daemon 默认 userland-proxy，
不证明再次遍历 Docker DNAT、直达业务容器或关闭 proxy 的路径可用。
内存逆序账本不是生产持久归属合同；范围冲突、旧会话/conntrack 撤销、
异常退出恢复、真实规则漂移、重启/卸载、TUIC 范围能力、自动跳跃、
原生宿主/arm64/公网和可信发布仍 deferred，总目标 active。
最终 Linux amd64 `docker-entry-port-alias-real -Jobs 2` 内部/入口
20890/21943 ms、排队 198 ms、exit 0、cache_hit=false，工具镜像和离线镜像直接复用；
证据 `.tmp-regression-docker-9e0c69bbea85410bb6c97c86146634a9/`。
阶段事件 `8/0/8`，最后撤销规则正文等于基线；旧 alias 三阶段、认证/SNI/CA
负面与 Hy2 客户端字段能力断言保持。成功 Python 文件与最终输入逐行一致，
Python AST、diff 和独立只读复审通过；仅扩展独立真实测试，
完整合同路径未变，沿用 5B.4l 的 53/53 证据，不重复跑全套。
早期成功输入 `.tmp-regression-docker-884f72e1ee70439681079a02114dba52/`、
`.tmp-regression-docker-e428f5a99ed640a6b8c4e32f1b56358d/` 保留日志和结果，
验收后清理本轮成功源码副本；未新增生产管理支持。

#### 5C.9c.1 跳跃范围的生产只读预检

net 镜像内部 `preflight port-hopping <start> <end> <target>` 复用现有
入口，先提供无写操作的范围合同；不接 CLI、菜单或规则启用。
端口必须为规范十进制 `1..65535`，范围不能倒置或包含目标。
检查 iptables-nft 两族完整 NAT、nft NAT 布局和全部宿主 UDP 套接字
（含已 connect 的 ESTAB）；已有 `port-hopping.state` 或未知跳跃链/
comment 均拒绝，不由同名资源推断归属。

转换规则覆盖单端口、闭区间及 multiport；两族重叠、端口/协议取反、
无端口范围、重复/未知选择器、工具失败或不完整输出均拒绝。
来源、地址和接口限制不授予共享范围；Docker 的接口取反不妨碍
独立非重叠端口证明。legacy NAT 共存、未验证原生 nft NAT 布局和
原生转换表达式继续拒绝；预检只是一时快照，写入前仍须锁与再次核验。

本轮 `docker-port-hopping-preflight -Jobs 2` 的 61 个只读合同通过，
内部/入口 `7016/8595 ms`；
`.tmp-regression-docker-8e84eae1e2c64f188ef1a3d840a126de/`。
真实双栈 selector 复用 5C.9b 的唯一 daemon/离线镜像，确认外来
IPv4/IPv6 转换与两族 UNCONN/ESTAB 套接字冲突被生产入口拒绝，
每次预检前后完整 NAT 正文相同；既有 `8/0/8` 流量证据保持。
同时验证双族原生 nft 转换拒绝并精确按 handle 移除本轮规则，
IPv4 legacy 共存拒绝且正文保持。Desktop 内核缺少 IPv6 legacy NAT
表（rc=3），不计该族真实证据，不加载宿主模块或扩大权限。
内部/入口 `24093/25470 ms`、排队见结果；
`.tmp-regression-docker-5cb8f5812e184571a3ccebc678a79944/`。
首次两份失败快照保留，原因是将 Docker `! -i` 错当端口取反；
已修根因并补合同，不删失败证据。
新增真实探针初次暴露 nft comment 引用及 IPv6 legacy 内核边界，
修正夹具并限定证据，相关失败快照继续保留。

新 selector 接完整与 fast-rest 集合；不为本子项重复构建工具镜像。
顺手删除 alias 合同中被覆盖且未读取的一次目录遍历/哈希，
原幂等、预览和失败恢复断言保持；不宣称已测得显著耗时收益。
`docker-entry-port-alias -Jobs 2` 内部/入口 `45851/46966 ms`；
`.tmp-regression-docker-3b3bba5f4bd34e8d82ca73769f7785c9/`。
持久归属、写入竞态、精确撤销、旧 conntrack、异常/重启/卸载及
自动跳跃继续待交付，完整端口跳跃/协议管理仍 deferred，总目标 active。

最终完整 `docker-contracts -Jobs 6` 的 54/54 叶子通过，
内部/入口 `586127/587215 ms`、排队 `45567 ms`、exit 0、cache_hit=false；
`.tmp-regression-docker-2fe7234e2e7b435c99f0e69938f3072a/`。
复用工具镜像，无重新构建；运行中单次采样 `625.99% CPU / 474.5 MiB`，
不是峰值，不用单轮时长变化证明稳定性能收益。完整输入与最终六个
实现/测试文件哈希一致，sh/Bash 语法、ShellCheck error、Python AST
和 diff 检查通过。菜单别名、CDN、XHTTP、区域输入及参数派发只读复核
未发现新的可复现缺陷，未追加无效改动或重复测试。
本轮成功归档仅清理 source.tar/files.list，日志、结果及失败输入保留。
独审发现 legacy-save 时间戳可能跨秒误报，改为去除生成注释后比较完整
规则正文；修复后真实 selector 内部/入口 `23238/24516 ms`、排队 `214 ms`，
`.tmp-regression-docker-8e4f2efc2dfc4914abd4b68f8b7872bf/` 通过。
该显式真实 selector 不在完整合同叶子内，其它完整输入未变，不重跑全套。
独审收口无阻断；本轮成功输入共清理 `84880131 bytes`。

#### 5C.9c.2a 持久归属审计与精确撤销前置

内部 `port-hopping-audit|port-hopping-health|port-hopping-clean <token>`
仅接受已有固定 state 和资源，不提供创建、启用、Compose 或菜单接口。
固定 `schema_version=1`、32 hex token、token 派生短链、规范端口、
IPv4/IPv6 字面目的地址及 intent/active 阶段；原始 ASCII 字节精确比较。
state 要求 root:root、0600、单硬链接、至多 512 bytes；拒绝链接、
重复/额外字段、NUL、不规范地址、范围倒置或包含目标。

双族固定资源为 PREROUTING 首位范围 hook、同目的/range 的 DNAT、
短链末位 token RETURN sentinel；只接受无资源、sentinel、DNAT+sentinel
或完整布局的中断子集。其它跳跃 owner、外来引用、额外/重复/错序规则、
无归属标记空链均拒绝。单端口范围按 iptables 规范输出匹配单个端口。
health 只要求 active state 和双族完整布局，不证明目标发布归属、
现时流量可达性、其它 nft/legacy 表或全部 UDP socket 无冲突。

clean 使用私有常驻 `.port-hopping.lock` 和非阻塞 flock；
每次写前重读原 state 的字节、inode/时间/大小及锁身份，再审计双族。
仅按 hook→DNAT→sentinel→链逐条精确删除，不 flush 或删除 conntrack。
仅当前进程刚删 sentinel 形成的空链允许继续撤销；删链失败时核验后
精确补回 sentinel，保留 state 可重试。跨进程同名空链仍拒绝，
SIGKILL 的删 sentinel→删链窗口不承诺自动恢复。

归属合同与范围预检共用已有 selector，不新增完整叶子或构建镜像；
真实双族探针由隔离夹具创建 state/规则，生产入口审计和撤销，
启用/关闭/重建要求既有 8/0/8 新连接路径，撤销正文等于外来基线。
生产写入启动、原子 intent/active 提交、信号恢复、候选 owned 预检、
目标发布见证、自动跳跃和菜单接入继续待实施；完整端口跳跃及协议
管理仍 deferred，总目标 active。预检/核验与内核写入存在非原子窗口，
不宣称抵御特权并发修改、整机重启持久性或旧会话排空。

定向 `docker-port-hopping-preflight -Jobs 2` 的 61 个范围预检与
126 个归属/撤销合同通过，内部/入口 `18976/20051 ms`；
`.tmp-regression-docker-cc1e5b521e6448649e1497c05c34f4f4/`。
覆盖 state/lock 字节和身份替换、元数据、规则漂移、双族部分残留、
无标记空链拒绝、删链失败 sentinel 补回重试及锁竞争；
首次失败是 IPv6 非首位 hook 夹具仍只有一个 hook，修正夹具，
`.tmp-regression-docker-942a5136825e4eeaa08a50bdd47cf122/` 失败输入保留。
独审发现单端口范围的 `-S` 规范化误拒，已修根因并补双族合同。
真实最终内部/入口 `21623/22767 ms`；
`.tmp-regression-docker-17ffb6e5a56f40ef9d69c22d2aff9581/`。
既有 TLS/认证拒绝及范围能力断言保持，audit/health/clean 均调用
本次生产代码，事件 8/0/8、两次撤销全 NAT 正文等于基线。
fixture 先写 active 再部分创建仅是夹具，不是生产事务证据；
ledger 故障兜底亦不计生产恢复支持。独立只读复审无剩余阻断。
随后完整 `docker-contracts -Jobs 6` 的 54/54 叶子通过，内部/入口
`483875/484875 ms`、排队 `388 ms`、exit 0、cache_hit=false；
`.tmp-regression-docker-1c43a574cf74428dbaaf03bf4fbc9d3e/`。
完整快照与四个关键实现/测试文件哈希一致，语法、ShellCheck error、
Python AST、diff 检查通过；成功源码副本清理 `12166732 bytes`。
批量 bundle 暂存优化 `19f68fd8` 已随本次完整快照验证，累计完整入口
从 `587215 ms` 降至 `484875 ms`，不把单轮采样当作稳定峰值证明。

#### 5C.9c.2b 启动事务与信号恢复

内部 `port-hopping <start> <end> <target> <ipv4> <ipv6>` 复用 2a 的
同一 Python body，预检/参数/state/audit/clean 不保留第二份实现。
持锁 Python 通过 exec 成为 PID 1；常驻 flock 且每次写前核对原 state、
lock 身份和双族资源。同参数旧 owner 先审计、精确撤销，再重新全域预检
并核对双族本地地址；参数变更在撤旧前拒绝，不提供在线迁移。

随机 token 的 intent/active 用 0600 临时文件写入、flush/fsync、身份复核、
原子 replace、预期字节与 inode/size 读回、刷新 baseline、目录 fsync 提交。
双族按链→RETURN sentinel→DNAT 首位→PREROUTING 首位 hook 创建，完整核验后
才提交 active。TERM/INT 只置标志，命令返回后记账，再统一精确清理；
恢复旧 owner 的审计期间收到 TERM 也先完成该已核验 owner 的撤销，不另建事务。

仅当前创建链或刚删除 sentinel 的进程允许继续处理无标记空链。
SIGKILL 在创建链→sentinel 或删除 sentinel→删链窗口仍需人工核对；
intent/active 的可核验残留可换 token 重建。state/lock 替换停止并保留证据，
不会将提交读回的未知 owner 认领为新 baseline；不 flush 或删除 conntrack。
原子文件提交不证明跨特权修改的原子性、整机断电持久恢复或旧会话排空。

现有 selector 保留 61 个范围预检、126 个归属合同，新增生命周期、八处 TERM、
两处 SIGKILL 重建、未知空链拒绝、参数冻结、锁竞争和 state/lock 替换；
原子提交额外覆盖 intent 创建/写入/fsync/replace、active replace/目录 fsync
和 replace 后同字节换 inode，故障只在测试包装器内注入，无生产开关。
真实 selector 用生产 run 替代手写规则，仍要求新连接事件 8/0/8、完整 NAT
正文等于外来基线；额外检查 SIGKILL 换 token、旧链消失及 PID 1 docker stop
退出 0、state 消失。复用离线 net 镜像并只读挂载当前入口，无生产权限新增。

初轮合同/真实失败来自恢复探针误读旧 active 的等待竞态，已改为等待新 token；
后续真实验证通过全部业务断言，但清理遇到 daemon 的 netns 残留挂载。
复用已有测试的限定目录卸载方式，保留失败输入，不扩大清理范围。
真实最终内部/入口 `24052/25100 ms`、Jobs 2、exit 0，证据
`.tmp-regression-docker-41938d654e5e490194b6bd3d35d165b5/`。
169 个归属/生命周期/文件故障合同与 61 个预检通过，内部/入口
`54019/55038 ms`；`.tmp-regression-docker-460a5b36d670462ba61ec091785471ab/`。
随后补恢复审计期间 TERM 的 active/partial intent 两个合同并修早退，
最终 61+171 定向内部/入口 `56985/58013 ms`，Jobs 2、exit 0；
`.tmp-regression-docker-7f129a83c9954f7a9ac1e175dc3408df/`。
集中完整 54/54 内部/入口 `505260/506319 ms`、排队 `388 ms`、
Jobs 6、exit 0、cache_hit=false；
`.tmp-regression-docker-917ae3b3c3ca4ff5918124f7febec88e/`。
五个关键实现/测试文件与完整输入哈希一致；容器 sh/Bash、ShellCheck error、
Python AST、PowerShell 解析及 diff 通过，独立复审收口。
单次资源采样 `610.15% CPU / 363.2 MiB` 不是峰值；新增合同增加约 21 秒
完整耗时，暂不宣称新的稳定性能收益。本轮工具镜像未重建。
成功 source.tar/files.list 与核对副本清理，日志/result 与失败输入保留。

五参数仅为内部实验 tuple，尚无受管 listener/core/protocol、实际 container/image、
UDP PortBindings 和配置账号的可信发布见证。不接菜单、Compose/schema，
不授予生产 Docker socket；完整端口跳跃与协议管理仍 deferred，总目标 active。
后续 5C.9c.3 先补受管目标发布的只读核验，再设计受管启停与菜单事务。

#### 5C.9c.3a 受管目标配置与发布快照

本子项实现内部只读 `dockerPortHoppingTargetWitness`，不接 CLI、菜单、
Compose/schema 或生产 run 的启用门禁。只接受 v3 已有双族 Hy2/sing-box
listener 与规范本地 IPv4/IPv6；目标端口来自规格，不允许另传任意端口。
本机 rootful daemon、完整规格/部署/Compose/镜像记录、完整账号输入与
按当前累计/额度渲染的运行配置必须一致；选中入站仍有启用账号才可返回。
实际容器的健康、固定身份、镜像、标准命令、权限、挂载、UDP 发布和桥接
网络按既有受管合同核对，关键文件与容器前后快照漂移拒绝。

返回固定身份与端口/地址、启用账号数量，不输出账号标识或密码。
这是配置文件与实际发布的诊断快照，不证明进程已加载同版本配置、
所有禁用账号在内存撤销、可达性或可信发布；后续受管启停门控前仍需
启动配置版本绑定。真实标准部署的独立验收见 3b。目标函数不写受管文件、锁或 state，
不执行 Docker exec/启停，不给 net 服务新增 Docker socket。
独立 `docker-port-hopping-target` 定向入口避免重复旧生命周期；
完整集合仍由原端口跳跃叶子调用一次，保持 54 项并发/队列预算不变。
复审修复完整配置与流量状态进入 `jq` argv 的凭据暴露，改用
进程替代/管道读取；共享渲染器保持单对象状态合同。补密码与账号 argv
守卫，不将完整账号或密码输出。文件快照后重新检查全部支持条件，
避免同端口/域名完整切换到单族仍返回双族见证；确定性切换夹具要求拒绝。
祖先目录只冻结路径身份和权限，不冻结随其它测试创建目录变化的链接数。
有限核对 Hy2 首配、参数、复制与站点派发，未发现可确认菜单缺陷。

修复后的 `docker-port-hopping-target -Jobs 2` 46 个只读合同通过，
内部/入口 `8040/9050 ms`；`.tmp-regression-docker-0b6fbc8bdbd544dcaa7e7bc1853abde1/`。
共享 `docker-traffic -Jobs 2` 内部/入口 `3820/4863 ms`；
`.tmp-regression-docker-07ec23fbe18e4a21aff2bf6ee54389e6/`。
不改变支持矩阵或整体 deferred 状态；集中完整验收已通过，见 3b。

#### 5C.9c.3b 标准真实部署只读验收

独立 `docker-port-hopping-target-real` 仅离线传入已有 sing-box 镜像，
在私有 daemon 与 `/n` 本轮目录生成完整规格、账号、额度渲染配置、
Compose、部署和镜像环境。标准用户、命令、健康检查与目录挂载
不通过 service override 改写，生产只读函数核对真实健康容器。
重启后同容器返回新的启动代次；磁盘账号漂移拒绝，见证前后受管树
内容和元数据不变。复用既有 namespace/daemon helper，仅清理本轮
私有目录下的残留挂载，容器删除失败也继续私有目录清理。
该显式真实 selector 不进入普通 54 叶子集合，不重复旧客户端矩阵。

初轮标准真实内部/入口 `15711/16755 ms` 通过，
`.tmp-regression-docker-03a5bdc4c1cb47ada0035b39fdb39207/`；
其后作用域、共享渲染器和清理收口的最终真实内部/入口
`15492/16542 ms` 通过，Jobs 2；
`.tmp-regression-docker-7d78865f0b5744908b870452097e67f8/`。
集中完整 54/54 内部/入口 `532595/533647 ms`、排队 `392 ms`，
Jobs 6、exit 0、cache_hit=false；
`.tmp-regression-docker-025fcfbd9d6348c5ad6486290291a4e3/`。
容器 Bash、ShellCheck error、Python AST、宿主 PowerShell AST 和 diff 通过；
本轮静态临时文件已清理，完整回归日志和结果保留。总耗时未达到五分钟，
不通过扩大三槽预算缩短耗时。
它只证明标准配置与发布诊断路径，不证明配置加载版本绑定、账号内存
撤销、可达或完整自动跳跃。后续 3c 继续启动配置版本绑定，再设计
受管启停/菜单事务；整体目标仍 active。

#### 5C.9c.3c 启动后文件改动拒绝

保留 3a 的只读诊断 `dockerPortHoppingTargetWitness`，新增独立
`dockerPortHoppingTargetStartupWitness`，共用同一个实现及完整双轮固定容器、
镜像、网络和文件快照。只将运行配置 `config/sing-box/config.json` 与所选
TLS crt/key 的 `mtime_ns`、`ctime_ns` 同固定容器 `StartedAt` 比较，纳秒解析
不经过浮点数；恢复旧修改时间、同字节替换及无效日期拒绝。
流量 state、目录和锁的正常后续变化不适用启动时间限制；见证期间漂移仍拒绝。

这是更严格的文件诊断，不是加载版本绑定或生产启用门控。墙钟回退、
启动前父目录替换后容器仍引用旧 bind 目录、进程先读入旧文件等情形未由
时间比较证明。不给生产 net 服务新增 socket、schema、菜单或 Compose 开关。
后续受管启停需在已有部署锁内整合一次流量采集/额度重渲染、启动前快照、
新容器强制启动、健康与固定身份、相同文件快照，再继续启用事务；
不能靠跨事务成功标记或单独 recreate 绕过流量保留。

定向新增纳秒边界、恢复旧 mtime 的完整账号更新、TLS crt/key 同字节替换、
固定启动代次与正常累计/目录变更，共 62 个只读合同通过，内部/入口
`12294/13360 ms`、Jobs 2；
`.tmp-regression-docker-c1a7337694674bb38a78f0067f855109/`。
初轮失败仅新增流量夹具将无限额度写成 null，按现有合同改为 0，保留失败证据
`.tmp-regression-docker-d2de3fb82fd54523b65bed1eb810b979/`。
标准真实验收内部/入口 `28232/29391 ms`，Jobs 2；
`.tmp-regression-docker-132b6f65bc084293b9cc32ea442b7c36/`。
覆盖双族旧/新密码认证反转、恢复旧 mtime 的配置更新拒绝、
crt/key 同字节替换拒绝、重启后恢复、正常 traffic state 更新和全树只读；
最终定向含 Bash、ShellCheck error 与 Python AST，62 合同内部/入口
`17906/19179 ms`；`.tmp-regression-docker-994fd000e5f84f5187e324f6d3e58725/`。
集中完整 54/54 内部/入口 `519459/520506 ms`、排队 `230415 ms`，
Jobs 6、exit 0、cache_hit=false；
`.tmp-regression-docker-f4f28a076c3046e997e3925d2545e888/`。
四个关键实现/测试/入口文件与完整输入一致（仅规范化 CRLF 比较），
PowerShell AST、diff 及独立复审通过。静态临时文件和成功输入已清理，
日志/result 与失败输入保留；完整跳跃/协议管理仍 deferred，总目标 active。

#### 5C.9c.3c.1 公共规格前置校验提速

`dockerConfigureSpecValidate` 合并 JSON 语法与单对象形状的两次 jq 启动，
每次仍完整解析 schema、matrix、spec，不缓存成功或删减完整语义与控制/SSH
下游校验。形状 false 保留原单对象诊断；读取或语法失败仍优先 JSON 诊断。
已有 XHTTP validation 新增 4 个形状、4 个语法与语法优先共 9 个拒绝边界，
核对退出码 1、空 stdout 和精确 stderr，保持原有效规格和协议语义矩阵。

同容器同材料、各 100 次按 old/new/new/old 的 A/B，中位耗时
`381.2175 -> 240.4935 ms`，jq 启动 `200 -> 100`，只证明该前置约减少 37%，
不推算全套收益。输入摘要、样本与 9 边界通过证据：
`.tmp-regression-docker-eda4520f31e147179180787b0c9b34f4/`，
内部/入口 `5793/7079 ms`；计时代码取得证据后删除。
6 种传统 TLS 的定向验证内部/入口 `195718/196927 ms`，Jobs 2，
`.tmp-regression-docker-ac296344a6e547dcb48225fe195fcc00/`。
此混跑耗时不用于前后性能比较。删除计时代码后集中完整 54/54，
内部/入口 `530229/531402 ms`、排队 `228323 ms`、Jobs 6、
exit 0、cache_hit=false；
`.tmp-regression-docker-7070fe0301884d9f94e1ed8dd210ca09/`。
services/xhttp 两实现文件与本次输入原始字节 SHA256 一致，静态与独立复审通过。
单次资源采样 `523.37% CPU / 229.5 MiB` 不是峰值；全套未形成可确认提速，
仍约 8.9 分钟，维持三槽预算，不扩大并发或宣称五分钟目标完成。
本轮成功输入累计清理 `98,133,520 bytes`；日志/result、输入哈希及失败证据保留。
支持范围不变，3d 与整体计划继续待实施。

#### 5C.9c.3d 受管启动事务，内部入口已交付

首个内部入口限已持有部署锁的当前 Bash 进程、健康单 sing-box 与已有双族
Hy2，不接 CLI、菜单、schema 或 net 服务。固定 root、lock 目录、pid 文件的
路径、dev/inode、权限与 owner；采集后、文件切换前、Compose 前、提交和恢复
均复验，锁身份变化即保留证据。只检查 pid 内容不构成同一锁的证明。

直接严格 `dockerTrafficSnapshot sing-box`；确认未提交新累计的采集失败
不改运行配置或执行 Compose，已经原子提交时按下文安全恢复。
现有 `dockerTrafficBeforeChange` 吞采集失败且总返回 0，不能用于此门控。
生成与核对 baseline 一次，读取新累计 state 并渲染一次、验证候选；正常路径
仅一次受管 `up -d --force-recreate --no-deps --wait … sing-box`，
不先 ApplyQuotas 再额外 restart/recreate。启动前后固定文件版本、
新容器代次和健康身份，成功后仍持同一锁继续后续启用，不留跨事务成功标记。

恢复保留新累计；若本次已撤销超额账号，不能重启会重新启用该账号的旧配置。
Compose 一旦开始就按 runtime 可能变化处理，即使 CLI 失败；旧 CID 可能消失，
不能仅按旧 CID restart。INT/TERM 停止推进并在同锁内执行受限恢复，
恢复失败或状态不明保留备份与证据；SIGKILL、非合作替换和 daemon 异步变化
不宣称自动崩溃恢复。实现时补采集失败、刚跨额度、一次渲染/正常重建、
锁替换、文件/健康/启动失败、信号及恢复失败合同与标准真实新连接验收。

采集已提交后、候选校验或文件切换前失败，也要处理旧运行进程仍启用刚超额
账号的窗口；不能只删候选后返回。恢复不能启动会重新启用该账号的旧配置。
若不能验证并加载保留新累计的安全配置，应在同锁内核对受管服务身份并受限
停止，保留备份和证据；停止状态不明不能宣称已撤销。信号可能打断采集的
原子 state 提交，须复验实际状态，不能只按 Snapshot 返回码决定恢复旧状态。
锁身份漂移后还要阻止调用方退出清理仅按 pid 内容释放替换锁；事务自己不调用
释放入口并不能覆盖外层清理，必须保留替换锁及失败证据。
`dockerComposeExecute up` 会附加 `--remove-orphans`，首版还须拒绝同项目未纳入
受管 Compose 的非 oneoff 容器；`--no-deps sing-box` 不能单独证明外围服务不变。
候选与旧运行 JSON 语义不同则保守按额度撤销处理，只复用已验证的候选字节
作恢复目标；旧备份仅留证据，新累计 state 永不回退。正常只有一次重建，
失败恢复的额外重建单列预算并复验当前归属，不能按可能已经消失的旧 CID 重启。

##### 5C.9c.3d.1 只读锁身份前置

新增内部 `dockerPortHoppingTargetLockedWitness`，仅直接在当前持部署锁的
Bash 进程调用；在已有 startup 见证前后取得 `dockerPortHoppingTargetLockSnapshot`，
两次一致才输出原见证 JSON。逐级从 `/` 以 `O_NOFOLLOW` 和目录 fd 打开，
固定祖先、root、locks、deployment.lock 的 dev/inode/mode/uid/gid；
三个受管目录要求当前 owner、0750，pid 要求普通单链接、当前 owner、0640、
精确当前 BASHPID 加换行，并核对大小与纳秒 mtime/ctime。两轮保留已打开 fd，
拒绝替换，不释放或重写锁。目录 mtime/ctime 不作身份依据。

拒绝非规范路径与双前导斜杠，FIFO、符号/硬链接、错误 owner/权限/pid、
子 shell 与外层命令替换冒用，以及见证期间同内容 pid、锁目录和 locks
父目录的 inode 替换。已有 62 个只读合同加锁场景共 86 个父进程场景通过，
另有子 shell、命令替换和双斜杠的拒绝断言，Jobs 2，内部/入口
`32443/33901 ms`；`.tmp-regression-docker-7e226e843793492eb7352cce120ef2b9/`。
标准私有 daemon 真实验收复用原认证反转矩阵，新增同一 Bash 获取锁后
见证前后全树只读、随后释放锁；内部/入口 `29645/30941 ms`，Jobs 2，
`.tmp-regression-docker-8527c36c2f714a3a91c01efc9bb3f6d8/`。
集中完整 Docker 合同 54/54，内部/入口 `538256/539371 ms`，排队 `202755 ms`，
Jobs 6、exit 0、cache_hit=false；
`.tmp-regression-docker-b104450eff22468fa1679a569f39324f/`。
三个实现/测试文件与完整源码快照原始字节 SHA256 一致，静态与独立复审通过。
清理本轮成功源码归档 `36,802,560 bytes`，保留日志、文件清单和 result；
全套仍约 9 分钟，不宣称提速或扩大三槽预算。

只约束本次见证读到的身份，不证明获取锁前至释放锁后的完整生命周期，
不抵御非合作进程中途换出又换回，不接生产启用门控，也不证明内存或挂载
内容一致。完整采集、一次渲染/重建、额度安全恢复和信号事务继续待实施；
3d 及整体计划仍 active。

##### 5C.9c.3d.2 严格采集与额度安全启动

内部 `dockerPortHoppingTargetStartManaged` 仅由当前持锁 Bash 直接调用；
已有 `data/traffic` 目录、健康单 sing-box、单个双族 Hy2 入口、无宿主集成及其它
项目容器。生成器默认未运行的 ACME profile 允许保留；额外服务、oneoff、
同项目孤儿先拒绝，避免 `up --remove-orphans` 扩大影响。未接 CLI、菜单、
schema 或 net 自动启用，不接受外层命令替换冒用锁。

复用只读见证，将文件快照提取为同一 helper；目录固定 dev/inode/mode/owner，
文件另含 nlink、纳秒 mtime/ctime 和摘要，避免 stage/query 合法创建影响目录
链接数。生成 baseline 与初始账号配置一次；严格 `dockerTrafficSnapshot sing-box`
后复验初始 CID/StartedAt，读取新 state 一次、渲染安全候选一次并核对 state
对应版本。候选放受管核心目录外，验证时挂载到已有只读 `config.json` 路径，
不在只读目录新建挂载点。复制前后校验候选摘要及内容，原子切换后复验。
正常仅一次 `up -d --force-recreate --no-deps --wait … sing-box`；
后置见证复用已验证 baseline/候选，要求新 CID、StartedAt 和相同目标/镜像。

已提交累计永不回退；采集返回非 0 或信号也按实际 state 决定恢复。
候选未验证、无启用账号、输入或 state 漂移时核对受管核心身份后受限停止；
验证通过后失败只恢复安全候选字节，旧 live 留证据，不能重新启用超额账号。
Compose 开始即按旧 CID 可能已删除处理；恢复失败核对当前归属尝试停止，
daemon 或停止不明保留证据，不声称已撤销。停止前固定身份复验排除正常健康
日志 tick。INT/TERM 停止原流程推进、同锁恢复后还原调用方 trap；
锁漂移清本 Bash 的释放入口变量，避免外层按相同 pid 删除替换锁。

36 个事务合同覆盖采集/读/渲染/验证失败、提交后返回失败、刚跨额度、
全部超额、锁/spec/TLS/state/live/候选漂移、未实际重建、健康 tick、
已删旧 CID 的启动/恢复失败、7 个 INT/TERM 边界及 trap 还原。
正常断言 Generate 1、Render 2、Read 3、Query/Write/Validate/Up 各 1；
计入初始见证，新增累计与候选仅各处理一次。结合既有 86 个身份场景，
定向内部/入口 `43883/45062 ms`、Jobs 2：
`.tmp-regression-docker-86a2a50a5e1c4e2c9cb7182e0ea7ad82/`。
标准私有 daemon 两族新客户端均先成功；采集跨 Alice 额度后仅 self
能新建连接；真实发布完成后注入非 0，安全恢复仍拒绝 Alice 且累计不减。
内部/入口 `55959/56983 ms`、Jobs 2：
`.tmp-regression-docker-f88fa83ee6404cdaa4509bf97efef475/`。
同时消除 Snapshot 账号对象中的主认证 UUID 经 jq argv 外泄，改用 slurpfile；
累计算法保持原样，事务合同有 argv 守卫。

最终材料合同补默认 ACME profile 正例、额外服务/多入口拒绝、后验不重新
读取累计或生成/渲染、候选漂移、缺少累计目录及命令替换冒用拒绝。
最终定向内部/入口 `46016/47061 ms`、Jobs 2、exit 0、cache_hit=false：
`.tmp-regression-docker-34a67b75852741a89f755d20fcddd21f/`。
集中完整 Docker 合同 54/54，内部/入口 `544423/545488 ms`、排队 `394 ms`、
Jobs 6、exit 0、cache_hit=false：
`.tmp-regression-docker-3b8e6590e6f6431b8dd975ed9170de4d/`。
七个实现/测试/回归入口文件与完整快照原始字节 SHA256 一致，
语法、ShellCheck error、Python AST、diff 及独立只读复审通过。
本轮成功源码归档及核对副本清理 `62,214,216 bytes`，日志、文件清单、
result 和失败输入保留；复用工具镜像，全套仍约 9 分钟，不宣称稳定提速。

不保证非合作进程中途替换再换回、SIGKILL、墙钟回退或全锁生命周期，
不证明全部 worker 内存或旧会话排空。首次统计目录初始化、其它服务集成、
原生宿主/arm64、公网、重启/卸载、真实自动跳跃及 TUIC 范围仍 deferred；
完整 net 启用门控及菜单/schema 是下一步，整体计划保持 active。

##### 5C.9c.3e.1 同锁启用准备

内部 `dockerPortHoppingTargetPrepareActivation listener start end ipv4 ipv6`
冻结当前 Bash 的部署锁及输入身份，只从唯一受管双族 Hy2 listener 推导目标，
调用者不能传入 target 或见证。范围必须是规范十进制 `1..65535`、正序且不含目标；
错误 listener、单族、非规范地址或范围在采集、写累计、Compose 及 stage 创建前拒绝。
既有统计目录、健康单 sing-box、无宿主集成及其它项目容器的限制沿用 3d.2。

使用重定向直接调用 StartManaged 一次，避免命令替换冒用父进程锁。
成功后轻量复验锁、spec/baseline/deployment/images.env/Compose/TLS 及目录身份，
精确检查 CID、StartedAt、Image、RestartCount 和 healthy，再执行
`FileSnapshot(domain, StartedAt)`。live/state 允许随启动更新，不要求等于初始版本；
不再调用 LockedWitness/StartupWitness 或重复 Generate/ReadState/Render。
诊断仅增加 `range_start/range_end`；失败 stdout 为空，130/143 原样传播，
还原调用方 trap，保留证据及已提交累计，锁漂移阻止通用 Release 删除外来锁。
账号数只反映本次启动采用的额度版本，允许后续 state 更新不等于已经重新应用
限制；该诊断不能证明输出时全部账号仍满足最新额度。

38 个准备合同覆盖规范范围、非法输入零启动/采集/重建、一次调用、后置锁/输入/
权限/容器代次/健康漂移、state 合法变化、内层失败与信号原样传播及 trap 还原。
另补启动成功清理节点 INT/TERM 合同，原事务合计 38 场景，修复此前忽略信号后
仍可能成功返回的问题；失败恢复期间仍忽略后续信号以完成受限恢复。
集中完整 54/54 无重复或遗漏，内部/入口 `521278/522353 ms`，Jobs 6，
排队 `218328 ms`、exit 0、cache_hit=false：
`.tmp-regression-docker-6b5e18288cfb49959939648d86e9f2a1/`。
七个关键实现/测试/入口文件 SHA256 与本次快照一致。
最终真实双族准备、跨额度撤销、安全恢复、NAT 正文和 jumpstate 不变通过，
内部/入口 `61253/62765 ms`、Jobs 2：
`.tmp-regression-docker-5f32558f8fc24616970021a72c31bee6/`。
独立只读复审及语法/ShellCheck error/Python AST/diff 通过。
完整合同中长耗时跳跃分片从第 35 位前移至第 16 位，数量仍为 54，并发不变；
本轮入口较上轮减少 `23135 ms`（约 4.2%），测试内容亦变化，不宣称稳定提速。
本轮七份成功 source.tar 清理 `86,446,080 bytes`，保留日志、清单和 result。

本阶段不调用 net run、不写 jumpstate/NAT，不证明 UDP 范围当前空闲。
3e.2 再实现实时单次父子交接、net 锁及前后全域冲突预检；静态 JSON、
环境变量及旧五参数 tuple 都不能授权写规则。菜单/schema/Compose 自动启用、
原生宿主/arm64、公网、旧会话排空等继续 deferred，整体目标 active。

##### 5C.9c.3e.2a 实验 net 启动前后冲突复验

复用既有 `port_hopping_resources(run)` 的 net flock 和归属审计，抽出共用
`conflicts(start,end,owned)`。初始 preflight 仍拒绝已有 state 并检查完整资源；
两族规则写成后，在 active 原子提交前和提交后各执行一次全域冲突检查。
owned 模式对同一份两族 NAT `-S` 快照先 audit，必须所有自有资源完整，
再逐行精确扣除 `["-N",chain]` 及已核验的三条 rules；其余正文保留。
继续使用原 nft/legacy NAT/UDP 监听检查，不按 chain/comment 前缀宽泛豁免；
当前 iptables-nft 自产 xt DNAT 表示可接受，其它未核表示仍拒绝。
末尾复验 owner/完整资源。删除重复的提交后 health 扫描，独立 health 命令不变。

冲突检查仅用于启动门控，不放入 audit/write/clean；外来冲突出现后，
finally 仍只按精确归属清理自有资源，外来规则保留。锁被替换时拒绝继续清理，
保留原 state、两族规则及替换锁供人工核对，不能宣称已经撤销。
12 个新增合同在最后规则写入或 active 真实原子提交之后注入两族外来 DNAT、
UDP 占用、nft 布局变化、读取失败和锁替换；注入前核验完整自有库存，
拒绝后核对外来正文、state/规则回收或替换锁 dev/inode 保留。
测试就绪等待本次提交后复验，不再凭暂态 active 文件与只读断言并发。

最终定向 61 个只读预检、183 个归属/清理/生命周期场景、86 个锁身份及材料、
38 个启动事务和 38 个准备场景通过，内部/入口 `172812/174060 ms`、Jobs 2：
`.tmp-regression-docker-a4a9a7b29d5f4aa78fd133bf37fabf48/`。
标准真实双族跳跃、撤销、kill-recovery、PID 1 清理与外来 NAT 保留通过，
内部/入口 `25981/27071 ms`、Jobs 2：
`.tmp-regression-docker-796a845a512c4f0391ac0676ebeb9a15/`。
集中完整 54/54 无重复遗漏，内部/入口 `543044/544148 ms`、Jobs 6，
排队 `613 ms`、exit 0、cache_hit=false：
`.tmp-regression-docker-2c53f3226ade402f879d60c65cc4786d/`。
两份关键源码原始字节 SHA256 与最终定向、真实和完整输入一致；
独立只读复审及 diff 通过。三份成功 source.tar 清理 `37,109,760 bytes`，
保留日志、清单、result 和失败输入；完整回归约 9 分钟，未证稳定提速。

本阶段仍是旧五参数实验入口，不能据此生产启用。net flock 不排斥非合作写入，
前后检查不能证明全域原子范围预留；active 文件可能先于后验拒绝暂时出现，
最终实时 ACK 必须等全部门控通过。实时父子交接须绑定当前父锁、本轮子容器、
StartManaged 实际采用的 state/live 精确版本，不能把 3e.1 诊断 JSON 加 nonce
当写授权。菜单/schema/Compose、生产 Docker socket 及整体对齐继续 deferred。

##### 5C.9c.3e.2b.1 启动版本受限诊断出口

StartManaged 只接受原三参数或固定第四参数 `bound`，PrepareActivation 只接受
原五参数或固定第六参数 `bound`；其它模式或额外参数在采集前拒绝。
普通路径保持允许后续累计变化的诊断合同。bound 路径在启动成功、清理 stage 前，
从实际渲染/安装采用的 `ph_files/ph_stateFile/ph_live/ph_lock` 构造 startup_binding，
只返回路径身份、元数据及摘要；不输出账号、密码或配置正文，不重读累计或渲染。

清理前后复用 BindingCheck，严格比对原固定输入、state/live 和部署锁；
流量目录必须 0700，固定 CID/Image/StartedAt/RestartCount 与 healthy，
容器检查前后文件快照一致。同字节替换仍因 inode/ctime 漂移拒绝；
准备层也在内层返回后、清理前后使用原绑定复验，不能刷新为新基线。
成功后的绑定拒绝不进入原启动失败恢复，不额外 recreate 或回退累计。
清理前失败保留已有 stage；清理后失败只保留诊断与当前受管状态，
不能承诺已经删除的 stage 仍有完整材料。INT/TERM 返回 130/143，失败 stdout 为空。

定向先通过 43 个绑定场景、86 个锁身份及材料、38 个启动和38个准备场景，
内部/入口 `129904/131389 ms`、Jobs 2：
`.tmp-regression-docker-4c91cbf759df46e5bc50411e52f5daee/`。
初轮仅新增夹具错误要求 live 快照为单行，实际含完整元数据和目录遍历条目，
修正断言后通过；失败输入留在
`.tmp-regression-docker-476772880d5945f480c85ccdae722b52/`。
随后去掉重复跨阶段组合，保留正常/额度、非法模式、state/live 同字节替换、
检查期间漂移、清理前后锁/固定输入/权限/容器/健康及 INT/TERM，最终 27 场景。
标准真实 bound 准备的 state/live 完整元数据及摘要与磁盘一致，
双族刚跨额度撤销、失败安全恢复、NAT/jumpstate 不变通过，
内部/入口 `62974/64342 ms`、Jobs 2：
`.tmp-regression-docker-b395743146e243f88649f2b7556c5323/`。
最终集中完整 54/54 无遗漏重复，含27个绑定场景，内部/入口
`523638/524695 ms`、Jobs 6、排队 `110471 ms`、exit 0、cache_hit=false：
`.tmp-regression-docker-a811beaf4b7846a0b0ec987e5d43fef1/`。
两测试文件原始字节 SHA256 与完整输入一致；实现仅在快照后改两条 stderr，
逐字核对除此无差异，最终源码另在 Linux 工具容器通过 Bash 解析。
独立只读复审及 diff 通过；三份成功输入清理 `37,171,200 bytes`，
保留日志、清单、result、失败输入。入口较上一阶段减少 `19453 ms`，
输入亦变化，未证稳定提速，仍维持三槽预算。

本出口始终是诊断，不是跨事务授权凭据。后续实时父子通道必须在当前持锁 Bash
直接调用 bound 入口，仅消费本次控制流产生的结果，再绑定本轮子容器与随机挑战；
保存 JSON、环境变量、调用方输入或旧五参数 tuple 都不能授权写规则。
只读 child、写门控、菜单/schema/Compose、原生宿主/arm64 与公网继续 deferred，
整体目标保持 active。

##### 5C.9c.3e.2b.2 一次性实时父子只读握手

内部 `dockerPortHoppingTargetProbe listener start end ipv4 ipv6` 仅由当前持部署锁
Bash 直接调用 PrepareActivation 的固定 bound 模式，结果写本轮私有目录再读取；
不接受保存 JSON、环境变量或外部 tuple 授予写权限。初始父锁必须等于准备绑定锁，
请求摘要与后续复验均沿用实际启动采用的版本，锁替换不能刷新为新基线。

coproc 仅启动 Docker transport，立即保存 PID、复制并关闭原读写 FD；
父端固定随机 12 位 hex hostname、唯一 probe 标签、CID/Image/Created/StartedAt、
标准 entrypoint/五参数 tuple、完整 Config/HostConfig/Mounts。容器使用 host 网络、
root、只读根、cap-drop ALL 与唯一 CAP_NET_ADMIN、no-new-privileges、关闭 healthcheck，
只挂 net 数据目录与固定 /tmp、/run tmpfs，不给 net Docker socket 或设备。
固定 net 目录及全部祖先 dev/inode/mode/uid/gid，在请求前、退出后及清理后复验；
目录时间不固定，允许 flock 创建空锁文件改变目录时间。

子端复用当前本地双族地址、net flock、无跳跃 state 和全域冲突预检，发送随机挑战。
父端复验原启动绑定、目录和完整子容器投影后，只发送一行请求并关闭所有写端；
子端须读到 EOF，再核精确键、类型、nonce、CID/Image/目标 tuple 与摘要形状，
重新检查锁、地址、无 state 和全域冲突，输出唯一 ACK 后退出。
双方每帧限 4096 字节、20 秒；父逐字节读取，不能吞掉下一帧或噪声；
ACK 后限时确认 EOF，并核请求原始行摘要、transport 退出 0、子 exited/ExitCode 0、
原绑定与目录。回收只接受私有 cidfile、唯一标签与完整投影二次匹配的本轮容器；
无法核验归属时保留证据。准备或握手 INT/TERM 保持 130/143，失败 stdout 为空。
读取子 stdin 的 Python 使用 FD 3 源码，run/probe 仍 exec 为 PID 1，原命令路径保留。

新增聚焦 selector `docker-port-hopping-probe`，完整 preflight 复用该函数；
没有向完整集合重复加入同一叶子。21 个子端只读协议与身份场景、93 个帧/目录/
容器/父流程检查通过，含直接 Bash 身份、原锁基线替换、绑定和目录漂移、
错 nonce、重复 ACK、未挑战容器回收、替换配置保留与两阶段信号传播。
最终定向内部/入口 `10460/11582 ms`、Jobs 2、排队 `201 ms`：
`.tmp-regression-docker-ebb1a9c6eb554aca95bd694d658424dc/`。
首轮 ss 夹具多写空行、后续父夹具未含新锁字段均只修夹具，失败输入保留；
真实首轮暴露 host 网络默认 hostname 继承宿主、CapAdd 规范为 CAP_NET_ADMIN，
据实际 inspect 修正，使用显式随机 hostname 而非 CID 前缀假设。

最终真实双族握手、唯一 ACK、子回收、唯一 root:root/0600/单链接空锁、NAT/jumpstate
不变、刚跨额度撤销和失败安全恢复通过，内部/入口 `61822/62878 ms`、Jobs 2、
排队 `206 ms`：
`.tmp-regression-docker-dd3c8c61e4974e63b156c33a285155d1/`。
工具/业务基镜像与离线包复用，nested daemon 只复制当前标准 net 入口生成派生镜像，
固定其实际 digest 后生成部署材料；此证据不替代发布 Dockerfile 的净构建验收。
最终集中完整 54/54，无遗漏重复，内部/入口 `545510/546564 ms`、Jobs 6、
排队 `413 ms`、exit 0、cache_hit=false，证据：
`.tmp-regression-docker-af595a8c67ec466580b2936650876aea/`。
定向、真实和完整源码归档摘要相同，10 个当前关键实现/测试/入口原始字节
SHA256 与完整输入一致；独立只读复审、Bash/ShellCheck error 与 diff 通过。
聚焦修复反馈约 11.6 秒，完整入口较上阶段增加 `21869 ms`，测试内容亦增加，
未证稳定提速，不扩大三槽预算。中途采样 CPU 551.67%、内存 357.4 MiB，
采样时 cgroup memory.peak `1160847360 bytes`；不当作最终 CPU/内存峰值，
原始采样保留在完整证据的 `runtime-metrics.json`。
五份成功 source.tar 清理 `62,300,160 bytes`，保留日志/清单/result/核验摘要与失败输入。

本阶段只读；net 唯一可能写入是取得 flock 时新建空锁文件，不写 NAT/jumpstate。
父先准备受管核心，失败不回退累计或再次重建；诊断 ACK 不授予写入权限，
不证明全域原子范围预留、锁全生命周期、进程内存或完整 bind 视图一致。
net flock 仍不排斥非合作写入；SIGKILL/daemon 状态不明保留证据，不承诺自动恢复。
下一阶段 3e.2b.3 实施同锁实时写门控及最终启用 ACK，不能直接复用诊断 JSON 或
旧五参数 run 作为生产授权。菜单/schema/Compose、原生宿主/arm64、公网、
旧会话排空及完整跳跃继续 deferred，整体目标 active。

##### 菜单取消判断精简

CDN 地址及额外端口菜单的 7 处 `变量 != 0` 判断删除；这些输入均先经过
dockerSetupRead，输入 0 已返回失败。保留空输入检查及直接 read 的协议菜单判断，
不改变添加、删除、默认分享端口与取消语义。既有真实 PTY 菜单合同含取消、EOF、
非法输入、CLI 失败及信号，通过后不新增等价测试或重复全套。
Linux amd64 `docker-menu` 内部/入口 `106653/107891 ms`、Jobs 2、排队 `243 ms`、
exit 0、cache_hit=false：
`.tmp-regression-docker-832cd57aa53f4860b282975b6e87b473/`。
menu.sh 原始字节 SHA256 与本轮输入一致；diff 通过。成功 source.tar 清理
`12,472,320 bytes`，日志/清单/result 保留。外来订阅短链及工具镜像改动未暂存。
本次复审未确认新的菜单 bug，整体对齐及 3e.2b.3 写门控继续 active。

##### 5C.9c.3e.2b.3a 有限 net 写入与撤销协议

内部 `port_hopping_resources guarded` 复用原 net flock、state 原子提交、
精确归属审计和清理，不开放 entrypoint case、菜单、schema 或 Compose。
子端先预检地址、无 state 和全域冲突，再 challenge；prepare 仅绑定当前
请求材料。ready/write、written/finalize、active/close 各使用新随机 nonce，
后续帧严格回显 phase、CID 和原请求摘要，拒绝预先重放下一阶段。
中间帧逐字节读取，保留下一帧；每帧最多 4096 字节、等待 20 秒。

write 后再次核锁、地址和完整冲突，才写 intent 与两族规则；finalize 前、
active 提交后均复验完整自有资源、地址和全域冲突。active 是有限窗口，
不是持续启用成功。close 后必须唯一 EOF；finally 精确回收自有资源、
state 消失、原锁仍匹配且无信号，才输出 closed。INT/TERM 仅置标志，
命令返回完成记账后清理，清理完成仍退出 130/143，不输出成功 closed。
关闭期间地址消失或普通外来冲突不阻断自有撤销；锁/state 替换或清理失败
保留证据并拒绝成功，不删外来规则或 conntrack。

抽出原规则建立顺序供 run/guarded 共用，保留原 run 的错误传播与逐步记账。
47 个独立场景覆盖阶段 EOF/旧 nonce/摘要/乱序/额外键/超长/重放、INT/TERM、
两族写失败、written 超时、地址/冲突变化、锁/state 同字节替换、active
提交后的冲突与归属漂移、清理失败及清理期间信号。初轮 EOF/信号竞争及
关闭期间地址消失的夹具期望已修正，失败输入保留。

同一工具镜像、Linux amd64、Jobs 2，47 场景串行内部/入口
`123419/124552 ms`：
`.tmp-regression-docker-973c9814876a47b99880b0c5844eb3ef/`。
固定两个 worker、独立目录和进程组，同 47 场景 `68688/69832 ms`，
排队 `4903 ms`、exit 0、cache_hit=false：
`.tmp-regression-docker-e7fb414181e446bcbda770616f42d6c5/`。
随后让工具夹具直接复用既有 ownership 驱动，减少重复脚本加载；最终
同 47 场景内部/入口 `47179/48265 ms`、排队 `3844 ms`、exit 0、cache_hit=false：
`.tmp-regression-docker-7ec834c9fab14ad5a9290b9bf8a616d4/`。
相对串行入口约减少 61%，不推算完整回归或宣称稳定提速；三槽预算不变。
既有只读 Probe 21 + 93 场景通过，内部/入口 `10430/11509 ms`，
Jobs 2、排队 `209 ms`、exit 0、cache_hit=false：
`.tmp-regression-docker-3cd84c7db0a147c38d7edebb1c7fcff0/`。
最终三个关键源码原始字节与定向输入一致，摘要见最终目录 `verification.md`。
四份成功 source.tar 核对后清理 `50,063,360 bytes`，失败输入/日志/result 保留。
真实双族新连接、额度撤销、NAT/state 恢复、子容器回收及失败启动安全恢复通过，
内部/入口 `69228/70698 ms`、Jobs 2、排队 `241 ms`、exit 0、cache_hit=false：
`.tmp-regression-docker-25a990311700412ab36ac9ad3a120436/`。
前次两次自动审批超时未启动命令；2026-10-13 Docker 只读检查恢复后实际执行。
集中完整 54/54，无重复叶子，内部/入口 `541946/543082 ms`、Jobs 6、
排队 `103353 ms`、exit 0、cache_hit=false：
`.tmp-regression-docker-25d6f4f771d74837a8dd4b4065bd55f1/`。
四个阶段源码原始字节与真实及完整输入一致；独立复审及 diff 通过。
入口较上一阶段减少 `3482 ms`，输入亦变化，未证完整回归稳定提速；
本轮未取得 CPU/内存峰值，不推算峰值或扩大三槽预算。
两份新成功输入核对后清理，保留日志、清单、result 与 SHA256 核验记录。

本阶段子端只校验摘要形状，不证明真实父锁或实际启动 state/live。
下一步仍须由当前持锁父端逐门复验原 startup_binding、锁和子容器；
不得复用只读 transport 的 65 秒总时限与 `stop --time 2` 直接处置写事务。
有限写后撤销不交付持续启用、旧会话排空或自动跳跃，整体目标保持 active。

##### 5C.9c.3e.2b.3b 同锁父端有限写门与关闭确证

内部 `dockerPortHoppingTargetGuarded` 在当前持锁 Bash 直接调用
`PrepareActivation bound`，固定原锁、startup_binding、受管目录和子容器投影。
新增固定 `port-hopping-guarded` net 入口，仍不接 CLI、菜单、schema 或 Compose。
challenge/prepare、ready/write、written/finalize、active/close 每次发送前
复验原业务 state/live、部署锁、目录、固定 child 和信号；任何漂移停止授权，
不刷新绑定或用保存 JSON 代替实际准备。

各中间 nonce 必须新鲜并绑定原请求摘要与 CID；closed 回显最终 active nonce，
严格要求唯一帧、EOF、transport 退出 0、原 child exited/ExitCode 0。
关闭输入后由子端精确撤销；不使用 stop/kill 强杀容器。退出后两次核对
child 投影与退出码 0 才删除容器，再删除本轮 stage 并复验原业务绑定。
非零退出、归属漂移或状态不明保留容器及 stage，不凭 exited 推断撤销完成。
成功只返回 `guarded_closed`，有限 active 窗口不报告持续部署成功。

父端保存、忽略并恢复 PIPE trap，使真实 EPIPE 进入失败回收；
INT/TERM 在清理期间仍置标志并最终返回 130/143，恢复调用方原 trap。
wait 被信号中断时保留 transport；回收仅向当前 Bash 的运行作业发 TERM，
等待已保存的客户端退出，不按已退出数字 PID 的 kill-0 结果判断归属。
transport 使用 `timeout -k 2 150` 和 `--sig-proxy=false`；150 秒仅限客户端，
不构成准备阶段总事务时限。写门 Docker 查询分别限时 5 秒，
清理轮询预算 25 秒，各查询和 rm 另有限时；不把轮询预算称严格总时限。

Linux amd64、固定工具镜像、定向 Jobs 2，子端 47 + 父端/helper 54 个检查通过，
覆盖各门业务/child 漂移、旧 nonce、closed 缺失/重复/尾随、非零退出保留、
真实 EPIPE、查询超时、写后/清理期间/wait 中断 INT/TERM、transport 回收及 trap 恢复。
内部/入口 `69574/70638 ms`、排队 `218 ms`、exit 0、cache_hit=false：
`.tmp-regression-docker-e4eb3dc365eb46ccaeacf5dbc3175aac/`。
前次查询超时实际退出 4，修正过窄的退出 1 预期；失败输入保留，
未改变生产错误传播或绕过无授权、证据保留和小于 8 秒的限时断言。
旧 Probe 21 + 93 检查通过，内部/入口 `11605/12759 ms`、排队 `210 ms`：
`.tmp-regression-docker-33d817e5be8d4dddbdc287b22d0260fd/`。

标准 entrypoint 与当前持锁父端真实验收通过：closed 后 child/stage 消失，
双族 NAT 正文恢复、state 消失、原 net 锁 inode 保持，额度撤销仍生效；
原内部 payload 的新双族连接及安全恢复断言保持。内部/入口
`74672/75870 ms`、排队 `219 ms`、Jobs 2、exit 0、cache_hit=false：
`.tmp-regression-docker-f8794d605be745a2ab95d93441ef00a3/`。
内部 payload 不证明真实父锁，其记录保持相应 false；新增实际父端证据单独报告。
七个阶段实现/测试文件已与定向、真实和集中完整快照按原始字节核对一致。
集中完整 54/54，无重复叶子，内部/入口 `550331/551344 ms`、Jobs 6、
排队 `405 ms`、exit 0、cache_hit=false：
`.tmp-regression-docker-9ee1e1591a0241618806c59c5f7aa93f/`。
54 条容器采样观察到最高 `840.82% CPU / 1.041 GiB`；采样未覆盖完整运行期，
不宣称真实全程峰值或稳定性能收益。相对 3a 入口增加 `8262 ms`，
输入与父端检查均增加；继续复用工具镜像、两个定向 worker 和三槽预算，
未扩大并发或重复全套。原始字节核验在完整目录 `verification.md`，
仅文档在回归后补验收记录；成功归档核验后清理，保留日志/result/清单与失败输入。

本阶段持续启用、父端退出后的接管与最终部署 ACK 仍 deferred；同锁父端监督
的持续会话和失败撤销见 3c，不能复用旧五参数 run 作为写授权。
更新/重启的旧代次撤销、菜单/schema/Compose、原生宿主/arm64、公网、
旧 conntrack 与完整自动跳跃继续待交付，整体目标保持 active。

##### 5C.9c.3e.2b.3c 同锁父端监督持续会话

内部 `dockerPortHoppingTargetSupervised` 与有限入口共用同一事务实现；
只接受当前持锁 Bash 的本轮 `PrepareActivation bound`，不刷新原
startup_binding、部署锁、目录或 child 投影。固定独立
`port-hopping-supervised` Cmd 与 `io.padm.hopping-supervised` label，
旧 run、Probe 与有限 guarded 均不授予持续写权限，不接外部 CLI、
菜单、schema、Compose 或脱离父端的部署成功 ACK。

初始 challenge/prepare、ready/write、written/finalize 门沿用原复验。
active 仅接受精确 continue；之后 running 帧要求严格整数 seq 从 1
连续增长、原 CID/请求摘要与新 nonce。每轮发送前复验原业务 state/live、
部署锁、目录及固定 child，拒绝前一轮和固定初始 nonce 重用，
不无限保存会话历史。发送成功后原子替换 0600 `supervised.json`，
只记录原 target 及最新 running 帧，不作为新会话的写授权。

子端每轮等待 1 秒，再复验冲突、地址与归属后发新挑战；
窗口只允许空 EOF 停止，提前续期、半帧、跳号、bool 和旧帧均拒绝。
active/running 空 EOF 自行精确撤销，退出 0，不发有限 closed。
父端失败或信号先关闭输入，保留输出读端到退出/回收轮询结束，
避免下一挑战因 EPIPE 把正常 EOF 撤销变成非零。双复验退出 0 才 rm；
非零、归属漂移或停止不明仍保留 child/state/stage，原 trap 恢复。

持续 transport 使用 `timeout -k 2 0`，会话全程持部署锁。
20 秒只限制单帧读取；1 秒窗口另加子端规则复验和父端绑定复验，
不是固定续期间隔或硬撤销上界。父端前台 helper 期间的信号可延迟到
本帧返回后处理。Docker 查询 5 秒、清理轮询 25 秒与各 rm 预算保持；
没有会话总时长、准备总时限或统一撤销总时限。当前原 state/live
变化即终止；持续期间在线更新、重启及自动流量采集不在交付范围。

Linux amd64 固定工具镜像，Jobs 2 定向通过子端 70（原 47 + 新 23）、
有限父端/helper 54 和持续父端/helper 41 检查。复用现有调度器，
子端完成后让两个独立父端夹具并行，不增加本机槽位：
内部/入口 `114411/115452 ms`，排队 `200 ms`，exit 0、cache_hit=false，
证据 `.tmp-regression-docker-53b903f126e14a87a40aed59f19290d3/`。
串行首次入口 `127846 ms`；本次少 `12394 ms`，输入和同机负载并非
严格控制实验，不声称稳定收益。旧 Probe 21 + 93 检查通过，
内部/入口 `10732/11796 ms`，排队 `213 ms`：
`.tmp-regression-docker-64e2174a1c6841139763d9dd7d33fa9a/`。

真实标准 entrypoint 与同锁父端持续 `41.336 s`，观察 34 次续期，
同 CID/token/父锁/net 锁/固定投影不变，初末两个范围端口的双族新连接
self 可达、Alice 额度拒绝。TERM 返回 143；第二会话同字节、同权限
live 换 inode 后原绑定拒绝，返回 1。两者均无部署成功 stdout，
双族 NAT 正文恢复、state 消失、child 回收、stage/收据保留。
既有安全候选恢复与累计不回退检查保持，漂移场景末置避免污染该夹具。
内部/入口 `139877/140927 ms`、排队 `201 ms`、Jobs 2、exit 0：
`.tmp-regression-docker-b8e4cb4a412542a996af717432a7878a/`。
首轮夹具顺序失败输入保留：
`.tmp-regression-docker-a389c35180c744d18065dfbb3980dea3/`。

集中完整 54/54 唯一叶子通过，无遗漏或重复，Jobs 6、三槽预算，
内部/入口 `547727/548773 ms`、排队 `411 ms`、exit 0、cache_hit=false：
`.tmp-regression-docker-f1625d799a1b41cba277ed4a77ec4d58/`。
八个相关源码/入口/测试与最终定向、真实、完整快照原始字节一致；
Probe helper/lifecycle 也与最终源码一致，核验保存在完整目录
`verification.md`。42 条非全程资源样本最高观察值为
`851.03% CPU / 723.8 MiB`，不称真实全程峰值。较 3b 完整入口少
`2571 ms`，测试输入与同机条件变化，不据此宣称稳定提速。
验收后清理成功源码归档和提取副本，保留日志、结果、清单及失败输入。
父退出接管/最终部署 ACK、启用期更新/重启、菜单/schema/Compose、
旧 conntrack、真实自动跳跃、原生宿主/arm64/公网和完整协议管理
继续 deferred；当前仅交付父端存活且全程持锁的内部持续会话，
整体目标保持 active。

##### 5C.9c.3e.2b.3d 独立监督归属与实时交接

内部 `dockerPortHoppingSupervisorStart/Status/Stop` 复用原持续事务。
manager 以独立 session 启动持锁 Bash，Bash 自取新部署锁并直接 freshly bound；
调用者的旧锁、JSON、binding/tuple 和环境变量不授予写入或恢复权限。
owner 固定 manager/Bash 的 PID、starttime、boot ID、PID/net namespace 和 session，
以 pidfd 固定代次，私有 0700 会话目录和 0600 owner/socket 不自动恢复旧 owner。
Unix socket 使用固定目录 fd 的短路径，避免临时根超过 Linux 地址长度限制；
每次连接仍检查 SO_PEERCRED、进程代次、完整目录链和原 socket 身份。

启动 hello/随机挑战/commit 完成后才生成持锁 Bash。commit 前断流不写规则，
保留已创建的 starting owner/session 作为失败证据；commit 后 ACK 丢失不重建，
调用者可用新挑战查询原 owner。ready 必须来自 running seq 2，manager 确认后
Bash 发送续期并再次核原业务绑定/child 投影，started 用同一 payload；
seq 1 收据只证明父端发送，不作为最终 ACK。后续 running 要求连续 seq/新 nonce
及固定 target/child/directory/stage；owner 保存当前代次，不作为新的写授权。

停止不预取持续占用的部署锁。挑战 commit 后重核 owner、目录和 Bash pidfd，
再向固定 Bash 发 TERM；Bash 关闭输入，由原 child 退出 0 并精确净撤销，
双复验容器投影/退出、复验业务绑定及无 state、删除本轮 stage 后通知 cleaned。
原锁快照仍一致且安全释放才通知 finished 143/true；manager 必须观察 Bash
实际终止并严格核通知 nonce、字段和类型，确认会话/原锁/state 净清理后返回 stopped。
非零、SIGKILL、超时、归属漂移或未知停止保留证据，不按数字 PID 或旧文件接管。

root status/stop 的 hello/commit 同步等待各 2 秒，最多 4 秒暂时阻塞续期；
这不是固定续期间隔或统一撤销上界。原子目录独占拒绝重复启动。
manager 异常关闭通道并通过原 pidfd TERM Bash，90 秒仅作等待回收预算，
不能把超时当作净撤销。仍无事务总时限或自动旧 owner 恢复。

本阶段 Docker Desktop Linux amd64 当前源码快照验证通过，均复用工具镜像
`sha256:44edfa2f5437bd852b0249fcf5fde85913ac29e2d56d744fa4d4728ad00bf978`：

| selector | `.tmp-regression-docker-` 结果目录后缀 | 入口耗时 ms |
| --- | --- | ---: |
| `docker-port-hopping-supervisor` | `cc45d6fefe0445f1a042baa6de9e1515` | 2005 |
| `docker-port-hopping-guarded` | `3afdf8b3e82a4fc483a1c303058dcdae` | 116473 |
| `docker-phase1` | `b9d18f30705d4d2dbaf7eee032e54d7c` | 48977 |
| `docker-port-hopping-target-real` | `d8d8a811e5d2499f89e079d49ce3fb49` | 213088 |
| `docker-setup-core` | `864f23e9a9bc4486b01c525a290b2ccd` | 67998 |
| `docker-release` | `c8cbbf4b9c394faab5113fed59902a1a` | 21568 |
| `docker-phase6` | `a6972e2a239b4b9985ea29eefffcf2b2` | 54528 |
| `docker-contracts` | `52c8333e8a1741abad44c85429cb2963` | 535325 |

定向 Jobs 2；guarded 70、有限父端 54、持续父端 41、独立监督父端 13 项通过。
三个父端夹具共用两个 worker，独立监督有聚焦 selector，完整回归沿原 preflight
链覆盖，不增重复顶层叶子。缺 Probe/supervisor helper 的控制包拒绝；
setup/release/phase6 三份包夹具同步补全，定向和完整均通过。

真实验收总耗时 210.631 秒；独立监督持续 43.27 秒、观察 29 次续期，
started seq 2、最终 seq 31；调用者退出后仍存活，双族新连接与 Alice 额度拒绝、
重复启动和旧 token 拒绝、正常停止净撤销、第二代独立启动/停止均通过。
原持续父端 41.354 秒/34 次续期及绑定漂移拒绝保持通过。
长路径 socket、目录身份和 Windows 快照入口权限的失败输入保留；
入口权限只在容器私有夹具规范为 0750，并断言源码字节不变。

完整 Jobs 6、54/54 唯一叶子通过，cache_hit=false、排队 400 ms；
39 条非全程资源采样最高观察 719.43% CPU / 725.6 MiB，不称真实峰值。
入口较上一阶段 548773 ms 少 13448 ms，输入和负载不同，不作稳定提速结论。
八份成功快照的相关源码原始 SHA 与最终文件一致，核验保存在完整目录
`verification.md`；Bash syntax/ShellCheck error、Python AST 和差异检查通过。
首轮完整发现包夹具缺 helper 后主动停止，修正后集中重跑本次完整；
失败输入及日志保留，成功重复源码归档、提取副本和本轮临时脚本清理。

仅交付内部 Linux root owner/control/ACK；systemd、原生宿主/arm64/公网、
重启卸载、启用期更新/重启、菜单/schema/Compose、旧 conntrack、
真实自动跳跃和完整协议管理继续 deferred，整体目标保持 active。

##### 5C.9c.3e.2b.3d.1 运行态监督信号验收

复用上阶段真实双族网络与独立监督夹具，只增加收到 `started` ACK 后的信号断言：
manager HUP 后跨两次帧租约，原 owner、部署锁、规则 state 和 child 投影保持，
新挑战查询确认 seq 增长并继续验证双族新连接/额度拒绝。
manager TERM 通过原 pidfd 触发 Bash TERM，观察原 child、state、NAT、
部署锁、stage 和 session 净清理；不伪造 CLI stopped ACK。
manager SIGKILL 后等待本轮 Bash 因控制通道 EOF/EPIPE 关闭 child 输入；
规则/state 净撤销、child 回收且原部署锁释放，session/owner/stage 保留。
旧 active JSON 仅作失败证据；status、stop 和新 start 均拒绝并不覆盖证据。

`docker-port-hopping-target-real` Jobs 2 通过：
`.tmp-regression-docker-f136ce591d0a4e1ab5c7d5e35a687152/`，
入口 241294 ms、排队 4955 ms、cache_hit=false，复用与 3d 相同的工具镜像。
真实验收 238.825 秒，本次 manager TERM 观察 1.666 秒、SIGKILL 观察 1.722 秒；
这些耗时不是撤销上界。八个相关文件与真实快照原始 SHA 一致，
六个生产文件与 3d 完整回归核验一致，见本目录 `verification.json`。
仅改真实夹具和文档，因此不重复 54 项完整合同；差异检查通过，
成功重复归档与提取副本清理，结果、日志和核验保留。

范围限于运行态：初始化期间的 HUP/TERM、Bash SIGKILL、daemon 重启、
整机重启、systemd、原生宿主/arm64/公网仍未验收。
manager 异常退出的 finally 先关闭控制通道再 TERM Bash，Bash 可能已删 stage
后发送 cleaned 失败；session/log 保留，不承诺所有异常都保留全部目录，
也不以丢失的清理回执确认 stopped 或自动接管。
90 秒仅作 manager 等待预算，仍无统一撤销/事务时限；整体计划保持 active。

##### 5C.9c.3e.2b.3d.2 监督启用期部署门禁

共用 `dockerAcquireDeploymentLock` 在创建锁前、等待循环中且清理旧锁前、
本轮锁 PID 写入后检查 `.hopping-supervisor` 任意现存路径或悬空符号链接。
活动、starting 或停止未核验的残留均拒绝普通部署操作，既不读取旧 JSON 授权，
也不因死 PID 自动清除会话或原锁证据。后置检查遇到会话竞争只释放本轮新锁。
install、普通启动/停止/重启、更新、回滚及其它共用取锁入口沿用该检查，
失败返回原锁错误，不调用 Compose、不误报更新/停止成功或等待完整 30 秒。

持锁监督 Bash 经双向控制 fd 检查后使用内部 `--hopping-owner` 取锁；
参数仅豁免自身会话占用检查，原锁快照、freshly bound 和 manager 新挑战仍独立
决定授权，不接收环境变量或旧 owner 作授权。正常 stop 净清理 session/原锁后，
普通取锁恢复；SIGKILL 留下的会话继续阻断部署，不自动接管或删除。

定向合同覆盖三种会话路径、七个生命周期入口、死 PID 锁证据、
等待期间/成功取锁后会话出现、活动监督续期与停止成功/失败后的门禁。
证据比对固定 inode、权限、owner、link count、size、mtime/ctime 和内容；
解析链接或读取产生的 atime 变化不判为写入。真实夹具复用双族网络，
刻意保留 SIGKILL 的独立监督验收置于最后；外部 live inode 漂移之后复用真实
重启见证形成新 StartedAt，再验下一会话，不删除失败证据或放宽生产检查。

验证均使用 Docker Linux amd64、同一当前源码归档与工具镜像
`sha256:44edfa2f5437bd852b0249fcf5fde85913ac29e2d56d744fa4d4728ad00bf978`：

- 定向 `docker-port-hopping-supervisor`，Jobs 2，40 项通过，入口 3352 ms：
  `.tmp-regression-docker-901d7270ee384970976aa93254b3ddbe/`。
- 真实 `docker-port-hopping-target-real`，Jobs 2，exit 0，验收 261.977 秒、
  入口 264434 ms、排队 199 ms：
  `.tmp-regression-docker-7bf65c02fce54844a27f0af6843b05c2/`。
  独立监督续期 28 次，活动/净停止/KILL 残留门禁分别耗时 50/56/47 ms；
  正常 stop、manager TERM 净清理，以及 KILL 会话和 stage 留证均通过。
- 集中 `docker-contracts`，Jobs 6，54/54 顶层叶子唯一且与源码声明一致，
  exit 0，入口 572615 ms、排队 427 ms、cache=false：
  `.tmp-regression-docker-61d340d4bf004384ba45f2d6eba4748b/`。

三归档 SHA-256 相同；流式逐项核对 370 个文件，369 个与当前工作区一致，
仅计划文档在验证后补写。结果目录保留 `verification.json/md`、日志和结果，
成功重复归档及本轮核验脚本清理。失败输入仍保留：安装夹具 ref 长度、
误将读访问 atime 当成写入、KILL 留证后再次启动及 drift 后旧启动见证均已修正；
未通过删除失败证据或放宽生产检查绕过门禁。

该检查不是原子会话预约：普通事务通过后置检查后，manager 仍可能创建 session；
已有事务持原锁完成，监督 Bash 等待新锁，未并发激活。长事务可能超过监督帧
等待预算并留下 starting 证据；并发启动可用性和在线更新/重启协调仍 deferred。
普通 status/logs 等共用锁入口也会拒绝该会话，专用监督 Status/Stop 沿用原控制
通道。菜单/schema/Compose、自动恢复、真实自动跳跃、完整协议管理及
原生宿主/arm64/公网/systemd/整机重启仍待交付，总目标保持 active。

##### 5C.9c.3e.2b.3d.3 同锁会话预约

独立 manager 先完成原 start 挑战，再用短 Bash 通过普通部署锁入口预约。
普通事务仍持锁时只等待，不提前创建 `.hopping-supervisor`，不消耗 hello
帧预算；两个同时启动者沿用相同锁和部署门禁，仅一个能创建会话。
预约 Bash 固定真实 owner 后形成原锁快照，随后 `exec` Python 保持内核 PID，
由锁 owner 本身创建目录，避免 Bash 退出后孤儿 helper 再创建 marker 的竞争。

预约仅复用本轮锁的实时见证：当前 PID、创建前后原锁快照、完整目录链、
命名路径与已打开锁 fd、原 pid 元数据均核对，随后只 unlink 原锁的 pid，
再 rmdir 原锁并确认路径消失。manager 重新打开预约目录，严格比对 canonical
目录与 session 投影后才创建控制端和 owner、启动监督 Bash。
保存的预约快照不授权目标事务，也不向新 Bash 转交锁；它仍独立自取锁并
freshly bound。目录、原锁或 pid 漂移及删除失败保留会话/锁证据，不删 state/stage。
commit 前 EOF 不再留下未建立的会话；移除未被读取的 committed 标志。

定向 `docker-port-hopping-supervisor`，Docker Linux amd64、Jobs 2，48 项通过，
入口 5919 ms，复用同一工具镜像：
`.tmp-regression-docker-56869a3d956e4c31a99cacfe3edc559b/`。
新增确定性场景同时覆盖两个预约已进入等待、普通原锁不变、释放后仅一个启用、
pid 变化/锁内额外目录/预约目录替换留证，以及锁 owner 在创建 marker 前后
真实 SIGKILL：前者没有孤儿写入且普通入口可回收死锁，后者保留会话与锁并拒绝
普通操作。

真实 `docker-port-hopping-target-real`，Jobs 2，exit 0，验收 259.382 秒，
入口 261877 ms、排队 167 ms，独立监督持续 43.792 秒、续期 28 次，
活动/净停止/KILL 留证门禁 45/52/46 ms，净清理及 TERM/KILL 边界均通过：
`.tmp-regression-docker-33eaed9f919845bd9a968e844af9395d/`。
集中 `docker-contracts`，Jobs 6，54/54 顶层叶子唯一且与实际归档声明一致，
exit 0，入口 534164 ms、排队 27790 ms，cache=false：
`.tmp-regression-docker-c2b6c0c4d2d0458a8e8e7f249ab06911/`。
两归档 SHA-256 相同，补录文档前 370/370 文件逐项匹配当前工作区；
三次回归的本轮两个代码/测试文件均匹配。定向归档仅计划文档和另一个任务的
`contracts.sh` 后续修改不同，差异记录于 `verification.json/md`，未扩大本轮提交。
本轮保留结果、日志、逐项核验及多余构建停止说明，清理成功重复归档和核验脚本。
工具镜像在 Docker 初始化后恢复，停止多余构建并复用原 ID，没有重复下载工具。

这是合作部署入口之间的会话预约，仍不宣称抵御最后 syscall 前任意特权替换；
manager 初始化信号的完整矩阵与无人值守恢复未交付。普通部署入口继续拒绝
已启用会话，在线 restart/update/rollback/down/uninstall 协调仍待实施。
菜单/schema/Compose、真实自动跳跃和原生宿主等范围不扩大，总目标保持 active。

#### 5C.9c.3e.2b.3d.4 在线 restart 集成

已有活动独立监督时，现有 `restart` CLI/菜单经原控制挑战协调交接。
旧规则净撤销、`finished 143/true`、Bash 实际退出及原锁释放全部确证后，
同一 manager、socket 和会话目录启动新 Bash；目录贯穿交接，普通部署不能插入。
新 Bash 自取锁并通过新 restart 写门，复用原累计采集、额度安全渲染及配置检查，
执行共享生命周期 restart，核心 CID 保持、StartedAt 更新；不再额外 recreate。
随后重新形成启动绑定和持续监督，新 token/Bash/stage/子端及 ACK 必须匹配。
旧 token、非法净停止回执和新锁漂移拒绝；重启失败不重复重启，
按已有恢复路径保留累计、会话与事务证据，不能把旧 active JSON 当作成功。
连续两次控制重启、额度边界、失败单次重启和实际双族业务验证复用现有夹具，
定向通过后集中完整回归，不为每个控制子步骤重复跑全套。

Docker Linux amd64 验收通过，复用工具镜像
`sha256:44edfa2f5437bd852b0249fcf5fde85913ac29e2d56d744fa4d4728ad00bf978`：
定向 target 含 3 项 restart 事务，入口 125580 ms；
真实验收 268.615 秒、入口 271186 ms，在线交接及双族认证恢复通过；
集中合同 54/54 顶层叶子与归档声明唯一匹配，含 57 项监督检查，
入口 527066 ms、排队 267555 ms，cache=false。
证据分别在 `.tmp-regression-docker-5c36e47f49ba4a99b4ebe0480f0a4ab6/`、
`.tmp-regression-docker-1b0d6bae269443418db5fad4e0915a1a/`、
`.tmp-regression-docker-8a0f34f406a64d2fbf0961b1c3c89259/`；
三份归档的本轮 5 个代码/测试文件 SHA-256 均匹配，详见各目录
`verification.json`。清理成功归档和核验脚本，保留日志、结果及失败输入。

当前仅覆盖既有单 sing-box、双族 Hy2、无宿主集成的内部监督范围。
菜单启用、schema/Compose 持久化、其它生命周期协调、TUIC、自动恢复与真实自动跳跃，
原生宿主/systemd/整机重启/arm64/公网及可信发布仍未交付或未验；
支持状态仍 deferred，总目标 active。

#### 5C.9c.3e.2b.3d.5 down/uninstall 协调

既有 `down` CLI/菜单和卸载在参数、宿主与当前 bundle 检查后，经原监督控制
通道净停止活动会话，再复用普通部署锁及原生命周期事务。停止 ACK 仅在旧 Bash
退出、规则 state 和原锁净清理后成立；随后重新检查 marker 消失并正常取锁，
竞争中新会话仍由原门禁拒绝。未知残留、非法净停止回执或停止失败不继续
Compose、计划删除或卸载，不删除证据。普通 `up`、status、更新、回滚等
仍沿用部署门禁；更新/回滚中的恢复与重新启用协调继续 deferred。

定向复用实际 manager 与确定性 owner 夹具，覆盖 down/uninstall 成功、
非法参数不停止会话及停止失败不修改部署。真实夹具安装当前源码受管 bundle、
独立 CLI，验证 down/uninstall 后监督与核心清理、状态保留和恢复业务。
Docker Linux amd64 定向 69 项通过，入口 13882 ms：
`.tmp-regression-docker-162070a784e44678930b5eb096bc3f96/`。
真实验收 312.077 秒、入口 314859 ms、排队 170 ms，退出与业务恢复通过：
`.tmp-regression-docker-950ee6b285fa43fbaf5fcfa7b3e1d34e/`。
两次复用同一工具镜像，定向生产逻辑/监督测试及真实的 3 个交付文件
均匹配相应源码归档；定向未执行的真实夹具后续改动由真实验收覆盖。
集中 `docker-contracts` 54/54 顶层叶子唯一匹配实际归档，入口 563566 ms、
排队 74763 ms，Jobs 6、cache=false：
`.tmp-regression-docker-cb5a5dc485554261a18fb01c2edef2b1/`。
真实与集中归档 SHA-256 相同，本轮 3 个代码/测试文件匹配当前工作区；
保留各目录核验、结果和日志，清理成功重复归档及本轮核验脚本。
本阶段不升级公开支持范围，完整 purge、原生宿主等验收仍 deferred。

#### 5C.9c.3e.2b.3d.6 update/rollback 协调

更新和回滚复用在线 restart 的原控制挑战和净停止交接，同一 manager/session
覆盖整个事务，新 Bash 自取锁并通过写门执行已有候选、备份及失败恢复流程。
事务结束后以当前部署重新形成跳跃启动绑定；事务失败但恢复成功仍返回失败，
并确认恢复后的跳跃业务。未知残留、非法停止回执及新写门漂移拒绝并保留证据。
范围限定在内部监督、单 sing-box、双族 Hy2、无宿主集成，不升级无人值守恢复
或完整公开端口跳跃支持。

活动会话只允许目标 bundle 的 `lifecycle.sh`、`port-hopping-supervisor.py`
与当前执行版本逐字节一致；跨监督版本需要协议协商后再开放。
回滚切换前拒绝不同 schema、多入口、不同端口/双族/domain；旧备份未记录
`bundle.target` 时沿用当前 bundle。保留原监听、范围与目标地址，更新/回滚允许
核心 CID/image 改变，restart 仍要求同 CID/image。修复公共更新候选的
Compose 发布标签同步，使新规格与实际容器版本见证一致。

新增 `docker-port-hopping-change-real` 复用真实节点和独立监督生命周期断言，
省去配置漂移、额度及有限父子场景的重复前置；标准真实入口继续覆盖完整集合。
夹具使用真实 ops 镜像，并按 configure 准备运行态目录与权限。
离线 manifest 只核本轮固定内容，不代表真实发布验签通过。

Docker Linux amd64 复用工具镜像
`sha256:0f7d1c14744a66023ae528226890eb84d0d607114ce5a1f0157216cb6bfdd722`：
监督定向 86 项通过，入口 15895 ms，证据在
`.tmp-regression-docker-93ad8d1c68f84dd8a10a05382d9af9d1/`。
集中合同 54/54 通过，Jobs 6，入口 357766 ms、排队 48102 ms、cache=false：
`.tmp-regression-docker-fdb14d74a0d946faaea99455b594baec/`。
最终真实定向通过，场景 218.018 秒、入口 220710 ms、排队 159 ms：
`.tmp-regression-docker-2c2978627df14e40beeabd76b008b0f1/`。
更新、回滚和注入更新启动失败的 ACK 分别为 0、0、14；每轮双族新连接、
同 session/manager、新 owner/child、累计不回退及随后 down/TERM/uninstall/
SIGKILL 证据行为均通过。最终真实与集中归档的 14 份文件核验匹配，详见真实
目录 `verification.json`；标准真实入口未重复整套执行，最终夹具由缩短入口验收。
清理成功重复归档、核验脚本及诊断副本，保留结果、日志、核验与失败输入。
菜单启停与 schema/Compose 持久化继续推进，整体目标保持 active。

#### 5C.9c.3e.2b.3d.7 手动跳跃菜单与持久规格

v3 增加可选 `port_hopping` 保存字段，并同步写入 deployment 与 Compose
`x-padm-port-hopping`；旧 bundle 缺少 `x-padm-port-hopping-manual` 时拒绝带字段
的规格。当前范围固定为单个 sing-box、单个双族 Hy2、无宿主集成和其它常驻运行服务；
默认未运行的 ACME profile 可以保留。范围起止、监听器、规范 IPv4/IPv6 及目标端口
在保存和启用前重复校验，保存不会自动启动监督。

协议菜单提供状态、保存、手动启用、停止和清除；CLI 提供
`edit --port-hopping`、`edit --port-hopping-clear` 及
`port-hopping status|start|stop`。活动监督通过原控制通道查询，普通 status 不占用
持续部署锁；启动在预约部署锁内读取保存参数并再次核对，避免编辑竞态。清除、
失败恢复、更新、回滚均保持三份材料一致，参数不匹配时不采集累计或重建核心。

本阶段不开放自动恢复、普通 up/daemon/systemd/整机重启接管、真实自动跳跃、TUIC、
旧会话排空、原生宿主、arm64、公网或其它多监听场景；整体目标保持 active。
配置、完整合同和真实双族变更回归集中验收，避免重复已通过的监督长集合。

Linux amd64 配置定向通过，入口 14551 ms：
`.tmp-regression-docker-4942dda4a9b64169ac0b319648003c95/`；
规格差分 185 案例通过，入口 13158 ms：
`.tmp-regression-docker-c1690690985c4ec4b3db4c4a11dc227f/`。
集中合同 54/54 通过，Jobs 6，入口 364096 ms、排队 302 ms、cache=false：
`.tmp-regression-docker-859d2c526a074ff28da8d5a9ac323cad/`。
真实双族变更定向通过，场景 258.079 秒、入口 261132 ms、排队 157 ms：
`.tmp-regression-docker-7e17d3a1a87141949f06502155d7f86a/`。
两份归档各 13 份阶段代码与测试均匹配，见各自 `verification.json`；
文档在打包后精简，不属于回归快照，不为文档重复回归。
清理成功输入归档和清单，保留结果、日志及核验；下一组合继续真实自动跳跃，
不得将手动菜单完成当作完整跳跃或整体计划完成。

#### 5C.9c.3e.2b.3e 活动范围分享链接

`port-hopping share` 只在监督状态仍 active，且活动范围、双族地址及目标端口与
受管规格一致时输出 Hy2 范围 URI；菜单同步提供该动作。不写入静态订阅文件，
停止或配置漂移后拒绝输出。范围仍限单 sing-box、单个双族 Hy2 和内部监督；
真实自动跳跃及宿主/arm64/公网验收继续 deferred，整体目标保持 active。

Docker Linux amd64 定向 `docker-port-hopping-config` 通过，入口 13940 ms，
排队 3550 ms，Jobs 2，cache=false；配置、CLI 漂移拒绝及 PTY 菜单共用一次回归：
`.tmp-regression-docker-1a819c8cf72b4f41a56da2b18c27b55f/`。
未做真实客户端导入或外部网络验收，不扩大支持状态。

#### 5C.9c.3e.2b.3f 真实客户端自动跳跃定向验收

新增 `docker-port-hopping-auto-real` 复用已有隔离 daemon、当前 net 入口与真实
sing-box 镜像；只跑保存配置的 CLI 启用、分享、双族自动跳跃、停止和新连接拒绝。
服务端继续转发完整范围，客户端以 `server_ports` 和 `hop_interval=5s` 自动切换，
无需新增服务端轮换逻辑。客户端 netns 按目标端口计数，同一进程持续请求；
两族都实际发送到两个端口后才通过，不以等待时间或静态规则代替跳跃证据。
定向分支不改变原真实生命周期集合的前置或断言，避免重复跑长集合。

Docker Linux amd64、Jobs 2 通过，入口 38493 ms、排队 153 ms、cache=false：
`.tmp-regression-docker-5100a126d133496f954e9413f543d476/`。
早期事件文件未初始化的夹具失败已修正，失败输入保留。成功采样第 2 轮双族
已跨端口，采样 5.226 秒；停止后双族 NAT 正文恢复、state、
session、部署锁和子容器清理，新的 QUIC 连接拒绝。

中英文说明同步活动范围分享和本地真实客户端证据；范围 URI 外部导入、
原生宿主/arm64/公网、自动恢复、TUIC、旧 conntrack 排空仍待验或待交付。
支持范围仍是内部监督、单 sing-box、单个双族 Hy2；整体目标保持 active。

#### 5C.9c.3e.2b.3g 跳跃分享复用协议生成器

活动范围分享复用 `dockerGenerateSubscription`，仅投影已核对的目标入口与端口范围；
保留 TLS、ALPN、Brutal 带宽方向和混淆参数，删除重复 URI 拼接。
生成器需要重复读取规格，使用权限 0600 的临时文件并随命令退出清理；
不写受管规格、静态订阅或其它账号。活动目标与保存配置的一致性门禁保留。

Docker Linux amd64、Jobs 2、cache=false：配置定向 14594 ms、排队 150 ms，
`.tmp-regression-docker-7b6f5c2fd2064dc193b8727d5c07518c/`；
真实双族自动跳跃 53626 ms、排队 152 ms，
`.tmp-regression-docker-10abca8b93524bcdbc49f91108e8a544/`。
配置断言覆盖 BBR、Brutal 上下行交换、混淆保留及分享前后受管文件不变；
真实专项复验同一客户端跨端口、停止清理和新连接拒绝。未重复完整长集合，
未新增外部客户端 URI 导入证据；既有支持范围与 deferred 保留，整体目标仍 active。

#### 5C.9c.3e.2b.3h 监督初始化信号处理

manager 在初始握手、预约或 Popen 前登记 INT/TERM，handler 只置停止标志；
原子创建、写入及释放锁完成后检查，避免丢失本次归属。预约等待可取消，
取消时回收直接预约子进程，Popen 后 identity/pin 失败也回收尚无 pidfd 的 Bash。
ready/started 的 owner 持久化后再次检查信号，不确认启动或开放下一写门。
已有 ready 见证、净撤销回执、Bash 状态 143 与原锁释放全部成立才清会话；
较早中断保留未核验现场并拒绝普通部署变更，不自动恢复。

定向复用真实 service/reserve 子进程和 pidfd，覆盖 14 个初始化边界的 INT/TERM，
共 28 例，加原控制/归属合同合计 115 项。Docker Linux amd64、Jobs 2 通过，
入口 25139 ms，排队 165 ms：
`.tmp-regression-docker-0e57f24f01754229a4d1cd19bb5e0435/`。
最初 marker-before 夹具阻断放在安全检查之后，已调整，旧失败输入保留。
同快照真实生产入口的 ready TERM 与正常双族自动跳跃合用节点，入口 64027 ms，
排队 158 ms：`.tmp-regression-docker-eaedc71dbb1444c786668a08758bbe96/`。
TERM 后双族 NAT、state、stage、子容器、session 和部署锁净清理且无启动 ACK；
保存配置逐字节保持，随后同一客户端跨双族两个端口及停止后新连接拒绝通过。

集中合同 57/57 通过，Jobs 6，入口 359780 ms、排队 315 ms、cache=false：
`.tmp-regression-docker-0874d178bb9942b485ce0c9f337b7118/`。
三份归档各 3 份生产/测试文件与最终源码一致，见各自 `verification.json`；
文档在打包后同步，不重复已通过的代码回归。成功输入归档及清单清理，
保留日志/result/verification 与失败输入。支持范围仍限内部监督、单 sing-box、
单个双族 Hy2；自动恢复、TUIC、旧会话排空、原生宿主/arm64/公网、
整机重启及完整卸载仍待交付或验收，整体目标保持 active。

#### 5C.9c.3e.2b.3i 监督事务推进与停止等待预算

监督启动/重启共用 120 秒、更新/回滚共用 840 秒绝对推进预算，
覆盖初始挑战、预约、准备及代次交接，单帧或新 Bash 不重置总预算。
正常 started 后清除推进截止，活动会话无总时长限制。
到期不再授权写门、创建下一代或发送成功 ACK；原 pidfd 请求 Bash TERM，
等待净撤销证据。停止只登记一次 90 秒截止，finally 复用剩余时间；
耗尽保留未核验证据，不 KILL、不把退出当净撤销或自动恢复。
这是监督推进与等待限制，不是阻塞文件操作或内核清理的硬撤销上界。

Docker Linux amd64、Jobs 2，复用工具镜像且 cache=false：
最终监督定向 128 项通过，入口 28998 ms、排队 167 ms，
`.tmp-regression-docker-22d965cc97714140a380726ed0ed5f50/`。
原 115 项加辅助绝对截止、进程回收及 9 个服务边界，
包含 ready/started、restart/update/rollback、写门 owner 读取、
最终启动 ACK、停止等待与清理后 ACK；到期辅助进程在 Popen 前拒绝。
真实 ready 到期与原 TERM 场景共用节点，双族 NAT/state/stage/child/session/
锁净清理、无启动 ACK、保存配置不变，随后同一客户端双族跨两端口通过。
入口 76255 ms、排队 161 ms，
`.tmp-regression-docker-bb8376765d584873b7151b86e91b5e8a/`。
真实验收后仅补 Popen 前拒绝检查，由最终定向覆盖，不重复真实长集合。
配置合同、生成器、Compose 和菜单未改，不重复完整合同矩阵。

成功回归输入由入口清理，结果/log 保留，移除本轮 Python 缓存。
较早 deadline 夹具已修已回收 PID 的检查，失败输入保留。
范围仍限内部监督、单 sing-box、双族 Hy2；自动恢复、TUIC、
外部 URI 导入、Bash SIGKILL、原生宿主/arm64/公网、整机重启、
完整卸载和可信发布继续待交付或验收，整体目标保持 active。

#### 5C.9c.3e.2b.3j 持锁 Bash SIGKILL 真实故障闭环

复用 `docker-port-hopping-auto-real` 的现有私有 daemon/双族节点，
正常停止后新启一代，按 owner 严格核 manager/Bash 身份并绑定 pidfd，
仅向本代持锁 Bash 发送 SIGKILL。原 Bash/manager 退出，子端在控制输入
关闭后正常退出 0，双族 NAT 正文恢复且 state 消失；
缺少 cleaned/finished 回执，不确认净停止、不回收退出容器或清旧 owner。
session/owner、stage、退出子容器和原部署锁保留，
status/stop/start/restart/down/uninstall 全部失败且证据身份/内容不变。
这验证故障拒绝与留证，不开放旧 owner 自动接管或恢复。

Docker Linux amd64、Jobs 2、cache=false，工具镜像复用：
入口 82729 ms、排队 4081 ms，
`.tmp-regression-docker-e191d9052295426abf0227da5c9e3036/`。
同节点已有 ready TERM/到期取消、同进程双族两端口跳跃及新连接拒绝同时通过；
新增故障验收不重跑已有 update/rollback/down/uninstall 长生命周期集合。
仅改真实夹具与中英文边界说明，AST/diff 通过，不重复无变化合同。
成功输入由入口清理，日志/result 保留，未创建宿主依赖或临时源码副本。

自动恢复、TUIC、外部 URI 导入、旧会话排空、原生宿主/arm64/公网、
systemd/整机重启、完整卸载和可信发布继续待交付或验收；
支持范围与整体 deferred 保持，总目标 active。

#### 5C.9d TUIC 范围转发与活动单端口分享

把已有 Hy2 范围管理扩展到单 sing-box、单个双族 TUIC 入口，一批接通持久规格、
菜单/CLI、实际目标核验、启停清除和 restart/update/rollback 协调。
沿用内部监督、双族 DNAT、部署锁、账号/额度渲染、失败净撤销或保留证据；
不增加宿主权限、核心、进程监督机制或第二套状态模型。
目标投影从协议 ID 严格选择 domain 和真实入站类型，witness 保留结构并逐代核对
`protocol_id`；更新/回滚不允许换协议、入口身份、端口、地址族或 TLS 域名。
新 TUIC 跳跃规格要求 `x-padm-port-hopping-tuic`，旧 Hy2 子集兼容；
仍拒绝别名、控制面、HTTP relay、HTTP-01、订阅发布、副核心及其它宿主集成。

`port-hopping share` 的 Hy2 无参数范围 URI 保持；TUIC 默认输出范围首端口的普通
`tuic://`。两协议均可 `share <端口>`，菜单 `7` 输入活动范围内端口，
复用已有协议生成器与认证/TLS，未启用、目标漂移、非规范或范围外端口拒绝，
不改静态订阅。固定 sing-box TUIC 不接受 `server_ports`，本阶段只交付范围转发，
客户端可选择范围内任一端口；不生成非标准范围 URI 或宣称客户端自动换端口。
TUIC 客户端自动跳跃、自动恢复、外部 URI 导入、旧会话排空、原生宿主/arm64/
公网、整机重启、完整卸载及可信发布仍 deferred，整体目标保持 active。

本批验收在 Docker Linux amd64 当前源码快照、复用工具镜像下完成：
定向 preflight 93310 ms、TUIC 真实 124339 ms、Hy2 真实自动跳跃保护 105247 ms，
均 Jobs 2；完整合同一次 57/57 通过，Jobs 6，入口 357253 ms、内部 355334 ms、
排队 332 ms、cache=false，未扩大共享三槽并发。
四份结果源码 SHA-256 均为
`3EF4EE38DB217026293E111F0467745D5BB1A1197655DF9B9296DB592622DBDD`；
随后仅补本文验收文字。完整证据
`.tmp-regression-docker-4f2341a09df6416eba6d34089297a3ab/`，
TUIC 真实证据 `.tmp-regression-docker-0e57ff8708fe4ce48892fbd65631a1f7/`。
TUIC 已验双族基础口和范围首尾、分享、restart、update、rollback、失败更新恢复，
逐代保持 ID 31、入口身份、保存配置和累计；public stop 后双族范围新 QUIC 拒绝，
基础口仍通，NAT/state、子容器、会话和部署锁净撤销。
停止断言以当前代次为基线，精确扣除四条跳跃规则后比较全表，避免把 Compose
更新的普通 NAT 变化当残留；补齐三个旧握手夹具的协议 ID。
菜单 `7` 的 `0 返回` 已修复并由现有 PTY 覆盖；输入归档已清理，日志/result 保留。
未重复 TUIC 上游阻塞探针或长生命周期矩阵，不升级完整协议管理状态。

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
