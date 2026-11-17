# Distroless 镜像验收记录

日期：2026-11-17。范围：五个运行镜像迁移及两轮体积优化，本机为 `linux/amd64`。

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

复验入口（需先构建五个 `padm-distroless/padm-<名称>:local` 候选）：

```powershell
.\shell\regression\run-docker.ps1 -Selector docker-phase2 -Jobs 2
.\shell\regression\run-docker.ps1 -Selector docker-phase5 -Jobs 2
.\shell\regression\run-docker.ps1 -Selector docker-distroless-real -Jobs 2
.\shell\regression\test-run-docker.ps1 -Scope distroless
```

未验证 ARM64 构建及运行、生产部署、自然续期、压力与长期稳定性；
控制 HTTP 冒烟不证明 WireGuard 握手，Fail2ban 复用夹具保留 Docker 默认
capabilities。未运行 full 或完整漏洞扫描。Python 上游标签发现限第一页
100 条，未来标签增长可能导致漏更。
