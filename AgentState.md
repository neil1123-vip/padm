# Agent State

> 当前快照；详细证据见 Git、验收记录及 `.tmp-*`。

## 当前

- 整体计划未完成；透明代理保持关闭，不以阶段通过替代整体完成。
- VPS：Debian 13 amd64、bridge、公网 IPv4、正式 `3.42.3`；
  bundle=`36efda04`，三业务 healthy、严格公网 TLS/200、续期 timer active。
- 本机 Docker Linux 可用，复用工具镜像，未跑 full。
- 原生账号 8 阶段及恢复整轮通过，508821 ms/exit 0；
  26 正/5 拒绝、断网独验及 13 项篡改拒绝通过，已恢复清场。
- 4A.4 业务备份/preview/merge/replace、真实健康失败回滚与分享授权恢复
  7 阶段通过，616534 ms/exit 0；断网独验及 10 项篡改拒绝通过并清场。

## 最近完成

- 3.42.3 发布 run 40406148426：30 成功/1 条件跳过，三件套验签、
  300 个源码核对通过；正式升级保持材料权限、timer、boot 和累计。
- 业务轮 22 正/8 拒绝、23 次严格 HTTPS 订阅下载、7 个 fresh nonce，
  核 66 份正式命令、24 个资源采样；merge 保额外对象、replace 撤销，
  旧身份/token 恢复及轮换身份撤销通过，较新 2 GiB 额度/累计保持。
  原 spec raw、材料权限、timer 和历史账恢复，临时账号/分享均删除；
  新旧两轮远端暂存及四容器已清，最终公网 TLS/200（782 ms）。
  `.tmp-native-business-close-20261027/verification.json`；
  完整归档 `7476fd85f1dbaf8e0e42a66ae09accdd8b25a350bf42a67773c92b413dde2d52`。
- 首轮临时脚本误判 Docker 小写 no such，打断回滚；失败/候选原件保留，
  独立正式 up/基线恢复与断网恢复独验通过。新轮兼容大小写、保证 finally
  回收子进程并处理终止信号；不把旧失败改写成功。
  `.tmp-native-business-20261027/failure-verification.json`。
- 账号额度、解除、轮换及删除通过，32 命令/30 采样/8 nonce；
  已恢复清场，旧 quota rc1 原件不改写。
  `.tmp-native-account-close-20261027/verification.json`；
- 额度候选改独立 0750 子目录/config.json，0640 与组归属保持；
  正式固定 Xray 非 root 断网五项实测通过，避免健康扫描提前合并候选。
  docker-traffic 5014 ms，daily 207118 ms/34 项，均非缓存；
  旧失败 `.tmp-native-account-workflow-20261027/failure-verification.json`。
- SSH 双轮封禁/解封/来源清退、WS 端口事务及 TUN 关闭态诊断已独验清场；
  详见原生验收记录。复用 3.42.0 重启，本轮 3.42.3 未新重启。

## 未决

- WS 公网旧端口 TCP 拒绝、原生 IPv6 未证明；固定 CONNECT 只证 TLS EOF。
- ICMP 原生启用态收发/arm64/公网/重启、IPv6/traceroute/PMTU；
  真实 TUN 必须启用宿主透明接管，受透明保持关闭约束。
- 原生 arm64、IPv6/双栈、新主机灾备、多机控制/WG、WARP 实账号、
  约 2026-12-17 自然 ACME 续期缺条件；VPS 无全局 IPv6/默认路由。
- 公网 h3/CDN、其它客户端/算法、性能长稳未扩范围；gRPC Cloudflare
  透传缺有效 Zone 授权，不重跑无变化矩阵。
- 透明启用重启按要求不做；SOCKS UDP、Xray 解析后阻断继续拒绝。
- 旧 Vision reset、XHTTP TLS 超时、TUIC 超时缺原现场材料，根因未定。

## 工作区注意

- 保留既有未跟踪 `.tmp-ci-timeout-actionlint.tar.gz`、
  `.tmp-reality-palette-preview*`、`.tmp-remote-xray-config.json`、`NUL`。
