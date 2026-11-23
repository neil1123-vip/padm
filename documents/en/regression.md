# 🧪 Validation and Regression

[🏠 English home](README_EN.md#documentation) · [🌍 中文](../regression.md)

Run the read-only checks after deployment. When working in the repository, choose a regression selector that covers the area you changed.

[Post-install validation](#post-install-validation) · [Local regression on Windows](#local-regression-on-windows) · [Concurrency, snapshots, and results](#concurrency-snapshots-and-results) · [Linux and CI](#linux-and-ci)

## Post-install validation

On a server with a native installation, run the read-only check from the installation directory, `/etc/padm` by default.

```bash
bash shell/validate_install.sh [domain]
```

Add `--online` to check public DNS, HTTP, HTTPS, and TLS.

```bash
bash shell/validate_install.sh --online example.com
```

## Local regression on Windows

Use PowerShell 7.3 or later with Docker Desktop. Tests run in a Linux container on the same architecture as the host. The first run builds `padm-regression:local`, which subsequent runs reuse when the architecture and tools match.

```powershell
.\shell\regression\run-docker.ps1 -Selector fast
.\shell\regression\run-docker.ps1 -Selector ui-subscription-workflow-focused
.\shell\regression\run-docker.ps1 -Selector docker-routing-domains-workflow
.\shell\regression\run-docker.ps1 -Selector ci -Jobs 3
.\shell\regression\run-docker.ps1 -Selector docker-contracts -Jobs 6
```

Start with a selector that covers your change. For a broader check, use `docker-contracts -Jobs 6`. Its 34 contracts cover common areas including permissions, ownership, keys, rollback, recovery preview, and the control plane. Use `docker-contracts-full` for full acceptance checks or a coordinated pre-release run. Add a focused selector for features outside the 34-contract set.

| Area changed | Focused selector |
| --- | --- |
| 🔗 Subscription menus | `ui-subscription-workflow-focused` |
| 🧱 Direct / Block CSV and menus | `docker-routing-domains-workflow`, `docker-menu` |
| 🔌 Extra listener ports | `docker-entry-port-alias`, `docker-menu-port-alias` |
| 🧭 Multiple listeners and dual-core topology | `docker-phase3-entries-topology` |
| ⚙️ Adding or removing protocols, TLS, or reinstalling | `docker-phase3-entries-management` |

`docker-routing-domains-workflow` reuses the Direct / Block transaction assertions. For broader changes, add schema, generator, routing matrix, or real traffic checks that cover the affected behavior. `docker-menu-port-alias` runs the same port alias PTY cases as `docker-menu`.

`docker-phase3-entries` runs the topology and management selectors in parallel. The full contract suite and CI shards cover the same cases. Validate real host behavior, reboots, public connectivity, and connectivity from application containers separately in the target environment.

## Concurrency, snapshots, and results

| Selector | Default jobs | `-Jobs` range |
| --- | --- | --- |
| Focused selectors | 2 | 1–4 |
| `all` | 3 | 1–4 |
| `ci`, `ci-pr` | 3 | 2–4 |
| `docker-contracts`, `docker-contracts-full` | 6 | 1–8 |

- 🧵 **Concurrency.** Three slots are shared by worktrees of the same repository for the same Windows user. Focused runs take one slot. Aggregate runs take two and have priority while waiting for those slots, so only one aggregate run can run at a time. Queue order can vary. `-Jobs` controls test concurrency inside each container.
- 📸 **Snapshots.** Before queueing, the runner archives tracked and unignored new files, including uncommitted changes, and excludes `.git` and `.tmp-*`. Sources and temporary directories live on the container's Linux filesystem. Image builds run one at a time, and each regression pins the image ID. After an abnormal exit, the queue cleans up leftover containers created by this runner before making their slots available.
- 📦 **Tool image.** The runner checks the native architecture and tool content label before reusing the image. The image contains pinned test dependencies, and the source comes from the snapshot. Containers run with isolated networking by default. Some focused checks use bridge networking. Use `-Rebuild` to update the tool image.
- 🧾 **Logs.** `.tmp-regression-docker-*/` contains logs and `result.json`, which records queue time, slot usage, image ID, and result provenance. On failure, the runner keeps the inputs needed to reproduce it and returns the original exit code.
- ♻️ **Result reuse.** Aggregate runs reuse a successful result if its evidence is still available and the source paths, contents, file types and permissions, tool image, selector, architecture, `Jobs`, and workspace storage mode match. The shared index lives under `.tmp-regression-shared-*/`. Focused selectors run every time. Use `-ForceRun` to rerun an aggregate selector.

Run `.\shell\regression\test-run-docker.ps1` to check the Windows runner itself.

## Linux and CI

Use the Bash dispatcher to run selectors on Linux.

| Level | Command | Purpose |
| --- | --- | --- |
| Fast feedback | `bash shell/subscription_groups_regression.sh fast` | Representative checks after small changes. Use `fast-full` for the full set of fast checks. |
| Main product regression | `bash shell/subscription_groups_regression.sh all` | Core product checks scheduled within a shared resource budget. |
| Focused checks | `bash shell/subscription_groups_regression.sh <selector>` | Protocol, deep rollback, or harness checks tailored to the change. |

Pull requests use `ci-pr` for native regressions by default and use `ci` for subscription or regression harness changes. Release uses the full native `ci` selector and pins static checks, regressions, and release preparation to the same commit. Docker contract shards in CI cover the full set of cases. `ci` and `ci-pr` default to three jobs. Set `PADM_REGRESSION_CI_PARALLEL_JOBS` or the Docker CI manual input to choose between two and four.

After pushing a version-only commit, the Release run builds and publishes it using the completed checks. Release hands off to a new run if a competing push prevents the version update or the checked commit uses a newer workflow revision.

`all` runs `subscription`, `static-sites`, `ui`, `transaction-core-main`, `transaction-system`, `routing`, `runtime`, `remote-control-smoke`, `remote-control-contract-service-install`, and `remote-control-contract-server-response` in parallel within a shared resource budget. Add `transaction-core`, `fast-full`, `protocol-capabilities`, `remote-control-deep`, or harness contracts as needed for the changed area.

<details>
<summary>🧪 Common product selectors</summary>

```bash
bash shell/subscription_groups_regression.sh protocol-capabilities
bash shell/subscription_groups_regression.sh platform-hot
bash shell/subscription_groups_regression.sh platform-smoke
bash shell/subscription_groups_regression.sh fast-full
# sing-box 1.14 compatibility migration (also covered by fast-full)
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
<summary>🧰 Regression harness selectors</summary>

```bash
bash shell/subscription_groups_regression.sh regression-dispatcher-contract
bash shell/subscription_groups_regression.sh regression-case-loader-contract
bash shell/subscription_groups_regression.sh framework-parallel-selector-list-with-jobs
bash shell/subscription_groups_regression.sh targeted-batch-helpers
```

</details>

To reduce concurrency or run resource-intensive suites more conservatively, use `PADM_REGRESSION_PARALLEL_JOBS`, `PADM_REGRESSION_CHILD_PARALLEL_JOBS`, or the suite's `PADM_REGRESSION_*_RESOURCE_PROFILE=all` setting. The `shell/regression/protocol_capabilities.sh` compatibility entry point forwards to the dispatcher and preserves the original success marker.

The dispatcher loads `framework/`, `cases/load.sh`, and `suites/` in that order. It loads each case once.

See the maintainer guide for repository structure and release automation. [🛠️ Maintainer Guide](maintenance.md)
