# Distroless 镜像验收记录

日期：2026-11-17。范围：五个运行镜像迁移及两轮体积优化，本机为 `linux/amd64`，
正式发布覆盖原生双架构构建、冒烟及 ARM64 真实运行。

## 实现

- 运行层统一使用固定 digest 的 Debian 13 `distroless/static`。
  按需导出 ELF 依赖，缺库拒绝构建；Debian 软件来自固定快照并由 apt 验签。
- 保留 CA、时区、NSS、BusyBox 诊断 shell、运行文件清单和对应 Debian
  包的版本、架构及许可证。无 apt/apk/pip 入口；清单不代表完整 SBOM。
- ops 使用官方 Python 3.14.10，net 使用 Debian Python 3.13 保持 Fail2ban ABI。
  保留常规标准库，排除测试扩展及 pyc；ops/net 使用 dash 避免内置命令绕过 PATH。
- Cronet 仅去除非必要符号，保留原资产校验和安装后摘要，并以 Naive TLS 验证。
  ACME 保留脚本、全部 DNS/deploy/notify 插件和许可证。
- Xray 保留完整 Geo 数据；目录为 0755、文件为 0644，非 root 运行时真实加载。
- Nginx 静态编入 stream，默认配置及宿主网站分流生成器均移除旧动态模块加载。
- 保留运行 UID、健康检查、只读根目录及停止信号。
  共享 runtime 输入变化使五镜像的发布复用失效；兼容旧客户端的清单仍为五键，
  其中 `upstream.alpine` 为 `none`。
- Bake 和 CI 的 image/docker 输出均显式使用 gzip 9。
  已有压缩缓存层不承诺重新压缩；未变化镜像仍可保持原摘要。

## 体积

MB = 1,000,000 字节。Docker 本机计数使用 `image inspect .Size`；
压缩层按导出 OCI manifest 逐层求和，并核对 blob 长度和 gzip 格式，
不含 manifest、config 及传输开销。

| 镜像 | 本机计数 MB | 压缩层 MB | 候选镜像 ID 前 12 位 |
| --- | ---: | ---: | --- |
| Xray | 73.06 | 18.97 | `8c02c9f8e440` |
| sing-box | 135.30 | 35.11 | `c7092d340b34` |
| Nginx | 28.92 | 7.41 | `a71142a3e3c3` |
| ops | 90.05 | 22.68 | `dce80f646e9c` |
| net | 79.54 | 19.83 | `5bf4a9bff10b` |

与首次优化前的同版本候选相比，本机计数合计由 513,021,537 B 降到
406,871,625 B，减少 20.69%。第二轮压缩层合计由 104,262,998 B 降到
104,009,840 B。合计没有扣除共享层，不代表去重磁盘占用或增量下载量。
Xray 的程序及完整 Geo 内容未裁剪，第二轮收益来自层合并和输出压缩。

## 验证

已有日常 34 项 `docker-contracts` 通过；最终体积候选另通过 `docker-phase2`、
`docker-phase5`、`docker-distroless-real` 和回归入口权限隔离检查。
真实运行覆盖 SOCKS、非 root Geo、Naive/Cronet TLS、Nginx HTTP/stream、
ACME/TLS/GNU date、订阅及控制 HTTP API、NSS/DNS/ctypes/时区、
Fail2ban、iptables/nftables/WireGuard 接口及正常停止。

提交前审计修复宿主 stream 配置的旧模块路径，并补实际生成配置的 `nginx -t`。
Fail2ban 复用测试挂载源码入口前，先断言候选入口 SHA-256 与当前源码一致。
补验 `docker-distroless-real -Jobs 2` 通过，实际耗时 69.150 秒、无结果复用；
本机证据位于 `.tmp-regression-docker-d8364bd8b884411aa7eb134cf1d63e26/`。
该夹具验证 owner/action、封禁及清理，不代表 SSH 日志采集整链。

发布流程增加原生 ARM64 的同一真实运行门禁：下载本轮 smoke 的固定摘要，
混合旧版复用引用后逐个核对架构，以精确镜像 ID 离线送入隔离 daemon。
未挂宿主 Socket、未开放公网；失败、取消或有新构建却跳过均阻止镜像发布。
本机包装回归覆盖混合复用、错架构、缺摘要、启动失败、非零退出和清场，
最终 `docker-phase5 -Jobs 2` 10.953 秒通过；两份工作流的 actionlint 通过。
证据 `.tmp-regression-docker-25a48451ff7945f89732c4876a0838f7/`。
原生 ARM64 实际结果及边界见下述正式发布核验。

远端 `44053903394` 暴露 sing-box 候选覆盖整个 fetch 阶段后缺少
`/out/rootfs` 的双架构构建错误。现将下载包阶段独立为 package，候选仅覆盖包；
正式依赖安装、strip、许可证和 rootfs 导出仍共用 fetch，原失败保持。
基线 `df5656be` 的本机 full 实际 67 项全部通过，845.194 秒、无结果复用，
证据 `.tmp-regression-docker-6839b5299e6e4bb38b8278098cbac270/`；
之后两处发布修复由上述最终 phase5 验证，不重复全量。

Release `44055641704` 的 18 个合同分片及 10 个原生 smoke 全通过，
但 ARM64 的离线导入后找不到原 config ID，真实运行尚未开始，发布被阻止；
该失败轮的自动版本提交 `fe5233f9` 只准备了 `3.43.8`，当时未正式发布。
固定 amd64/jq 的真实对照证实 classic 与 containerd 的 ID 表示不同，
仅给导出镜像补标签仍不足。现让内层匹配宿主的 overlay2/overlayfs，
未知驱动拒绝，使用命名导出并保留导入后的原 ID 精确比较。
同类型存储的两组 ID 及运行检查通过；三容器、三匿名卷和临时标签已清场。
证据 `.tmp-docker-load-repro-20261117/summary.json`，不替代远端 ARM64 验收。
最终 `docker-phase5 -Jobs 2` 的 9 个包装场景及既有检查通过，13.359 秒；
证据 `.tmp-regression-docker-69525f2938764caabd33e7df8f508440/`，actionlint 通过。

Release `44062180595` 于北京时间 2026-11-17 18:27:41 正式发布 `v3.43.8`，
来源及标签均为 `6e880813a92c6518678ec518d292d585c2cb775d`，复用已准备版本。
41 个任务全部成功、无跳过：18 个合同分片、10 个原生 build/smoke、
ARM64 真实运行及五镜像发布均通过。ARM64 真实运行耗时 74.240 秒，
工件及实际 job 日志中的 15 个成功标记一致；原镜像 ID 校验保持。

发布后独验确认三资产的 SHA-256 和长度、313 个源码文件的 Git blob、
完整 payload 路径集合及生成的 `bundle.paths` 字节一致；清单经固定 Cosign
工具独立验签，成功记录绑定本轮 run、源码及清单/签名包/日志摘要。
五镜像均本轮新建，实时 GHCR 索引及版本标签与 CI 原件一致；双平台摘要、
smoke 构建索引、ARM64 config ID 和真实运行 ID 完整绑定，保留 attestation。
五镜像验签依据本次 CI 声明和成功日志，未另作本机独立镜像验签。
核验器的 2 正例/7 反例自检及 7 个实际证据反例通过，成功报告未被替换。
证据 `.tmp-runtime-release-20261117/application-verification.json` 及同目录
`negative-verification.json`；旧失败原件保持，A/B VPS 未升级或重启。

复验入口（需先构建五个 `padm-distroless/padm-<名称>:local` 候选）：

```powershell
.\shell\regression\run-docker.ps1 -Selector docker-phase2 -Jobs 2
.\shell\regression\run-docker.ps1 -Selector docker-phase5 -Jobs 2
.\shell\regression\run-docker.ps1 -Selector docker-distroless-real -Jobs 2
.\shell\regression\test-run-docker.ps1 -Scope distroless
```

原生 ARM64 CI 构建及运行已验；ARM64 宿主生命周期、生产部署、
自然续期、压力与长期稳定性未验，16 supported / 14 deferred 保持；
控制 HTTP 冒烟不证明 WireGuard 握手，Fail2ban 复用夹具保留 Docker 默认
capabilities。未运行完整漏洞扫描。Python 上游标签发现限第一页
100 条，未来标签增长可能导致漏更。
