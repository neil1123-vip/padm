# Docker 版功能对照表

日期：2026-10-06

这份表是“原生菜单功能”和“Docker 当前能力”的第一阶段基线。状态只表示
Docker 现在能否通过受管控制命令完成对应能力，不表示底层镜像里是否包含某个
上游程序。

后续实施顺序和验收门槛见
[Docker 菜单与功能对齐实施计划](docker-menu-parity-plan.md)。计划安排不改变本表的当前支持状态。

## 状态定义

| 状态 | 含义 |
| --- | --- |
| `supported` | Docker 配置合同、控制命令和 Compose profile 已能完成该能力。 |
| `host-integrated` | 能力依赖宿主内核、接口或防火墙；只能通过显式 `net-*` profile 使用。 |
| `deferred` | 原生已有能力，Docker 已记录边界或后续方向，但当前合同/控制命令尚未开放。 |
| `unsupported` | 当前 Docker 版本不提供，也没有可安全复用的现成入口。 |

协议的 `status` 只表示通过首次向导或 JSON spec 配置并运行的能力；`management_status`
另行表示原生协议管理工作流的迁移状态。初始配置可运行不代表完整菜单管理已支持。

3A.3 已通过本地回归：v3 明确主副核心与每个入口归属，两核心合计最多 16 个入口，
菜单和 `edit --spec` 可复制、删除现有协议入口；v1/v2 的配置及备份恢复继续兼容。
Reality 可跨核心复制，删除副核心最后入口会关闭副核心，主核心至少保留一个入口。
复制复用凭据，同 UUID 跨核心共享流量与额度；两核采样全部复验后才写累计，
额度应用失败或中断恢复全部配置，既有身份、核心归属和 WS 内部端口不改排。
Xray 仅 Reality/WS TLS，sing-box 仅 Reality；双核心暂不能组合宿主集成。
新协议类型、
TLS 轮换及完整管理未交付，协议的 `management_status` 继续为 `deferred`。
Fail2ban 关联 WS 的增删及公开端口修改暂冻结；真实签名发布、业务镜像及
双架构客户端连通仍待验，不能由工具容器回归推断完成。

机器可读状态位于 [`docker/contracts/features.json`](../docker/contracts/features.json)：

- `protocols[]` 记录公开协议 ID、配置运行状态、管理状态、核心、profile、`transport`、`udp_support` 和原因。
- `features` 保留旧的兼容状态子集；同名值必须与 `feature_matrix` 一致。
- `feature_matrix` 记录完整功能状态、原生菜单入口、Docker profile、宿主权限、前置条件和原因。

## 主菜单对照

| 原生菜单 | Docker 当前状态 | 已覆盖 | 尚未覆盖或边界 |
| --- | --- | --- | --- |
| 安装与重装 | 部分已交付，完整管理 `deferred` | `install`、可信发布输入 `release`、交互首配 `setup`、`edit`、`configure`、候选校验及恢复 | 支持 `1`、`21` 字段编辑、完整原始 spec 接入、多入口及主副核心；重装和真实发布连通未完成。 |
| 订阅与用户 | `supported` + `host-integrated` + `deferred` | 有条件的订阅发布、流量采集/额度、WireGuard 宿主集成 | 发布仅支持包含协议 `21` 和受管 TLS 的 Xray 配置；用户 CRUD 和多服务器工作流未迁移；WireGuard 需 `net-wireguard`。 |
| 协议与入口 | 部分 `supported`，管理工作流 `deferred` | 协议 `1` Reality Vision、`21` VLESS WS TLS 的配置运行、字段编辑、多入口和跨核心 Reality 复制/删除 | 完整协议管理、Reality 目标库/扫描/参数重生成/443 共存、其余公开协议、内部路由协议和 CDN 地址覆盖尚未开放；Fail2ban WS 增删及端口联动未交付。 |
| 站点与证书 | 部分 `supported`，其余 `deferred` | TLS 文件安装、DNS-01 ACME、Nginx WebSocket 入口 | webroot/standalone ACME、静态站点/302/ALPN 管理尚未迁移。 |
| 路由与访问控制 | `host-integrated` + `deferred` | WireGuard、TUN/TProxy 宿主集成合同 | WARP、IPv6 调优、Socks/HTTP 中继、DNS/hosts、BT、访问控制和路由规则尚未迁移。 |
| 核心与服务 | `supported` + `deferred` | 基础状态、启动、停止、重启、日志、更新、回滚、配置校验 | 预发布试跑、升级风险扫描、Xray Geo 文件更新和自动任务尚未迁移；当前使用宿主子命令，不是原生全部生命周期管理。 |
| 系统与脚本 | `supported` + `host-integrated` + `unsupported` | `padm-docker update`、Fail2ban 宿主集成 | BBR/网络优化不由 Docker 修改宿主内核；Fail2ban 需 `net-fail2ban`。 |
| 高级/危险操作 | `supported` + `unsupported` | 受管卸载、移除镜像、显式 purge | VLESS Encryption 实验尚未纳入 Docker 合同。 |

## 公网协议

协议 ID 与原生 [`shell/core/protocols.sh`](../shell/core/protocols.sh) 的
`category=node` 注册表保持一致。Docker 当前只接受配置运行状态为 `supported`
且核心匹配的协议；管理状态独立记录，不能由运行状态推断。

| ID | 能力 | 原生入口 | 配置运行状态 | 管理状态 | 核心 | Compose profile | 网络/监听 | 原因 |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | VLESS Reality Vision | 安装与重装；协议与入口 -> REALITY 管理 | `supported` | `deferred` | Xray / sing-box | `core-xray` / `core-sing-box` | bridge / TCP | 支持单核心或主副核心配置、字段编辑及跨核心同协议多入口；完整管理未迁移。 |
| 2 | VLESS Reality XHTTP | 协议与入口 -> XHTTP 管理 | `deferred` | `deferred` | Xray | 无 | bridge / TCP | XHTTP 入站及参数管理尚未进入 Docker 合同。 |
| 3 | Hysteria2 | 协议与入口 -> Hysteria2 管理 | `deferred` | `deferred` | sing-box | 无 | bridge / UDP | UDP、端口跳跃、拥塞模式和订阅输出尚未接入。 |
| 4 | AnyTLS | 安装与重装 -> 自定义安装 | `deferred` | `deferred` | sing-box | 无 | bridge / TCP | AnyTLS 入站、TLS 和订阅合同尚未接入。 |
| 5 | NaiveProxy | 安装与重装 -> TLS 指纹抗性 | `deferred` | `deferred` | sing-box | 无 | bridge / TCP | 域名、证书和 NaiveProxy 配置尚未接入。 |
| 21 | VLESS WS TLS | 安装与重装 -> 自定义安装 / 传统 TLS 兼容安装 | `supported` | `deferred` | Xray | `core-xray` / `nginx` | bridge / TCP + Nginx | 已有多入口 Xray 后端、Nginx 反代和同域 TLS；Fail2ban 关联入口增删/改端口及完整管理未迁移。 |
| 22 | VMess WS TLS | 安装与重装 -> 自定义安装 | `deferred` | `deferred` | Xray | 无 | bridge / TCP | Docker 当前只开放 VLESS WebSocket 合同。 |
| 23 | VMess HTTPUpgrade TLS | 安装与重装 -> 自定义安装 | `deferred` | `deferred` | Xray / sing-box | 无 | bridge / TCP + Nginx | HTTPUpgrade 入口和订阅输出尚未接入。 |
| 24 | VLESS gRPC TLS | 安装与重装 -> 自定义安装 | `deferred` | `deferred` | Xray | 无 | bridge / TCP + Nginx | gRPC 反代和 HTTP/2 合同尚未接入。 |
| 25 | Trojan gRPC TLS | 安装与重装 -> 自定义安装 | `deferred` | `deferred` | Xray | 无 | bridge / TCP + Nginx | gRPC 反代和 Trojan 输出尚未接入。 |
| 26 | VLESS Reality gRPC | 安装与重装 -> 自定义安装 | `deferred` | `deferred` | Xray / sing-box | 无 | bridge / TCP | Reality gRPC 配置和双核心输出尚未接入。 |
| 27 | VLESS TCP TLS Vision | 安装与重装 -> 自定义安装 / 传统 TLS 兼容安装 | `deferred` | `deferred` | Xray | 无 | bridge / TCP + fallback | fallback 后端和传统 TLS 站点合同尚未接入；站点菜单只维护已有站点。 |
| 28 | Trojan TCP TLS direct | 安装与重装 -> 自定义安装 | `deferred` | `deferred` | Xray / sing-box | 无 | bridge / TCP | 双核心 Trojan 配置和订阅输出尚未接入。 |
| 29 | Trojan TCP TLS fallback | 安装与重装 -> 自定义安装 / 传统 TLS 兼容安装 | `deferred` | `deferred` | Xray | 无 | bridge / TCP + fallback | fallback 后端和传统 TLS 站点合同尚未接入；站点菜单只维护已有站点。 |
| 30 | Shadowsocks | 安装与重装 -> 自定义安装 | `deferred` | `deferred` | sing-box | 无 | bridge / TCP + UDP | sing-box 入站、TCP/UDP 端口映射和订阅输出尚未接入。 |
| 31 | TUIC | 协议与入口 -> Tuic 管理 | `deferred` | `deferred` | sing-box | 无 | bridge / UDP | UDP、端口跳跃、拥塞控制和 Tuic 参数尚未接入。 |

### 内部服务端能力

原生协议注册表另含内部 ID `201..207`。这些能力不是公网节点，但属于路由、
中继和访问控制菜单，不能从对照范围中漏掉。

| ID | 能力 | 原生入口 | Docker 状态 | Docker 边界 |
| ---: | --- | --- | --- | --- |
| 201 | Socks 中继 | 路由与访问控制 -> 分流工具 | `deferred` | 尚无内部 Socks 入站合同。 |
| 202 | HTTP 中继 | 路由与访问控制 -> 分流工具 | `deferred` | 尚无内部 HTTP 入站合同。 |
| 203 | WireGuard | 订阅与用户 / 路由与访问控制 | `host-integrated` | `net-wireguard`、host network、`NET_ADMIN`。 |
| 204 | TUN | 路由与访问控制 | `host-integrated` | `net-transparent`、host network、`NET_ADMIN`、`/dev/net/tun`。 |
| 205 | Redirect/TProxy | 路由与访问控制 | `host-integrated` | `net-transparent`、host network、`NET_ADMIN`。 |
| 206 | DNS/Direct/Block | 路由与访问控制 -> DNS/hosts | `deferred` | 尚无可编辑、可校验的路由规则合同。 |
| 207 | Tunnel/dokodemo-door | 路由与访问控制 -> 访问控制 | `deferred` | 尚无对应入站和防火墙合同。 |

## 功能和宿主边界

| 功能键 | 原生入口 | Docker 状态 | Profile | 网络/权限边界 | 当前说明 |
| --- | --- | --- | --- | --- | --- |
| `nginx` | 站点与证书 -> 传统 TLS fallback | `supported` | `nginx` | bridge | 独立 Nginx 容器，承载 WS 反代和静态入口。 |
| `tls-files` | 站点与证书 -> 本机 TLS 证书 | `supported` | `nginx` / `acme` | bridge | 菜单/CLI 校验、导入轮换和只读挂载；Nginx 校验、重载或健康检查失败恢复旧证书。核心端 TLS 待 3B.2。 |
| `acme-dns` | 站点与证书 -> 本机 TLS 证书 | `supported` | `acme` | bridge | 菜单/CLI 显式 DNS-01 issue/renew；候选账户与证书同事务，保留其他域名。自动调度待 3B.3。 |
| `subscription` | 订阅与用户 -> 订阅发布 | `supported` | `core-xray` / `nginx` / `subscription` | bridge | token 保护的发布；要求主核心或副核心中的 Xray 协议 `21` 和受管 TLS，可包含两核心 Reality 链接；没有 Xray WS TLS 入口时不可发布。 |
| `subscription-traffic` | 订阅与用户 -> 流量与额度 | `supported` | 核心 profile | 宿主 CLI | 定时采集以及 show/limit/reset。 |
| `subscription-users` | 订阅与用户 -> 用户和分享订阅 | `deferred` | 核心、订阅 | bridge | 规格能声明账号，但交互式增删改工作流尚未迁移。 |
| `subscription-multiserver` | 订阅与用户 -> 主控/被控、多服务器同步 | `deferred` | 订阅、WireGuard | host | WireGuard 集成存在；角色管理、同步事务和恢复向导未迁移。 |
| `acme-webroot` | 站点与证书 -> 传统 TLS fallback | `deferred` | `acme` / `nginx` | bridge | 需要 webroot、端口归属和原子 reload。 |
| `acme-standalone` | 站点与证书 -> 本机 TLS 证书 | `deferred` | `acme` | host | 需要 80/443 宿主端口和停机回滚。 |
| `site-static-redirect-alpn` | 站点与证书 -> fallback 站点、302、ALPN | `deferred` | `nginx` | bridge | 尚无站点管理、ALPN 诊断和修复事务。 |
| `reality-target-management` | 协议与入口 -> REALITY 管理 -> 目标站管理 | `deferred` | 核心 profile | 宿主 CLI | 配置时目标检测已有；扫描、候选库、黑名单和 PQC 管理尚未迁移。 |
| `reality-parameter-management` | 协议与入口 -> REALITY 管理 -> 重新生成参数 | `deferred` | 核心 profile | 宿主 CLI | 初始规格可声明密钥、short ID 和 SNI，但参数重生成工作流尚未迁移。 |
| `reality-coexistence` | 协议与入口 -> REALITY 管理 -> 443 共存分流 | `deferred` | `core-xray` / `nginx` | 宿主 CLI | 共存开启、状态检查、关闭及端口恢复事务尚未迁移。 |
| `entry-port-management` | 协议与入口 -> 入口端口管理 | `deferred` | 核心 | bridge | v2/v3 已有多入口端口映射及候选事务，v3 明确核心归属；既有内部端口冻结，Fail2ban 联动和 443 共存等完整管理未交付。 |
| `cdn-entry-management` | 协议与入口 -> CDN 入口管理 | `deferred` | `subscription` | bridge | 尚无独立订阅入口地址覆盖管理。 |
| `fail2ban` | 系统与脚本 -> Fail2ban 防护 | `host-integrated` | `net-fail2ban` | host + `NET_ADMIN` | 封禁规则属于宿主防火墙。 |
| `wireguard` | 订阅与用户 / 路由与访问控制 | `host-integrated` | `net-wireguard` | host + `NET_ADMIN` | 接口和密钥由宿主内核拥有。 |
| `tun` | 路由与访问控制 -> TUN | `host-integrated` | `net-transparent` | host + `NET_ADMIN` + `/dev/net/tun` | 显式启用透明代理设备。 |
| `tproxy` | 路由与访问控制 -> Redirect/TProxy | `host-integrated` | `net-transparent` | host + `NET_ADMIN` | 依赖宿主路由和防火墙规则。 |
| `routing-tools` | 路由与访问控制 -> WARP/IPv6/Socks5/DNS/BT/访问控制 | `deferred` | 视后续合同 | 可能需要 host | 原生路由策略尚未迁移。 |
| `internal-201-socks-relay` | 路由与访问控制 -> Socks 中继 | `deferred` | 无 | bridge | 内部能力 `201` 尚未迁移。 |
| `internal-202-http-relay` | 路由与访问控制 -> HTTP 中继 | `deferred` | 无 | bridge | 内部能力 `202` 尚未迁移。 |
| `internal-203-wireguard` | 订阅与用户 / 路由 -> WireGuard | `host-integrated` | `net-wireguard` | host + `NET_ADMIN` | 接口由宿主内核拥有。 |
| `internal-204-tun` | 路由与访问控制 -> TUN | `host-integrated` | `net-transparent` | host + `NET_ADMIN` + `/dev/net/tun` | 依赖宿主设备和转发规则。 |
| `internal-205-redirect-tproxy` | 路由与访问控制 -> Redirect/TProxy | `host-integrated` | `net-transparent` | host + `NET_ADMIN` | 依赖宿主路由和防火墙。 |
| `internal-206-routing-rules` | 路由与访问控制 -> DNS/Direct/Block | `deferred` | 无 | bridge | 规则编辑及核心适配尚未迁移。 |
| `internal-207-access-control` | 路由与访问控制 -> Tunnel/dokodemo-door | `deferred` | 无 | bridge | 入站和防火墙合同尚未迁移。 |
| `interactive-menu` | 全部主菜单 | `deferred` | 无 | 宿主 CLI | 已有菜单、状态、启停日志、可信首配、规格编辑/完整旧输入接入、多入口及主副核心共存；完整协议/用户/维护管理、真实发布和双架构连通待验。 |
| `core-lifecycle` | 核心与服务 | `supported` | 核心 profile | 宿主 CLI | 基础 `status/up/down/restart/logs/update/rollback/validate` 已可用，不代表原生全部升级管理。 |
| `core-upgrade-assessment` | 核心与服务 -> Xray / sing-box 生命周期 | `deferred` | 核心 profile | 宿主 CLI | 原生预发布试跑和升级风险扫描尚未迁移。 |
| `geo-data` | 核心与服务 -> Xray Geo 数据 | `deferred` | `core-xray` | bridge | 尚未提供 Geo 更新和自动任务合同。 |
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
