# Docker TLS 真实镜像验收基线

日期：2026-10-06。对应菜单对齐计划 3B.4 的部分验收，不代表整个 3B 已完成。

## 环境与输入

- Docker Desktop 的 rootful Linux daemon：Docker 29.8.2、amd64、
  内核 `6.6.87.2-microsoft-standard-WSL2`；验收驱动使用 Compose 5.5.1。
- 四个业务镜像按本仓库 Dockerfile、Bake 与现有 `versions.lock` 构建，
  无依赖锁变更；这不是已验签的正式发布。
- 驱动运行真实 Docker/Compose、实际 bundle、配置生成器、统计准备和 TLS 事务，
  不替换 Docker，也不伪造重建或健康检查成功。
- 测试 CA 签发三张不同 serial 的同域证书；三个 sing-box 客户端出站
  使用该 CA 正常校验 TLS。证书序列号和订阅内容探测另用不校验 CA 的 Python 连接，
  不能将其单独作为证书信任证据。

| 镜像 | 本轮实际引用 |
| --- | --- |
| Xray | `padm-local/padm-xray:tls-3b4@sha256:edb005cb17f2961596b42cd2266a87ef5adcd3c6601cf529b6a088ac5f37dacd` |
| sing-box | `padm-local/padm-sing-box:tls-3b4@sha256:5fdff482ad9c65aa0e583a20e27d5f322b2539e673432e2cf78c7f460028fcb3` |
| Nginx | `padm-local/padm-nginx:tls-3b4@sha256:26a968bf692d1ccaf46e400e967ecc223534672eb8bfdb764c9751f7ec98ac9d` |
| ops | `padm-local/padm-ops:tls-3b4@sha256:ca6bf4a8b7936718eb9d3633fb8580e6e50de388c93275394f5c3768bb2587f6` |

## 复现

在无现有 `padm-docker` 容器或同名网络的独立 rootful Linux 主机上运行。
四个镜像必须已存在，参数必须为实际的 `tag@digest`，不能使用示例 digest。
宿主需要已有安装前置工具及 `openssl`、`python3`、`nsenter`，
并提供支持 HTTP/2 的 `curl`；当前生产支持范围仍不包含 Windows/Docker Desktop。

```bash
sudo bash docker/tests/tls-real.sh \
  "${XRAY_IMAGE}" "${SINGBOX_IMAGE}" "${NGINX_IMAGE}" "${OPS_IMAGE}"
```

本轮在 Windows 通过独立 Linux 驱动运行：源码只读绑定到 `/work`，
使用带 `io.padm.test=tls-3b4` 标签的独立测试卷；卷挂载在与 daemon 相同的
Linux 绝对路径，`HOME` 和 `TMPDIR` 指向卷，保证业务 bind source 可见。
驱动用 `--init`、`--pid=host`、`SYS_ADMIN`、`SYS_PTRACE` 和 Docker Socket
执行宿主 `nsenter`；这些仅属测试驱动，不进入任何业务服务的 Compose 合同。
原生 Linux 主机直接运行上述脚本，不需要驱动容器。

脚本使用私有临时状态根，不写宿主 `/etc/padm-docker` 或 `/etc/padm`。
容器/网络查询失败直接退出；结束时清理本次容器、网络和临时目录，
若 Compose 清理失败则保留目录并输出恢复路径，不丢失再次清理所需配置。
成功输出 `docker-tls-real-ok`，并要求脚本退出码为 `0`。

## 已通过的断言

- 双核心、Nginx、订阅服务、客户端和 HTTP origin 均运行真实镜像。
- Xray 和 sing-box 的核心 TLS 夹具，以及 Xray VLESS WS TLS，
  三条 SOCKS 路径均取得真实 HTTP 内容；订阅 HTTPS 返回 WS 与 Reality 链接。
- 证书 serial `01` 成功轮换为 `02`，三个 TLS 消费者都持有新证书，
  三路客户端流量和订阅仍可用。
- serial `03` 仅通过修改独立 `health.check` 注入 sing-box 健康故障；
  注入 marker 与实际 Compose `is unhealthy` 错误同时断言，避免提前失败假通过。
  失败后所有消费者恢复 `02`，客户端及订阅重新通过。
- 对实际事务进程 `BASHPID` 发送 TERM，等待退出码 `143`；
  恢复 `02` 后重新检查三路流量，累计流量不回退，候选与部署锁无残留。
- 内部 Trojan TLS 只用于测试已有 TLS 底座，不开放协议 `28` 或其它菜单协议。

真实测试暴露了 Compose 读取 stdin、吞掉 `while read` 中后续消费者的问题。
共享 `dockerComposeRun` 的管理调用统一使用 `</dev/null`；现有调用均无需交互输入。
`phase6.sh` 的最小反例主动读取 stdin，要求 Xray/sing-box 两项均处理；
删除修复时该检查失败。

同一 Linux 工具环境中，TLS/续期顺序回归耗时 61 秒，
复用既有并行框架的 `docker-tls-focused` 耗时 37 秒，减少约 39%，范围未缩减。
Docker CI 与 Release 均改用该门禁；更新/回滚 `phase6` 38 秒，
发布合同 `phase5` 12 秒，Bash、ShellCheck error 与 actionlint 1.7.12 均通过。
Windows 文件复制到 phase5 的 Linux 临时副本时仅将版本锁 CRLF 转为 LF，
仓库中的锁文件未改。原始日志和本轮测试资源验收后清理，证据由本文件和脚本保留。

## 尚未验收

真实 DNS 服务商的 DNS-01 申请/续期、宿主 systemd/cron 重启与双向迁移、
原生 Linux/SSH 安装生命周期、arm64 业务路径，以及可信签名发布仍待补证据。
Reality 链接在订阅中检查，但此脚本不验证 Reality 客户端连接。
Nginx `-t`/reload 仍输出默认日志路径的 `Permission denied` 提示；
命令、健康检查与实际 TLS/流量通过，该提示未被隐藏，不能据此宣称无运行告警。
3B.4 保持进行中，协议支持及 `management_status` 不因本次验收升级。
