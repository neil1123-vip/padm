# Docker 版功能对照表

日期：2026-10-15

这份表是“原生菜单功能”和“Docker 当前能力”的第一阶段基线。状态只表示
Docker 现在能否通过受管控制命令完成对应能力，不表示底层镜像里是否包含某个
上游程序。

后续实施顺序和验收门槛见
[Docker 菜单与功能对齐实施计划](docker-menu-parity-plan.md)。计划安排不改变本表的当前支持状态。

3D.11–3D.13 提供协议菜单 `14/15/16` 与
`edit --protocol-add/--protocol-remove/--protocol-rebuild`。
新增接受已有受管 v1/v2/v3，旧规格仅在成功确认后迁移；
默认源核心，可选 Xray/sing-box 并启用副核心，主核心保持，跨核心拒绝宿主集成。
复用源 UUID、地址和已有 TLS，只追加一个入口，不扩账号授权；
Reality 仅从 Reality 派生。无 TLS 部署新增首个 TLS 协议可显式选择受管/导入/
DNS-01/HTTP-01 standalone 证书，复用候选证书和配置恢复事务，不迁移已有 TLS 域名。
ACME 预览只校验计划，确认后才申请并验证完整候选，不自动登记续期。
首次 SS2022 新增生成独立服务器/用户密钥，私密候选文件冻结复验，不进 argv/预览；
同 UUID 已有 SS 保留原密钥。删除与重建仍要求 v3。
删除沿用账号最后关联、主核心、共存和 Fail2ban 门禁并清理入口附属配置；
重建保留完整规格，按现有候选事务统一验证和重建。
复制/派生/删除共用实现，fallback 复制保留共享后端，不同协议新增分配内部监听。
完整管理及原生宿主/arm64/公网验收继续 `deferred`。

3D.14 提供“安装与重装”的重新选择向导与 `reinstall --spec` 完整规格路径。
重装允许替换核心、入口、账号与路由，成功时撤销旧分享组授权；
保留累计账本、证书、ACME、独立资产和恢复快照，失败恢复旧配置及分享组。
向导拒绝宿主集成、Reality 共存、跳跃和控制角色；完整规格仍沿用各转换门禁。
Linux amd64 三项定向及一次完整合同 57/57、347 项规格差分通过，
完整入口 `374895 ms`、Jobs 6，详细证据见实施计划。
已有 TLS 域名迁移、真实发布及完整管理继续 `deferred`。

5B.4g 已接入区域子菜单 `7` 与 CLI 的自定义直连例外单条原位替换，`8` 查看路由状态。
仅修改已有非空 `.routing.region.allow_domains`；保留次序、区域模式、固定八条例外及
其它配置，拒绝缺旧项、重复新项、同值、CSV、未启用或空名单。固定默认例外不可替换。
`routing-tools`、`internal-206-routing-rules` 与完整菜单状态继续为 `deferred`。
只读 `routing-status` 已提供跨策略 `full/domain` 域名层级覆盖诊断，
按标签边界比较并保留原精确重叠；另报告跨策略 `full/domain/keyword`
正文包含 `keyword` 的确定关系，不查询 GeoSite 成员、DNS 或最终流量。
5B.4r 菜单 `17 → 45/46` 与 CLI 提供已有手工 IP 名单的显式解析后阻断，
限单 sing-box、无副核心，支持 WARP/IPv6 出站组合，目的 IP 可为双族。
每条实际路径按出站地址族从 hosts/指定 DNS/local 解析一次，重新阻断后立即选路，
代理使用经检查的字面 IP；
DNS 失败拒绝，Direct 例外优先，缺省字面模式及其它配置保持。
新字段 `block_ips.resolve_domains:true` 由独立 bundle marker 保护，组合另需 egress marker。
Xray `IPOnDemand` 的代理重解析与 DNS 失败回退可绕过判定，继续 deferred；
完整区域及宿主过滤也不升级支持状态；WARP 本地加密 Peer 不替代公网实际出口验收。

5B.4h 已接入菜单 `17 → 34/35/36` 与 CLI 的已有非空 selective SOCKS5 域名增删/单条替换。
未启用/global 拒绝；追加稳定去重、合并最多 256 条，删除缺项整批拒绝，
替换拒绝 CSV/缺旧/重复新/同值并保留位置。非空只改 `domains`，冻结上游、凭据及其它配置；
删空关闭整个 SOCKS5，重新启用须导入凭据，不切 global。定向合同、菜单 PTY 与完整 49 项回归已通过，
不新增 schema/marker 或宿主权限，不升级上述整体 `deferred` 状态。

5B.4i 已接入菜单 `17 → 37` 与 `edit --hosts-replace <已有精确 FQDN> <新单字面 IP>`，
仅替换已有 hosts 单键值，不新增、删除或批量编辑。key 只将 ASCII 字母转小写，不去空白，
IP 原文保持；空白、尾换行、CSV、规则前缀和坏地址返回 `2`，缺键、未启用、同值返回 `15`。
其它 hosts 键、路由、完整配置、分享 URI、订阅和累计流量保持，复用原预览/确认及健康/信号恢复。
原私有 JSON 整组入口保持，不扩 hosts 语义、schema、marker、权限或状态。
DNS/hosts 定向与菜单通过，集中完整 49 项回归通过；这是有限管理增强，原生完整迁移及整体状态仍 `deferred`。

5B.4j 接入菜单 `17 → 38/39` 与 `--hosts-add <精确 FQDN> <单字面 IP>` /
`--hosts-remove <精确 FQDN>`。新增可创建缺省映射，仅接受缺失键；重复键及合并超
256 项返回 `15`。删除要求已有键，缺键/未启用返回 `15`；删空关闭 hosts，
其它 routing 存在时保留。ASCII 小写、不去空白、IP 原文及非法输入 `2` 沿用；
冻结精确单键变换之外的完整配置、URI/订阅/累计，不新增 schema/marker/权限/状态。
Linux amd64 增删定向与菜单 PTY 通过，集中完整 53 项回归通过；完整状态保持 `deferred`。

5B.4k 在现有路由状态追加只读 `domain_rule_overlaps`，按完整规则字符串列出
Direct/Block/IPv6/WARP/SOCKS5 候选顺序及优先者，包括区域合成的域名规则。
同策略重复来源去重，global 出站不参与；旧手工 `direct_block_overlaps` 语义保留。
优先者只针对相同完整 selector，不推断包含关系、分类成员、IP/BT、HTTP 中继或实际流量。
完整冲突检测、区域管理及原生宿主/arm64/公网验收仍 `deferred`。

5B.4l 接入区域菜单 `9` 与 `--region-mode <both|domain|ip>`，
仅切换已有 `.routing.region.mode`，保留自定义例外顺序、固定八条例外及其它配置。
同模式或未启用返回 `15`，非法值返回 `2`；原 `--region` 整组替换语义保持，
菜单 `1`–`3` 明示替换自定义例外、留空清空。完整区域管理和整体状态仍 `deferred`。

5C.9a 仅补固定 amd64 sing-box 1.14.2 客户端前置：Hy2 接受范围字段，
TUIC 拒绝 `server_ports`，两者单端口基线均通过。Hy2 两个现有 UDP alias
分别通过双栈严格 TLS、认证与 TCP/UDP；范围客户端跨 5.1 秒保持业务，
精确包计数仅记录观察，不证明两族都切换或新 QUIC 握手。
未新增生产跳跃合同、菜单或宿主规则，完整跳跃和协议管理仍 `deferred`。

5C.9b 仅补隔离双栈 iptables-nft DNAT 到现有宿主发布口的启用/撤销/重建前置，
随机链/token 和精确逆序撤销保留 Docker 与模拟外来 NAT 规则正文。
撤销用此前无跳跃流量的第二来源，重建同来源恢复；均为新客户端进程。
沿用默认 userland-proxy，不证明直达容器 DNAT、生产持久归属、旧会话撤销、
范围冲突、重启/卸载或自动跳跃，不升级完整支持状态。

5C.9c.1–2b 为内部端口跳跃前置：只读范围冲突检查、固定 state/token 的
双族 audit/health/clean、全生命周期 flock、原子 intent/active 及 TERM/INT 清理。
已核验的同参数残留可精确撤销并换 token 重建；不同参数在撤旧前拒绝。
跨进程无标记空链、state/lock 替换和未知布局保留并拒绝，不删除 conntrack。
health 只证明自有双族布局；目标发布归属、菜单/Compose 接入、旧会话排空、
原生宿主/arm64、公网、整机重启和卸载仍待验，完整跳跃与协议管理保持 `deferred`。

5C.9c.3a 内部只读快照只核对已有双族 Hy2 的完整规格、账号/额度渲染配置、
Compose/镜像与实际健康受管容器的 UDP 发布，输出身份及启用账号数量。
3b 标准真实部署已验证健康快照、重启代次和磁盘漂移拒绝。
3c 只读启动检查另行拒绝运行配置或所选 TLS 文件晚于固定启动时间的
`mtime/ctime`，恢复旧修改时间或同字节替换也拒绝；正常流量累计不受时间限制。
这不证明加载版本、容器挂载视图或墙钟回退下的一致性。
3d.1–2 内部持锁启动事务限已有统计目录、健康单 sing-box 和单个双族 Hy2 入口、
无宿主集成及其它项目容器；可保留生成器默认未运行 ACME profile。
严格采集、一次新候选渲染与正常一次重建后核对新代次；失败或 INT/TERM
仅恢复已验证安全候选，无法确认则核对归属后停止，不回退累计。
Linux amd64 私有 daemon 已验两族新连接的刚跨额度撤销及发布失败恢复；
非合作替换、SIGKILL、原生宿主/arm64、公网、旧会话排空和 net/菜单/schema
启用门控继续待实施或待验，不提升完整跳跃及协议管理状态。
3e.1 同锁启用准备已增加规范范围及唯一双族 listener 前置检查，直接复用启动事务一次，
后验固定输入及新代次，只返回诊断；不写 jumpstate/NAT，不证明范围空闲或授权 net 启用。
账号数仅对应本次启动采用的额度版本，不保证后续累计变化已重新应用。
3e.2a 实验 net run 在 active 提交前后复验全域冲突，仅扣除同快照核验完整的自有
链与规则；外来冲突不阻止精确自有清理。无全域原子预留或实时父子授权，
active state 不能作为最终启用成功，生产启用及管理状态不变。
3e.2b.1 固定 bound 诊断出口绑定实际启动采用的锁、固定输入及 state/live，
前后严格拒绝版本漂移，不重渲染；它不授予 net 写权限。
后续内部只读 Probe、同锁有限写门与持锁持续会话分别验证新挑战、固定投影和失败撤销。
3e.2b.3d 增加 Linux root 独立监督、自取锁与本轮 bound，seq 2 后复验才返回启动 ACK；
状态和停止走 root Unix socket 新挑战及 pidfd，不借用调用者旧锁或保存的 JSON 授权。
commit 前断流不启动持锁 Bash，失败会话保留；commit 后 ACK 丢失可实时查询同一 owner。
停止须净撤销回执、Bash 实际退出和原锁释放后才确认，不自动恢复未知 owner。
3d.1 已验 started 后 HUP 续期、manager TERM 净清理与 manager SIGKILL 后
规则撤销/旧 owner 拒绝。3h 补初始化 INT/TERM 写门与直接子进程回收；
已核验 ready 资源取得净撤销回执后可清会话，较早中断保留未核验证据并拒绝普通变更。
3d.4–7 已接菜单/CLI、v3 持久规格及 restart/update/rollback/down/uninstall 协调，
3f 已验同一 sing-box 客户端双族跨两端口自动跳跃，3g 分享复用原协议生成器。
3i 监督启动/重启共用 120 秒推进预算，更新/回滚 840 秒，交接不重置；
到期停止授权/成功 ACK，原 Bash TERM 与 finally 共用 90 秒停止等待。
活动会话无总时长限制，等待到期保留未核验证据，不承诺内核撤销上界。
3j 已验真实 Bash SIGKILL 后双族 NAT/state 撤销、退出容器和 owner/stage/锁留证，
查询/停止/新启用及生命周期命令拒绝接管，不将其当作正常净停止。
5C.9d 将同一范围管理扩展到单个双族 TUIC，协议身份、真实入站类型和 TLS 逐代核对；
保存、启停、清除、restart/update/rollback 沿用既有监督和净撤销。
新 TUIC 配置要求 `x-padm-port-hopping-tuic`，Hy2 旧包子集保持。
活动 `share` 默认 TUIC 范围首端口，`share <端口>` 为两协议输出普通单端口 URI，
只允许活动范围内端口，不改静态订阅；固定 TUIC 客户端无原生范围字段，不宣称自动跳跃。
自动恢复、外部 URI 导入、TUIC 客户端自动跳跃、旧 conntrack 排空及
原生宿主/arm64/公网与完整协议管理继续 `deferred`；阶段验收见实施计划。

3B.4 的 Linux amd64 与 arm64 仿真双核心 TLS、WS 客户端及失败/信号恢复已通过，
证据和剩余限制见[真实 TLS 验收基线](docker-tls-real-baseline.md)。
内部 TLS 夹具不代表新增协议支持；真实 DNS、完整宿主重启、原生 arm64 和可信发布仍待验。

## 状态定义

| 状态 | 含义 |
| --- | --- |
| `supported` | Docker 配置合同、控制命令和 Compose profile 已能完成该能力。 |
| `host-integrated` | 能力依赖宿主内核、接口或防火墙；只能通过显式 `net-*` profile 使用。 |
| `deferred` | 原生已有能力，Docker 已记录边界或后续方向，但当前合同/控制命令尚未开放。 |
| `unsupported` | 当前 Docker 版本不提供，也没有可安全复用的现成入口。 |

协议的 `status` 只表示通过首次向导或 JSON spec 配置并运行的能力；`management_status`
另行表示原生协议管理工作流的迁移状态。初始配置可运行不代表完整菜单管理已支持。

3D.1 已接入逐入口 Reality 参数重生成：菜单或 `edit --regenerate-reality <入口 ID>`
更新私钥、公钥和 short ID，支持两核心 Vision/gRPC 及 Xray XHTTP。
保留 UUID、目标/SNI、端口、其它入口和额度，更新分享链接及已启用的 HTTPS 发布内容；
预览不提交，取消、中断或健康失败恢复旧状态。该子功能为 `supported`，
3D.2 已按当前原生 8 项菜单接入目标检测、目标库刷新、网段/同 ASN 扫描、
A 级分页筛选与切换、独立 SNI 和黑名单；共用原生全部 A/AAAA 最差评分、
PQC 和 CDN 风险算法。缓存选择仍重新验签和复测，再按 Docker 事务确认提交；
扫描和检测不改部署，目标状态保存于 `/etc/padm-docker/data/reality-targets`。
首次配置默认先检测全部候选，再从本次实测 A 级列表中选择；也可手动输入
`host[:port]` 和独立 SNI。候选检测先验证发布签名，不生成账号、不持部署锁，
结果只留在临时目录，返回或最终取消不发布目标库。手动安全 B/C 目标显示质量告警。
扫描进度、非零状态下的有效结果导入和失败批次继续处理共用原生实现，
中断先清理后台扫描再删除临时目录。
公网扫描、部署网络候选可用性及原生 arm64 仍待环境验收；443 共存未完成，
协议完整 `management_status` 继续为 `deferred`。

3A.3 已通过本地回归：v3 明确主副核心与每个入口归属，两核心合计最多 16 个入口，
菜单和 `edit --spec` 可复制、删除现有协议入口；v1/v2 的配置及备份恢复继续兼容。
Reality 可跨核心复制，删除副核心最后入口会关闭副核心，主核心至少保留一个入口。
复制复用凭据，同 UUID 跨核心共享流量与额度；两核采样全部复验后才写累计，
额度应用失败或中断恢复全部配置，既有身份、核心归属和 WS 内部端口不改排。
3C.2 新增 Xray Reality XHTTP 和 Xray/sing-box Reality gRPC：
首配、完整 v3 规格导入、基础参数编辑、传输派生及本地分享链接已接入。
Vision/gRPC 可跨核心复制，XHTTP 仅限 Xray；副核心首配仍默认 Vision。
双核心暂不能组合宿主集成；目标 bundle 版本与协议/核心支持均需匹配。
3D.4 接入已有 v3 Xray XHTTP 单入口的日常、兼容、流式、单并发预设，以及客户端
XMUX 三键自定义/清除、CLI/菜单状态和统一链接发布。显式 XMUX 进入 URI `extra`，
服务端原固定 XMUX 不变；旧规格和无显式 XMUX 的链接保持，旧包仅拒绝显式对象。
3D.5 增加已有单入口的可选 `xPaddingBytes` 设置/恢复缺省，规范整数或正序范围
`1..4096`；这是本阶段产品边界。服务端和客户端 URI `extra` 同值并合并 XMUX，
显式字段要求 `x-padm-xhttp-padding`，缺省旧包和旧链接保持；`0`/`0-0` 拒绝，
不能关闭，clear 恢复 Xray 缺省 `100-1000`。菜单、状态、冻结与事务已接入。
3D.6 增加已有单入口的 `noGRPCHeader`/`noSSEHeader` 布尔开关与清除，
显式 `false` 保留，缺省不补字段；任一键存在要求 `x-padm-xhttp-headers`。
客户端 stream POST 的 gRPC 首部与服务端下载 SSE 首部分别控制，
`packet-up` 原本没有 gRPC 请求首部；三模式的固定 Xray TLS/h2 首部对照通过。
3D.7 本轮实施并已在本地 Linux `amd64` 容器验收四项原生 packet/stream limits：
`scMaxEachPostBytes`、
`scMinPostsIntervalMs`、`scMaxBufferedPosts`、`scStreamUpServerSecs`。
前三项接受 `0..2147483647` 整数，最后一项接受同范围整数或正序范围；
`0`/`0-0` 保留在 spec、server 和 URI，状态显示核心默认
`1000000/30/30/20-80`，显式字段要求 `x-padm-xhttp-limits`。
菜单 `12`/`13` 与 `--xhttp-limits`/`--xhttp-limits-clear` 已接入；
空输入采用默认值，`default` 对前三项保存零。清除删除字段，缺省不补 spec/URI；
其它编辑保留，复制/派生继承，状态的 `limits_explicit` 区分显式字段。
3D.10 合批接入菜单 `14`–`17` 与 CLI `--xhttp-mode`、`--xhttp-path-host`、
`--xhttp-advanced`、`--xhttp-defaults`，状态同时显示 path/host。
模式限 `auto/packet-up/stream-up`；路径和非空域名 Host 成对修改，沿用规格校验。
高级参数一次设置 Padding、四项 limits、两项首部，保留 mode/XMUX；
推荐恢复显式写入 `auto`、XMUX `16-32/600-900/1800-3000`、
Padding `100-1000`、首部 `false/false`、limits `1000000/30/30/20-80`，保留 path/host。
仅相应字段豁免冻结，复用既有能力门禁及发布/失败恢复，不扩 schema 或支持状态。
3D.10 Linux amd64 XHTTP/菜单定向通过，集中完整合同 57/57 一次通过，`380824 ms`；
定向和完整源码摘要相同，临时输入已清，真实客户端矩阵复用既有证据。
其它 sc*、自定义 headers、
downloadSettings、H3/CDN 与上下行分离未开放，
完整管理继续 `deferred`，
填充字节分布、抗识别、长时复用和吞吐收益未证明；本地 amd64 合同、菜单、
定向 limits 30.079 秒、真实 XHTTP 25.743 秒、菜单校正后 55.976 秒、
dispatcher 2.217 秒，完整 `docker-contracts` 一次通过（383.362 秒，
345 项差分，`Jobs 6`、`queue_wait_ms=320`、`cache_hit=false`）。
真实覆盖 5 个入口、20 条业务请求及 32 KiB POST 大于 16 KiB，server/URI
与 spec 一致；首次菜单标签不匹配失败证据保留，校正后通过。
3C.3 新增 sing-box Hysteria2：首配、完整 v3 规格导入、参数编辑、复制/删除及本地分享链接，
支持单 UDP 入口、BBR/Brutal、Salamander/Gecko 和 HTTPS 伪装；复用 TLS 和 UUID 流量账号。
3C.3a 接通 Gecko 首配、已有入口类型切换及分享；要求 `x-padm-hy2-gecko`，
旧无混淆/Salamander 子集兼容，包长等高级参数不开放。
5A.1c 接入已有入口的受管本地网页：先发布目录/notes/photos/docs，再设置 `local`；
固定只读目录、无混淆、静态模式，拒绝任意 file URL；Nginx 混合部署共用网页。
local 启用期间默认页/302/混淆拒绝，关闭保留内容；纯 Hy2 静态准备与 local
要求新能力标记，旧默认/HTTPS 子集兼容。
带宽为服务端方向，链接转为客户端方向；包含 Hysteria2 时暂不接受宿主集成。
真实 amd64 的 BBR/Brutal/Salamander/Gecko 各 IPv4/IPv6 共 8 条 HTTP proof 已通过；
端口跳跃限下述内部监督的单 sing-box、双族 Hy2 手动管理；
第三方导入 UI、公网宿主入口和原生 arm64 未验或尚未开放。
3C.4 新增 sing-box AnyTLS：v3 首配、完整规格导入、通用字段编辑、同核复制/删除及分享链接，
支持 TCP 双栈，复用受管 TLS 和 UUID 流量账号；TLS 域名与凭据按身份合同冻结。
真实 amd64 的 IPv4/IPv6 两条 SOCKS HTTP proof 已通过；包含 AnyTLS 时暂拒绝宿主集成。
AnyTLS 单独部署不能发布 HTTPS 订阅，组合 Xray WS TLS 后可包含 AnyTLS 链接。
3C.5 新增 sing-box NaiveProxy：v3 首配、导入、通用字段编辑、同核复制/删除及原生分享 URI，
仅监听 TCP，入口域名与 TLS 域名一致；UUID 作为用户名、密码和统计标识，不添加 `name` 字段。
真实 amd64 双栈 SOCKS HTTP proof 及 UUID 正上/下行计数已通过；宿主集成、QUIC 和独立 IP/SNI 覆盖未开放。
3C.6 新增 sing-box Shadowsocks 2022 AES-128 多用户：v3 首配、导入、通用编辑、
同核复制/删除与 SIP002 分享链接，TCP/UDP 双栈，不需要 TLS。
服务器/用户密钥分别生成，UUID 共享统计额度；超额移除入站，解除额度恢复原输入。
真实 amd64 双栈 TCP/UDP、UUID 正计数、服务器密钥单独认证拒绝及超额/恢复通过。
凭据轮换、用户 CRUD、宿主集成与完整管理尚未开放。
3C.7 新增 sing-box TUIC：v3 首配、导入、通用字段与拥塞/认证超时/心跳/0-RTT 参数编辑、
同核复制/删除及分享链接；单 UDP 双栈入口，复用受管 TLS 与 UUID 流量账号。
默认 `cubic`、`3s`、`10s` 和关闭 0-RTT；有限范围转发见 5C.9d，宿主集成及完整管理尚未开放。
3D.8 合批提供协议菜单 `12/13` 与 `hy2-status/tuic-status`：
Hy2 单入口 BBR/Brutal 带宽专项，Brutal 一次设置模式和服务端双向速率，
BBR 保留原速率；TUIC 单入口拥塞、连接参数、0-RTT 和推荐值恢复。
时长、速率沿用现有规格边界，只豁免选中字段，保留其它入口、身份、TLS、
Hy2 混淆/伪装及累计额度；菜单开启 0-RTT 默认否并提示重放风险。
已有生成器、URI 与发布/失败恢复事务复用，完整管理仍 `deferred`。
Linux amd64 定向 TUIC（含 Hy2）152.468 秒、菜单 59.860 秒、
dispatcher 1.630 秒，完整合同一次 393.961 秒通过（Jobs 6、排队 363 ms）。
TUIC 首轮测试基线不匹配已修正并补跑，不放松其它字段冻结；静态/独立复核通过。
3D.9 将同一 Hy2 菜单扩展为 Salamander/Gecko/关闭混淆和 HTTPS/local/关闭伪装，
对应 `--hy2-obfs/--hy2-masquerade`。密码复用静默输入或严格私密 JSON，
local 先校验已发布受管 static 且无混淆，只豁免所选字段，沿用旧包能力门禁。
Hy2 定向 106.702 秒、菜单 57.549 秒及完整 57 项合同 375.917 秒通过；
顺手修正跳跃 stop 夹具的清理观察竞态，生产预算与拒绝留证边界保持。
真实 amd64 三算法各双栈 TCP/UDP、错误密码拒绝、UUID 正计数及同客户端额度拒绝/恢复通过。
3C.8 新增两核心 direct Trojan：v3 首配、导入、通用字段编辑、跨核心复制/删除及分享链接，
TCP/TLS 双栈直连，不依赖 Nginx；UUID 密码与统计标识复用既有共享流量/额度。
真实 amd64 两核各双栈 TCP/UDP-through-TCP、错误密码拒绝、UUID 正统计及同客户端额度恢复通过。
TLS 域名与凭据冻结，fallback、宿主集成及完整用户管理尚未开放。
3C.9 新增 Xray VMess WS TLS：v3 首配、导入、入口与 WS 路径编辑、同核复制/删除及 `vmess://`
分享链接；固定 `alterId=0`，复用 Nginx、受管 TLS 和 UUID 流量账号。
真实 amd64 Nginx TLS/WS 双栈、错误 UUID 拒绝、UUID 正统计及同客户端额度拒绝/恢复已通过。
协议 22 单独部署不开放 HTTPS 订阅发布，暂不接受宿主集成，完整管理仍为 `deferred`；
公网宿主入口、第三方导入 UI、业务镜像签名发布和原生 arm64 客户端仍待验。
3C.10 新增两核心 VMess HTTPUpgrade TLS：v3 首配、导入、入口与路径编辑、跨核心复制/删除及分享链接，
固定 `alterId=0`，独立 `httpupgrade` 字段复用 Nginx/TLS、UUID 统计和额度。
Nginx 按入口核心反代，后端端口按核心隔离，TLS 端口全局唯一；路径不附加 `ws`。
真实 amd64 两核心各双栈 TCP/UDP 隧道、大小写域名 Host/SNI、错误 UUID、统计与同客户端额度恢复通过。
协议 23 单独部署不发布 HTTPS 订阅；宿主集成及完整管理继续未开放。
3C.11 新增 Xray VLESS/Trojan gRPC TLS：v3 首配、导入、通用字段与服务名编辑、同核复制/删除及分享链接。
独立 `grpc_tls` 字段复用 Nginx HTTP/2、受管 TLS 和 UUID 统计额度；后端端口按核心避让，
TLS 端口与 WS/HTTPUpgrade 共享全局池；不支持 sing-box、宿主集成或 fallback。
单独部署不发布 HTTPS 订阅，和协议 21 混合时可输出并发布两类 gRPC TLS 链接；完整管理继续未开放。
真实 amd64 两协议均通过严格 CA/SNI、HTTP/2 双栈 TCP/UDP 隧道、错误凭据拒绝、
UUID 正统计及同客户端额度拒绝/恢复；未暴露宿主端口或核心 gRPC 后端。
3C.12 新增 Xray VLESS TCP TLS Vision 与 Trojan TCP TLS fallback：v3 首配、导入、
通用字段编辑、同核复制/删除及分享链接；Xray 直接终止受管 TLS，固定 PROXY v1
回落到 Nginx HTTP/1.1 和 HTTP/2 后端，两个后端端口与现有 Nginx TLS/健康端口共用全局池。
仅 fallback 的 Nginx 不挂载 TLS 私钥、不依赖核心；混合反代时只依赖对应前端核心。
默认静态首页可用，旧无站点规格保留 `data/static/index.html` 优先行为。
5A.1 已开放已有 Nginx TLS/fallback 入口的默认页、静态目录和 302 事务管理；
静态内容随候选、备份、安装与失败/信号恢复一致处理，旧无静态快照保留当前目录。
生产发布只接受 root 所有、不可外部写入的独立公开资源目录，拒绝受管/秘密路径、
链接、硬链接、特殊文件及可识别私钥；不能据此证明内容无任何凭据。
5A.2 提供逐入口 ALPN 配置诊断、推荐修复及三种持久化顺序，核心与 URI 同序；
专项仅容许选中入站 ALPN 漂移，不覆盖其它账号、路由、fallback、Nginx 或编排。
真实 Nginx PROXY HTTP/2 已验，真实 Xray ALPN 协商、公网及原生双架构仍待验；
5A.3a/5A.3b 已提供 standalone/webroot HTTP-01 的本地事务底座；公网 CA、
真实宿主生命周期及原生双架构仍待验，组合管理状态保持 `deferred`。
独立 27/29 不发布 HTTPS 订阅，组合协议 21 可发布其链接；宿主集成、sing-box 与完整管理仍拒绝。
本阶段真实客户端、HTTP/1.1/HTTP/2 回落和恢复验收已通过；Docker Linux 定向回归约 `109.543` 秒，
真实 amd64 27/29 及旧 22/24/25 顺序验收约 `277` 秒，静态 ShellCheck、Schema `4` 正例/`50` 反例
和 phase3 矩阵检查通过。公网宿主入口、原生 arm64、真实 DNS/整机重启及可信发布仍未验。
Nginx 与核心端 TLS 轮换底座已交付；其它新协议类型和完整管理尚未交付，
协议的 `management_status` 继续为 `deferred`。
Fail2ban 关联 WS 的增删与通用端口编辑暂冻结；5C.6d 仅提供单直接 WS 21、
单集成和单保护端口的专项联动，实际迁移验收见实施计划。真实签名发布、业务镜像及
双架构客户端连通仍待验，不能由工具容器回归推断完成。

机器可读状态位于 [`docker/contracts/features.json`](../docker/contracts/features.json)：

- `protocols[]` 记录公开协议 ID、配置运行状态、管理状态、核心、profile、`transport`、`udp_support` 和原因。
- `features` 保留旧的兼容状态子集；同名值必须与 `feature_matrix` 一致。
- `feature_matrix` 记录完整功能状态、原生菜单入口、Docker profile、宿主权限、前置条件和原因。

## 主菜单对照

| 原生菜单 | Docker 当前状态 | 已覆盖 | 尚未覆盖或边界 |
| --- | --- | --- | --- |
| 安装与重装 | 部分已交付，完整管理 `deferred` | `install`、可信发布输入 `release`、交互首配 `setup`、`reinstall`、`edit`、`configure`、候选校验及恢复 | 支持 `1`、`2`、`3`、`4`、`5`、`21`、`22`、`23`、`24`、`25`、`26`、`27`、`28`、`29`、`30`、`31` 字段编辑、完整原始 spec 接入、多入口及主副核心；3D.11–3D.13 提供旧规格迁移后的增量新增、核心选择、新 SS 密钥、首个 TLS 证书联动以及 v3 删除/保身份重建。3D.14 提供重新选择和完整规格重装，并撤销旧分享授权、保留累计及失败恢复。已有 TLS 域名迁移及真实发布连通未完成。 |
| 订阅与用户 | `supported` + `host-integrated` + `deferred` | 有条件的订阅发布、流量采集/额度、v3 独立账号与双核心认证/统计、账号/分享组及业务备份恢复、主控管理与被控接入/手动同步、已有单 Peer 被控自动同步 CLI/菜单、WireGuard 宿主集成 | HTTPS 链接仍要求受管 TLS；H3 和完整多服务器工作流未迁移。隔离 amd64 双部署事务及真实 cron 自主同步已验，WireGuard 需 `net-wireguard`；原生双机、arm64 和重启另验。 |
| 协议与入口 | 部分 `supported`，管理工作流 `deferred` | `1` Reality Vision、`2` XHTTP、`3` Hysteria2、`4` AnyTLS、`5` NaiveProxy、`21` VLESS WS TLS、`22` VMess WS TLS、`23` VMess HTTPUpgrade TLS、`24` VLESS gRPC TLS、`25` Trojan gRPC TLS、`26` Reality gRPC、`27` TLS Vision fallback、`28` direct Trojan、`29` Trojan TLS fallback、`30` Shadowsocks、`31` TUIC 的配置运行、字段编辑、分享链接、多入口、Reality 传输派生、参数重生成和目标站管理；有限 Reality 443 共存及 21/22/23/24/25 CDN 连接地址覆盖 | XHTTP、VMess WS、gRPC TLS 和传统 TLS fallback 仅限 Xray，Hysteria2/AnyTLS/NaiveProxy/Shadowsocks/TUIC 仅限 sing-box；HTTPUpgrade 支持两核心；完整协议管理、UDP 端口跳跃、其余 CDN 和完整内部路由工作流尚未开放；Fail2ban WS 增删及通用端口编辑拒绝，单入口保护端口专项见 5C.6d。 |
| 站点与证书 | 部分 `supported`，其余 `deferred` | TLS 文件安装、DNS-01 与 HTTP-01 standalone/受管 webroot 本地事务、Nginx WebSocket/HTTPUpgrade/gRPC HTTP/2 入口及传统 TLS fallback；默认页、静态目录、302、受管三主题、Hysteria2 local 与逐入口 ALPN 事务管理 | 隔离 amd64 TLS ALPN 和 H3 已有实测；公网 CA、宿主生命周期及原生双架构验收待补。 |
| 路由与访问控制 | `host-integrated` + `deferred` | WireGuard、TUN/TProxy 宿主集成合同；5B.1–5B.4i 两核心 SOCKS5 TCP 出站、DNS/hosts、域名 Direct/Block、目的 IP、明文 BT、CN 预设、IPv6 与用户态 WARP 子能力；已有 DNS/选择性 SOCKS5/IPv6/WARP 名单增删、七类域名及手工字面 IP/CIDR 单条原位替换、已有 hosts 单键地址替换；5B.5a 已有 Xray 的 HTTP 中继事务 | SOCKS5 名单定向、菜单及完整 49 项回归已通过；hosts 单键替换定向与菜单已通过，集中完整 49 项回归通过；SOCKS UDP 发布、完整区域/访问控制仍未交付；WARP 公网出口、IPv6/HTTP 公网发布、真实宿主及双架构验收待补，完整状态不升级。 |
| 核心与服务 | `supported` + `deferred` | 基础状态、启动、停止、重启、日志、更新、回滚、配置校验、可信候选核心试跑与升级风险扫描、Xray Geo 状态/更新/每日任务 | 评估要求受管 spec；预发布须有匹配的可信发布资产，不现场构建；Geo 的本地合同及真实 amd64 解析/权限已验收，真实上游、生产重建、宿主调度和双架构生命周期另验；当前不是原生全部生命周期管理。 |
| 系统与脚本 | `supported` + `host-integrated` + `unsupported` | `padm-docker update`、Fail2ban 宿主集成 | BBR/网络优化不由 Docker 修改宿主内核；Fail2ban 需 `net-fail2ban`。 |
| 高级/危险操作 | `supported` + `unsupported` | 受管卸载、移除镜像、显式 purge | VLESS Encryption 实验尚未纳入 Docker 合同。 |

## 公网协议

协议 ID 与原生 [`shell/core/protocols.sh`](../shell/core/protocols.sh) 的
`category=node` 注册表保持一致。Docker 当前只接受配置运行状态为 `supported`
且核心匹配的协议；管理状态独立记录，不能由运行状态推断。

| ID | 能力 | 原生入口 | 配置运行状态 | 管理状态 | 核心 | Compose profile | 网络/监听 | 原因 |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | VLESS Reality Vision | 安装与重装；协议与入口 -> REALITY 管理 | `supported` | `deferred` | Xray / sing-box | `core-xray` / `core-sing-box` | bridge / TCP | 支持单核心或主副核心配置、字段编辑及跨核心同协议多入口；完整管理未迁移。 |
| 2 | VLESS Reality XHTTP | 协议与入口 -> XHTTP 管理 | `supported` | `deferred` | Xray | `core-xray` | bridge / TCP | v3 支持首配、导入、路径/Host/模式编辑、复制及分享链接；3D.4 四预设、XMUX 三键自定义/清除，3D.5 Padding `1..4096`，3D.6 两项首部开关已交付。3D.7 已验收四项原生 packet/stream limits 的状态、发布事务、保留/清除和复制/派生继承；前三项为 `0..2147483647` 整数，末项为整数或正序范围；`0`/`0-0` 保留显式值但状态折算核心默认，要求 `x-padm-xhttp-limits`。3D.10 提供模式、成对路径/Host、七项高级参数和推荐值恢复专项，推荐恢复保留路径/Host，复用既有门禁和事务。其它 sc*、自定义 headers、downloadSettings、H3/CDN、上下行分离与完整管理仍未开放。 |
| 3 | Hysteria2 | 协议与入口 -> Hysteria2 管理 | `supported` | `deferred` | sing-box | `core-sing-box` | bridge / UDP | v3 支持首配、导入、BBR/Brutal、Salamander/Gecko、HTTPS 伪装编辑、复制及分享链接；3D.8–3D.9 菜单 12 提供状态、带宽、混淆与伪装单入口专项，BBR 保留速率，密码仅私密文件或静默输入。Gecko 要求新能力标记，不开放包长参数。已有入口可两步发布受管静态网页并启用 local，固定只读目录且无混淆，操作先验证已发布网页。复用受管 TLS 和 UUID 流量账号；端口跳跃限单 sing-box、双族 Hy2 的内部监督手动管理，完整跳跃与协议管理仍 deferred。 |
| 4 | AnyTLS | 安装与重装 -> 自定义安装 | `supported` | `deferred` | sing-box | `core-sing-box` | bridge / TCP | v3 支持首配、导入、通用字段编辑、同核复制/删除及分享链接；复用受管 TLS 与 UUID 流量账号，域名与凭据冻结，宿主集成组合及完整管理未开放。 |
| 5 | NaiveProxy | 安装与重装 -> TLS 指纹抗性 | `supported` | `deferred` | sing-box | `core-sing-box` | bridge / TCP | v3 支持首配、导入、通用编辑、同核复制/删除及原生 URI；入口与 TLS 同域，UUID 用户名/密码共享统计额度；QUIC、独立 IP/SNI 覆盖及完整管理未开放。 |
| 21 | VLESS WS TLS | 安装与重装 -> 自定义安装 / 传统 TLS 兼容安装 | `supported` | `deferred` | Xray | `core-xray` / `nginx` | bridge / TCP + Nginx | 已有多入口 Xray 后端、Nginx 反代和同域 TLS；5C.6d 单直接 WS 21/单集成/单保护端口的专项迁移接入菜单和事务，新旧端口均要求 fresh 来源；关联入口增删、通用端口编辑及完整管理仍拒绝。 |
| 22 | VMess WS TLS | 安装与重装 -> 自定义安装 | `supported` | `deferred` | Xray | `core-xray` / `nginx` | bridge / TCP + Nginx | v3 支持首配、导入、入口与 WS 路径编辑、同核复制/删除及 `vmess://` 分享；固定 `alterId=0`，单独部署不发布 HTTPS 订阅，宿主集成及完整管理未开放。 |
| 23 | VMess HTTPUpgrade TLS | 安装与重装 -> 自定义安装 | `supported` | `deferred` | Xray / sing-box | `core-xray` / `core-sing-box` / `nginx` | bridge / TCP + Nginx | v3 两核心首配、导入、入口/路径编辑、跨核心复制/删除及分享；固定 `alterId=0`，UUID 共享额度，单独部署不发布 HTTPS 订阅，宿主集成及完整管理未开放。 |
| 24 | VLESS gRPC TLS | 安装与重装 -> 自定义安装 | `supported` | `deferred` | Xray | `core-xray` / `nginx` | bridge / TCP + Nginx | v3 首配、导入、入口/服务名编辑、同核复制/删除及 `vless://` 分享；Nginx HTTP/2 反代，UUID 共享额度，单独部署不发布 HTTPS 订阅，宿主集成、fallback 及完整管理未开放。 |
| 25 | Trojan gRPC TLS | 安装与重装 -> 自定义安装 | `supported` | `deferred` | Xray | `core-xray` / `nginx` | bridge / TCP + Nginx | v3 首配、导入、入口/服务名编辑、同核复制/删除及 `trojan://` 分享；Nginx HTTP/2 反代，UUID 共享额度，单独部署不发布 HTTPS 订阅，宿主集成、fallback 及完整管理未开放。 |
| 26 | VLESS Reality gRPC | 安装与重装 -> 自定义安装 | `supported` | `deferred` | Xray / sing-box | `core-xray` / `core-sing-box` | bridge / TCP | v3 支持首配、导入、service name 编辑、跨核心复制及分享链接；完整管理未迁移。 |
| 27 | VLESS TCP TLS Vision | 安装与重装 -> 自定义安装 / 传统 TLS 兼容安装 | `supported` | `deferred` | Xray | `core-xray` / `nginx` | bridge / TCP + fallback | v3 首配、导入、通用编辑、同核复制/删除及 URI；Xray TLS/Vision 与 PROXY v1 HTTP/1.1、HTTP/2 回落，UUID 共享额度；默认页/静态/302 与逐入口 ALPN 可事务管理，宿主集成与完整管理未开放。 |
| 28 | Trojan TCP TLS direct | 安装与重装 -> 自定义安装 | `supported` | `deferred` | Xray / sing-box | `core-xray` / `core-sing-box` | bridge / TCP | v3 两核首配、导入、通用编辑、跨核心复制/删除及 URI；受管 TLS、UUID 密码共享流量额度，fallback、宿主集成及完整管理未开放。 |
| 29 | Trojan TCP TLS fallback | 安装与重装 -> 自定义安装 / 传统 TLS 兼容安装 | `supported` | `deferred` | Xray | `core-xray` / `nginx` | bridge / TCP + fallback | v3 首配、导入、通用编辑、同核复制/删除及 URI；Trojan 直接终止 TLS，无额外 VLESS 前端，PROXY v1 HTTP/1.1、HTTP/2 回落，UUID 共享额度；默认页/静态/302 与逐入口 ALPN 可事务管理，宿主集成与完整管理未开放。 |
| 30 | Shadowsocks | 安装与重装 -> 自定义安装 | `supported` | `deferred` | sing-box | `core-sing-box` | bridge / TCP + UDP | v3 SS2022 AES-128 多用户首配、导入、通用编辑、同核复制/删除及 SIP002 链接；3D.12 支持增量新增并首次生成私密双密钥，同 UUID 已有 SS 保留原密钥。无需 TLS，UUID 共享统计额度，宿主集成及完整管理未开放。 |
| 31 | TUIC | 协议与入口 -> Tuic 管理 | `supported` | `deferred` | sing-box | `core-sing-box` | bridge / UDP | v3 首配、导入、入口/拥塞/认证超时/心跳/0-RTT 编辑、同核复制/删除及 URI；3D.8 菜单 13 提供状态、各参数专项和推荐值恢复，开启 0-RTT 确认重放风险；受管 TLS、UUID 共享额度。5C.9d 提供单核心、单个双族入口的监督范围 DNAT 和活动单端口分享，要求新 bundle marker；固定客户端自动换端口与完整管理仍 deferred。 |

### 内部服务端能力

原生协议注册表另含内部 ID `201..207`。这些能力不是公网节点，但属于路由、
中继和访问控制菜单，不能从对照范围中漏掉。

| ID | 能力 | 原生入口 | Docker 状态 | Docker 边界 |
| ---: | --- | --- | --- | --- |
| 201 | Socks 中继 | 路由与访问控制 -> 分流工具 | `deferred` | 5B.1–5B.2 已交付认证 TCP 全局/域名出站；入站仍未交付：sing-box 动态 UDP BND 发布不通，活动关联允许未认证且不在来源名单的 IP 借用，host-network 不能修复；5B.5b Xray 固定发布可达但控制关闭后无认证 UDP 仍可转发。 |
| 202 | HTTP 中继 | 路由与访问控制 -> 分流工具 | `deferred` | 5B.5a 提供已有受管 Xray 的私有认证 HTTP/CONNECT 入站、来源规则和事务管理；5B.5a.1 增加端口与来源名单日常管理，删空拒绝、认证冻结。双栈发布与来源已在隔离 amd64 Linux daemon 验证，IPv6 只接受管 bridge 并拒绝旧 plain bridge 恢复；sing-box 来源头绕过导致明确拒绝，公网/宿主/arm64 待验。 |
| 203 | WireGuard | 订阅与用户 / 路由与访问控制 | `host-integrated` | `net-wireguard`、host network、`NET_ADMIN`。 |
| 204 | TUN | 路由与访问控制 | `host-integrated` | 菜单 17→44 和 CLI 启用/关闭/规格状态；单 sing-box/单 Reality/IPv4，无其它宿主集成。固定接口和地址，host network、root、`NET_ADMIN`、`/dev/net/tun`；全局 IPv4 TCP/UDP，IPv6 拒绝。审计完整归属、正常停止及基线恢复后清证据；漂移或异常退出保留现场。 |
| 205 | Redirect/TProxy | 路由与访问控制 | `host-integrated` | `net-transparent`、host network、`NET_ADMIN`。 |
| 206 | DNS/Direct/Block | 路由与访问控制 -> DNS/hosts | `deferred` | 5B.3–5B.4f 已交付 DNS/hosts、已有 DNS 的域名稳定追加/精确删除（保留上游，删空关闭）、域名 Direct/Block（私有 JSON、CSV 整组替换、增量追加和精确删除）、目的 IP 名单（私有 JSON 替换/追加/完整字符串删除及字面单条替换）、明文 BT、CN 预设、IPv6 与 WARP 子合同和事务；5B.4e 已有 DNS/Direct/Block 与 selective WARP/IPv6 可单条原位替换，仅名单可改，缺旧/重复新/同值/CSV 拒绝。5B.4i 菜单 17→37 与 CLI 只替换已有 hosts 单键字面地址，key ASCII 转小写不去空白、IP 原文保持，其它键与完整配置冻结，不新增/删除/批量；定向与菜单通过，集中完整 49 项回归通过，属于有限管理增强。手工 IP 替换保留原文和位置，GeoIP 替换值拒绝；不匹配网络包含或区域合成项，完整区域策略、其它规则编辑与完整冲突检测待补。 |
| 207 | Tunnel/dokodemo-door | 路由与访问控制 -> 访问控制 | `deferred` | 5B.5c–5B.5e 提供已有受管入口的额外 Compose 发布端口、逐入口默认分享选择及别名原位改端口，复用认证/统计及 TLS/SNI 前端；宿主集成和公网/双架构验收未交付，不做任意目的转发。 |

## 功能和宿主边界

| 功能键 | 原生入口 | Docker 状态 | Profile | 网络/权限边界 | 当前说明 |
| --- | --- | --- | --- | --- | --- |
| `nginx` | 站点与证书 -> 传统 TLS fallback | `supported` | `nginx` | bridge | 独立 Nginx 容器，承载 WS/HTTPUpgrade/gRPC 反代与传统 TLS fallback 的 PROXY v1 HTTP/1.1、HTTP/2 后端；默认页、静态目录、302 与传统 TLS ALPN 经菜单/CLI 事务管理。 |
| `tls-files` | 站点与证书 -> 本机 TLS 证书 | `supported` | `nginx` / `acme` | bridge | 菜单/CLI 校验、导入轮换和只读挂载；Nginx 与 Xray/sing-box 逐消费者校验、重载/重建及健康失败恢复旧证书。核心端仅交付受管 TLS 文件底座，不代表新增协议或完整管理。 |
| `acme-dns` | 站点与证书 -> 本机 TLS 证书 | `supported` | `acme` | bridge + 宿主 CLI 调度 | 菜单/CLI DNS-01 issue/renew 及自动续期启停/状态；root 私有输入、唯一 systemd/cron 任务、部署锁和候选账户/证书事务；未到期跳过，更新/回滚保留最新输入，卸载只撤销受管任务。 |
| `subscription` | 订阅与用户 -> 订阅发布 | `supported` | `core-xray` / `nginx` / `subscription` | bridge | 既有部署级 token 发布继续要求 Xray 协议 `21` 和受管 TLS；分享组另有独立 token，可按账号/入口生成纯订阅内容并查看 HTTPS 链接；CDN/H3 仍未迁移。 |
| `subscription-traffic` | 账号管理 -> 流量与额度 | `supported` | 核心 profile | 宿主 CLI | 定时采集以及 show/collect/limit/reset；菜单 `10 -> 9` 查看不隐式采集，额度 `0` 表示不限额，设置/重置各确认一次，重置保留额度。沿用 CLI 采样与失败副作用；自用按原 UUID、独立账号按稳定 ID 共享跨核心累计与额度，凭据轮换和恢复不回退累计。 |
| `subscription-users` | 订阅与用户 -> 用户和分享订阅 | `supported` | 核心、订阅 | bridge | 4A.1–4A.4 账号底座、账号 CLI/菜单事务、独立 token 分享组及业务备份恢复已交付；账号/入口筛选、启停/轮换、纯内容与 HTTPS 链接，账号/组/额度/累计 merge/replace 恢复均复用候选事务，轮换与恢复不回退最新累计。4A.2a 凭据不进外部 argv，修复首次 SS 关联生成与迁移入口选择；已有账号须显式设置新增入口授权。CDN/H3 与完整多服务器工作流按独立功能边界验收。 |
| `subscription-multiserver` | 订阅与用户 -> 主控/被控、多服务器同步 | `deferred` | 订阅、WireGuard | host | 4C.1–4C.5 提供私网 API、主控管理、被控接入/手动同步及已有单 Peer 被控每 5 分钟自动同步 CLI/菜单。校验 Peer 归属、地址与唯一 `/32`，不建接口/密钥/路由；默认关闭，持久邀请限本机 root 私有目录，不进规格/备份/普通日志，停用清除凭据。独立服务和客户端零能力，无公网映射。隔离 amd64 双 Docker Engine 的生产 CLI/Compose、WS/TLS 流量、真实 cron 自主推进、同版幂等、锁竞争、轮换/撤销及健康失败/INT/TERM 恢复已验。正常 down 跳过，异常归属和 WS/SSH 来源防护组合拒绝。多 Peer、网络向导、角色重绑定、迁移、灾备、原生 systemd/双机/arm64、重启和可信发布待补。 |
| `acme-webroot` | 站点与证书 -> 传统 TLS fallback | `deferred` | `acme` / `nginx` | bridge | 5A.3b 已提供显式 opt-in 双栈 `80:8088`、独立 HTTP vhost、只读稳定根与 ops 独占 `active/`，菜单/CLI 和 schema 3 自动续期；归属及目录校验、不停 Nginx、失败/信号恢复和关闭/回滚保护。公网 CA、真实宿主生命周期及原生双架构未验，完整状态不升级。 |
| `acme-standalone` | 站点与证书 -> 本机 TLS 证书 | `deferred` | `acme` | 宿主预检 + bridge | 5A.3a 已提供 HTTP-01 首配、菜单/CLI 和自动续期；非 root ops 临时双栈 `80:8080`，实际归属校验，只暂停原运行拥有者并恢复；未到期不暂停。公网 CA、原生 Linux/双架构和 TLS-ALPN-01 未验，完整状态不升级。 |
| `site-static-redirect-alpn` | 站点与证书 -> fallback 站点、302、ALPN | `deferred` | `nginx` / `core-sing-box` | bridge | 5A.1 站点、5A.1b 受管 notes/photos/docs 模板、5A.1c Hysteria2 local 与 5A.2 逐入口 ALPN 诊断/三种顺序事务已提供；模板限已有 v3 Xray 21–25/27/29 或 Hy2，拒绝 sing-box 23，资源清单随 bundle 校验，生成后仍普通 static。local 固定只读目录且无混淆，纯 Hy2 只开放静态模式。隔离 amd64 27/29 的真实 Xray 双栈 TLS ALPN、h1/h2 fallback/404、PROXY 来源与认证已验，公网及原生双架构仍待验。 |
| `reality-target-management` | 协议与入口 -> REALITY 管理 -> 目标站管理 | `supported` | 核心 profile | 宿主 CLI | 对齐原生 8 项管理及首配候选检测/手动输入；检测 TLS/PQC/ASN/证书链、刷新库、网段/同 ASN 抽样扫描、A 级筛选分页与逐入口切换、host[:port]/独立 SNI、黑名单；扫描进度和部分结果处理共用原生，B/C 手动告警，全部地址按最差评分及 CDN 风险判定，缓存切换重新复测，Docker 私密状态与事务恢复独立于原生。 |
| `reality-parameter-management` | 协议与入口 -> REALITY 管理 -> 重新生成参数 | `supported` | 核心 profile | 宿主 CLI | 菜单/CLI 按入口重生成密钥对和 short ID，派生校验、候选确认和失败恢复；账号、目标、其它入口及额度保持，链接和已启用发布同步更新。 |
| `reality-coexistence` | 协议与入口 -> REALITY 管理 -> 443 共存分流 | `deferred` | `core-xray` / `nginx` / `nginx-stream` | 宿主 CLI | 已提供受管 TLS 入口、桥接可达宿主网站或独立 host 网络分流入口与一个 Xray Vision/XHTTP 后端的 443 共存；菜单/CLI 状态、开启、更换、关闭及端口恢复复用候选事务。宿主网站的多个 SNI、host-gateway、可路由 IP 或回环支持有明确边界；原生宿主、适用公网及完整管理仍待验收。 |
| `entry-port-management` | 协议与入口 -> 入口端口管理 | `deferred` | 核心 | bridge | v2/v3 多入口复制/删除及端口事务，v3 明确核心归属；5B.5c–5B.5e 额外端口增删/原位修改/状态/默认分享的菜单/CLI 与候选恢复，已有本地真实发布证据；修改保留别名顺序及默认分享标记，复用原认证、统计及 TLS/SNI 前端。受管或桥接可达宿主网站的 Reality 443 共存可使用别名；拒绝 WS/SSH Fail2ban、TUN/TProxy 和 host-network，允许已有 WireGuard/控制面 Fail2ban。既有身份/内部端口冻结，端口跳跃及适用公网/IPv6/原生宿主/arm64、完整管理仍待交付或验收。 |
| `cdn-entry-management` | 协议与入口 -> CDN 入口管理 | `deferred` | `subscription` | bridge | 4A.5–4A.5b 提供协议 21/22/23/24/25 的逐入口多连接地址覆盖，菜单/CLI 状态、设置和清除，统一生成本地链接、主订阅及分享组；保留端口、SNI、Host/路径或 gRPC serviceName/h2 与认证，候选确认及失败恢复复用现有事务。24/25 仅已有 Xray/Nginx TLS，带映射另要求 x-padm-cdn-grpc-tls，旧三协议/无映射 gRPC 子集保持。其它协议、H3、公网供应商透传、真实宿主/arm64 和可信发布仍待验。 |
| `fail2ban` | 系统与脚本 -> Fail2ban 防护 | `host-integrated` | `net-fail2ban` / `net-fail2ban-control` / `net-fail2ban-ssh` | host + `NET_ADMIN` | WS DOCKER-USER、控制面 INPUT 与专用 SSH INPUT 的独立 owner 和菜单/CLI；SSH/control 不共存。5C.6d 单 WS 保护端口专项已验实际双栈封禁、端口迁移、SQLite 保留、来源/健康失败恢复与旧规则清理，新旧端口均需 fresh 来源，别名、Reality stream 和其它集成拒绝；WS 日志组为 `0:10001`，权限不放宽。控制认证日志支持菜单/CLI 每小时轮转检查，默认关闭、本机私有登记、同锁与旧 bundle 门禁；线上 auto 入口及隔离 amd64 原始每小时 :19 cron 自主触发、实际归档/续写/停用已验，systemd 实际定时触发待验。SSH 限原生 root systemd/cgroup v2、无存量会话且禁止 reload 的单 service/单显式监听，只消费启动后的可信密码失败。transient collector、只读日志/10 秒 guard、启停/状态/单 IP 解封已接，来源失效自动停 jail/精确清理，禁自动重启和恢复旧封禁；SSH 启用时 update/rollback/业务恢复拒绝，先受管停用。隔离 amd64 OpenSSH 10/Fail2ban 1.1 实际启停、封禁、连接 DROP、解封和来源失效清理已验；原生宿主/arm64/公网/重启卸载及完整管理仍待验收。 |
| `wireguard` | 订阅与用户 / 路由与访问控制 | `host-integrated` | `net-wireguard` | host + `NET_ADMIN` | 接口和密钥由宿主内核拥有。 |
| `tun` | 路由与访问控制 -> TUN | `host-integrated` | `net-transparent` | host + `NET_ADMIN` + `/dev/net/tun` | 显式启用透明代理设备。 |
| `tproxy` | 路由与访问控制 -> Redirect/TProxy | `host-integrated` | `net-transparent` | host + `NET_ADMIN` | 菜单 17→43 和 CLI 管理单 Xray/sing-box Reality，IPv4/IPv6/双栈 PREROUTING TCP/UDP。OUTPUT 默认关闭，可选 UID 或包含 root 的全主机主动 TCP/UDP；互斥、省略保留，关闭保留 PREROUTING。全主机核心 0:10001，GID 10001、LOCAL/REPLY 绕过；实际核心身份与两族两链均须核验。漂移或缺关键绕过保留现场；旧 schema 2/3/4 兼容，全主机 schema 5 和共享 marker。拒绝其它宿主集成；原生宿主/arm64/公网/重启/完整卸载及完整管理待验。 |
| `redirect` | 路由与访问控制 -> Redirect/TProxy | `host-integrated` | `net-transparent` | host + `NET_ADMIN` | 菜单 17→47 和 CLI 管理单 Xray/sing-box Reality 1/2/26，同核心多入口；三族 PREROUTING，OUTPUT 可选 UID 或全主机主动 TCP，UDP 保持原路由。默认关闭、互斥、省略保留；全主机包含 root，核心 0:10001，GID 10001、LOCAL/REPLY 绕过，实际身份须核验。schema 1 兼容，全主机 schema 2 和共享 marker。两族两链先完整审计再精确撤销，漂移保留现场；拒绝其它宿主集成或副核心。原生宿主/arm64/公网/重启/完整卸载及完整管理待验。 |
| `routing-tools` | 路由与访问控制 -> WARP/IPv6/Socks5/DNS/BT/访问控制 | `deferred` | 核心 | bridge | 5B.1–5B.4g 已交付 SOCKS5 TCP 出站、DNS/hosts、域名 Direct/Block、目的 IP、明文 BT、CN 预设、IPv6 和用户态 WARP 子能力及失败恢复；已有 WARP 可保留密钥修改域名、全局模式及地址族，已有 selective WARP/IPv6 可增删域名，缺失/global 拒绝、删空关闭；区域自定义例外及手工字面 IP/CIDR 可单条原位替换，冻结其余配置。5B.4h 接入已有非空 selective SOCKS5 域名增删/单条替换，保留上游/凭据；缺失/global 拒绝，删空关闭整个 SOCKS5，重新导入才可启用，不转全局，定向、菜单及完整 49 项回归已通过。5B.4i 菜单 17→37 与 --hosts-replace 只替换已有精确 FQDN 的单字面 IP；key ASCII 转小写不去空白，IP 原文保持，空白/尾换行/CSV/前缀/坏地址返回 2，缺键/未启用/同值返回 15；其余 hosts、完整配置、URI/订阅/累计冻结，原 JSON 整组入口保持，不新增/删除/批量，不扩 schema/marker/权限/状态。定向与菜单通过，集中完整 49 项回归通过，属于有限管理增强。不改宿主；完整区域/访问控制和公网/宿主/双架构验收待补。 |
| `internal-201-socks-relay` | 路由与访问控制 -> Socks 中继 | `deferred` | 核心 | bridge | 5B.1–5B.2 TCP 出站子能力已交付；5B.5b–5B.5b.1 确认 sing-box 动态 BND 发布阻塞且未认证来源可借用活动 UDP 关联，Xray 26.3.27 的 UDP 来源许可在当前进程内不随控制关闭撤销。host-network 不能解决核心鉴权问题，完整入站不交付、不降为 TCP-only；不作为公网节点。 |
| `internal-202-http-relay` | 路由与访问控制 -> HTTP 中继 | `deferred` | `core-xray` | bridge | 5B.5a 独立 `relay.http` 合同、私有认证与来源前置规则、菜单/CLI/关闭/回滚；5B.5a.1 提供已有中继端口及来源名单替换/追加/精确删除，冻结认证与其余规格、删空拒绝；专属直连且不计业务额度。双栈发布与真实来源已在隔离 amd64 Linux daemon 验证，IPv6 relay 只接受管 bridge，拒绝旧包/旧 plain bridge 恢复；拒绝 sing-box 的代理头来源覆盖，公网、宿主、arm64 和可信发布待验。详见 `docker-http-relay.md`。 |
| `internal-203-wireguard` | 订阅与用户 / 路由 -> WireGuard | `host-integrated` | `net-wireguard` | host + `NET_ADMIN` | 接口由宿主内核拥有；4C.3a 核验真实归属后预检/健康/撤销，活动旧式标记需先正常停止旧容器。 |
| `internal-204-tun` | 路由与访问控制 -> TUN | `host-integrated` | `net-transparent` | host + `NET_ADMIN` + `/dev/net/tun` | 5C.2c 菜单 17→44 与 CLI 启用/关闭/状态；限单 sing-box、单 Reality、IPv4、无其它宿主集成。全局 IPv4 TCP/UDP，IPv6 拒绝；CID/StartedAt/netns/接口/规则/路由完整绑定，候选只读检查，正常停止且基线清净才清 state。隔离 amd64 生产启停/重启/漂移拒绝/异常退出保留现场已验；原生宿主/arm64/公网/重启/完整卸载及完整管理仍待验。 |
| `internal-205-redirect-tproxy` | 路由与访问控制 -> Redirect/TProxy | `host-integrated` | `net-transparent` | host + `NET_ADMIN` | TProxy TCP/UDP 和 Redirect TCP 的有限管理范围同上，两者互斥；完整 Redirect/TProxy 管理及宿主验收仍 deferred。 |
| `internal-206-routing-rules` | 路由与访问控制 -> DNS/Direct/Block | `deferred` | 核心 | bridge | 5B.3–5B.4g 已交付 DNS/hosts、已有 DNS 的域名稳定追加/精确删除（保留上游，删空关闭）、域名 Direct/Block（私有 JSON、CSV 整组替换、增量追加和精确删除）、目的 IP 私有 JSON 替换/追加/完整字符串删除及字面单条替换、明文 BT、CN 预设与自定义直连例外增删/单条替换、IPv6、WARP 子合同及日常域名/模式/地址族编辑、已有 selective IPv6/WARP 域名增删、双核心适配及专项事务；已有域名单条替换保留位置、DNS 上游和 WARP 私有字段，缺旧/重复新/同值/CSV 拒绝。5B.4h 接入已有非空 selective SOCKS5 名单增删/替换，非空只改 domains，冻结 server/port/username/password；删空仅 remove 可关闭整个 SOCKS5，重启用需导入凭据，不转 global，定向、菜单及完整 49 项回归已通过。5B.4i 菜单 17→37 与 --hosts-replace 只替换已有 hosts 单键字面地址，key ASCII 转小写不去空白、IP 原文保持；空白/尾换行/CSV/前缀/坏地址返回 2，缺键/未启用/同值返回 15，冻结其它键及完整配置/URI/累计；原 JSON 整组保持，不新增/删除/批量或 schema/marker/权限/状态。定向与菜单通过，集中完整 49 项回归通过，原生完整迁移仍 deferred。手工 IP 替换保留 IPv6 原文/CIDR 宿主位和顺序，仅 ips 数组可改，GeoIP 替换值拒绝。global/缺失增删拒绝、删空关闭对应策略，手工 IP 与区域合成保持独立，完整区域策略、其它规则编辑、完整冲突检测和适用公网验收待补。 |
| `internal-207-access-control` | 协议与入口 -> 额外入口端口 | `deferred` | 原业务核心/Nginx | bridge | 5B.5c–5B.5e 独立 `port_aliases`、菜单/CLI 增删/原位修改/状态/默认分享与候选回滚；双栈 TCP/UDP 发布已在隔离 amd64 Linux daemon 验证，同入口认证/统计，TLS/SNI 前端不旁路，URI/主订阅/分享组逐入口选择已有别名，修改保留默认标记，恢复或删除后回退 base，不增加节点。拒绝 WS/SSH Fail2ban、TUN/TProxy 和 host-network，允许已有 WireGuard/控制面 Fail2ban；适用公网/原生宿主/arm64 与完整管理验收待补。 |
| `interactive-menu` | 全部主菜单 | `deferred` | 无 | 宿主 CLI | 已有状态/启停/日志、可信首配、规格编辑/多入口/双核心、Reality 目标/参数/443 共存、TLS/ACME、账号/分享组/额度/业务备份恢复、核心/Geo、多服务器手动同步和已有单 Peer 被控自动同步、站点/路由与 WS/控制面/有限 SSH Fail2ban 菜单。仅开放已交付组合；完整协议管理、多 Peer/迁移/灾备、剩余宿主能力及可信发布/原生双架构完整生命周期仍待交付或验收。 |
| `core-lifecycle` | 核心与服务 | `supported` | 核心 profile | 宿主 CLI | 基础 `status/up/down/restart/logs/update/rollback/validate` 已可用，不代表原生全部升级管理。 |
| `core-upgrade-assessment` | 核心与服务 -> Xray / sing-box 生命周期 | `supported` | 核心 profile | 宿主 CLI | 菜单第 13 项及 `assess` 复用只读风险扫描，使用可信候选镜像/配置副本执行版本检查、双核心配置试跑、Xray 严格模式与能力探针及已启用的 TLS/订阅/宿主前置检查；旧核心不启用严格解析时明确警告，不切换生产状态。要求受管 spec，预发布须提供匹配的可信发布资产；真实客户端连通另验。 |
| `geo-data` | 核心与服务 -> Xray Geo 数据 | `supported` | `core-xray` | 宿主 CLI | 菜单第 14 项与 `geo status/update/schedule/auto-update` 已交付；完整受管数据经双摘要及真实 Xray 解析校验后切换读取路径，重建前采集 Xray 流量，仅重建原本运行的 Xray，失败恢复数据/Compose/运行状态；每日 01:35 systemd/cron 任务有部署归属和锁。编辑、更新和回滚保留数据及调度登记，旧 bundle 在切换前拒绝；真实上游、生产重建、宿主调度、arm64 和整机重启另验。 |
| `script-update` | 系统与脚本 -> 更新 padm | `supported` | 无 | 宿主 CLI | `padm-docker update` 处理签名 bundle、镜像和配置事务。 |
| `network-optimization` | 系统与脚本 -> 网络优化 | `unsupported` | 无 | host | Docker 不修改宿主 BBR/fq。 |
| `uninstall` | 高级/危险操作 -> 卸载脚本 | `supported` | 无 | 宿主 CLI | 受管卸载、移除镜像和显式 purge。 |
| `vless-encryption` | 高级/危险操作 -> VLESS Encryption 实验 | `unsupported` | `core-xray` | bridge | 尚未纳入 Docker 配置合同和回滚边界。 |

## 第一阶段验收

完成本阶段后，后续实现必须满足：

1. 新增 Docker 能力必须同步更新配置合同、Compose、控制命令和回归；实现及验证齐备后再升级 `features.json` 的支持状态。
2. 配置运行状态为 `supported` 的协议必须同时有核心、profile、生成配置和回归证据；管理工作流必须单独更新 `management_status`。
3. `host-integrated` 必须写明 `network_mode`、capability、device 和宿主规则所有权。
4. `deferred` 和 `unsupported` 必须在安装前明确拒绝，不能偷偷调用原生安装器。
5. 原生公开协议 ID、`transport` 或 `udp_support` 改变时，Docker 阶段 3 回归必须发现矩阵漂移。
6. `features` 的每个兼容状态值必须与 `feature_matrix` 同名值一致；`supported` 功能的 `requires` 前置条件必须与实际校验一致。
