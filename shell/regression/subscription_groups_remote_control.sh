#!/usr/bin/env bash
set -euo pipefail

REGRESSION_ENTRY_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
REMOTE_CONTROL_SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")"
# shellcheck source=/dev/null
source "${REGRESSION_ENTRY_DIR}/regression/bootstrap.sh"

SUBSCRIBE_CAPTURE_DIR="${TMP_DIR}/subscribe_local"
configPath="${TMP_DIR}/xray-conf/"
singBoxConfigPath="${TMP_DIR}/sing-box-conf/"

remoteControlRegressionSourceId() {
    local source=$1
    local id=${source#*\"id\":\"}
    printf '%s\n' "${id%%\"*}"
}

runRemoteControlConcurrencyRegression() (
    local healthResult
    local planResult

    subscriptionRemoteControlSources() {
        cat <<'JSON'
[{"id":"src0","name":"Src0"},{"id":"src2","name":"Src2"},{"id":"src10","name":"Src10"}]
JSON
    }
    subscriptionRemoteControlPayload() {
        local source=$1
        local dryRun=$2
        local sourceId
        sourceId=$(remoteControlRegressionSourceId "${source}")
        printf '{"version":1,"group_id":"default","source_id":"%s","dry_run":%s,"desired_users":[]}\n' "${sourceId}" "${dryRun}"
    }

    subscriptionRemoteControlHealth() {
        local source=$1
        local id
        id=$(remoteControlRegressionSourceId "${source}")
        [[ "${id}" == "src0" ]] && sleep 0.01
        printf '{"id":"%s","name":"%s","ok":true}\n' "${id}" "${id}"
    }

    subscriptionRemoteSyncPlanForSource() {
        local source=$1
        local sourceId
        sourceId=$(remoteControlRegressionSourceId "${source}")
        [[ "${sourceId}" == "src0" ]] && sleep 0.01
        printf '{"source_id":"%s","status":"success","dry_run":true,"request":{"source_id":"%s"},"response":{"ok":true,"changed":false,"plan":{"create":[],"remove":[]}}}\n' "${sourceId}" "${sourceId}"
    }

    healthResult=$(subscriptionRemoteControlHealthAll | jq -c .)
    [[ "${healthResult}" == *'"id":"src0"'*'"id":"src2"'*'"id":"src10"'* ]]

    planResult=$(subscriptionRemoteSyncPlan | jq -c .)
    [[ "${planResult}" == *'"source_id":"src0"'*'"source_id":"src2"'*'"source_id":"src10"'* ]]
    [[ "${planResult}" == *'"status":"success"'* ]]
)

runRemoteControlAggregationFailureRegression() (
    local healthResult
    local planResult

    subscriptionRemoteControlSources() {
        cat <<'JSON'
[{"id":"edge-a","name":"Edge A"},{"id":"edge-b","name":"Edge B"}]
JSON
    }
    subscriptionRemoteControlPayload() {
        local source=$1
        local dryRun=$2
        local sourceId
        sourceId=$(remoteControlRegressionSourceId "${source}")
        printf '{"version":1,"group_id":"default","source_id":"%s","dry_run":%s,"desired_users":[]}\n' "${sourceId}" "${dryRun}"
    }

    subscriptionRemoteControlHealth() {
        local source=$1
        case "$(remoteControlRegressionSourceId "${source}")" in
        edge-a)
            printf '{"id":"edge-a","name":"Edge A","ok":true}\n'
            ;;
        edge-b)
            printf 'broken-health-json\n'
            ;;
        *)
            printf '{"id":"main","name":"Main","ok":true}\n'
            ;;
        esac
    }
    subscriptionRemoteSyncPlanForSource() {
        local source=$1
        case "$(remoteControlRegressionSourceId "${source}")" in
        edge-a)
            printf '{"source_id":"edge-a","status":"success","dry_run":true,"request":{"source_id":"edge-a"},"response":{"ok":true,"changed":false,"plan":{"create":[],"remove":[]}}}\n'
            ;;
        edge-b)
            printf 'broken-plan-json\n'
            ;;
        *)
            printf '{"source_id":"main","status":"success","dry_run":true,"request":{"source_id":"main"},"response":{"ok":true,"changed":false,"plan":{"create":[],"remove":[]}}}\n'
            ;;
        esac
    }

    healthResult=$(subscriptionRemoteControlHealthAll | jq -c .)
    [[ "${healthResult}" == *'"id":"edge-a"'*'"status":"internal_error"'*'"type":"internal_error"'* ]]

    planResult=$(subscriptionRemoteSyncPlan | jq -c .)
    [[ "${planResult}" == *'"source_id":"edge-a"'*'"status":"success"'* ]]
    [[ "${planResult}" == *'"status":"internal_error"'*'"type":"internal_error"'* ]]
)

runRemoteControlHealthRegression() (
    local sourceMissing='{"id":"edge-missing","name":"Edge Missing","scheme":"wireguard","transport":"wireguard","host":"remote.example","port":443}'
    local sourceRemote='{"id":"edge-remote","name":"Edge Remote","control_token":"token","scheme":"wireguard","transport":"wireguard","host":"remote.example","port":443}'
    local sourceUnauthorized='{"id":"edge-auth","name":"Edge Auth","control_token":"token","scheme":"wireguard","transport":"wireguard","host":"remote.example","port":443}'
    local response

    curl() {
        case "${PADM_FAKE_REMOTE_HEALTH_MODE:-}" in
        unauthorized)
            printf '{"ok":false,"error":"unauthorized"}\n401'
            ;;
        remote_error)
            printf '{"ok":false,"error":"service_unavailable","error_detail":{"type":"service_unavailable","message":"服务暂时不可用"}}\n503'
            ;;
        success)
            printf '{"ok":true,"version":"test","capabilities":["health","sync"]}\n200'
            ;;
        *)
            printf '{"ok":false,"error":"unexpected"}\n500'
            ;;
        esac
    }

    response=$(subscriptionRemoteControlHealth "${sourceMissing}" | jq -c .)
    [[ "${response}" == *'"status":"missing_token"'* ]]
    [[ "${response}" == *'"type":"missing_token"'* ]]
    [[ "${response}" == *'未配置控制 token'* ]]

    response=$(PADM_FAKE_REMOTE_HEALTH_MODE=unauthorized subscriptionRemoteControlHealth "${sourceUnauthorized}" | jq -c .)
    [[ "${response}" == *'"status":"unauthorized"'* ]]
    [[ "${response}" == *'"status_code":"401"'* ]]
    [[ "${response}" == *'"type":"unauthorized"'* ]]
    [[ "${response}" == *'控制 token 验证失败'* ]]

    response=$(PADM_FAKE_REMOTE_HEALTH_MODE=remote_error subscriptionRemoteControlHealth "${sourceRemote}" | jq -c .)
    [[ "${response}" == *'"status":"remote_error"'* ]]
    [[ "${response}" == *'"status_code":"503"'* ]]
    [[ "${response}" == *'"type":"remote_error"'* ]]
    [[ "${response}" == *'服务暂时不可用'* ]]

    response=$(PADM_FAKE_REMOTE_HEALTH_MODE=success subscriptionRemoteControlHealth "${sourceRemote}" | jq -c .)
    [[ "${response}" == *'"ok":true'* ]]
    [[ "${response}" == *'"version":"test"'* ]]
    [[ "${response}" == *'"capabilities":["health","sync"]'* ]]
    [[ "${response}" == *'"id":"edge-remote"'* ]]
    [[ "${response}" == *'"name":"Edge Remote"'* ]]
)

runRemoteControlServerRefreshRegression() (
    local refreshMode=${1:-full}
    local lightMode=${2:-all}
    local lightModeTag=${lightMode}
    local runLightSections=true
    local runLightApplySections=false
    local runLightApplyBasicSections=false
    local runLightApplyPrepareSections=false
    local runLightApplyFailureSections=false
    local runLightRestoreSections=false
    local runLightReconcileSections=false
    local runDeepSections=true
    local subscribeCalls=0
    local subscribeArgs=
    local reconcileCalls=0
    local responseFile="${TMP_DIR}/remote-control-server-refresh-${refreshMode}-${lightModeTag}.json"
    local oldConfigPath="${configPath:-}"
    local oldSingBoxConfigPath="${singBoxConfigPath:-}"
    local rollbackRoot="${TMP_DIR}/remote-control-rollback"
    local rollbackStateBefore
    local rollbackFirstBefore
    local rollbackSecondBefore
    local oldCoreInstallType="${coreInstallType:-}"
    local setUsersCalls=0
    local rollbackExpectedFile="${TMP_DIR}/remote-control-rollback-expected.json"
    local lightweightBackupRoot="${TMP_DIR}/remote-control-lightweight-backups-${refreshMode}-${lightModeTag}"
    local lightweightConfigIndex=0
    local lightweightOutputIndex=0
    local controlApplyCaptureFile="${TMP_DIR}/remote-control-apply-response-${refreshMode}-${lightModeTag}.json"

    case "${refreshMode}" in
    light)
        runDeepSections=false
        case "${lightMode}" in
        all)
            runLightApplySections=true
            runLightApplyBasicSections=true
            runLightApplyPrepareSections=true
            runLightApplyFailureSections=true
            runLightRestoreSections=true
            runLightReconcileSections=true
            ;;
        apply)
            runLightApplySections=true
            runLightApplyBasicSections=true
            runLightApplyPrepareSections=true
            runLightApplyFailureSections=true
            ;;
        apply-basic)
            runLightApplySections=true
            runLightApplyBasicSections=true
            ;;
        apply-prepare)
            runLightApplySections=true
            runLightApplyPrepareSections=true
            ;;
        apply-failure)
            runLightApplySections=true
            runLightApplyFailureSections=true
            ;;
        restore)
            runLightRestoreSections=true
            ;;
        reconcile)
            runLightReconcileSections=true
            ;;
        *)
            printf 'unknown remote-control server refresh light mode: %s\n' "${lightMode}" >&2
            return 2
            ;;
        esac
        ;;
    deep)
        runLightSections=false
        ;;
    full)
        runLightApplySections=true
        runLightApplyBasicSections=true
        runLightApplyPrepareSections=true
        runLightApplyFailureSections=true
        runLightRestoreSections=true
        runLightReconcileSections=true
        ;;
    *)
        printf 'unknown remote-control server refresh mode: %s\n' "${refreshMode}" >&2
        return 2
        ;;
    esac

    eval "$(declare -f subscriptionControlApplyAccountPlan | sed '1s/^subscriptionControlApplyAccountPlan/originalSubscriptionControlApplyAccountPlan/')"
    eval "$(declare -f subscriptionSyncSetUsersInFile | sed '1s/^subscriptionSyncSetUsersInFile/originalSubscriptionSyncSetUsersInFile/')"
    eval "$(declare -f subscriptionSyncPlanFromAccounts | sed '1s/^subscriptionSyncPlanFromAccounts/originalSubscriptionSyncPlanFromAccounts/')"
    eval "$(declare -f subscriptionSyncCreateConfigBackups | sed '1s/^subscriptionSyncCreateConfigBackups/originalSubscriptionSyncCreateConfigBackups/')"
    eval "$(declare -f subscriptionSyncCreateSubscribeOutputBackups | sed '1s/^subscriptionSyncCreateSubscribeOutputBackups/originalSubscriptionSyncCreateSubscribeOutputBackups/')"
    eval "$(declare -f subscriptionSyncRestoreConfigBackups | sed '1s/^subscriptionSyncRestoreConfigBackups/originalSubscriptionSyncRestoreConfigBackups/')"
    eval "$(declare -f subscriptionSyncRestoreSubscribeOutputBackups | sed '1s/^subscriptionSyncRestoreSubscribeOutputBackups/originalSubscriptionSyncRestoreSubscribeOutputBackups/')"
    eval "$(declare -f subscriptionGroupsStateRead | sed '1s/^subscriptionGroupsStateRead/originalSubscriptionGroupsStateRead/')"
    eval "$(declare -f subscriptionGroupsStateWrite | sed '1s/^subscriptionGroupsStateWrite/originalSubscriptionGroupsStateWrite/')"

    useLightweightSyncBackups() {
        subscriptionSyncCreateConfigBackups() {
            local backupDir
            printf -v backupDir '%s/config-%02d' "${lightweightBackupRoot}" "${lightweightConfigIndex}"
            lightweightConfigIndex=$((lightweightConfigIndex + 1))
            mkdir -p "${backupDir}" || return 1
            printf '%s\n' "${backupDir}"
        }
        subscriptionSyncCreateSubscribeOutputBackups() {
            local backupDir
            printf -v backupDir '%s/output-%02d' "${lightweightBackupRoot}" "${lightweightOutputIndex}"
            lightweightOutputIndex=$((lightweightOutputIndex + 1))
            mkdir -p "${backupDir}" || return 1
            printf '%s\n' "${backupDir}"
        }
        subscriptionSyncRestoreConfigBackups() {
            return 0
        }
        subscriptionSyncRestoreSubscribeOutputBackups() {
            return 0
        }
    }

    useRealSyncBackups() {
        subscriptionSyncCreateConfigBackups() {
            originalSubscriptionSyncCreateConfigBackups "$@"
        }
        subscriptionSyncCreateSubscribeOutputBackups() {
            originalSubscriptionSyncCreateSubscribeOutputBackups "$@"
        }
        subscriptionSyncRestoreConfigBackups() {
            originalSubscriptionSyncRestoreConfigBackups "$@"
        }
        subscriptionSyncRestoreSubscribeOutputBackups() {
            originalSubscriptionSyncRestoreSubscribeOutputBackups "$@"
        }
    }

    defaultRemoteControlGroupsStateJson() {
        cat <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    }

    setVirtualSubscriptionGroupsState() {
        virtualGroupsState=$1
    }

    virtualSubscriptionGroupsStateRead() {
        jq "$@" <<<"${virtualGroupsState}"
    }

    virtualSubscriptionGroupsStateWrite() {
        local nextState
        nextState=$(jq "$@" <<<"${virtualGroupsState}") || return 1
        virtualGroupsState=${nextState}
    }

    useVirtualSubscriptionGroupsState() {
        subscriptionGroupsStateRead() {
            virtualSubscriptionGroupsStateRead "$@"
        }
        subscriptionGroupsStateWrite() {
            virtualSubscriptionGroupsStateWrite "$@"
        }
    }

    useRealSubscriptionGroupsState() {
        subscriptionGroupsStateRead() {
            originalSubscriptionGroupsStateRead "$@"
        }
        subscriptionGroupsStateWrite() {
            originalSubscriptionGroupsStateWrite "$@"
        }
    }

    resetVirtualSubscriptionGroupsState() {
        setVirtualSubscriptionGroupsState "$(defaultRemoteControlGroupsStateJson)"
    }

    setupLightweightControlApplyFixtures() {
        subscriptionSyncPlanFromAccounts() {
            printf '{"create":["sub_team_a"],"remove":[]}'
        }
        subscriptionControlApplyAccountPlan() {
            return 0
        }
        subscribe() {
            subscribeCalls=$((subscribeCalls + 1))
            subscribeArgs="$*"
        }
        subscriptionSyncReconcileLocalServices() {
            reconcileCalls=$((reconcileCalls + 1))
        }
    }

    mkdir -p "${lightweightBackupRoot}"
    useLightweightSyncBackups
    useVirtualSubscriptionGroupsState
    resetVirtualSubscriptionGroupsState

    if [[ "${runLightSections}" == "true" ]]; then
        setupLightweightControlApplyFixtures

        responseHasErrorType() {
            local response=$1
            local errorName=$2
            jq -e --arg errorName "${errorName}" '.error == $errorName and .error_detail.type == $errorName' <<<"${response}" >/dev/null
        }

        responseHasPlanCreateEntry() {
            local response=$1
            local expected=$2
            jq -e --arg expected "${expected}" '.plan.create == [$expected]' <<<"${response}" >/dev/null
        }

        responseHasPlanRemoveEmpty() {
            local response=$1
            jq -e '.plan.remove == []' <<<"${response}" >/dev/null
        }

        responseHasChangedAndDryRun() {
            local response=$1
            local changed=$2
            local dryRun=$3
            jq -e --argjson changed "${changed}" --argjson dryRun "${dryRun}" '.changed == $changed and .dry_run == $dryRun' <<<"${response}" >/dev/null
        }

        responseHasApplySuccess() {
            local response=$1
            local changed=$2
            local dryRun=$3
            jq -e --argjson changed "${changed}" --argjson dryRun "${dryRun}" '.ok == true and .changed == $changed and .dry_run == $dryRun' <<<"${response}" >/dev/null
        }

        runControlApplyCapture() {
            local responseVar=$1
            local statusVar=$2
            local applyMode=$3
            local payload=$4
            local response=
            local commandStatus

            : >"${controlApplyCaptureFile}" || return 1
            set +e
            case "${applyMode}" in
            server)
                PADM_CONTROL_SERVER=1 subscriptionControlApplySync "${payload}" >"${controlApplyCaptureFile}"
                ;;
            local)
                PADM_CONTROL_SERVER= subscriptionControlApplySync "${payload}" >"${controlApplyCaptureFile}"
                ;;
            *)
                printf 'unknown remote control apply mode: %s\n' "${applyMode}" >&2
                return 2
                ;;
            esac
            commandStatus=$?
            set -e
            response=$(<"${controlApplyCaptureFile}")
            printf -v "${responseVar}" '%s' "${response}"
            printf -v "${statusVar}" '%s' "${commandStatus}"
        }

        if [[ "${runLightApplySections}" == "true" ]]; then
            if [[ "${runLightApplyBasicSections}" == "true" ]]; then
                local invalidEmptyIdResponse invalidDuplicateResponse invalidUuidResponse
                local invalidEmptyIdStatus invalidDuplicateStatus invalidUuidStatus
                runControlApplyCapture invalidEmptyIdResponse invalidEmptyIdStatus local '{"desired_users":[{"id":"","uuid":""}]}'
                runControlApplyCapture invalidDuplicateResponse invalidDuplicateStatus local '{"desired_users":[{"id":"team-a"},{"id":"team-a"}]}'
                runControlApplyCapture invalidUuidResponse invalidUuidStatus local '{"desired_users":[{"id":"team-a","uuid":123}]}'
                [[ "${invalidEmptyIdStatus}" -ne 0 ]]
                [[ "${invalidDuplicateStatus}" -ne 0 ]]
                [[ "${invalidUuidStatus}" -ne 0 ]]
                responseHasErrorType "${invalidEmptyIdResponse}" invalid_payload
                responseHasErrorType "${invalidDuplicateResponse}" invalid_payload
                responseHasErrorType "${invalidUuidResponse}" invalid_payload

                subscriptionSyncPlanFromAccounts() {
                    printf '{"create":["sub_team_a"],"remove":[]}'
                }
                local remoteSuccessResponse localSuccessResponse
                local remoteSuccessStatus localSuccessStatus
                runControlApplyCapture remoteSuccessResponse remoteSuccessStatus server '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}'
                [[ "${remoteSuccessStatus}" -eq 0 ]]
                responseHasApplySuccess "${remoteSuccessResponse}" true false
                [[ "${subscribeCalls}" == "1" ]]
                [[ "${subscribeArgs}" == "false false" ]]
                [[ "${reconcileCalls}" == "0" ]]

                runControlApplyCapture localSuccessResponse localSuccessStatus local '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}'
                [[ "${localSuccessStatus}" -eq 0 ]]
                responseHasApplySuccess "${localSuccessResponse}" true false
                [[ "${subscribeCalls}" == "1" ]]
                [[ "${reconcileCalls}" == "1" ]]
            fi

            if [[ "${runLightApplyPrepareSections}" == "true" ]]; then
                (
                    local prepareResponse
                    local prepareStatus
                    resetVirtualSubscriptionGroupsState
                    subscriptionSyncCreateConfigBackups() {
                        return 1
                    }
                    runControlApplyCapture prepareResponse prepareStatus server '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}'
                    [[ "${prepareStatus}" -ne 0 ]]
                    responseHasErrorType "${prepareResponse}" prepare_failed
                    responseHasChangedAndDryRun "${prepareResponse}" false false
                    [[ "${prepareResponse}" == *'配置备份失败'* ]]
                    responseHasPlanCreateEntry "${prepareResponse}" sub_team_a
                    responseHasPlanRemoveEmpty "${prepareResponse}"
                )

                (
                    local prepareRoot="${TMP_DIR}/remote-control-prepare-output-failure"
                    local prepareResponse
                    local expectedBackupDir="${prepareRoot}/created-backup"
                    local prepareStatus
                    resetVirtualSubscriptionGroupsState
                    subscriptionSyncCreateConfigBackups() {
                        local backupPath="${expectedBackupDir}"
                        mkdir -p "${backupPath}" || return 1
                        printf '%s\n' "${backupPath}"
                    }
                    subscriptionSyncCreateSubscribeOutputBackups() {
                        return 1
                    }
                    runControlApplyCapture prepareResponse prepareStatus server '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}'
                    [[ "${prepareStatus}" -ne 0 ]]
                    responseHasErrorType "${prepareResponse}" prepare_failed
                    responseHasChangedAndDryRun "${prepareResponse}" false false
                    [[ "${prepareResponse}" == *'订阅输出备份失败'* ]]
                    responseHasPlanCreateEntry "${prepareResponse}" sub_team_a
                    responseHasPlanRemoveEmpty "${prepareResponse}"
                    [[ ! -e "${expectedBackupDir}" ]]
                )
            fi

            if [[ "${runLightApplyFailureSections}" == "true" ]]; then
                subscribe() {
                    subscribeCalls=$((subscribeCalls + 1))
                    subscribeArgs="$*"
                    return 1
                }
                local refreshFailureResponse applyFailureResponse
                local refreshStatus applyStatus
                runControlApplyCapture refreshFailureResponse refreshStatus server '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}'
                [[ "${refreshStatus}" -ne 0 ]]
                responseHasErrorType "${refreshFailureResponse}" refresh_failed

                subscriptionControlApplyAccountPlan() {
                    return 1
                }
                runControlApplyCapture applyFailureResponse applyStatus server '{"desired_users":[{"id":"team-b","uuid":"22222222-2222-2222-2222-222222222222"}],"dry_run":false}'
                [[ "${applyStatus}" -ne 0 ]]
                responseHasErrorType "${applyFailureResponse}" apply_plan_failed
            fi
        fi

        if [[ "${runLightRestoreSections}" == "true" ]]; then
            (
                local restoreFailureStateWriteCalls=0
                local restoreFailureResponse
                local restoreFailureStatus
                setVirtualSubscriptionGroupsState '{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":false,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"00000000-0000-0000-0000-000000000000"}],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}'
                subscriptionSyncPlanFromAccounts() {
                    printf '{"create":["sub_team_a"],"remove":[]}'
                }
                subscriptionControlApplyAccountPlan() {
                    originalSubscriptionControlApplyAccountPlan "$@"
                }
                subscriptionSyncApplyAccountPlanTransaction() {
                    return 1
                }
                subscriptionGroupsStateWrite() {
                    restoreFailureStateWriteCalls=$((restoreFailureStateWriteCalls + 1))
                    if [[ "${restoreFailureStateWriteCalls}" == "2" ]]; then
                        return 1
                    fi
                    virtualSubscriptionGroupsStateWrite "$@"
                }
                runControlApplyCapture restoreFailureResponse restoreFailureStatus server '{"desired_users":[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}],"dry_run":false}'
                [[ "${restoreFailureStatus}" -ne 0 ]]
                responseHasErrorType "${restoreFailureResponse}" apply_plan_failed
                [[ "${restoreFailureResponse}" == *'订阅状态恢复失败'* ]]
                jq -e '.groups[0].user_groups[0].enabled == false and .groups[0].user_groups[0].allowed_sources == ["*"] and .groups[0].user_groups[0].uuid == "11111111-1111-1111-1111-111111111111"' <<<"${virtualGroupsState}" >/dev/null
            )

            (
                local restoreOrderLog="${TMP_DIR}/remote-control-restore-order.log"
                local restoreOrderConfig="${TMP_DIR}/remote-control-restore-config"
                local restoreOrderOutput="${TMP_DIR}/remote-control-restore-output"
                mkdir -p "${restoreOrderConfig}" "${restoreOrderOutput}"
                subscriptionGroupsStateWrite() {
                    printf 'state\n' >>"${restoreOrderLog}"
                    return 0
                }
                subscriptionSyncRestoreConfigBackups() {
                    printf 'config\n' >>"${restoreOrderLog}"
                    return 1
                }
                subscriptionSyncRestoreSubscribeOutputBackups() {
                    printf 'output\n' >>"${restoreOrderLog}"
                    return 0
                }
                SUBSCRIPTION_CONTROL_RESTORE_ERROR=
                rm -f "${restoreOrderLog}"
                set +e
                subscriptionControlRestoreAppliedPlan '{"version":2,"groups":[]}' "${restoreOrderConfig}" "${restoreOrderOutput}"
                local restoreOrderStatus=$?
                set -e
                [[ "${restoreOrderStatus}" -eq 1 ]]
                grep -qx 'state' "${restoreOrderLog}"
                grep -qx 'config' "${restoreOrderLog}"
                grep -qx 'output' "${restoreOrderLog}"
                [[ "${SUBSCRIPTION_CONTROL_RESTORE_ERROR}" == *"配置恢复失败"* ]]
            )

            (
                local restoreOrderLog="${TMP_DIR}/remote-control-restore-order-state.log"
                local restoreOrderConfig="${TMP_DIR}/remote-control-restore-config-state"
                local restoreOrderOutput="${TMP_DIR}/remote-control-restore-output-state"
                mkdir -p "${restoreOrderConfig}" "${restoreOrderOutput}"
                subscriptionGroupsStateWrite() {
                    printf 'state\n' >>"${restoreOrderLog}"
                    return 1
                }
                subscriptionSyncRestoreConfigBackups() {
                    printf 'config\n' >>"${restoreOrderLog}"
                    return 0
                }
                subscriptionSyncRestoreSubscribeOutputBackups() {
                    printf 'output\n' >>"${restoreOrderLog}"
                    return 0
                }
                SUBSCRIPTION_CONTROL_RESTORE_ERROR=
                rm -f "${restoreOrderLog}"
                set +e
                subscriptionControlRestoreAppliedPlan '{"version":2,"groups":[]}' "${restoreOrderConfig}" "${restoreOrderOutput}"
                local restoreOrderStatus=$?
                set -e
                [[ "${restoreOrderStatus}" -eq 1 ]]
                grep -qx 'state' "${restoreOrderLog}"
                grep -qx 'config' "${restoreOrderLog}"
                grep -qx 'output' "${restoreOrderLog}"
                [[ "${SUBSCRIPTION_CONTROL_RESTORE_ERROR}" == *"状态恢复失败"* ]]
            )
        fi
    fi

    if [[ "${runDeepSections}" == "true" ]]; then
        useRealSyncBackups
        useRealSubscriptionGroupsState
        mkdir -p "$(dirname "$(subscriptionGroupsFile)")"
        cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON

        mkdir -p "${rollbackRoot}/xray"
        configPath="${rollbackRoot}/xray/"
        singBoxConfigPath="${rollbackRoot}/xray/"
        cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[]}}]}
JSON
        cat >"${configPath}03_VLESS_WS_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[]}}]}
JSON
        cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
        coreInstallType=1
        subscriptionSyncPlanFromAccounts() {
            printf '{"create":["sub_rollback"],"remove":[]}'
        }
        rollbackStateBefore=$(<"$(subscriptionGroupsFile)")
        rollbackFirstBefore=$(<"${configPath}02_VLESS_TCP_inbounds.json")
        rollbackSecondBefore=$(<"${configPath}03_VLESS_WS_inbounds.json")
        subscriptionControlApplyAccountPlan() {
            originalSubscriptionControlApplyAccountPlan "$@"
        }
        subscriptionSyncSetUsersInFile() {
            setUsersCalls=$((setUsersCalls + 1))
            if [[ "${setUsersCalls}" -eq 2 ]]; then
                return 1
            fi
            originalSubscriptionSyncSetUsersInFile "$@"
        }
        set +e
        PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"rollback","uuid":"66666666-6666-6666-6666-666666666666"}],"dry_run":false}' >"${responseFile}.rollback"
        local rollbackStatus=$?
        set -e
        [[ "${rollbackStatus}" -ne 0 ]]
        jq -e '.ok == false and .error == "apply_plan_failed" and .error_detail.type == "apply_plan_failed"' "${responseFile}.rollback" >/dev/null
        printf '%s\n' "${rollbackStateBefore}" >"${rollbackExpectedFile}"
        jq -e --slurpfile expected "${rollbackExpectedFile}" '. == $expected[0]' "$(subscriptionGroupsFile)" >/dev/null
        [[ "$(<"${configPath}02_VLESS_TCP_inbounds.json")" == "${rollbackFirstBefore}" ]]
        [[ "$(<"${configPath}03_VLESS_WS_inbounds.json")" == "${rollbackSecondBefore}" ]]
        if regressionFindHasMatches "${rollbackRoot}" \( -name '*.sync.*' -o -name '*subscription-sync-backup*' \); then
            return 1
        fi
        configPath="${oldConfigPath}"
        singBoxConfigPath="${oldSingBoxConfigPath}"
        coreInstallType="${oldCoreInstallType}"
        subscriptionSyncSetUsersInFile() {
            originalSubscriptionSyncSetUsersInFile "$@"
        }

        local refreshRollbackRoot="${TMP_DIR}/remote-control-refresh-rollback"
        local refreshRollbackLocalDir="${refreshRollbackRoot}/subscribe_local"
        local refreshRollbackPublicDir="${refreshRollbackRoot}/subscribe"
        local refreshRollbackStateBefore
        local refreshRollbackFirstBefore
        local refreshRollbackOldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
        local refreshRollbackOldPublicDir="${PADM_SUBSCRIBE_DIR:-}"
        local refreshRollbackOldScriptDir="${SCRIPT_DIR}"
        local refreshRollbackPublicBefore
        local refreshRollbackLocalBefore
        local refreshRollbackExpectedFile="${TMP_DIR}/remote-control-refresh-rollback-expected.json"
        local refreshRollbackPublicExpected="${TMP_DIR}/remote-control-refresh-public-expected.txt"
        local refreshRollbackLocalExpected="${TMP_DIR}/remote-control-refresh-local-expected.txt"
        mkdir -p "${refreshRollbackRoot}/xray"
        configPath="${refreshRollbackRoot}/xray/"
        singBoxConfigPath="${refreshRollbackRoot}/xray/"
        cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[]}}]}
JSON
        mkdir -p "${refreshRollbackLocalDir}/default" "${refreshRollbackLocalDir}/clashMeta" "${refreshRollbackLocalDir}/sing-box" "${refreshRollbackPublicDir}/default" "${refreshRollbackPublicDir}/clashMeta"
        export PADM_SUBSCRIBE_LOCAL_DIR="${refreshRollbackLocalDir}"
        export PADM_SUBSCRIBE_DIR="${refreshRollbackPublicDir}"
        SCRIPT_DIR="${PROJECT_ROOT}"
        subscribeType=https
        subscribePort=39778
        currentHost=refresh.example.com
        printf 'old salt\n' >"${refreshRollbackLocalDir}/subscribeSalt"
        printf 'old local default\n' >"${refreshRollbackLocalDir}/default/existing"
        printf 'old public default\n' >"${refreshRollbackPublicDir}/default/existing-md5"
        cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
        coreInstallType=1
        subscriptionSyncPlanFromAccounts() {
            printf '{"create":["sub_publish"],"remove":[]}'
        }
        subscriptionControlApplyAccountPlan() {
            subscriptionGroupsStateWrite '.groups |= map(.user_groups += [{"id":"publish","name":"Publish","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"77777777-7777-7777-7777-777777777777"}])'
            cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_publish-vless","id":"77777777-7777-7777-7777-777777777777"}]}}]}
JSON
        }
        refreshRollbackStateBefore=$(<"$(subscriptionGroupsFile)")
        refreshRollbackFirstBefore=$(<"${configPath}02_VLESS_TCP_inbounds.json")
        refreshRollbackLocalBefore=$(find "${refreshRollbackLocalDir}" -type f -printf '%P\t' -exec cat {} \; | sort)
        refreshRollbackPublicBefore=$(find "${refreshRollbackPublicDir}" -type f -printf '%P\t' -exec cat {} \; | sort)
        printf '%s\n' "${refreshRollbackLocalBefore}" >"${refreshRollbackLocalExpected}"
        printf '%s\n' "${refreshRollbackPublicBefore}" >"${refreshRollbackPublicExpected}"
        subscriptionControlRefreshPublishedSubscriptions() {
            printf 'new salt\n' >"${refreshRollbackLocalDir}/subscribeSalt"
            printf 'new local default\n' >"${refreshRollbackLocalDir}/default/existing"
            printf 'new local created\n' >"${refreshRollbackLocalDir}/default/generated"
            printf 'new public default\n' >"${refreshRollbackPublicDir}/default/existing-md5"
            printf 'new public created\n' >"${refreshRollbackPublicDir}/default/generated-md5"
            return 1
        }
        set +e
        PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"publish","uuid":"77777777-7777-7777-7777-777777777777"}],"dry_run":false}' >"${responseFile}.refresh-rollback"
        local refreshRollbackStatus=$?
        set -e
        [[ "${refreshRollbackStatus}" -ne 0 ]]
        jq -e '.ok == false and .error == "refresh_failed" and .error_detail.type == "refresh_failed"' "${responseFile}.refresh-rollback" >/dev/null
        printf '%s\n' "${refreshRollbackStateBefore}" >"${refreshRollbackExpectedFile}"
        jq -e --slurpfile expected "${refreshRollbackExpectedFile}" '. == $expected[0]' "$(subscriptionGroupsFile)" >/dev/null
        [[ "$(<"${configPath}02_VLESS_TCP_inbounds.json")" == "${refreshRollbackFirstBefore}" ]]
        diff -u "${refreshRollbackLocalExpected}" <(find "${refreshRollbackLocalDir}" -type f -printf '%P\t' -exec cat {} \; | sort)
        diff -u "${refreshRollbackPublicExpected}" <(find "${refreshRollbackPublicDir}" -type f -printf '%P\t' -exec cat {} \; | sort)
        if regressionFindHasMatches "${refreshRollbackRoot}" \( -name '*.sync.*' -o -name '*subscription-sync-backup*' -o -name '*subscription-output-backup*' \); then
            return 1
        fi
        configPath="${oldConfigPath}"
        singBoxConfigPath="${oldSingBoxConfigPath}"
        coreInstallType="${oldCoreInstallType}"
        SCRIPT_DIR="${refreshRollbackOldScriptDir}"
        if [[ -n "${refreshRollbackOldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${refreshRollbackOldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
        if [[ -n "${refreshRollbackOldPublicDir}" ]]; then export PADM_SUBSCRIBE_DIR="${refreshRollbackOldPublicDir}"; else unset PADM_SUBSCRIBE_DIR; fi
        subscriptionControlRefreshPublishedSubscriptions() {
            subscribe false false >/dev/null 2>&1
        }

        local restoreFailureRoot="${TMP_DIR}/remote-control-restore-failure"
        local restoreFailureLocalDir="${restoreFailureRoot}/subscribe_local"
        local restoreFailurePublicDir="${restoreFailureRoot}/subscribe"
        local restoreFailureOldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
        local restoreFailureOldPublicDir="${PADM_SUBSCRIBE_DIR:-}"
        local restoreFailureOldScriptDir="${SCRIPT_DIR}"
        local restoreFailureOldTmpDir="${TMPDIR:-}"
        local restoreFailureBackupDirs=()
        mkdir -p "${restoreFailureRoot}/xray" "${restoreFailureLocalDir}/default" "${restoreFailurePublicDir}/default"
        configPath="${restoreFailureRoot}/xray/"
        singBoxConfigPath="${restoreFailureRoot}/xray/"
        TMPDIR="${restoreFailureRoot}"
        cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[]}}]}
JSON
        export PADM_SUBSCRIBE_LOCAL_DIR="${restoreFailureLocalDir}"
        export PADM_SUBSCRIBE_DIR="${restoreFailurePublicDir}"
        SCRIPT_DIR="${PROJECT_ROOT}"
        printf 'old local\n' >"${restoreFailureLocalDir}/default/existing"
        printf 'old public\n' >"${restoreFailurePublicDir}/default/existing-md5"
        cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"remote_enabled":true,"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
        coreInstallType=1
        subscriptionSyncPlanFromAccounts() {
            printf '{"create":["sub_restore_fail"],"remove":[]}'
        }
        subscriptionControlApplyAccountPlan() {
            subscriptionGroupsStateWrite '.groups |= map(.user_groups += [{"id":"restore-fail","name":"Restore Fail","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"88888888-8888-8888-8888-888888888888"}])'
            cat >"${configPath}02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_restore_fail-vless","id":"88888888-8888-8888-8888-888888888888"}]}}]}
JSON
        }
        subscriptionControlRefreshPublishedSubscriptions() {
            printf 'new local\n' >"${restoreFailureLocalDir}/default/existing"
            printf 'new local created\n' >"${restoreFailureLocalDir}/default/generated"
            printf 'new public\n' >"${restoreFailurePublicDir}/default/existing-md5"
            printf 'new public created\n' >"${restoreFailurePublicDir}/default/generated-md5"
            return 1
        }
        cp() {
            if [[ "$1" == "-a" && "$2" == ${restoreFailureRoot}/padm-subscription-output-backup.*/local/. ]]; then
                return 1
            fi
            command cp "$@"
        }
        set +e
        PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"restore-fail","uuid":"88888888-8888-8888-8888-888888888888"}],"dry_run":false}' >"${responseFile}.restore-failure"
        local restoreFailureStatus=$?
        set -e
        unset -f cp
        [[ "${restoreFailureStatus}" -ne 0 ]]
        jq -e '.ok == false and .error == "refresh_failed" and .error_detail.type == "refresh_failed" and (.error_detail.message | contains("订阅输出恢复失败"))' "${responseFile}.restore-failure" >/dev/null
        mapfile -t restoreFailureBackupDirs < <(find "${restoreFailureRoot}" -maxdepth 1 -type d \( -name 'padm-subscription-output-backup.*' -o -name 'padm-subscription-sync-backup.*' \) -print)
        [[ "${#restoreFailureBackupDirs[@]}" == "2" ]]
        regressionFindHasMatches "${restoreFailureRoot}" -maxdepth 1 -type d -name 'padm-subscription-output-backup.*'
        [[ ! -e "${restoreFailureLocalDir}/default/existing" || "$(<"${restoreFailureLocalDir}/default/existing")" != "old local" ]]
        if regressionFindHasMatches "${restoreFailureRoot}/xray" -name '*.sync.*'; then
            return 1
        fi
        if [[ -n "${restoreFailureOldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${restoreFailureOldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
        if [[ -n "${restoreFailureOldPublicDir}" ]]; then export PADM_SUBSCRIBE_DIR="${restoreFailureOldPublicDir}"; else unset PADM_SUBSCRIBE_DIR; fi
        configPath="${oldConfigPath}"
        singBoxConfigPath="${oldSingBoxConfigPath}"
        coreInstallType="${oldCoreInstallType}"
        SCRIPT_DIR="${restoreFailureOldScriptDir}"
        if [[ -n "${restoreFailureOldTmpDir}" ]]; then export TMPDIR="${restoreFailureOldTmpDir}"; else unset TMPDIR; fi
        subscriptionControlRefreshPublishedSubscriptions() {
            subscribe false false >/dev/null 2>&1
        }
        subscriptionControlApplyAccountPlan() {
            originalSubscriptionControlApplyAccountPlan "$@"
        }
        subscriptionSyncPlanFromAccounts() {
            originalSubscriptionSyncPlanFromAccounts "$@"
        }
        useLightweightSyncBackups
        if [[ "${runLightSections}" == "true" ]]; then
            useVirtualSubscriptionGroupsState
            resetVirtualSubscriptionGroupsState
        fi
    fi

    if [[ "${runLightReconcileSections}" == "true" ]]; then
        subscriptionControlApplyAccountPlan() {
            return 0
        }
        useVirtualSubscriptionGroupsState
        resetVirtualSubscriptionGroupsState
        (
            local reconcileLog="${TMP_DIR}/remote-control-local-reconcile-retry.log"
            reconcileCalls=0
            : >"${reconcileLog}"
            subscriptionSyncReconcileLocalServices() {
                reconcileCalls=$((reconcileCalls + 1))
                printf '%s\n' "${1:-<empty>}" >>"${reconcileLog}"
                [[ -n "${1:-}" ]]
            }
            set +e
            PADM_CONTROL_SERVER= subscriptionControlApplySync '{"desired_users":[{"id":"team-c","uuid":"33333333-3333-3333-3333-333333333333"}],"dry_run":false}' >"${responseFile}"
            local reconcileStatus=$?
            set -e
            [[ "${reconcileStatus}" -ne 0 ]]
            [[ "${reconcileCalls}" == "2" ]]
            grep -qx '<empty>' "${reconcileLog}"
            grep -qx 'true' "${reconcileLog}"
            jq -e '.ok == false and .error == "reconcile_failed" and .error_detail.type == "reconcile_failed" and (.error_detail.message | contains("已恢复旧配置")) and ((.error_detail.message | contains("恢复旧配置后服务重建仍失败")) | not)' "${responseFile}" >/dev/null
        )

        (
            local reconcileLog="${TMP_DIR}/remote-control-local-reconcile-retry-fail.log"
            reconcileCalls=0
            : >"${reconcileLog}"
            subscriptionSyncReconcileLocalServices() {
                reconcileCalls=$((reconcileCalls + 1))
                printf '%s\n' "${1:-<empty>}" >>"${reconcileLog}"
                return 1
            }
            set +e
            PADM_CONTROL_SERVER= subscriptionControlApplySync '{"desired_users":[{"id":"team-c","uuid":"33333333-3333-3333-3333-333333333333"}],"dry_run":false}' >"${responseFile}.reconcile-retry-fail"
            local reconcileStatus=$?
            set -e
            [[ "${reconcileStatus}" -ne 0 ]]
            [[ "${reconcileCalls}" == "2" ]]
            grep -qx '<empty>' "${reconcileLog}"
            grep -qx 'true' "${reconcileLog}"
            jq -e '.ok == false and .error == "reconcile_failed" and .error_detail.type == "reconcile_failed" and (.error_detail.message | contains("恢复旧配置后服务重建仍失败"))' "${responseFile}.reconcile-retry-fail" >/dev/null
        )

        subscriptionSyncPlanFromAccounts() {
            printf '{"create":[null],"remove":[]}'
        }
        set +e
        PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"team-d","uuid":"44444444-4444-4444-4444-444444444444"}],"dry_run":true}' >"${responseFile}"
        local invalidPlanStatus=$?
        set -e
        [[ "${invalidPlanStatus}" -ne 0 ]]
        jq -e '.ok == false and .error == "plan_failed" and .error_detail.type == "plan_failed" and (.plan.create[0] == null)' "${responseFile}" >/dev/null

        subscriptionSyncPlanFromAccounts() {
            printf 'not-json\n'
        }
        set +e
        PADM_CONTROL_SERVER=1 subscriptionControlApplySync '{"desired_users":[{"id":"team-e","uuid":"55555555-5555-5555-5555-555555555555"}],"dry_run":true}' >"${responseFile}"
        local badPlanStatus=$?
        set -e
        [[ "${badPlanStatus}" -ne 0 ]]
        jq -e '.ok == false and .error == "plan_failed" and .error_detail.type == "plan_failed" and has("plan") == false' "${responseFile}" >/dev/null
    fi
)

runRemoteControlServerRefreshLightApplyBasicRegression() (
    runRemoteControlServerRefreshRegression light apply-basic
)

runRemoteControlServerRefreshLightApplyPrepareRegression() (
    runRemoteControlServerRefreshRegression light apply-prepare
)

runRemoteControlServerRefreshLightApplyFailureRegression() (
    runRemoteControlServerRefreshRegression light apply-failure
)

runRemoteControlServerRefreshLightRestoreRegression() (
    runRemoteControlServerRefreshRegression light restore
)

runRemoteControlServerRefreshLightReconcileRegression() (
    runRemoteControlServerRefreshRegression light reconcile
)

runRemoteControlServerRefreshDeepRegression() (
    runRemoteControlServerRefreshRegression deep
)

runSubscriptionControlServiceInstallSuccessRegression() (
    runSubscriptionControlServiceInstallRegression success
)

runSubscriptionControlServiceInstallSystemctlFailRegression() (
    runSubscriptionControlServiceInstallRegression systemctl-fail
)

runSubscriptionControlServiceInstallHealthFailRegression() (
    runSubscriptionControlServiceInstallRegression health-fail
)

runSubscriptionControlServiceInstallHealthRollbackRegression() (
    runSubscriptionControlServiceInstallRegression health-rollback
)

runSubscriptionControlTokenTransactionRegression() (
    local tokenRoot="${TMP_DIR}/remote-control-token-transaction"
    local fakeBin="${tokenRoot}/bin"
    local tokenFile
    local oldPath="${PATH}"
    local tokenStatus

    mkdir -p "${fakeBin}" "${tokenRoot}"
    cat >"${fakeBin}/openssl" <<'SH'
#!/usr/bin/env bash
printf 'partial-token'
exit 1
SH
    chmod +x "${fakeBin}/openssl"

    PATH="${fakeBin}:${oldPath}"
    PADM_SUBSCRIPTION_GROUPS_DIR="${tokenRoot}/groups"
    tokenFile=$(subscriptionControlTokenFile)

    set +e
    subscriptionControlEnsureToken >/dev/null 2>&1
    tokenStatus=$?
    set -e

    [[ "${tokenStatus}" == "1" ]]
    [[ ! -e "${tokenFile}" ]]
    if regressionFindHasMatches "${tokenRoot}" -maxdepth 2 -type f -name '.control.token.token.*'; then
        return 1
    fi
)

runSubscriptionControlServiceInstallRegression() (
    local installMode=${1:-all}
    local installModeTag=${installMode}
    local runSuccessSection=false
    local runSystemctlFailSection=false
    local runHealthFailSection=false
    local runHealthRollbackSection=false

    case "${installMode}" in
    all)
        runSuccessSection=true
        runSystemctlFailSection=true
        runHealthFailSection=true
        runHealthRollbackSection=true
        ;;
    success)
        runSuccessSection=true
        ;;
    systemctl-fail)
        runSystemctlFailSection=true
        ;;
    health-fail)
        runHealthFailSection=true
        ;;
    health-rollback)
        runHealthRollbackSection=true
        ;;
    *)
        printf 'unknown remote-control service install mode: %s\n' "${installMode}" >&2
        return 2
        ;;
    esac

    local controlRoot="${TMP_DIR}/remote-control-service-install-${installModeTag}"
    local actionsFile="${TMP_DIR}/remote-control-systemctl-actions-${installModeTag}.txt"
    local healthTokensFile="${TMP_DIR}/remote-control-health-tokens-${installModeTag}.txt"
    local knownToken="known-control-token"
    local installStatus
    local oldServerScript
    local oldServiceFile
    local successServiceFile
    local virtualBackupDir="${TMP_DIR}/remote-control-service-backup-${installModeTag}"
    local virtualBackupServerPath=
    local virtualBackupServicePath=
    local virtualBackupServerExists=false
    local virtualBackupServiceExists=false
    local virtualBackupServerContent=
    local virtualBackupServiceContent=

    mkdir -p "${controlRoot}"
    subscriptionControlHealthCheck() {
        printf '%s\n' "$1" >>"${PADM_FAKE_HEALTH_TOKENS}"
        [[ "${PADM_FAKE_HEALTH_FAIL:-}" != "true" ]]
    }
    writeSubscriptionControlServer() {
        local serverScript
        serverScript=$(subscriptionControlServerScript)
        mkdir -p "$(dirname "${serverScript}")" || return 1
        printf '#!/usr/bin/env bash\nexit 0\n' >"${serverScript}" || return 1
        chmod 755 "${serverScript}" || return 1
    }
    subscriptionControlEnsureToken() {
        return 0
    }
    subscriptionControlToken() {
        printf '%s\n' "${knownToken}"
    }
    subscriptionGroupsSecureStateFiles() {
        return 0
    }
    checkLogBackupCreate() {
        local resultVar=$1
        shift
        virtualBackupServerPath=${1:-}
        virtualBackupServicePath=${2:-}
        if [[ -n "${virtualBackupServerPath}" && -f "${virtualBackupServerPath}" ]]; then
            virtualBackupServerExists=true
            virtualBackupServerContent=$(<"${virtualBackupServerPath}")
        else
            virtualBackupServerExists=false
            virtualBackupServerContent=
        fi
        if [[ -n "${virtualBackupServicePath}" && -f "${virtualBackupServicePath}" ]]; then
            virtualBackupServiceExists=true
            virtualBackupServiceContent=$(<"${virtualBackupServicePath}")
        else
            virtualBackupServiceExists=false
            virtualBackupServiceContent=
        fi
        printf -v "${resultVar}" '%s' "${virtualBackupDir}"
    }
    restoreVirtualServiceInstallFile() {
        local filePath=$1
        local fileExists=$2
        local fileContent=$3
        [[ -n "${filePath}" ]] || return 0
        if [[ "${fileExists}" == "true" ]]; then
            mkdir -p "$(dirname "${filePath}")" || return 1
            printf '%s' "${fileContent}" >"${filePath}" || return 1
        else
            rm -f -- "${filePath}" >/dev/null 2>&1 || return 1
        fi
    }
    checkLogBackupRestore() {
        local backupDir=$1
        local status=0
        [[ "${backupDir}" == "${virtualBackupDir}" ]] || return 1
        restoreVirtualServiceInstallFile "${virtualBackupServerPath}" "${virtualBackupServerExists}" "${virtualBackupServerContent}" || status=1
        restoreVirtualServiceInstallFile "${virtualBackupServicePath}" "${virtualBackupServiceExists}" "${virtualBackupServiceContent}" || status=1
        return "${status}"
    }
    systemctl() {
        printf '%s\n' "$*" >>"${PADM_FAKE_SYSTEMCTL_ACTIONS}"
        case "$1" in
        daemon-reload)
            [[ "${PADM_FAKE_SYSTEMCTL_FAIL:-}" == "daemon-reload" ]] && return 1
            return 0
            ;;
        is-active)
            [[ "${PADM_FAKE_SYSTEMCTL_ACTIVE:-}" == "true" ]] && return 0
            return 3
            ;;
        is-enabled)
            [[ "${PADM_FAKE_SYSTEMCTL_ENABLED:-}" == "true" ]] && return 0
            return 1
            ;;
        restart)
            [[ "${PADM_FAKE_SYSTEMCTL_FAIL:-}" == "restart" ]] && return 1
            return 0
            ;;
        enable)
            [[ "${PADM_FAKE_SYSTEMCTL_FAIL:-}" == "enable" ]] && return 1
            return 0
            ;;
        *)
            return 0
            ;;
        esac
    }

    subscriptionControlServiceFile() {
        printf '%s\n' "${controlRoot}/systemd/padm-subscription-control.service"
    }
    export PADM_FAKE_SYSTEMCTL_ACTIONS="${actionsFile}"
    export PADM_FAKE_HEALTH_TOKENS="${healthTokensFile}"
    export PADM_CONTROL_HEALTH_RETRIES=1
    export PADM_CONTROL_HEALTH_RETRY_DELAY=0
    export PADM_CONTROL_HEALTH_TIMEOUT=0.05
    sleep() { return 0; }

    if [[ "${runSuccessSection}" == "true" || "${runSystemctlFailSection}" == "true" || "${runHealthFailSection}" == "true" ]]; then
        PADM_SUBSCRIPTION_GROUPS_DIR="${controlRoot}/success"
        mkdir -p "${PADM_SUBSCRIPTION_GROUPS_DIR}"
        : >"${actionsFile}"
        : >"${healthTokensFile}"
        installSubscriptionControlService
        [[ -x "$(subscriptionControlServerScript)" ]]
        grep -q 'ExecStart=/usr/bin/env python3' "$(subscriptionControlServiceFile)"
        grep -qxF 'enable --now padm-subscription-control.service' "${actionsFile}"
        grep -qxF "${knownToken}" "${healthTokensFile}"
        successServiceFile=$(<"$(subscriptionControlServiceFile)")
    fi

    if [[ "${runSystemctlFailSection}" == "true" ]]; then
        PADM_SUBSCRIPTION_GROUPS_DIR="${controlRoot}/systemctl-fail"
        mkdir -p "${PADM_SUBSCRIPTION_GROUPS_DIR}"
        export PADM_FAKE_SYSTEMCTL_FAIL=enable
        set +e
        installSubscriptionControlService
        installStatus=$?
        set -e
        PADM_FAKE_SYSTEMCTL_FAIL=
        [[ "${installStatus}" -ne 0 ]]
        [[ ! -e "$(subscriptionControlServerScript)" ]]
        [[ -f "$(subscriptionControlServiceFile)" ]]
        [[ "$(<"$(subscriptionControlServiceFile)")" == "${successServiceFile}" ]]
        [[ "${SUBSCRIPTION_CONTROL_INSTALL_ERROR}" == *"已恢复安装前状态"* ]]
    fi

    if [[ "${runHealthFailSection}" == "true" ]]; then
        PADM_SUBSCRIPTION_GROUPS_DIR="${controlRoot}/health-fail"
        mkdir -p "${PADM_SUBSCRIPTION_GROUPS_DIR}"
        : >"${actionsFile}"
        export PADM_FAKE_HEALTH_FAIL=true
        set +e
        installSubscriptionControlService
        installStatus=$?
        set -e
        PADM_FAKE_HEALTH_FAIL=
        [[ "${installStatus}" -ne 0 ]]
        [[ ! -e "$(subscriptionControlServerScript)" ]]
        [[ -f "$(subscriptionControlServiceFile)" ]]
        [[ "$(<"$(subscriptionControlServiceFile)")" == "${successServiceFile}" ]]
        [[ "${SUBSCRIPTION_CONTROL_INSTALL_ERROR}" == *"已恢复安装前状态"* ]]
    fi

    if [[ "${runHealthRollbackSection}" == "true" ]]; then
        PADM_SUBSCRIPTION_GROUPS_DIR="${controlRoot}/health-rollback"
        mkdir -p "${PADM_SUBSCRIPTION_GROUPS_DIR}" "$(dirname "$(subscriptionControlServerScript)")" "$(dirname "$(subscriptionControlServiceFile)")"
        printf 'old-server\n' >"$(subscriptionControlServerScript)"
        printf 'old-service\n' >"$(subscriptionControlServiceFile)"
        oldServerScript=$(subscriptionControlServerScript)
        oldServiceFile=$(subscriptionControlServiceFile)
        : >"${actionsFile}"
        export PADM_FAKE_SYSTEMCTL_ACTIVE=true
        export PADM_FAKE_SYSTEMCTL_ENABLED=true
        export PADM_FAKE_HEALTH_FAIL=true
        set +e
        installSubscriptionControlService
        installStatus=$?
        set -e
        PADM_FAKE_SYSTEMCTL_ACTIVE=
        PADM_FAKE_SYSTEMCTL_ENABLED=
        PADM_FAKE_HEALTH_FAIL=
        [[ "${installStatus}" -ne 0 ]]
        [[ "$(<"${oldServerScript}")" == "old-server" ]]
        [[ "$(<"${oldServiceFile}")" == "old-service" ]]
        [[ "$(grep -c '^daemon-reload$' "${actionsFile}")" == "2" ]]
        [[ "$(grep -c '^restart padm-subscription-control.service$' "${actionsFile}")" == "2" ]]
    fi
)

runSubscriptionControlServerResponseRegression() (
    command -v python3 >/dev/null 2>&1 || return 0

    local controlRoot="${TMP_DIR}/remote-control-server-response"
    local fakeInstall="${controlRoot}/install.sh"
    local modeFile="${controlRoot}/mode"
    local responseFile="${controlRoot}/response.txt"
    local serverLog="${controlRoot}/server.log"
    local serverScript
    local serverPid=
    local testPort
    local serverToken="test-token"
    local status
    local body
    local ready=
    mkdir -p "${controlRoot}"
    testPort=$(python3 <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)
    getScriptVersion() {
        printf 'test\n'
    }
    cat >"${fakeInstall}" <<'SH'
#!/usr/bin/env bash
endpoint=${2:-}
mode=
if [[ -f "${PADM_FAKE_CONTROL_MODE_FILE}" ]]; then
    mode=$(<"${PADM_FAKE_CONTROL_MODE_FILE}")
fi
payload=
if [[ "${PADM_CONTROL_TOKEN:-}" != "${PADM_FAKE_SERVER_TOKEN:-}" ]]; then
    printf '{"ok":false,"error":"unauthorized","error_detail":{"type":"unauthorized","message":"控制 token 验证失败"}}\n'
    exit 1
fi
    if [[ "${endpoint}" == "sync" || "${endpoint}" == "subscribe" ]]; then
        payload=$(cat)
        if [[ -z "${payload}" ]]; then
            if [[ "${endpoint}" == "sync" ]]; then
                printf '{"ok":false,"error":"empty_payload","error_detail":{"type":"empty_payload","message":"同步请求体为空"}}\n'
            else
                printf '{"ok":false,"error":"empty_payload","error_detail":{"type":"empty_payload","message":"订阅请求体为空"}}\n'
            fi
            exit 1
        fi
        if [[ "${payload}" == "not-json" ]]; then
            if [[ "${endpoint}" == "sync" ]]; then
                printf '{"ok":false,"error":"invalid_payload","error_detail":{"type":"invalid_payload","message":"同步请求体格式不正确"}}\n'
            else
                printf '{"ok":false,"error":"invalid_payload","error_detail":{"type":"invalid_payload","message":"订阅请求体格式不正确"}}\n'
            fi
            exit 1
        fi
    fi
    case "${endpoint}:${mode}" in
health:*)
    printf '{"ok":false,"error":"health_should_not_execute"}\n'
    exit 9
    ;;
sync:noise)
    printf 'ui noise before sync\n'
    printf '{"ok":false,"error":"first_json"}\n'
    printf 'ui noise between json\n'
    printf '{"ok":true,"changed":true,"plan":{"create":[],"remove":[]}}\n'
    ;;
sync:failed)
    printf 'ui noise before failed sync\n'
    printf '{"ok":true,"changed":true}\n'
    exit 7
    ;;
sync:timeout)
    /bin/sleep 2
    printf '{"ok":true}\n'
    ;;
    sync:invalid)
        printf 'ui noise only\n'
        exit 0
        ;;
    subscribe:noise)
        printf 'ui noise before subscribe\n'
        printf '{"ok":false,"error":"first_json"}\n'
        printf 'ui noise between json\n'
        cat <<'JSON'
{"ok":true,"default":"dmxlc3M6Ly91dWlkQGV4YW1wbGUuY29tOjQ0MyN0ZWFtLWE=","clash_meta":"proxies:\n- name: team-a\n","sing_box":[{"tag":"team-a"}]}
JSON
        ;;
    *)
        printf '{"ok":false,"error":"unexpected"}\n'
        exit 1
        ;;
    esac
SH
    chmod +x "${fakeInstall}"

    subscriptionControlPort() {
        printf '%s\n' "${testPort}"
    }
    subscriptionGroupSyncInstallScript() {
        printf '%s\n' "${fakeInstall}"
    }
    PADM_SUBSCRIPTION_GROUPS_DIR="${controlRoot}/state"
    mkdir -p "$(dirname "$(subscriptionControlTokenFile)")"
    printf '%s\n' "${serverToken}" >"$(subscriptionControlTokenFile)"
    export PADM_FAKE_SERVER_TOKEN="${serverToken}"
    writeSubscriptionControlServer
    serverScript=$(subscriptionControlServerScript)
    printf 'noise\n' >"${modeFile}"
    PADM_CONTROL_SCRIPT_TIMEOUT=0.4 PADM_FAKE_CONTROL_MODE_FILE="${modeFile}" python3 "${serverScript}" >"${serverLog}" 2>&1 &
    serverPid=$!
    trap '[[ -n "${serverPid}" ]] && kill "${serverPid}" >/dev/null 2>&1 || true; [[ -n "${serverPid}" ]] && wait "${serverPid}" 2>/dev/null || true' EXIT

    PADM_TEST_CONTROL_PORT="${testPort}" \
    PADM_TEST_CONTROL_MODE_FILE="${modeFile}" \
    PADM_TEST_CONTROL_TOKEN="${serverToken}" \
    python3 <<'PY' >"${responseFile}"
import json
import os
import time
import urllib.error
import urllib.request

port = os.environ["PADM_TEST_CONTROL_PORT"]
mode_file = os.environ["PADM_TEST_CONTROL_MODE_FILE"]
token = os.environ["PADM_TEST_CONTROL_TOKEN"]
base_url = f"http://127.0.0.1:{port}/s/control"

def set_mode(value):
    with open(mode_file, "w", encoding="utf-8") as handle:
        handle.write(value)

def request(method, endpoint, payload="", token_override=None):
    current_token = token_override if token_override is not None else token
    data = payload.encode("utf-8") if method == "POST" else None
    headers = {"Authorization": f"Bearer {current_token}"}
    if method == "POST":
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(
        f"{base_url}/{endpoint}",
        data=data,
        method=method,
        headers=headers,
    )
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            status = response.status
            body_text = response.read().decode()
    except urllib.error.HTTPError as error:
        status = error.code
        body_text = error.read().decode()
    except Exception as error:
        return {"status": 0, "error": type(error).__name__, "body": None}
    try:
        body = json.loads(body_text) if body_text else None
    except json.JSONDecodeError:
        body = None
    return {"status": status, "body": body}

results = {}
set_mode("noise")
for _ in range(20):
    results["health_ready"] = request("GET", "health")
    body = results["health_ready"].get("body") or {}
    if results["health_ready"]["status"] == 200 and body.get("ok") is True:
        break
    time.sleep(0.05)

set_mode("noise")
results["sync_success"] = request("POST", "sync", '{"desired_users":[]}')
results["subscribe_success"] = request("POST", "subscribe", '{"account":"team_a"}')
results["health_unauthorized"] = request("GET", "health", token_override="wrong-token")
results["sync_empty_payload"] = request("POST", "sync", "")
results["sync_invalid_payload"] = request("POST", "sync", "not-json")
results["subscribe_empty_payload"] = request("POST", "subscribe", "")
results["subscribe_invalid_payload"] = request("POST", "subscribe", "not-json")

set_mode("failed")
results["sync_failed"] = request("POST", "sync", '{"desired_users":[]}')
set_mode("timeout")
results["sync_timeout"] = request("POST", "sync", '{"desired_users":[]}')
set_mode("invalid")
results["sync_invalid_response"] = request("POST", "sync", '{"desired_users":[]}')

print(json.dumps(results, ensure_ascii=False))
PY

    jq -e '.health_ready.status == 200 and .health_ready.body.ok == true and .health_ready.body.version == "test" and .health_ready.body.capabilities == ["health","sync","subscribe"]' "${responseFile}" >/dev/null
    jq -e '.sync_success.status == 200 and .sync_success.body.ok == true and .sync_success.body.changed == true and (.sync_success.body.plan.create | length) == 0' "${responseFile}" >/dev/null
    jq -e '.subscribe_success.status == 200 and .subscribe_success.body.ok == true and (.subscribe_success.body.default | @base64d) == "vless://uuid@example.com:443#team-a" and (.subscribe_success.body.clash_meta | contains("team-a")) and .subscribe_success.body.sing_box[0].tag == "team-a"' "${responseFile}" >/dev/null
    jq -e '.health_unauthorized.status == 401' "${responseFile}" >/dev/null
    jq -e '.sync_empty_payload.status == 400' "${responseFile}" >/dev/null
    jq -e '.sync_invalid_payload.status == 400' "${responseFile}" >/dev/null
    jq -e '.subscribe_empty_payload.status == 400' "${responseFile}" >/dev/null
    jq -e '.subscribe_invalid_payload.status == 400' "${responseFile}" >/dev/null
    jq -e '.sync_failed.status == 503 and .sync_failed.body.error == "script_failed" and .sync_failed.body.error_detail.type == "script_failed" and .sync_failed.body.exit_code == 7' "${responseFile}" >/dev/null
    jq -e '.sync_timeout.status == 503 and .sync_timeout.body.error == "script_timeout" and .sync_timeout.body.error_detail.type == "script_timeout"' "${responseFile}" >/dev/null
    jq -e '.sync_invalid_response.status == 503 and .sync_invalid_response.body.error == "invalid_response" and .sync_invalid_response.body.error_detail.type == "invalid_response"' "${responseFile}" >/dev/null
)

runRegressionRemoteControlSmokeCoreSteps() {
    runRegressionStep remote-control-concurrency runRemoteControlConcurrencyRegression &&
        runRegressionStep remote-control-aggregation-failure runRemoteControlAggregationFailureRegression &&
        runRegressionStep remote-control-health runRemoteControlHealthRegression
}

runRegressionRemoteControlSmokeRefreshApplyBasicSteps() {
    runRegressionStep remote-control-server-refresh-light-apply-basic runRemoteControlServerRefreshLightApplyBasicRegression
}

runRegressionRemoteControlSmokeRefreshApplyPrepareSteps() {
    runRegressionStep remote-control-server-refresh-light-apply-prepare runRemoteControlServerRefreshLightApplyPrepareRegression
}

runRegressionRemoteControlSmokeRefreshApplyFailureSteps() {
    runRegressionStep remote-control-server-refresh-light-apply-failure runRemoteControlServerRefreshLightApplyFailureRegression
}

runRegressionRemoteControlSmokeRefreshRestoreSteps() {
    runRegressionStep remote-control-server-refresh-light-restore runRemoteControlServerRefreshLightRestoreRegression
}

runRegressionRemoteControlSmokeRefreshReconcileSteps() {
    runRegressionStep remote-control-server-refresh-light-reconcile runRemoteControlServerRefreshLightReconcileRegression
}

runRegressionRemoteControlContractServiceInstallSuccessSteps() {
    runRegressionStep remote-control-service-install-success runSubscriptionControlServiceInstallSuccessRegression
}

runRegressionRemoteControlContractServiceInstallSystemctlFailSteps() {
    runRegressionStep remote-control-service-install-systemctl-fail runSubscriptionControlServiceInstallSystemctlFailRegression
}

runRegressionRemoteControlContractServiceInstallHealthFailSteps() {
    runRegressionStep remote-control-service-install-health-fail runSubscriptionControlServiceInstallHealthFailRegression
}

runRegressionRemoteControlContractServiceInstallHealthRollbackSteps() {
    runRegressionStep remote-control-service-install-health-rollback runSubscriptionControlServiceInstallHealthRollbackRegression
}

runRegressionRemoteControlContractServiceInstallTokenTransactionSteps() {
    runRegressionStep remote-control-service-install-token-transaction runSubscriptionControlTokenTransactionRegression
}

runRegressionRemoteControlContractServerResponseSteps() {
    runRegressionStep remote-control-server-response runSubscriptionControlServerResponseRegression
}

runParallelRemoteControlTotals() {
    local orchestrationRoot=$1
    local -a logs=()
    local -a pids=()
    local -a statuses=()
    local status=0
    local index=0

    shift
    if [[ $# -eq 0 || $(( $# % 2 )) -ne 0 ]]; then
        printf 'runParallelRemoteControlTotals expects mode/runner pairs\n' >&2
        return 2
    fi

    mkdir -p "${orchestrationRoot}"
    set +e
    while [[ $# -gt 0 ]]; do
        local modeName=$1
        local runner=$2
        local logFile="${orchestrationRoot}/${modeName}.log"
        shift 2

        (
            trap - EXIT INT TERM
            set -e
            runRegressionStep "total:${modeName}" "${runner}"
        ) >"${logFile}" 2>&1 &
        pids+=("$!")
        logs+=("${logFile}")
    done

    for index in "${!pids[@]}"; do
        wait "${pids[$index]}"
        statuses[$index]=$?
    done
    set -e

    for index in "${!logs[@]}"; do
        [[ -f "${logs[$index]}" ]] && cat "${logs[$index]}"
        if [[ "${statuses[$index]}" -ne 0 && "${status}" -eq 0 ]]; then
            status=${statuses[$index]}
        fi
    done

    return "${status}"
}

runParallelRemoteControlModes() {
    local orchestrationRoot=$1
    local firstLabel=$2
    local firstMode=$3
    local secondLabel=$4
    local secondMode=$5
    local firstLog="${orchestrationRoot}/${firstLabel}.log"
    local secondLog="${orchestrationRoot}/${secondLabel}.log"
    local firstStatus secondStatus
    local firstPid secondPid

    mkdir -p "${orchestrationRoot}"
    set +e
    PADM_REGRESSION_SUPPRESS_DONE=1 bash "${REMOTE_CONTROL_SCRIPT_PATH}" "${firstMode}" >"${firstLog}" 2>&1 &
    firstPid=$!
    PADM_REGRESSION_SUPPRESS_DONE=1 bash "${REMOTE_CONTROL_SCRIPT_PATH}" "${secondMode}" >"${secondLog}" 2>&1 &
    secondPid=$!
    wait "${firstPid}"
    firstStatus=$?
    wait "${secondPid}"
    secondStatus=$?
    set -e

    cat "${firstLog}"
    cat "${secondLog}"

    [[ "${firstStatus}" -eq 0 ]]
    [[ "${secondStatus}" -eq 0 ]]
}

runRegressionRemoteControl() {
    runParallelRemoteControlModes \
        "${TMP_DIR}/remote-control-default" \
        smoke remote-control-smoke \
        contract remote-control-contract
}

runRegressionRemoteControlLight() {
    runRegressionRemoteControl
}

runRegressionRemoteControlSmokeCore() {
    runRegressionRemoteControlSmokeCoreSteps
}

runRegressionRemoteControlSmokeRefresh() {
    local orchestrationRoot="${TMP_DIR}/remote-control-smoke-refresh"
    local applyLog="${orchestrationRoot}/apply.log"
    local restoreLog="${orchestrationRoot}/restore.log"
    local reconcileLog="${orchestrationRoot}/reconcile.log"
    local applyStatus restoreStatus reconcileStatus
    local applyPid restorePid reconcilePid

    mkdir -p "${orchestrationRoot}"
    set +e
    PADM_REGRESSION_SUPPRESS_DONE=1 bash "${REMOTE_CONTROL_SCRIPT_PATH}" remote-control-smoke-refresh-apply >"${applyLog}" 2>&1 &
    applyPid=$!
    PADM_REGRESSION_SUPPRESS_DONE=1 bash "${REMOTE_CONTROL_SCRIPT_PATH}" remote-control-smoke-refresh-restore >"${restoreLog}" 2>&1 &
    restorePid=$!
    PADM_REGRESSION_SUPPRESS_DONE=1 bash "${REMOTE_CONTROL_SCRIPT_PATH}" remote-control-smoke-refresh-reconcile >"${reconcileLog}" 2>&1 &
    reconcilePid=$!
    wait "${applyPid}"
    applyStatus=$?
    wait "${restorePid}"
    restoreStatus=$?
    wait "${reconcilePid}"
    reconcileStatus=$?
    set -e

    cat "${applyLog}"
    cat "${restoreLog}"
    cat "${reconcileLog}"

    [[ "${applyStatus}" -eq 0 ]]
    [[ "${restoreStatus}" -eq 0 ]]
    [[ "${reconcileStatus}" -eq 0 ]]
}

runRegressionRemoteControlSmokeRefreshApply() {
    local orchestrationRoot="${TMP_DIR}/remote-control-smoke-refresh-apply"
    local basicLog="${orchestrationRoot}/basic.log"
    local prepareLog="${orchestrationRoot}/prepare.log"
    local failureLog="${orchestrationRoot}/failure.log"
    local basicStatus prepareStatus failureStatus
    local basicPid preparePid failurePid

    mkdir -p "${orchestrationRoot}"
    set +e
    PADM_REGRESSION_SUPPRESS_DONE=1 bash "${REMOTE_CONTROL_SCRIPT_PATH}" remote-control-smoke-refresh-apply-basic >"${basicLog}" 2>&1 &
    basicPid=$!
    PADM_REGRESSION_SUPPRESS_DONE=1 bash "${REMOTE_CONTROL_SCRIPT_PATH}" remote-control-smoke-refresh-apply-prepare >"${prepareLog}" 2>&1 &
    preparePid=$!
    PADM_REGRESSION_SUPPRESS_DONE=1 bash "${REMOTE_CONTROL_SCRIPT_PATH}" remote-control-smoke-refresh-apply-failure >"${failureLog}" 2>&1 &
    failurePid=$!
    wait "${basicPid}"
    basicStatus=$?
    wait "${preparePid}"
    prepareStatus=$?
    wait "${failurePid}"
    failureStatus=$?
    set -e

    cat "${basicLog}"
    cat "${prepareLog}"
    cat "${failureLog}"

    [[ "${basicStatus}" -eq 0 ]]
    [[ "${prepareStatus}" -eq 0 ]]
    [[ "${failureStatus}" -eq 0 ]]
}

runRegressionRemoteControlSmokeRefreshApplyBasic() {
    runRegressionRemoteControlSmokeRefreshApplyBasicSteps
}

runRegressionRemoteControlSmokeRefreshApplyPrepare() {
    runRegressionRemoteControlSmokeRefreshApplyPrepareSteps
}

runRegressionRemoteControlSmokeRefreshApplyFailure() {
    runRegressionRemoteControlSmokeRefreshApplyFailureSteps
}

runRegressionRemoteControlSmokeRefreshRestore() {
    runRegressionRemoteControlSmokeRefreshRestoreSteps
}

runRegressionRemoteControlSmokeRefreshReconcile() {
    runRegressionRemoteControlSmokeRefreshReconcileSteps
}

runRegressionRemoteControlSmoke() {
    runParallelRemoteControlModes \
        "${TMP_DIR}/remote-control-smoke" \
        smoke-core remote-control-smoke-core \
        smoke-refresh remote-control-smoke-refresh
}

runRegressionRemoteControlContract() {
    runParallelRemoteControlModes \
        "${TMP_DIR}/remote-control-contract" \
        service-install remote-control-contract-service-install \
        server-response remote-control-contract-server-response
}

runRegressionRemoteControlContractServiceInstall() {
    runParallelRemoteControlTotals \
        "${TMP_DIR}/remote-control-contract-service-install" \
        remote-control-contract-service-install-success runRegressionRemoteControlContractServiceInstallSuccess \
        remote-control-contract-service-install-systemctl-fail runRegressionRemoteControlContractServiceInstallSystemctlFail \
        remote-control-contract-service-install-health-fail runRegressionRemoteControlContractServiceInstallHealthFail \
        remote-control-contract-service-install-health-rollback runRegressionRemoteControlContractServiceInstallHealthRollback \
        remote-control-contract-service-install-token-transaction runRegressionRemoteControlContractServiceInstallTokenTransaction
}

runRegressionRemoteControlContractServiceInstallSuccess() {
    runRegressionRemoteControlContractServiceInstallSuccessSteps
}

runRegressionRemoteControlContractServiceInstallSystemctlFail() {
    runRegressionRemoteControlContractServiceInstallSystemctlFailSteps
}

runRegressionRemoteControlContractServiceInstallHealthFail() {
    runRegressionRemoteControlContractServiceInstallHealthFailSteps
}

runRegressionRemoteControlContractServiceInstallHealthRollback() {
    runRegressionRemoteControlContractServiceInstallHealthRollbackSteps
}

runRegressionRemoteControlContractServiceInstallTokenTransaction() {
    runRegressionRemoteControlContractServiceInstallTokenTransactionSteps
}

runRegressionRemoteControlContractServerResponse() {
    runRegressionRemoteControlContractServerResponseSteps
}

runRegressionRemoteControlDeep() {
    runRegressionStep remote-control-server-refresh-deep runRemoteControlServerRefreshDeepRegression
}

regressionName=${1:-remote-control}
case "${regressionName}" in
remote-control)
    regressionRunner=runRegressionRemoteControl
    ;;
remote-control-smoke)
    regressionRunner=runRegressionRemoteControlSmoke
    ;;
remote-control-smoke-core)
    regressionRunner=runRegressionRemoteControlSmokeCore
    ;;
remote-control-smoke-refresh)
    regressionRunner=runRegressionRemoteControlSmokeRefresh
    ;;
remote-control-smoke-refresh-apply)
    regressionRunner=runRegressionRemoteControlSmokeRefreshApply
    ;;
remote-control-smoke-refresh-apply-basic)
    regressionRunner=runRegressionRemoteControlSmokeRefreshApplyBasic
    ;;
remote-control-smoke-refresh-apply-prepare)
    regressionRunner=runRegressionRemoteControlSmokeRefreshApplyPrepare
    ;;
remote-control-smoke-refresh-apply-failure)
    regressionRunner=runRegressionRemoteControlSmokeRefreshApplyFailure
    ;;
remote-control-smoke-refresh-restore)
    regressionRunner=runRegressionRemoteControlSmokeRefreshRestore
    ;;
remote-control-smoke-refresh-reconcile)
    regressionRunner=runRegressionRemoteControlSmokeRefreshReconcile
    ;;
remote-control-contract)
    regressionRunner=runRegressionRemoteControlContract
    ;;
remote-control-contract-service-install)
    regressionRunner=runRegressionRemoteControlContractServiceInstall
    ;;
remote-control-contract-service-install-success)
    regressionRunner=runRegressionRemoteControlContractServiceInstallSuccess
    ;;
remote-control-contract-service-install-systemctl-fail)
    regressionRunner=runRegressionRemoteControlContractServiceInstallSystemctlFail
    ;;
remote-control-contract-service-install-health-fail)
    regressionRunner=runRegressionRemoteControlContractServiceInstallHealthFail
    ;;
remote-control-contract-service-install-health-rollback)
    regressionRunner=runRegressionRemoteControlContractServiceInstallHealthRollback
    ;;
remote-control-contract-service-install-token-transaction)
    regressionRunner=runRegressionRemoteControlContractServiceInstallTokenTransaction
    ;;
remote-control-contract-server-response)
    regressionRunner=runRegressionRemoteControlContractServerResponse
    ;;
remote-control-light)
    regressionRunner=runRegressionRemoteControlLight
    ;;
remote-control-deep)
    regressionRunner=runRegressionRemoteControlDeep
    ;;
*)
    printf 'usage: %s [remote-control|remote-control-smoke|remote-control-contract|remote-control-light|remote-control-deep]\n' "$0" >&2
    exit 2
    ;;
esac

runRegressionStep "total:${regressionName}" "${regressionRunner}"
if [[ "${PADM_REGRESSION_SUPPRESS_DONE:-}" != "1" ]]; then
    echo "subscription-groups-regression-ok:${regressionName}"
fi
