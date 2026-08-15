#!/usr/bin/env bash

REGRESSION_TRANSACTION_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_TRANSACTION_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_TRANSACTION_SUITE_DIR}/../subscription_groups_legacy.sh" --reuse

runRegressionTransactionLegacyLeafWithCompat() (
    # Re-source legacy transaction-backed subscription fixtures in an isolated
    # subshell so later suite loads cannot leave source-time TMP_DIR globals stale.
    PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_TRANSACTION_SUITE_DIR}/../subscription_groups_legacy.sh"
    "$@"
)

listRegressionTransactionChildSelectors() {
    printf '%s\n' \
        transaction-core \
        transaction-subscription \
        transaction-system
}

listRegressionTransactionSubscriptionChildSelectors() {
    printf '%s\n' \
        cdn-address-write-transaction \
        subscribe-server-name \
        subscribe-nginx-config-write \
        subscribe-nginx-service-failure \
        subscribe-salt-write-transaction \
        subscribe-user-output-transaction \
        remove-user-subscription-menu-failure \
        user-subscription-menu-mutation-failure \
        remote-subscribe-snapshots
}

listRegressionTransactionCoreSelectorEntries() {
    printf '%s\n' \
        'light core-rollback-result-message' \
        'medium config-transaction' \
        'heavy core-port-file-transaction' \
        'light core-port-unsafe-config-dir' \
        'medium entry-helper-config' \
        'light check-port-open-nginx-directory-target' \
        'light alone-nginx-directory-target' \
        'light xray-reality-port-failure' \
        'light reality-profile-failure' \
        'light sing-box-reality-key-transaction' \
        'light core-template-return-failure' \
        'light core-template-managed-remove' \
        'light core-binary-install-copy-failure' \
        'light sing-box-cronet-rollback' \
        'light finalize-sing-box-rollback' \
        'light core-upgrade-directory-target' \
        'light legacy-core-upgrade-keeps-existing' \
        'light core-first-install-failure-clean' \
        'light core-first-install-commit-rollback' \
        'light core-install-unsafe-binary-path' \
        'light core-release-archive-unsafe-path' \
        'light core-release-archive-symlink-payload' \
        'light sing-box-download-artifacts-cleanup' \
        'light network-check-return-failure' \
        'light tls-failure-return' \
        'light tls-reinstall-rollback' \
        'medium tls-renew-failure-propagation' \
        'light service-queue-apply-propagation' \
        'heavy core-install-service-action-failure' \
        'light sing-box-merge-start-failure' \
        'medium sing-box-merge-config-transaction' \
        'light sing-box-uninstall-failure-propagation' \
        'light sing-box-uninstall-rejects-unsafe-config-path' \
        'light sing-box-managed-cleanup' \
        'light sing-box-protocol-reload-failure' \
        'light geo-update-reload-failure' \
        'light xray-geo-commit-rollback' \
        'light core-cleanup-failure-propagation' \
        'medium reload-core-propagation' \
        'medium sing-box-log-transaction'
}

listRegressionTransactionCoreSelectors() {
    local profile=${1:-default}
    local wave selector

    case "${profile}" in
    heavy)
        printf '%s\n' core-install-service-action-failure core-port-file-transaction
        return
        ;;
    medium)
        printf '%s\n' config-transaction entry-helper-config reload-core-propagation \
            sing-box-log-transaction sing-box-merge-config-transaction tls-renew-failure-propagation
        return
        ;;
    default | light) ;;
    *)
        printf 'unknown transaction-core selector profile: %s\n' "${profile}" >&2
        return 2
        ;;
    esac

    while read -r wave selector; do
        [[ -n "${selector}" ]] || continue
        if [[ "${profile}" == "default" || "${wave}" == "${profile}" ]]; then
            printf '%s\n' "${selector}"
        fi
    done < <(listRegressionTransactionCoreSelectorEntries)
}

listRegressionTransactionCoreChildSelectors() {
    listRegressionTransactionCoreSelectors default
}

listRegressionTransactionCoreHeavyChildSelectors() {
    listRegressionTransactionCoreSelectors heavy
}

listRegressionTransactionCoreMediumChildSelectors() {
    listRegressionTransactionCoreSelectors medium
}

listRegressionTransactionCoreLightChildSelectors() {
    listRegressionTransactionCoreSelectors light
}

listRegressionTransactionSystemChildSelectors() {
    printf '%s\n' \
        nginx-service-failure \
        nginx-service-refresh \
        uninstall-nginx-cleanup \
        clean-agent-nginx-managed-remove \
        fail2ban-managed-cleanup \
        fail2ban-apply-transaction \
        uninstall-wireguard-cleanup \
        wireguard-key-transaction \
        wireguard-control-safe-dir \
        warp-config-safe-dir \
        warp-config-file-cleanup \
        uninstall-service-stop-failure \
        clean-last-installation-failure \
        clean-last-installation-acme-home \
        clean-last-installation-acme-relative-home \
        alone-nginx-write-transaction \
        alone-nginx-update-transaction
}

runRegressionTransactionCoreSuiteRoot() {
    if [[ "${PADM_REGRESSION_TRANSACTION_CORE_RESOURCE_PROFILE:-}" == "all" ]]; then
        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_TRANSACTION_CORE_HEAVY_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-2}}" \
            runFrameworkParallelRegressionSelectorList "${TMP_DIR}/transaction-core-parallel-heavy-${BASHPID:-$$}" \
            listRegressionTransactionCoreHeavyChildSelectors

        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_TRANSACTION_CORE_MEDIUM_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-3}}" \
            runFrameworkParallelRegressionSelectorList "${TMP_DIR}/transaction-core-parallel-medium-${BASHPID:-$$}" \
            listRegressionTransactionCoreMediumChildSelectors

        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_TRANSACTION_CORE_LIGHT_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}" \
            runFrameworkParallelRegressionSelectorList "${TMP_DIR}/transaction-core-parallel-light-${BASHPID:-$$}" \
            listRegressionTransactionCoreLightChildSelectors
        return
    fi

    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/transaction-core-parallel-${BASHPID:-$$}" \
        listRegressionTransactionCoreChildSelectors
}

runRegressionTransactionSystemSuiteRoot() {
    PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_TRANSACTION_SYSTEM_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}" \
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/transaction-system-parallel-${BASHPID:-$$}" \
        listRegressionTransactionSystemChildSelectors
}

runRegressionTransactionLegacyTmpDirIsolationRegression() (
    set -euo pipefail
    local originalTmpDir="${TMP_DIR}"

    # Simulate later suite loads re-sourcing bootstrap and drifting TMP_DIR.
    source "${REGRESSION_TRANSACTION_SUITE_DIR}/../bootstrap.sh"
    [[ "${TMP_DIR}" != "${originalTmpDir}" ]]

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain subscribe-user-output-transaction
)

runRegressionTransactionCoreParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-transaction-core-parallel-composition.log"

    : >"${callLog}"

    runRegressionAllSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        if [[ "${selector}" == "core-rollback-result-message" ]]; then
            runFrameworkWaitForFile "${TMP_DIR}/config-transaction-started"
        elif [[ "${selector}" == "config-transaction" ]]; then
            : >"${TMP_DIR}/config-transaction-started"
        elif [[ "${selector}" == "core-install-service-action-failure" ]]; then
            if [[ -f "${TMP_DIR}/transaction-core-expect-heavy-concurrency" ]]; then
                runFrameworkWaitForFile "${TMP_DIR}/core-port-file-transaction-started"
                [[ -f "${TMP_DIR}/core-port-file-transaction-started" ]] || : >"${TMP_DIR}/transaction-core-heavy-concurrency-violation"
            fi
        elif [[ "${selector}" == "core-port-file-transaction" ]]; then
            : >"${TMP_DIR}/core-port-file-transaction-started"
        fi
        case "${selector}" in
        config-transaction | entry-helper-config | reload-core-propagation | sing-box-log-transaction | sing-box-merge-config-transaction | tls-renew-failure-propagation)
            if [[ -f "${TMP_DIR}/transaction-core-expect-profile-boundary" ]] &&
                { [[ ! -f "${TMP_DIR}/core-install-service-action-failure-finished" ]] || [[ ! -f "${TMP_DIR}/core-port-file-transaction-finished" ]]; }; then
                : >"${TMP_DIR}/transaction-core-wave-boundary-violation"
            fi
            ;;
        esac
        case "${selector}" in
        core-install-service-action-failure) : >"${TMP_DIR}/core-install-service-action-failure-finished" ;;
        core-port-file-transaction) : >"${TMP_DIR}/core-port-file-transaction-finished" ;;
        esac
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegressionTransactionCoreSuiteRoot

    runFrameworkAssertSelectorListLogged "${callLog}" listRegressionTransactionCoreChildSelectors
    awk '
        $0 == "core-rollback-result-message-start" { firstStart = NR }
        $0 == "config-transaction-start" { configStart = NR }
        $0 == "core-rollback-result-message-finish" { firstFinish = NR }
        END { exit !(firstStart && configStart && firstFinish && configStart < firstFinish) }
    ' "${callLog}"

    : >"${callLog}"
    rm -f \
        "${TMP_DIR}/core-port-file-transaction-started" \
        "${TMP_DIR}/core-install-service-action-failure-finished" \
        "${TMP_DIR}/core-port-file-transaction-finished" \
        "${TMP_DIR}/transaction-core-heavy-concurrency-violation" \
        "${TMP_DIR}/transaction-core-wave-boundary-violation"
    : >"${TMP_DIR}/transaction-core-expect-heavy-concurrency"
    : >"${TMP_DIR}/transaction-core-expect-profile-boundary"
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector PADM_REGRESSION_PARALLEL_JOBS=6 PADM_REGRESSION_TRANSACTION_CORE_RESOURCE_PROFILE=all runRegressionTransactionCoreSuiteRoot

    while IFS= read -r selector; do
        [[ -n "${selector}" ]] || continue
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done < <(
        listRegressionTransactionCoreHeavyChildSelectors
        listRegressionTransactionCoreMediumChildSelectors
    )
    [[ ! -f "${TMP_DIR}/transaction-core-heavy-concurrency-violation" ]]
    [[ ! -f "${TMP_DIR}/transaction-core-wave-boundary-violation" ]]

    : >"${callLog}"
    rm -f \
        "${TMP_DIR}/transaction-core-expect-heavy-concurrency" \
        "${TMP_DIR}/transaction-core-expect-profile-boundary" \
        "${TMP_DIR}/core-port-file-transaction-started" \
        "${TMP_DIR}/core-install-service-action-failure-finished" \
        "${TMP_DIR}/core-port-file-transaction-finished"
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector PADM_REGRESSION_TRANSACTION_CORE_RESOURCE_PROFILE=all PADM_REGRESSION_TRANSACTION_CORE_HEAVY_PARALLEL_JOBS=1 PADM_REGRESSION_TRANSACTION_CORE_MEDIUM_PARALLEL_JOBS=1 PADM_REGRESSION_TRANSACTION_CORE_LIGHT_PARALLEL_JOBS=1 runRegressionTransactionCoreSuiteRoot
    awk '
        $0 == "core-install-service-action-failure-finish" { serviceFinish = NR }
        $0 == "core-port-file-transaction-start" { portStart = NR }
        $0 == "core-port-file-transaction-finish" { portFinish = NR }
        $0 == "config-transaction-start" { configStart = NR }
        $0 == "config-transaction-finish" { configFinish = NR }
        $0 == "entry-helper-config-start" { entryStart = NR }
        END {
            exit !(serviceFinish && portStart && portFinish && configStart && configFinish && entryStart &&
                serviceFinish < portStart && portFinish < configStart && configFinish < entryStart)
        }
    ' "${callLog}"
)

runRegressionTransactionSystemParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-transaction-system-parallel-composition.log"

    : >"${callLog}"

    runRegressionAllSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        if [[ "${selector}" == "nginx-service-failure" ]]; then
            runFrameworkWaitForFile "${TMP_DIR}/fail2ban-apply-transaction-started"
        elif [[ "${selector}" == "fail2ban-apply-transaction" ]]; then
            : >"${TMP_DIR}/fail2ban-apply-transaction-started"
        fi
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector runRegressionTransactionSystemSuiteRoot

    while IFS= read -r selector; do
        [[ -n "${selector}" ]] || continue
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
        [[ "$(grep -c "^${selector}-start$" "${callLog}")" == "1" ]]
        [[ "$(grep -c "^${selector}-finish$" "${callLog}")" == "1" ]]
    done < <(listRegressionTransactionSystemChildSelectors)
    awk '
        $0 == "nginx-service-failure-start" { firstStart = NR }
        $0 == "fail2ban-apply-transaction-start" { fail2banStart = NR }
        $0 == "nginx-service-failure-finish" { firstFinish = NR }
        END { exit !(firstStart && fail2banStart && firstFinish && fail2banStart < firstFinish) }
    ' "${callLog}"

    : >"${callLog}"
    rm -f "${TMP_DIR}/fail2ban-apply-transaction-started"
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector PADM_REGRESSION_TRANSACTION_SYSTEM_PARALLEL_JOBS=1 runRegressionTransactionSystemSuiteRoot
    awk '
        $0 == "nginx-service-failure-finish" { firstFinish = NR }
        $0 == "uninstall-nginx-cleanup-start" { secondStart = NR }
        $0 == "uninstall-nginx-cleanup-finish" { secondFinish = NR }
        $0 == "clean-agent-nginx-managed-remove-start" { thirdStart = NR }
        END { exit !(firstFinish && secondStart && secondFinish && thirdStart && firstFinish < secondStart && secondFinish < thirdStart) }
    ' "${callLog}"
)

registerRegressionFunctionLeaf core-rollback-result-message runCoreRollbackResultMessageRegression
registerRegressionFunctionLeaf config-transaction runConfigTransactionRegression
registerRegressionFunctionLeaf core-port-file-transaction runCorePortFileTransactionRegression
registerRegressionFunctionLeaf core-port-unsafe-config-dir runCorePortRejectsUnsafeConfigDirRegression
registerRegressionFunctionLeaf entry-helper-config runEntryHelperConfigRegression
registerRegressionFunctionLeaf check-port-open-nginx-directory-target runCheckPortOpenNginxRejectsDirectoryTargetRegression
registerRegressionFunctionLeaf alone-nginx-directory-target runAloneNginxRejectsDirectoryTargetRegression
registerRegressionFunctionLeaf sing-box-managed-cleanup runSingBoxManagedCleanupRegression
registerRegressionFunctionLeaf xray-reality-port-failure runXrayRealityPortFailureRegression
registerRegressionFunctionLeaf sing-box-reality-key-transaction runSingBoxRealityKeyTransactionRegression
registerRegressionFunctionLeaf core-template-managed-remove runCoreTemplateManagedConfigRemovalRegression
registerRegressionFunctionLeaf core-template-return-failure runCoreTemplateReturnFailureRegression
registerRegressionFunctionLeaf core-binary-install-copy-failure runCoreBinaryInstallCopyFailureRegression
registerRegressionFunctionLeaf sing-box-cronet-rollback runSingBoxCronetRollbackRegression
registerRegressionFunctionLeaf finalize-sing-box-rollback runFinalizeSingBoxBinaryInstallRollbackRegression
registerRegressionFunctionLeaf service-queue-apply-propagation runServiceQueueApplyPropagationRegression
registerRegressionFunctionLeaf core-install-service-action-failure runCoreInstallServiceActionFailureRegression
registerRegressionFunctionLeaf sing-box-merge-start-failure runSingBoxMergeStartFailureRegression
registerRegressionFunctionLeaf sing-box-uninstall-rejects-unsafe-config-path runSingBoxUninstallRejectsUnsafeConfigPathRegression
registerRegressionFunctionLeaf sing-box-uninstall-failure-propagation runSingBoxUninstallFailurePropagationRegression
registerRegressionFunctionLeaf sing-box-protocol-reload-failure runSingBoxProtocolReloadFailureRegression
registerRegressionFunctionLeaf geo-update-reload-failure runGeoUpdateReloadFailureRegression
registerRegressionFunctionLeaf xray-geo-commit-rollback runXrayGeoCommitRollbackRegression
registerRegressionFunctionLeaf core-cleanup-failure-propagation runCoreCleanupFailurePropagationRegression
registerRegressionFunctionLeaf sing-box-log-transaction runSingBoxLogTransactionRegression
registerRegressionFunctionLeaf core-upgrade-directory-target runCoreUpgradeRejectsDirectoryTargetRegression
registerRegressionFunctionLeaf legacy-core-upgrade-keeps-existing runLegacyCoreUpgradeKeepsExistingBinaryRegression
registerRegressionFunctionLeaf core-first-install-failure-clean runCoreFirstInstallLeavesNoLiveArtifactsOnFailureRegression
registerRegressionFunctionLeaf core-install-unsafe-binary-path runCoreInstallRejectsUnsafeBinaryPathRegression
registerRegressionFunctionLeaf core-first-install-commit-rollback runCoreFirstInstallCommitFailureRollbackRegression
registerRegressionFunctionLeaf core-release-archive-unsafe-path runCoreReleaseArchiveRejectsUnsafePathRegression
registerRegressionFunctionLeaf core-release-archive-symlink-payload runCoreReleaseArchiveRejectsSymlinkPayloadRegression
registerRegressionFunctionLeaf sing-box-download-artifacts-cleanup runSingBoxDownloadArtifactsCleanupRegression
registerRegressionFunctionLeaf network-check-return-failure runNetworkCheckReturnFailureRegression
registerRegressionFunctionLeaf sing-box-merge-config-transaction runSingBoxMergeConfigTransactionRegression
registerRegressionFunctionLeaf reload-core-propagation runReloadCorePropagationRegression

registerRegressionFunctionLeaf regression-transaction-core-parallel-composition runRegressionTransactionCoreParallelCompositionRegression
registerRegressionFunctionLeaf regression-transaction-system-parallel-composition runRegressionTransactionSystemParallelCompositionRegression
registerRegressionFunctionLeaf regression-transaction-legacy-tmpdir-isolation runRegressionTransactionLegacyTmpDirIsolationRegression
registerRegressionFunctionLeaf cdn-address-write-transaction runRegressionTransactionLegacyLeafWithCompat runCdnAddressTransactionRegression
registerRegressionFunctionLeaf subscribe-server-name runRegressionTransactionLegacyLeafWithCompat runSubscribeServerNameRegression
registerRegressionFunctionLeaf subscribe-nginx-config-write runRegressionTransactionLegacyLeafWithCompat runSubscribeNginxConfigWriteRegression
registerRegressionFunctionLeaf subscribe-nginx-service-failure runRegressionTransactionLegacyLeafWithCompat runSubscribeNginxServiceFailureRegression
registerRegressionFunctionLeaf subscribe-salt-write-transaction runRegressionTransactionLegacyLeafWithCompat runSubscribeSaltWriteTransactionRegression
registerRegressionFunctionLeaf subscribe-user-output-transaction runRegressionTransactionLegacyLeafWithCompat runSubscribeUserOutputTransactionRegression
registerRegressionFunctionLeaf remove-user-subscription-menu-failure runRegressionTransactionLegacyLeafWithCompat runRemoveUserSubscriptionMenuFailureRegression
registerRegressionFunctionLeaf user-subscription-menu-mutation-failure runRegressionTransactionLegacyLeafWithCompat runUserSubscriptionMenuMutationFailureRegression
registerRegressionFunctionLeaf remote-subscribe-snapshots runRegressionTransactionLegacyLeafWithCompat runRemoteSubscribeSnapshotRegression
registerRegressionFunctionLeaf nginx-service-failure runNginxServiceFailureRegression
registerRegressionFunctionLeaf nginx-service-refresh runNginxServiceRefreshRegression
registerRegressionFunctionLeaf uninstall-nginx-cleanup runUninstallNginxCleanupRegression
registerRegressionFunctionLeaf clean-agent-nginx-managed-remove runCleanAgentNginxManagedRemovalRegression
registerRegressionFunctionLeaf fail2ban-managed-cleanup runFail2banManagedCleanupRegression
registerRegressionFunctionLeaf fail2ban-apply-transaction runFail2banApplyTransactionRegression
registerRegressionFunctionLeaf uninstall-wireguard-cleanup runUninstallWireGuardCleanupRegression
registerRegressionFunctionLeaf wireguard-key-transaction runWireGuardKeyTransactionRegression
registerRegressionFunctionLeaf wireguard-control-safe-dir runWireGuardControlSafeDirRegression
registerRegressionFunctionLeaf warp-config-safe-dir runWarpConfigSafeDirRegression
registerRegressionFunctionLeaf warp-config-file-cleanup runWarpConfigFileCleanupRegression
registerRegressionFunctionLeaf uninstall-service-stop-failure runUninstallServiceStopFailureRegression
registerRegressionFunctionLeaf clean-last-installation-failure runCleanLastInstallationConfigFailureRegression
registerRegressionFunctionLeaf clean-last-installation-acme-home runCleanLastInstallationConfigAcmeHomeFailureRegression
registerRegressionFunctionLeaf clean-last-installation-acme-relative-home runCleanLastInstallationConfigResolvesRelativeAcmeHomeRegression
registerRegressionFunctionLeaf alone-nginx-write-transaction runAloneNginxConfigWriteTransactionRegression
registerRegressionFunctionLeaf alone-nginx-update-transaction runAloneNginxUpdateTransactionRegression

registerRegressionAggregateRunner parallel transaction-system runRegressionTransactionSystemSuiteRoot \
    $(listRegressionTransactionSystemChildSelectors)

registerRegressionAggregateRunner parallel transaction-core runRegressionTransactionCoreSuiteRoot \
    $(listRegressionTransactionCoreChildSelectors)

registerRegressionSequentialSelectorList transaction-subscription listRegressionTransactionSubscriptionChildSelectors

registerRegressionSequentialSelectorList transaction listRegressionTransactionChildSelectors
