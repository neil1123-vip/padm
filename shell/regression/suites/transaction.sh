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
        'default light core-rollback-result-message' \
        'default medium config-transaction' \
        'default heavy core-port-file-transaction' \
        'default light core-port-unsafe-config-dir' \
        'default medium entry-helper-config' \
        'default light check-port-open-nginx-directory-target' \
        'default light alone-nginx-directory-target' \
        'default light xray-reality-port-failure' \
        'default light reality-profile-failure' \
        'default light sing-box-reality-key-transaction' \
        'default light core-template-return-failure' \
        'default light core-template-managed-remove' \
        'default light core-binary-install-copy-failure' \
        'default light sing-box-cronet-rollback' \
        'default light finalize-sing-box-rollback' \
        'default light core-upgrade-directory-target' \
        'default light legacy-core-upgrade-keeps-existing' \
        'default light core-first-install-failure-clean' \
        'default light core-first-install-commit-rollback' \
        'default light core-install-unsafe-binary-path' \
        'default light core-release-archive-unsafe-path' \
        'default light core-release-archive-symlink-payload' \
        'default light sing-box-download-artifacts-cleanup' \
        'default light network-check-return-failure' \
        'default light tls-failure-return' \
        'default light tls-reinstall-rollback' \
        'default medium tls-renew-failure-propagation' \
        'default light service-queue-apply-propagation' \
        'default heavy core-install-service-action-failure' \
        'default light sing-box-merge-start-failure' \
        'default medium sing-box-merge-config-transaction' \
        'default light sing-box-uninstall-failure-propagation' \
        'default light sing-box-uninstall-rejects-unsafe-config-path' \
        'default light sing-box-managed-cleanup' \
        'default light sing-box-protocol-reload-failure' \
        'default light geo-update-reload-failure' \
        'default light xray-geo-commit-rollback' \
        'default light core-cleanup-failure-propagation' \
        'default medium reload-core-propagation' \
        'default medium sing-box-log-transaction' \
        'default light user-config-write' \
        'default light remove-user' \
        'heavy heavy core-install-service-action-failure' \
        'heavy heavy core-port-file-transaction' \
        'medium medium config-transaction' \
        'medium medium entry-helper-config' \
        'medium medium reload-core-propagation' \
        'medium medium sing-box-log-transaction' \
        'medium medium sing-box-merge-config-transaction' \
        'medium medium tls-renew-failure-propagation' \
        'light light core-rollback-result-message' \
        'light light core-port-unsafe-config-dir' \
        'light light check-port-open-nginx-directory-target' \
        'light light alone-nginx-directory-target' \
        'light light xray-reality-port-failure' \
        'light light reality-profile-failure' \
        'light light sing-box-reality-key-transaction' \
        'light light core-template-return-failure' \
        'light light core-template-managed-remove' \
        'light light core-binary-install-copy-failure' \
        'light light sing-box-cronet-rollback' \
        'light light finalize-sing-box-rollback' \
        'light light core-upgrade-directory-target' \
        'light light legacy-core-upgrade-keeps-existing' \
        'light light core-first-install-failure-clean' \
        'light light core-first-install-commit-rollback' \
        'light light core-install-unsafe-binary-path' \
        'light light core-release-archive-unsafe-path' \
        'light light core-release-archive-symlink-payload' \
        'light light sing-box-download-artifacts-cleanup' \
        'light light network-check-return-failure' \
        'light light tls-failure-return' \
        'light light tls-reinstall-rollback' \
        'light light service-queue-apply-propagation' \
        'light light sing-box-merge-start-failure' \
        'light light sing-box-uninstall-failure-propagation' \
        'light light sing-box-uninstall-rejects-unsafe-config-path' \
        'light light sing-box-managed-cleanup' \
        'light light sing-box-protocol-reload-failure' \
        'light light geo-update-reload-failure' \
        'light light xray-geo-commit-rollback' \
        'light light core-cleanup-failure-propagation' \
        'light light user-config-write' \
        'light light remove-user'
}

listRegressionTransactionCoreSelectors() {
    local profile=${1:-default}
    local sourceProfile wave selector

    while read -r sourceProfile wave selector; do
        [[ -n "${selector}" ]] || continue
        if [[ "${sourceProfile}" != "${profile}" ]]; then
            continue
        fi
        case "${profile}" in
        default | heavy | medium | light)
            printf '%s\n' "${selector}"
            ;;
        *)
            printf 'unknown transaction-core selector profile: %s\n' "${profile}" >&2
            return 2
            ;;
        esac
    done < <(listRegressionTransactionCoreSelectorEntries)

    return 0
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
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${TMP_DIR}/config-transaction-started" ]] && break
                sleep 0.05
            done
        elif [[ "${selector}" == "config-transaction" ]]; then
            : >"${TMP_DIR}/config-transaction-started"
        elif [[ "${selector}" == "core-install-service-action-failure" ]]; then
            if [[ -f "${TMP_DIR}/transaction-core-expect-heavy-concurrency" ]]; then
                for _ in 1 2 3 4 5 6 7 8 9 10; do
                    [[ -f "${TMP_DIR}/core-port-file-transaction-started" ]] && break
                    sleep 0.05
                done
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
    runRegressionRealityLegacyLeafWithCompat() { "$@"; }
    runRegressionTlsLegacyLeafWithCompat() { "$@"; }
    runCoreRollbackResultMessageRegression() { runRegressionAllSelector core-rollback-result-message; }
    runConfigTransactionRegression() { runRegressionAllSelector config-transaction; }
    runCorePortFileTransactionRegression() { runRegressionAllSelector core-port-file-transaction; }
    runCorePortRejectsUnsafeConfigDirRegression() { runRegressionAllSelector core-port-unsafe-config-dir; }
    runEntryHelperConfigRegression() { runRegressionAllSelector entry-helper-config; }
    runCheckPortOpenNginxRejectsDirectoryTargetRegression() { runRegressionAllSelector check-port-open-nginx-directory-target; }
    runAloneNginxRejectsDirectoryTargetRegression() { runRegressionAllSelector alone-nginx-directory-target; }
    runXrayRealityPortFailureRegression() { runRegressionAllSelector xray-reality-port-failure; }
    runRealityProfileFailureRegression() { runRegressionAllSelector reality-profile-failure; }
    runSingBoxRealityKeyTransactionRegression() { runRegressionAllSelector sing-box-reality-key-transaction; }
    runCoreTemplateReturnFailureRegression() { runRegressionAllSelector core-template-return-failure; }
    runCoreTemplateManagedConfigRemovalRegression() { runRegressionAllSelector core-template-managed-remove; }
    runCoreBinaryInstallCopyFailureRegression() { runRegressionAllSelector core-binary-install-copy-failure; }
    runSingBoxCronetRollbackRegression() { runRegressionAllSelector sing-box-cronet-rollback; }
    runFinalizeSingBoxBinaryInstallRollbackRegression() { runRegressionAllSelector finalize-sing-box-rollback; }
    runCoreUpgradeRejectsDirectoryTargetRegression() { runRegressionAllSelector core-upgrade-directory-target; }
    runLegacyCoreUpgradeKeepsExistingBinaryRegression() { runRegressionAllSelector legacy-core-upgrade-keeps-existing; }
    runCoreFirstInstallLeavesNoLiveArtifactsOnFailureRegression() { runRegressionAllSelector core-first-install-failure-clean; }
    runCoreFirstInstallCommitFailureRollbackRegression() { runRegressionAllSelector core-first-install-commit-rollback; }
    runCoreInstallRejectsUnsafeBinaryPathRegression() { runRegressionAllSelector core-install-unsafe-binary-path; }
    runCoreReleaseArchiveRejectsUnsafePathRegression() { runRegressionAllSelector core-release-archive-unsafe-path; }
    runCoreReleaseArchiveRejectsSymlinkPayloadRegression() { runRegressionAllSelector core-release-archive-symlink-payload; }
    runSingBoxDownloadArtifactsCleanupRegression() { runRegressionAllSelector sing-box-download-artifacts-cleanup; }
    runNetworkCheckReturnFailureRegression() { runRegressionAllSelector network-check-return-failure; }
    runTlsFailureReturnRegression() { runRegressionAllSelector tls-failure-return; }
    runTlsReinstallRollbackRegression() { runRegressionAllSelector tls-reinstall-rollback; }
    runTlsRenewalFailurePropagationRegression() { runRegressionAllSelector tls-renew-failure-propagation; }
    runServiceQueueApplyPropagationRegression() { runRegressionAllSelector service-queue-apply-propagation; }
    runCoreInstallServiceActionFailureRegression() { runRegressionAllSelector core-install-service-action-failure; }
    runSingBoxMergeStartFailureRegression() { runRegressionAllSelector sing-box-merge-start-failure; }
    runSingBoxMergeConfigTransactionRegression() { runRegressionAllSelector sing-box-merge-config-transaction; }
    runSingBoxUninstallFailurePropagationRegression() { runRegressionAllSelector sing-box-uninstall-failure-propagation; }
    runSingBoxUninstallRejectsUnsafeConfigPathRegression() { runRegressionAllSelector sing-box-uninstall-rejects-unsafe-config-path; }
    runSingBoxManagedCleanupRegression() { runRegressionAllSelector sing-box-managed-cleanup; }
    runSingBoxProtocolReloadFailureRegression() { runRegressionAllSelector sing-box-protocol-reload-failure; }
    runGeoUpdateReloadFailureRegression() { runRegressionAllSelector geo-update-reload-failure; }
    runXrayGeoCommitRollbackRegression() { runRegressionAllSelector xray-geo-commit-rollback; }
    runCoreCleanupFailurePropagationRegression() { runRegressionAllSelector core-cleanup-failure-propagation; }
    runReloadCorePropagationRegression() { runRegressionAllSelector reload-core-propagation; }
    runSingBoxLogTransactionRegression() { runRegressionAllSelector sing-box-log-transaction; }
    runUserConfigWriteRegression() { runRegressionAllSelector user-config-write; }
    runRemoveUserRegression() { runRegressionAllSelector remove-user; }

    runRegressionTransactionCoreSuiteRoot

    while IFS= read -r selector; do
        [[ -n "${selector}" ]] || continue
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done < <(listRegressionTransactionCoreChildSelectors)
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
    PADM_REGRESSION_PARALLEL_JOBS=6 PADM_REGRESSION_TRANSACTION_CORE_RESOURCE_PROFILE=all runRegressionTransactionCoreSuiteRoot

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
    PADM_REGRESSION_TRANSACTION_CORE_RESOURCE_PROFILE=all PADM_REGRESSION_TRANSACTION_CORE_HEAVY_PARALLEL_JOBS=1 PADM_REGRESSION_TRANSACTION_CORE_MEDIUM_PARALLEL_JOBS=1 PADM_REGRESSION_TRANSACTION_CORE_LIGHT_PARALLEL_JOBS=1 runRegressionTransactionCoreSuiteRoot
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
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${TMP_DIR}/fail2ban-apply-transaction-started" ]] && break
                sleep 0.05
            done
        elif [[ "${selector}" == "fail2ban-apply-transaction" ]]; then
            : >"${TMP_DIR}/fail2ban-apply-transaction-started"
        fi
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }
    runNginxServiceFailureRegression() { runRegressionAllSelector nginx-service-failure; }
    runNginxServiceRefreshRegression() { runRegressionAllSelector nginx-service-refresh; }
    runUninstallNginxCleanupRegression() { runRegressionAllSelector uninstall-nginx-cleanup; }
    runCleanAgentNginxManagedRemovalRegression() { runRegressionAllSelector clean-agent-nginx-managed-remove; }
    runFail2banManagedCleanupRegression() { runRegressionAllSelector fail2ban-managed-cleanup; }
    runFail2banApplyTransactionRegression() { runRegressionAllSelector fail2ban-apply-transaction; }
    runUninstallWireGuardCleanupRegression() { runRegressionAllSelector uninstall-wireguard-cleanup; }
    runWireGuardKeyTransactionRegression() { runRegressionAllSelector wireguard-key-transaction; }
    runWireGuardControlSafeDirRegression() { runRegressionAllSelector wireguard-control-safe-dir; }
    runWarpConfigSafeDirRegression() { runRegressionAllSelector warp-config-safe-dir; }
    runWarpConfigFileCleanupRegression() { runRegressionAllSelector warp-config-file-cleanup; }
    runUninstallServiceStopFailureRegression() { runRegressionAllSelector uninstall-service-stop-failure; }
    runCleanLastInstallationConfigFailureRegression() { runRegressionAllSelector clean-last-installation-failure; }
    runCleanLastInstallationConfigAcmeHomeFailureRegression() { runRegressionAllSelector clean-last-installation-acme-home; }
    runCleanLastInstallationConfigResolvesRelativeAcmeHomeRegression() { runRegressionAllSelector clean-last-installation-acme-relative-home; }
    runAloneNginxConfigWriteTransactionRegression() { runRegressionAllSelector alone-nginx-write-transaction; }
    runAloneNginxUpdateTransactionRegression() { runRegressionAllSelector alone-nginx-update-transaction; }

    runRegressionTransactionSystemSuiteRoot

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
    PADM_REGRESSION_TRANSACTION_SYSTEM_PARALLEL_JOBS=1 runRegressionTransactionSystemSuiteRoot
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
registerRegressionFunctionLeaf user-config-write runUserConfigWriteRegression
registerRegressionFunctionLeaf remove-user runRemoveUserRegression
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

registerRegressionAggregateRunnerWithArgs sequential \
    transaction-subscription \
    runFrameworkSequentialRegressionSelectorList \
    listRegressionTransactionSubscriptionChildSelectors \
    -- \
    $(listRegressionTransactionSubscriptionChildSelectors)

registerRegressionAggregateRunnerWithArgs sequential \
    transaction \
    runFrameworkSequentialRegressionSelectorList \
    listRegressionTransactionChildSelectors \
    -- \
    $(listRegressionTransactionChildSelectors)
