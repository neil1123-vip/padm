# Debian 13 原生与公网验收

验收日期：2026-10-18–20（北京时间）。本阶段补原生 amd64 证据，不代表整体计划完成。

**当前现场（2026-10-20）**：3.41.2 已正式发布并验签升级，依赖路径表与 ACME 私密诊断均进入运行 bundle；
3.41.1 的正式 restart、整机重启、严格 HTTPS 和外部 WS 正反例通过，透明代理保持关闭。
正式 webroot/ALPN `acme issue` 各取得新证书并完成在线换证；第三次申请提前失败，
本轮不再签发。3.41.1 缓存 ACME 导出后真实消费失败恢复通过，正式 issue/renew 全链仍缺；
原业务、材料字节/权限和定时器已恢复；
本轮临时资源及私密材料清理结果见末节，不把两条签发路径通过计作整体完成。

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
- webroot/ALPN 的独立 staging 公网挑战、正式 `tls install` 换证与 Nginx 失败回滚已通过；
  3.41 正式 `acme issue` 两条签发安装路径通过，本轮 fresh 公网挑战未核实，
  第三次申请在候选阶段失败，未覆盖正式 ACME 消费失败回滚。
  WARP 仍缺真实账号/公网出口。Reality 已通过生产重装生成，受管/桥接同机流量、
  75 秒连接和外部 WS 通过；宿主回环 Vision 正反例、75.001 秒同连接与严格网站
  HTTPS 通过；本批外部 Vision 三次正反例通过，但不替代正式发布及完整恢复验收。
- HTTP relay 原生外部 IPv4 验收通过；公网 IPv6 不在本次通过范围内。
- 自然到期真实续期：当前登记续期约为 `2026-12-17 08:03:22 CST`，证书到期约为
  `2027-01-16 04:29:07 CST`；调度 no-op 不算换证。
- 3.41.1 已正式发布并完成原生验签升级，新增依赖路径表已生效；
  后续 ACME 失败私密诊断修复尚未进入正式包。
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
均 reset，同机通过但服务端未见对应 accepted 请求，根因未确定，不能计为公网通过。
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
