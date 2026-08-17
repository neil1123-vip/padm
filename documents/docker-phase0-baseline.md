# Docker 容器化阶段 0 基线

## 基线身份

- 日期：2026-08-17。
- 基准提交：`341cecbcf08a012e629b8067f5cf1fd05e019f7f`。
- 工作树：阶段 0 完成候选，尚未提交；未进入 Docker 控制骨架、镜像或 Compose 实现。
- 环境：Windows 11 + MSYS2，GNU Bash 5.3.15、jq 1.8.2。
- 执行约束：`HOME`、`TMPDIR` 指向仓库内 `.tmp-msys/`，命令使用仓库约定的 MSYS2 PATH。

## 已冻结契约

| 项目 | 原生版 | Docker 版 |
| --- | --- | --- |
| 入口 | `install.sh` | `install-docker.sh`（阶段 1 实现） |
| 命令 | `padm` | `padm-docker` |
| 状态根 | `/etc/padm` | `/etc/padm-docker` |
| 模式标记 | `/etc/padm/mode` = `native` | `/etc/padm-docker/mode` = `docker` |
| 部署状态 | `absent/installed/active/ambiguous` | `absent/installed/active/ambiguous` |
| Desired state | 不适用 | `deployment.json`，schema 版本 1 |

Docker `deployment.json` 的字段、类型和未知字段策略冻结在
`docker/contracts/deployment.schema.json`。原生安装只写 `/etc/padm`；阶段 0
没有 Docker 入口，因此不会创建或修改 `/etc/padm-docker`。

## 互斥基线

- 原生安装在任何包事务、脚本复制或独立订阅安装前检查 Docker 部署。
- Docker 活跃态使用 `io.padm.project=padm-docker` 或
  `com.docker.compose.project=padm-docker` label 识别。
- marker 异常、残留文件、无法识别的 `deployment.json` 均为 `ambiguous`，安装 fail-closed。
- 旧原生安装没有 marker 时，兼容识别入口、ref、module manifest、核心文件、服务单元和运行进程。
- 原生卸载入口未增加全局拦截，冲突状态下仍可执行显式清理。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| 受影响 Bash 文件 `bash -n` | 通过 |
| `jq empty docker/contracts/deployment.schema.json` | 通过 |
| 阶段 0 mode/schema 定向契约 | 通过 |
| `platform-rest`（受影响专项） | 通过，36.189 秒 |
| `fast-full`（最终工作树，含新增断言） | 通过，79.083 秒 |
| `all` | 通过，557.154 秒 |
| `git diff --check` | 通过 |

正式基线命令：

```bash
bash shell/subscription_groups_regression.sh fast-full
bash shell/subscription_groups_regression.sh all
```

## 边界

本基线证明现有原生回归和阶段 0 的静态/行为契约在 MSYS2 环境通过；它不证明
Linux 上的真实 systemd/OpenRC、Docker daemon、容器网络或 Compose 生命周期。
这些验证从阶段 1 和阶段 2 开始加入 Linux CI/E2E 门禁。

最终 `fast-full` 之后只做了文档、状态记录和本基线文件更新；`all` 已覆盖同一阶段
0 代码，新增的测试断言另以定向用例复核通过。
