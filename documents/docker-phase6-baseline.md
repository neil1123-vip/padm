# Docker 容器化阶段 6 基线

## 结果

阶段 6 完成生产端发布清单验签、固定 digest 更新、失败恢复、回滚和卸载边界：

- `manifest.sh` 严格校验 release manifest 字段、镜像 reference/index digest 一致性、Sigstore bundle SHA-256、固定 Cosign identity/issuer 和当前架构。
- `update` 在部署锁内验签、预拉取五个完整 digest reference，生成候选状态，备份 `backups/update.*`，切换 Compose 并等待健康检查；失败恢复旧配置和旧镜像引用。
- `rollback` 只接受受管、无符号链接、路径在状态根内且 deployment 有效的最近 `update.*` 快照；恢复失败会尝试恢复当前版本。
- 普通 `uninstall` 停止 Compose、移除本部署 CLI，保留状态、配置、数据、备份和镜像；`--remove-images` 只删除 deployment/images.env 一致的五个精确 digest。
- `--purge` 必须提供 `--confirm PADM-DOCKER-PURGE`，停止和备份失败时不继续清理，仅删除解析后的受管状态根。

## 验证

本地已通过：

- `docker/tests/phase1.sh` 到 `docker/tests/phase6.sh`
- `docker-phase6` 回归选择器
- 修改脚本 `bash -n`
- JSON/YAML 合同解析和 `git diff --check`

本机 Docker daemon 不可用，因此真实镜像拉取、Compose health 和 Cosign OIDC 只在 CI/Release 环境验收。
