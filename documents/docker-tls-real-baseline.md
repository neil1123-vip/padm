# Docker TLS 真实镜像验收基线

日期：2026-10-06。对应菜单对齐计划 3B.4 的部分验收，不代表整个 3B 已完成。

## 环境与输入

- Docker Desktop 的 rootful Linux daemon：Docker 29.8.2、amd64、
  内核 `6.6.87.2-microsoft-standard-WSL2`；验收驱动使用 Compose 5.5.1。
- 本轮最终五路脚本在 amd64 原生容器与 arm64 仿真容器均通过；
  每次从实际 HTTPS 订阅生成 WS/Reality 客户端，再检查流量和恢复。
  脚本拒绝四个输入混用架构，分别输出 daemon 与镜像架构；仿真不算原生主机证据。
- 四个业务镜像按本仓库 Dockerfile、Bake 与现有 `versions.lock` 构建，
  无依赖锁变更；这不是已验签的正式发布。
- 驱动运行真实 Docker/Compose、实际 bundle、配置生成器、统计准备和 TLS 事务，
  不替换 Docker，也不伪造重建或健康检查成功。
- 测试 CA 包含 CA 约束和 `keyCertSign/cRLSign`，签发三张不同 serial 的同域证书；
  三条普通 TLS/WS 客户端、Python 证书序列号及 HTTPS 订阅探测均正常校验 CA 与域名，
  不使用跳过证书校验的连接。

| 镜像 | 本轮实际引用 |
| --- | --- |
| Xray | `padm-local/padm-xray:tls-3b4@sha256:edb005cb17f2961596b42cd2266a87ef5adcd3c6601cf529b6a088ac5f37dacd` |
| sing-box | `padm-local/padm-sing-box:tls-3b4@sha256:5fdff482ad9c65aa0e583a20e27d5f322b2539e673432e2cf78c7f460028fcb3` |
| Nginx | `padm-local/padm-nginx:tls-3b4@sha256:26a968bf692d1ccaf46e400e967ecc223534672eb8bfdb764c9751f7ec98ac9d` |
| ops | `padm-local/padm-ops:tls-3b4@sha256:ca6bf4a8b7936718eb9d3633fb8580e6e50de388c93275394f5c3768bb2587f6` |

| arm64 镜像 | 仿真验收实际引用 |
| --- | --- |
| Xray | `padm-local/padm-xray:tls-subscription-3b4-arm64@sha256:3686b2673cb4044703d1200d3b092d8f1a8cb09b2a4fe26cac27170334bf5abb` |
| sing-box | `padm-local/padm-sing-box:tls-subscription-3b4-arm64@sha256:74d011dc6c4c069f17541dea2d040ec2e927bcfc9f8c544b4577c771a663badf` |
| Nginx | `padm-local/padm-nginx:tls-subscription-3b4-arm64@sha256:0edeb8a665801e29b6b9e15a8f90eaaf15d94b9e4b0107bc2192427732a2a371` |
| ops | `padm-local/padm-ops:tls-subscription-3b4-arm64@sha256:09004c24b0a0c8e4fb24e9a3059d2a9586e86814a909e843d9f7080b61a0ad96` |

## 复现

在无现有 `padm-docker` 容器或同名网络的独立 rootful Linux 主机上运行。
四个镜像必须已存在，参数必须为实际的 `tag@digest`，不能使用示例 digest。
宿主需要已有安装前置工具及 `openssl`、`python3`、`nsenter`，
并提供支持 HTTP/2 的 `curl`，两核心可访问 Reality 目标 `www.debian.org:443`；
当前生产支持范围仍不包含 Windows/Docker Desktop。

```bash
sudo bash docker/tests/tls-real.sh \
  "${XRAY_IMAGE}" "${SINGBOX_IMAGE}" "${NGINX_IMAGE}" "${OPS_IMAGE}"
```

本轮在 Windows 通过独立 Linux 驱动运行：源码只读绑定到 `/work`，
使用带 `io.padm.test=tls-subscription-3b4` 标签的独立测试卷；卷挂载在与 daemon 相同的
Linux 绝对路径，`HOME` 和 `TMPDIR` 指向卷，保证业务 bind source 可见。
驱动用 `--init`、`--pid=host`、`SYS_ADMIN`、`SYS_PTRACE` 和 Docker Socket
执行宿主 `nsenter`；这些仅属测试驱动，不进入任何业务服务的 Compose 合同。
原生 Linux 主机直接运行上述脚本，不需要驱动容器。

脚本使用私有临时状态根，不写宿主 `/etc/padm-docker` 或 `/etc/padm`。
容器/网络查询失败直接退出；结束时清理本次容器、网络和临时目录，
若 Compose 清理失败则保留目录并输出恢复路径，不丢失再次清理所需配置。
成功输出 `docker-tls-real-ok`，并要求脚本退出码为 `0`。

## 已通过的断言

- 双核心、Nginx、订阅服务、客户端和 HTTP origin 均运行真实镜像；
  原有三路 TLS/WS 断言在 amd64 与 arm64 仿真分别通过，均退出 `0`。
- Xray 和 sing-box 的核心 TLS 夹具，以及 Xray VLESS WS TLS，
  三条 SOCKS 路径均取得真实 HTTP 内容。
- Xray 与 sing-box 的 Reality Vision 入口使用正式生成器，
  SOCKS `2084/2085` 的公开密钥、short ID、UUID、SNI 和 flow 来自实际 HTTPS 订阅，
  经公网 Debian 目标完成 Reality 握手并取得私有 origin 的真实 HTTP 内容。
  无直连旁路或握手失败重试，任一路失败则整个脚本失败。
- HTTPS 订阅返回 WS 和两核 Reality 链接；标准库解析实际返回内容，
  逐项对比公开 spec 的协议、服务器、端口、UUID、TLS/WS、Reality 和传输参数，
  拒绝缺失/重复入口、未知/重复查询字段。客户端参数只取自 URI；
  spec 只作断言和隔离端点映射，不提供客户端凭据的旁路。
- 每次生成 `0640 root:10001` 客户端候选，用真实 sing-box `check` 校验成功后
  才替换配置并重建客户端。错误协议、额外密码、空值重复 SNI、空值未知参数
  四个反例必须被同一解析函数拒绝；真实订阅异常不在反例的异常捕获范围内。
- 证书 serial `01` 成功轮换为 `02`，三个 TLS 消费者都持有新证书，
  两架构五路客户端流量和订阅仍可用。
- serial `03` 仅通过修改独立 `health.check` 注入 sing-box 健康故障；
  注入 marker 与实际 Compose `is unhealthy` 错误同时断言，避免提前失败假通过。
  失败后所有消费者恢复 `02`，客户端及订阅重新通过。
- 对实际事务进程 `BASHPID` 发送 TERM，等待退出码 `143`；
  恢复 `02` 后重新检查客户端流量，累计流量不回退，候选与部署锁无残留。
- 内部 Trojan TLS 只用于测试已有 TLS 底座，不开放协议 `28` 或其它菜单协议。

本轮最终脚本在 amd64 / arm64 仿真均退出 `0`，耗时 `72.719 / 95.714` 秒；
首装 `01`、成功轮换 `02`、真实健康故障恢复 `02`、TERM/`143` 恢复 `02`
四次均重新从 HTTPS 订阅生成客户端并输出五路 probe 成功。
Bash 语法、ShellCheck 0.11.0 warning/error 和 `git diff --check` 通过；
全级 ShellCheck 仍有两处原有 SC2015 信息提示，不宣称全级零提示。

arm64 首轮暴露客户端 started 但还未监听的竞态，五路均连接拒绝；
最终脚本在实际客户端网络命名空间内等待五个 TCP 端口，共享 10 秒截止时间。
只有监听就绪才进行各路一次 HTTP/Reality 检查，超时直接失败，不重试协议握手。
四个临时 arm64 镜像复用原 Bake/锁和缓存构建，未修改构建合同或依赖锁；
它们、驱动、测试卷、容器和临时文件验收后精确清理，旧 amd64 业务镜像保留。

原夹具目标 `www.microsoft.com:443` 的直连 TLS 1.3/h2/证书校验通过，
sing-box Reality 也取得 HTTP 内容，但 Xray Reality 连续两次返回 EOF。
临时握手日志显示密钥、时间和 short ID 认证成功、目标握手未完成；
未确认更深原因，不归因于生产生成器，也不据此宣称 Microsoft 目标兼容。
最终脚本固定使用 Debian 目标，不在失败后自动替换目标；临时 debug 已撤除。

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

## 真实调度器

`docker/tests/renewal-real.sh` 仅允许明确设置 `PADM_RENEWAL_REAL_ISOLATED=1` 的
一次性 root 容器。它直接调用生产的续期登记校验与调度安装/撤销逻辑，
不替换 `systemctl`、`crontab` 或 `pgrep`；受管 CLI 路径放置标明用途的
probe，只记录参数、root、UID 和 PID 1 的启动时刻，不执行 ACME 或业务 Docker。

实际工具环境：Debian 12、systemd `252.39-1~deb12u2`、cron `3.0pl1-162`、
Bash `5.2.15`、jq `1.6`，Docker 29.8.2 的独立 cgroup2 容器。
五阶段最终通过，依次耗时 `4.191 / 0.115 / 26.061 / 59.266 / 3.336` 秒：
systemd 首装、systemd 重启、迁移到 cron、cron 重启、迁回 systemd。
每次重启要求 PID 1 的 starttime 改变，且基线之后的新 probe 事件携带当前
PID 1 标识，不能由旧进程的累计次数满足。

覆盖两域共用唯一任务、重复安装、逐域停用/恢复、真实 daemon 执行、
原样每日 `03:17`/`Persistent`/参数/环境与 root `0644` unit，
以及同名外部 unit、异 root 续期 cron 拒绝和无关 cron 保留。
隔离夹具先验证每日配置，再用临时 timer drop-in 或只替换 cron 的五个时间列
加速触发；执行路径与参数仍由生产模块生成，最后恢复每日配置并撤销受管任务。
语法、ShellCheck 0.11.0 全级、无隔离标记/未知阶段/初始 crontab 查询失败负例通过。
查询失败负例在创建夹具前退出。

复现需独立工具镜像，以下 Dockerfile 仅用于一次性验收：

```dockerfile
FROM rust:1.85-bookworm@sha256:e51d0265072d2d9d5d320f6a44dde6b9ef13653b035098febd68cce8fa7c0bc4
RUN apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends systemd-sysv cron dbus jq && \
    systemctl enable cron.service && apt-get clean && rm -rf /var/lib/apt/lists/*
ENV container=docker
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT ["/sbin/init"]
```

在独立测试 daemon 上构建为 `padm-local/renewal-real-driver:3b4`。
`REPO` 是仓库的绝对路径；每次启动 systemd 后，等待
`docker exec <容器> systemctl show-environment` 成功再执行相应阶段。
Docker 可写层保留测试状态，重启仍用同一容器；切换后端通过停止后 snapshot，
不拷贝宿主 unit、crontab 或业务目录：

```bash
docker run -d --pull=never --name padm-renewal-real-systemd --privileged --cgroupns=private \
  --tmpfs /run --tmpfs /run/lock --tmpfs /tmp \
  --mount "type=bind,source=${REPO},target=/work,readonly" padm-local/renewal-real-driver:3b4
docker exec -e PADM_RENEWAL_REAL_ISOLATED=1 padm-renewal-real-systemd bash /work/docker/tests/renewal-real.sh systemd-init
docker restart --timeout 1 padm-renewal-real-systemd
docker exec -e PADM_RENEWAL_REAL_ISOLATED=1 padm-renewal-real-systemd bash /work/docker/tests/renewal-real.sh systemd-resume
docker stop --timeout 1 padm-renewal-real-systemd
docker commit padm-renewal-real-systemd padm-local/renewal-real-state:systemd
docker run -d --pull=never --name padm-renewal-real-cron \
  --tmpfs /run --tmpfs /run/lock --tmpfs /tmp \
  --mount "type=bind,source=${REPO},target=/work,readonly" \
  --entrypoint /usr/sbin/cron padm-local/renewal-real-state:systemd -f
docker exec -e PADM_RENEWAL_REAL_ISOLATED=1 padm-renewal-real-cron bash /work/docker/tests/renewal-real.sh cron-migrate
docker restart --timeout 1 padm-renewal-real-cron
docker exec -e PADM_RENEWAL_REAL_ISOLATED=1 padm-renewal-real-cron bash /work/docker/tests/renewal-real.sh cron-resume
docker stop --timeout 1 padm-renewal-real-cron
docker commit padm-renewal-real-cron padm-local/renewal-real-state:cron
docker run -d --pull=never --name padm-renewal-real-systemd-return --privileged --cgroupns=private \
  --tmpfs /run --tmpfs /run/lock --tmpfs /tmp \
  --mount "type=bind,source=${REPO},target=/work,readonly" \
  --entrypoint /sbin/init padm-local/renewal-real-state:cron
docker exec -e PADM_RENEWAL_REAL_ISOLATED=1 padm-renewal-real-systemd-return bash /work/docker/tests/renewal-real.sh systemd-migrate
```

上述权限仅让测试容器运行自身 systemd/cgroup；源码是唯一只读 bind，
没有 Docker Socket、宿主 `/etc` 或新卷。三个容器、驱动和两个 snapshot 镜像
验收后按确切名称清理，不执行全局 prune。此证据证明真实调度器及容器重启，
不证明真实 DNS 续期、完整 `padm-docker` 调用链或宿主整机重启。

## 尚未验收

真实 DNS 服务商的 DNS-01 申请/续期、完整宿主 systemd/cron 重启、
原生 Linux/SSH 安装生命周期、原生 arm64 业务路径，以及可信签名发布仍待补证据。
隔离容器内的真实调度器执行、双向迁移和容器重启证据见上节，不等同整机重启。
已验证的是测试解析器从真实 HTTPS 订阅导入 sing-box；Reality 的服务地址及 WS
公开端口映射到同一入口的隔离网络端点，不测试公网入口、SSH 或第三方客户端导入 UI。
原生 arm64、其它客户端实现和其它 Reality 目标兼容性未验，仿真五路证据不能代替。
Nginx `-t`/reload 仍输出默认日志路径的 `Permission denied` 提示；
命令、健康检查与实际 TLS/流量通过，该提示未被隐藏，不能据此宣称无运行告警。
arm64 仿真还会显示平台不匹配和 `io_setup() ... Function not implemented`，
不能以已通过的网络行为推断原生内核兼容性。
3B.4 保持进行中，协议支持及 `management_status` 不因本次验收升级。
