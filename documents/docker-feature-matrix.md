# Docker 版功能对照表

日期：2026-10-12

这份表是“原生菜单功能”和“Docker 当前能力”的第一阶段基线。状态只表示
Docker 现在能否通过受管控制命令完成对应能力，不表示底层镜像里是否包含某个
上游程序。

后续实施顺序和验收门槛见
[Docker 菜单与功能对齐实施计划](docker-menu-parity-plan.md)。计划安排不改变本表的当前支持状态。

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
完整管理继续 `deferred`，headers/sc*、downloadSettings、H3/CDN 与上下行分离未开放，
填充字节分布、抗识别、长时复用和吞吐收益未证明；本地 amd64 合同、菜单、
五组真实链路与 49 项完整回归已通过。
3C.3 新增 sing-box Hysteria2：首配、完整 v3 规格导入、参数编辑、复制/删除及本地分享链接，
支持单 UDP 入口、BBR/Brutal、Salamander 和 HTTPS 伪装；复用 TLS 和 UUID 流量账号。
带宽为服务端方向，链接转为客户端方向；包含 Hysteria2 时暂不接受宿主集成。
真实 amd64 的 BBR/Brutal/Salamander 各 IPv4/IPv6 共 6 条 HTTP proof 已通过；
端口跳跃、Gecko、第三方导入 UI、公网宿主入口和原生 arm64 未验或尚未开放。
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
默认 `cubic`、`3s`、`10s` 和关闭 0-RTT；端口跳跃、宿主集成及完整管理尚未开放。
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
| 安装与重装 | 部分已交付，完整管理 `deferred` | `install`、可信发布输入 `release`、交互首配 `setup`、`edit`、`configure`、候选校验及恢复 | 支持 `1`、`2`、`3`、`4`、`5`、`21`、`22`、`23`、`24`、`25`、`26`、`27`、`28`、`29`、`30`、`31` 字段编辑、完整原始 spec 接入、多入口及主副核心；重装和真实发布连通未完成。 |
| 订阅与用户 | `supported` + `host-integrated` + `deferred` | 有条件的订阅发布、流量采集/额度、v3 独立账号与双核心认证/统计、账号/分享组及业务备份恢复、主控管理与被控接入/手动同步、已有单 Peer 被控自动同步 CLI/菜单、WireGuard 宿主集成 | HTTPS 链接仍要求受管 TLS；H3 和完整多服务器工作流未迁移。隔离 amd64 双部署事务及真实 cron 自主同步已验，WireGuard 需 `net-wireguard`；原生双机、arm64 和重启另验。 |
| 协议与入口 | 部分 `supported`，管理工作流 `deferred` | `1` Reality Vision、`2` XHTTP、`3` Hysteria2、`4` AnyTLS、`5` NaiveProxy、`21` VLESS WS TLS、`22` VMess WS TLS、`23` VMess HTTPUpgrade TLS、`24` VLESS gRPC TLS、`25` Trojan gRPC TLS、`26` Reality gRPC、`27` TLS Vision fallback、`28` direct Trojan、`29` Trojan TLS fallback、`30` Shadowsocks、`31` TUIC 的配置运行、字段编辑、分享链接、多入口、Reality 传输派生、参数重生成和目标站管理；有限 Reality 443 共存及 21/22/23/24/25 CDN 连接地址覆盖 | XHTTP、VMess WS、gRPC TLS 和传统 TLS fallback 仅限 Xray，Hysteria2/AnyTLS/NaiveProxy/Shadowsocks/TUIC 仅限 sing-box；HTTPUpgrade 支持两核心；完整协议管理、UDP 端口跳跃、其余 CDN 和完整内部路由工作流尚未开放；Fail2ban WS 增删及通用端口编辑拒绝，单入口保护端口专项见 5C.6d。 |
| 站点与证书 | 部分 `supported`，其余 `deferred` | TLS 文件安装、DNS-01 与 HTTP-01 standalone/受管 webroot 本地事务、Nginx WebSocket/HTTPUpgrade/gRPC HTTP/2 入口及传统 TLS fallback；默认页、静态目录、302 与逐入口 ALPN 事务管理 | 真实 Xray ALPN 协商、公网 CA、宿主生命周期及原生双架构验收待补。 |
| 路由与访问控制 | `host-integrated` + `deferred` | WireGuard、TUN/TProxy 宿主集成合同；5B.1–5B.4d 两核心 SOCKS5 TCP 出站、DNS/hosts、域名 Direct/Block、目的 IP、明文 BT、CN 预设、IPv6 与用户态 WARP 子能力；已有 DNS/选择性 IPv6/WARP 名单增删；5B.5a 已有 Xray 的 HTTP 中继事务 | SOCKS UDP 发布、完整区域/访问控制仍未交付；WARP 公网出口、IPv6/HTTP 公网发布、真实宿主及双架构验收待补，完整状态不升级。 |
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
| 2 | VLESS Reality XHTTP | 协议与入口 -> XHTTP 管理 | `supported` | `deferred` | Xray | `core-xray` | bridge / TCP | v3 支持首配、导入、路径/Host/模式编辑、复制及分享链接；3D.4 四预设、客户端 XMUX 三键自定义/清除和 3D.5 有限 Padding 1..4096 设置/恢复缺省、状态及发布事务已接入。Padding 双端一致，拒绝零且不能关闭，显式字段另需 bundle 能力；本地合同/菜单/五组真实链路通过；其它高级参数和完整管理未开放。 |
| 3 | Hysteria2 | 协议与入口 -> Hysteria2 管理 | `supported` | `deferred` | sing-box | `core-sing-box` | bridge / UDP | v3 支持首配、导入、BBR/Brutal、Salamander/HTTPS 伪装编辑、复制及分享链接；复用受管 TLS 和 UUID 流量账号，端口跳跃与完整管理未开放。 |
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
| 30 | Shadowsocks | 安装与重装 -> 自定义安装 | `supported` | `deferred` | sing-box | `core-sing-box` | bridge / TCP + UDP | v3 SS2022 AES-128 多用户首配、导入、通用编辑、同核复制/删除及 SIP002 链接；无需 TLS，UUID 共享统计额度，凭据/身份冻结，宿主集成及完整管理未开放。 |
| 31 | TUIC | 协议与入口 -> Tuic 管理 | `supported` | `deferred` | sing-box | `core-sing-box` | bridge / UDP | v3 首配、导入、入口/拥塞/认证超时/心跳/0-RTT 编辑、同核复制/删除及 URI；受管 TLS、UUID 共享额度，端口跳跃与完整管理尚未开放。 |

### 内部服务端能力

原生协议注册表另含内部 ID `201..207`。这些能力不是公网节点，但属于路由、
中继和访问控制菜单，不能从对照范围中漏掉。

| ID | 能力 | 原生入口 | Docker 状态 | Docker 边界 |
| ---: | --- | --- | --- | --- |
| 201 | Socks 中继 | 路由与访问控制 -> 分流工具 | `deferred` | 5B.1–5B.2 已交付认证 TCP 全局/域名出站；入站仍未交付：sing-box 动态 UDP BND 发布不通，5B.5b Xray 固定发布可达但控制关闭后无认证 UDP 仍可转发。 |
| 202 | HTTP 中继 | 路由与访问控制 -> 分流工具 | `deferred` | 5B.5a 提供已有受管 Xray 的私有认证 HTTP/CONNECT 入站、来源规则和事务管理；双栈发布与来源已在隔离 amd64 Linux daemon 验证，IPv6 只接受管 bridge 并拒绝旧 plain bridge 恢复；sing-box 来源头绕过导致明确拒绝，公网/宿主/arm64 待验。 |
| 203 | WireGuard | 订阅与用户 / 路由与访问控制 | `host-integrated` | `net-wireguard`、host network、`NET_ADMIN`。 |
| 204 | TUN | 路由与访问控制 | `host-integrated` | `net-transparent`、host network、`NET_ADMIN`、`/dev/net/tun`。 |
| 205 | Redirect/TProxy | 路由与访问控制 | `host-integrated` | `net-transparent`、host network、`NET_ADMIN`。 |
| 206 | DNS/Direct/Block | 路由与访问控制 -> DNS/hosts | `deferred` | 5B.3–5B.4 已交付 DNS/hosts、已有 DNS 的域名稳定追加/精确删除（保留上游，删空关闭）、域名 Direct/Block（私有 JSON、CSV 整组替换、增量追加和精确删除）、目的 IP 名单（私有 JSON 替换/追加/完整字符串删除）、明文 BT、CN 预设、IPv6 与 WARP 子合同和事务；手工 IP 删除不匹配网络包含或区域合成项，完整区域策略、逐条规则编辑与冲突检测待补。 |
| 207 | Tunnel/dokodemo-door | 路由与访问控制 -> 访问控制 | `deferred` | 5B.5c–5B.5d 提供已有受管入口的额外 Compose 发布端口及逐入口默认分享选择，复用认证/统计及 TLS/SNI 前端；宿主集成和公网/双架构验收未交付，不做任意目的转发。 |

## 功能和宿主边界

| 功能键 | 原生入口 | Docker 状态 | Profile | 网络/权限边界 | 当前说明 |
| --- | --- | --- | --- | --- | --- |
| `nginx` | 站点与证书 -> 传统 TLS fallback | `supported` | `nginx` | bridge | 独立 Nginx 容器，承载 WS/HTTPUpgrade/gRPC 反代与传统 TLS fallback 的 PROXY v1 HTTP/1.1、HTTP/2 后端；默认页、静态目录、302 与传统 TLS ALPN 经菜单/CLI 事务管理。 |
| `tls-files` | 站点与证书 -> 本机 TLS 证书 | `supported` | `nginx` / `acme` | bridge | 菜单/CLI 校验、导入轮换和只读挂载；Nginx 与 Xray/sing-box 逐消费者校验、重载/重建及健康失败恢复旧证书。核心端仅交付受管 TLS 文件底座，不代表新增协议或完整管理。 |
| `acme-dns` | 站点与证书 -> 本机 TLS 证书 | `supported` | `acme` | bridge + 宿主 CLI 调度 | 菜单/CLI DNS-01 issue/renew 及自动续期启停/状态；root 私有输入、唯一 systemd/cron 任务、部署锁和候选账户/证书事务；未到期跳过，更新/回滚保留最新输入，卸载只撤销受管任务。 |
| `subscription` | 订阅与用户 -> 订阅发布 | `supported` | `core-xray` / `nginx` / `subscription` | bridge | 既有部署级 token 发布继续要求 Xray 协议 `21` 和受管 TLS；分享组另有独立 token，可按账号/入口生成纯订阅内容并查看 HTTPS 链接；CDN/H3 仍未迁移。 |
| `subscription-traffic` | 订阅与用户 -> 流量与额度 | `supported` | 核心 profile | 宿主 CLI | 定时采集以及 show/limit/reset；自用按原 UUID、独立账号按稳定 ID 共享跨核心累计与额度，凭据轮换和恢复不回退累计。 |
| `subscription-users` | 订阅与用户 -> 用户和分享订阅 | `supported` | 核心、订阅 | bridge | 4A.1–4A.4 账号底座、账号 CLI/菜单事务、独立 token 分享组及业务备份恢复已交付；账号/入口筛选、启停/轮换、纯内容与 HTTPS 链接，账号/组/额度/累计 merge/replace 恢复均复用候选事务，轮换与恢复不回退最新累计。CDN/H3 与完整多服务器工作流按独立功能边界验收。 |
| `subscription-multiserver` | 订阅与用户 -> 主控/被控、多服务器同步 | `deferred` | 订阅、WireGuard | host | 4C.1–4C.5 提供私网 API、主控管理、被控接入/手动同步及已有单 Peer 被控每 5 分钟自动同步 CLI/菜单。校验 Peer 归属、地址与唯一 `/32`，不建接口/密钥/路由；默认关闭，持久邀请限本机 root 私有目录，不进规格/备份/普通日志，停用清除凭据。独立服务和客户端零能力，无公网映射。隔离 amd64 双 Docker Engine 的生产 CLI/Compose、WS/TLS 流量、真实 cron 自主推进、同版幂等、锁竞争、轮换/撤销及健康失败/INT/TERM 恢复已验。正常 down 跳过，异常归属和 WS/SSH 来源防护组合拒绝。多 Peer、网络向导、角色重绑定、迁移、灾备、原生 systemd/双机/arm64、重启和可信发布待补。 |
| `acme-webroot` | 站点与证书 -> 传统 TLS fallback | `deferred` | `acme` / `nginx` | bridge | 5A.3b 已提供显式 opt-in 双栈 `80:8088`、独立 HTTP vhost、只读稳定根与 ops 独占 `active/`，菜单/CLI 和 schema 3 自动续期；归属及目录校验、不停 Nginx、失败/信号恢复和关闭/回滚保护。公网 CA、真实宿主生命周期及原生双架构未验，完整状态不升级。 |
| `acme-standalone` | 站点与证书 -> 本机 TLS 证书 | `deferred` | `acme` | 宿主预检 + bridge | 5A.3a 已提供 HTTP-01 首配、菜单/CLI 和自动续期；非 root ops 临时双栈 `80:8080`，实际归属校验，只暂停原运行拥有者并恢复；未到期不暂停。公网 CA、原生 Linux/双架构和 TLS-ALPN-01 未验，完整状态不升级。 |
| `site-static-redirect-alpn` | 站点与证书 -> fallback 站点、302、ALPN | `deferred` | `nginx` | bridge | 5A.1 站点、5A.1b 受管 notes/photos/docs 模板与 5A.2 逐入口 ALPN 诊断/三种顺序事务已提供；模板限已有 v3 Xray 21–25/27/29，拒绝 sing-box 23/Hy2 共存，资源清单随 bundle 校验，生成后仍普通 static。隔离 amd64 27/29 的真实 Xray 双栈 TLS ALPN、h1/h2 fallback/404、PROXY 来源与认证已验，公网及原生双架构仍待验。 |
| `reality-target-management` | 协议与入口 -> REALITY 管理 -> 目标站管理 | `supported` | 核心 profile | 宿主 CLI | 对齐原生 8 项管理及首配候选检测/手动输入；检测 TLS/PQC/ASN/证书链、刷新库、网段/同 ASN 抽样扫描、A 级筛选分页与逐入口切换、host[:port]/独立 SNI、黑名单；扫描进度和部分结果处理共用原生，B/C 手动告警，全部地址按最差评分及 CDN 风险判定，缓存切换重新复测，Docker 私密状态与事务恢复独立于原生。 |
| `reality-parameter-management` | 协议与入口 -> REALITY 管理 -> 重新生成参数 | `supported` | 核心 profile | 宿主 CLI | 菜单/CLI 按入口重生成密钥对和 short ID，派生校验、候选确认和失败恢复；账号、目标、其它入口及额度保持，链接和已启用发布同步更新。 |
| `reality-coexistence` | 协议与入口 -> REALITY 管理 -> 443 共存分流 | `deferred` | `core-xray` / `nginx` / `nginx-stream` | 宿主 CLI | 已提供受管 TLS 入口、桥接可达宿主网站或独立 host 网络分流入口与一个 Xray Vision/XHTTP 后端的 443 共存；菜单/CLI 状态、开启、更换、关闭及端口恢复复用候选事务。宿主网站的多个 SNI、host-gateway、可路由 IP 或回环支持有明确边界；原生宿主、适用公网及完整管理仍待验收。 |
| `entry-port-management` | 协议与入口 -> 入口端口管理 | `deferred` | 核心 | bridge | v2/v3 多入口复制/删除及端口事务，v3 明确核心归属；5B.5c–5B.5d 额外端口增删/状态/默认分享的菜单/CLI、候选恢复与本地真实发布已验，复用原认证、统计及 TLS/SNI 前端。受管或桥接可达宿主网站的 Reality 443 共存可使用别名；拒绝 WS/SSH Fail2ban、TUN/TProxy 和 host-network，允许已有 WireGuard/控制面 Fail2ban。既有身份/内部端口冻结，端口跳跃及适用公网/IPv6/原生宿主/arm64、完整管理仍待交付或验收。 |
| `cdn-entry-management` | 协议与入口 -> CDN 入口管理 | `deferred` | `subscription` | bridge | 4A.5–4A.5b 提供协议 21/22/23/24/25 的逐入口多连接地址覆盖，菜单/CLI 状态、设置和清除，统一生成本地链接、主订阅及分享组；保留端口、SNI、Host/路径或 gRPC serviceName/h2 与认证，候选确认及失败恢复复用现有事务。24/25 仅已有 Xray/Nginx TLS，带映射另要求 x-padm-cdn-grpc-tls，旧三协议/无映射 gRPC 子集保持。其它协议、H3、公网供应商透传、真实宿主/arm64 和可信发布仍待验。 |
| `fail2ban` | 系统与脚本 -> Fail2ban 防护 | `host-integrated` | `net-fail2ban` / `net-fail2ban-control` / `net-fail2ban-ssh` | host + `NET_ADMIN` | WS DOCKER-USER、控制面 INPUT 与专用 SSH INPUT 的独立 owner 和菜单/CLI；SSH/control 不共存。5C.6d 单 WS 保护端口专项已验实际双栈封禁、端口迁移、SQLite 保留、来源/健康失败恢复与旧规则清理，新旧端口均需 fresh 来源，别名、Reality stream 和其它集成拒绝；WS 日志组为 `0:10001`，权限不放宽。控制认证日志支持菜单/CLI 每小时轮转检查，默认关闭、本机私有登记、同锁与旧 bundle 门禁；线上 auto 入口及隔离 amd64 原始每小时 :19 cron 自主触发、实际归档/续写/停用已验，systemd 实际定时触发待验。SSH 限原生 root systemd/cgroup v2、无存量会话且禁止 reload 的单 service/单显式监听，只消费启动后的可信密码失败。transient collector、只读日志/10 秒 guard、启停/状态/单 IP 解封已接，来源失效自动停 jail/精确清理，禁自动重启和恢复旧封禁；SSH 启用时 update/rollback/业务恢复拒绝，先受管停用。隔离 amd64 OpenSSH 10/Fail2ban 1.1 实际启停、封禁、连接 DROP、解封和来源失效清理已验；原生宿主/arm64/公网/重启卸载及完整管理仍待验收。 |
| `wireguard` | 订阅与用户 / 路由与访问控制 | `host-integrated` | `net-wireguard` | host + `NET_ADMIN` | 接口和密钥由宿主内核拥有。 |
| `tun` | 路由与访问控制 -> TUN | `host-integrated` | `net-transparent` | host + `NET_ADMIN` + `/dev/net/tun` | 显式启用透明代理设备。 |
| `tproxy` | 路由与访问控制 -> Redirect/TProxy | `host-integrated` | `net-transparent` | host + `NET_ADMIN` | 依赖宿主路由和防火墙规则。 |
| `routing-tools` | 路由与访问控制 -> WARP/IPv6/Socks5/DNS/BT/访问控制 | `deferred` | 核心 | bridge | 5B.1–5B.4d 已交付 SOCKS5 TCP 出站、DNS/hosts、域名 Direct/Block、目的 IP、明文 BT、CN 预设、IPv6 和用户态 WARP 子能力及失败恢复；已有 WARP 可保留密钥修改域名、全局模式及地址族，已有 selective WARP/IPv6 可增删域名，缺失/global 拒绝、删空关闭，不改宿主。完整区域/访问控制和公网/宿主/双架构验收待补。 |
| `internal-201-socks-relay` | 路由与访问控制 -> Socks 中继 | `deferred` | 核心 | bridge | 5B.1–5B.2 TCP 出站子能力已交付；5B.5b 确认 sing-box 动态 BND 发布阻塞、Xray 26.3.27 固定 UDP 发布的来源许可在当前进程内不随控制关闭撤销，完整入站不交付、不降为 TCP-only；不作为公网节点。 |
| `internal-202-http-relay` | 路由与访问控制 -> HTTP 中继 | `deferred` | `core-xray` | bridge | 5B.5a 独立 `relay.http` 合同、私有认证与来源前置规则、菜单/CLI/关闭/回滚；专属直连且不计业务额度。双栈发布与真实来源已在隔离 amd64 Linux daemon 验证，IPv6 relay 只接受管 bridge，拒绝旧包/旧 plain bridge 恢复；拒绝 sing-box 的代理头来源覆盖，公网、宿主、arm64 和可信发布待验。详见 `docker-http-relay.md`。 |
| `internal-203-wireguard` | 订阅与用户 / 路由 -> WireGuard | `host-integrated` | `net-wireguard` | host + `NET_ADMIN` | 接口由宿主内核拥有；4C.3a 核验真实归属后预检/健康/撤销，活动旧式标记需先正常停止旧容器。 |
| `internal-204-tun` | 路由与访问控制 -> TUN | `host-integrated` | `net-transparent` | host + `NET_ADMIN` + `/dev/net/tun` | 依赖宿主设备和转发规则。 |
| `internal-205-redirect-tproxy` | 路由与访问控制 -> Redirect/TProxy | `host-integrated` | `net-transparent` | host + `NET_ADMIN` | 依赖宿主路由和防火墙。 |
| `internal-206-routing-rules` | 路由与访问控制 -> DNS/Direct/Block | `deferred` | 核心 | bridge | 5B.3–5B.4d 已交付 DNS/hosts、已有 DNS 的域名稳定追加/精确删除（保留上游，删空关闭）、域名 Direct/Block（私有 JSON、CSV 整组替换、增量追加和精确删除）、目的 IP 私有 JSON 替换/追加/完整字符串删除、明文 BT、CN 预设与自定义直连例外增删、IPv6、WARP 子合同及日常域名/模式/地址族编辑、已有 selective IPv6/WARP 域名增删、双核心适配及专项事务；global/缺失增删拒绝、删空关闭对应策略，手工 IP 与区域合成保持独立，完整区域策略、逐条规则编辑、冲突检测和适用公网验收待补。 |
| `internal-207-access-control` | 协议与入口 -> 额外入口端口 | `deferred` | 原业务核心/Nginx | bridge | 5B.5c–5B.5d 独立 `port_aliases`、菜单/CLI 增删/状态/默认分享与候选回滚；双栈 TCP/UDP 发布已在隔离 amd64 Linux daemon 验证，同入口认证/统计，TLS/SNI 前端不旁路，URI/主订阅/分享组逐入口选择已有别名，恢复或删除后回退 base，不增加节点。拒绝 WS/SSH Fail2ban、TUN/TProxy 和 host-network，允许已有 WireGuard/控制面 Fail2ban；适用公网/原生宿主/arm64 与完整管理验收待补。 |
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
