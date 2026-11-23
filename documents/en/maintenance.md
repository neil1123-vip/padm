# 🛠️ Maintainer Guide

[🏠 English home](README_EN.md#documentation) · [🌍 中文](../maintenance.md)

This guide covers entry scripts, module layout, and release workflows. See the [English documentation](README_EN.md#documentation) for deployment and day-to-day operations.

[Runtime model](#runtime-model) · [sing-box stats builds and version refresh](#stats-builds) · [GitHub Actions dependency updates](#actions-dependencies)

## Runtime Model

- 🚪 **Native.** `install.sh` uses `/etc/padm`. The `shell/core/bootstrap.sh` entry loads the platform, protocol, routing, TLS, subscription, and menu modules. The menu and the `RenewTLS`, `UpdateGeo`, `SyncSubscriptionGroups`, `SubscriptionControl`, and `InstallSubscription` subcommands share this runtime.
- 🔄 **Module refresh.** padm atomically replaces `shell/`, `documents/`, `assets/`, `README.md`, and `.padm-module-manifest`. If the refresh fails, it attempts to restore the previous modules.
- 🐳 **Docker.** `install-docker.sh` uses `/etc/padm-docker`. The host-side `padm-docker` command manages the deployment through the Docker CLI and Compose. The Docker socket stays on the host.

| Path | Purpose |
| --- | --- |
| `install.sh` | 🚪 Repository entry script; handles self-refresh, argument parsing, formal subcommands, and first-run module bootstrap. |
| `install-docker.sh` | 🐳 Independent Docker entry; installs and refreshes the Docker control bundle without building images. |
| `padm-docker` | 🎛️ Installed host-side Docker command; controls the fixed `padm-docker` Compose project. |
| `docker/` | 📦 Dockerfiles, Compose, manifests, configuration contracts, and lifecycle implementation. |
| `shell/core/` | ⚙️ Platform detection, runtime helpers, protocol templates, Reality/TLS/routing/service/menu logic. |
| `shell/subscription/` | 🔗 Subscription publishing, subscription-group state, user accounts, WireGuard control plane, remote sync, and traffic accounting. |
| `shell/regression/` | 🧪 `framework/` provides the environment, runners, and registry; `cases/` loads fixtures, stubs, and test functions once; `suites/` only registers selectors, groups, and compositions. |
| `shell/subscription_groups_regression.sh` | 🧪 The single public regression dispatcher for suite, aggregate, contract, and composition selectors. |
| `shell/validate_install.sh` | ✅ Read-only post-install validation script. |
| `documents/` | 📚 Usage guides, maintainer documentation, and example configuration. |
| `assets/` | 🖼️ Three local static-site themes for Nginx or native Hysteria2. |

When adding a Docker feature, update its menu entry and support status in both the feature matrix and `docker/contracts/features.json`. [Docker feature matrix (Chinese)](../docker-feature-matrix.md)

<a name="stats-builds"></a>

## 📦 sing-box Stats Builds and Version Refresh

Run `Build sing-box Traffic Stats` to build the stats-enabled release. Leave `version` empty to use `versions.lock`, or enter an upstream tag such as `v1.14.0`. On `main`, changes to the stats build files, stats decoders, image checks, or relevant lock inputs trigger build preparation. Manual runs and changes to the build logic, distroless runtime, or official digests for the same version revalidate existing releases and preserve published assets.

Both architectures must pass native startup, Naive/Cronet loading, Hysteria2 and TUIC transfers, and per-user stats checks. The actual Dockerfile also runs image smoke tests with the candidate package, pinned Debian dependencies, and distroless base. The release contains binaries, corresponding source, and `SHA256SUMS`. Binary archives include `LICENSE` and build information. The stats build uses a separate release so padm's latest marker points to the main program.

`Refresh Upstream Versions` checks the official stable sing-box release daily at 03:17 UTC (11:17 Beijing time). GitHub may start the workflow later, and maintainers can also run it manually. A missing stats release triggers builds for both architectures. The workflow validates the lock and runs preflight and Docker CI on a temporary branch. It fast-forwards `main` and dispatches Release if the base is unchanged and the diff contains only `versions.lock`. A later run can recover a failed dispatch.

Automatic refresh uses published stable stats releases from this repository. A stats build failure reports a failed workflow. Base image and Debian snapshot locks can still refresh against a published stats version. To build a prerelease, run the stats workflow with `version` set explicitly.

<a name="actions-dependencies"></a>

## 🔄 GitHub Actions Dependency Updates

Dependabot checks GitHub Actions dependencies daily and groups major, minor, and patch updates. `Dependabot Automation` responds to successful Docker CI runs on same-repository Dependabot branches, then checks the event's branch and commit. Reconciliation is scheduled daily at 04:37 UTC (12:37 Beijing time) and can also run manually.

Stable Action reference upgrades in same-repository PRs qualify for automatic merging. When `main` advances, the workflow syncs the update branch and checks the latest CI for that commit, including Cosign installation, local signing and verification, and tamper rejection. Once the checks pass, the workflow uses the PR title for the merge commit, retains the tested tree and branch history, and fast-forwards `main` with its previous head as the first parent. Downgrades, changes to other files, requested changes, and genuine test failures require manual handling. Branch protection must allow the merge workflow to proceed. Official releases still use OIDC signing and trusted-identity verification.

In repository settings, open Settings → Secrets and variables → Actions and set `DEPENDABOT_AUTOMATION_TOKEN`. Use a fine-grained PAT scoped to this repository with read and write access to Actions, Contents, Pull requests, and Workflows. Replace the token when it expires. The workflow needs this token to sync branches with workflow changes and stops before the API call if the secret is missing.

The `pull_request` event starts CI after synchronization, and `push` starts Release after the merge. Reconciliation waits at least 10 minutes before dispatching a missing run. A fallback Release also requires `main` to still point to that merge commit. Queued, running, and failed jobs keep their results. An existing manual CI run prevents a duplicate fallback for a native CI run awaiting approval. Release keeps the main-branch regression gates and builds and publishes images when a release is needed.

[⚙️ Configuration checks and traffic stats recovery](operations.md) · [🧪 Local and CI regression tests](regression.md)
