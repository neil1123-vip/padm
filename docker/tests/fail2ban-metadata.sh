#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-fail2ban-metadata.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

fail() {
    printf 'docker-fail2ban-metadata-regression-fail: %s\n' "$*" >&2
    exit 1
}

for type in fail2ban fail2ban-control fail2ban-ssh; do
    spec="${TEST_ROOT}/${type}.json"
    candidate="${TEST_ROOT}/${type}"
    jq -n --arg type "${type}" '{
      core:{protocols:[{id:21,public_port:24444,address_families:["ipv4","ipv6"]}]},
      control:{role:"main",listen:{interface:"wg-padm",address:"10.77.0.1",port:18080}},
      host_integrations:[{
        type:$type,profile:("net-"+$type),
        firewall_rules:[if $type == "fail2ban" then "DOCKER-USER" else "INPUT" end],
        devices:[],schedules:[],
        settings:({max_retry:3,find_time:600,ban_time:3600} +
          if $type == "fail2ban" then {ports:[24444]}
          elif $type == "fail2ban-ssh" then {unit:"ssh.service",target:"192.0.2.10",port:2222}
          else {} end)
      }]
    }' >"${spec}"
    mkdir -p -- "${candidate}/config/net/fail2ban" "${candidate}/logs/nginx"
    case "${type}" in
    fail2ban) generator=dockerGenerateFail2banConfig ;;
    fail2ban-control) generator=dockerGenerateControlFail2banConfig ;;
    fail2ban-ssh) generator=dockerGenerateSshFail2banConfig ;;
    esac
    "${generator}" "${spec}" "${candidate}" || fail "有效元数据被拒绝: ${type}"
    (
        # 正常字段已输出也不能忽略 jq 的非零退出，生成前须完整取得元数据。
        jq() {
            command jq "$@" || return $?
            [[ "$*" != *'join("|")'* ]] || return 17
        }
        rejected="${TEST_ROOT}/${type}-rejected"
        if "${generator}" "${spec}" "${rejected}" >"${TEST_ROOT}/failure.log" 2>&1; then
            fail "已输出字段的 jq 失败未传播: ${type}"
        fi
        [[ ! -e "${rejected}" ]] || fail "失败仍写入候选: ${type}"
        if [[ "${type}" == fail2ban-control ]]; then
            if "${generator}" "${spec}" "${rejected}" 3 600 3600 \
                >"${TEST_ROOT}/failure.log" 2>&1; then
                fail '显式控制参数分支忽略 jq 失败'
            fi
            [[ ! -e "${rejected}" ]] || fail '显式控制参数分支写入失败候选'
        fi
    )
done

(
    # 隔离外部动作，元数据门禁继续调用实际安全路径与 JSON 校验。
    root="${TEST_ROOT}/disable"
    mkdir -p -- "${root}/config"
    next="${TEST_ROOT}/disable-next.json"
    printf '%s\n' '{"host_integrations":[]}' >"${next}"
    dockerInstallRoot() { printf '%s\n' "${TEST_ROOT}/disable"; }
    docker() {
        [[ "$1" == ps ]] || return 91
        printf 'ps\n' >>"${TEST_ROOT}/disable-events"
        [[ "${scenario}" != orphan ]] || printf 'aaaaaaaaaaaa\n'
    }
    dockerFail2banConfigurationCheck() { printf 'audit:%s\n' "$2" >>"${TEST_ROOT}/disable-events"; }
    dockerFail2banCleanCheck() { printf 'clean:ws\n' >>"${TEST_ROOT}/disable-events"; }
    dockerComposeExecute() { printf 'clean:%s\n' "${scope}" >>"${TEST_ROOT}/disable-events"; }
    dockerSshCollectorStop() { printf 'collector\n' >>"${TEST_ROOT}/disable-events"; }

    for scope in ws control ssh; do
        case "${scope}" in
        ws) type=fail2ban service=net-fail2ban ;;
        control) type=fail2ban-control service=net-fail2ban-control ;;
        ssh) type=fail2ban-ssh service=net-fail2ban-ssh ;;
        esac
        for scenario in disabled enabled deployment-enabled compose-enabled \
            invalid-deployment invalid-compose malformed-deployment malformed-compose \
            empty-deployment empty-compose linked-deployment linked-compose missing-spec \
            corrupt-spec corrupt-enabled corrupt-missing orphan jq-failure restore-jq-failure; do
            printf '%s\n' '{"host_integrations":[]}' >"${root}/config/spec.json"
            cp -- "${root}/config/spec.json" "${root}/deployment.json"
            printf '%s\n' '{"services":{}}' >"${root}/compose.json"
            : >"${TEST_ROOT}/disable-events"
            mode=normal expected=1
            case "${scenario}" in
            disabled) expected=0 ;;
            enabled)
                printf '{"host_integrations":[{"type":"%s","settings":{"target":"192.0.2.10","port":2222}}],"control":{"listen":{"address":"10.77.0.1","port":18080}}}\n' \
                    "${type}" >"${root}/config/spec.json"
                cp -- "${root}/config/spec.json" "${root}/deployment.json"
                printf '{"services":{"%s":{}}}\n' "${service}" >"${root}/compose.json"
                expected=0
                ;;
            deployment-enabled)
                printf '{"host_integrations":[{"type":"%s"}]}\n' "${type}" >"${root}/deployment.json"
                ;;
            compose-enabled) printf '{"services":{"%s":{}}}\n' "${service}" >"${root}/compose.json" ;;
            invalid-deployment) printf '%s\n' '{"host_integrations":null}' >"${root}/deployment.json" ;;
            invalid-compose) printf '%s\n' '{"services":[]}' >"${root}/compose.json" ;;
            malformed-deployment) printf '{\n' >"${root}/deployment.json" ;;
            malformed-compose) printf '{\n' >"${root}/compose.json" ;;
            empty-deployment) : >"${root}/deployment.json" ;;
            empty-compose) : >"${root}/compose.json" ;;
            linked-deployment)
                rm -- "${root}/deployment.json"
                ln -s config/spec.json "${root}/deployment.json"
                ;;
            linked-compose)
                rm -- "${root}/compose.json"
                ln -s config/spec.json "${root}/compose.json"
                ;;
            missing-spec) rm -- "${root}/config/spec.json"; expected=0 ;;
            corrupt-spec) printf '{\n' >"${root}/config/spec.json"; mode=restore expected=0 ;;
            corrupt-enabled)
                printf '{\n' >"${root}/config/spec.json"
                printf '{"host_integrations":[{"type":"%s"}]}\n' "${type}" >"${root}/deployment.json"
                mode=restore
                ;;
            corrupt-missing) printf '{\n' >"${root}/config/spec.json"; rm -- "${root}/deployment.json"; mode=restore ;;
            restore-jq-failure) printf '{\n' >"${root}/config/spec.json"; mode=restore ;;
            esac
            (
                if [[ "${scenario}" == *jq-failure ]]; then
                    jq() {
                        command jq "$@" || return $?
                        [[ "$*" != *'--slurpfile deployment '* ]] || return 17
                    }
                fi
                status=0
                dockerFail2banDisablePrepare "${next}" "${mode}" "${scope}" \
                    >"${TEST_ROOT}/disable-output" 2>"${TEST_ROOT}/disable-error" || status=$?
                [[ "${status}" == "${expected}" ]] ||
                    fail "停用元数据结果错误: ${scope}/${scenario}/${status}"
            )
            [[ $(<"${TEST_ROOT}/disable-events") == ps || "${scenario}" == enabled ]] ||
                fail "元数据失败仍触发审计或清理: ${scope}/${scenario}"
            if [[ "${scenario}" == enabled ]]; then
                grep -Fxq "audit:${scope}" "${TEST_ROOT}/disable-events" &&
                    grep -Fxq "clean:${scope}" "${TEST_ROOT}/disable-events" ||
                    fail "已启用的旧保护未审计和清理: ${scope}"
            fi
            rm -f -- "${root}/deployment.json" "${root}/compose.json"
        done
    done
)
printf 'docker-fail2ban-metadata-regression-ok\n'
