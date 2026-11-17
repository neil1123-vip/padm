# Docker deferred 状态对账

初始对账：2026-11-04；更新至 2026-11-18（北京时间）。

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
| F | [实施计划 3D.27](docker-menu-parity-plan.md#3d27-新增管理能力真实验收与-deferred-对账)：正式 `3.43.4` 可信发布、来源及五镜像绑定；Debian 13 amd64/bridge/IPv4 的 `.2 → .4` 升级和固定 WS 公网正负例；固定 amd64/IPv4/Reality/gRPC/chrome/pgxn.org 的 ML-DSA 正式 CLI 公网四阶段及重建；同 IP、同证书别名独立 SNI 仅隔离整链。11-08 次日只读复核通过，不替代宿主重启、实际回滚或长稳。原件 `.tmp-release-3434-20261107/`、`.tmp-vps-upgrade-3434-20261107/`、`.tmp-mldsa-public-3434-20261107/`、`.tmp-mldsa-sni-3434-20261107/`、`.tmp-vps-post-upgrade-3434-20261108/`。 |
| B | [实施计划 6A.29–6A.32](docker-menu-parity-plan.md)：正式 `3.43.7` 可信发布；独立 B Debian 13 amd64/bridge/IPv4 的原 `.4` 归档预览与自动清场、外部续期隔离、正式恢复、公网 Xray WS 443 正反例及单次整机重启通过。控制入口为 `.7`，业务与五镜像保持原 `.4`；公网经 A 临时 SSH TCP 转发，不计 Windows 直连或原生 URI 导入。原件 `.tmp-release-3437-20261116/`、`.tmp-native-dr-preview-3437-20261116/`、`.tmp-native-dr-acme-isolation-20261116/`、`.tmp-native-dr-apply-3437-20261116/`、`.tmp-native-dr-reboot-3437-20261116/`。 |
| W | [实施计划 6A.35–6A.48](docker-menu-parity-plan.md)：A/B Debian 13/amd64/IPv4 单 Peer 的正式 WG 准备、配对、首次启用、停启、加密及原规格恢复通过，密钥精确手工清场，业务/账目/隔离保持。另在可销毁、完整独立内核/systemd/Engine 的双 QEMU guest 上，正式 `.7` 的账号增删、原 systemd 自主传播及严格 TLS 业务通过；6A.39 补齐单 Peer 控制角色/WG 启用态双 guest 真实重启、7 个原容器自然恢复、重启后自主删除、六组 TLS 正反例及累计。6A.40 补齐固定地址密钥/端口迁移；6A.41 补齐关联改址撤权、新地址拒绝旧凭据、新邀请恢复及原日历自主传播、六组 TLS 和计量，两段均正常关机。6A.41 的 source-check rc 15 保留失败。6A.42 补齐固定本地主控改址的真实 bind 失败恢复、持故障恢复旧址及仅撤权、新邀请同版同步、原调度与业务；两次验收断言失败原判保持，三次正常关机，未重测自主传播。6A.43 只定位新跟踪轮在相等快照后的 30 秒相对时限检查拒绝，不证明原失败同因。6A.44 补齐预加载正式 helper 条件下的固定本地 server fresh 见证；6A.45 另补完整 Peer CLI 预热及当前 nonce 的正式 CLI/主控 rc 0 闭环，首轮准备失败保留、锁 owner 未查无归因，30 秒窗不变。6A.46 补齐固定本地单 Peer 的全新空目标正式恢复、新控制身份/rebind、WG 身份保持、原日历自主传播及 TLS/计量；恢复联网、独验断网，3002 份原件绑定。6A.47 单次正式防护启用 rc 14、未 verified，随后新 child 断网恢复审计通过；窗口内原回执不定位拒绝分支，首轮审计遇锁失败保留，不重复 enable，防护未通过。6A.48 补齐实际候选切换后 pidfd TERM、rc 143、旧址/WG 恢复及撤权、新邀请/原调度和 TLS/计量，断网独验 1439 份。只关闭上述固定子项，不等同其它信号/断电及其它故障、公网多机、arm64/IPv6、多 Peer 重启/灾备。原件 `.tmp-native-wg-cli-20261116/`、`.tmp-native-control-readiness-20261116/`、`.tmp-native-control-vms-20261116/`。 |
| K | [实施计划 6A.66](docker-menu-parity-plan.md#6a66-正式-v3438-双-kvm-升级与控制防护完整恢复)：正式 `.8`/`6e880813`、本地 Debian 13 amd64/IPv4/单 Peer KVM 双机，完整升级、控制防护及严格恢复通过。六次真实下载、每机 312 个 payload 文件和五镜像绑定、真实 22 次 401 封禁/DROP/解封、启停后 TLS/计量、终态安全及 Peer 清场均通过；稳定 `.8` before 全文件精确恢复，无候选元数据例外。断网独验绑定 1940 份本轮/基线证据、17 负控通过；正常关机、父盘保持。6A.65 候选及 6A.47、6A.64 旧失败保持；根目录权限和其余环境边界见原节。原件 `.tmp-formal-control-3438-20261117/`。 |
| N | [6A.67](docker-menu-parity-plan.md#6a67-正式原生-arm64-宿主生命周期整轮) 的原生 Ubuntu ARM64/IPv4/Xray WS 正式 `.7/.8` 七阶段、22 客户端及 56 工件独验通过。另补 [6A.68](docker-menu-parity-plan.md#6a68-正式-arm64-engine-自动安装与纯-sing-box-生命周期)：移除 runner 预装包后，正式 `.44` 入口自动安装官方 Docker 29.10.0/Compose 5.7.2；纯 sing-box Trojan TLS/id 28 的 `.8/.44` 七阶段、22 严格 TLS 客户端、两账目/额度/计量、10 ARM64 index/manifest 与实际镜像、业务材料及精确清场通过，69 份工件断网只读独验及 19 负控通过。再补 [6A.69](docker-menu-parity-plan.md#6a69-正式-arm64-入口路由中继与站点集中专项)：正式 `.44`/Xray 29+sing-box 28 的别名/默认分享、双核心路由、Xray HTTP/严格 HTTPS CONNECT、站点/ALPN 和服务重启；58 检查/六 checkpoint、126 工件断网只读独验、31 组件及 19 完整工件负控通过。[6A.70](docker-menu-parity-plan.md#6a70-正式-arm64-reality-共存与-vless-encryption-集中验收) 补齐固定 `.44` 的 Reality Vision/XHTTP 三拓扑共存、普通 bridge 双入口 Encryption 启停/恢复、三次服务 restart 及正反例；19 checkpoint/64 proxy/16 site/29 辅助采样、292 工件断网只读独验、46 组件及 41 完整工件负控通过。Mihomo 限显式 hybrid 投影，不称原 URI 导入通过；首次 spec 仅语义恢复，旧失败保留，第六轮 CI 成功仍因 12 relay reset 被独验拒绝。业务 origin 仅本地 lo；受管站点用测试 CA，host/loopback 本地 443 透明中继至固定 A HTTPS 后端，不计 ARM64 公网入站、不传生产私钥。无宿主重启，不外推裸 OS、IPv6、其它既定组合。原件 `.tmp-native-arm64-host-20261117/`、`.tmp-native-arm64-singbox-20261117/`、`.tmp-native-arm64-specialties-20261117/`、`.tmp-native-arm64-reality-20261117/`。 |

M：[6A.71](docker-menu-parity-plan.md#6a71-正式本地三节点控制验收与-icmp-首配阻塞)
补齐正式 `.44` 本地 Debian 13 amd64/IPv4 的一主两被控、6 次原 timer 自主
同步、16 次业务探测、三机整机重启和单 Peer 撤权隔离；3986 份原件断网
只读独验通过，三机正常关机。
[6A.72](docker-menu-parity-plan.md#6a72-正式本地双-peer-主控新机灾备)
另补固定本地双 Peer 空白替代主控：新控制身份、旧邀请失效、双端显式
重绑及原 timer 自主传播、严格 TLS/计量通过；1697 份原件断网只读独验，
四机正常关机。固定本地三节点重启和双 Peer 主控新机灾备缺口关闭，
不替代公网多机、其它拓扑或灾后重启。

## 14 项对账

“未决完成条件”只列既定范围内尚缺的证据；多 Peer 新主机灾备不再包括 M 的固定本地双 Peer 组合。正式 `3.43.4`、`3.43.7` 与 `3.43.8` 的共同可信发布门槛
已取得，见 F、B 及[distroless 正式发布独验](docker-distroless-baseline.md)；不替代各专项尚缺的原生环境、宿主生命周期或新主机灾备证据，
不为每行重复发布或跑全套。arm64/公网 IPv6 同样按实际适用组合集中验收。

| deferred 项 | 已有证据 | 未决完成条件 | 明确限制与重复归属 |
| --- | --- | --- | --- |
| `subscription-multiserver` | P：私网 API、单 Peer 迁移、v2 多被控逐节点管理、自动同步、隔离 amd64 双/三节点业务和授权隔离；6A.19/6A.23 新身份灾备。W 补齐原生固定单 Peer 隧道，以及正式 `.7` 本地独立完整内核双机的账号自主增删、启用态真实重启、固定地址密钥/端口迁移、关联改址撤权、新邀请恢复、原日历自主同步、业务和累计；6A.42 另补主控改址真实 bind 失败恢复、仅撤权及新邀请同版同步；6A.44 的预加载 helper 与 6A.45 的完整 Peer CLI 预热条件分别补齐固定本地 server fresh 见证。6A.46 补齐固定本地 amd64/IPv4/单 Peer 角色/WG 新机恢复、新控制身份/rebind 及自主同步、TLS/计量；6A.47 补齐正式防护启用失败后的固定本地恢复审计；6A.48 补齐固定本地实际迁移切换后 TERM 恢复、撤权、新邀请/原调度与业务。K 另补正式 `.8` 本地双 KVM 完整升级、防护及严格恢复。 | 公网多机控制同步、arm64/IPv6、多 Peer 新主机灾备及适用重启证据；新机恢复联网，不计断网恢复。6A.47 原 enable rc 14 保持，不定位拒绝分支；本地正式 `.8` 防护已由 K 补齐。6A.41/6A.43 失败保持且原失败同因未证，准备/审计遇锁未查 owner；TERM 只补固定本地单 Peer，不外推其它信号/断电及其它故障或长稳。 | v2 关联地址/密钥迁移、控制面 Fail2ban 拒绝，不新增开发。控制 API 无公网映射；公网业务验证不等于公开 API。灾备归 `interactive-menu`，宿主隧道归 `wireguard`。 |
| `acme-webroot` | P+A：稳定只读根与独占写入、归属/树校验、不停 Nginx；正式公网签发/在线换证及 3.41.4 新证书消费失败完整回滚。 | 真实登记自然到期续期；原生 arm64/公网 IPv6、当前版本尚未覆盖的适用生命周期。 | 自然续期与下一行共用一项门槛，约 2026-12-17 的窗口须以实际登记为准。no-op、强制到期、fresh 申请均不能替代自然到期。 |
| `acme-standalone` | P+A：HTTP-01/TLS-ALPN-01 及原拥有者暂停/恢复；正式签发、standalone/ALPN 消费失败回滚、ALPN 在线往返和单次 fresh 完整链。 | 同一 ACME 自然续期门槛；原生 arm64/公网 IPv6、当前其它适用生命周期。 | 仅暂停本部署原运行拥有者；站点 Fail2ban 的自监听停启仍拒绝。其它 CA/provider 不借本次证据扩大范围。 |
| `site-static-redirect-alpn` | P+S+N：模板/local/ALPN 事务及隔离双栈；固定正式 3.41.5 公网 13 阶段，包括特殊站名、302、订阅与完整恢复。N/6A.69 补正式 `.44` 原生 ARM64/Xray 29 的三模板/特殊标题、static/302、三种 ALPN 顺序、实际 HTTP/2 和服务重启。 | 公网 IPv6、其它既定 ARM64/协议组合及尚缺的适用生命周期；固定本地 origin 不计 ARM64 公网。 | Hy2 local 固定受管只读目录且无混淆，纯 Hy2 只开放 static。ACME 另行归属，不把公网站点/ALPN 重新列为完全未验。 |
| `entry-port-management` | P+U+R+N：多入口、额外端口、默认分享/原位改端口、内部端口专项；SS2022 公网 IPv4 默认别名/删除及限定合并重启。N/6A.69 补正式 `.44` 原生 ARM64/sing-box Trojan 的别名/默认分享/原位替换/删除及基口恢复，双核心恢复和服务重启业务通过。 | 公网 IPv6、其它既定 ARM64/端口组合及尚缺的适用生命周期；固定本地 origin 不计 ARM64 公网。 | 与内部 207 共用别名证据。额外端口别名拒绝 WS/SSH Fail2ban、TUN/TProxy、host-network 组合；3D.26 已另行放行活动 WS 防护下未保护入口的基础增删改。跳跃限单 sing-box/单个双族入口/手动监督，不承诺 TUIC 客户端自动换端口或崩溃/开机恢复。 |
| `reality-coexistence` | P+C+N：受管、桥接宿主和 host 回环三拓扑恢复；限定公网 Vision/XHTTP 正反例与六点真实重启。N/6A.70 补正式 `.44` 原生 ARM64/IPv4 的三拓扑 × 双入口、关闭恢复、loopback 服务 restart 及正反例。 | 公网 IPv6、ARM64 整机重启、其它既定共存组合及当前版本尚缺的适用生命周期；本地入口与公网网站后端不等于 ARM64 公网入站。 | 一个 Xray Vision/XHTTP 后端，网站证书/内容仍由原维护方负责。N 的 host/loopback 仅经本地透明 TCP relay 到固定 A HTTPS 后端，不传生产私钥；旧 reset/超时不因本轮成功改判，3D.26 协议管理 supported 不重列为缺口。 |
| `cdn-entry-management` | P+D：2/21/22/23/24/25 地址覆盖和链接/订阅投影；固定 Cloudflare WS 公网正反例。 | 既定 XHTTP/h3 与 gRPC 供应商透传、原生 arm64/公网 IPv6 和当前其它适用组合；gRPC 仍缺有效 Zone 条件。 | H3 只有使用说明，不新增开关、其它协议或自动建设外部 TLS/H3/CDN；WS 通过不外推其它传输。 |
| `interactive-menu` | P+G+B+W+K+N：6A.23 本机代码收口；3D.26 的 16 个公开协议管理 supported；正式安装/升级回滚/公网/重启、同机灾备及账号/业务恢复限定证据；B 正式 `.7` 从原 `.4` 归档完成固定 Xray WS 新主机恢复和单次整机重启。6A.46 另补本地完整独立内核双机的 amd64/IPv4/单 Peer 新机角色/WG 恢复、新身份/rebind、自主同步和 TLS/计量；K 补齐正式 `.8` 本地双 KVM 完整升级、防护及严格恢复；N 补齐 Ubuntu ARM64/IPv4/Xray WS `.7/.8`、纯 sing-box Trojan `.8/.44` 七阶段及 `.44` 官方 Engine 自动安装和清场，6A.69 再补固定 `.44` 入口/路由/中继/站点四类专项及服务重启，6A.70 补固定 Reality 三拓扑与普通 bridge 双入口 Encryption 集中验收、恢复及三次服务 restart。 | 自然续期、ARM64 其它既定组合及整机重启、公网 IPv6、其它核心/协议及发行版适用安装、公网多机/多 Peer 角色/WG 新主机灾备与各专项尚缺的适用生命周期。 | 汇总项，不重复计下属各行。N 的原点限本地 lo、host/loopback 站点限本地中继至固定公网后端，不计 ARM64 公网入站。已有部署替换、其它 ACME 材料、未处理输入、v2 关联迁移等保持拒绝，不追加开发。 |
| `routing-tools` | P+R+N：两核心 SOCKS5 TCP、DNS/hosts、Direct/Block、CN 与名单管理；sing-box 解析后阻断、pure 发布共存、DNS 拒绝回退和限定合并重启。N/6A.69 补正式 `.44` 原生 ARM64/Xray 29+sing-box 28 的 SOCKS 全局/选择匹配/绕过/认证拒绝、DNS/hosts、Direct/Block 及恢复/服务重启。 | WARP 真实 Cloudflare 账号/公网出口；公网 IPv6、其它既定 ARM64/路由组合及尚缺的适用生命周期。 | 与内部 206 共用证据/条件；SOCKS 入站限制归内部 201。N 的 DNS 错误拒绝不单独证明系统解析器无回退。固定 Xray 解析后阻断拒绝；原生 CN 预设已覆盖，不追加任意国家向导或最终流量语义引擎。 |
| `internal-201-socks-relay` | P：5B.5b/5B.5b.1 已证固定 sing-box 的动态 BND/活动关联真实来源问题及 Xray 许可不随控制关闭撤销。 | 当前按限制关闭，无一轮普通环境回归可以使其成立；仅在相关核心行为变化后，重证发布、真实来源、会话鉴权及控制关闭撤销，才重新评估。 | 不开放完整入站、不降为 TCP-only、不增加辅助核心。host-network 不能修复鉴权。TCP 出站归 `routing-tools`；201 不作为公开节点协议。 |
| `internal-202-http-relay` | P+H+N：Xray 认证 HTTP/CONNECT、字面来源白名单、管理/回滚；隔离 amd64 双栈和原生外部 IPv4 三目标 TLS/200、407、来源拒绝。N/6A.69 补正式 `.44` 原生 ARM64 的认证 HTTP/严格 HTTPS CONNECT、改端口、HTTP/CONNECT 来源拒绝、关闭及业务恢复；负例原点 TCP/请求为零。 | 公网 IPv6、其它既定 ARM64/中继组合及尚缺的适用生命周期；固定本地 origin 不计 ARM64 公网，第二轮空成功异常根因未定。 | sing-box 信任 X-Forwarded-For 覆盖来源且无关闭选项，固定反例继续拒绝。专属直连、不计业务额度，不扩跨核心；202 不作为公开节点协议。 |
| `internal-206-routing-rules` | P+R+N，与 `routing-tools` 共用规则/名单、原生 IPv4 路由/DNS 拒绝回退及限定真实重启；N/6A.69 另补固定正式 `.44` ARM64 双核心规则及服务重启。 | 同 `routing-tools`：WARP 账号/出口、公网 IPv6、其它既定 ARM64/路由组合及尚缺的适用生命周期，不重复计数。 | Xray 固定反例继续拒绝；只读重叠/覆盖不预测 GeoSite/DNS/最终流量。不追加任意国家/语义引擎；206 不作为公开节点协议。 |
| `internal-207-access-control` | P+U+R+N，与 `entry-port-management` 共用发布别名、默认分享/原位修改及固定原生公网 IPv4/重启证据；N/6A.69 另补正式 `.44` ARM64/sing-box Trojan 别名与双核心恢复/服务重启。 | 同端口管理的公网 IPv6、其它既定 ARM64/端口组合及尚缺的适用生命周期，不重复计数。 | 只复用已有入口认证、统计及 TLS/SNI，不做任意目的转发。拒绝宿主组合保持原边界；207 不作为公开节点协议。 |
| `vless-encryption` | P+E+N：配对/投影/marker/失败恢复，固定正式 3.41.5 amd64 公网启停与普通 bridge 双加密入口真实重启。N/6A.70 补固定正式 `.44` 原生 ARM64/IPv4 普通 bridge 双入口的五阶段启停/服务 restart/恢复、精确错误配对与旧 none/错误 encryption 拒绝，正式 Xray 与 Mihomo v1.19.28 显式 hybrid 正例通过。 | 其它既定客户端/算法、Mihomo 原 URI 直接导入、ARM64 整机重启/公网入站/IPv6、其它拓扑的加密生命周期及当前版本尚缺的适用生命周期。 | 只按固定 Xray/Mihomo 组合及 schema 3 Reality 1/2 实验范围使用；N 固定显式 X25519MLKEM768，不宣称原 URI 导入成功。不能与 3D.27/F 的 ML-DSA-65 签名验证证据相互替代；未验组合不暗中开放，旧失败和 curl 28 不改判。 |

## 本轮更新边界

本表已对齐正式 `3.43.4` 的 VPS 升级、公网 ML-DSA 和有限独立 SNI，以及正式
`3.43.7` 的可信发布和 B 恢复/重启证据，见 F、B；旧版专项成功只保留其版本与环境范围。
11-08 次日只读复核的 32 项比对及 3 个反例自检通过；三容器 healthy、生命周期、
业务材料/权限及 timer 保持，19 个账号身份/限额不变、累计与升级后基线相同。
该次只读复核不证明新一轮公网业务、自然流量增长或长稳；A 的 `.4` 升级验收未重启
宿主，恢复点校验通过不等于实际回滚。错 pqv 仅证明受控零有效期 X.509 拒绝，不称直接 ML-DSA 错误日志。
旧失败原件、客户端超时/false 原值及跨核心 gRPC 不兼容结论保留。
其它指纹/核心/算法、arm64 Reality 整轮、真实公网 IPv6 及 hybrid-only 未证明；
同 IP/同证书别名 SNI 的隔离通过不外推跨站点或公网独立 SNI。
本表不改变 14 个 deferred 状态、协议支持状态或 schema，也不要求每行重复全量回归。

11-15 至 11-16，6A.26 的独立 B 安装、授权敏感归档 A→B 传输、损坏拒绝及清场通过。
原 `.4` 正确 preview 的 jq 1.7 语法失败（exit 15）和 `.6` 预览后的默认网络遗留失败
保持原判；修复后正式 `.7` 的可信发布、原归档预览与自动清场通过，见 6A.29。
`.7` 发布清单沿用 `.5` 五镜像引用，未新建镜像或新增 smoke。

6A.30–6A.32 已完成 B 外部续期隔离、正式 apply、公网 WS 正反例和单次整机重启。
原 `.4` 归档及其清单/签名/控制包、业务与五镜像未升级；规格/分享、19 条保存账目
身份/额度/历史累计、TLS/续期/Geo 和 9 份规范化 ACME 内容及权限保持。
原三个业务容器自然 healthy、无 OOM，两个 timer active/enabled；隔离先于 Docker
自然启动，默认桥阻断及业务网对照通过。A 仍为 `.4`，业务、材料、调度与 DNS 未改。
公网经 A 临时 SSH TCP 转发且已清场，不计 Windows 直连或原生 URI 导入通过。

本轮只关闭固定 Debian 13/amd64/bridge/IPv4/Xray WS 443 的恢复与单次重启子项。
B 保留恢复部署及续期隔离，nftables 重载仍可能清表；真实自然续期、arm64/IPv6、
其它核心/协议、控制角色、WG/多 Peer 新机恢复及长稳未验，16 supported/14 deferred 不变。

6A.35 的固定原生双机单 Peer WG 闭环见 W，不把全部原生多机网络笼统称为未验。
6A.36 两端只读审计区分了 0 个显式账号与 19 条历史账目；空账号无已知碰撞阻碍，
正式接入仍须先恢复受管 WG；无角色退出入口，退回须空目标灾备及最新业务合并。
按当前流程估算，真实账号增删传播
与完整恢复至少 13 次业务重建并另有清空停服；新账号也会进入历史账本。
该成本审计未执行同步矩阵，不把 timer 空同步记为真实账号传播。

6A.38 随后使用可销毁的完整独立内核双机完成正式 `.7` 单 Peer 账号新增与删除、
原 systemd 日历自主传播及四组严格 TLS 业务；22 份安装源码、10 份镜像和 351 份
原件绑定通过，三次失败保留，两 guest 正常关机。未连接或修改 A/B；隔离原点别名
不是公网业务，不将该固定本地组合外推公网多机、arm64/IPv6、启用态重启或灾备。

6A.39 随后补齐同一正式 `.7` 固定单 Peer 控制角色/WG 的双 guest 启用态真实重启：
两 boot 的双向加密、原 7 个容器自然恢复、重启后自主删除、六组严格 TLS 正反例与
全量下载计量增量通过；`2 → 3 → 4` 的传播分别绑定原日历和同 boot invocation。
首轮 Docker 自动更新中断保留为失败，重跑通过后两 guest 正常关机；断网独验绑定
1029 份原件并复核原 351 份证据。本项不使用或修改 A/B，不扩大公网、多 Peer、
迁移、新机灾备或长稳范围，支持状态不变。

6A.40 随后补齐固定地址下的双端密钥/端口迁移、持久 endpoint、原邀请与
原日历恢复后的自主修改传播；迁移前新增仅手动同步基线，不计自主传播。
六组严格 TLS、迁移后完整正文计量与正常关机通过；断网独验绑定 837 份原件，
复核旧 351 份证据。未连接或修改 A/B；正式完整内核的关联改址/迁移失败恢复、
新机灾备、公网多机及其它架构仍未验，16 supported/14 deferred 不变。

6A.41 随后补齐同一固定单 Peer 的正式关联改址、主控自动撤权、新地址旧 token
401 与旧邀请 rc 10 拒绝、新邀请同身份恢复、原日历 `4 → 5` 自主传播及六组严格
TLS/完整正文计量。首轮 source-check 返回 rc 15，probe 与回执命中仍不计见证
通过；保留失败并正常关机，从其新 child 接续，不重做迁移、不扩大 30 秒窗口。
断网独验共绑定 1222 份原件，其中复核前轮 837 份；两段均正常关机，无活动 guest。
未连接或修改 A/B；fresh 来源见证、控制面防护、完整内核迁移失败恢复、新机灾备、
公网多机和其它架构范围不扩大，16 supported/14 deferred 不变。

6A.42 随后补齐固定本地正式单 Peer 主控关联改址的真实 bind 失败恢复：
候选规格、持久配置与实际内核地址确已切换，同一 control 容器因端口冲突
die 78/Errno 98，正式 CLI rc 14 恢复旧 tuple；故障持续到旧址 healthy/no-op
之后才释放。原身份、密钥、版本 5、账号及 TLS 保持，主控仅撤权两字段。
两次验收脚本断言错误分别保留 exit 1，正常关机后从新 child 接续，不重跑迁移；
旧 token 401、旧邀请授权失配 rc 11、新邀请同版无变化同步、原调度与四组严格
TLS/完整正文计量通过，本轮未重测自主传播。断网独验共绑定 1634 份原件，
其中复核前轮 1222 份，故障归档 29 项；三次正常关机，无活动 guest。
未连接或修改 A/B；只关闭上述固定故障子项，不外推信号/断电、其它故障、
fresh 来源见证、新机灾备、公网多机、其它架构或长稳，16 supported/14 deferred 不变。

6A.43 从 6A.41 原失败后正常关机磁盘新建 child，保持正式 `.7`，不重跑迁移。
两次准备失败分别为 guest 启动前的 NameError、来源检查前的 timer 状态误断言，
原 exit 1/1 保持；最后仅执行一次正式来源检查，rc 15，不产生 source-verified。
helper 回执 verified、第二次快照相等，随后 30 秒相对时限检查立即拒绝；
EXIT 清理进入和退出均为 15，后续墙钟/登记检查未执行。默认 xtrace 缺逐行计时，
只证明本轮分支，不认定原 6A.41 同因，也不计 fresh 见证或防护通过。
断网独验绑定 1384 份原件，其中复核前轮 1222 份；两次启动双机均正常关机、
父盘摘要保持，最终无活动 guest，敏感 trace 仅留私密卷。
未连接/修改 A/B、改变源码/合同/支持状态、重复回归、重启生产、推送或发布。

6A.44 随后从 6A.41 原失败父盘的新 child，先在正式 ops 镜像内预加载
`control_client.source_probe` 等待 stdin nonce，再执行原正式主控 source-check。
错 nonce 不产生当前 nonce 回执且挑战仍在；当前 nonce 得到唯一回执及
source-verified，主控 CLI rc 0。镜像 ID、helper 与发布 bundle 摘要绑定，
临时探测容器无挂载/密钥、exit 0 且已清场；前后规格/文件/服务/WG 身份/限额
保持，累计不降，双端 WG 收发增长。单次驱动 147.905 秒、正常关机 6.870 秒，
父盘摘要保持、无强停/活动 guest。断网独验绑定 1490 份原件，其中重核旧 1384 份。
只关闭预加载 helper 条件下的固定本地 server fresh 见证；完整 peer source-probe
CLI、防护和原失败同因未证，30 秒窗不变，旧失败不改判。未连接/重启 A/B、
修改运行源码/合同/支持状态、重复回归、推送或发布，16 supported/14 deferred 不变。

6A.45 另从原父盘新建 child，以全零 dummy nonce 完整执行正式 Peer
source-probe CLI rc 0，预热前后回执 inode/字节数/摘要/mode/uid/gid 及场景
完全不变。首轮随后仅见部署锁仍在，临时目录/探测容器为空，准备断言失败，
未执行主控 source-check、当前 nonce probe 或生成 result；锁 owner 未查，
不归因 timer 或探测 CLI 遗留，原失败及正常关机原件保留。
清场改为最长 110 秒只读观察、连续两次稳定，未删锁或停 timer；唯一新轮
再次新建 child，dummy 完整 CLI rc 0 且回执不变，清场后启动原正式主控检查。
新 challenge 后当前 nonce 的完整 Peer CLI rc 0、主控 rc 0，唯一 verified
与同 nonce 唯一回执匹配，最终挑战/临时材料/容器/锁稳定清场。
前后规格/文件/服务/WG 身份/限额保持、累计不降、双端 WG 收发增长；
驱动 149.230 秒、正常关机 5.131 秒、父盘摘要保持。断网独验 exit 0、
passed true，绑定 1691 份原件，其中重核旧 1490 份。
仅补固定本地单 Peer、完整 CLI 预热条件的 fresh 见证；旧失败不改判，
原失败同因、稳定可靠性及控制面防护未证，原 30 秒窗不变。
未连接/重启 A/B 或修改支持状态，新机灾备仍缺，16 supported/14 deferred 不变；
公开摘要 `.tmp-native-control-vms-20261116/source-cli-warm-verification.json`。

6A.46 随后补齐正式 `.7` 固定本地 amd64/IPv4/单 Peer 的新机角色/WG 恢复。
旧源正式停同步、清授权/unit、collect/export/verify 后正常关机隔离；
从官方 Debian base 建双空目标，新 machine/SSH/Engine 身份、初始无 PADM/Docker
数据、每机 13 份源码及五镜像绑定通过。双端正式 preview 不落地、apply 成功，
主控显式 rebuild 换控制身份、revision 0 并撤权，WG 身份/地址/密钥和业务/额度/累计保持。
旧 token 两次 401，旧邀请与新邀请普通 sync 均 rc 11；显式 rebind 后原日历
`OnCalendar=*-*-* *:0/5:15` 同 boot、无 drop-in 自主 `0 → 1`。
严格 TLS 错 UUID 零原点请求，managed/core 正文 311296/286720 字节及计量增量通过。
源导出人读输出误按 JSON 解析、首次恢复误要求重生成文件与源字节相等两次驱动
失败保留，均正常关机；重生成 deployment/spec 的精确摘要断言经 2 正/4 篡改反例核对。
独验初稿 glob 误命中 `schedule-status-after` 的 exit 1 保留，改为 metadata.label
精确检查后仅重跑独验；成功恢复 1124.161 秒、正常关机 6.978 秒、QEMU exit 0/0，
父盘及官方 base 摘要保持。正式恢复联网按 digest pull，仅事后独验断网，
最终 exit 0、passed/restore_verified true，绑定 3002 份原件；重核旧 CLI 1691 份和
rollback 1634 份，集合重叠、不相加，七个容器均退出且无 OOM，私密卷无活动容器。
公开摘要 `.tmp-native-control-vms-20261116/dr-verification.json`，
SHA-256 `2af6eb5d6d37d2b5d86bd8575db58c32ad52472d57f071d46bb963331a5d2b39`。
未连接/重启 A/B，未改运行源码/合同、重复回归、推送或发布；
公网多机、多 Peer、arm64/IPv6、其它核心、信号/断电、控制面防护及长稳仍缺，
原 30 秒窗口及 16 supported/14 deferred 不变，旧失败不改判。

6A.47 单次正式控制防护 enable 返回 rc 14，唯一 challenge 的完整 Peer
source-probe CLI rc 0，主控无 source-verified，原失败保持；完整命令
302.077 秒含正式下载/部署，不作为 challenge 耗时。
随后只从失败后正常关机盘另建 child 审计恢复，不重复 enable。
首轮恢复不变量通过后遇部署锁断言失败，未进入业务；正常关机 6.000 秒，
未采集 owner，不归因 timer/CLI 遗留。仅改为最长 110 秒只读清场观察，
连续两次无部署锁/挑战/临时材料后继续，不删锁或停 timer。
最终 network none 审计通过：规格/文件/源码与实际镜像、WG 身份/地址/端口、
调度和额度保持，累计不降、双向加密收发增长；无 jail/owner/控制规则残留，
WS 资源保持，挑战、临时材料、锁及 Peer 探测容器稳定清场。
严格 TLS 错 UUID 零原点请求；managed/core 正文 303104/278528 字节及
managed 计量增量通过。原唯一同 nonce 回执时间在原窗口内，不能定位具体拒绝分支，
也不证明旧失败同因。最终审计 144.083 秒、正常关机 5.288 秒，
QEMU exit 0/0、父盘摘要保持；原启用正常关机 8.901 秒，全部原失败保持。
独验首稿误要求已停用的 Peer timer active/enabled，exit 1 保留；改为原
inactive/空 UnitFileState 精确状态后，只重跑断网独验，最终 exit 0。
绑定 1994 份原件（重核旧 1691 份），recovery_audit_passed true，
整体 passed/control_protection_verified/failure_branch_proven 均 false。
五容器均退出、无 OOM，专用卷无活动容器；公开摘要
`.tmp-native-control-vms-20261116/protection-verification.json`，
SHA-256 `5a33de750c8e5b9bc811c1f072f493371379fe8939067528002ae9083e87a9cc`。
只补固定本地 amd64/IPv4/单 Peer 的失败恢复，不计控制防护通过；
未改运行源码/合同/支持状态、重复回归、推送或发布，未连接/重启 A/B，
原 30 秒门禁及 16 supported/14 deferred 不变。

6A.48 补齐正式 `.7` 本地完整独立内核双机单 Peer 关联改址的 TERM 恢复：
实际候选规格/WG/内核新址见证后，绑定部署锁 owner、正式入口、ppid 和 start ticks，
通过 pidfd 对迁移 Bash 单次发送 TERM，正式 rc 143；旧址/WG 恢复且仅撤权，
旧 token 401，新邀请同版同步及原调度恢复，文件/源码/镜像/额度保持、累计不降。
严格 TLS 错 UUID 零原点请求，managed/core 正文 270336/245760 字节及计量通过。
断网驱动 483.320 秒、正常关机 5.138 秒，QEMU exit 0/0、无强停、父盘摘要保持；
独验两稿端口/空 stop 错误原判保留，未重跑 guest。最终断网独验 1439 份，
重核旧 1222 份，四容器退出且无 OOM；公开摘要
`.tmp-native-control-vms-20261116/term-verification.json`，SHA-256
`48661ce36089f7ba3d8e2326e2591fd82e85d7d10c3e4d181b47f623d6a01696`。
仅关闭固定 TERM 子项，其它信号/断电、公网多机、多 Peer、arm64/IPv6、防护及长稳仍缺。
未改运行源码/合同/支持状态、连接/重启 A/B、重复回归、推送或发布。

6A.49 只定位新的正式 `.7` 本地完整内核双机单 Peer 带跟踪 enable 拒绝分支：
同一 Witness Bash 连续 21 次 pending，SECONDS 190→220 后在原 30 秒门槛
返回 HOST 10，外层恢复后 enable 14；仅挑战前一次 Snapshot，无 current/Recheck/Commit。
完整 Peer CLI rc 0、宿主总计 31.983262 秒包含检查和清理，不据此判断 HTTP 时点，
不将 TCG/xtrace 新轮结论外推 6A.47 或旧失败。驱动因恢复重建主控四服务的
ID/StartedAt 比较失败、exit 1 保留；独验只确认前后健康/静态/镜像/账目和
正常关机，final_peer/final_security 未执行，不计完整恢复审计或防护通过。
QEMU exit 0/0、正常关机 4.848023 秒、父盘保持，私密卷无活动容器。
断网独验 1803 份、重核旧 1691 份，diagnosis_verified true，passed、
control_protection_verified、full_recovery_audit_verified、original_failure_cause_proven false。
公开摘要 `.tmp-native-control-vms-20261116/protection-diagnostic-verification.json`，
SHA-256 `c148a12c61c1d19a7a73fd8f6b2e2ff6a1701d6d4eb270d735f602885f600ccf`。
原窗口、旧失败及 16 supported/14 deferred 保持；未改运行源码/合同、
连接/重启 A/B、重复回归、推送或发布。

6A.50–6A.66 的后续定位、调用合并、候选及正式 KVM 验收见实施计划。
K 补齐 `subscription-multiserver` 和 `interactive-menu` 的固定本地正式 `.8`
完整升级、防护及严格恢复子项，不将 6A.47 正式 `.7` 或 6A.64 原失败改判为通过，
不外推生产、公网多机、多 Peer、arm64/IPv6 或长期稳定性；14 个 deferred 状态不变。

6A.67/N 随后补齐原生 Ubuntu ARM64/IPv4/Xray WS 的固定正式 `.7/.8` 安装、
升级回滚、启停、保留卸载重装与 purge，22 个客户端、10 份 ARM64 manifest
绑定及 56 份脱敏工件的断网只读独验通过。仅关闭 `interactive-menu` 的该固定
宿主生命周期子项；各专项的 ARM64 组合仍须实际验收。预装 Engine、容器
restart 和本地 lo origin 不分别替代自动安装、整机重启和公网入站。
自然续期、公网 IPv6、多 Peer/公网控制与灾备、其它组合和长稳继续未决；
主线 CI 权限修复已通过。归档期间独立上游自动更新发布正式 `v3.44.0`/
`da790587`，Release run `44081637875` 的 41 个 job 全部成功，含 ARM64
runtime；不自动覆盖本轮 `.7/.8` 的宿主整轮证据，A/B 未升级。
16 supported/14 deferred 不变。

6A.68/N 再补 Ubuntu ARM64/IPv4 的正式 `.44` Engine 自动安装及纯 sing-box
Trojan TLS/id 28 `.8/.44` 七阶段；run `44093133554`/`c8ee532f`、
69 脱敏工件、22 新客户端、两账目/额度/计量、10 ARM64 index/manifest 与
实际镜像、业务材料和精确集合清场均经断网只读独验通过。
镜像列表按原顺序重建摘要再比集合，驱动 25/独验器 19 负控通过；
首轮运行通过但两次离线失败、对应验证器及报告保持，不改判。
仅关闭该固定自动安装和纯 sing-box 生命周期子项；安装前为移除 runner
预装包后的条件，不称裸 OS。原生宿主重启、公网/IPv6、其它既定协议/专项、
自然续期、多 Peer 及长稳仍待验，A/B 未变，16 supported/14 deferred 不变。

6A.69/N 集中补齐固定正式 `.44` 原生 ARM64/IPv4/Xray 29+sing-box 28 的
入口/双核心路由/Xray HTTP 与严格 HTTPS CONNECT/站点 ALPN，服务重启和精确
清场通过。run `44112277450`/`7808de09` 的 126 工件、58 检查、六 checkpoint
断网只读独验，31 组件及 19 完整工件负控通过；前三轮和本轮首次独验失败保持。
首次 CLI 编辑只保持现场完整 JSON 语义恢复，不称跨编辑字节一致或私密语义离线重算。
第二轮中继空成功异常未定位，不因第四轮成功改判；DNS 错误不单独证明无回退。
仅关闭上述固定子项，复用预装 Engine、本地 lo origin 和服务 restart 分别不替代
自动安装、公网入站和整机重启；其它组合/生命周期、公网 IPv6、自然续期、
WARP、多 Peer 及长稳仍待验，A/B 未访问或改动，16 supported/14 deferred 不变。

6A.70/N 再补固定正式 `.44` 原生 ARM64/IPv4 的 Reality Vision/XHTTP
三拓扑共存及普通 bridge 双入口 Encryption 启停/恢复、三次服务 restart。
第七轮 `44146178086`/`261048c4` 的 292 工件、19 checkpoint、64 proxy、
16 site/29 辅助采样经断网只读独验通过，46 组件及 41 完整工件负控全部拒绝。
前五轮失败和第六轮 CI 成功但独验因 12 relay reset 拒绝均保持；
原 URI 导入、短请求超时不改判，仅固定 Mihomo 显式 hybrid 投影通过。
恢复保持现场 JSON 语义，首次序列化前后字节不同，不称私密语义离线重算。
业务 origin 仅本地 lo；受管站点用测试 CA，host/loopback 经本地 443
透明中继至固定公网 A HTTPS 后端，不计 ARM64 公网入站，不传生产私钥。
本轮不登录或变更生产 A/B、不重测 Engine 安装或宿主重启；其它组合/算法、
加密拓扑生命周期、公网 IPv6、自然续期、多 Peer 及长稳仍待验。
主线仅记证据、不合并临时驱动或触发应用发布，16 supported/14 deferred 不变。
