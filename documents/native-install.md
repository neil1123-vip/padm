# 📦 原生版安装与参数

[🏠 返回首页](../README.md#文档导航)

在 Linux 服务器上使用 `install.sh` 部署原生版。首次安装命令见 [README 的安装入口](../README.md#安装)，容器部署见 [Docker 版使用指南](docker-guide.md)。

[系统要求](#系统要求) · [交互式安装](#交互式安装) · [主菜单](#主菜单) · [短链二维码](#短链二维码) · [非交互安装](#非交互安装) · [参数参考](#参数参考)

## 系统要求

🐧 原生版识别 Debian、Ubuntu、RHEL、CentOS、AlmaLinux、Rocky Linux、Oracle Linux、Fedora 和 Alpine，按系统使用 `apt`、`yum` 或 `apk` 安装依赖。

| 项目 | 要求 |
| --- | --- |
| 权限 | 需要 root 或等价权限。 |
| 架构 | `x86_64/amd64`、`aarch64/arm64`。 |
| 基础命令 | 入口下载至少需要 `curl` 或 `wget`，wget 回退还需 `timeout` 限制总时长；完整包刷新需要 `tar`。 |
| 常用依赖 | 脚本会按功能安装或使用 `jq`、`nginx`、`acme.sh`、WireGuard tools、Fail2ban 等组件。 |
| 服务管理 | 核心服务优先使用 systemd；Alpine/OpenRC 路径有专门处理。主控/被控订阅控制服务目前要求 systemd 和 `python3`。 |

> [!IMPORTANT]
> 原生版在 RHEL 系或 Fedora 检测到 SELinux 处于 Enforcing 时会停止，并提示调整模式后重新运行。

## 交互式安装

首次运行时，脚本会检查 `shell/`、`documents/`、`assets/` 和模块 manifest。发现文件缺失或 manifest 不匹配时，会下载完整仓库归档并补齐模块。

怀疑本地模块仍是旧版本时，可以强制刷新。

```bash
wget -O /root/install.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/install.sh" && chmod 700 /root/install.sh && PADM_FORCE_SCRIPT_MODULE_REFRESH=1 /root/install.sh
```

安装后运行 `padm` 可再次打开管理面板。

```bash
padm
```

## 主菜单

运行 `padm` 打开原生版管理面板。顶部显示版本、核心运行状态和已安装协议，下方按任务选择入口。

| 菜单 | 负责什么 |
| --- | --- |
| 🚀 `1. 安装与重装` | 选择推荐方案、自定义协议或重装已有核心。 |
| 🔗 `2. 订阅与用户` | 发布订阅、创建分享订阅、管理额度和同步多台服务器。 |
| 🧭 `3. 协议与入口` | 查看本机链接与二维码，管理协议、端口和 CDN 入口。 |
| 🔐 `4. 站点与证书` | 管理静态站点、传统 TLS fallback、ALPN 和本机证书。 |
| 🧱 `5. 路由与访问控制` | 管理分流、BT 限制、阻断规则和直连例外。 |
| ⚙️ `6. 核心与服务` | 切换版本、控制服务、查看日志和维护 Xray Geo 数据。 |
| 🧰 `7. 系统与脚本` | 更新 padm、查看安装状态、管理 Fail2ban 和 BBR。 |
| ⚠️ `8. 高级与危险操作` | 卸载脚本或启用 VLESS Encryption 实验。 |

📱 `3. 协议与入口 → 1. 查看全部协议链接` 从当前配置读取本机节点，生成完整链接和二维码。二维码由 `qrencode` 生成，最多显示 80 列。生成失败或二维码过宽时，可以直接复制完整链接。终端若将黑白半块字符显示为双宽，需将其调整为单列。

## 短链二维码

📱 完整链接的二维码超出终端宽度时，可部署 Cloudflare Worker，在终端显示较短的 HTTPS 二维码。以 root 登录 VPS 后运行以下命令。

```bash
mkdir -p -m 700 /root/padm-shortlink && wget -O /root/padm-shortlink/deploy.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/tools/shortlink-worker/deploy.sh" && test -s /root/padm-shortlink/deploy.sh && chmod 700 /root/padm-shortlink/deploy.sh && bash /root/padm-shortlink/deploy.sh
```

按提示输入 Cloudflare API Token 和 Account ID 后，脚本会安装依赖、部署 Worker 并保存配置。部署凭据由 `age` 口令加密，再次部署时解锁。已安装的 padm 会自动使用短链。

协议内容保存在 Cloudflare KV，短链应按节点凭据保管。手机相机打开短链后，可以保存完整协议的 PNG 二维码，再从客户端导入。v2rayNG 直接扫描短 HTTPS 地址时会按订阅导入。
系统要求、授权权限、客户端导入和本地源码部署见 [部署说明](https://github.com/neil1123-vip/padm/blob/main/tools/shortlink-worker/README.md)。

## 非交互安装

用以下命令查看完整参数。

```bash
bash install.sh --help
```

以下命令中的 `target.example.com` 仅为占位符，必须替换为通过实时检测的 Reality 目标站。

**🧭 直连 Reality Vision**

```bash
bash install.sh --install-type custom --core xray --protocols 1 --entry-host node.example.com --reality-target target.example.com:443 --reality-server-name target.example.com --reuse-last no
```

**🌐 CDN Reality XHTTP**

```bash
bash install.sh --install-type custom --core xray --protocols 2 --entry-host cdn.example.com --reality-target target.example.com:443 --reality-server-name target.example.com --reuse-last no
```

**📍 无域名 Reality**

```bash
bash install.sh --install-type reality --core xray --reality-target target.example.com:443 --reuse-last no
```

**🛡️ NaiveProxy**

```bash
bash install.sh --install-type custom --core sing-box --protocols 5 --domain naive.example.com --port 443 --reuse-last no
```

命令行使用逗号分隔的公开协议 ID，例如 `--protocols 1,2,21`。交互安装按屏幕显示的编号选择，也支持逗号多选。旧配置若仍使用已废弃的 `0..13/20` 编号，请重新选择当前协议后重装或调整。

**🔐 传统 TLS 兼容安装（Cloudflare DNS-01）**

```bash
bash install.sh --install-type install --core xray --domain example.com --port 443 --tls-ca letsencrypt --dns-api yes --dns-api-type cloudflare --dns-api-wildcard yes --cloudflare-api-token <token> --cloudflare-zone-id <zone_id> --reuse-last no
```

Cloudflare API Token 建议仅授权目标 Zone，并授予 `Zone:DNS:Edit`。脚本也可从环境变量读取 Token 和 Zone ID。请通过运行环境注入真实凭据。

```bash
PADM_CLOUDFLARE_API_TOKEN=<token> PADM_CLOUDFLARE_ZONE_ID=<zone_id> bash install.sh --install-type install --core xray --domain example.com --dns-api yes --dns-api-type cloudflare
```

**🔗 为已有节点安装或更新 HTTPS 订阅发布**

```bash
bash install.sh InstallSubscription --domain subscribe.example.com --subscribe-port 39778 --install-nginx yes
```

订阅发布单独配置 TLS 域名和证书。脚本优先复用该域名的可用证书，缺少证书时可用 `--tls-ca`、`--dns-api` 和服务商凭据完成签发。复用自定义证书时由你负责续期。

## 参数参考

📋 用 `bash install.sh --help` 查看当前版本的完整参数。下表列出常用安装和订阅发布选项。

| 参数 | 可选值 | 默认行为 | 说明 |
| --- | --- | --- | --- |
| `--install-type` | `install`、`custom`、`reality` | 无自动参数时打开菜单。有其他安装参数时默认 `custom`。 | 选择安装类型。 |
| `--core` | `xray`、`sing-box`、`1`、`2` | `xray` | `1` 等同 `xray`，`2` 等同 `sing-box`。 |
| `--protocols` | 当前公开协议编号，逗号分隔 | 无固定默认 | 自定义安装协议，例如 `1` 或 `1,2,21`；旧版 `0..13/20` 编号已废弃。 |
| `--list-protocols` | 无 | 输出后退出 | 列出可安装的公网节点能力。 |
| `--list-capabilities` | 无 | 输出后退出 | 列出公网节点、内部能力和上游已知能力。 |
| `--show-risky-protocols` | 无 | 输出后退出 | 列出带风险提示的高级公网节点能力。 |
| `--domain` | 域名 | TLS 安装时必须提供或交互输入 | 用作 TLS 证书域名，也可作为 Reality 客户端入口。 |
| `--entry-host` | 域名或 IP | 优先于 `--domain`、历史 entry、`currentHost` 和公网 IP | Reality 客户端实际连接地址。 |
| `--reality-target` | `host[:port]` | 未传时按安装方式复用或选择目标。 | Reality 目标站，必须通过实时风险校验。 |
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

下一步可查看 [🧭 协议与入口](protocols.md) 或 [🔗 订阅与用户](subscriptions.md)。
