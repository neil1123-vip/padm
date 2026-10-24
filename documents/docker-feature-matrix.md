# Docker 版功能对照表

日期：2026-10-18

这份表是“原生菜单功能”和“Docker 当前能力”的第一阶段基线。状态只表示
Docker 现在能否通过受管控制命令完成对应能力，不表示底层镜像里是否包含某个
上游程序。

当前导航（2026-10-19）：Docker 首页已按原生版归为安装与重装、订阅与用户、
协议与入口、站点与证书、路由与访问控制、核心与服务、系统与脚本、
高级/危险操作 8 类，并复用共享菜单样式。当前路径见 [README](../README.md#docker-版)；
下文历史记录的顶层 `9` 协议、`17` 路由和 `18` 维护，分别对应
`3 → 9`、`5 → 1 → 9` 和 `7 → 1`，专项操作编号保留。
SOCKS5 入站保留不可用说明；两版核心升级机制保持原样，Docker 继续整包验签升级与回滚。
共享样式也覆盖首次配置、TLS 管理和配置编辑的标题、列表及摘要边框；
专项操作编号、输入顺序、默认值、凭据隐藏、确认与事务和非交互 `--preview` 输出保持。
本表支持状态和历史验收结论不变。

后续实施顺序和验收门槛见
[Docker 菜单与功能对齐实施计划](docker-menu-parity-plan.md)。计划安排不改变本表的当前支持状态。

2026-10-18 已补 Debian 13 原生 amd64 的正式发布验签、WS 21 首配、
升级/回滚、整机重启、公网客户端和 Cloudflare CDN 正反例，以及
Let's Encrypt standalone 签发、真实续期调度和 WS/SSH 精确封禁。
SSH 项依赖测试目录权限修正，正式版本缺陷及尚未发布的源码修复见
[本轮原生验收记录](docker-native-acceptance-2026-10-18.md)。
Redirect 另有 IPv4 TCP/TLS 与实际规则计数证据；TProxy 出现广播误捕获和内存/Swap
耗尽后，已通过 SSH 恢复及重启验证。完整循环机制尚未实测；精确撤销后规格已清除
透明宿主集成，业务保持停止且 `restart=no`；TProxy/TUN 及完整卸载仍待补验，
远端原生测试目录已清理。
当前源码还禁止 TProxy/Redirect 规则容器自动重启，旧编排仅兼容受管停止、清理与更新；
更新及旧备份恢复规范化该策略，普通启动先拒绝旧策略。此修复尚未发布，不改变支持状态。
透明集成启用时仅允许具备受管重启 marker 的当前及目标控制包；旧包须先停用集成再切换版本。
证据只覆盖记录中的组合；原生 arm64、实际到期续期和其余验收缺口继续保留，
不据单一工作流通过升级完整管理或灾备状态。

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
真实发布及完整管理继续 `deferred`。

3D.15 提供证书菜单 `10` 与 `edit --tls-migrate` 的已有 TLS 域名迁移，
显式选择受管/导入/DNS-01/HTTP-01 standalone 证书。
仅改变 TLS 域名和等于旧域名的 TLS 连接地址，其余规格、账号、分享 token、
累计和独立资产保持；失败沿用现有恢复。ACME 预览不申请证书。
旧续期登记不迁移，活跃 webroot 按 3D.19 在迁移成功后停用；宿主集成、Reality 共存、
跳跃及控制角色继续拒绝。验证结果见实施计划，公网 CA 验收继续 `deferred`。
Linux amd64 entries/menu 定向、同快照静态检查和完整 57/57、
347 项规格差分通过；完整入口 `382722 ms`、Jobs 6，本批无失败重跑。

3D.16 将 ACME 成功后的续期入口接入首配/重新选择、首个 TLS 安装、
域名迁移和证书菜单申请/续期；交互默认否，可复用原参数直接启用。
非交互编辑显式加 `--tls-auto-renew`，仅 DNS-01/standalone 接受；
预览和取消不登记，受管/导入证书保持原流程。
登记沿用独立恢复事务，失败返回错误并明确保留成功配置与证书。
不迁移旧登记、不暗中开放 webroot；完整状态仍按现有边界。
Linux amd64 `docker-setup-tls`、`docker-menu`、`docker-phase3-entries` 定向，
同快照静态检查及一次 `docker-contracts -Jobs 6` 通过；合同 57/57、规格差分 347 项，
完整入口 `409194 ms`，本批无失败重跑。公网 CA、真实宿主调度和新部署 webroot 引导继续 `deferred`。

3D.17 新增 Nginx TLS `21–25/27/29` 的首配、首个 TLS 和域名迁移 webroot 引导：
证书选项 `5` 与 `--tls-webroot <邮箱>` 先临时运行仅 HTTP-01 的固定 Nginx，
再由正式配置持久监听双栈 80，可显式接续 schema 3 自动续期。
预览/取消不启动挑战，失败和信号复用现有恢复；旧登记不迁移，
活跃旧域名 webroot 按 3D.19 衔接停用。公网 CA、原生宿主与 arm64 等边界保持。
四项定向与 Bash/ShellCheck error 通过，真实非 root Nginx 双栈 token 及四类 404 通过；
集中 `docker-contracts -Jobs 6` 一次通过，57/57 合同、347 项规格差分，
入口 `382523 ms`，排队 `3989 ms`。证据
`.tmp-regression-docker-673f7ecc870f4537aff98efed3ee5509/`；
工具镜像 Nginx 自检不代替固定发行镜像、公网 CA 或真实宿主调度验收。

3D.19 允许已有 TLS 域名通过专项迁移跨过活跃旧 webroot 续期保护，
配置成功后用独立事务停用旧登记，再沿原选择登记新域名；
预览、取消及配置失败保留旧登记。旧证书、ACME 账户与其它域名登记保持，
普通配置、关闭入口和回滚的保护不变。续期调整失败返回错误并保留成功配置，
提交后中断可能需手动重试旧登记停用。公网 CA、原生宿主/arm64 及完整管理继续 deferred。
Linux amd64 续期及静态检查通过；完整合同 56/57 通过，唯一 entries 测试预期
修正后定向补验通过，347 项规格差分通过，未重复全套；详细证据见实施计划。

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

5B.4t 菜单 `17 → 14/26/27` 直接录入 IP/CIDR CSV，CLI 增加
`--block-ips-csv`、`--block-ips-add-csv` 和 `--block-ips-remove-csv`。
仅去每项首尾空白，保留 IPv6 写法和 CIDR 主机位；复用已有私有候选、校验和事务，
保持 1–256 项、固定 `geoip:cn`、整批缺项拒绝、删空关闭及解析模式保留。
原 JSON 接口继续提供，不扩展 schema、渲染、权限或完整路由支持状态。

5B.4h 已接入菜单 `17 → 34/35/36` 与 CLI 的已有非空 selective SOCKS5 域名增删/单条替换。
未启用/global 拒绝；追加稳定去重、合并最多 256 条，删除缺项整批拒绝，
替换拒绝 CSV/缺旧/重复新/同值并保留位置。非空只改 `domains`，冻结上游、凭据及其它配置；
删空关闭整个 SOCKS5，重新启用须录入或导入凭据，不切 global。定向合同、菜单 PTY 与完整 49 项回归已通过，
不新增 schema/marker 或宿主权限，不升级上述整体 `deferred` 状态。

5B.4i 已接入菜单 `17 → 37` 与 `edit --hosts-replace <已有精确 FQDN> <新单字面 IP>`，
该单键替换操作不负责新增、删除或批量编辑，分别见 5B.4j/5B.4w。key 只将 ASCII 字母转小写，不去空白，
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

5B.4u 与 5B.5a.2 将 SOCKS5 上游/认证、HTTP 中继认证/来源接入直接录入，
旧私有 JSON CLI 保留。凭据隐藏输入并通过标准输入进入私有候选，
完整校验和一次确认沿用原事务，不扩 schema、核心、权限或公开支持状态。
HTTP 来源必须明确填写，SOCKS UDP 与 sing-box HTTP 来源限制保持。

5B.4w 将菜单 `17 → 8` 与交互 `--hosts-input` 接入 hosts 批量录入：
一个字面 IP 与 1–256 个精确 FQDN 整组替换，域名去空白、ASCII 小写和去重，
拒绝空项、规则前缀及通配符；仅交互 TTY，空/0/EOF 取消，原私有 JSON CLI 保留。
复用完整校验、冻结比较、一次确认和失败恢复，不扩 schema、权限或支持状态。

5B.4v 将已有 WARP Peer 七字段接入菜单 `17 → 20 → 1` 与交互 `--warp-input`，
隐藏私钥、stdin 写入私有候选，旧 JSON CLI 和原完整校验/恢复事务保持。
仍不注册 Cloudflare 账号或保证公网出口，完整路由管理继续 `deferred`。

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
5C.9e 增加 `port-hopping recover --preview` 与
`--confirm PADM-DOCKER-HOPPING-RECOVER`，跳跃菜单 `8` 先预览再确认。
仅同 boot/namespace 内原 manager/Bash 代次均结束、绑定的 stage 路径/child/target/
root-data-net 投影及部署锁仍匹配、
精确子容器退出 `0`、state 消失且双族 NAT 无残留时清理，活跃/未知/漂移均拒绝留证。
持目录描述符拒绝本次核验/清理期间替换；既有证据不记录 stage/session 历史 inode，
不能识别此前同内容重建，合作锁不抵御任意特权替换。
返回 `recoverable/stopped` 与完整 `saved`，保留规格、账号和累计，不删 conntrack；
清理后须显式 `start` 建立新代次和挑战，不用旧 JSON/tuple 授权。
旧无 spec 部署先用 `edit --spec <完整原始输入>` 匹配实际部署接入，
保留账号配置与累计，再保存范围并显式启用；不从运行配置推造完整规格。
本地 amd64 旧接入定向 25.819 秒、TUIC 恢复真实 53.793 秒、
Hy2 自动跳跃及恢复链 105.324 秒通过；集中合同一次 57/57 组、含 141 项监督合同，
入口 428.109 秒、Jobs 6/tmpfs、排队 335 ms、`cache_hit=false`。
后续恢复改动优先 `docker-port-hopping-recovery-real`（Jobs 2），
Hy2 自动跳跃使用 `docker-port-hopping-auto-real`，不另行重复旧长生命周期集合；
完整证据 `.tmp-regression-docker-7c7189dcb0f348d88174f898f342d922/`。
5C.9f–5C.9g 补固定官方 Mihomo `v1.19.28` 的原始分享 URI 导入验收。
Hy2 共用生成器保留 `upmbps/downmbps`，同时增加等值 `up/down`，
保持客户端方向，修复该客户端转换时丢失 Brutal 带宽；仅测试依赖，不新增生产核心。
`docker-port-hopping-share-real`（Jobs 2）分别在独立 netns 核验
Hy2 Brutal + Salamander/Gecko 原范围 URI 的同进程双族跨端口 HTTP，
以及 TUIC 首尾普通 URI 的双族连接、错误账号拒绝与停止净撤销。
Hy2 使用客户端原生默认 30 秒随机换端口，观察上限 300 秒，满足即停。
生成器合同与配置定向分别 127.283 秒、29.466 秒通过，
分享组合真实 146.808 秒、集中完整合同 57/57 组 555.266 秒通过；证据见实施计划。
停止后的新连接探针带齐实际带宽/混淆参数，并先用同参数证明范围首尾端口均可连接；
Hy2/TUIC 停止后再由新客户端进程验证拒绝。三种独立场景按入口 Jobs 并行，
本次完整分享专项 284.515 秒通过，累计场景耗时 392.462 秒；随机选端口仍可能拉长等待。
自动恢复、其它客户端导入、TUIC 客户端自动跳跃、
旧 conntrack 排空及原生宿主/arm64/公网与完整协议管理继续 `deferred`。

3B.4 的 Linux amd64 与 arm64 仿真双核心 TLS、WS 客户端及失败/信号恢复已通过，
证据和剩余限制见[真实 TLS 验收基线](docker-tls-real-baseline.md)。
内部 TLS 夹具不代表新增协议支持；真实 DNS、完整宿主重启、原生 arm64 和可信发布仍待验。

## 状态定义

| 状态 | 含义 |
| --- | --- |
| `supported` | Docker 配置合同、控制命令和 Compose profile 已能完成该能力。 |
| `host-integrated` | 能力依赖宿主内核、接口或防火墙；只能通过显式 `net-*` profile 使用。 |
| `deferred` | 原生已有能力，Docker 完整管理或所需验收尚未完成；已交付子能力以逐项边界为准。 |
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
公网扫描、部署网络候选可用性及原生 arm64 仍待环境验收；有限 443 共存已交付，范围见对应专项，
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
3D.23 菜单按普通/高级/实验分组并保留原编号；参数回车采用本次状态的当前值。
新增 `23/24` 与 `--xhttp-concurrency` 只改 XMUX 并发，保留另外两键及 mode，
原无 XMUX 时初始化默认请求数和复用秒数；沿用原能力门禁、锁与发布事务。
`docker-menu-xhttp` 可独立验证交互，完整菜单保留相同场景。
3D.23 Linux amd64 菜单/编辑/回滚/分发定向通过，源码摘要与唯一集中完整合同相同；
完整 `58/58`、`469466 ms`、Jobs `6`、cache=false，TERM 退出清理断言通过。
证据 `.tmp-regression-docker-923b1a3b57b043a2820ee249f5f3568b/`，成功输入已清。
3D.10 Linux amd64 XHTTP/菜单定向通过，集中完整合同 57/57 一次通过，`380824 ms`；
定向和完整源码摘要相同，临时输入已清，真实客户端矩阵复用既有证据。
3D.20 接入菜单 `18/19` 和 `--xhttp-request-headers`/`--xhttp-request-headers-clear`，
管理已有 v3 Xray XHTTP 单入口的客户端请求首部；1–8 项，名称为 1–64 位字母/数字/连字符，
以字母或数字开头且忽略大小写唯一，值为 0–256 位可打印 ASCII。
拒绝 Host、连接控制、Content-Type 和 Referer 等核心保留字段；清除删除字段，
显式字段要求 `x-padm-xhttp-request-headers`，状态、服务端配置和 URI 同步。
预设/高级参数/推荐恢复保留，复制/派生继承；不提供服务端响应首部或访问认证，
内容会进入分享链接和订阅。完整管理继续 deferred。
本地 amd64 合同、菜单、真实 TLS/h2 与 Reality 链路通过；集中完整合同
57/57、353 项差分，入口 404.019 秒，合法长转义 JSON 补验 50.896 秒。
新增 `docker-xhttp-headers` 直接复用已有分片，后续仅跑匹配定向。
3D.21 增加同入口额外端口的上下行分离：菜单 `20/21`、
`--xhttp-download`/`--xhttp-download-clear` 管理可选 `xhttp.download_port`，
要求 `x-padm-xhttp-download`。端口必须是同一 v3 Xray 协议 `2` 入口已登记的
非默认分享别名，拒绝基础、默认分享、其它入口和未登记端口；沿用已有后端及端口发布。
状态增加 `download_port`（缺省 `null`）和 `download_enabled`，
统一 URI `extra.downloadSettings` 指向本入口服务器与所选端口，
Reality 公钥/short ID/SNI、路径/Host 和其它 XHTTP 参数随来源更新，下行模式固定 `auto`；
服务端配置不投影 `download_port` 或 `downloadSettings`。
预设、高级参数、推荐恢复保留绑定，复制/派生只保留源入口绑定，新入口清除，
不能借用源入口的别名。
新增 `docker-xhttp-download` 复用验证、发布、失败恢复及复制/派生分片；
本地 amd64 下行定向/菜单/真实链路分别 33.797/60.831/26.798 秒通过，
真实 5 入口/20 业务及 4 个坏下行端口拒绝通过；集中合同 57/57、
365 项差分，407.727 秒、Jobs 6、排队 318 ms、`cache_hit=false`。
3D.22 增加菜单 `22` 和 `--xhttp-download-settings` 的独立下行客户端元数据，
完整显式 `xhttp.download` 对象与 `download_port` 互斥，设置任一形式清除另一形式，
菜单 `21`/`--xhttp-download-clear` 清除两类绑定。地址为域名或严格 IPv4/IPv6，
端口 `1..65535`，SNI/Host 为域名，安全路径与上行相同；
模式 `auto/stream-one/packet-up/stream-up`，TLS 仅接受单一 ALPN `["h2"]`/`["h3"]`，
Reality 要求公钥和 short ID，安全类型字段不得混用，其它字段拒绝。
要求 `x-padm-xhttp-download-settings`，旧无字段规格与原下行端口子集兼容；
状态新增 `download_settings`，URI 仅投影该对象地址、安全身份及三项 XHTTP 参数，
不继承上行高级参数，服务端不投影客户端字段。其它编辑保留，复制/派生只清新入口绑定。
外部前置必须已部署并汇入同一 XHTTP handler/认证，不自动建设 TLS/H3/CDN
拓扑，不支持无会话关联的独立后端。本地 amd64 定向 62.650 秒、真实 28.090 秒通过；
真实复用既有入口，不另行启动旧 3D.21 矩阵，同一入口仍执行原首部 18 项和原业务 20 项，
新增 TLS h2/h3/Reality 同 handler 前置的 12 项回显及 8 项坏身份拒绝。
唯一一次集中合同 56/57 分片、386 项差分通过，483.718 秒、Jobs 6、排队 317 ms；
新增菜单取消场景检查点失步，修正 INT 返回和等待截止后，菜单单独补验 61.201 秒通过，
其余未变分片复用本轮证据，不记为同一次 57/57。完整证据
`.tmp-regression-docker-6423ec078ca84c4e88274c4ef55c7378/`，菜单补验证据
`.tmp-regression-docker-87308a5670734e82947e2c497a808970/`。
当前原生菜单的四项 `sc*` 参数已覆盖；公网、宿主/arm64、完整管理及性能收益继续 `deferred`。
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
AnyTLS 单独部署不能发布 HTTPS 订阅，组合至少一个同域 Nginx TLS `21–25` 入口后可包含 AnyTLS 链接。
3C.5 新增 sing-box NaiveProxy：v3 首配、导入、通用字段编辑、同核复制/删除及原生分享 URI，
仅监听 TCP，入口域名与 TLS 域名一致；UUID 作为用户名、密码和统计标识，不添加 `name` 字段。
真实 amd64 双栈 SOCKS HTTP proof 及 UUID 正上/下行计数已通过；宿主集成、QUIC 和独立 IP/SNI 覆盖未开放。
3C.6 新增 sing-box Shadowsocks 2022 AES-128 多用户：v3 首配、导入、通用编辑、
同核复制/删除与 SIP002 分享链接，TCP/UDP 双栈，不需要 TLS。
服务器/用户密钥分别生成，UUID 共享统计额度；超额移除入站，解除额度恢复原输入。
真实 amd64 双栈 TCP/UDP、UUID 正计数、服务器密钥单独认证拒绝及超额/恢复通过。
Docker 账号子命令支持 SS 账号创建、复制、授权关联/移除、独立密钥轮换及失败恢复；
3D.24 新增菜单 `9 → 19` 与 `edit --rotate-ss-user ID`，仅轮换已有 v3 sing-box
协议 `30` 的选中入口自用用户密钥，保留服务器密钥、UUID、同 UUID 其它入口、
独立账号密钥、额度与累计。主订阅/自用 URI 更新，独立账号分享组内容保持，
客户端须重新导入；专项、amd64 双族 TCP/UDP 真实探针及完整合同通过，
3D.25 增加菜单 `9 → 20` 与 `edit --rotate-ss-server ID`，只修改选中入口服务器密钥；
自用/独立账号用户密钥、其它入口、授权/token、额度与累计保持，该入口所有客户端须重新导入。
专项与真实链路的当前验收见实施计划；宿主集成与完整管理仍未开放。
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
4A.7 扩展协议 22 复用自身同域 Nginx TLS 入口发布 HTTPS 订阅，隔离 amd64 主/组实链路已验；暂不接受宿主集成，完整管理仍为 `deferred`；
公网宿主入口、第三方导入 UI、业务镜像签名发布和原生 arm64 客户端仍待验。
3C.10 新增两核心 VMess HTTPUpgrade TLS：v3 首配、导入、入口与路径编辑、跨核心复制/删除及分享链接，
固定 `alterId=0`，独立 `httpupgrade` 字段复用 Nginx/TLS、UUID 统计和额度。
Nginx 按入口核心反代，后端端口按核心隔离，TLS 端口全局唯一；路径不附加 `ws`。
真实 amd64 两核心各双栈 TCP/UDP 隧道、大小写域名 Host/SNI、错误 UUID、统计与同客户端额度恢复通过。
4A.7 扩展协议 23 复用自身同域 Nginx TLS 入口发布 HTTPS 订阅，含纯 sing-box 部署，隔离 amd64 主/组实链路已验；宿主集成及完整管理继续未开放。
3C.11 新增 Xray VLESS/Trojan gRPC TLS：v3 首配、导入、通用字段与服务名编辑、同核复制/删除及分享链接。
独立 `grpc_tls` 字段复用 Nginx HTTP/2、受管 TLS 和 UUID 统计额度；后端端口按核心避让，
TLS 端口与 WS/HTTPUpgrade 共享全局池；不支持 sing-box、宿主集成或 fallback。
4A.7 扩展两类 gRPC TLS 入口复用自身同域 Nginx TLS 发布 HTTPS 订阅，无须包含协议 `21`，隔离 amd64 主/组与同名 `subscriptions` 服务实链路已验；完整管理继续未开放。
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
真实 Nginx PROXY HTTP/2 与隔离 amd64 Xray ALPN 协商已验，公网及原生双架构仍待验；
5A.3a/5A.3b 已提供 standalone/webroot HTTP-01 的本地事务底座；公网 CA、
真实宿主生命周期及原生双架构仍待验，组合管理状态保持 `deferred`。
4A.9 允许独立 27/29 复用自身 fallback 发布 HTTPS 订阅，HTTP/1.1 与 HTTP/2 后端共用 token 路由；宿主集成、sing-box fallback 与完整管理仍拒绝。
本阶段真实客户端、HTTP/1.1/HTTP/2 回落和恢复验收已通过；Docker Linux 定向回归约 `109.543` 秒，
真实 amd64 27/29 及旧 22/24/25 顺序验收约 `277` 秒，静态 ShellCheck、Schema `4` 正例/`50` 反例
和 phase3 矩阵检查通过。公网宿主入口、原生 arm64、真实 DNS/整机重启及可信发布仍未验。
Nginx 与核心端 TLS 轮换底座及当前矩阵所列基础协议已交付；完整管理尚未交付，
协议的 `management_status` 继续为 `deferred`。
Fail2ban 关联 WS 的增删与通用端口编辑暂冻结；5C.6d 仅提供单直接 WS 21、
单集成和单保护端口的专项联动，实际迁移验收见实施计划。真实签名发布、业务镜像及
双架构客户端连通仍待验，不能由工具容器回归推断完成。

4A.7/4A.9 将 HTTPS 订阅发布限定扩展到至少一个现有 Nginx TLS `21–25` 或 Xray fallback `27/29` 入口，
复用同域受管 TLS、Nginx 和 subscription 服务；未包含 `21` 的启用规格要求
`x-padm-subscription-nginx-tls`；含 `27/29` 的发布另需 `x-padm-subscription-fallback-tls`，关闭发布的旧子集保持兼容。
分享组 URL 使用 `core.protocols` 中首个适用入口的实际公开端口，省略 `443`；
Reality 共存选中的 website 入口使用公开 `443`。首配 `12–17` 接入发布提问，
仅删除最后一个适用入口时关闭发布。22–25 的主/组 HTTPS、严格 TLS 及双族 TCP/UDP
已通过隔离 amd64 验收；变量代理补齐 Docker DNS 解析，同名 gRPC 服务不遮蔽 token。
不增加独立发布域名、证书或服务，
其它核心端 TLS 协议仍不能单独发布，完整管理继续按原边界。
4A.8 增加 `subscription content/links --base` 和菜单 `11 → 10/11`：
本地主订阅复用节点生成器，不依赖分享组或启用发布；HTTPS 链接沿用实际公开端口及发布门禁。
5A.1d–5A.1e 将受管模板扩展到已有 sing-box `23`，并复用原生 renderer 接入可选站名；
仅渲染公开内容，不新增规格字段或放宽模板资源校验。

机器可读状态位于 [`docker/contracts/features.json`](../docker/contracts/features.json)：

- `protocols[]` 记录公开协议 ID、配置运行状态、管理状态、核心、profile、`transport`、`udp_support` 和原因。
- `features` 保留旧的兼容状态子集；同名值必须与 `feature_matrix` 一致。
- `feature_matrix` 记录完整功能状态、原生菜单入口、Docker profile、宿主权限、前置条件和原因。

## 主菜单对照

| 原生菜单 | Docker 当前状态 | 已覆盖 | 尚未覆盖或边界 |
| --- | --- | --- | --- |
| 安装与重装 | 部分已交付，完整管理 `deferred` | `install`、可信发布输入 `release`、交互首配 `setup`、`reinstall`、`edit`、`configure`、候选校验及恢复 | 支持 `1`、`2`、`3`、`4`、`5`、`21`、`22`、`23`、`24`、`25`、`26`、`27`、`28`、`29`、`30`、`31` 字段编辑、完整原始 spec 接入、多入口及主副核心；3D.11–3D.13 提供旧规格迁移后的增量新增、核心选择、新 SS 密钥、首个 TLS 证书联动以及 v3 删除/保身份重建。3D.14 提供重新选择和完整规格重装，并撤销旧分享授权、保留累计及失败恢复；3D.15 提供保身份 TLS 域名迁移，3D.16 可在 ACME 成功后显式登记新域名续期，旧登记不迁移。真实发布连通未完成。 |
| 订阅与用户 | `supported` + `host-integrated` + `deferred` | 有条件的订阅发布、流量采集/额度、v3 独立账号与双核心认证/统计、账号/分享组及业务备份恢复、主控管理与被控接入/手动同步、已有单 Peer 被控自动同步 CLI/菜单、WireGuard 宿主集成 | 4A.7 的 HTTPS 发布复用至少一个 `21–25` 入口与同域受管 TLS，隔离 amd64 主/组实链路已验；独立域名/证书发布、H3 和完整多服务器工作流未迁移。隔离 amd64 双部署事务及真实 cron 自主同步已验，WireGuard 需 `net-wireguard`；原生双机、arm64 和重启另验。 |
| 协议与入口 | 部分 `supported`，管理工作流 `deferred` | `1` Reality Vision、`2` XHTTP、`3` Hysteria2、`4` AnyTLS、`5` NaiveProxy、`21` VLESS WS TLS、`22` VMess WS TLS、`23` VMess HTTPUpgrade TLS、`24` VLESS gRPC TLS、`25` Trojan gRPC TLS、`26` Reality gRPC、`27` TLS Vision fallback、`28` direct Trojan、`29` Trojan TLS fallback、`30` Shadowsocks、`31` TUIC 的配置运行、字段编辑、分享链接、多入口、Reality 传输派生、参数重生成和目标站管理；有限 Reality 443 共存及 2/21/22/23/24/25 CDN 连接地址覆盖 | XHTTP、VMess WS、gRPC TLS 和传统 TLS fallback 仅限 Xray，Hysteria2/AnyTLS/NaiveProxy/Shadowsocks/TUIC 仅限 sing-box；HTTPUpgrade 支持两核心；完整协议管理、完整 UDP 端口跳跃、其余 CDN 和完整内部路由工作流尚未开放；Fail2ban WS 增删及通用端口编辑拒绝，单入口保护端口专项见 5C.6d。 |
| 站点与证书 | 部分 `supported`，其余 `deferred` | TLS 文件安装、保身份域名迁移、DNS-01 与 HTTP-01 standalone/受管 webroot 本地事务、Nginx WebSocket/HTTPUpgrade/gRPC HTTP/2 入口及传统 TLS fallback；默认页、静态目录、302、受管三主题、Hysteria2 local 与逐入口 ALPN 事务管理 | 域名迁移不迁移续期登记；隔离 amd64 TLS ALPN 和 H3 已有实测；公网 CA、宿主生命周期及原生双架构验收待补。 |
| 路由与访问控制 | `host-integrated` + `deferred` | WireGuard、TUN/TProxy 宿主集成合同；5B.1–5B.4i 两核心 SOCKS5 TCP 出站、DNS/hosts、域名 Direct/Block、目的 IP、明文 BT、CN 预设、IPv6 与用户态 WARP 子能力；已有 DNS/选择性 SOCKS5/IPv6/WARP 名单增删、七类域名及手工字面 IP/CIDR 单条原位替换、已有 hosts 单键地址替换；5B.5a 已有 Xray 的 HTTP 中继事务 | SOCKS5 名单定向、菜单及完整 49 项回归已通过；hosts 单键替换定向与菜单已通过，集中完整 49 项回归通过；SOCKS UDP 发布、完整区域/访问控制仍未交付；WARP 公网出口、IPv6/HTTP 公网发布、真实宿主及双架构验收待补，完整状态不升级。 |
| 核心与服务 | `supported` + `deferred` | 基础状态、启动、停止、重启、日志、更新、回滚、配置校验、可信候选核心试跑与升级风险扫描、Xray Geo 状态/更新/每日任务 | 评估要求受管 spec；预发布须有匹配的可信发布资产，不现场构建；Geo 的本地合同及真实 amd64 解析/权限已验收，真实上游、生产重建、宿主调度和双架构生命周期另验；当前不是原生全部生命周期管理。 |
| 系统与脚本 | `supported` + `host-integrated` + `unsupported` | `padm-docker update`、Fail2ban 宿主集成 | BBR/网络优化不由 Docker 修改宿主内核；Fail2ban 需 `net-fail2ban`。 |
| 高级/危险操作 | `supported` + `deferred` | 受管卸载、移除镜像、显式 purge；有限 VLESS Encryption 实验开关 | 实验限 schema 3 Xray Reality Vision/XHTTP；固定客户端组合之外与完整验收仍待补。 |

维护菜单 `18 → 8/9` 的灾备预览/应用支持默认发布或自备匹配的 manifest、
Sigstore bundle、control-bundle；逐字段取消或 EOF 不执行恢复，应用保留原确认。
这只补齐菜单与现有 CLI 的资产输入，恢复范围仍以 6A 专项限制为准。

## 公网协议

协议 ID 与原生 [`shell/core/protocols.sh`](../shell/core/protocols.sh) 的
`category=node` 注册表保持一致。Docker 当前只接受配置运行状态为 `supported`
且核心匹配的协议；管理状态独立记录，不能由运行状态推断。

| ID | 能力 | 原生入口 | 配置运行状态 | 管理状态 | 核心 | Compose profile | 网络/监听 | 原因 |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | VLESS Reality Vision | 安装与重装；协议与入口 -> REALITY 管理 | `supported` | `deferred` | Xray / sing-box | `core-xray` / `core-sing-box` | bridge / TCP | 支持单核心或主副核心配置、字段编辑及跨核心同协议多入口；完整管理未迁移。 |
| 2 | VLESS Reality XHTTP | 协议与入口 -> XHTTP 管理 | `supported` | `deferred` | Xray | `core-xray` | bridge / TCP | v3 支持首配、导入、路径/Host/模式编辑、复制及分享链接；3D.4 四预设、XMUX 三键自定义/清除，3D.5 Padding `1..4096`，3D.6 两项首部开关已交付。3D.7 四项原生 packet/stream limits 的状态、事务、清除与复制/派生继承；前三项 `0..2147483647` 整数，末项为整数或正序范围；`0`/`0-0` 保留显式值、状态折算核心默认，要求 `x-padm-xhttp-limits`。3D.10 提供模式、成对路径/Host、七项高级参数及推荐恢复。3D.20 支持客户端请求首部设置/清除、状态和统一链接，1–8 项、名称 1–64 位、值 0–256 位可打印 ASCII，拒绝大小写重复及核心保留字段，要求 `x-padm-xhttp-request-headers`；不提供服务端响应或访问认证。3D.21 支持同入口已登记非默认分享额外端口的下行绑定及清除，要求 `x-padm-xhttp-download`；链接沿用来源 Reality 身份/路径/Host，固定下行模式 `auto`，复制/派生的新入口清除绑定。3D.22 支持独立外部下行地址与 TLS h2/h3 或 Reality 身份元数据，要求 `x-padm-xhttp-download-settings`；与原端口绑定互斥、共用清除，URI 不继承上行高级参数，其它编辑保留，复制/派生仅清除新入口绑定。4A.5c 支持逐入口多连接 CDN 地址设置/清除、状态和统一链接输出，要求 `x-padm-cdn-xhttp`；只替换分享上行地址，保留原入口端口与 XHTTP `downloadSettings.address`，不自动建设 TLS/H3/CDN 拓扑。外部前置须已部署并回到同一 XHTTP handler/认证，不支持无会话关联的独立后端；公网前置、宿主/arm64、完整管理及性能收益继续 deferred。 |
| 3 | Hysteria2 | 协议与入口 -> Hysteria2 管理 | `supported` | `deferred` | sing-box | `core-sing-box` | bridge / UDP | v3 支持首配、导入、BBR/Brutal、Salamander/Gecko、HTTPS 伪装编辑、复制及分享链接；3D.8–3D.9 菜单 12 提供状态、带宽、混淆与伪装单入口专项，BBR 保留速率，密码仅私密文件或静默输入。Gecko 要求新能力标记，不开放包长参数。已有入口可两步发布受管静态网页并启用 local，固定只读目录且无混淆，操作先验证已发布网页。复用受管 TLS 和 UUID 流量账号；端口跳跃限单 sing-box、双族 Hy2 的内部监督手动管理，5C.9f–5C.9g 补固定 Mihomo 的 Brutal + Salamander/Gecko 原范围 URI 导入验收，完整跳跃与协议管理仍 deferred。 |
| 4 | AnyTLS | 安装与重装 -> 自定义安装 | `supported` | `deferred` | sing-box | `core-sing-box` | bridge / TCP | v3 支持首配、导入、通用字段编辑、同核复制/删除及分享链接；复用受管 TLS 与 UUID 流量账号，域名与凭据冻结，宿主集成组合及完整管理未开放。 |
| 5 | NaiveProxy | 安装与重装 -> TLS 指纹抗性 | `supported` | `deferred` | sing-box | `core-sing-box` | bridge / TCP | v3 支持首配、导入、通用编辑、同核复制/删除及原生 URI；入口与 TLS 同域，UUID 用户名/密码共享统计额度；QUIC、独立 IP/SNI 覆盖及完整管理未开放。 |
| 21 | VLESS WS TLS | 安装与重装 -> 自定义安装 / 传统 TLS 兼容安装 | `supported` | `deferred` | Xray | `core-xray` / `nginx` | bridge / TCP + Nginx | 已有多入口 Xray 后端、Nginx 反代和同域 TLS；5C.6d 单直接 WS 21/单集成/单保护端口的专项迁移接入菜单和事务，新旧端口均要求 fresh 来源；关联入口增删、通用端口编辑及完整管理仍拒绝。 |
| 22 | VMess WS TLS | 安装与重装 -> 自定义安装 | `supported` | `deferred` | Xray | `core-xray` / `nginx` | bridge / TCP + Nginx | v3 支持首配、导入、入口与 WS 路径编辑、同核复制/删除及 `vmess://` 分享；固定 `alterId=0`，4A.7 自身同域 Nginx TLS 发布已通过隔离 amd64 实测，宿主集成及完整管理未开放。 |
| 23 | VMess HTTPUpgrade TLS | 安装与重装 -> 自定义安装 | `supported` | `deferred` | Xray / sing-box | `core-xray` / `core-sing-box` / `nginx` | bridge / TCP + Nginx | v3 两核心首配、导入、入口/路径编辑、跨核心复制/删除及分享；固定 `alterId=0`，UUID 共享额度，4A.7 含纯 sing-box 的自身同域 Nginx TLS 发布已通过隔离 amd64 实测，宿主集成及完整管理未开放。 |
| 24 | VLESS gRPC TLS | 安装与重装 -> 自定义安装 | `supported` | `deferred` | Xray | `core-xray` / `nginx` | bridge / TCP + Nginx | v3 首配、导入、入口/服务名编辑、同核复制/删除及 `vless://` 分享；Nginx HTTP/2 反代，UUID 共享额度，4A.7 自身同域 Nginx TLS 发布已通过隔离 amd64 实测，宿主集成、fallback 及完整管理未开放。 |
| 25 | Trojan gRPC TLS | 安装与重装 -> 自定义安装 | `supported` | `deferred` | Xray | `core-xray` / `nginx` | bridge / TCP + Nginx | v3 首配、导入、入口/服务名编辑、同核复制/删除及 `trojan://` 分享；Nginx HTTP/2 反代，UUID 共享额度，4A.7 自身同域 Nginx TLS 发布已通过隔离 amd64 实测，宿主集成、fallback 及完整管理未开放。 |
| 26 | VLESS Reality gRPC | 安装与重装 -> 自定义安装 | `supported` | `deferred` | Xray / sing-box | `core-xray` / `core-sing-box` | bridge / TCP | v3 支持首配、导入、service name 编辑、跨核心复制及分享链接；完整管理未迁移。 |
| 27 | VLESS TCP TLS Vision | 安装与重装 -> 自定义安装 / 传统 TLS 兼容安装 | `supported` | `deferred` | Xray | `core-xray` / `nginx` | bridge / TCP + fallback | v3 首配、导入、通用编辑、同核复制/删除及 URI；Xray TLS/Vision 与 PROXY v1 HTTP/1.1、HTTP/2 回落，UUID 共享额度；默认页/静态/302 与逐入口 ALPN 可事务管理，宿主集成与完整管理未开放。 |
| 28 | Trojan TCP TLS direct | 安装与重装 -> 自定义安装 | `supported` | `deferred` | Xray / sing-box | `core-xray` / `core-sing-box` | bridge / TCP | v3 两核首配、导入、通用编辑、跨核心复制/删除及 URI；受管 TLS、UUID 密码共享流量额度，fallback、宿主集成及完整管理未开放。 |
| 29 | Trojan TCP TLS fallback | 安装与重装 -> 自定义安装 / 传统 TLS 兼容安装 | `supported` | `deferred` | Xray | `core-xray` / `nginx` | bridge / TCP + fallback | v3 首配、导入、通用编辑、同核复制/删除及 URI；Trojan 直接终止 TLS，无额外 VLESS 前端，PROXY v1 HTTP/1.1、HTTP/2 回落，UUID 共享额度；默认页/静态/302 与逐入口 ALPN 可事务管理，宿主集成与完整管理未开放。 |
| 30 | Shadowsocks | 安装与重装 -> 自定义安装 | `supported` | `deferred` | sing-box | `core-sing-box` | bridge / TCP + UDP | v3 SS2022 AES-128 多用户首配、导入、通用编辑、同核复制/删除及 SIP002 链接；3D.12 增量新增首次生成私密双密钥，同 UUID 已有 SS 保留原密钥。3D.24 仅轮换选中入口的自用用户密钥，服务器密钥、其它入口及独立账号不变，专项/amd64 实链路/完整合同通过。无需 TLS，UUID 共享统计额度，宿主集成及完整管理未开放。 |
| 31 | TUIC | 协议与入口 -> Tuic 管理 | `supported` | `deferred` | sing-box | `core-sing-box` | bridge / UDP | v3 首配、导入、入口/拥塞/认证超时/心跳/0-RTT 编辑、同核复制/删除及 URI；3D.8 菜单 13 提供状态、各参数专项和推荐值恢复，开启 0-RTT 确认重放风险；受管 TLS、UUID 共享额度。5C.9d 提供单核心、单个双族入口的监督范围 DNAT 和活动单端口分享，要求新 bundle marker；5C.9f 补固定 Mihomo 的首尾普通 URI 导入验收，固定客户端自动换端口与完整管理仍 deferred。 |

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
| 206 | DNS/Direct/Block | 路由与访问控制 -> DNS/hosts | `deferred` | 两核心 DNS/hosts、Direct/Block、手工 IP/CIDR、BT、CN 区域预设、IPv6 与 WARP 已交付；名单增删/单条替换保留上游、私有字段和顺序，缺旧/重复新/同值拒绝，删空关闭对应策略。hosts 支持单键增删/替换、私有 JSON 整组替换，以及 5B.4w 单 IP/精确 FQDN CSV 交互整组录入，冻结其它完整规格与累计。sing-box 显式解析后 IP 阻断及 WARP/IPv6 组合受独立能力门禁保护；Xray、完整区域/语义冲突检测和原生迁移仍待交付或验收。 |
| 207 | Tunnel/dokodemo-door | 路由与访问控制 -> 访问控制 | `deferred` | 5B.5c–5B.5e 提供已有受管入口的额外 Compose 发布端口、逐入口默认分享选择及别名原位改端口，复用认证/统计及 TLS/SNI 前端；宿主集成和公网/双架构验收未交付，不做任意目的转发。 |

## 功能和宿主边界

TUN/TProxy/Redirect 的透明核心保留 `cap_drop: ALL`，仅授予 `NET_ADMIN`、
`NET_BIND_SERVICE`、`DAC_OVERRIDE`；网络检查 helper 仍仅 `NET_ADMIN`，
普通核心不增权。低端口能力用于宿主监听和透明 UDP 原目的端口回包，
不放宽私密材料权限。旧透明控制包须先停用透明集成，再更新并重新启用；
新控制器在停服前拒绝缺少三能力合同的包，历史备份可读不代表可直接恢复运行。
权限修复已通过实流量矩阵，升级保护已通过同源码 TUN 与 Phase 6 定向补验，
支持状态保持原值。

| 功能键 | 原生入口 | Docker 状态 | Profile | 网络/权限边界 | 当前说明 |
| --- | --- | --- | --- | --- | --- |
| `nginx` | 站点与证书 -> 传统 TLS fallback | `supported` | `nginx` | bridge | 独立 Nginx 容器，承载 WS/HTTPUpgrade/gRPC 反代与传统 TLS fallback 的 PROXY v1 HTTP/1.1、HTTP/2 后端；默认页、静态目录、302 与传统 TLS ALPN 经菜单/CLI 事务管理。 |
| `tls-files` | 站点与证书 -> 本机 TLS 证书 | `supported` | `nginx` / `acme` | bridge | 菜单/CLI 校验、导入轮换和只读挂载；Nginx 与 Xray/sing-box 逐消费者校验、重载/重建及健康失败恢复旧证书。核心端仅交付受管 TLS 文件底座，不代表新增协议或完整管理。 |
| `acme-dns` | 站点与证书 -> 本机 TLS 证书 | `supported` | `acme` | bridge + 宿主 CLI 调度 | 菜单/CLI DNS-01 issue/renew 及自动续期启停/状态；root 私有输入、唯一 systemd/cron 任务、部署锁和候选账户/证书事务；未到期跳过，更新/回滚保留最新输入，卸载只撤销受管任务。 |
| `subscription` | 订阅与用户 -> 订阅发布 | `supported` | `nginx` / `subscription` | bridge | 4A.7/4A.9 复用至少一个 `21–25/27/29` 入口及同域受管 TLS，含纯 sing-box `23`；无 `21` 需 `x-padm-subscription-nginx-tls`，含 fallback 发布另需 `x-padm-subscription-fallback-tls`。HTTP/1.1 与 HTTP/2 后端共用 token 路由。部署/分享组 token 沿用，分享 URL 按首个适用入口的实际公开端口；独立域名/证书发布与 H3 未迁移，27/29 新范围验收见 4A.9。 |
| `subscription-traffic` | 账号管理 -> 流量与额度 | `supported` | 核心 profile | 宿主 CLI | 定时采集以及 show/collect/limit/reset；菜单 `10 -> 9` 查看不隐式采集，额度 `0` 表示不限额，设置/重置各确认一次，重置保留额度。沿用 CLI 采样与失败副作用；自用按原 UUID、独立账号按稳定 ID 共享跨核心累计与额度，凭据轮换和恢复不回退累计。 |
| `subscription-users` | 订阅与用户 -> 用户和分享订阅 | `supported` | 核心、订阅 | bridge | 4A.1–4A.4 账号底座、账号 CLI/菜单事务、独立 token 分享组及业务备份恢复已交付；账号/入口筛选、启停/轮换、纯内容与 HTTPS 链接，账号/组/额度/累计 merge/replace 恢复均复用候选事务，轮换与恢复不回退最新累计。4A.2a 凭据不进外部 argv，修复首次 SS 关联生成与迁移入口选择；已有账号须显式设置新增入口授权。CDN/H3 与完整多服务器工作流按独立功能边界验收。 |
| `subscription-multiserver` | 订阅与用户 -> 主控/被控、多服务器同步 | `deferred` | 订阅、WireGuard | host | 4C.1–4C.6 提供私网 API、主控管理、被控接入、手动/每 5 分钟自动同步及 API 端口重连；4C.7–4C.11 提供单 Peer 建链、同隧道主控 rebind 及连接/关联地址迁移。4C.12–4C.14 提供无角色多 Peer 管理/本机迁移及 v2 多被控逐节点邀请、授权、撤销和故障隔离。保留业务累计和普通版本门禁，token 仅写外部 root 私有邀请，API/客户端零能力且无公网映射。隔离 amd64 双/三节点真实业务、授权与来源隔离、自动同步及失败恢复证据见各阶段；6A.19/6A.23 接续隔离旧主控后的 v1/v2 新身份空目标恢复，全部撤权并逐端新邀请/rebind。v2 关联迁移和控制面 Fail2ban 明确拒绝；完整灾备、原生 systemd/双机/arm64、重启和可信发布待验。 |
| `acme-webroot` | 站点与证书 -> 传统 TLS fallback | `deferred` | `acme` / `nginx` | bridge | 5A.3b 已提供显式 opt-in 双栈 `80:8088`、独立 HTTP vhost、只读稳定根与 ops 独占 `active/`，菜单/CLI 和 schema 3 自动续期；归属及目录校验、不停 Nginx、失败/信号恢复和关闭/回滚保护。公网 CA、真实宿主生命周期及原生双架构未验，完整状态不升级。 |
| `acme-standalone` | 站点与证书 -> 本机 TLS 证书 | `deferred` | `acme` | 宿主预检 + bridge | 5A.3a/5A.3c 已提供 HTTP-01 standalone 与 TLS-ALPN-01 首配、重新选择、首个 TLS、迁移、菜单/CLI 和自动续期；非 root ops 临时双栈 `80:8080` 或 `443:8443`，实际归属校验，只暂停本部署原运行拥有者并恢复；未到期不暂停。ALPN 使用无凭据 schema `4`，Fail2ban Nginx 拒绝自监听停启。公网 CA、原生 Linux/双架构及宿主生命周期待验，完整状态不升级。 |
| `site-static-redirect-alpn` | 站点与证书 -> fallback 站点、302、ALPN | `deferred` | `nginx` / `core-sing-box` | bridge | 5A.1 站点、5A.1b–5A.1e 受管 notes/photos/docs 模板及可选站名、5A.1c Hysteria2 local 与 5A.2 逐入口 ALPN 事务已提供；模板限已有 v3 Nginx TLS 21–25（含 sing-box 23）、Xray 27/29 或 Hy2，资源清单随 bundle 校验，生成后仍普通 static，站名只写入转义后的网页。local 固定只读目录且无混淆，纯 Hy2 只开放静态模式。隔离 amd64 27/29 的真实 TLS ALPN、fallback 与认证、sing-box 23 的模板资源及主/组订阅双栈共存已验；公网及原生双架构仍待验。 |
| `reality-target-management` | 协议与入口 -> REALITY 管理 -> 目标站管理 | `supported` | 核心 profile | 宿主 CLI | 对齐原生 8 项管理及首配候选检测/手动输入；检测 TLS/PQC/ASN/证书链、刷新库、网段/同 ASN 抽样扫描、A 级筛选分页与逐入口切换、host[:port]/独立 SNI、黑名单；扫描进度和部分结果处理共用原生，B/C 手动告警，全部地址按最差评分及 CDN 风险判定，缓存切换重新复测，Docker 私密状态与事务恢复独立于原生。 |
| `reality-parameter-management` | 协议与入口 -> REALITY 管理 -> 重新生成参数 | `supported` | 核心 profile | 宿主 CLI | 菜单/CLI 按入口重生成密钥对和 short ID，派生校验、候选确认和失败恢复；账号、目标、其它入口及额度保持，链接和已启用发布同步更新。 |
| `reality-coexistence` | 协议与入口 -> REALITY 管理 -> 443 共存分流 | `deferred` | `core-xray` / `nginx` / `nginx-stream` | 宿主 CLI | 已提供受管 TLS 入口、桥接可达宿主网站或独立 host 网络分流入口与一个 Xray Vision/XHTTP 后端的 443 共存；菜单/CLI 状态、开启、更换、关闭及端口恢复复用候选事务。宿主网站的多个 SNI、host-gateway、可路由 IP 或回环支持有明确边界；原生宿主、适用公网及完整管理仍待验收。 |
| `entry-port-management` | 协议与入口 -> 入口端口管理 | `deferred` | 核心 | bridge | v2/v3 多入口复制/删除及端口事务，v3 明确核心归属；5B.5c–5B.5e 额外端口增删/原位修改/状态/默认分享的菜单/CLI 与候选恢复，已有本地真实发布证据；修改保留别名顺序及默认分享标记，复用原认证、统计及 TLS/SNI 前端。受管或桥接可达宿主网站的 Reality 443 共存可使用别名；拒绝 WS/SSH Fail2ban、TUN/TProxy 和 host-network，允许已有 WireGuard/控制面 Fail2ban。既有身份/内部端口冻结，端口跳跃及适用公网/IPv6/原生宿主/arm64、完整管理仍待交付或验收。 |
| `cdn-entry-management` | 协议与入口 -> CDN 入口管理 | `deferred` | `subscription` | bridge | 4A.5–4A.5c 提供协议 2/21/22/23/24/25 的逐入口多连接地址覆盖，菜单/CLI 状态、设置和清除，统一生成本地链接、主订阅及分享组；协议 2 只替换分享上行地址并要求 `x-padm-cdn-xhttp`，XHTTP `downloadSettings.address` 保留原入口地址；其余协议保留端口、SNI、Host/路径或 gRPC serviceName/h2 与认证，候选确认及失败恢复复用现有事务。24/25 仅已有 Xray/Nginx TLS，带映射另要求 `x-padm-cdn-grpc-tls`，旧三协议/无映射 gRPC 子集保持。其它协议、H3、公网供应商透传、真实宿主/arm64 和可信发布仍待验。 |
| `fail2ban` | 系统与脚本 -> Fail2ban 防护 | `host-integrated` | `net-fail2ban` / `net-fail2ban-control` / `net-fail2ban-ssh` | host + `NET_ADMIN` | WS DOCKER-USER、控制面 INPUT 与专用 SSH INPUT 的独立 owner 和菜单/CLI；SSH/control 不共存。5C.6d 单 WS 保护端口专项已验实际双栈封禁、端口迁移、SQLite 保留、来源/健康失败恢复与旧规则清理，新旧端口均需 fresh 来源，别名、Reality stream 和其它集成拒绝；WS 日志组为 `0:10001`，权限不放宽。控制认证日志支持菜单/CLI 每小时轮转检查，默认关闭、本机私有登记、同锁与旧 bundle 门禁；线上 auto 入口及隔离 amd64 原始每小时 :19 cron 自主触发、实际归档/续写/停用已验，systemd 实际定时触发待验。SSH 限原生 root systemd/cgroup v2、无存量会话且禁止 reload 的单 service/单显式监听，只消费启动后的可信密码失败。transient collector、只读日志/10 秒 guard、启停/状态/单 IP 解封已接，来源失效自动停 jail/精确清理，禁自动重启和恢复旧封禁；SSH 启用时 update/rollback/业务恢复拒绝，先受管停用。隔离 amd64 OpenSSH 10/Fail2ban 1.1 实际启停、封禁、连接 DROP、解封和来源失效清理已验；原生宿主/arm64/公网/重启卸载及完整管理仍待验收。 |
| `wireguard` | 订阅与用户 / 路由与访问控制 | `host-integrated` | `net-wireguard` | host + `NET_ADMIN` | 接口由宿主内核拥有。4C.7 接入控制连接菜单 `18` 及 `wireguard status/prepare/peer/start/stop`，仅支持 RFC1918 IPv4 `/32` 单 Peer，已通过定向及隔离 amd64 真实 CLI 验收。私密准备、首次部署事务、精确容器启停及限制见下文，完整管理状态不升级。 |
| `tun` | 路由与访问控制 -> TUN | `host-integrated` | `net-transparent` | host + `NET_ADMIN` + `NET_BIND_SERVICE` + `DAC_OVERRIDE` + `/dev/net/tun` | 显式启用透明代理设备。 |
| `tproxy` | 路由与访问控制 -> Redirect/TProxy | `host-integrated` | `net-transparent` | host + `NET_ADMIN` | 菜单 17→43 和 CLI 管理单 Xray/sing-box Reality，IPv4/IPv6/双栈 PREROUTING TCP/UDP。OUTPUT 默认关闭，可选 UID 或包含 root 的全主机主动 TCP/UDP；互斥、省略保留，关闭保留 PREROUTING。全主机核心 0:10001，GID 10001、LOCAL/REPLY 绕过；实际核心身份与两族两链均须核验。漂移或缺关键绕过保留现场；旧 schema 2/3/4 兼容，全主机 schema 5 和共享 marker。拒绝其它宿主集成；原生宿主/arm64/公网/重启/完整卸载及完整管理待验。 |
| `redirect` | 路由与访问控制 -> Redirect/TProxy | `host-integrated` | `net-transparent` | host + `NET_ADMIN` | 菜单 17→47 和 CLI 管理单 Xray/sing-box Reality 1/2/26，同核心多入口；三族 PREROUTING，OUTPUT 可选 UID 或全主机主动 TCP，UDP 保持原路由。默认关闭、互斥、省略保留；全主机包含 root，核心 0:10001，GID 10001、LOCAL/REPLY 绕过，实际身份须核验。schema 1 兼容，全主机 schema 2 和共享 marker。两族两链先完整审计再精确撤销，漂移保留现场；拒绝其它宿主集成或副核心。原生宿主/arm64/公网/重启/完整卸载及完整管理待验。 |
| `routing-tools` | 路由与访问控制 -> WARP/IPv6/Socks5/DNS/BT/访问控制 | `deferred` | 核心 | bridge | 已交付两核心 SOCKS5 TCP、DNS/hosts、Direct/Block、IP/CIDR、BT、CN 预设、IPv6 和用户态 WARP，以及名单、上游、模式和地址族管理。SOCKS5、已有 WARP Peer 和 hosts 支持交互直接录入，私有 JSON CLI 保留；hosts 单键增删/替换与单 IP/精确 FQDN CSV 整组录入共用完整校验和失败恢复。只读重叠/覆盖诊断不预测最终流量；SOCKS UDP 撤销、Xray 解析后阻断、完整区域/访问控制及公网/宿主/双架构验收待补。 |
| `internal-201-socks-relay` | 路由与访问控制 -> Socks 中继 | `deferred` | 核心 | bridge | 5B.1–5B.2 TCP 出站子能力已交付；5B.5b–5B.5b.1 确认 sing-box 动态 BND 发布阻塞且未认证来源可借用活动 UDP 关联，Xray 26.3.27 的 UDP 来源许可在当前进程内不随控制关闭撤销。host-network 不能解决核心鉴权问题，完整入站不交付、不降为 TCP-only；不作为公网节点。 |
| `internal-202-http-relay` | 路由与访问控制 -> HTTP 中继 | `deferred` | `core-xray` | bridge | 5B.5a 独立 `relay.http` 合同、私有认证与来源前置规则、菜单/CLI/关闭/回滚；5B.5a.1 提供已有中继端口及来源名单替换/追加/精确删除，冻结认证与其余规格、删空拒绝；专属直连且不计业务额度。双栈发布与真实来源已在隔离 amd64 Linux daemon 验证，IPv6 relay 只接受管 bridge，拒绝旧包/旧 plain bridge 恢复；拒绝 sing-box 的代理头来源覆盖，公网、宿主、arm64 和可信发布待验。详见 `docker-http-relay.md`。 |
| `internal-203-wireguard` | 订阅与用户 / 路由 -> WireGuard | `host-integrated` | `net-wireguard` | host + `NET_ADMIN` | 接口由宿主内核拥有；4C.3a 核验真实归属后预检/健康/撤销，活动旧式标记需先正常停止旧容器。4C.7 增加受限单 Peer 准备与启停入口，已通过定向及隔离 amd64 真实 CLI 验收，不新增运行机制。 |
| `internal-204-tun` | 路由与访问控制 -> TUN | `host-integrated` | `net-transparent` | host + `NET_ADMIN` + `/dev/net/tun` | 5C.2c 菜单 17→44 与 CLI 启用/关闭/状态；限单 sing-box、单 Reality、IPv4、无其它宿主集成。全局 IPv4 TCP/UDP，IPv6 拒绝；CID/StartedAt/netns/接口/规则/路由完整绑定，候选只读检查，正常停止且基线清净才清 state。隔离 amd64 生产启停/重启/漂移拒绝/异常退出保留现场已验；原生宿主/arm64/公网/重启/完整卸载及完整管理仍待验。 |
| `internal-205-redirect-tproxy` | 路由与访问控制 -> Redirect/TProxy | `host-integrated` | `net-transparent` | host + `NET_ADMIN` | TProxy TCP/UDP 和 Redirect TCP 的有限管理范围同上，两者互斥；完整 Redirect/TProxy 管理及宿主验收仍 deferred。 |
| `internal-206-routing-rules` | 路由与访问控制 -> DNS/Direct/Block | `deferred` | 核心 | bridge | 两核心 DNS/hosts、Direct/Block、IP/CIDR、BT、CN 预设、IPv6/WARP 和专项事务已交付；名单增删/原位替换、上游和区域自定义例外管理冻结未选字段。hosts 单键增删/替换及交互单 IP/精确 FQDN CSV 整组替换共存，原 JSON CLI 保留。手工 IP 保留原文和顺序，不改区域合成项；sing-box 可显式解析后阻断并组合 WARP/IPv6，Xray 继续拒绝。只读重叠/覆盖不推断 GeoSite 或最终流量；完整区域、语义冲突检测、原生迁移及公网/宿主/双架构验收待补。 |
| `internal-207-access-control` | 协议与入口 -> 额外入口端口 | `deferred` | 原业务核心/Nginx | bridge | 5B.5c–5B.5e 独立 `port_aliases`、菜单/CLI 增删/原位修改/状态/默认分享与候选回滚；双栈 TCP/UDP 发布已在隔离 amd64 Linux daemon 验证，同入口认证/统计，TLS/SNI 前端不旁路，URI/主订阅/分享组逐入口选择已有别名，修改保留默认标记，恢复或删除后回退 base，不增加节点。拒绝 WS/SSH Fail2ban、TUN/TProxy 和 host-network，允许已有 WireGuard/控制面 Fail2ban；适用公网/原生宿主/arm64 与完整管理验收待补。 |
| `interactive-menu` | 全部主菜单 | `deferred` | 无 | 宿主 CLI | 已有可信首配、规格/协议/Reality/TLS、账号/分享/额度、备份、核心/Geo、多被控逐节点管理、站点/路由及适用 Fail2ban 菜单。6A.1–6A.23 提供私密导出、只读验证和同架构 v3 空目标恢复；逐项支持范围、权限与失败恢复见下文。ACME 限单域 EC-P256 standalone、固定受管 Webroot、ALPN 或 dns_acmedns 及匹配唯一启用登记；健康后按 traffic、Geo、renewal 安装适用调度，独立快照、统一漂移检查、逆序撤销，预览不安装调度。其它启用 DNS、未知材料、已有部署替换仍拒绝。无控制角色允许 canonical 多 Peer，被控恢复仍限单 Peer；主控接受 v1 单项或 v2 非空集合，须停机隔离旧宿主后重建全部控制身份、撤权并逐端新邀请/rebind。完整协议管理、v2 关联迁移、原生双架构生命周期及可信发布仍待交付或验收。 |
| `core-lifecycle` | 核心与服务 | `supported` | 核心 profile | 宿主 CLI | 基础 `status/up/down/restart/logs/update/rollback/validate` 已可用，不代表原生全部升级管理。 |
| `core-upgrade-assessment` | 核心与服务 -> Xray / sing-box 生命周期 | `supported` | 核心 profile | 宿主 CLI | 菜单第 13 项及 `assess` 复用只读风险扫描，使用可信候选镜像/配置副本执行版本检查、双核心配置试跑、Xray 严格模式与能力探针及已启用的 TLS/订阅/宿主前置检查；旧核心不启用严格解析时明确警告，不切换生产状态。要求受管 spec，预发布须提供匹配的可信发布资产；真实客户端连通另验。 |
| `geo-data` | 核心与服务 -> Xray Geo 数据 | `supported` | `core-xray` | 宿主 CLI | 菜单第 14 项与 `geo status/update/schedule/auto-update` 已交付；完整受管数据经双摘要及真实 Xray 解析校验后切换读取路径，重建前采集 Xray 流量，仅重建原本运行的 Xray，失败恢复数据/Compose/运行状态；每日 01:35 systemd/cron 任务有部署归属和锁。编辑、更新和回滚保留数据及调度登记，旧 bundle 在切换前拒绝；真实上游、生产重建、宿主调度、arm64 和整机重启另验。 |
| `script-update` | 系统与脚本 -> 更新 padm | `supported` | 无 | 宿主 CLI | `padm-docker update` 处理签名 bundle、镜像和配置事务。 |
| `network-optimization` | 系统与脚本 -> 网络优化 | `unsupported` | 无 | host | Docker 不修改宿主 BBR/fq。 |
| `uninstall` | 高级/危险操作 -> 卸载脚本 | `supported` | 无 | 宿主 CLI | 受管卸载、移除镜像和显式 purge。 |
| `vless-encryption` | 高级/危险操作 -> VLESS Encryption 实验 | `deferred` | `core-xray` | bridge | 5C.10 提供菜单 8→2、`edit --vless-encryption ID enable/disable` 及 `protocol encryption-status [ID]`，限 schema 3 Xray 协议 1/2；配置与 URI、私密配对校验、失败恢复及旧 bundle marker 门禁已接入。固定 Xray 26.3.27/Mihomo v1.19.28 的 Linux amd64 实验和正式 3.41.5 的 Debian 13 amd64 公网启停矩阵通过，含逐入口隔离、旧 none/错 UUID/错配拒绝和原配置恢复；bridge 双入口加密后的真实整机重启也通过，原容器自然启动、URI/材料权限/调度及累计保持。其它客户端、算法、arm64、其它拓扑加密重启与完整能力仍待验。 |

4C.7 单 Peer WireGuard 先以 `wireguard prepare` 生成本机私密身份，仅输出公钥等公开状态，
交换公钥后用 `wireguard peer` 固定唯一 RFC1918 IPv4 `/32` 对端；可选字面 IPv4 endpoint，
监听及 endpoint 端口均为 `1024–65535`。准备和设置对端仅适用尚无 WireGuard 和控制角色的部署；
私密目录/文件为 `0700/0600 root:root`，拒绝覆盖或更换已有密钥/Peer，手工配置仍走原完整规格入口。
控制连接菜单 `18` 提供状态、本机准备、设置对端、启动和临时停止。
首次 `wireguard start` 显式确认后复用配置事务增加 WireGuard 集成，可能更新并检查全部署；
已登记 `start/stop` 仅操作精确审计的 WireGuard 容器。`stop` 保留规格和容器，
`up/restart` 可重新启用；有 `control/control_sync` 依赖时拒绝单独停止。
沿用现有 owner/preflight/run/cleanup/health，拒绝归属漂移。CLI 示例及定向、隔离 amd64 真实验收证据见实施计划；
4C.8 的同隧道主控重绑定及 4C.9–4C.11 的单 Peer 连接迁移见下文；
无角色多 Peer 集合管理见 4C.12，主控新身份恢复见 6A.19/6A.23，原生双架构、重启、公网边界不变。

4C.8 新增 `control rebind --invite <私有文件> [--yes]` 及控制菜单 `19`。
须先停用被控自动同步，认证新邀请后显式替换旧主控受管账号；
保留 WireGuard 密钥/地址、入口映射、本机账号及累计，API 端口可变化。
先校验旧受管快照和全部账号映射；同 ID 认证身份及异 ID 凭据碰撞门禁保持。
仅控制身份 tuple 变化时重置版本基线，同身份重试仍校验 revision/digest。
复用原锁、私密邀请、健康和失败/INT/TERM 恢复；同版幂等。
普通 sync/reconnect 拒绝旧主控邀请，再次显式 rebind 可主动切回。
客户端/事务/控制菜单及隔离 amd64 双部署生产 CLI、真实业务检查通过，
该入口保持 WireGuard 参数不变，网络参数更新见 4C.9–4C.11；完整状态保持 `deferred`。

4C.9 增加 `wireguard migrate` 和 WireGuard 子菜单 `6`，限已登记且运行健康、
无控制角色的 4C.7 canonical 三件套。可合并更换本机地址/监听端口、Peer 地址/公钥、
endpoint 及轮换本机密钥；省略保持，endpoint `none` 清空，同配置不重建。
可信 net 镜像核旧密钥配对并生成新密钥，候选 root `0700/0600`，
原配置事务在精确停服/接口消失后整体交接私密目录，失败和 INT/TERM 恢复旧 inode。
目录/运行归属漂移保留现场，普通恢复不能跨迁移覆盖密钥。
定向及隔离 amd64 双部署生产 CLI、双方轮换、失败恢复后加密流量和幂等检查通过。
双方逐端迁移会暂时断联，单端健康不等于远端连通；未扩展多 Peer、关联控制角色和灾备范围。

4C.10 将同一迁移入口扩展至固定隧道地址的主控和已接入被控：
旧输入、新候选均须匹配角色登记的本机/Peer 地址，允许更新密钥、监听端口和 endpoint，
保留角色身份、同步版本、账号、入口及累计。主控先停控制日志调度、控制面 Fail2ban，
被控先停自动同步；拒绝残留来源挑战。成功后沿用原邀请，防护重新执行 fresh 来源核验。
失败和 INT/TERM 恢复撤销主控 Peer 授权，须重新邀请，不能沿用成功路径的授权。
定向与隔离 amd64 真实双端业务、旧邀请、来源更新和失败恢复通过。
4C.11 允许主控/已接入被控将角色地址与 canonical 隧道三件套关联迁移。
仅白名单地址变化，主控同时撤权；身份、API 端口、版本、账号和累计冻结。
失败及 INT/TERM 恢复旧地址/密钥并保持主控撤权；普通回滚拒绝跨控制地址。
双方逐端迁移后重新邀请、同步及 fresh 来源核验，依赖调度/防护门禁与 4C.10 相同。
定向与隔离 amd64 真实双端改址、加密业务、旧邀请拒绝、版本保护及失败恢复已验。
控制角色多 Peer 及原生宿主验收继续 deferred；被控空目标恢复见 6A.16，主控新身份恢复见 6A.19。

4C.12 为无控制角色的已启用 canonical 配置提供 `wireguard peers list/add/update/remove`
和菜单 `15 → 18 → 7–10`。按 RFC1918 IPv4 精确选择 `/32` Peer；更新只改选定项的
公钥/endpoint，逐字节保留本机身份与私钥，不能移除最后一项。沿用三件套及 `4096` 字节上限，
重复地址/公钥、本机引用及非规范配置拒绝。4C.14 的无角色多 Peer 本机迁移见下文；控制角色迁移仍限单 Peer，
无控制角色多 Peer 空目标恢复见 6A.22；全配置事务可能短暂影响其它连接。定向 helper `32`、CLI `106`、
事务 `144`、菜单 `90` 通过，三节点实际链路证据见实施计划；完整多服务器状态保持 `deferred`。

4C.13 增加显式 `control upgrade`、v2 `peers` 非空集合及逐节点 CLI/菜单。
旧单项格式严格兼容，升级保留身份、授权、revision/digest、账号和累计；HTTP/邀请/被控
仍使用 v1。每节点独立 ID、来源、token 和有效期，v2 邀请/撤销/来源检查强制 `--peer-id`。
先配置 canonical WireGuard `/32` 再登记控制 Peer，移除须先撤销且保留至少一项。
未登记隧道项可维护，已登记项须先移除控制登记；主控端口及账号版本共享，
配置事务可能短暂影响其它连接。v2 失败恢复仅保留可信快照中完整未变化的旧授权；
变化项禁用，无可信比较证据时全部禁用。v2 新身份灾备接续 6A.23，关联地址/密钥迁移和控制面
Fail2ban 明确拒绝。定向 CLI、菜单、WireGuard、备份及状态组已通过；
隔离 amd64 一主两被控事务及最终 API 双来源请求隔离已通过，证据见实施计划。
旧 bundle 须显式支持 v2 集合；完整灾备及原生环境缺口保留，整体状态不提前升级。

6A.8 将空目标恢复扩展到单 sing-box 双族 Hy2/TUIC 的已保存 `port_hopping` 规格。
候选重新校验，身份、累计及 tuple 保留；恢复后状态为 `stopped`，不恢复旧监督进程、
内核规则或运行态，重新启用须显式预检。宿主集成、控制角色、已有部署替换及完整灾备边界不变。

6A.9 接入桥接可达 `host_website` Reality 共存的空目标恢复；保留域名、地址及端口，
仅接受 host-gateway 或可路由 IP，并从规格重新生成 stream、验证能力 marker 和 Nginx。
回环、host 网络及未处理的 host-main 输入仍拒绝；宿主网站服务、内容与证书不在恢复范围。
恢复定向及集中完整合同 `65/65` 通过，入口 `529.143` 秒，证据见实施计划 6A.9；
原生宿主、arm64、公网和完整灾备继续 deferred。

6A.10 接入 schema `3`、`enabled=false` 的 webroot 续期登记，原字节和私密权限保留。
仅停用登记不恢复调度；非 DNS 登记夹带凭据继续拒绝，webroot ACME 与启用登记扩展见 6A.18。
6A.11 保留已有 HTTP-01 规格，重建容器 UID/GID `0750` 空挑战根、只读挂载和双栈
`80:8088`；不恢复旧挑战文件，受限 CA 账户和启用续期扩展见 6A.18。恢复定向 helper `69`、
preview `51`、apply `66` 场景通过，与 6A.12 集中合同 `65/65` 通过，证据见实施计划。
6A.12 先持久登记精确暂存再解包或生成候选；准备期硬杀后核对原骨架、路径和权限，
仅回收登记暂存，不执行未验证 Compose、不改调度。定向 helper `72`、preview `51`、
apply `88`、集中合同 `65/65` 通过；未知暂存或篡改继续拒绝。
6A.13 接入 Geo `enabled=true`：仍按原字节恢复三文件并离线解析，安装及健康检查通过后
恢复每日 Geo 调度；停用或无 Geo 输入不接管已有调度，预览不安装调度。
流量与 Geo 使用独立私密持久快照，先统一检查外部漂移，再按 Geo、流量逆序撤销。
需要写 systemd unit 时，unit 与私密暂存须同文件系统；原子替换不回退为跨文件系统复制。
当前验收见实施计划，完整灾备和整体菜单管理仍为 deferred。

6A.14 接受 acme.sh `3.1.6`、单域名、账户及域名 EC-P256、standalone HTTP-01 `8080`，
须有对应 schema `2` 停用续期登记，且 `.tls.http01` 不启用。恢复器不执行归档 shell，
重建固定 9 文件，仅丢弃已知 CSR/暂态材料；拒绝 hook、DNS/SAN/RSA/EAB、
未知配置和自定义执行路径。可信 ops 容器无网络验证密钥、有序唯一证书链及固定 TLS 输出绑定，
保留 CA 账户和域名密钥，停用登记不安装续期调度。定向与本地 CA 实际续期验收见实施计划。
6A.15 仅在上述安全材料匹配且续期登记只有该域时，允许 schema `2` standalone 保留 `enabled=true`；
候选安装及健康成功后按 traffic、Geo、renewal 顺序安装适用任务。
三项独立私密持久快照，统一检查外部漂移后按 renewal、Geo、traffic 逆序撤销，
unit 沿用同文件系统原子替换；预览不安装调度，停用或无登记不接管外部续期任务。
此阶段未接入 webroot，后续扩展见 6A.18；启用 DNS/ALPN 及其它 ACME 组合继续拒绝，空 `data/acme` 不能授权启用续期。
定向 helper `85`、材料 `24`、preview `54`、apply `202` 及本地 CA 启用恢复后的实际续期通过，
apply 入口 `263.726` 秒，实际续期 `24.428` 秒；日常 `docker-contracts` 34 项集成通过，入口 `262.522` 秒，证据见实施计划。
公网 CA、原生宿主/arm64、真实调度/整机重启和完整灾备仍待交付或验收。

4C.14 为无控制角色多 Peer 提供本机 `--address`、`--listen-port`、`--rotate-key`
迁移；至少显式提供一个本机字段，全部 Peer 地址、公钥及 endpoint 保持。
拒绝在多 Peer 迁移中使用任意对端字段，避免隐式选择；控制角色范围不扩大。
菜单沿用 `15 → 18 → 6`，使用原私密候选、配置事务及健康失败/INT/TERM 恢复。
本机地址或密钥改变后须逐端更新远端，服务重建可暂时中断全部连接，单端健康不证明远端连通。
定向 helper `34`、CLI `126`、事务 `152`、菜单 `91` 通过，入口 `68.771` 秒；
三独立 Engine/netns 的双链加密、业务/累计及健康失败恢复通过，入口 `269.265` 秒。
独立复审无实质问题，发布信任为离线夹具；证据及原生环境边界见实施计划。

6A.16 接入 canonical 单 Peer 无角色或已接入被控的同架构 v3 空目标恢复：
严格核三件套、清单、摘要及 `root:root 0700/0600`，可信 net 镜像验证密钥配对，
保留密钥、双方地址、被控身份/连接/受管快照/版本、账号与累计。
被控须先停自动同步，归档不得含 `secrets/control-sync`；恢复后重新邀请并手动同步，
保留版本防倒退门禁。先停止旧节点，不能同时运行同一 WG 身份。
不恢复接口、ifindex、alias、运行归属或来源挑战；目标重新预检。
失败撤销先停容器，再证明接口消失才清私密材料；残留接口或探测失败保留现场。
本阶段不接主控，后续新身份恢复见 6A.19，无控制角色多 Peer 见 6A.22；其它宿主集成、控制角色多 Peer、已有部署替换和完整灾备继续拒绝。
helper `93`、材料 `24`、preview `67`、完整 apply `227` 项及隔离 amd64 真实双端恢复通过；
真实恢复入口 `293.748` 秒，发布信任明确为离线夹具，证据见实施计划。整体支持状态不升级。

6A.18 接入同架构 v3 空目标、单域名 EC-P256 受管 webroot ACME 与启用续期恢复。
要求 `.tls.http01=true`、已有 Nginx TLS `21–25/27/29`、匹配 schema `3` 登记；
固定 `/var/lib/padm/acme-webroot` 且不得含 `Le_HTTPPort`。停用登记携带 ACME 同样严格绑定；
启用时登记目录只能有该域且材料完整。复用 9 文件安全重建、空挑战根及三任务恢复事务，
不执行归档 shell。helper `96`、材料 `28`、preview `69`、专用 apply `16` 通过，
定向入口 `84.124` 秒；真实验收结果见实施计划。DNS/ALPN、任意路径/hooks/SAN/RSA、
公网 CA、原生宿主/arm64、真实调度/重启和完整灾备继续待交付或验收。

6A.19 接入隔离旧主控后的单 Peer 新身份空目标恢复。显式 `--rebuild-controller`
及隔离确认只重建主控/Peer 身份、撤销授权并将 revision 归零；保留 API 端口、
WireGuard 密钥/地址、账号及累计。原规格/发布状态须一致，拒绝控制日志登记、
来源/历史日志及持久同步授权；被控须新邀请后显式 rebind，普通版本及凭据碰撞门禁保留。
helper `102`、材料 `28`、maintenance `38`、专用 apply `18` 及隔离 amd64
真实双端恢复/rebind/业务/累计通过；真实入口 `365.034` 秒，发布信任为离线夹具。
v2 集合新身份恢复接续 6A.23；原身份恢复、已有部署替换、原生宿主/arm64 与完整灾备仍未支持。

6A.20 接入单域 EC-P256、schema `4`／`alpn` ACME 与启用续期恢复，
固定 `Le_Webroot='alpn'`、`Le_TLSPort='8443'`，拒绝残留 HTTP 端口及验证方式混用。
允许合法 HTTP-01 入口共存；唯一启用登记及完整材料门禁保持，复用原恢复/调度事务。
helper `105`、材料 `32`、专用 apply `16` 及本地 CA 真实初签、空目标恢复、
挑战失败恢复和成功续期通过；真实入口 `112.758` 秒，发布信任为离线夹具。
ALPN 续期会临时停启占用 `443` 的受管服务，不承诺零中断；
DNS 启用续期、任意 hooks/端口、RSA/SAN、原生宿主/arm64/公网及完整灾备继续待验或拒绝。

6A.21 接入单域 EC-P256、schema `1`／`dns_acmedns` ACME 及匹配唯一启用续期登记。
域配置四个 `ACMEDNS_*` 字段与归档私密凭据精确绑定，规范 HTTPS 地址和有界 DNS 等待；
拒绝自监听端口、其它 provider、hooks/未知字段，沿用原 9 文件重建及离线 OpenSSL 校验。
外部 acme-dns 注册/CNAME 须仍有效，恢复不重建外部服务或交互注册；不增加生产依赖。
helper `109`、材料 `35`、preview `75`、专用 apply `16` 和派发合同通过，入口 `71.658` 秒。
本地权威 DNS、标准递归解析器和 CA 的真实初签、空目标恢复及生产续期通过，
入口 `84.251` 秒；TXT/serial 改变，`85` 次 HTTPS 全成功且 Nginx 未重启，
凭据私密权限、密钥及累计保持，证据见实施计划；发布信任为离线夹具。
其它启用 DNS、SAN/RSA、公网 CA、原生宿主/arm64、真实 systemd/重启和完整灾备仍待验或拒绝。

6A.22 接入无控制角色 canonical 非空 WireGuard Peer 集合的同架构 v3 空目标恢复，
保留原三文件、全部 Peer 地址/公钥/endpoint、本机身份密钥、账号及累计。
沿用原候选与持久恢复事务；本阶段控制角色限单 Peer，v2 主控接续 6A.23；旧节点须先停止并确认接口消失。
helper `110`、材料 `35`、preview `77`、apply `26` 及派发合同一次通过，入口 `76.102` 秒。
隔离 amd64 三独立 Engine/netns 的网关恢复、双链加密、真实业务和累计通过，
入口 `218.121` 秒，发布信任为离线夹具，证据见实施计划。
其它宿主集成、已有部署替换和原生宿主/arm64/公网/重启仍待交付或验收。

6A.23 复用主控显式新身份恢复入口，同架构 v3 空目标接受 v2 非空控制 Peer 集合。
旧主控须停机隔离；原规格、发布状态及所有登记 WG 地址严格绑定，
保留完整 canonical 隧道集合、Peer 次序、地址/API、业务和累计。
主控及全部 Peer ID/token hash 换新且无交叉碰撞，全部授权停用/过期、revision 归零；
不导入旧认证日志及来源现场，各被控须逐端新邀请/rebind，再继续正常同步。
helper `113`、材料 `35`、apply `18`、派发合同及 preview `81` 通过，唯一预览测试桩
修复后仅补该叶。三独立 Engine/netns 的双旧邀请拒绝、双端 rebind、revision `1`
同步、双链加密、业务及累计通过，真实入口 `641.241` 秒；证据见实施计划。
不扩大 v2 关联迁移、控制面 Fail2ban、已有部署替换及环境范围，完整状态仍 deferred。

## 第一阶段验收

完成本阶段后，后续实现必须满足：

1. 新增 Docker 能力必须同步更新配置合同、Compose、控制命令和回归；实现及验证齐备后再升级 `features.json` 的支持状态。
2. 配置运行状态为 `supported` 的协议必须同时有核心、profile、生成配置和回归证据；管理工作流必须单独更新 `management_status`。
3. `host-integrated` 必须写明 `network_mode`、capability、device 和宿主规则所有权。
4. `deferred` 和 `unsupported` 必须在安装前明确拒绝，不能偷偷调用原生安装器。
5. 原生公开协议 ID、`transport` 或 `udp_support` 改变时，Docker 阶段 3 回归必须发现矩阵漂移。
6. `features` 的每个兼容状态值必须与 `feature_matrix` 同名值一致；`supported` 功能的 `requires` 前置条件必须与实际校验一致。
