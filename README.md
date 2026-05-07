# padm

Xray-core / sing-box 一键安装与运维脚本，支持协议安装、证书申请、订阅发布、用户订阅组、多服务器源同步和流量统计。

## 新人先看

如果你第一次使用，不需要先理解所有协议，按下面路径走即可：

1. **直连/有域名**：优先选择 `1.安装管理` -> `2.自定义安装` -> `Xray-core` -> `7.VLESS Reality Vision`，有域名时把域名作为 entry。
2. **需要 CDN**：在 `1.安装管理` -> `2.自定义安装` 中优先选择 `12.VLESS Reality XHTTP`，传统 TLS/WS/gRPC/HTTPUpgrade 仅在兼容旧客户端时使用。
3. **没有域名**：选择 `1.安装管理` -> `3.无域名 Reality 安装`，脚本会生成 Reality 节点。
4. **安装完成**：回到主菜单选择 `2.查看/管理订阅`，先查看“我的订阅”，再按需创建“用户订阅”。
5. **验证服务**：在服务器上运行 `bash shell/validate_install.sh [domain]` 做只读验收。

不要一开始就使用“自定义安装”“CDN节点管理”“多服务器同步”这类高级入口，除非你明确知道客户端需要什么协议和网络形态。

## 功能

* **多核心支持**：支持 Xray-core 和 sing-box。
* **多协议支持**：支持 VLESS、VMess、Trojan、Hysteria2、Tuic、NaiveProxy、AnyTLS 等协议。
* **自动 TLS**：自动申请和续订 SSL 证书。
* **参数化安装**：支持通过命令行参数完成核心、域名、端口、TLS CA、订阅端口等非交互安装配置。
* **交互式管理**：提供中文菜单管理安装、更新、用户、端口、证书、服务和配置。
* **订阅支持**：支持 default、Clash Meta 和 sing-box 订阅输出，并可安装订阅发布服务。
* **订阅组管理**：使用 `/etc/padm/subscribe_groups/groups.json` 作为状态真源，管理用户订阅、服务器源、自动同步、流量统计、限额提示、限额计划和状态备份恢复。
* **多服务器源同步**：支持远程服务器源控制通道、健康检查、同步预览、手动同步和定时同步。
* **分流管理**：提供 WireGuard、IPv6、Socks5、DNS、VMess(ws)、SNI 反向代理等工具。
* **目标域名管理**：提供域名黑名单管理，可用于禁止访问指定网站。
* **BT 下载管理**：可用于禁止下载 P2P 相关内容。

## 快速开始

### 交互式安装

```bash
wget -P /root -N "https://raw.githubusercontent.com/neil1123-vip/padm/master/install.sh" && chmod 700 /root/install.sh && /root/install.sh
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
bash install.sh --install-type custom --core xray --protocols 7 --entry-host node.example.com --reality-target www.microsoft.com:443 --reality-server-name www.microsoft.com --reuse-last no
```

VLESS Reality XHTTP + CDN 推荐安装：

```bash
bash install.sh --install-type custom --core xray --protocols 12 --entry-host cdn.example.com --reality-target www.microsoft.com:443 --reality-server-name www.microsoft.com --reuse-last no
```

传统 TLS 组合安装（兼容旧客户端或迁移时使用）：

```bash
bash install.sh --install-type install --core xray --domain example.com --port 443 --tls-ca letsencrypt --dns-api no --reuse-last no --clean-acme yes
```

无域名 Reality：

```bash
bash install.sh --install-type reality --core xray --reality-target www.microsoft.com:443 --reuse-last no --clean-acme no
```

自定义安装示例：

```bash
bash install.sh --install-type custom --core xray --protocols 7 --entry-host node.example.com --reality-target www.microsoft.com:443 --reality-server-name www.microsoft.com --reuse-last no --clean-acme yes
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
| `--install-type` | `install`、`custom`、`reality` | 不传时进入交互菜单；传其它安装参数但不传本参数时不会自动选择安装入口 | 安装类型。`install` 为完整安装；`custom` 为任意组合协议安装；`reality` 为无域名 Reality 快速安装。 |
| `--core` | `xray`、`sing-box`、`1`、`2` | `xray` | 安装核心。`1` 等同 `xray`，`2` 等同 `sing-box`。 |
| `--protocols` | 协议编号，多个用英文逗号分隔 | 无固定默认，按安装类型进入对应协议选择 | 仅自定义安装时使用，例如 `0,1,7`。Xray 支持 `0,1,3,4,7,12`；sing-box 支持 `0,1,3,4,6,7,8,9,10,11,13`。 |
| `--domain` | 域名 | 无固定默认；TLS 安装时必须提供或交互输入；Reality 可作为默认 entry | TLS 证书域名和默认客户端入口地址；不会作为 Reality 伪装目标。 |
| `--entry-host` | 域名或 IP | Reality 默认优先使用 `--domain`，否则使用公网 IP | 客户端实际连接到服务器的地址，订阅中的 `server/address/@host` 会使用该值。 |
| `--reality-target` | `host[:port]` | 未传时交互输入或随机目标，端口默认 `443` | Reality 伪装目标站，写入 Xray `realitySettings.target` 或 sing-box `tls.reality.handshake`。 |
| `--reality-server-name` | SNI 域名 | 默认等于 `--reality-target` 的 host | Reality SNI，写入 Xray `serverNames` 或 sing-box `tls.server_name`。 |
| `--port` | 端口号 | `443`；检测到面板域名场景时回车会随机生成 `10000-30000` 端口 | TLS 入口端口。 |
| `--tls-ca` | `letsencrypt`、`zerossl`、`buypass` | `letsencrypt` | 申请证书使用的 CA。 |
| `--dns-api` | `yes`、`no`、`y`、`n` | `no` | 是否使用 DNS API 方式申请证书。 |
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
| `7` | VLESS Reality Vision | 新手直连/有域名场景优先选择；解决 TLS in TLS 和指纹问题，但不自带多路复用、不支持 CDN。 |
| `8` | VLESS Reality gRPC | 需要 gRPC/HTTP2 多路复用且不走 CDN 时作为备选。 |
| `9` | Tuic | UDP/移动网络场景可考虑。 |
| `10` | Naive | 需要 NaiveProxy 时选择。 |
| `11` | VMess HTTPUpgrade TLS | 传统 TLS/CDN 兼容方案；新建 CDN 优先选 12。 |
| `12` | VLESS Reality XHTTP | CDN 场景优先选择；兼顾 TLS in TLS、指纹、XMUX 多路复用和 CDN。 |
| `13` | AnyTLS | sing-box AnyTLS 场景使用。 |


## 推荐协议能力对照

| 脚本协议名 | 解决 TLS in TLS | 解决指纹问题 | 自带多路复用 | 支持 CDN | 推荐场景 |
| --- | --- | --- | --- | --- | --- |
| VLESS TCP TLS Vision | ✅ | ❌ | ❌ | ❌ | 传统 TLS 兼容/迁移。 |
| VLESS Reality Vision | ✅ | ✅ | ❌ | ❌ | 新手直连、有域名或无域名 Reality 首选。 |
| VLESS Reality gRPC | ❌ | ✅ | ✅ HTTP/2 | ❌ | 需要 gRPC/HTTP2 多路复用但不走 CDN 时备选。 |
| VLESS Reality XHTTP | ✅ | ✅ | ✅ XMUX | ✅ | CDN 场景首选。 |

## Reality 参数语义

Reality 新模型中，入口地址、伪装目标和 SNI 是三个不同概念：

| 概念 | 含义 | 对应输出/配置 |
| --- | --- | --- |
| entry | 客户端实际连接服务器的地址 | 订阅链接中的 `@host`、Clash Meta 的 `server`、sing-box profile 的 `server` |
| Reality target | Reality 伪装访问的真实目标站 | Xray `realitySettings.target`；sing-box `tls.reality.handshake.server/server_port` |
| Reality SNI | Reality 握手使用的 SNI | Xray `realitySettings.serverNames`；sing-box `tls.server_name`；订阅中的 `sni/servername` |

常见配置是：客户端连接自有域名 `node.example.com`，Reality 伪装目标使用 `www.microsoft.com:443`，SNI 使用 `www.microsoft.com`。

## 传统 TLS fallback 静态站点

主菜单 `4.工具箱` -> `1.传统 TLS fallback 静态站点` 只服务于传统 TLS 类协议：当访问没有命中代理协议时，Nginx fallback 会展示本机静态页面或 302 跳转。脚本内置 20 个轻量模板，安装或更换时会随机化标题、行业文案、按钮、卡片内容、页脚和主题色，增加站点外观差异。

VLESS Reality Vision、Reality gRPC 和 Reality XHTTP 不依赖这个本机静态站点。Reality 的伪装由外部 `target` 和 `SNI` 完成，认证失败的探测流量会被转发到目标站；因此新手安装 Reality 时无需先配置主菜单 `4.工具箱`。

如果只是需要自用直连，优先按 Reality Vision 示例安装；只有在继续使用 VLESS TCP TLS Vision、WS TLS、gRPC TLS、Trojan TLS 等传统 TLS/fallback 方案，或确实要在本机展示网站时，再配置静态站点。

## Reality 443 共存分流

只安装 Reality Vision 时通常只需要一个入口端口，默认推荐 `443`，并不需要本机再准备一个伪装站点。Reality 的伪装由外部 `target` 和 `SNI` 完成；只有同一台机器还要在 `443` 上提供真实网站时，才需要在主菜单 `3.协议管理` -> `2.REALITY 管理` 中使用“配置 443 共存分流”：

1. Nginx stream 监听公网 `443`。
2. 真实网站域名显式转发到网站后端，例如 `127.0.0.1:8443`。
3. 其他 SNI 默认转发到 Xray Reality 后端，例如 `127.0.0.1:2443`。
4. 订阅输出仍然使用 `entry-host:443`，Reality SNI 仍然保持伪装目标站。

该模式的关键点是：Nginx stream 看到的是 TLS ClientHello 中的 SNI，而 Reality 客户端发出的 SNI 通常是外部伪装目标站，不是 `entry-host`。因此脚本只让用户填写“哪些域名是真网站”，剩余 SNI 全部默认转给 Reality。新人或不需要网站共存时不建议启用；`443` 被占用时也可以直接把 Reality 入口端口改为 `8443` 或随机高位端口。

## 订阅管理教程

主菜单 `2.查看/管理订阅` 使用订阅组模型：

1. **我的订阅（管理员）**：查看管理员订阅链接，适合自用和检查节点输出。
2. **用户订阅**：给不同用户创建独立订阅。创建后会生成托管账号 `sub_<ID>`，同步后写入核心配置。
3. **服务器**：管理本机和远程服务器源。`main` 表示本机，远程源需要订阅服务和控制 Token。
4. **流量**：刷新并查看总流量、管理员、用户订阅和服务器来源流量。首次刷新会建立计数基线，后续按增量累计。
5. **设置**：安装订阅服务，配置自动同步、限额策略和状态备份。

给用户创建订阅的推荐流程：

1. `用户订阅` -> `新建用户订阅`，ID 使用英文、数字或短横线，例如 `team-a`。
2. `管理用户订阅` -> `设置可用服务器`，输入 `main`、远程服务器 ID，或 `*` 表示全部服务器。
3. `设置` -> `自动同步` -> `查看本机同步计划`，确认 create/remove 内容。
4. `立即执行同步`，再查看订阅链接。

多服务器同步推荐流程：

1. 在远端服务器安装订阅服务，确保 `/s/control/health` 可用。
2. 本机进入 `服务器` -> `添加服务器`，填写 `域名:订阅端口:别名[:http|https]`。
3. `设置控制Token`，填写远端 `/etc/padm/subscribe_groups/control.token` 中的 token。
4. `测试连接`，成功后到 `自动同步` 查看远程同步计划并执行。

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
