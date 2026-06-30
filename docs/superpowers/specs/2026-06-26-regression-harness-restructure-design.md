# Regression Harness Restructure Design

Status: implemented snapshot for the current `codex/all-resource-aware-regression` branch

## Summary

This document captures the current regression harness structure after the dispatcher, suite split, legacy retirement, and layered parallelization work already landed in the repository.

The harness has been reshaped around one dispatcher entry:

- `shell/subscription_groups_regression.sh`

That entry now loads shared framework modules plus suite-specific registration files, validates a selector registry, and runs a selected suite through a uniform dispatch path.

The main goals of the restructure are:

- make `shell/subscription_groups_regression.sh` the single supported entrypoint
- replace ad hoc top-level case routing with selector registration
- move long serial chains into suite-local layered parallel groups
- keep legacy regression coverage intact while reducing direct dependence on legacy dispatch files
- make resource-aware throttling explicit through environment variables instead of hard-coded nested shell behavior

Non-goals for this phase:

- rewriting legacy regression bodies
- changing coverage semantics of existing regression leaves
- removing every legacy source file immediately

## Current Architecture

### Dispatcher

`shell/subscription_groups_regression.sh` now does only four things:

1. source framework modules:
   - `shell/regression/framework/env.sh`
   - `shell/regression/framework/runtime.sh`
   - `shell/regression/framework/registry.sh`
2. source all suite registration files under `shell/regression/suites/`
3. restore legacy reality stubs through `restoreLegacyRealityRegressionStubs`
4. call `runRegisteredRegressionMain "${1:-fast}"`

This makes the dispatcher a bootstrap layer instead of a second suite definition surface.

### Framework Registry

The selector registry now supports only four kinds:

- `function`
- `aggregate-runner`
- `aggregate`
- `alias`

Important simplification:

- `registerRegressionScriptLeaf` and script-selector dispatch paths have been removed
- legacy internal CLI selector forwarding has been removed

Each registered selector is validated before first execution. Validation checks:

- duplicate selector rejection
- runner presence for `function` and `aggregate-runner`
- child selector existence for `aggregate` and `aggregate-runner`
- target existence for `alias`

### Runtime Helpers

The active runtime primitives are:

- `runParallelRegressionRunners`
- `runFrameworkParallelRegressionSelectors`
- `runFrameworkParallelRegressionSelectorList`
- `runFrameworkSequentialRegressionSelectorList`
- `runParallelRegressionSelectors` as a compatibility alias

`runFrameworkParallelRegressionSelectors` is now the common slot-limited orchestration primitive. It supports:

- selector lists or explicit label/selector pairs
- custom selector runners through `PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER`
- slot limiting through `PADM_REGRESSION_PARALLEL_JOBS`
- ordered log replay after background execution

`runFrameworkParallelRegressionSelectorList` is the preferred suite helper when a suite can expose its children as selectors.

`runFrameworkSequentialRegressionSelectorList` is the corresponding ordered-dispatch helper for suite roots that still need one child selector after another, but no longer need to hand-wire `runRegressionStep` chains locally.

`runParallelRegressionRunners` still exists for local same-file runner groups that are not yet expressed as selector trees.

## Suite Layout

### Fast

`fast` is now a selector aggregate instead of a large flat serial body.

Shape:

- `fast`
  - `platform-hot`
  - `fast-only`
- `fast-only`
  - `fast-only-safety`
  - `fast-only-output`
  - `fast-only-core`
- `fast-only-output`
  - `fast-only-output-auto-install`
  - `fast-only-output-rest`

This gives the short-path suite a clean layered shape and keeps output-focused work independently tunable.

`fast-reality` remains a sequential aggregate runner, but its suite root now dispatches
`fast` then `reality-candidates-fast` through `runFrameworkSequentialRegressionSelectorList`
instead of a hand-written serial chain. Its `reality-candidates-fast` tail step still
reuses the reality suite compat leaf instead of calling the legacy-backed reality runner
directly. That keeps fast-path reality coverage aligned with the same legacy isolation
boundary used by the dedicated reality suite.

### Platform

`platform-hot` is a parallel aggregate runner over:

- `platform-update`
- `platform-refresh`
- `platform-rest`

These leaves run through isolated compat wrappers that re-source `subscription_groups_fast.sh` in a subshell. The goal is to prevent later suite loads from mutating source-time fast fixture state.

`platform-io` remains a sequential suite root, but its legacy-backed install-tools,
package, and reality-scanner leaves now also run through a suite-local compat helper
that re-sources `subscription_groups_legacy.sh` in a subshell before each step.
That keeps the public `platform-io` selector on suite-owned dispatch while aligning
its leaf isolation boundary with the other suites that already defend source-time
`TMP_DIR`-derived state.

### Subscription

`subscription` has been decomposed into selector groups instead of monolithic legacy case branches.

Key selectors:

- `subscription-output`
- `subscription-remote`
- `subscription-tx`
- `subscription-state`
- `subscription`

`subscription-output` keeps the public selector name, but its long tail is split into four leaf selectors:

- `subscription-output-profile-and-reality`
- `subscription-output-publish-accounts-and-remote-hint`
- `subscription-output-tls-vless-vmess-trojan`
- `subscription-output-tls-any-hysteria-tuic-naive`

The public `subscription-output` wrapper still appends one compatibility tail step after the parallel suite root:

- `subscription-remote-sources-no-reverse-decode`

Defaults:

- `PADM_REGRESSION_SUBSCRIPTION_OUTPUT_PARALLEL_JOBS` falls back to `PADM_REGRESSION_PARALLEL_JOBS`, then `2`
- `PADM_REGRESSION_SUBSCRIPTION_REMOTE_PARALLEL_JOBS` falls back to `PADM_REGRESSION_PARALLEL_JOBS`, then `4`

`subscription` also supports a resource-aware profile split:

- light wave:
  - `subscription-output`
  - `subscription-state`
- heavy wave:
  - `subscription-tx`
  - `subscription-remote`

That split is enabled by:

- `PADM_REGRESSION_SUBSCRIPTION_RESOURCE_PROFILE=all`

Compatibility boundary:

- subscription leaves still call existing legacy regression functions
- isolated subshell compat wrappers re-source `subscription_groups_legacy.sh` to avoid stale `TMP_DIR`-derived state and source-time fixture drift

### Transaction

`transaction` remains a sequential top-level aggregate runner:

- `transaction-core`
- `transaction-subscription`
- `transaction-system`

This preserves existing suite semantics while allowing both heavy subtrees to optimize internally.

Its public suite root now also routes those ordered children through
`runFrameworkSequentialRegressionSelectorList`, so the suite keeps aggregate-runner
registration while dropping one more hand-written serial chain.

#### Transaction Core

`transaction-core` is a parallel aggregate runner with optional profile layering.

Default mode:

- run all registered core selectors through one selector-parallel wave

Profile mode:

- `PADM_REGRESSION_TRANSACTION_CORE_RESOURCE_PROFILE=all`

Waves:

1. heavy
2. medium
3. light

Default profile-specific child limits:

- heavy: `PADM_REGRESSION_TRANSACTION_CORE_HEAVY_PARALLEL_JOBS` -> fallback `2`
- medium: `PADM_REGRESSION_TRANSACTION_CORE_MEDIUM_PARALLEL_JOBS` -> fallback `3`
- light: `PADM_REGRESSION_TRANSACTION_CORE_LIGHT_PARALLEL_JOBS` -> fallback `4`

#### Transaction System

`transaction-system` is now a parallel aggregate runner over sixteen leaf selectors:

- `nginx-service-failure`
- `uninstall-nginx-cleanup`
- `clean-agent-nginx-managed-remove`
- `fail2ban-managed-cleanup`
- `fail2ban-apply-transaction`
- `uninstall-wireguard-cleanup`
- `wireguard-key-transaction`
- `wireguard-control-safe-dir`
- `warp-config-safe-dir`
- `warp-config-file-cleanup`
- `uninstall-service-stop-failure`
- `clean-last-installation-failure`
- `clean-last-installation-acme-home`
- `clean-last-installation-acme-relative-home`
- `alone-nginx-write-transaction`
- `alone-nginx-update-transaction`

Default limit:

- `PADM_REGRESSION_TRANSACTION_SYSTEM_PARALLEL_JOBS` -> fallback `PADM_REGRESSION_PARALLEL_JOBS` -> `4`

This change targets the previous long serial tail inside `all`.

The intermediate `transaction-subscription` suite root follows the same pattern:
its ordered child selector chain is now emitted by
`runFrameworkSequentialRegressionSelectorList`, while the public
`transaction-subscription` selector and leaf coverage semantics stay unchanged.

### UI

`ui` is now a selector-parallel aggregate runner with long-tail leaf expansion.

Two active shapes exist:

- default flattened leaf order for better overlap
- `PADM_REGRESSION_UI_RESOURCE_PROFILE=all` grouped profile shape for full-wave orchestration

The suite keeps the public `ui` selector while splitting nested flows such as:

- publish sync
- publish user
- wireguard peer rollback apply
- wireguard peer rollback credential
- wireguard peer source control

Nested aggregate wrappers inside the suite now share two suite-local orchestration helpers:

- `runUiSelectorListRegression`
- `runUiLeafSelectorListRegression`

The second helper preserves the existing nested leaf fan-out overrides instead of repeating inline environment wiring per wrapper.

Nested leaf fan-out can be limited with:

- `PADM_REGRESSION_UI_LEAF_PARALLEL_JOBS`

Compatibility boundary:

- UI leaf coverage still calls the existing legacy menu-smoke and wireguard regression functions
- those legacy-backed UI leaves now run through isolated compat wrappers that re-source `subscription_groups_legacy.sh` in a subshell before each leaf
- this was required because parallel UI menu-smoke leaves shared source-time `TMP_DIR`-derived state such as `PADM_SUBSCRIPTION_GROUPS_DIR`, and some leaves explicitly removed that shared directory during setup

At the `all` layer, UI child concurrency defaults are controlled separately from the top-level slot count.

### Routing

`routing` uses compat wrappers that re-source `subscription_groups_legacy.sh` inside a subshell before each legacy-backed leaf. This isolates source-time state such as `readInstallType`.

It supports two modes:

- flat selector-parallel mode
- resource-profile layering with:
  1. core
  2. heavy
  3. light

Profile mode is enabled by:

- `PADM_REGRESSION_ROUTING_RESOURCE_PROFILE=all`

Important limits:

- `PADM_REGRESSION_ROUTING_PARALLEL_JOBS`
- `PADM_REGRESSION_ROUTING_WAVE_PARALLEL_JOBS`
- `PADM_REGRESSION_ROUTING_LIGHT_PARALLEL_JOBS`

### Runtime

`runtime` also supports a profile split:

- light wave:
  - `runtime-core`
  - `runtime-autoread-unset-auto-install`
  - `runtime-auto-install-reality-route`
  - `runtime-tempdir`
- heavy wave:
  - `reality-candidates`
  - `reality-config`

Profile mode is enabled by:

- `PADM_REGRESSION_RUNTIME_RESOURCE_PROFILE=all`

Limits:

- `PADM_REGRESSION_RUNTIME_LIGHT_PARALLEL_JOBS`
- `PADM_REGRESSION_RUNTIME_HEAVY_PARALLEL_JOBS`

Compatibility boundary:

- the direct runtime leaves registered in the suite now all run through
  `runRegressionRuntimeLegacyLeafWithCompat`
- that includes:
  - `runtime-core`
  - `runtime-autoread-unset-auto-install`
  - `runtime-auto-install-reality-route`
  - `runtime-tempdir`
- the wrapper re-sources `subscription_groups_legacy.sh` in a subshell before each
  leaf so later suite loads cannot leave source-time `TMP_DIR`-derived paths stale
- the heavier `reality-candidates` and `reality-config` children still route through
  the dedicated reality suite boundary rather than duplicating reality leaf ownership

### Reality

`reality-candidates` and `reality-stream` remain sequential aggregate runners.
Their suite roots now dispatch ordered children through
`runFrameworkSequentialRegressionSelectorList`, keeping the aggregate-runner shell
stable while removing local `runRegressionStep` chains. They are already registered in
the selector framework, but they are not yet layered further.

### TLS

`tls` remains a sequential aggregate runner.

Its suite root now also uses `runFrameworkSequentialRegressionSelectorList` to dispatch:

- `tls-failure-return`
- `tls-reinstall-rollback`
- `tls-renew-failure-propagation`

That keeps the public selector topology unchanged while moving another straight-line
suite root onto the shared framework helper.

### Remote Control

`remote-control` now uses selector registration plus framework selector-list orchestration for the suite root.

The top-level suite root fans out through a suite-local selector runner over:

- `smoke`
- `contract`
- `deep`

Nested public aggregates include:

- `remote-control-smoke`
- `remote-control-contract`
- `remote-control-contract-service-install`

Important boundary:

- the top-level suite root now uses `runFrameworkParallelRegressionSelectorList`
- nested public aggregates inside `subscription_groups_remote_control.sh` now also use suite-local selector-list helpers plus `runFrameworkParallelRegressionSelectorList`
- the suite-local selector runner still preserves source-only compatibility for the legacy-backed helper tree while keeping orchestration on framework primitives
- legacy-backed direct leaves now also run through isolated compat wrappers that re-source `subscription_groups_remote_control.sh` in a subshell before each leaf
- this isolates source-time `TMP_DIR`-derived globals such as `SUBSCRIBE_CAPTURE_DIR`, `configPath`, and `singBoxConfigPath`

### Subscription State

`subscription-state` now uses framework selector-list orchestration for both its suite root and core subtree.

The current top-level shape is:

- `subscription-state-core`
- `subscription-state-support`
- `subscription-state-sync-rollback`

The core subtree fans out through selector-list orchestration over:

- `subscription-state-structure`
- `subscription-state-quota`
- `subscription-state-remote-restore`

Those nested public aggregates now also live in the suite layer instead of the legacy-backed full script:

- `subscription-state-structure-foundation`
- `subscription-state-structure`
- `subscription-state-quota`
- `subscription-state-remote-restore`
- `subscription-state-sync-rollback`

The legacy-backed full script now keeps the leaf implementations plus the support and serial helper chains, while suite-local isolated wrappers own the nested selector topology and framework orchestration.

The suite already has composition coverage proving parallel isolation for:

- structure subtree
- remote restore subtree
- sync rollback subtree

## All-Suite Resource Scheduling

`shell/regression/suites/all.sh` is the top-level resource-aware scheduler.

Current default top-level slot budget:

- `PADM_REGRESSION_ALL_PARALLEL_JOBS:-5`

The first top-level wave now runs through a suite-local selector list helper plus framework selector-list orchestration:

- `listRegressionAllParallelChildSelectors`
- `runFrameworkParallelRegressionSelectorList`

The current first-wave selector list is:

- `subscription`
- `ui`
- `transaction-core`
- `routing`
- `runtime`
- `remote-control-smoke`
- `remote-control-contract-service-install`

Because the slot budget is `5`, the initial first wave is effectively the first five selectors that fit:

- `subscription`
- `ui`
- `transaction-core`
- `routing`
- `runtime`

After that wave drains enough capacity, lighter remote-control selectors can run. Two serial tail steps remain intentionally explicit:

- `transaction-system`
- `remote-control-contract-server-response`

This protects the machine from stacking every heavy child suite at once while still keeping the front wave broad.

Important boundary:

- `all` now uses `runFrameworkParallelRegressionSelectorList` for the first wave instead of manually listing selectors through `runFrameworkParallelRegressionSelectors`
- the top-level resource semantics do not change with that refactor:
  - first-wave slot budget stays `5`
  - the selector order stays `subscription -> ui -> transaction-core -> routing -> runtime -> remote-control-smoke -> remote-control-contract-service-install`
  - `transaction-system` and `remote-control-contract-server-response` remain explicit serial tail steps

### Child Budgets Forwarded by `all`

Default forwarded child budgets:

- `PADM_REGRESSION_ALL_CHILD_PARALLEL_JOBS:-2`
- `PADM_REGRESSION_ALL_UI_CHILD_PARALLEL_JOBS:-3`
- `PADM_REGRESSION_ALL_SUBSCRIPTION_CHILD_PARALLEL_JOBS:-2`
- `PADM_REGRESSION_ALL_TRANSACTION_SYSTEM_CHILD_PARALLEL_JOBS:-4`
- `PADM_REGRESSION_ALL_TRANSACTION_CORE_CHILD_PARALLEL_JOBS:-3`
- `PADM_REGRESSION_ALL_ROUTING_CHILD_PARALLEL_JOBS:-1`
- `PADM_REGRESSION_ALL_RUNTIME_CHILD_PARALLEL_JOBS:-1`
- `PADM_REGRESSION_ALL_LIGHT_CHILD_PARALLEL_JOBS:-1`

Default forwarded resource profiles:

- `PADM_REGRESSION_ALL_UI_RESOURCE_PROFILE:-all`
- `PADM_REGRESSION_ALL_SUBSCRIPTION_RESOURCE_PROFILE:-all`
- `PADM_REGRESSION_ALL_TRANSACTION_CORE_RESOURCE_PROFILE:-`
- `PADM_REGRESSION_ALL_ROUTING_RESOURCE_PROFILE:-`
- `PADM_REGRESSION_ALL_RUNTIME_RESOURCE_PROFILE:-`

The intent is:

- keep top-level breadth at five slots
- let UI and subscription keep their profile-aware wave splits by default
- keep routing and runtime conservative inside `all`
- keep transaction-system parallel internally, but not in the first top-level wave

## Legacy Compatibility Boundary

Legacy regression code still exists, but it has been demoted to fixture and leaf-function ownership rather than dispatch ownership.

Current boundary:

- legacy files are source-only inputs for suite wrappers
- suite files own selector registration
- dispatcher owns entrypoint behavior
- direct invocation of `shell/regression/subscription_groups_legacy.sh` and `shell/regression/subscription_groups_remote_control.sh` now prints a redirect hint and exits `2`

Active compat wrapper patterns:

- `subscription.sh`
- `routing.sh`
- `platform.sh`
- `reality.sh`
- `remote_control.sh`
- `tls.sh`
- `runtime.sh`
- `transaction.sh`
- `ui.sh`

These wrappers intentionally re-source legacy or fast bootstrap files inside an isolated subshell before calling old leaf runners. The pattern exists because some source files mutate globals and source-time paths such as:

- `TMP_DIR`
- `readInstallType`-dependent state
- fixture helper function bindings
- `PADM_SUBSCRIPTION_GROUPS_DIR`

The platform suite now uses both sides of that pattern:

- fast-backed wrappers for `platform-hot` and the public `platform` root
- legacy-backed wrappers for `platform-io`

## Contracts and Verification Strategy

The regression harness now defends its structure with contract tests in:

- `shell/regression/suites/contracts.sh`

Contract coverage includes:

- dispatcher contract
- dispatcher step coverage guards
- selector registration shape
- legacy retirement guards
- shared helper-adoption guards for repeated contract shapes
- aggregate-runner registration expectations
- wrapper and child-step ordering guards
- parallel composition behavior
- child budget forwarding
- resource-layer ordering

Common helpers now cover most repeated contract shapes:

- `runRegressionStepSequenceAssertions`
- `runRegressionDispatcherStepCoverageAssertions`
- `runContractHelperAdoptionAssertions`
- `runAggregateRunnerRegistrationAssertions`
- `runRegisteredChildSelectorsAlignedAssertions`
- `runAggregateRunnerDispatchesChildrenInOrderAssertions`

These helpers intentionally stop at fully repeated or single-hit shapes. Wrapper-order guards, multi-hit assertions such as `runRealitySuiteChildStepsContract`, and suite-specific legacy-public checks remain explicit where that keeps intent clearer.

Representative composition checks already exist for:

- `fast`
- `platform-hot`
- `subscription`
- `subscription-output`
- `subscription-remote`
- `subscription-tx`
- `transaction-core`
- `transaction-system`
- `ui`
- `routing`
- `runtime`
- `all`

Recommended verification set for future harness changes:

1. `bash -n shell/subscription_groups_regression.sh`
2. `bash -n shell/regression/framework/runtime.sh shell/regression/framework/registry.sh`
3. targeted composition selectors for touched suites
4. `shell/subscription_groups_regression.sh regression-dispatcher-contract`
5. `shell/subscription_groups_regression.sh regression-all-composition`
6. `shell/subscription_groups_regression.sh regression-all-child-parallel-budget-composition`
7. `shell/subscription_groups_regression.sh regression-all-resource-layer-composition`
8. `git diff --check`

## Implemented Milestones

Already landed in this branch:

- `6b1be39` `refactor: dedupe helper adoption contracts`
- `ebd8a09` `refactor: dedupe dispatcher step coverage contracts`
- `81b8b45` `test: restore subscription-state cli retirement dispatcher guard`
- `fc0fff2` `refactor: dedupe subscription-state cli retirement checks`
- `820ba2f` `refactor: batch ui legacy wrapper retirement checks`
- `ae071dc` `refactor: extend legacy retirement helper rollout`
- `e9ed787` `refactor: dedupe legacy retirement assertions`
- `eb11a60` `refactor: dedupe aggregate runner order assertions`
- `b641ba6` `refactor: dedupe registered selector alignment contracts`
- `632f723` `refactor: dedupe dispatcher contract helper definitions`
- `6e43f06` `refactor: route all selector wave through selector list`
- `6bf295c` `refactor: route ui selector waves through selector lists`
- `452f838` `refactor: route transaction selector waves through selector lists`

- `2926d71` `perf: split subscription output regression layers`
- `f7ae91f` `refactor: layer fast regression selectors`
- `98d901e` `refactor: isolate platform hot regression leaves`
- `4233536` `refactor: retire empty legacy script-leaf shim`
- `31f7678` `refactor: retire script regression selectors`
- `717ecf4` `refactor: retire legacy internal cli regression paths`
- `21ab955` `refactor: inline remaining regression leaf registrations`
- `93d07bd` `refactor: route remote control suite through selector helper`
- `32fe720` `refactor: route subscription state suites through selector helper`
- `9110545` `refactor: route remote control nested aggregates through selector helper`
- `43da388` `refactor: route ui nested aggregates through selector lists`
- `4258e33` `refactor: isolate ui legacy leaf state`
- `306d949` `refactor: isolate reality suite selector helpers`
- `5d2dac0` `test: guard pre-legacy suite helper collisions`
- `ae69d33` `refactor: finish selector retirement helper rollout`
- `b76d6c1` `refactor: finish aggregate registration helper rollout`
- `aa79eec` `refactor: dedupe suite-local helper contracts`
- `8c4ba82` `refactor: dedupe framework helper contracts`
- `9eb8ced` `refactor: dedupe layered framework helper contracts`
- `a0f1222` `refactor: dedupe ui framework helper contract`
- `9565ff4` `refactor: localize subscription selector helpers`
- `364d9f3` `refactor: guard routing compat contracts`
- `d3a5c75` `refactor: guard subscription-state support steps`
- `07ed432` `refactor: guard subscription-state serial steps`
- `91e022a` `refactor: move subscription-state nested topology into suite`
- `6f4f141` `refactor: guard remote control smoke core steps`
- `c81bcd7` `refactor: guard platform refresh steps`
- `6814252` `refactor: guard fast auto install steps`
- `40fd32e` `refactor: guard fast output rest steps`
- `86bf29e` `refactor: guard fast core steps`
- `8edde82` `refactor: guard fast safety steps`
- `8f36627` `refactor: guard platform rest steps`
- `57196d9` `refactor: guard platform update steps`
- `f8754d3` `refactor: guard reality suite steps`
- `1baf3dc` `refactor: guard runtime suite steps`
- `4ef5932` `refactor: guard platform io steps`
- `b020cef` `refactor: guard tls suite steps`
- `924ebd5` `refactor: guard transaction subscription steps`
- `b8c6402` `refactor: guard targeted batch helper steps`
- `7a46d83` `refactor: guard subscription output wrapper steps`
- `a43c112` `refactor: guard transaction suite wrapper steps`
- `f1e39b0` `refactor: guard all suite wrapper steps`
- `1d36d7a` `refactor: dedupe child step contract assertions`

Together these commits establish the current harness direction:

- framework-first dispatch
- selector-owned suite topology
- targeted legacy compat wrappers
- resource-aware layered parallelism
- shared contract helpers for repeated framework invariants, dispatcher-step inclusion checks, helper-adoption checks, and repeated child-step sequences
- source-order guards where pre-legacy suite loads can silently collide with legacy names
- explicit wrapper-order guards where public suite roots still mix aggregate calls with serial tail steps

## Remaining Cleanup Opportunities

The current structure is usable, but there is still cleanup headroom.

Most likely next steps:

1. keep reviewing legacy-backed suites for source-time global drift and add compat wrappers only where concrete collisions are proven
2. decide whether nested aggregates still living inside legacy-backed scripts should also be lifted onto selector-list orchestration, or intentionally remain local runner groups
3. keep trimming contract duplication only where a cross-suite assertion shape is still materially repeated; aggregate-runner, helper-dispatch, registered-child alignment, child-order, dispatcher-step coverage, helper-adoption, and straight-line child-step invariants now already sit behind common helpers, so mixed wrapper-order, multi-hit, and suite-specific selector-retirement contracts should stay explicit unless a truly repeated shape emerges
4. keep checking legacy-backed suites for source-time state that is initialized from bootstrap exports and later mutated or deleted inside leaf setup; the UI `PADM_SUBSCRIPTION_GROUPS_DIR` collision and remote-control `SUBSCRIBE_CAPTURE_DIR` / `configPath` / `singBoxConfigPath` drift are the current examples of that failure mode
5. refresh this design snapshot whenever a suite root, resource-profile boundary, compat boundary, or contract-helper boundary changes, so the spec remains an authoritative map instead of a historical note

Deferred on purpose:

- removing legacy leaf function implementations
- merging unrelated suite refactors into the dispatcher work
- changing regression semantics just to make the registry cleaner

## Decision Record

Key decisions captured by the current implementation:

1. keep one public dispatcher and many suite-owned selector trees
2. prefer aggregate runners over legacy case labels
3. split long tails where timing gains are material, but keep leaf coverage unchanged
4. forward child concurrency budgets from `all` instead of letting every nested suite fully fan out
5. use isolated compat wrappers when legacy source-time globals make shared sourcing unsafe
6. prefer shared contract assertion helpers for repeated framework invariants, dispatcher-step coverage checks, single-helper adoption checks, and fully repeated child-step sequences, but leave wrapper-order expectations and multi-hit suite-specific contracts explicit when abstraction would hide intent

That is the intended baseline for the next round of regression time work.
