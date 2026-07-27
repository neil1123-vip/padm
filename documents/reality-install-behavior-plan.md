# Reality 安装行为修正计划

状态：已实施并验收通过。

基线：`main` / `8e28975`（`v2.1.8`）

## 目标

修正 Reality 安装行为，使 entry、端口、证书和 Nginx 各自职责明确，并确保 Xray/sing-box、交互/自动安装行为一致。

## 固定行为合同

| 场景 | 最终行为 |
| --- | --- |
| Reality `1/2/26` | 均不申请本机证书，不因本次安装依赖 Nginx |
| 严格域名模式 | 仅支持单选 Reality Vision `1`，Xray 与 sing-box 行为一致 |
| XHTTP、gRPC、多协议与 `--reality-domain yes` 组合 | 写配置或执行清理前直接报错 |
| entry 来源 | `--entry-host` > `--domain` > `/etc/padm/reality_entry_host` > `currentHost` > 公网 IP |
| 普通单选 Reality 端口 | 显式 `--port` > 历史端口 > `443` |
| 多协议端口 | 各协议维持独立随机端口，`--port` 不注入 Reality 子端口 |
| 纯 Reality 安装 | 不创建站点、不操作 ACME/Cron、不停止或重启 Nginx |
| 明确选择“不复用并清空旧配置” | 唯一允许执行既有全量清理的例外 |

## 实施步骤

### 1. 隔离工作区

实施时从当前 HEAD 创建 `codex/reality-install-contract` 独立 worktree。保留当前 `shell/core/entry_helpers.sh` 和 `shell/core/protocol_runtime.sh` 的未提交文案修改，并在新分支中按新行为合同重新纳入，避免污染 `main`。

### 2. 统一能力与安装路由

删除 `realityOnlyWithDomain` 对证书和 Nginx 能力的覆盖。快速安装、自定义安装、Xray 和 sing-box 共用同一套严格域名判断。

验收：Reality `1/2/26` 均不触发证书或 Nginx 安装能力；严格域名模式只对单选 Vision 生效。

### 3. 提前拒绝非法组合

`--reality-domain yes` 仅接受协议选择恰好为 Vision `1`。XHTTP `2`、gRPC `26` 或任何多选组合，在安装依赖、清理配置或写文件之前失败。

验收：失败路径不改变配置、entry、端口放行或任何服务状态。

### 4. 独立收集 entry

将严格域名 entry 输入从 ACME 流程移出。交互安装独立询问域名；自动安装没有可用域名时明确失败，不退回公网 IP。

验收：全新严格域名安装拥有独立输入入口；自动模式缺少域名时给出可操作错误。

### 5. 落实 entry 优先级和校验

严格执行以下优先级：

1. `--entry-host`
2. `--domain`
3. `/etc/padm/reality_entry_host`
4. `currentHost`
5. 公网 IP

严格域名模式验证域名格式和 DNS；非严格模式复用 `padmIsValidConnectAddress()`，兼容 IPv4、域名和纯 IPv6 VPS。只在安装成功后保留新的 entry。

### 6. 修正端口选择

普通单选 Reality 使用“显式端口、历史端口、443”顺序。多协议继续使用现有各协议端口初始化逻辑，不把顶层 `--port` 错当 Reality 子端口。

验收：单选的三个优先级分别覆盖；多协议中的 Reality 端口不受顶层 `--port` 注入。

### 7. 保护 Reality 443 共存

已启用 Reality 443 共存时：

| 输入 | 行为 |
| --- | --- |
| 未传 `--port` | 复用内部历史端口 |
| 显式端口等于已记录公网端口 | 接受输入，但不改变内部端口 |
| 显式传入其他端口 | 失败并要求先关闭共存 |

任何失败均不得停止或重启现有 Nginx、Xray 或 sing-box 服务。

### 8. 清除纯 Reality 的 Nginx 副作用

纯 Reality 安装不创建或删除站点，不申请证书，不操作续签任务，不停止、启动或重载 Nginx。`nginxRuntimeRequired()` 只负责判断既有功能是否需要安装或保留 Nginx，不决定本次 Reality 安装是否修改 Nginx。

### 9. 完善端口占用检测

Xray 和 sing-box 在提交模板前统一预检目标端口。`checkPort()` 优先识别 Nginx/OpenResty；目标端口被占用时直接失败并保持现有服务运行。

### 10. 补齐 Nginx 运行需求兜底

在没有 `jq` 时，通过现有配置文件检查以下既有 Nginx 使用场景：

- stream 配置
- `alone.conf`
- HTTPUpgrade
- 订阅服务
- 控制面

不新增依赖、状态文件或持久化格式。

### 11. 扩展事务回滚

模板事务同时备份 `/etc/padm/reality_entry_host`。任何配置生成、端口放行或服务应用失败，都恢复 entry、配置文件以及 Xray/sing-box 各自原始启停状态。

明确选择“不复用并清空旧配置”时，继续执行既有全量清理；这是唯一例外。

### 12. 统一界面和文档

更新菜单、TLS 状态、CLI 帮助、中英文 README。修正当前两处端口文案：TLS 入口不再描述为“域名 Reality 所需”，Reality 端口明确为客户端公网连接端口或共存内部端口。

### 13. 更新回归测试

删除“域名 Reality 会申请证书”的旧断言，并覆盖：

- Xray 和 sing-box 严格域名 Vision
- XHTTP、gRPC 和多协议非法严格域名组合
- entry 五级优先级、交互输入、自动安装失败和 IPv6
- 单选端口优先级及多协议端口隔离
- Reality 443 共存的三种输入分支
- Nginx/OpenResty 端口占用及服务保持
- `nginxRuntimeRequired()` 无 `jq` 兜底
- entry、配置及双核心服务状态回滚
- 明确全量清理例外

## 验证顺序

1. 对相关 Shell 文件执行 `bash -n`。
2. 运行新增的最小定向回归。
3. 复跑现有 `protocol-capabilities`、Reality 安装失败、模板事务、服务动作和自动安装路由测试。
4. 运行相关完整回归入口。
5. 执行 `git diff --check`，确认没有格式错误。
6. 检查最终差异，确认未引入依赖、持久化格式、状态机、菜单层级或无关重构。
7. 核对 Nginx、Xray 和 sing-box 在成功与失败路径中的最终服务状态。

## 完成标准

- Reality `1/2/26` 的安装路径不申请本机证书。
- 纯 Reality 不安装、清理或操作 Nginx；既有 Nginx 服务不受影响。
- 严格域名只允许单选 Vision，所有非法组合在产生副作用前失败。
- entry、端口和 443 共存行为符合固定合同，并覆盖 IPv6。
- 安装失败可以恢复 entry、配置和两个核心的原服务状态。
- 相关文案、README 和测试与实际行为一致。
- 所有定向验证通过，`git diff --check` 无错误。

## 边界

- 不新增依赖。
- 不改变现有持久化格式。
- 不新增状态机、菜单层级或预留扩展点。
- 不混入无关重构和格式化。
- 未经用户再次确认，不提交、不推送。
