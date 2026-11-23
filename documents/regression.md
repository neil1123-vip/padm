# 🧪 验收与回归

[🏠 返回首页](../README.md#文档导航)

部署后可用只读脚本验收。在仓库开发时，可按改动范围选择回归。

[安装后验收](#安装验收) · [Windows 本机回归](#windows-回归) · [并发、快照与结果](#回归结果) · [Linux 与 CI](#linux-回归)

<a name="安装验收"></a>

## ✅ 安装后验收

在原生版部署服务器上，进入安装目录（默认 `/etc/padm`）运行只读检查。

```bash
bash shell/validate_install.sh [domain]
```

加上 `--online` 检查公网 DNS、HTTP、HTTPS 和 TLS。

```bash
bash shell/validate_install.sh --online example.com
```

<a name="windows-回归"></a>

## 🧪 Windows 本机回归

使用 PowerShell 7.3 或更新版本，经 Docker Desktop 在与宿主同架构的 Linux 容器中运行回归。首次运行会构建 `padm-regression:local`，以后复用匹配的工具镜像。

```powershell
.\shell\regression\run-docker.ps1 -Selector fast
.\shell\regression\run-docker.ps1 -Selector ui-subscription-workflow-focused
.\shell\regression\run-docker.ps1 -Selector docker-routing-domains-workflow
.\shell\regression\run-docker.ps1 -Selector ci -Jobs 3
.\shell\regression\run-docker.ps1 -Selector docker-contracts -Jobs 6
```

先跑与改动匹配的定向 selector。需要综合检查时运行 `docker-contracts -Jobs 6`，覆盖权限、所有权、密钥、回滚、恢复预览和控制链等 34 项常用合同。全量 `docker-contracts-full` 用于明确要求的全量验收，或发布前由集成任务集中运行。日常集合之外的功能可追加对应定向回归。

| 改动范围 | 定向 selector |
| --- | --- |
| 🔗 订阅交互 | `ui-subscription-workflow-focused` |
| 🧱 Direct / Block CSV 与菜单 | `docker-routing-domains-workflow`、`docker-menu` |
| 🔌 额外入口端口 | `docker-entry-port-alias`、`docker-menu-port-alias` |
| 🧭 多入口与双核心拓扑 | `docker-phase3-entries-topology` |
| ⚙️ 协议增删、TLS 或重装 | `docker-phase3-entries-management` |

拓扑与管理也可通过 `docker-phase3-entries` 并行运行。全量和 CI 分片覆盖同一组场景。真实宿主、整机重启、公网和业务容器连通性仍需在匹配环境单独验收。

<a name="回归结果"></a>

## ⚙️ 并发、快照与结果

| 回归范围 | 默认并发 | `-Jobs` 范围 |
| --- | --- | --- |
| 普通定向 selector | 2 | 1–4 |
| `all` | 3 | 1–4 |
| `ci`、`ci-pr` | 3 | 2–4 |
| `docker-contracts`、`docker-contracts-full` | 6 | 1–8 |

- 🧵 **并发。** 同一仓库、同一 Windows 用户共享三个回归槽。普通定向占一个，上表的聚合回归占两个并优先取得所需槽位。两套聚合回归不能重叠。排队次序可能变化，`-Jobs` 只控制容器内测试并发。
- 📸 **快照。** 排队前归档当前工作区的已跟踪文件和未忽略的新文件，包含未提交修改，排除 `.git` 与 `.tmp-*`。源码和临时目录位于容器内的 Linux 文件系统。镜像构建串行且每次回归固定镜像 ID。异常退出时，队列会先清理本入口标记的残留容器。
- 📦 **工具镜像。** 复用时核对原生架构和工具内容标签。镜像装有固定的测试依赖，测试源码随快照同步。容器默认隔离网络，部分专项使用桥接网络。需要更新工具层时使用 `-Rebuild`。
- 🧾 **日志。** `.tmp-regression-docker-*/` 保存日志和 `result.json`，记录排队时间、槽位、镜像 ID 和结果来源。失败会保留复现输入并返回原退出码。
- ♻️ **结果复用。** 聚合回归会在源码路径、内容、类型与权限、工具镜像、selector、架构、`Jobs` 和工作区存储方式均一致时，复用证据仍有效的成功结果。共享索引位于 `.tmp-regression-shared-*/`。普通定向用例每次实际执行，聚合回归也可用 `-ForceRun` 重跑。

Windows 入口自检使用 `.\shell\regression\test-run-docker.ps1`。

<a name="linux-回归"></a>

## 🐧 Linux 与 CI

Linux 环境统一通过 Bash 回归入口按 selector 运行。

| 层级 | 命令 | 用途 |
| --- | --- | --- |
| 快速反馈 | `bash shell/subscription_groups_regression.sh fast` | 日常小改后的代表性检查，完整快检集合用 `fast-full`。 |
| 主产品回归 | `bash shell/subscription_groups_regression.sh all` | 验证核心产品功能，按资源预算编排回归。 |
| 按需专项 | `bash shell/subscription_groups_regression.sh <selector>` | 按改动范围补跑协议、深层回滚或 harness 行为检查。 |

PR 原生回归默认执行 `ci-pr`，订阅或回归框架改动使用 `ci`。Release 始终运行完整原生 `ci`，静态检查、回归和发布准备固定到同一提交。CI 的 Docker 合同分片覆盖全量场景。`ci` 和 `ci-pr` 默认并发为 3，可用 `PADM_REGRESSION_CI_PARALLEL_JOBS` 或 Docker CI 手动输入在 2–4 之间调整。

`all` 在同一资源预算内并行运行 `subscription`、`ui`、`transaction-core-main`、`transaction-system`、`routing`、`runtime`、`remote-control-smoke`、远程控制服务安装契约和远程控制响应契约。完整 `transaction-core`、`fast-full`、`protocol-capabilities`、`remote-control-deep` 和 harness 契约按改动范围追加。

<details>
<summary>🧪 常用产品专项命令</summary>

```bash
bash shell/subscription_groups_regression.sh protocol-capabilities
bash shell/subscription_groups_regression.sh platform-hot
bash shell/subscription_groups_regression.sh platform-smoke
bash shell/subscription_groups_regression.sh fast-full
# sing-box 1.14 兼容性迁移专项（fast-full 已包含）
bash shell/subscription_groups_regression.sh fast-only-compatibility
bash shell/subscription_groups_regression.sh subscription-output
bash shell/subscription_groups_regression.sh transaction-core
bash shell/subscription_groups_regression.sh core-safety-rollback
bash shell/subscription_groups_regression.sh routing-safety
bash shell/subscription_groups_regression.sh subscription-safety
bash shell/subscription_groups_regression.sh transaction-system
bash shell/subscription_groups_regression.sh remote-control-smoke
bash shell/subscription_groups_regression.sh remote-control-contract
bash shell/subscription_groups_regression.sh remote-control-deep
bash shell/subscription_groups_regression.sh subscription-state
bash shell/subscription_groups_regression.sh ui-full-core
bash shell/subscription_groups_regression.sh ui-full-core-maintenance
```

</details>

<details>
<summary>🧰 回归框架专项命令</summary>

```bash
bash shell/subscription_groups_regression.sh regression-dispatcher-contract
bash shell/subscription_groups_regression.sh regression-case-loader-contract
bash shell/subscription_groups_regression.sh framework-parallel-selector-list-with-jobs
bash shell/subscription_groups_regression.sh targeted-batch-helpers
```

</details>

需要压并发或保守跑重型 suite 时，优先用 `PADM_REGRESSION_PARALLEL_JOBS`、`PADM_REGRESSION_CHILD_PARALLEL_JOBS`，以及按 suite 开启 `PADM_REGRESSION_*_RESOURCE_PROFILE=all`。`shell/regression/protocol_capabilities.sh` 仅作为保留原成功标记的兼容转发入口。

主入口按 `framework/`、`cases/load.sh`、`suites/` 的固定顺序装配回归；case 只加载一次，不再保留历史 source-only 分组层。

仓库结构和发布自动化见 [🛠️ 维护者指南](maintenance.md)。
