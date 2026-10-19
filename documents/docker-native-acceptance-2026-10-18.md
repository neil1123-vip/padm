# Debian 13 原生与公网验收

验收日期：2026-10-18–19（北京时间）。本阶段补原生 amd64 证据，不代表整体计划完成。

**当前现场（2026-10-19 19:22 CST）**：SSH 与原三项业务已恢复，透明测试继续暂停。
本轮两次真实证书签发后的正式 TLS 安装、真实 Nginx 失败回滚及原材料恢复通过；
公网严格 HTTPS 和外部 WS 正反例通过。临时工具、备份、私密材料及远端工作目录已清理。
正式 ACME 全链仍受旧受管镜像限制，不把分段验收或业务恢复计作整体完成。

## 环境与可信输入

- 获授权的 Debian 13 amd64 VPS，内核 `6.12.113+deb13-amd64`，真实 systemd、cgroup v2。
- 项目安装入口从官方源安装 Docker `29.9.1`、Compose `5.6.0`；不使用嵌套 daemon 代替宿主。
- 正式 `v3.39.0`、`v3.40.0` 的 manifest、Sigstore bundle 和控制归档全部经过生产 CLI 验签。
- Cosign `3.1.3` 及用于验收的 jq `1.8.2` 均按官方资产 digest 核验；未修改正式归档或跳过验签。
- 正式 manifest 的五个镜像均按 digest 拉取；固定引用保存在各阶段脱敏 inspect 证据中。
- 域名 `b.951101.xyz` 仅临时切换自身 DNS 记录的代理状态；CDN 测试后已恢复直连。

| 正式版本 | 源提交 | manifest SHA256 |
| --- | --- | --- |
| 3.39.0 | `6b2d31bbbcbad1b9b5d9f261b625ef0a4d45cdf0` | `c49394b968e3267e6e8bfc646fc11e8b9790d7e83f483baf2017e4d4dbd77093` |
| 3.40.0 | `6f3676355f621bf5d4a10eb043ba4dc23cbf2084` | `467a4e4ec801e3c8ba4f3da63a44fe7f97edc12085b698cffdfecc1704b247d3` |

## 已取得证据

| 工作流 | 实际结果 |
| --- | --- |
| 安装与首配 | 正式 3.39 bundle 安装、Xray WS 21、受管 TLS 及 HTTPS 订阅 443 配置成功，运行容器健康、validate 通过。 |
| 升级与回滚 | 3.39 → 3.40 → 3.39 成功，稳定规格、账号摘要及 bundle 目标匹配；随后再升级至 3.40。 |
| 公网客户端 | 独立客户端从正式分享 URI 生成配置；首配、升级、回滚、重启后均可访问 HTTPS，出口匹配 VPS；错误 UUID 均被拒绝。TLS 校验始终开启。 |
| 公网 CDN | 解析到 Cloudflare 地址后，固定该地址并保留原 SNI/Host，真实 WS 正反例通过；DNS 代理状态恢复原值。 |
| 公网 CA | 正式 ops 的 HTTP-01 签发和生产 `acme issue --standalone` 均成功，EC-P256、Let's Encrypt 证书安装及 Nginx 重载通过。CLI 测试前单独保存首次测试域名材料，未覆盖旧证书来伪造成功。 |
| 续期调度 | 生产 CLI 登记、timer enabled/active、真实 oneshot Result=success/ExecMainStatus=0；重启后再次执行成功。新证书未到期，续期入口明确跳过，不计作真实续期。 |
| 整机重启 | boot ID 改变，原三个业务容器 ID 保持、健康恢复，流量与续期调度恢复，公网正反例通过。 |
| SSH 防护 | 专用 systemd sshd 显式监听 2222，错误认证触发 jail、精确 INPUT DROP、外部新连接超时；解封和停用成功，管理 22 保持可用。受下述正式版本目录缺陷影响，必须先修正测试目录权限。 |
| WS 防护 | 生产启用流程中的 fresh 来源挑战由独立客户端自动响应；6 次预设无效路径触发封禁，外部后续连接超时，解封成功。 |
| Redirect | 正式 3.40 重装为单 Xray Reality 后，IPv4、端口 `12345`、OUTPUT UID `65532` 启用及 validate 成功；该 UID 的独立 HTTPS 请求成功，实际 OUTPUT REDIRECT 计数从 `0:0` 增至 `1:60`。仅覆盖 IPv4 TCP/TLS 主动连接，不包含 UDP、IPv6、转发入口或 profile 重启。 |
| HTTP relay | 独立外部客户端经公网 IPv4 入口访问三个 HTTPS 目标，严格 TLS 校验和 HTTP 200 通过；错误认证 407、未允许来源 blocked 通过，不包含公网 IPv6。 |
| 卸载与同机灾备 | 保留数据卸载及最终 purge → 整机重启 → 空目标复核 → 同机 v3 灾备恢复通过；原 nginx/xray/subscription healthy、严格 HTTPS 和独立外部 WS 正反例通过，不代表全新主机灾备。 |
| 透明代理源码矩阵 | TUN 当前 validator 的一次性只读挂载验收通过 TCP/TLS、UDP DNS、restart 与净停止后的整机重启/显式 up/down/off；TProxy 当前源码事务 helper 的 TCP/TLS 与对应生命周期通过。指定 UID UDP DNS 的早期失败已定位为缺少 `NET_BIND_SERVICE`，原生固定五元组增权对照和修复后的双核心三地址族隔离回归通过；尚不替代当前修复的正式发布镜像/CLI 及重启矩阵验收。 |
| Reality 共存 | 受管 Vision/WS 同机正反例、Vision 同一连接空闲 75 秒及外部 WS 通过；本批另取得外部 Vision 直连及 443 共存三次正反例，限定条件见末节。桥接与宿主回环网站 HTTPS 200/verify 0、同机 Vision 正反例和 75 秒连接通过。 |

WS 挑战仅开放经过字段白名单校验的域名、端口、地址族和随机 URI。
完整 CLI 输出保存在私有证据目录，不通过临时 HTTP 服务公开。

## 实机发现与修复

- Debian 系统 jq `1.7` 无法解析共享 Xray 生成器中的对象值加法，WS 首配也会失败。
  `992e274d` 补外层括号，输出语义不变；回归镜像保留默认 jq 并增加系统 jq。
  旧生成器加新测试实际失败，修复后 canonical 输出一致；定向总 `9.356` 秒。
- 新 TLS 首配未显式选择站点，legacy Nginx 首页返回 403。
  同一提交让新向导仅在当前包及待切换包都支持站点时写入 `site.default`，
  复用已有 Welcome 页面，不修改旧规格识别；setup 定向总 `85.643` 秒。
- SSH collector 的宿主运行目录未准备，Docker 自动创建为 `0755 root:root`，
  正式 3.40 的候选启用和失败恢复均被生产 `Directory` 的 `0700` 门禁拒绝。
  `8d607f55` 仅为启用 SSH 防护的规格安全创建/归一目录，复用现有 root 属主准备；
  普通部署不生成 collector 状态。旧实现加新测试准确失败，
  修复后的权限定向总 `4.280` 秒，覆盖真实 `Directory` 接受与重复准备。

正式版本失败后，先修正精确测试目录权限，再由生产 CLI 停用、恢复健康并重新启用，
才进行 SSH 真实封禁验收；不把这一人工修正宣称为正式版本已修复。
三个源码修复已本地签名提交，尚未进入新的正式发布；本任务没有推送或发布。
共享工具镜像只重建一次，未重复日常集合或 full。

## 宿主测试中断与恢复

Redirect 验证返回 `0` 后，执行停用 Redirect、启用 TProxy 的串行命令；
该命令未返回阶段退出码，原 SSH 会话即超时。用户报告重启后负载仍高，
VPS 网页控制台也持续报错。随后通过 SSH 完成恢复；未实测网页控制台恢复。
以下数据来自恢复会话观察，远端原始日志及 Redirect 计数文件尚未取回。

现场内存使用约 `914 MiB`、Swap 使用约 `511 MiB` 且已满，`kswapd0` 高占用；
Xray 使用约 `59%–68%` 内存，流量采集服务停在 activating。
Xray 日志反复出现 `[tproxy-in >> direct]` 的 UDP 广播，
目的为 `23.185.168.255:21027` 和 `255.255.255.255:5678`。
源码的 PREROUTING/OUTPUT 首条仅绕过 `LOCAL`，未排除广播、多播。
广播误捕获已经确认；循环放大及其对全部资源耗尽的贡献尚未隔离实测，
不能将完整事故根因写成已证明。

恢复先停止 Xray。Docker 正常停止请求超时后，对核对过的宿主 PID `1144`
发送 TERM，Xray 最终正常退出 `0`；随后正常停止唯一 `net-transparent` 容器，
退出 `0`。两容器均为 `OOMKilled=false`。停止后确认 mangle 无 TProxy 链，
策略规则只剩系统默认项，策略表 `23001` 不存在；未执行全表 flush 或强杀。
将两容器重启策略改为 `no`，禁用 `padm-docker-traffic.timer` 并停止采集服务，
再受控重启。重启后 SSH 可用，内存使用约 `298 MiB`、可用约 `630 MiB`，
Swap 使用为 `0`，负载为 `0.94/0.41/0.15`，无需据此重装系统。

生产规格撤销命令实际执行过：

```bash
PADM_DOCKER_LOCK_TIMEOUT=0 padm-docker edit --tproxy-off --confirm PADM-DOCKER-EDIT
```

该命令因 REALITY 目标 `b.951101.xyz:14443` 的风险检查结果为 unknown，
返回 `15`；没有绕过检查。规格仍为 installed/configured，
profiles 仍含 `core-xray,net-transparent`。`restart=no` 和停止服务只是止血，
再次执行 Compose 或业务启动可能覆盖此状态，不能写成 TProxy 已从规格停用。
当时后续操作须先核对现场，再精确撤销或卸载；未直接拉起事故配置。

随后按精确撤销路径完成现场收口。2026-10-18 19:21 CST 经 SSH 只读复核：
负载 `0.00/0.00/0.00`、Swap 使用 `0 MiB`，`nginx/xray/subscription` 均 healthy；
`net-transparent` 退出 `0`、`restart=no`，Compose profile 仅为
`core-xray,nginx,subscription`，`config/spec.json` 的 `host_integrations` 为空，
`padm-native-target4.service` 已不存在，`padm-docker-traffic.timer` 为 disabled/inactive。
该恢复阶段未部署当前源码或重新启用透明代理；域名 HTTPS 与业务恢复状态保持通过。
用户随后明确授权同一 VPS 可销毁，本轮已转入受独立 containment/watchdog 保护的
TProxy/TUN 集中矩阵；已取得的限定源码证据及未决边界见末节，不沿用旧恢复态
宣称透明代理完整通过。

## 当前未决

- 原生 arm64 安装、升级、回滚、重启、卸载及客户端生命周期：缺少原生 arm64 主机，不能用
  Buildx 或 amd64 仿真替代。
- TProxy 指定 UID UDP 的能力根因、原生单包增权对照及修复后的隔离流量回归已通过；
  正式 `3.40` 缺少 managed-restart marker，TProxy 编辑入口正确拒绝，
  新增能力仍需当前源码正式发布后的镜像、CLI 和原生重启矩阵验收。
  TUN restart 首次 DNS 曾超时，后续独立复测通过，不构成连续稳定证据。
- 公网双栈端口跳跃、旧连接排空和自动恢复：当前 VPS 无公网 IPv6，不能判定通过。
- 同机 v3 空目标恢复已通过；新原生主机灾备仍缺少同架构全新目标。
- webroot/ALPN 的独立 staging 公网挑战、候选校验与服务恢复已通过；本轮新增真实签发后
  正式 `tls install` 换证与 Nginx 失败回滚。签发复用 CA 授权，未重新验证挑战入口；
  正式 `acme issue` 全链仍待当前修复的受管发布升级。
  WARP 仍缺真实账号/公网出口。Reality 已通过生产重装生成，受管/桥接同机流量、
  75 秒连接和外部 WS 通过；宿主回环 Vision 正反例、75.001 秒同连接与严格网站
  HTTPS 通过；本批外部 Vision 三次正反例通过，但不替代正式发布及完整恢复验收。
- HTTP relay 原生外部 IPv4 验收通过；公网 IPv6 不在本次通过范围内。
- 自然到期真实续期：当前登记续期约为 `2026-12-17 08:03:22 CST`，证书到期约为
  `2027-01-16 04:29:07 CST`；调度 no-op 不算换证。
- 当前源码修复的可信正式发布、发布后首配/升级/客户端验收：未获 push、PR 或发布授权。
- 明确拒绝的恢复、协议与宿主组合保持原边界，不因本批环境验收扩大支持状态。

## 2026-10-19 追加原生收口记录

本轮只读复核确认 `net-transparent` 未启用、`host_integrations=[]`、无 port alias、
无 HTTP relay，`nginx`、`xray`、`subscription` 均 healthy，公网 HTTPS 返回 200。
Geo 数据固定版本 `202610172205` 已完成上游拒绝、真实下载、Xray 重建、
systemd timer/service 执行、停用调度和 validate；现有 Geo 数据保留，调度保持关闭。
`geoip.dat` 和 `geosite.dat` 的 SHA256 见私有 evidence，不把凭据或私密输入写入文档。

临时增加 `vless-ws` 的 `2443` alias 后，监听和 HTTPS 200 均通过；随后自动撤销，
规格哈希恢复，临时目录清理完成。该结果只证明受管额外端口的局部原生路径，不等同完整
双栈端口跳跃或旧连接排空验收。

此前临时远端目录和脚本均已删除。后续集中验收使用独立的本轮临时目录，
保持原有来源范围；透明代理另按新的可销毁授权和防护矩阵执行。

### HTTP relay 与公网 CA 集中补验

HTTP relay 的旧测试名单写为 `172.17.0.1/32`，实际受管网桥网关为 `172.18.0.1`。
修正为实际网关后，宿主回环经受管 `36080` 发布端口访问 `api.ipify.org`、
`www.debian.org`、`example.com`，三次真实 HTTPS 证书校验均成功、返回 200。
未允许的 VPS 公网地址访问同一入口时，CONNECT 返回 200，随后 curl 报 TLS 失败；
Xray 同时记录真实来源及 `padm-relay-http -> blocked`。这证明旧 EOF 可以由来源拒绝触发，
不能据此放宽为全网允许。此前外部客户端两次网络检查为超时或 CONNECT 中断；
后续补验已从独立外部客户端取得三个 HTTPS 目标严格 TLS/200、错误认证 407 和
未允许来源 blocked 的完整 IPv4 证据。测试后关闭 relay，原规格 SHA256 恢复。

本机现有 `docker-http-relay-real` 增加真实 TLS origin、IPv4/IPv6 和域名 CONNECT、
严格 CA/hostname 验证、错误 hostname 拒绝以及拒绝来源/错误认证不达目标的断言；
已有 DNS 隔离和业务流量统计对照保留。定向首跑通过，入口 `1.611` 秒，排队
`4.727` 秒，证据 `.tmp-regression-docker-d1b798a6592b42b2aaf3f3fcc1f5d154/`。
改动前的生产 Compose 双栈发布/来源专项也通过，入口 `12.431` 秒；
未改发布逻辑，不重复该专项或 full。

公网 CA 使用独立空候选 ACME home 与 Let's Encrypt staging，复用正式版本的挑战准备、
执行、恢复和候选校验函数，不调用最终提交。ALPN 实际临时暂停并恢复 443 的 Nginx；
webroot 显式临时启用 HTTP-01，挑战期间 Nginx 容器 ID/StartedAt 保持一致。
两项均取得 `b.951101.xyz` 的 EC-P256 候选证书，发行者为
`(STAGING) Artificial Amaranth YE1`，serial 分别为
`2C8A4383396E37E10DF221D51A978F9F5CDA` 和 `2C18A1EA773083417325F3AAFD7CE671EB1C`。
候选证书未安装到生产，不能计作自然续期或正式 CLI 换证。

签发暴露 ops 镜像 BusyBox `date` 无法解析证书日期：
`_ssldate2time Dec 21 17:27:28 2026 GMT` 实际失败。
修复为安装锁定的官方 GNU coreutils，并把依赖贯通到发布锁校验、版本查询、
ops fingerprint 和镜像 smoke；不修改上游 acme.sh。旧镜像的新 smoke 实际失败，
修复镜像直接调用上游 `_ssldate2time` 返回正确 epoch `1797874048`。
新镜像 smoke `2.115` 秒、`docker-phase2` `1.360` 秒、`docker-phase5` `9.898` 秒通过；
证据分别在 `.tmp-ops-date-20261019/`、
`.tmp-regression-docker-f5e89368841f4beab1367694bb1fcab1/` 和
`.tmp-regression-docker-fb2f2b0113b14ccf980608b1d7a7d887/`。
生产仍运行旧正式镜像，日期解析修复需要正式发布后才会生效。

集中补验结束后，`validate` 返回 0，三个业务容器 healthy，HTTPS 返回 200 且证书校验成功；
relay、HTTP-01 和透明集成均关闭，80/36080 无监听，续期 timer active，
正式证书、ACME home、续期登记及原规格哈希全部保持。候选目录与挑战容器均已清理。
脱敏日志归档为 `.tmp-vps-native-20261018/evidence/native-closure-20261019.tar.gz`，
SHA256 为 `9f9460f46793096fb8040656a095822fbda0aaac088e0bef7fdcd2793291ca3c`；
上述补验的远端临时目录、输入凭据和 curl 配置已删除，SSH 会话已退出。

### 可销毁 VPS 集中验收与回归收口

用户随后授权同一 VPS 可销毁。保留数据卸载及最终 purge、整机重启、空目标复核、
同机灾备恢复已通过：boot ID 改变，空目标没有受管业务、规则或集成残留，
随后恢复原 nginx/xray/subscription；该证据不替代全新主机灾备。
代码已签名提交并验签：`f5b35f3a` 的 12 个文件覆盖
ACME、权限与夹具修复，`eff6fd2c` 的 2 个文件覆盖 TUN validator 及测试；尚未正式发布。

原生备份暴露通用候选权限准备把 ACME 私密文件放宽为 `0640`，本轮统一修复为
`0600`，贯通 candidate/runtime/TLS 提交并拒绝链接和特殊文件。`up` 不会自动修复旧权限；
旧材料显式安全修复后内容不变，backup export/verify 通过。ACME 账户恢复绑定
`DEFAULT_ACME_SERVER` 与 `Le_API` 的来源、端口及目录，缺省 `CA_EMAIL`
只从合法登记补齐。真实恢复后完整业务规格与 TLS 的 SHA256 保持，
`.accounts // []` 规范化哈希与原值一致，续期 timer active 且没有 pending。

透明核心读取属主 `10001` 的 `0750` 数据目录与 `0600` TLS 私钥需要
`DAC_OVERRIDE`；后续 UDP 增权对照又确认宿主低端口绑定需要 `NET_BIND_SERVICE`。
透明核心能力统一为 `NET_ADMIN`、`NET_BIND_SERVICE`、`DAC_OVERRIDE`，保留
`cap_drop: ALL`、文件权限与普通核心能力，网络 sidecar 仍仅有 `NET_ADMIN`。
权限准备保留 `data/net/transparent` 子树元数据，避免二次准备把预检创建的
`0600 .tun.lock` 改成 `0640`；严格 validator 继续拒绝篡改。

真实 TUN snapshot 暴露 bridge 动态倒计时、RA 路由到期、GSO 布尔值及 nft
表示差异。validator 仅规范化 bridge 的 `hello_timer/tcn_timer/topology_change_timer/gc_timer`
和协议 `9` 的合法非负整数 `expires` 倒计时，保留字段存在、全路由身份、
其它桥配置及 nft 语义 timer；GSO 使用严格布尔校验，`DOCKER-USER` 只识别链首
两条精确规则，IPv4 interval range 采用规范表示。完整真实 snapshot 重放及独立复审通过，
最终 validator SHA256 为
`d1d17b914cc7a00d6991e1d76a7124df20d9e04acf02f5da5da08794e93944af`。
早前误报由 watchdog 正常 TERM 停止核心，intent 随后经生产 helper 真实 abort/clean
清除；未手工删除 state，内核检查清净。

本机只补与改动匹配的 Docker Linux amd64 回归：TLS `38.540` 秒、
backup `151` 项 `19.236` 秒；日常集合原通过 `31` 项，另 `3` 项夹具修复后
定向通过。最终补验均 exit `0`，不把原失败聚合结果改写成成功：

| 定向检查 | 入口耗时 | 证据目录 |
| --- | --- | --- |
| permissions | `4.821` 秒 | `.tmp-regression-docker-d5fcced58da94948aec9f49f0efaf0d9/` |
| TUN | `24.150` 秒 | `.tmp-regression-docker-fad8f1c4baa14779a98111bd63f1a3d7/` |
| TProxy/Redirect | `54.205` 秒 | `.tmp-regression-docker-1801ec655dd54cd29b1cb2e510ed4354/` |
| phase3-edit | `52.420` 秒 | `.tmp-regression-docker-31651b267ff244d285519abe42e95eea/` |
| TUN resources | `1.325` 秒（测试 `202 ms`） | `.tmp-regression-docker-bfef03b40243481c8587d7d6936de329/` |

该批 `services.sh` SHA256 为
`3a474923a62b84ddc823a54cccac2d683a6e3289de13462af8c2d7b1eba3224c`。
最终 WireGuard focused `74.858` 秒。
其 `77` 次夹具安装改为复用并复制，单次由 `371–387 ms` 降为 `14–15 ms`，
据此估算约节省 `28` 秒；两次 selector 不同，不能当作端到端回归提速实测。
保留有效失败断言，不重复已经通过的日常叶子或 full。

原生 TUN 当前源码通过预检冲突拒绝、enable、TCP 严格 TLS 与 UDP DNS、
restart 后 token 改变及归属核验、down/check；净停止后整机重启（boot ID 改变）、
显式 up、TCP 严格 TLS/UDP DNS、down/off 清理也通过。restart 首次 DNS 超时，
后续独立的严格解析 TCP 与 UDP DNS 通过；这不证明重启后连续稳定。
测试仅在一次性 `net-tun-check` 只读挂载当前 validator，不改 Compose、镜像 digest
或元数据门禁，不能计作正式发布镜像或完整正式 CLI 通过。

TProxy 当前源码生产事务 helper 通过 conflict、enable、TCP 严格 TLS 与规则计数、
restart/down，以及净停止后整机重启、显式 up、TCP/down/off。正式 `3.40` 缺少
managed-restart marker，正式 CLI 正确拒绝，helper 结果不替代发布后 CLI 验收。
早期指定 UID 的 UDP DNS 未通过；root 访问同一 DNS 目标正常，抓包见 loopback 入包
而无外发，监听器具有透明标志。strace 记录进程 `2230` 与监听器进程 `2250`
（fd `8`）不一致，未建立对应关系，不能据空日志判断监听器未收包或内核丢弃。
该批观察本身不足以确定根因；后续已关联真实 PID、FD、socket inode 并固定
五元组完成能力对照，结果见下节，不改写原失败证据。
两套矩阵均未改 sysctl，内存始终充足，
未再发生资源耗尽；容器 healthy 仅作为状态，实际流量另行验证。

Reality 共存使用生产入口生成规格和实际分享 URI。受管 Vision/WS 同机正反例、
Vision 同一 TCP 连接空闲 `75` 秒后数据往返，以及独立外部 WS 通过；
外部 Vision 未通过。桥接网站使用 nginx 容器实际 `host-gateway` 地址，
HTTPS 返回 `200`、证书 `verify=0`，同机 Vision/75 秒通过。桥接地址校验本来不保证
后端可达；启用成功不能代替网站实流量。宿主回环同机 Vision 正反例、
同一 TCP socket 空闲 `75.001` 秒后再次往返、网站 HTTPS `200`/`verify=0` 均通过。
这些结果不补齐外部 Vision、当前修复正式发布或完整支持矩阵。

最终恢复后三项业务均 healthy，严格 HTTPS 返回 `200`、`verify=0`，
独立外部 Docker WS 客户端结果再次保存为 `ok=true`、`positive=ok`、
`negative=SSLEOFError`，见 `evidence/final-public-result-20261019.json`。
TLS 与续期材料原字节由 restore 直接保持；ACME 先按恢复合同规范化，随后人工从
原应急快照精确补回同账户原配置字节，并收紧普通文件为 `0600`。
最终账号哈希保持，续期 timer active/enabled，transparent、relay、alias 均关闭。
临时 DNS `reality-native.b.951101.xyz` 精确删除后查询为 `NXDOMAIN`。

两份脱敏归档均已下载到 `.tmp-vps-native-20261018/evidence/` 并核验：
`native-matrix-20261019-evidence.tar.gz` 的 SHA256 为
`43a0d432158ee626f6e051fa0b16e637c8293664b70faf21299f39f1fea31053`，
`native-matrix-20261019-diagnostics.tar.gz` 的 SHA256 为
`b47ddca8f985e7b1135e7874ef3c6fb93b0a19c8969d85357685514d4e18d47a`。
远端本轮目录经严格路径核对后已删除，无对应测试 unit 或进程；Docker 仅保留原三项
健康业务，策略路由仅有三张默认表，无透明规则。本机 `.tmp-native-disposable-20261019`
及客户端容器已删除，私密应急备份、分享输入和测试二进制已清理；
脱敏日志、snapshots 与前述历史小证据继续保留，不改写原始归档。
账号、客户端私密配置、私钥和 DNS/VPS 凭据不进入本文件或提交。

### TProxy UDP 能力根因与定向收口

原生 VPS 的 `net.ipv4.ip_unprivileged_port_start=1024` 保持不变。
本轮关联 Xray 宿主 PID `32535`、FD `7` 和 socket inode `84673`，
strace 确认监听器 `recvmsg` 已收到带 `IP_ORIGDSTADDR 1.1.1.1:53` 的 DNS，
随后同一 Xray 报 `fake: socket bind: permission denied`。因此早期空 trace
不能用作“内核未投递”的依据；`NET_ADMIN` 本身也不能授权低端口绑定。

保持生产镜像、配置、UID、源端口及 DNS 目标相同，唯一增加
`NET_BIND_SERVICE` 后，dig 返回 `0`、`NOERROR`、两条答案、查询耗时 `8 ms`，
Xray 记录 accepted UDP 并实际外发。该最小对照确认本次失败的能力缺口，
不等同正式 CLI、当前修复的原生重启矩阵或全部 UDP 目标已验收。
修复只作用于 host 透明核心；普通核心不增加 capability，
网络 helper 仍仅 `NET_ADMIN`，不以放宽 sysctl 或文件权限替代。

Docker Desktop Linux amd64 的真实 TProxy 回归固定低端口门槛 `1024`，
覆盖 Xray/sing-box 各自 IPv4、IPv6、双栈共六组，PREROUTING、指定 UID
OUTPUT、全主机 OUTPUT 的 TCP/UDP/DNS、绕过与清理均通过。
Redirect 对应六组 TCP、UDP 直连、绕过和清理通过。
这避免独立网络命名空间默认低端口豁免掩盖宿主能力缺口，不替代公网双栈原生验收。
升级兼容代码已补齐：当前 bundle 以已有三能力合同作使用门禁，backup 保持可读；
透明生命周期包含 TUN，旧包在停服前明确要求 off → update → 重新启用。
TUN 更新重生成 Compose，恢复精确核验模板；Phase 6 新增三透明类型及缺能力旧包
拒绝、漂移不改服务断言，TUN 管理增加只读候选生成检查。独立只读审阅及新增
TUN/Phase 6 定向均通过；当前修复尚未正式发布。

以下七项定向均 exit `0`，仅覆盖此前权限修复快照，不证明新增升级兼容逻辑通过。
该快照 SHA256 为：
`d7dbf52d5c2f442086716de1d7aa9e64b078f1461e990f4243dd11cb2ffcfe25`。
复用工具镜像，未重复 full；下表路径统一位于工作区。

| 定向检查 | 入口耗时 | 证据目录 |
| --- | --- | --- |
| permissions | `6.394` 秒 | `.tmp-regression-docker-f0d2a24cdfc744d4af4c3a6f1397b919/` |
| tproxy-management | `56.710` 秒 | `.tmp-regression-docker-3eeaff274d104a6487810c3d19ba2051/` |
| tun-management | `27.396` 秒 | `.tmp-regression-docker-7e0a3072c0934004afc8347c3167647d/` |
| phase3-edit | `55.272` 秒 | `.tmp-regression-docker-a97336126dd24e139e8d06a5b62017d7/` |
| phase4-lifecycle | `53.284` 秒 | `.tmp-regression-docker-25cab9c6e25f4a0ba41dc40aba1e0d83/` |
| tproxy-real | `104.278` 秒 | `.tmp-regression-docker-9418a4c84c0843769d73d2562f97d788/` |
| redirect-real | `72.564` 秒 | `.tmp-regression-docker-061016311da5413da92b4104da7164bf/` |

新增升级兼容代码另以同一源码快照完成以下两项补验，均 exit `0`：
`4b53efc2027027ae96633bc20cd135b95913bdcc0ea7484496ac57163f7bf31e`。
两项均为 Linux amd64、Jobs `2`、`cache_hit=false`，复用工具镜像
`sha256:be8156c6f4c4a562ff808db15a2609dc84456fdc58712051c1f1d0d6df0215ab`，
不以此前七项结果代替新增逻辑的补验。

| 升级兼容补验 | 入口耗时 | 排队 | 证据目录 |
| --- | --- | --- | --- |
| tun-management | `25.516` 秒 | `5.342` 秒 | `.tmp-regression-docker-3b53620df68445b2b9964a0c13ff6b6f/` |
| phase6 | `57.911` 秒 | `0.222` 秒 | `.tmp-regression-docker-0b6f161716b341fe984c1d868c322bcb/` |

原生脱敏证据包为
`.tmp-vps-native-20261018/evidence/native-tproxy-udp-proof-20261019.tar.gz`，
本机已核 SHA256：
`d113d97d1d1b982ab39248668d0f9006e8a58970edc4762bbedc68423a38896a`。
该最小探针的四项内核资源、两条防护规则和测试容器均已清理；
本机三个 UDP 调查临时文件也已删除。远端 11 个本批临时文件已逐项核对类型、
精确删除并复核不存在。清理后 nginx/xray/subscription 均 healthy，
严格 HTTPS 返回 `200`、证书 `verify=0`，IPv4 策略规则仅余默认优先级
`0/32766/32767`。该清理及健康检查不扩大正式 CLI、重启或支持范围。

### 本批安装入口、菜单与外部 Vision 补验

本批源码基于 `53d2e5ae`。安装入口原先仅凭进程命令行含 `/etc/padm/` 判定原生
部署，误把 Docker 内同名配置路径识别为宿主安装。修复核对受管 executable
或进程根目录中受管路径与宿主路径的 inode，继续拒绝真正原生部署。
两条负断言再改为显式失败，防止断言失败后继续执行掩盖错误。
Docker Linux amd64 `platform-rest -Jobs 2` 两轮 exit `0`，分别为
`6.880` 秒和断言强化后的 `7.012` 秒，均无缓存复用，不重复 full。
最终证据为 `.tmp-regression-docker-1cf631b46bdc47b9a7215a4f0c65077a/`，
源码 SHA256 `dd054679fa3b443a11f128707ffa7c0af4fa2179d9e023f0a416aff2522b171f`。
VPS 当前源码安装执行成功；该源码未正式发布。

远端菜单 PTY 执行曾返回四组通过，总 `36853 ms`，覆盖导航/取消、首页及字段
SIGINT、SIGTERM `143`、EOF。夹具 SHA256 为
`9d45d9a7850bc21fc5f5379e18c2c068601f0bdb4271a311d54a21de9ffa7788`。
原始 `menu-native.json` 已取回并核对，见本批恢复证据包；不以夹具自检代替原生证据。

本机独立 Docker Vision 客户端三次探针均通过：直连入口 `2443`、共存入口
`443`、恢复阶段的 `443`。均固定公网 IP，正确 UUID 获得严格 TLS 校验的
HTTPS `200`，随机错误 UUID 在 TLS 阶段被拒绝。证据位于
`.tmp-native-batch-20261019/reality-external-{direct,stream,recovered}.json`，
每文件为两行 JSON。它们证明对应外部流量正反例，不证明 DNS 解析或当前业务健康；
stream/recovered 字节相同，恢复事务仍须取回远端日志核验，不能只凭文件名认定。

### 本批透明过载取证与业务恢复

正式 `3.40` 控制包仍缺少当前能力合同，本批正式 TProxy 编辑返回 `16`，
正确拒绝旧发布输入。随后受限 wrapper 复用已验证安装输入，调用当前源码生产
`dockerConfigureApply`，但仍使用旧 net 镜像；这不等同正式发布 CLI 验收。
TUN 本批尚未执行，当前透明重启矩阵未通过。

本轮启动前 `systemctl restart padm-native-batch-guard.service` 返回 unit 不存在，
执行链却继续启动 TProxy helper；停止后的 transient unit 不能靠 restart 重建。
取回的 journal 确认 guard 在 UTC `08:59:29` 已停止，随后测试期间未运行；
这是本轮执行保护失误。恢复前面板 CPU `100%`、内存最高 `95.1%`。
取回的 Xray 尾部 `500` 行中，`486` 行是 `[tproxy-in >> direct]` 接收
`255.255.255.255` 或 `23.185.168.255` 的 UDP，确认再次发生广播误捕获。
旧 net 镜像仍只绕过 `LOCAL`；预先插入全局广播/多播规则不能证明其位于
后插入的捕获 hook 之前。没有事故时完整规则快照，不能量化回环放大的贡献。
前一启动的内核日志未发现 OOM 记录，也不能据此否定当时的内存压力。

本机早期 `resources-progress.jsonl` 仅有 UTC `08:54:26–08:56:08` 的 `52` 个样本，
最低 MemAvailable `478440 KiB`、SwapFree `510736 KiB`，不覆盖后续中断。
完整 guard 文件虽有 `152` 个样本，但最后在 UTC `08:59:28`，仍不覆盖事故。
`tproxy-progress.log` 仅记录旧门禁 `exit=16`，不能计作新矩阵通过。

2026-10-19 控制面板重启成功，新的启动从 UTC `09:55:42` 开始，SSH 恢复。
重启后透明容器已退出，TProxy 规则与策略路由已消失，但磁盘 owner 仍在。
使用原镜像的 `tproxy_cleanup` 审计并撤销该 owner，删除已核验的退出容器后，
生产 `dockerConfigureApply` 恢复事务返回 `0`。验收结果：

- nginx/xray/subscription 均 healthy，`host_integrations=[]`，无透明 owner、
  测试规则或 TUN 设备，IPv4 策略规则仅 `0/32766/32767`。
- 原 spec、账号文件、运行中 TLS 证书/私钥、ACME 账号及原域 ACME 证书/私钥，
  共 `7` 项逐字节等于本批原始备份；续期 timer 为 active/enabled。
- 宿主与外部固定公网 IP 的网站 HTTPS 均 `200/verify=0`；独立本机 Docker
  WS 客户端正确账号得到严格 TLS/HTTPS `200`，错误 UUID 在 TLS 阶段被拒绝。
  原域名正常解析访问也返回 `200/verify=0`，本机客户端容器与卷复核无残留。
- 清理后可用内存约 `476 MiB`，Swap 使用不足 `1 MiB`；独立临时 unit 无残留。

2026-10-19 `17:13:17 CST` 已按 ID、类型、域名、地址精确删除本批临时 DNS
`reality-native.b.951101.xyz`，API 复核记录数为 `0`，本机解析返回不存在。
恢复证据已取回，归档排除私密 ACME 日志，本机核 SHA256 为
`b766fe0b1c95e508b38e85635ab0d3f9f4cca5f100d923325eeee33c7489d713`，
路径 `.tmp-native-batch-20261019/native-recovery-evidence.tar.gz`。
WS 证据为同目录 `recovery-ws-external.json`，恢复核对为
`evidence/recovery-verified.json`，菜单原始 JSON 也在该 evidence 目录。
远端本批目录、私密备份、ACME 副本、源码和活动路径标记均已清理。
按原始业务归档的备份清单做差集，精确删除本轮新增 `7` 个备份目录，
原始备份数为 `0`；未清空其它目录。本机私密分享输入也已删除。
透明原生测试保持暂停；必须先匹配修复后的镜像并验证独立 guard 及实际链顺序，
防护失败立即阻断测试。恢复完成不等于透明矩阵或整体计划完成。

### 真实签发、正式 TLS 换证与消费者回滚补验

2026-10-19 UTC `11:10:17–11:12:11`，本轮串行验收返回 `exit_code=0/restored=true`，
不启用透明代理。原正式 ops 仍缺少 GNU 日期解析工具；显式指定独立修复工具的
正式 `acme issue` 返回 `15`，原材料不变。保留该身份门禁，不替换受管镜像引用。
独立工具镜像 `sha256:c569ebf5e0fddfa72db4223fef040a7a520c7e4b25e87a2429822c203ab7ecb9`
仅用于候选签发，未修改部署、镜像身份或正式 CLI。

- webroot、ALPN 各取得一份 Let's Encrypt YE2 EC-P256 证书。两次均复用已有 CA 授权，
  日志明确跳过 `http-01` / `tls-alpn-01`，不宣称本轮 CA 重新访问挑战入口；
  早前独立 staging 账户的挑战证据保持单独引用。
- 两份证书分别通过正式 `padm-docker tls install` 提交，在线严格 TLS、
  指纹切换、HTTP `200` 和三项服务健康通过。
- 复用第一份证书，给 Nginx 固定第二份证书的私钥，触发真实 `key values mismatch`。
  正式 TLS 事务返回 `15` 并自动恢复；TLS 与完整 ACME 内容摘要保持，
  旧在线指纹、严格 TLS、HTTP `200` 通过。该结果属于 TLS 安装失败回滚，
  不宣称正式 `acme issue` 自身失败回滚。
- 原证书通过正式 TLS 安装恢复。规格、配置、账号投影、TLS、ACME、续期材料、
  订阅及 webroot 树的内容和权限匹配原快照；续期及流量 timer 恢复 active/enabled，
  累计流量不回滚。原三项服务 healthy，HTTP-01、relay、透明集成关闭。

独立 systemd guard 在启动验收前确认为 active，并留下 `72` 个资源样本：
最低 MemAvailable `388172 KiB`、最低 SwapFree `502904 KiB`，未触发保护。
保护脚本的低内存自检确认先停止测试再恢复；未复用上轮已停止的 transient unit。
最终外部 WS 正确账号严格 TLS/HTTPS `200`，错误 UUID 被拒绝；
禁用本机代理后的域名直连为 `200/verify=0`，远端地址匹配 VPS。

证据位于 `.tmp-native-close-20261019/`：`native-close-evidence.tar.gz` 的 SHA256 为
`13f24e56b7ba318409227c396eeb63f7fcc4f0728503716b030854db0483a675`，
外部结果为 `ws-external.json`、`https-external-direct.json`。归档排除私密 CA 日志及材料，
脱敏扫描通过；清理记录 `cleanup-final.json` 之后，UTC `11:22:10` 又核实远端工作目录
已删除并退出 SSH。本轮新增 `5` 个备份、候选、临时 unit、工具镜像和私密副本均已清理；
本机分享输入及镜像归档已删除。未重复日常集合或 full，也未扩大支持范围。
正式 ACME 全链、当前透明重启矩阵及既有环境缺口继续未完成。
