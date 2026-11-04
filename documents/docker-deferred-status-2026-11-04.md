# Docker deferred 状态对账

日期：2026-11-04（北京时间）。

本表对齐 `docker/contracts/features.json` 的 14 个 `feature_matrix` deferred 项，
只修正原因和证据归属，不修改状态枚举、schema 或支持组合。36 项功能中的
13 个 supported、8 个 host-integrated、1 个 unsupported 保持；16 个公开协议的
`management_status` 已按实施计划 3D.26 为 supported。

本机代码项随实施计划 6A.23 收口。deferred 汇总了环境门槛、已声明限制和重复索引，
不能按行数当作待开发功能数。明确拒绝的组合不追加为原计划必须开发的需求。
原生证据只证明记录中的正式版本、固定客户端、架构、网络和操作；旧版通过既不
作废，也不自动覆盖当前源码或其它组合。失败原件及根因未定结论保持。

## 证据索引

以下链接指向受版本控制的说明；原始归档、摘要及独立核验结果由对应章节给出。

| 编号 | 证据与范围 |
| --- | --- |
| P | [实施计划](docker-menu-parity-plan.md)：4C.1–4C.14 双/三节点控制与 WireGuard；5B.4 路由、5B.5 中继/端口；5C.9 有限跳跃；6A.1–6A.23 灾备。使用各章固定快照与隔离 Linux amd64 证据，不等同原生多机。 |
| A | [原生记录](docker-native-acceptance-2026-10-18.md#2026-10-23-正式-webroot-issue-消费失败全链)：正式 3.41.4 webroot 新证书消费失败回滚；同文 standalone auto-renew、ALPN issue/同证书在线往返及 3.41.5 ALPN auto-renew、2026-10-24 单次 fresh ALPN 完整链。Debian 13 amd64、正式公网 Let's Encrypt；强制到期/fresh 不算自然续期。原件 `.tmp-native-acme-fullchain-20261023/`。 |
| S | [站点/ALPN 原生收口](docker-native-acceptance-2026-10-18.md#2026-10-24-站点与-fallback-alpn-原生收口)：3.41.5、Debian 13 amd64、bridge、公网 IPv4、Mihomo v1.19.28；13 阶段、57 正/35 拒绝，覆盖 Xray 27/29 三种 ALPN 顺序、三主题/特殊站名/302、主/组订阅与恢复。原件 `.tmp-native-sites-alpn-20261024/`。 |
| H | [HTTP relay 与公网 CA 集中补验](docker-native-acceptance-2026-10-18.md#http-relay-与公网-ca-集中补验)：原生外部 IPv4 访问三个 HTTPS 目标严格 TLS/200、错误认证 407、未允许来源 blocked；恢复原规格。原件 `.tmp-vps-native-20261018/evidence/native-closure-20261019.tar.gz`。 |
| R | [3.41.6 路由业务](docker-native-acceptance-2026-10-18.md#2026-10-24-3416-路由业务与失败态恢复)、同文纯 sing-box 发布共存/系统解析器回退陷阱，以及[路由与 UDP 合并真实重启](docker-native-acceptance-2026-10-18.md#2026-10-24-3416-路由与-udp-合并真实重启)。Debian 13 amd64、bridge、公网 IPv4、固定 Mihomo；旧整轮收尾失败保留，补验及新重启分别独核。原件 `.tmp-native-routing-combined-20261024/`、`.tmp-native-routing-publication-20261024/`、`.tmp-native-resolver-trap-20261024/`、`.tmp-native-routing-udp-reboot-20261024/`。 |
| U | [3.41.6 UDP 别名补验](docker-native-acceptance-2026-10-18.md#2026-10-24-3416-udp-别名最小补验)：固定 Mihomo、amd64、bridge、公网 IPv4 的 SS2022 默认别名/删除/基口恢复及 TUIC；9 正/7 拒绝。重启子项共用 R，不重复计数；原件 `.tmp-native-udp-close-20261024/`。 |
| C | [正式 443 共存公网复验](docker-native-acceptance-2026-10-18.md#2026-10-22-正式-443-共存公网复验)、同文三拓扑/XHTTP 双模式与[六点实际重启](docker-native-acceptance-2026-10-18.md#2026-10-23-visionxhttp-六点实际重启)。固定 Debian 13 amd64 的限定拓扑/客户端证据，不说明旧 reset/超时根因已修复；原件 `.tmp-native-topologies-20261022/`、`.tmp-native-reality-reboot-20261023/` 等。 |
| D | [原生已取得证据](docker-native-acceptance-2026-10-18.md#已取得证据)：固定 Cloudflare WS 地址、原 SNI/Host 的公网正反例，DNS 代理状态恢复；不等同 XHTTP/h3 或 gRPC 供应商透传。 |
| E | [VLESS Encryption 公网矩阵](docker-native-acceptance-2026-10-18.md#2026-10-24-vless-encryption-正式公网矩阵)及[双入口加密真实重启](docker-native-acceptance-2026-10-18.md#2026-10-24-双入口加密真实整机重启)：3.41.5、Debian 13 amd64、bridge、公网 IPv4、Xray 26.3.27/Mihomo v1.19.28；六阶段 28 正/38 拒绝、重启 16 正/32 拒绝，URI/材料/调度/累计与恢复通过。原件 `.tmp-native-vless-encryption-20261024/`、`.tmp-native-encryption-reboot-20261024/`。 |
| G | [原生记录](docker-native-acceptance-2026-10-18.md)：正式安装/首配、升级回滚、重启、卸载/purge 后同机 v3 空目标恢复，3.42.3 账号及业务备份/分享恢复整轮。账号/业务原件 `.tmp-native-account-close-20261027/`、`.tmp-native-business-close-20261027/`；不代表新主机或全组合。 |

## 14 项对账

“未决完成条件”只列既定范围内尚缺的证据；当前源码发布是一次共同门槛，
不得为每行分别重发、重启或重复跑全套。arm64/公网 IPv6 同样按实际适用组合集中验收。

| deferred 项 | 已有证据 | 未决完成条件 | 明确限制与重复归属 |
| --- | --- | --- | --- |
| `subscription-multiserver` | P：私网 API、单 Peer 迁移、v2 多被控逐节点管理、自动同步、隔离 amd64 双/三节点业务和授权隔离；6A.19/6A.23 新身份灾备。 | 匹配当前源码的可信发布；原生多机/arm64、适用重启及新主机灾备证据。 | v2 关联地址/密钥迁移、控制面 Fail2ban 拒绝，不新增开发。控制 API 无公网映射；公网业务验证不等于公开 API。灾备归 `interactive-menu`，宿主隧道归 `wireguard`。 |
| `acme-webroot` | P+A：稳定只读根与独占写入、归属/树校验、不停 Nginx；正式公网签发/在线换证及 3.41.4 新证书消费失败完整回滚。 | 真实登记自然到期续期；原生 arm64/公网 IPv6、当前版本尚未覆盖的适用生命周期。 | 自然续期与下一行共用一项门槛，约 2026-12-17 的窗口须以实际登记为准。no-op、强制到期、fresh 申请均不能替代自然到期。 |
| `acme-standalone` | P+A：HTTP-01/TLS-ALPN-01 及原拥有者暂停/恢复；正式签发、standalone/ALPN 消费失败回滚、ALPN 在线往返和单次 fresh 完整链。 | 同一 ACME 自然续期门槛；原生 arm64/公网 IPv6、当前其它适用生命周期。 | 仅暂停本部署原运行拥有者；站点 Fail2ban 的自监听停启仍拒绝。其它 CA/provider 不借本次证据扩大范围。 |
| `site-static-redirect-alpn` | P+S：模板/local/ALPN 事务及隔离双栈；固定正式 3.41.5 公网 13 阶段，包括特殊站名、302、订阅与完整恢复。 | 原生 arm64/公网 IPv6、其它既定适用组合和当前版本生命周期。 | Hy2 local 固定受管只读目录且无混淆，纯 Hy2 只开放 static。ACME 另行归属，不把公网站点/ALPN 重新列为完全未验。 |
| `entry-port-management` | P+U+R：多入口、额外端口、默认分享/原位改端口、内部端口专项；SS2022 公网 IPv4 默认别名/删除及限定合并重启。 | 原生 arm64/公网 IPv6、其它既定端口组合及当前版本适用生命周期。 | 与内部 207 共用别名证据。额外端口别名拒绝 WS/SSH Fail2ban、TUN/TProxy、host-network 组合；3D.26 已另行放行活动 WS 防护下未保护入口的基础增删改。跳跃限单 sing-box/单个双族入口/手动监督，不承诺 TUIC 客户端自动换端口或崩溃/开机恢复。 |
| `reality-coexistence` | P+C：受管、桥接宿主和 host 回环三拓扑恢复；限定公网 Vision/XHTTP 正反例与六点真实重启。 | 原生 arm64/公网 IPv6、其它既定共存组合及当前源码发布/生命周期。 | 一个 Xray Vision/XHTTP 后端，网站证书/内容仍由原维护方负责。旧 reset/超时根因未定；3D.26 协议管理 supported 不重列为缺口。 |
| `cdn-entry-management` | P+D：2/21/22/23/24/25 地址覆盖和链接/订阅投影；固定 Cloudflare WS 公网正反例。 | 既定 XHTTP/h3 与 gRPC 供应商透传、原生 arm64/公网 IPv6 和当前其它适用组合；gRPC 仍缺有效 Zone 条件。 | H3 只有使用说明，不新增开关、其它协议或自动建设外部 TLS/H3/CDN；WS 通过不外推其它传输。 |
| `interactive-menu` | P+G：6A.23 本机代码收口；3D.26 的 16 个公开协议管理 supported；正式安装/升级回滚/公网/重启、同机灾备及账号/业务恢复限定证据。 | 新原生主机灾备、arm64/公网 IPv6、当前源码可信发布，以及各所属专项尚缺的适用宿主生命周期。 | 汇总项，不重复计下属各行。已有部署替换、其它 ACME 材料、未处理输入、v2 关联迁移等保持拒绝，不追加开发。 |
| `routing-tools` | P+R：两核心 SOCKS5 TCP、DNS/hosts、Direct/Block、CN 与名单管理；sing-box 解析后阻断、pure 发布共存、DNS 拒绝回退和限定合并重启。 | WARP 真实 Cloudflare 账号/公网出口；原生 arm64/公网 IPv6、当前其它适用组合。 | 与内部 206 共用证据/条件；SOCKS 入站限制归内部 201。固定 Xray 解析后阻断拒绝；原生 CN 预设已覆盖，不追加任意国家向导或最终流量语义引擎。 |
| `internal-201-socks-relay` | P：5B.5b/5B.5b.1 已证固定 sing-box 的动态 BND/活动关联真实来源问题及 Xray 许可不随控制关闭撤销。 | 当前按限制关闭，无一轮普通环境回归可以使其成立；仅在相关核心行为变化后，重证发布、真实来源、会话鉴权及控制关闭撤销，才重新评估。 | 不开放完整入站、不降为 TCP-only、不增加辅助核心。host-network 不能修复鉴权。TCP 出站归 `routing-tools`；201 不作为公开节点协议。 |
| `internal-202-http-relay` | P+H：Xray 认证 HTTP/CONNECT、字面来源白名单、管理/回滚；隔离 amd64 双栈和原生外部 IPv4 三目标 TLS/200、407、来源拒绝。 | 公网 IPv6、原生 arm64、当前源码可信发布/适用生命周期。 | sing-box 信任 X-Forwarded-For 覆盖来源且无关闭选项，固定反例继续拒绝。专属直连、不计业务额度，不扩跨核心；202 不作为公开节点协议。 |
| `internal-206-routing-rules` | P+R，与 `routing-tools` 共用规则/名单、原生 IPv4 路由/DNS 拒绝回退及限定真实重启。 | 同 `routing-tools`：WARP 账号/出口、arm64/公网 IPv6 和当前其它适用组合，不重复计数。 | Xray 固定反例继续拒绝；只读重叠/覆盖不预测 GeoSite/DNS/最终流量。不追加任意国家/语义引擎；206 不作为公开节点协议。 |
| `internal-207-access-control` | P+U+R，与 `entry-port-management` 共用发布别名、默认分享/原位修改及固定原生公网 IPv4/重启证据。 | 同端口管理的原生 arm64/公网 IPv6、其它既定组合及当前源码发布/生命周期，不重复计数。 | 只复用已有入口认证、统计及 TLS/SNI，不做任意目的转发。拒绝宿主组合保持原边界；207 不作为公开节点协议。 |
| `vless-encryption` | P+E：配对/投影/marker/失败恢复，固定正式 3.41.5 amd64 公网启停与普通 bridge 双加密入口真实重启。 | 其它既定客户端/算法、原生 arm64/公网 IPv6、其它拓扑和当前源码发布/适用生命周期。 | 只按固定 Xray/Mihomo 组合及 schema 3 Reality 1/2 实验范围使用。不能与 3D.26 的 ML-DSA-65 证据相互替代；未验组合不暗中开放。 |

## 本轮更新边界

本轮补齐了“已有原生/公网/重启证据”的版本与环境限定，未把旧版成功外推当前全组合，
deferred 对账本身未改 14 个状态、协议支持状态、schema 或运行逻辑。
本轮 ML-DSA-65 XHTTP 客户端正反例、Nginx/WS 整轮结果及已确认的跨核心 gRPC
不兼容边界、正式旧包失败、本地 Chrome 候选及独立构建修订整轮通过见
实施计划 3D.27；不以局部通过外推其它组合或整轮成功。当前源码发布等后续证据，
应在所属章节和原生记录取得后再引用；修订构建已接入，仍待原生 arm64 验收、
发布及 lock 刷新，不要求重复已有成功叶子或每行各跑一次全量回归。
