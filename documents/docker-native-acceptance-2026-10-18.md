# Debian 13 原生与公网验收

验收日期：2026-10-18–27（北京时间）。本阶段补原生 amd64 证据，不代表整体计划完成。

**当前现场（2026-10-27）**：VPS 已完成正式 `3.41.6 → 3.41.8 → 3.41.6 → 3.41.8 → 3.42.0 → 3.42.1 → 3.42.2`，
其中前四阶段构成 `3.41.8` 升级/回滚闭环，最终运行正式 `3.42.2` bundle；
四阶段公网 WS 4 正/4 拒绝、材料/权限/调度/累计及独立负控通过，
三运行镜像绑定正式 manifest，ops 的 curl `8.23.0-r0` 可执行，透明保持关闭；
固定 Xray 的 TLS 七入口显式 URI 转换互通已通过四阶段独验并清场；
XHTTP 实际 POST 计数和 60 秒有界连接证据也已补齐，不扩大原生 URI 导入或长稳范围。
固定 Mihomo 的公网精确 POST、取消、累计及双模式 60 秒同连接完整轮已独验，
此前失败原件仍保留，详见 2026-10-26 完整补验记录。
Vision/XHTTP 三拓扑故障恢复、
公网双模式、同 handler 独立下行及六点实际整机重启已取得限定范围证据。
原失败前序的两次 bridge 重启及 host 前测补验通过，未复现不等于根因已修复。
原 WS、材料/权限、调度与严格 TLS 均已恢复并复核，本轮临时资源已清理，透明代理保持关闭。
正式 webroot/ALPN `acme issue` 各取得新证书并完成在线换证；第三次申请提前失败，
当轮停止签发。2026-10-23 正式 3.41.4 webroot issue 新证书消费失败全链通过；
3.41.1 缓存 ACME 导出后真实消费失败恢复证据保留；standalone auto-renew
消费失败回滚已补验。ALPN issue 消费失败回滚及同张新证书在线往返通过；
ALPN auto-renew 消费失败回滚已补验。fresh 新账户真实挑战成功，随后以零 CA 请求
完成同张证书在线往返。2026-10-24 修正夹具后的单次 fresh 完整链已通过；
此前两轮失败记录原样保留，不把后续通过覆盖到旧 runner。
原材料、三业务及调度已恢复，测试暂存和认领备份已清，透明代理保持关闭；
不把局部通过计作整体完成。

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

3.41.0 的源提交为 `13b5b5726f35f774ca3a69d4d1ed507007407559`，
控制包 SHA256 为 `4b314c1e4964a2d70b37dd605ab03d63273b25fa3b2e0f7b823a7265a3ba10fd`；
正式签名和归档 digest 已核验，具体升级修复与镜像边界见 2026-10-20 记录。

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
  3.41 正式 net/validator 与验签包逐文件一致，但透明代理按最新授权保持关闭，
  正式 CLI 启用后的连续重启矩阵仍未执行。
  TUN restart 首次 DNS 曾超时，后续独立复测通过，不构成连续稳定证据。
- 公网双栈端口跳跃、旧连接排空和自动恢复：当前 VPS 无公网 IPv6，不能判定通过。
- 同机 v3 空目标恢复已通过；新原生主机灾备仍缺少同架构全新目标。
- 正式 webroot/ALPN issue、standalone/ALPN auto-renew 消费失败回滚已分别通过。
  2026-10-24 单次 fresh ALPN 真实挑战、消费失败完整回滚及同证书在线往返通过；
  此前两轮申请的夹具失败记录保留，自然续期仍待验。
  WARP 仍缺真实账号/公网出口。Reality 已通过生产重装生成，受管/桥接同机流量、
  75 秒连接和外部 WS 通过；宿主回环 Vision 正反例、75.001 秒同连接与严格网站
  HTTPS 通过；本批外部 Vision 三次正反例通过，但不替代正式发布及完整恢复验收。
- HTTP relay 原生外部 IPv4 验收通过；公网 IPv6 不在本次通过范围内。
- 自然到期真实续期仍缺：须等待实际登记窗口；调度 no-op、强制到期及本轮新账户申请
  均不等于自然续期。
- 3.41.5 已正式发布并完成原生验签升级，新增依赖路径表、ACME 私密诊断及 stdin 修复
  已进入运行包；不据此升级其它环境的验收结论。
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

## 2026-10-20 正式升级与原生补验

SSH 主机 ED25519 指纹经用户在控制台独立提供并核对为
`SHA256:K3xTlRmHLGP/jSuM1KhSqyGaA0zMvrUl9lmcAcVEhUo`。
正式 3.41.0 发布签名和控制包核验通过；受管 ops 的 GNU 日期解析以及正式
net/validator 与控制包的一致性均已验证。透明代理始终关闭。

### 升级依赖遗漏修复

旧升级进程沿用旧 `dockerBundlePayloadPaths`，即使新归档含 `shell/core/locale.sh`，
复制和写 manifest 时仍会漏掉它，导致安装后 CLI 失败。本轮没有改写验签归档；
安装 payload 与正式归档逐文件比对一致后，在副本演练官方 manifest 生成流程，
差异仅补 locale。按新 manifest 摘要建 bundle 目录，以官方激活函数切换，
并按 staging 规则规范权限；正式 `padm-docker validate` 返回 0，旧 bundle 保留。

源码改为由新发布包携带纯数据 `docker/contracts/bundle.paths`，升级器验证外部依赖表，
同时完整枚举 docker 目录，保留旧包兼容、已知必需文件与站点资源校验。
绝对路径、穿越、重复、缺失、反斜杠、漏已知依赖及软/硬链接均拒绝。
回归验证未知于当前枚举器的新文件被复制并进入新 manifest。
旧版进程无法追溯获得新逻辑，本次现场迁移修复与今后路径表发布分别计证。

### 正式 ACME 与恢复

UTC `03:40:34–03:41:03`，使用正式 3.41.0 CLI 和受管 ops，
webroot、ALPN 各完成一次 `acme issue`。两次均取得新证书、在线指纹变化，
严格 TLS、HTTP 200 与 nginx/xray/subscription 健康通过，没有使用独立签发工具。
本轮未取得 CA 重新访问挑战入口的证据，不能宣称 fresh challenge 通过或确认授权复用。

第三次原计划固定 Nginx 私钥触发真实消费者失败，但申请在候选阶段提前失败，
尚未到达消费校验。生产入口丢弃了 acme.sh 的原始 stdout/stderr，现有日志只能证明
候选申请失败，不能判断限额或其它具体 CA 原因。累计 3 次后停止签发；
runner 为 `exit_code=1/restored=true`，不得计作正式 ACME 消费失败回滚通过。
原证书经正式 TLS 安装恢复，全部受保护状态树的内容与权限和原快照一致。

### 重启、保护与清理

独立 systemd 资源 guard 在验收前为 active，整机重启前安装临时启动单元，
重连后再次确认 active；保护未触发。阈值为可用内存 150 MiB、剩余 swap 96 MiB、
load1 4，连续 3 次或 45 分钟超时即停止测试并恢复。未记录连续资源样本，
不把几个现场值外推为整个过程的资源峰值。

正式 `restart` 和整机 reboot 均通过；boot ID 变化，三项业务 healthy，
原状态树字节/权限匹配，续期与流量 timer 均 active/enabled，
IPv4/IPv6 策略规则与重启前一致，`host_integrations=[]`。
外层快照曾在中断后的 timer 暂停期采集；原采集值已保留，
以两份一致的中断前 active/enabled 记录校准 timer 基线，没有改动状态树摘要。
重启后可用内存约 538 MiB、swap 使用 0；外部固定公网 IP 的严格 HTTPS 为
200/verify=0，独立 Docker WS 客户端正确账号 HTTP 200、错误 UUID 拒绝。
关闭状态的重启不替代 TProxy/TUN 启用矩阵。

本轮新增 5 个 TLS/configure 测试备份、候选和临时 guard 已清理，
原有两个 update 备份与旧 bundle 保留；归档摘要核对后已删除远端私密工作目录并退出 SSH。
离场复核三项业务 healthy、定时器 active/enabled，无 failed unit；
本机分享 URI、临时 HOME/TMPDIR、已解包源码及中间归档已删除。
脱敏原生证据为 `.tmp-release-native-20261020/native-release-evidence.tar.gz`，
SHA256 `e8268d0b2be11d2dc71afd54268f28cde39c96ec89c890963c4e5d669584e740`；
只收录 JSON、公开证书元数据、boot ID 和阶段标记，不包含私密材料及原始申请日志。
外部结果为同目录 `ws-external.json`、`https-external.json`；
归档后的最终清理记录为同目录 `final-close.json`。

本机复用同一工具镜像，当前修复的定向 `docker-bundle-focused` 为 106.516 秒、
`docker-phase5` 为 10.253 秒；34 项 `docker-contracts -Jobs 6` 为 218.604 秒，均返回 0，
未复用旧结果，未运行 full。证据目录分别为
`.tmp-regression-docker-80ea123be040476d8289f776c2f7df05/`、
`.tmp-regression-docker-93c479fe5f4141fcad540f64fc25a111/`、
`.tmp-regression-docker-9447918c37ca482d89bacff571327308/`。
原生 arm64、公网 IPv6、新机灾备、WARP 实账号、自然续期、ACME 消费失败回滚、
透明启用矩阵及本轮升级修复的正式发布在当时仍未完成；路径表发布接续下节。

### 3.41.1 路径表发布与原生升级

正式 Release run `39380475292` 已成功，3.41.1 源提交为
`b0fd3a07ea92615541449cda3f4166df48f07aeb`，发布于 UTC `06:33:29`。
控制包 SHA256 为
`2f464de653652f29022d74b6a667e5772dfc6d36838a3e03360d8b07ca332cd9`。
VPS 使用 Cosign 验签并核对归档摘要，正式 `assess`、`update`、`validate` 均返回 0；
新 bundle 的 `bundle.paths`、locale 和共享核心依赖存在，bundle ref 匹配源提交。
正式 `restart` 后已等到 nginx/xray/subscription 全部 healthy，未把 starting 算作通过。
续期与流量 timer 均 active/enabled，系统无 failed unit，IPv4/IPv6 策略规则保持默认。

独立外部客户端固定 VPS 公网 IPv4，网站严格 TLS 返回 `200/verify=0`；
Docker WS 客户端正确 UUID 得到严格 TLS/HTTPS 200，错误 UUID 在 TLS 阶段被拒绝。
升级生成的正式回滚点 `update.t5vJXt` 和旧 bundles 保留。
本轮未对升级过程部署连续资源采样，不声明升级全过程峰值。

ACME 错误诊断改为共享运行器保存私密原始输出，失败入口显示阶段、底层退出码与安全路径。
日志位于 `logs/acme/diagnostics/last-error.log`，目录 0700、文件 0600，拒绝链接、
非 root 属主及可被其它用户替换的父路径；终端不回显原始输出。
成功、正常续期 skip 和预检 due 清除无效诊断，保持既有 CLI 15/续期 2 语义。
Docker Linux amd64 定向 `docker-tls-focused` 为 40.049 秒、
`docker-setup-tls` 为 69.772 秒，均 exit 0；未重复日常集合或 full。
这不能补回第三次签发已经丢弃的输出，也不能仅凭 rc 判断具体 CA 原因。

### 3.41.1 离线消费失败恢复与重启

使用正式安装 bundle、受管 ops 及缓存 ECC 账户/证书，容器以 `--network none`
执行 `acme.sh --install-cert --reloadcmd true`，全程 CA 请求为 0。
候选先通过真实校验；仅对本轮提交临时 key 注入随机不匹配私钥，
真实 `dockerCommitTlsCandidate` 切换 ACME 树后被 Nginx `key values mismatch` 拒绝。
原事务自动恢复，TLS/ACME 的完整字节、mode、uid、gid 与原快照一致；
候选 marker 消失，旧在线指纹、严格 TLS/HTTP 200、三项服务健康及透明关闭状态通过。
runner 为 `Result=success/ExecMainStatus=0`。

该结果证明缓存 ACME 导出后的共享提交事务能从真实消费者失败中恢复。
候选证书与原证书相同，没有证明新在线证书再切回旧证书，也不替代正式
issue/renew 消费失败全链或 fresh 公网挑战。本次离线回滚使用 3.41.1；
新增诊断的 3.41.2 实机验收见下节。

外层状态恢复及 verify 返回 0，续期/流量 timer 恢复 active/enabled。
独立 guard 正常退出、未触发，共记录 594 个两秒资源样本，持续 1186.479 秒；
最低 MemAvailable `412492 KiB`、最低 SwapFree `514040 KiB`、最高 load1 `0.9`。
采样仅覆盖重启前的离线验收，不覆盖前面的升级或后面的整机重启。

随后对正式 3.41.1 整机 reboot，boot ID 从
`23a97514-b7e9-49f0-9d23-1fe5cfb13b1f` 变为
`2c686c25-2623-401e-b19c-e866db90b181`。
重连后外层状态再次 verify 通过，三项服务 healthy，timer active/enabled，
IPv4/IPv6 策略规则与重启前一致，透明保持关闭、无 failed unit；
可用内存约 553 MiB、swap 使用 0。
独立外部 Docker WS 客户端正确账号严格 TLS/HTTPS 200、错误 UUID 拒绝；
固定 VPS IPv4 的网站 HTTPS 为 `200/verify=0`。

脱敏证据为 `.tmp-release-upgrade-20261020/native-3411-evidence.tar.gz`，
SHA256 `2481155cdc607fb6ddc6f6ca1477b942f5f81e4fe598aeaba332c701b64d1fe2`。
公网复核为同目录 `ws-post-reboot.log`、`https-post-reboot.json`。
正式回滚点 `update.t5vJXt`、原有两个 update 备份和旧 bundles 保留；
本轮 TLS 测试备份 `tls.Znpksg`、两个远端私密目录、临时 unit、三个 `/tmp`
日志及本机分享 URI、known_hosts、发布中间归档均已清理，SSH 已退出。
UTC `09:15:23` 离场核对三项业务 healthy、timer active/enabled、无 failed unit；
最终记录为同目录 `final-close.json`，归档脱敏扫描通过。

### 3.41.2 诊断修复可信发布与原生验收

签名提交 `e89cb144236b7b419d0ff6f451b53ba3cda7e142` 的 SSH 签名为 G，
按用户授权推送；Release run `39399653170` 的 30 项任务全部 success。
正式 3.41.2 发布于 UTC `09:24:42`，源提交为
`c2688ce06d43f4899aaab6dd6e969aec4263c58e`，控制包 SHA256 为
`8e70d1f4b9a9a758935856840fc6027c75cec1635ad2fdc1cb73255ca68cf744`。
镜像依照正式 manifest 复用 3.41.0 digest，没有强制重新打镜像标签。

VPS 由正式 3.41.1 CLI 完成 Cosign 验签及摘要核对，assess、update、validate 返回 0；
运行 bundle ref 与 3.41.2 源提交一致。TLS、完整 ACME、续期、订阅及 webroot 树的
字节、mode、uid、gid 保持；业务规格只变更 `release` 元数据，透明保持关闭。
正式升级回滚点为 `update.s3aMp6`，原有三个 update 备份继续保留。

持有正式部署锁，通过新 bundle 的真实共享运行器和受管 ops 执行固定无效参数；
额外施加 `--network none --pull never`，使用独立空账户目录，CA 请求为 0。
底层 rc=1，原始输出与私密副本逐字一致，日志 0600/root/单链接，目录 0700；
终端不泄露原文，阶段/rc/安全路径提示通过。随后真实 `--version` 成功，
旧诊断自动清除，本轮账户目录与日志均清理。
该结果验证正式诊断运行器，不宣称重现第三次公网申请原因或正式签发全链失败。

独立 guard 贯穿本次 assess/update/validate/诊断，正常退出、未触发；
146 个两秒样本持续 290.812 秒，最低 MemAvailable `463780 KiB`、
最低 SwapFree `516044 KiB`、最高 load1 `2.87`。
升级后三项业务 healthy，两个 timer 均 active/enabled、无 failed unit，
本地严格 SNI HTTPS 为 `200/verify=0`。本轮不重复 3.41.1 已通过的整机重启。

外部验收固定源站 IPv4：HTTPS `200/verify=0`；公网 WS 正确 UUID 严格 TLS/HTTP
200，错误 UUID 在 TLS 阶段被拒绝。透明代理保持关闭。

脱敏证据为 `.tmp-release-diagnostics-20261020/native-3412-evidence.tar.gz`，
SHA256 `ea4c0b9b9183ea660b3c1ce85c6e6aed74be37cdc6efbf5cd0bbe88287124aef`。
公网结果保留为同目录 `https-external.json`、`ws-external.log`。本机私密 WS URI、
临时 known_hosts、正式 bundle/manifest 副本及一次性验收脚本已清理。
原 SSH 会话已不存在，当前公钥认证失败；未恢复交互 root 登录，因此远端
`/root/.tmp-padm-release-native.UDMdBR` 尚未完成最终核对/清理，不能沿用早先的
`final-close.json` 推断该目录已清除。恢复授权连接后只需核对此精确目录及业务状态。

本阶段关闭不等于整体计划完成：正式 ACME issue/renew 消费失败回滚与 fresh
challenge、透明启用重启矩阵、原生 arm64、公网 IPv6、新主机灾备、WARP 实账号、
Reality 完整失败恢复和自然续期仍未完成；透明代理继续关闭。

### 2026-10-21 本地 CA 新证书消费失败补验

复用 `acme-recovery-real.sh` 的既有 webroot/ALPN 部署、内部 Pebble CA 和发布信任
夹具，新增两种挑战各自的 `acme issue`、`acme auto-renew` 消费失败验收，共四条链。
调用生产 CLI 完成真实签发与候选校验，确认新序列证书和新 ACME 树已提交后，
仅在首次 Nginx 校验前替换为错配私钥，真实 Nginx 报 `key values mismatch`，
CLI 返回 15 并执行原恢复事务，不伪造消费者退出码。

四条链均核对 TLS/ACME 完整字节、mode、uid、gid、链接数，旧在线证书、
规格、续期登记、累计流量、原 Nginx 容器和未重启的 Xray 均保持；
挑战、候选及部署锁清理，真实业务复测通过。故障后再次正常续期成功，
证书序列改变且证书链验证通过。ALPN 原有挑战失败恢复及 HTTPS 暂停断言仍通过。

Docker Linux amd64、Jobs 2，复用工具镜像，两组均 `cache_hit=false`：
`docker-webroot-recovery-real` 为 `103672 ms`，证据
`.tmp-regression-docker-7916a79bd63d4004b8a70fcd7adb8132/`；
`docker-alpn-recovery-real` 为 `141172 ms`，证据
`.tmp-regression-docker-bb5ba78741a7498eb081c394654a9a98/`。
同一源码快照摘要为 `D0CAFE5A099144E93E25CA3B20F08BA1714D0D637C5A0044869FA7A17062A47C`。
入口同时通过 Bash 语法及 ShellCheck error；未重复 daily/full。

本轮所有私钥、临时材料和 nested daemon 资源由原夹具清理；本机仅保留脱敏日志、
结果和镜像清单，两个主机指纹检查临时文件已删除，用户原有临时项未动。
本轮未连接 VPS，远端精确临时目录仍待授权 SSH 连接恢复后核对。
这些证据限定为本地 CA、强制到期和发布信任夹具，不证明正式公网全链、
新证书在线生效再回退或自然续期；透明保持关闭，整体计划未完成。

### 2026-10-22 正式 3.41.4 升级与受管共存六点恢复

用户恢复公钥后，以固定 ED25519 主机指纹连接；未改 SSH 认证策略或尝试密码登录。
正式 3.41.4 源提交 `e2a2248953af907bea33c1b881788e0912a38b97`，控制包 SHA256
`c55828df56b17a5f64473f17d9528fff977f4bcb5932f177c366358085131ed7`。
VPS 通过生产 Cosign 验签，assess/update/validate 均返回 0，运行 bundle ref 匹配；
TLS、完整 ACME、续期、订阅及 webroot 的字节、mode、uid、gid 保持，
业务 spec 除 release/images 保持，正式升级回滚点为 `update.dPN15p`。
升级 guard 正常结束：38 个两秒样本、74.462 秒，最低 MemAvailable `416804 KiB`、
SwapFree `482732 KiB`、最高 load1 `3.22`。

恢复矩阵限定 Debian 13 原生 amd64、正式 bundle、受管网站 bridge 拓扑：
临时 Vision 入口直连 2443，共存公开 443，绑定既有 `vless-ws`。
公网 Reality 目标为 `pgxn.org`（A `88.198.49.178`，当时无 AAAA），
正式 schema 和风险门通过，不使用目标 DNS/ASN/质量元数据或发布信任夹具。
故障 wrapper 只在现有 Docker 调用处注入故障，不替换生产事务。

| 方向 | 故障点 | 真实结果 |
| --- | --- | --- |
| 启用、停用 | 候选安装后健康失败 | 两点均真实 unhealthy/ExitCode 17，CLI 14 |
| 启用、停用 | 旧 443 owner 已停、候选尚未安装时 TERM | 两点 CLI 143，恢复原规格 |
| 启用、停用 | 候选已真实健康、事务提交前 TERM | 两点 CLI 143，恢复原规格 |

六点均核对规格、部署元数据、TLS/ACME/续期/订阅的字节、mode、uid、gid、链接数，
分享 URI、累计不下降、timer 文件/enabled/active，以及部署锁/候选清理；
每点恢复后实际运行同机 Vision 正流量、错误 UUID 拒绝、网站严格 HTTPS，
并确认上传/下载记账增加。正常启用、正常停用和恢复原 WS 业务也返回 0。

独立 Docker 公网 Vision 在 443 连续两次 TLS ConnectionResetError，正确/错误 UUID
均 reset，同机通过但服务端未见对应 accepted 请求，当时根因未确定，不能计为公网通过。
达到两次后停止重试；原 runner 因等待外部复核超时失败，但 outer restore=0。
保留已通过启用 3 点，接续停用 3 点，最终 runner_exit=0/outer_restore=0，
acceptance-complete 及 matrix passed=6，最终 guard completed=true/triggered=false。
恢复原业务后，独立公网 WS 正确 UUID 严格 TLS/HTTP 200、错误 UUID 被拒绝，
固定源站 IPv4 的网站 HTTPS `200/verify=0`。

早期两次保护器按旧 load1>4 阈值中止，内存仍充足；一次 guard 恢复未直接完成，
后续外层恢复/verify 成功。另一次脚本误把快照时主动暂停的 timer 当作丢失，已修正。
这些失败均归档，不表述为整个批次从未失败。保护器保留 MemAvailable<150 MiB、
SwapFree<96 MiB 硬阈值；负载调整为 load1>8，或 load1>4 且 load5>3，连续 3 次触发，
最长 45 分钟。重操作前等待 load1≤1.1；本轮未启用透明代理。
成功启用/停用矩阵分两段采样，共 810 条、采样时长和 `1623.565` 秒，
最低 MemAvailable `357080 KiB`、SwapFree `487984 KiB`、最高 load1 `6.00`；
这是分段和，不是连续总耗时，也不覆盖全部早期失败尝试。

脱敏归档 `.tmp-native-3414-20261022/native-3414-evidence.tar.gz` 共 62 文件，SHA256
`1b63574c5e4d574bc40725d48a4114477c7c816f2c0745475a441ddb85ae2bff`。
包含升级、六点断言、资源分段、早期失败及公网失败，不含 private、URI 或原始业务日志。
本机 Linux 容器离线复核路径、JSON、脚本语法、脱敏及结果门禁通过。
证据目录另保留 `archive-summary.json`、`archive-verified.json`、`ws-external.log`、
`https-external.json`、`remote-close.log` 和 `final-remote-state.log`。

精确清除 19 个本轮 configure 测试备份及保护中止遗留 `.edit.bAO1jz`，不按宽泛前缀删除；
保留 `update.dPN15p`、`update.LnP9nE`、`update.pDAJCS`、`update.s3aMp6`、
`update.t5vJXt` 五个正式备份。本轮两个远端工作目录及此前待清理的
`/root/.tmp-padm-release-native.UDMdBR`、上传脚本已清；原有 pre-recovery 目录未动。
本机分享 URI、known_hosts、manifest 副本及一次性脚本已清，用户原有临时项未动。
UTC `02:44:02` 离场：三服务 healthy、两 timer active/enabled、无 failed unit、
无事务暂存，load1/load5 均 `0.00`，MemAvailable 约 433 MiB、SwapFree 约 484 MiB。

本轮无生产代码修改，未重复已通过的 24 场景、权限合同、日常 34 项或 full。
六点仅证明本拓扑原生失败恢复，不替代其它原生拓扑、XHTTP 全矩阵或整机重启；
本次公网 Vision 失败、正式 ACME 全链/fresh 挑战、透明启用重启矩阵、原生 arm64、
公网 IPv6、新主机灾备、WARP 实账号及自然续期仍未完成，整体计划保持未完成。

### 2026-10-22 公网 Vision reset 的测试端路径定位

后续只读核对两端 Xray 均为 `26.3.27/d2758a0`。现有 VPS 443 已恢复为原 Nginx WS，
只装载 `b.951101.xyz` 证书，不含 pgxn 证书或 REALITY stream。
Docker 客户端固定连接 `23.185.168.63:443`，分别使用 b 域、pgxn、Debian、pgxn SNI，
四次严格 TLS 均成功且证书主体随 SNI 改变；VPS 同期抓包仅见一条 TCP 连接，
17 包、内核丢包 0。该现象说明固定 IP 没有保证流量确实到达 VPS。

本机 Docker Desktop 手动 HTTP/HTTPS 代理为 `127.0.0.1:10808`，该 v2rayN/Xray
入口启用 TLS sniffing、`destOverride=["http","tls"]`、`routeOnly=false`。
另有 Proxifier 将 curl、SSH 等进程送入同一入口，故 `curl --noproxy` 也不等于直连。
显式通过 10808 的 SOCKS 请求仍指定 VPS IP，但 pgxn SNI 得到真实 pgxn 证书。
这与 Xray 官方入站定义吻合：非 routeOnly 嗅探会用域名重置目标地址。
本轮只读原代理配置，未修改或重启用户的代理服务。

两种不改写目标的对照均指向原 VPS：SSH 封装下 pgxn SNI 因域名不符而严格校验失败，
b 域通过；临时原生 Xray 只监听回环并固定转发 VPS 443、关闭嗅探，pgxn 请求返回
VPS Nginx 404，b 域返回原网站 200。未开放通用 SOCKS 或任意目标转发。

另启动独立临时 Xray Vision 2443，使用正式镜像、随机账号/密钥和 pgxn 目标，
不改原部署、不占生产 443，限制 96 MiB 内存并由 systemd 15 分钟自动停止。
普通公网与 SSH 两条路径均 `Verified=true`、严格 HTTPS 200，错误 UUID 拒绝，
服务端 accepted/invalid-user 与两条客户端结果对应。
原公网 443 路径复现 `ConnectionResetError`，底层为 `uConn.Verified: false`、
`REALITY: received real certificate (potential MITM or redirection)`。
由此将问题收窄为测试端上游 TLS 嗅探改写目标，不再归为未解释的 VPS 服务故障。

证据保留 `.tmp-vision-diagnose-20261022/diagnosis.json`、严格 TLS 对照 JSONL、
三组探针结果、脱敏客户端日志、`local-routing-sanitized.json` 和 `remote-close.json`。
原始 AuthKey/debug 日志、临时 URI、主机密钥文件、脚本和 VPS 抓包均已清；
SSH/回环转发已停，临时容器/卷已回收。UTC `04:08:35` 清理核验：
四份生产配置哈希不变、三服务 healthy、两 timer active/enabled、严格本机 HTTPS 成功、
无 failed unit、透明保持关闭。

原两次失败未保留底层日志，本轮是同环境目标改写及同样 reset 的后续复现；
443 复现发生于原 WS 已恢复之后，独立 2443 通过也不能替代正式 bundle 共存验收。
因此不把原两次改写为通过；正式 443 共存须先隔离或修正测试端嗅探再复验。
未重复完整回归，未改变生产代码、代理设置或支持矩阵，整体计划仍未完成。

### 2026-10-22 正式 443 共存公网复验

在原 Debian 13 amd64 VPS、正式 3.41.4 bundle 上补验受管网站 bridge 拓扑，
源 `e2a2248953af907bea33c1b881788e0912a38b97`，控制包及生产验签素材与前节相同。
通过正式 `configure` 建立临时 Vision，再用正式 `edit --reality-stream`
绑定 `entry-native-reality-vision` 与 `vless-ws`；目标保持 `pgxn.org:443`。
不替换生产事务、不使用发布信任或目标质量元数据夹具，透明代理始终关闭。

独立 Docker 客户端通过本机原生 Xray 的回环 TCP 转发，唯一目标固定为
`23.185.168.63:443`、关闭嗅探；容器经 `host.docker.internal:18443` 接入。
转发仅监听 `127.0.0.1`，不提供通用代理、不改全局 v2rayN/Proxifier/Docker 设置。
公网 TLS 对照先确认 b 域严格校验并返回 200、pgxn SNI 收到 VPS 证书并产生
主机名不匹配；本轮不是 SSH 封装路径，固定目标不再被 SNI 改写。

| 检查 | 结果 |
| --- | --- |
| 原 WS 公网基线 | 正确 UUID 严格 HTTPS 200；错误 UUID 拒绝 |
| 正式 443 共存 Vision | 正确 UUID 严格 HTTPS 200；错误 UUID 拒绝 |
| 同一 443 共存 WS | 正确 UUID 严格 HTTPS 200；错误 UUID 拒绝 |
| 共存网站 | b 域严格 TLS 校验、HTTP 200 |
| 服务端关联及记账 | 抓包 510 包、内核丢包 0；双向累计增加且无账号累计回退 |
| 恢复原 WS | 正式恢复、外层恢复和 verify 均 0；字节/权限/timer 保持 |
| 恢复后公网复验 | WS 正反例通过、网站严格 HTTPS 200 |

最终 runner_exit=0，guard completed=true/triggered=false；87 个两秒资源样本，
采样时长 `173.246` 秒，最低 MemAvailable `323624 KiB`、SwapFree `505104 KiB`，
最高 load1 `5.23`。该时长仅覆盖最后成功 runner，不包括此前失败、审批或清理等待。
资源门禁沿用前节，不将短时峰值描述为所有尝试均无异常。

此前客户端夹具权限、重复 guard、审批超时及采集错误均保留，不改写为成功。
本轮第一次公网正反例已通过，但 tcpdump 默认降权无法写入私密目录，
runner=1、恢复=0；随后读取自检也发现同样限制，尚未变更部署即停止。
最终通过父进程预先打开文件、以继承的 stdout/stdin 完成抓包读写，
保留 tcpdump 降权及私密目录权限；读写自检通过后才运行最后一轮。

归档 `.tmp-vision443-final/native443-evidence.tar.gz`，SHA256
`18332e479b2a553dedd07d6cfd665611839b92865458f9af0d1f2bd703f57fb7`，
包含五次 runner 的脱敏结果、资源样本、最终正反例、抓包统计、记账与恢复断言。
Linux 容器验证归档摘要、路径、38 份 JSON、3 个 Python 脚本语法、关键结果及脱敏通过；
不含原始抓包、私密输入或业务 URI。本机保留基线/恢复后探针、关闭报告和验证结果。
5 个远端测试目录及 13 个日志精确列明的 configure 测试备份已清理，
5 个正式 update 备份全部保留；本机固定转发、客户端容器/卷及临时 URI 已清。
UTC `09:12:19` 离场：三服务 healthy、两 timer active/enabled、无 failed unit，
load1 `0.17`、MemAvailable 约 452 MiB、SwapFree 约 493 MiB。

本轮只补受管 bridge 的正式公网链路，不重复 6 点恢复、本机 24 场景、daily 或 full，
不改变生产代码与支持矩阵。其它原生 Reality 拓扑/重启、XHTTP 原生矩阵、
正式 ACME issue/renew 消费失败全链及 fresh 公网挑战、透明启用重启矩阵、
原生 arm64、公网 IPv6、新主机灾备、WARP 实账号及自然续期仍未完成。

### 2026-10-22 原生 Vision/XHTTP 拓扑收口与远端清理

在同一台 Debian 13 amd64 测试 VPS、正式 3.41.4 bundle 上完成本批剩余的
Vision/XHTTP 原生故障恢复收口；透明代理全程关闭。Vision host/loopback 的
启停三故障点和两次互切共 14 点已通过；XHTTP bridge、host-gateway、
host-loopback 的启停三故障点和两次互切共 20 点已通过。每个通过点均验证
正确/错误 UUID、严格 HTTPS 200、XHTTP HTTP/2、Host/mode、上传下载记账、
候选/部署锁清理、原规格材料和三项业务健康。

XHTTP bridge 早期 3 点触发资源看门狗，随后完成恢复；另有历史暂存残留和
控制器中断，均保留原始失败证据并在恢复后继续。最终 D 阶段剩余 bridge 1
点加 host 6 点为 7 点，E 阶段 loopback 6 点加 host/loopback 互切 2 点为
8 点，均为 `runner_exit=0`、`official_restore=0`、`outer_restore=0`、
`verify=0`，guard 最终 `completed=true/triggered=false`。

脱敏归档 `.tmp-native-topologies-20261022/native-topologies-final.tar.gz`
共 264 个文件，SHA256
`58b22a95a73111a059acfd6794d5d5438a937cab13fe57c832851c8bec19e5de`。
Docker Linux 工具容器内的 `verify-archive.py` 通过，统计 34 个唯一点
（Vision 14、XHTTP 20），不含私密材料。早期三个看门狗归档的空
`outer-state/verify.json` 不作为结果读取，门禁改用同阶段 `restore.json`
及 runner/guard 恢复字段校验，没有补造测试输出。

用户已授权精确清理测试 VPS。脚本在删除前复核三业务容器 healthy、renewal/
traffic timer active/enabled、透明关闭、正式协议和无部署锁；随后删除本轮
8 个远端工作目录及 83 个新增 `configure.*` 备份，保留
`update.LnP9nE`、`update.dPN15p`、`update.pDAJCS`、`update.s3aMp6`、
`update.t5vJXt` 五个正式备份。远端清理返回 0。

本批没有把 XHTTP 隔离 CLI 24 点、`packet-up`、`stream-up`、独立下行、
整机重启、正式公网 ACME 消费失败全链、fresh 挑战、透明启用重启矩阵、
原生 arm64、IPv6、新主机灾备、WARP 实账号或自然续期写成已完成；整体计划
仍未完成。

### 2026-10-23 XHTTP 隔离恢复与正式公网双模式

本批补齐原生拓扑收口后明确保留的两个缺口。新增独立 selector
`docker-reality-stream-xhttp-cli-real`，共用既有 CLI 矩阵并显式选择 XHTTP；
Vision 入口显式选择 Vision。权限白名单按完整名称匹配，两个准确名称
及两个近似名称的 4 项 Linux 容器检查通过；新增定向
`-Scope reality-stream`，不重复完整队列测试。分派合同 `1.951` 秒通过，
Bash 语法、ShellCheck error 和 PowerShell parser 通过。

隔离 `linux/amd64`、Jobs 2 的当前源码快照完成 24/24 恢复点：
三拓扑启停三故障点及六次定向互切，12 个真实 unhealthy 退出 `14`、
12 个 TERM 退出 `143`。每点核对原规格、权限、调度、分享 URI、双协议
正确/错误账号、严格网站 TLS 和累计；入口耗时 `1019979 ms`，未命中缓存。
证据为 `.tmp-regression-docker-084cdabf0a7b4eb49bbc318edd077395/`。

正式 Debian 13 amd64 VPS、3.41.4 bundle 源
`e2a2248953af907bea33c1b881788e0912a38b97`，通过正式 CLI 的
`compatible/stream` 预设，在 bridge、host-gateway、host-loopback 逐一验证
`packet-up/stream-up`，共 6 个唯一公网点。客户端仅通过回环固定转发连接
唯一测试 VPS，校验正确/错误 UUID、严格网站 HTTPS 200、精确 HTTP/2、
Host `pgxn.org`、准确 mode 和双向累计；两个宿主网站拓扑还核对独立正文。
原 WS 基线与最终恢复后的公网正反例均通过。

首轮在配置成功后立即断言无锁，遇到已启动的流量调度竞争而失败；
正式/外层恢复与 verify 全为 `0`，恢复后公网 WS 通过。首轮原始失败归档
保留在 `attempt-1/`；沿用现有故障矩阵 30 秒等锁门槛重跑后六点通过，
未放宽 guard。最终 `runner_exit=0`、`official_restore=0`、
`outer_restore=0`、`verify=0`，guard `completed=true/triggered=false`。
离场初查的 traffic 失败来自配置切换 TERM（143）；原始日志保留，
恢复后定时采集及主动启动均成功，不以清除失败状态代替验证。

成功归档 `.tmp-native-xhttp-modes-20261022/native-xhttp-modes-evidence.tar.gz`
SHA256 为 `54fca8e695aeb00480ef0ca1b1920c4b5d357cb13ce99fba02eb4382751ef267`。
隔离 Linux 容器运行 `verify-evidence.py`，同时核对 24 个唯一恢复点、
12×14/12×143、4 项权限检查、首轮真实失败、正式六点及完整恢复通过。
远端两轮目录和各 CLI 日志明确点名的 12 个 `configure.*` 备份已清理，
保留五个正式 `update.*` 备份；清理前再次 verify，确认原 WS、三业务健康、
两 timer active/enabled、无候选/编辑暂存、无部署锁和透明关闭。

本批只证明准确模式及上述业务，不证明大上传分段、性能、独立下行或重启。
正式公网 ACME 消费失败全链、fresh 挑战、透明启用重启矩阵、原生 arm64、
IPv6、新主机灾备、WARP 实账号及自然续期仍未完成；整体计划仍未完成。

### 2026-10-23 同 handler 独立下行公网点

正式 3.41.4 CLI 在 Docker bridge 拓扑保留原 WS/网站 `443`，创建 XHTTP
上行 `2444`，通过 `edit --port-alias` 将下行 `2443` 指向同一 Xray 容器内
`2444` handler，再通过 `edit --xhttp-download-settings` 登记完整 Reality
对象。服务端 deployment 及实际 PortBindings 均确认两个公开端口归同
handler；客户端完整核对正式 URI 的字段，只映射固定 TCP 通道的地址和端口。

严格公网 HTTPS 200 正例通过，HTTP/2、Host `pgxn.org` 和上行 `packet-up`
日志准确；同一客户端 PID 独占的 ESTABLISHED socket 同时观察到映射端口
`12444/12443`。分别使用新进程测试错 UUID、仅改下行 SID、仅改下行端口
到原 WS `443`，三项完整业务均拒绝；每项仅一个 outbound、无回退出口，
客户端仍存活且上行设置未变。原 WS 正反例和网站严格 TLS 同时通过，
三次探针的双向累计增长且无账号回退。

`runner_exit=0`、`official_restore=0`、`outer_restore=0`、`verify=0`，
guard `completed=true/triggered=false`，恢复后公网 WS 通过。隔离 Linux
容器的纯 selfcheck、6 个 Python AST、Bash 语法、ShellCheck error 和最终
`verify-evidence.py` 门禁通过。脱敏归档
`.tmp-native-xhttp-down-20261023/native-xhttp-down-evidence.tar.gz` 的 SHA256：
`70a4a9e954917eded5717c103f621902ae80acdab66c7c4f06ce1ee382d94055`。

远端目录与 baseline/alias/download-edit/restore-official 四条 CLI 日志
明确点名的四份配置备份已精确清理，五个正式 update 备份保留；再次核对
原材料/权限、三业务 healthy、两 timer active/enabled、透明关闭和无暂存。
离场 traffic 主动采集成功、无 failed unit，load1 `0.42`、MemAvailable
`453964 KiB`、SwapFree `504648 KiB`。本地 URI、二进制及测试容器已清理。

此点只关闭同 handler、同 Reality 身份的独立下行端点子范围；
公网独立 Reality 身份、TLS/h3/CDN、其它下行拓扑、整机重启及性能未覆盖，
其余缺口按计划继续保留。

### 2026-10-23 Vision/XHTTP 六点实际重启

正式 3.41.4 bundle、源 `e2a2248953af907bea33c1b881788e0912a38b97`，
在同一 Debian 13 amd64 VPS 执行 Vision/XHTTP × host-gateway、受管 bridge、
host-loopback 六点整机重启，XHTTP 固定 `packet-up`，透明全程关闭。
每点前后均验证双协议账号正反例、严格网站 HTTPS、精确 HTTP/2/Host/mode
及双向累计；bridge 同时验证原 WS，宿主网站拓扑核对独立正文。

六个新 boot ID 和 12 个前后公网探针均通过。每点核对原容器 ID 不变、
StartedAt 变化及相同重启策略，等待容器自然健康，不调用 up/restart 修复后
冒充成功；材料字节/权限与续期、traffic timer 保持。持久 guard、网站和
worker 自动跨 boot 运行，保护证据绑定当前 boot 的真实样本；八分钟断联
恢复期限在原材料、调度及恢复后公网 WS 全部通过前保持。
host-loopback 指 nginx-stream 使用 host 网络，Xray 仍为 bridge，
选中 `443` 映射至 `127.0.0.1:15443`，未将 Xray 改成 host 网络。

首轮 bridge 两点通过后，Vision/host-gateway 重启前未选中 XHTTP:2444
业务 TLS 超时，未执行第三次重启。正式/外层恢复与 verify 均为 `0`，
恢复后公网 WS 通过；根因未确定，不能凭第二轮通过宣称修复。
首轮原归档保留在 `attempt-1/native-reality-reboot-evidence.tar.gz`，SHA256
`4676572f8afae5233e565b7127f1791cd156dfe4bf7fcfa1c08993a01170c325`。
第二轮增加脱敏实际 Compose/PortBindings 和异常服务端私密诊断，
改按 host→bridge→loopback 优先复测失败点，未放宽超时、资源门槛或增加重试。
打包前本机旧 payload 冲突在部署前退出，核对路径后精确清旧 payload；
原控制器错误保留，不计入 VPS 成功证据。

第二轮 `runner_exit=0`、`official_restore=0`、`outer_restore=0`、`verify=0`，
guard `completed=true/triggered=false`，原 WS 恢复后公网正反例通过。
独立 Linux 容器 `verify-evidence.py` 核对六 boot、12 探针、原容器、
材料/调度、跨 boot 保护及真实端口映射通过。成功脱敏归档
`.tmp-native-reality-reboot-20261023/native-reality-reboot-evidence.tar.gz` SHA256：
`1f0f838c999f1cbb3515096ddde0a265779fe61622bfe0f0cd0b88f59728c214`。

离场初查出现 traffic 失败，journal 保留配置切换期间 TERM/143；
随后定时采集及清理前主动采集均成功。六个 owned unit、七份 CLI 日志精确
点名的 `configure.*` 备份和远端目录已删除，五份正式 update 备份保留。
清理首次在 unit 已卸载后 reset-failed 返回 not-loaded，尚未删除目录或
备份；调整为卸载前 reset 并验证六项接续/拒绝自检后完成，不吞掉原错误。
本机 URI、xray 二进制、payload、重复失败日志及客户端/验证容器已清，
首轮失败归档与成功归档摘要均未改变。

最终三业务 healthy、两 timer active/enabled、无 failed unit，严格 TLS
HTTPS 200、透明关闭，load1 `0.00`、MemAvailable `532572 KiB`、
SwapFree `519612 KiB`；证书仍至 2027-01-15，未发新 CA 请求。
本批未改生产代码，未重复 daily/full。公网独立下行身份、TLS/h3/CDN、
正式 ACME 消费失败全链/fresh、透明启用重启、原生 arm64、IPv6、
新主机灾备、WARP 实账号及自然续期继续未完成；整体计划仍未完成。

### 2026-10-23 原 XHTTP 失败前序定向补验

在同一正式 3.41.4 VPS 按原失败前序执行 bridge Vision 实际重启、bridge
XHTTP 实际重启，再在同一 boot 切换至 host-gateway Vision:443、
XHTTP:2444，仅补原失败 pre-public，不执行第三次重启。
两次真实 boot、原容器自然启动及五个公网矩阵探针均通过；核对脱敏实际
Compose/inspect/PortBindings、材料/权限、timer、跨 boot guard/deadline，
原 WS 基线及恢复后正反例、网站严格 HTTPS 均通过。

`runner_exit=0`、`official_restore=0`、`outer_restore=0`、`verify=0`，
guard `completed=true/triggered=false`。独立 Linux 归档门禁通过；
`.tmp-native-xhttp-transition-20261023/native-xhttp-transition-evidence.tar.gz`
SHA256 为 `25a7cb2ffee943e2d32edbd0647069dc5a4b002e25d48f215d6f2751c272e1a1`。
六个测试 unit、四份 CLI 精确点名的配置备份及远端工作目录已清理，
五份正式 update 备份保留；本机 URI、二进制、payload 和转发输入已清。
清理时 unit 卸载后 reset-failed 的接续错误原样保留；限定仅 reset failed
unit，六案自检通过后清理成功。

本轮未复现原 XHTTP 超时。旧失败缺当时真实映射与服务端日志，仍不足以
区分公网迟滞和切换残留，不将通过写为根因修复；原失败归档继续保留。

### 2026-10-23 正式 webroot issue 消费失败全链

在同一 Debian 13 amd64、正式 3.41.4 bundle 上调用生产 CLI：
`acme issue --webroot` 单次申请，没有操作者重试。先保留缓存 CA 账户、
移走本域材料，确保新 key；新证书 DER、序列号与 issuer 已独立捕获，
系统 CA 信任链及域名校验通过。新证书 SHA256：
`09e5dceabf34ae98705d20ad06b8b60e163e09061256e5460c1e984ec9a5e27a`，
issuer 为 `Let's Encrypt YE1`，序列号 `0605E3C5CD24172A8129F48CDFFB4A8C94ED`。

受管 `default.conf` 全程不改。先用独立旧 key pin 验证 Nginx baseline，
随后移除该配置；仅本轮 PATH 的 Docker 参数转发器在首次真实消费者
`nginx -t` 前确认新 TLS 与 ACME 证书相同、新 key 不同旧 key、候选 marker
已提交到 ACME 树，才一次性重建 pin。真实 Nginx 报 `key values mismatch`，
CLI 返回 `15` 并自动恢复旧证书和 ACME 状态，未用模拟退出码替代消费失败。

| 核对项 | 实际结果 |
| --- | --- |
| 新证书与注入时点 | 新 DER、受信任链和域名通过；新 TLS/ACME 及 marker 提交后注入 |
| 自动回滚 | TLS/完整 ACME 字节、mode、uid、gid、链接数等于失败前快照 |
| 业务与累计 | 旧在线证书保持；三业务 healthy；账户累计不回退 |
| 完整恢复 | 正式恢复、outer restore、verify 均 `0`；timer active/enabled |
| 独立公网复验 | 原 WS 正 UUID 严格 HTTPS 200、错 UUID 拒绝；网站严格 TLS/200 |
| 保护 | guard completed=true/triggered=false；透明全程关闭 |

44 个两秒资源样本最低 MemAvailable `444780 KiB`、SwapFree `510944 KiB`，
最高 load1 `4.29`。本轮 guard 沿用六点重启的持续负载判断：连续三样本
MemAvailable 低于 150 MiB、SwapFree 低于 96 MiB、load1 高于 8，或
load1 高于 4 且 load5 高于 3 时恢复；成功还须等待 guard 最终结束且无
stop/trigger 标记，不能以 runner 正常退出掩盖恢复末尾触发。

首轮将注入写入受管配置，被 webroot 一致性门禁正确拒绝，CLI `15`，
未发 CA 请求；旧 guard 仅看 load1，`4.49/4.49/4.21` 三样本触发。
最低 MemAvailable `461884 KiB`、SwapFree `511456 KiB`，不能称内存耗尽。
首轮原始失败和私密诊断独立保留在 `attempt-1/`，公开归档 SHA256：
`1e774cdbdee943538bb04b242f0630abcc37d0f7c961f6abf246cc0d1374862e`。
恢复后两次本机探针启动失败分别暴露 `-d`、`-p` 被 PowerShell advanced
包装函数解析为通用参数；统一改为普通函数原样透传，两个参数自检及
实际公网复验通过。原启动失败另留证，未修改 VPS 或追加 CA 请求。

Bash 语法、ShellCheck error、离线脚本自检、supervisor 四分支与 guard
自检通过；独立 Linux 归档门禁核对真实新证书、注入、CLI 15、完整恢复、
公网结果、资源样本和脱敏通过。成功公开归档
`.tmp-native-acme-fullchain-20261023/native-acme-fullchain-evidence.tar.gz`
SHA256：`a874327b70a1ad9c3320843bd9fe2781c0b593492abd5863ffafd2e24c9cc533`。
私密日志单独取回，未进入公开归档。两轮远端工作目录及本轮三份、首轮
两份按材料关系和完整树 SHA 认领的备份已精确清理，五份正式 update
备份保留；本机 URI、xray、payload、转发输入及测试容器已清理。

离场三业务 healthy、两 timer active/enabled、主动 traffic 成功、
无 failed unit；严格 HTTPS `200/verify=0`、透明关闭，load1 `0.04`、
MemAvailable `496984 KiB`、SwapFree `510944 KiB`。旧证书仍至
2027-01-15，新签发证书只进入失败候选，未成为在线证书。
当时关闭的为正式 webroot issue 与 standalone auto-renew 消费失败全链。
后续发现 standalone 的公网文件沿用前案、远端清理未完成；已补齐本案独立
证明并精确清理，修正结果及 ALPN 接续如下；整体计划继续未完成。

### 2026-10-23 正式 standalone auto-renew 消费失败全链

在同一 Debian 13 amd64、正式 3.41.4 bundle 上调用生产 CLI：
`acme auto-renew` 单次执行，provider 为现有 `standalone` 登记。测试仅在
快照完成后把本轮候选输入强制到期（`Le_NextRenewTime=1`、新域名 key、
`NO_ARI=1`），未通过正式 CLI 环境变量注入 ACME 参数，也未自动重试 CA。
正式 CLI 取得新的 Let's Encrypt 候选证书并通过系统信任链与域名校验，
新证书未上线前被真实 Nginx 消费校验拒绝。

| 核对项 | 实际结果 |
| --- | --- |
| 续期动作 | `auto-renew`，provider `standalone`，正式 CLI 调用 1 次 |
| 消费失败 | 真实 `key values mismatch`，CLI 返回 `15` |
| 自动回滚 | TLS/完整 ACME 字节、mode、uid、gid、链接数恢复到失败前；旧在线证书保持 |
| 业务与调度 | 三业务 healthy；累计不回退；renewal/traffic timer active/enabled |
| 外层保护 | runner、outer restore、verify 均 `0`；resource guard `completed=true/triggered=false` |
| 透明代理 | 始终关闭 |

最终公开归档 `.tmp-native-acme-fullchain-20261023/standalone-renew/native-acme-fullchain-evidence.tar.gz`
SHA256：`61237019a4e86a22ab4f8425e5d23e87335cdf35ec539755c29c70ff14af92c0`；
独立 Linux 门禁以 `action=auto-renew/provider=standalone` 复核通过。
原始归档 `6ede108e…` 保留为 `original-run-evidence.tar.gz`。新公网结果携带
本案 nonce、开始/结束时间、响应与证书 SHA256，旧 nonce 拒绝检查通过；
两份认领备份 `tls.9oksEJ`、`tls.gakNJ8` 与远端目录已补清，私密日志已取回。
本轮资源样本 23 个，最低 MemAvailable `449944 KiB`、SwapFree `510688 KiB`，
最高 load1 `3.39`。远端工作目录与认领备份已精确清理，五份正式 update
备份保留；透明代理保持关闭。

本节只关闭正式 standalone auto-renew 消费失败回滚子项，不外推 ALPN、
fresh 公网挑战、新证书在线生效再回退、自然续期或其它环境；整体计划继续未完成。

### 2026-10-23 正式 ALPN issue 与同张证书在线往返

正式 3.41.4 的 `acme issue --alpn` 单次取得新受信任证书，提交后注入
旧 key pin，真实 Nginx `key values mismatch`，CLI `15` 自动回滚。
随后单独正式 `tls install` 将同张候选上线，独立公网确认新指纹
`f72de8fd45226c9df87e79381f5eaab998e134e44ee32cf108ee603a2ddb668c`，
再恢复原指纹 `e30e977c8a39eaf92f3289a4b315dd6360b16a34529829900fd6a5b8dce191d8`。
在线及恢复探针分别绑定新 nonce、时间和内容摘要，未增加 CA 请求。

正式/外层恢复、原材料与权限、业务、累计、timer 均通过，guard 未触发。
40 个样本最低 MemAvailable `423176 KiB`、SwapFree `510688 KiB`，
最高 load1 `2.73`。`alpn-issue/native-acme-fullchain-evidence.tar.gz` SHA256：
`7733b37535d97b20a227f364493a3dbf7b2f046cda618cdf3be4560f16a87c69`。
独立 Linux 门禁及只读复核通过；目录和三份认领备份已清理。该结果不证明
fresh CA challenge 或自然续期。

### 2026-10-23 ALPN auto-renew 失败、恢复及源码修复

快照后仅在测试账户将 `Le_Webroot='no'` 精确改为 `'alpn'`，正式启用
ALPN 登记后强制到期。Nginx 已暂停，但 Python 入口卡在 `sys.stdin.read()`，
尚未 exec acme.sh；Docker CLI stdin 为 `/dev/null`，容器 stdin 为管道，
等待点 `pipe_read`，`OpenStdin/StdinOnce=true`。底层 EOF 原因尚未确认。

停止测试 unit 时监督器恢复子进程也收到 TERM；原 runner
`runner_exit=-1/outer_restore=-15/verify=-1` 保留。独立 SSH 另行执行既有
outer restore/verify，核对材料与权限、三业务、timer 和透明关闭，再以新
nonce 完成公网 WS 正反例及严格 TLS 网站 `200`。独立恢复门禁明确输出
`acceptance_passed=false/recovery_verified=true`。328 个样本最低
MemAvailable `414008 KiB`、SwapFree `510688 KiB`、最高 load1 `2.54`。
`alpn-auto-renew/native-acme-fullchain-evidence.tar.gz` SHA256：
`d4dafa6bbf2b8d5b07b353e90bbe8da1fc14f4e8bbc63b563354cde10ab3211b`。
私密日志分离保留；本轮目录及 `tls.f7jZ6L` 已清，五份正式 update 备份保留。

`dockerAcmeRun` 改为仅 DNS 凭据非空时传 `-i`，无凭据关闭容器 stdin；
凭据仍经 stdin，不进入 Docker 参数或环境。修复前新断言失败，修复后
`docker-tls-focused -Jobs 2` 的 TLS 与 renewal 均通过，总耗时 `39.436` 秒，
证据 `.tmp-regression-docker-8c94b91549b242f092ccbff583e9d43a/`。
同 VPS 断网容器的空输入/合成凭据检查均进入 acme.sh，未申请证书或暂停业务；
它不替代修复进入可信发布包后的正式 ALPN auto-renew 补验。
未重复 daily/full；透明继续关闭，其余环境缺口及整体计划保持未完成。

### 2026-10-23 3.41.5 验签升级与 ALPN auto-renew 补验

Release `39946059875` 的 32/32 作业成功，正式源
`a1f623557158aea59e12402369fc00c5418080aa` 已通过生产 Cosign 验签及
`assess/update/validate` 升级到 Debian 13 amd64 VPS。控制包 SHA256：
`1f75d64aaa7d419594a6dcfb8d2740d758237d17f4e2799adbc09c64a9c46a4c`，
manifest 为 `7e1d56e6b97db26f73ca33a013daa31b2c1d973acaea58cbaaaec3a8537b0d80`，
Sigstore 为 `c26083369455292160088d9b3834e9e358f46b4fa922cfc56b73123f4d4f56f6`。
升级后原业务规格、证书/ACME/续期/订阅材料及权限保持，三业务 healthy，
调度保持，独立新 nonce 公网 WS 正反例、严格 TLS 网站 200 通过。
`upgrade-3415/native-upgrade-evidence.tar.gz` SHA256：
`90f9602531f10702b71f4fb2c76da3b06a3dabe9168b8ec96192f8dfa925fa0b`。

快照后构造测试账户的 ALPN 登记并强制到期，正式 `acme auto-renew` 单次取得
新可信 Let's Encrypt 候选，真实 Nginx key mismatch 导致 CLI `15`，
TLS/完整 ACME 字节及权限自动回滚。正式恢复、outer restore、verify 均为 `0`，
资源 guard 完成且未触发；24 个样本最低 MemAvailable `393880 KiB`、
SwapFree `507432 KiB`，最高 load1 `2.79`。新 nonce 公网 WS 正反例、
原证书指纹及严格 TLS 网站通过；不称自然续期。
`alpn-auto-renew-3415/native-acme-fullchain-evidence.tar.gz` SHA256：
`31269a57dc095268a20ea5db020dbffa79c8be05d594295a093018c9ae35f404`。
独立 Linux 门禁和只读复核通过。早期 `final-state.log` 的 traffic failed 保留；
后续清理前实际启动并核对 `Result=success`，不抹掉旧错误。

### 2026-10-23 fresh 挑战与零 CA 在线接续

本批 fresh 正式申请共两次，均隔离原账户及域名材料，向原 Let's Encrypt
directory 新建账户。两次日志均包含注册、`Verifying`、真实 TLS server、
`Success` 和 `Cert success`，不是缓存授权或本地 CA。
第一轮夹具把 `Standalone alpn mode` 的日志顺序写反，且 fresh 环境误拒绝
restore，原 runner 保留 `1/2/-1`；另行恢复及新 nonce 公网复验通过，
guard 未正常完成的事实保留。公开归档 SHA256：
`9616e9f34efe5eebf9b7676c191bae059ad4cd44a6910fbca5d5838b5c63ffcd`。

修正顺序及恢复入口后，第二轮取得新可信候选，真实消费者 mismatch、CLI `15`
及回滚均执行。夹具新建的 `account.conf` 为 root 属主，正式权限归一化使
uid/gid 从 `0` 变为 `10001`，字节、`0600` 和链接数不变；原始清单已补入
接续归档，可独立重算唯一差异。原 runner 保持 `1/0/0`，result 保持失败，
不按完整 fresh 验收通过处理。原申请归档 SHA256：
`e21825f4e0841dc562a0b9fe3448e27508e60f3a67604ecec80ddc1c7aa2f021`。
夹具随后保留原账户属主，离线元数据检查通过；没有第三次 CA 申请。

改用已捕获的同张证书，通过正式 `tls install` 单独完成在线往返，
本阶段额外 CA 请求为 `0`。新证书和恢复原证书的公网探针各带新 nonce、
时间、boot ID 及内容摘要，WS 正反例和网站严格 TLS/200 均通过；
独立 online runner、outer restore、verify 均为 `0`，原失败 runner 未改写。
guard 完成未触发；接续 30 个资源样本最低 MemAvailable `374152 KiB`、
SwapFree `507688 KiB`，最高 load1 `1.49`。接续公开归档位于
`alpn-issue-3415-fresh-r2-online/native-acme-fullchain-evidence.tar.gz`，SHA256：
`d6e098e9a048d86a5e2667b48ede2241c0f1cdc4201b05921acc02cdf2a40083`。

本节相对路径均在 `.tmp-native-acme-fullchain-20261023/`；公私归档分离。
远端升级暂存、两轮申请及接续目录、各轮精确认领的 TLS 备份已清理，
六份正式 update 回滚点保留，三业务和调度恢复、主动 traffic 成功。
本机 URI、转发输入、xray 二进制和客户端容器已清；验收源码与归档保留。
Bash/ShellCheck、离线夹具、supervisor 六分支及后代进程组清理检查通过，
未重复 daily/full。单次 fresh 完整链、透明启用重启、原生 arm64、IPv6、
新主机灾备、WARP 实账号、独立 Reality/TLS/h3 和自然续期仍待验，
原 XHTTP 超时未定根因，整体计划继续未完成。

### 2026-10-24 单次 fresh ALPN 完整链

在正式 3.41.5 上以隔离后的空账户执行一次 `acme issue --alpn`，没有操作者重试。
修正后的夹具保留原账户 `10001:10001/0600` 属主及权限，真实日志按序出现
新建账户、注册、`Verifying`、TLS server、`Success` 和签发成功。
新 Let's Encrypt 候选通过系统信任链及域名校验；仅在新 TLS/ACME 及 marker
提交后注入旧 key pin，真实 Nginx mismatch、CLI `15` 后完整回滚，
TLS/全部 ACME 字节、mode、uid、gid 和链接数严格相等。

同一 runner 随后经正式 `tls install` 上线同张候选，独立公网验证新指纹，
再正式恢复旧证书和原账户。新在线及恢复阶段分别绑定本轮 nonce、
时间、boot ID、响应与证书摘要；WS 正向严格 TLS/200、错误 UUID 拒绝、
网站严格 TLS/200 均通过。runner、正式恢复、outer restore、verify 全为 `0`，
guard 完成未触发；46 个样本最低 MemAvailable `385580 KiB`、
SwapFree `507432 KiB`，最高 load1 `3.55`。

fresh 归档门禁现在必须包含在线往返文件、在线/完成阶段及新证书公网 receipt；
使用已有归档的合成副本验证一个正例、缺往返文件/阶段/receipt 三个拒绝反例，
CA 请求为 `0`。Bash/ShellCheck、离线夹具、supervisor 六分支、进程组和 guard
自检均通过，未重复 daily/full。

证据在 `.tmp-native-acme-fullchain-20261023/alpn-issue-3415-fresh-20261024/`，
公开归档 `native-acme-fullchain-evidence.tar.gz` SHA256：
`09fd285cbdeb557ba7bddaec10fd7d538d6b2ecad4c91bcd152a9894c86a0339`。
远端目录及 `tls.0L0xQ0`、`tls.6atT5Z`、`tls.5QNFQJ` 已按归属清理，
六份正式 update 回滚点保留；本机私密输入、二进制和探针容器已清，
源码与公私分离归档保留。三业务及调度恢复、主动 traffic 成功，透明始终关闭。
本节关闭单次 fresh ALPN 完整链子项，不代表自然续期、其它 CA/provider
或其余原生环境矩阵通过，整体计划继续未完成。

### 2026-10-24 同 handler 独立下行完整公网接续矩阵

在正式 `3.41.5`、同一 Debian 13 amd64 VPS 上接续前一轮独立下行验收。
首轮已通过的 Reality 四模式与 h2 `auto` 保留为 `5/12` 前缀证据；在
h2 `stream-one/packet-up/stream-up` 及 h3 `auto/stream-one/packet-up/stream-up`
七个剩余点上重新使用正式 CLI 和同一 XHTTP handler。接续轮复用首轮已验签
资产、基线和上行后端配置摘要，前置下行 Reality 身份重新生成且与上行身份
严格不同；透明代理始终关闭。

接续矩阵七点均通过，原 WS 基线和恢复后 WS 正反例、严格 TLS、网站 `200`、
双向 traffic 增长均通过；`runner_exit=0`、正式恢复 `0`、`outer_restore=0`、
`verify=0`。`resource-guard` `completed=true/triggered=false`，接续公开归档
`native-evidence.tar.gz` SHA256：
`be415a9939847a67e668418fc8a18f70a5c35c3a299529431c13f7d337ec902a`；
私密归档 SHA256：
`7db58df094b3cfcbb5fce43c6f69255632a2bcc93b49b811199506576492baf9`。
接续样本最低 MemAvailable `355808 KiB`、最低 SwapFree `489368 KiB`，
最高 load1 `5.36`；guard 未触发恢复。

双轮独立验证器核对首轮 `5` 点/`5` 个正业务与接续 `7` 点/`7` 个正业务，
合计 `12` 点、`12` 个正业务、`11` 个身份拒绝和 `4` 个控制项，
`coverage_complete=true`。首轮 `first_round_guard_triggered=true`、
接续 `guard_triggered=false`，因此 `single_run_passed=false`、
`all_rounds_clean=false`；这表示完整覆盖已经取得，不把两轮结果改写成
单次无故障成功。

本节只关闭同 handler、同正式后端的独立下行 h2/h3 模式覆盖；`formal_service_native_h3=false`，
不代表正式服务端原生 h3/CDN、独立 Reality/TLS 公网身份、整机重启、透明启用、
原生 arm64、IPv6、新主机灾备、WARP 实账号、自然续期或原 XHTTP 超时根因已解决。
远端目录和本机测试容器已清，公私归档分离保留，透明代理继续关闭，整体计划仍未完成。

### 2026-10-24 VLESS Encryption 正式公网矩阵

在同一 Debian 13 amd64 VPS 上使用验签正式 `3.41.5`、源 `a1f62355`，
通过正式 CLI 添加 bridge Reality Vision/XHTTP 并逐入口启停实验加密。
原 WS `443` 保留；独立 Linux 客户端使用固定 Xray `26.3.27/d2758a0` 与
Mihomo `v1.19.28`，后者直接导入原分享 URI。固定无嗅探公网通道预检确认：
原网站严格 TLS/200、对同一目标使用 `pgxn.org` SNI 返回域名失配，未改写为目标站。

原 WS、未加密双入口、仅 Vision 加密、双入口加密、关闭、原 WS 恢复六阶段通过。
`28` 个正例均为真实严格 TLS/HTTP 200 且有正文，`38` 个负例覆盖错 UUID、
旧 `none` 与两个独立加密配对交叉使用；逐阶段 nonce 唯一、客户端版本及二进制摘要
一致。未选入口 URI 不变、两配对不同、关闭后 URI 与 baseline 一致；六阶段
双向 traffic 增长、累计不回退，原网站始终严格 TLS/200。

`runner_exit=official_restore=outer_restore=verify=0`，原材料字节与权限、
timer 和三业务健康恢复，透明始终关闭。guard `completed=true/triggered=false`；
`423` 个样本最低 MemAvailable `345196 KiB`、最低 SwapFree `495572 KiB`，
最高 load1 `4.71`，样本覆盖 `846.403` 秒。独立断网 Linux 核验按完整阶段、
客户端与身份组合检查集合无缺项、无重复，并核对恢复和 guard 结果。

证据位于 `.tmp-native-vless-encryption-20261024/`。公开归档
`public-evidence.tar.gz` SHA256：
`daf38382d4fd49c5a128dfc23ab70f9974d86a5c81945bb46412d0ebe63ebe77`；
私密归档 `private-evidence.tar.gz` SHA256：
`896d5b922f89f89610ee764d89e5b700a5f2c61e8f9421abcf3823b5a5004273`。
远端按 `实际新增备份 == CLI 认领备份` 精确删除本轮六份 configure 快照和
唯一测试目录；其它备份保留。清理后业务健康、timer 一致、443 开放、
2443/2444 关闭、runner/guard 停止。`cleanup-remote.json` 复核通过；
本机容器、固定转发、二进制、输入与私密散件已清，公私归档分离保留。
该证据关闭固定版本组合的原生 amd64 公网加密启停子项，不代表其它客户端、
算法、arm64、加密启用后的整机重启、自然续期或原 XHTTP 超时根因已解决。
未重复本机 daily/full，整体计划仍未完成。

### 2026-10-24 双入口加密真实整机重启

在上述 Debian 13 amd64 VPS 上，继续使用验签正式 `3.41.5`、源 `a1f62355`，
固定 Xray `26.3.27/d2758a0` 与 Mihomo `v1.19.28`。本轮仅覆盖普通 bridge
三入口部署：原 WS `443`、分别启用加密的 Vision `2443` 与 XHTTP `2444`
（packet-up），没有 `reality_stream` 或 host 网络，透明代理始终关闭。

原 WS、双加密重启前、双加密重启后、恢复原 WS 四阶段共 `16` 个严格 TLS/200
正例、`32` 个错 UUID/旧 none/交叉配对拒绝通过；客户端摘要固定、nonce 唯一。
原 boot `46dcd1a1-48b9-4d99-b628-ba939909fc21` 实际变为
`27461660-19bc-4e08-9567-33627676ef46`。新 boot 在任何 configure/up/restart 前
观察 nginx/xray/subscription 自动启动：三个原容器 ID 保持、StartedAt 改变，
restart policy 一致。加密 URI、材料字节/权限和两个业务 timer 保持，
跨 boot 累计不回退；四阶段双向记账增长。

五个持久测试 unit 提供 worker、guard、正式恢复及八分钟断联期限；新 boot
的 guard 真实样本与恢复 timer 剩余 `475.126` 秒均核验。随后正式 configure
原 WS、outer restore/verify、最终公网 WS 全通过，
`runner_exit=official_restore=outer_restore=verify=0`，guard 未触发。
`357` 个资源样本覆盖两个 boot，最低 MemAvailable `315048 KiB`、
SwapFree `499980 KiB`，最高 load1 `4.45`。只读预检无 global IPv6 地址和默认路由，
不能据此完成公网双栈验收。

独立断网 Linux 核验通过，证据 `.tmp-native-encryption-reboot-20261024/`：
公开归档 `public-evidence.tar.gz` SHA256
`6702b69a2009808669904ccfc122e9e22bf1553c2f8d792c049ed28ee45cfbad`；
私密归档 `private-evidence.tar.gz` SHA256
`6133406703162acb3507f08446550031231c30777eb776c4240e4e719c00edf6`。
按归档摘要、unit 原内容和 CLI 日志认领精确清理本轮五个持久单元、四份 configure
备份及唯一目录，其它备份保留。清理后公网严格 TLS/200、三业务健康、两个 timer
active、透明两 unit inactive，443 开放且 2443/2444 关闭。本机客户端容器、
forward、二进制和私密散件已清，公私证据与 runner 源码分开归档保留；
`cleanup-remote.json`、`cleanup-local.json` 和 `final-clean-state.json` 复核通过。
本轮只关闭固定客户端、amd64、普通 bridge 双入口加密的真实重启子项。
其它拓扑/客户端/算法、arm64、透明启用重启、自然续期及历史 XHTTP 超时根因
不由本证据证明；整体计划仍未完成，未重复无变化的 daily/full。

### 2026-10-24 XHTTP 双模式大流完整性

正式验签 `3.41.5`、源 `a1f62355`，在同一 Debian 13 amd64 VPS 一次配置
普通 bridge packet-up `2444` 与 stream-up `2445`，保留 WS `443`。
固定 Xray `26.3.27/d2758a0`、Mihomo `v1.19.28` 直接消费正式 URI，
两模式各执行 `1 MiB`、`8 MiB`，`8` 组、`16` 个方向的长度及 SHA256 全部通过，
每方向合计 `36 MiB`。服务端和 URI 的 POST 上限均为 `16384`，
Xray 日志核对实际模式及 HTTP/2；不按载荷大小推算实际 POST 次数。
原点仅监听 Xray bridge 网络命名空间的 `127.0.0.1:18888`，
没有增加公网原点、host 网络或宿主路由。

首轮尚未启动原点就因夹具禁止所有路由规则而失败，实际唯一规则为统计 API
专用入站到 API；正式/outer 恢复和 verify 全 `0`。修正为精确允许这条规则、
继续拒绝其它业务规则后重跑。首轮 `runner_exit=1`、公私归档及原源码保留在
`attempt-1/`，其两个认领备份和远端目录已精确清理，不改写首轮结果。

成功轮原 WS 前/中/后两客户端共 `6` 个严格 TLS/200 正例与 `6` 个错 UUID
拒绝通过，各阶段双向累计增长、不回退。原点按 PID 代次停止，
`runner_exit=official_restore=outer_restore=verify=0`，
guard `completed=true/triggered=false`。独立断网 Linux 核验通过：
组合无缺项/重复，摘要唯一，客户端版本与二进制摘要固定，原材料字节/权限、
timer 和三业务健康恢复。`192` 样本覆盖 `382.755` 秒，最低 MemAvailable
`424432 KiB`、SwapFree `520932 KiB`，最高 load1 `1.85`。
单次传输耗时 `1.882–96.725` 秒，仅作运行证据，不作为性能门槛。

证据 `.tmp-native-xhttp-bulk-20261024/`：公开归档 SHA256
`7f349b009498fac558c9944c98c4efc0a1ca43a7971f013e5e8391c1a2504e85`；
私密归档 SHA256
`9ec6c360210affa8f70a65146ac05203237b9a971fdb29cf75cc2a0aa48aeeee`。
成功轮按实际新增集合与正式 CLI 日志认领精确清理两个备份及唯一远端目录；
其它备份保留。原点、本机客户端容器和转发已停止，清理后业务 healthy、
两个 timer 与原状态匹配、443 开放、2444/2445 关闭、透明两 unit inactive；
公私及源码归档分离保留，清理记录位于 `cleanup-remote.json`。
本机 `docker-xhttp-real -Jobs 2` 的既有 Reality/h2/h3 同 handler 前置增加
`12` 个 1/8 MiB 大流检查，最终入口 `29.061` 秒通过；共享探针增加正常/损坏
回显自检。负例任一业务字节即失败，单字节注入检查通过；此前一次既有小回显
握手超时保留，不将其归因于大流或通过放宽超时消除。

仅关闭固定客户端、amd64 普通 bridge、未启用 VLESS Encryption 的双模式
大流完整性子项。精确分段数、性能与长时稳定、正式服务端原生 h3/CDN、
其它环境和原历史握手超时根因仍未证明；透明保持关闭，整体计划仍未完成。

### 2026-10-24 SS 自用与服务器密钥轮换

验签正式 `3.41.5`、源 `a1f62355`，同一 Debian 13 amd64 VPS，
普通 bridge 保留原 WS `443` 并增加 sing-box SS2022 AES-128 两入口
`2446/2447`。两入口共用自用 UUID、各用不同密钥，另关联一个独立账号。
固定 Mihomo `v1.19.28` 直接通过原生 file provider 导入正式 SIP002 URI，
只替换连接 authority，保留原百分号编码认证段；只验 IPv4 TCP。

原 WS、baseline、自用轮换、服务器轮换、恢复原 WS 五阶段通过，
分别为 `1/1`、`5/2`、`5/2`、`5/3`、`1/1` 个正例/拒绝，合计 `17/9`。
正例均为真实严格 TLS/200 且有正文，拒绝覆盖错 WS UUID、仅服务器密钥、
旧自用 URI 及服务器轮换后的旧独立账号 URI。
整个 spec 精确比较，两个正式轮换命令分别只放行选中入口一个密钥字段；
其它入口、独立用户密钥、UUID、token、分享组及额度保持。
三个 SS 阶段检查 Xray/sing-box 真实非 host 网络和唯一 IPv4 TCP 映射；
各阶段双向累计增长、全部账号累计不回退。

`runner_exit=official_restore=outer_restore=verify=0`，原材料字节/权限、
两个 timer 与三业务健康恢复；guard `completed=true/triggered=false`。
独立断网 Linux 核验按精确阶段与身份集合检查无重复、缺项，并关联新旧 URI
摘要、冻结字段和固定客户端二进制。`230` 样本覆盖 `460.042` 秒，
最低 MemAvailable `360256 KiB`、SwapFree `492444 KiB`，最高 load1 `4.34`。

证据 `.tmp-native-ss-rotation-20261024/`：公开归档 SHA256
`29777353997849c1b8dabcadb5bebdc5e9e249fa5fc60802988b6fef1d95f00e`；
私密归档 SHA256
`4a9f2107bcb536720e0c5d00f76eb4bd9580adb1201d55240554cfcd7bb6dfa7`；
执行源码归档 SHA256
`d0cfd3ef69dd717505aafdf1a0a20556ff615d35555a3f3f14322b0d521f320c`。
`cleanup-remote.json` 确认实际新增集合与 CLI 认领精确匹配后，删除四份本轮
备份及唯一远端目录，其它备份保留。清理后业务 healthy、两个 timer 匹配，
`443` 开放、`2446/2447` 关闭，runner/guard 停止、透明两 unit inactive。
本机客户端容器、转发、二进制和私密散件已清，公私、客户端及执行源码分开归档。

只关闭固定 Mihomo、amd64 普通 bridge 的两类 SS 轮换公网 IPv4 TCP 子项，
不代表 UDP、IPv6、重启、旧连接排空、其它算法/客户端、宿主集成或完整管理。
透明继续关闭，整体计划仍未完成；没有生产代码变化，不重复本机 daily/full。

### 2026-10-24 TLS 客户端边界与 UDP 部分证据

TLS 两轮失败均已恢复并精确清理，保留在
`.tmp-native-tls-combined-20261024/attempt-1/` 与 `attempt-2/`。
第二轮主/组订阅下载、15/7 节点导入及协议 22 原生业务通过，随后协议 23 失败中止。
固定 Mihomo `v1.19.28` 的 VMess HTTPUpgrade 原生 URI 导入首包非 HTTP；
显式 `network=ws` 与 `ws-opts.v2ray-http-upgrade=true` 的手工对照发出正确 GET。
不修改正式 URI 迁就客户端，也不把手工对照写成原生 URI 矩阵通过。
诊断归档位于 `httpupgrade-diagnostic/`，公开归档 SHA256 为
`154ab8ba27fa1b3d69483910029dd4bd85c677a57ae698eb6b520e8ae6666950`。

UDP 证据位于 `.tmp-native-udp-combined-20261024/`。首轮 SSH255 中断，
取得 18 正例、14 拒绝，34 个有效 UDP nonce 各到达一次、10 个拒绝 nonce 零到达；
迟获的原客户端请求单独保留，不覆盖当时输入链不足的独验结论。
第二轮原 WS、六 UDP 入口基线、默认分享和替换别名阶段通过；
删除别名阶段前五个 UDP 正例通过，TUIC 正例约 12 秒超时，业务原点零到达，
其后两项删除端口拒绝、原 WS 正反例未执行。恢复原 WS 的独立阶段通过。

第二轮实际独验共 31 正例、16 拒绝，48 个有效 nonce 各到达一次、
11 个拒绝 nonce 零到达，完整输入链成立；五类篡改拒绝实测通过。
`runner_exit=1`、正式/outer/verify 为 `0`，不产生矩阵成功结论；
guard 无触发记录，也无完成记录。最低 MemAvailable `355928 KiB`、
SwapFree `483980 KiB`，最高 load1 `5.10`，没有连续三个样本越界。
五份 CLI 认领备份及唯一远端目录已精确清理，三服务、timer、443 恢复，
`2460–2467` TCP/UDP 关闭，透明关闭。第二轮公开/私密归档 SHA256 分别为
`fcdbf4f1dde0091e87b3b4dca7b53755f8c7a236168539b06935bb39e4bae532`、
`26d2f4a354173309fb992d080b22927d999129046b628505930ccb45b9bf5ec9`。
TUIC 当前 URI 与上一成功阶段一致；现有材料不足以确定公网 QUIC、丢包或服务端根因。
后续只定向补未完成项，不重复整个 UDP 矩阵，不用后续通过解释旧超时。

### 2026-10-24 站点与 fallback ALPN 原生收口

验签正式 `3.41.5`、源 `a1f62355`，同一 Debian 13 amd64 VPS，
普通 bridge、公网 IPv4 TCP，固定 Mihomo `v1.19.28` 原生 file provider。
保留原 WS `443`，增加 Xray `27/29` 两入口 `2455/2456`、一个独立账号和分享组。
两入口分别执行逆序、仅 HTTP/1.1、推荐顺序，再切换 notes/photos/docs 三主题
及 302；notes 使用含中文、引号、尖括号和反斜杠的站名。
13 阶段共 57 正例、35 拒绝，22 次主/组严格 HTTPS 下载与 22 次错 token 404、
230 次资源 200、45 次资源 404、5 次 302、88 项 ALPN、35 次错 SNI 均通过。

独立断网 Linux 核验不导入运行器或客户端，从固定正式 bundle 重算主题资源正文，
检查认证、ALPN 次序、订阅内容、特殊字符转义、Location、原材料字节/权限和调度；
13 份原客户端请求与远端逐阶段请求逐项相等。
`runner_exit=official_restore=outer_restore=verify=0`，
guard `completed=true/triggered=false`，最低 MemAvailable `378528 KiB`、
最高 load1 `4.02`。执行时间 `08:38:07–09:06:47 UTC`，共 `28m40s`。

证据 `.tmp-native-sites-alpn-20261024/`：
公开归档 SHA256 `d4344f542e513b49cc4d8fc318c9f58ed54b8aa63d1e136d0a15791941d98026`；
私密归档 SHA256 `a6d5f151773f41b9e7ba7d8472385675e21f75bb6de7886369e6ad87c6273c5a`；
实际执行源码归档 SHA256 `22d3dd86583114bcad3a3309e8d4f03ef37437b4e6458f76dc99dbeb6d1c724d`；
原客户端归档 SHA256 `25585b3b50a3b578909597a8d989c06812722ccd5501ba00932a7eeb47e1cc4c`。
12 份 CLI 认领备份和唯一远端目录已精确删除，其它备份保留；
三业务健康、timer 匹配，测试端口关闭、443 开放、透明两 unit inactive。
本机容器、forward、私密散件及重复保险副本已清，四份归档保留。
结束后另行修复控制器取证失败仍删容器的问题，并用实际 finally 的成功/失败两路自检；
加固版源码另存，未冒充已结束本轮的执行输入。
该证据仅关闭上述固定客户端和环境的站点/ALPN 子项，整体计划仍未完成；
未改生产代码，不重复 daily/full。

### 2026-10-24 3.41.6 正式升级与业务保持

同一 Debian 13 amd64 VPS 从正式 `3.41.5` 升级至 `3.41.6`，运行源
`56223a1eff500c2a77c13d14e84cb66a97c86c62`。新旧清单、Sigstore bundle
及控制包均固定摘要，生产 Cosign 验签后执行正式 `update`。
升级前后固定 Mihomo `v1.19.28` 原生 WS 共 2 正例、2 拒绝，严格 TLS、
网站和错 SNI 检查通过；两份原客户端请求与远端请求逐项相等。
完整 spec 只改变 release/images，业务材料字节、属主权限、URI、
两个 timer 和累计保持；保留唯一新增回滚点 `update.SR95Tw` 及既有备份。

`runner_exit=official_restore=outer_restore=verify=0`，保留新版基线，
guard `completed=true/triggered=false`。执行时间 `09:16:29–09:17:47 UTC`。
独立断网核验检查固定发布材料、原始请求/响应、客户端配置、业务树元数据、
计量、调度和备份集合；原始资源 39 样本覆盖 `76.422` 秒，
最低 MemAvailable `416448 KiB`、SwapFree `505904 KiB`，最高 load1 `2.44`。

证据 `.tmp-native-upgrade-3416-20261024/`：
公开归档 SHA256 `72e60b4ac733f6c109700cc082e534302c45296b127345ceb506191eb80c28b1`；
私密归档 SHA256 `89ea0e4aa6c13fe7f69a4596d50cdfd15fa8b8f03b34cd50f3f92aad38664846`；
实际源码归档 SHA256 `85f8affe044ff18f61ae770fd94d5e1b0232de6e6e1f590753cff6d66e747f35`；
原客户端归档 SHA256 `322c42b48c8978cee92a9a397628c3ee0a3e16040ed06f7cd317eb4723147100`。
客户端大二进制未重复放入归档，独验另读保留的原实际二进制并核固定摘要。
升级唯一远端目录已精确删除，既有备份及 `update.SR95Tw` 保留；
原实际二进制另行压缩保全，本机容器、转发和重复散件已清。
此次运行包含合法未排序分享组列表修复；不改变其它客户端、架构、网络和透明支持范围。
透明保持关闭，整体计划仍未完成。

### 2026-10-24 3.41.6 TLS 四阶段限定验收

同一 VPS、正式 `3.41.6`、普通 bridge、公网 IPv4 TCP、固定 Mihomo
`v1.19.28`。保留原 WS `443`，联合验证 `22/23/24/25/27/29` 七入口
`2450–2456`、独立账号和分享组，再切换纯 sing-box 协议 23，最后恢复原 WS。
正式 CLI 接受合法未排序的七入口分享组并保存 canonical 顺序；
主/组共 4 次严格 HTTPS 下载、4 次错 token 404、11 次错 SNI 拒绝通过。
原生客户端共 13 正例、8 拒绝；协议 23 的 HTTPUpgrade 手工对照另计
6 正例、3 拒绝，包含 Xray/sing-box 及纯 sing-box 阶段。
`raw_uri_matrix_passed=false`，此前固定客户端原生导入失败仍保留。

四阶段实际归档通过独立断网核验，四份原客户端请求与远端请求逐份相等，
校验实际二进制、原生 provider 与手工配置、下载正文、身份及计量，
原材料字节/权限和 timer 恢复。`runner_exit=official_restore=outer_restore=verify=0`，
guard 正常完成且未触发。174 样本覆盖 `346.879` 秒，最低 MemAvailable
`341708 KiB`、SwapFree `499932 KiB`，最高 load1 `3.41`；结束于 `09:58:47 UTC`。

证据 `.tmp-native-tls-finish-20261024/`：
公开归档 SHA256 `ce6831300357c85447c06b2b4856e56a5e4b46fbeaa5bd42bfce4fa1df27fe45`；
私密归档 SHA256 `5573561180b33cc7f625c38a8a46936ff1f56b2ac574c81a9475f79013d73801`；
实际源码归档 SHA256 `e60efe996f6e0233736d6125a23e3deafb1e7c0780d71b46ccf55fddd1846229`；
原客户端归档 SHA256 `03ceadc906f5d373798971761704b3aa89d0afbccf1123182ef392ecb99e8846`。
前两次准备分别因临时发布缓存不存在、旧 failed transient 单元占名中止，
均在业务变更前封存并精确清理；后续显式提供固定发布材料并增加启动前门禁。
后验工具修正新建分享组 token 的 48 位生成断言，合成归档及 27 项篡改拒绝通过；
该修正未改动运行器、原归档或实际运行源码。
三份本轮认领备份及唯一远端目录已精确清理，其它备份保留；
三业务健康、timer 匹配、测试端口关闭、443 开放，本机容器、转发及重复散件已清。
透明关闭；UDP、IPv6、重启、其它客户端及完整管理不由本轮证明，整体计划未完成。

### 2026-10-24 3.41.6 路由业务与失败态恢复

同一 Debian 13 amd64 VPS、正式 `3.41.6`、普通 bridge、公网 IPv4 TCP、
固定 Mihomo `v1.19.28`。原 WS 加 15 个业务阶段覆盖两核心选择性/全局
SOCKS5 TCP，以及纯 sing-box SS2022 入口的解析后 IP 阻断；各路径均检查
正常、认证拒绝、认证恢复、上游不可用和恢复。独立断网核验取得
50 正例、31 拒绝，49 个原点 nonce 各一次、30 个拒绝 nonce 零到达；
16 份原客户端请求/响应与远端相等，27 份完整客户端配置/URI 及实际二进制另核。
该轮另以 `configure --preview` 的非零退出声称验证混合核心解析后阻断拒绝。
后核正式 `3.41.6` 的 `dockerConfigureCommand` 不接受 `--preview`，在规格验证前
即返回用法码 `2`；因此撤回该原生语义门禁子结论，只保留参数拒绝及部署未变事实。
这不改变上述实际业务阶段的 50 正例、31 拒绝和原点记录。

正式恢复、outer restore 和 verify 日志各唯一 `rc=0`，原材料字节/权限、
规格及 timer 恢复，三项服务健康。随后全宿主地址相等断言失败：
Docker 重建仅将三条旧 veth `fe80::/64` 地址替换为三条新地址，
lo/eth0/docker0/br 稳定地址保持。原归档没有 runner、guard 完成或第 17 阶段
恢复 WS 记录，保持 `matrix_complete=false/guard_completed=false`。
不补造整轮通过，也不重复未变的 15 阶段业务矩阵。

新 nonce 的独立恢复 WS 探针另档，通过 1 正例、1 错 UUID 拒绝与网站严格
TLS/200；实际配置、URI、二进制和当前 boot 独立断网复核通过。
核恢复后仅停止本轮 guard，精确删除四份日志认领的 configure 备份及唯一路由
目录，保留所有既有备份和 `update.SR95Tw`；夹具进程/认领为空，
2470 TCP/UDP 关闭、443 开放，runner/guard transient 已清。

证据 `.tmp-native-routing-combined-20261024/`：
公开归档 SHA256 `9002ca0fa9b72309e8aad9f72cfd552c00cc24d0f9cb295289aeb5b7a4c7a627`；
私密归档 SHA256 `e0cfb379ac46486943757a4facb1d5d7a4c77311d2616f38559be674a4614574`；
实际源码归档 SHA256 `36b5a1a5ced5a71d892fa3c95f41f13bb24aa56d3837ce0d01770764e06dde81`；
原客户端归档 SHA256 `5d785b6521cdf52b3a70b1c3910431f3b0545f124a5f9161ddc5bde98566887f`；
原运行客户端二进制补档 SHA256 `345a885d63037c948c8b21f6971bf78554e5e7a99ea66d2c4000754770aadfab`；
独立恢复客户端归档 SHA256 `3b7fdfb8173ec5f70be0f823dd0cbd58477601b2dd74b3a3bab91c96441ad47f`。
该补档来自实际运行容器，不是事后从镜像重新提取。失败态 verifier 的稳定地址
篡改及默认完整模式拒绝 16 阶段自检通过。本机本轮容器、转发及重复散件已清。
不证明系统解析器回退陷阱、纯 sing-box 阶段网站/订阅、UDP、IPv6、WARP 或
重启；透明保持关闭，完整路由管理与整体计划继续未完成。

### 2026-10-24 3.41.6 UDP 别名最小补验

复用同一 VPS、普通 bridge、公网 IPv4 与固定 Mihomo `v1.19.28`，
保留六个 UDP 入口配置，仅探原 WS、TUIC 与 SS2022，执行一次删除别名 edit。
四阶段为原 WS、SS 默认别名 2467、删除该别名、恢复原 WS；
共 9 正例、7 拒绝，11 个有效 UDP nonce 各到达一次、3 个拒绝 nonce 零到达。
失效别名的每个拒绝均有前后有效基口对照，TUIC 在删除别名后此次通过；
不据此解释此前 12 秒超时的根因。

实际四份原请求/响应及逐例时间与远端一致，22 份完整配置/URI 和实际运行
二进制独验通过。主订阅正文精确一致，身份、其它监听、额度及累计保持。
`runner_exit=official_restore=outer_restore=verify=0`，guard 正常完成且未触发。
资源样本覆盖 `315.055` 秒，最低 MemAvailable `355860 KiB`、
SwapFree `496108 KiB`，最高 load1 `4.11`；systemd 于 `10:58:39 UTC` 成功退出。

首轮 v2 在第一个 UDP 请求前因 AppArmor 拒绝 tcpdump 在隐藏私密目录创建
pcap 而失败，内核 DENIED 与策略已保全；原 WS/恢复 WS 通过，恢复三项全 0。
修正仅令父 Python 预开 `0600` pcap 输出、tcpdump 使用 `-w -` 并分离 stderr，
未修改 AppArmor 策略或放宽目录权限。原机一次有界自检实际捕获唯一 UDP 包，
头、payload、日志和进程认领通过；新 process 默认路径六项真实容器检查、
证据核验器 23 类篡改及客户端 provider/URI 篡改自检通过。
v2 失败档封存于 `attempt-1/`，未覆盖此前两轮 UDP 失败。

证据 `.tmp-native-udp-close-20261024/`：
公开归档 SHA256 `a93755c6668e3b135146a06544054f79488796f0a629552aa9a1e1c2156ab867`；
私密归档 SHA256 `392d0012f2e641052a75bf03bc75e154236407e9e9bfbbde2872a44b9ceda142`；
实际 v3 源码归档 SHA256 `dac333ae3f893ce030a8ea79cd5a66962f3956185861cd6e43405baefc03d030`；
原客户端归档 SHA256 `87fa57c527e713535f753f42ec0ad748d381ed6a0b5d1997d08396effd221f4a`；
v3 实际运行二进制补档 SHA256 `345a885d63037c948c8b21f6971bf78554e5e7a99ea66d2c4000754770aadfab`；
原机抓包自检归档 SHA256 `f1d0e7727d820b720b4bc2a19a1b9fe3231ac4e51c4b5c689720b9fc41682926`。
断网独验后精确清理三份 CLI 日志认领备份及唯一远端目录，保留既有备份和
`update.SR95Tw`；材料字节/权限、timer、三服务健康与透明关闭均核对，
2460–2467 TCP/UDP 关闭、443 开放。本机运行容器、转发和重复原始散件已清。
未重复 Hy2 探针或默认别名替换 CLI，不证明自动跳跃、IPv6、重启、其它客户端、
性能或完整管理；本批无生产代码变更，不重复 daily/full，整体计划仍未完成。

### 2026-10-24 HTTPUpgrade 原生导入根因复现

固定官方 Mihomo `v1.19.28` tag 对应 commit
`cbd11db1e13a75d8e680e0fe7742c95be4cba2be`。其
`common/convert/converter.go:308–317,356–390` 保留 `network=httpupgrade`
并生成 `ws-opts`，未归一为 `ws` 或设置 `v2ray-http-upgrade=true`；
`adapter/outbound/vmess.go:164–175` 仅在 `network=ws` 进入升级引擎，
`249–258` 的默认分支使用普通 TLS，`NewVmess` 从 `490` 行开始的 switch
未拒绝未知 network。此前“转换器显式改成 TCP”的诊断不准确，以该源码链为准。

使用与原生验收相同的实际二进制，SHA256 为
`788bb454fb613d8a060795ed4a6f4c3dae1f110b91556b21796771c1ac89a804`，
在 Docker `--network none` 中，以假 UUID、`.invalid` 域名及本地可信证书执行
三个对照；均成功导入、严格 TLS 1.3 和正确 SNI。原生 URI 与直接配置
`network=httpupgrade` 的首包分别为 133、124 字节，均非 HTTP；
手工 `network=ws` 加升级标志发出 134 字节的正确 GET、Host、Upgrade。
源码和记录的摘要、tag/commit、三例身份与结果经独立核对一致。

证据 `.tmp-httpupgrade-rootcause-20261024/evidence.tar.gz`，SHA256 为
`066eb8a15b30c482e3e773905b0e572e3ee89ce1049bda28efb8f5ba1d31ad81`，
包含固定官方源码、tag、复现输入和结果；容器、提取 binary 和假证书已清。
该证据定位固定客户端的导入/发送分支限制，不修改 padm 的正式
`net=httpupgrade` URI，也不把手工对照或后续服务器通过晋升为原生 URI 成功。
未操作 VPS，不证明其它客户端版本；原公网失败及整体未完成状态保持。

### 2026-10-24 3.41.6 纯 sing-box 路由与发布共存

固定同一 Debian 13 amd64 VPS、正式 `3.41.6`、普通 bridge、公网 IPv4 TCP、
Mihomo `v1.19.28`。原 WS → 纯 sing-box `23/30` → 原 WS，仅两次正式
configure（含恢复）。五个客户端阶段共 8 正例、7 拒绝，其中 HTTPUpgrade
手工对照另计 1 正/1 拒绝，原生部分为 7 正/6 拒绝。纯部署始终只有
sing-box、Nginx 和 subscription 三个运行服务；同一容器集合完成健康、
SOCKS 认证拒绝及恢复，无额外 configure。解析后阻断、hosts 优先、DNS 分流、
直连重叠及独立账号业务取得 6 个有效原点 nonce 各一次、5 个拒绝零到达。

主订阅精确 3 URI，分享组只含独立 SS 账号的 1 URI；CLI、发布文件、实际 HTTPS
下载正文和客户端选择相等。两次严格下载、两次错 token 404 通过。
五阶段网站正文精确等于运行中 Nginx 配置内的 53 字节 inline return 200
literal；配置原件与宿主正式配置字节一致，pure 来源容器 ID 与 inspect 相符。
派生的 `*-index.html` 仅为比对正文，不是部署中的静态文件。

四份实际归档经 Docker 断网独核，包含实际 binary、五份原请求/响应、
逐例 URI/provider/手工配置、DNS/SOCKS/原点事件、网站原件及身份。
原材料 before/after/verify 字节摘要、权限/属主清单相等，稳定宿主地址保持，
计量无回退，恢复四项全 `0`，guard 正常完成且未触发。
篡改实际网站来源容器 ID 的最小检查被拒绝。
86 个资源样本覆盖 `170.541` 秒，最低 MemAvailable `393104 KiB`、
SwapFree `504436 KiB`，最高 load1 `3.28`、load5 `1.07`；
恢复 WS 于 `2026-10-24T12:36:51.094Z` 完成。

证据 `.tmp-native-routing-publication-20261024/`：
公开归档 SHA256 `00454e4ba23c52fa9da68a43e5cbd639515363a8622b5ad5dc4d21490f202aa1`；
私密归档 SHA256 `2c15386845f5f06c59ee3becd84cc329a5220b91cab11ec1df540eef9a05bfba`；
实际源码归档 SHA256 `bbad197c32a5f09b9a04df65979ed39a0250c0c0162de7d69f924281b26013c2`；
原客户端归档 SHA256 `bc3d1b98a03da7521cb20734aaffad0f5fc3cfbba1163c5d343b642685e827de`。
前两次准备分别因不支持的 `configure --preview`、错误假设存在静态首页而停止，
均在客户端请求和 pure configure 前，原档保留。第二次正式/outer/verify
恢复全 `0`，唯一认领恢复备份已清。第三次改用正式 schema 函数只读验证、
从实际 Nginx 取正文，并先离线生成同候选集中核对路径与 CLI。
旧路由同一 preview 所声称的原生语义门禁结论已撤回，见前节。

独验后精确删除两份本轮 CLI 认领备份和唯一远端目录，保留其它备份及
`update.SR95Tw`；三服务健康、调度匹配、2470 TCP/UDP 关闭、443 开放。
本机容器、转发及已归档的请求/响应、candidate、payload 散件已清。
SS 虽有 TCP/UDP 映射，本轮只测 TCP；不证明系统解析器回退陷阱、UDP 业务、
IPv6、WARP、重启或原生 HTTPUpgrade URI 导入，旧失败保留，透明关闭。
本批无生产代码变更，不重复 daily/full；完整路由管理与整体计划仍未完成。

### 2026-10-24 3.41.6 系统解析器回退陷阱

固定同一 Debian 13 amd64 VPS、正式 `3.41.6`、普通 bridge、公网 IPv4 TCP、
Mihomo `v1.19.28` 原生 URI 导入。原 WS → 纯 SS2022 系统解析 A →
仅增两个 exact DNS 选择器的 B → 原 WS；含恢复三次 configure。
四阶段独验通过 6 正例、4 拒绝，其中系统解析正例 4 个、指定 DNS 拒绝 2 个。

A 将两个随机域名仅写入实际 sing-box 容器的 Docker hosts 文件，解析到
未被阻断的 `127.0.0.2`，两次认证 SOCKS 出站业务成功。B 使用同名、相同
hosts 映射及其它配置，只增加两个 exact DNS 选择器；夹具分别返回 SERVFAIL
和丢弃查询。实际核心日志明确结束两次请求，客户端均为 `RemoteDisconnected`，
不是客户端等待超时。指定查询真实到达 DNS 夹具，两拒绝无 SOCKS 连接或原点
到达；第三个未匹配域名严格按“正控 → 两拒绝 → 正控”完成，4 个有效原点
nonce 各一次。容器 hosts 按原字节、inode、权限恢复，容器及宿主 resolv.conf
不变，未修改宿主 hosts。

独立断网核验实际四归档、四份原请求/响应、URI/provider、生成配置和原始日志。
正式镜像使用 gcompat loader；取证分别绑定 loader 的 exe/摘要、实际 core
的 map_files 引用与容器 root 文件的 stat/inode/摘要，保留原 maps 和 NUL
分隔 cmdline，不把 loader 当作 sing-box。将实际两份核心记录的 core 摘要
同时替换为 loader 摘要的最小篡改负控被拒。原材料 before/after/verify 清单相等，
恢复四项全 `0`，guard 正常完成未触发，四阶段计量增长与不回退检查通过。
115 个资源样本覆盖 `228.603` 秒，最低 MemAvailable `411476 KiB`、
SwapFree `505020 KiB`，最高 load1 `1.69`、load5 `0.82`。

证据 `.tmp-native-resolver-trap-20261024/`：
公开归档 SHA256 `790ed752b0ae57c526ad401af3a7c5238c1c6d0f2faacf4361d7bc00929d672b`；
私密归档 SHA256 `2d58a3e6cc718ae128295d2033e2ef6da51402ae52d26a4ebcda86939118d051`；
实际源码归档 SHA256 `d3a8863d38de2f0afeb588f7f3e53e09fed79ea1a713b86a361e22214ae74601`；
原客户端归档 SHA256 `83eec5bc21ea26b11c6e053e916b78e20923abb916e9091b562ddb1808d92fc7`。
前两轮在 A 业务前错误认定 init 或 loader 的进程身份；首轮未保存原异常栈，
不补造。第三轮程序恢复成功，但 JSON 对象键排序把末尾正控提前，独验拒绝
整轮通过；三轮原档与恢复/清理材料保留。显式执行序列经真实记录器的排序请求
离线自检后，第四轮才完成上述完整矩阵，不将先前失败改写为通过。

独验后已精确删除三份本轮 CLI 认领备份和唯一远端目录，保留其它备份及
`update.SR95Tw`；三服务健康、调度匹配、2470 TCP/UDP 关闭、443 开放，
控制器容器/转发和独验容器已停止清理，透明保持 inactive。
本轮不证明 UDP 业务、IPv6、WARP、重启或其它客户端；无生产代码变化，
未重复 daily/full，整体计划仍未完成。

### 2026-10-24 3.41.6 路由与 UDP 合并真实重启

固定同一 Debian 13 amd64 VPS、正式 `3.41.6`、source
`56223a1eff500c2a77c13d14e84cb66a97c86c62`、普通 bridge、公网 IPv4、
Mihomo `v1.19.28` 原生 URI 导入，不混换 `3.41.7`。原 WS → 纯 sing-box
重启前 → 重启后 → 恢复 WS，共四阶段、14 正例/10 拒绝；
另有 12 次 UDP 前后正控，不重复计入上述主例数。

一次真实 VPS 重启的 boot ID 从
`27461660-19bc-4e08-9567-33627676ef46` 变为
`125369c6-77f7-409d-97b9-37c97d19cabf`。同一组受管容器按原重启策略自然恢复，
未用 configure、up 或 restart 替代重启后的业务验证。每个 pre/post 阶段均完成
hosts、DNS、解析后 IP 阻断、认证 SOCKS5 TCP 四项，以及 TUIC `2464/udp`、
SS2022 基口 `2465`、默认别名 `2467` 的 UDP 正反例。错身份均在同端口执行
“正控 → 拒绝 → 正控”；共 6 个 TCP 原点 nonce、18 个有效 UDP nonce
各到达一次，6 个拒绝 UDP nonce 零到达。UDP 回环原点直连，不经过 SOCKS；
这些结果不扩大 SOCKS UDP 支持范围。

四份实际归档在 Docker `--network none` 内独立核验通过：
四份原请求/响应与顺序、URI/provider/运行配置、实际客户端二进制、
loader 与映射核心的独立身份、24 个逐尝试抓包窗口和 96 份客户端抓包
请求/应答原件均匹配。先验证实际四档成功，再逐项篡改客户端二进制、
provider 路径、全部响应副本顺序、boot ID、原容器身份、原点事件、
拒绝抓包长度、映射核心摘要、正式恢复退出码和 guard 状态；
10 项负控均被拒绝，未通过放宽验收条件消除失败。

原材料 before/after/verify 字节与权限/属主清单相等，调度及累计保持。
`runner_exit=official_restore=outer_restore=verify=0`，guard 正常完成未触发，
原 WS 恢复于 `2026-10-24T15:05:44Z` 完成。257 个资源样本分属重启前
132 个、重启后 125 个；最低 MemAvailable `396556 KiB`、
SwapFree `505020 KiB`，最高 load1 `2.57`、load5 `0.75`。
未跨 boot 直接相减 monotonic 时间。

前三轮失败分别封存在 `attempt-1/`、`attempt-2/`、`attempt-3/`：

- 首轮在 combined-pre 客户端导入前失败，0 pure 业务/0 重启。`mapped_uri`
  误改 contextmanager 包装层，真实生成器仍检查旧端口 `2470`；修正真实函数
  作用域后，SS2465 实际导入成功，故意恢复旧映射的负控准确失败。
- 第二轮在首 TUIC 窗口的离线解码失败，0 重启。AppArmor 拒绝 tcpdump
  直接读取私密路径；改为父进程预开 stdin、`tcpdump -r -` 后，同 VPS 原安全
  策略下正负控通过，未调整 AppArmor。原 pcap/stderr 和 seq2 缺失响应保留；
  控制器的恢复序号绑定修正经自检，并在第三轮真实早恢复中生效。
- 第三轮原 WS 到外部 HTTPS 目标发生 `SSLEOFError`，未进入 pure/未重启；
  根因未确定。自动恢复和正式/outer/verify 全 `0`，原档保留。同冻结源码的
  第四轮才完整通过，不将新成功倒推为已证明该 EOF 是瞬态故障。

三轮失败均由 root 断网独核并被完整成功验收器拒绝，恢复与精确清理证据保留。
证据 `.tmp-native-routing-udp-reboot-20261024/` 的最终四档 SHA256：
公开归档 `96bb75fce5630ed62af04590e01c35ca0b106253b4d329f3c0f33f8b0f1c23cd`；
私密归档 `e591c1a0cf92b9cbc468389b02aadc2a7a231a6f5bafc1c49ecd6e90f0c06bfa`；
原客户端归档 `bb45556461d49d2f8a318bdde6205989886a8f0304819ed3aa606670dbf7c3f0`；
实际源码归档 `98cc366e81a3981187b4da8a29c8761bffd6a97a2408d4ead47ae984d0ac7263`。

独验后已精确清除 5 个本轮 systemd 单元、2 份 CLI 认领备份及唯一远端目录，
保留其它备份和 `update.SR95Tw`。nginx/xray/subscription 健康，调度匹配，
2464/2465/2467 TCP/UDP 关闭，443 开放，透明保持 inactive。本机控制器和
断网独验容器、18443 转发、已入档并逐字核对的重复源码/运行散件已清；
最终四档、三轮失败原档和清理结果保留。

本轮不重复 Hy2、网站/订阅常态矩阵或全量回归；无生产源码变化，
不声称本次说明提交已运行 CI。仍不证明透明启用重启、IPv6、自动跳跃、
WARP、其它核心/客户端/算法、性能长稳或完整能力，整体计划继续未完成。

### 2026-10-25 3.41.6 XHTTP 实际 POST 与有界连接

对应计划 5C.2f.9。固定同一 Debian 13 amd64 VPS、普通 bridge、公网 IPv4、
正式验签 `3.41.6`，source
`56223a1eff500c2a77c13d14e84cb66a97c86c62`，bundle SHA256
`4b441c5fe4fdfef58986f0c133972e8ff53db1dd95ead27f0990e89050657f2d`，
manifest SHA256
`1348ae73776cdd43e8ced23b6cb120da4e03327afffa303655c0d8a15b909982`。
唯一客户端 Xray `26.3.27/d2758a0`，实际二进制 SHA256
`8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed`。
原生客户端工具镜像固定 `be8156c6`，离线观察工具镜像为 `73f8f813`，
不混记为同一镜像。日期按北京时间记录，原件 UTC 为 2026-10-24，
证据目录沿用 `.tmp-native-xhttp-posts-20261024/`。

单次 configure 保留原 WS `443`，添加 packet-up `2444`、stream-up `2445`，
不启用 VLESS Encryption，不重启 VPS。每模式按 1 MiB 正控、错 UUID、
8 MiB 正控、60 秒同业务连接执行；另有原/恢复 WS 各正反例。
12 主例共 8 正、4 拒，8 个 XHTTP 窗口分别抓包。正式配置与 URI 一致保留
`scMaxEachPostBytes=16384`、`scMinPostsIntervalMs=5`、
`scMaxBufferedPosts=16`、`scStreamUpServerSecs="1-2"`。

| 实际 POST 计数 | 1 MiB 正控 | 错 UUID | 8 MiB 正控 | 60 秒观察 |
| --- | ---: | ---: | ---: | ---: |
| packet-up | 65 | 1，拒绝 | 513 | 206 |
| stream-up | 1 | 1，拒绝 | 1 | 1 |

次数来自原始 pcap 与客户端 TLS keylog 的独立 HTTP/2 解密，
以 `tcp.stream + http2.streamid` 去重，不按业务大小推算。
正例 POST 均实际双向 END_STREAM/HTTP `200`；packet-up 单次正文
不超过 16384 字节，序号按 session 跨 TCP 检查连续。stream-up 不适用该
正文上限，也不预设 POST 数。错 UUID 使用真实错误身份、原点零到达及前后
正控判定，不强加成功状态。8 份抓包均零内核丢包，保留原始抓包、解密命令、
tshark 版本、PDML 和逐帧观察；TCP 乱序重组显式开启，累计重组正文经 fragment
及长度验证后仅取当前帧实际载荷，避免重复计数。

回显原点只监听 Xray 网络命名空间的 `127.0.0.1:18888`，不新增公网原点。
28 个有效 nonce 各到达一次，对应 56 个 start/complete 事件；两个错误身份
nonce 零到达。持续例每模式在同一业务连接/同一原点 peer 完成 12 次 256 KiB
往返，观察窗分别为 `60.000138`/`60.000158` 秒，实际业务跨度分别为
`56.017092`/`56.025879` 秒。上传 VLESS 身份、目标、业务 nonce/字节/SHA256
和下行逐字节回显均由解密字节重验，只证明该有界观察，不称性能或长稳。

两个独立 `--network none` 容器各完整核对四档及 8 份 pcap；
第二个在完整 baseline 通过后执行实际 pcap 截断、TLS 密钥替换、
packet 序号重复、业务 nonce 不符 4 项实物负控，均被拒绝。
原材料 before/after/verify 的字节、权限和属主相等；baseline、业务后与恢复
调度严格匹配，配置前仅两个 timer 为精确暂停态。累计增长且恢复不回退，
正式恢复、outer restore、verify 全 `0`，guard 正常完成未触发。
213 个资源样本最低 MemAvailable `406140 KiB`、最高 load1 `3.09`。

首轮 prepare 在 outer snapshot 暂停 timer 后，baseline 仍强验 active 而失败，
0 configure、0 业务、0 单元安装；恢复与原材料权限已独核，失败四档保留于
`attempt-1/`。将 baseline 移到暂停前，并仅在 before-configure 显式强验暂停态，
其它阶段仍强验 active；暂停/恢复正控、5 项错误状态及权限篡改自检通过后，
第二轮才完成上述矩阵。首轮未被回写为成功。

新增 `docker/tests/xhttp-post-observe.py` 与 `xhttp-posts-real.py`，
接入已有 `docker-xhttp-real`，复用受信固定 Xray 和真实回显逻辑。
工具层从官方 apt 一次补齐 tcpdump/tshark；TLS/Reality × 两模式 4 例，
真实 VLESS/业务字节/双 END_STREAM/200 和 19 项负控通过，新增部分
`37.070` 秒，完整定向入口 `66.724` 秒。相同源码和镜像的首轮在原有
reality-auto 小回显超时，尚未进入新 POST 检查；原错保留，未放宽期限、
不倒推根因。未重复 daily/full，不声称本次提交已运行 CI。

最终四档 SHA256：

- 公开归档 `d44bc95acd4c34e0b325162476dc46390c9c5bc1a55c65758e8b3e7893b5e1a4`。
- 私密归档 `e52fde75fba30bf914847352e426be906c27feec44b39e61cdf068dc7a74ac59`。
- 原客户端归档 `60d43f589995cfcb280fbfd62300a5a07fc39a01c3edc0febda7d30e65b15ac5`。
- 实际源码归档 `201c2bd115ebe873ae1e3d4e72649a5d384ab78419923c7e175c82da48665157`。

两次独验后按冻结清场器精确删除 5 个本轮 systemd 单元、2 份 CLI 认领
configure 备份和唯一远端目录，保留其它备份及 `update.SR95Tw`。
nginx/xray/subscription 健康，原调度匹配，443 开放、2444/2445 关闭，
透明 inactive。本轮本机容器、转发进程及 18443/12444/12445 监听已清除，
独验容器已删除；四档、失败原件、解码及清理结果保留。

本节只关闭上述固定 Xray 组合的实际 POST 计数和有界连接子项，不扩大至
Mihomo 计数、正式原生 h3/CDN、性能长稳、其它核心/客户端/算法或环境。
透明继续关闭；arm64、IPv6、新主机、多机控制/WG、WARP 实账号、
自然续期及历史 Vision reset/XHTTP/TUIC 超时根因仍未由本节证明，
整体计划继续未完成。

### 2026-10-26 Mihomo 公网累计与有界连接完整补验

沿用正式 `3.41.6`、source `56223a1e`、Debian 13 amd64、普通 bridge、
公网 IPv4 和 Mihomo `v1.19.28`。仅一次正式双模式配置，原 WS → XHTTP →
原 WS 共 12 项，8 正例、4 拒绝，`runner_exit=0,points_passed=1`；
正式恢复、外层恢复和复核全为 `0`。此前两轮失败与原件保持，不改写历史结论。

本轮先恢复生成配置字节，保留运行核心完成正式 `traffic collect`，再重启撤回
观察投影及恢复调度。独验核对配置、采集时序和前后同一核心身份，双向累计各
增长 `25,166,720` 字节，全部账号累计不回退。

| 实际 POST 计数 | 1 MiB 正例 | 错 UUID | 8 MiB 正例 | 60 秒同连接 |
| --- | --- | --- | --- | --- |
| packet-up | 65 | 1 | 513 | 204 |
| stream-up | 1 | 1 | 1 | 1 |

两个持续例均在同一业务连接每 5 秒发送一轮，共 12 轮、每轮 `256 KiB`；
独验核对完整窗口、业务跨度、派生 nonce、原点 peer、上下行字节与摘要。
28 个原点事务各一次，两个错误身份原点零到达；stream-up 三个正例均有
真实同连接 SYN、业务后的 CANCEL 和 FIN，不要求双向 END_STREAM。

断网容器只解码 8 份正常抓包一次，9 项实物篡改负控全部拒绝，含漏第 12 轮、
伪造重启后的采集结束时间、错误密钥出处及提前 FIN。资源 guard 未触发；
最小可用内存 `379884 KiB`、最高 load1 `4.69`，不作性能或长稳结论。
四档、冻结源、独验及清理证明保留在 `.tmp-native-mihomo-close-20261026/`：

- 公开 `4f196aad671332099054806024ac65ff3d2628bf3d105b64a1be7aebe8064d10`。
- 私密 `170622824435706e002c58c431f02ae0895654d6b6541b72c47dbbfa10582dec`。
- 客户端 `7e92ef0868d38151b32fa9856458f82c9e574d7ddeefd969f2077c39ce5c6348`。
- 冻结源码 `738f0895a4ce71f632386b299b740d878c689fb3c15450cb69c370037aba01cf`。

恢复后的材料字节/权限/属主、调度、严格 TLS 和原 WS 正反例通过；只删除
认领的两份配置备份、五个测试 unit 与本轮远端目录，历史备份保留。
本机逐字节核对后清理 18 份可重建副本，共 `48,983,679` 字节，
测试与断网容器已删除，四档和旧失败轮保留。没有重复 daily/full。

仅关闭固定组合的公网 POST、取消、累计、60 秒有界连接和完整恢复子项；
不扩展其它架构、IPv6、核心/客户端、正式原生 h3/CDN 或性能长稳，不解释
旧 Vision reset、XHTTP/TUIC 超时。透明保持关闭，整体计划未完成。

### 2026-10-26 Mihomo 公网 POST 子项及取消时序修正

固定正式 `3.41.6`、source `56223a1e`、Debian 13 amd64、普通 bridge、
公网 IPv4 与 Mihomo `v1.19.28`，透明始终关闭。两轮 runner 均未通过，
自动恢复和精确清理完成；首轮正式 URI 读取时遇 keylog 投影漂移保护，
第二轮已先读取正式 URI，再安装观察投影，没有绕过生产校验。

第二轮原 WS 前后正反例及 XHTTP 六项业务成功，但撤回 keylog 投影时先重启
核心，随后才采集流量，丢失了尚未采集的内存计数。原件保留
`runner_exit=1,points_passed=0`，不存在成功 `matrix.json` 或
`snapshot-after-business.json`；整轮和累计增长继续未通过，不补造结果。

在断网 Docker 容器中重新解密四档原件，独立核对抓包出处、零内核丢包、
服务端 keylog、正式 URI/错误身份、业务字节和原点 nonce：

| 模式 | 1 MiB 正例 POST | 错 UUID POST | 8 MiB 正例 POST |
| --- | --- | --- | --- |
| packet-up | 65 | 1 | 513 |
| stream-up | 1 | 1 | 1 |

四个业务 nonce 各到达一次，两个错误身份原点零到达。stream-up 两个正例
均有真实同连接 SYN/FIN；1 MiB 的最后 DATA、客户端 CANCEL、服务端 FIN、
客户端 FIN 分别为帧 `1359/1424/1428/1430`，无 TCP RST。旧解析器错误地
要求客户端 FIN 先于服务端 FIN；现以完整业务后的客户端 CANCEL 为边界，
仍拒绝 CANCEL 前的服务端 FIN，并保留连接归属、完整正文和关闭检查。
冻结源不变，独验器只接管精确命中的旧 FIN 断言，再用修正解析器重核同一 PDML。

当前源码的 `docker-xhttp-real -Jobs 2 -ForceRun` 实跑通过，入口 `84.664`
秒，`cache_hit=false`；取消后服务端 FIN 合成正控及两种提前 FIN 负控通过。
本地证据 `.tmp-regression-docker-de0b0f88caf84016bc69b61ee822cffb/`；
公网四档、失败轮、冻结源、独验器、`posts-only.json` 和清理证明保留在
`.tmp-native-mihomo-posts-20261025/`。四档摘要依次为：

- 公开 `ddf0e1c6f5557111ed02e06e4212f8f84c488570bcacf00b3553d5cfb661935c`。
- 私密 `9adc8b80c116bfdf3f84e5d68d6f85f9ef17a35eda005ea35b44e75232a7d92d`。
- 客户端 `67027be2875d09516cdc926cad264204df2bbfe046ead72c1f3864194ea54318`。
- 冻结源码 `3341e5a9859f5701865e8df1ee6f336d897283628a4ba2dea51ceb72c600da54`。

材料/权限、调度和原业务恢复通过；每轮只删除认领的两份配置备份、五个测试
unit 及测试目录，历史备份保留。本机逐字节核对归档后删除 14 份可重建副本，
共 `48,976,249` 字节，断网容器已停止删除。仅关闭固定组合的公网精确 POST
和取消子项；累计、成功整轮、有界长连接及其它环境仍待验，不解释历史超时，
透明保持关闭，整体计划未完成。

### 2026-10-25 3.41.6 固定 Xray 的 TLS 七入口转换互通

对应计划 5C.2f.10。沿用同一 Debian 13 amd64、普通 bridge、公网 IPv4 TCP，
正式 `3.41.6`、源提交 `56223a1eff500c2a77c13d14e84cb66a97c86c62`，
bundle/manifest 摘要与上节相同，生产 Cosign `Verified OK` 已复核。
唯一客户端 Xray `26.3.27/d2758a0`，二进制 SHA256
`8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed`，
客户端镜像固定 `9f96453256b30374c66c90d676953402d47ec9f1fbc1aa251feb1bde21985f31`。

原 WS → TLS 七入口共存 → 纯 sing-box 23 → 恢复 WS 四阶段通过；
七入口为 22/Xray、23/Xray、23/sing-box、24/Xray、25/Xray、27/Xray、
29/Xray，临时端口 `2450–2456`。逐阶段正/拒分别为 `1/1`、`15/8`、
`2/1`、`1/1`，合计 30 例＝19 正、11 错认证拒绝。另有 4 次主/组
严格 HTTPS 下载及 4 次错 token `404`、2 次分享组业务、11 次错 SNI 拒绝。
七入口合法未排序分享组保持同一身份，纯 sing-box 23 阶段从 `2452`
发布网站与主/组订阅。正例 URI 来自实际 HTTPS 下载正文，CLI、发布文件、
下载正文逐字相等；配置只映射连接地址/端口，认证、SNI、ALPN、Host、
path、serviceName、flow 均保持。

本轮明确为 `uri-to-xray-config`，不是 Xray 原生 URI 导入；
`raw_uri_matrix_passed=false`、`native_uri_import=false`。
不修改正式 URI，也不把本轮成功用于关闭 Mihomo 原生 HTTPUpgrade 限制。
新增测试转换器 `docker/tests/tls-uri-xray.py`，7 种正式模板及 14 项负控
自检通过；接入 `vmess-real.sh` 的实际 links 核对与 `vmess.sh` 日常合同。
`docker-vmess -Jobs 2` 在当前源码 Docker 快照实跑 `227.036` 秒通过，
`cache_hit=false`；没有重复 daily/full，不声称本次提交已运行 CI。

四档在 `--network none`、只读证据挂载的容器中独验通过，核实际执行源码、
二进制、四份原请求/响应、逐条订阅转换、仅地址/端口映射、计量和原件恢复。
完整 baseline 后，真实归档中的 TLS 放宽、下载正文替换、额度改变、
恢复原件字节篡改 4 项负控均被拒绝。145 个资源样本最低 MemAvailable
`369248 KiB`、最高 load1 `3.35`，guard 正常完成且未触发；
正式恢复、outer restore、verify 全 `0`。材料字节/属主权限、调度匹配，
双向累计增长且不回退，透明始终关闭。

证据目录 `.tmp-native-tls-xray-20261025/`，四档 SHA256：

- 公开归档 `91cf80e4ad1d85804596222c7cdaa9d92e267bad7da1be8ed32647e89cee4794`。
- 私密归档 `ba1a9f53087f999c37cf8f59dd805411cc3db49d7150945ab7592f98252362d2`。
- 原客户端归档 `43904c1c0125166e03a849309bba9e0575b16e8f3fb973b7d0d10cebd965d47d`。
- 实际源码归档 `68d261ea3b4f2a3ec1d6a46115514541fd926dec0f09cededff19f1bc247ec07`。

独验后按上述公开/私密摘要核对远端，精确删除唯一测试目录及 CLI 认领的
3 份备份，其它备份与 `update.SR95Tw` 保留。三项业务健康、timer 匹配，
443 开放，`2450–2456` 关闭，runner/guard inactive，透明 inactive。
本机客户端/转发已停止删除；重复源码、配置、URI 和二进制均先入档逐字
核对后删除，四档、私有观察归档、独验器及清理证明保留。清理脚本先遇空
tar 文件流处理错误，删除前已修正；删除后汇总报错，随后只读补核全部
预定路径消失与四档摘要不变，没有重复删除或丢弃原证据。

本节不验证 UDP、VPS 重启、原生 URI 导入、其它核心/客户端/算法或环境，
不解释历史 Vision reset、XHTTP/TUIC 超时；透明启用重启按要求不做。
原生 arm64、IPv6、新主机灾备、多机控制/WG、WARP 实账号、自然续期、
正式原生 h3/CDN 和性能长稳仍未完成，整体计划继续未完成。

### 2026-10-26 本地 Docker XHTTP POST 与取消负控

在本机 Docker Linux `amd64` 使用当前工作区快照运行
`docker-xhttp-real -Jobs 2 -ForceRun`，入口通过，`cache_hit=false`，
总耗时 `84.782` 秒。固定 Xray `26.3.27/d2758a0` 与 Mihomo
`v1.19.28`，分别覆盖 Xray Reality/TLS 和 Mihomo Reality 的
packet-up、stream-up，共 6 组 1 MiB 实际回显。各 packet-up 均独立解密
并计得 65 个 POST，各 stream-up 均计得 1 个 POST；真实 VLESS 业务字节
与逐字节回显校验通过。此为本地容器互通证据，不是 VPS、公网或生产验收。

Mihomo stream-up 取消例在业务完成后停止客户端，HTTP/2 CANCEL 与进程生命
周期检查通过；抓包未稳定包含客户端 SYN/FIN，因此仍使用生命周期证据，
不声称观察到真实 TCP FIN。新增离线负控合成同一连接、早于 HTTP/2 业务的
服务端 FIN PDML，解析器按预期拒绝；该合成帧只验证拒绝逻辑，不是线上抓包。
本轮报告及日志保留在
`.tmp-regression-docker-a611a1aead7e441ca9a1985c1ad6917e/`；
测试容器退出时清除了每次运行的 pcap、TLS keylog 与 PDML，未保留这些原始材料。
透明代理保持关闭；正式 Mihomo 公网验收、性能/长稳及其余环境仍未完成，
整体计划继续未完成。

### 2026-10-26 正式 3.41.8 升级与回滚闭环

在同一 Debian 13 amd64、普通 bridge、公网 IPv4 VPS 上，使用两版正式三件套，
现场分别核对 SHA256 和 Cosign 身份后，通过正式 CLI 完成
`3.41.6 → 3.41.8 → rollback 3.41.6 → 3.41.8`，最终留在新版，
source=`e671328edede4c80d1c003eeb38495c48411a5e7`。
此为实际版本往返，不以发布 CI、离线夹具或规格中的 version 字段替代运行 bundle。

四阶段固定 Mihomo `v1.19.28` 的正式原生 WS URI 共 4 正/4 错 UUID 拒绝，
另核四次网站严格 TLS/HTTP `200` 和四次错误 SNI 拒绝。URI 恒等，
规格仅 release/images 随版本改变，每阶段源码 ref 精确匹配。
业务配置、分享组、订阅、TLS、完整 ACME、续期及 webroot 材料的字节、
mode/uid/gid 均保持，两个 timer 最终匹配原状态；每阶段双向累计增加，
跨更新/回滚的全部账号额度保持、累计不回退。最终 nginx、xray、subscription
均 healthy，运行镜像逐项匹配正式 manifest；断网启动正式 ops 验证 curl
`8.23.0-r0` 可执行，并用 `apk --no-network info --who-owns` 核包归属。
首次附加包查询尝试读取软件源索引且输出断言失败，改为上述离线查询后通过，
未因此安装依赖或改动镜像。

最终 runner=`0`，正式恢复/outer/verify 状态均 `0`，保留新版。
独立断网容器核验四档，业务 UUID、回滚阶段版本、正式回滚目标、
rollback 安全快照版本共 4 项实物篡改均被拒绝。
147 个资源样本覆盖 `292.898` 秒，最小 MemAvailable `369156 KiB`、
最小 SwapFree `498188 KiB`、最高 load1/load5 为 `3.09/1.13`，
guard 正常完成且未触发，不作性能/长稳结论。

证据 `.tmp-native-upgrade-3418-final-20261026/verification.json`，四档 SHA256：

- 公开：`5e9d5ca191e326677b7ff9bb3b4986d4b3c0bd165743db85c023adbd327456d8`。
- 私密：`3e5adf3572d4fdd27b892abb1acda6f32e2e89b3b8838b21526eb2cacadc5b5c`。
- 客户端：`57047f603e829e25fb321e1a16b3a5f272426b9964807ef427b0390d157b49c0`。
- 冻结源码：`c8fa0cc4402070a0b008d04e9927fb41a3c3b9913bdf2ecd8a174d00190a74a3`。

前三轮失败原件分别保留于 `.tmp-native-upgrade-3418-20261026/`、
`.tmp-native-upgrade-3418-retry-20261026/`、`.tmp-native-upgrade-3418-close-20261026/`。
首轮缺已清理的旧缓存，业务切换前退出；第二轮四阶段业务通过，但验收误要求
只新增两份 update，漏算正式 rollback 保留的安全快照，runner=`1` 后自动恢复。
该运行器的 configure/外层字节恢复没有切回旧控制 bundle，导致第三轮源码前置
断言拒绝，未进入矩阵。随后核对最新 update 的规格和 bundle 目标，正式 rollback
恢复一致的 `3.41.6` 基线；最终轮失败恢复改为正式 update 并增加源码 ref 断言。
不改写前三轮结果，不把这些运行器缺陷归为产品运行缺陷。

独验后核对远端归档摘要，精确删除本轮四个测试目录；保留本轮两份正式
update 快照 `update.MndTa6`、`update.5KqtQj` 和 rollback 保护快照
`rollback.leCxpt`，全部历史备份也保留。业务服务健康、timer 匹配、透明 inactive。
本机测试和独验容器已删除，转发进程已停；逐字节核对归档后清理 108 个二进制/
源码副本，共 `392091808` 字节，四档、失败原件、独验与清理证明继续保留。
本批无运行源码变更，不重复本机 daily/full 或制造新 release。

该结果只关闭固定环境的正式版本升级/回滚闭环；原生 `network.sh` 不在
Docker bundle 内，不宣称该原生修复已由本次升级安装。未新增 arm64、IPv6、
新主机灾备、多机原生控制/WG、WARP 实账号、自然续期、正式原生 h3/CDN、
其它客户端或性能长稳证据，不解释旧 Vision/XHTTP/TUIC 失败；透明启用重启按要求不做，
整体计划仍未完成。

### 2026-10-26 正式 3.42.0 升级与重启后复核

在同一 Debian 13 amd64、普通 bridge、公网 IPv4 VPS 上，使用已独立验签的正式
`v3.42.0` 三件套执行 `3.41.8 → 3.42.0` 更新。活动 bundle ref 为
`489d16c9d1db77591daa36e2f47c645f6d057d90`，manifest SHA256 为
`99dab8c8739ad38467f3e8cd00353828596d2bb27f63b2850156822243db695a`，
Sigstore identity 为
`https://github.com/neil1123-vip/padm/.github/workflows/create_release.yml@refs/heads/main`。
运行中的 Xray、Nginx、ops 三镜像摘要分别核对为
`c2ea68d092cb583d7b076b542af67a9d42e6dd49a631083e7e33128f735c8b34`、
`86e64bdfc2e06bfea83239d9db3d60ed51f93d0b0de4b350cc282b7153d93eb0`、
`dd3841cf39713cc8762e12bd6debc48f3e6ce2edad10dfb9cb2c3fe2a4525e9a`。

随后完成整机重启，重启后 Docker active，`nginx`、`xray`、`subscription`
均为 `healthy`，`padm-docker validate` 返回 `0`，公网 HTTPS 返回 `200`，
续期 timer 保持 active。透明代理保持关闭：无 `net-transparent` 容器，
`host_integrations=[]`，未发现 TPROXY、REDIRECT 或 MARK 规则。

证据为 `.tmp-native-upgrade-3420-20261026/verification.json`。本轮只验证
正式升级与重启后的恢复，不重复 3.41.8 回滚；不新增 arm64、IPv6/双栈、
自然到期续期或透明启用重启矩阵证据，整体计划仍未完成。

### 2026-10-26 正式 SSH 专用来源补验

在正式 3.41.8/source=`e671328e` 的 Debian 13 amd64 上，新增短期专用
systemd sshd，仅显式监听 `23.185.168.63:22220`，管理 `22` 不变。
collector 初始不存在，通过正式 `fail2ban ssh enable` 自动创建 root `0700`
目录；未人工 chmod，补齐 10 月 18 日旧正式版本需人工修复目录的证据缺口。
其余配置、来源、运行器与 jail 均使用正式 bundle，不挂载当前未发布源码。

独立 Docker 客户端 Paramiko `3.5.1` 固定用户已核对的 ED25519 指纹，
4 次真实错误密码认证共触发 2 轮封禁。独立读取实际规则，核对唯一 INPUT
挂钩仅含目标 `/32`、端口 `22220`、NEW 与专用随机链，精确来源 DROP；
外部新建连接超时，正式解封后重连成功，管理 `22` 始终可新建连接。
第二轮封禁后停止专用来源服务，collector guard 撤销，jail exit=`0`
且未 OOM，owner state 删除，IPv4/IPv6 规则 `2102 ms` 内恢复基线。

正式停用后，规格 SHA256 与完整字节、业务/分享组/订阅/TLS/ACME/续期/
webroot 材料及 mode/uid/gid、两个 timer、source 全部匹配。三业务 healthy，
新增 collector/锁/jail 状态路径、专用 unit/监听/运行 collector 均已清理；
全部 33 份原有备份及新增 `configure.JljKFp`、`configure.xA6v7b` 保留。
最终 UTC `11:55:04`：load1=`0.08`、MemAvailable 约 `445 MiB`，
透明规格为空；不作性能或长稳结论。

断网容器独验原档、最终实物读回、客户端结果和 3 项合成越界规则负控通过。
私密归档 SHA256：
`a42db50675a521a0dcc3fa74d1342dc554d201a334ea9fb9fe0d3e1a5eb7a6b8`；
证据 `.tmp-native-ssh-3418-20261026/verification.json`。
首次本地 apt 因 cap-drop ALL 无法 setgroups/setuid，未操作 VPS；
改在依赖镜像安装，客户端仍禁用全部能力。矩阵及恢复已通过后，
封装 tar 因同目录创建输出而报 `file changed as we read it`，改用明确文件
归档并重新读回实物，未重跑矩阵。附加直连 TLS 探针 EOF，原探针未记录失败
SNI，不判定根因；既有不嗅探固定目标通道的严格 TLS/200、错误 SNI 拒绝均通过，
不把后续成功改写为直连通过。上述未完整运行及原脚本均保留。

归档下载核摘要后精确删除远端暂存；本机客户端、独验容器与转发均已停止清理，
复用 Paramiko 依赖镜像。无运行源码变化，不重复 daily/full 或制造 release。
仅关闭专用无存量会话、显式单监听、密码失败格式的原生 IPv4 子项；
arm64、IPv6、整机重启和任意 SSH 服务不由本轮证明，整体计划仍未完成。

### 2026-10-27 SSH 整机重启与 guard 轮换故障

正式 3.42.0/source=`489d16c9`、Debian 13 amd64、专用单监听 IPv4 `22220`：
真实错误密码触发精确 INPUT DROP，公网新连接超时，管理 `22` 始终可达。
仍封禁时整机重启，boot 从 `d3243e56-b911-4d88-b7bb-2fb44a94cda1`
变为 `8703c6d6-786a-4dd2-b4e2-78a7a9dd3b27`。三业务自动恢复 healthy，
旧 jail exit=`0`、`restart=no`，transient collector/guard/规则清退；
旧 owner 不被接管，status 拒绝，正式 CLI 停用可退役残留。严格公网 TLS/200
与续期 timer 通过，透明代理未启用。

重新启用返回成功，约 12 秒后 jail 因 `unsafe SSH collector guard` 清退，
而 collector 仍 active、runtime check=`0`、guard age=`792 ms`。
源码及确定性旧实现回归确认：每秒原子轮换与读取竞态会让旧 inode 的
`st_nlink=0`，或只改变 ctime，被误判为不安全文件。修复已在两个读取端
限定重读一次；正常轮换通过，连续轮换、同 inode 修改、权限及硬链接仍拒绝。
本地 `docker-ssh-preflight` 与 `docker-fail2ban-ownership` 均通过；
正式可信包包含修复后仍须补原生重新启用、封禁和解封，当前不宣称恢复通过。

失败矩阵及断网独验：
`.tmp-native-ssh-reboot-3420-20261027/verification.json`；
私密归档 SHA256=`a1b869022b69803b5cd883e69baefa6b1f772353a0aeab565dbe4128f039f76c`。
正式 CLI 已恢复原规格字节、材料与权限、timer 和所有备份；最终三业务
healthy、严格公网 TLS/200。测试 unit/collector/net 路径、远端暂存和独立
客户端已清；未扩大任意 SSH、arm64、IPv6、长稳或透明代理范围。

### 2026-10-27 guard 修复发布与成员采样竞态

签名修复 `888b62e4` 已进入正式 `3.42.1`，发布提交 `e9b24415`；
流水线 `40363599105` 的 32 项任务成功，三件套独立验签及 300 个包内源码
核对通过，仅 net 镜像重建。VPS 用正式 CLI 从 3.42.0 升级，材料权限和
timer 保持。零人工 chmod 重新启用后，guard 连续 `25408 ms`、20 次 runtime
检查健康，首轮真实错误认证、精确 INPUT DROP、公网超时与解封恢复通过。

第二轮认证子进程自然退出时，collector 报
`SSH unit 的 cgroup 成员在核验期间变化`，返回 15 并删除 guard；
jail 随后正常退出 0。原子 guard 修复有效，但本轮矩阵仍按失败保留。
成员采样修复只对可证明的非 MainPID 进出完整重取证一次，固定原 unit、
master 及已见监听，连续变化、主进程/代次、namespace、权限、额外监听
继续拒绝。旧实现 6 项红测，修复 `docker-ssh-preflight -Jobs 2`
入口 `5569 ms` 通过；可信 bundle 发布及原生复验仍待完成。

正式恢复、清理和实物读回通过，原规格字节、材料权限、timer、全部备份保持，
三业务 healthy、公网严格 TLS/200，测试 unit/collector/net 路径、客户端与
远端暂存已清。断网独验 `.tmp-native-ssh-guard-close-20261027/verification.json`；
私密归档 SHA256：
`a5118709229da0ce40f292f283e818baa46001732a7ee5286a46272525a45e95`。
沿用已实测 boot=`8703c6d6-786a-4dd2-b4e2-78a7a9dd3b27`，没有在 3.42.1
再次重启；不扩大任意 SSH、arm64、IPv6、透明或长稳范围，整体计划未完成。

### 2026-10-27 成员采样修复正式原生闭环

签名提交 `ef5194eb` 已发布正式 `3.42.2`/source=`4aaa9158`；
流水线 `40369406371` 30 项成功、1 项 Smoke 条件跳过。三件套摘要、
Sigstore 身份及全部 300 个包内源码独验通过，五组镜像全部复用 3.42.1。
正式 `3.42.1 → 3.42.2` 升级保持材料权限、调度、业务规格和 boot。

专用 IPv4 单监听 22220、管理 22 独立，正式 CLI 零人工 chmod 重新启用。
四次真实错误密码完成两轮封禁，各次精确 INPUT DROP 与公网超时均通过；
首轮正式 unban 后恢复，第二轮封禁后连续 `26180 ms`、21 次 runtime
核验健康。停止来源后 jail 正常退出 0、guard 和 owner state 清退、
IPv4/IPv6 规则回到基线；再次启动测试来源后公网可连接，管理 22 始终可达。

正式恢复、清理、实物读回和断网独验通过，原规格字节、材料权限、timer、
全部备份保持；三业务 healthy、严格公网 TLS/200、透明关闭。
测试 unit/collector/net 路径、客户端及远端暂存均清理。证据
`.tmp-native-ssh-members-close-20261027/verification.json`；
私密归档 SHA256：
`cb5ee5a6c1c6ebfb47c7c741913588ae6396b8b2975e4dddd117cae603deb253`。
两版失败原件保留；复用既有真实 boot，本版未再次重启。
本节只关闭可信包的专用来源 IPv4 双轮恢复子项，任意 SSH、arm64、
IPv6、透明启用和整体计划仍未完成。

### 2026-10-27 正式 WS IPv4 端口事务有限补验

Debian 13 原生 amd64、正式 `3.42.2`/source=`4aaa9158`，单直接 WS、
单公开端口与单 jail。正确 TLS SNI、错误 HTTP Host 产生 3 次真实 404
并封禁。错误来源拒绝、暂停候选 Nginx 的真实健康失败均回滚旧端口；
正常 `443 → 25443` 迁移保留 SQLite inode 和封禁记录。
4 次公网受封禁请求均超时、DROP 计数增加、请求 nonce 未进入 Nginx；
宿主旧监听、旧 hook、旧 owner 清退，6 个 fresh nonce、4 份 SQLite 实物。
固定现有 HTTP CONNECT 路径，两端口抓包确认同一公网来源，
未豁免正式来源校验；用正式 unban 清理检测窗口内旧日志造成的基线重封。

原编排保留 `exit 1`：旧端口探针漏接实际 TLS handshake timeout，
补充分类后未重跑整轮。后续独验精确绑定原始 Codex 工具调用/输出、
同轮 migration nonce、`old-closed/443`、宿主清退及恢复正控
`recovery-client.json`。只证明固定 HTTP CONNECT 路径下，旧 HTTPS
请求未完成 TLS；未定位超时发生在上游，未观察公网 TCP 拒绝，
未生成虚假的旧端口成功记录，也不称整轮 runner 通过。

断网独验通过，trigger、final-target、challenge-tls、database、
restore、tool-observation 六项实物篡改全部拒绝。
原规格字节、材料权限、timer、累计及备份恢复，管理 22 可达，
三业务 healthy；远端暂存、两个本轮容器及本地控制归档清理，
25443 无监听，清场后严格公网 TLS/443/200 再次通过，透明保持关闭。
失败原件与冻结脚本保留，证据
`.tmp-native-ws-migration-20261027/verification.json`、
`negative-verification.json`、`remote-cleanup.json`、`post-cleanup-client.json`；
原生原件 SHA256：
`0468ec8da72ffef07eeb15408e61caded7694cb9d5c0ca9dbc032c5cdc0ecbd9`；
完整归档 SHA256：
`89b381c5bc138338abeda0fbf65040d677143f11e3009a04a5bf6d9ad2cfde64`。
本节只关闭单 WS IPv4 迁移与失败恢复的有限事务子项；原编排整轮成功、
公网旧端口 TCP 拒绝、原生 IPv6/arm64、透明启用和整体计划仍未完成。

### 2026-10-26 当前源码 TUN/ICMP 定向补验

本轮针对未提交源码在 Docker Desktop Linux/amd64 中复用
`padm-regression:local-c7b9508f3f52687088ed089057fdfdd5931df0026935e9c57def4e07674e26fd`
完成三个定向 selector，均为实际执行、非缓存结果：

- `docker-tun-management`：`36.366 s`，`exit=0`；
  `tun-diagnose` 关闭态只读、核心身份/能力/组范围采样、容器重启漂移、
  旧 TUN 模板兼容、候选生成/恢复和 3 项不支持路由拒绝通过。
- `docker-tun-real`：`60.664 s`，`exit=0`；
  固定 `sing-box 1.14.4` 镜像摘要与 `versions.lock` 一致，新增 nft 动态计数
  对照拒绝结构变化；隔离 veth 目标上的 IPv4 Echo 在 `ping_group_range`
  允许时经 `direct` 往返，范围拒绝时无 wire 回包，TCP/UDP 仍成功；
  诊断不发包、不改变 owner 或网络资源，异常退出仍拒绝并保留现场。
- `docker-menu-tun`：`2.115 s`，`exit=0`；TUN 菜单入口回归通过。

真实流量证据目录分别为
`.tmp-regression-docker-0ec23e4d68b047a4bec64db132870170/`、
`.tmp-regression-docker-8984671b397542209b77a53aa10cd1aa/`、
`.tmp-regression-docker-86b7c4ed45394bb0a5e547e9467e395e/`；三次
`cache_hit=false`，源码摘要均为
`197CB359DB0BDAE7FBE4A8D2FF90988EB0021A7CB32C188ED1328B72D44CBE2F`。
本轮不增加 `NET_RAW`、不修改宿主 sysctl，不启用透明代理。

随后补验权限允许但远端只丢弃 Echo 的场景：`docker-tun-real` 三阶段实际执行
`70.779 s`，`exit=0`、`cache_hit=false`。正常阶段 wire 请求/回复与应用回复
各 `1`；远端过滤阶段 TUN 与 wire 请求各 `1`，目标丢弃计数 `1`，
wire/应用回复均为 `0`；核心缺权阶段 TUN 请求 `1`、wire 请求/回复及应用回复
均为 `0`。三阶段 TCP/UDP 均往返成功，诊断保持只读，清理后网络基线恢复。
这也验证了组范围允许不会被诊断为 Echo 已可达，未使用本地合成回复。
证据 `.tmp-regression-docker-75fa27b0f5224516bc34e12780f44bd8/`，
源码摘要 `5AD08B3349BCAE0AF8DCC2469070127A3D9AF3C82A06AD0E8B133507348EAC1B`。

该结果只关闭当前源码的隔离 Linux/amd64 TUN/IPv4 Echo 子项；原生宿主、
arm64、公网、IPv6/traceroute/PMTU、整机重启及透明启用矩阵仍未完成，
不把 Echo 直连结果外推为代理隧道或其它协议健康，整体计划继续未完成。

### 2026-10-26 TUN/ICMP 发布包独验

功能提交 `7f12133f` 对应的既有自动 Release 流水线 `40321534513` 已完成，
`30` 项成功、`1` 项 Smoke 条件跳过；下载 `docker-contracts-fast-rest` 原始日志，
确认 `docker-tun-icmp-ok` 和 `docker-tun-management-ok` 均实际出现。
发布 `v3.42.0` 的提交为 `489d16c9`，相对功能提交仅修改两个版本文件。

本轮只读下载公开三件套，复用官方 Cosign `v3.0.6` 镜像在隔离 Linux 容器验签，
固定 `create_release.yml@refs/heads/main` 身份和 GitHub Actions OIDC issuer，
结果 `Verified OK`。三个资产 SHA256 与 GitHub 发布记录一致，控制包摘要也与
已验签 manifest 绑定；包内 `300` 个源码文件逐一匹配发布提交的 Git blob，
唯一生成文件为 `docker/contracts/bundle.paths`。新诊断入口、ICMP 路由生成器
和两项 ICMP 测试文件均在包内，没有遗漏发布依赖。

五组镜像的 index、amd64 和 arm64 摘要与已独验的 `3.41.8` 相同，
本轮未重复拉取或运行镜像；这不新增原生宿主、arm64 或公网 ICMP 的运行证据。
证据 `.tmp-tun-icmp-release-3420-20261026/verification.json`、
`cosign-verify.log` 和 `contracts-fast-rest.log`。GH CLI 首次取日志被本机缓存目录
权限拒绝，提权只读重取成功；未操作 VPS、未发起新的发布，整体计划仍未完成。
