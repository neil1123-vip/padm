# Docker 版使用指南

[返回 README](../README.md#docker-版) · [系统要求](../README.md#docker-版要求) · [功能对照表](docker-feature-matrix.md)

[安装](#安装) · [五个镜像](#五个镜像) · [状态与日常控制](#状态与日常控制) · [可信发布输入](#可信发布输入) · [灾备归档](#灾备归档) · [用户流量与额度](#用户流量与额度) · [更新](#更新) · [回滚](#回滚) · [卸载](#卸载)

Docker 版用于把核心、Nginx、订阅和运维任务与宿主系统隔离。它和原生版是两条独立且互斥的入口：原生版使用 `install.sh` / `padm`，Docker 版使用 `install-docker.sh` / `padm-docker`；不会自动混装、迁移或接管另一种部署。

## 安装

Docker 入口会安装并校验 Docker 控制 bundle；缺少 Docker 时，`install` 会在明确确认后引导安装 Docker Engine 和 Compose CLI 插件（v2 及以上）。它不在生产机执行 `docker build`，也不会把 Xray、sing-box、Nginx 或其它业务依赖安装到宿主机。镜像由本仓库 CI 预构建并发布，首次部署可在菜单中完成：

```bash
wget -O /root/install-docker.sh "https://raw.githubusercontent.com/neil1123-vip/padm/main/install-docker.sh" && chmod 700 /root/install-docker.sh && /root/install-docker.sh install
```

交互终端安装成功后自动进入菜单；已安装后直接运行 `padm-docker` 或
`padm-docker menu` 可查看状态、启停重启和日志，选择“安装与重装 → 首次配置”收集核心、协议、地址和证书。
当前向导支持 Xray Reality Vision/XHTTP/gRPC、sing-box Reality Vision/gRPC/Hysteria2/AnyTLS/NaiveProxy/Shadowsocks/TUIC，以及两核心 direct Trojan、VMess HTTPUpgrade TLS，
以及 Xray VLESS WS TLS、VMess WS TLS、VLESS/Trojan gRPC TLS、VLESS TCP TLS Vision、Trojan TLS fallback 或 Reality Vision + WS TLS；
已有部署可从同一菜单选择重装，或改用下述保身份编辑入口。
16 个公开协议的管理状态已按声明的核心和组合更新为 `supported`；
新增、编辑、复制、保身份重建、删除、分享和失败恢复均有命令入口。
公网、arm64 和完整宿主生命周期仍单独验收，详见[功能对照表](docker-feature-matrix.md#状态定义)。
`install --no-menu` 禁止安装后自动进入菜单；无参数非交互调用只显示帮助，
不会安装 Docker、下载 bundle 或初始化状态，现有显式 CLI 命令保持可用。

首页采用与原生版相同的 8 类入口和共享菜单样式：

| 编号 | 菜单 | 常用入口 |
| --- | --- | --- |
| `1` | 安装与重装 | 首次配置、重新选择核心与协议、完整规格重装 |
| `2` | 订阅与用户 | `1` 账号、`2` 订阅、`3` 流量额度、`4` 控制连接、`5` 业务备份 |
| `3` | 协议与入口 | REALITY、XHTTP、Hysteria2、TUIC、额外端口、CDN；`9` 入口高级管理 |
| `4` | 站点与证书 | `1` 传统 TLS fallback 与站点、`2` 本机 TLS 证书 |
| `5` | 路由与访问控制 | `1` 分流工具、`2` BT、`3` 访问控制 |
| `6` | 核心与服务 | 状态、启停、重启、日志、校验；`7` 升级评估、`8` Geo、`9` 配置编辑 |
| `7` | 系统与脚本 | `1` 原有发布包维护、`2` 安装状态、`3` Fail2ban |
| `8` | 高级/危险操作 | `1` 保留数据卸载、`2` VLESS Encryption 实验 |

专项页面保留原有操作编号：旧协议菜单 `9` 迁至 `3 → 9`，旧完整路由菜单 `17`
迁至 `5 → 1 → 9`，旧服务维护菜单 `18` 迁至 `7 → 1`。
SOCKS5 入站在 `5 → 1 → 3 → 2` 显示不可用及固定核心的鉴权、来源限制原因。
核心升级保持两版各自原有机制，Docker 继续使用验签发布包整包升级与回滚。
共享样式同时覆盖菜单、首次配置、TLS 管理和配置编辑中的标题、列表及摘要边框。
专项操作编号、输入顺序、默认值、凭据隐藏、确认和事务保持原样，非交互 `--preview`
输出不变；功能支持边界和原生宿主验收要求保持。

```bash
padm-docker setup
padm-docker validate
padm-docker status
```

向导最终确认后才验签发布、生成 UUID/Reality 参数/订阅 token，并准备候选配置与证书。
没有 `cosign` 时停止，不自动从未验证来源安装验证器，也不能跳过验签。
WS/HTTPUpgrade/gRPC TLS、传统 TLS fallback、Hysteria2、AnyTLS、NaiveProxy、TUIC 和 direct Trojan 可选择已有受管证书、导入完整证书链与私钥，或使用 DNS-01/HTTP-01 standalone/TLS-ALPN-01；
私钥和 DNS 凭据必须是仅持有者可读的普通文件。订阅发布要求至少一个 Nginx TLS `21–25` 或 Xray TLS fallback `27/29` 入口和同域受管证书，可仅使用 sing-box HTTPUpgrade `23`。
发布复用已有 Nginx 和 subscription 服务，不新增独立发布域名、证书或服务；
没有协议 `21` 时启用发布需要 bundle 能力 `x-padm-subscription-nginx-tls`；含 `27/29` 的发布还需要 `x-padm-subscription-fallback-tls`，关闭发布的旧子集保持兼容。
fallback 的 HTTP/1.1 和 HTTP/2 后端均提供相同订阅路由，不新增公开端口或 Nginx TLS 私钥挂载。
分享组 HTTPS 链接使用 `core.protocols` 中首个适用入口的实际公开端口，`443` 省略；
Reality 共存选中的 website 入口实际公开端口为 `443`。4A.7 已通过隔离 amd64 的
22/23/24/25 HTTPS 主/组订阅下载、严格 TLS 及双族 TCP/UDP 验收；公网及原生双架构另验。
菜单 `2 → 2 → 10/11` 或 `subscription content --base` / `subscription links --base`
直接输出部署主订阅内容或 HTTPS 链接。内容复用现有节点生成器，包含自用及启用账号，
即使关闭发布或只有 Reality 入口仍可本地读取；HTTPS 链接要求已启用发布。
查询不创建分享组或修改发布文件，内容和链接含凭据，仅交给获授权的客户端。
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
认证超时、心跳和 0-RTT 可在 `协议与入口 → 5. Tuic 管理` 或编辑菜单 `14` 管理，默认 `3s`、`10s`、关闭 0-RTT。
`tuic://` 使用 `h3`、原生 UDP 中继及严格 TLS 校验；单个双族入口可使用下述范围转发管理。
Direct Trojan 在 Xray 或 sing-box 首配中选 `11`，使用 TCP/TLS 双栈入口，不经过 Nginx；
UUID 作为密码及流量账号，可输出 `trojan://` 链接。服务器地址可与 TLS 域名不同，链接保留独立 SNI。
TLS 域名与凭据冻结；支持通用字段编辑、跨核心复制和删除，不包含 fallback 或独立 HTTPS 发布。
VMess WS TLS 在 Xray 首配中选 `12`，复用 Nginx、受管 TLS 和 UUID 流量账号；
固定 `alterId=0`，可输出标准 Base64 `vmess://` 链接。协议 22 可与 VLESS WS TLS 共用 Nginx，
也可复用自身同域 Nginx TLS 入口发布 HTTPS 订阅；不接受 sing-box、宿主集成或跨核心复制。
VMess HTTPUpgrade TLS 在 Xray 或 sing-box 首配中选 `13`，复用 Nginx 和受管 TLS；
使用独立 `httpupgrade` 字段、固定 `alterId=0`，链接的 `net=httpupgrade`，路径为 `/` 加受管路径段，不附加 `ws`。
支持路径编辑和跨核心复制，同一 UUID 共享流量及额度；两核心均可复用自身同域 Nginx TLS 入口发布 HTTPS 订阅，不接受宿主集成。
VLESS/Trojan gRPC TLS 在 Xray 首配中分别选 `14`/`15`，复用 Nginx HTTP/2、受管 TLS 和 UUID 流量账号；
使用独立 `grpc_tls` 字段，服务名为 1–64 位字母、数字、下划线或连字符，编辑菜单 `12` 可修改。
支持通用字段编辑、Xray 内复制/删除及 `vless://`/`trojan://` 链接；不接受 sing-box、宿主集成或 fallback。
两类协议均可复用自身同域 Nginx TLS 入口发布 HTTPS 订阅，无须包含协议 `21`。

Docker `协议与入口 → 4. Hysteria2 管理` 与 `5. Tuic 管理` 为已有 v3
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
沿用预览、确认、发布和失败恢复；宿主集成组合仍拒绝，TUIC 范围转发见下文。

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
当前原生菜单的四项 `sc*` 参数已覆盖。正式 `3.41.5` 在 Debian 13 amd64 普通
bridge 上，固定 Xray `26.3.27` / Mihomo `v1.19.28` 的 packet-up、stream-up
各通过 1 MiB、8 MiB 双向 SHA256 完整性校验；
16 KiB 仅为 packet-up 单次 POST 正文上限，不限制 stream-up 正文。
2026-10-25 正式 `3.41.6`、同一 amd64/IPv4/bridge 环境，固定 Xray 的原始
抓包与 TLS keylog 独立解密通过：packet-up 的 1 MiB、8 MiB、60 秒观察分别
实测 `65/513/206` 个 POST，stream-up 分别实测 `1/1/1`；正例均为双向
END_STREAM 和 HTTP `200`，错误 UUID 的原点事务零到达。两模式各在同一业务
连接完成 12 次往返，观察约 60 秒、实际业务跨度分别约 56.017/56.026 秒。
上述正式计数仅为固定 Xray 生产组合，不证明吞吐或长时稳定性。2026-10-26
另在本地 Docker Linux 对固定 Xray Reality/TLS、Mihomo Reality 的 packet-up/
stream-up 各跑 1 MiB 真实回显；各 packet-up 计得 65 个 POST，各 stream-up
计得 1 个 POST，并验证 Mihomo 取消生命周期及解析器的合成服务端先 FIN 负控。
这不是 VPS/公网验收；正式原生 h3/CDN 和其它环境仍待补。详细范围与
证据见[原生验收记录](docker-native-acceptance-2026-10-18.md)。

VLESS TCP TLS Vision、Trojan TCP TLS fallback 在 Xray 首配中分别选 `16`/`17`。
Xray 直接终止 TLS，未命中协议的 HTTP/1.1 和 HTTP/2 请求通过 PROXY v1 回落到 Nginx；
`fallback_tls` 固定域名及两个内部端口，默认 `31300`/`31302`，同核复制可共享后端。
默认首页不写入站点目录，已有 `/etc/padm-docker/data/static/index.html` 优先；
支持通用字段编辑、同核复制/删除与链接；默认页、静态目录、302 和 ALPN 已支持事务管理，4A.9 可复用自身 fallback 发布 HTTPS 订阅，宿主集成与独立发布域名仍未开放。

Docker 菜单 `4 → 1. 传统 TLS fallback 维护` 管理已有 Nginx TLS 入口 `21–25`、fallback `27`/`29`
或 Hysteria2 的静态网页：

```bash
padm-docker edit --site-template notes --preview
padm-docker edit --site-template notes --site-title "My Notes" --preview
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

菜单 `4 → 1 → 8. 内置静态站点` 可选择 `notes`、`photos` 或 `docs`。内置主题仅适用于
已有 v3 Nginx TLS `21–25`（含纯/混合 sing-box `23`）、Xray fallback `27/29`
或 sing-box Hysteria2；其它不提供网站的 Reality 入口可共存。选主题后可输入站名，
回车使用主题默认值，`0` 返回；CLI `--site-title` 仅配合 `--site-template`，
接受 2–60 个字符，拒绝纯空白和控制字符，HTML 特殊字符转义后写入网页。主题从验签后的
控制包复制，随包清单和资源完整性校验失败即拒绝；生成后只保存普通 `site.mode=static`，
不保存主题身份或站名，之后需改名时重新选择模板；旧控制包的默认页、静态目录和 302 行为保持。

Hysteria2 先通过上面的模板或目录命令发布网页，再在 `协议与入口 → 4. Hysteria2 管理`
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

2026-10-24，正式 `3.41.5` 在 Debian 13 amd64 普通 bridge、公网 IPv4 TCP 上，
完成 `27/29` 逆序、仅 HTTP/1.1、推荐顺序，以及三套主题、特殊站名和 302 跳转。
13 阶段共 57 正例、35 拒绝，主/组 HTTPS 订阅、88 项 ALPN 与资源正文摘要均通过独立核验，
原 WS、材料权限和调度恢复后已精确清理。该证据不包含 IPv6、UDP、重启或其它客户端；
完整支持边界见[原生验收记录](docker-native-acceptance-2026-10-18.md)。

同日正式 `3.41.6` 已在该 VPS 经 Cosign 验签和正式 `update` 升级。
升级前后 WS 原生客户端共 2 正例、2 拒绝通过，URI、业务材料字节与权限、
调度及累计保持；仅规格的 release/images 改变，保留 `update.SR95Tw` 回滚点。
本次运行包含分享组合法未排序列表修复，不代表其余环境验收完成。

正式 `3.41.6` 随后完成 TLS 四阶段限定验收：原生客户端 13 正/8 拒绝，
HTTPUpgrade 手工对照 6 正/3 拒绝，主/组订阅 4 次下载及 4 次错 token 拒绝，
并验证合法未排序的七入口分享组。固定 Mihomo `v1.19.28` 的协议 23 原生
URI 导入仍未通过，已用固定源码和同一二进制的三个断网假身份对照定位：
客户端保留 `network=httpupgrade`，但仅 `network=ws` 进入升级分支，实际回落到
普通 TCP/TLS。正式 URI 保持不变，手工对照不计入原生成功；具体边界见上述验收记录。

2026-10-25 同包再通过固定 Xray `26.3.27/d2758a0` 的七入口显式转换互通：
原 WS → 七入口共存 → 纯 sing-box 23 → 恢复 WS，共 19 正/11 错认证拒绝，
另有主组 4 次严格 HTTPS 下载/4 次错 token 404、2 次组业务及 11 次错 SNI 拒绝。
正式 URI 来自实际下载正文，只映射连接地址/端口；四档和 4 项实物篡改负控
独验通过，原材料权限、调度及累计保持，测试资源已清。
这是 URI→Xray 配置转换互通，不代表 Xray 原生 URI 导入，也不改变上述
Mihomo HTTPUpgrade 限制；透明保持关闭，其它环境仍待验。

同包路由原 WS 与 15 个业务阶段独验取得 50 正/31 拒绝，覆盖两核心
选择性/全局 SOCKS5 TCP 和纯 sing-box 解析后阻断的认证拒绝、上游不可用及恢复。
收尾因 Docker veth 地址变化断言失败，整轮仍记失败；原材料与调度恢复、
独立 WS 1 正/1 拒绝及网站严格 TLS/200 已另验，测试资源已精确清理。

同包另完成纯 sing-box 路由与发布共存补验：五阶段共 8 正/7 拒绝
（其中 HTTPUpgrade 手工对照 1 正/1 拒绝），主/组各一次严格 HTTPS 下载及错 token
拒绝，五阶段默认页正文与实际 Nginx inline return 一致。实际客户端材料、原请求链、
恢复及精确清理已独验；不改变旧失败，不证明系统解析器回退陷阱或原生 HTTPUpgrade 导入。

系统解析器回退陷阱另经同包四阶段独验通过，共 6 正/4 拒绝。两个随机域名先经
实际容器 hosts 完成业务，再仅添加 exact DNS 选择器；SERVFAIL 与丢包均由核心
明确结束，未回退系统解析、未到达原点，未用客户端超时冒充拒绝。未匹配域名在
两次拒绝前后均成功，容器 hosts 与宿主解析配置已恢复；前三轮取证或顺序失败保留。
该证据只覆盖固定客户端、IPv4 TCP，不扩大 UDP、重启或其它环境的支持范围。

UDP 定向补验另通过四阶段 9 正/7 拒绝，覆盖 TUIC、SS2022 基口/默认别名、
删除别名及 WS 恢复，11 个有效 UDP nonce 各一次、3 个拒绝 nonce 零到达。
22 份实际客户端配置/URI 和运行二进制独验一致，原材料与调度恢复、测试资源已清。
此前失败归档保留；本轮不重复 Hy2 探针，不证明自动跳跃、IPv6 或重启。

路由与 UDP 随后合并完成一次真实 VPS 重启：原 WS、重启前、重启后、
恢复 WS 四阶段共 14 正/10 拒绝，纯 sing-box 的 hosts/DNS、解析后 IP 阻断、
认证 SOCKS5 TCP 路由及 TUIC、SS2022 基口/默认别名 IPv4 UDP 自然恢复。
同一组受管容器身份与 boot ID 改变已核，6 个 TCP 原点 nonce 和 18 个有效
UDP nonce 各一次，6 个拒绝 UDP nonce 零到达；24 份独立抓包及四档断网独验、
10 项实物篡改负控通过。原材料、调度及 WS 已恢复，本轮测试资源已清。
前三轮失败原档保留；透明始终关闭，不证明透明启用重启、SOCKS UDP、
IPv6、自动跳跃、其它客户端或整体计划完成。

完整规格保存于 `/etc/padm-docker/config/spec.json`，由 root 持有、权限 `0600`；
取消不提交，配置失败恢复旧规格、证书及 ACME 状态。该文件含秘密，不应打印或公开。

Docker 菜单 `5 → 1 → 3 → 1 → 1` 提供认证 SOCKS5 TCP 全局或域名分流直接录入，
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
菜单 `5 → 1 → 3 → 1` 的 `34/35/36` 和 `--socks5-domains-add/remove/replace` 管理已有非空域名名单；
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

菜单 `5 → 1` 的 `4. DNS 覆盖` 和 `5. DNS/hosts 覆盖` 提供核心内 DNS 分流和精确 hosts 覆盖。两者可独立使用，也可与 SOCKS5 共存；
只改变客户端直连域名目标的解析，不改宿主 DNS、路由、防火墙或公开监听。
DNS 私有 JSON 示例为 `{"server":"192.0.2.53","port":53,"domains":["domain:example.net"]}`，
仅接受字面 IPv4/IPv6 UDP 服务器，`domains` 必须包含 1–256 条已规范化的
`full:`、`domain:`、`keyword:` 或 `geosite:` 规则，各类为 OR；本阶段不提供全局 DNS、DoH 或 DoT。
菜单 `5 → 1 → 4 → 6` 可直接输入服务器 IP、端口（留空默认 `53`）和域名规则 CSV，
或使用 `--dns-rules <IP> <端口> <CSV>`；CSV 规范化与 Direct/Block 相同。
此操作创建或整组替换 DNS 分流，保留 `--dns` 私有 JSON CLI 和其它路由子项。
菜单 `5 → 1 → 4` 的 `28/29` 与 `--dns-domains-add/--dns-domains-remove <CSV>` 可增删已有
DNS 分流的域名名单，保留原服务器和端口。追加保留历史顺序并去重，合并后最多 256 条；
删除按完整规范化规则匹配，任一缺项整次拒绝，删空关闭该 DNS 分流并保留其它路由。
未启用 DNS 时增删明确拒绝；重复追加仍经过确认事务，可能更新回滚元数据。
菜单 `5 → 1 → 4 → 41`、`5 → 1 → 3 → 1 → 42` 与 `edit --dns-upstream <IP> <端口>` /
`--socks5-upstream <IP> <端口>` 可修改已有上游，保留域名名单、SOCKS5 凭据与其它配置。
地址沿用可路由字面 IPv4/IPv6 合同并保留原文；端口显式填写 `1–65535`，没有缺省值，
CLI 中的前导零按十进制处理。未启用或地址和端口均未变化返回 `15`；
预览、唯一确认、失败及信号恢复沿用原编辑事务，菜单空值、`0` 或 EOF 取消。
hosts 私有 JSON 示例为 `{"exact.example.net":"192.0.2.10"}`，接受 1–256 个小写精确域名，
每个域名对应一个可路由字面 IPv4/IPv6；不支持 hosts 后缀、关键字或分类匹配。
地址示例不可直接用作服务器；文件安全要求与 SOCKS5 输入相同。
菜单 `5 → 1 → 5 → 37` 与 `edit --hosts-replace <已有精确 FQDN> <新单字面 IP>` 可替换已有
hosts 的一个地址，不新增、删除或批量编辑映射。域名只将 ASCII 字母转小写，不去空白；
IP 保留原文，包括 IPv6 大小写和写法。空白、末尾换行、CSV、域名规则前缀或非法地址返回 `2`；
缺键、未启用 hosts 或地址原文同值返回 `15`。只豁免目标键的值，其它 hosts、路由和完整配置冻结，
分享 URI、订阅及累计流量保持；预览、确认和健康失败/信号恢复复用原事务。
菜单先显示状态，状态失败不读输入，空值、`0` 或 EOF 取消；独立 CLI 只确认一次。
原 `--hosts <私有 JSON>` 整组入口保持，不新增 schema、marker、权限或状态。
这是有限管理增强，不代表原生 hosts 完整迁移；DNS/hosts 定向与菜单已通过，集中完整 49 项回归通过。

菜单 `5 → 1 → 5 → 38/39` 与 `edit --hosts-add <精确 FQDN> <单字面 IP>` /
`--hosts-remove <精确 FQDN>` 提供单键新增和精确删除。新增可创建缺省 hosts，
但已有键不论地址是否相同均返回 `15`，须用替换入口改地址；合并最多 256 项。
删除要求键已存在，缺键或未启用返回 `15`；删掉最后一键关闭 hosts，
只在没有其它策略时清理 routing。沿用 ASCII 小写、不去空白及地址原文边界，
其它映射、完整配置、URI/订阅和累计流量保持。增删专项已通过 Linux amd64
定向与菜单 PTY 回归，集中完整 53 项回归通过；
完整区域策略、冲突检测及原生 hosts 完整迁移仍为 `deferred`。

菜单 `5 → 1 → 5 → 8` 与交互 CLI `edit --hosts-input` 可输入一个字面 IPv4/IPv6，
再输入精确 FQDN CSV，整组替换 hosts；旧键不会保留，确认前可取消。
域名去除首尾空白、ASCII 转小写并去重，接受 1–256 个精确域名；
不接受规则前缀、通配符或空项。IP 保留原文并复用完整规格校验。
空输入、`0` 或 EOF 取消；仅限交互 TTY，不能与 `--preview`/`--confirm` 组合。
原私有 JSON CLI、单键增删/替换、权限与失败恢复保持，支持范围仍为 `deferred`。

```bash
padm-docker edit --dns /root/padm-dns.json --preview
padm-docker edit --dns /root/padm-dns.json --confirm PADM-DOCKER-EDIT
padm-docker edit --dns-rules 192.0.2.53 53 'example.net,full:exact.example.org' --preview
padm-docker edit --dns-domains-add 'full:updates.example.net' --preview
padm-docker edit --dns-domains-remove 'full:updates.example.net' --confirm PADM-DOCKER-EDIT
padm-docker edit --hosts /root/padm-hosts.json --confirm PADM-DOCKER-EDIT
padm-docker edit --hosts-input
padm-docker edit --hosts-replace Exact.Example.NET 2001:0DB8::10 --preview
padm-docker edit --hosts-replace exact.example.net 192.0.2.11 --confirm PADM-DOCKER-EDIT
padm-docker edit --hosts-add new.example.net 2001:DB8::11 --preview
padm-docker edit --hosts-remove new.example.net --confirm PADM-DOCKER-EDIT
padm-docker edit --dns-off --confirm PADM-DOCKER-EDIT
padm-docker edit --hosts-off --confirm PADM-DOCKER-EDIT
```

已有域名名单可单条替换：菜单 `5 → 1 → 4 → 30` 编辑 DNS，`5 → 3 → 31/32` 分别编辑 Direct、Block，
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

菜单 `5 → 1 → 7 → 1` 或终端 `padm-docker edit --http-relay-input` 可直接录入
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
详见 [Docker HTTP 中继](docker-http-relay.md)。

菜单 `5 → 3` 的 `10/12` 分别替换 Direct 直连例外和 Block 域名阻断，可直接输入
逗号分隔规则；CLI `--direct-domains/--block-domains` 使用相同输入。
CSV 去首尾空白、转小写、按首次出现去重，裸域名补 `domain:`，
整组替换而非累加，空项/非法或超过 256 条拒绝；清空请使用对应关闭命令。
菜单 `5 → 3` 的 `22/23` 或 `--direct-domains-add/--block-domains-add` 可增量追加：
保留原规则顺序，再添加首次出现的新项；对应组缺失时创建，合并后超过 256 条拒绝。
重复追加不重复规则，确认仍沿用部署事务，可能更新回滚元数据。
菜单 `5 → 3` 的 `24/25` 或 `--direct-domains-remove/--block-domains-remove` 可精确删除：
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

菜单 `5 → 3` 的 `14/26/27` 分别直接录入、追加和精确删除 IP/CIDR 阻断 CSV，
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

菜单 `5 → 3` 的 `33` 和 `--block-ips-replace <旧规则> <新规则>` 可单条替换已有手工
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

菜单 `5 → 3 → 45/46` 或 `--block-ips-resolve/--block-ips-literal` 可切换已有手工
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

菜单 `5 → 2` 的 `16–17` 管理 BT 协议阻断，v3 `.routing.block_bt:true` 启用，
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

菜单 `5 → 3 → 18` 提供 CN 区域预设，分别按 `geosite:cn` 域名、`geoip:cn`
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

菜单 `5 → 1 → 2` 管理 IPv6 域名出站。v3 `.routing.ipv6` 使用独立
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

菜单 `5 → 1 → 1 → 1` 和交互 CLI `edit --warp-input` 直接录入已有 WARP Peer 参数，
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
Hysteria2/AnyTLS/NaiveProxy/Shadowsocks/TUIC 仅支持 sing-box 内复制；
已有 v3 部署可通过“协议与入口”的新增操作或 `edit --protocol-add` 添加受支持协议，
沿用来源入口身份和已授权账号范围；首次 TLS 仍须提供域名及受管证书。
Shadowsocks 的方法、服务器密钥、UUID 和已有入口身份冻结；普通编辑/`--spec`
仍拒绝手改密钥，自用用户与服务器密钥须使用下面的专项轮换。
AnyTLS/NaiveProxy/direct Trojan 复用通用入口字段编辑，TLS 域名与 UUID 冻结，证书轮换使用证书管理入口。
NaiveProxy 的入口域名随 TLS 身份固定，不能单独修改为其它域名或 IP。
编辑器可从现有 Reality 入口派生其它 Reality 传输入口，不生成新账号或密钥。
删除副核心的最后入口会关闭副核心，不能改写已有入口的核心归属。
新增与删除须分次确认提交，不能在同一事务中用替换绕过已有身份及内部端口保护。
复制复用原入口凭据；同一 UUID 的多个入口共享累计流量与额度，不会创建独立用户。
旧部署没有 `config/spec.json` 时，必须导入保留的完整原始 spec，匹配运行配置后才能接入；
缺字段、额外账号、手写路由/站点或不匹配的挂载路径会拒绝编辑，不从运行摘要伪造输入。

Docker 菜单 `3 → 9 → 19. Shadowsocks 自用用户密钥轮换` 或以下命令，
每次只轮换一个已有 v3 sing-box 协议 `30` 入口的 `shadowsocks.user_password`：

```bash
padm-docker edit --rotate-ss-user <入口ID> --preview
padm-docker edit --rotate-ss-user <入口ID> --confirm PADM-DOCKER-EDIT
```

服务器密钥、UUID、其它入口（包括同 UUID）、独立账号密钥、额度与累计保持。
发布验签后由可信 ops 的 OpenSSL 生成规范 Base64 的 16 字节密钥，
最多尝试 32 次并拒绝与现存 SS 服务器/自用/独立账号密钥碰撞；秘密不进 argv 或日志。
主订阅和该入口自用 URI 更新，独立账号分享组内容保持；客户端须重新导入，
不承诺既有连接排空。不能与其它专项或 `--spec` 组合，不新增 schema 或能力 marker。
专项、Docker amd64 双族 TCP/UDP 真实回归及集中完整合同 61/61 项通过；
轮换范围见[实施计划 3D.24](docker-menu-parity-plan.md#3d24-shadowsocks-逐入口自用用户密钥轮换)，协议管理状态接续 3D.26。

菜单 `3 → 9 → 20. Shadowsocks 服务器密钥轮换` 或 `edit --rotate-ss-server <入口ID>`
复用同一专项事务，只修改选中入口的 `shadowsocks.server_password`，支持相同的预览与确认参数。
自用及独立账号用户密钥、UUID、其它入口、分享授权/token、额度与累计保持；
该入口的主订阅和所有账号 URI 随服务器密钥更新，所有客户端须重新导入。
不联动同 UUID 的其它入口，不承诺旧连接排空；普通 `--spec` 的密钥冻结不变。
正式 `3.41.5` 已在 Debian 13 amd64 普通 bridge 完成两类轮换的公网 IPv4 TCP 验收：
固定 Mihomo `v1.19.28` 原生导入 SIP002 URI，五阶段 `17` 正例、`9` 拒绝通过，
核对两入口、自用/独立账号、精确字段冻结、累计和原 WS 恢复，并经断网独立核验。
此证据不包含 UDP、IPv6、重启或旧连接排空；宿主集成组合仍拒绝。
详见[实施计划 3D.25a](docker-menu-parity-plan.md#3d25a-两类-ss-密钥轮换原生验收)。

```bash
padm-docker edit
padm-docker edit --spec /root/original-spec.json --preview
padm-docker edit --spec /root/original-spec.json --confirm PADM-DOCKER-EDIT
```

菜单“协议与入口 → 入口高级管理 → 核心/Nginx 内部端口”（`3 → 9 → 17`）可同时修改已有 WS/HTTPUpgrade/gRPC TLS
（21–25）入口的核心后端端口与 Nginx TLS 内部端口，保留公开端口、账号及分享身份。
HTTPUpgrade 支持 Xray/sing-box，其余仅 Xray；额外公开端口及受管 Reality 443 共存同步投影。
端口须为 1–65535，并通过各容器监听、统计 API、HTTP-01 及共存端口冲突检查。
带站点 Fail2ban 时需先停用防护；普通规格导入仍不能修改内部端口。

```bash
padm-docker edit --internal-ports entry-ws 31300 8446 --preview
padm-docker edit --internal-ports entry-ws 31300 8446 --confirm PADM-DOCKER-EDIT
```

菜单“协议与入口 → 额外入口端口管理”（`3 → 6`）可给已有受管入口添加、删除或修改额外公开端口。
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

菜单“协议与入口 → 入口高级管理 → 端口跳跃”（`3 → 9 → 11`）提供 Hy2/TUIC 范围 DNAT 的配置、启停、清除及活动端口分享。
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

菜单“协议与入口 → CDN 入口管理”（`3 → 7`）可为已有 `2` Reality XHTTP 及 `21/22/23/24/25` WS/HTTPUpgrade/gRPC TLS
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
`x-padm-cdn-grpc-tls`；协议 `2` 另需 `x-padm-cdn-xhttp`，只替换上行连接地址，
保留 Reality 身份及独立下行地址。旧包可继续处理原三种覆盖及没有覆盖的 gRPC TLS。
Reality gRPC 与其它 TCP/UDP 协议仍不在范围内；外部 CDN、TLS/H3 和下行服务须已部署。
原生 CDN 菜单只有 H3 使用说明，不另设 H3 参数开关。公网透传与完整环境验收仍为 `deferred`。

新生成的 `21/22/23` TLS 前端拒绝错误 Host；无 CDN 字段的完整旧 Nginx
正文可继续通过只读和编辑基线，下一次确认配置编辑会生成新正文。
带 CDN 字段要求新正文；缺失部分 Host 校验或其它手写漂移仍拒绝。
`24/25` 沿用受管 Nginx HTTP/2 gRPC 反代和严格 TLS 身份，不套用 WS 的 Host/path 门禁。
公网 CDN 供应商的 gRPC 透传仍需独立验收。

菜单“协议与入口 → 入口高级管理”（`3 → 9`）可查看稳定入口 ID、核心、协议、地址/端口及地址族，
查看全部或指定入口的分享链接，并进入现有编辑器修改、复制或删除入口。
`protocol links` 标准输出只含 URI；关闭 HTTPS 订阅发布时仍可输出本地链接，
不会开启发布、修改受管规格或采集流量。旧部署缺少完整规格或运行配置存在漂移时拒绝输出；
本地链接含用户凭据，不应公开。

```bash
padm-docker protocol list
padm-docker protocol links
padm-docker protocol links vless-reality
```

已有受管部署可用菜单 `3 → 9 → 14` 增量安装；v3 部署还可用同页 `15` 直接删除、`16` 保留参数重建：

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
受管 Nginx `default.conf` 缺失或正文损坏时，可用菜单 `3 → 9 → 21` 或：

```bash
padm-docker edit --protocol-rebuild entry-1 --repair-nginx --preview
padm-docker edit --protocol-rebuild entry-1 --repair-nginx --confirm PADM-DOCKER-EDIT
```

仅适用于 v3 的 `21–25/27/29`，完整规格保持不变；其它配置、部署、证书、
权限和属主仍严格核验，符号链接、硬链接或额外文件拒绝。
站点 Fail2ban 须先停用；预览或取消不改现场，提交失败恢复原正文或原缺失状态。
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
协议管理状态见功能对照表；重装不会扩大所列支持组合。

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
删除最后一个适用发布入口（`21–25/27/29`）会关闭订阅；仍有 Hysteria2、AnyTLS、NaiveProxy、TUIC 或 direct Trojan 时保留规格中的 TLS，
否则将 `tls` 设为 `null`，受管 TLS/ACME 文件与 token 均保留。
Nginx 端轮换、核心端受管 TLS 底座及 Reality XHTTP/gRPC、Hysteria2/AnyTLS/NaiveProxy/Shadowsocks/TUIC/direct Trojan/VMess WS/HTTPUpgrade/gRPC TLS/传统 TLS fallback 基础入口已交付；
逐入口 Reality 参数重生成、目标库/扫描、有限 443 共存与 XHTTP 管理已交付，具体边界见各专项说明。
更新或回滚的目标 bundle 必须同时支持规格版本及每个入口的协议/核心组合。
带 Fail2ban 的部署可增删或修改未受保护 WS 21 的公开端口；
受保护入口身份、核心、地址族、公开端口、内部 TLS 端口和域名保持冻结，
保护端口迁移使用专项，不能通过交换端口或删除后重建绕过。
3A.3 已通过本地双核心事务、PTY、流量、更新/回滚和 Linux 权限回归；真实签名发布、业务镜像及双架构客户端连通仍待验。

菜单 `协议与入口 → REALITY 管理 → 重生成 Reality 参数`（`3 → 2 → 2`）可选择已有入口，确认后更新密钥对和 short ID。
也可使用 CLI：

```bash
padm-docker edit --regenerate-reality <入口ID> --preview
padm-docker edit --regenerate-reality <入口ID> --confirm PADM-DOCKER-EDIT
```

仅修改该 Reality 入口，保留 UUID、目标/SNI、端口、其它入口和流量额度；
提交后需重新导入该入口链接，已启用的 HTTPS 订阅内容同步更新。
预览不提交，确认前的候选参数不会保留到下一次命令；普通 `edit --spec` 仍禁止手工改密钥。
失败或中断使用配置快照恢复；公开 `rollback` 仍只回滚更新快照，不是编辑撤销命令。

v3 Xray 的 Reality `1/2/26` 在参数重生成时，还按原生 `target_host:port`
探测中带 SNI 的握手结果决定 ML-DSA-65：TLS 1.3、X25519MLKEM768 且证书链
超过 3500 字节时生成或复用已有配对；成功探测不满足条件时清除，探测失败中止。
独立 `server_name` 的可用性仍须单独验证。seed 只在私密输入中流转，
可信 ops OpenSSL 通过标准输入派生并核对 verify，错配拒绝；
普通编辑不能改写配对。核心配置、`pqv` 分享及同身份 XHTTP 下行同步更新，
提交后重新导入链接。带配对的更新/恢复要求 `x-padm-reality-mldsa65`；
旧无配对规格保持兼容，sing-box 不接受该字段；已有配对的来源只能向 Xray
复制或派生，不能借跨核心复制静默清除该安全参数。

Docker 菜单 `8 → 2. VLESS Encryption 实验` 仅管理 schema 3 的 Xray
Reality Vision（协议 `1`）与 Reality XHTTP（协议 `2`）已有入口：

```bash
padm-docker protocol encryption-status
padm-docker protocol encryption-status <入口ID>
padm-docker edit --vless-encryption <入口ID> enable --preview
padm-docker edit --vless-encryption <入口ID> enable --confirm PADM-DOCKER-EDIT
padm-docker edit --vless-encryption <入口ID> disable --confirm PADM-DOCKER-EDIT
```

`vless_encryption` 对象保存 `decryption/encryption`，缺省为 `none`。
固定使用服务端 `mlkem768x25519plus.native.600s.<seed>` 与客户端
`mlkem768x25519plus.native.0rtt.<public>`；可信 Xray 生成后，由 ops 内 Python/OpenSSL
校验 ML-KEM-768 密钥配对。私密文件为 `0600`，秘密不进入命令参数、预览、状态或日志。
普通编辑与同核复制保留该对象，复制到不支持的核心/协议时拒绝。
重复启用或关闭返回 `15`；轮换须先关闭再启用，每次变更后重新导入分享 URI。
更新/回滚的目标 bundle 缺少 `x-padm-vless-encryption` 时拒绝带实验配置的操作。
固定 Xray `26.3.27` / Mihomo `v1.19.28` 的 Linux amd64 实验和正式
`3.41.5` 在 Debian 13 amd64 上的公网启用、逐入口隔离、错误身份拒绝、关闭恢复，
以及 bridge 双入口加密后的真实整机重启恢复已通过；原容器自然启动、原 URI、
材料权限、调度和累计均保持。其它客户端、算法、arm64 及其它拓扑的加密重启未验，
完整能力继续 `deferred`，
验收证据见[实施计划 5C.10](docker-menu-parity-plan.md#5c10-vless-encryption-有限实验管理)。

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

## 五个镜像

五个镜像都由仓库中的 Dockerfile 定义，当前统一以锁定的 Alpine 3.24.1 基础镜像构建；基础 digest、上游版本和架构校验值由 `versions.lock` 锁定，再由 CI 构建 `amd64/arm64` 多架构镜像。一个镜像可以被多个 Compose service 复用，但不同长期职责仍是独立容器。

| 镜像 | 职责 | 宿主集成 |
| --- | --- | --- |
| `padm-xray`（`xray`） | Xray-core、Geo 数据和核心配置校验。 | 普通 bridge 容器。 |
| `padm-sing-box`（`sing-box`） | sing-box、核心配置校验和对应协议运行时。 | 普通 bridge 容器。 |
| `padm-nginx`（`nginx`） | TLS、WebSocket、反向代理和静态入口。 | 只发布被选中的入口端口。 |
| `padm-ops`（`ops`） | ACME、订阅控制、Geo/同步等运维任务，按 Compose service 作为长期或一次性进程运行。 | 不持有 Docker Socket。 |
| `padm-net`（`net`） | WireGuard、Fail2ban、TUN/TProxy 和端口/防火墙集成工具。 | 仅在显式 `net-*` profile 下使用 `NET_ADMIN`、host network 或 `/dev/net/tun`。 |

`net` 的业务工具放在镜像中，但真正的 WireGuard、转发、TUN 和防火墙对象仍属于宿主内核；默认安装不启用这些高权限 profile。普通服务不使用 `privileged`、`SYS_ADMIN` 或 Docker Socket。

## 状态与日常控制

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

菜单 `7 → 3. Fail2ban 防护` 提供受管 Fail2ban 的状态、单 IP 解封、WS 站点扫描启停及参数管理：

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
TProxy/Redirect 的 `net-transparent` 禁用 Docker 自动重启；daemon 或宿主重启后，
须通过受管入口重新预检启动。旧 `unless-stopped` 编排仍可审计后停止、清理，
并在兼容控制包下更新为新策略；旧备份恢复也规范化该策略，保留备份原文。
启用透明集成时，当前及目标控制包须有 `x-padm-transparent-managed-restart`；
缺少该能力的旧包须先停用集成再升级或回退。旧 CLI 升级进程不会重载新代码，
首次迁移也先停用集成。仅设置 `restart=no` 不等于从规格停用。
TProxy 管理入口为菜单 `5 → 1 → 9 → 43`，或以下命令：

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

Redirect TCP 管理入口为菜单 `5 → 1 → 9 → 47`：

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

TUN 管理入口为菜单 `5 → 1 → 9 → 44`：

```bash
padm-docker protocol tun-status
padm-docker protocol tun-diagnose
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

TUN 的 IPv4 Echo 请求明确交给 `direct`，不增加 `CAP_NET_RAW`。
这里验证的是直连出口的 Echo 往返，不能据此判断 Reality 入口、代理隧道或 TCP/UDP 服务健康；
Echo 失败也不能单独判定这些服务故障。
核心在 raw socket 权限不足时可回退到受 `net.ipv4.ping_group_range` 约束的
ping socket；范围检查使用核心的有效 GID 或附加组。组范围不允许或其它系统策略拒绝时，
ICMP 可以失败，普通 TCP/UDP 服务不因此停止，也不自动修改宿主 sysctl 或扩大能力。
`tun-diagnose` 仅读取受管核心进程的身份、能力和所在网络空间的组范围，
报告 `ping_group_allowed`、`net_raw_effective`；读取失败为 `unknown` 并保留原因。
`ping_group_allowed=true` 只表示组范围允许，不代表 socket 创建成功或目标可达。
远端可能只过滤 Echo；即使组范围允许且 TCP/UDP 正常，Echo 仍可能超时。
`socket_probe`、`echo_roundtrip` 与 `capture` 明确标为未验证，诊断不发包、不启停核心。
旧 TUN 模板仍可查询、诊断和关闭；缺少显式规则时报告 `policy_dependent`，
仅更新镜像会保留原配置，后续配置重新生成时才写入该规则。
TUN 仍拒绝与 SOCKS/WARP 等 `routing` 配置共存，不通过直连或本地构造回复掩盖不支持的出站。
这项能力限定基本 IPv4 Echo，不承诺 traceroute、IPv6 ICMP 或 PMTU；也不增加全局 ICMP 丢弃规则。

菜单 `6 → 7. 核心升级评估` 或 `assess` 会验签并预拉取候选镜像，使用私有配置副本
执行菜单版升级风险扫描、实际核心配置试跑和 Xray 严格校验，以及已启用的 TLS、
订阅和宿主集成检查。输出候选发布与实际核心版本；不备份、不采集流量、不切换
配置或控制 bundle，也不启停现有服务。完成、失败或取消后清理候选。
旧部署必须先通过 `edit --spec` 导入完整受管规格。默认评估最新可信发布；评估预发布时
传入与该版本匹配的 `--manifest`、`--bundle` 和 `--control-bundle`，不接受未签名
镜像或现场构建核心。通过只证明这些检查完成，不替代真实客户端连通验收。
Xray 严格解析另用未知字段探针确认；不识别严格模式的候选核心会明确显示“未启用”，
不能将普通配置试跑通过视为严格解析通过。

Xray Geo 数据可在菜单 `6 → 8` 管理，单 Xray 和包含 Xray 的双核心部署均可用：

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
v1 恢复、失败回滚或显式版本回滚均禁用授权，避免复活旧 token，之后需重新邀请。
邀请文件原子交付后即使配置失败也保留，但不保证授权有效，以 `control status` 为准。
被控端先配置并启动归属一致的单 Peer WireGuard，再将邀请安全送至其 root 私有目录。
主控地址须是唯一 Peer 的 `/32` AllowedIPs，本机接口地址须与邀请的 `peer_address` 一致，
到主控的指定源地址路由必须走 `wg-padm`。接入和手动同步也可从“控制连接”菜单执行：

```bash
padm-docker control join --invite /root/padm-control-invite.json --listener entry-reality --yes
padm-docker control sync --invite /root/padm-control-invite.json
```

`--listener` 可重复指定现有入口；菜单 `2 → 4 → 5` 输入逗号分隔的入口 ID（最多 16 个），
空段、尾逗号或非法 ID 拒绝。接入一次确认，在同一事务中初始化被控身份、固定映射并完成首轮同步。
失败保留原角色、账号和流量；重复同步同版本同内容不重建。
双方身份和 WireGuard 地址随后冻结，不能用另一邀请重新认领。普通同步保留已提交映射和 API 端口。
菜单 `2 → 4 → 15` 或以下命令可在同连接上重新认证并替换映射：

```bash
padm-docker control remap --invite /root/padm-control-invite.json --listener entry-secondary --yes
```

先停用自动同步，提交后用同连接邀请重新启用；版本、摘要和旧受管快照仍须一致，
本机账号及流量保持。轮换后安全传递新的邀请文件，再同步。
菜单 `2 → 4 → 16/17` 提供同身份的 API 端口更新与重连，命令顺序如下：

```bash
# 被控端先停用自动同步；主控端先停用控制日志调度和控制面 Fail2ban。
padm-docker control set-port --port 19443 --yes
padm-docker control invite --output /root/padm-control-new-port.json --yes
# 将新邀请安全传至被控端，再执行：
padm-docker control reconnect --invite /root/padm-control-new-port.json --yes
```

仅接受 `1024–65535` 端口，保留主控/被控身份、WireGuard 密钥和地址、入口映射与累计流量；
重连仍认证邀请并核对版本、摘要和旧受管快照，可能同时取得主控的新账号版本。
同端口、同版本重复执行不重建；失败或 INT/TERM 走原事务恢复，不允许跨端口显式回滚。
切换后旧端口不再提供 API；主控须重新 `source-check` 才能启用来源相关防护和日志调度，
被控须用新邀请重新启用自动同步。该入口不支持地址/身份/密钥迁移、多 Peer 或跨主控重绑定。
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
控制菜单提供单 Peer 角色连接维护、显式同隧道主控重绑定及 v2 多被控管理；
任意历史账号恢复仍未开放。
无主控/被控角色的已启用 canonical WireGuard 可通过菜单 `2 → 4 → 18 → 7–10`
或以下命令按地址管理 Peer 集合：

```bash
padm-docker wireguard peers list
padm-docker wireguard peers add --peer-address 10.77.0.3 --peer-public-key "$PEER_PUBLIC_KEY" --endpoint 192.0.2.3:51820 --yes
padm-docker wireguard peers update --peer-address 10.77.0.3 --endpoint none --yes
padm-docker wireguard peers remove --peer-address 10.77.0.3 --yes
```

每项仍限定唯一 RFC1918 IPv4 `/32` 和公钥；重复、任意路由及 hooks 拒绝，
配置沿用 `4096` 字节上限。更新的地址是精确选择器，不改变该项地址；
省略字段保持，`none` 清除 endpoint，至少保留一个 Peer。
变更逐字节保留本机身份和私钥，复用完整配置事务及失败/INT/TERM 恢复，
会重建部署服务并可能短暂中断连接。v1 主控与被控集合变更继续拒绝；
无控制角色的多 Peer 可通过菜单 `2 → 4 → 18 → 6` 或以下命令更新本机地址、监听端口和密钥：

```bash
padm-docker wireguard migrate --address 10.78.0.1 --listen-port 51821 --rotate-key --yes
```

至少显式提供一个本机字段；全部 Peer 地址、公钥和 endpoint 保持。
多 Peer 禁止在该命令中传 `--peer-address`、`--peer-public-key` 或 `--endpoint`，不会默认选择首项。
地址或密钥更新后须逐端更新远端配置，期间可能断联；健康失败和 INT/TERM 沿用原三件套恢复。
控制角色范围不扩大；无控制角色的多 Peer 空目标恢复见下文。

已有 v1 主控可通过菜单 `2 → 4 → 20` 显式升级为 v2，再登记第二个被控：

```bash
padm-docker control upgrade --yes
padm-docker wireguard peers add --peer-address 10.77.0.3 --peer-public-key "$PEER_PUBLIC_KEY" --endpoint 192.0.2.3:51820 --yes
padm-docker control peers add --peer-address 10.77.0.3 --yes
padm-docker control peers list
padm-docker control invite --peer-id "$PEER_ID" --output /root/padm-peer-3.json --yes
padm-docker control source-check --peer-id "$PEER_ID"
padm-docker control revoke --peer-id "$PEER_ID" --yes
padm-docker control peers remove --peer-id "$PEER_ID" --yes
```

从脱敏列表取得生成的 `PEER_ID`；菜单 `21–23` 提供查看、登记与移除。
v2 即使只剩一项，邀请、撤销及来源检查仍必须指定 ID；升级保留原身份、授权、版本、
账号和累计，旧邀请继续有效，HTTP API 与被控格式仍为 v1。
每个被控独立持有邀请并沿原接入/同步流程操作，来源与 token 必须同时匹配该项。
API 端口及账号发布版本由主控共享；更换端口后每个被控分别重连。
同来源允许一个处理请求和一个最多等待 `100 ms` 的交接请求，均计入总并发上限 `8`；
监听线程不等待交接，每连接总时限 `5` 秒。
同一主控的配置事务仍可能短暂影响全部连接。v2 失败回滚只保留在全部可信计划中
身份、监听和完整 Peer 元数据均未变化的旧授权；其它项禁用，不能证明时整体禁用。
移除前必须先撤销，集合至少保留一项。v2 主控可维护未登记的 WireGuard Peer；
已登记项须先撤销并移除控制登记，再修改或移除其隧道项。
v2 更新/回滚要求目标 bundle 声明 `x-padm-control-peers=true`，旧单项 bundle 在切换前拒绝。
v2 关联地址/本机密钥迁移及控制面 Fail2ban 暂不支持；升级前先停用后者。
主控新身份空目标恢复见下文，不能恢复旧授权。
本机定向及三节点验收状态见[实施计划](docker-menu-parity-plan.md)，
原生宿主、arm64、公网、重启和可信发布仍分别待验。

`wireguard migrate` 及其子菜单 `6` 支持主控/已接入被控的关联地址迁移，例如：

```bash
padm-docker wireguard migrate --address 10.78.0.1 --peer-address 10.78.0.2 --yes
```

先停自动同步、控制日志调度及控制面 Fail2ban，并清除未完成来源挑战。
本机和 Peer 的角色地址与 canonical 隧道三件套在同一事务切换；身份、API 端口、
账号、同步版本和累计保持。主控改址撤销原邀请，双方逐端改址会暂时断联，
完成后须重新邀请、同步和核验来源；同地址的密钥/端口/endpoint 更新仍沿用原行为。
失败及 INT/TERM 恢复旧地址和密钥，主控授权保持撤销；普通回滚拒绝跨控制地址覆盖。
隔离 Linux amd64 双 daemon 真实改址、业务及恢复已验；主控新身份灾备见下文，原生宿主验收仍待补。
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
[4C 实施计划](docker-menu-parity-plan.md#4c-多服务器控制后端)。

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

菜单 `4 → 2. 本机 TLS 证书管理` 可查看/校验证书、导入轮换、DNS-01/HTTP-01 standalone/webroot/TLS-ALPN-01 申请或续期，并显式开关 HTTP-01 入口、管理自动续期；最终确认前不持有部署锁。
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
详见[真实 TLS 验收基线](docker-tls-real-baseline.md)。
真实 systemd/cron 的隔离调度探针、双向迁移与容器重启已验证，不替代整机或 DNS 验收。

配置变更先生成候选文件、校验端口和 Compose，再备份当前状态并执行健康检查；失败时保留旧配置。Docker 入口安装的控制命令是 `/usr/local/bin/padm-docker`，实际 bundle、配置、数据、密钥、日志和备份分别位于状态根下的 `bundle/`、`config/`、`data/`、`secrets/`、`logs/` 和 `backups/`。

## 可信发布输入

首次配置向导会自动验证发布输入。需要独立检查或准备非交互配置时，也可先检查签名发布、控制 bundle 和 5 个固定 digest 镜像：

```bash
padm-docker release
padm-docker release --manifest /path/release-manifest.json \
  --bundle /path/release-manifest.sigstore.json --control-bundle /path/padm-docker-bundle.tar.gz
```

成功时标准输出只有包含 `release`、`images` 的 JSON；签名验证、归档校验和全部镜像拉取完成前不输出该结果，进度与错误写入标准错误。该命令不生成完整 spec 或凭据、不切换已安装控制脚本、不启动或重配服务；镜像拉取会更新宿主 Docker 缓存，本地发布资产也不代表离线镜像可用。输出 JSON 不是签名证明，后续配置仍须核对原 manifest 与 Sigstore bundle。

需要支持 Sigstore bundle v0.3 的 `cosign`。缺少该工具时命令停止，不跳过验签、不自动安装宿主工具；先通过独立受信的软件源或 Sigstore 官方发布说明核验并安装，再重试。固定发布身份和验证器信任来源不能由尚未验签的 manifest 指定。

## 灾备归档

菜单 `7 → 1 → 6/7` 提供受管输入导出和只读校验，宿主需要 Python 3：

```bash
padm-docker backup export /root/padm-recovery.tar
padm-docker backup verify /root/padm-recovery.tar
```

导出在部署锁内检查当前规格与部署，生成版本 1 USTAR 归档及路径、大小、模式、
SHA-256 清单，归档 `0600` 且拒绝覆盖。目标目录须属于当前 root 且不可被组或其他用户写入。
范围含规格/核心配置、部署与镜像引用、Geo 实际数据、账号/已保存流量、网站/订阅、
TLS/ACME、续期登记、WireGuard 密钥、控制状态/自动同步私密登记及 Reality 目标库。
归档包含凭据，不能公开分发；流量保留已保存累计及原始基线，不隐式采集。
导出前后核对源文件与清单稳定性，文件变化则拒绝；不包含锁、日志、宿主规则/调度、
运行会话、挑战、镜像层、旧备份和控制 bundle，固定镜像/版本须另从可信发布获取。

`verify` 不要求 Docker、部署状态或 root，不解包、不创建临时文件，只接受当前用户
持有且无组/其他权限的单硬链接普通文件。它流式核对版本、白名单、权限、成员和摘要，
拒绝越界路径、链接/特殊成员、重复、缺失、额外内容及损坏。
本阶段限 ASCII USTAR 路径（总长最多 255 字节、文件名最多 100 字节）、
16,384 项、单文件 512 MiB、正文合计 2 GiB；超限拒绝而不截断。
归档完整性不证明来源可信、业务状态一致或恢复就绪。

菜单 `7 → 1 → 8` 和以下命令提供受限的恢复预览：
菜单可选择默认发布或自备匹配的 manifest、Sigstore bundle 与 control-bundle，
菜单 `7 → 1 → 9` 应用恢复也使用同一选择；含空格的资产路径保持为完整参数。

```bash
padm-docker restore preview /root/padm-recovery.tar
# 归档不是当前最新发布时，显式提供对应的可信发布资产：
padm-docker restore preview /root/padm-recovery.tar --manifest /root/release-manifest.json --bundle /root/release-manifest.sigstore.json --control-bundle /root/control.tar.gz
```

目标须仅安装控制骨架，配置、数据、密钥、日志和备份目录为空，且没有同项目容器。
当前接受同架构 v3 普通部署、受管或桥接可达宿主网站 Reality 共存：核心、手动 TLS、静态站、账号/分享身份、
已保存流量、Reality 目标库、下述受限 Geo、ACME、续期及 canonical WireGuard 输入。
主控仅接受下述显式新身份恢复；其它宿主集成、自动同步授权、host 网络共存及未处理 ACME 仍拒绝。
停用分享组的悬空引用也须先修正。
WireGuard 要求完整 canonical `identity.json`、`private.key`、`wg-padm.conf` 三件套，
均为 `root:root`、目录 `0700`、文件 `0600`，可信 net 镜像另核私钥与公钥配对。
无控制角色支持非空 Peer 集合；已接入被控仍限单 Peer，主控须使用下述显式新身份重建。
被控自动同步须先停用，归档不得含 `secrets/control-sync`。
保留全部 Peer 地址、公钥和 endpoint，以及本机密钥、适用的控制身份、连接、受管快照、版本、账号及累计；被控恢复后重新邀请并手动同步，
不清空版本防倒退门禁。恢复前先停止旧节点并确认接口消失，不能同时运行相同 WireGuard 身份。
宿主接口、ifindex、alias、运行归属及来源挑战不随归档恢复；目标重新预检并生成运行归属。
撤销时仅在容器和接口均确认消失后清理私密材料；探测失败或接口残留时保留现场供 `restore recover` 重试。
已有 `.tls.http01=true` 可保留，按规格重建空挑战根和双栈 `80:8088`，
不恢复旧挑战文件；ACME 账户及续期仅接受下述受限组合，目标端口仍须通过现有预检。
单 sing-box 双族 Hy2/TUIC 可恢复已保存的 `port_hopping` 规格；恢复后为 `stopped`，
不恢复旧监督进程、规则或运行态。启用前须在目标主机显式执行 `port-hopping start` 并重新预检。
Reality 仅恢复 `data/reality-targets/results.tsv`（15/16 列 TSV）及 `blocked.tsv`（4 列 `|` 分隔），
每文件最多 16 MiB，先完整验证再按原字节复制，保留空列、重复项和自定义屏蔽原因。
目录为 `0700 root:root`、文件为 `0600 root:root`；不联网刷新，不保证旧评分或握手仍有效。
Geo 接受包含 Xray 且 `state.enabled` 为布尔值的固定版本受管库，
按原字节恢复 `config/xray/geo/` 下的 `state.json`、`geoip.dat` 和 `geosite.dat`，两份数据各不超过 128 MiB。
先核对归档清单和 state 中的数据摘要，再进行无网络 Xray 解析校验；恢复过程不联网下载 Geo 数据。
`enabled=true` 在安装和健康检查成功后恢复目标主机的每日自动更新调度；
`enabled=false` 仍使用 Geo 数据，但不安装或接管已有 Geo 调度。预览不安装调度。
续期仅恢复 `enabled=false` 的 DNS、standalone、webroot 或 ALPN 登记及 DNS 凭据，保持原字节和
`0700/0600 root:root` 权限，非 DNS 登记不得夹带凭据，不安装续期调度；启用登记仅接受下述受限组合。
ACME 数据仅接受 acme.sh `3.1.6` 的单域名、账户及域名 EC-P256：
standalone HTTP-01 `8080` 须匹配 schema `2` 登记且关闭 `.tls.http01`；
受管 webroot 须匹配 schema `3` 登记、开启 `.tls.http01` 并已有 Nginx TLS 入口 `21–25/27/29`。
webroot 固定为 `/var/lib/padm/acme-webroot`，不得残留自监听端口或自定义路径。
TLS-ALPN-01 须匹配 schema `4`／`alpn` 登记、`Le_Webroot='alpn'` 和固定 `Le_TLSPort='8443'`，
不得残留 `Le_HTTPPort`；可保留合法 HTTP-01 入口，后续续期仍重新预检 `443` 归属。
DNS-01 仅接受 schema `1`／`dns_acmedns`，`Le_Webroot='dns_acmedns'` 及预登记的
`ACMEDNS_USERNAME`、`ACMEDNS_PASSWORD`、`ACMEDNS_SUBDOMAIN`、`ACMEDNS_BASE_URL`；
域配置与私密 `credentials.env` 四值必须完全相同，URL 须为规范 HTTPS，拒绝自监听端口。
外部 acme-dns 注册和域名 CNAME 必须仍然有效，恢复不重建该外部服务或交互注册。
恢复器不执行归档 shell：严格解析并重建固定 9 个文件，只丢弃已知 CSR/临时材料；
未知配置、hook、其它 DNS provider、SAN/RSA/EAB 和自定义执行路径均拒绝。私钥、公钥、证书链及固定 TLS 输出
先在无网络的可信 ops 容器内验证绑定；账户和域名密钥保留。
仅对应材料匹配且登记只有该域时，可保留 standalone、webroot、ALPN 或 `dns_acmedns` 的 `enabled=true`；
健康成功后按 traffic、Geo、renewal 安装适用调度。其它启用 DNS 登记继续拒绝，
空 `data/acme` 不能授权启用续期。
空 `data/acme` 仍兼容。受管 Reality 共存从规格重新生成 stream，公开入口仍为 `443`，
不执行归档 Nginx stream 文件。桥接宿主网站恢复保留域名、上游地址和端口，
仅接受 host-gateway 或可路由 IP；回环、host 网络和未处理的 host-main 输入仍拒绝。
网站服务、内容及其证书仍由宿主维护方提供，不随本归档恢复。
归档的发布、签名身份、清单摘要和镜像必须与独立验签的发布完全一致。
预览会创建 `0700` 私密暂存、按需拉取固定摘要镜像并运行候选验证容器；
从原始规格重新生成候选，不执行归档 Compose、镜像环境文件或脚本。
累计及限额保留，历史流量键保留，旧核心 baseline 清空，超额账号在候选中停用。
成功、失败或中断均清理暂存，不安装部署或调度；这不同于完全只读的 `backup verify`。
同样的支持范围可通过菜单 `7 → 1 → 9` 应用，归档不是当前发布时仍需显式提供匹配资产：

```bash
padm-docker restore apply /root/padm-recovery.tar --confirm PADM-DOCKER-RESTORE
padm-docker restore recover
```

主控须先停机并隔离旧宿主，再通过维护菜单 `7 → 1 → 11/12` 或以下命令重建：

```bash
padm-docker restore preview /root/padm-recovery.tar --rebuild-controller
padm-docker restore apply /root/padm-recovery.tar --rebuild-controller --confirm PADM-DOCKER-RESTORE-CONTROLLER-ISOLATED
```

仅接受同架构 v3 空目标、完整 canonical WireGuard 和一致的原规格及发布状态；
v1 主控仍限单 Peer，v2 主控保留非空控制 Peer 集合及全部 WireGuard 项，所有已登记地址必须匹配。
归档不得含控制日志登记、来源现场、历史日志或持久同步授权。
保留账号、累计、API 端口及 WireGuard 密钥和地址，重新生成主控与所有 Peer 身份，
禁用并过期全部旧授权，版本从 `0` 开始；逐节点重新签发邀请后在各被控端显式执行 `control rebind`。
普通同步的旧身份、版本及凭据碰撞门禁继续生效。新身份不能撤销仍存活的旧副本，
故隔离旧宿主是恢复前提；不恢复原主控身份或覆盖已有部署。

首次业务写入前持久保存可信候选的停机输入、原空目录元数据和调度快照。
安装、健康检查、流量、Geo 或续期调度失败及 INT/TERM 时撤销本次恢复；登记发布后的 SIGKILL
可用菜单 `7 → 1 → 10` 或 `restore recover` 继续。普通部署命令在登记清理前拒绝运行。
恢复失败保留现场；外部调度被改写时拒绝覆盖。已提交事务的重试只清暂存，不停止服务。
流量、Geo 和续期分别持久保存调度快照；撤销前统一核对外部漂移，再按续期、Geo、流量的逆序恢复。
恢复中需要写回 systemd unit 时，unit 目录必须与部署私密暂存位于同一文件系统，
以便原子替换完整文件；跨文件系统在修改外部调度前拒绝。纯 cron 恢复不受此限制。
登记内的提交元数据及调度 source/build 暂存使用固定私密路径，半写或硬杀后
可随撤销或已提交清理重试回收，不按半写元数据认定提交成功。
准备阶段先创建私密登记，再创建精确登记的解包和候选目录；首次元数据半写、
解包或候选生成时遭硬杀，可由 `restore recover` 核对原空骨架、路径和权限后回收。
准备期接管不执行未验证的 Compose、不修改外部调度；未知暂存或篡改仍拒绝。
覆盖已有部署、其它持久输入、角色迁移、原生新宿主与完整灾备验收仍待交付。

## 用户流量与额度

Docker 菜单 `2 → 3. 流量与额度` 可查看已保存计数、立即采集并检查额度、
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

## 更新

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

## 回滚

```bash
padm-docker rollback
```

回滚只使用受管的最近一次 `update.*` 快照，默认退回一个版本，并同时恢复快照记录的控制脚本；旧快照没有控制 bundle 指针时只恢复部署配置和镜像，不猜测旧脚本版本。没有有效快照时直接失败，不猜测或拼接任意历史版本。已启用用户统计时，回滚目标 sing-box 必须具备 `with_v2ray_api`，否则会在停止现有部署前拒绝，避免丢失额度约束。回滚失败会尝试恢复当前版本，并保留备份路径供排障。
控制 bundle 必须声明支持快照规格版本；v2 快照不能交给仅支持 v1 的 bundle，v3 快照不能交给仅支持 v1/v2 的 bundle。合法旧版单核心快照仍可恢复，移除多余核心服务但保留累计流量。

## 卸载

```bash
# 停止并移除 Docker 控制命令；保留配置、数据、备份和镜像
padm-docker uninstall

# 在保留状态根的前提下，仅删除 deployment 记录中五个精确 digest 镜像
padm-docker uninstall --remove-images

# 生成最后备份后删除 /etc/padm-docker（不可逆，必须显式确认）
padm-docker uninstall --purge --confirm PADM-DOCKER-PURGE
```

普通卸载只清理本项目的 Compose 容器、网络和 CLI 链接，不执行全局 `docker prune`，也不删除其它 Compose project 或用户卷；脚本自动安装的 Docker Engine、Compose 插件和软件源不会由 `padm-docker uninstall` 卸载。`--purge` 仅删除带有效 Docker 模式标记的受管状态根；需要保留数据时不要使用它。
