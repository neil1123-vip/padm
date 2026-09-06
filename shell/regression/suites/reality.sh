#!/usr/bin/env bash

listRegressionRealitySuiteCandidatesChildSelectors() {
    printf '%s\n' \
        reality-candidates-fast \
        reality-asn-scan-plan \
        reality-candidates-full
}

registerRegressionFunctionLeaf reality-candidates-fast runRealityCandidateFastRegression
registerRegressionFunctionLeaf reality-asn-scan-plan runRealityAsnScanPlanRegression
registerRegressionFunctionLeaf reality-candidates-full runRealityCandidateFullRegression
registerRegressionFunctionLeaf reality-profile-failure runRealityProfileFailureRegression

listRegressionRealityConfigChildSelectors() {
    printf '%s\n' \
        reality-config-vless-encryption \
        reality-config-scanner \
        reality-config-blocked-transaction \
        reality-config-unified-library-rollback \
        reality-config-apply \
        reality-config-change-reload-failure \
        reality-config-change-subscription-refresh-failure \
        reality-config-xhttp-download-settings \
        reality-config-refresh-subscription \
        reality-config-controlled-refresh \
        reality-config-import-skip
}

runRealityConfigParallelChildRegressionIsolatedSelector() (
    local selector=$1
    local isolatedRoot="${TMP_DIR}/reality-config-${selector}"

    unset PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER
    unset PADM_REGRESSION_PARALLEL_SELECTOR_MODE
    TMP_DIR="${isolatedRoot}"
    TMPDIR="${isolatedRoot}/tmp"
    PADM_CLEANUP_PATHS=()
    padmRegisterCleanupPath "${TMP_DIR}"
    configPath="${isolatedRoot}/xray-conf/"
    singBoxConfigPath="${isolatedRoot}/sing-box-conf/"
    nginxConfigPath="${isolatedRoot}/nginx/"
    REALITY_TLS_PING_ARGS_FILE="${isolatedRoot}/tls_ping_args.txt"
    export TMPDIR PADM_SUBSCRIPTION_GROUPS_DIR="${isolatedRoot}/groups" \
        PADM_REALITY_TARGET_CANDIDATES_FILE="${isolatedRoot}/reality_candidates.tsv" \
        PADM_REALITY_TARGET_RESULTS_FILE="${isolatedRoot}/reality_results.tsv" \
        PADM_REALITY_TARGET_SCAN_FILE="${isolatedRoot}/reality_results.tsv" \
        PADM_REALITY_TARGET_BLOCKED_FILE="${isolatedRoot}/reality_blocked.tsv" \
        PADM_VLESS_ENCRYPTION_STATE_FILE="${isolatedRoot}/vless_encryption.json" \
        PADM_ACCESS_CONTROL_BACKUP_DIR="${isolatedRoot}/access_control_backup" \
        REALITY_TLS_PING_ARGS_FILE
    mkdir -p "${TMP_DIR}" "${TMPDIR}" "${PADM_SUBSCRIPTION_GROUPS_DIR}" \
        "${configPath}" "${singBoxConfigPath}" "${nginxConfigPath}"

    case "${selector}" in
    reality-config-vless-encryption) runRealityConfigVlessEncryptionRegression ;;
    reality-config-scanner) runRealityConfigScannerRegression ;;
    reality-config-blocked-transaction) runRealityBlockedCandidateTransactionRegression ;;
    reality-config-unified-library-rollback) runRealityUnifiedLibraryRollbackRegression ;;
    reality-config-apply) runRealityConfigApplyRegression ;;
    reality-config-change-reload-failure) runRealityConfigChangeReloadFailureRegression ;;
    reality-config-change-subscription-refresh-failure) runRealityConfigChangeSubscriptionRefreshFailureRegression ;;
    reality-config-xhttp-download-settings) runXHTTPDownloadSettingsRegression ;;
    reality-config-refresh-subscription) runRealityConfigRefreshSubscriptionRegression ;;
    reality-config-controlled-refresh) runRealityConfigControlledRefreshRegression ;;
    reality-config-import-skip) runRealityConfigImportSkipRegression ;;
    *) return 2 ;;
    esac
)

runRealityConfigParallelSuiteRoot() {
    PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_REALITY_CONFIG_CHILD_PARALLEL_JOBS:-4}" \
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/reality-config-parallel-${BASHPID:-$$}" \
            listRegressionRealityConfigChildSelectors
}

registerRegressionFunctionLeaf reality-config-vless-encryption runRealityConfigParallelChildRegressionIsolatedSelector reality-config-vless-encryption
registerRegressionFunctionLeaf reality-config-scanner runRealityConfigParallelChildRegressionIsolatedSelector reality-config-scanner
registerRegressionFunctionLeaf reality-config-blocked-transaction runRealityConfigParallelChildRegressionIsolatedSelector reality-config-blocked-transaction
registerRegressionFunctionLeaf reality-config-unified-library-rollback runRealityConfigParallelChildRegressionIsolatedSelector reality-config-unified-library-rollback
registerRegressionFunctionLeaf reality-config-apply runRealityConfigParallelChildRegressionIsolatedSelector reality-config-apply
registerRegressionFunctionLeaf reality-config-change-reload-failure runRealityConfigParallelChildRegressionIsolatedSelector reality-config-change-reload-failure
registerRegressionFunctionLeaf reality-config-change-subscription-refresh-failure runRealityConfigParallelChildRegressionIsolatedSelector reality-config-change-subscription-refresh-failure
registerRegressionFunctionLeaf reality-config-xhttp-download-settings runRealityConfigParallelChildRegressionIsolatedSelector reality-config-xhttp-download-settings
registerRegressionFunctionLeaf reality-config-refresh-subscription runRealityConfigParallelChildRegressionIsolatedSelector reality-config-refresh-subscription
registerRegressionFunctionLeaf reality-config-controlled-refresh runRealityConfigParallelChildRegressionIsolatedSelector reality-config-controlled-refresh
registerRegressionFunctionLeaf reality-config-import-skip runRealityConfigParallelChildRegressionIsolatedSelector reality-config-import-skip

registerRegressionAggregateRunner parallel reality-config runRealityConfigParallelSuiteRoot \
    $(listRegressionRealityConfigChildSelectors)

registerRegressionSequentialSelectorList reality-candidates listRegressionRealitySuiteCandidatesChildSelectors
