# 核心与服务菜单深度重构计划

## 目标

- 本次审计基线为 `main` 的 `70c07ab`，相对 `origin/main` 领先 3 个提交；实现时从届时的 `main` HEAD 创建 `codex/core-services-menu-refactor` 独立 worktree。本文件只交付计划，不修改源码。
- 只重构菜单、服务编排和核心检查链，不改配置格式、CLI、持久化数据或部署方式，不新增依赖。
- 将“核心与服务”常驻页面的循环、渲染和导航集中到 `shell/core/menu.sh`，核心版本/配置/Geo 业务及动作内部的一次性确认、版本选择留在 `shell/core/cores.sh`，服务状态、动作和队列集中到 `shell/core/services.sh`；`shell/core/locale.sh` 的通用渲染器继续复用，不新增菜单 DSL。
- 不保留独立的“配置健康与兼容”页面；Xray 与 sing-box 的检查分别归回各自生命周期页，并统一显示为“检查当前配置”“扫描升级风险”“试跑预发布版”。
- “安装与重装”只保留在主菜单，不在“核心与服务”首页或其子页重复提供入口。

## 第 1 轮审计：范围、入口与真实调用链

### 已核对的现状

| 边界 | 现状证据 | 重构约束 |
| --- | --- | --- |
| 生产入口 | `install.sh` 的 `loadScriptModules` 加载 `shell/core/bootstrap.sh`，随后 `initScriptRuntime` 读取安装状态，`runMainMenu` 调用 `menu` | 不改变脚本命令、cron 分支或模块锁；菜单重构只发生在 `runMainMenu -> menu` 之后 |
| 顶层菜单 | `shell/core/menu.sh` 定义 `menu`、安装、协议、站点、路由、系统和危险操作入口 | 保留这些函数名及被 `manage.sh`、路由模块调用的返回约定；编号可调整但入口语义不变 |
| 核心子菜单 | `shell/core/cores.sh` 同时包含 `coreVersionManageMenu`、`xrayVersionManageMenu`、`singBoxVersionManageMenu`、`coreServiceControlMenu`、`coreConfigMaintenanceMenu`、`coreLogsMenu`、`coreAllServicesMenu` 和业务函数 | 把 6 个保留的常驻菜单壳及 `showCoreStatusOverview`/`coreDisplayState` 移到 `menu.sh`，新增实际入口 `xrayGeoDataMenu` 承接原 Geo 三项动作；删除独立配置页，`coreConfigMaintenanceMenu` 仅留薄兼容入口；版本选择、确认、配置校验、Geo 和安装实现仍留在 `cores.sh` |
| 服务层 | `shell/core/services.sh` 提供 `nginxRunning`、`xrayRunning`、`singBoxRunning`、`handle*`、`serviceQueue*` 和 `reloadCore` | 新入口只调用服务层公开动作；不在菜单中直接调用 `systemctl`、`rc-service` 或 `nginx` |
| 加载顺序 | 生产和回归 bootstrap 都先加载 `services.sh`、`cores.sh`，最后加载 `menu.sh` | 继续沿用现有顺序；移动菜单壳不新增 bootstrap 文件，也不依赖未加载的函数 |
| 回归调用者 | UI 回归会直接调用旧菜单函数，并对源码中的兼容入口计数 | 旧函数名保留为薄包装或同名实现；同步更新 selector 断言，禁止静默删除入口 |

### 第 1 轮修订结论

- 目标范围锁定为菜单状态机、服务编排和核心检查链，不做全仓目录拆分，不改配置/持久化格式、CLI 参数、模块加载和部署流程。
- `menu.sh` 负责常驻页面显示、输入、导航和留页；`cores.sh` 负责核心领域业务及动作内部的短提示/确认；`services.sh` 负责服务状态、动作、队列和结果码。
- `nginx.sh`、`manage.sh` 及 `shell/subscription/` 继续持有 Nginx 配置生成、订阅发布和 WireGuard 控制面；服务页只消费状态/动作 API。
- 首个可验证切点是 Xray 普通/严格共享执行器：保持两个旧包装函数及调用者不变，先固定模式、日志和 `0/1/2`；再对齐 sing-box 三项检查的结果和预发布流程，最后迁移生命周期菜单及 `coreVersionManageMenu`。

## 第 2 轮审计：菜单信息架构、导航与 EOF

### 已核对的现状

- `coreVersionManageMenu`、`coreServiceControlMenu`、`coreConfigMaintenanceMenu`、`coreLogsMenu` 和 `coreAllServicesMenu` 都是“一次渲染、一次读取、调用后返回”的函数；无效输入通过 `coreInvalidInputRetryMenu` 递归重入。
- `autoRead` 最终直接执行 `read -r`，因此可以区分 EOF，但现有菜单没有检查其返回码；连续 EOF 会递归增长调用栈。
- `coreVersionManageMenu` 在两个核心都未安装时调用 `menu` 后 `exit 0`；`menu` 本身也有 `cd "$HOME" || exit`，这两个硬退出都阻断了安全返回。
- 回归会用 here-string 直接调用菜单（例如 `coreVersionManageMenu <<<"6"`），所以函数签名和“调用后返回”必须保持。

### 修订后的信息架构

核心与服务首页每次渲染先输出本地状态总览，再显示固定 6 个入口：

1. Xray-core 生命周期（升级、回退、检查当前配置、扫描升级风险、试跑预发布版）
2. sing-box 生命周期（升级、回退、检查当前配置、扫描升级风险、试跑预发布版）
3. 服务运行态（Xray、sing-box、条件依赖的 Nginx）
4. 日志与诊断（Xray、sing-box、Nginx `nginx -t`）
5. Xray Geo 数据（`xrayGeoDataMenu`：更新、状态、定时任务）
6. 返回主菜单

两个生命周期页使用相同顺序：升级稳定版、升级预发布版、回退稳定版、检查当前配置、扫描升级风险、试跑预发布版、返回。两页不再跳转到共享配置页；原配置维护页中的 Geo 更新、状态和定时任务完整迁入 `xrayGeoDataMenu`。

| 用户入口 | 菜单说明 | Xray 内部执行 | sing-box 内部执行 |
| --- | --- | --- | --- |
| 检查当前配置 | 验证当前核心能否正常加载 | 先运行校验，再执行严格规则；严格阶段不单列菜单 | 使用当前二进制执行 merge + check |
| 扫描升级风险 | 查找已知的不兼容配置 | 扫描现有 6 类 Xray 规则 | 扫描现有 1.13/1.14 迁移规则 |
| 试跑预发布版 | 只用最新预发布版测试当前配置，不执行升级 | 下载目标二进制并执行运行/严格校验 | 下载目标二进制并执行 merge + check |

菜单和首屏结果不出现“普通模式”“严格模式”、`PASS/WARN/FAIL` 或环境变量名；统一显示“通过”“需关注”“失败”“无法检查”。两种核心的结果卡片标题固定为“当前配置检查”“升级风险扫描”“预发布版试跑”，不能菜单改名后继续显示“配置体检”“兼容体检”或“预发布兼容检查”；技术阶段名、原始错误和日志路径只在结果详情及日志中出现。

对象页和领域页的返回只返回一层：对象页返回核心与服务首页，首页的 6 返回主菜单；禁止通过再次调用父菜单形成递归。

### 两种核心检查现状与问题

- 普通和严格校验分别由 `validateXrayConfigWithBinary`、`validateXrayConfigStrictWithBinary` 实现，前置判断与命令拼装重复；二进制或配置目录缺失时直接返回，可能留下旧日志且没有可诊断原因。
- `showXrayConfigHealthCheck` 会连续执行普通、严格和静态兼容扫描，但只有普通校验失败稳定返回非零；严格失败或兼容 `FAIL` 仍可能因卡片函数成功而表现为成功。
- Xray 与 sing-box 的静态扫描都对同一 JSON 重复启动 `jq`；扫描本身只依赖配置和 `jq`，却会因未安装对应核心二进制而跳过。
- `showCoreStatusOverview` 每次渲染都会执行配置校验及两个核心的完整兼容扫描，导致进入菜单即运行二进制并重复扫描配置。
- `checkXrayPrereleaseCompatibility` 已能复用下载后的临时二进制，但未在校验前核对其实际版本，也未纳入静态兼容 `FAIL/WARN`；版本获取失败会经过 `checkVersionNotEmpty` 退出进程，合并报告后还会留下 `.validate`/`.strict` 中间日志。
- `checkSingBoxPrereleaseCompatibility` 未纳入本地兼容扫描和实际版本核对，预发布升级还会再次下载而不是复用已验证文件；版本获取失败同样可能退出菜单进程。
- `shell/validate_install.sh` 另行编排严格校验与两个兼容扫描，容易与生命周期页的结果语义漂移。

### 三项用户动作契约

| 动作 | Xray | sing-box | 结果、网络与副作用 |
| --- | --- | --- | --- |
| 检查当前配置 | 当前二进制先执行 `-test -confdir`；通过后以命令级 `XRAY_JSON_STRICT=true` 再检查。运行阶段失败为“失败”；仅严格阶段失败为“需关注” | 当前二进制对合并配置执行 merge + check；失败为“失败” | 不联网、不改配置、不动服务；通过或仅 Xray 严格阶段未通过为 `0`，执行/校验失败为 `1`，二进制或配置缺失为 `2` |
| 扫描升级风险 | 每个 JSON 一次 `jq` 产出 finding code；非法 JSON、legacy reverse 阻断，其余现有规则提醒 | 每个 JSON 一次 `jq` 产出 finding code；非法 JSON 及现有 6 类 1.13/1.14 风险阻断 | 不要求本机核心二进制、不联网、不修改文件；无阻断为 `0`，阻断或 `jq`/输出失败为 `1`，无配置为 `2` |
| 试跑预发布版 | 先扫描升级风险，再解析/下载并核对目标版本，依次执行运行和严格校验 | 先扫描升级风险，再解析/下载并核对目标版本，使用目标二进制执行 merge + check | 只有本地扫描通过且用户明确选择时才联网；不停止服务、不替换二进制。仅提醒可返回 `0`，任何阻断/下载/版本/目标校验失败为 `1`，无配置为 `2` |

统一约定 `0=通过或仅需关注`、`1=检查失败/基础设施错误`、`2=缺少适用前提`。菜单不显示数值结果码，也不让动作状态码改变导航；升级流程只接受 `0`，`1/2` 都禁止替换二进制。Xray 严格阶段的底层返回仍是失败，但“检查当前配置”将“运行检查通过、仅严格检查失败”映射为“需关注/0”；在预发布试跑中，严格失败仍是阻断 `1`。

### 最小实现收敛

- 新增一个内部 `runXrayConfigValidation <binary> <normal|strict> <log>`，只用简单 `case` 处理模式；它先截断日志并校验模式、二进制和配置，再执行一次测试命令。现有 `validateXrayConfigWithBinary` 和 `validateXrayConfigStrictWithBinary` 保留签名并委托它，避免修改安装、TLS 和事务调用面。
- 保留 `showXrayConfigHealthCheck` 并将其收敛为“检查当前配置”页面动作：只编排运行/严格两个阶段，不再执行静态扫描；`showXrayStrictValidation [log]` 保留给现有直接调用者，但不出现在菜单。新增薄动作 `showSingBoxConfigValidation [log]` 调用现有 merge + check；不增加跨核心校验框架。
- `collectXrayCompatibilityFindings`、`collectSingBoxCompatibilityFindings` 的三个路径参数保持不变并直接返回聚合结果；扫描前显式检查 `jq` 和输出文件，每个 JSON 只启动一次 `jq`，同一文件同一 finding code 只记一次。保留两种核心各自的现有规则，不增加规则 DSL、外部规则文件或版本策略注册表。
- 删除只为首页即时检查服务的 `coreValidationStateWithPaths`、`xrayCompatibilityAuditOverviewSummary`、`singBoxCompatibilityAuditOverviewSummary`；首页只显示版本、运行态和配置存在性，三项检查仅在用户明确选择时执行，不增加缓存或持久化结果格式。
- 每次检查先清空自己的目标日志并写入核心、二进制、目标版本、配置目录和阶段结果，不复制配置正文、UUID 或凭据。预发布报告统一包含本地风险扫描、目标版本和目标二进制校验；Xray 另含运行/严格两个阶段。所有失败分支清理下载目录和中间日志，只保留最终报告。
- 两个预发布检查都不要求当前核心二进制存在，只要求当前配置可用；先消费本地风险扫描结果，`1/2` 直接返回且不请求版本。目标版本为空或为 `null` 时在各自函数内返回 `1`，不得调用会 `exit` 的 `checkVersionNotEmpty`。下载文件先通过现有归档/文件安全校验，再分别从 `Xray x.y.z`、`sing-box version x.y.z` 首行核对实际版本；目标值只去掉一个前导 `v` 后精确比较，无法解析或不相等都在配置测试前失败。
- `checkXrayPrereleaseCompatibility` 保留第三个可选的已验证目录输出参数；为 `checkSingBoxPrereleaseCompatibility` 和 `installDownloadedSingBoxBinary` 增加向后兼容的可选目录参数，使预发布升级复用同一已验证目录。两种核心在提交前仍用当前配置重验目标二进制，防止确认期间配置变化；独立“试跑预发布版”始终清理临时目录。
- `shell/validate_install.sh` 改为消费相同的低层校验函数和兼容摘要，只负责映射到现有 pass/warn 输出，不再复制检查顺序或把“无法检查”报告为通过。

### 导航状态机与边界

| 事件 | 处理 | 页面结果 |
| --- | --- | --- |
| 无效输入 | 写入一次错误卡片，`continue` | 留在当前页 |
| 动作成功、失败或用户取消 | 保留现有状态/错误提示，忽略动作返回值对导航的影响 | 留在当前页并重新渲染 |
| 显式“返回” | `return 0` | 返回调用者的一层 |
| `autoRead` 返回 EOF | 清空本轮选择并 `return 0`，把 EOF 当作安全关闭 | 不重试、不递归、不打印伪错误 |
| 未安装核心 | 首页仍渲染版本和服务的“未安装”状态，并提示返回主菜单使用“安装与重装”；升级、回退和“检查当前配置”显示“无法检查”，不能把升级当作隐式安装；若现有配置仍存在，“扫描升级风险”和“试跑预发布版”可按契约运行 | 可查看总览和只读检查，但不在本页启动安装流程 |

核心与服务首页及其子页使用 `while`/`continue`；不改动全仓通用的 `coreInvalidInputRetryMenu`，以免扩大协议、路由和订阅菜单的行为范围。顶层 `menu` 只做两个配套改动：`cd "$HOME" || return 1`，以及 case 6 的核心菜单返回后 `continue` 重新渲染主菜单；其余顶层入口保持现有一次调用行为。`menu.sh` 承接菜单壳和兼容入口，`cores.sh` 继续提供被菜单调用的领域动作。

## 第 3 轮审计：服务动作、队列顺序与失败语义

### 已核对的现状

- `serviceQueueAdd` 以 `service:action` 精确去重并保留首次加入顺序；`serviceQueueApply` 会逐项尝试并在末尾清空队列，但未知服务没有 `default` 分支，会被静默忽略。
- Xray 和 sing-box 当前对“已运行时 `start`”执行停后启，和幂等启动要求冲突；Nginx 的 `start` 还受 `nginxRuntimeRequired`/`restore` 条件控制。
- `handleNginx`、`handleXray`、`handleSingBox` 的失败路径在非队列调用下可能 `exit 0`；队列通过 `SERVICE_QUEUE_ALLOW_FAILURE=true` 避免退出，多个安装、TLS、订阅、路由和回滚调用者也依赖这个变量。
- `reloadCore` 被大量配置事务调用，当前语义是按安装状态加入 Xray/sing-box `restart` 后立即 `serviceQueueApply`，不能在菜单重构中直接改成 Nginx 操作或改变其返回码。

### 最小服务 API 与动作矩阵

只增加一个薄分派层，不引入注册表、对象或 DSL：

| API | 责任 | 允许值 |
| --- | --- | --- |
| `serviceInstalled` | 通过现有二进制/服务文件探测安装状态 | `xray`、`sing-box`、`nginx` |
| `serviceRunning` | 统一调用现有 `xrayRunning`、`singBoxRunning`、`nginxRunning` | 同上 |
| `serviceActionSupported` | 在执行前拒绝未知服务/动作 | 核心：`start/stop/restart`；Nginx 另加 `reload` 和仅供内部队列使用的 `refresh` |
| `runServiceAction` | 用一个 `case` 调用现有 `handle*` 并返回其状态码 | 不直接执行 `systemctl`、`rc-service` 或二进制 |

动作语义固定为：

- `start`：已运行即成功返回，不停后启；未运行才执行启动和状态等待。
- `stop`：已停止即成功返回；运行中执行停止并等待确认。
- `restart`：始终执行完整停、启；停失败仍记录失败并继续尝试启，以保持队列“全部尝试”契约。
- `reload`：只允许 Nginx，先 `nginx -t`，校验通过后才发送 `nginx -s reload`；核心不接受该动作。
- `refresh`：只允许 Nginx 且不出现在菜单；根据校验结果、运行态和 `nginxRuntimeRequired` 决定 reload、start 或保持停止。
- 不支持的服务/动作在分派层返回非零并写错误卡片，不能变成成功空操作。

### 队列契约

- `serviceQueueRefresh` 复用现有 `serviceQueueAdd` 的字符串队列；菜单上的 reload 直接调用 `runServiceAction`，不增加无调用点的 `serviceQueueReload`。加入顺序和精确去重保持不变，`start`、`stop`、`restart` 的冲突项不做隐式合并。
- `serviceQueueApply` 对每个条目都调用 `runServiceAction`，未知条目记失败但继续后续条目；无论成功或失败，应用结束都清空 `SERVICE_ACTIONS` 并恢复之前的 `SERVICE_QUEUE_ALLOW_FAILURE` 值。
- 处理器统一只 `return 0/非零`，保留现有诊断卡片和日志路径；移除所有 `exit 0`，`SERVICE_QUEUE_ALLOW_FAILURE` 暂时保留为兼容上下文而不再决定进程退出。
- `reloadCore` 保留原函数名和“核心重启后立即应用”语义，菜单的新服务页通过 `runServiceAction`/队列调用；只有明确属于 Nginx 纯配置刷新的调用点迁移到 `refresh`。

### 本轮回归切点

在改动服务实现前先固定以下断言：systemd/OpenRC 两套探测、已运行/已停止幂等启停、重启停启顺序、未知动作失败、队列失败后仍执行后续项且清空、处理器失败不退出、`reloadCore` 的旧调用者仍收到非零失败码。

## 第 4 轮审计：Nginx 归属、refresh 迁移与回滚边界

### 已核对的现状

- `nginxRuntimeRequired` 已通过协议选择和受管配置识别传统 TLS/fallback、Reality 443 共存、sing-box HTTPUpgrade、订阅发布及 WireGuard 控制面，但只返回布尔值，服务页还不能解释依赖原因。
- 生产代码只有 8 处直接 `serviceQueueRestart nginx`，集中在 Reality 共存、传统 TLS 302、WireGuard 控制面和 sing-box 安装；其中前三类已有 `nginx -t`、备份和失败回滚，可迁移为平滑刷新。
- `writeAloneNginxConfig`、`updateAloneNginxConfig`、`writeSubscribeNginxConfig` 和 `ensureSubscriptionWireGuardNginxConfig` 已在提交后校验并恢复旧文件；`refresh` 不应重复实现文件事务。
- 订阅/核心安装、HTTPUpgrade 首装、临时端口检测、TLS 续期、卸载和故障恢复会改变开机自启、监听端口或原运行状态，必须继续走明确的 stop/start 或 restart。

### 领域归属

| 配置/动作 | 继续归属 | 服务页权限 |
| --- | --- | --- |
| `alone.conf`、302、证书 | 站点与证书 | 只显示依赖原因、运行态和诊断 |
| Reality stream、HTTPUpgrade | 协议与入口 | 不提供配置编辑 |
| `subscribe.conf`、`padm-control-wg.conf` | 订阅与用户 | 不提供发布或 WireGuard 设置 |
| start/stop/restart/reload、`nginx -t` | 核心与服务 | 仅当 `nginxRuntimeRequired` 为真时可控 |

新增一个本地 `nginxRuntimeReasons` 输出依赖原因，`nginxRuntimeRequired` 直接以其是否有输出作为布尔结果，避免维护两份条件列表。已安装或正在运行但没有任何 padm 依赖原因的 Nginx 标记为“外部/非 padm 依赖，只读”，菜单不得发送服务动作。

### refresh 状态机

`serviceQueueRefresh nginx` 是内部配置应用动作，不暴露为用户按钮：

1. 先执行 `nginx -t`；失败立即返回非零，不发送 reload/start。
2. Nginx 正在运行时调用 Nginx `reload`，保持连接不中断。
3. Nginx 已停止且 `nginxRuntimeRequired` 为真时调用幂等 `start`。
4. Nginx 已停止且当前不被 padm 需要时成功空操作，保持停止。
5. `refresh` 只返回结果，不创建/删除备份、不恢复配置；原调用者在失败后恢复旧文件，再次调用 `refresh` 应用旧配置。

菜单上的显式 `reload` 只在 Nginx 正在运行且属于 padm 当前依赖时可用；否则显示不可用原因。`stop` 仍需默认否的确认，`restart`/`reload` 直接执行并提示连接影响。

### 迁移白名单

| 调用点 | 修改 | 保留的回滚责任 |
| --- | --- | --- |
| `realityStreamApplyServicesOrRollback` | 前向应用和恢复旧配置时将 Nginx `restart` 改为 `refresh`；核心 `reloadCore` 不变 | `realityStreamRollback` 继续管理配置/状态备份 |
| `manageTraditionalTlsRedirect`、`checkNginx302` | 添加、删除和探测失败回滚都使用 `refresh`；纯配置编辑路径不再先停止 Nginx | `backupNginxConfig`、`write/updateAloneNginxConfig` 继续校验和恢复 |
| `refreshSubscriptionWireGuardNginxControl`、`disableSubscriptionWireGuardControl` | 写入/移除配置后加入 `refresh`；Fail2ban 通过同一入口受益 | 现有 `checkLogBackup*` 和 `subscriptionWireGuardRestoreStateOrReport` 不变 |

为实现上述边界，`updateRedirectNginxConf` 只负责写入和校验，不再自行停止 Nginx；安装调用者继续在现有生命周期步骤中停启，维护调用者在提交后统一排队 `refresh`。

以下路径明确不迁移：`customSingBoxInstallApply`、`installSubscribeApply`、HTTPUpgrade 首装、`ensureTraditionalTlsFallbackNginxConfig` 的首次启动、`checkPortOpen`、TLS 续期、卸载以及任何“恢复原运行状态”分支。

## 第 5 轮审计：测试、文档、兼容与发布影响

### 现有回归基线与补强位置

| 行为 | 现有公开 selector / runner | 实现时的最小补强 |
| --- | --- | --- |
| 核心菜单渲染与导航 | `ui-full-core`、`ui-full-core-maintenance`；`runMenuSmokeRegression` | 改写对递归重试和“返回时再次调用父菜单”的源码计数，增加空安装态、固定 6 入口、核心子树无安装入口、两个生命周期页相同的 7 项顺序和三项检查文案、无独立 Xray 严格入口、Geo 三项只归 `xrayGeoDataMenu`、无独立配置页、单层返回、连续无效输入、EOF、失败后留页、stop 默认拒绝确认、外部 Nginx 只读且不发动作，以及渲染期零网络请求 |
| 服务状态探测 | `core-running-service-state`；`runCoreRunningFallsBackToServiceStateRegression` | 覆盖 `serviceInstalled`/`serviceRunning` 对 systemd、OpenRC、二进制存在但服务缺失及完全未安装的结果 |
| 动作与队列失败传播 | `service-queue-apply-propagation`、`reload-core-propagation`；对应同名 runner | 覆盖幂等 start/stop、restart 停启顺序、未知服务/动作失败、精确去重、失败后继续、队列清空、上下文恢复和 `reloadCore` 返回码兼容 |
| Nginx 服务失败 | `nginx-service-failure`；`runNginxServiceFailureRegression` | 保留 SELinux 重试和 systemd/OpenRC 失败断言，增加 `handle*` 只返回不退出及显式 reload 先校验；Nginx 是否可控由菜单回归固定，不改变内部恢复调用能力 |
| Nginx 配置事务与回滚 | `reality-stream-enable`、`reality-stream-disable`、`subscribe-nginx-config-write`、`subscribe-nginx-service-failure`、`wireguard-menu-flow-control-restore` | 将断言从 restart 更新为 refresh，并验证前向失败后恢复旧配置、再次 refresh 旧配置，以及原运行态不被意外改变 |
| Xray 检查 | `xray-strict-validation`、`xray-compat-audit`、`xray-compat-trusted-xff`、`xray-configured-validation-path`、`xray-prerelease-dry-run`、`platform-rest` | 扩充既有 runner：运行/严格底层模式与 `0/1/2`、当前检查将仅严格失败映射为“需关注/0”、前提失败覆盖旧日志、无环境泄漏、无二进制静态扫描、缺少 `jq` 失败、单文件单次 `jq`、规则去重、旧页面动作参数兼容、版本获取失败只返回不退出、预发布严格失败/版本不符前置阻断、所有临时路径清理及 `validate_install` 复用；不新增 Xray selector |
| sing-box 检查 | `singbox-compat-audit`、`singbox-prerelease-dry-run`、`platform-rest` | 扩充既有 runner：merge + check 的 `0/1/2`、“检查当前配置”页面结果、无二进制静态扫描、单文件单次 `jq`、版本获取失败只返回不退出、下载版本不符阻断、独立试跑清理、升级复用已验证目录及 `validate_install` 复用；不新增 sing-box selector |

仅新增一个独立 leaf selector：`nginx-service-refresh`。runner 放在现有 `shell/regression/subscription_groups_legacy.sh`，在 `shell/regression/suites/transaction.sh` 注册并纳入 `transaction-system`，同步更新 `shell/regression/suites/contracts.sh` 的注册契约。它固定 `nginx -t` 失败、运行中 reload、停止且需要时 start、停止且不需要时无动作四个分支；其余行为追加到现有 selector，避免继续拆分测试入口。

### README 同步范围

- `README.md` 和 `documents/en/README_EN.md` 同步修改主菜单表中的“核心与服务”描述，以及现有“核心与服务 / Cores and Services”章节；两份文档保持相同信息层级。
- 文档列出固定 6 个语义入口，明确配置健康与兼容已拆回两个核心生命周期页、“安装与重装”只在主菜单，并说明首页只读取本地状态、未安装仍可进入、远端版本只在明确动作时获取。
- Xray 与 sing-box 生命周期章节使用相同的“检查当前配置”“扫描升级风险”“试跑预发布版”入口和“通过/需关注/失败/无法检查”结果；Xray 的运行/严格阶段只在详情中解释，预发布试跑明确不会替换二进制或操作服务。
- 文档说明 Nginx 只在 padm 当前依赖时可控，外部 Nginx 只读；配置仍由协议、站点和订阅领域管理。
- 回归章节追加本次聚焦 selector，不复制内部 runner 命令；公开执行形式保持 `bash shell/subscription_groups_regression.sh <selector>`。

### 兼容契约

| 表面 | 必须保持 | 允许改变 |
| --- | --- | --- |
| 菜单入口 | `menu`、`coreVersionManageMenu`、`xrayVersionManageMenu`、`singBoxVersionManageMenu`、`coreServiceControlMenu`、`coreConfigMaintenanceMenu`、`coreLogsMenu`、`coreAllServicesMenu` 的函数名和现有参数仍可通过 bootstrap 直接调用 | 函数实现迁到 `menu.sh`、编号和页面分组调整；新增 `xrayGeoDataMenu` 作为 Geo 唯一页面，`coreConfigMaintenanceMenu` 只作为跳回核心首页的薄兼容入口，不再渲染页面；交互菜单在动作失败后留页并在显式返回/EOF 时返回 0；单独 source `cores.sh` 不作为公开加载方式 |
| 服务处理器 | `handleNginx`、`handleXray`、`handleSingBox` 的参数继续有效，错误信息和日志路径保留 | 失败改为非零 `return`，不再以 `exit 0` 终止调用进程；所有直接调用点必须显式传播或明确忽略结果 |
| 服务队列 | `serviceQueueStart/Stop/Restart/Apply`、`SERVICE_ACTIONS` 和加入顺序保留，`reloadCore` 仍立即应用核心 restart 队列 | 未知条目由静默成功改为失败；新增 Nginx `reload`/`refresh`，但不合并冲突动作 |
| Xray 检查 | `validateXrayConfigWithBinary`、`validateXrayConfigStrictWithBinary`、`collectXrayCompatibilityFindings`、`showXrayConfigHealthCheck`、`showXrayStrictValidation`、`showXrayCompatibilityAudit` 和 `checkXrayPrereleaseCompatibility` 的参数顺序与默认路径、现有最终日志路径及“升级复用已验证目录”约定保留 | 统一 `0/1/2`；`showXrayConfigHealthCheck` 不再执行静态扫描，严格页面动作不再出现在菜单；静态阻断开始返回非零，版本获取失败不再退出菜单进程 |
| sing-box 检查 | `validateSingBoxConfigWithBinary`、`collectSingBoxCompatibilityFindings`、`showSingBoxCompatibilityAudit` 和 `checkSingBoxPrereleaseCompatibility` 的现有参数顺序与默认路径保留；原有单参数 `installDownloadedSingBoxBinary` 调用继续有效 | 新增 `showSingBoxConfigValidation`；统一 `0/1/2`；为预发布检查和安装函数追加可选的已验证目录参数；静态阻断开始返回非零，版本获取失败不再退出菜单进程 |
| 外部表面 | `install.sh` 命令参数、bootstrap 加载顺序、配置/状态文件格式、cron、部署和依赖不变 | 菜单文字、导航留页、幂等启停及 Nginx 纯配置应用方式改变 |

### 发布影响

- 这是交互和内部服务语义变更，不需要数据迁移、配置转换或重新安装；回滚代码即可恢复旧行为。
- 用户可见变化是菜单编号/分组、核心子树不再重复提供安装入口、动作后留在当前页、未安装可进入，以及受管 Nginx 的状态和原因展示。
- 两个生命周期页统一为三项用户检查；Xray 运行/严格仍是两个内部阶段，当前运行通过但严格失败显示“需关注”，预发布严格失败才阻断。缺少前提不再显示为成功；前两项不联网，只有“试跑预发布版”按需联网。
- `start` 从“已运行时重启”改成真正幂等；需要完整停启的旧调用必须继续使用 `restart`，这是实施前调用点审计的硬门槛。
- Nginx 纯配置刷新优先 reload，减少连接中断；安装、端口占用、TLS 续期、卸载和恢复状态路径不受该优化影响。

## 第 6 轮审计：最小实现、回退点与验收标准

### 最小文件范围

| 组 | 文件 | 必要改动 |
| --- | --- | --- |
| 菜单 | `shell/core/menu.sh`、`shell/core/cores.sh` | 6 个保留菜单、一个新增 `xrayGeoDataMenu` 及状态总览渲染迁到 `menu.sh` 并改显式循环；`coreConfigMaintenanceMenu` 收敛为薄兼容入口；`cores.sh` 保留状态数据、版本、配置、Geo、安装动作及动作内部短交互 |
| 核心检查 | `shell/core/cores.sh`、`shell/validate_install.sh` | Xray 统一运行/严格执行器并收敛当前检查；两种核心统一三项用户动作、按需静态扫描、预发布状态机、结果码、日志和临时目录清理；删除首页即时检查 helper |
| 服务 | `shell/core/services.sh` | 统一状态/动作分派、幂等语义、队列失败契约、Nginx 原因/reload/refresh；处理器只返回状态码 |
| Nginx 调用点 | `shell/core/nginx.sh`、`shell/core/manage.sh`、`shell/subscription/wireguard_control.sh` | 只迁移第 4 轮白名单中的纯配置路径；其他直接调用不顺手整理 |
| 回归 | `shell/regression/subscription_groups_fast.sh`、`shell/regression/subscription_groups_legacy.sh`、`shell/regression/suites/transaction.sh`、`shell/regression/suites/contracts.sh` | 扩充既有 runner，注册唯一新增 selector，并更新受菜单文件迁移影响的源码契约 |
| 文档 | `README.md`、`documents/en/README_EN.md` | 同步信息架构、Nginx 边界和聚焦回归命令 |

预计不改 `shell/core/bootstrap.sh`、`shell/core/locale.sh`、`install.sh`、配置 schema 或依赖清单。若实现时发现白名单之外的文件必须改动，先以调用链和失败传播证据重新评估范围，不能借本重构做顺手清理。

### 分阶段执行与回退点

1. **隔离与基线**：从实施时的 `main` HEAD 创建 `codex/core-services-menu-refactor` 独立 worktree；记录上述聚焦 selector、`fast` 和 `transaction-core` 的结果。基线不通过则先区分既有失败，不带病改语义。
2. **核心检查链**：先统一 Xray 运行/严格执行器和当前检查结果，再优化两个静态扫描，最后收敛两种核心的预发布流程及 `validate_install` 消费端；逐个运行现有 Xray、sing-box selector。回退点是按核心恢复旧 helper 和调用顺序，不涉及配置或二进制回滚。
3. **服务契约**：改 `services.sh` 及服务/队列 runner，确认允许动作矩阵、幂等性、全部尝试和返回码。回退点是只撤销服务层及对应测试，不触碰菜单和 Nginx 调用点。
4. **Nginx refresh**：实现四分支状态机，再逐个迁移 Reality、传统 TLS 302 和 WireGuard 白名单，每迁移一类即跑其事务/回滚 selector。出现回归时将该类调用点退回 `restart`，配置备份格式无需回退。
5. **菜单状态机**：迁移同名菜单函数，增加核心子树循环和顶层返回配套逻辑，随后更新 UI runner。出现导航回归时可整体恢复原菜单函数；核心检查链、服务 API 与 Nginx refresh 可独立保留。
6. **文档与总验收**：同步中英文 README，执行全部门槛并检查 diff。任何阶段都不做配置迁移，因此发布回退只需 revert 对应阶段代码。

### 完成定义（DoD）

- 核心与服务首页在空安装态、单核心和双核心下均有固定 6 个语义入口；不存在“安装与重装”或独立“配置健康与兼容”入口，Xray 与 sing-box 生命周期页都按相同顺序显示“检查当前配置”“扫描升级风险”“试跑预发布版”，Geo 更新/状态/定时任务只出现在 `xrayGeoDataMenu`；渲染不访问网络。
- 两种核心的三个用户动作统一遵守 `0/1/2` 和“通过/需关注/失败/无法检查”；首页渲染不执行检查，前两项不联网且只读，预发布只在本地扫描通过后按需联网，动作失败或版本获取失败不得退出菜单进程。
- Xray 运行/严格只作为“检查当前配置”的内部阶段并共享一个执行器；运行失败为“失败”，运行通过而仅严格失败为“需关注”，预发布严格失败为阻断，菜单不存在独立普通/严格入口。
- Xray 静态兼容扫描无需本机二进制，每个 JSON 仅调用一次 `jq`，6 类规则无重复 finding；非法 JSON/legacy reverse 为阻断，其他已知项为 WARN。
- Xray 预发布检查先处理本地阻断项，再精确校验下载二进制实际版本并执行普通/严格检查；任何阻断都不操作服务、不替换文件且清理临时内容，通过升级时只复用同一已校验目录并在提交前重验当前配置；未安装 Xray 但保留有效配置时仍可 dry-run。
- sing-box 静态扫描无需本机二进制，每个 JSON 仅调用一次 `jq`，非法 JSON和现有 6 类迁移风险均阻断；预发布试跑先扫描、再核对目标二进制版本并执行 merge + check，独立试跑清理目录，升级复用同一已验证目录并在提交前重验。
- 子页无递归导航：无效输入留页，成功/失败/取消后重绘当前页，返回只退一层，EOF 安全返回；从核心首页返回后主菜单重新显示。
- Xray、sing-box、Nginx 的安装/运行状态统一；start/stop 幂等，restart 完整停启，Nginx reload 先校验；未知服务或动作返回非零。
- 队列保持顺序和精确去重，失败不短路后续项，结束后清空并恢复上下文；三个 `handle*` 和合并失败处理不再执行 `exit`。
- 非 padm 依赖的 Nginx 只读；refresh 四分支全部通过，迁移白名单的前向和回滚路径都能重新应用有效配置，白名单外调用保持原语义。
- 旧菜单函数名、服务处理器参数、队列入口、`reloadCore`、CLI、配置/状态格式、bootstrap 顺序和依赖保持兼容；中英文 README 同步。
- 语法与定向门槛通过：`bash -n` 覆盖所有改动的 `.sh`；`ui-full-core`、`ui-full-core-maintenance`、`xray-strict-validation`、`xray-compat-audit`、`xray-compat-trusted-xff`、`xray-configured-validation-path`、`xray-prerelease-dry-run`、`singbox-compat-audit`、`singbox-prerelease-dry-run`、`core-running-service-state`、`service-queue-apply-propagation`、`reload-core-propagation`、`nginx-service-failure`、`nginx-service-refresh` 逐个通过。
- 聚合与跨域门槛通过：`fast`、`platform-rest`、`transaction-core`、`transaction-system`、`reality-stream-enable`、`reality-stream-disable`、`subscribe-nginx-config-write`、`subscribe-nginx-service-failure`、`wireguard-menu-flow-control-restore` 和 `regression-dispatcher-contract` 通过；`git diff --check` 无错误且无范围外改动。

## 六轮审计结论

最终方案只新增简单 `case` 分派、一个共享 Xray 校验执行器、一个 sing-box 当前检查薄动作、现有 Bash 循环和一个必要的 refresh selector；两个生命周期页统一使用三项用户检查，Xray 严格模式只保留为内部阶段，安装与重装只留在主菜单。两种核心的规则继续写在现有代码中，不增加跨核心扫描框架、缓存、依赖或持久化结构。实施顺序固定为“核心检查链 -> 服务契约 -> Nginx refresh -> 菜单状态机 -> 文档与总验收”，每段都能独立验证和回退；未通过对应门槛时不得进入下一段。
