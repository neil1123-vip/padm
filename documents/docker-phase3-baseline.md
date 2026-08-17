# Docker 容器化阶段 3 基线

日期：2026-08-17

## 结论

阶段 3 已接通 Docker 版核心配置、Nginx/TLS、订阅控制和 DNS-01 ACME。
原生入口与 Docker 入口继续分离；Docker 模式只消费本仓库 CI 预构建的
`tag@sha256:digest` 镜像，不在生产机安装或编译上游程序。

本阶段支持协议 1（VLESS Reality，Xray 或 sing-box）和协议 21
（VLESS WebSocket/TLS，仅 Xray + Nginx）。其他协议在支持矩阵中明确标记为
`deferred`，配置时直接拒绝，不回退到原生安装路径。

## 控制接口

安装后的 `padm-docker` 新增以下命令：

```text
configure --spec <JSON 文件>
tls install --domain <域名> --cert <文件> --key <文件> [--ops-image <tag@digest>]
acme issue|renew --domain <域名> --email <邮箱> --dns <dns_*> --credentials <文件> [--ops-image <tag@digest>]
validate
```

`docker/contracts/configure.schema.json` 冻结请求格式，
`docker/contracts/features.json` 记录协议和功能状态。Reality 与 Nginx/TLS 示例分别为
`docker/configure.example.json` 和 `docker/configure-nginx.example.json`。

## 配置事务

`configure` 的提交顺序固定为：

```text
校验请求和支持矩阵
-> 检查宿主端口
-> 在候选目录生成核心、Nginx、订阅、Compose 和 deployment.json
-> 使用候选镜像校验核心、TLS、Nginx、订阅和 Compose
-> 备份当前配置
-> 切换候选配置
-> compose up --wait
```

候选校验失败不会修改在线配置；切换、权限设置、启动或健康检查失败时，控制脚本
停止候选部署并恢复旧快照。`deployment.json` 记录核心、协议、监听器、profiles、
镜像 digest 和前一 manifest，用作后续状态恢复的唯一部署身份。

TLS 安装先在 `padm-ops` 中检查证书格式、公私钥匹配和域名，再以临时文件切换。
已启用 Nginx 时，reload 或健康检查失败会恢复旧证书。ACME 只支持显式 DNS-01
provider；凭据和私钥必须是非符号链接的受限普通文件。

## 运行边界

- 核心、Nginx、订阅和 ACME 继续使用只读根、`cap_drop: ALL` 和
  `no-new-privileges`，不挂载 Docker Socket。
- 订阅由 `padm-ops` 内的 Python 标准库服务只读发布；token 只能包含安全字符，
  文件通过 `O_NOFOLLOW` 打开，访问日志不记录 token。
- Nginx 仅发布外部 TLS 端口；协议 21 的 Xray WebSocket 后端和订阅服务只在
  Compose 网络内可达。
- ACME 复用 `padm-ops`，不新增第 6 个镜像；阶段 4 的 `padm-net` 仍未启用。

## 固定版本核对

已按 `versions.lock` 对照固定上游版本：Xray `v26.3.27` 支持当前
`-test/-confdir` 与 Reality 字段；sing-box `v1.13.19` 支持 `run/check`、
`-c/-D`、Reality 字段和 `direct` outbound；acme.sh `3.1.4` 支持当前
DNS-01、renew 和 install-cert 参数。

## 验证结果

| 验证 | 结果 |
|---|---|
| 受影响 Shell 文件 `bash -n`、JSON `jq empty`、订阅服务自检 | 通过 |
| Reality 与 Nginx 两种生成 Compose 的真实 Docker CLI 静态解析 | 通过 |
| `docker-phase3` selector | 通过，176.660 秒 |
| `docker-phase2` selector | 通过，3.011 秒 |
| `docker-phase1` 专项回归 | 通过，170.239 秒 |
| 原生 `fast-full` | 通过，97.555 秒 |
| 原生 `all` | 通过，655.668 秒 |
| `git diff --check` | 通过 |
| 真实镜像 build/run、容器网络和双架构 smoke | Docker daemon 未运行，待阶段 5 CI |

## 后续边界

阶段 3 不接入 WireGuard、Fail2ban、TUN/TProxy，不实现 ACME webroot/standalone，
也不扩展其他协议。阶段 4 只处理必须与宿主内核、设备、防火墙和真实客户端地址交互
的能力；阶段 5 再落地镜像构建、签名、SBOM、provenance 和发布门禁。
