<h1 align="center">padm</h1>

<p align="center"><strong>✨ 面向 Xray-core / sing-box 的一站式安装与长期运维脚本</strong></p>
<p align="center">🚀 节点安装 · 🔗 订阅发布 · 🌐 多服务器协同 · 🧭 路由控制 · 🔐 证书维护 · ⚙️ 核心升级</p>
<p align="center"><a href="documents/en/README_EN.md">🌍 English</a></p>

<p align="center">
  <a href="#快速选择">🚀 快速选择</a> ·
  <a href="#安装">📦 安装</a> ·
  <a href="#docker-版">🐳 Docker 版</a> ·
  <a href="#协议选择">🧭 协议选择</a> ·
  <a href="#订阅与用户">🔗 订阅与用户</a>
  <br>
  <a href="#路由与访问控制">🧱 路由控制</a> ·
  <a href="#核心与服务">⚙️ 核心服务</a> ·
  <a href="#参数参考">📋 参数参考</a> ·
  <a href="#验收与回归">✅ 验收回归</a>
</p>

---

> **✨ 一句话选协议**
>
> 🧭 直连/有域名 `Reality Vision` · 🌐 CDN/反代 `Reality XHTTP`
>
> 📍 无域名 `Reality` · 🛡️ TLS 指纹抗性 `NaiveProxy`

## 快速选择

第一次使用时，不需要先理解全部协议。运行脚本后按这个路径走：

| 场景 | 菜单入口 | 说明 |
| --- | --- | --- |
| 🧭 不知道选什么 | `安装与重装` -> `推荐直连 Reality Vision` | 新手首选，配置少，适合直连或自有域名入口。 |
| 🌐 需要 CDN / 反代 | `安装与重装` -> `推荐 CDN Reality XHTTP` | 新建 CDN 场景优先选它，使用 XHTTP 与 XMUX。 |
| 📍 没有域名 | `安装与重装` -> `无域名 Reality` | 使用服务器 IP 或自定义 entry-host，不需要本机证书。 |
| 🛡️ 需要 TLS 指纹抗性 | `安装与重装` -> `TLS 指纹抗性 NaiveProxy` | 需要真实域名和可信证书，不是无域名 Reality 的替代品。 |
| 🧰 已有旧客户端或迁移需求 | `安装与重装` -> `传统 TLS 兼容安装` | 仅在明确需要 WS/TLS、VMess、Trojan 等旧形态时使用。 |
| 🔗 安装完成后拿订阅 | `订阅与用户` | 未初始化时可选择本机单独使用、这台作为主控或这台作为被控。 |

> [!TIP]
> **第一次使用：** 优先走上面的推荐路径。只有明确了解客户端、网络和运维目标时，再进入自定义协议组合、CDN 入口细调、多服务器同步或危险实验开关。

## 安装

### 交互式安装

```bash
wget -O /root/install.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/install.sh" && chmod 700 /root/install.sh && /root/install.sh
```

首次运行时，如果入口脚本检测到本地缺少 `shell/`、`documents/`、`assets/` 或模块 manifest 不匹配，会自动下载完整仓库归档并补齐模块。

怀疑本地模块仍是旧版本时，可以强制刷新模块：

```bash
wget -O /root/install.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/install.sh" && chmod 700 /root/install.sh && PADM_FORCE_SCRIPT_MODULE_REFRESH=1 /root/install.sh
```

安装后再次打开管理面板：

```bash
padm
```

### 非交互安装

查看脚本当前支持的参数和示例：

```bash
bash install.sh --help
```

以下命令中的 `target.example.com` 仅为占位符，必须替换为通过实时检测的 Reality 目标站。

推荐直连 Reality Vision：

```bash
bash install.sh --install-type custom --core xray --protocols 1 --entry-host node.example.com --reality-target target.example.com:443 --reality-server-name target.example.com --reuse-last no
```

推荐 CDN Reality XHTTP：

```bash
bash install.sh --install-type custom --core xray --protocols 2 --entry-host cdn.example.com --reality-target target.example.com:443 --reality-server-name target.example.com --reuse-last no
```

无域名 Reality：

```bash
bash install.sh --install-type reality --core xray --reality-target target.example.com:443 --reuse-last no
```

NaiveProxy：

```bash
bash install.sh --install-type custom --core sing-box --protocols 5 --domain naive.example.com --port 443 --reuse-last no
```

多个协议可以逗号分隔，例如 `--protocols 1,2,21`。当前公开 ID 是唯一安装入口，旧版 `0..13/20` 编号已废弃；已有旧配置需要重新选择当前公开 ID 后重装或调整。

传统 TLS 兼容安装，Cloudflare DNS-01 可全程非交互：

```bash
bash install.sh --install-type install --core xray --domain example.com --port 443 --tls-ca letsencrypt --dns-api yes --dns-api-type cloudflare --dns-api-wildcard yes --cloudflare-api-token <token> --cloudflare-zone-id <zone_id> --reuse-last no
```

Cloudflare 建议使用限制到目标 Zone 的 API Token，至少具备 `Zone:DNS:Edit`。为避免 token 出现在命令历史中，也可以用环境变量：

```bash
PADM_CLOUDFLARE_API_TOKEN=<token> PADM_CLOUDFLARE_ZONE_ID=<zone_id> bash install.sh --install-type install --core xray --domain example.com --dns-api yes --dns-api-type cloudflare
```

已有节点只补装或刷新 HTTPS 订阅发布服务：

```bash
bash install.sh InstallSubscription --domain subscribe.example.com --subscribe-port 39778 --install-nginx yes
```

订阅发布独立管理自己的 TLS 域名和证书，不会自动使用 Reality entry 或传统 TLS 域名。已有匹配且可用的证书会直接复用；缺少证书时可继续传入上面的 `--tls-ca`、`--dns-api` 和服务商凭据参数完成签发。自定义证书可复用，但需自行续期。

## Docker 版

Docker 版用于把核心、Nginx、订阅和运维任务与宿主系统隔离。它和原生版是两条独立且互斥的入口：原生版使用 `install.sh` / `padm`，Docker 版使用 `install-docker.sh` / `padm-docker`；不会自动混装、迁移或接管另一种部署。

### 安装

Docker 入口会安装并校验 Docker 控制 bundle；缺少 Docker 时，`install` 会在明确确认后引导安装 Docker Engine 和 Compose CLI 插件（v2 及以上）。它不在生产机执行 `docker build`，也不会把 Xray、sing-box、Nginx 或其它业务依赖安装到宿主机。镜像由本仓库 CI 预构建并发布，首次部署可在菜单中完成：

```bash
wget -O /root/install-docker.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/install-docker.sh" && chmod 700 /root/install-docker.sh && /root/install-docker.sh install
```

交互终端安装成功后自动进入菜单；已安装后直接运行 `padm-docker` 或
`padm-docker menu` 可查看状态、启停重启和日志，选择“首次配置”收集核心、协议、地址和证书。
当前向导支持 Xray Reality Vision/XHTTP/gRPC、sing-box Reality Vision/gRPC/Hysteria2/AnyTLS/NaiveProxy/Shadowsocks/TUIC，以及两核心 direct Trojan、VMess HTTPUpgrade TLS，
以及 Xray VLESS WS TLS、VMess WS TLS、VLESS/Trojan gRPC TLS、VLESS TCP TLS Vision、Trojan TLS fallback 或 Reality Vision + WS TLS；
已有部署不会被向导覆盖，可改用下述编辑入口；完整协议管理仍待后续阶段交付。
`install --no-menu` 禁止安装后自动进入菜单；无参数非交互调用只显示帮助，
不会安装 Docker、下载 bundle 或初始化状态，现有显式 CLI 命令保持可用。

```bash
padm-docker setup
padm-docker validate
padm-docker status
```

向导最终确认后才验签发布、生成 UUID/Reality 参数/订阅 token，并准备候选配置与证书。
没有 `cosign` 时停止，不自动从未验证来源安装验证器，也不能跳过验签。
WS/HTTPUpgrade/gRPC TLS、传统 TLS fallback、Hysteria2、AnyTLS、NaiveProxy、TUIC 和 direct Trojan 可选择已有受管证书、导入完整证书链与私钥，或使用 DNS-01/HTTP-01 standalone；
私钥和 DNS 凭据必须是仅持有者可读的普通文件。订阅发布仍要求 Xray、协议 21 VLESS WS TLS 和受管证书。
Hysteria2 使用单 UDP 入口，支持 BBR/Brutal、Salamander 混淆和 HTTPS 伪装；
带宽按服务端方向输入，分享链接自动转换为客户端方向。端口跳跃及 Gecko 尚未开放。
AnyTLS 使用 sing-box 直连 TCP/TLS 入口，不经过 Nginx；首配选择 sing-box 后选 `7=AnyTLS`。
复用 UUID 作为密码及流量账号，可输出 `anytls://` 分享链接；AnyTLS 单独部署不提供 HTTPS 订阅发布。
NaiveProxy 在 sing-box 首配中选 `8`，使用 TCP/TLS 直连入口；服务器地址必须与 TLS 域名一致。
UUID 同时作为用户名、密码及流量账号，分享链接使用 `naive+https://`；不开放独立 IP/SNI 覆盖或 QUIC。
Shadowsocks 在 sing-box 首配中选 `9`，固定为 `2022-blake3-aes-128-gcm` 多用户模式；
同端口支持 TCP/UDP 双栈，不需要 TLS。确认后独立生成服务器与用户密钥，UUID 作为流量账号。
`ss://` 按 SIP002 百分号编码组合密码；超额时撤销运行入站，解除额度后恢复原密钥和监听。
TUIC 在 sing-box 首配中选 `10`，使用单 UDP 双栈入口和受管 TLS；
UUID 同时作为用户 ID、密码及流量账号。拥塞控制支持 `cubic`、`bbr`、`new_reno`，
认证超时、心跳和 0-RTT 可在编辑菜单 `14` 管理，默认 `3s`、`10s`、关闭 0-RTT。
`tuic://` 使用 `h3`、原生 UDP 中继及严格 TLS 校验；端口跳跃尚未开放。
Direct Trojan 在 Xray 或 sing-box 首配中选 `11`，使用 TCP/TLS 双栈入口，不经过 Nginx；
UUID 作为密码及流量账号，可输出 `trojan://` 链接。服务器地址可与 TLS 域名不同，链接保留独立 SNI。
TLS 域名与凭据冻结；支持通用字段编辑、跨核心复制和删除，不包含 fallback 或独立 HTTPS 发布。
VMess WS TLS 在 Xray 首配中选 `12`，复用 Nginx、受管 TLS 和 UUID 流量账号；
固定 `alterId=0`，可输出标准 Base64 `vmess://` 链接。协议 22 可与 VLESS WS TLS 共用 Nginx，
但单独部署不发布 HTTPS 订阅，也不接受 sing-box、宿主集成或跨核心复制。
VMess HTTPUpgrade TLS 在 Xray 或 sing-box 首配中选 `13`，复用 Nginx 和受管 TLS；
使用独立 `httpupgrade` 字段、固定 `alterId=0`，链接的 `net=httpupgrade`，路径为 `/` 加受管路径段，不附加 `ws`。
支持路径编辑和跨核心复制，同一 UUID 共享流量及额度；单独部署不发布 HTTPS 订阅，也不接受宿主集成。
VLESS/Trojan gRPC TLS 在 Xray 首配中分别选 `14`/`15`，复用 Nginx HTTP/2、受管 TLS 和 UUID 流量账号；
使用独立 `grpc_tls` 字段，服务名为 1–64 位字母、数字、下划线或连字符，编辑菜单 `12` 可修改。
支持通用字段编辑、Xray 内复制/删除及 `vless://`/`trojan://` 链接；不接受 sing-box、宿主集成或 fallback。
单独部署只提供本地链接，和协议 21 混合时可纳入其 HTTPS 订阅。
VLESS TCP TLS Vision、Trojan TCP TLS fallback 在 Xray 首配中分别选 `16`/`17`。
Xray 直接终止 TLS，未命中协议的 HTTP/1.1 和 HTTP/2 请求通过 PROXY v1 回落到 Nginx；
`fallback_tls` 固定域名及两个内部端口，默认 `31300`/`31302`，同核复制可共享后端。
默认首页不写入站点目录，已有 `/etc/padm-docker/data/static/index.html` 优先；
支持通用字段编辑、同核复制/删除与链接；默认页、静态目录、302 和 ALPN 已支持事务管理，宿主集成及独立 HTTPS 发布尚未开放。

Docker 菜单 `16. 站点管理` 管理已有 Nginx TLS 入口 `21–25` 或 fallback `27`/`29` 的站点：

```bash
padm-docker edit --site-static /root/public-site --preview
padm-docker edit --site-static /root/public-site --confirm PADM-DOCKER-EDIT
padm-docker edit --site-redirect https://example.com/ --confirm PADM-DOCKER-EDIT
padm-docker edit --site-default --confirm PADM-DOCKER-EDIT
```

静态源必须是包含非空 `index.html` 的独立目录，生产路径须 root 所有且不可被其他用户写入；
只接受常见公开资源，拒绝受管目录及祖先、隐藏/秘密文件、可识别 PEM 私钥、链接和特殊文件。
该检查不能识别所有嵌入的凭据，发布前仍须确认目录仅含公开内容。源路径不保存到规格，
发布时复制内容；切换默认页/302 或不提供新目录的编辑均保留原静态文件。
站点模式适用于部署中所有上述 Nginx 入口，不改变代理、订阅、端口、TLS 或 ALPN；
失败和 INT/TERM 同时恢复站点及规格，旧无站点快照保留当前静态目录。
删除最后一个 Nginx 入口会清除站点模式，仍保留静态文件及其它 TLS 入口。
`status` 只报告 `site_mode`，不输出目标 URL。已有旧规格保持兼容，带 `.site` 的 v3
规格要求控制 bundle 声明 `x-padm-site-content`；受管 webroot 与 standalone HTTP-01 见证书管理。

同一菜单提供 `27`/`29` 的 ALPN 诊断、推荐修复和三种手动顺序：

```bash
padm-docker protocol alpn-status
padm-docker protocol alpn-status entry-fallback
padm-docker edit --alpn entry-fallback h2,http/1.1 --preview
padm-docker edit --alpn entry-fallback http/1.1,h2 --confirm PADM-DOCKER-EDIT
padm-docker edit --alpn entry-fallback http/1.1 --confirm PADM-DOCKER-EDIT
```

推荐顺序为 `h2,http/1.1`，手动选择持久化到可选 `fallback_tls.alpn`，核心配置和分享链接同步；
显式字段要求 bundle 声明 `x-padm-fallback-alpn`，旧无字段规格保持兼容。
诊断输出配置与实际 ALPN、fallback/Nginx 一致性和 `repairable`，只验证配置，不代表真实 TLS 协商；
符合手动规格的非推荐顺序不是配置损坏。修复只放行所选入站的 ALPN 字段差异，
完整账号输入和运行配置都核对，其它入口、账号、路由、fallback、Nginx 或编排漂移继续拒绝。
预览和取消不写生产文件，健康失败及 INT/TERM 恢复原状态，包括修复前的 ALPN 漂移。

完整规格保存于 `/etc/padm-docker/config/spec.json`，由 root 持有、权限 `0600`；
取消不提交，配置失败恢复旧规格、证书及 ACME 状态。该文件含秘密，不应打印或公开。

Docker 菜单 `17. 路由与出站` 提供认证 SOCKS5 TCP 全局或域名分流出站。先在 root 私有目录准备
`0600` JSON 文件，内容为 `{"server":"192.0.2.10","port":1080,"username":"user","password":"secret"}`；
这是格式示例，不是可用服务器。文件须单链接，所有祖先 root 所有且不可被组/其他用户写入，
不接受 `/tmp`、符号链接或特殊文件，最大 64 KiB。地址先限可路由 IPv4/IPv6 字面量，
凭据为 1–255 个可见 ASCII 字符，不含空格或控制字符。

```bash
padm-docker edit --socks5 /root/padm-socks5.json --preview
padm-docker edit --socks5 /root/padm-socks5.json --confirm PADM-DOCKER-EDIT
padm-docker protocol routing-status
padm-docker edit --socks5-domains 'example.net,full:exact.example.com,keyword:video,geosite:cn' --preview
padm-docker edit --socks5-domains 'example.net,full:exact.example.com,keyword:video,geosite:cn' --confirm PADM-DOCKER-EDIT
padm-docker edit --socks5-global --confirm PADM-DOCKER-EDIT
padm-docker edit --socks5-off --confirm PADM-DOCKER-EDIT
```

可选 v3 `.routing.socks5` 要求控制包声明 `x-padm-routing-socks5`；旧无路由规格保持直连。
两核心的客户端 TCP 目的流量经认证上游，认证失败或上游断开不回退直连；
客户端 UDP 目的流量显式阻断，不限制 Hysteria2/TUIC 承载 TCP 的 UDP 入口传输。
私有 JSON 可额外包含 `domains` 数组，或启用后用菜单替换规则：`full:` 精确域名、
`domain:` 域名及子域名、`keyword:` 安全 ASCII 关键字、`geosite:` 显式分类；最多 256 条。
CSV 输入去除首尾空白、转小写并按首次出现去重，裸域名补 `domain:`，不猜分类标签；
私有 JSON 中规则须已规范化。各类规则之间为 OR，匹配 TCP 经上游、匹配 UDP 阻断，
未匹配 TCP/UDP 直连；无域名且无法嗅探的 IP 流量也直连，不是强制全局代理。
`--socks5-global` 仅删除域名规则、保留上游及凭据，恢复全局出站。
域名模式另要求 `x-padm-routing-domains`；Xray 使用受管或镜像 Geo 数据，
sing-box 从固定 SagerNet 源直连下载所选分类，资源缺失或下载失败拒绝候选启动并恢复旧配置。
状态返回 `mode` 和 `domain_rules`，不显示凭据；嗅探只选择路由，不改写实际目的地址。
核心 Reality 握手、统计 API、控制服务、Nginx、证书及宿主自身流量不包含在此代理范围。
不增加监听端口、宿主权限或防火墙规则，暂不与 TUN/TProxy 组合。
启用、替换与关闭复用候选、确认、备份及失败/信号恢复，状态和预览不显示凭据；
凭据保存在私有规格、受管核心配置及备份中。SOCKS5 认证链路本身不加密，须使用可信上游网络。
完整 SOCKS 入站、WARP 和其它路由策略仍待迁移。

菜单 `17` 还提供核心内 DNS 分流和精确 hosts 覆盖。两者可独立使用，也可与 SOCKS5 共存；
只改变客户端直连域名目标的解析，不改宿主 DNS、路由、防火墙或公开监听。
DNS 私有 JSON 示例为 `{"server":"192.0.2.53","port":53,"domains":["domain:example.net"]}`，
仅接受字面 IPv4/IPv6 UDP 服务器，`domains` 必须包含 1–256 条已规范化的
`full:`、`domain:`、`keyword:` 或 `geosite:` 规则，各类为 OR；本阶段不提供全局 DNS、DoH 或 DoT。
菜单 `17` 的 `6` 可直接输入服务器 IP、端口（留空默认 `53`）和域名规则 CSV，
或使用 `--dns-rules <IP> <端口> <CSV>`；CSV 规范化与 Direct/Block 相同。
此操作创建或整组替换 DNS 分流，保留 `--dns` 私有 JSON CLI 和其它路由子项。
hosts 私有 JSON 示例为 `{"exact.example.net":"192.0.2.10"}`，接受 1–256 个小写精确域名，
每个域名对应一个可路由字面 IPv4/IPv6；不支持 hosts 后缀、关键字或分类匹配。
地址示例不可直接用作服务器；文件安全要求与 SOCKS5 输入相同。

```bash
padm-docker edit --dns /root/padm-dns.json --preview
padm-docker edit --dns /root/padm-dns.json --confirm PADM-DOCKER-EDIT
padm-docker edit --dns-rules 192.0.2.53 53 'example.net,full:exact.example.org' --preview
padm-docker edit --hosts /root/padm-hosts.json --confirm PADM-DOCKER-EDIT
padm-docker edit --dns-off --confirm PADM-DOCKER-EDIT
padm-docker edit --hosts-off --confirm PADM-DOCKER-EDIT
```

v3 可选 `.routing.dns` 与 `.routing.hosts` 要求控制包声明 `x-padm-routing-dns-hosts`。
hosts 优先于 DNS 分流；未匹配域名使用容器本地解析，匹配 DNS 失败不回退本地解析。
SOCKS5 匹配目标仍交上游解析，DNS/hosts 不改变上游域名或实际 IP 目的地；
只用于嗅探匹配的 HTTP Host/TLS SNI 不会被当作新的连接目的。
每次专项编辑只替换或关闭相应子能力，保留其他路由、入口、账号和累计流量；
普通 `--spec` 编辑不能绕过路由冻结。启用、替换与关闭复用原候选确认、备份和失败/信号恢复。
`routing-status` 额外返回 DNS 服务器、域名规则和 hosts 映射，不显示 SOCKS5 凭据。

菜单 `17` 的 `10/12` 分别替换 Direct 直连例外和 Block 域名阻断，可直接输入
逗号分隔规则；CLI `--direct-domains/--block-domains` 使用相同输入。
CSV 去首尾空白、转小写、按首次出现去重，裸域名补 `domain:`，
整组替换而非累加，空项/非法或超过 256 条拒绝；清空请使用对应关闭命令。
菜单 `17` 的 `22/23` 或 `--direct-domains-add/--block-domains-add` 可增量追加：
保留原规则顺序，再添加首次出现的新项；对应组缺失时创建，合并后超过 256 条拒绝。
重复追加不重复规则，确认仍沿用部署事务，可能更新回滚元数据。
仍保留 root 私有 JSON 导入，格式均为
`{"domains":["full:exact.example.net","domain:example.org","keyword:example","geosite:cn"]}`。
规则接受 1–256 条唯一小写 `full/domain/keyword/geosite`，四类保持 OR；
文件安全要求与 SOCKS5 输入相同。Direct 明确优先于 Block 和全局/域名 SOCKS5，
直连仍使用 hosts 与 DNS 分流；Block 对匹配 TCP/UDP 拒绝且不发起本地解析。
无法识别域名的 IP 流量不等同于域名策略命中；IP/CIDR 由独立子项管理。

```bash
padm-docker edit --direct /root/padm-direct.json --preview
padm-docker edit --direct /root/padm-direct.json --confirm PADM-DOCKER-EDIT
padm-docker edit --block /root/padm-block.json --confirm PADM-DOCKER-EDIT
padm-docker edit --direct-domains 'example.org,full:exact.example.net' --preview
padm-docker edit --block-domains 'keyword:example,geosite:cn' --confirm PADM-DOCKER-EDIT
padm-docker edit --direct-domains-add 'full:updates.example.org' --preview
padm-docker edit --block-domains-add 'domain:ads.example.net' --confirm PADM-DOCKER-EDIT
padm-docker edit --direct-off --confirm PADM-DOCKER-EDIT
padm-docker edit --block-off --confirm PADM-DOCKER-EDIT
```

v3 `.routing.direct`、`.routing.block` 要求控制包声明 `x-padm-routing-direct-block`。
各子项独立关闭，最后一项关闭才删除 routing；普通 `--spec` 不能更改路由。
`routing-status` 追加 Direct/Block 域名规则，不改变现有 SOCKS5 状态字段含义。

菜单 `17` 的 IP/CIDR 阻断使用独立 v3 `.routing.block_ips`，私有 JSON 为
`{"ips":["192.0.2.8","198.51.100.0/24","2001:db8::/32","geoip:cn"]}`。
接受 1–256 条唯一 IPv4/纯 IPv6 字面地址或 CIDR，以及固定 `geoip:cn`；
不接受主机名、地址范围、IPv6 scope、点分嵌入 IPv4 或其它 GeoIP 分类。
地址可包含回环/私网；这是目的匹配规则，不是代理或 DNS 上游地址。
文件安全要求与其它路由私有 JSON 相同，控制包须声明 `x-padm-routing-block-ips`。

```bash
padm-docker edit --block-ips /root/padm-block-ips.json --preview
padm-docker edit --block-ips /root/padm-block-ips.json --confirm PADM-DOCKER-EDIT
padm-docker edit --block-ips-off --confirm PADM-DOCKER-EDIT
```

IP 规则只匹配客户端提供的字面目的 IP，TCP/UDP 拒绝发生在 SOCKS/DNS/hosts 前。
Direct 域名例外（包括识别出的 HTTP Host/TLS SNI）优先且不改目的地址。
客户端以域名提交的目标不会为了 IP 匹配而提前解析；DNS/hosts 解析后的地址
不重新匹配本阶段 IP 规则，因此它不是最终拨号 IP 或宿主防火墙过滤。
Xray 复用受管/镜像 GeoIP；sing-box 从固定官方地址经直连下载 `geoip-cn`，
缺资产或下载失败拒绝候选启动并恢复原部署，词法合法不等于分类资源可用。
关闭仅删除 IP 子项，保留域名 Block、Direct、SOCKS、DNS/hosts。
状态追加 `block_ips.ip_rules`，完整区域策略向导与最终目的过滤仍待迁移。

菜单 `17` 的 `16–17` 管理 BT 协议阻断，v3 `.routing.block_bt:true` 启用，
关闭删除字段，不接受 `false` 或其它类型；控制包须声明 `x-padm-routing-block-bt`。
只阻断核心嗅探识别出的明文 `bittorrent`，不保证加密、混淆、DHT 或部分 uTP；
两核心 UDP 识别范围不同，不能把开关等同于所有 BT 流量或端口封禁。
Direct 域名例外优先，BT 在 SOCKS/DNS/hosts 前拒绝；原目的地址保持不变。

```bash
padm-docker edit --block-bt --preview
padm-docker edit --block-bt --confirm PADM-DOCKER-EDIT
padm-docker edit --block-bt-off --confirm PADM-DOCKER-EDIT
```

开关复用现有候选校验、备份与恢复事务；独立关闭保留其它路由子项及流量累计，
`routing-status` 启用时追加 `block_bt:true`。没有新增监听、宿主权限或防火墙规则。

菜单 `17` 的 `18` 提供 CN 区域预设，分别按 `geosite:cn` 域名、`geoip:cn`
字面目的 IP 或两者组合阻断。v3 `.routing.region` 保存 `mode` 和
`allow_domains`，控制包须声明 `x-padm-routing-region`。
固定直连例外为 `dl.google.com`、`apple.com`、`bing.com`、`microsoft.com`、
`gstatic.com`、`xn--ngstr-lra8j.com`、`googleapis.com` 和 `googleapis.cn`，
均匹配域名及其子域；可追加现有四类域名规则。
所有例外按 Direct 语义优先于域名/IP/BT 阻断和 SOCKS5，而不只豁免区域预设。

```bash
padm-docker edit --region both --region-allow 'example.com,full:api.example.net' --preview
padm-docker edit --region domain --confirm PADM-DOCKER-EDIT
padm-docker edit --region ip --region-allow '' --confirm PADM-DOCKER-EDIT
padm-docker edit --region-off --confirm PADM-DOCKER-EDIT
```

模式切换替换预设及追加例外，不累加旧模式；未指定追加例外时保存空列表。
关闭仅删除区域预设，保留手工配置的相同 CN 规则、Direct 例外及其它路由能力。
状态单独输出 `region.mode`、`allow_domains` 和 `default_allow_domains`。
IP 模式不为域名目标提前解析或在解析后复查；CN 数据沿用现有资源与下载失败恢复门禁，
不代表最终拨号 IP 过滤或完整区域策略管理。

菜单 `17` 的 `19` 管理 IPv6 域名出站。v3 `.routing.ipv6` 使用独立
`x-padm-routing-ipv6` 门禁，保存 `mode` 与 `domains`；选择性模式接受现有四类
域名规则，全局模式仅改变默认出口，不删除其它策略。

```bash
padm-docker edit --ipv6 selective --ipv6-domains 'example.com,full:api.example.net' --preview
padm-docker edit --ipv6 global --confirm PADM-DOCKER-EDIT
padm-docker edit --ipv6-off --confirm PADM-DOCKER-EDIT
```

Direct 例外、域名/IP/BT 阻断优先于选择性 IPv6，选择性 IPv6 优先于 SOCKS5；
全局 IPv6 保留显式 SOCKS5 分流，但不能与全局 SOCKS5 同时定义默认出口。
匹配的域名仅使用 AAAA 地址，不回退使用 A 地址；系统 resolver 仍可能查询 A。
原 hosts 与 DNS 分流来源保持不变，IPv4-only hosts 在此路径拒绝，不换源回退。
这不是 IPv4 防火墙，字面 IPv4 不会转换为 IPv6。
关闭只删除 IPv6 子项，保留其它路由、凭据与累计流量。
核心仍为无额外权限的普通容器；启用时附加本项目独立 IPv6 bridge，
不修改原默认网络、Docker daemon 或宿主接口，宿主仍须具备 IPv6 路由与出口。
TUN/TProxy 的宿主网络模式不属于本阶段支持范围，完整 WARP 和宿主验收继续待补。

菜单 `17` 的 `20` 导入、关闭或查看 WARP 出站。独立 v3 `.routing.warp`
通过 `x-padm-routing-warp` 门禁；输入为 root 所有、`0600`、最多 64 KiB 的私有 JSON，
沿用路由输入的单链接及安全祖先目录限制，密钥不放在命令参数、预览或状态中。
输入包含 `mode`（`selective` 或 `global`）、`family`（`ipv4` 或 `ipv6`）、
`private_key`、`peer_public_key`、`ipv6_address`、`reserved` 和 `domains`。
密钥为规范的 32 字节 Base64，`reserved` 为 3 个 `0–255` 整数；
选择性模式要求 1–256 条唯一四类域名规则，全局模式必须使用空 `domains`。

```bash
padm-docker edit --warp /root/warp.json --preview
padm-docker edit --warp /root/warp.json --confirm PADM-DOCKER-EDIT
padm-docker edit --warp-off --confirm PADM-DOCKER-EDIT
```

账号参数由用户已有的 WARP 配置提供，不自动注册账号或安装第三方注册器。
固定 Peer 为 `162.159.192.1:2408`、MTU 为 `1280`；`family` 选择单一本地隧道地址及
匹配域名的解析地址族。IPv4 为 `172.16.0.2/32`，IPv6 为导入的 `ipv6_address/128`；
只使用该族地址，不回退另一族，不保证公网出口地址族，字面目的 IP 不转换。
Xray 和 sing-box 明确使用用户态 WireGuard，不创建宿主接口或新增权限、设备和端口。
Direct、域名/IP/BT Block、选择性 IPv6 先于 WARP，选择性 WARP 先于 SOCKS；
全局 WARP 保留显式 IPv6/SOCKS 规则，但不能与其它全局默认出口并存。
仍使用原 hosts/DNS 分流来源，关闭只移除 WARP 子项，不改变其它规则与累计流量。
双核心已在隔离环境验证本地加密 Peer 的 TCP/UDP、DNS 来源、失联无直连及关闭恢复；
夹具为非零 reserved 记录后适配标准内核 Peer，不代表 Cloudflare 服务验收。
Cloudflare 账号有效性、公网 UDP 和真实公网出口仍需独立验收。

完整 v3 `configure` 规格可选 `accounts`，用于追加 1–256 个独立账号，不替换原自用账号。
每项必须包含 `id`、`name`、`enabled`、`uuid`、`password`、`shadowsocks_password` 和
`listeners`；`id` 是稳定的小写 UUID，认证 `uuid` 和密码独立，`listeners` 引用现有入口 ID。
关联 Shadowsocks 时需要独立的 SS2022 用户密钥，未关联时该字段为 `null`；
身份与同类凭据必须唯一，不得复用自用身份/凭据或 SS 服务器密钥。
Naive 的用户名使用稳定 ID，TUIC 使用认证 UUID 和独立密码；跨核心累计与额度按稳定 ID 归集。
停用保留身份及累计，仅移除运行认证和输出节点；轮换认证或配置恢复不会清零、回退累计。
两核心 `config/*/users.base` 保留停用凭据，与 spec 一样为 `0600 root:root`，
运行配置不含账号私有映射。旧控制包缺少 `x-padm-accounts` 能力时拒绝配置、更新或恢复该规格。
账号底座和账号管理已提供：菜单及 `padm-docker account` 支持列表、新建、名称/
入口关联编辑、复制、启停、删除和凭据轮换。每次变更都经过私有草稿、候选校验、
备份和健康检查事务；未选账号、累计流量和额度保持不变，复制会生成新的稳定身份
与凭据。普通链接/订阅输出包含自用和启用账号，仍共用部署级 token，不是独立分享链接。
分享组、单账号发布授权、纯内容复制和业务备份恢复仍待实现。

已有受管规格可从菜单的“编辑配置/导入原始规格”或 `padm-docker edit` 修改入口端口、
服务器地址、地址族、节点名称、Reality 目标/SNI、XHTTP 路径/Host/模式、
gRPC service name、WS/HTTPUpgrade 路径、Hysteria2 拥塞/带宽/混淆/伪装和订阅开关。
编辑先生成私有草稿，显示不含秘密值的差异，候选验证通过并确认后才提交；
未选中的入口、UUID、密钥、token、证书、宿主集成和累计流量保持不变。
菜单可按入口 ID 复制或删除现有协议入口，主核心至少保留一个入口。
Reality Vision/gRPC、direct Trojan 和 VMess HTTPUpgrade 可复制到另一核心，XHTTP 仅支持 Xray；
VLESS/VMess WS TLS、VLESS/Trojan gRPC TLS 和传统 TLS fallback 仅支持 Xray 内复制，已有入口的 TLS 身份及内部端口冻结。
Hysteria2/AnyTLS/NaiveProxy/Shadowsocks/TUIC 仅支持 sing-box 内复制；已有部署新增这些类型须导入完整 v3 `configure` 规格。
Shadowsocks 的方法、服务器/用户密钥、UUID 和已有入口身份冻结，不通过通用编辑轮换凭据。
AnyTLS/NaiveProxy/direct Trojan 复用通用入口字段编辑，TLS 域名与 UUID 冻结，证书轮换使用证书管理入口。
NaiveProxy 的入口域名随 TLS 身份固定，不能单独修改为其它域名或 IP。
编辑器可从现有 Reality 入口派生其它 Reality 传输入口，不生成新账号或密钥。
删除副核心的最后入口会关闭副核心，不能改写已有入口的核心归属。
新增与删除须分次确认提交，不能在同一事务中用替换绕过已有身份及内部端口保护。
复制复用原入口凭据；同一 UUID 的多个入口共享累计流量与额度，不会创建独立用户。
旧部署没有 `config/spec.json` 时，必须导入保留的完整原始 spec，匹配运行配置后才能接入；
缺字段、额外账号、手写路由/站点或不匹配的挂载路径会拒绝编辑，不从运行摘要伪造输入。

```bash
padm-docker edit
padm-docker edit --spec /root/original-spec.json --preview
padm-docker edit --spec /root/original-spec.json --confirm PADM-DOCKER-EDIT
```

菜单“协议与入口”的“额外入口端口”可给已有受管入口添加或删除额外公开端口。
v3 可选顶层 `port_aliases` 保存最多 16 项 `{listener_id, public_port}`；
TCP/UDP 和地址族继承目标入口，多个发布端口仍使用同一认证、入口 ID、账号与累计流量。
TLS 入口继续经 Nginx TLS 前端；bridge 的 Reality 443 共存别名继承完整 SNI 分流，
不是单独隔离的网站或 Reality 入口。没有新核心、证书、宿主权限或任意目的转发。

```bash
padm-docker protocol port-alias-status
padm-docker edit --port-alias entry-reality 8444 --preview
padm-docker edit --port-alias entry-reality 8444 --confirm PADM-DOCKER-EDIT
padm-docker edit --port-alias-default entry-reality 8444 --confirm PADM-DOCKER-EDIT
padm-docker edit --port-alias-default entry-reality base --confirm PADM-DOCKER-EDIT
padm-docker edit --port-alias-remove entry-reality 8444 --confirm PADM-DOCKER-EDIT
```

默认分享链接使用原公开端口，不自动生成别名节点。
可将已有别名选为该入口的默认分享端口：对应项保存 `share_default: true`，
每个入口最多一项；本地 URI、主订阅和分享组一致切换，账号、凭据和节点数量不变。
`base` 恢复原入口，删除被选别名也自动回退；443 共存恢复到公开 SNI 前端，
不改容器后端。选择只影响指定入口，不联动同数字的 TCP/UDP 其它入口。
重复 TCP 或 UDP 发布端口会拒绝，同一数字的 TCP/UDP 可分别使用；
Fail2ban、TUN/TProxy 与 host-network 共存暂不接受别名。
普通 `edit --spec` 不能新增或改写别名；删除入口同步清理其别名，复制不继承。
旧控制 bundle 缺少 `x-padm-port-aliases` 时拒绝配置、更新或恢复带别名的规格。
带默认分享标记的规格还要求 `x-padm-port-alias-default`，不能回滚到忽略该标记的旧 bundle。
公网、IPv6 发布、原生宿主及 arm64 仍需独立验收，完整 `207` 保持 `deferred`。

菜单新增“协议与入口”，可查看稳定入口 ID、核心、协议、地址/端口及地址族，
查看全部或指定入口的分享链接，并进入现有编辑器修改、复制或删除入口。
`protocol links` 标准输出只含 URI；关闭 HTTPS 订阅发布时仍可输出本地链接，
不会开启发布、修改受管规格或采集流量。旧部署缺少完整规格或运行配置存在漂移时拒绝输出；
本地链接含用户凭据，不应公开。

```bash
padm-docker protocol list
padm-docker protocol links
padm-docker protocol links vless-reality
```

`--preview` 不提交、不采集流量、不启停业务服务；验证仍会验签发布、拉取镜像并运行候选检查。
`edit` 默认验证当前部署版本而非 latest，也可传入下述同版本发布资产参数。
首次配置输出 `schema_version: 3`；`configure` 和备份恢复继续接受 v1/v2。
编辑先严格核对原规格与部署，再将草稿迁到 v3，确认前不改写受管规格。
v3 明确每个入口的 `core` 归属及 `core.secondary_type`（不用副核心时为 `null`），
两核心合计最多 16 个入口；v2 仍为单核心。新增协议 `2`/`3`/`4`/`5`/`22`/`23`/`24`/`25`/`26`/`27`/`28`/`29`/`30`/`31` 仅接受 v3；
Xray 可用 Reality Vision/XHTTP/gRPC、VLESS WS TLS、VMess WS TLS/HTTPUpgrade、VLESS/Trojan gRPC TLS、传统 TLS fallback 和 direct Trojan，sing-box 可用 Reality Vision/gRPC/Hysteria2/AnyTLS/NaiveProxy/Shadowsocks/TUIC/direct Trojan/VMess HTTPUpgrade。
首次向导支持 Xray+sing-box 或 sing-box+Xray，副核心首配为 Reality Vision；
主 sing-box、副 Xray 的 WS TLS 首次需使用完整 v3 spec；已有 Xray WS 入口可继续复制。
双核心目前只支持普通 bridge 部署，不能与宿主集成组合。
包含 Hysteria2、AnyTLS、NaiveProxy、Shadowsocks、TUIC、direct Trojan、VMess、gRPC TLS 或传统 TLS fallback 的单核心部署也暂不接受宿主集成。
每个入口的 `listener_id` 固定；旧入口迁移保留 `vless-reality` / `vless-ws`，
新入口使用 `entry-*`。WS 的 `websocket.backend_port` 与 `websocket.tls_port`
按入口独立分配，HTTPUpgrade 对应 `httpupgrade.backend_port` 与 `httpupgrade.tls_port`，
gRPC TLS 对应 `grpc_tls.backend_port` 与 `grpc_tls.tls_port`，
传统 TLS fallback 对应 `fallback_tls.http_port` 与 `fallback_tls.http2_port`。
不重排已有内部端口；后端监听按实际核心避让，Nginx TLS 与 fallback 端口全局避让，公开端口不得冲突。
已有部署的 `edit --spec` 也支持这些入口变更，仍经过相同的预览、校验与确认。
删除最后一个 VLESS WS 入口会关闭订阅；仍有 VMess WS/HTTPUpgrade、gRPC TLS、传统 TLS fallback、Hysteria2、AnyTLS、NaiveProxy、TUIC 或 direct Trojan 时保留规格中的 TLS，
否则将 `tls` 设为 `null`，受管 TLS/ACME 文件与 token 均保留。
Nginx 端轮换、核心端受管 TLS 底座及 Reality XHTTP/gRPC、Hysteria2/AnyTLS/NaiveProxy/Shadowsocks/TUIC/direct Trojan/VMess WS/HTTPUpgrade/gRPC TLS/传统 TLS fallback 基础入口已交付；
逐入口 Reality 参数重生成已交付；高级 XHTTP 参数、Reality 目标库/扫描/443 共存与完整协议管理仍未开放。
更新或回滚的目标 bundle 必须同时支持规格版本及每个入口的协议/核心组合。
带 Fail2ban 的 WS 入口暂不允许增删或修改公开端口，需后续联动封禁规则的管理事务。
3A.3 已通过本地双核心事务、PTY、流量、更新/回滚和 Linux 权限回归；真实签名发布、业务镜像及双架构客户端连通仍待验。

主菜单 `协议与入口` -> `重生成 Reality 参数` 可选择已有入口，确认后更新密钥对和 short ID。
也可使用 CLI：

```bash
padm-docker edit --regenerate-reality <入口ID> --preview
padm-docker edit --regenerate-reality <入口ID> --confirm PADM-DOCKER-EDIT
```

仅修改该 Reality 入口，保留 UUID、目标/SNI、端口、其它入口和流量额度；
提交后需重新导入该入口链接，已启用的 HTTPS 订阅内容同步更新。
预览不提交，确认前的候选参数不会保留到下一次命令；普通 `edit --spec` 仍禁止手工改密钥。
失败或中断使用配置快照恢复；公开 `rollback` 仍只回滚更新快照，不是编辑撤销命令。

离线使用同一 Release 的三个资产：

```bash
padm-docker setup --manifest /root/release-manifest.json \
  --bundle /root/release-manifest.sigstore.json \
  --control-bundle /root/padm-docker-bundle.tar.gz
```

非交互部署继续使用 `configure --spec /root/padm-docker-config.json`，可传入相同发布参数；
`release` 可输出已验证的 `release`、`images` 输入，但它不是签名证明，`configure`
会重新验证原资产。示例字段须替换为实际参数，并让发布字段和全部镜像与验签清单完全一致。
更新/回滚会同步保存完整规格；损坏或不匹配的规格在停止当前服务前被拒绝。
v3 编辑还要求当前控制脚本及同部署版本的可信发布资产支持 v3；不支持时先刷新到支持 v3 的已发布控制脚本。
规格的 `schema_version` 与运行格式 `formats.config` 分开版本化，后者当前仍为 `1`。

需要固定控制脚本版本时，把 `install` 改为 `install --ref <40 位 commit SHA>`；不要把 `latest` 当作生产版本锁。CI Release 同时提供 `release-manifest.json`、Cosign 签发的 Sigstore bundle v0.3（`release-manifest.sigstore.json`，签名内嵌）和 `padm-docker-bundle.tar.gz`，更新时会校验 bundle 签名和摘要。

`main` 的安装入口、运行脚本、Docker 配置、镜像输入或版本锁存在未发布变化时才自动发布。Docker 测试、发布脚本和 CI 文件变化也会触发 `Release` 检查；没有待发布运行变化时只跑 Docker 契约测试，不递增版本、不构建镜像、不发布附件。若前次发布失败，修复测试或 CI 后的推送会继续处理尚未发布的运行变化。仅文档变化不触发。PR 的 `Docker CI` 先运行独立的 actionlint 和全部 Shell 语法门槛，再按改动范围运行 `ci-pr` 或完整 `ci` 原生回归，门槛通过后才构建镜像；`Release` 会在版本递增前执行完整门槛，并只读预检两架构 Alpine 索引中的锁定 APK 版本。版本提交后当前 Release run 会交给新的 run 接管，避免同一版本重复构建。发布任务串行处理最新 `main`，三个附件全部上传并核对摘要后才公开 Release。需要重试或主动发布时运行 `Release` 工作流；PR 和手动镜像验证使用 `Docker CI`。

CI 按每个镜像的目录、共享构建定义及实际锁定依赖判断是否重建；未变化的镜像沿用上一份已验签 manifest 的 `tag@sha256`，其标签可能早于当前脚本版本，并只执行 manifest、平台摘要和签名校验。每个变化镜像的两个架构各构建一次，按精确摘要测试后合并并签名；没有可信基线时完整重建。SBOM、provenance 和镜像签名保存在 OCI 仓库，诊断 JSON 仅作为保留 7 天的 Actions artifact，不再作为 Release 附件重复上传。

示例文件中的 digest、密钥和 token 是占位值，不能直接用于生产。生产镜像引用必须使用 CI Release 提供的版本标签和 digest，例如 `ghcr.io/neil1123-vip/padm-xray:3.1.9@sha256:<digest>`；不要使用 `latest`，也不要在主机上手工改成未发布的 tag。

### 五个镜像

五个镜像都由仓库中的 Dockerfile 定义，当前统一以锁定的 Alpine 3.24.1 基础镜像构建；基础 digest、上游版本和架构校验值由 `versions.lock` 锁定，再由 CI 构建 `amd64/arm64` 多架构镜像。一个镜像可以被多个 Compose service 复用，但不同长期职责仍是独立容器。

| 镜像 | 职责 | 宿主集成 |
| --- | --- | --- |
| `padm-xray`（`xray`） | Xray-core、Geo 数据和核心配置校验。 | 普通 bridge 容器。 |
| `padm-sing-box`（`sing-box`） | sing-box、核心配置校验和对应协议运行时。 | 普通 bridge 容器。 |
| `padm-nginx`（`nginx`） | TLS、WebSocket、反向代理和静态入口。 | 只发布被选中的入口端口。 |
| `padm-ops`（`ops`） | ACME、订阅控制、Geo/同步等运维任务，按 Compose service 作为长期或一次性进程运行。 | 不持有 Docker Socket。 |
| `padm-net`（`net`） | WireGuard、Fail2ban、TUN/TProxy 和端口/防火墙集成工具。 | 仅在显式 `net-*` profile 下使用 `NET_ADMIN`、host network 或 `/dev/net/tun`。 |

`net` 的业务工具放在镜像中，但真正的 WireGuard、转发、TUN 和防火墙对象仍属于宿主内核；默认安装不启用这些高权限 profile。普通服务不使用 `privileged`、`SYS_ADMIN` 或 Docker Socket。

### 状态与日常控制

Docker 状态根固定为 `/etc/padm-docker`，原生状态根 `/etc/padm` 不会被 Docker 入口读取或覆盖。常用命令如下：

```bash
padm-docker status
padm-docker up
padm-docker down
padm-docker restart
padm-docker logs
padm-docker validate
padm-docker assess
```

服务维护菜单第 5 项提供受管 Fail2ban 的状态、单 IP 解封、WS 站点扫描启停及参数管理：

```bash
padm-docker fail2ban status
padm-docker fail2ban unban 192.0.2.7
padm-docker fail2ban unban 2001:db8::7
padm-docker fail2ban enable 443,8443 6 600 3600 --preview
padm-docker fail2ban enable 443,8443 6 600 3600 --confirm PADM-DOCKER-EDIT
padm-docker fail2ban settings 443,8443 8 900 7200 --confirm PADM-DOCKER-EDIT
padm-docker fail2ban disable --preview
padm-docker fail2ban disable --confirm PADM-DOCKER-EDIT
padm-docker fail2ban verify-source entry-ws 203.0.113.7
```

状态与解封只操作当前运行且规格、镜像、标签及挂载一致的 `net-fail2ban` 容器和固定
`padm-nginx` jail；不自动启动服务、不修改配置或新增封禁。解封接受单个
IPv4/IPv6 字面地址，不接受域名、CIDR、zone、任意 jail 或全部解封；
菜单执行前需要确认。未配置、停机或归属不一致时拒绝操作，底层失败返回非零。
维护前通过容器内 Fail2ban 原生只读协议核对已加载动作、公开参数和有效属性缓存；
动作、地址族参数或缓存漂移，以及额外 action，均拒绝操作并返回 `15`；
随后只读核对私密 runtime state 和两族内核规则，归属漂移时不执行解封 client。
审计不是与特权管理员并发操作的原子事务，也不抵御恶意 Python action、
私有执行缓存或 Fail2ban 程序本身被篡改；此时应先停止服务并人工核对。
`enable` 只接受尚未启用的受管规格，`settings` 要求已经启用；四项参数依次为
保护 WS 公开端口列表、失败阈值（1–20）、检测窗口（60–86400 秒）、
封禁时长（60–604800 秒）。端口最多 16 个，必须是已有协议 21 的直连 WS，
不接受端口别名或共存分流；重复启用不会重置已有参数。
菜单启用的数字默认值为 `6 / 600 / 3600`，修改参数须逐项显式填写。
两项复用专项编辑和配置事务，只改变该 Fail2ban 条目，保留其它集成、账号及持久数据；
不是对运行 jail 直接 reload。预览或取消不启停服务，确认后的更新也必须重新完成来源挑战。
停用复用配置编辑事务及既有规格迁移，只移除 Fail2ban 条目，其它宿主集成和业务数据保持不变。
预览或取消不停止容器；确认后先审计旧拥有者，只停止该容器并保留退出证据，
确认正常退出、私密 state 和两族受管规则均已清理，才安装新配置。
停止超时、异常退出、归属漂移或残留规则会拒绝提交，保留旧配置及恢复证据；
服务可能已停止，需人工核对原拥有者，不可删除 state 强制继续。
提交后启动失败沿既有快照恢复旧配置，保留 SQLite 封禁历史，不复制旧内核规则。
`disable` 只接受预览或固定确认参数；未启用时返回状态错误，不隐式启用或修改防护参数。
来源核对菜单和 `verify-source <WS 入口 ID> <外部客户端 IPv4/IPv6>` 只做现场诊断。
它为所选地址族生成一次性挑战，外部客户端在 30 秒内向显示的域名和公开端口请求该 URI；
核对当前受管 Nginx 的真实来源、内部端口与容器启动身份，不信任转发头或历史日志。
本机、容器、网关来源、共享内部端口的额外别名及共存分流入口拒绝验证。
结果不保存为新启用凭证，不启动 Fail2ban、不修改配置或规则。
配置提交、更新、启动/重启及回滚启用 Fail2ban 时，先审计并停止旧拥有者、证明清理，
再启动非 jail 长期服务，对每个保护端口与地址族生成新挑战，整批复核通过后才单独启动 jail。
失败恢复也必须重新挑战；缺输入或任一证明失败时不启动 jail，并保留备份与恢复标记。
菜单在确认后采集本次外部 IPv4/IPv6；非交互命令可设置
`PADM_DOCKER_FAIL2BAN_SOURCE_IPV4` / `PADM_DOCKER_FAIL2BAN_SOURCE_IPV6`，
它们只是预期来源，不能替代外部客户端响应新 URI，也不保存成功票据。
停用前也收集旧配置可能恢复所需的来源；预览、取消不要求响应挑战。
`net-fail2ban` 禁用 Docker 自动重启，daemon 重启后须通过管理入口重新见证；
旧 `unless-stopped` 编排须先标准更新，已验证旧备份恢复时仅规范化该策略，备份原文不变。
启用防护的 Nginx 不接受 standalone HTTP-01 停启，请使用 webroot；
TLS 重载同样需要本次来源输入与现场挑战，未配置输入的无人值守轮换会拒绝提交。
30 秒是日志采集窗口；Docker 日志或地址查询阻塞时命令可能更久，超时仍以失败收场。
该检查证明磁盘配置、容器元数据和现场请求一致，不证明特权修改后的 Nginx worker
已加载全部配置字节，也不替代新启用事务的现场门禁。
Fail2ban 使用 schema 2 的私密 `data/net/fail2ban/fail2ban.state`、随机链和完整 token
标记 hook、封禁规则及末尾 RETURN。启动、动作和停止先核对归属，逐条精确删除，
不 flush 固定链；旧 `ports=` state、固定 `padm-f2b`、外来引用及 hook 遮蔽拒绝接管。
不要删除 state 强制重试：先停原拥有者，在原生 Linux 上人工核对遗留资源。
双栈 WS 防护让 Nginx 接入已有受管 IPv6 辅助网，避免 IPv4 bridge proxy 丢失来源；
旧双栈 Compose 需通过标准配置/升级事务更新，不能直接绕过正文一致性检查。
隔离 Linux amd64 已验证真实双栈来源、日志自动封禁、丢包及解封；
同事务双端口/双栈启用已验收；SSH/控制面防护、真实宿主、arm64、重启/卸载与完整管理仍按 5C 门槛验收。

已有 TProxy profile 使用私密 `data/net/transparent/tproxy.state` 记录随机链、
规则 token、mark、路由表和路由身份。预检只读核对当前归属与候选冲突；
启动失败及正常停止逐条精确撤销，不 flush 整个链或路由表。
旧两字段 state、固定 `padm-tproxy` 链、未知随机链或外来规则漂移均拒绝接管，
保留资源及恢复证据。此版本独占对应路由表和策略优先级，不支持共享表。
不要直接删除 state 后重试：先停止原拥有者，并在原生 Linux 主机上核对实际资源。
SIGKILL 若留下无 token 规则的空链，需人工确认归属后恢复，不会按同名链猜测清理。
这只是 TProxy 所有权前置，不代表透明代理客户端、宿主重启或完整 5C 已验收。

主菜单第 13 项“核心升级评估”或 `assess` 会验签并预拉取候选镜像，使用私有配置副本
执行菜单版升级风险扫描、实际核心配置试跑和 Xray 严格校验，以及已启用的 TLS、
订阅和宿主集成检查。输出候选发布与实际核心版本；不备份、不采集流量、不切换
配置或控制 bundle，也不启停现有服务。完成、失败或取消后清理候选。
旧部署必须先通过 `edit --spec` 导入完整受管规格。默认评估最新可信发布；评估预发布时
传入与该版本匹配的 `--manifest`、`--bundle` 和 `--control-bundle`，不接受未签名
镜像或现场构建核心。通过只证明这些检查完成，不替代真实客户端连通验收。
Xray 严格解析另用未知字段探针确认；不识别严格模式的候选核心会明确显示“未启用”，
不能将普通配置试跑通过视为严格解析通过。

Xray Geo 数据可在主菜单第 14 项管理，单 Xray 和包含 Xray 的双核心部署均可用：

```bash
padm-docker geo status
padm-docker geo update
padm-docker geo update --version 202610070140
padm-docker geo schedule enable
padm-docker geo schedule status
padm-docker geo schedule disable
padm-docker geo auto-update
```

更新使用与原生版相同的 `Loyalsoldier/v2ray-rules-dat` 发布数据；未指定版本时先解析
最新发布的固定 tag，下载 `geosite.dat`、`geoip.dat` 及各自 SHA256 校验文件。
两文件摘要、Xray Geo 解析和当前配置校验全部通过后，才保存至
`/etc/padm-docker/config/xray/geo`，并通过只读配置挂载和
`XRAY_LOCATION_ASSET=/etc/padm/xray/geo` 切换实际读取路径。
未更新的旧部署继续使用镜像内置 Geo，不会因空目录覆盖丢失数据。
更新不轮换账号、订阅或镜像；仅在 Xray 原本运行时定向重建 Xray，
下载、校验、重建失败或取消时恢复旧数据、Compose 和原运行状态。
菜单的更新与开启自动更新需要先确认，等待输入时不持部署锁。
每日任务在宿主本地时间 01:35 执行，优先 systemd timer，否则使用 cron；
任务按部署 root 管理所有权，使用部署锁并记录结果，重复启用不创建重复任务，
不覆盖或删除其它部署的调度。`geo auto-update` 是受管任务入口，不进入交互菜单。
本地回归与真实发布、公网、原生 arm64 和整机重启验收分别记录，不由模拟通过推断完成。

多服务器控制已有独立私网只读 API 和被控端同步事务基座：授权绑定被控源地址，
token 过期、轮换与撤销立即生效，公开订阅服务不变。v3 受管规格保存来源身份、
入口映射、版本/内容摘要和完整受管账号快照；同步只替换主控所属账号，保留本机账号，
同版本同内容不重建，版本冲突、凭据碰撞或归属漂移拒绝覆盖，应用失败恢复旧规格与配置。
普通配置不能改变同步归属，受管账号只能由主控修改后同步。
4C.3a 已补 WireGuard 归属与撤销底座：预检、健康和清理共同核对接口索引、公钥及随机
接口标记，撤销使用 root 私有启动快照。外部替换或活动旧式标记拒绝自动接管/删除；
升级前先正常停止旧容器，不能只凭同名接口或相同公钥认领归属。
4C.3b 新增独立 `control-health --state PATH`：安全读取状态、核对实际接口地址，
限时直连私网服务，验证无认证的固定拒绝响应，不传递 token，也不受邀请过期影响。
4C.3c 主控期望账号已接入候选、备份、更新和恢复事务；账号顺序或本机监听映射变化
不增加发布版本，账号内容变化才递增，回滚旧内容也发布为更高版本，不倒退同步序号。
独立 Compose `control` 服务使用 host 网络、UID `10001`、零能力，无公开端口映射，
只读挂载 `config/control` 并依赖 WireGuard 健康。普通配置不能更改主控身份、监听或授权。
`padm-docker control status [--json]` 和菜单“控制连接”可查看脱敏角色状态。
已有受管单 Peer WireGuard 运行健康时，可初始化主控：

```bash
padm-docker control init --address 10.77.0.1 --port 18443 --peer-address 10.77.0.2 --yes
```

地址必须与实际接口及唯一 Peer 的 `/32` AllowedIPs 一致；初始化不创建密钥、接口或路由，
拒绝覆盖既有角色，默认授权关闭。主控健康反映已安装服务，不输出 token、账号或摘要。
邀请和凭据轮换共用同一命令，生成新文件并使旧 token 立即失效：

```bash
padm-docker control invite --output /root/padm-control-invite.json --expires-in 86400 --yes
padm-docker control revoke --yes
```

邀请文件保存私网地址、双方身份、过期时间和唯一原始 token，权限为 `0600 root:root`。
有效期允许 `60–604800` 秒，省略时为 `86400` 秒。
输出须为受管部署目录外的绝对路径；父目录链必须 root 所有、无符号链接且不可被组/其他用户写入。
已有文件、目录或链接均拒绝覆盖；轮换时选择新文件名。普通输出、日志和进程参数不含 token，
受管 spec 只保存摘要。撤销不要求网络健康，重复撤销不重建；状态提供脱敏授权开关与过期时间。
撤销先原子禁用 API，再更新 spec；两步之间中断时重复执行 `revoke` 补齐，不恢复旧授权。
恢复、失败回滚或显式版本回滚均禁用授权，避免复活旧 token，之后需重新邀请。
邀请文件原子交付后即使配置失败也保留，但不保证授权有效，以 `control status` 为准。
被控端先配置并启动归属一致的单 Peer WireGuard，再将邀请安全送至其 root 私有目录。
主控地址须是唯一 Peer 的 `/32` AllowedIPs，本机接口地址须与邀请的 `peer_address` 一致，
到主控的指定源地址路由必须走 `wg-padm`。接入和手动同步也可从“控制连接”菜单执行：

```bash
padm-docker control join --invite /root/padm-control-invite.json --listener entry-reality --yes
padm-docker control sync --invite /root/padm-control-invite.json
```

`--listener` 可重复指定现有入口；接入一次确认，在同一事务中初始化被控身份、固定映射并完成首轮同步。
失败保留原角色、账号和流量；重复同步同版本同内容不重建。
双方身份、连接地址和映射随后冻结，不能用另一邀请重新认领。轮换后安全传递新的邀请文件，再同步。
每次同步显式读取受管目录外的 root 私有邀请，祖先目录权限与输出要求一致；过期或撤销时拒绝。
原始 token 不写入 spec、备份、参数、环境或普通日志。客户端无能力、固定本机私网源地址直连，
不使用代理、重定向或公网回退；状态只展示连接元数据，不据此宣称远端健康。
新控制 API 同时写入受管 `logs/control/auth.log` 和标准输出，仅记录 UTC 毫秒时间、
状态和实际 socket 的来源、目标及端口，
忽略代理转发头，不记录请求路径、请求头、账号、凭据或异常原文。
文件安全核验、完整写入和同步成功后才发送响应；日志失效或来源不可证明时停止 API。
日志留在配置恢复之外，首次创建不截断已有内容。连接关闭与鉴权失败分开记录；
精确旧版本恢复可保留仅标准输出的受管格式，不宣称具备新日志能力。
自动轮转和控制面 Fail2ban 防护尚未交付。
新版主控可执行 `padm-docker control source-check` 登记最多 30 秒的随机挑战，
再在受管 Peer 执行输出的 `control source-probe` 命令。探测绑定 WireGuard 源地址，
不读取邀请或发送 token；精确匹配登记、真实 socket 与主控状态的 401 才写独立
`logs/control/source.receipt`，普通访问日志不记录 nonce。
登记退出或中断即清理，旧回执不作为后续启用凭证；配置/容器代次变化时拒绝证明。
存在陌生或变化后的登记时保留并拒绝，不自动删除；此命令不会启用 jail。
旧无连接元数据的内部被控规格继续兼容，但不能直接使用外部同步；旧 bundle 不得恢复新连接规格。
显式 `rollback` 在采集、备份和停服前检查被控身份、入口映射与连接一致，拒绝降同步版本，
同版本必须保持摘要和受管账号；同步状态未变的兼容发行版快照仍可回滚。
被控规格要求 bundle 声明回滚保护能力，不能回到缺少该保护的旧脚本。
普通接入/同步失败或中断仍恢复事务前状态，不在本机伪造上游版本。
尚未提供自动同步、角色重绑定、任意历史账号恢复或 WireGuard 连接向导。
定向夹具覆盖候选、安装、恢复和权限，核心/宿主动作是桩，不代替真实双节点验收。
4C.4a 已在隔离 Linux 容器的两个独立网络空间实测 WireGuard 握手和加密传输，
通过生产 API/零能力客户端验证接入规划、幂等、凭据轮换、过期/撤销、版本冲突及断网恢复。
专用回归 `docker-control-two-node-real` 仅在隔离测试容器增加 `NET_ADMIN`/`SYS_ADMIN`，
仍使用 `network none`，不发布端口、不使用宿主网络；生产服务权限不变。
4C.4a 不调用 Compose 应用/恢复；4C.4b 的 `docker-control-two-deployment-real`
使用两个独立 Docker Engine、PID/mount/net namespace 和真实 cron，
执行生产 CLI 接入/同步、真实 WS/TLS 客户端流量、账号与累计流量保持、
断网/版本冲突、轮换撤销及健康失败/INT/TERM 恢复。
专用测试容器需要 privileged 和独立 Linux 数据卷，但不挂宿主 Socket、
不发布端口、不修改生产 Compose；普通和近似 selector 不获得该权限。
节点从 `local-test-only-not-release-verified` 已安装夹具开始，不证明可信发布首次配置。
完整角色迁移/灾备另行定义，多服务器保持 `deferred`。阶段边界见
[4C 实施计划](documents/docker-menu-parity-plan.md#4c-多服务器控制后端)。

证书和 ACME 任务也由同一个宿主控制命令分发到 `ops` 镜像：

```bash
padm-docker tls manage
padm-docker tls validate --domain example.com
padm-docker tls install --domain example.com --cert /path/fullchain.pem --key /path/privkey.pem
padm-docker acme <issue|renew> --domain example.com --email admin@example.com --dns <dns_provider> --credentials /path/credentials
padm-docker acme schedule enable --domain example.com --email admin@example.com --dns <dns_provider> --credentials /path/credentials
padm-docker acme <issue|renew> --domain example.com --email admin@example.com --standalone
padm-docker acme schedule enable --domain example.com --email admin@example.com --standalone
padm-docker edit --http01 enable --preview
padm-docker edit --http01 enable --confirm PADM-DOCKER-EDIT
padm-docker acme <issue|renew> --domain example.com --email admin@example.com --webroot
padm-docker acme schedule enable --domain example.com --email admin@example.com --webroot
padm-docker acme schedule status
padm-docker acme schedule disable --domain example.com
padm-docker acme auto-renew
```

主菜单第 8 项可查看/校验证书、导入轮换、DNS-01/HTTP-01 standalone/webroot 申请或续期，并显式开关 HTTP-01 入口、管理自动续期；最终确认前不持有部署锁。
已配置部署必须使用部署记录的 ops 镜像，不能用 `--ops-image` 换成其他镜像。
候选证书检查有效期、域名和私钥匹配后，先执行 `nginx -t` 再重载并检查健康；
失败或中断恢复旧证书和 ACME 账户，保留其他域名及累计流量。
无消费者的域名只保存或校验证书，不修改当前入口和规格。
核心端 TLS 只处理配置中引用的同域名受管 `.crt/.key` 对，使用只读
`/etc/padm/secrets/tls` 挂载；全部消费者先校验，再定向重建核心或 reload Nginx，
逐服务检查健康，失败时尝试恢复全部消费者且累计流量不回退。
HTTP-01 standalone 使用非 root ops 容器的 `8080`，临时发布宿主双栈 TCP `80`；
域名必须解析到本机且公网 `80` 可达，不修改防火墙，也不提供 TLS-ALPN-01。
挑战前核对实际容器标签、镜像、挂载、部署与端口归属；外部或无法确认的监听拒绝。
只暂停本部署原本运行的 `80` 拥有者，同容器的 HTTPS 会短暂停机，不停止无关 `443` 服务。
成功、失败或信号后恢复原容器；原本停止的 TLS 消费者不启动。
续期先让 acme.sh 完成到期/ARI 判断，未到期不发布端口、不暂停服务；
恢复失败保留私有候选内的 `challenge.json` 容器 ID 记录，不继续下一域名。
webroot 必须已有受管 Nginx 入口 `21–25`/`27`/`29`，先显式设置 v3 `.tls.http01=true`；
旧规格不自动开放 `80`。专用 HTTP vhost 固定双栈 `80:8088`，只服务当前 TLS 域名的标准
`/.well-known/acme-challenge/<token>`，不沿用站点重定向、代理或订阅规则。
Nginx 只读挂载稳定的 `data/acme-webroot`；ops 仅写本次独占 `active/`，完成或中断清理该子目录，
不替换挂载根，不暂停 Nginx，也不额外发布端口。根目录为 `0750 10001:10001`，
拒绝链接、特殊文件、外部可写父目录和未完成挑战；清理失败保留候选与挑战，不继续下一域名。
申请不会隐式开启入口。关闭使用 `edit --http01 disable --confirm PADM-DOCKER-EDIT`；
启用 webroot 自动续期时，关闭、改域名、删除最后一个 Nginx 或回滚到关闭入口的快照均先拒绝，
须先停用该域名自动续期。未到期不创建挑战目录或改动服务。
自动续期需要该域名已有与验证方式匹配的受管 ACME 账户，不能为仅导入的外部证书
直接开启。DNS 将 `NAME=value` 凭据和续期输入保存在宿主
`secrets/renewal/<域名>/`，目录为 `0700 root:root`、文件为 `0600 root:root`；
凭据经标准输入进入工具，不放在调度、参数或 Docker 环境变量元数据中。
standalone 登记只保存 schema `2`、webroot 保存 schema `3` 请求，均无凭据文件；DNS 保持 schema `1`。
bundle 必须支持所有已启用登记的最高 schema；停用时事务删除该域名登记，允许重新使用兼容旧 bundle。
多个域名共用一个每日 03:17 的任务，优先 systemd timer（最多随机延迟 5 分钟），
否则使用正在运行的 cron；两个后端互斥，重复启用不增加任务，未到期正常跳过。
`down` 和卸载移除任务但保留私有输入，`up` 恢复；更新/回滚保留最新输入，
已启用时拒绝切到不支持续期的旧控制 bundle，外部同名任务不覆盖。
核心 TLS 底座不表示新增协议或完整管理。Linux amd64 与 arm64 仿真已通过双核心
TLS 夹具、WS 客户端流量及轮换恢复，全部 TLS 探测校验测试 CA/域名；
amd64 与 arm64 仿真另通过实际 HTTPS 订阅解析生成 sing-box 客户端、
两核 Reality Vision 公网目标握手、五路流量及恢复；隔离端点映射不代表公网入口、
第三方导入 UI 或其它目标兼容性通过。
真实 DNS、完整宿主重启、原生 arm64 和可信发布仍待验，
详见[真实 TLS 验收基线](documents/docker-tls-real-baseline.md)。
真实 systemd/cron 的隔离调度探针、双向迁移与容器重启已验证，不替代整机或 DNS 验收。

配置变更先生成候选文件、校验端口和 Compose，再备份当前状态并执行健康检查；失败时保留旧配置。Docker 入口安装的控制命令是 `/usr/local/bin/padm-docker`，实际 bundle、配置、数据、密钥、日志和备份分别位于状态根下的 `bundle/`、`config/`、`data/`、`secrets/`、`logs/` 和 `backups/`。

### 可信发布输入

首次配置向导会自动验证发布输入。需要独立检查或准备非交互配置时，也可先检查签名发布、控制 bundle 和 5 个固定 digest 镜像：

```bash
padm-docker release
padm-docker release --manifest /path/release-manifest.json \
  --bundle /path/release-manifest.sigstore.json --control-bundle /path/padm-docker-bundle.tar.gz
```

成功时标准输出只有包含 `release`、`images` 的 JSON；签名验证、归档校验和全部镜像拉取完成前不输出该结果，进度与错误写入标准错误。该命令不生成完整 spec 或凭据、不切换已安装控制脚本、不启动或重配服务；镜像拉取会更新宿主 Docker 缓存，本地发布资产也不代表离线镜像可用。输出 JSON 不是签名证明，后续配置仍须核对原 manifest 与 Sigstore bundle。

需要支持 Sigstore bundle v0.3 的 `cosign`。缺少该工具时命令停止，不跳过验签、不自动安装宿主工具；先通过独立受信的软件源或 Sigstore 官方发布说明核验并安装，再重试。固定发布身份和验证器信任来源不能由尚未验签的 manifest 指定。

### 用户流量与额度

`configure` 和 `update` 会为当前核心配置用户统计，并安装每分钟执行的宿主采集任务：优先使用 `padm-docker-traffic.timer`，无 systemd 时使用已运行的 cron。Xray 和 sing-box 均按稳定账号 ID 累计上传、下载流量；同一 UUID 在多个协议入口中合并计量，显示名称独立保留。

```bash
padm-docker traffic collect
padm-docker traffic show
padm-docker traffic limit <账号ID> 100
padm-docker traffic limit <账号ID> 0
padm-docker traffic reset <账号ID>
```

`collect` 立即采集并执行额度检查，`show` 显示已保存的计数；账号 ID 从 `show` 输出中读取。`limit` 的单位为 GiB，`0` 表示不限额，额度按上传与下载之和计算。`reset` 清零累计量并保留额度，重新启用因此恢复额度的用户。超额或恢复用户时会先校验配置，再仅重启对应核心，该核心的现有连接会短暂中断。

完整用户配置保存在 `config/<核心>/users.base`，超额用户仅从运行配置中停用。累计量、额度与采样基线保存在 `/etc/padm-docker/data/traffic/state.json`，不随核心重启、配置重建或版本回滚清零。采集失败会保留已有累计量；额度检查按分钟执行，可能有一个采样周期及任务延迟的超额，意外退出前尚未采集的流量无法补算。

双核心逐核采样、统一复验后一次提交累计；跨核心同 UUID 共享额度。两核候选均验证后才应用额度，任一重启失败或中断都会尝试恢复两核配置，累计量不回退。

sing-box 采集要求宿主提供 `nsenter` 和支持 HTTP/2 的 `curl`，通过容器网络命名空间访问 `127.0.0.1:10087`；Xray 使用容器内的统计命令访问 `127.0.0.1:10085`。统计端口不发布到公网，容器不挂载 Docker Socket。`down` 和 `uninstall` 会移除采集调度，`up` 和 `restart` 会恢复调度。

### 更新

更新只接受已签名的 CI Release manifest。默认命令读取最新 Release 的 manifest、Cosign 签发的 Sigstore bundle v0.3 和控制 bundle；也可以显式指定本地或 HTTPS 资产：

```bash
padm-docker update
padm-docker update \
  --manifest <URL|文件> \
  --bundle <URL|文件> \
  [--control-bundle <URL|文件>]
```

`padm-docker update` 同时更新五个镜像和宿主控制脚本，无需另行执行 `install`。更新事务依次验签 manifest、校验并暂存控制 bundle、预拉取五个固定 digest 镜像、校验当前配置、保存 `backups/update.*` 快照、切换镜像引用和控制 bundle 原子指针，再运行 Compose health check。拉取或校验失败时不切换现有部署；切换、启动、健康检查或采集调度失败时会尝试恢复旧配置、旧镜像引用和旧控制脚本。生产机不会在线编译镜像。需要新版本时，先由 CI 根据新的锁文件构建并发布，再在生产机执行 `padm-docker update`。

尚不支持控制脚本自更新的旧版需一次过渡：重新下载 `/root/install-docker.sh`，执行 `bash /root/install-docker.sh install --ref <本次发布的 40 位 commit SHA>`，再执行 `padm-docker update`。之后只需 `padm-docker update`。

### 回滚

```bash
padm-docker rollback
```

回滚只使用受管的最近一次 `update.*` 快照，默认退回一个版本，并同时恢复快照记录的控制脚本；旧快照没有控制 bundle 指针时只恢复部署配置和镜像，不猜测旧脚本版本。没有有效快照时直接失败，不猜测或拼接任意历史版本。已启用用户统计时，回滚目标 sing-box 必须具备 `with_v2ray_api`，否则会在停止现有部署前拒绝，避免丢失额度约束。回滚失败会尝试恢复当前版本，并保留备份路径供排障。
控制 bundle 必须声明支持快照规格版本；v2 快照不能交给仅支持 v1 的 bundle，v3 快照不能交给仅支持 v1/v2 的 bundle。合法旧版单核心快照仍可恢复，移除多余核心服务但保留累计流量。

### 卸载

```bash
# 停止并移除 Docker 控制命令；保留配置、数据、备份和镜像
padm-docker uninstall

# 在保留状态根的前提下，仅删除 deployment 记录中五个精确 digest 镜像
padm-docker uninstall --remove-images

# 生成最后备份后删除 /etc/padm-docker（不可逆，必须显式确认）
padm-docker uninstall --purge --confirm PADM-DOCKER-PURGE
```

普通卸载只清理本项目的 Compose 容器、网络和 CLI 链接，不执行全局 `docker prune`，也不删除其它 Compose project 或用户卷；脚本自动安装的 Docker Engine、Compose 插件和软件源不会由 `padm-docker uninstall` 卸载。`--purge` 仅删除带有效 Docker 模式标记的受管状态根；需要保留数据时不要使用它。

## 系统要求

padm 面向 Linux 服务器运行。代码会识别 Debian、Ubuntu、RHEL/CentOS/AlmaLinux/Rocky/Oracle Linux、Fedora 和 Alpine，并按系统使用 `apt`、`yum` 或 `apk` 安装必要组件。

| 项目 | 要求 |
| --- | --- |
| 权限 | 需要 root 或等价权限。 |
| 架构 | `x86_64/amd64`、`aarch64/arm64`。 |
| 基础命令 | 入口下载至少需要 `curl` 或 `wget`，wget 回退还需 `timeout` 限制总时长；完整包刷新需要 `tar`。 |
| 常用依赖 | 脚本会按功能安装或使用 `jq`、`nginx`、`acme.sh`、WireGuard tools、Fail2ban 等组件。 |
| 服务管理 | 核心服务优先使用 systemd；Alpine/OpenRC 路径有专门处理。主控/被控订阅控制服务目前要求 systemd 和 `python3`。 |

### Docker 版要求

| 项目 | 要求 |
| --- | --- |
| 操作系统 | Linux；Docker daemon 必须运行 Linux 容器。Windows、macOS 和 Docker Desktop 不在首发支持范围。 |
| 权限与连接 | root，rootful Docker Engine，本机 rootful Unix socket；不支持 rootless daemon、远程 context 或用户级 socket。 |
| Compose | Docker Compose CLI 插件（主版本 v2 及以上）。 |
| 架构 | `amd64` 或 `arm64`，主机和 daemon 架构必须一致。 |
| 主机命令 | `bash` 4+、`jq`、`sha256sum`、`tar`，以及 `curl` 或 `wget`；可信发布输入和签名更新还需要支持 Sigstore bundle v0.3 的 `cosign`（CI 当前使用 3.x）。缺少 Docker 时，`install-docker.sh install` 会先询问是否从 Docker 官方软件源安装 Engine、Compose CLI 插件及其宿主前置工具。 |
| 用户统计 | 正在运行的 systemd 或 cron；sing-box 还需宿主 `nsenter`（通常来自 `util-linux`）及支持 HTTP/2 的 `curl`。配置或更新时检查，缺少则停止。 |
| 内核能力 | 普通 profile 不需要额外 capability；WireGuard、Fail2ban、TUN/TProxy 等 `net-*` profile 需要按支持矩阵提供 `NET_ADMIN`、host network 或 `/dev/net/tun`。 |

首次执行 `install-docker.sh install` 时，如果检测不到 `docker` 命令，脚本会询问是否从 Docker 官方软件源安装 Docker Engine 和 Compose CLI 插件；回答否、未确认或安装失败都会停止，且不会初始化 `/etc/padm-docker`。宿主软件包或软件源已经完成的变更不会由脚本擅自删除。仅在命令缺失时触发询问；已有 Docker 但 daemon 或 Compose 不可用时仍直接报错，不会重装。自动安装目前只覆盖 Debian、Ubuntu、CentOS、Fedora、RHEL 的 rootful systemd 主机；其它发行版请先手动安装 Docker。脚本不会安装 Xray、sing-box、Nginx 等业务宿主依赖，也不会执行 `docker build`。检测到原生版已安装、正在运行或残留状态时会拒绝安装，请先明确清理原生部署；两种模式不提供隐式迁移。

> [!IMPORTANT]
> **CentOS / RHEL：** SELinux 处于 Enforcing 时，脚本会提示先手动关闭后再继续。

## 主菜单

padm 主菜单按任务对象分组，一个功能只放在一个主要入口里：

| 菜单 | 负责什么 |
| --- | --- |
| 🚀 安装与重装 | 新手选择指引；推荐直连、推荐 CDN、无域名 Reality、NaiveProxy、自定义安装、传统 TLS 兼容安装。 |
| 🔗 订阅与用户 | 可本机单独使用，也可初始化主控/被控，再处理发布订阅、多服务器协同、流量限额、同步和备份恢复。 |
| 🧭 协议与入口 | REALITY、XHTTP、Hysteria2、Tuic、入口端口和 CDN 入口地址。 |
| 🔐 站点与证书 | 传统 TLS fallback 站点、302 重定向、ALPN 诊断/修复和本机 TLS 证书。 |
| 🧱 路由与访问控制 | WARP、IPv6、Socks5、DNS/hosts、BT 阻断、域名/IP 阻断、直连例外和区域阻断。 |
| ⚙️ 核心与服务 | Xray-core / sing-box 生命周期、服务运行态、日志诊断和 Xray Geo 数据；首页只读本地状态。 |
| 🧰 系统与脚本 | 更新 padm、查看脚本安装状态、Fail2ban 防护、网络优化 / BBR。 |
| ⚠️ 高级/危险操作 | 卸载脚本和 VLESS Encryption 实验等高风险开关。 |

## 运行模型

padm 不是单个超长 Bash 文件，而是“独立入口 + 分模块运行时”：

1. 原生入口是 `install.sh`，Docker 入口是 `install-docker.sh`；两者分别维护 `/etc/padm` 和 `/etc/padm-docker`，不会互相迁移或混装。
2. 模块刷新会原子替换 `shell/`、`documents/`、`assets/`、`README.md` 和 `.padm-module-manifest`；失败时尽量恢复旧模块。
3. `shell/core/bootstrap.sh` 是运行时装配点，按顺序加载平台、运行时、协议、Reality、服务、路由、TLS、订阅、菜单等模块。
4. 交互菜单和正式子命令共用同一套模块。正式子命令包括 `RenewTLS`、`UpdateGeo`、`SyncSubscriptionGroups`、`SubscriptionControl`、`InstallSubscription`。
5. Docker 控制 bundle 位于 `docker/`，由宿主上的 `padm-docker` 直接调用 Docker CLI 和 Compose；容器不挂载 Docker Socket。
6. 排障时先找实际控制点：入口脚本、模块加载顺序、状态文件、生成配置和校验命令，而不是只看菜单文案。

| 路径 | 作用 |
| --- | --- |
| `install.sh` | 🚪 仓库入口；负责自刷新、参数解析、正式子命令分发和首次模块补齐。 |
| `install-docker.sh` | 🐳 Docker 独立入口；安装并刷新 Docker 控制 bundle，不构建镜像。 |
| `padm-docker` | 🎛️ 安装后的 Docker 宿主控制命令；调用固定的 `padm-docker` Compose project。 |
| `docker/` | 📦 Dockerfile、Compose、manifest、配置合同和生命周期实现。 |
| `shell/core/` | ⚙️ 平台检测、运行时 helper、协议模板、Reality/TLS/路由/服务/菜单等核心逻辑。 |
| `shell/subscription/` | 🔗 订阅发布、订阅组状态、用户账号、WireGuard 控制面、远程同步和流量统计。 |
| `shell/regression/` | 🧪 `framework/` 提供环境、runner 和 registry，`cases/` 单次加载 fixture、stub 与测试函数，`suites/` 只注册 selector、分组和组合。 |
| `shell/subscription_groups_regression.sh` | 🧪 唯一公开回归分发入口；统一分发 suite、aggregate、contract 和 composition selector。 |
| `shell/validate_install.sh` | ✅ 安装后的只读验收脚本。 |
| `documents/` | 📚 示例配置和英文 README。 |
| `assets/` | 🖼️ 传统 TLS fallback 静态站点模板。 |

## 安装后的控制点

这些路径是 padm 真正读写和校验的状态源。排障、备份、迁移或读代码时优先看它们：

| 路径 | 作用 |
| --- | --- |
| `/etc/padm/install.sh` | 🚪 已安装入口；`padm` 命令最终回到这里。 |
| `/etc/padm/.padm-ref` | 🏷️ 当前已安装模块 ref，用于脚本刷新状态展示。 |
| `/etc/padm/.padm-module-manifest` | 🧾 当前模块 manifest，用于检测模块集是否完整。 |
| `/etc/padm/xray/conf/` | 🧩 Xray 分片配置目录；用 `xray -test -confdir` 校验。 |
| `/etc/padm/sing-box/conf/config/` | 🧩 sing-box 分片配置目录；合并成 `config.json` 后校验。 |
| `/etc/padm/tls/` | 🔐 本机 TLS 证书、密钥和 acme 日志。 |
| `/etc/padm/subscribe/` | 🔗 面向客户端发布的订阅产物。 |
| `/etc/padm/subscribe_local/` | 📦 本机订阅缓存和中间产物。 |
| `/etc/padm/subscribe_groups/groups.json` | 🧭 订阅组状态真源，包含角色、服务器源、用户订阅、额度、同步和流量统计。 |
| `/etc/padm/subscribe_groups/backups/` | 💾 `groups.json` 备份目录。 |
| `/etc/padm/wireguard/` | 🔒 主控/被控 WireGuard 控制面状态、密钥和 peer 信息。 |
| `/etc/wireguard/wg-padm.conf` | 🔒 padm 控制面 WireGuard 配置。 |
| `/etc/padm/reality_entry_host` | 📍 当前 Reality 客户端入口地址。 |
| `/etc/padm/reality_targets_results.tsv` | 📊 Reality 目标库，按目标保留最新实测结果。 |

Docker 部署的实际状态源：

| 路径 | 作用 |
| --- | --- |
| `/etc/padm-docker/mode` | 🏷️ 固定为 `docker` 的模式标记，用于互斥和卸载保护。 |
| `/etc/padm-docker/bundle` | 🔗 当前已验证控制 bundle 的原子指针。 |
| `/etc/padm-docker/deployment.json` | 🧾 当前版本、profiles、端口和五个镜像 digest。 |
| `/etc/padm-docker/compose.json`、`images.env` | 🐳 当前 Compose 配置和固定镜像引用。 |
| `/etc/padm-docker/config/`、`data/`、`secrets/`、`backups/` | 💾 配置、运行数据、密钥和更新/卸载备份。 |

Docker 与原生菜单的逐项支持边界见
[Docker 版功能对照表](documents/docker-feature-matrix.md)。新增 Docker 能力时先更新
该矩阵和 `docker/contracts/features.json`，避免把“已有镜像”误认为“已有菜单功能”。

公网订阅和服务器间控制面是两套地址体系：

- 🌍 客户端订阅走 `/s/default/...`、`/s/clashMeta/...`、`/s/sing-box...` 等 HTTPS 路径。
- 🔒 主控/被控控制接口走 `/s/control/...`，只通过 WireGuard 内网访问，不提供公网 HTTP/HTTPS 来源回退。

## 协议选择

常规推荐按目标选协议，而不是按“看起来功能更多”选协议：

| 目标 | 推荐协议 | 说明 |
| --- | --- | --- |
| 新手直连、有域名或普通自用 | `1` VLESS Reality Vision | 当前主线推荐；不依赖本机伪装站点。 |
| CDN / 反代 | `2` VLESS Reality XHTTP | 新建 CDN 节点优先；使用 XHTTP 与 XMUX。本项目只用 Xray 生成 XHTTP，sing-box 当前没有 XHTTP transport。 |
| 没有域名 | 无域名 Reality | 菜单会走 Reality 快速路径。 |
| TLS 指纹抗性 | `5` NaiveProxy | 需要真实域名和证书；依赖 sing-box。 |
| UDP、移动网络、弱网 | `3` Hysteria2 | Hysteria2 节点流量不套 CDN/Nginx；需要 UDP 可达，可按需使用端口跳跃。 |
| 明确需要 AnyTLS | `4` AnyTLS | sing-box AnyTLS 场景；确认客户端支持后再用。 |
| 兼容或迁移 | 高级协议 `21..31` | 仅在旧客户端、存量 CDN、传统 TLS 或迁移窗口需要时选择。 |

能力库是协议选择、核心支持、Nginx 拓扑和订阅输出的统一事实源。`category=node` 的公开 ID 才能传给 `--protocols`；旧版公开编号已废弃，不再作为 CLI、菜单或订阅同步输入。

### 推荐公网节点能力

| ID | 能力 | 项目生成核心 | Nginx 模式 | UDP | CDN | 推荐场景 |
| --- | --- | --- | --- | --- | --- | --- |
| `1` | VLESS Reality Vision | Xray / sing-box | `none` | 否 | 否 | 新手直连、有域名或无域名 Reality 首选。 |
| `2` | VLESS Reality XHTTP | Xray | `none` | 否 | 条件支持 | 新建 CDN / 反代首选；XHTTP 在本项目中是 Xray-only。 |
| `3` | Hysteria2 | sing-box | `none` | 是 | 否 | 移动网络、UDP、弱网和端口跳跃场景；节点流量不经过 CDN/Nginx。 |
| `4` | AnyTLS | sing-box | `none` | 否 | 否 | 明确需要 sing-box AnyTLS 且客户端支持时选择。 |
| `5` | NaiveProxy | sing-box | `none` | 否 | 否 | 明确需要 TLS 指纹抗性且有真实域名和可信证书时选择。 |

### 高级公网节点能力

gRPC、WebSocket 和 HTTPUpgrade 是高级协议，不是删除协议。它们仍可显式选择，但新建节点优先使用推荐能力，特别是直连 Reality Vision 或 CDN/反代 Reality XHTTP。

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
| `none` | 核心直接监听公网；节点流量不安装、不启动 Nginx。 | Reality Vision、Reality XHTTP、Hysteria2、AnyTLS、NaiveProxy、Reality gRPC、Trojan direct、Shadowsocks、TUIC。 |
| `http_front` | Nginx HTTP/1.1 反代，显式处理 `Upgrade` / `Connection`。 | WS / HTTPUpgrade 能力 `21..23`。 |
| `grpc_front` | Nginx HTTP/2 + `grpc_pass` 反代。 | gRPC TLS 能力 `24..25`。 |
| `xhttp_front` | 预留给显式 XHTTP TLS/CDN/反代能力；默认不套到 Reality XHTTP。 | 当前无默认公网节点使用。 |
| `fallback_backend` | Xray fallback 后端，只允许 TCP+TLS 能力使用。 | `27`、`29`。 |
| `acme_only` | Nginx 可服务证书申请或订阅发布，不代表节点流量经过 Nginx。 | 证书与订阅服务。 |

sing-box 订阅输出中的 `utls.fingerprint=chrome` 是客户端兼容/模拟选项，不是抗封锁保证。需要抗 TLS 指纹识别时，优先考虑 Reality Vision、Reality XHTTP 或 NaiveProxy。

## Reality 语义

Reality 里有三个容易混淆的概念：

| 概念 | 含义 | 出现位置 |
| --- | --- | --- |
| 📍 entry | 客户端实际连接到你的服务器的地址 | 订阅链接 `@host`、Clash `server`、sing-box `server` |
| 🎭 Reality target | Reality 伪装访问的外部真实 HTTPS 站点 | Xray `realitySettings.target`；sing-box `tls.reality.handshake` |
| 🧾 Reality SNI | Reality 握手使用的 SNI | Xray `serverNames`；sing-box `tls.server_name`；订阅 `sni/servername` |

常见配置是：客户端连接 `node.example.com`，Reality target 使用已实测的 `target.example.com:443`，Reality SNI 使用 `target.example.com`。

Reality Vision、Reality XHTTP 和 Reality gRPC 均不申请本机 TLS 证书；纯 Reality 安装不创建或清理站点，不操作 ACME/Cron，也不停止、启动或重载 Nginx。`--reality-domain yes` 是严格域名模式，只允许单选 Reality Vision `1`，并校验 entry 域名及 DNS；协议 `2`、`26` 或任何多选组合会在安装依赖和写配置前拒绝。

Reality entry 按 `--entry-host`、`--domain`、`/etc/padm/reality_entry_host`、`currentHost`、公网 IP 的顺序选择。普通单选 Reality 端口按显式 `--port`、历史端口、`443` 的顺序选择；多协议继续使用各自端口，不把顶层 `--port` 注入 Reality 子端口。启用 443 共存后，客户端仍连接记录的公网端口，核心继续复用已记录的内部端口。

交互安装没有显式目标或可复用目标时，仅提供两种方式：`1：检测候选后选择`（默认）和 `2：手动输入`。方式 1 先检测全部候选，仅展示 `cdn_risk=no` 且评分为 A 的实测结果，由用户选择，不自动替用户选站；方式 2 接受 `host[:port]`，端口默认 `443`，留空取消。非交互安装优先使用 `--reality-target` 或已有目标；都没有时检测全部推荐候选，从本次 `no + A` 结果中随机选择一个，不混入未复测的旧目标库记录。无 Xray、检测失败或没有 A 级时安装失败，不使用 B/C 级或未经检测的兜底目标。选中后仍复测全部 A/AAAA，随机推荐必须保持 `no + A` 才能写配置。每个地址独立评分并取最差结果：任一地址属于 AS13335 或可响应 `cloudflare.com` SNI 即标记 `cloudflare_relay`；DNS CNAME 指向已知 CDN 边缘域名，或 ASN/组织属于已知专属 CDN 时标记 `cdn_edge`，两者都会拒绝。DNS、ASN 或 TLS 探测不完整则标记 `unknown` 并拒绝。手工仅接受 `no + A/B/C`，其中 B/C 会明确警告；检测当前已安装目标只告警，不会静默切换配置。`java.com`、`nodejs.org` 与 `riotcdn.net` 及其子域名属于不可覆盖的静态硬风险，候选刷新、扫描导入、自动/手工选择和 Docker 部署都会拒绝。

内置候选池保留 25 个已在本机原生网络按全部 A/AAAA 实测为 A 级的推荐候选，不含普通备选；这不保证用户服务器也能得到 25 个 A 级，安装时仍按当地网络重新检测。交互安装由用户选择，非交互未指定且无已有目标时按上述规则随机选 A 级。已知 CDN/边缘代理域名保留在独立黑名单清单中，用于运行时过滤、审计和黑名单展示，不从候选池输出。候选筛选统一按关键词处理，`dev`、`developer`、`开发者` 是同一筛选别名。

Reality 目标站主结果库使用 16 列 TSV 写入 `/etc/padm/reality_targets_results.tsv`，末列为实测 IP 的英文地理位置，例如 `Los Angeles, United States`；兼容旧 15 列记录。位置来自 IP 地理查询，成功结果按完整 IP 复用；批量写入仅查询缺少缓存的唯一 IP，沿用 `PADM_REALITY_SECONDARY_JOBS` 分批并行，默认 8、最多 16 个请求，完成后统一入库。城市缺失时回退区域或国家，查询失败显示 `Unknown`，不影响评分与切换。物理上仅保留每个目标最新状态仍为 `cdn_risk=no`、评分为 A 且未命中静态或自定义黑名单的记录。目标的新结果降为 B/C/FAIL、风险或 `unknown` 时会移除旧 A；空批次写入也会清理旧格式风险记录。评分包含 TLS 1.3、`X25519MLKEM768` 和证书链长度；可选目标按 `same_asn > same_provider > different_network > unknown`、证书链长度、检测时间排序。

`协议与入口` -> `REALITY 管理` 可检测当前目标、刷新目标库、运行 RealiTLScanner、切换 A 级目标、查看 PQC/ML-DSA-65 状态和配置 443 共存分流。“刷新目标库”统一选择范围：默认复测目标库与推荐候选，并自动补测尚未出现在结果文件的 `recommended=yes` 目标；选择“全部候选”可覆盖全部内置/托管候选。查看与详情页共用选择确认流程，取消或切换失败不会提前覆盖当前目标状态。

> [!WARNING]
> **扫描风险：** RealiTLScanner 是高级功能，云端扫描可能导致 VPS 被标记；脚本会在执行前提示确认。

## XHTTP 与 CDN

安装 `2. VLESS Reality XHTTP` 后，在 `协议与入口` -> `XHTTP 管理` 调整协议参数：

| 层级 | 内容 |
| --- | --- |
| ✅ 普通设置 | 查看当前配置、选择场景预设、切换 `auto` / `packet-up` / `stream-up`。 |
| 🧪 高级设置 | 调整 XMUX、path/host、header、packet、stream 参数。 |
| ⚠️ 实验功能 | 配置或关闭上下行分离 `downloadSettings`。 |

默认推荐值面向日常和 CDN：`mode=auto`，`xmux.maxConcurrency=16-32`，`hMaxRequestTimes=600-900`，`hMaxReusableSecs=1800-3000`。每次修改都会先写临时配置并执行 Xray 校验，失败会自动回滚并提示日志路径。

XHTTP 在本项目中由 Xray 生成；sing-box 当前没有 XHTTP transport，因此不会输出 sing-box XHTTP 客户端配置。

`协议与入口` -> `CDN 入口管理` 只负责订阅里的客户端入口地址覆盖，例如 CDN CNAME、优选 IP 或多个入口地址。XHTTP 的 mode、XMUX、path/host 等协议参数仍在 `XHTTP 管理` 中调整。

## 传统 TLS 与本机站点

`站点与证书` -> `传统 TLS fallback 维护` 只服务于传统 TLS/fallback 协议。当流量没有命中代理协议时，Nginx fallback 可以展示本机静态页面或 302 跳转。

这个入口提供：

- 🖼️ 20 个轻量静态站点模板，并在安装或更换时随机化标题、文案、按钮、卡片和主题色。
- ↪️ 302 重定向维护。
- 🔎 ALPN 诊断/修复，检查 Xray fallback、`fallbacks[].alpn=h2` 和 Nginx h2 fallback 是否匹配。
- ✅ 写入后执行 `xray -test -confdir /etc/padm/xray/conf`，失败自动回滚。

Reality Vision、Reality gRPC 和 Reality XHTTP 不依赖本机静态站点。Reality 的伪装由外部 target 和 SNI 完成。只有你继续使用 VLESS TCP TLS Vision、WS TLS、gRPC TLS、Trojan TLS 等传统 TLS/fallback 协议，或确实要在本机展示网站时，才需要维护这个入口。

## 订阅与用户

订阅系统按服务器角色组织；本机和主控首页只保留 `订阅与用户`、`订阅同步` 以及角色对应的协同/控制入口，低频维护动作放在对应菜单内。

| 状态 | 菜单形态 | 适合做什么 |
| --- | --- | --- |
| 🟡 未初始化 | `本机单独使用` / `这台作为主控` / `这台作为被控` | 单机可直接管理本机订阅；需要多服务器时再选择主控或被控。 |
| 🟢 主控 | 主控首页提供订阅与用户、订阅同步、被控服务器和本机控制面 | 统一查看本机自用与分享订阅，创建分享订阅、添加被控服务器、执行同步和限额治理。 |
| 🔵 被控 | 被控首页直接提供接入、状态、凭据和控制面动作 | 粘贴主控邀请、提供本机节点给主控、查看 WireGuard 与同步状态。 |

主控和本机模式首页都直接提供统一的 `订阅同步` 菜单：立即完整同步、开启/关闭自动同步、设置间隔、状态与排障、状态备份与恢复。自动同步开关控制节点配置变更通知后的同步和 cron；分享订阅及被控服务器的手动管理动作仍立即同步一次，不改变自动同步设置。

首页的 `订阅与用户` 统一处理链接刷新、分享订阅创建/维护和流量限额。`分享订阅` 与 `流量与限额` -> `管理分享订阅与额度` 共用同一个列表和详情；列表、详情直接显示已保存用量及限额状态，选一次即可修改额度、启停或同步，支持多选，不隐式采集流量。新建 ID 或编辑额度输入有误时在当前字段重试，未保存的草稿不会写入。管理员自用订阅仍由本机协议配置自动维护，不写入 `user_groups`、不参与额度治理，也不会通过主控同步下发；统一的是管理入口和发布流程。

- 主控会同步所有已启用的被控服务器源，不再另设全局“远程同步”开关；在 `管理被控服务器` -> `管理已有被控服务器` 选择一次目标，即可连续更新凭据、启停、检查连接、同步或移除，失败后保留当前目标。
- 同步会先完成本机配置，再按来源处理被控服务器快照。只要本机成功且远端同步结果可解析，就发布本次成功来源；失败来源从本次输出排除，并将整体标记为“部分失败”。仅远端用户没有任何可用来源时，保留该用户上一版输出；本机失败或远端结果整体无效时，保留整版公网订阅。
- 修改任一被控的 Reality 目标等节点配置后，被控会通过 WireGuard 通知主控；主控自动同步开启时会重新生成本机节点、拉取启用来源并发布可用来源。外层 HTTPS 订阅地址不变，其他成功服务器节点仍会保留。
- 被控服务器不提供主动同步菜单；配置变更通知失败时，请在主控执行“立即完整同步”。

本机或主控创建分享订阅推荐流程：

1. 在本机或主控首页进入 `安装/更新发布服务`，配置公网订阅入口。
2. 在同一菜单进入 `分享订阅` -> `新建分享订阅`，使用英文、数字或短横线 ID，例如 `team-a`。
3. 按向导选择可用服务器源和流量上限。
4. 保存后立即执行一次完整同步，不改变自动同步设置。托管账号 `sub_<ID>` 会写入核心配置。
5. 完整同步完成后，在分享订阅管理页查看链接；首页的 `立即同步并更新链接` 也可刷新全部链接。

多服务器协同推荐流程：

1. 主控服务器从本机订阅首页进入 `启用主控协同` 完成初始化，再进入 `管理被控服务器` -> `创建被控邀请`，输入一次被控别名。主控会自动预留 WireGuard 地址。
2. 被控服务器进入 `接入主控`，粘贴邀请即可完成初始化和主控 Peer 导入；无需填写地址。成功后复制一次接入回执。
3. 回到主控服务器，从主控首页进入 `管理被控服务器` -> `完成被控接入`，粘贴回执即可按预留别名完成 Peer、服务器源和控制 Token 写入，并立即完整同步。
4. 需要暂时排除某台被控时，在 `管理已有被控服务器` 选择目标并停用；清理远端托管账号后立即同步，保留 Peer、Token 和历史状态。启用、凭据更新及移除后也立即同步。
5. 待完成邀请可按别名查看或取消；邀请和回执都是 bearer secret，列表、普通状态和健康结果不会显示完整秘密。丢失邀请时应取消并重建。
6. 旧版 `main` / `controlled` 凭据仅保留在明确命名的维护入口，用于更新已有连接；首次接入只接受邀请/回执。包含长期控制 Token 的回执或旧版被控凭据只通过可信通道传递。
7. WireGuard 使用 UDP，控制 API 只在隧道内使用 HTTP，不需要 TLS 证书；客户端订阅继续单独使用公网 HTTPS。

`订阅同步` -> `状态备份与恢复` 只作用于 `/etc/padm/subscribe_groups/groups.json`。恢复备份或重建状态前会先要求输入 `yes`，确认后才创建当前状态备份；当前结构为精确的 `version: 6` 单组根对象，不再持久化 `groups[]`、`active_group` 或流量汇总字段，并按 Xray / sing-box 核心分别保存流量基线。首次读取旧 `version: 2`、`3`、`4`、`5` 状态时会原子迁移；其中 v5 聚合基线先保存为兼容基线，并在首次新格式采集后替换为按核心基线。旧文件会备份到对应的 `groups-pre-v3-migration-*`、`groups-pre-v4-migration-*`、`groups-pre-v5-migration-*` 或 `groups-pre-v6-migration-*`；多组、其他旧版结构以及含额外、缺失或无效字段的状态会被拒绝。

## 路由与访问控制

`路由与访问控制` 负责服务端出站和访问策略，不是客户端配置教程。

| 功能 | 说明 |
| --- | --- |
| 🧭 分流工具 | WARP WireGuard 出站、IPv6 出站、Socks5 中继、DNS 分流、DNS/hosts 覆盖。 |
| ⛔ BT 下载管理 | 通过协议嗅探阻断已识别的 bittorrent 流量；加密、混淆或部分 uTP 场景无法保证完全覆盖。 |
| 🧱 访问控制 | 域名/IP 阻断、直连例外、区域阻断。 |

Xray 访问控制使用 routing + blackhole/direct；sing-box 使用 remote rule_set、domain_suffix/domain 和 ip_cidr。直连例外会放在阻断规则之前，适合系统更新、证书签发或必须直连的客户端服务。区域阻断属于危险操作，可能影响系统更新、证书申请和应用连接。

> [!NOTE]
> **安全写入：** 修改访问控制前会快照相关规则文件；写入后会执行 Xray 和 sing-box 校验，失败自动回滚并提示日志路径。

## 核心与服务

`核心与服务` 首页只读取本地版本、配置、服务和 Xray Geo 状态，不执行配置检查或访问网络。即使尚未安装核心，也可以进入页面查看状态和执行不依赖本机二进制的只读扫描；远端版本只在明确升级、回退或试跑预发布版时获取。

### Xray 主核心与 sing-box 辅助核心

本项目支持保留 Xray 作为主核心，同时增量启用 sing-box 作为辅助核心。操作步骤如下：

1. 先通过 `安装与重装` 安装 Xray。
2. 打开 `协议与入口`，进入 `Hysteria2` 或 `Tuic`，选择安装。
3. sing-box 会独立安装、生成自己的分片配置并运行对应服务；Xray 的配置和服务会继续保留，订阅和状态页会同时读取两套核心。

这不是 `--core both` 模式；`--core` 仍然只能填写 `xray` 或 `sing-box`。从 `安装与重装` 重新执行完整的 sing-box 安装会切换主核心并清理 Xray。当前公开的辅助核心增量入口是 Hysteria2 和 Tuic。

辅助 Hysteria2/TUIC 重装时，回车一次即可复用本协议全部用户、端口和网络参数；选择 `n` 后逐项调整，仍可保留用户只修改端口或网络参数。取消输入或前置校验失败不会进入安装事务，也不影响主核心及其他协议。

Hysteria2 安装会统一生成服务端、Clash Meta 和 sing-box 订阅参数：默认使用 Brutal 固定带宽，带宽按客户端视角填写（下行是服务端到客户端，上行是客户端到服务端）；选择 BBR 时不写入固定带宽，由客户端使用自适应 BBR。端口跳跃会在 sing-box 订阅中生成 `server_ports` 范围。混淆为可选项，支持 `salamander` 和 `gecko`，开启后会同步到 Clash Meta、sing-box 和 Hysteria2 URI；回车重装会保留已有模式和混淆配置，输入 `off` 可关闭混淆。

首页固定为 6 个入口：

1. Xray-core 生命周期
2. sing-box 生命周期
3. 服务运行态
4. 日志与诊断
5. Xray Geo 数据
6. 返回主菜单

`安装与重装` 只在主菜单提供；不再有独立的“配置健康与兼容”页面。两个核心生命周期页使用相同顺序，并统一提供“检查当前配置”“扫描升级风险”“试跑预发布版”。结果显示为“通过”“需关注”“失败”或“无法检查”。前两项只读且不联网；预发布版试跑不会替换二进制或操作服务。

Xray 的“检查当前配置”内部依次执行运行检查和严格检查：运行检查失败显示“失败”，仅严格阶段未通过显示“需关注”。sing-box 会先合并分片配置，再执行 `sing-box check -c /etc/padm/sing-box/conf/config.json`。技术阶段和日志路径只在结果详情中显示。

升级或回退核心时，脚本先下载目标版本到临时目录，用目标二进制校验当前配置；校验通过后才替换 `/etc/padm/xray/xray` 或 `/etc/padm/sing-box/sing-box` 并重启服务。若新核心启动失败，会尝试恢复旧二进制。

Nginx 只在当前协议、站点或订阅配置确实依赖它时可启动、停止、重启或平滑 reload；已安装但不属于 padm 当前依赖的 Nginx 只读。Nginx 配置仍由协议、站点和订阅入口管理，服务页只负责状态与动作。Xray `geosite.dat` / `geoip.dat` 的更新、状态和定时任务统一位于 `Xray Geo 数据`。

### sing-box 统计版与流量恢复

原生部署的 sing-box 主核心、副核心及 Docker 的 `padm-sing-box` 镜像统一使用本仓库 CI 从上游源码构建的统计版，保留上游默认构建标签并追加 `with_purego,with_v2ray_api`，具备 Hysteria2、TUIC 等协议的按用户流量统计能力。服务器直接下载 Linux amd64 / arm64 安装包或镜像，无需现场编译。

`with_grpc` 控制完整的 gRPC 传输实现；未启用时仍有默认 gRPC lite，本项目的 Reality gRPC 配置可以使用。按用户统计由 `with_v2ray_api` 独立启用，Hysteria2 和 TUIC 也不依赖 `with_grpc`。

Docker 镜像按 `versions.lock` 固定统计包版本和双架构 SHA256；官方包摘要单独保留，用于统计版构建时校验 Cronet 来源。Docker 已接入上述用户采集和额度管理，执行 `padm-docker update` 会同时更新镜像、宿主控制 bundle 并初始化统计。尚不支持自更新的旧版先按“更新”章节完成一次过渡刷新，必须使用新下载的入口，避免旧 `padm-docker install` 遗漏新增共享模块。现有协议配置会保留，协议入口仍以 Docker 支持矩阵为准。以下菜单步骤适用于原生部署。

若旧核心出现 `v2ray api is not included in this build`，或曾清理统计配置后恢复连接，请在运行 sing-box 的服务器上执行：

1. 从 `系统与脚本` 更新 padm 脚本。
2. 进入 `核心与服务` -> `sing-box 生命周期` -> `升级稳定版`，切换到已发布的统计版。
3. 在 `核心与服务` 确认 `sing-box 用户统计能力` 为“支持”、服务正常，并执行“检查当前配置”。

升级成功后会根据现有协议用户自动恢复 `14_stats_api.json` 并重载核心，统计 API 仅监听 `127.0.0.1:10087`；已有端口、证书和用户凭据继续保留。统计恢复失败时会尝试回滚核心和配置。复用上次安装配置时，也会将缺少统计能力的旧核心切换为统计版。未采集期间的历史流量无法补算，恢复后的新流量继续按现有账号归集。

稳定版、预发布版试跑和版本回退均只选择本仓库已发布的 `sing-box-v<上游版本>`，安装时校验资产摘要、实际版本和 `with_v2ray_api` 标签；缺少安装包或校验失败会停止，不会替换当前核心。

维护者可运行 Actions 的 `Build sing-box Traffic Stats` 工作流，`version` 留空时读取 `versions.lock`，也可指定上游标签（如 `v1.14.0`）。推送至 `main` 时，仅统计版构建文件、统计解码器、镜像检查或相关版本锁输入变化才进入构建准备；无关锁变化跳过。构建逻辑、Alpine 运行依赖或同版本官方摘要变化，以及手动运行，都会重新验证已发布版本，但不会覆盖已发布资产；日常巡检和已发布版本的锁升级仍可复用统计包。两个架构均须通过原生启动、Naive/Cronet 加载、Hysteria2/TUIC 实际传输和用户统计检查，再将本次候选包放入实际 Dockerfile，使用锁定的 Alpine 依赖完成镜像 smoke，才会发布二进制包、对应源码包和 `SHA256SUMS`。二进制包包含 `LICENSE` 和构建信息；统计版 release 不占用 padm 自身的 latest 标记。首次使用前需等待该工作流成功发布。

`Refresh Upstream Versions` 每天北京时间 11:17 调度检查官方 sing-box 最新稳定版（GitHub 调度可能延迟），也可手动运行。发现尚未发布的统计版时，自动调用上述双架构构建工作流；日常巡检复用已完整发布的版本。刷新会更新 Docker 版本锁并创建或继续更新同一个 PR：保留人工提交，合并 `main` 后刷新锁，以普通 push 更新分支；冲突、多个候选 PR 或并发分支变更会明确失败。即使锁没有变化，也会继续检查该 PR 当前提交的 Docker CI，补派缺失或待审批的检查，真实测试失败则保留失败。统计版构建失败时工作流仍报告失败，但允许为已发布版本刷新依赖锁，避免旧 APK 下架阻断修复；失败候选不会进入锁。自动刷新只选择本仓库已发布的正式统计版，忽略草稿和预发布版。更新 PR 仍需合并，Docker CI 在两种架构上检查统计标签、API 启动及 Cronet 加载后才允许发布镜像。需要预发布版时仍可手动指定 `version` 运行统计版工作流。

## 系统与脚本

`系统与脚本` 负责 padm 自身和宿主机辅助项：

- 🔄 更新 padm 脚本；若订阅控制服务已启用或正在运行，会同步刷新并重启。刷新失败不会回滚脚本更新，界面会提示从控制面维护入口重试。
- 🧾 查看入口校验、版本、ref 和 manifest。
- 🛡️ 管理 Fail2ban 防护，包含 SSH 和 `/s/control/` 的基础防护入口。
- 🚀 查看或启用网络优化 / BBR。

网络优化推荐项只启用当前内核提供的官方 `bbr`，并写入 padm 自己管理的 `/etc/sysctl.d/99-padm-bbr.conf`：

```conf
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

关闭时只删除 padm 自己写入的 sysctl 文件，并尝试恢复启用前的拥塞控制和 qdisc，不会改动用户其它 sysctl 文件。

## 高级实验

`高级/危险操作` -> `VLESS Encryption 实验` 可为 Xray Reality 节点启用实验加密。脚本调用 `xray vlessenc` 生成参数：

- 🧭 Reality Vision：`VLESS Encryption + XTLS Vision`
- 🌐 Reality XHTTP：`VLESS Encryption + XTLS Vision + XHTTP XMUX`

> [!CAUTION]
> **兼容性提醒：** default VLESS 分享链接和 Mihomo（原 Clash.Meta）订阅会携带 experimental encryption 字段；需 Mihomo v1.19.13+。sing-box 上游尚不支持该字段，因此 sing-box 订阅仍会省略。该功能属于高级实验，不建议新手默认开启。

## 参数参考

| 参数 | 可选值 | 默认/行为 | 说明 |
| --- | --- | --- | --- |
| `--install-type` | `install`、`custom`、`reality` | 无自动参数时进入交互菜单；传其它安装参数但不传本参数时默认 `custom` | 安装类型。 |
| `--core` | `xray`、`sing-box`、`1`、`2` | `xray` | `1` 等同 `xray`，`2` 等同 `sing-box`。 |
| `--protocols` | 当前公开协议编号，逗号分隔 | 无固定默认 | 自定义安装协议，例如 `1` 或 `1,2,21`；旧版 `0..13/20` 编号已废弃。 |
| `--list-protocols` | 无 | 输出后退出 | 列出可安装的公网节点能力。 |
| `--list-capabilities` | 无 | 输出后退出 | 列出公网节点、内部能力和上游已知能力。 |
| `--show-risky-protocols` | 无 | 输出后退出 | 列出带风险提示的高级公网节点能力。 |
| `--domain` | 域名 | TLS 安装时必须提供或交互输入 | TLS 证书域名；也是 Reality entry 的第二优先级，但 Reality 不为其申请证书。 |
| `--entry-host` | 域名或 IP | 优先于 `--domain`、历史 entry、`currentHost` 和公网 IP | Reality 客户端实际连接地址。 |
| `--reality-target` | `host[:port]` | 未传时进入目标站选择器；无可接受的安全结果则失败 | Reality 伪装目标站；显式目标也必须通过实时风险校验。 |
| `--reality-server-name` | SNI 域名 | 默认等于 target host | Reality SNI。 |
| `--port` | 端口号 | TLS 默认 `443`；单选 Reality 为显式端口 > 历史端口 > `443` | TLS 入口端口或单选 Reality 客户端连接端口；多协议不注入 Reality 子端口。 |
| `--tls-ca` | `letsencrypt`、`zerossl`、`buypass` | `letsencrypt` | 证书 CA。 |
| `--dns-api` | `yes`、`no`、`y`、`n` | `no` | 是否使用 DNS API 申请证书。 |
| `--dns-api-type` | `cloudflare`、`aliyun`、`1`、`2` | `cloudflare` | DNS API 服务商。 |
| `--dns-api-wildcard` | `yes`、`no`、`y`、`n` | `no` | 是否申请 `*.根域名` 通配符证书。 |
| `--cloudflare-api-token` | token | 也可用 `PADM_CLOUDFLARE_API_TOKEN` | Cloudflare DNS API Token。 |
| `--cloudflare-zone-id` | zone id | 可选，也可用 `PADM_CLOUDFLARE_ZONE_ID` | 设置 `CF_Zone_ID`，减少 Zone 查询依赖。 |
| `--aliyun-api-key` | key | 也可用 `PADM_ALIYUN_API_KEY` | 阿里云 AccessKey ID。 |
| `--aliyun-api-secret` | secret | 也可用 `PADM_ALIYUN_API_SECRET` | 阿里云 AccessKey Secret。 |
| `--reuse-last` | `yes`、`no`、`y`、`n` | 已有配置时默认复用；交互回车保留 | `no` 重新填写安装参数和用户，保留证书和订阅，不清空现有安装。 |
| `--clean-acme` | `yes`、`no`、`y`、`n` | 忽略 | 仅为兼容旧脚本保留；重装始终保留 ACME 证书和账号配置。 |
| `--reality-domain` | `yes`、`no`、`y`、`n` | `no` | 严格域名模式，仅支持单选 Reality Vision `1`；优先用 `--entry-host`，其次 `--domain`。 |
| `--subscribe-port` | 端口号 | 无固定默认 | 订阅发布服务端口。 |
| `--install-nginx` | `yes`、`no`、`y`、`n` | `no` | 订阅或反代需要 Nginx 时是否自动安装。 |
| `--uuid` | UUID 或密码 | 新建时随机生成；复用时保留已有用户 | 纯密码的自定义协议可用普通密码；含 VLESS、VMess 或 TUIC 时必须是 UUID。复用历史时，显式值须匹配已有用户，否则在安装前失败。 |
| `--user` | 用户名 | 新建时随机生成；复用时保留已有用户 | 初始用户名；与 `--uuid` 同传时须匹配同一已有用户。需要新建用户时指定 `--reuse-last no`。 |

完整参数以 `bash install.sh --help` 为准。

## 验收与回归

安装后只读验收：

```bash
bash shell/validate_install.sh [domain]
```

检查公网 HTTP/HTTPS/TLS 可达性：

```bash
bash shell/validate_install.sh --online example.com
```

回归统一通过 selector dispatcher 运行，按三个层级使用：

Windows 本机使用 PowerShell 7.3 或更新版本运行专用 Docker Linux 回归入口，首次运行自动构建 `padm-regression:local`
工具镜像，后续复用构建缓存：

```powershell
.\shell\regression\run-docker.ps1 -Selector fast
.\shell\regression\run-docker.ps1 -Selector ui-subscription-workflow-focused
.\shell\regression\run-docker.ps1 -Selector docker-routing-domains-workflow
.\shell\regression\run-docker.ps1 -Selector ci -Jobs 3
```

普通定向 selector 默认 `-Jobs 2`，完整 `ci`、`ci-pr`、`all` 默认 `-Jobs 3`，
完整 `docker-contracts` 默认 `-Jobs 6`（支持 1–8）。
Direct/Block CSV 或菜单派发改动优先使用 `docker-routing-domains-workflow` 和 `docker-menu`；
工作流定向复用原事务断言，不替代 Schema、生成器、其它路由矩阵和真实流量验收。
各任务先运行匹配改动的定向回归，集成完成后集中执行完整回归。
入口归档当前工作区的已跟踪文件和未忽略的新文件，包含未提交修改，不包含 `.git`
和 `.tmp-*`；源码、`TMPDIR`、`HOME` 在容器内部，不挂载 Windows 工作目录。
每次运行的源码快照、日志和结果保存在 `.tmp-regression-docker-*/`，测试失败保留日志并返回原退出码。
镜像只装工具，不固化项目源码；使用 Debian 官方依赖、固定 digest 的官方静态 jq 1.8.2 和官方 Docker CLI/Buildx/Compose，
不安装 daemon、不挂 Docker socket，运行时无网络。工具层需要重新安装时使用 `-Rebuild`。
同一仓库、同一 Windows 用户的各任务和 worktree 试用三个回归槽位；普通 selector 占一个，
`ci`、`ci-pr`、`all` 和 `docker-contracts` 占两个。完整回归登记等待后，不再放行新普通任务，
优先等待所需槽位；取得槽位后，普通任务可以使用剩余一槽。最多三个普通任务或一套完整回归加一个普通任务，
两套完整回归不能重叠；没有足够空位时自动等待，不保证严格 FIFO。
排队前生成源码快照；镜像构建串行化并固定镜像 ID；异常退出后的槽位接管会先清理本入口标记的残留容器。
完整回归复用输入相同的成功结果：源码按路径、内容、类型和权限匹配，忽略归档时间戳；
同时匹配工具镜像内容、selector、架构和 `Jobs`。失败、输入变化或 `-ForceRun` 都会实际执行。
共享索引放在主工作区 `.tmp-regression-shared-*/`；原始日志或结果丢失/改变时不再复用。
`result.json` 记录等待时长、占用槽位数、总预算 `queue_budget`、镜像 ID 和复用来源；
`-Jobs` 只控制容器内测试并发，不是宿主资源配额。
真实宿主、重启、公网及业务容器连通性验收仍须单独环境，普通回归容器不能代替。
入口自检运行 `.\shell\regression\test-run-docker.ps1`。下面的 Bash 命令适用于 Linux 执行环境。

| 层级 | 命令 | 用途 |
| --- | --- | --- |
| 快速反馈 | `bash shell/subscription_groups_regression.sh fast` | 日常小改后的代表性检查；完整 fast 集合用 `fast-full`。 |
| 主产品回归 | `bash shell/subscription_groups_regression.sh all` | 较大改动的主验证集；按资源预算编排核心产品 suite，但不是所有公开 selector 的并集。 |
| 按需专项 | `bash shell/subscription_groups_regression.sh <selector>` | 按改动范围补跑协议、深层回滚或 harness 行为检查。 |

PR 的原生门槛使用 `ci-pr` 作为默认快速集合；订阅或 harness 改动升级到 `ci`，主分支发布门槛始终使用完整 `ci`。两者顶层默认并发为 3，可用 `PADM_REGRESSION_CI_PARALLEL_JOBS` 或 Docker CI 手动输入在 2 到 4 之间调整。Release 的静态检查、原生回归和发布准备固定到同一提交，后续主分支推送不会替换已验证的候选源码。

`all` 在同一资源预算内并行运行 `subscription`、`ui`、`transaction-core-main`、`transaction-system`、`routing`、`runtime`、`remote-control-smoke`、远程控制服务安装契约和远程控制响应契约。完整 `transaction-core`、`fast-full`、`protocol-capabilities`、`remote-control-deep` 和 harness 契约按改动范围追加。

常用产品专项：

```bash
bash shell/subscription_groups_regression.sh protocol-capabilities
bash shell/subscription_groups_regression.sh platform-hot
bash shell/subscription_groups_regression.sh platform-smoke
bash shell/subscription_groups_regression.sh fast-full
# sing-box 1.14 兼容性迁移专项（fast-full 已包含）
bash shell/subscription_groups_regression.sh fast-only-compatibility
bash shell/subscription_groups_regression.sh subscription-output
bash shell/subscription_groups_regression.sh transaction-core
bash shell/subscription_groups_regression.sh core-safety-rollback
bash shell/subscription_groups_regression.sh routing-safety
bash shell/subscription_groups_regression.sh subscription-safety
bash shell/subscription_groups_regression.sh transaction-system
bash shell/subscription_groups_regression.sh remote-control-smoke
bash shell/subscription_groups_regression.sh remote-control-contract
bash shell/subscription_groups_regression.sh remote-control-deep
bash shell/subscription_groups_regression.sh subscription-state
bash shell/subscription_groups_regression.sh ui-full-core
bash shell/subscription_groups_regression.sh ui-full-core-maintenance
```

harness 专项：

```bash
bash shell/subscription_groups_regression.sh regression-dispatcher-contract
bash shell/subscription_groups_regression.sh regression-case-loader-contract
bash shell/subscription_groups_regression.sh framework-parallel-selector-list-with-jobs
bash shell/subscription_groups_regression.sh targeted-batch-helpers
```

需要压并发或保守跑重型 suite 时，优先用 `PADM_REGRESSION_PARALLEL_JOBS`、`PADM_REGRESSION_CHILD_PARALLEL_JOBS`，以及按 suite 开启 `PADM_REGRESSION_*_RESOURCE_PROFILE=all`。`shell/regression/protocol_capabilities.sh` 仅作为保留原成功标记的兼容转发入口。

主入口按 `framework/`、`cases/load.sh`、`suites/` 的固定顺序装配回归；case 只加载一次，不再保留历史 source-only 分组层。

## 许可证

本项目根据 [AGPL-3.0 许可证](LICENSE) 授权。
