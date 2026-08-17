# Docker 容器化阶段 1 基线

## 基线身份

- 日期：2026-08-17。
- 基准提交：`c27451dbe52e7a64c31d0bf8de359cf6743feca3`。
- 工作树：阶段 1 完成候选，尚未提交；未进入镜像、Compose 或 CI 发布实现。
- 环境：Windows 11 + MSYS2，GNU Bash 5.3.15、jq 1.8.2。
- 执行约束：`HOME`、`TMPDIR` 指向仓库内 `.tmp-msys/`，命令使用仓库约定的 MSYS2 PATH。

## 已实现控制面

Docker 版使用独立入口 `install-docker.sh`，安装后的宿主命令为
`padm-docker`。Docker 控制代码位于 `docker/lib/`，没有进入原生
`install.sh` 的模块 manifest 或刷新路径。

安装前一次性检查：

- Linux、root、Bash 4+、`amd64/arm64`。
- 本机 rootful Docker Engine、Linux daemon、主机与 daemon 架构一致。
- 本机 Unix socket Docker context，拒绝 rootless 和远程 context。
- Docker Compose v2、jq、SHA-256、tar，以及 curl/wget 之一。

前置检查和原生部署互斥检查通过后，初始化以下状态：

```text
/etc/padm-docker/
├─ mode                         # docker，0640
├─ bundle -> .bundles/<digest>  # 当前控制 bundle 的原子指针
├─ .bundles/<digest>/           # 内容寻址、manifest 已验证的 bundle
├─ config/ data/ logs/ backups/ locks/  # 0750
└─ secrets/                     # 0700
```

除受管的 `bundle` 原子指针外，状态目录必须由当前 root 拥有且不能是符号链接。bundle 覆盖
`install-docker.sh`、`docker/`、`shell/core/deployment_mode.sh` 和 Docker
专项文档；候选内容先按独立 manifest 逐文件验证 SHA-256，再原子切换
`bundle` 链接。干净 Git 源记录 commit；脏工作区或无 Git 源记录整个
payload 的聚合 SHA-256。

阶段 1 不创建虚假的 `deployment.json`。该文件需要阶段 2 的真实核心、
监听器、镜像 digest 和 Compose profile 才能满足冻结的 schema v1；当前安装
状态由 `mode`、bundle ref 和 bundle manifest 组成。

## 命令与退出码

| 命令 | 阶段 1 行为 |
| --- | --- |
| `install` | 本地完整源安装；支持 `--source`，以及按 40 位 commit 的 `--ref` 原子刷新。 |
| `status` | 输出部署和 bundle 状态；Compose 缺失时明确返回 14。 |
| `up/down/restart/logs` | 真实转发到固定 project `padm-docker`；不模拟成功。 |
| `uninstall` | Compose 存在时先 down，移除 CLI，保留状态、bundle、配置和数据。 |

稳定非零退出码：`2` 参数错误、`10` 主机前置检查、`11` 部署冲突、
`12` 部署锁、`13` bundle、`14` Compose、`15` 状态或受管路径错误。

阶段 1 不提供 `purge`、镜像删除、`update/rollback`、迁移或备份恢复；这些
操作不能在没有真实镜像 manifest 和 desired state 时伪实现。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| 新增和受影响 Bash 文件 `bash -n` | 通过 |
| `docker-phase1` 统一回归 selector | 通过，121.269 秒 |
| 原生 `fast-full` | 通过，80.359 秒 |
| 原生 `all` | 通过，584.710 秒 |
| `git diff --check` | 通过 |

专项回归使用假 Docker CLI，覆盖 daemon 不可用、rootless、Compose v1、
不支持架构、原生冲突、无 marker 活跃容器、异常状态根、锁超时、重复安装、
bundle 失败不切换、缺 Compose 非零、Compose 参数转发和卸载数据保留。

正式专项命令：

```bash
bash shell/subscription_groups_regression.sh docker-phase1
```

## 边界

本阶段不包含 Dockerfile、镜像引用、`compose.yaml`、端口 desired state、
签名发布 manifest 或 CI 构建，因此不会执行 `docker build`、安装宿主软件或
修改软件源。Windows/MSYS2 回归验证控制逻辑，不证明真实 Linux rootful
Docker daemon、Compose 网络或容器生命周期；真实 E2E 从阶段 2 开始。
