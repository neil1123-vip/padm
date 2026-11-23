# 🛠️ 维护者指南

[🏠 返回首页](../README.md#文档导航)

从入口脚本、模块目录和发布工作流定位维护任务。日常部署、核心更新和应用配置见首页的使用文档。

[运行模型](#运行模型) · [统计版构建与依赖更新](#统计版构建) · [GitHub Actions 依赖维护](#actions-依赖)

## 运行模型

- 🚪 **原生版。** `install.sh` 使用 `/etc/padm`，由 `shell/core/bootstrap.sh` 加载平台、协议、路由、TLS、订阅和菜单模块。菜单与 `RenewTLS`、`UpdateGeo`、`SyncSubscriptionGroups`、`SubscriptionControl`、`InstallSubscription` 共用运行时。
- 🔄 **模块刷新。** 原子替换 `shell/`、`documents/`、`assets/`、`README.md` 和 `.padm-module-manifest`。失败时尝试恢复旧模块。
- 🐳 **Docker 版。** `install-docker.sh` 使用 `/etc/padm-docker`。宿主上的 `padm-docker` 通过 Docker CLI 和 Compose 操作部署，业务容器不挂载 Docker socket。

| 路径 | 作用 |
| --- | --- |
| `install.sh` | 🚪 仓库入口；负责自刷新、参数解析、正式子命令分发和首次模块补齐。 |
| `install-docker.sh` | 🐳 Docker 独立入口；安装并刷新 Docker 控制 bundle，不构建镜像。 |
| `padm-docker` | 🎛️ 安装后的 Docker 宿主控制命令；调用固定的 `padm-docker` Compose project。 |
| `docker/` | 📦 Dockerfile、Compose、manifest、配置合同和生命周期实现。 |
| `shell/core/` | ⚙️ 平台检测、运行时 helper、协议模板、Reality/TLS/路由/服务/菜单等核心逻辑。 |
| `shell/subscription/` | 🔗 订阅发布、订阅组状态、用户账号、WireGuard 控制面、远程同步和流量统计。 |
| `shell/regression/` | 🧪 `framework/` 提供环境、runner 和 registry，`cases/` 单次加载 fixture、stub 与测试函数，`suites/` 只注册 selector、分组和组合。 |
| `shell/subscription_groups_regression.sh` | 🧪 唯一公开回归分发入口；统一分发 suite、aggregate、contract 和 composition selector。 |
| `shell/validate_install.sh` | ✅ 安装后的只读验收脚本。 |
| `documents/` | 📚 使用指南、维护文档、示例配置和英文 README。 |
| `assets/` | 🖼️ 三套本地静态站点资产，供 Nginx 或原生 Hysteria2 使用。 |

Docker 能力的菜单入口和支持范围记录在功能对照表及 `docker/contracts/features.json`，新增能力时同步更新两处。 [Docker 版功能对照表](docker-feature-matrix.md)

<a name="统计版构建"></a>

## 📦 统计版构建与依赖更新

维护者可运行 `Build sing-box Traffic Stats`。默认读取 `versions.lock`，也可指定上游标签，如 `v1.14.0`。推送到 `main` 时，相关构建文件、统计解码器、镜像检查或版本锁变更会触发构建准备。构建逻辑、distroless 运行层或同版本官方摘要有变更时，以及手动运行时，会重新验证已发布版本并保留已发布资产。

发布前，两个架构均须通过原生启动、Naive / Cronet 加载、Hysteria2 / TUIC 实际传输和按用户统计检查。候选二进制还会放入正式 Dockerfile，用锁定的 Debian 依赖和 distroless 底座做镜像冒烟测试。通过后发布二进制、对应源码和 `SHA256SUMS`。二进制包包含 `LICENSE` 和构建信息。统计版有自己的 Release，padm 的 latest 标记仍用于主程序发布。

`Refresh Upstream Versions` 每天北京时间 11:17 检查官方 sing-box 最新稳定版。GitHub 调度可能延迟，也可手动运行。缺少对应统计版时，会触发双架构构建。临时分支上的版本锁通过校验、预检和该提交的 Docker CI 后，如果 `main` 基线一致且只改了 `versions.lock`，脚本会快进合入并派发 Release。派发失败时可补派。

自动刷新只选择本仓库已发布的正式统计版。构建失败会报告失败，基础镜像和 Debian 快照锁仍可按已发布版本更新。构建预发布版时，可手动传入 `version`。

<a name="actions-依赖"></a>

## 🔄 GitHub Actions 依赖维护

Dependabot 每日检查 GitHub Actions 依赖，大版本、次版本和补丁更新合为一组。`Dependabot Automation` 响应同仓库 Dependabot 分支的 Docker CI 成功事件，按事件的分支和提交再次核对。全量巡检在北京时间 12:37 调度，也可手动运行。

允许自动合入同仓库 PR 中符合条件的稳定版 Action 引用升级。主分支前进时，先同步更新分支，再核对对应提交的最新 CI、Cosign 安装、本地签验和篡改拒绝测试。通过后，以 PR 标题生成合并提交，保留受测文件树及同步历史，以 `main` 为第一父提交并快进推送。降级、其他文件改动、人工要求修改或真实测试失败的 PR 由人工处理。启用主分支保护的仓库需配置兼容的合并门禁。正式发布仍需执行 OIDC 签名及可信身份验证。

启用前，在仓库的 Settings → Secrets and variables → Actions 中配置 `DEPENDABOT_AUTOMATION_TOKEN`。使用仅授权本仓库的 fine-grained PAT，授予 `Actions`、`Contents`、`Pull requests` 和 `Workflows` 读写权限，到期后更换。同步含工作流变动的分支需要使用专用 PAT，缺少该 Secret 时工作流会在调用 API 前停止。

同步后由 `pull_request` 事件启动 CI，合入后由 `push` 触发 Release。巡检在等待至少 10 分钟后补派缺失的运行，Release 还要求当前 `main` 仍指向该合并提交。已排队、运行中或失败的作业保留原结果。已有手动 CI 时，原生 CI 待审批也会继续等待。Release 保留主分支回归，需要发布时才继续构建和发布镜像。

配置检查和恢复流量统计见 [⚙️ 服务与系统运维](operations.md)，本机和 CI 的回归入口见 [🧪 验收与回归](regression.md)。
