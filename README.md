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
| 📱 无域名自用拿节点 | `协议与入口` -> `查看全部协议链接` | 查看当前本机自用协议链接和二维码，无需订阅发布服务。 |
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

### 短链二维码

可选组件：通过 Cloudflare Worker 保存完整协议链接，并在终端显示短 HTTPS 地址的二维码。
适用于完整链接二维码超出终端宽度的场景。以 root 登录 VPS，执行以下命令部署：

```bash
mkdir -p -m 700 /root/padm-shortlink && wget -O /root/padm-shortlink/deploy.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/tools/shortlink-worker/deploy.sh" && test -s /root/padm-shortlink/deploy.sh && chmod 700 /root/padm-shortlink/deploy.sh && bash /root/padm-shortlink/deploy.sh
```

按提示输入 Cloudflare API Token 和 Account ID，脚本自动安装依赖、部署 Worker 并保存配置；
部署凭据用 `age` 口令加密，再次部署时解锁。日常运行 `padm` 不需要口令。
已安装的 padm 随后自动使用短链。协议内容存于 Cloudflare KV，短链接应按节点凭据保管。
用手机相机打开短链可查看完整协议 PNG，保存后由客户端识别图片导入节点；
v2rayNG 直接扫描短 HTTPS 地址时会作为订阅导入。
系统要求、授权权限、客户端导入和本地源码部署见 [部署说明](tools/shortlink-worker/README.md)。

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
`padm-docker menu` 可查看状态、启停重启和日志，选择“安装与重装 → 首次配置”收集核心、协议、地址和证书。
当前向导支持 Xray Reality Vision/XHTTP/gRPC、sing-box Reality Vision/gRPC/Hysteria2/AnyTLS/NaiveProxy/Shadowsocks/TUIC，以及两核心 direct Trojan、VMess HTTPUpgrade TLS，
以及 Xray VLESS WS TLS、VMess WS TLS、VLESS/Trojan gRPC TLS、VLESS TCP TLS Vision、Trojan TLS fallback 或 Reality Vision + WS TLS；
已有部署可从同一菜单选择重装，或改用下述保身份编辑入口；完整协议管理仍待后续阶段交付。
`install --no-menu` 禁止安装后自动进入菜单；无参数非交互调用只显示帮助，
不会安装 Docker、下载 bundle 或初始化状态，现有显式 CLI 命令保持可用。

```bash
padm-docker setup
padm-docker validate
padm-docker status
```

向导最终确认后才验签发布、生成 UUID/Reality 参数/订阅 token，并准备候选配置与证书。
没有 `cosign` 时停止，不自动从未验证来源安装验证器，也不能跳过验签。
WS/HTTPUpgrade/gRPC TLS、传统 TLS fallback、Hysteria2、AnyTLS、NaiveProxy、TUIC 和 direct Trojan 可选择已有受管证书、导入完整证书链与私钥，或使用 DNS-01/HTTP-01 standalone/TLS-ALPN-01；
私钥和 DNS 凭据必须是仅持有者可读的普通文件。订阅发布仍要求 Xray、协议 21 VLESS WS TLS 和受管证书。
Hysteria2 使用单 UDP 入口，支持 BBR/Brutal、Salamander/Gecko 混淆和 HTTPS 伪装；
带宽按服务端方向输入，分享链接自动转换为客户端方向。
首配混淆输入 `y` 选择 Salamander、`gecko` 选择 Gecko、`n` 关闭；已有入口在 Hysteria2 参数菜单切换类型，空密码保留已有值。
Gecko 规格要求 `x-padm-hy2-gecko`，旧无混淆/Salamander 子集继续兼容；不开放 Gecko 包长参数，`local` 网页仍要求关闭混淆。
端口跳跃提供下述手动双族 Hy2 范围管理；客户端范围自动跳跃已在隔离 amd64 验收。
AnyTLS 使用 sing-box 直连 TCP/TLS 入口，不经过 Nginx；首配选择 sing-box 后选 `7=AnyTLS`。
复用 UUID 作为密码及流量账号，可输出 `anytls://` 分享链接；AnyTLS 单独部署不提供 HTTPS 订阅发布。
NaiveProxy 在 sing-box 首配中选 `8`，使用 TCP/TLS 直连入口；服务器地址必须与 TLS 域名一致。
UUID 同时作为用户名、密码及流量账号，分享链接使用 `naive+https://`；不开放独立 IP/SNI 覆盖或 QUIC。
Shadowsocks 在 sing-box 首配中选 `9`，固定为 `2022-blake3-aes-128-gcm` 多用户模式；
同端口支持 TCP/UDP 双栈，不需要 TLS。确认后独立生成服务器与用户密钥，UUID 作为流量账号。
`ss://` 按 SIP002 百分号编码组合密码；超额时撤销运行入站，解除额度后恢复原密钥和监听。
TUIC 在 sing-box 首配中选 `10`，使用单 UDP 双栈入口和受管 TLS；
UUID 同时作为用户 ID、密码及流量账号。拥塞控制支持 `cubic`、`bbr`、`new_reno`，
认证超时、心跳和 0-RTT 可在 `协议与入口 → 13. TUIC 管理` 或编辑菜单 `14` 管理，默认 `3s`、`10s`、关闭 0-RTT。
`tuic://` 使用 `h3`、原生 UDP 中继及严格 TLS 校验；单个双族入口可使用下述范围转发管理。
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

Docker `协议与入口 → 12. Hysteria2 管理` 与 `13. TUIC 管理` 为已有 v3
sing-box 单入口提供专项编辑：

```bash
padm-docker protocol hy2-status entry-hy2
padm-docker edit --hy2-bandwidth entry-hy2 brutal 100 50 --preview
padm-docker edit --hy2-bandwidth entry-hy2 bbr --confirm PADM-DOCKER-EDIT
padm-docker edit --hy2-obfs entry-hy2 gecko /root/hy2-password.json --preview
padm-docker edit --hy2-obfs entry-hy2 off --confirm PADM-DOCKER-EDIT
padm-docker edit --hy2-masquerade entry-hy2 https://www.example.com/ --preview
padm-docker edit --hy2-masquerade entry-hy2 off --confirm PADM-DOCKER-EDIT
padm-docker protocol tuic-status entry-tuic
padm-docker edit --tuic-congestion entry-tuic bbr --preview
padm-docker edit --tuic-connection entry-tuic 3s 10s --preview
padm-docker edit --tuic-zero-rtt entry-tuic false --confirm PADM-DOCKER-EDIT
padm-docker edit --tuic-defaults entry-tuic --confirm PADM-DOCKER-EDIT
```

Hy2 带宽按服务端方向填写，整数范围 `1..1000000` Mbps；Brutal 菜单默认
`100/50`，BBR 保留规格中的速率，分享链接自动转换客户端方向。
混淆可选 `salamander/gecko/off`；非交互开启须提供 root 所有、`0600`、
单链接的私密 JSON，唯一字段为 `password`，值为 16–128 位字母、数字、`_` 或 `-`。
交互静默输入，空输入保留旧密码，无旧值才随机生成；`0` 或 EOF 取消。
伪装可选 `off/local/HTTPS_URL`，local 的前置条件见下文。
TUIC 时长接受 1–6 位正整数加 `ms/s/m/h`，恢复推荐值为 `cubic/3s/10s/false`。
0-RTT 默认关闭，开启菜单要求确认重放风险。专项不能与规格导入或其它专项混用，
仅改选中字段，保留认证、TLS、其它入口、其它参数和累计额度；
沿用预览、确认、发布和失败恢复。完整协议管理及宿主集成组合仍未开放；TUIC 范围转发见下文。

Docker `协议与入口 → XHTTP 管理` 可管理已有 v3 Xray 协议 `2` 的模式、
路径/Host、预设、XMUX、Padding、首部、四项原生 packet/stream limits 及下行分离：

```bash
padm-docker protocol xhttp-status entry-xhttp
padm-docker edit --xhttp-headers entry-xhttp true false --preview
padm-docker edit --xhttp-headers entry-xhttp true false --confirm PADM-DOCKER-EDIT
padm-docker edit --xhttp-headers-clear entry-xhttp --confirm PADM-DOCKER-EDIT
padm-docker edit --xhttp-request-headers entry-xhttp '{"X-Trace":"edge value"}' --preview
padm-docker edit --xhttp-request-headers-clear entry-xhttp --confirm PADM-DOCKER-EDIT
padm-docker edit --xhttp-download entry-xhttp 35444 --preview
padm-docker edit --xhttp-download-settings entry-xhttp '{"address":"download.example.net","port":443,"security":"tls","server_name":"tls.example.net","host":"relay.example.net","path":"/down/path","mode":"auto","alpn":["h2"]}' --preview
padm-docker edit --xhttp-download-clear entry-xhttp --confirm PADM-DOCKER-EDIT
padm-docker edit --xhttp-limits entry-xhttp 2000000 20 50 30-40 --preview
padm-docker edit --xhttp-limits-clear entry-xhttp --confirm PADM-DOCKER-EDIT
padm-docker edit --xhttp-mode entry-xhttp stream-up --preview
padm-docker edit --xhttp-path-host entry-xhttp /padm/new-path www.example.com --preview
padm-docker edit --xhttp-advanced entry-xhttp 128-256 2000000 20 50 30-40 true false --preview
padm-docker edit --xhttp-defaults entry-xhttp --confirm PADM-DOCKER-EDIT
```

菜单 `14` 单独设置 `auto/packet-up/stream-up`；`15` 同时设置安全路径和非空域名 Host。
`16` 一次设置七项高级参数，顺序为 Padding、POST 字节数、间隔毫秒、
缓冲 POST 数、流式秒数、noGRPCHeader、noSSEHeader，保留模式和 XMUX。
`17` 一次恢复 `auto`、XMUX `16-32/600-900/1800-3000`、Padding `100-1000`、
两项首部 `false` 和 limits `1000000/30/30/20-80`，保留路径/Host。
各专项仅改所选入口的相应字段，复用预览、确认、发布和失败恢复。

两个值依次为 `noGRPCHeader`、`noSSEHeader`。`true` 分别去掉客户端 stream
POST 的 gRPC Content-Type 和服务端下载响应的 SSE Content-Type；`packet-up`
原本没有 gRPC 请求首部。显式 `false` 保留，clear 删除字段恢复缺省；
任一字段存在要求 `x-padm-xhttp-headers`。菜单 `10` 设置、`11` 恢复缺省，
修改保持其它入口、XMUX、Padding、认证、主订阅/分享组和额度累计。
四项 limits 为 `scMaxEachPostBytes`、`scMinPostsIntervalMs`、
`scMaxBufferedPosts` 和 `scStreamUpServerSecs`，前三项接受 `0..2147483647`
整数，最后一项接受整数或端点 `0..2147483647` 的正序范围；`0`/`0-0`
保留在 spec、服务端和 URI，状态显示核心默认 `1000000/30/30/20-80`。
空输入使用同一组默认值，菜单 `12` 设置、`13` 清除，显式字段要求
`x-padm-xhttp-limits`。`clear` 删除字段恢复缺省，其它编辑保留、复制/派生继承；
缺省不补 spec 或 URI，状态通过 `limits_explicit` 区分显式值。
首部变化不代表抗识别或性能收益。

菜单 `18` 设置 `xhttp.headers` JSON 对象，`19` 删除字段恢复无自定义首部。
范围为已有 v3 Xray XHTTP 单入口的客户端请求首部，接受 1–8 项；
名称为 1–64 位字母、数字和连字符且以字母或数字开头，忽略大小写后必须唯一；
值为 0–256 位可打印 ASCII，拒绝 CR/LF、控制字符及非 ASCII。
`Host`、`Content-Length`、`Transfer-Encoding`、`Connection`、`Keep-Alive`、
`Proxy-Connection`、`Upgrade`、`TE`、`Trailer`、`Content-Type`、`Referer`
保留给独立 Host 字段或传输核心，不能覆盖。显式字段要求
`x-padm-xhttp-request-headers`；状态的 `requestHeaders` 和
`request_headers_explicit` 区分缺省，统一 URI `extra`、复制/派生继承。
预设、高级参数和推荐值恢复均保留自定义首部；这不提供服务端响应首部或访问认证，
首部内容会进入分享链接和订阅。

菜单 `20` 绑定下行端口，`21` 清除；只接受本入口已登记、未设为默认分享的额外端口，
先在入口端口菜单登记，再设置 `xhttp.download_port`。不接受基础端口、默认分享端口、
其它入口或未登记端口；不会创建新后端或更改端口发布。显式绑定要求
`x-padm-xhttp-download`，状态返回 `download_port`（缺省为 `null`）及 `download_enabled`。
统一链接的 `extra.downloadSettings` 使用本入口服务器和下行端口，自动跟随同一
Reality 公钥、short ID、SNI、路径、Host 和其它 XHTTP 参数，下行模式固定 `auto`。
服务端配置不写入该客户端字段；主订阅、分享组和本地链接同步更新。
预设、高级参数和推荐恢复保留绑定；复制/派生保留源入口绑定，新入口清除绑定，
需自行登记新入口的额外端口。

菜单 `22` 或 `--xhttp-download-settings <入口 ID> <JSON>` 设置独立下行地址和身份，
保存为 `xhttp.download`；与 `download_port` 互斥，设置任一形式会清除另一形式，
菜单 `21` 和 `--xhttp-download-clear` 可清除两类绑定。对象必须完整显式指定
`address`、`port`、`security`、`server_name`、`host`、`path`、`mode`。
地址接受域名或严格 IPv4/IPv6，SNI 和 Host 使用域名，路径与上行约束相同；
下行模式可选 `auto/stream-one/packet-up/stream-up`。
`security=tls` 必须指定 `alpn:["h2"]` 或 `["h3"]`；
`security=reality` 必须指定 43 位 base64url `public_key` 和 1–8 字节小写十六进制 `short_id`，
不能混入另一安全类型的字段或其它高级参数。显式对象要求
`x-padm-xhttp-download-settings`，状态新增 `download_settings`（缺省 `null`）。
URI 使用对象自己的地址、安全身份和三项 XHTTP 字段，不继承上行高级参数；
预设及其它编辑保留对象，复制/派生只清除新入口对象，服务端配置不写入客户端字段。
本功能只管理客户端元数据，外部前置必须已部署并转回同一 XHTTP handler 及认证。
不会自动建设 TLS/H3/CDN 拓扑，也不能将上下行指向无会话关联的独立后端；
当前原生菜单的四项 `sc*` 参数已覆盖；公网前置验收、宿主/arm64、性能收益和完整管理仍待补。

VLESS TCP TLS Vision、Trojan TCP TLS fallback 在 Xray 首配中分别选 `16`/`17`。
Xray 直接终止 TLS，未命中协议的 HTTP/1.1 和 HTTP/2 请求通过 PROXY v1 回落到 Nginx；
`fallback_tls` 固定域名及两个内部端口，默认 `31300`/`31302`，同核复制可共享后端。
默认首页不写入站点目录，已有 `/etc/padm-docker/data/static/index.html` 优先；
支持通用字段编辑、同核复制/删除与链接；默认页、静态目录、302 和 ALPN 已支持事务管理，宿主集成及独立 HTTPS 发布尚未开放。

Docker 菜单 `16. 站点管理` 管理已有 Nginx TLS 入口 `21–25`、fallback `27`/`29`
或 Hysteria2 的静态网页：

```bash
padm-docker edit --site-template notes --preview
padm-docker edit --site-template photos --confirm PADM-DOCKER-EDIT
padm-docker edit --site-template docs --confirm PADM-DOCKER-EDIT
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
删除最后一个 Nginx 入口时，仍有 Hysteria2 则保留静态模式；没有站点消费者时清除模式，
静态文件及其它 TLS 入口仍保留。
`status` 只报告 `site_mode`，不输出目标 URL。已有旧规格保持兼容，带 `.site` 的 v3
规格要求控制 bundle 声明 `x-padm-site-content`；受管 webroot 与 standalone HTTP-01 见证书管理。

菜单 `16 → 8. 内置静态站点` 可选择 `notes`、`photos` 或 `docs`。内置主题仅适用于
已有 v3 Xray Nginx TLS `21–25`、fallback `27/29` 或 sing-box Hysteria2，
包含 sing-box `23` 的部署明确拒绝；其它不提供网站的 Reality 入口可共存。主题从验签后的
控制包复制，随包清单和资源完整性校验失败即拒绝；生成后只保存普通 `site.mode=static`，
不保存主题身份，旧控制包的默认页、静态目录和 302 行为保持。

Hysteria2 先通过上面的模板或目录命令发布网页，再在 `协议与入口 → 12. Hysteria2 管理`
关闭混淆、选择本地网页；CLI 使用 `edit --hy2-masquerade <入口 ID> local`，
沿用 `--preview/--confirm PADM-DOCKER-EDIT`。操作前校验已发布网页，不自动创建站点或关闭混淆。
只挂载受管 `data/static` 到固定只读 `/srv/padm/`，拒绝任意 `file://` 输入；
所有 local 入口与 Nginx 共用该网页。local 要求 `site.mode=static`、`obfs=null`，
启用期间切换默认页、302 或开启混淆均拒绝。先把伪装设为 `off` 或 HTTPS 可关闭
本地网页，静态文件保留；纯 Hysteria2 不提供默认页/302，首配不接受 local。
local 与纯 Hysteria2 静态准备规格要求 `x-padm-hy2-local-site`；旧默认/HTTPS
规格及无 local 的 Nginx 静态组合保持旧包兼容。网页外观不证明抗识别能力。

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

Docker 菜单 `17. 路由与出站 → 1` 提供认证 SOCKS5 TCP 全局或域名分流直接录入，
也可在终端运行 `padm-docker edit --socks5-input`。用户名和密码隐藏输入，
凭据不进入进程参数或预览；空输入或 EOF 取消，密码 `0` 是合法值，其它字段 `0` 返回。
完整候选验证后仍需确认提交，该入口不能与 `--preview` 或 `--confirm` 组合。
自动化继续在 root 私有目录准备
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
padm-docker edit --socks5-domains-add 'full:next.example.net' --preview
padm-docker edit --socks5-domains-remove 'full:exact.example.com' --confirm PADM-DOCKER-EDIT
padm-docker edit --socks5-domains-replace 'full:exact.example.com' 'full:next.example.net' --preview
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
菜单 `17` 的 `34/35/36` 和 `--socks5-domains-add/remove/replace` 管理已有非空域名名单；
未启用或全局模式拒绝。追加规范化后稳定去重，合并最多 256 条；
删除按完整规范化规则匹配，缺项整批拒绝，保留剩余次序。删空关闭整个 SOCKS5，
以后启用须重新导入私有凭据，不自动切为全局。单条替换保留原位置，
拒绝 CSV、缺旧项、重复新项和同值；非空编辑仅修改 `domains`，
`server/port/username/password` 及其它路由和配置冻结，只有删除末条允许移除整个子项。
三项菜单先显示路由状态，状态失败不读输入；空输入、`0` 和 EOF 取消，独立 CLI 只确认一次。
原整组替换和全局入口保持；复用双核心生成与既有事务，不新增 schema、marker 或宿主权限。
SOCKS5 名单定向合同、菜单 PTY 与集中完整 49 项回归已通过。
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
菜单 `17` 的 `28/29` 与 `--dns-domains-add/--dns-domains-remove <CSV>` 可增删已有
DNS 分流的域名名单，保留原服务器和端口。追加保留历史顺序并去重，合并后最多 256 条；
删除按完整规范化规则匹配，任一缺项整次拒绝，删空关闭该 DNS 分流并保留其它路由。
未启用 DNS 时增删明确拒绝；重复追加仍经过确认事务，可能更新回滚元数据。
菜单 `17 → 41/42` 与 `edit --dns-upstream <IP> <端口>` /
`--socks5-upstream <IP> <端口>` 可修改已有上游，保留域名名单、SOCKS5 凭据与其它配置。
地址沿用可路由字面 IPv4/IPv6 合同并保留原文；端口显式填写 `1–65535`，没有缺省值，
CLI 中的前导零按十进制处理。未启用或地址和端口均未变化返回 `15`；
预览、唯一确认、失败及信号恢复沿用原编辑事务，菜单空值、`0` 或 EOF 取消。
hosts 私有 JSON 示例为 `{"exact.example.net":"192.0.2.10"}`，接受 1–256 个小写精确域名，
每个域名对应一个可路由字面 IPv4/IPv6；不支持 hosts 后缀、关键字或分类匹配。
地址示例不可直接用作服务器；文件安全要求与 SOCKS5 输入相同。
菜单 `17 → 37` 与 `edit --hosts-replace <已有精确 FQDN> <新单字面 IP>` 可替换已有
hosts 的一个地址，不新增、删除或批量编辑映射。域名只将 ASCII 字母转小写，不去空白；
IP 保留原文，包括 IPv6 大小写和写法。空白、末尾换行、CSV、域名规则前缀或非法地址返回 `2`；
缺键、未启用 hosts 或地址原文同值返回 `15`。只豁免目标键的值，其它 hosts、路由和完整配置冻结，
分享 URI、订阅及累计流量保持；预览、确认和健康失败/信号恢复复用原事务。
菜单先显示状态，状态失败不读输入，空值、`0` 或 EOF 取消；独立 CLI 只确认一次。
原 `--hosts <私有 JSON>` 整组入口保持，不新增 schema、marker、权限或状态。
这是有限管理增强，不代表原生 hosts 完整迁移；DNS/hosts 定向与菜单已通过，集中完整 49 项回归通过。

菜单 `17 → 38/39` 与 `edit --hosts-add <精确 FQDN> <单字面 IP>` /
`--hosts-remove <精确 FQDN>` 提供单键新增和精确删除。新增可创建缺省 hosts，
但已有键不论地址是否相同均返回 `15`，须用替换入口改地址；合并最多 256 项。
删除要求键已存在，缺键或未启用返回 `15`；删掉最后一键关闭 hosts，
只在没有其它策略时清理 routing。沿用 ASCII 小写、不去空白及地址原文边界，
其它映射、完整配置、URI/订阅和累计流量保持。增删专项已通过 Linux amd64
定向与菜单 PTY 回归，集中完整 53 项回归通过；
完整区域策略、冲突检测及原生 hosts 完整迁移仍为 `deferred`。

```bash
padm-docker edit --dns /root/padm-dns.json --preview
padm-docker edit --dns /root/padm-dns.json --confirm PADM-DOCKER-EDIT
padm-docker edit --dns-rules 192.0.2.53 53 'example.net,full:exact.example.org' --preview
padm-docker edit --dns-domains-add 'full:updates.example.net' --preview
padm-docker edit --dns-domains-remove 'full:updates.example.net' --confirm PADM-DOCKER-EDIT
padm-docker edit --hosts /root/padm-hosts.json --confirm PADM-DOCKER-EDIT
padm-docker edit --hosts-replace Exact.Example.NET 2001:0DB8::10 --preview
padm-docker edit --hosts-replace exact.example.net 192.0.2.11 --confirm PADM-DOCKER-EDIT
padm-docker edit --hosts-add new.example.net 2001:DB8::11 --preview
padm-docker edit --hosts-remove new.example.net --confirm PADM-DOCKER-EDIT
padm-docker edit --dns-off --confirm PADM-DOCKER-EDIT
padm-docker edit --hosts-off --confirm PADM-DOCKER-EDIT
```

已有域名名单可单条替换：菜单 `17` 的 `30/31/32` 分别编辑 DNS、Direct、Block，
IPv6 子菜单 `7` 和 WARP 子菜单 `10` 编辑已有 selective 名单。先查看当前规则，
再输入旧规则与新规则，沿用预览和确认事务：

```bash
padm-docker edit --dns-domains-replace 'full:old.example.net' 'full:new.example.net' --preview
padm-docker edit --direct-domains-replace 'domain:old.example.net' 'domain:new.example.net' --confirm PADM-DOCKER-EDIT
padm-docker edit --block-domains-replace 'keyword:oldword' 'keyword:newword' --preview
padm-docker edit --ipv6-domains-replace 'full:old.example.net' 'full:new.example.net' --preview
padm-docker edit --warp-domains-replace 'full:old.example.net' 'full:new.example.net' --preview
```

两值各限一条规则，不接受 CSV；规范化后旧规则必须恰好存在一次，新规则不得重复
或与旧规则相同。按完整规则匹配，`full:` 与 `domain:` 不互换；只替换原位置，
保留其它项的次序、DNS 服务器/端口、WARP 私有字段及全部其它配置。
缺失名单、WARP/IPv6 的 global 模式明确拒绝；不会创建或切换分流模式。
取消、失败和信号恢复沿用原事务，完整区域和其它规则管理仍未开放。

v3 可选 `.routing.dns` 与 `.routing.hosts` 要求控制包声明 `x-padm-routing-dns-hosts`。
hosts 优先于 DNS 分流；未匹配域名使用容器本地解析，匹配 DNS 失败不回退本地解析。
SOCKS5 匹配目标仍交上游解析，DNS/hosts 不改变上游域名或实际 IP 目的地；
只用于嗅探匹配的 HTTP Host/TLS SNI 不会被当作新的连接目的。
每次专项编辑只替换或关闭相应子能力，保留其他路由、入口、账号和累计流量；
普通 `--spec` 编辑不能绕过路由冻结。启用、替换与关闭复用原候选确认、备份和失败/信号恢复。
`routing-status` 额外返回 DNS 服务器、域名规则和 hosts 映射，不显示 SOCKS5 凭据。

菜单 `17 → 21 → 1` 或终端 `padm-docker edit --http-relay-input` 可直接录入
已有 Xray 的中继端口、地址族、隐藏用户名/密码和必填来源 CSV；
候选验证后确认提交，空输入/EOF 取消，密码 `0` 合法，其它字段 `0` 返回。
来源不设开放默认值，旧私有 JSON CLI 保留，支持范围不变。
子菜单 `4–7` 管理已有 Xray HTTP 中继的端口和来源允许名单：
`edit --http-relay-port <端口>`、`--http-relay-sources <CSV>`、
`--http-relay-sources-add <CSV>`、`--http-relay-sources-remove <CSV>`。
CSV 去项首尾空白、稳定去重并保留字面写法；追加保留旧顺序，删除须全部精确存在。
删空、缺项、无变化、非法 IP/CIDR、超过 256 条或端口冲突均拒绝。
认证、核心、地址族、其余规格及业务累计保持；状态失败和空输入/`0`/EOF 返回，
一次确认复用候选、备份及失败/信号恢复。只支持已有受管 Xray，
完整 `202` 的原生宿主/公网/arm64/可信发布验收继续 deferred，
详见 [Docker HTTP 中继](documents/docker-http-relay.md)。

菜单 `17` 的 `10/12` 分别替换 Direct 直连例外和 Block 域名阻断，可直接输入
逗号分隔规则；CLI `--direct-domains/--block-domains` 使用相同输入。
CSV 去首尾空白、转小写、按首次出现去重，裸域名补 `domain:`，
整组替换而非累加，空项/非法或超过 256 条拒绝；清空请使用对应关闭命令。
菜单 `17` 的 `22/23` 或 `--direct-domains-add/--block-domains-add` 可增量追加：
保留原规则顺序，再添加首次出现的新项；对应组缺失时创建，合并后超过 256 条拒绝。
重复追加不重复规则，确认仍沿用部署事务，可能更新回滚元数据。
菜单 `17` 的 `24/25` 或 `--direct-domains-remove/--block-domains-remove` 可精确删除：
输入中的每条规范化规则必须已存在于对应手工列表，否则整次操作拒绝；删除保留剩余顺序，
最后一条删除后清理该子项。不会删除区域策略、IP/CIDR 或其它路由子项。
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
padm-docker edit --direct-domains-remove 'full:updates.example.org' --preview
padm-docker edit --block-domains-remove 'domain:ads.example.net' --confirm PADM-DOCKER-EDIT
padm-docker edit --direct-off --confirm PADM-DOCKER-EDIT
padm-docker edit --block-off --confirm PADM-DOCKER-EDIT
```

v3 `.routing.direct`、`.routing.block` 要求控制包声明 `x-padm-routing-direct-block`。
各子项独立关闭，最后一项关闭才删除 routing；普通 `--spec` 不能更改路由。
`routing-status` 追加 Direct/Block 域名规则，不改变现有 SOCKS5 状态字段含义。
只读 `direct_block_overlaps` 按 Direct 顺序列出手工 Direct/Block 的完整规则字符串交集。
Direct 保持优先；不推断域名包含、分类成员或区域合成，不把重叠当作配置错误。

同一状态另输出 `domain_rule_overlaps`：按完整规则字符串排序，逐项列出 `rule`、
按 Direct → Block → IPv6 → WARP → SOCKS5 排序的 `policies` 和其中优先的 `winner`。
这里包含区域默认/自定义 Direct 例外，以及 domain/both 模式合成的 `geosite:cn`；
同一策略的重复来源只计一次，global 出站不参与。`winner` 只表示相同完整规则的候选优先者，
不推断其它规则的包含关系、分类成员、字面 IP/BT、HTTP 中继或最终流量去向；
SOCKS5 策略对 TCP 代理、UDP 拒绝。诊断只读，完整冲突检测仍待交付。

`domain_rule_coverages` 补充不同策略之间可确定的域名覆盖：`domain:` 覆盖同名
`full:`、子域 `full:` 和子域 `domain:`，按 `narrow_rule/broad_rule` 排序，
列出参与这对规则的 `policies/winner`，包含区域直连例外，同策略覆盖不报告。
域名按标签边界比较，不把 `notexample.net` 归入 `example.net`；不推断 keyword、
GeoSite 成员或 IP/BT。`winner` 仅针对所列规则，不表示最终流量路径。
`domain_rule_keyword_coverages` 另列出 `full:`、`domain:` 或 `keyword:` 规则正文
包含其它策略的 `keyword:` 正文时的覆盖，沿用相同字段、排序和优先级。
例如 `full:ads.example.net` 被 `keyword:ads` 覆盖，`keyword:advert` 被
`keyword:ad` 覆盖；同策略关系不报告。只比较规范字符串，不查询 GeoSite、
DNS 或最终目的地址，不把诊断升级成配置拒绝或完整冲突检测。
单 sing-box 已提供显式解析后 IP 阻断，见下文；Xray 继续待交付。
本地解析结果不能代替代理实际连接地址，Xray `IPOnDemand` 不满足此门槛。

菜单 `17` 的 `14/26/27` 分别直接录入、追加和精确删除 IP/CIDR 阻断 CSV，
使用独立 v3 `.routing.block_ips`；原 CLI 私有 JSON 接口保留，格式为
`{"ips":["192.0.2.8","198.51.100.0/24","2001:db8::/32","geoip:cn"]}`。
接受 1–256 条唯一 IPv4/纯 IPv6 字面地址或 CIDR，以及固定 `geoip:cn`；
不接受主机名、地址范围、IPv6 scope、点分嵌入 IPv4 或其它 GeoIP 分类。
地址可包含回环/私网；这是目的匹配规则，不是代理或 DNS 上游地址。
文件安全要求与其它路由私有 JSON 相同，控制包须声明 `x-padm-routing-block-ips`。

```bash
padm-docker edit --block-ips /root/padm-block-ips.json --preview
padm-docker edit --block-ips /root/padm-block-ips.json --confirm PADM-DOCKER-EDIT
padm-docker edit --block-ips-add /root/padm-block-ips.json --confirm PADM-DOCKER-EDIT
padm-docker edit --block-ips-remove /root/padm-block-ips.json --confirm PADM-DOCKER-EDIT
padm-docker edit --block-ips-csv '192.0.2.8,2001:DB8::/32,geoip:cn' --preview
padm-docker edit --block-ips-add-csv '198.51.100.17/24' --confirm PADM-DOCKER-EDIT
padm-docker edit --block-ips-remove-csv '198.51.100.17/24' --confirm PADM-DOCKER-EDIT
padm-docker edit --block-ips-replace '198.51.100.0/24' '203.0.113.17/24' --preview
padm-docker edit --block-ips-off --confirm PADM-DOCKER-EDIT
```

直接录入只去除每项首尾空白，保留 IPv6 大小写、压缩写法和 CIDR 主机位；
空项、重复项、非法值或超过 256 项整批拒绝，空输入、`0` 或 EOF 取消。
CSV 与私有 JSON 复用相同校验、预览、确认及恢复事务，保留已有解析后阻断模式。
`--block-ips-add/--block-ips-remove` 继续接受原私有 JSON 格式。
追加保留原顺序，再按输入顺序添加新规则；不存在的手工名单会创建，合并后最多 256 项。
删除要求请求中的每条完整字符串都在手工名单中，缺一条即整组拒绝；
不按 CIDR 包含关系匹配，也不合并 IPv6 的大小写、压缩写法或 CIDR 主机位。
空数组、重复项或非法输入在合并前拒绝。删空只移除手工 IP 子项，
保留区域预设生成的 `geoip:cn` 和其它路由，预览与取消不切换配置。

菜单 `17` 的 `33` 和 `--block-ips-replace <旧规则> <新规则>` 可单条替换已有手工
IP/CIDR 名单。先查看当前规则，再输入两个字面地址或 CIDR；原位替换并冻结其它配置。
两值保持原文，不去空白、不转换 IPv6 写法或 CIDR 宿主位；完整字符串旧项必须
恰好存在一次，新值不得重复或与旧项相同。不接受 CSV、GeoIP、域名和区域合成项；
缺失手工名单明确拒绝。两步空输入、`0` 或 EOF 取消，确认及失败恢复沿用原事务。

缺省 IP 规则只匹配客户端提供的字面目的 IP，TCP/UDP 拒绝发生在 SOCKS/DNS/hosts 前。
Direct 域名例外（包括识别出的 HTTP Host/TLS SNI）优先且不改目的地址。
客户端以域名提交的目标不会为了 IP 匹配而提前解析；DNS/hosts 解析后的地址
不重新匹配本阶段 IP 规则，因此它不是最终拨号 IP 或宿主防火墙过滤。
Xray 复用受管/镜像 GeoIP；sing-box 从固定官方地址经直连下载 `geoip-cn`，
缺资产或下载失败拒绝候选启动并恢复原部署，词法合法不等于分类资源可用。
关闭仅删除 IP 子项，保留域名 Block、Direct、SOCKS、DNS/hosts。
状态追加 `block_ips.ip_rules`，完整区域策略向导与宿主目的过滤仍待迁移。

菜单 `17 → 45/46` 或 `--block-ips-resolve/--block-ips-literal` 可切换已有手工
IP 名单的解析模式。新模式要求单 sing-box、无副核心，支持与 WARP 或
`.routing.ipv6` 出站策略组合；目的地址仍可为 IPv4/IPv6。v3
`.routing.block_ips.resolve_domains:true` 需控制包声明
`x-padm-routing-block-ips-resolve`；旧包拒绝，恢复字面模式删除该字段。
组合 WARP/IPv6 还需 `x-padm-routing-block-ips-resolve-egress`；仅支持基础解析模式的旧包拒绝组合。
解析按精确 hosts、指定 DNS、local 顺序选择来源，选路前重新执行 IP 阻断，
代理使用已解析字面 IP，解析失败拒绝且不交给远端回退。Direct 例外仍优先。
按 IPv6 selective、WARP selective、显式 SOCKS、global 出站顺序选路；
各路径使用对应地址族解析后立即阻断并选路，保留已检查的目的地址。
同值或未启用名单返回 `15`；名单、其它配置与流量累计保持，沿用预览和失败恢复。
整组替换、增删和单条替换名单保留已启用的解析开关，删空或关闭名单则一并移除。
只在新模式的 `routing-status.block_ips` 追加 `resolve_domains:true`。
Xray、完整区域策略与宿主过滤继续待交付。WARP 组合以本地加密 Peer 验证，
Cloudflare 账号与公网实际出口仍待验收。

```bash
padm-docker edit --block-ips-resolve --preview
padm-docker edit --block-ips-resolve --confirm PADM-DOCKER-EDIT
padm-docker edit --block-ips-literal --confirm PADM-DOCKER-EDIT
```

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
padm-docker edit --region-mode domain --preview
padm-docker edit --region-allow-add 'example.com,full:api.example.net' --confirm PADM-DOCKER-EDIT
padm-docker edit --region-allow-remove 'full:api.example.net' --confirm PADM-DOCKER-EDIT
padm-docker edit --region-allow-replace 'full:api.example.net' 'full:next.example.net' --preview
padm-docker edit --region-off --confirm PADM-DOCKER-EDIT
```

`--region` 替换模式及自定义例外，不累加旧模式；未指定例外时保存空列表。
区域菜单 `1`–`3` 明示替换自定义例外、留空清空；仅切换已有模式并保留例外使用
菜单 `9` 或 `--region-mode <both|domain|ip>`，只修改 `region.mode`。
未启用或同模式返回 `15`，其它值返回 `2`；固定八条例外、其它路由和配置保持。
已有预设可从区域菜单增删自定义直连例外；追加规范化后按首次出现去重，
自定义列表最多 256 条。删除只匹配完整规范化规则，任一缺项整组拒绝；
删除最后一项后保留模式和空自定义列表，固定八条例外及其它策略保持。
区域子菜单 `7` 单条原位替换已有自定义例外，`8` 查看路由状态。替换前先显示状态，
旧值必须完整规范化匹配一次，新值不能重复现有自定义项；同值、CSV、缺旧项、
未启用或空自定义名单均拒绝。仅改变所选项，保留次序、区域模式、固定八条例外及
其它配置；不能借此替换固定默认例外。状态失败、空输入、`0` 和 EOF 不进入编辑。
关闭仅删除区域预设，保留手工配置的相同 CN 规则、Direct 例外及其它路由能力。
状态单独输出 `region.mode`、`allow_domains` 和 `default_allow_domains`。
IP 模式不为域名目标提前解析或在解析后复查；CN 数据沿用现有资源与下载失败恢复门禁，
不代表最终拨号 IP 过滤或完整区域策略管理。

菜单 `17` 的 `19` 管理 IPv6 域名出站。v3 `.routing.ipv6` 使用独立
`x-padm-routing-ipv6` 门禁，保存 `mode` 与 `domains`；选择性模式接受现有四类
域名规则，全局模式仅改变默认出口，不删除其它策略。

```bash
padm-docker edit --ipv6 selective --ipv6-domains 'example.com,full:api.example.net' --preview
padm-docker edit --ipv6-domains-add 'full:updates.example.net' --preview
padm-docker edit --ipv6-domains-remove 'full:updates.example.net' --confirm PADM-DOCKER-EDIT
padm-docker edit --ipv6 global --confirm PADM-DOCKER-EDIT
padm-docker edit --ipv6-off --confirm PADM-DOCKER-EDIT
```

IPv6 子菜单 `5/6` 与 `--ipv6-domains-add/--ipv6-domains-remove <CSV>` 增删已有
selective 名单，未启用或 global 模式明确拒绝。追加规范化、保留顺序并稳定去重，
合并最多 256 条；删除要求每条完整规范化规则已存在，否则整组拒绝。
删空关闭 IPv6 策略，不切全局模式；其它路由和累计流量保持。
Direct 例外、域名/IP/BT 阻断优先于选择性 IPv6，选择性 IPv6 优先于 SOCKS5；
全局 IPv6 保留显式 SOCKS5 分流，但不能与全局 SOCKS5 同时定义默认出口。
匹配的域名仅使用 AAAA 地址，不回退使用 A 地址；系统 resolver 仍可能查询 A。
原 hosts 与 DNS 分流来源保持不变，IPv4-only hosts 在此路径拒绝，不换源回退。
这不是 IPv4 防火墙，字面 IPv4 不会转换为 IPv6。
关闭只删除 IPv6 子项，保留其它路由、凭据与累计流量。
核心仍为无额外权限的普通容器；启用时附加本项目独立 IPv6 bridge，
不修改原默认网络、Docker daemon 或宿主接口，宿主仍须具备 IPv6 路由与出口。
TUN/TProxy 的宿主网络模式不属于本阶段支持范围，完整 WARP 和宿主验收继续待补。

菜单 `17 → 20 → 1` 和交互 CLI `edit --warp-input` 直接录入已有 WARP Peer 参数，
私钥隐藏输入，只经标准输入进入私有候选。空输入/EOF 或 `0` 取消；
该入口仅交互终端，不与 `--preview`/`--confirm` 组合，最后只确认一次。
子菜单还可关闭、查看状态或管理已有配置的分流域名、全局模式和隧道地址族；
菜单 `6/7` 不保证公网出口地址族。独立 v3 `.routing.warp`
通过 `x-padm-routing-warp` 门禁。原 `--warp <JSON>` CLI 保留，
文件须为 root 所有、`0600`、最多 64 KiB，沿用单链接及安全祖先目录限制；
私钥不放在命令参数、预览或状态中。
输入包含 `mode`（`selective` 或 `global`）、`family`（`ipv4` 或 `ipv6`）、
`private_key`、`peer_public_key`、`ipv6_address`、`reserved` 和 `domains`。
密钥为规范的 32 字节 Base64，`reserved` 为 3 个 `0–255` 整数；
选择性模式要求 1–256 条唯一四类域名规则，全局模式必须使用空 `domains`。

```bash
padm-docker edit --warp-input
padm-docker edit --warp /root/warp.json --preview
padm-docker edit --warp /root/warp.json --confirm PADM-DOCKER-EDIT
padm-docker edit --warp-domains 'example.com,full:api.example.net' --confirm PADM-DOCKER-EDIT
padm-docker edit --warp-domains-add 'full:updates.example.net' --preview
padm-docker edit --warp-domains-remove 'full:updates.example.net' --confirm PADM-DOCKER-EDIT
padm-docker edit --warp-global --confirm PADM-DOCKER-EDIT
padm-docker edit --warp-family ipv6 --confirm PADM-DOCKER-EDIT
padm-docker edit --warp-off --confirm PADM-DOCKER-EDIT
```

日常编辑要求已有合法 WARP 配置，不需重写私有 JSON。域名替换切为 selective，
全局模式清空域名，地址族只改 family；密钥、Peer、隧道地址和 reserved 保持。
这些动作互斥，预览和取消不提交，默认出口冲突在写入前拒绝。
WARP 子菜单 `8/9` 与 `--warp-domains-add/--warp-domains-remove <CSV>` 增删已有
selective 名单，未启用或 global 模式明确拒绝。稳定追加、256 条上限与精确删除
沿用域名增量规则，非空时保留 mode、family、密钥、Peer、隧道地址及 reserved。
删空关闭 WARP 并移除当前私有配置，之后须重新录入或导入；不会隐式切到全局模式。
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
与凭据。凭据生成后的碰撞检查和写入使用标准输入或匿名管道，不进入外部进程参数；
新建、复制和轮换成功后返回该账号凭据。新增入口不自动扩展已有账号授权，
可用 `account edit <账号 ID> --listeners <完整入口 ID 列表>` 显式设置关联；
首次关联 SS 自动生成独立用户密钥，保留关联沿用原密钥，移除全部 SS 关联时清空该密钥。
显式入口选择也接受迁移保留的 `vless-reality/vless-ws`。
普通链接/订阅输出包含自用和启用账号；分享组另有独立 token、账号/入口授权及
纯内容输出，业务备份恢复保留累计，详见 Docker 功能对照表的对应边界。

已有受管规格可从菜单的“编辑配置/导入原始规格”或 `padm-docker edit` 修改入口端口、
服务器地址、地址族、节点名称、Reality 目标/SNI、XHTTP 路径/Host/模式、
gRPC service name、WS/HTTPUpgrade 路径、Hysteria2 拥塞/带宽/混淆/伪装和订阅开关。
编辑先生成私有草稿，显示不含秘密值的差异，候选验证通过并确认后才提交；
未选中的入口、UUID、密钥、token、证书、宿主集成和累计流量保持不变。
菜单可按入口 ID 复制或删除现有协议入口，主核心至少保留一个入口。
Reality Vision/gRPC、direct Trojan 和 VMess HTTPUpgrade 可复制到另一核心，XHTTP 仅支持 Xray；
VLESS/VMess WS TLS、VLESS/Trojan gRPC TLS 和传统 TLS fallback 仅支持 Xray 内复制，通用编辑冻结已有入口的 TLS 身份及内部端口。
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

菜单“协议与入口”的“核心/Nginx 内部端口”可同时修改已有 WS/HTTPUpgrade/gRPC TLS
（21–25）入口的核心后端端口与 Nginx TLS 内部端口，保留公开端口、账号及分享身份。
HTTPUpgrade 支持 Xray/sing-box，其余仅 Xray；额外公开端口及受管 Reality 443 共存同步投影。
端口须为 1–65535，并通过各容器监听、统计 API、HTTP-01 及共存端口冲突检查。
带站点 Fail2ban 时需先停用防护；普通规格导入仍不能修改内部端口。

```bash
padm-docker edit --internal-ports entry-ws 31300 8446 --preview
padm-docker edit --internal-ports entry-ws 31300 8446 --confirm PADM-DOCKER-EDIT
```

菜单“协议与入口”的“额外入口端口”可给已有受管入口添加、删除或修改额外公开端口。
v3 可选顶层 `port_aliases` 保存最多 16 项 `{listener_id, public_port}`；
TCP/UDP 和地址族继承目标入口，多个发布端口仍使用同一认证、入口 ID、账号与累计流量。
TLS 入口继续经 Nginx TLS 前端；bridge 的 Reality 443 共存别名继承完整 SNI 分流，
不是单独隔离的网站或 Reality 入口。没有新核心、证书、宿主权限或任意目的转发。

```bash
padm-docker protocol port-alias-status
padm-docker edit --port-alias entry-reality 8444 --preview
padm-docker edit --port-alias entry-reality 8444 --confirm PADM-DOCKER-EDIT
padm-docker edit --port-alias-replace entry-reality 8444 8445 --preview
padm-docker edit --port-alias-replace entry-reality 8444 8445 --confirm PADM-DOCKER-EDIT
padm-docker edit --port-alias-default entry-reality 8445 --confirm PADM-DOCKER-EDIT
padm-docker edit --port-alias-default entry-reality base --confirm PADM-DOCKER-EDIT
padm-docker edit --port-alias-remove entry-reality 8445 --confirm PADM-DOCKER-EDIT
```

修改要求旧别名存在、新端口不同且不冲突；原位保留别名顺序、默认分享标记和其它规格。
若旧别名已选为默认，链接随事务切换到新端口；预览、取消或失败不保留变更。
默认分享链接使用原公开端口，不自动生成别名节点。
可将已有别名选为该入口的默认分享端口：对应项保存 `share_default: true`，
每个入口最多一项；本地 URI、主订阅和分享组一致切换，账号、凭据和节点数量不变。
`base` 恢复原入口，删除被选别名也自动回退；443 共存恢复到公开 SNI 前端，
不改容器后端。选择只影响指定入口，不联动同数字的 TCP/UDP 其它入口。
重复 TCP 或 UDP 发布端口会拒绝，同一数字的 TCP/UDP 可分别使用；
WS/SSH Fail2ban、TUN/TProxy 与 host-network 共存暂不接受别名；
已有 WireGuard/控制面 Fail2ban 可与别名组合。
普通 `edit --spec` 不能新增或改写别名；删除入口同步清理其别名，复制不继承。
旧控制 bundle 缺少 `x-padm-port-aliases` 时拒绝配置、更新或恢复带别名的规格。
带默认分享标记的规格还要求 `x-padm-port-alias-default`，不能回滚到忽略该标记的旧 bundle。
双栈发布已在隔离 amd64 Linux daemon 验收；公网、原生宿主及 arm64 仍需独立验收，
完整 `207` 保持 `deferred`。

菜单“协议与入口 → 端口跳跃”提供 Hy2/TUIC 范围 DNAT 的配置、启停、清除及活动端口分享。
v3 可选 `port_hopping` 保存 `{listener_id, range_start, range_end, ipv4, ipv6}`，
同步到部署记录和 Compose 的 `x-padm-port-hopping` 元数据。
当前范围限于单 sing-box、单个双族 Hy2 或 TUIC 入口、已有流量统计目录，
无宿主集成或额外运行服务；未运行的 ACME profile 可保留。
不接受别名、控制面、HTTP relay、HTTP-01 或启用的订阅组合。
范围须排除目标公开端口，地址须为本机规范原生 IPv4/IPv6。
TUIC 跳跃配置要求 bundle 能力 `x-padm-port-hopping-tuic`，旧包继续接受原有 Hy2 子集。

保存后须显式 `start`，不会自动启用。启动核对配置和实际容器、采集流量累计并应用额度，
由独立监督维护双族规则。编辑或清除前须 `stop` 并确认清理完成。
`restart/update/rollback/down/uninstall` 通过监督协调；无法确认停止或交接时拒绝继续，
保留累计和失败证据。初始化收到 INT/TERM 后停止后续写入并回收直接子进程；
只有已核验资源且取得净撤销回执才清除会话，较早中断保留未核验现场并拒绝普通变更。
监督启动/重启的推进预算为 120 秒，更新/回滚为 840 秒，代次交接不重置预算。
到期停止授权与成功确认，向原 Bash 请求 TERM；停止等待共用 90 秒预算，
超时保留未核验证据，不强制 KILL 或自动接管。活动会话没有总时长限制；
这些预算限制监督推进和等待，不保证内核资源在固定时间内撤销。
以下入口和地址须换为本机实际值：

```bash
padm-docker edit --port-hopping entry-hy2 30000 30001 198.18.1.1 2001:db8:1::1 --preview
padm-docker edit --port-hopping entry-hy2 30000 30001 198.18.1.1 2001:db8:1::1 --confirm PADM-DOCKER-EDIT
padm-docker port-hopping status
padm-docker port-hopping start
padm-docker port-hopping share
padm-docker port-hopping share 30001
padm-docker port-hopping stop
padm-docker edit --port-hopping-clear --confirm PADM-DOCKER-EDIT
```

`up`、Docker daemon、systemd 或整机重启均不自动恢复监督。
SIGKILL、非合作替换或未知残留保留证据，不自动接管；冲突检查无法排除外部同时修改规则。
隔离 amd64 已验直接 SIGKILL 持锁 Bash：子端退出并撤销双族 NAT/state，
退出容器、owner、stage 和原部署锁保留；查询、停止、启用及生命周期操作拒绝接管。
菜单 `8`“核验并清理残留会话”先预览，再确认清理；也可使用：

```bash
padm-docker port-hopping recover --preview
padm-docker port-hopping recover --confirm PADM-DOCKER-HOPPING-RECOVER
padm-docker port-hopping start
```

`recover` 只处理同一 boot/namespace 归属内原 manager 和 Bash 代次均已结束的受管终态：
已绑定的 stage 路径、子容器、目标与 root/data/net 投影一致，部署锁仍匹配，
精确子容器已退出且退出码为 `0`，
跳跃 state 已消失，双族 NAT 无本会话残留。活跃 owner、未知记录、非零退出或任何漂移均拒绝，
保留现场。核验和清理持目录描述符，拒绝本次期间的路径替换；
现有证据不记录 stage/session 历史 inode，不能识别此前同内容重建，合作锁不抵御任意特权替换。
预览返回 `state:"recoverable"`，确认清理后返回 `state:"stopped"`，
两者的 `saved` 均保留完整范围。清理只回收已核验残留，不修改保存规格、账号或累计，
不删除 conntrack；再次启用须显式 `start`，以新代次和新挑战建立会话。
旧 JSON、环境变量或 tuple 不授权清理，不能删除 owner/锁强行继续。

旧部署缺少 `config/spec.json` 时，先用保留的完整原始输入匹配实际部署：

```bash
padm-docker edit --spec /root/padm-original.json --confirm PADM-DOCKER-EDIT
```

接入后再保存跳跃范围并显式 `start`；缺少输入或账号身份不匹配时拒绝接入。
接入保留 `users.base`、运行账号配置与流量累计，保存范围不会自动启用；
不从运行配置或环境变量推造完整规格。无人值守恢复仍为 `deferred`。
本批 Linux amd64 的 TUIC 恢复、Hy2 自动跳跃及恢复链分别 53.793 秒、105.324 秒通过，
集中合同 57/57 组通过（428.109 秒，含 141 项监督合同）。
后续恢复改动优先运行 `docker-port-hopping-recovery-real`（Jobs 2），
它聚焦 TUIC 残留清理和重新启用；Hy2 自动跳跃使用 `docker-port-hopping-auto-real`。

`share` 只在活动目标与保存规格一致时输出链接，不写静态订阅。
Hy2 无参数输出范围 URI，TUIC 无参数输出范围起始端口的普通 `tuic://`；
`share <端口>` 或菜单 `7` 为两协议输出范围内指定单端口的普通链接，保留认证和 TLS。
TUIC 的范围 DNAT 让客户端可选择其中任一端口，当前固定 sing-box TUIC 客户端
没有 `server_ports`/`hop_interval`，不输出非标准范围 URI，也不宣称客户端自动换端口。
sing-box 客户端 `server_ports` 与 `hop_interval=5s` 已在隔离 Linux amd64
验证同一进程的双族跨端口请求。Hy2 分享生成器同时输出等值的
`upmbps/downmbps` 和 `up/down`，保持客户端方向，修复 Mihomo 原始 URI 导入丢失 Brutal 带宽。
`docker-port-hopping-share-real`（Jobs 2）固定官方 Mihomo `v1.19.28`，
直接导入原始分享 URI，核验 Hy2 Brutal + Salamander/Gecko 范围跳跃及 TUIC 首尾普通 URI，
覆盖双族 HTTP、错误账号拒绝与停止净撤销；停止探针带齐带宽/混淆参数，
先验证同参数能连接，再由新进程验证停止后拒绝。该客户端仅用于回归，不增加生产核心。
三种场景各用独立 netns、daemon 和数据目录，按入口 Jobs 并行。
Hy2 使用客户端原生默认 30 秒随机换端口，最多观察 300 秒，两族跨端口满足即结束。
本地 Linux amd64 的固定客户端导入与实链路已通过，具体证据见实施计划。
其它客户端导入、原生宿主、arm64、公网、TUIC 客户端自动跳跃、
旧会话排空及完整 Hy2/TUIC 跳跃仍为 `deferred`。

菜单“协议与入口 → CDN 连接地址”可为已有 `21/22/23/24/25` WS/HTTPUpgrade/gRPC TLS
入口设置多个 IP 或域名，覆盖自用链接、主订阅和分享组中的连接地址。
v3 可选 `cdn_entries` 保存最多 16 项 `{listener_id, addresses}`，每项 1–16 个唯一地址；
不含该字段时使用原服务器地址。地址不接受 URL、端口、空白或空项。
多个地址按输入顺序生成节点，名称追加 `-1`、`-2`；账号、有效分享端口、
SNI、Host、路径或 gRPC serviceName 和 `h2` 保持，HTTPS 订阅 URL 仍使用原 TLS 域名。

```bash
padm-docker protocol cdn-status
padm-docker edit --cdn-entry entry-ws edge.example.com,203.0.113.8 --preview
padm-docker edit --cdn-entry entry-ws edge.example.com,203.0.113.8 --confirm PADM-DOCKER-EDIT
padm-docker edit --cdn-entry entry-grpc edge.example.com,203.0.113.8 --preview
padm-docker edit --cdn-entry-clear entry-ws --confirm PADM-DOCKER-EDIT
```

清除后恢复原地址；删除入口同步清理覆盖，复制入口不继承。
专项编辑沿用候选、确认和失败恢复事务，提交会按现有流程重建服务。
普通规格编辑不能改写 CDN 覆盖；旧 bundle 缺少 `x-padm-cdn-entry-addresses`
时拒绝带该字段的配置、更新和恢复。仅覆盖 `24/25` 时另要求
`x-padm-cdn-grpc-tls`；旧包可继续处理原三种覆盖及没有覆盖的 gRPC TLS。
本阶段拒绝 Reality XHTTP/gRPC、
其它 TCP/UDP 协议及 H3 参数管理；完整 CDN 管理仍为 `deferred`。

新生成的 `21/22/23` TLS 前端拒绝错误 Host；无 CDN 字段的完整旧 Nginx
正文可继续通过只读和编辑基线，下一次确认配置编辑会生成新正文。
带 CDN 字段要求新正文；缺失部分 Host 校验或其它手写漂移仍拒绝。
`24/25` 沿用受管 Nginx HTTP/2 gRPC 反代和严格 TLS 身份，不套用 WS 的 Host/path 门禁。
公网 CDN 供应商的 gRPC 透传仍需独立验收。

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

已有受管部署可用协议菜单 `14` 增量安装；v3 部署还可用 `15` 直接删除、`16` 保留参数重建：

```bash
padm-docker edit --protocol-add vless-reality 2 28443 --preview
padm-docker edit --protocol-add entry-hy2 31 29443 --confirm PADM-DOCKER-EDIT
padm-docker edit --protocol-add vless-reality 30 30443 --protocol-core sing-box --preview
padm-docker edit --protocol-add vless-reality 21 30444 --tls-domain proxy.example.com --tls-import /root/fullchain.pem /root/key.pem --preview
padm-docker edit --protocol-remove entry-1 --preview
padm-docker edit --protocol-rebuild entry-1 --confirm PADM-DOCKER-EDIT
```

新增默认沿用源核心，可用 `--protocol-core xray|sing-box` 或菜单显式选择核心；
主核心保持，必要时启用副核心，跨核心不能与宿主集成组合。
沿用源 UUID、服务器及地址族，只追加一个稳定身份的入口，
不改变已有账号关联、订阅授权或累计流量。Reality 只能从已有 Reality 派生；
已有 TLS 部署沿用原域名，Naive 使用该证书域名作为服务器。
无 TLS 部署新增首个 TLS 协议时，菜单会询问域名和证书来源；
CLI 使用 `--tls-domain` 以及互斥的 `--tls-existing`、`--tls-import <证书链> <私钥>`、
`--tls-dns <邮箱> <dns_provider> <私密凭据文件>`、`--tls-standalone <邮箱>` 或 `--tls-alpn <邮箱>`。
Nginx TLS 协议还可选 `--tls-webroot <邮箱>`：先以临时 Nginx 提供 HTTP-01，
取得证书后由正式 Nginx 持久监听双栈公网 `80`。仅支持 `21–25/27/29`，
不接管无关端口服务；引导期间可能暂停本部署的 80 所在容器及其 HTTPS。
已有受管/导入证书可做完整候选预览；ACME 预览只校验计划，不申请证书或暂停服务，
交互确认或显式 `--confirm` 后才申请，再验证完整候选并提交。
证书和 ACME 数据沿用现有备份/恢复事务，保留其它域名和账户。
ACME 交互成功后可直接启用自动续期；非交互用 `--tls-auto-renew` 显式选择，
不带该参数保持原登记，预览不登记。登记失败返回错误并保留已成功的配置与证书，
可从证书菜单重新启用，不需重复安装协议。
Shadowsocks2022 不需要 TLS，首次新增在基线和发布验签通过后生成独立服务器/用户密钥，
密钥通过私密候选文件传入，不进入命令参数或预览；同 UUID 已有 SS 则保留原密钥。
v1/v2 沿用现有迁移器生成 v3 草稿，确认成功后才更新部署；证书申请须显式选择。
删除会清理该入口的账号关联、额外端口和 CDN 覆盖；账号最后关联、
主核心最后入口、Reality 共存及 Fail2ban 保护仍须先处理。
重建保留完整规格与身份，并沿用候选验证、确认和失败恢复。
现有事务可能统一重建所有核心，要求当前部署与受管规格匹配。
需要重新选择核心和协议时，使用“安装与重装 → 重新选择核心与协议”或
`padm-docker reinstall`，复用首次向导的核心、协议、地址和四种证书来源选择。
最终确认后生成新账号、密钥和分享身份，替换全部入口、分享组与路由；
累计账本、其它证书、ACME、静态文件与恢复快照保留。
含宿主集成、Reality 共存、端口跳跃或控制角色的部署需先处理对应功能，
向导不会隐式移除这些设置。
完整规格重装可从菜单选择文件，或使用：

```bash
padm-docker reinstall --spec /root/reinstall.json --preview
padm-docker reinstall --spec /root/reinstall.json --confirm PADM-DOCKER-REINSTALL
```

规格须为 root 所有的私密普通文件，支持 v1/v2/v3 候选迁移。
本操作允许替换核心、协议和账号，并撤销全部旧分享组授权；
先核对原受管部署、验签发布和验证完整候选，
再确认并使用现有备份、健康检查与恢复。`edit` 的身份冻结保持。
证书须已受管或通过重装向导显式准备；控制角色、HTTP-01 webroot、共存和
宿主规则转换仍受对应门禁约束，不能用重装绕开。
完整协议管理继续为 `deferred`。

已有 TLS 部署可从“证书管理 → 10. 迁移入口 TLS 域名”，或使用：

```bash
padm-docker edit --tls-migrate new.example.com --tls-import /root/fullchain.pem /root/key.pem --preview
padm-docker edit --tls-migrate new.example.com --tls-existing --confirm PADM-DOCKER-EDIT
```

迁移须显式选择上述四种证书来源之一；复用现有证书准备、候选校验和失败恢复。
仅修改根 TLS 域名、各 TLS 入口域名及等于旧域名的 TLS 连接地址，
保留独立 IP/地址、Reality、SS、端口、账号、分享 token、累计及其它完整规格。
客户端须重新导入链接。ACME 预览只校验计划，确认后才申请证书并验证完整候选。
旧域名的续期登记不迁移；本次迁移成功后自动停用旧域名的活跃 webroot 续期，
保留旧证书与 ACME 账户，DNS-01/standalone/ALPN 的旧登记保持。
新域名使用 ACME 时，可在交互成功后选择续期，或在命令加 `--tls-auto-renew`；
受管/导入来源不接受该参数。宿主集成、Reality 共存、端口跳跃和控制角色暂不支持。
Nginx TLS 部署的迁移也可选 `--tls-webroot <邮箱>`，显式启用新域名 HTTP-01 入口；
预览、取消与配置失败不改旧登记；停用旧登记或启用新登记失败返回错误，
保留已经成功的配置，请从证书菜单重试。提交后中断也须核对并重试旧登记停用。

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
逐入口 Reality 参数重生成、目标库/扫描、有限 443 共存与 XHTTP 管理已交付，具体边界见各专项说明；完整协议管理仍为 `deferred`。
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
padm-docker edit --fail2ban-port entry-ws 8443 --preview
padm-docker edit --fail2ban-port entry-ws 8443 --confirm PADM-DOCKER-EDIT
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
Fail2ban 子菜单第 20 项提供单入口 WS 保护端口迁移，CLI 为
`edit --fail2ban-port <入口 ID> <新公开端口>`。仅接受一个直接 WS 21 入口、
一个 Fail2ban 集成和一个保护端口，新端口必须与旧端口不同；别名、Reality 共存、
SSH/控制面或其它宿主集成及额外编辑组合均拒绝。
专项只联动入口公开端口和 jail 的端口，其余规格冻结；普通导入或通用端口编辑仍拒绝此变更。
确认后先证明旧 jail 清理，再验证新端口的各地址族真实来源，最后启动防护；
失败恢复旧端口也须新挑战。账号、证书、内部端口和 SQLite 封禁历史保留，
客户端需改用新公开端口；预览不切换服务。
WS jail 以 `0:10001` 读取受管 Nginx 日志，目录和文件保持 `0750/0640`；
精确旧无 `user` 编排只用于归属清理和受管迁移，正常启动要求新编排。
旧 WS 与控制面防护并存的部署须先用旧受管入口停用 WS，再升级。
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
启用防护的 Nginx 不接受 HTTP-01 standalone/TLS-ALPN-01 停启，请使用 DNS-01 或 webroot；
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

Fail2ban 子菜单第 12 项和以下命令提供 SSH 宿主只读预检：

```bash
padm-docker fail2ban ssh preflight
padm-docker fail2ban ssh preflight --json
```

沿用 Docker 版 Linux/root、本机 rootful daemon 门禁，不要求已有部署。
从宿主默认 `sshd -T` 读取端口，核对 `ss` 中明确属于 `sshd` 的实际监听端口集合，
仅列出本次 boot 的 `sshd`/`sshd-session` journal 或固定 `/var/log/auth.log`、`/var/log/secure` 日志候选。
文件候选必须是 root 拥有的普通文件，路径无软链接且不允许组/其他用户写入；
不输出认证日志正文、账号或来源地址。工具缺失、端口不符或无候选返回 `10`。
JSON 明确 `scope=host-preflight-only`，`source_verified`、
`runtime_configuration_verified`、`jail_ready` 均为 `false`。
默认配置不能证明运行实例的 `-f/-p/-o` 或 socket activation 配置，
端口一致也不证明绑定地址及地址族一致。历史日志不证明真实失败来源；
该命令不保存凭证、不修改规则或配置、不启用 SSH jail。

Fail2ban 子菜单第 13 项验证本机 SSH 端点的实时外部来源：

```bash
padm-docker fail2ban ssh verify-source 198.51.100.10 2222 203.0.113.7
```

目标须是本机已配置地址，客户端须是同族独立地址；拒绝本机、Docker 网络、
loopback、映射及无 scope 的 link-local 地址。宿主需要 `python3`、`ip`、`ss`、
`journalctl`；这里只读验证，返回的证明不保存、不跨事务使用。
命令输出 `source-challenge` 的随机用户名后，在外部客户端执行：

```bash
python3 -B docker/lib/ssh-source-client.py 198.51.100.10 2222 padm-source-<48位随机值> /client/known_hosts
```

客户端通过官方源安装 `python3-paramiko`，`known_hosts` 必须已可信登记该端点公钥
（非 22 端口使用 `[IP]:端口` 条目）。客户端核对主机密钥后只发送一次无凭据
`auth_none`，保持未认证连接 25 秒。普通 `ssh` 认证失败后会断开，不能替代此客户端。
宿主在 30 秒内将 cursor 后的可信 journal emitter 与同一 master 的 live socket
绑定，精确核对来源及临时端口、目标地址及端口、boot、进程代次和 inode/fd，
成功输出 `source-verified`。只支持唯一宿主 `sshd` listener 与直接子进程 emitter；
同一 socket 由 emitter 与 privsep child 共享时，逐一核对专用 `sshd` UID、安全
可执行文件、直接父子关系、boot/netns、时间、inode/fd 和稳定代次，拒绝其它 owner。
日志文件/tag、旧记录、已断开连接或身份漂移均不能成为证明。
`source_verified=true` 只表示本次来源绑定完成，`runtime_configuration_verified`
和 `jail_ready` 仍为 `false`；本命令不启用 SSH 防护。

Fail2ban 子菜单第 14 项可核对明确 systemd service 的当次实时来源：

```bash
padm-docker fail2ban ssh verify-unit sshd.service 198.51.100.10 2222 203.0.113.7
```

沿用上面的外部挑战客户端，宿主另需 `systemctl` 与可读取的 cgroup v2。
service 必须是实际 `Id`，不接受仅指向另一 service 的 alias。unit 来源核验
进一步要求 fresh master 等于所选 systemd service 的 MainPID，
固定当前 invocation/cgroup，并完整核对两族监听。socket activation、wildcard、
额外 listener/master、不可读 owner 和代次变化均拒绝。成功返回
`scope=ssh-unit-source-only`、`source_verified=true`、`unit_verified=true`；
`runtime_configuration_verified`、`jail_ready` 仍为 `false`。它只证明当次仍存活
连接，不授权历史日志、连续 collector 或 jail，不启停宿主 SSH 服务。

Fail2ban 子菜单第 15–19 项管理有限范围的 SSH 防护：

```bash
padm-docker fail2ban ssh status
padm-docker fail2ban ssh unban 203.0.113.7
padm-docker fail2ban ssh enable sshd-padm.service 198.51.100.10 2222 6 600 3600 --preview
padm-docker fail2ban ssh enable sshd-padm.service 198.51.100.10 2222 6 600 3600 --confirm PADM-DOCKER-EDIT
padm-docker fail2ban ssh settings sshd-padm.service 198.51.100.10 2222 8 900 7200 --confirm PADM-DOCKER-EDIT
padm-docker fail2ban ssh disable --confirm PADM-DOCKER-EDIT
```

只支持原生 Linux root、systemd/cgroup v2 下无存量会话、禁止 reload 的专用
OpenSSH service；从控制台或其它管理通道启用。service 须只有 MainPID 和一个
唯一显式 TCP 监听；拒绝已有子进程、socket activation、别名、wildcard、多监听、
不可信 journal 身份及代次漂移。仅消费本次启动后可信 `Failed password ... ssh2`
事件，不读取历史日志、不恢复旧封禁；不支持其它认证失败格式和 SSH/control INPUT 共存。
单地址族的 INPUT 动作只保护所选目标和端口，WS 防护仍使用独立 DOCKER-USER owner。

启动受管 transient collector 后才启动 `net-fail2ban-ssh`，后者禁自动重启，
只读挂载 root `0700` 来源目录；每批核验刷新 `0600` guard，过期 10 秒或代次
失效时停止 jail 并按 token 清理规则。状态和解封核验当前 unit、容器、动作及 guard；
停止先证明 jail 退出和规则清空，再回收 collector。未证明的残留保留并拒绝接管。
已配置 SSH 时 update、rollback 和业务恢复明确拒绝，先经受管菜单停用再操作；
普通 Docker Compose 启动不能代替此入口，宿主 SSH service 本身不由菜单启停。
隔离 amd64 systemd/OpenSSH/Fail2ban 的实际启停、认证封禁、连接阻断、解封和
来源失效清理已验；原生宿主、arm64、公网、整机重启及完整卸载仍待验收。

已有 TProxy profile 使用私密 `data/net/transparent/tproxy.state` 记录随机链、
规则 token、mark、路由表和路由身份。预检只读核对当前归属与候选冲突；
启动失败及正常停止逐条精确撤销，不 flush 整个链或路由表。
旧两字段 state、固定 `padm-tproxy` 链、未知随机链或外来规则漂移均拒绝接管，
保留资源及恢复证据。此版本独占对应路由表和策略优先级，不支持共享表。
不要直接删除 state 后重试：先停止原拥有者，并在原生 Linux 主机上核对实际资源。
SIGKILL 若留下无 token 规则的空链，需人工确认归属后恢复，不会按同名链猜测清理。
TProxy 管理入口为菜单 `17 → 43`，或以下命令：

```bash
padm-docker protocol tproxy-status
padm-docker edit --tproxy-enable 31298 129 --tproxy-family dual
padm-docker edit --tproxy-settings 31299 131
padm-docker edit --tproxy-settings 31299 131 --tproxy-output-uid 65534
padm-docker edit --tproxy-settings 31299 131 --tproxy-output-all
padm-docker edit --tproxy-settings 31299 131 --tproxy-output-off
padm-docker edit --tproxy-off
```

仅管理单 Xray 或 sing-box 核心的已有 Reality 部署，不能与其它宿主集成共存。
透明入口处理 `PREROUTING` 的 TCP/UDP，族可选 `ipv4`、`ipv6` 或 `dual`。
启用未指定族时默认 IPv4，修改参数未指定族时保留当前值。
菜单第 5/6 项或 `--tproxy-output-uid` 可显式捕获一个本机 UID 主动发起的 TCP/UDP，
UID 范围为 `1–2147483647`，排除受管业务 UID `10001`；root 核心拨号、服务回包与
本地目的不捕获。未指定时保持关闭，修改省略时保留旧 UID；`--tproxy-output-off`
只关闭本机转发，保留 PREROUTING。该模式需 owner/conntrack/MARK，并使用 schema 4
绑定两条链及地址族，旧包须有 `x-padm-tproxy-output-uid` 才能使用或恢复。
菜单第 7 项或 `--tproxy-output-all` 捕获全主机主动 TCP/UDP，包含 root，
与指定 UID 互斥；核心以 `0:10001` 运行，用专用 GID `10001` 绕过拨号，
同组进程也会绕过。LOCAL 与服务 REPLY 保持原路由；修改省略保留当前 OUTPUT 模式。
新状态使用 schema 5 的 `output_all=true`，旧包须有共享
`x-padm-transparent-output-all`；管理时同时检查实际核心身份和规则归属。
所选族须已开启宿主转发并支持对应 TPROXY target，
预检不修改 sysctl。
旧 schema 2 的 IPv4 state 保持兼容；IPv6/双栈使用 schema 3，同一 token
分别绑定两族资源，任一族漂移时保留全部资源与 state，不先清另一族。
启用后核心使用 host 网络、root 和 `NET_ADMIN`；修改或关闭先审计旧容器，
正常停止并确认规则清空，再沿原配置事务提交；预览和取消不停止旧服务。
状态命令显示规格，实际健康仍用 `validate`。隔离 Linux amd64 已验两核心、
三种族的真实 TCP/UDP 转发和停止清理。原生宿主重启、arm64、公网及完整
5C 仍待验收。

Redirect TCP 管理入口为菜单 `17 → 47`：

```bash
padm-docker protocol redirect-status
padm-docker edit --redirect-enable 31298 --redirect-family dual
padm-docker edit --redirect-settings 31299 --redirect-output-uid 65534
padm-docker edit --redirect-settings 31299 --redirect-output-all
padm-docker edit --redirect-settings 31299 --redirect-output-off
padm-docker edit --redirect-off
```

支持单 Xray/sing-box 核心的已有 Reality `1/2/26`，允许同核心多个入口，
不能与其它宿主集成或副核心共存。Redirect 仅捕获 TCP，UDP 保持原路由；
需要透明 TCP/UDP 时选择 TProxy。地址族可选 `ipv4/ipv6/dual`，默认 IPv4；
修改省略时保留旧族。可选一个 UID 的 OUTPUT 主动 TCP，范围与 TProxy 相同，
默认关闭，修改省略保留旧 UID；本地目的、服务回包和 root 核心拨号绕过。
菜单第 7 项或 `--redirect-output-all` 捕获全主机主动 TCP，包含 root；
核心专用 GID `10001`、LOCAL 和 REPLY 绕过，UDP 保持原路由。
与指定 UID 互斥，修改省略保留模式；核心身份、共享 marker 与 TProxy 全主机模式相同。
核心使用 host 网络、root 与 `NET_ADMIN`，所选族需 NAT REDIRECT target，
OUTPUT 另需 owner/conntrack；预检不修改 sysctl。
私密 `redirect.state` 以随机 token 绑定两族及 PREROUTING/OUTPUT 链；
先完整审计再精确撤销，任一漂移保留所有资源与 state，不 flush 或删除 conntrack。
启用、修改、关闭沿现有候选和失败恢复事务，旧 bundle 必须有 `x-padm-redirect`。
两核心、三地址族真实 TCP、UDP 原路径和生产 Compose 撤销已在隔离 Linux amd64 验证。
全主机状态使用 schema 2 的 `output_all=true`，旧 schema 1 兼容。
原生宿主、arm64、公网、重启和完整卸载仍待验。

TUN 管理入口为菜单 `17 → 44`：

```bash
padm-docker protocol tun-status
padm-docker edit --tun-enable
padm-docker edit --tun-off
```

仅支持单 sing-box、单 Reality、IPv4、无其它宿主集成的受管部署。固定接口
`padm-tun`、地址 `198.18.0.1/30`，接管宿主全局 IPv4 TCP/UDP；IPv6 会被拒绝。
核心使用 host 网络、root、`NET_ADMIN` 和 `/dev/net/tun`，禁用容器自动重启。
私密 `tun.state` 绑定 CID、启动时间、网络空间、接口及完整规则/路由归属；
关闭、重启、配置更新和恢复先审计，再正常停止核心，确认恢复基线后才移除证据。
候选只读检查在线归属；异常退出、残留或漂移保留现场，不自动接管或清理。
旧 bundle 缺少 TUN 管理能力时拒绝启用或恢复，不能删除 state 绕过门禁。
Docker Linux amd64 隔离验收已通过；原生宿主、arm64、公网、整机重启和完整卸载仍待验。

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
每次手动同步显式读取受管目录外的 root 私有邀请，祖先目录权限与输出要求一致；过期或撤销时拒绝。
原始 token 不写入 spec、备份、参数、环境或普通日志。客户端无能力、固定本机私网源地址直连，
不使用代理、重定向或公网回退；状态只展示连接元数据，不据此宣称远端健康。
已有被控角色可从控制菜单启用每 5 分钟自动同步，也可执行：

```bash
padm-docker control sync-schedule enable --invite /root/padm-control-invite.json --yes
padm-docker control sync-schedule status
padm-docker control sync-schedule disable --yes
```

默认关闭；启用或更新凭据只导入已验证邀请，不提前应用账号。邀请和身份、连接、入口映射
登记保存在本机 root 私有 `secrets/control-sync/`，不进入配置或业务备份；停用清除持久 token。
轮换后用同一 `enable` 命令导入新邀请。过期、撤销或断网时同步拒绝提交，仍可查询或停用。
固定作业执行 `control auto-sync`，同部署锁冲突退出 `12`，正常停服时跳过且不启动服务；
定时执行在每五分钟边界后延迟 15 秒，避开每分钟流量采集的固定启动秒位。
长事务仍可能让本次同步跳过；直接执行 CLI 仍立即试锁一次，不等待或重试。
已有本部署的精确旧调度可迁移，其它改写任务拒绝接管。
启动恢复任务，更新、回滚和恢复保留本机登记并在停服前拒绝不兼容 bundle 或身份漂移。
仅支持已有单 Peer 被控连接；多 Peer、角色重绑定和需要现场来源证明的 WS/SSH 防护组合拒绝。
新控制 API 同时写入受管 `logs/control/auth.log` 和标准输出，仅记录 UTC 毫秒时间、
状态和实际 socket 的来源、目标及端口，
忽略代理转发头，不记录请求路径、请求头、账号、凭据或异常原文。
文件安全核验、完整写入和同步成功后才发送响应；日志失效或来源不可证明时停止 API。
日志留在配置恢复之外，首次创建不截断已有内容。连接关闭与鉴权失败分开记录；
精确旧版本恢复可保留仅标准输出的受管格式，不宣称具备新日志能力。
新版主控可执行 `padm-docker control source-check` 登记最多 30 秒的随机挑战，
再在受管 Peer 执行输出的 `control source-probe` 命令。探测绑定 WireGuard 源地址，
不读取邀请或发送 token；精确匹配登记、真实 socket 与主控状态的 401 才写独立
`logs/control/source.receipt`，普通访问日志不记录 nonce。
登记退出或中断即清理，旧回执不作为后续启用凭证；配置/容器代次变化时拒绝证明。
存在陌生或变化后的登记时保留并拒绝，不自动删除；此命令不会启用 jail。
控制菜单的“手动轮转认证日志”或 `padm-docker control log-rotate --yes` 在
`auth.log` 达到 10 MiB 时轮转，固定保留 `auth.log.1`、`auth.log.2` 两份历史。
API 使用 root 拥有的 `auth.lock` 只读协作锁；轮转不重启 API，不使用 copytruncate，
不轮转或更换来源回执。旧无协作锁编排拒绝轮转，需先完成正常升级。
控制菜单可启停每小时自动检查，也可运行 `control log-schedule enable|disable --yes`，
`control log-schedule status` 分别显示登记开关与实际任务状态。默认关闭，登记保存在
本机 root 私有的 `data/control-log/schedule.json`，不随业务备份迁移；停服移除任务并
保留开关，启动时恢复。自动入口 `control auto-log-rotate` 在同一部署锁内复核登记
和受管主控，正常停服时跳过，锁冲突时退出 `12`，下次调度重试；来源或登记损坏时拒绝。
已启用调度时，更新和回滚会在切换前拒绝不支持此任务的旧控制 bundle，需先停用。
10 MiB 是检查阈值而非实时大小上限；异常恢复失败保留私有目录，
后续操作拒绝接管。强杀或断电后的现场需人工核对，不能直接删除残留或补建缺失日志。
INT/TERM 等待轮转容器结束并移除后才释放部署锁；Docker daemon 不可用时保持锁并等待恢复。
控制面独立 Fail2ban 后端已具备 `padm-control` jail、独立 SQLite 和随机 owner：
只对实际 `wg-padm` 上单个 RFC 1918 IPv4 /32、TCP 端口的 INPUT `NEW` 连接封禁，
不改 WS 的双栈 DOCKER-USER 资源。防护进程使用 `0:10001`、仅 `NET_ADMIN` 和只读可信日志。
服务维护的 Fail2ban 菜单已提供独立控制面状态、IPv4 解封、启停及参数管理：

```bash
padm-docker fail2ban control status
padm-docker fail2ban control unban 10.77.0.2
padm-docker fail2ban control enable 6 600 3600 --preview
padm-docker fail2ban control enable 6 600 3600 --confirm PADM-DOCKER-EDIT
padm-docker fail2ban control settings 8 900 7200 --confirm PADM-DOCKER-EDIT
padm-docker fail2ban control disable --confirm PADM-DOCKER-EDIT
```

独立 `fail2ban-control` 集成只保存失败阈值、检测窗口和封禁秒数，目标与端口从
`control.listen` 派生；必须为主控且有受管 WireGuard，不要求 Peer 的 API 授权启用。
确认后在同一部署锁内停止旧 jail 并证明本范围清洁，先启动普通服务，再输出本次挑战，
由 Peer 执行 `control source-probe`。nonce、回执、来源容器代次和配置重新核验后，
仅用 `--no-deps` 启动 `net-fail2ban-control`，恢复也必须取得新挑战，不能复用旧证明。
普通 401、旧日志、历史回执和独立 `source-check` 均不构成启用授权；禁止手工启动绕过。
两个 jail 禁用自动重启，daemon 重启后须通过管理入口重新挑战；清理失败保留 state 和规则。
后端真实夹具为 `docker-control-fail2ban-real`，事务验收复用 `docker-control-two-deployment-real`；
SSH、原生宿主 systemd/重启卸载、公网和 arm64 尚未验收。
旧无连接元数据的内部被控规格继续兼容，但不能直接使用外部同步；旧 bundle 不得恢复新连接规格。
显式 `rollback` 在采集、备份和停服前检查被控身份、入口映射与连接一致，拒绝降同步版本，
同版本必须保持摘要和受管账号；同步状态未变的兼容发行版快照仍可回滚。
被控规格要求 bundle 声明回滚保护能力，不能回到缺少该保护的旧脚本。
普通接入/同步失败或中断仍恢复事务前状态，不在本机伪造上游版本。
尚未提供多 Peer、角色重绑定、任意历史账号恢复或 WireGuard 连接向导。
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
padm-docker acme <issue|renew> --domain example.com --email admin@example.com --alpn
padm-docker acme schedule enable --domain example.com --email admin@example.com --alpn
padm-docker edit --http01 enable --preview
padm-docker edit --http01 enable --confirm PADM-DOCKER-EDIT
padm-docker acme <issue|renew> --domain example.com --email admin@example.com --webroot
padm-docker acme schedule enable --domain example.com --email admin@example.com --webroot
padm-docker acme schedule status
padm-docker acme schedule disable --domain example.com
padm-docker acme auto-renew
```

主菜单第 8 项可查看/校验证书、导入轮换、DNS-01/HTTP-01 standalone/webroot/TLS-ALPN-01 申请或续期，并显式开关 HTTP-01 入口、管理自动续期；最终确认前不持有部署锁。
首次配置、重新选择、首个 TLS 协议安装、TLS 域名迁移，以及证书菜单申请/续期成功后，
可复用刚输入的 ACME 邮箱、验证方式和凭据启用自动续期；默认否，`0` 或 EOF 跳过。
登记复用独立的调度恢复事务；失败返回 `15` 并说明证书或配置已成功，旧登记和调度按原事务恢复。
非交互 `edit --tls-dns/--tls-standalone/--tls-webroot/--tls-alpn` 需显式加 `--tls-auto-renew`；
直接 `acme` CLI 继续使用独立的 `acme schedule enable`。
首配/重新选择证书选项 `5` 和编辑 `--tls-webroot` 提供同一 webroot 引导，
可接续 schema 3 自动续期；取消和预览不启动挑战，申请或部署失败沿用现有恢复。
已配置部署必须使用部署记录的 ops 镜像，不能用 `--ops-image` 换成其他镜像。
候选证书检查有效期、域名和私钥匹配后，先执行 `nginx -t` 再重载并检查健康；
失败或中断恢复旧证书和 ACME 账户，保留其他域名及累计流量。
无消费者的域名只保存或校验证书，不修改当前入口和规格。
核心端 TLS 只处理配置中引用的同域名受管 `.crt/.key` 对，使用只读
`/etc/padm/secrets/tls` 挂载；全部消费者先校验，再定向重建核心或 reload Nginx，
逐服务检查健康，失败时尝试恢复全部消费者且累计流量不回退。
HTTP-01 standalone 使用非 root ops 容器的 `8080`，临时发布宿主双栈 TCP `80`；
域名必须解析到本机且公网 `80` 可达，不修改防火墙。
挑战前核对实际容器标签、镜像、挂载、部署与端口归属；外部或无法确认的监听拒绝。
只暂停本部署原本运行的 `80` 拥有者，同容器的 HTTPS 会短暂停机，不停止无关 `443` 服务。
成功、失败或信号后恢复原容器；原本停止的 TLS 消费者不启动。
续期先让 acme.sh 完成到期/ARI 判断，未到期不发布端口、不暂停服务；
恢复失败保留私有候选内的 `challenge.json` 容器 ID 记录，不继续下一域名。
TLS-ALPN-01 复用同一申请、恢复及续期事务，使用非 root ops 的 `8443`，
临时发布宿主双栈 TCP `443`；域名必须解析到本机，公网 `443` 直达该主机，
不能由 CDN 或其它 TLS 终止器代答。首配/重新选择证书选项 `6`，
首个 TLS 和迁移使用 `--tls-alpn <邮箱>`，证书菜单验证方式为 `4`。
仅暂停本部署原运行的 `443` 拥有者，同容器其它端口也会短暂停机，
无关 `80` 服务保持运行；Fail2ban 保护的 Nginx 拒绝自监听停启。
尚未验收公网 CA、原生宿主生命周期和原生双架构，完整 ACME 能力仍为 `deferred`。
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
standalone 登记只保存 schema `2`、webroot 保存 schema `3`、ALPN 保存 schema `4` 请求，均无凭据文件；DNS 保持 schema `1`。
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

Docker 菜单 `10. 账号管理 → 9. 流量与额度` 可查看已保存计数、立即采集并检查额度、
设置账号额度或重置累计。查看不隐式采集；设置和重置各确认一次，重置保留额度。
额度 `0` 表示不限额，空输入或 `r` 返回；账号 ID 使用查看结果原文。
采集、核心重启、锁和恢复语义沿用 CLI，失败可能已保存采样或额度状态。

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
| 🧭 协议与入口 | 本机协议链接与二维码、REALITY、XHTTP、Hysteria2、Tuic、入口端口和 CDN 入口地址。 |
| 🔐 站点与证书 | 传统 TLS fallback 站点、302 重定向、ALPN 诊断/修复和本机 TLS 证书。 |
| 🧱 路由与访问控制 | WARP、IPv6、Socks5、DNS/hosts、BT 阻断、域名/IP 阻断、直连例外和区域阻断。 |
| ⚙️ 核心与服务 | Xray-core / sing-box 生命周期、服务运行态、日志诊断和 Xray Geo 数据；首页只读本地状态。 |
| 🧰 系统与脚本 | 更新 padm、查看脚本安装状态、Fail2ban 防护、网络优化 / BBR。 |
| ⚠️ 高级/危险操作 | 卸载脚本和 VLESS Encryption 实验等高风险开关。 |

`协议与入口` 的第 1 项 `查看全部协议链接` 从当前配置生成本机自用链接，不修改订阅缓存、
公网产物或服务状态。安装完成和此入口共用完整协议链接与本地二维码展示；二维码依赖
`qrencode`，使用紧凑黑白半块字符，最多显示 80 列；二维码过宽、缺失或生成失败时仍保留完整链接。
协议链接保留客户端导入所需参数；
扫码可避免复制长链接，需要 URL 订阅时仍使用 `订阅与用户` 中已配置的发布服务。
半块字符需按单列显示；若终端将其显示为双宽，二维码仍可能错位，需调整终端的字符宽度设置。

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
| `assets/` | 🖼️ 三套本地静态站点资产，供 Nginx 或原生 Hysteria2 使用。 |

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
| 🧪 高级设置 | 调整 XMUX、path/host、首部开关和四项原生 packet/stream limits。 |
| ⚠️ 实验功能 | 配置或关闭上下行分离 `downloadSettings`。 |

默认推荐值面向日常和 CDN：`mode=auto`，`xmux.maxConcurrency=16-32`，`hMaxRequestTimes=600-900`，`hMaxReusableSecs=1800-3000`。每次修改都会先写临时配置并执行 Xray 校验，失败会自动回滚并提示日志路径。

XHTTP 在本项目中由 Xray 生成；sing-box 当前没有 XHTTP transport，因此不会输出 sing-box XHTTP 客户端配置。

`协议与入口` -> `CDN 入口管理` 只负责订阅里的客户端入口地址覆盖，例如 CDN CNAME、优选 IP 或多个入口地址。XHTTP 的 mode、XMUX、path/host 等协议参数仍在 `XHTTP 管理` 中调整。

## 传统 TLS 与本机站点

`站点与证书` -> `传统 TLS fallback 维护` 只服务于传统 TLS/fallback 协议。当流量没有命中代理协议时，Nginx fallback 可以展示本机静态页面或 302 跳转。

这个入口提供：

- 🖼️ 优先导入自有静态网站；没有现成网站时，可用 `notes`、`photos`、`docs` 三套内置布局初始化，包含文章、关于页、本地图片和 404 页面。
- ↪️ 302 重定向维护。
- 🔎 ALPN 诊断/修复，检查 Xray fallback、`fallbacks[].alpn=h2` 和 Nginx h2 fallback 是否匹配。
- ✅ 写入后执行 `xray -test -confdir /etc/padm/xray/conf`，失败自动回滚。

Reality Vision、Reality gRPC 和 Reality XHTTP 不依赖本机静态站点。Reality 的伪装由外部 target 和 SNI 完成。只有你继续使用 VLESS TCP TLS Vision、WS TLS、gRPC TLS、Trojan TLS 等传统 TLS/fallback 协议，或确实要在本机展示网站时，才需要维护这个入口。

`站点与证书` -> `本地静态站点` 可独立维护网页，不要求安装 Xray。首选 `import`：在独立绝对 Linux 目录（如 `/srv/own-site/`）准备完整静态网站，再原样复制到 `nginxStaticPath`（默认 `/usr/share/nginx/html/`）。源与目标不得重叠，源必须含可读 `index.html`；路径和文件名暂限 `A-Za-z0-9_./-`，不接受点文件、符号链接、硬链接、特殊文件、`check` 或 `static-site.json`。导入不改写原文或资源；更新源目录后需再次导入。

导入和内置布局复用暂存、原子替换与失败回滚。自动安装保留已有或修改过的网页；从菜单明确更换自有或修改过的网站时，先将持久私有备份保存到 `/etc/padm/static-site-backups/`。未修改的内置主题只做失败回滚所需的事务临时备份，不为每次切换保存档案。归属状态保存在公开目录之外的 `/etc/padm/static-site.json`，安装或后续配置事务失败时恢复网页与状态；卸载保留自有和导入网站，仅清理归属与内容摘要仍匹配的内置站点。自有网站有 `404.html` 时 Nginx 使用该页面，否则使用默认 404；响应状态均保持 404。

内置布局可配置站名，默认站名与配色固定，同主题重装保持已保存的值。安装后应持续维护真实文章、图片、导航和内页；整套内容与配置可在独立目录准备后导入。同一布局仍共用 HTML/CSS 结构，随机外观或内容差异都不能提供抗识别保证。

原生 Hysteria2 的“认证失败伪装”可直接填写 `file:///srv/own-site/` 使用独立自有网站目录，或填写受你控制的网站 `http://`、`https://` URL 进行反向代理。`local` 使用已有本机网页，`notes`、`photos`、`docs` 初始化内置布局；文件目录须满足上述可读首页及内容限制。sing-box 文件服务的未知路径使用 Go 默认 404 文本。启用混淆后，普通浏览器不能以标准 HTTP/3 访问该入口。Docker 仅支持受管静态网页加 `local`，使用固定只读目录并要求关闭混淆。协议细节参见 [Hysteria2 协议](https://v2.hysteria.network/docs/developers/Protocol/) 与 [sing-box Hysteria2 入站](https://sing-box.sagernet.org/configuration/inbound/hysteria2/)。

## 订阅与用户

订阅系统按服务器角色组织；本机和主控首页按使用顺序排列：`1. 安装/更新发布服务`、`2. 查看当前订阅链接`、`3. 分享订阅`、`4. 流量与限额`、`5. 立即完整同步`、`6. 订阅同步`，最后是角色对应的协同/控制入口和返回。

| 状态 | 菜单形态 | 适合做什么 |
| --- | --- | --- |
| 🟡 未初始化 | 本机订阅首页提供发布、链接、分享、流量和同步；末尾提供启用主控协同、接入主控 | 单机先安装发布服务即可使用订阅；需要多服务器时再选择主控或被控。 |
| 🟢 主控 | 主控首页与本机订阅首页共用发布和订阅入口；末尾提供被控服务器和本机控制面 | 统一查看本机自用与分享订阅，创建分享订阅、添加被控服务器、执行同步和限额治理。 |
| 🔵 被控 | 被控首页直接提供接入、状态、凭据和控制面动作 | 粘贴主控邀请、提供本机节点给主控、查看 WireGuard 与同步状态。 |

主控和本机模式首页的第 5 项执行 `立即完整同步`，第 6 项 `订阅同步` 提供开启/关闭自动同步、设置间隔、状态与排障、状态备份与恢复。自动同步开关控制节点配置变更通知后的同步和 cron；分享订阅及被控服务器的手动管理动作仍立即同步一次，不改变自动同步设置。

首页的 `安装/更新发布服务` 成功后立即完整同步并显示链接，`查看当前订阅链接` 只读展示现有发布结果。`分享订阅` 与 `流量与限额` -> `管理分享订阅与额度` 共用同一个列表和详情；列表、详情直接显示已保存用量及限额状态，选一次即可修改额度、启停或同步，支持多选，不隐式采集流量。新建 ID 或编辑额度输入有误时在当前字段重试，未保存的草稿不会写入。管理员自用订阅仍由本机协议配置自动维护，不写入 `user_groups`、不参与额度治理，也不会通过主控同步下发；统一的是管理入口和发布流程。

- 主控会同步所有已启用的被控服务器源，不再另设全局“远程同步”开关；在 `管理被控服务器` -> `管理已有被控服务器` 选择一次目标，即可连续更新凭据、启停、检查连接、同步或移除，失败后保留当前目标。
- 同步会先完成本机配置，再按来源处理被控服务器快照。只要本机成功且远端同步结果可解析，就发布本次成功来源；失败来源从本次输出排除，并将整体标记为“部分失败”。仅远端用户没有任何可用来源时，保留该用户上一版输出；本机失败或远端结果整体无效时，保留整版公网订阅。
- 修改任一被控的 Reality 目标等节点配置后，被控会通过 WireGuard 通知主控；主控自动同步开启时会重新生成本机节点、拉取启用来源并发布可用来源。外层 HTTPS 订阅地址不变，其他成功服务器节点仍会保留。
- 被控服务器不提供主动同步菜单；配置变更通知失败时，请在主控执行“立即完整同步”。

本机或主控创建分享订阅推荐流程：

1. 在本机或主控首页进入第 1 项 `安装/更新发布服务`，配置公网订阅入口；成功后自动完整同步并显示本机自用及已有分享订阅链接。
2. 在同一菜单进入 `分享订阅` -> `新建分享订阅`，使用英文、数字或短横线 ID，例如 `team-a`。
3. 按向导选择可用服务器源和流量上限。
4. 保存后立即执行一次完整同步，不改变自动同步设置。托管账号 `sub_<ID>` 会写入核心配置。
5. 完整同步完成后，在分享订阅管理页查看链接；首页的第 2 项 `查看当前订阅链接` 只读查看，第 5 项 `立即完整同步` 可刷新全部链接。

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

`核心与服务` 首页只读取本地版本、配置、服务和 Xray Geo 状态，不执行配置检查或访问网络。即使尚未安装核心，也可以进入页面查看状态和执行不依赖本机二进制的只读扫描；远端版本只在明确升级/切换版本时获取。

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

`安装与重装` 只在主菜单提供；不再有独立的“配置健康与兼容”页面。两个核心生命周期页固定为“升级/切换版本”“检查与诊断”“返回核心与服务”三项。“检查与诊断”依次执行当前配置校验和已知升级风险扫描，分别显示“通过”“需关注”“失败”或“无法检查”，只读且不联网、不操作服务。配置校验失败或核心二进制缺失时，仍继续执行不依赖二进制的风险扫描。

`升级/切换版本` 将最近 20 个版本合并显示，每项标注“正式版”或“预发布版”。直接选择编号可升级或切回列表中的旧版本，回车使用最新正式版；选择预发布版后先自动预检，通过后再确认安装。取消安装即可只预检而不替换核心；预检仅用目标二进制校验配置，不代表真实连接验收。输入 `0` 或结束输入取消，不执行升级。

“检查与诊断”的配置校验使用当前核心：Xray 内部依次执行运行检查和严格检查，运行检查失败显示“失败”，仅严格阶段未通过显示“需关注”；sing-box 会先将分片合并到临时文件，再执行 `sing-box check -c <临时配置>`，无分片时校验已有合并配置，不发布配置或操作服务。随后独立显示兼容提示，风险提示不会混为配置校验失败。技术阶段和日志路径只在结果详情中显示。

sing-box 的兼容提示显示本机版本，优先扫描分片、无分片时扫描合并配置，同类提示只报告一次。旧 WireGuard/special outbound、DNS server 格式和 domain_strategy 等显示为历史兼容提示；1.14 弃用字段提示在 1.16 前迁移，TUN `stack` 提示 1.15 起弃用、1.17 移除。JSON 解析或扫描失败仍显示“失败”；当前配置能否被接受以已安装核心的 `merge + check` 为准。升级和安装预检仍保留严格扫描、迁移拒绝和失败回滚。

升级或回退核心时，脚本先下载目标版本到临时目录，用目标二进制校验当前配置；校验通过后才替换 `/etc/padm/xray/xray` 或 `/etc/padm/sing-box/sing-box` 并重启服务。若新核心启动失败，会尝试恢复旧二进制。

Nginx 只在当前协议、站点或订阅配置确实依赖它时可启动、停止、重启或平滑 reload；已安装但不属于 padm 当前依赖的 Nginx 只读。Nginx 配置仍由协议、站点和订阅入口管理，服务页只负责状态与动作。Xray `geosite.dat` / `geoip.dat` 的更新、状态和定时任务统一位于 `Xray Geo 数据`。

### sing-box 统计版与流量恢复

原生部署的 sing-box 主核心、副核心及 Docker 的 `padm-sing-box` 镜像默认使用本仓库 CI 从上游源码构建的统计版，保留上游默认构建标签并追加 `with_purego,with_v2ray_api`，具备 Hysteria2、TUIC 等协议的按用户流量统计能力。原生版本菜单还可选择上游尚未发布统计包的版本，确认后在本机编译；Docker 继续下载锁定镜像。

`with_grpc` 控制完整的 gRPC 传输实现；未启用时仍有默认 gRPC lite，本项目的 Reality gRPC 配置可以使用。按用户统计由 `with_v2ray_api` 独立启用，Hysteria2 和 TUIC 也不依赖 `with_grpc`。

Docker 镜像按 `versions.lock` 固定统计包版本和双架构 SHA256；官方包摘要单独保留，用于统计版构建时校验 Cronet 来源。Docker 已接入上述用户采集和额度管理，执行 `padm-docker update` 会同时更新镜像、宿主控制 bundle 并初始化统计。尚不支持自更新的旧版先按“更新”章节完成一次过渡刷新，必须使用新下载的入口，避免旧 `padm-docker install` 遗漏新增共享模块。现有协议配置会保留，协议入口仍以 Docker 支持矩阵为准。以下菜单步骤适用于原生部署。

若旧核心出现 `v2ray api is not included in this build`，或曾清理统计配置后恢复连接，请在运行 sing-box 的服务器上执行：

1. 从 `系统与脚本` 更新 padm 脚本。
2. 进入 `核心与服务` -> `sing-box 生命周期` -> `升级/切换版本`，回车选择上游最新正式版，或直接选择列表中的版本编号。
3. 在 `核心与服务` 确认 `sing-box 用户统计能力` 为“支持”、服务正常，并执行“检查与诊断”。

升级成功后会根据现有协议用户自动恢复 `14_stats_api.json` 并重载核心，统计 API 仅监听 `127.0.0.1:10087`；已有端口、证书和用户凭据继续保留。统计恢复失败时会尝试回滚核心和配置。复用上次安装配置时，也会将缺少统计能力的旧核心切换为统计版。未采集期间的历史流量无法补算，恢复后的新流量继续按现有账号归集。

升级/切换版本菜单显示上游正式版和预发布版，优先下载本仓库已发布的 `sing-box-v<上游版本>`。明确缺少统计包时，可选择在原生 Linux amd64 / arm64 上编译：解析目标源码提交并下载固定提交的源码，按源码要求下载并校验 Go 工具链，复用与 CI 相同的构建参数，并从该版本官方包提取已校验的 `libcronet.so`。工具链、依赖和编译缓存保留在 `/etc/padm/cache/sing-box-build`，不会替换系统 Go。编译期间旧服务继续运行，版本、统计能力和当前配置校验通过后才进入安装事务，失败或取消不会替换旧核心。网络、限流、摘要或版本校验失败直接停止，不会自动改走编译。旧源码缺少当前构建文件时会拒绝；不承诺所有历史版本可编译或兼容当前配置。

维护者可运行 Actions 的 `Build sing-box Traffic Stats` 工作流，`version` 留空时读取 `versions.lock`，也可指定上游标签（如 `v1.14.0`）。推送至 `main` 时，仅统计版构建文件、统计解码器、镜像检查或相关版本锁输入变化才进入构建准备；无关锁变化跳过。构建逻辑、Alpine 运行依赖或同版本官方摘要变化，以及手动运行，都会重新验证已发布版本，但不会覆盖已发布资产；日常巡检和已发布版本的锁升级仍可复用统计包。两个架构均须通过原生启动、Naive/Cronet 加载、Hysteria2/TUIC 实际传输和用户统计检查，再将本次候选包放入实际 Dockerfile，使用锁定的 Alpine 依赖完成镜像 smoke，才会发布二进制包、对应源码包和 `SHA256SUMS`。二进制包包含 `LICENSE` 和构建信息；统计版 release 不占用 padm 自身的 latest 标记。首次使用前需等待该工作流成功发布。

`Refresh Upstream Versions` 每天北京时间 11:17 调度检查官方 sing-box 最新稳定版（GitHub 调度可能延迟），也可手动运行。发现尚未发布的统计版时，自动调用上述双架构构建工作流；日常巡检复用已完整发布的版本。刷新会更新 Docker 版本锁并创建或继续更新同一个 PR：保留人工提交，合并 `main` 后刷新锁，以普通 push 更新分支；冲突、多个候选 PR 或并发分支变更会明确失败。即使锁没有变化，也会继续检查该 PR 当前提交的 Docker CI，补派缺失或待审批的检查，真实测试失败则保留失败。统计版构建失败时工作流仍报告失败，但允许为已发布版本刷新依赖锁，避免旧 APK 下架阻断修复；失败候选不会进入锁。自动刷新只选择本仓库已发布的正式统计版，忽略草稿和预发布版。更新 PR 仍需合并，Docker CI 在两种架构上检查统计标签、API 启动及 Cronet 加载后才允许发布镜像。需要预发布版时仍可手动指定 `version` 运行统计版工作流。

## 系统与脚本

`系统与脚本` 负责 padm 自身和宿主机辅助项：

- 🔄 更新 padm 脚本；若订阅控制服务已启用或正在运行，会同步刷新并重启。刷新失败不会回滚脚本更新，界面会提示从控制面维护入口重试。
- 🧾 查看入口校验、版本、ref 和 manifest。
- 🛡️ 管理 Fail2ban 防护：原生版包含 SSH 和 `/s/control/`；Docker 版提供 WS、控制面及专用 SSH service 防护，完整宿主验收仍待补。
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
额外入口端口改动使用 `docker-entry-port-alias` 与 `docker-menu-port-alias`；
菜单定向复用完整入口的全部别名 PTY 断言，完整 `docker-menu` 保留原集合。
多入口/双核心拓扑改动使用 `docker-phase3-entries-topology`，
协议增删、TLS 或重装管理改动使用 `docker-phase3-entries-management`。
`docker-phase3-entries` 保留两组并行入口；完整合同直接调度两组，CI 分片覆盖相同叶子。
各任务先运行匹配改动的定向回归，集成完成后集中执行完整回归。
入口归档当前工作区的已跟踪文件和未忽略的新文件，包含未提交修改，不包含 `.git`
和 `.tmp-*`；源码、`TMPDIR`、`HOME` 在容器内部，不挂载 Windows 工作目录。
每次运行的源码快照、日志和结果保存在 `.tmp-regression-docker-*/`，测试失败保留日志并返回原退出码。
镜像只装工具，不固化项目源码；使用 Debian 官方依赖、固定 digest 的官方静态 jq 1.8.2 和官方 Docker CLI/Buildx/Compose，
不安装 daemon、不挂 Docker socket，运行时无网络。工具层需要重新安装时使用 `-Rebuild`。
工具镜像同时登记 `padm-regression:local-<工具内容 SHA256>` 标签；
不同 worktree 的工具输入各自复用对应标签，避免 `local` 被更新后反复构建。
复用前仍核对 Linux 原生架构及工具内容标签，本次回归固定镜像 ID。
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
