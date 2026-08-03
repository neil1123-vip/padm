# WireGuard 被控邀请与接入回执计划

状态：功能实现、功能分支验收、合并态验收、两台测试 VPS 现场验收和最终清场均已完成。

基线：`main` / `14a4075`（`v2.2.0` 后 1 个本地修复提交）。Peer 状态完整性修复已合并并通过合并态定向回归。

实施：功能分支 `codex/wireguard-invite-onboarding`，功能提交 `9408559`；验收中发现并由 `80d97e9` 修复根级 README 未被卸载的问题。

## 目标

将现有“主控凭据 -> 被控填写地址并导入 -> 被控凭据 -> 主控填写别名并添加”调整为：

```text
主控创建邀请 -> 被控导入并生成回执 -> 主控导入回执并自动验收
```

完成后应满足：

1. 被控不再手工填写 WireGuard 地址。
2. 主控只输入一次被控别名。
3. 主控自动分配并预留地址。
4. 被控只粘贴一次邀请，主控只粘贴一次回执。
5. 主控完成接入后自动检查 WireGuard 和控制服务健康。
6. 旧 `main` / `controlled` 凭据和维护流程继续可用。
7. 不新增公网注册服务，不要求额外证书。

## 固定范围

本计划只优化新增被控服务器的离线接入流程。双方私钥仍在各自服务器本地生成，因此双向公钥交换不能取消。

包含：

- 主控创建、查看、取消和消费待完成邀请。
- 主控预分配别名和 WireGuard 地址。
- 被控一次完成初始化、主控 Peer 导入和回执生成。
- 主控一次完成 Peer、服务器源和控制 Token 写入。
- 旧凭据兼容和接入后的健康检查。

不包含：

- 公网自动注册 API、回调服务或新的 TLS 入口。
- SSH 远程编排、二维码、剪贴板同步或批量注册。
- 现有“更新被控服务器凭据”流程重构。
- 任意 CIDR 的通用地址池；第一版只覆盖 padm 当前受管 `/24` 网络。
- 新依赖或手工修改 `SCRIPT_VERSION`。

## 目标流程

### 主控创建邀请

1. 用户输入被控别名，例如 `hk-1`。
2. 主控清理过期邀请，检查别名未被 Peer、服务器源或其他邀请占用。
3. 主控从当前 `/24` 网络的 `.2` 到 `.254` 选择首个未被本机、Peer 或邀请占用的地址。
4. 主控把别名、地址和有效期写入待完成邀请。
5. 主控输出一段被控邀请，供用户复制到被控服务器。

### 被控导入邀请

1. 被控在任何安装或状态写入前解析并校验邀请。
2. 被控执行现有角色转换预检，安装 WireGuard 工具并生成本机密钥。
3. 被控一次写入角色、网络、本机地址、主控 Peer 和邀请标识。
4. 被控只应用一次 WireGuard 配置，并安装 WireGuard 内网控制服务。
5. 被控生成接入回执，供用户复制回主控。

### 主控完成接入

1. 主控解析回执，通过邀请标识查找本地待完成邀请。
2. 主控只信任本地预留的别名和地址，不接受回执覆盖。
3. 主控在锁内增加或核对 Peer，但保留待完成邀请作为中断恢复点。
4. 主控应用 WireGuard，再写入或核对服务器源和控制 Token；已有字段只有完全匹配时才按幂等续跑。
5. 所有本地状态提交成功后，主控最后一次原子写入删除待完成邀请。
6. 可捕获的提交失败恢复旧 WireGuard 状态、配置、订阅组状态和待完成邀请；进程中断后在邀请有效期内再次导入同一回执可从保留的邀请续跑。
7. 提交成功后按本次预留别名读取刚加入的来源，并复用现有单源健康检查，显示健康或“已添加但暂不可达”。其他被控的状态不影响本次结果，健康失败不删除已添加配置。

## 凭据合同

继续使用 `padmwg1:` 和 JSON `version:1`，扩展 `invite` 和 `receipt` 两种 `kind`。新版解码器同时接受原有 `main`、`controlled`。

所有类型在 Base64URL 解码前统一执行包络校验：总长度不超过 4096 字节、前缀必须精确匹配、负载只能包含 Base64URL 字符。解码结果必须是单个 JSON 对象，不接受数组、标量、尾随内容或未知 `kind`。

### 邀请

```json
{
  "version": 1,
  "kind": "invite",
  "invite_id": "64 位十六进制随机值",
  "alias": "hk-1",
  "address": "10.77.0.2/24",
  "network": "10.77.0.0/24",
  "main_address": "10.77.0.1/24",
  "endpoint_host": "main.example.com",
  "listen_port": 51820,
  "main_public_key": "WireGuard 公钥",
  "expires_at": 1780000000
}
```

### 回执

```json
{
  "version": 1,
  "kind": "receipt",
  "invite_id": "与邀请一致",
  "public_key": "被控 WireGuard 公钥",
  "control_port": 39778,
  "token": "被控控制 Token"
}
```

`invite_id` 使用现有控制 Token 的安全随机源模式生成 32 字节随机数，并编码为 64 位小写十六进制；它同时承担查找标识和一次性授权能力。别名限制为 1 到 64 个 `[A-Za-z0-9_-]` 字符。新回执中的控制 Token 必须是现有生成器产生的 64 位字母数字值。默认有效期固定为 24 小时，`expires_at` 必须是正整数。回执不携带别名和地址，避免主控信任被控返回的可变身份字段。

时间、随机值和无回显读取分别通过 `wireguard_control.sh` 内的最小局部函数取得，供多个邀请操作复用，也允许回归通过覆盖函数得到确定性输入。不新增用户配置、环境变量或通用框架。

## 安全与信任边界

`padmwg1` 是 Base64URL 编码，不是加密、签名或身份认证。邀请中的 `invite_id` 只能让主控确认回执对应本机尚未消费的邀请，不能让一台从未信任过主控的被控服务器证明“这确实是预期主控”。双方仍必须通过可信的人工通道传递并核对邀请/回执；本计划不声称解决首次信任问题。

秘密处理合同：

- 新邀请和回执都按 bearer secret 处理；获得未消费邀请的人可以提交自己的被控公钥，获得回执的人同时获得长期控制 Token。
- 新邀请只在创建结果中显示一次；丢失时取消并重新创建，不在待完成列表中重新显示。
- 被控加入成功时显示一次回执；之后只能通过明确的“显示接入回执/兼容凭据”操作重新显示。
- 普通“查看本机状态”、健康结果、邀请列表和安装日志不得输出完整邀请、`invite_id`、回执或控制 Token。
- 粘贴邀请和回执使用本地无回显读取；非交互测试输入仍可从标准输入读取，但不得把值打印回终端。
- `control.json`、WireGuard 密钥和控制 Token 文件继续以 `0600` 保存，其父目录保持 `0700`。
- 主控和被控都检查邀请有效期；主控状态中的 `expires_at` 是最终判定依据。被控发现本机时间已超过有效期时在任何写操作前失败，并提示先校准系统时间或重建邀请。

## 状态合同

`/etc/padm/wireguard/control.json` 增加可选字段：

```json
{
  "pending_invites": [
    {
      "invite_id": "...",
      "alias": "hk-1",
      "address": "10.77.0.2/24",
      "expires_at": 1780000000
    }
  ],
  "join_invite_id": "..."
}
```

规则：

- 主控使用 `pending_invites`；被控使用 `join_invite_id`。
- 旧状态没有字段时按空数组或空值处理，不执行迁移。
- 新版严格校验可选字段的类型、别名、地址、有效期和唯一性。
- 尚未开始完成接入的邀请不进入 `.peers`。完成回执期间，邀请可以与别名、地址完全一致的 Peer 暂时共存，直到来源和 Token 写入成功后再消费；WireGuard 配置始终只读取 `.peers`。
- 创建、查看和完成邀请时顺带清理尚未进入提交阶段的过期项，不新增 cron。已经关联部分 Peer/来源的过期邀请保留为“接入未完成且已过期”，拒绝继续提交，供用户显式取消并清理部分状态。
- 邀请列表只显示别名、地址和过期时间，不显示 `invite_id`。
- 邀请列表同时显示本机时区下的过期时间、剩余时长和“待接入/接入未完成”状态；取消操作按唯一别名选择并再次确认，不要求用户输入已隐藏的 `invite_id`。
- 被控保留 `join_invite_id`，以便用户通过显式操作重新显示回执；普通状态页不自动显示。主控消费后重放仍会失败。
- 同一 `pending_invites` 内部的标识、别名和地址必须唯一。邀请与活动 Peer/服务器源发生冲突时不把整个控制状态判为损坏：别名和地址完全一致但来源或凭据尚未完成时保留邀请供同一回执续跑；活动 Peer、来源和凭据已经完整，或身份字段不一致时，以活动状态为权威并清理陈旧邀请。
- 旧 `main` 凭据导入、手工地址更新或其他不再绑定当前邀请的维护操作必须删除 `join_invite_id`，不得重新显示已经失去绑定关系的回执。

## 地址分配合同

第一版只接受主控当前网络前缀为 `/24`：

1. 排除网络地址 `.0`、约定主控地址 `.1` 和广播地址 `.255`。
2. 在现有 groups 锁内读取一致快照，排除 `control.json` 本机地址、已有 Peer 地址、活动服务器源和待完成邀请地址。
3. 从 `.2` 到 `.254` 返回第一个空闲地址。
4. 地址耗尽时不写邀请并明确报错。
5. 检测到非 `/24` 网络时拒绝自动邀请，提示使用旧凭据流程。
6. 创建、取消、完成邀请、被控导入邀请或旧主控凭据，以及旧版 Peer/来源添加、更新、移除，共用本机现有 `subscriptionGroupsWithLock()`；不增加第二个锁文件。依赖安装和密钥准备在锁外完成，锁覆盖快照、状态/服务提交与恢复，不覆盖提交后的健康等待和事件同步。

## 状态与服务事务

### 创建或取消邀请

- 创建邀请和取消尚未产生 Peer/来源的邀请只原子写入 `control.json`，不重写 WireGuard 配置，不重启服务。
- 中断后邀请已关联部分 Peer 或来源时，取消操作在现有 groups 锁内复用移除事务，清理该别名的部分 Peer、来源和凭据并应用 WireGuard，最后删除邀请；任一步失败恢复取消前状态。
- 已有 Peer、来源和凭据完整时把邀请视为本地提交已完成，只清理陈旧邀请并提示改用“移除被控服务器”，避免取消入口删除活动服务器。
- 候选状态必须通过完整状态校验后才能替换现有文件。

### 被控导入邀请

- 在写入前保存旧 WireGuard 状态。
- 邀请校验、角色预检、依赖安装和密钥读取在锁外完成；取得现有 groups 锁后重新核对当前状态，再保存快照并单次写入完整被控状态。
- WireGuard 应用、控制面 Nginx 或控制服务失败时复用现有恢复入口。
- 成功安装控制面后才输出回执。
- 失败恢复覆盖角色状态、WireGuard 配置、WireGuard/Nginx/控制服务状态和受管 Nginx 配置；已安装的软件包、新生成的 WireGuard 密钥及控制 Token 保持 `0600` 留存并在重试时复用，不宣称回滚这些身份工件。
- 已经接入主控的被控导入不同邀请时，必须在任何写入前明确确认替换现有主控；导入同一 `invite_id` 时，还必须核对本机地址、网络、主控地址、公钥和 endpoint 与现状完全一致，才按幂等重试重新应用未完成的服务步骤，任一字段变化都拒绝覆盖。
- 取锁超时或取得锁后发现状态已变化时不写入，明确提示重新执行，不使用锁外旧快照覆盖并发维护结果。

### 主控消费回执

- 取得现有 groups 锁后读取旧 WireGuard 状态和旧 groups.json；整个快照、Peer/来源/Token 提交、最终邀请消费和失败恢复都在锁内，嵌套 groups 写入复用已持有的锁。
- 复用现有 Peer/来源/Token 事务，不创建第二套添加实现；旧凭据添加、更新和移除也进入同一顶层锁，避免与邀请地址分配交错。
- 先保留邀请并增加或核对 Peer，再应用 WireGuard、写入或核对来源和 Token，最后原子删除邀请。已有 Peer、来源、端口、公钥或 Token 与回执不一致时失败，不借幂等重试覆盖活动身份。
- WireGuard 应用、来源写入或 Token 写入失败时恢复旧状态、配置和 groups.json；恢复后的邀请仍可重试。
- 若进程在最终消费前异常退出，邀请仍在；有效期内重新粘贴同一回执会核对已完成阶段并续跑，过期后只能显式取消并清理部分状态。最终消费发生在所有本地状态完整之后，因此邀请消失即表示本地提交已完成。本计划不新增写前日志。
- 健康检查和事件同步在释放锁后执行，属于提交后验收，不属于回滚条件。
- 接入后健康检查只按本次邀请的别名读取一个来源并调用现有 `subscriptionRemoteControlHealth()`；全量健康页仍供日常查看，不用其汇总结果判定本次接入。
- “完成接入”的成功与否只由本地事务提交决定。提交后健康或事件同步失败时显示“接入已保存，但健康/同步异常”，不得再次输出“被控服务器添加失败”，也不得把已经消费的回执描述成可重试的提交失败。

## 菜单调整

主控“添加/移除被控服务器”调整为：

1. `创建被控邀请`
2. `完成被控接入`
3. `查看/取消待完成邀请`
4. `移除被控服务器`
5. `返回多服务器协同`

“完成被控接入”自动识别新 `receipt` 或旧 `controlled` 凭据。旧凭据仍询问别名，新回执不再询问。

主控建链向导初始化成功后允许创建第一个邀请或稍后返回，不强制立即添加被控。

主控初始化和邀请结果明确说明：WireGuard 使用 UDP 隧道，控制 API 只在隧道内使用 HTTP，因此这一步不申请 TLS 证书；只有公网发布订阅时才单独配置 HTTPS 域名和证书。

被控“接入主控”先读取凭据：

- `invite`：使用主控预留地址，一次完成加入并输出回执。
- `main`：进入旧流程，继续询问本机地址并输出旧 `controlled` 凭据。

被控维护页保留旧被控凭据展示，供现有 Token/地址更新流程使用。

兼容凭据不混在普通状态或邀请列表中：主控“控制面与连接细节”提供“显示旧版主控凭据”，被控维护页提供“显示接入回执/旧版被控凭据”，并在输出前提示回执或旧版被控凭据包含长期控制 Token。取消邀请只使用列表中可见的别名。

被控普通“查看本机状态”只显示角色、地址、Peer、WireGuard 和同步结果，不自动调用包含控制 Token 的凭据展示函数。敏感凭据统一放到明确命名的显示操作中，并在显示前提示其包含长期控制 Token。

## 兼容合同

| 组合 | 行为 |
| --- | --- |
| 新主控 + 新被控 | 使用邀请/回执流程 |
| 新主控 + 旧被控 | 主控仍可显示旧 `main` 凭据并接受旧 `controlled` 凭据 |
| 旧主控 + 新被控 | 新被控接受旧 `main` 凭据并输出旧 `controlled` 凭据 |
| 旧状态 + 新程序 | 缺少新增可选字段时按空值读取 |
| 新状态 + 旧程序 | 旧程序可忽略并保留额外字段，但不能维护邀请语义；降级前应取消待完成邀请 |

旧程序不能解析新 `invite` / `receipt`，必须通过旧凭据路径互通。新版遇到不支持的 kind 或字段必须失败，不得猜测或降级解释。若旧程序在未取消邀请时新增了冲突 Peer/来源，重新升级后由邀请操作清理陈旧邀请，活动 Peer/来源保持不变；不能用严格校验把可恢复兼容状态变成启动阻塞。

## 失败合同

| 场景 | 行为 |
| --- | --- |
| 邀请包络、格式、字段或有效期无效 | 被控在安装和写状态前失败 |
| 主控别名或地址冲突 | 不生成邀请 |
| 被控 WireGuard 或控制服务应用失败 | 恢复旧状态、配置和服务；保留已安装包、密钥和 Token 供重试 |
| 回执未知、过期、已取消或已消费 | 主控不写 Peer、来源或 Token |
| 主控 WireGuard 应用失败 | 恢复旧状态、配置和待完成邀请 |
| 来源或 Token 写入失败 | 恢复 WireGuard、groups.json 和待完成邀请 |
| 进程在主控最终消费邀请前中断 | 保留邀请；有效期内再次导入同一回执并严格核对已有字段后续跑，过期后转为显式取消清理 |
| 取消接入未完成的邀请 | 二次确认后事务性清理该别名的部分 Peer/来源；失败恢复取消前状态 |
| 取锁超时或锁内状态已变化 | 不写入并提示重新执行 |
| 健康检查暂时失败 | 保留接入结果并提供重试入口 |

## 实现控制点与文件归属

| 文件 | 计划内改动 |
| --- | --- |
| `shell/subscription/wireguard_control.sh` | 包络/类型校验、局部时间/随机/秘密读取函数、可选状态字段、地址分配、邀请生命周期、锁内 Peer 事务和回执生成 |
| `shell/subscription/menu.sh` | 主控/被控向导、邀请管理菜单、显式秘密展示及提交后健康结果文案 |
| `shell/regression/subscription_groups_legacy.sh` | 菜单、邀请生命周期、事务失败、并发锁、秘密展示和旧流程回归 |
| `shell/regression/subscription_groups_subscription_state_full.sh` | 四种凭据包络与状态结构回归 |
| `README.md` | 中文多服务器推荐流程与秘密提示 |
| `documents/en/README_EN.md` | 英文多服务器推荐流程与秘密提示 |
| `documents/wireguard-invite-receipt-plan.md` | 实施结果、偏差和最终验收证据回填 |

现有 `subscriptionGroupsWithLock()`、远端 endpoint/health 和事件同步函数直接复用，默认不修改 `groups.sh`、`control.sh`、`runtime.sh` 或回归注册文件。实现中若证据证明必须扩大文件范围，应先在本计划记录原因和新的验证责任，不能为方便随意扩散。

## 实施步骤

1. 以已合并的 `14a4075` 为基线，复用候选状态完整校验和空 Peer endpoint 合同。
2. 扩展凭据解码和 `invite` / `receipt` 字段校验，保留旧类型。
3. 扩展状态校验，增加待完成邀请的创建、列出、取消、过期/冲突清理和地址分配。
4. 用现有 groups 锁串行化双方接入状态及现有 Peer/来源变更；主控保留邀请到 Peer、来源和 Token 全部完成后再消费，使同一回执可在异常中断后续跑。
5. 调整被控向导，在写操作前解析凭据，并让新邀请路径一次完成初始化和主控 Peer 导入；不同主控替换需明确确认。
6. 增加回执生成和重新显示入口；旧凭据导入或身份变更时清除失效的邀请绑定。
7. 增加主控消费回执入口，复用现有 Peer/来源/Token 事务并原子消费邀请。
8. 调整主控和被控菜单文案，自动识别新旧凭据。
9. 复用现有 WireGuard endpoint 等待、远端 health 和事件同步入口完成接入后验收，并把提交成功与后置异常分开报告。
10. 更新中英文 README 和本计划的实施状态、实际文件及验收结果。

## 测试矩阵

### 凭据和状态

- `invite`、`receipt`、`main`、`controlled` 编解码往返。
- 超长、非 Base64URL、非法 JSON、非法 kind、版本、随机标识、别名、地址、端口、公钥、Token 和有效期均失败。
- 新 `receipt` 只接受现有生成器产生的 64 位字母数字 Token；旧 `controlled` 继续接受旧验证器允许的非空无空白 Token，例如现有测试凭据，不因新合同收紧。
- 无新增字段的旧状态可读取；新增字段类型或角色组合错误时明确失败。
- 仅创建待完成邀请不会产生 Peer 或改变 WireGuard 配置；回执完成阶段的配置只读取 `.peers`，不直接读取邀请。
- 普通状态、健康结果、邀请列表和安装日志不包含完整秘密；只有明确的生成或显示操作输出凭据。
- 旧程序遗留的 Peer/来源与邀请冲突时清理邀请而不损坏活动配置；失去绑定的 `join_invite_id` 不再生成回执。

### 地址和邀请生命周期

- 首个邀请分配 `.2`，已有 Peer 或邀请占用时顺延。
- 本机地址、网络地址、广播地址不被分配。
- 别名重复、地址耗尽、非 `/24` 网络均在写入前失败。
- 取消或过期邀请释放地址。
- 待完成列表不显示 `invite_id`，可按列表中的唯一别名取消；未确认取消时状态不变，取消中断留下的部分接入时一并清理对应 Peer/来源并覆盖失败恢复。
- 已消费邀请不能重放，失败回滚后的邀请可以重试。
- 模拟进程在 Peer、WireGuard、来源和 Token 各阶段后中断时，邀请在有效期内仍可用；同一回执续跑成功，字段不一致的回执不得覆盖已有状态。
- 部分接入跨过有效期后不再接受回执，也不被自动清成孤立 Peer；列表保留为已过期未完成项，显式取消可清理部分状态。
- 两个并发创建/完成操作经现有 groups 锁串行执行，不产生重复地址或覆盖其他进程的 groups.json 更新。
- 取锁超时和取得锁后快照变化均在写入前失败；被控导入与本机维护并发时同样串行。

### 被控流程

- 新邀请不询问地址，一次写入本机地址和主控 Peer。
- 主控 endpoint、公钥、地址和网络来自邀请且完整校验。
- WireGuard、Nginx 控制面和控制服务各失败点恢复旧状态与配置。
- 后置失败时新生成的密钥和控制 Token 安全留存，重试沿用同一公钥和 Token。
- 相同 `invite_id` 只有在地址、网络、主控地址、公钥和 endpoint 全部一致时可续跑；篡改任一邀请字段不得覆盖当前状态。
- 已接入被控替换为不同主控前必须确认；拒绝确认时状态、配置和服务不变。
- 回执丢失后可以重新显示。
- 旧 `main` 凭据流程继续询问地址并输出旧凭据。

### 主控流程

- 新回执自动使用预留别名和地址，Peer endpoint 为合法空字符串。
- 成功后 Peer、服务器源和控制 Token 一致，邀请被删除。
- WireGuard 应用、来源写入和 Token 写入失败均恢复邀请和旧状态。
- 在最终邀请消费前模拟无清理中断，再次导入同一回执可补齐缺失阶段；邀请消费后本地 Peer、来源和 Token 必须已经一致。
- 失败恢复不会覆盖同一锁外的并发 groups.json 写入；健康等待不长期占用 groups 锁。
- 未知、过期、取消、重复回执在任何写入前失败。
- 健康成功显示已完成；健康失败保留配置并显示重试提示。
- 接入后只检查新别名；另一个既有来源故障时，不得污染本次健康结果。
- 健康或事件同步失败不把已提交接入误报成“添加失败”，来源继续使用现有 pending/failed 状态记录后置结果。
- 旧 `controlled` 凭据仍询问别名并走原事务。

### 基础回归与命令门

Windows 本地验收显式使用仓库内可写 `TMPDIR/HOME` 和 MSYS2 PATH。实现 worktree 中执行以下 PowerShell，命令在任一处失败即停止：

```powershell
$taskWorktreePath = 'E:\CC\padm\.worktrees\wireguard-invite-onboarding'
$env:PADM_TEST_WORKTREE = $taskWorktreePath
$env:TMPDIR = "$taskWorktreePath\.tmp-msys\tmp"
$env:HOME = "$taskWorktreePath\.tmp-msys\home"
New-Item -ItemType Directory -Force -Path $env:TMPDIR, $env:HOME | Out-Null
$bashCommands = @'
set -euo pipefail
cd "$(cygpath -u "$PADM_TEST_WORKTREE")"
PATH=/d/msys64/usr/bin:/d/msys64/clang64/bin:/d/msys64/mingw64/bin:$PATH
export PATH
bash -n shell/subscription/wireguard_control.sh shell/subscription/menu.sh \
  shell/regression/subscription_groups_legacy.sh \
  shell/regression/subscription_groups_subscription_state_full.sh
shell/subscription_groups_regression.sh subscription-state-structure-foundation-credential
shell/subscription_groups_regression.sh wireguard-menu-flow-bootstrap
shell/subscription_groups_regression.sh wireguard-menu-flow-peer-add-update
shell/subscription_groups_regression.sh wireguard-menu-flow-peer-rollback
shell/subscription_groups_regression.sh ui-full-subscription-main-entry
shell/subscription_groups_regression.sh ui-full-subscription-controlled
shell/subscription_groups_regression.sh wireguard-menu-flow
git diff --check
git diff --exit-code main -- shell/core/version.sh
'@
& 'D:\msys64\usr\bin\bash.exe' -lc $bashCommands
```

定向回归必须通过覆盖局部时间和随机函数固定 `now`、`invite_id`，不能依赖真实等待或概率。无回显读取需覆盖 TTY 分支的输出不含输入值，以及非 TTY/here-string 回归仍可驱动菜单。

功能提交合并到最新 `main` 后，在合并态至少复跑凭据结构、Peer 添加、Peer 回滚、完整 `wireguard-menu-flow`、`bash -n` 和 `git diff --check`。只有功能分支和合并态证据都通过，才进入 VPS 验收。

## 现场验收

在两台全新测试 VPS 上执行：

1. 主控创建 `hk-1` 邀请，确认自动预留 `.2`。
2. 被控粘贴邀请，确认没有地址输入且生成回执。
3. 主控粘贴回执，确认没有别名输入，WireGuard endpoint/握手和 health 成功。
4. 创建第二个邀请，确认自动分配 `.3`。
5. 重放第一份回执，确认写入前失败。
6. 取消和模拟过期邀请，确认地址可以重新分配。
7. 使用旧 `main` / `controlled` 凭据完成一次兼容接入。
8. 检查 `/etc/padm/install.log`、普通状态、健康结果和邀请列表不包含完整邀请或控制 Token；生成结果与显式凭据展示除外。
9. 检查 `control.json`、WireGuard 私钥和控制 Token 权限为 `0600`，父目录为 `0700`。
10. 人为阻断一次健康检查，确认主控显示“接入已保存但暂不可达”，Peer、来源和已消费邀请状态不回滚。

现场证据至少保存：两端角色/地址/Peer 摘要、主控针对该来源的 health JSON、重放失败提示、权限检查和日志秘密扫描结果。证据中必须遮蔽邀请、回执、完整公钥以外的长期 Token 和 DNS API 凭据。

现场验收前必须轮换此前已暴露的 Cloudflare API Token 和被控控制 Token，不复用聊天中出现过的凭据。

## 实施与自动验收记录

日期：2026-07-29 至 2026-07-30。

实施结果：

- `9408559 feat(subscription): add WireGuard invite onboarding` 完成邀请/回执合同、待完成邀请状态、`/24` 地址预留、双方事务与恢复、幂等续跑、旧凭据兼容、单来源健康检查和显式秘密展示入口。
- 邀请/回执功能差异为下列预计清单中的前 6 个文件；现场完整卸载另以最小补丁修改 `manage.sh` 和对应快速回归。没有修改 `groups.sh`、公共控制 API、TLS/公网入口、依赖或 `shell/core/version.sh`。
- 普通状态、健康输出和待完成列表不显示完整邀请、回执或控制 Token；完整秘密只在创建结果或明确命名的展示操作中输出。
- 完整聚合回归首次发现一条旧断言仍要求普通状态页显示主控凭据；只修正该回归为“状态仍可查看且不含 `padmwg1:`/测试 Token”，孤立复验与聚合复验随后均通过，生产代码未因此调整。

功能分支验收（`E:\CC\padm\.worktrees\wireguard-invite-onboarding`）：

- 四个改动 Shell 文件 `bash -n` 通过。
- `subscription-state-structure-foundation-credential`、`wireguard-menu-flow-bootstrap`、`wireguard-menu-flow-peer-add-update`、`wireguard-menu-flow-peer-rollback`、`ui-full-subscription-main-entry`、`ui-full-subscription-controlled` 全部通过。
- 完整 `wireguard-menu-flow` 最终通过，聚合耗时 `303618ms`；失败恢复、来源控制、邀请生命周期和菜单子项均返回成功。
- `git diff --check` 通过；`git diff --exit-code main -- shell/core/version.sh` 通过；差异和秘密输出扫描通过。

合并态验收（本地 `main` / `9408559`）：

- 四个改动 Shell 文件 `bash -n` 通过。
- 凭据结构 `13792ms`、Peer 添加/更新 `91789ms`、Peer 回滚聚合 `104856ms`、完整 `wireguard-menu-flow` `306533ms`，全部通过。
- 合并态 `git diff --check` 通过，工作区干净；本任务未推送。

现场验收（Debian 13，A 主控 / B 被控）：

- 验收前确认 `a.951101.xyz` 的 A 记录为 A 公网地址；聊天中暴露的 Cloudflare API Token 已由用户撤销，现场未使用该 Token。两台旧安装先经各自卸载器清理，再部署同一份本地 `caf5d04` 归档；远端 SHA-256、manifest 和 ref 均一致。
- A 初始化为 `10.77.0.1/24` 主控，B 仅接收一行邀请后初始化为 `10.77.0.2/24` 被控并生成回执；A 仅接收一行回执后以预留别名 `hk-1` 完成提交。两端接口均为 `wg-padm`，Peer 地址一致。
- 完成接入前人为停止 B 的控制服务；A 显示“接入已保存，但暂不可达”，同时 Peer、服务器源、64 位控制 Token 已提交且邀请已消费。恢复服务后 WireGuard 最新握手非零，单来源 health 返回 `{"id":"hk-1","ok":true,"version":"v2.2.0","capabilities":["health","sync","subscribe"]}`。
- B 通过显式入口重新显示同一回执后重放；A 返回“接入回执未知、已取消或已消费”，且 `control.json`、`groups.json` 和 WireGuard 配置的组合哈希前后不变。
- 第二个邀请自动分配 `10.77.0.3/24`。待完成列表显示别名和地址但不显示完整凭据或 `invite_id`；取消后新邀请复用 `.3`，模拟过期后下一邀请再次复用 `.3`，最终无待完成邀请。
- 旧兼容流程经强制 PTY 验证：B 导入旧 `main` 凭据时出现地址输入，A 添加旧 `controlled` 凭据时出现别名输入；旧导入清除 `join_invite_id`，`legacy-b` health 成功。
- 两端 `control.json`、WireGuard 私钥、控制 Token 和 `groups.json` 均为 `0600`，WireGuard 与 Token 父目录均为 `0700`。安装日志、普通状态、health 和待完成邀请列表均未出现实际控制 Token、`padmwg1:` 或 `cfat_`；完整秘密只在明确生成/显示入口出现。
- 两端 `shell/validate_install.sh` 均为 `PASS=21 WARN=9 FAIL=0`；现场功能验收完成后均调用产品卸载器清场。

现场验收发现与闭环：

- 首轮清场时，两台均只残留安装器同步的 `/etc/padm/README.md`；服务、WireGuard 接口/配置、Xray、快捷方式、上传包和 padm 防火墙标记均已清除，Nginx 保持 active。
- 根因为 `cleanupPadmManagedRootOnUninstall()` 的受管路径漏列根级 README。`80d97e9 fix(core): remove deployed readme on uninstall` 只增加该路径，并在 `runUninstallPadmRootScopeRegression()` 增加删除断言，同时继续保留未知 `custom/` 内容。
- `bash -n`、`git diff --check` 和 `fast-only-safety` 通过；后者包含卸载根目录范围、相邻路径安全与 WireGuard 防火墙生命周期，耗时 `97025ms`。
- 使用 `80d97e9` 在 A/B 再次完整安装，确认根级 README 已部署；随后再次完整卸载，两台均确认 `/etc/padm` 不存在、Nginx active、无 padm 防火墙标记，上传归档和暂存目录已删除。

## 预计影响文件

- `shell/subscription/wireguard_control.sh`
- `shell/subscription/menu.sh`
- `shell/regression/subscription_groups_legacy.sh`
- `shell/regression/subscription_groups_subscription_state_full.sh`
- `README.md`
- `documents/en/README_EN.md`
- `documents/wireguard-invite-receipt-plan.md`
- `shell/core/manage.sh`（现场验收发现的卸载闭环修复）
- `shell/regression/subscription_groups_fast.sh`（对应最小回归）

具体实现以调用链为准，不为满足文件清单制造无效改动。

## 提交与版本

计划审计使用当前独立 worktree `wireguard-invite-onboarding-plan` 和分支 `codex/wireguard-invite-onboarding-plan`，只提交本计划。计划合并并清理后，功能实施另建 worktree `wireguard-invite-onboarding` 和分支 `codex/wireguard-invite-onboarding`。

实际提交顺序：

1. `docs(subscription): plan WireGuard invite onboarding`
2. `feat(subscription): add WireGuard invite onboarding`
3. `docs(subscription): record WireGuard invite acceptance`
4. `fix(core): remove deployed readme on uninstall`
5. `docs(subscription): record VPS invite acceptance`

`docs(subscription)` 和现有 `fix(subscription)` 属于 patch 候选，`feat(subscription)` 属于 minor 候选。最终版本取决于推送时最新标签及其后的全部提交，由发布自动化统一计算；本地计划不预测或写死版本号，不手工修改 `SCRIPT_VERSION`，也不在本任务推送。

计划文档提交前执行 `git diff --check`、搜索遗留审计占位并核对五轮审计记录。功能实施完成后更新本计划的状态、实际提交、影响文件、自动回归和 VPS 证据，再创建第 3 个文档提交。

## 完成标准

- 新增被控流程只要求一次邀请粘贴和一次回执粘贴。
- 地址和别名由主控唯一预留，不依赖被控自行选择。
- 新旧凭据路径均有严格类型校验且可以明确互通。
- 被控初始化和主控消费回执均符合既定失败恢复合同。
- 邀请过期、取消、消费和重放行为确定且可测试。
- 健康检查失败不会破坏已经提交的接入状态。
- 公网订阅、TLS 和控制 API 暴露面不发生变化。
- 定向测试、相关现有回归和两台测试 VPS 现场验收全部通过。

## 审计记录

### 第 1 轮：协议与安全

| 级别 | 代码证据与缺口 | 计划修订 |
| --- | --- | --- |
| 高 | `subscriptionWireGuardCredentialEncode()` 只执行 Base64URL，凭据没有加密或签名；初稿没有说明首次信任边界 | 明确邀请/回执必须走可信人工通道；`invite_id` 只授权主控消费回执，不证明主控身份 |
| 高 | `showSubscriptionCurrentRoleCredential()` 会在普通被控状态页调用含控制 Token 的凭据展示 | 普通状态页不再自动展示秘密；回执和兼容凭据只在生成结果或显式操作中显示 |
| 中 | 当前解码器在 Base64 解码前没有输入长度和字符集上限 | 增加 4096 字节包络上限、Base64URL 字符检查和单对象 JSON 要求 |
| 中 | `autoRead()` 使用普通 `read -r -p`，粘贴秘密会回显 | 新邀请/回执输入改用局部无回显读取，不扩大到无关输入路径 |
| 中 | 初稿只写固定 24 小时，没有说明两台机器时钟和最终判定方 | 主控的待完成状态为最终依据；被控也做前置到期检查并对时钟异常给出明确提示 |

审计后保留 `padmwg1` 和离线传递方案。新增签名无法在没有预置信任锚的被控上解决首次信任，公网注册服务又超出既定攻击面，因此不引入伪安全的签名层或新网络入口。

### 第 2 轮：状态事务与兼容

| 级别 | 代码证据与缺口 | 计划修订 |
| --- | --- | --- |
| 高 | `subscriptionWireGuardAddPeerFromCredential()` 跨 `control.json`、WireGuard 和 groups.json 操作，但现有 groups 锁只包围单次 groups 写入；快照恢复可能覆盖并发变化 | 创建、取消、完成邀请及旧 Peer/来源增删改共用现有 groups 顶层锁；快照、提交、恢复在锁内，健康与同步在锁外 |
| 高 | `subscriptionWireGuardEnsureKeys()` 在状态提交前落地密钥；`installSubscriptionControlService()` 在服务备份前生成 Token，现有恢复函数不会删除它们 | 不再声称完全回滚；软件包、密钥和 Token 作为 `0600` 身份工件留存并在重试时复用，状态/配置/服务仍恢复 |
| 高 | 旧验证器允许额外字段，旧程序可能忽略待完成邀请并在其地址上添加 Peer；升级后若跨 Peer/邀请严格判重会把可恢复状态判坏 | 活动 Peer/来源优先，邀请操作在锁内清理冲突陈旧邀请；降级前提示取消邀请，但升级不因该冲突阻塞 |
| 中 | 初稿只保存 `join_invite_id`，旧主控凭据导入后可能重新显示与当前主控无关的旧回执 | 旧凭据导入、手工身份更新时清除邀请绑定；不同主控邀请替换前要求明确确认 |
| 中 | 健康等待可能持续数十秒，若放在全局状态锁内会阻塞同步和状态维护 | 锁在本地事务提交后立即释放，现有 endpoint/health 等待和事件同步全部在锁外执行 |

本轮没有新增数据库或锁文件。现有 `subscriptionGroupsWithLock()` 已支持嵌套调用和无 `flock` 时的目录锁回退，足以覆盖低频交互式接入事务。

### 第 3 轮：实施范围与验收

| 级别 | 代码证据与缺口 | 计划修订 |
| --- | --- | --- |
| 高 | 初稿只列测试名称，没有精确命令、确定性时间/随机入口或合并态复验；过期测试可能依赖真实时间而不稳定 | 增加局部可覆盖的时间/随机函数、精确 selector 命令、TTY/非 TTY 输入检查和合并态回归门 |
| 高 | 现有菜单把添加函数后的事件同步返回值沿用为流程结果；后置健康/同步失败可能让已提交状态被误报成“添加失败” | 接入成功只由本地事务决定；健康和事件同步在锁外单独报告，异常不回滚也不误报提交失败 |
| 中 | 初稿未说明无回显读取和全局锁复用应落在哪个文件，预计文件清单无法约束实现扩散 | 增加文件归属表；局部 helper 留在 `wireguard_control.sh`，默认不改 groups/control/runtime 和注册层 |
| 中 | 初稿把计划和功能写成同一 worktree，且容易把 Conventional Commit 分类误当成确定版本号 | 分离计划与功能 worktree/分支；只描述 patch/minor 候选，由自动化按推送时提交集合计算版本 |
| 中 | VPS 清单只有功能步骤，没有权限、后置失败语义和可交付证据格式 | 增加权限检查、人为健康失败、秘密扫描和需留存且必须脱敏的验收证据 |

三轮审计后，计划范围仍保持离线邀请/回执，没有引入公网 API、新数据库、新锁文件、任意 CIDR 地址池或批量编排。新增内容全部用于关闭真实安全、事务和验收缺口。

### 第 4 轮：并发、中断与幂等恢复

| 级别 | 代码证据与缺口 | 计划修订 |
| --- | --- | --- |
| 高 | 初稿要求在一次 `control.json` 写入中同时添加 Peer 并删除邀请，但 WireGuard 应用、groups 来源和 Token 随后才写；进程被终止或主机重启时可能留下“邀请已消费、来源未完成”的不可重试状态 | 邀请保留到 Peer、WireGuard、来源和 Token 全部完成后再原子消费；最终消费前中断时，有效期内同一回执可严格核对已有字段并续跑 |
| 高 | 现有添加流程在顶层锁外读取 WireGuard/groups 快照，内部单次 groups 写入虽各自加锁，失败恢复仍可能覆盖中间发生的并发更新 | 顶层取得现有 groups 锁后再读快照，嵌套状态写复用动态作用域中的已持有锁；快照、提交和恢复使用同一锁内视图 |
| 高 | “幂等重试”若只按别名判断，可能把已有 Peer 公钥、控制端口或 Token 覆盖成另一份回执的值 | 续跑要求邀请标识、预留别名/地址以及已有公钥、端口、Token 全部兼容；任一已存在字段不一致即失败，不以重试名义更新活动身份 |
| 中 | 初稿只把主控邀请和 Peer/来源变更放入锁，被控导入邀请仍可能和本机维护同时写 `control.json` 或重启服务 | 被控依赖安装和密钥准备留在锁外，锁内重新核对状态并完成快照、状态/服务应用和恢复；取锁超时不写入 |

本轮没有引入事务日志。保留邀请到最后已经覆盖交互式接入最关键的异常中断窗口；最终消费后本地三份状态均已提交，健康检查和事件同步仍是可重试的后置动作。

### 第 5 轮：可操作性、兼容与验收归因

| 级别 | 代码证据与缺口 | 计划修订 |
| --- | --- | --- |
| 高 | 现有 `showSubscriptionRemoteHealthPlan()` 调用 `subscriptionRemoteControlHealthAll()`，若把它直接用于完成接入，任一旧来源故障都会污染新来源的验收结果 | 按邀请预留别名读取刚加入的单个来源，直接复用现有 `subscriptionRemoteControlHealth()`；全量健康页只用于日常总览 |
| 高 | 新回执需要严格的 64 位 Token 合同，但旧 `controlled` 测试和已有部署允许任意非空无空白 Token；若共用收紧后的验证器会破坏兼容路径 | 新约束只应用于 `receipt`，旧 `controlled` 保持原验证合同，并增加两类凭据的对照回归 |
| 高 | 邀请列表按安全要求隐藏 `invite_id`，初稿既没有指定取消时使用哪个可见标识，也没有处理异常中断后邀请与部分 Peer/来源共存的取消语义 | 列表显示唯一别名、地址、本机时间、剩余时长和阶段；取消按别名二次确认，未开始时只删邀请，接入未完成时复用现有移除/恢复事务清理部分状态 |
| 中 | 普通状态移除秘密后，旧主控/被控凭据若没有明确入口，会使兼容合同存在但用户找不到 | 主控控制面细节和被控维护页分别增加明确命名的兼容凭据操作；含长期 Token 的输出前先提示 |
| 中 | 当前主控初始化只说控制服务经 WireGuard 启用，用户容易把它与公网订阅 HTTPS 混为一谈并期待立即申请证书 | 初始化和邀请结果明确区分 UDP WireGuard/隧道内 HTTP 与公网订阅 HTTPS，说明接入流程不需要证书 |
| 中 | 第 3 轮虽列出 selector 和 MSYS2 环境要求，但没有给出可直接执行的 Windows 包装命令，也没有把版本文件不变做成命令门 | 增加仓库内 `TMPDIR/HOME`、固定 MSYS2 PATH、失败即停的 PowerShell/Bash 包装，并用 `git diff --exit-code main -- shell/core/version.sh` 检查版本文件 |

五轮审计后，计划仍只复用现有凭据编码、groups 锁、单源健康检查、状态写入和恢复入口。没有新增公网服务、TLS 流程、数据库、锁文件、依赖或版本写入。

## 旧首次接入兼容退休记录（2026-08-02）

- 所有主控与被控均已升级，首次接入统一为“主控创建邀请 -> 被控导入邀请并生成回执 -> 主控完成回执”。
- 被控角色向导只接受 `invite`，主控完成接入只接受 `receipt`；地址和别名均来自主控预留，不再开放旧凭据手工填写路径。
- 旧 `initSubscriptionWireGuardControlled()` 与 `subscriptionWireGuardAddPeerFromCredential()` 已删除。
- `main` / `controlled` 凭据编解码、显示、导入和已有 Peer/Token 更新仍保留，仅用于维护现有连接，不再承担首次接入。
