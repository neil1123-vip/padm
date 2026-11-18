# Agent State

> 当前快照；证据见 Git 和 `.tmp-*`。

## 当前

- 16 supported、14 deferred。Hy2 `ss` 修复 `abf42b2f` 已发布。
- ARM64 架构默认接受，口径 `96da9b10` 已推。未跑组合仍记作未实测。
- 正式 `v3.44.8`/`f1321157`，Release `44369981596` 通过，附件、签名和合同独验通过，复用 `.7` 五镜像。
- `.7` 回环 Reality/XHTTP 双模式各 5 分钟及 257 轮计量通过，短测 reset 待查。
- `.7` 隔离 Hy2/TUIC 跳跃通过。IPv4 旧流停后静置 150 秒仍通，重启核心后关闭。
- 6A.76：Mihomo v1.19.31 原 URI，amd64 的 Vision/XHTTP 22 点及 gRPC 6 点、
  ARM64 的 5 正/18 拒绝及清场通过；旧失败保持。证据 `a992e079`。
- A/B Debian 13 amd64/bridge、业务仅 IPv4、透明关闭；A `.4`/`51d5f658`，DNS 未改。
  B `.7`/`2f17e6ac` 从原 `.4` 恢复控制入口，业务及五镜像原版。
  B 单次整机重启补验通过；隔离先于 Docker，默认桥阻断未撤防。
- A/B 单 Peer WG 及规格恢复通过，已清密钥；0 显式账号、各 19 条历史账目。
  WS 443 公网正反例经 A 临时 SSH 转发通过并清场，不计 Windows 直连。
- A 自然续期阈值为北京时间 2026-12-17 08:03:22，待自然换证。

## 最近完成

- `0da791c4` 对账正式 `.3` 恢复与 ICMP。`44241272794` 的 direct、filtered、
  denied 三场景和清场关机通过，旧失败保持。证据见 6A.74–75。
- 6A.72/73/77 正式 `.44` 双 Peer：主控及单被控分别恢复、旧邀请 401、
  自主同步、TLS/计量独验；灾后三机重启、单被控替换时其余两台在线。
- 6A.74 正式 `.44` 恢复中断遗留 `.manifest.*`；`91e9f64c` 候选清理/重试/
  双 Peer 重绑及原 timer/TLS/计量独验；修复已进 `.1`。
  正式 `.3` 控制入口恢复 `.44`：active 断电、两次 recover、重试 healthy 独验通过；
  116 文件/旧封存/父盘绑定齐全，正常关机；证据 `.tmp-native-restore-powercut-*`。
- 6A.67–70 ARM64 的双核心生命周期、Engine 安装、双入口管理、
  Reality 共存/Encryption 及清场通过。Mihomo 限显式 hybrid 投影。
- 本地单 Peer 双机同步、重启、迁移、bind/TERM、新机 WG 恢复通过，已关机。
  `.8` 升级、控制防护和全文件恢复已独验。
- Dependabot 去重定向已验，真实新 PR 待验；jq/health/Peer 定向已验。

## 未决

- B 续期隔离保持；nftables 重载会清表，变更须核表和探针。
  实际续期、ARM64 整机重启/其它组合/公网入站、IPv6/长稳未验；
  Reality 其它加密生命周期和原 URI 组合未验，spec 恢复限语义。
- 控制迁移限本地双机单 Peer。公网多机、其它灾备拓扑、信号和长稳待验。
  保留三次采样、即时清场及 30 秒窗口。WSL 变化后核对 KVM 模块。
- 独立 SNI：别名整链、TLS 对照已验；跨站点被拒（3D.27）。
  A 无全局 IPv6；B 公网 TCP/22 与本机 Linux 客户端路径已互证。
  B 静态网关 FAILED；同内核隔离切换保留 RA 选路，公网回滚待验。
  B `.7` 公网 IPv6 限源中继：WS/Hy2/TUIC 正反例、计量、Xray 29 站点九项及清场通过。
  初轮受影响的 docker0 已恢复，续期隔离已复验。生产 443 仅 IPv4。
  公网保源、直连、站点 CLI 事务、其它协议及容量待验。
- ICMP 已验限 Debian 13/amd64/IPv4；arm64/公网/IPv6/traceroute/PMTU/重启未验；
  TUN/透明启用重启按要求不做。SOCKS UDP、Xray 解析后阻断继续拒绝。
- `.7` WARP 原生 B 五分钟双核心各 21/21。Desktop 的 sing-box 间歇缺握手应答。
  CDN 缺代理测试记录及设置核验。
  Vision reset/XHTTP/TUIC 旧超时根因未定；旧跨核心失败原件保持。
  固定公网组合不外推活动 sing-box；拒绝配对及带来源的跨核心复制。
  ML-DSA 仍限 amd64/IPv4/Reality/gRPC/chrome。

## 工作区

- 保留现有改动及 `.tmp-*`，私钥不提交。
