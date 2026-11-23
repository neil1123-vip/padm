# 🧭 协议与入口

[🏠 返回首页](../README.md#文档导航)

按连接场景选择协议。部署后从 `协议与入口` 调整 Reality、XHTTP 和 CDN，或从 `站点与证书` 维护传统 TLS 与本机站点。

[协议选择](#协议选择) · [Reality](#reality-语义) · [XHTTP 与 CDN](#xhttp-与-cdn) · [传统 TLS 与本机站点](#传统-tls-与本机站点) · [高级实验](#高级实验)

## 协议选择

按实际连接场景选协议。表中的数字是命令行协议 ID。

| 目标 | 推荐协议 | 说明 |
| --- | --- | --- |
| 🧭 直连或自用 | `1` VLESS Reality Vision | 使用 Reality 目标站，可通过自有域名或服务器 IP 连接。 |
| 🌐 CDN / 反代 | `2` VLESS Reality XHTTP | 由 Xray 提供 XHTTP 和 XMUX，客户端需支持 XHTTP。 |
| 📍 没有域名 | 无域名 Reality | 安装菜单的第 `3` 项，使用服务器 IP 或自定义入口。 |
| 🛡️ TLS 指纹抗性 | `5` NaiveProxy | 使用 sing-box，需要真实域名和可信证书。 |
| 📶 UDP、移动网络或弱网 | `3` Hysteria2 | 需要 UDP 直达本机，可按需启用端口跳跃。 |
| 🔐 AnyTLS | `4` AnyTLS | 使用 sing-box，需确认客户端兼容。 |
| 🧰 兼容或迁移 | 高级协议 `21..31` | 按旧客户端、存量 CDN 或传统 TLS 的要求选择。 |

协议能力库统一记录核心支持、Nginx 拓扑和订阅格式。`--protocols` 和订阅同步使用 `category=node` 的公开 ID，交互安装使用屏幕上的编号。无域名安装菜单的第 `3` 项与命令行的 Hysteria2 ID `3` 各自对应不同入口。

### 推荐公网节点能力

| ID | 能力 | 项目生成核心 | Nginx 模式 | UDP | CDN | 推荐场景 |
| --- | --- | --- | --- | --- | --- | --- |
| `1` | VLESS Reality Vision | Xray / sing-box | `none` | 否 | 否 | 新手直连、有域名或无域名 Reality 首选。 |
| `2` | VLESS Reality XHTTP | Xray | `none` | 否 | 条件支持 | 新建 CDN / 反代首选；XHTTP 在本项目中是 Xray-only。 |
| `3` | Hysteria2 | sing-box | `none` | 是 | 否 | 移动网络、UDP、弱网和端口跳跃场景；节点流量不经过 CDN/Nginx。 |
| `4` | AnyTLS | sing-box | `none` | 否 | 否 | 明确需要 sing-box AnyTLS 且客户端支持时选择。 |
| `5` | NaiveProxy | sing-box | `none` | 否 | 否 | 明确需要 TLS 指纹抗性且有真实域名和可信证书时选择。 |

### 高级公网节点能力

gRPC、WebSocket 和 HTTPUpgrade 仍可在自定义安装中选择，主要用于兼容和迁移。新建直连节点可优先选择 Reality Vision，CDN 或反代可优先选择 Reality XHTTP。

| ID | 能力 | 项目生成核心 | Nginx 模式 | 使用边界 |
| --- | --- | --- | --- | --- |
| `21` | VLESS WS TLS | Xray | `http_front` | WebSocket 属高级兼容方案；新建 CDN 优先选 `2`。 |
| `22` | VMess WS TLS | Xray | `http_front` | VMess 与 WS 均为高级兼容方案；新建优先选 `1` 或 `2`。 |
| `23` | VMess HTTPUpgrade TLS | Xray / sing-box | `http_front` | HTTPUpgrade 属高级兼容方案；新建 CDN 优先选 `2`。 |
| `24` | VLESS gRPC TLS | Xray | `grpc_front` | gRPC 有主动探测与 fallback 限制；新建优先选 `2`。 |
| `25` | Trojan gRPC TLS | Xray | `grpc_front` | 仅在明确需要 Trojan + gRPC 时使用；可考虑 `4` 或 `2`。 |
| `26` | VLESS Reality gRPC | Xray / sing-box | `none` | Reality gRPC 是高级直连方案；新建优先选 `1` 或 `2`。 |
| `27` | VLESS TCP TLS Vision | Xray | `fallback_backend` | 传统 TLS/fallback 迁移路径；新建直连优先选 `1`。 |
| `28` | Trojan TCP TLS direct | Xray / sing-box | `none` | 传统 TLS 协议，仅在旧客户端或明确需求下选择。 |
| `29` | Trojan TCP TLS fallback | Xray | `fallback_backend` | fallback 只适用于 TCP+TLS；新建优先考虑 `4` 或 `1`。 |
| `30` | Shadowsocks | sing-box | `none` | 高级兼容项，不作为默认公网节点推荐。 |
| `31` | TUIC | sing-box | `none` | UDP/弱网高级项；新装优先引导使用 `3`。 |

### 内部服务端能力

内部能力只进入路由、中继、透明代理、访问控制或管理菜单，不能作为公网节点安装输入：`201` Socks 中继、`202` HTTP 中继、`203` WireGuard、`204` TUN、`205` Redirect/TProxy、`206` DNS/Direct/Block、`207` Tunnel/dokodemo-door。

### 上游已知但本项目暂不生成的能力

`301..309` 仅用于 `--list-capabilities` 和文档说明，不生成安装入口，包括 Xray Hysteria2 inbound、Hysteria v1、ShadowTLS、mKCP 组合、Cloudflared inbound、Selector、URLTest、Tor outbound、SSH outbound，以及纯 transport/security 说明项。

### Nginx 拓扑

| `nginx_mode` | 含义 | 适用能力 |
| --- | --- | --- |
| `none` | 核心直接监听公网并处理节点流量。 | Reality Vision、Reality XHTTP、Hysteria2、AnyTLS、NaiveProxy、Reality gRPC、Trojan direct、Shadowsocks、TUIC。 |
| `http_front` | Nginx HTTP/1.1 反代，显式处理 `Upgrade` / `Connection`。 | WS / HTTPUpgrade 能力 `21..23`。 |
| `grpc_front` | Nginx HTTP/2 + `grpc_pass` 反代。 | gRPC TLS 能力 `24..25`。 |
| `xhttp_front` | 预留给显式 XHTTP TLS/CDN/反代能力；默认不套到 Reality XHTTP。 | 当前无默认公网节点使用。 |
| `fallback_backend` | Xray fallback 后端，只允许 TCP+TLS 能力使用。 | `27`、`29`。 |
| `acme_only` | Nginx 可服务证书申请或订阅发布，不代表节点流量经过 Nginx。 | 证书与订阅服务。 |

sing-box 订阅输出中的 `utls.fingerprint=chrome` 是客户端兼容/模拟选项，不是抗封锁保证。需要抗 TLS 指纹识别时，优先考虑 Reality Vision、Reality XHTTP 或 NaiveProxy。

## Reality 语义

配置 Reality 时，先确定客户端入口，再选择目标站与 SNI。

| 概念 | 含义 | 出现位置 |
| --- | --- | --- |
| 📍 entry | 客户端实际连接到你的服务器的地址 | 订阅链接 `@host`、Clash `server`、sing-box `server` |
| 🎭 Reality target | Reality 伪装访问的外部真实 HTTPS 站点 | Xray `realitySettings.target`；sing-box `tls.reality.handshake` |
| 🧾 Reality SNI | Reality 握手使用的 SNI | Xray `serverNames`；sing-box `tls.server_name`；订阅 `sni/servername` |

例如，客户端连接 `node.example.com`，target 填写已通过检测的 `target.example.com:443`，SNI 填写 `target.example.com`。

Reality Vision、Reality XHTTP 和 Reality gRPC 均不申请本机 TLS 证书；纯 Reality 安装不创建或清理站点，不操作 ACME/Cron，也不停止、启动或重载 Nginx。`--reality-domain yes` 是严格域名模式，只允许单选 Reality Vision `1`，并校验 entry 域名及 DNS；协议 `2`、`26` 或任何多选组合会在安装依赖和写配置前拒绝。

**📍 入口与端口。** 客户端入口依次取 `--entry-host`、`--domain`、`/etc/padm/reality_entry_host`、`currentHost` 或公网 IP。普通单选 Reality 依次取 `--port`、历史端口或 `443`。安装多个协议时，各协议使用自己的端口。启用 443 共存后，客户端连接记录的公网端口，核心继续使用记录的内部端口。

**🎭 选择目标。** 交互安装时，`1. 检测候选后选择` 先复测候选，再让你从 `cdn_risk=no` 的 A 级结果中选取。`2. 手动输入` 接受 `host[:port]`，默认端口为 `443`，留空取消。非交互安装优先用 `--reality-target` 或已有目标。两者均缺失时，脚本从本次复测通过的 A 级推荐候选中随机选择。缺少 Xray、检测失败或没有符合条件的结果时停止。

**🔎 写入前检测。** 脚本复测目标的全部 A / AAAA 地址，并取最差结果。自动候选要求 `cdn_risk=no` 且为 A 级。手动输入允许无 CDN 风险的 A、B、C 级，B/C 级会提示风险。检测当前目标时，留待用户决定是否切换。

- 地址属于 AS13335 或能响应 `cloudflare.com` SNI 时，标记为 `cloudflare_relay`。
- CNAME 指向已知 CDN 边缘域名，或 ASN / 组织属于已知专属 CDN 时，标记为 `cdn_edge`。
- DNS、ASN 或 TLS 探测不完整时，标记为 `unknown`。

上述三类结果均会被拒绝。`java.com`、`nodejs.org`、`riotcdn.net` 及其子域名始终由静态黑名单拦截，适用于候选刷新、扫描导入、手动或自动选择及 Docker 部署。

内置清单维护 25 个实测为 `cdn_risk=no` 且评分为 A 的推荐候选。2026-11-23 复测时，这 25 个域名均仅返回 IPv4 地址，分属 25 个 ASN。安装时仍按部署网络的实际 DNS 和 TLS 结果筛选。已知 CDN/边缘代理域名由独立黑名单维护，用于运行时过滤、审计和黑名单展示。候选筛选统一按关键词处理，`dev`、`developer`、`开发者` 是同一筛选别名。

**📊 目标库。** `/etc/padm/reality_targets_results.tsv` 使用 16 列 TSV，兼容旧 15 列记录。新增末列显示实测 IP 的英文地理位置，例如 `Los Angeles, United States`。批量写入按完整 IP 复用查询缓存，只查询缺少缓存的地址。`PADM_REALITY_SECONDARY_JOBS` 默认并行 8 个请求，最多 16 个。城市缺失时显示区域或国家，查询失败时显示 `Unknown`，评分和切换照常进行。

目标库仅保留最新实测仍为 `cdn_risk=no`、评分为 A 且未命中黑名单的目标。评级下降、出现风险、探测失败或结果未知时会移除旧记录，空批次也会清理旧格式的风险条目。评分考虑 TLS 1.3、`X25519MLKEM768` 和证书链长度。可选目标按网络关系（`same_asn > same_provider > different_network > unknown`）、证书链长度和检测时间排序。

在 `协议与入口 → REALITY 管理 → 目标站管理` 可检测当前目标、刷新目标库、运行 RealiTLScanner、切换 A 级目标并查看 PQC / ML-DSA-65 状态。刷新时默认选择 `目标库 + 推荐候选`，也可选 `推荐候选`。切换成功后才更新当前目标状态。443 共存分流在 `REALITY 管理` 单独配置。

> [!WARNING]
> **扫描风险：** RealiTLScanner 是高级功能，云端扫描可能导致 VPS 被标记；脚本会在执行前提示确认。

## XHTTP 与 CDN

安装 VLESS Reality XHTTP（协议 ID `2`）后，从 `协议与入口 → XHTTP 管理` 调整传输参数。

| 层级 | 内容 |
| --- | --- |
| ✅ 普通设置 | 查看当前配置、选择场景预设、切换 `auto` / `packet-up` / `stream-up`。 |
| 🧪 高级设置 | 调整 XMUX、path/host、首部开关和四项原生 packet/stream limits。 |
| ⚠️ 实验功能 | 配置或关闭上下行分离 `downloadSettings`。 |

日常及 CDN 场景的推荐值为 `mode=auto`、`xmux.maxConcurrency=16-32`、`hMaxRequestTimes=600-900`、`hMaxReusableSecs=1800-3000`。修改时先写入临时配置并用 Xray 校验，失败时回滚并显示日志路径。

XHTTP 在本项目中由 Xray 生成；sing-box 当前没有 XHTTP transport，因此不会输出 sing-box XHTTP 客户端配置。

🌐 `协议与入口 → CDN 入口管理` 可覆盖订阅里的客户端连接地址，例如 CDN CNAME、优选 IP 或多个入口。mode、XMUX、path 和 host 属于 XHTTP 传输设置。

## 传统 TLS 与本机站点

`站点与证书 → 传统 TLS fallback 维护` 管理未匹配代理协议的请求。Nginx 可返回本机静态页面或 302 重定向。

- 🖼️ 优先导入自有静态网站；没有现成网站时，可用 `notes`、`photos`、`docs` 三套内置布局初始化，包含文章、关于页、本地图片和 404 页面。
- ↪️ 302 重定向维护。
- 🔎 ALPN 诊断/修复，检查 Xray fallback、`fallbacks[].alpn=h2` 和 Nginx h2 fallback 是否匹配。
- ✅ 写入后执行 `xray -test -confdir /etc/padm/xray/conf`，失败自动回滚。

本机站点适用于 VLESS TCP TLS Vision、WS TLS、gRPC TLS、Trojan TLS 等传统 TLS/fallback 部署。Reality Vision、Reality gRPC 和 Reality XHTTP 使用外部目标站及 SNI。

**🖼️ 导入自有站点。** 在独立 Linux 目录中准备完整网站，例如 `/srv/own-site/`，然后进入 `站点与证书 → 本地静态站点` 选择 `import`。菜单也可独立于 Xray 使用。脚本会将文件原样复制到 `nginxStaticPath`（默认 `/usr/share/nginx/html/`）。源目录必须含可读的 `index.html`，并与目标目录分开。路径和文件名仅支持 `A-Za-z0-9_./-`，点文件、链接、特殊文件、`check` 和 `static-site.json` 会被拒绝。修改源目录后需重新导入。

**💾 站点备份。** 导入和内置布局都先暂存、再原子替换，失败时恢复网页与状态。自动安装会保留已有或修改过的网页。从菜单手动更换这类网站时，私有备份保存在 `/etc/padm/static-site-backups/`。未修改的内置主题仅创建回滚所需的临时备份。站点归属记录在 `/etc/padm/static-site.json`，卸载时仅清理归属和内容摘要均匹配的内置站点。Nginx 优先使用自有网站的 `404.html`，否则使用默认页面，两者均返回 HTTP 404。

内置布局可配置站名，默认站名与配色固定，同主题重装保持已保存的值。安装后应持续维护真实文章、图片、导航和内页；整套内容与配置可在独立目录准备后导入。同一布局仍共用 HTML/CSS 结构，随机外观或内容差异都不能提供抗识别保证。

原生 Hysteria2 的“认证失败伪装”可直接填写 `file:///srv/own-site/` 使用独立自有网站目录，或填写受你控制的网站 `http://`、`https://` URL 进行反向代理。`local` 使用已有本机网页，`notes`、`photos`、`docs` 初始化内置布局；文件目录须满足上述可读首页及内容限制。sing-box 文件服务的未知路径使用 Go 默认 404 文本。启用混淆后，普通浏览器不能以标准 HTTP/3 访问该入口。Docker 仅支持受管静态网页加 `local`，使用固定只读目录并要求关闭混淆。协议细节参见 [Hysteria2 协议](https://v2.hysteria.network/docs/developers/Protocol/) 与 [sing-box Hysteria2 入站](https://sing-box.sagernet.org/configuration/inbound/hysteria2/)。

## 高级实验

⚠️ 从 `高级与危险操作 → VLESS Encryption 实验` 为 Xray Reality 节点启用实验加密。脚本使用 `xray vlessenc` 生成参数。

- 🧭 Reality Vision：`VLESS Encryption + XTLS Vision`
- 🌐 Reality XHTTP：`VLESS Encryption + XTLS Vision + XHTTP XMUX`

> [!CAUTION]
> 默认 VLESS 链接和 Mihomo（原 Clash.Meta）订阅会携带实验加密参数。使用 Mihomo 时需要 v1.19.13 或更新版本。sing-box 订阅会省略该参数，请先确认客户端兼容性再启用。

安装命令和协议参数见 [📦 原生版安装与参数](native-install.md)。
