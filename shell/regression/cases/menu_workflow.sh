#!/usr/bin/env bash

runSubscriptionMenuWorkflowCoreRegression() (
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
        local selectionFixture before token editedIds= syncCount=0
        selectionFixture=$(subscriptionGroupsStateRead -c '.')
        local PADM_SUBSCRIPTION_GROUPS_DIR="${root}/status-selection"
        mkdir -p "${PADM_SUBSCRIPTION_GROUPS_DIR}"
        subscriptionGroupsStateWrite --argjson fixture "${selectionFixture}" '$fixture'
        addUserSubscriptionState beta "Beta" '["main"]' 1
        addUserSubscriptionState gamma "Gamma" '["main"]' 2
        subscriptionActiveGroupWrite '
          .user_groups |= map(if .id == "beta" then .enabled = false else . end) |
          .traffic.user_groups = {
            "2":{sources:{edge:{upload:5368709120,download:0}}},
            alpha:{sources:{main:{upload:5368709120,download:0}}},
            beta:{sources:{main:{upload:1073741824,download:0}}},
            gamma:{sources:{main:{upload:1717986918,download:0}}}
          }
        '
        before=$(subscriptionGroupsStateRead -c '.')
        selectUserSubscriptionId true true <<<'@on'
        jq -e 'sort == ["2","alpha","gamma"]' <<<"${selectedUserSubscriptionIds}" >/dev/null
        [[ -z "${selectedUserSubscriptionId}" ]]
        selectUserSubscriptionId true true <<<'@off'
        [[ "${selectedUserSubscriptionId}" == beta && "${selectedUserSubscriptionIds}" == '[]' ]]
        selectUserSubscriptionId true true <<<'@over'
        jq -e 'sort == ["2","beta"]' <<<"${selectedUserSubscriptionIds}" >/dev/null
        [[ -z "${selectedUserSubscriptionId}" ]]
        selectUserSubscriptionId true true <<< $'1,missing\n  id:2, 1 '
        [[ "${selectedUserSubscriptionId}" == 2 && "${selectedUserSubscriptionIds}" == '[]' ]]
        for token in '1,missing' '1,' '@on,1'; do
            selectedUserSubscriptionId=stale
            selectedUserSubscriptionIds='["stale"]'
            regressionExpectStatus 1 selectUserSubscriptionId true true <<<"${token}"
            [[ -z "${selectedUserSubscriptionId}" && "${selectedUserSubscriptionIds}" == '[]' ]]
        done
        for token in '@on' '@off' '@over' '*' '1,2'; do
            regressionExpectStatus 1 selectUserSubscriptionId <<<"${token}"
            [[ -z "${selectedUserSubscriptionId}" && "${selectedUserSubscriptionIds}" == '[]' ]]
        done
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        (
            local readCount=0
            menuReadChoice() {
                readCount=$((readCount + 1))
                [[ "${readCount}" == 1 ]] || return 1
                printf -v "$3" '%s' '  id:2  '
            }
            selectUserSubscriptionId
            [[ "${selectedUserSubscriptionId}" == 2 && "${selectedUserSubscriptionIds}" == '[]' ]]
        )
        editUserSubscriptionsMenu() { editedIds=$1; }
        manageUserSubscriptionItem alpha <<< $'8\n@over\n3\n7'
        jq -e 'sort == ["2","beta"]' <<<"${editedIds}" >/dev/null
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        manageSharedSubscriptions <<< $'@on\n10\n7\n\n'
        [[ "${syncCount}" == 1 ]]
        subscriptionActiveGroupRead -e 'all(.user_groups[]; .enabled == false)' >/dev/null
        regressionExpectStatus 1 selectUserSubscriptionId true true <<<'@on'
        [[ -z "${selectedUserSubscriptionId}" && "${selectedUserSubscriptionIds}" == '[]' ]]
        selectUserSubscriptionId true true <<< $'@on\n@off'
        jq -e 'sort == ["2","alpha","beta","gamma"]' <<<"${selectedUserSubscriptionIds}" >/dev/null
        subscriptionActiveGroupWrite '.traffic.user_groups = {}'
        regressionExpectStatus 1 selectUserSubscriptionId true true <<<'@over'
        [[ -z "${selectedUserSubscriptionId}" && "${selectedUserSubscriptionIds}" == '[]' ]]
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
        local syncCount=0 syncStatus=0 published=true serviceCount=0 serviceReadCount=0 linkCount=0
        local shownCount=0 shownId= shownIds=
        installSubscribe() { serviceCount=$((serviceCount + 1)); return 99; }
        readNginxSubscribe() { serviceReadCount=$((serviceReadCount + 1)); return 99; }
        syncAndShowSubscriptionLinks() { linkCount=$((linkCount + 1)); return 99; }
        showPublishedSubscriptionLinks() {
            shownCount=$((shownCount + 1))
            shownId=$1
            shownIds=${2:-}
            return 1
        }
        setSubscriptionGroupSyncEnabledWithCron() { return 99; }
        runSubscriptionGroupSync() {
            syncCount=$((syncCount + 1))
            SUBSCRIPTION_SYNC_PUBLISHED=${published}
            return "${syncStatus}"
        }
        createAndSyncUserSubscriptionWizard <<< $'new-team\n1,2\n3'
        [[ "${syncCount}" == "1" && "${shownCount}" == "1" && "${shownId}" == "new-team" ]]
        [[ "${createdUserSubscriptionId}" == "new-team" && "${createdUserSubscriptionIds}" == '["new-team"]' ]]
        subscriptionActiveGroupRead -e '
          .sync.enabled == false and
          any(.user_groups[]; .id == "new-team" and .traffic_limit_gb == 3 and (.allowed_sources | sort) == ["edge","main"])
        ' >/dev/null
        syncStatus=1
        published=false
        regressionExpectStatus 1 createAndSyncUserSubscriptionWizard <<< $'pending-team\n1\n0'
        [[ "${syncCount}" == "2" && "${shownCount}" == "1" ]]
        userSubscriptionExists pending-team
        subscriptionActiveGroupRead -e '.sync.enabled == false' >/dev/null
        grep -q '已保存' "${statusLog}"
        local openedIds=
        manageUserSubscriptionsMenu() { openedIds=$1; }
        manageSharedSubscriptions <<< $'alpha\n\n'
        [[ "${openedIds}" == '["alpha"]' && "${syncCount}" == "2" ]]
        manageSharedSubscriptions <<< $'+\nretry-team\n1\n0\n\n'
        [[ "${openedIds}" == '["retry-team"]' && "${syncCount}" == "3" && "${shownCount}" == "1" ]]
        userSubscriptionExists retry-team
        published=true
        manageSharedSubscriptions <<< $'+\npartial-team\n1\n0\n\n'
        [[ "${openedIds}" == '["partial-team"]' && "${syncCount}" == "4" &&
            "${shownCount}" == "2" && "${shownId}" == "partial-team" ]]
        userSubscriptionExists partial-team
        grep -q '首次同步部分失败但链接已发布' "${statusLog}"
        syncStatus=0
        published=false
        SUBSCRIPTION_SYNC_PUBLISHED=true
        createAndSyncUserSubscriptionWizard <<< $'local-a,local-b\n1\n0'
        [[ "${syncCount}" == "5" && "${shownCount}" == "2" &&
            -z "${createdUserSubscriptionId}" && "${createdUserSubscriptionIds}" == '["local-a","local-b"]' ]]
        [[ "${SUBSCRIPTION_SYNC_PUBLISHED}" == false ]]
        grep -q '账号同步已完成，未发布订阅链接' "${statusLog}"
        syncStatus=1
        manageSharedSubscriptions <<< $'+\nbatch-pending-a,batch-pending-b\n1,2\n4\n\n'
        [[ "${syncCount}" == "6" && "${shownCount}" == "2" &&
            "${openedIds}" == '["batch-pending-a","batch-pending-b"]' &&
            "${createdUserSubscriptionIds}" == "${openedIds}" ]]
        subscriptionActiveGroupRead -e '
          all(.user_groups[] | select(.id == "batch-pending-a" or .id == "batch-pending-b");
            (.allowed_sources | sort) == ["edge","main"] and .traffic_limit_gb == 4 and .enabled)
        ' >/dev/null
        published=true
        regressionExpectStatus 1 createAndSyncUserSubscriptionWizard <<< $'batch-partial-a,batch-partial-b\n1\n0'
        [[ "${syncCount}" == "7" && "${shownCount}" == "3" && -z "${shownId}" &&
            "${shownIds}" == '["batch-partial-a","batch-partial-b"]' &&
            "${createdUserSubscriptionIds}" == "${shownIds}" ]]
        [[ "${serviceCount}" == "0" && "${serviceReadCount}" == "0" && "${linkCount}" == "0" ]]
    )

    (
        local syncCount=0 sourceChoiceCount=0 limitPromptCount=0 writeCount=0 before
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        eval "$(declare -f selectUserSubscriptionSources | sed '1s/^selectUserSubscriptionSources/originalCreateRetrySelectUserSubscriptionSources/')"
        selectUserSubscriptionSources() {
            sourceChoiceCount=$((sourceChoiceCount + 1))
            originalCreateRetrySelectUserSubscriptionSources "$@"
        }
        eval "$(declare -f menuReadChoice | sed '1s/^menuReadChoice/originalCreateRetryMenuReadChoice/')"
        menuReadChoice() {
            [[ "$1" != "user_subscription_traffic_limit" ]] || limitPromptCount=$((limitPromptCount + 1))
            originalCreateRetryMenuReadChoice "$@"
        }
        createAndSyncUserSubscriptionWizard <<< $'bad id\nalpha\nretry-id\n1\n9'
        [[ "${createdUserSubscriptionId}" == "retry-id" && "${syncCount}" == "1" &&
            "${sourceChoiceCount}" == "1" && "${limitPromptCount}" == "1" ]]
        subscriptionActiveGroupRead -e '
          any(.user_groups[]; .id == "retry-id" and .allowed_sources == ["main"] and .traffic_limit_gb == 9)
        ' >/dev/null
        eval "$(declare -f subscriptionGroupsStateWriteUnlocked | sed '1s/^subscriptionGroupsStateWriteUnlocked/originalCreateBatchStateWriteUnlocked/')"
        subscriptionGroupsStateWriteUnlocked() {
            [[ "${SUBSCRIPTION_GROUPS_LOCK_HELD:-}" == "1" ]] || return 99
            writeCount=$((writeCount + 1))
            originalCreateBatchStateWriteUnlocked "$@"
        }
        createAndSyncUserSubscriptionWizard <<< $'bad id,unused\nempty,\nrepeat,repeat\nnew-id,alpha\n retry-batch-a , retry-batch-b \n1,2\n9'
        [[ -z "${createdUserSubscriptionId}" && "${createdUserSubscriptionIds}" == '["retry-batch-a","retry-batch-b"]' &&
            "${syncCount}" == "2" && "${sourceChoiceCount}" == "2" &&
            "${limitPromptCount}" == "2" && "${writeCount}" == "1" ]]
        subscriptionActiveGroupRead -e '
          ([.user_groups[] | select(.id == "retry-batch-a" or .id == "retry-batch-b")] |
            length == 2 and all(.[]; .traffic_limit_gb == 9 and (.allowed_sources | sort) == ["edge","main"])) and
          all(.user_groups[]; .id != "unused" and .id != "empty" and .id != "repeat" and .id != "new-id")
        ' >/dev/null
        before=$(subscriptionGroupsStateRead -c '.')
        createdUserSubscriptionId=stale
        createdUserSubscriptionIds='["stale"]'
        regressionExpectStatus 1 createAndSyncUserSubscriptionWizard <<<""
        [[ -z "${createdUserSubscriptionId}" && "${createdUserSubscriptionIds}" == '[]' ]]
        createdUserSubscriptionId=stale
        createdUserSubscriptionIds='["stale"]'
        regressionExpectStatus 1 createAndSyncUserSubscriptionWizard </dev/null
        [[ -z "${createdUserSubscriptionId}" && "${createdUserSubscriptionIds}" == '[]' &&
            "${syncCount}" == "2" && "${sourceChoiceCount}" == "2" && "${limitPromptCount}" == "2" ]]
        createdUserSubscriptionId=stale
        createdUserSubscriptionIds='["stale"]'
        regressionExpectStatus 1 createAndSyncUserSubscriptionWizard < <(printf 'no-lf-a,no-lf-b')
        [[ -z "${createdUserSubscriptionId}" && "${createdUserSubscriptionIds}" == '[]' ]]
        regressionExpectStatus 1 createAndSyncUserSubscriptionWizard < <(printf 'source-eof-a,source-eof-b\n')
        regressionExpectStatus 1 createAndSyncUserSubscriptionWizard < <(printf 'limit-eof-a,limit-eof-b\n1\n7')
        [[ -z "${createdUserSubscriptionId}" && "${createdUserSubscriptionIds}" == '[]' &&
            "${syncCount}" == "2" && "${writeCount}" == "1" ]]
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
    )

    (
        local before syncCount=0 writeCount=0 raceInjected=false raceId=raced-id
        before=$(subscriptionGroupsStateRead -c '.')
        regressionExpectStatus 2 addUserSubscriptionsState '[{"id":"atomic-new","name":"New"},{"id":"alpha","name":"Existing"}]' '["main"]' 1
        regressionExpectStatus 1 addUserSubscriptionsState '[{"id":"duplicate","name":"A"},{"id":"duplicate","name":"B"}]' '["main"]' 1
        regressionExpectStatus 1 addUserSubscriptionsState '[{"id":"atomic-new","name":"New"},{"id":"bad id","name":"Bad"}]' '["main"]' 1
        regressionExpectStatus 1 addUserSubscriptionsState '[]' '["main"]' 1
        (
            subscriptionActiveGroupWrite() { return 2; }
            regressionExpectStatus 1 addUserSubscriptionsState '[{"id":"write-status-two","name":"Failure"}]' '["main"]' 1
        )
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        eval "$(declare -f subscriptionGroupsStateWriteUnlocked | sed '1s/^subscriptionGroupsStateWriteUnlocked/originalAtomicCreateStateWriteUnlocked/')"
        subscriptionGroupsStateWriteUnlocked() {
            [[ "${SUBSCRIPTION_GROUPS_LOCK_HELD:-}" == "1" ]] || return 99
            writeCount=$((writeCount + 1))
            originalAtomicCreateStateWriteUnlocked "$@"
        }
        addUserSubscriptionsState '[{"id":"atomic-a","name":"Custom A"},{"id":"atomic-b","name":"Custom B"}]' '["main"]' 2
        [[ "${writeCount}" == "1" ]]
        addUserSubscriptionState single-custom "Custom Single" '["edge"]' 3
        [[ "${writeCount}" == "2" ]]
        subscriptionActiveGroupRead -e '
          any(.user_groups[]; .id == "atomic-a" and .name == "Custom A") and
          any(.user_groups[]; .id == "atomic-b" and .name == "Custom B") and
          any(.user_groups[]; .id == "single-custom" and .name == "Custom Single" and
            .allowed_sources == ["edge"] and .traffic_limit_gb == 3)
        ' >/dev/null
        eval "$(declare -f addUserSubscriptionsState | sed '1s/^addUserSubscriptionsState/originalRaceAddUserSubscriptionsState/')"
        addUserSubscriptionsState() {
            if [[ "${raceInjected}" == false ]]; then
                raceInjected=true
                originalRaceAddUserSubscriptionsState "$(jq -cn --arg id "${raceId}" '[{id:$id,name:"Concurrent"}]')" '["main"]' 0
            fi
            originalRaceAddUserSubscriptionsState "$@"
        }
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        createdUserSubscriptionId=stale
        createdUserSubscriptionIds='["stale"]'
        regressionExpectStatus 1 createAndSyncUserSubscriptionWizard <<< $'raced-id,race-not-created\n1\n2'
        [[ "${syncCount}" == "0" && -z "${createdUserSubscriptionId}" && "${createdUserSubscriptionIds}" == '[]' ]]
        subscriptionActiveGroupRead -e '
          any(.user_groups[]; .id == "raced-id" and .name == "Concurrent") and
          all(.user_groups[]; .id != "race-not-created")
        ' >/dev/null
        raceInjected=false
        raceId=raced-empty
        regressionExpectStatus 1 createAndSyncUserSubscriptionWizard <<< $'raced-empty,race-empty-not-created\n1\n2\n'
        [[ "${syncCount}" == "0" && -z "${createdUserSubscriptionId}" && "${createdUserSubscriptionIds}" == '[]' ]]
        subscriptionActiveGroupRead -e '
          any(.user_groups[]; .id == "raced-empty" and .name == "Concurrent") and
          all(.user_groups[]; .id != "race-empty-not-created")
        ' >/dev/null
        local sourceChoiceCount=0 limitPromptCount=0
        eval "$(declare -f selectUserSubscriptionSources | sed '1s/^selectUserSubscriptionSources/originalRaceSelectUserSubscriptionSources/')"
        selectUserSubscriptionSources() {
            sourceChoiceCount=$((sourceChoiceCount + 1))
            originalRaceSelectUserSubscriptionSources "$@"
        }
        eval "$(declare -f menuReadChoice | sed '1s/^menuReadChoice/originalRaceMenuReadChoice/')"
        menuReadChoice() {
            [[ "$1" != user_subscription_traffic_limit ]] || limitPromptCount=$((limitPromptCount + 1))
            originalRaceMenuReadChoice "$@"
        }
        raceInjected=false
        raceId=raced-retry
        createAndSyncUserSubscriptionWizard <<< $'raced-retry,race-retry-not-created\n1,2\n11\nbad id\nalpha\nrace-recovered-a,race-recovered-b'
        [[ "${syncCount}" == "1" && "${sourceChoiceCount}" == "1" && "${limitPromptCount}" == "1" &&
            -z "${createdUserSubscriptionId}" && "${createdUserSubscriptionIds}" == '["race-recovered-a","race-recovered-b"]' ]]
        subscriptionActiveGroupRead -e '
          all(.user_groups[]; .id != "race-retry-not-created") and
          ([.user_groups[] | select(.id == "race-recovered-a" or .id == "race-recovered-b")] |
            length == 2 and all(.[]; .traffic_limit_gb == 11 and (.allowed_sources | sort) == ["edge","main"]))
        ' >/dev/null
    )

    for fault in before after; do
        (
            local before syncCount=0 addCount=0 remaining
            before=$(subscriptionGroupsStateRead -c '.')
            eval "$(declare -f addUserSubscriptionsState | sed '1s/^addUserSubscriptionsState/originalFailedAddUserSubscriptionsState/')"
            addUserSubscriptionsState() {
                addCount=$((addCount + 1))
                [[ "${fault}" != after ]] || originalFailedAddUserSubscriptionsState "$@" || return 1
                return 1
            }
            runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
            exec 3<<<"${fault}-write-failure"$'\n1\n4\n'"${fault}-must-not-retry"
            regressionExpectStatus 1 createAndSyncUserSubscriptionWizard <&3
            IFS= read -r remaining <&3
            exec 3<&-
            [[ "${remaining}" == "${fault}-must-not-retry" && "${addCount}" == "1" && "${syncCount}" == "0" &&
                -z "${createdUserSubscriptionId}" && "${createdUserSubscriptionIds}" == '[]' ]]
            if [[ "${fault}" == before ]]; then
                [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
            else
                subscriptionActiveGroupRead -e '
                  any(.user_groups[]; .id == "after-write-failure") and
                  all(.user_groups[]; .id != "after-must-not-retry")
                ' >/dev/null
            fi
        )
    done

    (
        local PADM_SUBSCRIPTION_GROUPS_DIR="${root}/empty-selection" openedCount=0
        mkdir -p "${PADM_SUBSCRIPTION_GROUPS_DIR}"
        writeDefaultSubscriptionGroupsState "$(subscriptionGroupsFile)"
        manageUserSubscriptionItem() { openedCount=$((openedCount + 1)); }
        manageUserSubscriptionsMenu() { openedCount=$((openedCount + 1)); }
        manageSharedSubscriptions <<< $'*\n'
        [[ "${openedCount}" == "0" && -z "${selectedUserSubscriptionId}" && "${selectedUserSubscriptionIds}" == '[]' ]]
        grep -q '暂无可选分享订阅' "${errorLog}"
    )

    (
        local syncCount=0 publishCount=0 publishedCount=0 serviceCount=0 serviceReadCount=0
        installSubscribe() { serviceCount=$((serviceCount + 1)); return 99; }
        readNginxSubscribe() { serviceReadCount=$((serviceReadCount + 1)); return 99; }
        runSubscriptionGroupSync() {
            syncCount=$((syncCount + 1))
            SUBSCRIPTION_SYNC_PUBLISHED=true
        }
        subscribe() { publishCount=$((publishCount + 1)); return 99; }
        showPublishedSubscriptionLinks() { publishedCount=$((publishedCount + 1)); }
        setUserSubscriptionEnabled alpha false
        regressionExpectStatus 1 syncAndShowSubscriptionLinks alpha
        [[ "${syncCount}" == "0" && "${publishCount}" == "0" ]]
        regressionExpectStatus 1 syncAndShowSubscriptionLinks missing
        [[ "${syncCount}" == "0" && "${publishedCount}" == "0" ]]
        setUserSubscriptionEnabled alpha true
        syncAndShowSubscriptionLinks alpha
        [[ "${syncCount}" == "1" && "${publishCount}" == "0" && "${publishedCount}" == "1" ]]
        syncAndShowSubscriptionLinks alpha
        [[ "${syncCount}" == "2" && "${publishCount}" == "0" && "${publishedCount}" == "2" ]]
        syncAndShowSubscriptionLinks
        [[ "${syncCount}" == "3" && "${publishCount}" == "0" && "${publishedCount}" == "3" ]]
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        SUBSCRIPTION_SYNC_PUBLISHED=true
        syncAndShowSubscriptionLinks alpha
        [[ "${syncCount}" == "4" && "${publishedCount}" == "3" && "${SUBSCRIPTION_SYNC_PUBLISHED}" == "false" ]]
        grep -q '账号同步已完成，未发布订阅链接' "${statusLog}"
        runSubscriptionGroupSync() {
            syncCount=$((syncCount + 1))
            SUBSCRIPTION_SYNC_PUBLISHED=true
            return 1
        }
        syncAndShowSubscriptionLinks alpha
        [[ "${syncCount}" == "5" && "${publishCount}" == "0" && "${publishedCount}" == "4" ]]
        syncAndShowSubscriptionLinks
        [[ "${syncCount}" == "6" && "${publishCount}" == "0" && "${publishedCount}" == "5" ]]
        runSubscriptionGroupSync() {
            syncCount=$((syncCount + 1))
            return 1
        }
        SUBSCRIPTION_SYNC_PUBLISHED=true
        regressionExpectStatus 1 syncAndShowSubscriptionLinks alpha
        [[ "${syncCount}" == "7" && "${publishedCount}" == "5" && "${SUBSCRIPTION_SYNC_PUBLISHED}" == "false" ]]
        regressionExpectStatus 1 syncAndShowSubscriptionLinks
        [[ "${syncCount}" == "8" && "${publishedCount}" == "5" ]]
        runSubscriptionGroupSync() {
            syncCount=$((syncCount + 1))
            SUBSCRIPTION_SYNC_PUBLISHED=true
        }
        showPublishedSubscriptionLinks() { publishedCount=$((publishedCount + 1)); return 1; }
        regressionExpectStatus 1 syncAndShowSubscriptionLinks alpha
        [[ "${syncCount}" == "9" && "${publishCount}" == "0" && "${publishedCount}" == "6" ]]
        [[ "${serviceCount}" == "0" && "${serviceReadCount}" == "0" ]]
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

)

runSubscriptionMenuDraftRegression() (
    local caseGroup=${1:-all}
    case "${caseGroup}" in
    all|validation|editing|conflicts|recovery) ;;
    *) return 2 ;;
    esac
    source "${PROJECT_ROOT}/shell/core/runtime.sh"
    source "${PROJECT_ROOT}/shell/subscription/groups.sh"
    source "${PROJECT_ROOT}/shell/subscription/menu.sh"
    source "${PROJECT_ROOT}/shell/subscription/traffic.sh"
    local root="${TMP_DIR}/subscription-menu-draft-${caseGroup}"
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
        [[ "${caseGroup}" == all || "${caseGroup}" == validation ]] || exit 0
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
        [[ "${caseGroup}" == all || "${caseGroup}" == validation ]] || exit 0
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
        [[ "${caseGroup}" == all || "${caseGroup}" == editing ]] || exit 0
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
        [[ "${caseGroup}" == all || "${caseGroup}" == editing ]] || exit 0
        local syncCount=0 mutationCount=0 before
        resetDraftFixture
        before=$(subscriptionGroupsStateRead -c '.')
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        eval "$(declare -f setUserSubscriptionsFields | sed '1s/^setUserSubscriptionsFields/originalSetUserSubscriptionsFields/')"
        setUserSubscriptionsFields() {
            mutationCount=$((mutationCount + 1))
            originalSetUserSubscriptionsFields "$@"
        }
        editUserSubscriptionsMenu '["alpha"]' <<<""
        [[ "${mutationCount}" == "0" && "${syncCount}" == "0" ]]
        editUserSubscriptionsMenu '["alpha"]' <<< $'3\n1\n'
        [[ "${mutationCount}" == "0" && "${syncCount}" == "0" ]]
        : >"${displayLog}"
        editUserSubscriptionsMenu '["alpha"]' <<< $'1,2,3,4\nAlpha\n2\n001\n'
        ! grep -qE '待保存字段：(名称|节点范围|订阅额度|启用状态)' "${displayLog}"
        editUserSubscriptionsMenu '["alpha"]' <<< $'1\nTemporary name\n1\nAlpha\n'
        [[ "${mutationCount}" == "0" && "${syncCount}" == "0" ]]
        (
            setUserSubscriptionSources alpha '["main","edge"]'
            before=$(subscriptionGroupsStateRead -c '.')
            editUserSubscriptionsMenu '["alpha"]' <<< $'2\n2,1\n'
            [[ "${mutationCount}" == "0" && "${syncCount}" == "0" &&
                "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        )
        resetDraftFixture
        regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha"]' </dev/null
        regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha"]' <<< $'1\nDiscarded draft\n3'
        regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha"]' < <(printf '3\n9')
        [[ "${mutationCount}" == "0" && "${syncCount}" == "0" ]]
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]

        editUserSubscriptionsMenu '["alpha"]' <<< $'3\n9\n'
        [[ "${mutationCount}" == "1" && "${syncCount}" == "1" ]]
        subscriptionActiveGroupRead -e '.sync.enabled == false and .user_groups[0].traffic_limit_gb == 9' >/dev/null
    )

    (
        [[ "${caseGroup}" == all || "${caseGroup}" == conflicts ]] || exit 0
        local syncCount=0 mutationCount=0 targetPatch= expectedSnapshot= concurrentChanged=false
        resetDraftFixture
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        eval "$(declare -f menuReadChoice | sed '1s/^menuReadChoice/originalMenuReadChoice/')"
        menuReadChoice() {
            local resultVar=$3
            originalMenuReadChoice "$@" || return $?
            if [[ "$1" == "user_subscription_item_menu" && "${!resultVar}" == "5" &&
                "${concurrentChanged}" == "false" ]]; then
                concurrentChanged=true
                subscriptionActiveGroupWrite '.user_groups[0].enabled = false'
            fi
        }
        eval "$(declare -f setUserSubscriptionsFields | sed '1s/^setUserSubscriptionsFields/originalSetUserSubscriptionsFields/')"
        setUserSubscriptionsFields() {
            mutationCount=$((mutationCount + 1))
            targetPatch=$2
            expectedSnapshot=${3:-}
            originalSetUserSubscriptionsFields "$@"
        }
        manageUserSubscriptionItem alpha <<< $'5\n7'
        [[ "${concurrentChanged}" == "true" && "${mutationCount}" == "1" && "${syncCount}" == "0" ]]
        jq -e '.enabled == false' <<<"${targetPatch}" >/dev/null
        jq -e 'length == 1 and .[0].id == "alpha" and .[0].enabled == true' <<<"${expectedSnapshot}" >/dev/null
        subscriptionActiveGroupRead -e '.user_groups[0].enabled == false' >/dev/null
        grep -q '停用当前订阅' "${displayLog}"
    )

    (
        [[ "${caseGroup}" == all || "${caseGroup}" == editing ]] || exit 0
        local syncCount=0 mutationCount=0
        resetDraftFixture
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        eval "$(declare -f setUserSubscriptionsFields | sed '1s/^setUserSubscriptionsFields/originalSetUserSubscriptionsFields/')"
        setUserSubscriptionsFields() {
            mutationCount=$((mutationCount + 1))
            originalSetUserSubscriptionsFields "$@"
        }
        editUserSubscriptionsMenu '["alpha"]' <<< $'1,2,3,5,6\nAlpha revised\n1,2\n6'
        [[ "${mutationCount}" == "1" && "${syncCount}" == "1" ]]
        subscriptionActiveGroupRead -e '
          .sync.enabled == false and
          .user_groups[0].name == "Alpha revised" and
          (.user_groups[0].allowed_sources | sort) == ["edge","main"] and
          .user_groups[0].traffic_limit_gb == 6 and .user_groups[0].enabled == false and
          .user_groups[1].name == "Beta"
        ' >/dev/null
        editUserSubscriptionsMenu '["alpha","beta"]' <<< $'2,3,4,6\n2\n8'
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
        regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha"]' <<< $'6,2\n2,6,3\n2,7\n2,8\n9,6\n2,9\n2,2\n4,5,6\nmissing\n7'
        [[ "${mutationCount}" == "2" && "${syncCount}" == "2" ]]
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha","beta"]' <<< $'1,3,6\n7'
        [[ "${mutationCount}" == "2" && "${syncCount}" == "2" &&
            "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha"]' <<< $'1,2,3\nDiscarded\n1\n'
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        resetDraftFixture
        regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha"]' < <(printf '1,3,5,6\nDiscarded\n')
        [[ "${mutationCount}" == "2" && "${syncCount}" == "2" &&
            "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        editUserSubscriptionsMenu '["alpha"]' <<< $'1,3,5\nDrafted\ninvalid\n9\n'
        [[ "${mutationCount}" == "3" && "${syncCount}" == "3" ]]
        subscriptionActiveGroupRead -e '
          .user_groups[0].name == "Drafted" and
          .user_groups[0].traffic_limit_gb == 9 and .user_groups[0].enabled == false
        ' >/dev/null

        local openedIds=
        manageUserSubscriptionsMenu() { openedIds=$1; }
        manageSharedSubscriptions <<< $'1,2\n\n'
        jq -e 'sort == ["alpha","beta"]' <<<"${openedIds}" >/dev/null
    )

    (
        [[ "${caseGroup}" == all || "${caseGroup}" == conflicts ]] || exit 0
        local syncCount=0 mutationCount=0 pickedCount=0 trafficChanged=false expectedSnapshot=
        resetDraftFixture
        : >"${displayLog}"
        selectUserSubscriptionId <<<alpha
        grep -q '已超限' "${displayLog}"
        grep -q '用量' "${displayLog}"
        manageUserSubscriptionItem alpha <<<7
        [[ "$(grep -c '已超限' "${displayLog}")" -ge 2 ]]
        eval "$(declare -f menuReadChoice | sed '1s/^menuReadChoice/originalTrafficManagementMenuReadChoice/')"
        menuReadChoice() {
            local resultVar=$3
            originalTrafficManagementMenuReadChoice "$@" || return $?
            [[ "$1" != "select_user_subscription_id" ]] || pickedCount=$((pickedCount + 1))
            if [[ "$1" == "edit_user_subscription_menu" && -z "${!resultVar}" && "${trafficChanged}" == "false" ]]; then
                trafficChanged=true
                subscriptionActiveGroupWrite '.traffic.user_groups.alpha.sources.main.download += 100'
            fi
        }
        eval "$(declare -f setUserSubscriptionsFields | sed '1s/^setUserSubscriptionsFields/originalTrafficManagementSetUserSubscriptionsFields/')"
        setUserSubscriptionsFields() {
            mutationCount=$((mutationCount + 1))
            expectedSnapshot=$3
            originalTrafficManagementSetUserSubscriptionsFields "$@"
        }
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        selectUserSubscriptionTrafficMenu <<< $'alpha\n3\n3\n9\n\n7\n\n'
        [[ "${pickedCount}" == "1" && "${mutationCount}" == "1" && "${syncCount}" == "1" && "${trafficChanged}" == "true" ]]
        jq -e 'all(.[]; keys == ["allowed_sources","enabled","id","name","traffic_limit_gb","uuid"])' <<<"${expectedSnapshot}" >/dev/null
        subscriptionActiveGroupRead -e '
          .user_groups[0].traffic_limit_gb == 9 and
          .traffic.user_groups.alpha.sources.main.download == 101
        ' >/dev/null
    )

    (
        [[ "${caseGroup}" == all || "${caseGroup}" == conflicts ]] || exit 0
        local syncCount=0 mutationCount=0 identityChanged=false
        resetDraftFixture
        eval "$(declare -f menuReadChoice | sed '1s/^menuReadChoice/originalIdentityConflictMenuReadChoice/')"
        menuReadChoice() {
            local resultVar=$3
            originalIdentityConflictMenuReadChoice "$@" || return $?
            if [[ "${identityChanged}" == "false" &&
                ( "$1" == "edit_user_subscription_menu" && -z "${!resultVar}" ||
                  "$1" == "user_subscription_item_menu" && "${!resultVar}" == "5" ) ]]; then
                identityChanged=true
                subscriptionActiveGroupWrite '
                  .user_groups |= map(if .id == "alpha" then .uuid = "22222222-2222-4222-8222-222222222222" else . end)
                '
            fi
        }
        eval "$(declare -f setUserSubscriptionsFields | sed '1s/^setUserSubscriptionsFields/originalIdentityConflictSetUserSubscriptionsFields/')"
        setUserSubscriptionsFields() {
            mutationCount=$((mutationCount + 1))
            jq -e '.[0].uuid == "11111111-1111-4111-8111-111111111111"' <<<"$3" >/dev/null
            originalIdentityConflictSetUserSubscriptionsFields "$@"
        }
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha"]' <<< $'3\n9\n\n7'
        [[ "${identityChanged}" == "true" && "${mutationCount}" == "1" && "${syncCount}" == "0" ]]
        subscriptionActiveGroupRead -e '.user_groups[0].traffic_limit_gb == 1' >/dev/null
        resetDraftFixture
        identityChanged=false
        mutationCount=0
        manageUserSubscriptionItem alpha <<< $'5\n7'
        [[ "${identityChanged}" == "true" && "${mutationCount}" == "1" && "${syncCount}" == "0" ]]
        subscriptionActiveGroupRead -e '
          .user_groups[0].enabled and .user_groups[0].uuid == "22222222-2222-4222-8222-222222222222"
        ' >/dev/null
    )

    (
        [[ "${caseGroup}" == all || "${caseGroup}" == conflicts ]] || exit 0
        local toggleCount=0
        resetDraftFixture
        toggleSubscriptionGroupQuotaAutoApplyEnabled
        subscriptionActiveGroupRead -e '.sync.quota_auto_apply == true' >/dev/null
        toggleSubscriptionGroupQuotaAutoApplyEnabled
        subscriptionActiveGroupRead -e '.sync.quota_auto_apply == false' >/dev/null
        showSubscriptionTrafficOverview() { :; }
        eval "$(declare -f toggleSubscriptionGroupQuotaAutoApplyEnabled | sed '1s/^toggleSubscriptionGroupQuotaAutoApplyEnabled/originalConflictToggleSubscriptionGroupQuotaAutoApplyEnabled/')"
        toggleSubscriptionGroupQuotaAutoApplyEnabled() {
            toggleCount=$((toggleCount + 1))
            originalConflictToggleSubscriptionGroupQuotaAutoApplyEnabled "$@"
        }
        eval "$(declare -f menuReadChoice | sed '1s/^menuReadChoice/originalQuotaConflictMenuReadChoice/')"
        menuReadChoice() {
            local resultVar=$3
            originalQuotaConflictMenuReadChoice "$@" || return $?
            if [[ "$1" == "traffic_quota_menu" && "${!resultVar}" == "4" ]]; then
                subscriptionActiveGroupWrite '.sync.quota_auto_apply = true'
            fi
        }
        manageTrafficAndQuota <<< $'4\n5'
        [[ "${toggleCount}" == "1" ]]
        subscriptionActiveGroupRead -e '.sync.quota_auto_apply == true' >/dev/null
        (
            local stateWriteCount=0
            subscriptionActiveGroupRead() { return 1; }
            menuReadChoice() { originalQuotaConflictMenuReadChoice "$@"; }
            eval "$(declare -f subscriptionGroupsStateWriteUnlocked | sed '1s/^subscriptionGroupsStateWriteUnlocked/originalUnreadableQuotaStateWriteUnlocked/')"
            subscriptionGroupsStateWriteUnlocked() {
                stateWriteCount=$((stateWriteCount + 1))
                originalUnreadableQuotaStateWriteUnlocked "$@"
            }
            manageTrafficAndQuota <<< $'4\n5'
            manageTrafficAndQuota </dev/null
            [[ "${toggleCount}" == "1" && "${stateWriteCount}" == "0" ]]
        )
    )

    (
        [[ "${caseGroup}" == all || "${caseGroup}" == conflicts ]] || exit 0
        local scenario
        for scenario in field identity; do
            (
                local syncCount=0 mutationCount=0 changed=false targetPatch= expectedSnapshot=
                resetDraftFixture
                : >"${errorLog}"
                runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
                eval "$(declare -f menuReadChoice | sed '1s/^menuReadChoice/originalRefreshConflictMenuReadChoice/')"
                menuReadChoice() {
                    local resultVar=$3
                    originalRefreshConflictMenuReadChoice "$@" || return $?
                    if [[ "$1" == edit_user_subscription_menu && "${!resultVar}" == 9 && "${changed}" == false ]]; then
                        changed=true
                        if [[ "${scenario}" == field ]]; then
                            subscriptionActiveGroupWrite '.user_groups[0].name = "Concurrent name"'
                        else
                            subscriptionActiveGroupWrite '.user_groups[0].uuid = "22222222-2222-4222-8222-222222222222"'
                        fi
                    fi
                }
                eval "$(declare -f setUserSubscriptionsFields | sed '1s/^setUserSubscriptionsFields/originalRefreshConflictSetUserSubscriptionsFields/')"
                setUserSubscriptionsFields() {
                    mutationCount=$((mutationCount + 1))
                    targetPatch=$2
                    expectedSnapshot=$3
                    originalRefreshConflictSetUserSubscriptionsFields "$@"
                }
                regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha"]' <<< $'1\nRetained draft\n9\n6\n7'
                [[ "${changed}" == true && "${mutationCount}" == 1 && "${syncCount}" == 0 ]]
                jq -e '.name == "Retained draft"' <<<"${targetPatch}" >/dev/null
                jq -e '.[0].name == "Alpha" and .[0].uuid == "11111111-1111-4111-8111-111111111111"' \
                    <<<"${expectedSnapshot}" >/dev/null
                if [[ "${scenario}" == field ]]; then
                    grep -q '冲突字段：名称' "${errorLog}"
                    subscriptionActiveGroupRead -e '.user_groups[0].name == "Concurrent name"' >/dev/null
                else
                    grep -q '所选订阅身份已变化，无法保留草稿' "${errorLog}"
                    subscriptionActiveGroupRead -e '
                      .user_groups[0].name == "Alpha" and
                      .user_groups[0].uuid == "22222222-2222-4222-8222-222222222222"
                    ' >/dev/null
                fi
            )
        done
    )

    (
        [[ "${caseGroup}" == all || "${caseGroup}" == conflicts ]] || exit 0
        local syncCount=0 mutationCount=0 reorderSnapshot=false before
        resetDraftFixture
        setUserSubscriptionSources alpha '["main","edge"]'
        before=$(subscriptionGroupsStateRead -c '.')
        : >"${errorLog}"
        : >"${statusLog}"
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        setUserSubscriptionsFields() { mutationCount=$((mutationCount + 1)); return 99; }
        eval "$(declare -f menuReadChoice | sed '1s/^menuReadChoice/originalReorderRefreshMenuReadChoice/')"
        menuReadChoice() {
            local resultVar=$3
            originalReorderRefreshMenuReadChoice "$@" || return $?
            if [[ "$1" == edit_user_subscription_menu && "${!resultVar}" == 9 ]]; then
                reorderSnapshot=true
            fi
        }
        eval "$(declare -f subscriptionActiveGroupRead | sed '1s/^subscriptionActiveGroupRead/originalReorderRefreshGroupRead/')"
        subscriptionActiveGroupRead() {
            if [[ "${reorderSnapshot}" == true ]]; then
                originalReorderRefreshGroupRead "$@" | jq -c 'map(.allowed_sources |= reverse)'
            else
                originalReorderRefreshGroupRead "$@"
            fi
        }
        regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha"]' <<< $'2\n2\n9'
        grep -q '已刷新订阅状态，草稿仍保留' "${statusLog}"
        [[ ! -s "${errorLog}" && "${mutationCount}" == 0 && "${syncCount}" == 0 &&
            "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
    )

    (
        [[ "${caseGroup}" == all || "${caseGroup}" == recovery ]] || exit 0
        local syncCount=0 mutationCount=0 changed=false refreshSelected=false expectedSnapshot=
        resetDraftFixture
        : >"${displayLog}"
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        eval "$(declare -f menuReadChoice | sed '1s/^menuReadChoice/originalPreservedRefreshMenuReadChoice/')"
        menuReadChoice() {
            local resultVar=$3
            originalPreservedRefreshMenuReadChoice "$@" || return $?
            if [[ "$1" == edit_user_subscription_menu && "${!resultVar}" == 6 ]]; then
                if [[ "${refreshSelected}" == true ]]; then
                    [[ "${mutationCount}" == 1 && "${syncCount}" == 0 ]]
                elif [[ "${changed}" == false ]]; then
                    changed=true
                    subscriptionActiveGroupWrite '.user_groups[0].traffic_limit_gb = 11'
                fi
            elif [[ "$1" == edit_user_subscription_menu && "${!resultVar}" == 9 ]]; then
                refreshSelected=true
            fi
        }
        eval "$(declare -f setUserSubscriptionsFields | sed '1s/^setUserSubscriptionsFields/originalPreservedRefreshSetUserSubscriptionsFields/')"
        setUserSubscriptionsFields() {
            mutationCount=$((mutationCount + 1))
            expectedSnapshot=$3
            originalPreservedRefreshSetUserSubscriptionsFields "$@"
        }
        editUserSubscriptionsMenu '["alpha"]' <<< $'1\nRefreshed draft\n6\n9\n6'
        [[ "${changed}" == true && "${refreshSelected}" == true && "${mutationCount}" == 2 && "${syncCount}" == 1 ]]
        jq -e '.[0].name == "Alpha" and .[0].traffic_limit_gb == 11' <<<"${expectedSnapshot}" >/dev/null
        grep -q '当前订阅额度：11 GB' "${displayLog}"
        subscriptionActiveGroupRead -e '.user_groups[0].name == "Refreshed draft" and .user_groups[0].traffic_limit_gb == 11' >/dev/null
    )

    (
        [[ "${caseGroup}" == all || "${caseGroup}" == recovery ]] || exit 0
        local fault
        for fault in failure missing; do
            (
                local syncCount=0 mutationCount=0 failRefresh=false before
                resetDraftFixture
                before=$(subscriptionGroupsStateRead -c '.')
                : >"${displayLog}"
                : >"${errorLog}"
                runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
                setUserSubscriptionsFields() { mutationCount=$((mutationCount + 1)); return 99; }
                eval "$(declare -f menuReadChoice | sed '1s/^menuReadChoice/originalFailedRefreshMenuReadChoice/')"
                menuReadChoice() {
                    local resultVar=$3
                    originalFailedRefreshMenuReadChoice "$@" || return $?
                    if [[ "$1" == edit_user_subscription_menu && "${!resultVar}" == 9 ]]; then
                        failRefresh=true
                    fi
                }
                eval "$(declare -f subscriptionActiveGroupRead | sed '1s/^subscriptionActiveGroupRead/originalFailedRefreshGroupRead/')"
                subscriptionActiveGroupRead() {
                    if [[ "${failRefresh}" != true ]]; then
                        originalFailedRefreshGroupRead "$@"
                    elif [[ "${fault}" == failure ]]; then
                        return 1
                    else
                        printf '[]\n'
                    fi
                }
                regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha"]' <<< $'1\nUnsaved draft\n9'
                [[ "${failRefresh}" == true && "${mutationCount}" == 0 && "${syncCount}" == 0 &&
                    "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
                if [[ "${fault}" == failure ]]; then
                    [[ "$(grep -c '待保存字段：名称' "${displayLog}")" -ge 2 ]]
                else
                    grep -q '所选订阅已不存在，请重新选择' "${errorLog}"
                fi
            )
        done
    )

    (
        [[ "${caseGroup}" == all || "${caseGroup}" == recovery ]] || exit 0
        local syncCount=0 mutationCount=0
        resetDraftFixture
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        eval "$(declare -f setUserSubscriptionsFields | sed '1s/^setUserSubscriptionsFields/originalSetUserSubscriptionsFields/')"
        setUserSubscriptionsFields() {
            mutationCount=$((mutationCount + 1))
            [[ "${mutationCount}" != "1" ]] || return 1
            originalSetUserSubscriptionsFields "$@"
        }
        # 组合保存失败后，下一次空回车仍使用保留的草稿重试。
        editUserSubscriptionsMenu '["alpha"]' <<< $'1,3,6\nRetained draft\n9\n'
        [[ "${mutationCount}" == "2" && "${syncCount}" == "1" ]]
        subscriptionActiveGroupRead -e '.user_groups[0].name == "Retained draft" and .user_groups[0].traffic_limit_gb == 9' >/dev/null
    )

    (
        [[ "${caseGroup}" == all || "${caseGroup}" == recovery ]] || exit 0
        local syncCount=0
        resetDraftFixture
        runSubscriptionGroupSync() {
            syncCount=$((syncCount + 1))
            [[ "${syncCount}" != "1" ]]
        }
        editUserSubscriptionsMenu '["alpha"]' <<< $'1\nRetry after sync\n3\n3\n\n'
        [[ "${syncCount}" == "3" ]]
        subscriptionActiveGroupRead -e '.sync.enabled == false and .user_groups[0].name == "Retry after sync" and .user_groups[0].traffic_limit_gb == 3' >/dev/null
    )

    (
        [[ "${caseGroup}" == all || "${caseGroup}" == validation ]] || exit 0
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

        local mutationCount=0 targetPatch=
        resetDraftFixture
        subscriptionActiveGroupWrite '.sync.quota_auto_apply = true'
        eval "$(declare -f setUserSubscriptionsFields | sed '1s/^setUserSubscriptionsFields/originalNoopEnabledSetUserSubscriptionsFields/')"
        setUserSubscriptionsFields() {
            mutationCount=$((mutationCount + 1))
            targetPatch=$2
            originalNoopEnabledSetUserSubscriptionsFields "$@"
        }
        editUserSubscriptionsMenu '["alpha"]' <<< $'4,1,6\nQuota name only'
        [[ "${mutationCount}" == 1 && "${syncCount}" == 2 ]]
        jq -e 'keys == ["name"] and .name == "Quota name only"' <<<"${targetPatch}" >/dev/null
        subscriptionActiveGroupRead -e '
          .user_groups[0].name == "Quota name only" and .user_groups[0].enabled and .user_groups[0].traffic_limit_gb == 1
        ' >/dev/null
        resetDraftFixture
        subscriptionActiveGroupWrite '.sync.quota_auto_apply = true | .user_groups[0].enabled = false'
        before=$(subscriptionGroupsStateRead -c '.')
        regressionExpectStatus 1 editUserSubscriptionsMenu '["alpha","beta"]' <<< $'4,6\n7'
        [[ "${mutationCount}" == 2 && "${syncCount}" == 2 &&
            "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        jq -e 'keys == ["enabled"] and .enabled' <<<"${targetPatch}" >/dev/null
    )

    (
        [[ "${caseGroup}" == all || "${caseGroup}" == conflicts ]] || exit 0
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
        [[ "${caseGroup}" == all || "${caseGroup}" == recovery ]] || exit 0
        local syncCount=0 installCount=0 shownCount=0 shownId= shownIds= copySourcePromptCount=0 copyLimitPromptCount=0
        resetDraftFixture
        installSubscribe() { installCount=$((installCount + 1)); return 99; }
        runSubscriptionGroupSync() {
            syncCount=$((syncCount + 1))
            SUBSCRIPTION_SYNC_PUBLISHED=true
        }
        showPublishedSubscriptionLinks() {
            shownCount=$((shownCount + 1))
            shownId=$1
            shownIds=${2:-}
            return 1
        }
        eval "$(declare -f menuReadChoice | sed '1s/^menuReadChoice/originalCopyMenuReadChoice/')"
        menuReadChoice() {
            [[ "$1" != user_subscription_sources ]] || copySourcePromptCount=$((copySourcePromptCount + 1))
            [[ "$1" != user_subscription_traffic_limit ]] || copyLimitPromptCount=$((copyLimitPromptCount + 1))
            originalCopyMenuReadChoice "$@"
        }
        setUserSubscriptionEnabled alpha false
        createAndSyncUserSubscriptionWizard alpha <<< $'copied-alpha\n\n\n'
        [[ "${syncCount}" == "1" && "${installCount}" == "0" && "${createdUserSubscriptionId}" == "copied-alpha" &&
            "${shownCount}" == "1" && "${shownId}" == "copied-alpha" ]]
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
        [[ "${syncCount}" == "2" && "${installCount}" == "0" && "${shownCount}" == "2" &&
            "${shownId}" == "zero-template-copy" ]]
        subscriptionActiveGroupRead -e '
          any(.user_groups[]; .id == "zero-template-copy" and .traffic_limit_gb == 0 and .allowed_sources == ["main"])
        ' >/dev/null
        createAndSyncUserSubscriptionWizard alpha <<<"copied-batch-a, copied-batch-b"
        [[ "${syncCount}" == "3" && "${installCount}" == "0" && "${shownCount}" == "3" &&
            -z "${createdUserSubscriptionId}" && -z "${shownId}" &&
            "${createdUserSubscriptionIds}" == '["copied-batch-a","copied-batch-b"]' &&
            "${shownIds}" == "${createdUserSubscriptionIds}" &&
            "${copySourcePromptCount}" == "0" && "${copyLimitPromptCount}" == "0" ]]
        subscriptionActiveGroupRead -e '
          . as $state |
          ([$state.user_groups[] | select(.id == "copied-batch-a" or .id == "copied-batch-b")] |
            length == 2 and all(.[]; .allowed_sources == ["edge"] and .traffic_limit_gb == 1 and
              .enabled and (has("uuid") | not) and (has("token") | not))) and
          (($state.traffic.user_groups | has("copied-batch-a") or has("copied-batch-b")) | not) and
          ($state.user_groups[0].uuid == "11111111-1111-4111-8111-111111111111") and
          ($state.traffic.user_groups.alpha.sources.main.upload == 1073741824)
        ' >/dev/null
        local before
        before=$(subscriptionGroupsStateRead -c '.')
        regressionExpectStatus 1 createAndSyncUserSubscriptionWizard missing <<<"missing-copy-a,missing-copy-b"
        [[ -z "${createdUserSubscriptionId}" && "${createdUserSubscriptionIds}" == '[]' && "${syncCount}" == "3" &&
            "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        local raceInjected=false
        eval "$(declare -f addUserSubscriptionsState | sed '1s/^addUserSubscriptionsState/originalCopyRaceAddUserSubscriptionsState/')"
        addUserSubscriptionsState() {
            if [[ "${raceInjected}" == false ]]; then
                raceInjected=true
                originalCopyRaceAddUserSubscriptionsState '[{"id":"copy-raced","name":"Concurrent"}]' '["main"]' 0
                setUserSubscriptionsFields '["alpha"]' '{"allowed_sources":["main"],"traffic_limit_gb":6}'
            fi
            originalCopyRaceAddUserSubscriptionsState "$@"
        }
        createAndSyncUserSubscriptionWizard alpha <<< $'copy-raced,copy-race-unused\nalpha\ncopy-race-recovered'
        [[ "${syncCount}" == "4" && "${createdUserSubscriptionId}" == "copy-race-recovered" &&
            "${copySourcePromptCount}" == "0" && "${copyLimitPromptCount}" == "0" ]]
        subscriptionActiveGroupRead -e '
          any(.user_groups[]; .id == "copy-race-recovered" and .allowed_sources == ["edge"] and .traffic_limit_gb == 1) and
          any(.user_groups[]; .id == "alpha" and .allowed_sources == ["main"] and .traffic_limit_gb == 6) and
          all(.user_groups[]; .id != "copy-race-unused")
        ' >/dev/null
    )

    (
        [[ "${caseGroup}" == all || "${caseGroup}" == recovery ]] || exit 0
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

runSubscriptionMenuBatchRegression() (
    source "${PROJECT_ROOT}/shell/core/runtime.sh"
    source "${PROJECT_ROOT}/shell/subscription/groups.sh"
    source "${PROJECT_ROOT}/shell/subscription/menu.sh"
    local root="${TMP_DIR}/subscription-menu-batch"
    local fixture idsJson='["alpha","beta"]'
    export PADM_SUBSCRIPTION_GROUPS_DIR="${root}/groups"
    unset AUTO_INSTALL
    mkdir -p "${PADM_SUBSCRIPTION_GROUPS_DIR}"
    writeDefaultSubscriptionGroupsState "$(subscriptionGroupsFile)"
    addUserSubscriptionState alpha "Alpha" '["main"]' 1
    addUserSubscriptionState beta "Beta" '["main"]' 0
    addUserSubscriptionState gamma "Untouched" '["main"]' 3
    subscriptionActiveGroupWrite '
      .sync.enabled = false |
      .traffic.user_groups.alpha = {sources:{main:{upload:1073741825,download:0}}} |
      .traffic.user_groups.beta = {sources:{main:{upload:20,download:0}}} |
      .traffic.user_groups.gamma = {sources:{main:{upload:30,download:0}}}
    '
    fixture=$(subscriptionGroupsStateRead -c '.')

    echoContent() { :; }
    menuLine() { :; }
    menuItem() { :; }
    menuDangerItem() { :; }
    menuReturnItem() { :; }
    menuClose() { :; }
    errorCard() { :; }
    statusCard() { :; }
    warnCard() { :; }
    successCard() { :; }
    subscriptionRequireLocalPublisherRole() { return 0; }
    subscriptionSyncCreateLocalApplyBackups() { :; }
    subscriptionSyncReleaseLocalApplyBackups() { :; }
    resetBatchFixture() {
        subscriptionGroupsStateWrite --argjson fixture "${fixture}" '$fixture'
    }

    (
        local syncCount=0 viewedId= viewedIds=
        resetBatchFixture
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); return 1; }
        showPublishedSubscriptionLinks() { viewedId=${1:-}; viewedIds=${2:-}; }
        manageUserSubscriptionItem alpha <<< $'9\ncopy-route-a,copy-route-b\n1\n7'
        [[ "${syncCount}" == "1" && -z "${viewedId}" &&
            "${viewedIds}" == '["copy-route-a","copy-route-b"]' &&
            "${createdUserSubscriptionIds}" == "${viewedIds}" ]]
        subscriptionActiveGroupRead -e '
          [.user_groups[] | select(.id == "copy-route-a" or .id == "copy-route-b")] |
          length == 2 and all(.[]; .enabled and .allowed_sources == ["main"] and .traffic_limit_gb == 1 and
            (has("uuid") | not) and (has("token") | not))
        ' >/dev/null
        resetBatchFixture
    )

    (
        local syncCount=0 syncStatus=0 createCount=0 sourcePromptCount=0 limitPromptCount=0 selectorPromptCount=0
        local viewedId= viewedIds= trafficIds= scope before writeCount=0
        local -a templateArgs=()
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); return "${syncStatus}"; }
        showPublishedSubscriptionLinks() { viewedId=${1:-}; viewedIds=${2:-}; }
        showUserSubscriptionTraffic() { trafficIds+="$1,"; }
        eval "$(declare -f createAndSyncUserSubscriptionWizard | sed '1s/^createAndSyncUserSubscriptionWizard/originalDirectCreateAndSyncUserSubscriptionWizard/')"
        createAndSyncUserSubscriptionWizard() {
            createCount=$((createCount + 1))
            templateArgs+=("${1:-}")
            originalDirectCreateAndSyncUserSubscriptionWizard "$@"
        }
        eval "$(declare -f menuReadChoice | sed '1s/^menuReadChoice/originalDirectCreateMenuReadChoice/')"
        menuReadChoice() {
            case "$1" in
            user_subscription_sources) sourcePromptCount=$((sourcePromptCount + 1)) ;;
            user_subscription_traffic_limit) limitPromptCount=$((limitPromptCount + 1)) ;;
            select_user_subscription_id) selectorPromptCount=$((selectorPromptCount + 1)) ;;
            esac
            originalDirectCreateMenuReadChoice "$@"
        }
        resetDirectCreateFixture() {
            resetBatchFixture
            syncCount=0 syncStatus=0 createCount=0 sourcePromptCount=0 limitPromptCount=0 selectorPromptCount=0
            viewedId= viewedIds= trafficIds= writeCount=0
            templateArgs=()
        }

        resetDirectCreateFixture
        addSubscriptionSourceState edge "Edge" 203.0.113.20 39778
        subscriptionActiveGroupWrite '.user_groups[0].allowed_sources = ["edge"] | .user_groups[0].traffic_limit_gb = 6'
        manageUserSubscriptionsMenu '["alpha"]' <<< $'+\ndirect-new-single\n1\n0\n1\n2\n7'
        [[ "${syncCount}" == 1 && "${createCount}" == 1 && "${viewedId}" == direct-new-single &&
            -z "${viewedIds}" && "${trafficIds}" == direct-new-single, && -z "${templateArgs[0]}" &&
            "${sourcePromptCount}" == 1 && "${limitPromptCount}" == 1 && "${selectorPromptCount}" == 0 ]]
        subscriptionActiveGroupRead -e '
          any(.user_groups[]; .id == "direct-new-single" and .allowed_sources == ["main"] and .traffic_limit_gb == 0) and
          any(.user_groups[]; .id == "alpha" and .allowed_sources == ["edge"] and .traffic_limit_gb == 6)
        ' >/dev/null

        resetDirectCreateFixture
        manageUserSubscriptionsMenu "${idsJson}" <<< $'+\ndirect-new-batch-a,direct-new-batch-b\n1\n2\n1\n2\n7'
        [[ "${syncCount}" == 1 && "${createCount}" == 1 && -z "${viewedId}" && -z "${templateArgs[0]}" &&
            "${viewedIds}" == '["direct-new-batch-a","direct-new-batch-b"]' &&
            "${createdUserSubscriptionIds}" == "${viewedIds}" &&
            "${trafficIds}" == direct-new-batch-a,direct-new-batch-b, && "${selectorPromptCount}" == 0 ]]
        subscriptionActiveGroupRead -e '
          [.user_groups[] | select(.id == "direct-new-batch-a" or .id == "direct-new-batch-b")] |
          length == 2 and all(.[]; .allowed_sources == ["main"] and .traffic_limit_gb == 2)
        ' >/dev/null

        resetDirectCreateFixture
        syncStatus=1
        manageUserSubscriptionsMenu '["alpha"]' <<< $'+\ndirect-pending-a,direct-pending-b\n1\n0\n1\n2\n7'
        [[ "${syncCount}" == 1 && "${createCount}" == 1 && -z "${viewedId}" &&
            "${viewedIds}" == '["direct-pending-a","direct-pending-b"]' &&
            "${createdUserSubscriptionIds}" == "${viewedIds}" &&
            "${trafficIds}" == direct-pending-a,direct-pending-b, && "${selectorPromptCount}" == 0 ]]
        subscriptionActiveGroupRead -e '
          [.user_groups[] | select(.id == "direct-pending-a" or .id == "direct-pending-b")] | length == 2
        ' >/dev/null

        resetDirectCreateFixture
        manageUserSubscriptionsMenu "${idsJson}" <<< $'+\ndirect-batch-to-single\n1\n3\n9\ndirect-copy-from-new\n2\n7'
        [[ "${syncCount}" == 2 && "${createCount}" == 2 && -z "${templateArgs[0]}" &&
            "${templateArgs[1]}" == direct-batch-to-single && "${trafficIds}" == direct-copy-from-new, &&
            "${sourcePromptCount}" == 1 && "${limitPromptCount}" == 1 && "${selectorPromptCount}" == 0 ]]
        subscriptionActiveGroupRead -e '
          [.user_groups[] | select(.id == "direct-batch-to-single" or .id == "direct-copy-from-new")] |
          length == 2 and all(.[]; .allowed_sources == ["main"] and .traffic_limit_gb == 3)
        ' >/dev/null

        for scope in '["alpha"]' "${idsJson}"; do
            resetDirectCreateFixture
            before=$(subscriptionGroupsStateRead -c '.')
            manageUserSubscriptionsMenu "${scope}" <<< $'+\n\n2\n7'
            [[ "${syncCount}" == 0 && "${createCount}" == 1 && "${createdUserSubscriptionIds}" == '[]' &&
                "${sourcePromptCount}" == 0 && "${limitPromptCount}" == 0 && "${selectorPromptCount}" == 0 &&
                "${trafficIds}" == "$(jq -r 'join(",") + ","' <<<"${scope}")" &&
                "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
            (
                writeCount=0 trafficIds=
                subscriptionGroupsStateWriteUnlocked() { writeCount=$((writeCount + 1)); return 1; }
                manageUserSubscriptionsMenu "${scope}" <<< $'+\ndirect-write-failed\n1\n0\n2\n7'
                [[ "${writeCount}" == 1 && "${syncCount}" == 0 && "${createCount}" == 2 &&
                    "${createdUserSubscriptionIds}" == '[]' && "${selectorPromptCount}" == 0 &&
                    "${trafficIds}" == "$(jq -r 'join(",") + ","' <<<"${scope}")" &&
                    "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
            )
        done
        resetBatchFixture
    )

    (
        local mutationCount=0 writeCount=0 syncCount=0
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        eval "$(declare -f setUserSubscriptionsFields | sed '1s/^setUserSubscriptionsFields/originalSetUserSubscriptionsFields/')"
        setUserSubscriptionsFields() {
            mutationCount=$((mutationCount + 1))
            originalSetUserSubscriptionsFields "$@"
        }
        eval "$(declare -f subscriptionGroupsStateWriteUnlocked | sed '1s/^subscriptionGroupsStateWriteUnlocked/originalSubscriptionGroupsStateWriteUnlocked/')"
        subscriptionGroupsStateWriteUnlocked() {
            writeCount=$((writeCount + 1))
            originalSubscriptionGroupsStateWriteUnlocked "$@"
        }
        manageUserSubscriptionsMenu "${idsJson}" <<< $'10\n10\n5\n5\n7'
        [[ "${mutationCount}" == "2" && "${writeCount}" == "2" && "${syncCount}" == "2" ]]
        subscriptionActiveGroupRead -e '
          .sync.enabled == false and all(.user_groups[]; .enabled) and
          .user_groups[2].name == "Untouched" and .traffic.user_groups.gamma.sources.main.upload == 30
        ' >/dev/null
        resetBatchFixture
        setUserSubscriptionsFields "${idsJson}" '{"enabled":false}'
        subscriptionActiveGroupWrite '.sync.quota_auto_apply = true'
        local before
        before=$(subscriptionGroupsStateRead -c '.')
        mutationCount=0 writeCount=0 syncCount=0
        manageUserSubscriptionsMenu "${idsJson}" <<< $'5\n7'
        [[ "${mutationCount}" == "1" && "${writeCount}" == "1" && "${syncCount}" == "0" ]]
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
    )

    (
        local publicBase="${root}/public" localBase="${root}/local"
        local linkLog="${root}/links.log" trafficLog="${root}/traffic.log" id accountHash
        local syncCount=0 installCount=0 copyCount=0 before editedIds=
        resetBatchFixture
        setUserSubscriptionEnabled beta false
        before=$(subscriptionGroupsStateRead -c '.')
        export PADM_SUBSCRIBE_DIR="${publicBase}" PADM_SUBSCRIBE_LOCAL_DIR="${localBase}"
        mkdir -p "${publicBase}/default" "${localBase}/default"
        printf 'batch-salt\n' >"${localBase}/subscribeSalt"
        for id in alpha beta gamma; do
            accountHash=$(printf '%s\n' "$(subscriptionSyncAccountName "${id}")batch-salt" | md5sum | awk '{print $1}')
            printf 'published\n' >"${publicBase}/default/${accountHash}"
        done
        readNginxSubscribe() { subscribeDomain=links.example.com; subscribeType=https; subscribePort=39778; }
        showSubscriptionUrlCard() { printf '%s\n' "$*" >>"${linkLog}"; }
        showUserSubscriptionTraffic() { printf '%s\n' "$1" >>"${trafficLog}"; }
        installSubscribe() { installCount=$((installCount + 1)); return 99; }
        runSubscriptionGroupSync() {
            syncCount=$((syncCount + 1))
            SUBSCRIPTION_SYNC_PUBLISHED=true
        }
        createAndSyncUserSubscriptionWizard() {
            createdUserSubscriptionId=
            createdUserSubscriptionIds='[]'
            copyCount=$((copyCount + 1))
        }
        editUserSubscriptionsMenu() { editedIds=$1; }
        manageUserSubscriptionItem gamma <<< $'8\nalpha,beta\n1\n2\n4\n3\n9\n7'
        [[ "${syncCount}" == "1" && "${installCount}" == "0" && "${copyCount}" == "0" ]]
        [[ "${editedIds}" == "${idsJson}" ]]
        [[ "$(wc -l <"${linkLog}")" == "2" && "$(<"${trafficLog}")" == $'alpha\nbeta' ]]
        accountHash=$(printf '%s\n' "$(subscriptionSyncAccountName alpha)batch-salt" | md5sum | awk '{print $1}')
        [[ "$(grep -cF "${accountHash}" "${linkLog}")" == "2" ]]
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        setUserSubscriptionEnabled alpha false
        regressionExpectStatus 1 syncAndShowSubscriptionLinks "" "${idsJson}"
        [[ "${syncCount}" == "1" && "${installCount}" == "0" ]]
    )

    (
        local collectCount=0 writeCount=0 syncCount=0 confirmCount=0
        resetBatchFixture
        eval "$(declare -f menuReadChoice | sed '1s/^menuReadChoice/originalMenuReadChoice/')"
        menuReadChoice() {
            [[ "$1" != "remove_user_subscription_confirm" ]] || confirmCount=$((confirmCount + 1))
            originalMenuReadChoice "$@"
        }
        eval "$(declare -f subscriptionGroupsStateWriteUnlocked | sed '1s/^subscriptionGroupsStateWriteUnlocked/originalSubscriptionGroupsStateWriteUnlocked/')"
        subscriptionGroupsStateWriteUnlocked() {
            writeCount=$((writeCount + 1))
            originalSubscriptionGroupsStateWriteUnlocked "$@"
        }
        subscriptionLocalTrafficBaselineExists() { return 0; }
        collectSubscriptionTraffic() {
            collectCount=$((collectCount + 1))
            subscriptionActiveGroupWrite '.traffic.user_groups.alpha.sources.main.upload += 50'
            writeCount=0
        }
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        manageUserSubscriptionsMenu "${idsJson}" <<< $'6\nyes'
        [[ "${collectCount}" == "1" && "${writeCount}" == "1" &&
            "${syncCount}" == "1" && "${confirmCount}" == "1" ]]
        subscriptionActiveGroupRead -e '
          .user_groups | length == 1 and .[0].id == "gamma"
        ' >/dev/null
        subscriptionActiveGroupRead -e '
          (.traffic.user_groups | keys) == ["gamma"] and .traffic.user_groups.gamma.sources.main.upload == 30
        ' >/dev/null
    )

    (
        local collectCount=0 syncCount=0 expected before
        resetBatchFixture
        expected=$(subscriptionActiveGroupRead -c '[.user_groups[] | select(.id != "gamma") |
          {id,uuid,name,enabled,allowed_sources,traffic_limit_gb}]')
        subscriptionLocalTrafficBaselineExists() { return 0; }
        collectSubscriptionTraffic() { collectCount=$((collectCount + 1)); }
        runSubscriptionGroupSync() { syncCount=$((syncCount + 1)); }
        before=$(subscriptionGroupsStateRead -c '.')
        regressionExpectStatus 1 removeUserSubscriptionMenu "" '["alpha","missing"]' <<<yes
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" ]]
        subscriptionActiveGroupWrite '.user_groups |= map(if .id == "alpha" then
          .uuid = "44444444-4444-4444-4444-444444444444" else . end)'
        before=$(subscriptionGroupsStateRead -c '.')
        regressionExpectStatus 1 removeUserSubscriptionMenu "" "${idsJson}" "${expected}" <<<yes
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" && "${syncCount}" == "0" ]]
        expected=$(subscriptionActiveGroupRead -c '[.user_groups[] | select(.id != "gamma") |
          {id,uuid,name,enabled,allowed_sources,traffic_limit_gb}]')
        setUserSubscriptionTrafficLimit beta 4
        before=$(subscriptionGroupsStateRead -c '.')
        regressionExpectStatus 1 removeUserSubscriptionMenu "" "${idsJson}" "${expected}" <<<yes
        [[ "$(subscriptionGroupsStateRead -c '.')" == "${before}" &&
            "${collectCount}" == "3" && "${syncCount}" == "0" ]]
    )

    (
        local syncCount=0 collectCount=0
        resetBatchFixture
        subscriptionSyncRestoreConfigBackups() { :; }
        subscriptionSyncRestoreSubscribeOutputBackups() { :; }
        subscriptionSyncReconcileLocalServices() { :; }
        subscriptionSyncMarkResult() { :; }
        subscriptionLocalTrafficBaselineExists() { return 0; }
        collectSubscriptionTraffic() {
            collectCount=$((collectCount + 1))
            subscriptionActiveGroupWrite '
              .traffic.user_groups.alpha.sources.main.upload += 50 |
              .traffic.user_groups.beta.sources.main.upload += 50 |
              .traffic.sources.main = {upload:50,download:0}
            '
        }
        runSubscriptionGroupSync() {
            syncCount=$((syncCount + 1))
            subscriptionActiveGroupWrite '.traffic.sources.main.upload += 25'
            return 1
        }
        regressionExpectStatus 1 removeUserSubscriptionMenu "" "${idsJson}" <<<yes
        [[ "${collectCount}" == "1" && "${syncCount}" == "2" ]]
        subscriptionActiveGroupRead -e '
          (.user_groups | map(.id)) == ["alpha","beta","gamma"] and
          .traffic.user_groups.alpha.sources.main.upload == 1073741875 and
          .traffic.user_groups.beta.sources.main.upload == 70 and
          .traffic.user_groups.gamma.sources.main.upload == 30 and .traffic.sources.main.upload == 100
        ' >/dev/null
    )
)
