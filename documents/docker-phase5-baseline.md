# Docker 容器化阶段 5 基线

## 状态

阶段 5 的 CI 构建与发布门禁已实现（2026-08-18）。镜像仍由本仓库定义，生产
环境不执行 `docker build`；Release 只消费带版本和 digest 的 CI 产物。

## 已实现

- `docker/release.sh` 统一校验 `versions.lock`、脚本版本和构建输入；Release
  bump 同时更新 `shell/core/version.sh` 与 `versions.lock`。
- `docker/contracts/release-manifest.schema.json` 固定 schema v1，包含源码提交、
  控制 bundle、五个镜像的多架构 index/platform digest、格式版本、主机兼容性
  和迁移列表；未知字段或缺失字段拒绝。
- `.github/workflows/build-images.yml` 仅作为可复用 workflow，按镜像输入变化决定构建或复用。
  发布时每架构只构建一次，携带 SBOM/provenance 按 digest 推送；精确摘要通过 smoke 后
  才合并双架构 index 并签名。普通验证使用 `--load`，复用镜像仍做双架构 smoke 和验签。
  分镜像/架构使用 Actions 构建缓存，复用基线须来自已验签且可追溯的旧 manifest。
- `.github/workflows/docker-ci.yml` 为 Pull Request 复用同一 workflow，禁止推送。
- `.github/workflows/create_release.yml` 只对运行内容变化自动发布，串行处理最新 `main`，
  跳过已发布的内容；只有镜像 workflow 成功、manifest 验签和资产摘要检查通过后才公开草稿。
- Release 只附带 `release-manifest.json`、Cosign 签发的 Sigstore bundle v0.3 和控制 bundle，
  不把 manifest 回提交到 `main`。镜像证明保存在 OCI 仓库，诊断 JSON 在 Actions 保留 7 天。
- PR 和手动验证共用去重并发组，过时验证取消；上游刷新优先等待已有的同提交 CI，缺失才补发。

## 本地验证

| 验证 | 结果 |
|---|---|
| `bash -n`（新增/受影响脚本） | 通过 |
| JSON schema/manifest 生成与未知字段拒绝 | 通过 |
| `docker-phase5` | 通过 |
| workflow YAML 解析 | 通过 |
| `git diff --check` | 待提交前复核 |

## CI 边界

本机 Docker daemon 未运行，未在 Windows 上伪造镜像 build/run 结果。真实的
Buildx 双架构构建、QEMU smoke、GHCR push、Cosign keyless 身份、SBOM/provenance
attestation 和 GitHub Release API 必须在 CI runner 上完成；任一门禁失败都不会进入
正式 Release。阶段 6 再接入生产端 manifest 验签、更新、回滚和卸载事务。
