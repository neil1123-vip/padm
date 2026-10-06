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
bash install.sh --install-type reality --core xray --reality-target target.example.com:443 --reuse-last no --clean-acme no
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
当前向导支持 Xray Reality Vision/XHTTP/gRPC、sing-box Reality Vision/gRPC/Hysteria2/AnyTLS/NaiveProxy/Shadowsocks，
以及 Xray WS TLS 或 Reality Vision + WS TLS；
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
WS TLS、Hysteria2、AnyTLS 和 NaiveProxy 可选择已有受管证书、导入完整证书链与私钥，或使用 DNS-01；
私钥和 DNS 凭据必须是仅持有者可读的普通文件。订阅发布仍要求 Xray、WS TLS 和受管证书。
Hysteria2 使用单 UDP 入口，支持 BBR/Brutal、Salamander 混淆和 HTTPS 伪装；
带宽按服务端方向输入，分享链接自动转换为客户端方向。端口跳跃及 Gecko 尚未开放。
AnyTLS 使用 sing-box 直连 TCP/TLS 入口，不经过 Nginx；首配选择 sing-box 后选 `7=AnyTLS`。
复用 UUID 作为密码及流量账号，可输出 `anytls://` 分享链接；AnyTLS 单独部署不提供 HTTPS 订阅发布。
NaiveProxy 在 sing-box 首配中选 `8`，使用 TCP/TLS 直连入口；服务器地址必须与 TLS 域名一致。
UUID 同时作为用户名、密码及流量账号，分享链接使用 `naive+https://`；不开放独立 IP/SNI 覆盖或 QUIC。
Shadowsocks 在 sing-box 首配中选 `9`，固定为 `2022-blake3-aes-128-gcm` 多用户模式；
同端口支持 TCP/UDP 双栈，不需要 TLS。确认后独立生成服务器与用户密钥，UUID 作为流量账号。
`ss://` 按 SIP002 百分号编码组合密码；超额时撤销运行入站，解除额度后恢复原密钥和监听。
完整规格保存于 `/etc/padm-docker/config/spec.json`，由 root 持有、权限 `0600`；
取消不提交，配置失败恢复旧规格、证书及 ACME 状态。该文件含秘密，不应打印或公开。

已有受管规格可从菜单的“编辑配置/导入原始规格”或 `padm-docker edit` 修改入口端口、
服务器地址、地址族、节点名称、Reality 目标/SNI、XHTTP 路径/Host/模式、
gRPC service name、WS 路径、Hysteria2 拥塞/带宽/混淆/伪装和订阅开关。
编辑先生成私有草稿，显示不含秘密值的差异，候选验证通过并确认后才提交；
未选中的入口、UUID、密钥、token、证书、宿主集成和累计流量保持不变。
菜单可按入口 ID 复制或删除现有协议入口，主核心至少保留一个入口。
Reality Vision/gRPC 可复制到另一核心，XHTTP 仅支持 Xray；
Hysteria2/AnyTLS/NaiveProxy/Shadowsocks 仅支持 sing-box 内复制；已有部署新增这些类型须导入完整 v3 `configure` 规格。
Shadowsocks 的方法、服务器/用户密钥、UUID 和已有入口身份冻结，不通过通用编辑轮换凭据。
AnyTLS/NaiveProxy 复用通用入口字段编辑，TLS 域名与 UUID 冻结，证书轮换使用证书管理入口。
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
两核心合计最多 16 个入口；v2 仍为单核心。新增协议 `2`/`3`/`4`/`5`/`26`/`30` 仅接受 v3；
Xray 可用 Reality Vision/XHTTP/gRPC 和 WS TLS，sing-box 可用 Reality Vision/gRPC/Hysteria2/AnyTLS/NaiveProxy/Shadowsocks。
首次向导支持 Xray+sing-box 或 sing-box+Xray，副核心首配为 Reality Vision；
主 sing-box、副 Xray 的 WS TLS 首次需使用完整 v3 spec；已有 Xray WS 入口可继续复制。
双核心目前只支持普通 bridge 部署，不能与宿主集成组合。
包含 Hysteria2、AnyTLS、NaiveProxy 或 Shadowsocks 的单核心部署也暂不接受宿主集成。
每个入口的 `listener_id` 固定；旧入口迁移保留 `vless-reality` / `vless-ws`，
新入口使用 `entry-*`。WS 的 `websocket.backend_port` 与 `websocket.tls_port`
按入口独立分配，不重排已有内部端口；身份、公开端口及同一容器网络空间的内部监听不得冲突。
已有部署的 `edit --spec` 也支持这些入口变更，仍经过相同的预览、校验与确认。
删除最后一个 WS 入口会关闭订阅；仍有 Hysteria2、AnyTLS 或 NaiveProxy 时保留规格中的 TLS，
否则将 `tls` 设为 `null`，受管 TLS/ACME 文件与 token 均保留。
Nginx 端轮换、核心端受管 TLS 底座及 Reality XHTTP/gRPC、Hysteria2/AnyTLS/NaiveProxy/Shadowsocks 基础入口已交付；
高级 XHTTP 参数、Reality 目标库/扫描/参数重生成/443 共存与完整协议管理仍未开放。
更新或回滚的目标 bundle 必须同时支持规格版本及每个入口的协议/核心组合。
带 Fail2ban 的 WS 入口暂不允许增删或修改公开端口，需后续联动封禁规则的管理事务。
3A.3 已通过本地双核心事务、PTY、流量、更新/回滚和 Linux 权限回归；真实签名发布、业务镜像及双架构客户端连通仍待验。

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
```

证书和 ACME 任务也由同一个宿主控制命令分发到 `ops` 镜像：

```bash
padm-docker tls manage
padm-docker tls validate --domain example.com
padm-docker tls install --domain example.com --cert /path/fullchain.pem --key /path/privkey.pem
padm-docker acme <issue|renew> --domain example.com --email admin@example.com --dns <dns_provider> --credentials /path/credentials
padm-docker acme schedule enable --domain example.com --email admin@example.com --dns <dns_provider> --credentials /path/credentials
padm-docker acme schedule status
padm-docker acme schedule disable --domain example.com
padm-docker acme auto-renew
```

主菜单第 8 项可查看/校验证书、导入轮换、DNS-01 申请或续期，并查看、启用或停用自动续期；最终确认前不持有部署锁。
已配置部署必须使用部署记录的 ops 镜像，不能用 `--ops-image` 换成其他镜像。
候选证书检查有效期、域名和私钥匹配后，先执行 `nginx -t` 再重载并检查健康；
失败或中断恢复旧证书和 ACME 账户，保留其他域名及累计流量。
无消费者的域名只保存或校验证书，不修改当前入口和规格。
核心端 TLS 只处理配置中引用的同域名受管 `.crt/.key` 对，使用只读
`/etc/padm/secrets/tls` 挂载；全部消费者先校验，再定向重建核心或 reload Nginx，
逐服务检查健康，失败时尝试恢复全部消费者且累计流量不回退。
自动续期需要该域名已有与 DNS provider 匹配的受管 ACME 账户，不能为仅导入的外部证书
直接开启。启用后将 `NAME=value` DNS 凭据和续期输入保存在宿主
`secrets/renewal/<域名>/`，目录为 `0700 root:root`、文件为 `0600 root:root`；
凭据经标准输入进入工具，不放在调度、参数或 Docker 环境变量元数据中。
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
| 基础命令 | 入口下载至少需要 `curl` 或 `wget`；完整包刷新需要 `tar`。 |
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

未传 `--reality-target` 时，脚本会进入目标站选择器。自动选择优先使用 `cdn_risk=no` 且评分为 A 的实测结果；全新 sing-box 安装没有 Xray 检测器时，才允许回退到本次由 OpenSSL 验证 TLS 1.3 的临时 `no + C` 结果，该结果不会写入主结果库。候选列表会先检测全部内置候选，再展示通过检测的结果供选择，不会把未经检测的候选直接交给用户。没有可接受结果时安装终止，不写入未经检测的兜底目标。手工目标会枚举全部 A/AAAA，每个地址独立评分并取最差结果：任一地址属于 AS13335 或可响应 `cloudflare.com` SNI 即标记 `cloudflare_relay`；DNS CNAME 指向已知 CDN 边缘域名，或 ASN/组织属于已知专属 CDN 时标记 `cdn_edge`，两者都会拒绝。DNS、ASN 或 TLS 探测不完整则标记 `unknown` 并拒绝。手工仅接受 `no + A/B/C`，其中 B/C 会明确警告；检测当前已安装目标只告警，不会静默切换配置。`java.com`、`nodejs.org` 与 `riotcdn.net` 及其子域名属于不可覆盖的静态硬风险，候选刷新、扫描导入、自动/手工选择和 Docker 部署都会拒绝。

内置候选池物理上仅保留 37 项未命中已知 CDN/边缘代理及静态风险的候选。原始 194 项中的 154 项 CDN/边缘代理域名仍保留在独立黑名单清单中，用于运行时过滤、审计和黑名单展示，不再从候选池输出。池内其余候选的未知或 TLS 失败状态仍需实时检测，不会被自动选用；目前有明确直连证据并作为默认推荐的是 `www.gnu.org`、`www.debian.org`、`www.ubuntu.com` 和 `mariadb.org`。候选筛选统一按关键词处理，`dev`、`developer`、`开发者` 是同一筛选别名。

Reality 目标站主结果库继续使用 15 列 TSV 写入 `/etc/padm/reality_targets_results.tsv`，物理上仅保留每个目标最新状态仍为 `cdn_risk=no`、评分为 A 且未命中静态或自定义黑名单的记录。目标的新结果降为 B/C/FAIL、风险或 `unknown` 时会移除旧 A；空批次写入也会清理旧格式风险记录。评分包含 TLS 1.3、`X25519MLKEM768` 和证书链长度；可选目标按 `same_asn > same_provider > different_network > unknown`、证书链长度、检测时间排序。

`协议与入口` -> `REALITY 管理` 可检测当前目标、刷新目标库、运行 RealiTLScanner、切换 A 级目标、查看 PQC/ML-DSA-65 状态和配置 443 共存分流。普通刷新会保留已有合格结果，并自动补测候选池中尚未出现在结果文件的 `recommended=yes` 目标，新增目标不会因已有结果而跳过；需要覆盖全部内置/托管候选时可使用“复测全部候选”。

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
| `--reuse-last` | `yes`、`no`、`y`、`n` | `no` | 是否复用上次安装配置。 |
| `--clean-acme` | `yes`、`no`、`y`、`n` | `no` | 清空上次配置时是否同时清理 acme。 |
| `--reality-domain` | `yes`、`no`、`y`、`n` | `no` | 严格域名模式，仅支持单选 Reality Vision `1`；优先用 `--entry-host`，其次 `--domain`。 |
| `--subscribe-port` | 端口号 | 无固定默认 | 订阅发布服务端口。 |
| `--install-nginx` | `yes`、`no`、`y`、`n` | `no` | 订阅或反代需要 Nginx 时是否自动安装。 |
| `--uuid` | UUID | 随机生成 | 初始用户 UUID。 |
| `--user` | 用户名 | 随机生成 | 初始用户名。 |

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
