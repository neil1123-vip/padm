# Docker deferred 状态对账

初始对账：2026-11-04；更新至 2026-11-19（北京时间）。

本表对齐 `docker/contracts/features.json` 的 14 个 `feature_matrix` deferred 项，
只修正原因和证据归属，不修改状态枚举、schema 或支持组合。36 项功能中的
13 个 supported、8 个 host-integrated、1 个 unsupported 保持；16 个公开协议的
`management_status` 已按实施计划 3D.26 为 supported。

本机代码项随实施计划 6A.23 收口。deferred 汇总了环境门槛、已声明限制和重复索引，
不能按行数当作待开发功能数。明确拒绝的组合不追加为原计划必须开发的需求。
原生证据只证明记录中的正式版本、固定客户端、架构、网络和操作；旧版通过既不
作废，也不自动覆盖当前源码或其它组合。失败原件及根因未定结论保持。

2026-11-18 起，**ARM64 架构维度按默认通过计入收口**。
未实测的 ARM64 组合和 ARM64 专属整机重启仍记为未实测，不折算成通过证据。
下表若把 ARM64 与公网 IPv6、重启恢复或其它条件并列，只免除必须在
ARM64 上复验的要求；尚未满足的独立功能门槛可在等效原生宿主上验收。
此口径不改 CI、支持矩阵或既有拒绝边界。

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
[6A.73](docker-menu-parity-plan.md#6a73-正式本地双-peer-灾后整机重启)
另补该灾备拓扑重启后的原容器恢复、双端原 timer、业务和计量；1352 份
原件断网只读独验通过。不替代公网多机、其它拓扑、断电或长稳。

后续集中补验：

| 编号 | 证据与范围 |
| --- | --- |
| M | [6A.71–6A.74](docker-menu-parity-plan.md#6a71-正式本地三节点控制验收与-icmp-首配阻塞)：固定正式 `.44`、Debian 13 amd64/IPv4、本地独立 KVM 一主两被控的自主增删、整机重启、单 Peer 撤权、主控新机灾备及灾后三机重启通过。新机恢复联网、独验断网；`3986/1697/1352` 份原件分别绑定，不相加。`.44` 恢复断电后的暂存遗留失败保持，候选清理/重试和双 Peer 业务补验通过；随后正式 `.3` 控制入口恢复旧 `.44` 业务的 active 窗口断电、两次 recover、空目标重试 healthy 和正常关机独验通过，绑定 `116` 文件，父盘与旧封存保持。该正式补验未重复双 Peer 重绑或 timer，不外推公网/arm64/IPv6/其它拓扑。原件 `.tmp-native-control-multipeer-20261118/`、`.tmp-native-restore-powercut-formal3443-20261118/` 及各节私密卷。 |
| I | [6A.75](docker-menu-parity-plan.md#6a75-正式-v3443-发布绑定与-icmp-三场景)：正式 `.3` 发布 `44233188541` 的 30 门禁、三附件、两次重建及五镜像签名/双架构绑定独验通过，两项 runtime/smoke 明确 skipped。ICMP r2 `2bb4191f`/`44241272794` 在独立 Debian 13 amd64/host-network/IPv4 完成 direct 往返、filtered 目标丢包、denied 实际核心 RAW `EPERM` → DGRAM `EACCES`，TCP/UDP、PID/权限、资源/材料/额度和 off/down 恢复均通过；662 文件/314 命令/13 资产、24 组件及 17 语义负控独验通过，正常关机且父盘保持。普通核心日志为空，旧失败不改判；不外推 ARM64/公网/IPv6/PMTU/启用态重启。原件 `.tmp-release-3443-44231991439/`。 |

## 14 项对账

`subscription-multiserver` 与 `interactive-menu` 的多 Peer 灾备及重启缺口均已排除
M 验证通过的固定本地 amd64/IPv4 双 Peer 组合；公网、其它组合和断电不计入本次通过。
[6A.77](docker-menu-parity-plan.md#6a77-双-peer-拓扑单被控新机恢复) 另关闭同一
拓扑下只替换一台被控的子项：主控及另一被控保持在线，旧邀请拒绝，
双端原 timer 自主同步、TLS 和计量通过，1380 份证据离线独验，四机正常关机。
[正式 v3.45.1](#正式-v3451-本地单被控替换与公网复测) 已复验本地单被控替换，
公网 IPv4 的同一替换拓扑仍待验。
正式 `3.43.4`、`3.43.7` 与 `3.43.8` 的共同可信发布门槛
已取得，见 F、B 及[distroless 正式发布独验](docker-distroless-baseline.md)；后续正式 `.3` 发布绑定见 I。本地双 Peer 灾备及灾后重启已由 M 补齐，不替代各专项尚缺的公网环境、宿主生命周期或其它新主机灾备证据，
不为每行重复发布或跑全套。公网 IPv6 等共用门槛按实际适用组合集中验收。

| deferred 项 | 已有证据 | 待补证据（ARM64 不单独阻塞） | 明确限制与重复归属 |
| --- | --- | --- | --- |
| `subscription-multiserver` | P：私网 API、单 Peer 迁移、v2 多被控逐节点管理、自动同步、隔离 amd64 双/三节点业务和授权隔离；6A.19/6A.23 新身份灾备。W 补齐原生固定单 Peer 隧道，以及正式 `.7` 本地独立完整内核双机的账号自主增删、启用态真实重启、固定地址密钥/端口迁移、关联改址撤权、新邀请恢复、原日历自主同步、业务和累计；6A.42 另补主控改址真实 bind 失败恢复、仅撤权及新邀请同版同步；6A.44 的预加载 helper 与 6A.45 的完整 Peer CLI 预热条件分别补齐固定本地 server fresh 见证。6A.46 补齐固定本地 amd64/IPv4/单 Peer 角色/WG 新机恢复、新控制身份/rebind 及自主同步、TLS/计量；6A.47 补齐正式防护启用失败后的固定本地恢复审计；6A.48 补齐固定本地实际迁移切换后 TERM 恢复、撤权、新邀请/原调度与业务。K 另补正式 `.8` 本地双 KVM 完整升级、防护及严格恢复。M 再补固定正式 `.44` 本地双 Peer 自主同步、撤权、重启、主控新机灾备及灾后重启；正式 `.3` 控制入口的旧 `.44` 业务断电恢复/重试另行通过。[公网中继](#公网中继控制同步与灾备) 补正式 `.44` 双 Peer 经 A 的公网 SSH 及 B 的公网 IPv4 UDP 中继，同步及主控灾备分阶段通过。[公网直连](#正式-v34413-公网双-peer-同步与主控灾备) 补齐 `.13` 固定公网 IPv4 拓扑的双 Peer 自主同步与主控替换。正式 `.0` 的隔离 IPv6 底层补齐同一双 Peer 主控灾备生命周期。 | 公网 IPv6、其它既定多 Peer 灾备拓扑及适用生命周期；本地双 Peer 主控灾备/灾后重启已验，不再作为完全空白。新机恢复联网，不计断网恢复。6A.47 原 enable rc 14 保持，不定位拒绝分支；本地正式 `.8` 防护已由 K 补齐。6A.41/6A.43 失败保持且原失败同因未证，准备/审计遇锁未查 owner；固定 TERM 和恢复事务断电不外推其它信号、故障或长稳。 | v2 关联地址/密钥迁移、控制面 Fail2ban 拒绝，不新增开发。控制 API 无公网映射；公网业务验证不等于公开 API。灾备归 `interactive-menu`，宿主隧道归 `wireguard`。 |
| `acme-webroot` | P+A：稳定只读根与独占写入、归属/树校验、不停 Nginx；正式公网签发/在线换证及 3.41.4 新证书消费失败完整回滚。 | 真实登记自然到期续期；原生 arm64/公网 IPv6、当前版本尚未覆盖的适用生命周期。 | 自然续期与下一行共用一项门槛，约 2026-12-17 的窗口须以实际登记为准。no-op、强制到期、fresh 申请均不能替代自然到期。 |
| `acme-standalone` | P+A：HTTP-01/TLS-ALPN-01 及原拥有者暂停/恢复；正式签发、standalone/ALPN 消费失败回滚、ALPN 在线往返和单次 fresh 完整链。 | 同一 ACME 自然续期门槛；原生 arm64/公网 IPv6、当前其它适用生命周期。 | 仅暂停本部署原运行拥有者；站点 Fail2ban 的自监听停启仍拒绝。其它 CA/provider 不借本次证据扩大范围。 |
| `site-static-redirect-alpn` | P+S+N：模板/local/ALPN 事务及隔离双栈；固定正式 3.41.5 公网 13 阶段，包括特殊站名、302、订阅与完整恢复。N/6A.69 补正式 `.44` 原生 ARM64/Xray 29 的三模板/特殊标题、static/302、三种 ALPN 顺序、实际 HTTP/2 和服务重启。B 补正式 `.7` Xray 29 限源中继的公网 IPv6 站点九项及清场。 | 公网 IPv6 直连、其它既定协议组合及适用生命周期。 | B 的 IPv6 证据限站点运行，CLI 编辑、恢复事务见已有组合。Hy2 local 固定受管只读目录且无混淆，纯 Hy2 只开放 static。ACME 另行归属。 |
| `entry-port-management` | P+U+R+N：多入口、额外端口、默认分享/原位改端口、内部端口专项；SS2022 公网 IPv4 默认别名/删除及限定合并重启。N/6A.69 补正式 `.44` 原生 ARM64/sing-box Trojan 的别名/默认分享/原位替换/删除及基口恢复，双核心恢复和服务重启业务通过。 | 公网 IPv6、其它既定 ARM64/端口组合及尚缺的适用生命周期；固定本地 origin 不计 ARM64 公网。 | 与内部 207 共用别名证据。额外端口别名拒绝 WS/SSH Fail2ban、TUN/TProxy、host-network 组合；3D.26 已另行放行活动 WS 防护下未保护入口的基础增删改。跳跃限单 sing-box/单个双族入口/手动监督，不承诺 TUIC 客户端自动换端口或崩溃/开机恢复。 |
| `reality-coexistence` | P+C+N：受管、桥接宿主和 host 回环三拓扑恢复；限定公网 Vision/XHTTP 正反例与六点真实重启。N/6A.70 补正式 `.44` 原生 ARM64/IPv4 的三拓扑 × 双入口、关闭恢复、loopback 服务 restart 及正反例。 | 公网 IPv6、ARM64 整机重启、其它既定共存组合及当前版本尚缺的适用生命周期；本地入口与公网网站后端不等于 ARM64 公网入站。 | 一个 Xray Vision/XHTTP 后端，网站证书/内容仍由原维护方负责。N 的 host/loopback 仅经本地透明 TCP relay 到固定 A HTTPS 后端，不传生产私钥；旧 reset/超时不因本轮成功改判，3D.26 协议管理 supported 不重列为缺口。 |
| `cdn-entry-management` | P+D：2/21/22/23/24/25 地址覆盖和链接/订阅投影；固定 Cloudflare WS 公网正反例。[Cloudflare 隔离透传](#cloudflare-隔离透传) 补齐固定 Xray gRPC 与 XHTTP packet-up/H3 公网透传。正式 `.12` 的 Xray VLESS gRPC 公网受管流程通过。正式 `.13` 补齐 XHTTP 地址覆盖与独立 H3 下行的隔离验收。正式 `v3.45.0` 的 Xray 镜像通过 Reality 上行与公网 H3 下行共享会话夹具。 | 公网 IPv6、其它核心和传输组合、正式 CLI 生成配置的公网共享会话。 | H3 验证客户端到边缘，实测回源 HTTP/2。H3 只有使用说明，不新增开关、其它协议或自动建设外部 TLS/H3/CDN。 |
| `interactive-menu` | P+G+B+W+K+N+M+I：6A.23 本机代码收口；3D.26 的 16 个公开协议管理 supported；正式安装/升级回滚/公网/重启、同机灾备及账号/业务恢复限定证据；B 正式 `.7` 从原 `.4` 归档完成固定 Xray WS 新主机恢复和单次整机重启。6A.46 另补本地完整独立内核双机的 amd64/IPv4/单 Peer 新机角色/WG 恢复、新身份/rebind、自主同步和 TLS/计量；K 补齐正式 `.8` 本地双 KVM 完整升级、防护及严格恢复；N 补齐 Ubuntu ARM64/IPv4/Xray WS `.7/.8`、纯 sing-box Trojan `.8/.44` 七阶段及 `.44` 官方 Engine 自动安装和清场，6A.69 再补固定 `.44` 入口/路由/中继/站点四类专项及服务重启，6A.70 补固定 Reality 三拓扑与普通 bridge 双入口 Encryption 集中验收、恢复及三次服务 restart。M 补固定本地双 Peer 主控灾备/灾后重启与正式 `.3` 控制入口断电恢复/重试，I 补正式 `.3` 发布绑定及固定 amd64 ICMP 三场景。正式 `.13` 补齐固定公网 IPv4 双 Peer 主控灾备。 | 自然续期、ARM64 其它既定组合及整机重启、公网 IPv6、其它核心/协议及发行版适用安装、其它既定多 Peer 角色/WG 灾备拓扑及各专项尚缺的适用生命周期。 | 汇总项，不重复计下属各行。N 的原点限本地 lo、host/loopback 站点限本地中继至固定公网后端，不计 ARM64 公网入站。M 的本地双 Peer 与恢复中断点不外推公网或其它故障，I 不外推其它架构或启用态重启。已有部署替换、其它 ACME 材料、未处理输入、v2 关联迁移等保持拒绝，不追加开发。 |
| `routing-tools` | P+R+N：两核心 SOCKS5 TCP、DNS/hosts、Direct/Block、CN 与名单管理；sing-box 解析后阻断、pure 发布共存、DNS 拒绝回退和限定合并重启。N/6A.69 补正式 `.44` 原生 ARM64/Xray 29+sing-box 28 的 SOCKS 全局/选择匹配/绕过/认证拒绝、DNS/hosts、Direct/Block 及恢复/服务重启。[正式 `.7` WARP 公网出站](#正式-v3447-的-warp-公网出站) 补齐两核心使用真实 Peer 的全局 IPv4、全局 IPv6、选择性 IPv4 HTTPS 出站。 | WARP 跨路径失败根因和长稳。其它路由组合的公网 IPv6 及适用生命周期待补。 | 与内部 206 共用证据/条件；SOCKS 入站限制归内部 201。N 的 DNS 错误拒绝不单独证明系统解析器无回退。固定 Xray 解析后阻断拒绝；原生 CN 预设已覆盖，不追加任意国家向导或最终流量语义引擎。 |
| `internal-201-socks-relay` | P：5B.5b/5B.5b.1 已证固定 sing-box 的动态 BND/活动关联真实来源问题及 Xray 许可不随控制关闭撤销。 | 当前按限制关闭，无一轮普通环境回归可以使其成立；仅在相关核心行为变化后，重证发布、真实来源、会话鉴权及控制关闭撤销，才重新评估。 | 不开放完整入站、不降为 TCP-only、不增加辅助核心。host-network 不能修复鉴权。TCP 出站归 `routing-tools`；201 不作为公开节点协议。 |
| `internal-202-http-relay` | P+H+N：Xray 认证 HTTP/CONNECT、字面来源白名单、管理/回滚；隔离 amd64 双栈和原生外部 IPv4 三目标 TLS/200、407、来源拒绝。N/6A.69 补正式 `.44` 原生 ARM64 的认证 HTTP/严格 HTTPS CONNECT、改端口、HTTP/CONNECT 来源拒绝、关闭及业务恢复；负例原点 TCP/请求为零。正式 `.8` 隔离双栈真实 CLI 的启用、端口/名单切换、关闭恢复及 24 组探测通过。B 原生 Xray 公网 IPv6 真实来源正反例通过。正式 `.13` 的受管 Docker 公网 IPv6 直连、认证、原始来源及端口迁移通过，隔离 IPv6 的完整 CLI 生命周期通过。 | 公网 IPv6 来源撤销、停用、规格恢复及完整原点计数。其它既定中继组合待补。第二轮空成功异常根因未定。 | B 原生试验使用单一回环原点。sing-box 的 `X-Forwarded-For` 来源限制按既有合同处理。202 为内部专属直连。 |
| `internal-206-routing-rules` | P+R+N，与 `routing-tools` 共用规则/名单、原生 IPv4 路由/DNS 拒绝回退及限定真实重启；N/6A.69 另补固定正式 `.44` ARM64 双核心规则及服务重启。沿用正式 `.7` 的真实 WARP Peer 出站记录。 | 同 `routing-tools` 的 WARP 跨路径、公网 IPv6 及适用生命周期。 | Xray 固定反例继续拒绝；只读重叠/覆盖不预测 GeoSite/DNS/最终流量。不追加任意国家/语义引擎；206 不作为公开节点协议。 |
| `internal-207-access-control` | P+U+R+N，与 `entry-port-management` 共用发布别名、默认分享/原位修改及固定原生公网 IPv4/重启证据；N/6A.69 另补正式 `.44` ARM64/sing-box Trojan 别名与双核心恢复/服务重启。正式 `.8` 隔离双栈 Xray WS 的真实 CLI 和严格 TLS 通过。 | 同端口管理的公网 IPv6、其它既定端口组合及尚缺的适用生命周期，不重复计数。 | 只复用已有入口认证、统计及 TLS/SNI，不做任意目的转发。拒绝宿主组合保持原边界；207 不作为公开节点协议。 |
| `vless-encryption` | P+E+N：配对/投影/marker/失败恢复，固定正式 3.41.5 amd64 公网启停与普通 bridge 双加密入口真实重启。N/6A.70 补固定正式 `.44` 原生 ARM64/IPv4 普通 bridge 双入口的五阶段启停/服务 restart/恢复、精确错误配对与旧 none/错误 encryption 拒绝，正式 Xray 与 Mihomo v1.19.28 显式 hybrid 正例通过。[6A.76](docker-menu-parity-plan.md#6a76-mihomo-原始-reality-uri-导入) 补隔离 amd64 和原生 ARM64 的 Mihomo v1.19.31 Vision/XHTTP 原 URI 导入（Encryption 开/关），及普通 gRPC 原 URI；原生 ARM64 五个正例、18 个负例和清场通过。 | 其它既定客户端/算法、其它环境的 Mihomo 原 URI 导入、ARM64 整机重启/公网入站/IPv6、其它拓扑的加密生命周期及当前版本尚缺的适用生命周期。 | 只按固定 Xray/Mihomo 组合及 schema 3 Reality 1/2 实验范围使用；N 的显式 X25519MLKEM768 证据和旧原 URI 失败不改判。不能与 3D.27/F 的 ML-DSA-65 签名验证证据相互替代；未验组合不暗中开放，旧 curl 28 不改判。 |

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
3D.27 另补同一公网 IP 的真实 TLS 对照：旧参数严格校验失败、显式独立 SNI 成功；
只关闭旧探测失败见证缺口，不扩大正式 CLI/业务验收范围。
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

2026-11-18 09:21:10/09:22:38 UTC，分别只读采集 A/B 当前业务容器的 cgroup v2
`memory.peak`。按 Nginx、订阅、Xray 顺序，A 为 `14516224/37277696/41574400`
字节，B 为 `14258176/35569664/30253056` 字节；六容器采集前后身份和启动时间
一致，均健康、`RestartCount=0`、`oom_kill=0`，自身 `memory.max` 均为 `max`。
峰值只对应各自现存 cgroup，发生时间未取证，不相加为整机峰值；没有额外施压，
未验证 CPU 峰值、容量预算或长稳，不改变支持状态。

2026-11-18，B 的公网 IPv6 入站前置通过：Globalping `2ZPMwAap8wXmhYO1p00021WfJ`
由德国 Falkenstein（AS24940）测点对 B 的 IPv6 TCP/22 发起两次连接，均返回。
B 在同一窗口于 `eth0` 抓到两个入站 SYN 及对应出站 SYN-ACK，四包、零内核丢包；
抓包按时结束。未改监听、DNS 或防火墙。该证据不替代应用请求见证、TLS 或协议验收；
业务 443 仍仅 IPv4，完整应用验收还需可运行协议客户端的独立 IPv6 链路。

同日 09:39 UTC，本机 Docker Desktop 的临时 Linux 客户端强制 `ssh -6` 两次直连 B，
均通过既有 ED25519 主机公钥校验，未提交用户凭据。B 的 `eth0` 同期见证来自本机
公网 IPv6 的两对 SYN/SYN-ACK，四包、零内核丢包。客户端路径可复用，无需新增 VPS；
此结果只验证公网传输与目标身份，正式应用仍需隔离 IPv6 入口及业务请求见证。

同日经固定主机公钥从 IPv4 登录 B，只读确认 `eth0` 由 `systemd-networkd` 管理。
IPv6 主路由表同时有静态和 RA 默认路由，外部探测目的选中 RA 路由。静态网关邻居
状态为 `FAILED`，RA 网关为 `STALE`。`all/default/eth0` 的 IPv6 转发均为 `0`，
`eth0.accept_ra=0`。准入和回滚检查需验证实际 IPv6 选路及独立客户端往返，不能只看
静态默认路由是否存在。

在 B 的独立网络命名空间中，用当前 `6.12.63+deb13-cloud-amd64` 内核重建静态和
带 nexthop 的 RA 默认路由，两者 metric 均为 `1024`，测试上联 `accept_ra=0`。
转发 `0 → 1 → 0` 三次取样都保留两条路由并选中 RA；恢复后接口和默认转发为 `0`。
本轮回滚验证限于命名空间内的路由和 sysctl，生产公网回程仍待验。

同日用签名清单锁定的 `v3.44.4` 正式包及五个 amd64 镜像在断网独立 daemon
复验双栈。HTTP/CONNECT 在端口和来源修改前后通过，原点与 Xray 日志核对允许和
拒绝来源。Xray 与 sing-box 的 control/selective/global/off 共八个真实 bridge
场景通过，包含 IPv6 TCP/UDP、AAAA、优先级和辅助网络清理。

端口别名原夹具的原点地址触发 Xray `26.11.9` 的默认目的地址限制。隔离原点改址后，
双核双栈的添加、选作默认分享和删除均通过，后续 Hy2 PID 1 用例显示正式 `net`
镜像缺少 `ss`。候选 `net` 使用已安装的 iproute2 导出 `ss`，保留其余四个正式镜像，
整套端口别名、Hy2 认证与 TLS 拒绝、隔离 DNAT 撤销/恢复及实际 `docker stop` 通过。
五镜像运行合同通过，包括 `net` 的 Fail2ban 和五个容器的停止检查。
正式 `v3.44.5`/`dbe6290a` 已发布，Release `44292234213` 的 33 项全通过，
包含双架构 net 构建与冒烟、原生 ARM64 五镜像运行合同。独验三个附件摘要、发布清单
与 net 索引签名、两架构清单及四镜像复用。用正式包和精确 amd64 镜像重跑端口别名
三个阶段、Hy2 PID 1 停止和规则撤销通过。原件 `.tmp-ipv6-formal3444-20261118/`。
B 抓包复核本机测试源的公网 IPv6，三个生产容器健康，候选端口空闲。
隔离环境验证限源 DNAT 保留原始源地址，非测试来源和绕过 DNAT 的直连均被拒。
B 单端口试验因全局转发和临时防火墙变更风险被自动审批拒绝，公网业务验收待完成。

同日，B 用非特权 systemd 临时服务绑定公网 IPv6 的 TCP/28600，仅允许本机 Linux
客户端的来源地址。限源负例超时，B 在 `eth0` 见证外部 TCP 握手。首轮应答客户端
超时，改由客户端先发送随机串后，两端记录同一回显，且 B 收到客户端回执。
退出后核对候选端口空闲，IPv6 全局转发为 `0`，防火墙规则摘要一致，原三个容器
仍健康。

同日用正式 `v3.44.7` 的验签 amd64 镜像导出 Xray `26.11.9`，两端校验同一
二进制摘要。在 B 的限源非特权临时服务中，公网 IPv6 VLESS/WS/TLS 通过两次
原点回显。B 明确拒绝 3 次错误 UUID，证书指纹负例由双方 TLS 日志互证，原点
仅收到两笔正常请求。首轮 `/run` 无执行权限、`/var/tmp` 在服务隔离范围内不可见，
改用专用临时目录后启动。中间复测有请求到达原点但客户端读取超时，根因待查。
最终单元、端口和临时文件清理通过，防火墙规则摘要、IPv6 转发和三个业务容器状态
复核通过。夹具在 `.tmp-native-ipv6-public-20261116/`。测试范围为独立 Xray、
一次性证书和回环原点，受管 Docker 发布入口及业务计量待验。

北京时间 2026-11-19，断网独立 Engine 使用验签 `v3.44.7` 发布包生成受管 Nginx
和 Xray 配置。IPv6-only 端口发布、静态站点及 VLESS/WS/TLS 两次原点回显通过。
Xray 见证 3 次错误账号，客户端见证错误证书指纹，原点仅收到两笔正常请求。
唯一账目收集到上行 240、下行 466 字节，重复采集累计及基线一致。端口、容器和
bridge 清除，防火墙规则与转发设置检查通过。另在独立网络和挂载命名空间重跑，
获得同一计量结果，外层哨兵 `docker0` 和直连路由逐字一致。

B 的首次公网受管试验失败。临时 Engine 在宿主网络命名空间移除了空闲 `docker0`，
容器启动也遇到 `/sbin/docker-init` 权限错误。随后按生产 Engine 登记的配置恢复
`docker0` 和 `172.17.0.0/16` 直连路由，复核三个业务容器原 ID、启动时间、重启
次数和健康状态。续期隔离三项阻断及业务网络三项对照复验通过，规则内容保持，
临时端口、单元和目录均已清理。

同日，B 以独立网络和挂载命名空间复验正式 `v3.44.7`。外部 IPv6 客户端连接
TCP/28600，经限源非特权 systemd 中继和 Unix 套接字进入隔离 Engine 的 Docker
发布端口，再由受管 Nginx/Xray 到达测试原点。两次 VLESS/WS/TLS 回显通过，
3 次错误 UUID 和错误证书指纹被拒，未放行来源被拒。唯一账目上行 240、下行
466 字节，重复采集无增量。`Client`、`Managed`、`Cleanup`、`SourceGuard`
均为 `true`，退出码为 `0`。复核生产 `docker0`、路由、规则、容器状态和临时
资源清理通过。入口见 `.tmp-native-ipv6-public-20261116/check-public-relay.sh`。
本轮范围为中继拓扑下的公网 IPv6 受管 WS。业务侧原始来源地址、生产 `443`
直连和其它协议的公网 IPv6 仍待验。

2026-11-19，B 用限源临时 UDP/28601 进行三轮公网 IPv6 回显预检。Windows
收到 1/3，Linux 客户端两轮各收到 3/6。末轮使用每包独立 socket，B 应用
收到 6/6 并发起 6 次回显，`eth0` 抓到 6 个入站和 5 个出站包，抓包内核
丢弃为 0。客户端超时的 64 和 1252 字节探测各有一个对应出站包，回包丢失
位置待验。三轮均复核监听释放、生产容器、`docker0`、
路由、规则与 IPv6 转发。末轮夹具见
`.tmp-native-ipv6-public-20261116/udp-wire-check.ps1`。

同日，使用 `v3.44.8` 清单对应的 sing-box `v1.14.4-padm.2` 官方构件，
先通过断网 IPv6 回环自检，再在 B 的限源临时服务跑两轮公网 IPv6 Hy2/TUIC。
每轮各协议均完成两个持一次性证书校验的原点回显，错误凭据均未到原点。
首轮 SSH 丢失部分服务端日志，复测补齐 Hy2 认证 404、TUIC token mismatch
及原点四正两空的记录。两端退出码均为 0，核对两端临时资源、生产容器、
`docker0`、路由、防火墙规则、转发状态和 Engine 进程均通过。夹具见
`.tmp-native-ipv6-public-20261116/quic-pilot.ps1`。

同日，复用验签 `v3.44.7` 发布包及 amd64 镜像，在 B 的隔离 Engine
通过受管 Hy2/TUIC 公网 IPv6 验收。限源 UDP 中继从 `28602/28603` 转发到
隔离 Engine 的 IPv6-only Docker 发布端口。中继启动后有效 UID 为 `65534`，
有效 capability 为零。各协议两个正例和一个错误凭据拒绝通过，原点只有四条
正例请求。单账号上行 `236`、下行 `900` 字节，重复采集无增量。两端退出码
均为 0，临时监听、目录、容器和网络清理通过，生产容器、`docker0`、路由、
规则、转发状态及守护进程基线一致。首轮离线镜像变量拼写错误，次轮中继读
命名空间被拒，两轮均清场通过。复测由 systemd 传入只读命名空间描述符，修复
属于临时夹具。证据限中继拓扑，公网原始来源透传、生产直连和长稳待验。

北京时间 2026-11-19，复用验签 `v3.44.7` 发布包及 amd64 镜像，在 B 的独立
Engine 补验 Xray 29 `fallback_tls`。公网 IPv6 客户端经限源 TCP/28600 中继
访问受管入口。三种模板和标题转义、静态正文逐字比对、302 的完整 `Location`
及默认页恢复通过。客户端同时提供两种协议时，`h2,http/1.1`、`http/1.1,h2`
和仅 `http/1.1` 分别协商得到 HTTP/2、HTTP/1.1、HTTP/1.1。一次性证书校验、
未信任证书和限源拒绝通过。首轮客户端证书管道因 CRLF 解码失败，清场通过。
修正后九项通过，生产容器身份、启动时间、健康、`docker0`、路由、规则、转发
及守护进程与基线一致。本轮使用正式候选生成和独立容器重建。公网直连及 CLI
在线编辑、恢复事务待验。

同日，正式 `v3.44.8` 控制包在断网独立 Engine 复跑 HTTP 中继 `202` 和入口别名
`207`。五个镜像引用与 `.7` 一致，复用已验签导出的 amd64 镜像。`202` 验证
IPv4/IPv6 的真实来源、HTTP/CONNECT、认证、端口与名单切换和旧来源拒绝。
`207` 验证双栈 TCP/UDP 别名发布、分享端口切换与关闭，并补验 Hy2 跳跃的
冲突拒绝、进程终止后恢复及规则清理。两套脚本退出码均为 `0`。原件位于
`.tmp-release-44369981596/v3.44.8/`，公网直连仍待验。

同日，B 使用正式 `.8` 的配置生成器和同清单绑定的 amd64 Xray，单独启动限源
systemd 测试单元。客户端直连公网 IPv6 的 TCP/28604。允许名单匹配时 HTTP 和
CONNECT 隧道内的 HTTP 均返回 200，错误及缺失凭据返回 407。名单换为文档
测试地址后，真实来源的 HTTP 返回 503，CONNECT 隧道内关闭。伪造的代理头
与名单地址匹配，服务端仍按实际 IPv6 来源将两次请求送入 `blocked`。前后各两次
来源见证，回环原点仅收到允许阶段两个正例。首轮预检、后续 systemd 日志启动及
缺少 `Connection: close` 的客户端超时原样保留。最终退出码为 0，临时单元、
目录及端口已清理，生产容器、`docker0`、路由、规则、转发及守护进程基线一致。
这轮公网证据覆盖原生 Xray 监听。夹具和原件
为验收 worktree 的 `.tmp-native-ipv6-http-relay.ps1` 与
`.tmp-native-ipv6-http-relay-checks.log`。

北京时间 2026-11-19，从已验签的正式 `.8` 包安装真实 CLI，在独立 Docker
Engine 29.8.2 上配置 Xray WS 和测试证书。`207` 经真实 `edit` 完成别名新增、
默认分享、替换、恢复默认与移除。双栈严格 TLS 握手、新旧端口切换及规格恢复
通过。此轮 `207` 探测覆盖 TLS 层。

`202` 经真实 `edit` 启用双栈中继、修改端口、反转 IPv4/IPv6 来源名单并关闭。
改动前后分别执行两地址族、HTTP 和严格 TLS CONNECT、允许来源与正确认证、
错误认证及拒绝来源共 24 组，原点精确收到 8 个正例。错误认证返回 `407`。
限源 HTTP 返回空体 `503`，限源 CONNECT 在代理返回 `200` 后未建立目标 TLS。
关闭前后的端口探针和规格复核通过。原点补齐 `Content-Length` 后，CONNECT
正例收到完整正文且 curl 退出 `0`。此前各次测试失败原样保留。

本轮 `207` 与 `202` 分别见验收 worktree 的
`.tmp-formal3448-dualstack-cli-attempt7.log` 与
`.tmp-formal3448-dualstack-cli-relay-r3.log`。公网 Docker 直连仍需独立 IPv6
测试地址。B 的两个候选地址通过 SSH 主机身份核验，另一个在 SSH 握手前超时。

北京时间 2026-11-19，断网 `ipvlan` 试验 `r5` 验证了动态邻居发现、两种模拟来源
地址透传、拒绝来源命中两次丢弃及清场。外层 IPv6 转发保持为 `0`，外层 HTTP
对照始终可达。随后 `r2` 在隔离的 Engine 29.8.2 上用正式 `.7` 包生成 Xray WS
部署，将发布端口绑定到测试 IPv6。外部命名空间的严格 TLS 和两个 WS 正例通过，
错误 UUID 和证书指纹均被拒绝。原点仅收到两次正例请求，计量为上行 240、下行
466 字节，重复采集保持一致。动态邻居、监听、容器和网络清理检查通过。

首轮 Engine 因无法访问 devices cgroup 而未启动。`r2` 仅切换网络命名空间后通过。
原件见 `.tmp-native-ipv6-public-20261116/` 的 `ipvlan-source-r5.log` 和
`ipvlan-engine-r2.log`。该结果覆盖断网拓扑，公网直连仍待可独立使用的 IPv6
地址与回程验证。

北京时间 2026-11-21，VPS B 使用短时独立 IPvlan 网络命名空间验证公网 IPv6 回程。
外部 Linux 客户端直连测试地址的 TCP/28604，双端核对同一随机串，服务端确认
原始客户端 IPv6。前三次尝试中，第一轮因 systemd 提前展开变量退出，第二轮因
网关邻居预检退出，第三轮确认已知网关及 MAC 后完成回显。宿主 IPv6 转发保持为 `0`。

第三轮回收了测试接口和监听端口，但归还地址时改变了 `eth0` 的地址顺序和标记，
默认出站选源随之改变。先通过停用该别名的首选寿命恢复选源，再用断网试验验证
地址原样恢复期间同一 TCP 连接的 220 次往返。B 随后恢复原地址顺序、标记和寿命，
四条既有 IPv6 连接、两条默认路由和三个健康生产容器保持。外部 HTTPS 回显确认
默认源已恢复。夹具见验收 worktree 的 `.tmp-ipv6-closure/`。

本次回显验证了公网 IPv6 链路回程和原始来源透传。正式应用证据见下方，
deferred 状态不变。

同日，B 的独立 Docker Engine 验签安装正式 `.13`，使用原生 IPv6 bridge 和真实 `edit`
启用 Xray `202`，从 TCP/28604 迁移至 TCP/28605。外部 Linux 客户端在两个端口各通过
HTTP 和严校验 HTTPS CONNECT，错密各返回 `407`。Xray 容器网络命名空间各见证四个
独立 TCP 连接，来源与 B `eth0` 先前观测的公网 IPv6 相同。旧端口已无映射和监听，
公网探针超时。同一轮撤销来源后，客户端首次连接超时，未取得应用拒绝证据。
归还地址后已核对顺序、标记、默认选源、四条原连接和三个健康生产容器。上一轮只验
到启用，旧端口探针超时提前退出。原件为验收 worktree 的 `.tmp-ipv6-closure/`。
`202` 公网直连、认证和端口迁移通过。公网来源撤销、停用、规格恢复及完整原点计数待验。

同日，以同一正式 `.13` 签名包和镜像在本机独立 Engine 29.8.2 复验 `202`。
真实 `edit` 完成 IPv6 启用、迁移端口、撤销名单和停用。应用容器分别见证
4、4、2 条独立连接均保留客户端来源。撤销后 HTTP 返回 `503`，CONNECT 建立后
未能握手目标 TLS。新旧端口与名单结果均通过，停用后恢复原部署规格，私有原点
精确收到四个正例，容器和卷已清理。Cosign 使用既有的 Sigstore 信任根在隔离环境
验签，另以修改过的清单验证拒绝。原件 `.tmp-ipv6-closure/local-202.log`。
该轮补齐正式 `.13` 隔离 IPv6 的 CLI 生命周期。公网撤销、停用与完整原点计数仍待验。

2026-11-21，本机 IPv6 客户端连接显示本地回环地址，B 的 `eth0` 未捕获探针。
改用 VPS A 的临时 Xray WARP IPv6 出口后，客户端收到 B 的 IPv6 SSH 标识，
B 的网卡捕获同轮入站 SYN，见到一个全球 IPv6 来源。临时设备已撤销，
专用服务、端口和文件已清理，A 的三个生产容器身份、启动时间、重启次数
和健康状态前后一致。该轮覆盖 A 至 B 的公网 IPv6 TCP 路径。
原件 `.tmp-ipv6-closure/warp-path-preflight-r3.log` 的 SHA-256 为
`404b3313fa84471ebcb72df4ac1677e3aef2cde9883798033074329341a31d67`。

完整中继夹具需要把现有次 IPv6 地址交给隔离实例，清场时恢复宿主地址顺序。
自动审批因恢复需短时移除并重新添加主 IPv6 地址，可能影响在途连接，拒绝运行。
本轮已确认 B 的三个全局 IPv6 地址均登记在宿主网卡配置，主地址存在四条 TCP 连接。
公网撤销、停用、规格恢复和原点计数仍待验收。

北京时间 2026-11-18，使用 `v3.44.5` 源码快照及清单绑定的 amd64 `ops`、`nginx`、`xray`、
`sing-box` 镜像，在独立断网 daemon 内补验 ACME。Pebble 本地 CA、发布信任夹具
和强制到期限定本轮范围。standalone 的九文件恢复、材料校验、证书序列变化及账号
密钥保持通过。webroot 和 TLS-ALPN-01 的空目标恢复、业务计量、两种证书消费故障
回滚及续期通过，分别观察到 89 和 127 次 HTTPS 请求。DNS-01 使用仓库定向入口
与既有镜像夹具通过，覆盖权威 TXT 变更、凭据绑定和强制到期续期。各轮测试容器及
其独立卷均已清理。

首轮 Docker 导出时筛选平台导致夹具 OCI 索引摘要变化，重导出保留原索引后通过
镜像校验。原 webroot/ALPN 探针访问 `172.31.0.1` 超时，改用断网命名空间的
`192.0.0.33` 回环原点后通过。失败原件及通过日志均保留在
`.tmp-ipv6-formal3444-20261118/v3.44.5/acme-*`，DNS-01 证据保留在
`.tmp-regression-docker-2bcab81297f84b66a0defece9d3a1ada/`。
A 的自然续期待北京时间 `2026-12-17 08:03:22` 阈值后的实际调度与证书消费。

功能合同的 13 条 `reason` 已对齐 ARM64 收口口径、双 Peer 恢复和上述专项证据。
结构化对比仅发现说明字段变化，`docker-phase3` 通过。回归原件
`.tmp-regression-docker-dd3f0669f08d48398fd5c6277cd6feda/`。

## 正式 v3.44.7 的 WARP 公网出站

北京时间 2026-11-19，以一次性免费设备取得真实 Cloudflare WARP Peer。
使用正式发布源码渲染全局 IPv4 WARP 配置，复用签名清单绑定的 amd64 核心。
测试以回环 SOCKS 入口接入生成的路由和 WireGuard 配置。断网环境的规格校验及
两个核心的回环启动通过。

- 本机隔离 Linux 容器里的 Xray 返回 `warp=on`，与同环境 `warp=off` 对照
  的公网出口地址不同。早期 Xray 请求重置与该轮 sing-box 请求超时均保留。
- A 用非特权进程运行相同夹具，sing-box 返回 `warp=on`，与 A 的直连对照
  的公网出口地址不同。该轮 Xray 请求重置。设备撤销成功，随后独立复核临时
  目录和回环端口已清除，三个生产容器健康。

早期规格夹具的入口 ID 与 Reality 公钥错误已修正，失败保留。测试设备按轮撤销，
测试输入和探针见 `.tmp-warp-daily-close/`。后续本机隔离容器的四个公网 HTTPS
用例全部通过。两核心的全局 IPv6 均返回 `warp=on` 和真实 IPv6 出口，选择性
IPv4 的匹配域名均返回 `warp=on`，未匹配请求均返回 `warp=off`。该轮设备已撤销，
退出码为 `0`。跨网络路径的早期重置和超时根因及长稳待验，路由与内部 206 仍为 deferred。

同日复用 `.7` 配置和核心构件，在 Docker Desktop 两种网络各跑一轮持续
全局 IPv4 探测。每个核心保持同一进程至少五分钟，逐次校验 HTTPS、
`warp=on`、出口地址族和与直连对照的差异：

| 网络 | Xray | sing-box |
| --- | --- | --- |
| 默认 bridge | 309 秒，0/12，连接超时 | 301 秒，20/20 |
| host | 301 秒，20/20 | 310 秒，0/13，TLS EOF |

bridge 抓包期间，Xray 的 UDP 源端口只有握手请求，切换到 sing-box 后
捕获到另一个源端口的握手回包和后续数据。bridge 上用同一设备重启 Xray
三次，采样依次为 4/4、0/3、4/4。host 网络的 sing-box 重启对照三次均
为 0/3，核心每次报告 `context deadline exceeded`。本机四轮设备撤销、
容器清理均完成。采样原件在 `.tmp-warp-daily-close/warp-*-20261119-*.log`。
持续通过范围限上表固定组合，失败组合的根因仍待确认。

B 的原生 Debian 对照使用同一一次性 WARP 配置顺序启动 Xray 三次。每次
进程保持 45 秒，四次 HTTPS 采样均通过，共 12/12。首轮 B 侧注册失败，
第二轮工作目录无法执行核心。最终改为本机注册，经固定主机公钥的 SSH
传送测试配置，从 B 已验证的执行目录启动。设备撤销、临时目录和端口清理、
生产容器、网桥、路由及防火墙基线复核通过。原件在
`.tmp-warp-daily-close/padm-warp-native-466b4ee24692.log`。失败轮保留。

2026-11-19，Docker Desktop（Engine 29.9.3，WSL2 内核 6.6.87.2）用同一个临时
Peer 和相同的正式核心构件做八轮交替测试。全局 IPv4 下，Xray 在 bridge、host
各 4/4，sing-box 各 0/4。
首轮抓包因工具默认切换 UID 失败，所用 Peer 已撤销。修正后完成八轮。
共用外部 UDP socket 的附加试验中，Xray 有握手请求无应答，sing-box 无握手
到达回环转发器，两个核心在该夹具下各 0/4。

原始 bridge 路径另用一个临时 Peer 走 Xray、sing-box、sing-box、Xray 四轮。
Xray 两轮各 2/2，sing-box 先 2/2、后 0/2。成功的三轮在容器 `eth0` 各看到
一个按源端口和索引匹配的握手应答。失败轮的六个握手请求设备标记均正确，
同接口无握手应答，另收到五个其它 UDP 包。该轮故障在探针的 TLS 建立之前，
丢失位置、其它路径的失败原因和长稳待验。三个正式采样轮次的 Peer 均已撤销，
临时容器余量为零。原件为验收 worktree 内的 `.tmp-warp-network-crossover-retest.log`、
`.tmp-warp-shared-socket-result.log` 和 `.tmp-warp-direct-headers-result.log`。

同日，B 在原生 Debian 的临时 systemd 单元用同一 Peer 交替启动两个核心，
Xray 通过 5/5，sing-box 通过 6/6。随后用另一个临时 Peer 各运行一个持续
300 秒的进程，双核心各通过 21/21 次全局 IPv4 HTTPS 采样。每次校验 `warp=on`、
出口地址族及与直连出口的差异。两轮设备均已撤销，临时缓存、监听和容器已清，
生产容器、路由、`docker0` 和防火墙基线一致。原件
`.tmp-warp-daily-close/padm-warp-native-7eb2fe85b858.log` 及
`.tmp-warp-daily-close/padm-warp-native-c7215f6eb799.log`。

同日，B 复用正式 `.7` 生成器和 amd64 核心，在独立的临时 systemd 单元中
依次测试 Xray、sing-box 的全局 IPv6 和选择性 IPv4。四组各持续至少 120 秒，
各通过 9/9 次 HTTPS 采样。匹配请求验证 `warp=on`、出口地址族和与直连出口的差异，
选择性 IPv4 的未匹配请求返回 `warp=off`。临时设备已撤销，进程退出码为 `0`，
本机临时容器余量为零。B 的临时目录、缓存及监听已清，生产容器、网桥、路由和
防火墙与前置快照一致。原件 `.tmp-warp-daily-close/padm-warp-native-17fab55522f0.log`。
采样范围为固定原生宿主的出站探针。其它路径、长稳和受管部署故障恢复仍待验。

2026-11-20，A 用同一临时 WARP Peer 顺序运行正式 `.7` 的 Xray 和
sing-box。Xray 运行 900 秒，sing-box 运行 901 秒，各通过 60/60 次
全局 IPv4 HTTPS 采样。每次验证 `warp=on`、IPv4 出口和与直连的差异。
前一次 SSH 传输中断后设备已撤销。本轮改用分段上传并核对归档摘要。
正式采样退出 0，测试设备撤销，临时目录、端口和容器清场通过，生产
容器、路由、网桥和防火墙基线一致。原件
`padm-warp-native-8b0c059d192c.log` 的 SHA-256 为
`16511f99375e0c0aaa894c7173f0803771d7fb0e95aff80920a52400ae21fcfb`。
证据覆盖固定宿主顺序运行的 15 分钟窗口，受管双核心并发长稳仍待验。

## 正式 v3.44.8 的受管 WARP 切换与恢复

2026-11-19，独立 Debian 13 amd64 虚机使用 Docker Engine 29.9.3，安装验签
`v3.44.8` 并配置 Xray、sing-box 两个 Trojan TLS 发布入口。客户端验证测试证书，
经两个入口访问公网 HTTPS。正式 `edit` 依次启用全局 IPv4、切换全局 IPv6、
切回 IPv4 并改为选择性路由。两个入口的匹配请求均验证指定出口地址族和
`warp=on`，选择性路由的未匹配请求验证 `warp=off`。

正式 `restart` 后，两核心容器均达到 `healthy`，选择性 IPv4 的匹配和未匹配
探测均在首轮通过。正式 `edit --warp-off` 后两个入口恢复直连，部署规格与两份
核心配置的 SHA-256 逐项回到基线。设备撤销、虚机正常关机、本机容器清场通过。
原件 `.tmp-warp-daily-close/managed-guest-r8.log`，SHA-256
`0b0fe55526b559f8967e602e23141baaf72c0c7b2248bc93a5e0413823669e03`。

此前 `r7` 的重启后即时探测返回 curl `97`，设备撤销成功，虚机正常关机等待超时。
旧轮原件保留。

`r9` 和 `r10` 的全局 IPv4 双核心基线均通过，分别在全局 IPv6 和选择性 IPv4
切换后探测超时（curl `28`）。`r11` 将场景缩至全局 IPv4，Xray 基线通过，
sing-box 探测超时。三轮均在断链注入前退出，设备已撤销，虚机已正常关机。
原件在 `.tmp-warp-daily-close/managed-guest-r9.log`、`managed-guest-r10.log`
和 `managed-guest-r11.log`。

`r12` 在同一正式包的独立虚机内完成全局 IPv4 断链与恢复。Xray 和 sing-box
在注入前首轮均返回 `warp=on`。虚机加入 WARP 对端的 `/32` 黑洞路由后，
宿主直连对照仍成功，两个业务入口分别超时（curl `28`），响应正文均为空。
保持黑洞路由时，正式 `edit --warp-off` 恢复两个入口的直连，规格和两份核心
配置摘要回到基线。移除黑洞路由后确认路由表无残留，测试设备撤销，虚机正常关机。
外层接口记录到 62 个对端 UDP 包，内核丢包计数为 `0`。原件
`.tmp-warp-daily-close/managed-guest-r12.log`，SHA-256
`ab4ac457b0d64f747eacb1ee19e5545452e6e21fa61c92da05dc78acb800742c`。

`r13` 的 10 分钟双核心采样在基线阶段退出。Xray 全局 IPv4 首次探测通过，
sing-box 连续四次在 12 秒窗口内超时。两次探测阶段分别对应两个外层 UDP
源端口。超时阶段的端口向对端发出 11 个 148 字节报文，未观察到该端口的回包。
同一接口上另一个端口与对端有往返，内核抓包丢包计数为 `0`。
设备已撤销，虚机正常关机。原件 `.tmp-warp-daily-close/managed-guest-r13.log`，
SHA-256 `0b93d0bfbf6ce3d8db27ae11b6b8cd389e7efc149e5e227f9ec643f7e6e47d67`。

`r14` 在同一虚机和同一个测试 Peer 上，先暂停 Xray 容器再探测 sing-box。
恢复 Xray 后，两入口按顺序探测。三个探测均首次返回 IPv4 `warp=on`。
关闭 WARP 后两入口均恢复直连，规格和配置摘要复原。设备撤销，虚机正常关机。
原件 `.tmp-warp-daily-close/managed-guest-r14.log`，SHA-256
`3cd89c303711e8fb13deaeb9cccdc35a908182ed96b65d962779907b6360fea4`。

`r15` 在相同拓扑下完成 600 秒全局 IPv4 采样。两入口共用一个临时 WARP
设备，每 15 秒并行发起一组严格 HTTPS 请求。Xray 为 `0/40`，sing-box
为 `34/40`。其余 46 次均为 curl `28`。抓包尾段观察到一个 UDP 源端口
持续发送 148 字节报文且没有回包，另一个端口有双向流量。正式关闭 WARP
后，两入口首轮恢复直连，规格和核心配置摘要匹配基线。设备已撤销，虚机
正常关机。原件 `.tmp-warp-daily-close/managed-guest-r15.log`，SHA-256
`7750f6036dcc81f49e4b3dabe12f9f74e015edd8dc66fb54df407cee9ccc1bfb`。

`r16` 在独立虚机内按共享设备、sing-box 独立设备、恢复共享设备运行各 90 秒。
每段重启 sing-box，Xray 进程的启动时间保持一致。Xray 三段均为 `6/6`，
sing-box 依次为 `6/6`、`5/6`、`5/6`。独立设备阶段出现一次 curl `97`，
恢复共享阶段出现一次 curl `28`。这三段尚不足以确定共享设备与故障的关系。
恢复共享配置后，正式关闭 WARP，两入口恢复直连，规格和核心配置摘要匹配
基线。两台测试设备均已撤销，虚机正常关机。原件
`.tmp-warp-daily-close/managed-guest-r16.log`，SHA-256
`421121177bc2eee4a3654870d7707864b43a7b040e80b5b894cc15c082fbe7ef`。

2026-11-20，`r17` 把 `r16` 的共享、独立、恢复共享设备三段各延长到
360 秒。每段并行采样 24 组，Xray 依次通过 15/24、13/24、12/24，
sing-box 为 12/24、2/24、11/24。失败均为 curl `28`。两种设备安排下
均有超时，单独给 sing-box 分配设备未恢复稳定。外层接口捕获 4,229 个
报文，抓包丢弃为 0。正式关闭 WARP 后，两个入口首轮恢复直连且配置摘要
匹配基线。两台测试设备已撤销，虚机正常关机，临时容器已清。
原件为 `.tmp-warp-managed-crossover/r17-live.log`，SHA-256
`245db2341c43167cb881db77ec245edb84bcb88e2c00efa1ed1992adb1b0c928`。

正式 `v3.44.11` 的双核心受管复验绑定 `b7921010` 及正式清单。
全局 IPv4 共用一个测试 Peer 并发采样 600 秒，Xray 为 32/40，sing-box
为 36/40，十二次失败均为 curl `28`。外层共捕获 2,520 个报文，抓包
丢弃为 0。正式关闭 WARP 后，两入口首轮恢复直连，规格和配置摘要回到基线。
测试设备撤销，虚机正常关机，临时容器清场。原件为
`.tmp-warp-managed-crossover/formal-34411-soak.log`，SHA-256
`2d0f80dfccb227c083e3aeeaf3721d30b1c8566399366f0cebf6976470bcf588`。

2026-11-20，正式 `v3.44.12` 共用一个 WARP Peer 并发采样 360 秒。Xray 通过
8/24，sing-box 通过 4/24。36 次 curl `28` 中有 5 次已完成 TLS 握手，
但超时前未收到 HTTP 首字节。另 31 次未记录连接完成时间。按来宾与外层
时钟偏移区间核对，每次超时所在窗口均有外层 WireGuard UDP 入站和出站。
抓包共 2,340 个报文，抓包丢弃为 0。下一轮需按单核心或独立外层流归因，
以区分并发报文与超时流量。关闭 WARP 后两个入口恢复直连，规格及配置回到
基线。测试设备已撤销，来宾正常关机。原件为
`.tmp-warp-managed-crossover/diagnostic-34412/diagnostic.log`，SHA-256
`d099382979c4735f3d7e2de43d806b77819ff9e522f13289644371b125d4096b`。

同一来宾拓扑改为依次暂停另一个核心，Xray 通过 2/8，sing-box 通过 3/8。
11 次超时中有 4 次已完成 TLS 握手，两个核心各 2 次。单独运行亦可复现。
外层捕获 501 个报文，抓包丢弃为 0。两个核心恢复运行并关闭 WARP 后均恢复
直连，配置返回基线。测试设备撤销，来宾正常关机。原件
`.tmp-warp-managed-crossover/solo-34412/diagnostic.log`，SHA-256
`c428e9c9e6370d1470a56af8c45b6ed27338d61066d8d6885ed19188ce11d8f6`。
按时钟偏差的完整区间重新核对，每个核心的单独采样阶段各只有一个外层 UDP
流。11 次超时中有 9 次所在窗口仍有双向报文。Xray 第 4 次和 sing-box
第 7 次只观察到发包，分别为 12 和 6 包。外层双向活动无法证明内层请求
已经交付，也无法定位这两次未见回包的环节。
双核心公网长稳、握手回包丢失位置及其它模式故障注入仍待验。

### 正式 v3.44.13 的 Docker Desktop 出站对照

2026-11-21，在 Docker Desktop 的隔离 Debian 13 容器内启动独立 Engine，
验签安装 `v3.44.13` / `7e46256b`，按正式清单拉取五个镜像。外层经
Docker Desktop bridge 出公网，取消此前试验的 QEMU 用户态网络转发。
正式双核心部署共用一个一次性 WARP Peer，连续 900 秒。每 15 秒从两个
入口经 WARP 请求同一个 HTTPS trace，同时从外层测试容器直连该地址。
Xray 通过 8/60，sing-box 通过 4/60，同批直连 60/60。108 次 WARP
超时中有 13 次已完成 TLS 握手但未收到首字节。

在隔离容器的外层接口抓到 463 个 WARP UDP 报文，内核抓包丢弃为 0。
完整覆盖的超时窗口内，按运行时套接字端口核对，Xray 有 6 次、sing-box
有 8 次在各自端口见到双向报文。另一次 Xray 超时窗口只观察到出站。
取消 QEMU 转发后故障仍可复现。报文摘要只证明相应端口的活动，丢包位置
仍待在独立的公网出口路径上对照。正式 `edit --warp-off` 后，两个入口
均在首轮恢复直连，部署规格和两份核心配置摘要与基线一致。临时设备已撤销，
部署容器、注册容器和抓包容器均已退出并清理。

原件 `.tmp-warp-managed-crossover/`。`direct-34413-separate.log` 的 SHA-256
为 `8cc4a4769dde15eb2347a847ab52dbc34785c2b3bcbb1f7456eddc6fafeab856`，
`direct-34413-udp.log` 为
`dea39ede9b561110db03cc71789f4535949004873b74bf6a0aedc55ab09f1dd6`。

同日使用正式 `.13` 的相同双核心配置在 VPS B 的隔离 Debian 容器复验。
独立 Engine 测试限 0.34 核、368 MiB，未映射外部端口。共享一次性
Peer 的 360 秒采样中，Xray 与 sing-box 均通过 14/24，直连 24/24。
20 次超时中，Xray 有 1 次、sing-box 有 3 次完成 TLS 后未收到首字节。
两个入口关闭 WARP 后首轮恢复直连，规格和配置摘要与基线一致。
设备已撤销，测试容器和网桥已清理，B 三项生产服务及默认网桥隔离复核通过。
故障在独立公网出口仍可复现。原件 `.tmp-padm-wan-bd9b6ae9d4/` 的
`warp-vps-soak.log` SHA-256 为 `217e7d6287a7cbe86884dc2c1fef4ca089a3ad1ac16fa87bae5999e0ad699e8a`。

在本机用同一正式配置另跑 240 秒，每批交替请求 Cloudflare trace 和固定
IPv4 的自有 HTTPS 源站。每个目标八批。trace 两个核心均为 8/8，自有
源站 Xray 为 8/8，sing-box 为 7/8。直连对照 16/16，TLS 和预期正文通过。
自有源站日志在七批见到直连和两个 WARP 出口，余下一批只见直连及一个
WARP 出口。该批 sing-box 在建立 TLS 前超时。自有源站同样可复现超时，
故障仍有间歇性。关闭 WARP 后配置摘要回到基线，设备和容器已清理。

原件 `.tmp-warp-managed-crossover/` 的 `targets-34413.log` 和
`targets-34413-origin.log` 的 SHA-256 分别为
`ddd5df1b010f5fdb79ecd84ec050022c3fad937b2b54dbc7cc04b424dd00f5ad` 和
`703b1de67b9f1bef428b9e7fa2c7e820f9015dc22b1c87de9923f4d0a4a68679`。


2026-11-21，沿用正式 `3.44.13` 的双核心隔离部署和同一临时 IPv4 WARP
Peer。依次以 MTU 1280、1180、1280 重启两核心并各采样 120 秒。
Xray 依次通过 2/8、1/8、0/8，sing-box 为 0/8、4/8、0/8。
同期直连 24/24。两核心共 39 次超时和两次 TLS EOF，较小 MTU 下仍出现失败。
样本不足以量化 MTU 的影响，长稳和故障定位仍待验。

关闭 WARP 后两入口均在首轮恢复直连，部署规格及两份核心配置摘要与
停用基线一致。临时设备已撤销，隔离部署已清理。原件
`.tmp-warp-managed-crossover/mtu-34413.log` 的 SHA-256 为
`efe944ecaa874fa9794ecc98c8248d62715231e620e218f909a726d77a39e9ff`。


同一正式版另测 HTTP/1.1 连接复用。每组由一个 curl 进程连续发两次请求，
每条路径八组。直连 16/16，八次复用均返回预期正文。Xray 8/16，
其中三次复用成功。sing-box 4/16，新连接的请求可成功；两组首个请求
成功，第二个请求未建立新连接，在收到首字节前超时。复用已有连接仍可
复现故障。关闭 WARP 后两入口首轮恢复直连，规格和配置摘要回到基线，
临时设备已撤销，隔离部署已清理。原件
`.tmp-warp-managed-crossover/reuse-34413.log` 的 SHA-256 为
`a872e9007833f2cdd9f64a0ea2b08f17d28833ebb3632842bd84781413aca2f9`。

## Cloudflare 隔离透传

2026-11-20，Cloudflare 区域已启用 gRPC、HTTP/3，SSL/TLS 为「完全」。
在 A 使用正式 `v3.44.11` 绑定的 Xray 与 nginx 镜像，配置独立测试源站。
临时代理 A 记录和精确域名规则将边缘 TCP/443 的请求转发到源站 TLS/8443。
源站直连以测试 CA 校验 TLS，gRPC 和 XHTTP packet-up 正反例均通过。
经 Cloudflare 重跑，两种传输均返回预期源站正文，未授权测试目标均被拒绝。
XHTTP 客户端仅提供 `h3`，镜像所用 Xray 冻结版本按此配置选用 QUIC
传输。独立 `--http3-only` 和 HTTP/2 健康探针均返回 200、`CF-Ray`
与预期正文，源站记录 gRPC POST 及 XHTTP GET/POST 均为 HTTP/2。

临时规则、代理记录和源站均清理。两台 Cloudflare 权威 DNS 确认测试域名
已无 A/AAAA，A 的三个生产容器均健康。该轮使用镜像直接配置，受管 CLI、
其它核心、传输和公网 IPv6 组合仍待补。原件在验收工作树
`.tmp-cdn-formal-probe/`。协议验收与边缘探针日志 SHA-256 分别为
`56b6c9ac29ddab194c188ca8ee0a4af165a63c4dee0e4e1ae7e1cfd29ee4fe19`、
`c45381095ba98e06d1d6a60463fec84faade5826a85bbd7e27933201c906e4b6`。

同日只读复核，Cloudflare 区域无 Origin Rules，两台权威 DNS 对测试域名的
A/AAAA 均返回 NXDOMAIN。使用正式 `.11` 源码的离线 CDN 管理事务回归通过，
发布和宿主服务动作由夹具替代。另用正式四个 amd64 镜像运行真实容器链路。
原夹具的私网测试原点被 Xray 默认出口规则拦截，21/24/25 的首个 TCP 正例超时。
在测试副本指定本轮 IPv4 原点和两个业务端口后，Xray 21/24/25 与 sing-box 23
通过地址覆盖、清除、认证正反例和服务保持检查。Xray 22/23 的正例在 VMess
请求收到 EOF，服务端报 `unknown security type: UNKNOWN`。
保留通过和失败原件，临时测试夹具未合入。公网受管 CLI 全生命周期仍待验。
原件在 `.tmp-cdn-managed-34411/`，事务和分组链路日志 SHA-256 分别为
`0abfd04ac8ef79232dbaeeb62b41032bbbd717eb255ea67dccf7a8b540053503`、
`3b4ce9197d25f2c5effb48129bcd5d2a78268fc297a84a2c44567c872213a756`。

后续对照确认，sing-box 在 TLS 下把 VMess 的 `auto` 转为 `zero`，
固定 Xray v26.11.9 拒绝该值。链接与订阅改用显式 `aes-128-gcm`。
修复源码与正式 `.11` 四个镜像的隔离链路通过 6/6，覆盖 TCP/UDP、负例、
CDN 地址覆盖与清除及服务状态。旧主订阅与新分享组可共存，篡改正文会拒绝编辑。
已有部署升级后可通过受管编辑重新生成订阅，客户端需刷新已保存的旧链接。
原生订阅格式回归通过。完整链路日志 `vmess-final-matrix.log` 的 SHA-256 为
`48bc327e69d5c1c8714c9d220c15a1ee23f7ad14f4aad45c802cc216d7d7515e`。
公网受管 CLI 全生命周期仍待验。
修复 `f05b13fc` 已随正式 `v3.44.12`/`a4c60688` 发布。Release `44683952145`
完成 30 项、跳过 2 项。独立核对清单签名、控制包摘要及五镜像的 amd64/arm64
绑定，五镜像均复用 `.11`。控制包内两份 Docker 订阅修改文件与发布提交一致。

同日，正式 `.12` 在本机 Debian 13 amd64 独立来宾验签安装并核对五镜像。
固定 Xray WS/IPv4 入口的受管 CLI 预览、发布、换址及清除均通过。
每个阶段的状态、分享链接与订阅正文一致，原 SNI 和端口保持，清除后
正文恢复为初始字节，三项服务在线。来宾正常关机，父盘摘要一致，
三轮来宾的临时盘及测试密钥已清理。前两轮因签名工具未正确打包而中止。
正式来宾结果为证据卷 `padm-cdn-34412-native-proof` 内
`control-multipeer-1795156925310133845`。公网受管流程仍需单独验证。

同版 Xray VLESS gRPC 受管源站补验了直连正例、错误认证及错误 SNI 拒绝。
QEMU 转发在 Docker 容器内能完成 TLS，在 Windows 的 Docker 发布端口
处超时。A 的临时转发已关闭，生产三容器健康，Cloudflare 无本轮规则，
两台权威 DNS 确认测试域名无记录。Windows 系统盘再次耗尽，Docker Desktop
停止，E 盘测试子盘已移除。源站直连原件在上述证据卷的
`control-multipeer-1795166625230504153`。该轮未走通公网受管流程。

2026-11-20，正式 `.12` 的 Xray VLESS gRPC/IPv4 受管流程通过公网验收。
在 Windows Docker Desktop 的隔离 Linux 容器内验签安装控制包，核对五个正式
amd64 镜像。VPS A 仅接受 Cloudflare 来源到临时 TCP/8443，经 SSH 回环转发
到独立源站，并验证源站证书、SNI 与 HTTP/2 ALPN。
预览不改订阅。发布与换址后，状态、链接和订阅正文一致，通过 Cloudflare
使用已发布域名成功传输，两阶段均拒绝错误认证和错误 SNI。换址时新增的
`192.0.2.12` 只核对发布内容。清除后订阅正文恢复为初始字节，直连正反例
再次通过，每阶段三项服务健康。公网标记为 `a5d6e06b1c57135e-LAX` 与
`a5d6e1862c1e3b32-LAX`，转发独立记录 7 次 Cloudflare 来源连接。
临时代理 A 记录、精确域名规则、本机测试容器及其卷均已清理。两台权威 DNS
均返回 NXDOMAIN，A 的 8443/18443 均关闭，三项生产服务健康。
原件 `container-cdn-public.log` 的 SHA-256 为
`ba924356011146df1049caaefc0141b4884d90cccdea4153392d9c31ce249198`。

### 正式 v3.44.13 的 XHTTP 地址覆盖与独立下行

2026-11-21，在 VPS B 的隔离容器中验签安装 `.13`，外层不映射端口。
正式 CLI 配置 Xray Reality/XHTTP 后完成地址覆盖预览、发布、换址和清除。
预览保留原订阅，发布和换址的入口状态、链接与订阅一致。覆盖仅修改上行
地址，独立 H3 下行的地址、TLS 身份与 ALPN 保持。packet-up 实际回显及
错误 UUID、错误 Reality 身份拒绝通过。清除后订阅与实链路恢复，测试资源
已清理，B 三项生产服务健康。本机初轮被正式门禁以 `cloudflare_relay`
拒绝，B 从另一条公网出口通过同一门禁。原件 `.tmp-padm-wan-3e7ea788aa/`
的 `xhttp-vps.log` SHA-256 为 `9debab4a609eefa8e3da0e087dff22ed9adcfcf3edf55d19f95d214b5edca488`。

隔离实链路另使用同版生成的链接及清单绑定的 Xray 26.11.9。测试前置将
Reality 上行和独立下行接到同一 XHTTP handler。独立 Reality、TLS h2、
TLS h3 各四种模式通过，共 12 正例、8 负例及 12 次 1/8 MiB 双向完整性校验。
TLS 使用测试证书指纹，H3 有客户端日志见证。原件 `.tmp-cdn-xhttp-34413/`
的 `offline-r6.log` SHA-256 为 `c8f4822c8dc23382e809b6fe185d491496dffb817be7987f8460061d9cd39620`。

### 正式 v3.45.0 Xray 镜像的公网共享会话

2026-11-21，在 VPS A 的隔离服务使用 `v3.45.0` 清单绑定的 Linux amd64 Xray，
将公网 IPv4 的 Reality 上行和独立 H3 下行接到同一回环 XHTTP handler。
Windows Docker Desktop 的 Linux 客户端直连 A，随后改用独立的 VPS B 客户端
验证 Cloudflare 下行。本机直达 Cloudflare 的 QUIC 探针超时，B 的 HTTP/3
健康探针返回 204。Cloudflare 临时规则仅匹配测试域名，回源至 A 的 TLS/8443。
B 的客户端记录 HTTP/3，A 的 Caddy 记录对应 GET 为 HTTP/2 且带 Cloudflare Ray 标头。

两种路径各完成双向 1 MiB 摘要校验，均拒绝错误证书指纹和错误 UUID。
每轮回环原点精确记录 1,064,960 字节，含完整性校验前的 16 KiB 预热。
两台 VPS 的临时夹具、Cloudflare 代理记录及回源规则已清理，两台权威 DNS
对 A/AAAA 均返回 NXDOMAIN。A 的三个生产容器 ID、启动时间、重启次数和健康状态前后一致。

原件在验收工作树 `.tmp-xhttp-public/`。日志 SHA-256：

- `direct-r6.log` `05645e6482408ecc72c40a72a93d10427b6a41d11d1ccc9f8f52b20848739bcb`
- `cdn-r2.log` `5790d85616f59520b1741ac72f4ad66e938eebfd03194e892e447a6b7b7d5413`
- `dns-cleanup.log` `c57654d1c1436d23ebd554e9528d6134addce82c7bc994ca90683d4c2b11643b`

本轮限固定公网 IPv4/Xray 夹具。正式 CLI 生成的 Reality 入口缺少外部下行
接入同一处理器的接口，受管联合公网流程仍待验。合同计数为 16 supported、14 deferred。

## 正式 v3.44.7 的 XHTTP 持续传输

从验签发布 `44306096595` 的 amd64 Xray 镜像
`sha256:60167cebb872a0fed89ea8108e168d3ecf0dab0fff33ea982d97ed3a3d2244f2`
取出 `26.11.9` 二进制，分别在两个断网只读容器内测试 Reality/XHTTP。
每种模式用同一个 SOCKS TCP 连接和同一个回显连接，中途停发 20 秒后恢复。

| 模式 | 持续秒数 | 轮数 | 每方向字节 |
| --- | ---: | ---: | ---: |
| `packet-up` | 301.971 | 116 | 30,408,704 |
| `stream-up` | 301.846 | 141 | 36,962,304 |

逐轮回显摘要与服务端双向计量均匹配。损坏回显被探针拒绝，错误账号未到达
回显服务，计量无增量。离线复核确认镜像摘要、每轮长度、时间顺序、空闲间隔
和计量合计，测试容器已自动删除。探针和日志为 `.tmp-xhttp-sustained-3447.py`、
`.tmp-xhttp-sustained-3447-packet.log` 和 `.tmp-xhttp-sustained-3447-stream.log`。
早期短测曾被默认出站规则拦截，并在精确放行测试回环地址和端口后出现一次
`stream-up` reset。reset 根因待查。五分钟结果限于固定 amd64/IPv4 回环、
Xray 双端和本轮负载。公网及更长时间的稳定性仍待验证。

## 正式 v3.44.7 的双栈端口跳跃

使用 `v3.44.7` 源码归档和签名清单绑定的 amd64 镜像，在两套断网容器
及独立 Docker daemon 上复验 5C.9e。测试按原夹具从正式 `net` 基础镜像
覆盖同版源码入口。首轮配置校验拒绝了来自离线归档的裸摘要引用，补入签名
清单的标签后通过。已核对离线镜像 ID。

- Hy2 在 `115.719` 秒完成。五次采样中，同一客户端在两种地址族都跨过了
  `30000/30001`，客户端侧最终包计数为 IPv4 `3/30`、IPv6 `20/12`。
  初始化取消和超时均清理成功，停止后新连接被拒。
- TUIC 在 `52.056` 秒完成。双栈认证对照和监督进程中断后的显式恢复通过。
- 两轮中断后 NAT 均恢复，预览无写入，保存规格保持，活跃 owner 拒绝接管；
  清理旧容器后，以新代次重新启用，两族均能建连，最终停止并清场。

另在两套相同隔离环境内保留停止前的已认证业务流。两种协议的 IPv4
旧连接在停止后约 `0/5/10` 秒均通过 nonce 回显，IPv6 旧连接在首次采样时
已关闭。回显原点每轮只有原来的两个连接，首尾端口的双栈新连接均被拒，
NAT 规则恢复。Hy2 复测抓包中，两个 `docker-proxy` 监听进程保持原 PID。
停止后 IPv4 旧流仍从范围端口收到回包，IPv6 仅观察到目标基础端口回包。
两种协议另各静置 150 秒，期间探针暂停发送业务数据，抓包仍观察到同一
IPv4 路径的 UDP 报文往返，Hy2 为 28 包，TUIC 为 60 包。两条 IPv4
旧流随后在原连接上回显成功。该环境的 UDP conntrack 超时为 30 秒，
双向流超时为 120 秒。两族差异和停止后的最终排空时间待核。

随后在相同隔离环境中先停止跳跃，再分别用 Compose 和实际安装的同版
`padm-docker restart` 重启原 sing-box 容器。两种协议的原容器均以原镜像
和原账号数恢复健康，回显服务确认两个旧连接均已关闭。基础端口的双栈
新连接恢复，范围首尾端口的双栈新连接仍被拒。CLI 使用实际运行的 cron
及夹具安装路径。早期通过源码函数直接调用 CLI 的两次失败保留，第二次
无错误正文。客户端可能先读超时，旧流关闭由回显服务的连接终止验证。

日志见 `.tmp-formal3447-hy2-hopping-r2.log`、`.tmp-formal3447-tuic-hopping.log`
及 `.tmp-formal3447-{hy2,tuic}-existing-flow-r3.log`。抓包摘要在
`.tmp-formal3447-hy2-flow-path.log`，重启结果见
`.tmp-formal3447-{hy2,tuic}-flow-restart-r4.log` 和
`.tmp-formal3447-{hy2,tuic}-flow-cli.log`，静置观测见
`.tmp-formal3447-{hy2,tuic}-idle.log`。公网双栈和跨启动恢复仍待验，
TUIC 客户端自动换端口超出当前支持范围。

断流排空补验中，停止跳跃后两种协议各剩一条 IPv4 旧映射。暂停客户端核心
及目标容器后，静默抓包窗口内均为零 UDP 包。Hy2 在 `120.039` 秒观察到旧
映射消失，TUIC 在 `120.038` 秒观察到。探针每两秒采样，双向 UDP 超时为
120 秒。两轮 NAT 恢复，两个范围端口的双栈新连接均被拒，测试容器已删除。
此处关闭固定隔离拓扑的断流排空验证，持续有报文的旧流和公网双栈仍待验。
日志为 `.tmp-hopping-3447-drain-{hy2,tuic}-r3.log`，SHA-256 分别为
`6c0501a2bbeb11ae640a342ddee83873deb9fcabf10a44cda2673ef3577efcf7` 与
`94e1d4e1c352d4d6373febd9fb7aa567e2f116d6166499ba177f87ee007690e2`。

## 公网中继控制同步与灾备

2026-11-19，北京时间。正式 `v3.44.0` 上的一主两 Peer 同在本机的独立
Debian 13 amd64 KVM 来宾。两条 WireGuard 链路经 VPS A 的公网 IPv4 SSH
会话往返。控制 API 继续绑定 WireGuard 地址。

两台 Peer 在灾前及灾后各通过原 systemd 定时器同步一次。旧主控关机后，
空白替代机验包并显式重建主控，WireGuard 身份保持。两份旧邀请返回 HTTP
`401`，两端显式重绑并继续同步。灾后严格 TLS 正反例与双向计量通过。
A 记录四个方向分别转发 67、69、65、76 个 WireGuard type 4 报文。
四台来宾正常关机，SSH 中继退出，A 的三个生产容器均健康。

断网只读复核确认 915 份 JSON 原件，聚合 SHA-256
`43a806ecca6823e7cf571941aab32402f22d6583f7b52a4c49b01dbc127d579d`。
证据在卷 `padm-native-kernel-probe-20261116` 的
`control-multipeer-1795082492893391608`。原生跨宿主和其它灾备拓扑仍待验。

### B 公网 IPv4 UDP 中继

正式 `v3.44.0` 的两条 WireGuard 链路经 VPS B 的公网 UDP 端口转发。
三个业务节点位于同一物理宿主的独立 KVM 来宾。两条链路的 1,392 字节
探针均为 4/8。灾前第二台 Peer 首次定时同步返回 `11`，下一次原定时器
触发后自行应用修订。旧主控关机后，从已核对摘要的备份重建主控并保留
WireGuard 身份。第一台 Peer 首次显式重绑失败，保留该轮证据。

从正常关机的子盘接续后，两份旧邀请均返回 HTTP `401`，两台 Peer 均显式
重绑、恢复原定时器并自主应用灾后修订。两阶段合计四次自主同步。业务
复验在本地断网环境从子盘继续，恢复夹具在重启时丢失的临时测试地址后，
两台 Peer 的严格 TLS 正反例和双向计量均通过。断网只读核对 1,108 份 JSON
原件，聚合 SHA-256 为
`b0a1760ee197aa5b6929d6a7679430369e2f48a53c1e773bc792bcf869835423`。
同一证据卷中的三段原件依次为 `control-multipeer-1795098601734197328`、
`control-multipeer-1795101028686281948`、`control-multipeer-1795101966081827998`。
各阶段来宾正常关机，B 的临时端口关闭，三个生产容器均健康。

跨宿主直连另行验证。B 的 384 MiB KVM 来宾通过公网 UDP 双向回显、正式
验签安装、五镜像核对及业务配置。独立密钥探针为 7.713 秒，正式
`wireguard prepare` 返回 `10` 且无错误正文，宿主预检和密钥容器两处
都可能返回该码。同配额本地断网对照通过，耗时 6.198 秒。B 测试来宾停止，
临时目录与端口已清理。原件 `control-multipeer-1795095146114912321`。
正式 `v3.44.10` 的 B 来宾复验通过 UDP 回显、验签安装、五镜像核对和
业务配置。独立密钥容器耗时 35.787 秒，正式 `wireguard prepare` 报密钥
容器退出 `124`。三个来宾正常关机，远端测试目录和端口均清场。
原件 `control-multipeer-1795105405773592923`。将首次准备的容器时限
调到 60 秒后随正式 `v3.44.11` 发布，三附件验签及五镜像绑定核对通过。

`.11` 首轮 B 来宾的正式 `wireguard prepare` 和 `peer` 分别在 244.73 和
124.89 秒内完成。`wireguard start` 已进入候选容器验证，随后达到验收脚本
600 秒等待上限，未取得正式命令结果。第二轮延长了脚本等待，准备阶段
密钥容器返回 `137`，同轮独立探针耗时 38.066 秒。已查的宿主与来宾
内核日志无 OOM 记录。两轮三个来宾均正常关机，临时目录和端口已清场。
原件为 `control-multipeer-1795109071744863074`、
`control-multipeer-1795112093581856321`。

`.11` 第三轮在 384 MiB 的 B 来宾复验。公网 UDP 双向回显、正式验签安装、
五镜像核对、业务配置、`wireguard prepare` 和 `peer` 均通过。
`wireguard start` 的候选 WireGuard、Xray 和 nginx 检查已经运行，随后
Compose 启动 WireGuard，报告 Xray healthy 和 nginx started。验收脚本在
1,200 秒后仍未取得 CLI 退出码。变更前的 Xray 统计采集也曾失败，保留原
累计流量。本轮未到公网 WireGuard 握手及控制同步阶段，阻塞点待定位。
三个来宾均正常关机，B 的临时目录与端口已清场。原件为同卷
`control-multipeer-1795114780858815793`。

从同轮本地 Peer 的正常关机子盘创建独立快照，在断网、384 MiB 来宾、
480 MiB 上限、70% 单核配额及直写磁盘对照中，`wireguard start` 在
24.8 秒返回 0。WireGuard 接口已启用，WireGuard、Xray、nginx 三服务均
健康，来宾正常关机。对照只覆盖本地启动，原件为同卷
`wan-start-only-1795118734527673118`。

本机使用正式 `.11` 绑定的 net 镜像，在独立容器内与 B 的独立网络命名空间
直连。密文 UDP 直接到达 B 公网 IPv4 的测试监听端口。双方均记录握手且
各收 4/4 个隧道 ICMP 回包，WireGuard 收发计数互证为 1,116/1,172 字节。
临时命名空间、接口和端口已复核清理。原件 `native-direct-proof.json` 的
SHA-256 为 `f3112bb09701f66c7c6e9ef1073fd7d6e2571dd892da05e876e9d8ddf9971c43`。
本轮覆盖公网传输。正式跨宿主同步与灾备仍待验，合同计数保持
16 supported、14 deferred。

B 复用正式 `.11` 的已验签测试盘，来宾业务配置退出 0，耗时 331.1 秒。
随后 `wireguard prepare` 的 SSH 连接在 banner 阶段超时，来宾正常关机。
另一轮在 344 MiB 来宾复用同盘时，B 本机也未取得转发端口的 SSH banner。
宿主采样的 CPU steal 达 71%–77%，测试 cgroup 未见 OOM。测试期间生产
订阅容器上报 unhealthy，33 秒后恢复 healthy，期间停止了测试来宾。
两台本地正式来宾正常关机，B 的三个生产容器复核健康，测试端口关闭。
B 的复用测试盘已在停机后清理。
原件为同卷 `wan-start-resume-1795133827680095337`、
`wan-start-resume-1795135508726738864`、`control-multipeer-1795135795151727567`。

2026-11-20，正式 `.12` 在 Windows Docker Desktop 的隔离 Linux 节点中验签
安装并核对五镜像。半核配额、432 MiB 和外层 512 线程上限下，正式 CLI 完成
WS 部署、WireGuard 启动和对端更新。双向各收 4/4 次 ICMP 回包，两端均记录
握手，正式节点收发计数为 1,116/1,204 字节，WireGuard、Xray 与 nginx 健康。
初轮 helper 的 `runc` 启动失败在无业务容器上同样复现。测试用 Docker 的
systemd 单元默认只允许 76 个线程，单元计数器记录 418 次触顶。去掉该单元
的重复限额并保留外层上限后，相同安全参数的 helper 连续通过 3/3。
原件 `capacity-local-pair-final.log` 的 SHA-256 为
`72f1beb2a857f156befa3fbf40890e2c4c95d185c4f6d63db8dfcbb65b7694c1`。
本轮进度为本机节点预检。A/B 仅只读核对，两机生产服务健康，
VPS B 的正式跨宿主定时同步和灾备整链继续待验。

正式 `.12` 的精简隔离 Peer 在 B 通过冷启动。默认桥依现有隔离规则拒绝
出站。专用网络通过清单验签及五镜像核对。内层 `runc` 原缺 `pids.max`，
容器 PID 1 先进入独立子组后，子组 PID 控制器委派与 helper 启动通过。
0.34 核、368 MiB 上限下，WS 部署、WireGuard 准备、配对与运行通过，
三个测试服务健康，无 OOM。测试网络和容器已清理，生产三个服务健康。
B 预检未映射公网端口。原件 `b-lean-preflight-20261120130920.log`，
SHA-256 `6ba82a508725d9e162660f653e36d56f0cbfb58519d26c2a5867e8c32bd950d9`。

同版在本机三个隔离节点完成主控备份和空节点替换。两台 Peer 在灾前及灾后
各由原 systemd 定时器同步，四次服务退出码为 0。旧主控先停机，两份旧邀请
返回 HTTP `401`，两台 Peer 显式重绑后保留原定时器，WireGuard 身份保持。
严格 TLS 正例及错误 UUID、错误 SNI 拒绝各两项通过，灾后双向累计增长。
四个测试容器与测试网桥已清理。原件 `.tmp-padm-wan-1abc13b07d/` 的
`events.json` SHA-256 为 `65b15997f9910980295bb50e90bad5381afdac4531a5b94092931eaa2b75598c`。

### 公网被控入组后的 WireGuard 端点丢失

正式 `.12` 在本机与 VPS B 间完成公网握手、双向各 4/4 探针及 B 入组。
前两轮启用 B 的自动同步返回 `11`。第三轮记录到 B 的 WireGuard 容器
重建、接口索引 `24 → 34`、学习的 Endpoint 变为 `(none)`。主控再次探测
4 发 0 收，本轮止于该探测。三轮都清理了 B 的测试 UDP，三项生产服务健康。
第三轮原件 `.tmp-padm-wan-1c65836363/` 中的 `events.json` SHA-256 为
`97d33461cbdee1cc87221f88bdea0c8065df300ab2097cd32e21993e2f863149`。

`192f8d9d` 仅在被控同步事务中保留未变且健康的 WireGuard 服务。本机
`docker-controller-peers-recovery-real` 通过，被控端在入组、同步、空主控
恢复后的重绑和再次同步中保持原容器及已学习端点。自动同步合同也通过。
两份回归日志 SHA-256 分别为
`b7d186c3f87ea6762e967f30334d235c64b9df9bf4c7475e575854279f44e5ce` 与
`6088eef64daf4d8b3ad3d2c5ff92ac4d5eba06fad0c8f53daea7bcb4a11640b4`。

### 正式 v3.44.13 公网双 Peer 同步与主控灾备

2026-11-21，正式 `v3.44.13` / `7e46256b` 在 Windows Docker Desktop 与
VPS B 的隔离 Linux 节点验签安装并核对五镜像。拓扑是一主两被控，其中
一台被控经公网 IPv4 直接连接，另一台在本机独立网络中。B 依靠学习到的
主控 Endpoint，入组、显式重绑及灾前灾后同步都保留原 WireGuard 容器、
接口和端点。两台 Peer 灾前、灾后各完成一次原 systemd 定时同步，四次
退出码均为 0。

旧主控先停机，空实例从备份恢复，公网 WireGuard 双向探针再次通过。
两份旧邀请均返回 HTTP `401`，两台 Peer 显式重绑后沿用原定时器。
灾后两台 Peer 的严格 TLS 正例、错误 UUID 和错误 SNI 共六个探针通过，
账号上下行累计继续增长。测试容器、网桥和临时 UDP 已清理，B 三项生产
服务复核健康。该证据覆盖这一公网 IPv4 拓扑，合同仍为 16 supported、
14 deferred。

原件 `.tmp-padm-wan-619b0d6770/`，`events.json` 的 SHA-256 为
`271452b53dbc89a3965b2986a754de9c3107c9eeb6422fe75d378baeeb930737`。

### 正式 v3.45.0 的双 Peer IPv6 底层灾备

正式 `v3.44.13` 的 WireGuard CLI 拒绝字面 `[IPv6]:端口`，首轮退出码为 15。
`94600eb3` 为受管端点加上 IPv6 校验，保留隧道内 RFC1918 IPv4 `/32`。
主线定向配置及迁移通过，隔离三节点另外抓到 IPv6 WireGuard 加密报文并完成主控恢复。
旧包降级说明随改动更新。

正式 `v3.45.0` / `ef30901e` 在本机独立三节点验签安装，五个镜像与发布清单相符。
旧主控先停止，新实例从备份恢复并接管同一 IPv6 端点。四阶段双向握手和计数合计
16 组，两台被控在灾前、灾后各执行一次原 systemd 定时器。两份旧邀请均返回 `401`，
新邀请重绑后严格 TLS 六个正反例通过，账号双向累计继续增长。被动 Peer 的
WireGuard 容器、接口及学习端点在入组、重绑和自动同步期间保持。测试容器、匿名卷
和网桥已清理。

证据为验收 worktree 的 `.tmp-padm-wan-0efc812e34/`。其中 `events.json` 的 SHA-256 为
`f5305ff0c0dafb262f043ce04803363cc261157a5ab5cac756dd0733bb0a3ef4`。
本轮覆盖 WireGuard IPv6 底层及原有 IPv4 隧道内控制。公网 IPv6 和其它既定拓扑待验。

### 正式 v3.45.1 本地单被控替换与公网复测

正式 `v3.45.1` / `1b6f5100` 在本机三个隔离 Linux 节点复验只替换一台被控。
主控与另一台被控保持在线且原授权保留。旧被控先停止，空节点恢复后用新邀请重绑，
旧邀请返回 `401`。两台被控的原 systemd 定时器自动从修订 1 同步到 2，TLS、流量
和累计计量通过。四个测试实例、测试网桥和匿名卷已清理。

本地原件 `.tmp-padm-wan-8009b6f430/`，其中 `events.json` 的 SHA-256 为
`f0ff407f6b2404f63223811294e9aafe6547f5a038b94f5cfc4f7f77c43b7d56`。

首次公网 IPv4 复测完成本机主控与 VPS B 的 WireGuard 握手和双向 ICMP 各 4/4。
B 的被控 `control join` 退出 `11`，入组失败原因待查。本轮 VPS B 清场和三项生产服务
健康均已核对。再次复测验签安装及五镜像核对通过，但 B 的 SSH 在 `wireguard prepare`
期间断开（退出 `255`）。本机测试资源已清理。自动清理期限后 B 的 SSH 仍超时，远端
清场和生产健康待核对。

两次公网原件分别为 `.tmp-padm-wan-6e5810eb61/` 与 `.tmp-padm-wan-0bbc6dda83/`，
对应 `events.json` 的 SHA-256 为
`a77b09f194b91556d099850090fe47f07df73821279d2f8822b710d44ab2c488` 和
`fd2d2b0d98aba29a7bc0e6a7d92f62bc295de230cf2b8386c175a104a9863ba7`。
公网单被控替换和公网 IPv6 灾备仍待验。

### TUN 启闭的 IPv6 拒绝回归

2026-11-21，主线 `f23ed61e` 的 TUN 在 Docker Desktop 隔离 Linux amd64 环境中，
用固定邻居的独立网络命名空间验证 IPv6 Echo。启用前和正常关闭后各收到一个对应
的远端回包。启用时，受管 ICMPv6 `no-route` 规则计数增加，出口未出现该次 Echo 请求。
关闭后目标路由与基线一致，TUN 归属状态已清除。

完整 `docker-tun-real` 同轮通过，包含 IPv4 direct、filtered、denied、TCP/UDP、
拒绝规则漂移及异常退出后保留证据。原生宿主、公网及 PMTU 待验。
原件 `.tmp-regression-docker-3de7bbd4c4fd4f40a6cb428daca05326/regression.log`，SHA-256
`2de9c56e9cc23659f940cae614e2df18da3cafbbbad697e0a137b2389b470cc6`。

补验在 TUN 关闭后清除两端的固定邻居。IPv6 Echo 恢复，出口动态学到对端 MAC，
邻居状态检查通过。未固定邻居的早期运行曾超时，自然收敛时间仍未确定。
完整 `docker-tun-real` 同轮通过，原件
`.tmp-regression-docker-2e405b77437644ae9e3c88083f0b6a7e/regression.log`，SHA-256
`7f39a37e2887dbd443718b6b1fad59e20de621ec4d829b91d64de2b8423fa95b`。
