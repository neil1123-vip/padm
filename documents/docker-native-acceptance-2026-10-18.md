# Debian 13 原生与公网验收

验收日期：2026-10-18–19（北京时间）。本阶段补原生 amd64 证据，不代表整体计划完成。

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
后续须先核对现场，再精确撤销或卸载，禁止自动拉起业务来验证事故。

随后按精确撤销路径完成现场收口。2026-10-18 19:21 CST 经 SSH 只读复核：
负载 `0.00/0.00/0.00`、Swap 使用 `0 MiB`，`nginx/xray/subscription` 均 healthy；
`net-transparent` 退出 `0`、`restart=no`，Compose profile 仅为
`core-xray,nginx,subscription`，`config/spec.json` 的 `host_integrations` 为空，
`padm-native-target4.service` 已不存在，`padm-docker-traffic.timer` 为 disabled/inactive。
本轮未在该 VPS 部署当前源码或重新启用透明代理；域名 HTTPS 与业务恢复状态保持通过。

## 当前未决

- 原生 arm64 安装、升级、回滚、重启、卸载及客户端生命周期：缺少原生 arm64 主机，不能用
  Buildx 或 amd64 仿真替代。
- 隔离 TProxy/TUN 启停、失败恢复、整机重启和真实流量：当前 VPS 已关闭
  `net-transparent`，事故后不再在同一实例重启透明代理。
- 完整卸载与 purge：当前只完成透明 orphan 清理，正式业务部署仍未 purge。
- 公网双栈端口跳跃、旧连接排空和自动恢复：当前 VPS 无公网 IPv6，不能判定通过。
- 新原生主机同架构 v3 空目标灾备与业务恢复：缺少可销毁的同架构第二主机。
- webroot/ALPN 的公网 CA 候选签发、候选校验与服务恢复已通过；正式 CLI 换证及回滚仍待验。
  WARP 真实账号/公网出口和 Reality 共存专项保持 deferred；当前 WS-only 部署不能通过
  协议新增 CLI 创建首个 Reality，不能靠手写规格绕过支持门禁。
- HTTP relay 原生 IPv4 到公网 HTTPS 已通过，旧 EOF 已定位为测试来源误写；
  外部客户端的公网入口仍超时或 CONNECT 中断，未标记完整验收通过。
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
不恢复透明代理或扩大原有来源范围。

### HTTP relay 与公网 CA 集中补验

HTTP relay 的旧测试名单写为 `172.17.0.1/32`，实际受管网桥网关为 `172.18.0.1`。
修正为实际网关后，宿主回环经受管 `36080` 发布端口访问 `api.ipify.org`、
`www.debian.org`、`example.com`，三次真实 HTTPS 证书校验均成功、返回 200。
未允许的 VPS 公网地址访问同一入口时，CONNECT 返回 200，随后 curl 报 TLS 失败；
Xray 同时记录真实来源及 `padm-relay-http -> blocked`。这证明旧 EOF 可以由来源拒绝触发，
不能据此放宽为全网允许。外部客户端两次网络检查仍为超时或 CONNECT 中断，
未形成允许来源成功证据。测试后关闭 relay，原规格 SHA256 恢复。

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
本轮远端临时目录、输入凭据和 curl 配置已删除，SSH 会话已退出。

本轮小证据保留在 `.tmp-vps-native-20261018/`；
原始签名输入摘要与各阶段 inspect、CLI 日志用于交叉核对。
账号、客户端私密配置、私钥和 DNS/VPS 凭据不进入本文件或提交。
