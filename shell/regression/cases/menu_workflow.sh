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
        local selectedSources= sourceId=stale sourcesJson
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
    )

    (
        local syncCount=0 syncStatus=0 published=false serviceCount=0 linkCount=0
        ensureSubscriptionServiceForSharedLinks() { serviceCount=$((serviceCount + 1)); return 2; }
        syncAndShowSubscriptionLinks() { linkCount=$((linkCount + 1)); return 99; }
        setSubscriptionGroupSyncEnabledWithCron() { return 99; }
        runSubscriptionGroupSync() {
            syncCount=$((syncCount + 1))
            SUBSCRIPTION_SYNC_PUBLISHED=${published}
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
        [[ "${openedId}" == "retry-team" && "${syncCount}" == "3" ]]
        userSubscriptionExists retry-team
        published=true
        manageSharedSubscriptions <<< $'+\npartial-team\n1\n0\n\n'
        [[ "${openedId}" == "partial-team" && "${syncCount}" == "4" ]]
        userSubscriptionExists partial-team
        grep -q '首次同步部分失败但链接已发布' "${statusLog}"
        [[ "${serviceCount}" == "0" && "${linkCount}" == "0" ]]
    )

    (
        local syncCount=0 publishCount=0 publishedCount=0
        ensureSubscriptionServiceForSharedLinks() { return 0; }
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        subscribe() { publishCount=$((publishCount + 1)); return 99; }
        showPublishedSubscriptionLinks() { publishedCount=$((publishedCount + 1)); }
        setUserSubscriptionEnabled alpha false
        regressionExpectStatus 1 syncAndShowSubscriptionLinks alpha
        [[ "${syncCount}" == "0" && "${publishCount}" == "0" ]]
        setUserSubscriptionEnabled alpha true
        syncAndShowSubscriptionLinks alpha
        [[ "${syncCount}" == "1" && "${publishCount}" == "0" && "${publishedCount}" == "1" ]]
        syncAndShowSubscriptionLinks alpha
        [[ "${syncCount}" == "2" && "${publishCount}" == "0" && "${publishedCount}" == "2" ]]
        syncAndShowSubscriptionLinks
        [[ "${syncCount}" == "3" && "${publishCount}" == "0" && "${publishedCount}" == "3" ]]
        runSubscriptionGroupSync() {
            syncCount=$((syncCount + 1))
            SUBSCRIPTION_SYNC_PUBLISHED=true
            return 1
        }
        syncAndShowSubscriptionLinks alpha
        [[ "${syncCount}" == "4" && "${publishCount}" == "0" && "${publishedCount}" == "4" ]]
        syncAndShowSubscriptionLinks
        [[ "${syncCount}" == "5" && "${publishCount}" == "0" && "${publishedCount}" == "5" ]]
        runSubscriptionGroupSync() {
            syncCount=$((syncCount + 1))
            return 1
        }
        regressionExpectStatus 1 syncAndShowSubscriptionLinks alpha
        [[ "${syncCount}" == "6" && "${publishedCount}" == "5" ]]
        regressionExpectStatus 1 syncAndShowSubscriptionLinks
        [[ "${syncCount}" == "7" && "${publishedCount}" == "5" ]]
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        showPublishedSubscriptionLinks() { publishedCount=$((publishedCount + 1)); return 1; }
        regressionExpectStatus 1 syncAndShowSubscriptionLinks alpha
        [[ "${syncCount}" == "8" && "${publishCount}" == "0" && "${publishedCount}" == "6" ]]
        ensureSubscriptionServiceForSharedLinks() { return 1; }
        regressionExpectStatus 1 syncAndShowSubscriptionLinks alpha
        [[ "${syncCount}" == "8" && "${publishedCount}" == "6" ]]
    )

    (
        local publicBase="${root}/public" localBase="${root}/local"
        local linkLog="${root}/links.log" accountHash before personalHash disabledHash removedHash
        local serviceCount=0 syncCount=0 publishCount=0
        export PADM_SUBSCRIBE_DIR="${publicBase}" PADM_SUBSCRIBE_LOCAL_DIR="${localBase}"
        mkdir -p "${publicBase}/default" "${publicBase}/clashMetaProfiles" "${publicBase}/sing-box" "${localBase}/default"
        printf 'fixed-salt\n' >"${localBase}/subscribeSalt"
        accountHash=$(printf '%s\n' "$(subscriptionSyncAccountName alpha)fixed-salt" | md5sum | awk '{print $1}')
        readNginxSubscribe() { subscribeDomain=links.example.com; subscribeType=https; subscribePort=39778; }
        showSubscriptionUrlCard() { printf '%s\n' "$*" >>"${linkLog}"; }
        installSubscribe() { serviceCount=$((serviceCount + 1)); return 99; }
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); return 99; }
        subscribe() { publishCount=$((publishCount + 1)); return 99; }
        regressionExpectStatus 1 showPublishedSubscriptionLinks alpha
        regressionExpectStatus 1 showPublishedSubscriptionLinks
        printf 'published-default\n' >"${publicBase}/default/${accountHash}"
        printf 'published-clash\n' >"${publicBase}/clashMetaProfiles/${accountHash}"
        before=$(subscriptionGroupsStateRead -c '.')
        showPublishedSubscriptionLinks alpha
        grep -qF "https://links.example.com:39778/s/default/${accountHash}" "${linkLog}"
        grep -qF "https://links.example.com:39778/s/clashMetaProfiles/${accountHash}" "${linkLog}"
        [[ "$(wc -l <"${linkLog}")" == "2" && "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]

        personalHash=$(printf '%s\n' personalfixed-salt | md5sum | awk '{print $1}')
        disabledHash=$(printf '%s\n' "$(subscriptionSyncAccountName 2)fixed-salt" | md5sum | awk '{print $1}')
        removedHash=$(printf '%s\n' "$(subscriptionSyncAccountName removed)fixed-salt" | md5sum | awk '{print $1}')
        printf 'local-personal\n' >"${localBase}/default/personal"
        printf 'stale-disabled\n' >"${localBase}/default/$(subscriptionSyncAccountName 2)"
        printf 'stale-removed\n' >"${localBase}/default/$(subscriptionSyncAccountName removed)"
        printf 'personal-default\n' >"${publicBase}/default/${personalHash}"
        printf 'personal-sing-box\n' >"${publicBase}/sing-box/${personalHash}"
        printf 'disabled-output\n' >"${publicBase}/default/${disabledHash}"
        printf 'removed-output\n' >"${publicBase}/default/${removedHash}"
        setUserSubscriptionEnabled 2 false
        before=$(subscriptionGroupsStateRead -c '.')
        showPublishedSubscriptionLinks
        [[ "$(wc -l <"${linkLog}")" == "6" && "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        grep -qF "https://links.example.com:39778/s/default/${personalHash}" "${linkLog}"
        grep -qF "https://links.example.com:39778/s/sing-box/${personalHash}" "${linkLog}"
        ! grep -qF "${disabledHash}" "${linkLog}"
        ! grep -qF "${removedHash}" "${linkLog}"
        [[ "${serviceCount}" == "0" && "${syncCount}" == "0" && "${publishCount}" == "0" ]]
        [[ "$(<"${localBase}/subscribeSalt")" == "fixed-salt" ]]
        setUserSubscriptionEnabled alpha false
        regressionExpectStatus 1 showPublishedSubscriptionLinks alpha
        [[ "$(wc -l <"${linkLog}")" == "6" ]]
        showPublishedSubscriptionLinks
        [[ "$(wc -l <"${linkLog}")" == "8" ]]
        setUserSubscriptionEnabled alpha true
        ensureSubscriptionServiceForSharedLinks() { return 0; }
        runSubscriptionGroupSync() {
            syncCount=$((syncCount + 1))
            setUserSubscriptionEnabled alpha false
            SUBSCRIPTION_SYNC_PUBLISHED=true
        }
        regressionExpectStatus 1 syncAndShowSubscriptionLinks alpha
        [[ "${syncCount}" == "1" && "$(wc -l <"${linkLog}")" == "8" ]]
        subscriptionGroupsWithLock() {
            [[ "${PADM_SUBSCRIPTION_GROUPS_LOCK_TIMEOUT}" == "0" && "${PADM_SUBSCRIPTION_GROUPS_LOCK_SKIP_BUSY}" == "true" ]]
            SUBSCRIPTION_GROUPS_LOCK_SKIPPED=true
        }
        regressionExpectStatus 1 showPublishedSubscriptionLinks alpha
        regressionExpectStatus 1 showPublishedSubscriptionLinks
        [[ "$(wc -l <"${linkLog}")" == "8" ]]
        grep -qF "订阅正在同步或修改" "${statusLog}"
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

    (
        local viewedId= syncedId= editedIds=
        showPublishedSubscriptionLinks() { viewedId=$1; }
        syncAndShowSubscriptionLinks() { syncedId=$1; }
        editUserSubscriptionsMenu() { editedIds=$1; }
        manageUserSubscriptionItem alpha <<< $'1\n4\n3\n7'
        [[ "${viewedId}" == "alpha" && "${syncedId}" == "alpha" && "${editedIds}" == '["alpha"]' ]]
    )

    runSubscriptionMenuDraftRegression
)

runSubscriptionMenuDraftRegression() (
    source "${PROJECT_ROOT}/shell/core/runtime.sh"
    source "${PROJECT_ROOT}/shell/subscription/groups.sh"
    source "${PROJECT_ROOT}/shell/subscription/menu.sh"
    local root="${TMP_DIR}/subscription-menu-draft"
    local displayLog="${root}/display.log"
    local errorLog="${root}/errors.log"
    local statusLog="${root}/status.log"
    local fixture
    export PADM_SUBSCRIPTION_GROUPS_DIR="${root}/groups"
    unset AUTO_INSTALL
    mkdir -p "${PADM_SUBSCRIPTION_GROUPS_DIR}"
    writeDefaultSubscriptionGroupsState "$(subscriptionGroupsFile)"
    addSubscriptionSourceState edge "Edge" 203.0.113.20 39778
    addUserSubscriptionState alpha "Alpha" '["edge"]' 1
    addUserSubscriptionState beta "Beta" '["main"]' 0
    setSubscriptionGroupSyncEnabled false
    subscriptionActiveGroupWrite '
      .user_groups |= map(
        if .id == "alpha" then .uuid = "11111111-1111-4111-8111-111111111111" else . end) |
      .traffic.user_groups.alpha = {sources:{main:{upload:1073741824,download:1}}}
    '
    fixture=$(subscriptionGroupsStateRead -c '.')

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
    successCard() { printf '%s\n' "$*" >>"${statusLog}"; }
    subscriptionRequireLocalPublisherRole() { return 0; }
    subscriptionCurrentRoleNormalized() { printf 'uninitialized\n'; }
    subscriptionSyncCreateLocalApplyBackups() { :; }
    subscriptionSyncReleaseLocalApplyBackups() { :; }
    resetDraftFixture() {
        subscriptionGroupsStateWrite --argjson fixture "${fixture}" '$fixture'
    }

    (
        local before expected
        setUserSubscriptionsFields '["alpha","beta"]' '{"allowed_sources":["main"],"traffic_limit_gb":4,"enabled":false}'
        subscriptionActiveGroupRead -e '
          all(.user_groups[]; .allowed_sources == ["main"] and .traffic_limit_gb == 4 and .enabled == false) and
          .user_groups[0].uuid == "11111111-1111-4111-8111-111111111111" and
          .traffic.user_groups.alpha.sources.main.upload == 1073741824
        ' >/dev/null
        before=$(subscriptionGroupsStateRead -c '.')
        regressionExpectStatus 1 setUserSubscriptionsFields '["alpha","missing"]' '{"enabled":true}'
        regressionExpectStatus 1 setUserSubscriptionsFields '["alpha","alpha"]' '{"traffic_limit_gb":8}'
        regressionExpectStatus 1 setUserSubscriptionsFields '[]' '{"enabled":true}'
        regressionExpectStatus 1 setUserSubscriptionsFields '["alpha"]' '{"uuid":"22222222-2222-4222-8222-222222222222"}'
        regressionExpectStatus 1 setUserSubscriptionsFields '["alpha"]' '{"traffic_limit_gb":-1}'
        regressionExpectStatus 1 setUserSubscriptionsFields '["alpha"]' '{"allowed_sources":["missing"]}'
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]

        expected=$(subscriptionActiveGroupRead -c '[.user_groups[] | {id,name,enabled,allowed_sources,traffic_limit_gb}]')
        setUserSubscriptionTrafficLimit alpha 9
        before=$(subscriptionGroupsStateRead -c '.')
        regressionExpectStatus 1 setUserSubscriptionsFields '["alpha","beta"]' '{"enabled":true}' "${expected}"
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        expected=$(subscriptionActiveGroupRead -c '[.user_groups[] | {id,name,enabled,allowed_sources,traffic_limit_gb}]')
        subscriptionActiveGroupWrite '.traffic.user_groups.alpha.sources.main.download += 1'
        setUserSubscriptionsFields '["alpha","beta"]' '{"enabled":true}' "${expected}"
        subscriptionActiveGroupRead -e 'all(.user_groups[]; .enabled) and .traffic.user_groups.alpha.sources.main.download == 2' >/dev/null
    )

    (
        local before
        resetDraftFixture
        setUserSubscriptionEnabled alpha false
        subscriptionActiveGroupWrite '.sync.quota_auto_apply = true'
        before=$(subscriptionGroupsStateRead -c '.')
        regressionExpectStatus 1 setUserSubscriptionsFields '["alpha","beta"]' '{"enabled":true}'
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        setUserSubscriptionsFields '["alpha"]' '{"traffic_limit_gb":3,"enabled":true}'
        subscriptionActiveGroupRead -e '.user_groups[0].enabled and .user_groups[0].traffic_limit_gb == 3' >/dev/null
        setUserSubscriptionsFields '["alpha"]' '{"traffic_limit_gb":1,"enabled":false}'
        setUserSubscriptionsFields '["alpha"]' '{"traffic_limit_gb":0,"enabled":true}'
        subscriptionActiveGroupRead -e '.user_groups[0].enabled and .user_groups[0].traffic_limit_gb == 0' >/dev/null

        setUserSubscriptionsFields '["alpha"]' '{"traffic_limit_gb":1,"enabled":false}'
        before=$(subscriptionGroupsStateRead -c '.')
        regressionExpectStatus 1 toggleUserSubscriptionState alpha
        regressionExpectStatus 1 setUserSubscriptionEnabled alpha true
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        setUserSubscriptionTrafficLimit alpha 2
        toggleUserSubscriptionState alpha
        subscriptionActiveGroupRead -e '.user_groups[0].enabled == true' >/dev/null
        toggleUserSubscriptionState alpha
        subscriptionActiveGroupRead -e '.user_groups[0].enabled == false' >/dev/null
    )

    (
        local before
        resetDraftFixture
        selectUserSubscriptionId true true <<<1,2
        jq -e 'sort == ["alpha","beta"]' <<<"${selectedUserSubscriptionIds}" >/dev/null
        [[ -z "${selectedUserSubscriptionId}" ]]
        selectUserSubscriptionId true true <<<'*'
        jq -e 'sort == ["alpha","beta"]' <<<"${selectedUserSubscriptionIds}" >/dev/null
        selectUserSubscriptionId true true <<< $'1,missing\n1,1'
        [[ "${selectedUserSubscriptionIds}" == '[]' && "${selectedUserSubscriptionId}" == "alpha" ]]
        selectedUserSubscriptionIds='["stale"]'
        regressionExpectStatus 1 selectUserSubscriptionId true true </dev/null
        [[ "${selectedUserSubscriptionIds}" == '[]' ]]

        before=$(subscriptionGroupsStateRead -c '.')
        regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha"]' <<< $'1\nDiscarded name\n3\n7\n7'
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha"]' <<< $'3\n7'
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha"]' <<< $'2'
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        editUserSubscriptionsMenu '["alpha"]' <<< $'3\n7\n8\n6'
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]

        resetDraftFixture
        before=$(subscriptionGroupsStateRead -c '.')
        editUserSubscriptionsMenu '["alpha","beta"]' <<< $'2\n\n3\n\n6'
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]

        local syncCount=0
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        editUserSubscriptionsMenu '["alpha"]' <<< $'3\n007\n3\n\n2\n1\n2\n\n6'
        [[ "${syncCount}" == "1" ]]
        subscriptionActiveGroupRead -e '.user_groups[0].traffic_limit_gb == 7 and .user_groups[0].allowed_sources == ["main"]' >/dev/null
        resetDraftFixture
        before=$(subscriptionGroupsStateRead -c '.')
        editUserSubscriptionsMenu '["alpha"]' <<< $'3\n1\n6'
        [[ "${syncCount}" == "1" ]]
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]

        syncCount=0
        manageUserSubscriptionItem alpha <<< $'5\n7'
        [[ "${syncCount}" == "1" ]]
        subscriptionActiveGroupRead -e '.sync.enabled == false and .user_groups[0].enabled == false' >/dev/null
        manageUserSubscriptionItem alpha <<< $'5\n7'
        [[ "${syncCount}" == "2" ]]
        subscriptionActiveGroupRead -e '.sync.enabled == false and .user_groups[0].enabled == true' >/dev/null
    )

    (
        local syncCount=0 mutationCount=0
        resetDraftFixture
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        eval "$(declare -f setUserSubscriptionsFields | sed '1s/^setUserSubscriptionsFields/originalSetUserSubscriptionsFields/')"
        setUserSubscriptionsFields() {
            mutationCount=$((mutationCount + 1))
            originalSetUserSubscriptionsFields "$@"
        }
        editUserSubscriptionsMenu '["alpha"]' <<< $'1,2,3,5\nAlpha revised\n1,2\n6\n6'
        [[ "${mutationCount}" == "1" && "${syncCount}" == "1" ]]
        subscriptionActiveGroupRead -e '
          .sync.enabled == false and
          .user_groups[0].name == "Alpha revised" and
          (.user_groups[0].allowed_sources | sort) == ["edge","main"] and
          .user_groups[0].traffic_limit_gb == 6 and .user_groups[0].enabled == false and
          .user_groups[1].name == "Beta"
        ' >/dev/null
        editUserSubscriptionsMenu '["alpha","beta"]' <<< $'2,3,4\n2\n8\n6'
        [[ "${mutationCount}" == "2" && "${syncCount}" == "2" ]]
        subscriptionActiveGroupRead -e '
          .sync.enabled == false and
          all(.user_groups[]; .allowed_sources == ["edge"] and .traffic_limit_gb == 8 and .enabled)
        ' >/dev/null

        resetDraftFixture
        local before
        before=$(subscriptionGroupsStateRead -c '.')
        editUserSubscriptionsMenu '["alpha","beta"]' <<< $'2,3\n\n\n6'
        [[ "${mutationCount}" == "2" && "${syncCount}" == "2" ]]
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha"]' <<< $'2,6\n2,2\n4,5\nmissing\n7'
        [[ "${mutationCount}" == "2" && "${syncCount}" == "2" ]]
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha"]' <<< $'1,2,3\nDiscarded\n1\n'
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        resetDraftFixture
        editUserSubscriptionsMenu '["alpha"]' <<< $'1,3,5\nDrafted\ninvalid\n6'
        [[ "${mutationCount}" == "3" && "${syncCount}" == "3" ]]
        subscriptionActiveGroupRead -e '
          .user_groups[0].name == "Drafted" and
          .user_groups[0].traffic_limit_gb == 1 and .user_groups[0].enabled
        ' >/dev/null

        local openedIds=
        editUserSubscriptionsMenu() { openedIds=$1; }
        manageSharedSubscriptions <<< $'1,2\n\n'
        jq -e 'sort == ["alpha","beta"]' <<<"${openedIds}" >/dev/null
    )

    (
        local syncCount=0 mutationCount=0
        resetDraftFixture
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        eval "$(declare -f setUserSubscriptionsFields | sed '1s/^setUserSubscriptionsFields/originalSetUserSubscriptionsFields/')"
        setUserSubscriptionsFields() {
            mutationCount=$((mutationCount + 1))
            [[ "${mutationCount}" != "1" ]] || return 1
            originalSetUserSubscriptionsFields "$@"
        }
        editUserSubscriptionsMenu '["alpha"]' <<< $'1\nRetained draft\n3\n9\n6\n6'
        [[ "${mutationCount}" == "2" && "${syncCount}" == "1" ]]
        subscriptionActiveGroupRead -e '.user_groups[0].name == "Retained draft" and .user_groups[0].traffic_limit_gb == 9' >/dev/null
    )

    (
        local syncCount=0
        resetDraftFixture
        runSubscriptionGroupSync() {
            syncCount=$((syncCount + 1))
            [[ "${syncCount}" != "1" ]]
        }
        editUserSubscriptionsMenu '["alpha"]' <<< $'1\nRetry after sync\n3\n3\n6\n6'
        [[ "${syncCount}" == "3" ]]
        subscriptionActiveGroupRead -e '.sync.enabled == false and .user_groups[0].name == "Retry after sync" and .user_groups[0].traffic_limit_gb == 3' >/dev/null
    )

    (
        local syncCount=0 before
        resetDraftFixture
        setUserSubscriptionEnabled alpha false
        subscriptionActiveGroupWrite '.sync.quota_auto_apply = true'
        before=$(subscriptionGroupsStateRead -c '.')
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha"]' <<< $'4\n6\n7'
        [[ "${syncCount}" == "0" && "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        editUserSubscriptionsMenu '["alpha"]' <<< $'4\n3\n2\n6'
        [[ "${syncCount}" == "1" ]]
        subscriptionActiveGroupRead -e '.user_groups[0].enabled and .user_groups[0].traffic_limit_gb == 2' >/dev/null
    )

    (
        local syncCount=0
        resetDraftFixture
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        eval "$(declare -f setUserSubscriptionsFields | sed '1s/^setUserSubscriptionsFields/originalSetUserSubscriptionsFields/')"
        setUserSubscriptionsFields() {
            setUserSubscriptionTrafficLimit beta 11
            originalSetUserSubscriptionsFields "$@"
        }
        regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha","beta"]' <<< $'3\n7\n6\n7'
        [[ "${syncCount}" == "0" ]]
        subscriptionActiveGroupRead -e '.user_groups[0].traffic_limit_gb == 1 and .user_groups[1].traffic_limit_gb == 11' >/dev/null
    )

    (
        local syncCount=0 ensureCount=0
        resetDraftFixture
        ensureSubscriptionServiceForSharedLinks() { ensureCount=$((ensureCount + 1)); return 99; }
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        setUserSubscriptionEnabled alpha false
        createAndSyncUserSubscriptionWizard alpha <<< $'copied-alpha\n\n\n'
        [[ "${syncCount}" == "1" && "${ensureCount}" == "0" && "${createdUserSubscriptionId}" == "copied-alpha" ]]
        subscriptionActiveGroupRead -e '
          . as $state |
          ($state.user_groups | map(select(.id == "copied-alpha")) | first) as $copy |
          ($state.sync.enabled == false) and
          ($copy.allowed_sources == ["edge"] and $copy.traffic_limit_gb == 1 and
            $copy.enabled == true and ($copy | has("uuid") | not)) and
          (($state.traffic.user_groups | has("copied-alpha")) | not) and
          ($state.user_groups[0].uuid == "11111111-1111-4111-8111-111111111111")
        ' >/dev/null

        createAndSyncUserSubscriptionWizard beta <<<zero-template-copy
        [[ "${ensureCount}" == "0" ]]
        subscriptionActiveGroupRead -e '
          any(.user_groups[]; .id == "zero-template-copy" and .traffic_limit_gb == 0 and .allowed_sources == ["main"])
        ' >/dev/null
    )

    (
        local syncCount=0
        resetDraftFixture
        setSubscriptionGroupSyncEnabled false
        subscriptionSyncRestoreConfigBackups() { :; }
        subscriptionSyncRestoreSubscribeOutputBackups() { :; }
        subscriptionSyncReconcileLocalServices() { :; }
        subscriptionSyncMarkResult() { :; }
        runSubscriptionGroupSync() {
            syncCount=$((syncCount + 1))
            subscriptionActiveGroupWrite '.traffic.user_groups.alpha.sources.main.upload += 50'
            return 1
        }
        regressionExpectStatus 1 subscriptionGroupsWithLock runUserSubscriptionMutationAndSyncUnlocked \
            "回滚流量检查" "" setUserSubscriptionsFields '["alpha"]' '{"enabled":false}'
        [[ "${syncCount}" == "2" ]]
        subscriptionActiveGroupRead -e '
          .user_groups[0].enabled and .traffic.user_groups.alpha.sources.main.upload == 1073741924
        ' >/dev/null

        resetDraftFixture
        setSubscriptionGroupSyncEnabled false
        syncCount=0
        collectSubscriptionTraffic() {
            subscriptionActiveGroupWrite '
              .traffic.user_groups.alpha.sources.main.upload += 50 |
              .traffic.sources.main = {upload:50,download:0}
            '
        }
        subscriptionLocalTrafficBaselineExists() { return 0; }
        subscriptionSyncRemoveAccount() { return 99; }
        reloadCoreWithTrafficStatsConfig() { return 99; }
        runSubscriptionGroupSync() {
            syncCount=$((syncCount + 1))
            subscriptionActiveGroupWrite '.traffic.sources.main.upload += 25'
            return 1
        }
        regressionExpectStatus 1 removeUserSubscriptionMenu alpha <<<yes
        [[ "${syncCount}" == "2" ]]
        subscriptionActiveGroupRead -e '
          any(.user_groups[]; .id == "alpha") and
          .traffic.user_groups.alpha.sources.main.upload == 1073741874 and
          .traffic.sources.main.upload == 100
        ' >/dev/null
        resetDraftFixture
        local before
        before=$(subscriptionGroupsStateRead -c '.')
        syncCount=0
        collectSubscriptionTraffic() { return 1; }
        regressionExpectStatus 1 removeUserSubscriptionMenu alpha <<<yes
        [[ "${syncCount}" == "0" && "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
    )
)
