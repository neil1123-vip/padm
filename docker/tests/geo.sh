#!/usr/bin/env bash
set -euo pipefail

[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || {
    printf 'docker-geo-regression requires Linux root\n' >&2
    exit 1
}
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-geo.XXXXXX")
trap '[[ "${PADM_TEST_KEEP:-0}" == 1 ]] || rm -rf -- "${TEST_ROOT}"' EXIT
export PADM_DOCKER_SKIP_CHOWN=0 PADM_DOCKER_LOCK_TIMEOUT=0 PADM_DOCKER_HEALTH_TIMEOUT=1
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

VERSION=202610070140
NEXT_VERSION=202610080140
BACKEND=systemd
MODE=ok
FRAGMENT_OVERRIDE=
fail() {
    printf 'docker-geo-regression-fail: %s\n' "$*" >&2
    [[ ! -f "${TEST_ROOT}/control.log" ]] || cat "${TEST_ROOT}/control.log" >&2
    exit 1
}
reject() { if "$@" >"${TEST_ROOT}/rejected.log" 2>&1; then fail "应拒绝: $*"; fi; }
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { [[ "$(<"${PADM_DOCKER_INSTALL_DIR}/mode")" == docker ]]; }
dockerComposeFile() { printf '%s/compose.json\n' "${PADM_DOCKER_INSTALL_DIR}"; }
dockerSetupCleanup() { :; }
dockerEntryCleanup() { :; }
dockerTrafficSnapshot() {
    [[ "$#" == 1 && "$1" == xray && "$(<"${TEST_ROOT}/running")" == 1 ]] ||
        fail 'Geo 没有只采集正在运行的 Xray'
    printf 'snapshot\n' >>"${TEST_ROOT}/docker.log"
    [[ "${MODE}" != traffic-fail ]]
}

# 只替代外部下载，仍由真实更新逻辑解析元数据、验证两份摘要和提交文件。
curl() {
    local argument previous= url= output= content= name tag digest
    for argument in "$@"; do
        if [[ "${previous}" == -o || "${previous}" == --output ]]; then output=${argument}; fi
        [[ "${argument}" != https://* ]] || url=${argument}
        previous=${argument}
    done
    [[ -n "${url}" ]] || fail '下载没有明确 URL'
    printf '%s\n' "${url}" >>"${TEST_ROOT}/download.log"
    [[ "${MODE}" != download-fail ]] || return 1
    if [[ "${MODE}" == download-term ]]; then kill -TERM "${BASHPID}"; fi
    if [[ "${url}" == */releases/latest ]]; then
        case "${MODE}" in
        latest-missing) content='{}' ;;
        latest-multi) content=$'{"tag_name":"202610070140"}\n{"tag_name":"202610080140"}' ;;
        *) content="{\"tag_name\":\"${VERSION}\"}" ;;
        esac
    elif [[ "${url}" == */releases/download/* ]]; then
        name=${url##*/}
        tag=${url%/*}
        tag=${tag##*/}
        [[ "${tag}" != latest && "${tag}" =~ ^[A-Za-z0-9._-]+$ ]] ||
            fail 'Geo 下载没有固定发布 tag'
        case "${name}" in
        geoip.dat|geosite.dat) content="valid-${tag}-${name}" ;;
        geoip.dat.sha256sum|geosite.dat.sha256sum)
            name=${name%.sha256sum}
            digest=$(printf 'valid-%s-%s\n' "${tag}" "${name}" | sha256sum | awk '{print $1}')
            [[ "${MODE}:${name}" != digest-fail:geosite.dat ]] || digest=$(printf '0%.0s' {1..64})
            content="${digest}  ${name}"
            ;;
        *) fail "意外 Geo 发布资产: ${name}" ;;
        esac
    else
        fail "意外下载 URL: ${url}"
    fi
    if [[ -n "${output}" ]]; then printf '%s\n' "${content}" >"${output}";
    else printf '%s\n' "${content}"; fi
}

docker() {
    local operation=${1:-} argument previous= compose= image= format= status=0
    printf '%s\n' "$*" >>"${TEST_ROOT}/docker.log"
    case "${operation}" in
    compose)
        for argument in "$@"; do
            [[ "${previous}" != --file && "${previous}" != -f ]] || compose=${argument}
            previous=${argument}
        done
        if [[ " $* " == *' ps '* ]]; then
            [[ "$(<"${TEST_ROOT}/running")" != 1 ]] || printf 'xray-test-container\n'
        elif [[ " $* " == *' run '* ]]; then
            [[ "${MODE}" != probe-fail ]] || return 1
            [[ ! -f "${compose}" ]] || jq -e '.services.xray.environment.XRAY_LOCATION_ASSET == "/etc/padm/xray/geo"' \
                "${compose}" >/dev/null || fail '候选 Xray 未指向受管 Geo 路径'
        elif [[ " $* " == *' up '* || " $* " == *' restart '* ]]; then
            [[ " $* " == *' --no-deps '* && " $* " == *' xray '* ]] || fail 'Geo 更新重建了非 Xray 服务'
            if [[ "${MODE}" == restart-fail && ! -e "${TEST_ROOT}/failed-once" ]]; then
                : >"${TEST_ROOT}/failed-once"
                return 1
            fi
            if [[ "${MODE}" == restart-term && ! -e "${TEST_ROOT}/failed-once" ]]; then
                : >"${TEST_ROOT}/failed-once"
                kill -TERM "${BASHPID}"
            fi
            printf '1\n' >"${TEST_ROOT}/running"
        elif [[ " $* " == *' down '* && "${MODE}" == uninstall ]]; then
            [[ -z "$(find "${PADM_DOCKER_SYSTEMD_DIR}" -name '*geo*' -print -quit)" &&
                "$(grep -c 'geo auto-update' "${TEST_ROOT}/crontab" || true)" == 0 ]] ||
                fail '卸载停止服务时仍有 Geo 自动调度'
        elif [[ " $* " == *' stop '* || " $* " == *' rm '* ]]; then
            [[ " $* " == *' xray '* ]] || fail 'Geo 回退操作了非 Xray 服务'
            printf '0\n' >"${TEST_ROOT}/running"
        fi
        ;;
    inspect)
        for argument in "$@"; do
            [[ "${previous}" != --format && "${previous}" != -f ]] || format=${argument}
            previous=${argument}
        done
        case "${format}" in
        *State.Running*) [[ "$(<"${TEST_ROOT}/running")" != 1 ]] || printf 'true\n' ;;
        *State.Status*) [[ "$(<"${TEST_ROOT}/running")" != 1 ]] || printf 'running\n' ;;
        *State.Health*) printf 'healthy\n' ;;
        *State.Pid*) printf '1234\n' ;;
        *json*)
            jq -n --argjson running "$(<"${TEST_ROOT}/running")" '[{Id:"xray-test-container",State:{Running:($running == 1),Status:(if $running == 1 then "running" else "exited" end),Health:{Status:"healthy"}}}]'
            ;;
        *) printf 'xray-test-container\n' ;;
        esac
        ;;
    ps)
        if [[ "$*" != 'ps -aq --filter label=com.docker.compose.project=padm-docker --filter label=com.docker.compose.service=net-fail2ban --filter label=com.docker.compose.oneoff=False' ]]; then
            [[ "$(<"${TEST_ROOT}/running")" != 1 ]] || printf 'xray-test-container\n'
        fi
        ;;
    run)
        [[ "${MODE}" != probe-fail ]] || status=1
        for argument in "$@"; do
            [[ "${argument}" != *@sha256:* ]] || image=${argument}
        done
        [[ -n "${image}" ]] || fail 'Geo 探针没有固定摘要镜像'
        return "${status}"
        ;;
    pull|rm|stop) ;;
    *) fail "意外 Docker 操作: $*" ;;
    esac
}

systemctl() {
    printf '%s\n' "$*" >>"${TEST_ROOT}/schedule.log"
    case "$1" in
    show-environment) [[ "${BACKEND}" == systemd ]]; return $? ;;
    show) printf '%s\n' "${FRAGMENT_OVERRIDE}"; return 0 ;;
    esac
    if [[ "${MODE}" == schedule-fail && ( "$1" == enable || "$1" == disable ) &&
        ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"
        return 1
    fi
    case "$1" in
    enable) : >"${TEST_ROOT}/timer-enabled"; [[ "$*" != *--now* ]] || : >"${TEST_ROOT}/timer-active" ;;
    start) : >"${TEST_ROOT}/timer-active" ;;
    stop) rm -f -- "${TEST_ROOT}/timer-active" ;;
    disable)
        rm -f -- "${TEST_ROOT}/timer-enabled"
        [[ "$*" != *--now* ]] || rm -f -- "${TEST_ROOT}/timer-active"
        ;;
    is-enabled) [[ -f "${TEST_ROOT}/timer-enabled" ]]; return $? ;;
    is-active) [[ -f "${TEST_ROOT}/timer-active" ]]; return $? ;;
    esac
    if [[ "${MODE}" == schedule-term && ( "$1" == enable || "$1" == disable ) &&
        ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"
        kill -TERM "${BASHPID}"
    fi
}
crontab() {
    if [[ "$1" == -l ]]; then cat "${TEST_ROOT}/crontab"; return 0; fi
    [[ "$1" == - ]] || fail '意外 crontab 参数'
    if [[ "${MODE}" == schedule-fail && ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"
        return 1
    fi
    cat >"${TEST_ROOT}/crontab"
    if [[ "${MODE}" == schedule-term && ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"
        kill -TERM "${BASHPID}"
    fi
}
pgrep() { [[ "${BACKEND}" == cron && "$*" == '-x cron' ]]; }
timeout() {
    # 外部进程边界由桩执行，保留真实探针参数与候选清理。
    shift 4
    "$@"
}

newState() {
    export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/$1"
    export PADM_DOCKER_SYSTEMD_DIR="${PADM_DOCKER_INSTALL_DIR}/systemd"
    dockerInitializeStateRoot
    mkdir -p "${PADM_DOCKER_INSTALL_DIR}/config/xray" "${PADM_DOCKER_INSTALL_DIR}/config/sing-box" \
        "${PADM_DOCKER_INSTALL_DIR}/data/traffic" "${PADM_DOCKER_SYSTEMD_DIR}"
    jq -n '
      {schema_version:3,release:{version:"3.1.8",manifest_sha256:("1"*64),signature_identity:"fixture"},
       core:{type:"xray",secondary_type:"sing-box",protocols:[
         {id:1,core:"xray",listener_id:"entry-1",server:"proxy.example.com",public_port:24443,
          address_families:["ipv4"],name:"self",uuid:"11111111-1111-4111-8111-111111111111",
          reality:{server_name:"www.example.com",target_host:"www.example.com",target_port:443,
            private_key:("A"*43),public_key:("B"*43),short_id:"1234abcd"}}]},
       tls:null,subscription:{enabled:false,token:"geo-test-subscription-token"},host_integrations:[],
       images:(["xray","sing-box","nginx","ops","net"] |
         map({key:.,value:("ghcr.io/example/padm-"+.+":test@sha256:"+("1"*64))}) | from_entries)}
    ' >"${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    dockerGenerateXrayConfig "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json"
    cp "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json" "${PADM_DOCKER_INSTALL_DIR}/config/xray/users.base"
    printf '{"inbounds":[],"outbounds":[]}\n' >"${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json"
    printf '{"schema_version":3,"core":{"type":"xray","secondary_type":"sing-box"},"host_integrations":[],"compose":{"profiles":["core-xray","core-sing-box"]}}\n' \
        >"${PADM_DOCKER_INSTALL_DIR}/deployment.json"
    printf '{"accounts":{"11111111-1111-4111-8111-111111111111":{"upload":123,"download":456}}}\n' \
        >"${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json"
    dockerGenerateCompose "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${PADM_DOCKER_INSTALL_DIR}/compose.json"
    dockerGenerateImagesEnv "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" "${PADM_DOCKER_INSTALL_DIR}"
    printf '# unrelated job\n' >"${TEST_ROOT}/crontab"
    printf '1\n' >"${TEST_ROOT}/running"
    for log in docker download schedule; do : >"${TEST_ROOT}/${log}.log"; done
    rm -f -- "${TEST_ROOT}/failed-once" "${TEST_ROOT}/timer-enabled" "${TEST_ROOT}/timer-active"
    MODE=ok
    FRAGMENT_OVERRIDE=
}
geoDir() { printf '%s/config/xray/geo\n' "${PADM_DOCKER_INSTALL_DIR}"; }
identity() (
    cd "${PADM_DOCKER_INSTALL_DIR}"
    sha256sum config/spec.json config/xray/config.json config/xray/users.base config/sing-box/config.json \
        data/traffic/state.json deployment.json images.env
)
materials() (
    cd "${PADM_DOCKER_INSTALL_DIR}"
    sha256sum compose.json
    if [[ -d config/xray/geo ]]; then find config/xray/geo -type f -print0 | sort -z | xargs -0 -r sha256sum; fi
)
jobs() (
    cd "${PADM_DOCKER_INSTALL_DIR}"
    find systemd -type f -print0 | sort -z | xargs -0 -r sha256sum
    cat "${TEST_ROOT}/crontab"
    [[ ! -f "${TEST_ROOT}/timer-enabled" ]] || printf 'timer-enabled\n'
    [[ ! -f "${TEST_ROOT}/timer-active" ]] || printf 'timer-active\n'
)
assertClean() {
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'Geo 操作没有释放部署锁'
    [[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 2 -name '.geo.*' -print -quit)" ]] ||
        fail 'Geo 操作遗留候选'
}
runControl() {
    local expected=$1 status=0
    shift
    (dockerMain "$@") >"${TEST_ROOT}/control.log" 2>&1 || status=$?
    if [[ "${expected}" == failure ]]; then [[ "${status}" != 0 ]] || fail "应失败: $*";
    else [[ "${status}" == "${expected}" ]] || fail "$*: 预期 ${expected}，实际 ${status}"; fi
    assertClean
}

newState first-update
beforeIdentity=$(identity)
runControl 0 geo status
[[ ! -s "${TEST_ROOT}/download.log" && ! -d "$(geoDir)" ]] || fail '只读状态开始下载或创建受管 Geo'
runControl failure geo schedule enable
[[ ! -s "${TEST_ROOT}/download.log" ]] || fail '启用调度擅自下载 Geo'
runControl 0 geo update
[[ "$(<"$(geoDir)/geoip.dat")" == "valid-${VERSION}-geoip.dat" &&
    "$(<"$(geoDir)/geosite.dat")" == "valid-${VERSION}-geosite.dat" ]] || fail '更新没有提交完整 Geo 文件对'
dockerGeoStateValidate "$(geoDir)" || fail '提交的 Geo 状态不合法'
jq -e --arg version "${VERSION}" '.schema_version == 1 and .version == $version and .enabled == false and
    (.sha256 | keys == ["geoip.dat","geosite.dat"])' "$(geoDir)/state.json" >/dev/null || fail 'Geo 状态缺失版本或摘要'
jq -e '.services.xray.environment.XRAY_LOCATION_ASSET == "/etc/padm/xray/geo"' \
    "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null || fail '运行 Compose 未切换受管 Geo 路径'
[[ "$(identity)" == "${beforeIdentity}" && "$(<"${TEST_ROOT}/running")" == 1 ]] ||
    fail 'Geo 更新修改身份、累计或其它核心'

for running in 0 1; do
    printf '%s\n' "${running}" >"${TEST_ROOT}/running"
    : >"${TEST_ROOT}/docker.log"
    runControl 0 geo update --version "${NEXT_VERSION}"
    [[ "$(<"${TEST_ROOT}/running")" == "${running}" ]] || fail 'Geo 更新改变原 Xray 运行状态'
    [[ "${running}" != 0 ]] || ! grep -Eq ' up | restart ' "${TEST_ROOT}/docker.log" ||
        fail '停机更新启动了 Xray'
done

for mode in download-fail digest-fail probe-fail traffic-fail download-term restart-fail restart-term latest-missing latest-multi; do
    newState "failure-${mode}"
    runControl 0 geo update --version "${VERSION}"
    before=$(materials)
    beforeIdentity=$(identity)
    MODE=${mode}
    : >"${TEST_ROOT}/docker.log"
    expected=failure
    [[ "${mode}" != *-term ]] || expected=143
    if [[ "${mode}" == latest-* ]]; then runControl "${expected}" geo update;
    else runControl "${expected}" geo update --version "${NEXT_VERSION}"; fi
    [[ "$(materials)" == "${before}" && "$(identity)" == "${beforeIdentity}" &&
        "$(<"${TEST_ROOT}/running")" == 1 ]] || fail "${mode}: 更新失败没有恢复完整数据、Compose 和运行状态"
    [[ "${mode}" != traffic-fail ]] || ! grep -q ' up ' "${TEST_ROOT}/docker.log" ||
        fail '采集失败后仍重建 Xray'
done

newState invalid-state
runControl 0 geo update --version "${VERSION}"
cp "$(geoDir)/state.json" "${TEST_ROOT}/valid-state.json"
for mutation in '.enabled = "true"' '.schema_version = 2' '.sha256["geoip.dat"] = "bad"' '.version = "../escape"'; do
    jq "${mutation}" "${TEST_ROOT}/valid-state.json" >"$(geoDir)/state.json"
    reject dockerGeoStateValidate "$(geoDir)"
done
cp "${TEST_ROOT}/valid-state.json" "$(geoDir)/state.json"
printf 'corrupted\n' >>"$(geoDir)/geoip.dat"
reject dockerGeoStateValidate "$(geoDir)"
runControl failure geo schedule enable
for args in 'update --version ../escape' 'update --version' 'schedule unknown' 'unknown'; do
    read -r -a arguments <<<"${args}"
    runControl 2 geo "${arguments[@]}"
done

newState no-xray
for file in deployment.json config/spec.json; do
    jq '.core.type = "sing-box" | del(.core.secondary_type)' "${PADM_DOCKER_INSTALL_DIR}/${file}" \
        >"${TEST_ROOT}/no-xray.json"
    cp "${TEST_ROOT}/no-xray.json" "${PADM_DOCKER_INSTALL_DIR}/${file}"
done
before=$(materials)
runControl failure geo update --version "${VERSION}"
runControl failure geo schedule enable
[[ "$(materials)" == "${before}" && ! -s "${TEST_ROOT}/download.log" ]] ||
    fail '没有 Xray 的部署仍下载或修改 Geo'

for BACKEND in systemd cron; do
    newState "schedule-${BACKEND}"
    runControl 0 geo update --version "${VERSION}"
    runControl 0 geo schedule enable
    runControl 0 geo schedule enable
    jq -e '.enabled == true' "$(geoDir)/state.json" >/dev/null || fail '启用调度未持久化状态'
    runControl 0 geo schedule status
    if [[ "${BACKEND}" == systemd ]]; then
        [[ "$(find "${PADM_DOCKER_SYSTEMD_DIR}" -name '*geo*.timer' | wc -l)" == 1 ]] ||
            fail '重复安装了 Geo timer'
    else
        [[ "$(grep -c 'geo auto-update' "${TEST_ROOT}/crontab")" == 1 ]] || fail '重复安装了 Geo cron'
    fi
    for mode in schedule-fail schedule-term; do
        before=$(materials)
        beforeJobs=$(jobs)
        MODE=${mode}
        rm -f -- "${TEST_ROOT}/failed-once"
        runControl failure geo schedule disable
        [[ "$(materials)" == "${before}" && "$(jobs)" == "${beforeJobs}" ]] ||
            fail "${BACKEND}/${mode}: 调度失败没有恢复登记和任务"
    done
    MODE=ok
    runControl 0 geo schedule disable
    jq -e '.enabled == false' "$(geoDir)/state.json" >/dev/null || fail '停用调度没有持久化'
    [[ -z "$(find "${PADM_DOCKER_SYSTEMD_DIR}" -name '*geo*' -print -quit)" &&
        "$(grep -c 'geo auto-update' "${TEST_ROOT}/crontab" || true)" == 0 ]] || fail '停用后遗留 Geo 调度'
    # 配置恢复后按恢复的登记重新同步调度，不保留当前版本的开关。
    jq '.enabled = true' "$(geoDir)/state.json" >"${TEST_ROOT}/restored-state.json"
    cp "${TEST_ROOT}/restored-state.json" "$(geoDir)/state.json"
    dockerGeoScheduleInstall || fail '恢复启用登记后未安装调度'
    jq '.enabled = false' "$(geoDir)/state.json" >"${TEST_ROOT}/restored-state.json"
    cp "${TEST_ROOT}/restored-state.json" "$(geoDir)/state.json"
    dockerGeoScheduleInstall || fail '恢复停用登记后未移除调度'
    [[ -z "$(find "${PADM_DOCKER_SYSTEMD_DIR}" -name '*geo*' -print -quit)" &&
        "$(grep -c 'geo auto-update' "${TEST_ROOT}/crontab" || true)" == 0 ]] ||
        fail '恢复停用登记后遗留调度'
    : >"${TEST_ROOT}/download.log"
    runControl 0 geo auto-update
    [[ ! -s "${TEST_ROOT}/download.log" ]] || fail '已停用的自动任务仍下载'
    runControl 0 geo schedule enable
    (
        dockerDeploymentState() { printf 'active\n'; }
        dockerTrafficBeforeChange() { :; }
        dockerTrafficScheduleRemove() { :; }
        dockerRemoveCli() { :; }
        MODE=uninstall
        runControl 0 uninstall
        [[ -z "$(find "${PADM_DOCKER_SYSTEMD_DIR}" -name '*geo*' -print -quit)" &&
            "$(grep -c 'geo auto-update' "${TEST_ROOT}/crontab" || true)" == 0 ]] ||
            fail '卸载遗留 Geo 自动调度'
    )
done

for BACKEND in systemd cron; do
    newState "ownership-${BACKEND}"
    runControl 0 geo update --version "${VERSION}"
    if [[ "${BACKEND}" == systemd ]]; then
        printf 'external-unit\n' >"${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-geo.service"
    else
        printf '1 2 * * * external # padm-docker Geo 自动更新 root=/outside\n' >>"${TEST_ROOT}/crontab"
    fi
    before=$(materials)
    beforeJobs=$(jobs)
    runControl failure geo schedule enable
    [[ "$(materials)" == "${before}" && "$(jobs)" == "${beforeJobs}" ]] ||
        fail '覆盖了外部调度或保留启用状态'
done

printf 'docker-geo-regression-ok\n'
