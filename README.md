# padm

padm 是面向 Xray-core / sing-box 的一键安装与日常运维脚本，聚焦三件事：快速部署可用节点、用订阅统一交付客户端配置、把常见运维动作收敛到清晰的菜单入口。

它支持 Reality Vision、Reality XHTTP、传统 TLS 兼容协议、证书申请、订阅发布、用户订阅组、多服务器源同步、流量统计、访问控制和只读验收。

## 新人先看

如果你第一次使用，不需要先理解所有协议，按下面路径走即可：

1. **不知道怎么选**：主菜单选择 `安装与重装`，菜单顶部会说明直连/CDN/无域名分别该选哪一项；不确定时直接选 `推荐直连 Reality Vision`。
2. **直连/有域名**：选择 `安装与重装` -> `推荐直连 Reality Vision`，有域名时把域名作为 entry。
3. **需要 CDN**：选择 `安装与重装` -> `推荐 CDN Reality XHTTP`，脚本会使用 XHTTP XMUX；传统 TLS/WS/gRPC/HTTPUpgrade 仅在兼容旧客户端时使用。
4. **没有域名**：选择 `安装与重装` -> `无域名 Reality`，脚本会生成 Reality 节点。
5. **安装完成**：回到主菜单选择 `订阅与用户` -> `订阅服务` 安装/更新订阅发布服务，再到 `我的订阅` 查看自用链接。
6. **验证服务**：在服务器上运行 `bash shell/validate_install.sh [domain]` 做只读验收。

不要一开始就使用“自定义安装”“CDN节点管理”“多服务器同步”这类高级入口，除非你明确知道客户端需要什么协议和网络形态。

## 菜单总览

padm 主菜单按任务对象分组，一个功能只放在一个入口里：

| 菜单 | 适用场景 |
| --- | --- |
| 安装与重装 | 含新手选择指引；创建或重建节点：推荐直连、推荐 CDN、无域名 Reality、自定义安装、传统 TLS 兼容安装。 |
| 订阅与用户 | 订阅服务、自用链接、给别人开订阅、多服务器同步、流量限额和自动同步。 |
| 协议与入口 | 管理 REALITY、XHTTP、Hysteria2、Tuic、入口端口和 CDN 入口地址。 |
| 站点与证书 | 维护传统 TLS fallback 站点、302、ALPN 诊断/修复和 TLS 证书。 |
| 路由与访问控制 | 管理服务端出站分流、BT 阻断、域名/IP 阻断、直连例外和区域阻断。 |
| 核心与服务 | 管理 Xray-core / sing-box 生命周期、配置校验、Geo 数据、服务启停和日志。 |
| 系统与脚本 | 更新 padm、查看或启用网络优化 / BBR。 |
| 高级/危险操作 | 卸载和 VLESS Encryption 等实验性高风险开关。 |

* **核心生命周期管理**：展示 Xray-core / sing-box 版本、服务状态和配置校验结果；支持稳定版/预发布版升级、稳定版回退、服务控制、日志和 Xray Geo 数据维护。
* **多协议支持**：支持 VLESS、VMess、Trojan、Hysteria2、Tuic、NaiveProxy、AnyTLS 等协议。
* **自动 TLS**：自动申请和续订 SSL 证书。
* **参数化安装**：支持通过命令行参数完成核心、域名、端口、TLS CA、订阅端口等非交互安装配置。
* **交互式管理**：提供中文卡片式菜单管理安装、更新、用户、端口、证书、服务和配置；状态、风险、排障、订阅链接和计划预览统一用状态卡/结果卡展示。
* **订阅支持**：支持 default、Clash Meta 和 sing-box 订阅输出，并可安装订阅发布服务。
* **订阅组管理**：使用 `/etc/padm/subscribe_groups/groups.json` 作为状态真源，管理用户订阅、服务器源、自动同步、流量统计、限额提示、限额计划和状态备份恢复。
* **多服务器源同步**：支持远程服务器源控制通道、健康检查、同步预览、手动同步和定时同步。
* **分流管理**：提供 WARP WireGuard 出站、IPv6 出站、Socks5 中继、DNS 分流和 DNS/hosts 覆盖；sing-box 分流使用 remote rule_set 与 domain_suffix。
* **传统 TLS fallback 维护**：提供静态站点、302 重定向和 ALPN 诊断/修复，用于传统 TLS/fallback 兼容排障。
* **访问控制**：统一管理域名/IP 阻断、直连例外和区域阻断；Xray 使用 routing + blackhole/direct，sing-box 使用 remote rule_set、domain_suffix/domain 和 ip_cidr。
* **网络优化**：查看内核、拥塞控制和 qdisc 状态；推荐启用官方内核自带 BBR + fq，并可单独关闭 padm 写入的 sysctl 配置。
* **BT 下载管理**：支持 Xray-core / sing-box 通过协议嗅探阻断已识别的 bittorrent 流量；加密、混淆或部分 uTP 场景可能无法完全覆盖。

## 快速开始

### 交互式安装

```bash
wget -P /root -N "https://raw.githubusercontent.com/neil1123-vip/padm/main/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

该命令会先下载入口脚本；首次运行时如果本地缺少 `shell/` 模块，入口脚本会自动拉取完整安装包并补齐依赖文件。

安装后，运行以下命令可再次打开管理菜单：

```bash
padm
```

### 非交互安装

查看参数和示例：

```bash
bash install.sh --help
```

VLESS Reality Vision 推荐安装：

```bash
bash install.sh --install-type custom --core xray --protocols 7 --entry-host node.example.com --reality-target www.ibm.com:443 --reality-server-name www.ibm.com --reuse-last no
```

VLESS Reality XHTTP + CDN 推荐安装（内置 XTLS Vision flow 与 XHTTP XMUX）：

```bash
bash install.sh --install-type custom --core xray --protocols 12 --entry-host cdn.example.com --reality-target www.ibm.com:443 --reality-server-name www.ibm.com --reuse-last no
```

传统 TLS 组合安装（兼容旧客户端或迁移时使用；Cloudflare DNS-01 可全程非交互）：

```bash
bash install.sh --install-type install --core xray --domain example.com --port 443 --tls-ca letsencrypt --dns-api yes --dns-api-type cloudflare --dns-api-wildcard yes --cloudflare-api-token <token> --cloudflare-zone-id <zone_id> --reuse-last no
```

Cloudflare 建议使用限制到目标 Zone 的 API Token，至少具备 `Zone:DNS:Edit`；若不传 `--cloudflare-zone-id`，需允许 acme.sh 自动识别 Zone。为避免 token 出现在命令历史中，也可以用环境变量：`PADM_CLOUDFLARE_API_TOKEN=... PADM_CLOUDFLARE_ZONE_ID=... bash install.sh ... --dns-api yes`。

无域名 Reality：

```bash
bash install.sh --install-type reality --core xray --reality-target www.ibm.com:443 --reuse-last no --clean-acme no
```

自定义安装示例：

```bash
bash install.sh --install-type custom --core xray --protocols 7 --entry-host node.example.com --reality-target www.ibm.com:443 --reality-server-name www.ibm.com --reuse-last no --clean-acme yes
```

安装订阅发布服务可使用正式子命令：

```bash
bash install.sh InstallSubscription --subscribe-port 39778 --http-subscribe yes --install-nginx yes
```

也可以在协议安装时追加订阅发布选项：

```bash
--subscribe-port 39778 --http-subscribe no --install-nginx yes
```

## 参数说明

| 参数 | 可选值 | 默认值/未传行为 | 说明 |
| --- | --- | --- | --- |
| `--install-type` | `install`、`custom`、`reality` | 无自动参数时进入交互菜单；传其它安装参数但不传本参数时默认按 `custom` 进入安装流程 | 安装类型。`install` 为传统 TLS 兼容安装；`custom` 为任意组合协议安装；`reality` 为无域名 Reality 快速安装。 |
| `--core` | `xray`、`sing-box`、`1`、`2` | `xray` | 安装核心。`1` 等同 `xray`，`2` 等同 `sing-box`。 |
| `--protocols` | 协议编号，多个用英文逗号分隔 | 无固定默认，按安装类型进入对应协议选择 | 仅自定义安装时使用，例如 `0,1,7`。Xray 支持 `0,1,3,4,7,12`；sing-box 支持 `0,1,3,4,6,7,8,9,10,11,13`。 |
| `--domain` | 域名 | 无固定默认；TLS 安装时必须提供或交互输入；Reality 可作为默认 entry | TLS 证书域名和默认客户端入口地址；不会作为 Reality 伪装目标。 |
| `--entry-host` | 域名或 IP | Reality 默认优先使用 `--domain`，否则使用公网 IP | 客户端实际连接到服务器的地址，订阅中的 `server/address/@host` 会使用该值。 |
| `--reality-target` | `host[:port]` | 未传时进入目标站选择器；优先使用已有实测 A/B 结果，无结果时回退 `www.ibm.com:443`，端口默认 `443` | Reality 伪装目标站，写入 Xray `realitySettings.target` 或 sing-box `tls.reality.handshake`。 |
| `--reality-server-name` | SNI 域名 | 默认等于 `--reality-target` 的 host 或候选目标 SNI | Reality SNI，写入 Xray `serverNames` 或 sing-box `tls.server_name`。 |
| `--port` | 端口号 | `443`；检测到面板域名场景时回车会随机生成 `10000-30000` 端口 | TLS 入口端口。 |
| `--tls-ca` | `letsencrypt`、`zerossl`、`buypass` | `letsencrypt` | 申请证书使用的 CA。 |
| `--dns-api` | `yes`、`no`、`y`、`n` | `no` | 是否使用 DNS API 方式申请证书。 |
| `--dns-api-type` | `cloudflare`、`aliyun`、`1`、`2` | `cloudflare` | DNS API 服务商。 |
| `--dns-api-wildcard` | `yes`、`no`、`y`、`n` | `no` | 是否申请 `*.根域名` 通配符证书。 |
| `--cloudflare-api-token` | Cloudflare API Token | 使用 Cloudflare DNS API 时必填或通过 `PADM_CLOUDFLARE_API_TOKEN` 传入 | 建议创建限制到目标 Zone 的 API Token，至少具备 `Zone:DNS:Edit`；若不传 `--cloudflare-zone-id`，还需允许自动识别 Zone。 |
| `--cloudflare-zone-id` | Cloudflare Zone ID | 可选；也可通过 `PADM_CLOUDFLARE_ZONE_ID` 传入 | 传入后会设置 `CF_Zone_ID`，减少 Zone 查询依赖。 |
| `--aliyun-api-key` | 阿里云 AccessKey ID | 使用 Aliyun DNS API 时必填或通过 `PADM_ALIYUN_API_KEY` 传入 | 用于 `dns_ali`。 |
| `--aliyun-api-secret` | 阿里云 AccessKey Secret | 使用 Aliyun DNS API 时必填或通过 `PADM_ALIYUN_API_SECRET` 传入 | 用于 `dns_ali`。 |
| `--reuse-last` | `yes`、`no`、`y`、`n` | `no`；存在历史配置时建议显式传入，避免自动化误清理 | 是否复用上次安装配置。 |
| `--clean-acme` | `yes`、`no`、`y`、`n` | `no` | 清空上次安装配置时，是否同时清理 acme 证书目录。 |
| `--reality-domain` | `yes`、`no`、`y`、`n` | `no` | 仅选择 Reality 协议时入口是否使用自有域名；新安装推荐直接使用 `--entry-host` 表达入口地址。 |
| `--subscribe-port` | 端口号 | 无固定默认；未传时由端口选择逻辑交互输入或生成可用端口 | 订阅发布服务端口。 |
| `--http-subscribe` | `yes`、`no`、`y`、`n` | `no` | 无 TLS 场景下是否允许 HTTP 订阅。 |
| `--install-nginx` | `yes`、`no`、`y`、`n` | `no` | 订阅发布或反代需要 Nginx 时，是否自动安装 Nginx。 |

## 协议编号

| 编号 | 协议 | 新人建议 |
| --- | --- | --- |
| `0` | VLESS TCP TLS Vision | 传统 TLS 类协议，解决 TLS in TLS，但不解决服务端 TLS 指纹问题；仅在兼容旧客户端或迁移时选择。 |
| `1` | VLESS WS TLS | 传统 TLS/CDN 方案，存在更高识别风险；新建 CDN 优先选 12。 |
| `3` | VMess WS TLS | 兼容旧客户端时选择。 |
| `4` | Trojan TCP TLS | 只在明确需要 Trojan 时选择。 |
| `6` | Hysteria2 | 移动网络或 UDP 场景可考虑。 |
| `7` | VLESS Reality Vision | 新手直连/有域名场景优先选择；启用高级 VLESS Encryption 实验后形成 `VLESS Encryption + XTLS Vision` 组合。 |
| `8` | VLESS Reality gRPC | 需要 gRPC/HTTP2 多路复用且不走 CDN 时作为备选。 |
| `9` | Tuic | UDP/移动网络场景可考虑。 |
| `10` | Naive | 需要 NaiveProxy 时选择。 |
| `11` | VMess HTTPUpgrade TLS | 传统 TLS/CDN 兼容方案；新建 CDN 优先选 12。 |
| `12` | VLESS Reality XHTTP | CDN 场景优先选择；使用 XTLS Vision flow、XHTTP XMUX，多路复用和 CDN 兼容更好；启用高级 VLESS Encryption 实验后形成 `VLESS Encryption + XTLS Vision + XHTTP XMUX` 组合。 |
| `13` | AnyTLS | sing-box AnyTLS 场景使用。 |


## 推荐协议能力对照

| 脚本协议名 | 解决 TLS in TLS | 解决指纹问题 | 自带多路复用 | 支持 CDN | 推荐场景 |
| --- | --- | --- | --- | --- | --- |
| VLESS TCP TLS Vision | ✅ | ❌ | ❌ | ❌ | 传统 TLS 兼容/迁移。 |
| VLESS Reality Vision | ✅ | ✅ | ❌ | ❌ | 新手直连、有域名或无域名 Reality 首选；高级实验可叠加 VLESS Encryption。 |
| VLESS Reality gRPC | ❌ | ✅ | ✅ HTTP/2 | ❌ | 需要 gRPC/HTTP2 多路复用但不走 CDN 时备选。 |
| VLESS Reality XHTTP | ✅ | ✅ | ✅ XMUX | ✅ | CDN 场景首选；高级实验可叠加 VLESS Encryption。 |

## XHTTP 管理

安装 `12.VLESS Reality XHTTP` 后，可在主菜单 `协议与入口` -> `XHTTP 管理` 调整 XHTTP 行为。管理入口按风险分层：

1. **普通设置**：查看当前配置、选择场景预设、切换 `auto` / `packet-up` / `stream-up`，并查看 CDN/H3 使用说明。
2. **高级设置**：调整 XMUX、path/host、header/packet/stream 参数；写入前会保留推荐默认值作为回退参照。
3. **实验功能**：配置或关闭上下行分离 `downloadSettings`，适合明确需要独立下行链路的高级场景。

默认推荐值面向日常和 CDN 使用：`mode=auto`，`xmux.maxConcurrency=16-32`，`hMaxRequestTimes=600-900`，`hMaxReusableSecs=1800-3000`。测速或排障时可切到单并发预设；兼容性优先时可切 `packet-up`，链路确认支持流式上行时再考虑 `stream-up`。每次修改都会先写临时配置，执行 Xray 配置校验，通过后 reload core 并刷新订阅；校验失败会自动回滚并提示日志路径。

`协议与入口` -> `CDN 入口管理` 只负责订阅入口地址覆盖：可把客户端连接地址改为 CDN CNAME、优选 IP 或自有域名，并为逗号分隔的多个入口生成多条节点；XHTTP 的 mode、XMUX、path/host 等参数仍在 `协议与入口` -> `XHTTP 管理` 中调整，避免入口地址和协议参数混在一起。

## VLESS Encryption 高级实验

主菜单 `高级/危险操作` -> `VLESS Encryption 实验` 可为 Xray Reality 节点启用实验加密。脚本调用 Xray 自带 `xray vlessenc` 生成参数，当前落地组合为：

- **直连/常规 Reality Vision**：`VLESS Encryption + XTLS Vision`。
- **CDN / Reality XHTTP**：`VLESS Encryption + XTLS Vision + XHTTP XMUX`。

启用时如果检测到 `12.VLESS Reality XHTTP`，会优先把 `decryption` 写入 XHTTP 配置；否则写入 `7.VLESS Reality Vision` 配置。default VLESS 分享链接会携带 `encryption=...` 与 `flow=xtls-rprx-vision`；Clash/Mihomo/sing-box 订阅暂不写入实验 encryption 字段，避免客户端兼容性误导。该功能仍属于高级实验，不建议新手默认开启。

## Reality 参数语义

Reality 新模型中，入口地址、伪装目标和 SNI 是三个不同概念：

| 概念 | 含义 | 对应输出/配置 |
| --- | --- | --- |
| entry | 客户端实际连接服务器的地址 | 订阅链接中的 `@host`、Clash Meta 的 `server`、sing-box profile 的 `server` |
| Reality target | Reality 伪装访问的真实目标站 | Xray `realitySettings.target`；sing-box `tls.reality.handshake.server/server_port` |
| Reality SNI | Reality 握手使用的 SNI | Xray `realitySettings.serverNames`；sing-box `tls.server_name`；订阅中的 `sni/servername` |

常见配置是：客户端连接自有域名 `node.example.com`，Reality 伪装目标使用 `www.ibm.com:443`，SNI 使用 `www.ibm.com`。

安装时未传 `--reality-target` 会进入 Reality 目标站选择器：自动选择会优先使用已有 A/B 级实测结果；没有实测结果时实测内置推荐候选并选择最优 A/B 目标，仍无可用结果时回退默认稳定目标 `www.ibm.com:443`。也可从内置候选池选择、手动输入或随机候选。内置候选池只是实测来源，不等于离线推荐度；Cloudflare/Fastly/Akamai/Apple 等不推荐目标已从候选池移入黑名单，不参与扫描和随机候选。

安装后可在主菜单 `协议与入口` -> `REALITY 管理` -> `目标站管理` 查看当前目标、运行 `xray tls ping` 检测、实测内置目标库、扫描本机附近网段、查看/切换检测结果或查看 PQC/ML-DSA-65 状态。检测结果统一保存到 `/etc/padm/reality_targets_results.tsv`，字段包括目标、SNI、IP/ASN、网络匹配、CDN 风险、评分、是否支持 `X25519MLKEM768`、TLS1.3、证书链长度和检测时间。查看/切换检测结果支持按 A、B、A/B、同 ASN、同提供商、同网络、C、失败或全部筛选，默认每页 10 条，支持 `n`/`p` 翻页、`f` 重新筛选、`r` 返回；A/B 级结果可直接输入本页编号切换。评分含义为：`A` 表示 TLS1.3 + `X25519MLKEM768` 可用且证书链长度大于 3500；`B` 表示 TLS1.3 + `X25519MLKEM768` 可用但证书链长度未超过 3500 或未知；`C` 表示 TLS1.3 可用但未检测到 `X25519MLKEM768`；`FAIL` 表示未检测到可用 TLS1.3 或二次检测失败。

RealiTLScanner 是高级功能：脚本会提示其作者建议本地运行，云端扫描可能导致 VPS 被标记；确认后可选择默认 `/24（254 台）`、快速 `/28（14 台）`、扩大 `/23（510 台）`、`/22（1022 台）`、`/21（2046 台）`、`/20（4094 台）`、`/19（8190 台）`、`/18（16382 台）` 或手动输入范围。缺少 `git` 或 Go 时会按系统包管理器自动补齐依赖。扫描阶段和导入二次检测阶段会按 10 秒节流显示当前范围/目标和耗时。导入时会过滤黑名单、通配证书、纯 IP、`localhost`、`invalid.invalid`、占位 CN 和 Cloudflare Origin Certificate 等无效证书名，并用 `xray tls ping -ip <扫描IP> <域名:443>` 二次检测后写入统一结果表。

## 传统 TLS fallback 维护

主菜单 `站点与证书` -> `传统 TLS fallback 维护` 只服务于传统 TLS 类协议：当访问没有命中代理协议时，Nginx fallback 会展示本机静态页面或 302 跳转。脚本内置 20 个轻量模板，安装或更换时会随机化标题、行业文案、按钮、卡片内容、页脚和主题色，增加站点外观差异。

维护入口还提供 **ALPN 诊断/修复**：脚本会检查传统 TLS fallback 入站、`fallbacks[].alpn=h2` 和 Nginx h2 fallback 是否匹配；存在 h2 fallback 时，推荐修复会把 Xray 入站 TLS ALPN 设置为 `["h2","http/1.1"]`。手动设置仅用于旧客户端兼容排障。每次写入后都会执行 `xray -test -confdir /etc/padm/xray/conf`，失败会自动回滚并提示 `/tmp/padm-alpn-xray-test.log`。

VLESS Reality Vision、Reality gRPC 和 Reality XHTTP 不依赖这个本机静态站点或 ALPN 维护入口。Reality 的伪装由外部 `target` 和 `SNI` 完成，认证失败的探测流量会被转发到目标站；因此新手安装 Reality 时无需先配置主菜单 `站点与证书`。

如果只是需要自用直连，优先按 Reality Vision 示例安装；只有在继续使用 VLESS TCP TLS Vision、WS TLS、gRPC TLS、Trojan TLS 等传统 TLS/fallback 方案，或确实要在本机展示网站时，再配置静态站点或 ALPN。

## 访问控制

主菜单 `路由与访问控制` -> `访问控制` 统一管理域名/IP 阻断、直连例外和区域阻断。可查看当前 Xray / sing-box 规则状态，按类型添加阻断或直连例外，也可以只移除域名阻断、IP/CIDR 阻断、直连例外、区域阻断或全部访问控制。

域名规则支持 `geosite:`、`domain:`、`full:`、`keyword:` 和普通域名。Xray 具体域名会写为 `domain:example.com`，不再生成宽泛的 `regexp:.*example.com.*`；sing-box 使用 `SagerNet/sing-geosite` remote SRS，普通域名写入 `domain_suffix`，`full:` 写入 `domain` 精确匹配。IP 规则支持 IPv4、IPv6、CIDR 和 `cn`，其中 `cn` 会映射到 Xray `geoip:cn` 或 sing-box 远程 GeoIP SRS。

直连例外会放在阻断规则之前，适合系统更新、证书签发或必须直连的客户端服务。区域阻断策略属于危险操作，可分别应用 `geosite:cn`、`geoip:cn` 或二者组合，可能影响系统更新、证书申请和应用连接。访问控制写入前会快照相关规则文件，写入后执行 Xray `-test` 和 sing-box `merge` 校验；失败会自动回滚，并提示 `/tmp/padm-access-xray-test.log` 或 `/tmp/padm-access-sing-box-test.log`。


## Reality 443 共存分流

只安装 Reality Vision 时通常只需要一个入口端口，默认推荐 `443`，并不需要本机再准备一个伪装站点。Reality 的伪装由外部 `target` 和 `SNI` 完成；只有同一台机器还要在 `443` 上提供真实网站时，才需要在主菜单 `协议与入口` -> `REALITY 管理` 中使用“配置 443 共存分流”：

1. Nginx stream 监听公网 `443`。
2. 真实网站域名显式转发到网站后端，例如 `127.0.0.1:8443`。
3. 其他 SNI 默认转发到 Xray Reality 后端，例如 `127.0.0.1:2443`。
4. 订阅输出仍然使用 `entry-host:443`，Reality SNI 仍然保持伪装目标站。

该模式的关键点是：Nginx stream 看到的是 TLS ClientHello 中的 SNI，而 Reality 客户端发出的 SNI 通常是外部伪装目标站，不是 `entry-host`。因此脚本只让用户填写“哪些域名是真网站”，剩余 SNI 全部默认转给 Reality。新人或不需要网站共存时不建议启用；`443` 被占用时也可以直接把 Reality 入口端口改为 `8443` 或随机高位端口。

## 核心生命周期管理

主菜单 `核心与服务` 会先展示 Xray-core / sing-box 的当前版本、最新稳定版、最新预发布版、服务状态、配置校验结果和 Xray Geo 数据状态。

升级或回退核心时，脚本会先下载目标版本到临时目录，用目标二进制校验当前配置；校验通过后才替换 `/etc/padm/xray/xray` 或 `/etc/padm/sing-box/sing-box` 并重启服务。若新核心启动失败，会尝试恢复旧二进制。Xray 使用 `xray -test -confdir /etc/padm/xray/conf` 校验；sing-box 会先合并配置，再执行 `sing-box check -c /etc/padm/sing-box/conf/config.json`。

Xray `geosite.dat` / `geoip.dat` 维护已收敛到“配置校验与数据维护”入口；服务启动、停止、重启和日志入口统一在 core 管理内处理。

## 网络优化

主菜单 `系统与脚本` -> `网络优化` 用于查看和调整服务器 TCP 网络优化状态。状态页会显示当前内核、当前拥塞控制、可用拥塞控制、当前默认 qdisc、BBR 是否可用，以及 padm 是否已写入 `/etc/sysctl.d/99-padm-bbr.conf`。

推荐入口是 **启用官方 BBR + fq**：脚本只启用当前内核提供的 `bbr`，并写入：

```conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

写入前会检查 `bbr` 是否可用；如果未列出，会尝试 `modprobe tcp_bbr`。仍不可用时只提示当前内核不支持 BBR，不会自动安装第三方内核或修改引导。关闭入口只删除 padm 自己写入的 `/etc/sysctl.d/99-padm-bbr.conf`，并尝试恢复启用前的拥塞控制和 qdisc，不会改动用户其它 sysctl 文件。

## 订阅管理教程

主菜单 `订阅与用户` 使用订阅组模型，并按任务流组织：

1. **订阅服务**：安装/更新订阅发布服务，查看本机被控凭据和订阅服务状态。
2. **我的订阅**：查看/刷新自用订阅链接、可用服务器和自用流量。
3. **给别人开订阅**：一键创建用户订阅并同步，生成托管账号 `sub_<ID>`，再查看用户订阅链接。
4. **多服务器订阅**：本机作为主控，管理远端被控服务器、被控凭据、健康检查和同步结果。
5. **流量与限额**：明确分开刷新流量和查看流量，查看/执行限额计划。
6. **自动同步与备份**：管理自动同步、手动同步、同步计划和状态备份恢复。

给用户创建订阅的推荐流程：

1. `给别人开订阅` -> `一键新建并同步订阅`，ID 使用英文、数字或短横线，例如 `team-a`。
2. 按向导设置授权服务器（默认 `main`）和流量上限。
3. 确认摘要后立即执行同步，托管账号 `sub_<ID>` 会写入核心配置。
4. 同步完成后查看/刷新用户订阅链接。

多服务器同步推荐流程：

1. 在被控服务器进入 `订阅服务`，安装/更新订阅发布服务，并复制“本机被控凭据”。
2. 回到主控服务器进入 `多服务器订阅` -> `添加/移除被控服务器`，粘贴被控凭据并设置本地别名。
3. `测试被控连接`，成功后查看同步计划或立即执行同步。
4. 被控地址、订阅端口和 Token 都包含在被控凭据中，控制通道强制 HTTPS。

主菜单和订阅管理输出使用卡片式展示：订阅链接会显示账号、订阅地址和在线二维码；用户订阅、服务器源、健康检查、同步计划、限额计划和流量统计会以结果卡或计划卡展示。HTTP 订阅、Reality 目标站、XHTTP 高级参数、DNS/端口/Nginx 排障等高风险或需要用户处理的内容会以风险卡/排障卡显示，便于区分普通状态和需要行动的提示。

## 验收

安装后可运行只读验收：

```bash
bash shell/validate_install.sh [domain]
```

需要检查公网 HTTP/HTTPS/TLS 可达性时使用：

```bash
bash shell/validate_install.sh --online example.com
```

## 许可证

本项目根据 [AGPL-3.0 许可证](LICENSE) 授权。
