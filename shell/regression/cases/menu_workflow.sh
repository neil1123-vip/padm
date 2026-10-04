#!/usr/bin/env bash

runSubscriptionMenuWorkflowRegression() (
    source "${PROJECT_ROOT}/shell/core/runtime.sh"
    source "${PROJECT_ROOT}/shell/subscription/groups.sh"
    source "${PROJECT_ROOT}/shell/subscription/menu.sh"
    local root="${TMP_DIR}/subscription-menu-workflow"
    local displayLog="${root}/display.log"
    local errorLog="${root}/errors.log"
    local statusLog="${root}/status.log"
    export PADM_SUBSCRIPTION_GROUPS_DIR="${root}/groups"
    unset AUTO_INSTALL
    mkdir -p "${PADM_SUBSCRIPTION_GROUPS_DIR}"
    writeDefaultSubscriptionGroupsState "$(subscriptionGroupsFile)"
    addSubscriptionSourceState edge "Edge" 203.0.113.20 39778
    addUserSubscriptionState 2 "Numeric ID" '["edge"]' 5
    addUserSubscriptionState alpha "Alpha" '["main"]' 0
    setSubscriptionGroupSyncEnabled false

    echoContent() { printf '%s\n' "$*" >>"${displayLog}"; }
    userResultCard() { printf '%s\n' "$*" >>"${displayLog}"; }
    menuLine() { printf '%s\n' "$*" >>"${displayLog}"; }
    menuItem() { printf '%s\n' "$*" >>"${displayLog}"; }
    menuDangerItem() { printf '%s\n' "$*" >>"${displayLog}"; }
    menuReturnItem() { printf '%s\n' "$*" >>"${displayLog}"; }
    menuClose() { :; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    statusCard() { printf '%s\n' "$*" >>"${statusLog}"; }
    warnCard() { printf '%s\n' "$*" >>"${statusLog}"; }
    successCard() { :; }
    subscriptionRequireLocalPublisherRole() { return 0; }
    subscriptionCurrentRoleNormalized() { printf 'uninitialized\n'; }

    (
        local readLog="${root}/reads.log"
        : >"${readLog}"
        eval "$(declare -f subscriptionActiveGroupRead | sed '1s/^subscriptionActiveGroupRead/originalSubscriptionActiveGroupRead/')"
        subscriptionActiveGroupRead() {
            printf 'read\n' >>"${readLog}"
            originalSubscriptionActiveGroupRead "$@"
        }
        selectUserSubscriptionId <<<2
        [[ "${selectedUserSubscriptionId}" == "alpha" ]]
        selectUserSubscriptionId <<<id:2
        [[ "${selectedUserSubscriptionId}" == "2" ]]
        selectUserSubscriptionId <<<alpha
        [[ "${selectedUserSubscriptionId}" == "alpha" ]]
        selectUserSubscriptionId <<< $'missing\n02'
        [[ "${selectedUserSubscriptionId}" == "alpha" ]]
        selectedUserSubscriptionId=stale
        regressionExpectStatus 1 selectUserSubscriptionId </dev/null
        [[ -z "${selectedUserSubscriptionId}" ]]
        [[ "$(wc -l <"${readLog}")" == "5" ]]
        [[ -s "${errorLog}" ]]
    )

    (
        local selectedSources= before sourceId=stale sourcesJson
        sourcesJson=$(subscriptionActiveGroupRead -c '[.sources[] | select(.role != "main")]')
        selectSubscriptionSourceId "${sourcesJson}" "选择被控:" sourceId <<< $'missing\n1'
        [[ "${sourceId}" == "edge" ]]
        regressionExpectStatus 1 selectSubscriptionSourceId "${sourcesJson}" "选择被控:" sourceId </dev/null
        [[ -z "${sourceId}" ]]
        selectUserSubscriptionSources user_subscription_sources "选择来源:" selectedSources '["edge"]' <<<""
        [[ "${selectedSources}" == '["edge"]' ]]
        selectUserSubscriptionSources user_subscription_sources "选择来源:" selectedSources <<<1,2
        jq -e 'sort == ["edge","main"]' <<<"${selectedSources}" >/dev/null
        selectUserSubscriptionSources user_subscription_sources "选择来源:" selectedSources <<< $'99\n2'
        [[ "${selectedSources}" == '["edge"]' ]]
        selectUserSubscriptionSources user_subscription_sources "选择来源:" selectedSources <<<'*'
        [[ "${selectedSources}" == '["*"]' ]]

        runUserSubscriptionMutationAndSyncUnlocked() { return 99; }
        setUserSubscriptionSourcesMenu 2 <<<""
        setUserSubscriptionTrafficLimitMenu 2 <<<""
        before=$(subscriptionGroupsStateRead -c '.user_groups')
        regressionExpectStatus 1 setUserSubscriptionSourcesMenu 2 </dev/null
        regressionExpectStatus 1 setUserSubscriptionTrafficLimitMenu 2 </dev/null
        [[ "$(subscriptionGroupsStateRead -c '.user_groups')" == "${before}" ]]
        setUserSubscriptionTrafficLimitMenu 2 <<< $'wrong\n7'
        subscriptionActiveGroupRead -e '.user_groups[0].traffic_limit_gb == 7' >/dev/null
    )

    (
        local syncCount=0 syncStatus=0
        ensureSubscriptionServiceForSharedLinks() { return 1; }
        setSubscriptionGroupSyncEnabledWithCron() { return 99; }
        runSubscriptionGroupSync() {
            syncCount=$((syncCount + 1))
            return "${syncStatus}"
        }
        createAndSyncUserSubscriptionWizard <<< $'new-team\n1,2\n3'
        [[ "${syncCount}" == "1" ]]
        subscriptionActiveGroupRead -e '
          .sync.enabled == false and
          any(.user_groups[]; .id == "new-team" and .traffic_limit_gb == 3 and (.allowed_sources | sort) == ["edge","main"])
        ' >/dev/null
        syncStatus=1
        regressionExpectStatus 1 createAndSyncUserSubscriptionWizard <<< $'pending-team\n1\n0'
        [[ "${syncCount}" == "2" ]]
        userSubscriptionExists pending-team
        subscriptionActiveGroupRead -e '.sync.enabled == false' >/dev/null
        grep -q '已保存' "${statusLog}"
        local openedId=
        manageUserSubscriptionItem() { openedId=$1; }
        manageSharedSubscriptions <<< $'+\nretry-team\n1\n0\n\n'
        [[ "${openedId}" == "retry-team" ]]
        userSubscriptionExists retry-team
    )

    (
        local syncCount=0 publishCount=0
        ensureSubscriptionServiceForSharedLinks() { return 0; }
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        refreshSubscriptionLinks() { publishCount=$((publishCount + 1)); }
        setUserSubscriptionEnabled alpha false
        regressionExpectStatus 1 showUserSubscriptionLinks alpha
        [[ "${syncCount}" == "0" && "${publishCount}" == "0" ]]
        setUserSubscriptionEnabled alpha true
        showUserSubscriptionLinks alpha
        [[ "${syncCount}" == "1" && "${publishCount}" == "1" ]]
        showUserSubscriptionLinks alpha true
        [[ "${syncCount}" == "1" && "${publishCount}" == "2" ]]
        runSubscriptionGroupSync() {
            syncCount=$((syncCount + 1))
            setUserSubscriptionEnabled alpha false
        }
        regressionExpectStatus 1 showUserSubscriptionLinks alpha
        [[ "${syncCount}" == "2" && "${publishCount}" == "2" ]]
    )

    (
        local trafficId= mutationCount=0
        runUserSubscriptionMutationAndSyncUnlocked() {
            mutationCount=$((mutationCount + 1))
            return 1
        }
        showUserSubscriptionTraffic() { trafficId=$1; }
        manageUserSubscriptionItem alpha <<< $'5\n2\n7'
        [[ "${mutationCount}" == "1" && "${trafficId}" == "alpha" ]]
        trafficId=
        manageUserSubscriptionItem 2 <<< $'8\n2\n2\n7'
        [[ "${trafficId}" == "alpha" ]]
        trafficId=
        manageSharedSubscriptions <<< $'2\n2\n7\n\n'
        [[ "${trafficId}" == "alpha" ]]
    )
)
