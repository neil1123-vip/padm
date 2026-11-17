# Agent State

> 当前快照；详细证据见 Git、实施计划及 `.tmp-*`。

## 当前

- 整体未收口；16 个协议管理 supported、14 个 deferred，支持状态未变。
- 当前正式 `v3.44.0`/`da790587`，独立上游自动更新发布；41 门禁全过。
- A/B 均 Debian 13 amd64/bridge/IPv4、透明关闭；A `.4`/`51d5f658`，DNS 未改。
- B `.7`/`2f17e6ac` 控制入口从原 `.4` 归档恢复，业务及五镜像保持原版。
  固定 WS 443 公网正反例经 A 临时 SSH TCP 转发通过，已清场，不计 Windows 直连。
- B 单次整机重启及补验通过；隔离先于 Docker 恢复，默认桥阻断保持，未撤防。
- A/B 单 Peer WG 正式 CLI 及原规格恢复通过；密钥已清空，账目保持。
- 本地正式 `.7` 完整内核双机单 Peer 的同步、启用态重启、迁移撤权、
  bind/TERM 恢复及新机角色/WG 恢复通过，均已关机。

## 最近完成

- `.8`/`6e880813` 发布，distroless 减 20.7%、完整 Geo；门禁及发布独验通过。
  证据 `.tmp-runtime-release-20261117/`。
- 6A.66 正式 `.8` 双 KVM 升级、防护及严格恢复通过，312 payload/五镜像、
  封禁/DROP/解封、TLS/计量及全文件恢复独验；正常关机、父盘保持。
  1940 份证据 `.tmp-formal-control-3438-20261117/`，旧失败保持。
- 6A.67 原生 Ubuntu ARM64/IPv4/Xray WS 正式 `.7/.8` 七阶段生命周期通过：
  安装、升级/回滚/再升级、restart、down/up、保留卸载重装、purge。
  22 客户端、两账号/额度/计量、10 ARM64 manifest 及清场，56 脱敏工件
  断网只读独验通过；`.tmp-native-arm64-host-20261117/`。原始私密输出未上传。
- CI 修复 `781b770e` 已推、run `44078479350` success；独立 `.44` 发布 run
  `44081637875` 全过含 ARM64 runtime，不替代 `.44` 宿主整轮，A/B 未升级。
- Dependabot 内置令牌同步 workflow 遭 403；修复后 42 例及 Actionlint 通过。
  待配 `DEPENDABOT_AUTOMATION_TOKEN` 后线上验证；PAT 事件已适配。
- jq、health/Peer 合并定向已验；旧计时/失败边界见 6A.62。
- 原生双机证据 `.tmp-native-control-vms-20261116/`；控制角色撤回及 A/B 恢复
  已清场，0 显式账号、各 19 条历史账目；`.7` 资产验签及双架构绑定通过。
- A/B 自然续期阈值：北京时间 2026-12-17 08:03:22，非 timer 时间；未到期未换证。

## 未决

- B 保留恢复部署及续期隔离；nftables 重载会清表，规则变化须核表和探针。
  实际续期、ARM64 其它组合/整机重启/Engine 自动安装、IPv6、
  其它核心及公网/多 Peer 新机恢复未验；ARM64 本轮 origin 仅本地 lo。
- 控制同步/启用态重启/密钥端口迁移仅补固定本地完整内核双机单 Peer；
  bind/TERM 恢复及预热后完整 Peer CLI 见证已补；其它信号/断电、
  公网多机、多 Peer 重启/灾备及长稳仍缺；`.8` 防护不外推生产/公网。
  保留全部校验/三次采样/即时 clean/30 秒窗口，无须重复相同 VM 验收。
  KVM 模块非持久加载，WSL 变化后须核对。
- 独立 SNI 仅同 IP/同证书别名正式整链，其它组合及旧缺陷失败见证未覆盖。
  A 无全球 IPv6，B 出口仅部分目标通过；本机 IPv6 nonce 命中 A/B=1/0，
  B 443 仅 IPv4；资源非峰值、预算未验。
- ICMP 原生启用态收发/arm64/公网/重启、IPv6/traceroute/PMTU 未验；
  TUN/透明启用重启按要求不做。SOCKS UDP、Xray 解析后阻断继续拒绝。
- WARP 实 Peer、自然换证、公网 h3/CDN 缺条件；gRPC Cloudflare 缺有效 Zone。
  旧 Vision reset/XHTTP/TUIC 超时根因未定；旧 sing-box→Xray 失败原件保持。
  固定公网组合不外推活动 sing-box；拒绝配对及带配对来源的跨核心复制。
- ML-DSA 仍限 amd64/IPv4/Reality/gRPC/chrome。

## 工作区注意

- 保留本地排除的 `.tmp-ci-timeout-actionlint.tar.gz`、`.tmp-reality-palette-preview*`、
  `.tmp-remote-xray-config.json`、`NUL` 及未跟踪身份取证 JSON；证据不改判、不覆盖。
