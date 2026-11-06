# Agent State

> 当前快照；详细证据见 Git、实施计划及 `.tmp-*`。

## 当前

- 整体未收口；16 个协议管理 supported、14 个 deferred，矩阵未变。
- VPS Debian 13 amd64/bridge/IPv4，正式 `3.43.2`/source `d8bac249`；
  Xray/WS 443、三业务 healthy、无 OOM、透明关闭、两个 timer active/enabled。
- 正式 `3.43.4` 已发布；固定 ML-DSA CLI 隔离整链通过，已清场，生产未变。
- 范围为 amd64/IPv4/Reality/gRPC/chrome/pgxn.org；未做本轮现网升级。

## 最近完成

- `.2`/`3.43.2` 发布、升级及固定公网 Reality 通过，真实恢复点保持；
  证据 `.tmp-release-revision2-20261105/`、`.tmp-reality-public-revision2-20261105/`。
- 独立 sing-box `3.43.3` 固定 amd64/IPv4/Reality/gRPC/chrome：
  CLI 分享、两正控 TLS/200、三服务端拒绝及双向统计独验通过，5 项篡改拒绝；
  超时/false 原件保留；已清场、25444 关闭，现网 48 项及 19 条累计保持。
  证据 `.tmp-singbox-server-public-20261106/`；历史 Docker 停启触发者未知。
- 独立 SNI/长公钥正则修复已签名提交 `461bfa43` 并推送；定向
  `docker-reality-parameters -Jobs 2` 通过，203353 ms/exit0；真 Alpine 格式自检通过。
- `3.43.4`/`51d5f658`：run `42260071838` 30 success/1 skipped、18 合同分片通过；
  三资产、精确 Cosign 身份、306 源码及五镜像双架构绑定独验通过。
  五镜像复用 `3.43.3`，未新增构建/smoke；证据 `.tmp-release-3434-20261107/`。
- 首轮正式 `3.43.4` 已启用 ML-DSA 并建立业务 TLS，但临时 HTTP 变量遮蔽导致失败；
  execution1/cleanup0，原件 `.tmp-mldsa-cli-3434-20261107/` 保留。
- 第二轮只修临时客户端并补 HTTP 200/503 断网自检；7 份输入摘要远端通过。
  正式验签、安装、configure、自动生成配对、完整 CLI 分享及重建通过，150309 ms。
  两正控严格 TLS 1.3/HTTP 200/15863 字节；错 pqv 和错 UUID 均非超时拒绝。
  pqv 为受控 X.509 拒绝，非直接 ML-DSA 错误；四阶段服务端身份/规格不变。
  execution0/cleanup0、生产快照一致；最终只读确认健康、timer 及临时对象清场。
  独立终审通过；证据 `.tmp-mldsa-cli-3434-r2-20261107/README.md`。

## 未决

- 公网 ML-DSA、独立 SNI 整链及其它组合仍未证明；现网升级和公网验收另需授权。
  11-06 前两轮及 11-07 正则失败见 `.tmp-mldsa-cli-public-20261106/`、
  `.tmp-mldsa-targets-20261107/`；空后快照/cleanup1、非法 IP 草案不改判。
  本机出口按 SNI 改路由；VPS 无全局 IPv6/默认路由。资源采样非峰值，预算未验。
- WS 旧公网端口 TCP 拒绝及原生 IPv6 未证明；固定 CONNECT 只证 TLS EOF。
- ICMP 原生启用态收发/arm64/公网/重启、IPv6/traceroute/PMTU 未验；
  TUN/透明启用重启按要求不做。SOCKS UDP、Xray 解析后阻断继续拒绝。
- 原生 arm64、双栈、新主机灾备、多机控制/WG、WARP 实账号及约 2026-12-17
  自然 ACME 续期缺条件；公网 h3/CDN、其它客户端/算法和性能长稳未扩范围。
  gRPC Cloudflare 透传缺有效 Zone 授权，不重跑无变化矩阵。
- 旧 Vision reset、XHTTP/TUIC 超时缺原材料；旧 sing-box→Xray 失败原件
  `d18652f4...` 保留。固定公网组合不外推其它组合或活动 sing-box 业务。
  sing-box 拒绝配对及带配对来源的跨核心复制。
- 本轮未跑 full；ML-DSA 结论不外推公网、arm64/IPv6、其它核心/指纹或长稳。

## 工作区注意

- 保留本地排除的 `.tmp-ci-timeout-actionlint.tar.gz`、`.tmp-reality-palette-preview*`、
  `.tmp-remote-xray-config.json`、`NUL`；证据不改判、不覆盖。
