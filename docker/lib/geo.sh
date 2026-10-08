#!/usr/bin/env bash

if [[ "${PADM_DOCKER_GEO_LOADED:-}" == 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_GEO_LOADED=1
readonly PADM_DOCKER_GEO_SCHEMA=1
DOCKER_GEO_STAGE=
DOCKER_GEO_SWITCHED=0
DOCKER_GEO_RUNNING=0

dockerGeoStateValidate() {
    local directory=$1 file digest
    [[ -d "${directory}" && ! -L "${directory}" &&
        -z "$(find "${directory}" ! -type f ! -type d -print -quit)" &&
        "$(find "${directory}" -mindepth 1 -maxdepth 1 | wc -l)" == 3 ]] || return 1
    for file in state.json geoip.dat geosite.dat; do
        [[ -s "${directory}/${file}" && ! -L "${directory}/${file}" ]] || return 1
    done
    jq -es '
      length == 1 and (.[0] |
        type == "object" and keys == ["enabled","schema_version","sha256","version"] and
        .schema_version == 1 and (.enabled | type == "boolean") and
        (.version | type == "string" and length <= 128 and
          test("^[A-Za-z0-9][A-Za-z0-9._-]*$") and . != "latest") and
        (.sha256 | type == "object" and keys == ["geoip.dat","geosite.dat"] and
          all(.[]; type == "string" and test("^[0-9a-f]{64}$"))))
    ' "${directory}/state.json" >/dev/null 2>&1 || return 1
    for file in geoip.dat geosite.dat; do
        digest=$(sha256sum "${directory}/${file}") || return 1
        [[ "${digest%% *}" == "$(jq -r --arg file "${file}" '.sha256[$file]' "${directory}/state.json")" ]] ||
            return 1
    done
}

dockerGeoPrepareCandidate() {
    local root=$1 candidate=$2 directory="${1}/config/xray/geo"
    dockerTrafficSafePath "${root}" "${directory}" || return 1
    [[ -e "${directory}" || -L "${directory}" ]] || return 0
    dockerGeoStateValidate "${directory}" || return 1
    cp -a -- "${directory}" "${candidate}/config/xray/geo"
}

dockerGeoBundleCheck() {
    local bundle=$1 root=${2:-} directory
    [[ -n "${root}" ]] || root=$(dockerInstallRoot) || return 1
    directory="${root}/config/xray/geo"
    dockerTrafficSafePath "${root}" "${directory}" || return 1
    [[ -e "${directory}" || -L "${directory}" ]] || return 0
    dockerGeoStateValidate "${directory}" &&
        [[ -f "${bundle}/docker/lib/geo.sh" && ! -L "${bundle}/docker/lib/geo.sh" ]] &&
        grep -qxF 'readonly PADM_DOCKER_GEO_SCHEMA=1' "${bundle}/docker/lib/geo.sh" || {
        dockerError '目标控制 bundle 不支持当前受管 Geo 数据，请选择兼容版本'
        return 1
    }
}

dockerGeoInterrupted() {
    local root stage=${DOCKER_GEO_STAGE:-} directory
    [[ -n "${stage}" ]] || return 0
    root=$(dockerInstallRoot) || return 1
    directory="${root}/config/xray/geo"
    dockerTrafficSafePath "${root}" "${stage}" &&
        [[ "${stage}" == "${root}/.geo."* && -d "${stage}" && -O "${stage}" &&
            -z "$(find "${stage}" ! -type f ! -type d -print -quit)" ]] || return 1
    if [[ "${DOCKER_GEO_SWITCHED}" == 1 ]]; then
        dockerTrafficSafePath "${root}" "${directory}" &&
            dockerRemoveManagedTree "${root}" "${directory}" || return 1
        [[ ! -d "${stage}/previous" ]] || cp -a -- "${stage}/previous" "${directory}" || return 1
        cp -a -- "${stage}/compose.previous.json" "${root}/compose.json" || return 1
        if [[ -f "${stage}/runtime-changed" ]]; then
            if [[ "${DOCKER_GEO_RUNNING}" == 1 ]]; then
                dockerTrafficSnapshot xray || dockerError 'Geo 恢复前采集失败，已保留历史流量'
                dockerComposeRun up -d --no-deps --force-recreate --wait \
                    --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" xray || return 1
            else
                dockerComposeRun stop xray && dockerComposeRun rm -f xray || return 1
            fi
        fi
        DOCKER_GEO_SWITCHED=0
    fi
    dockerRemoveManagedTree "${root}" "${stage}" || return 1
    DOCKER_GEO_STAGE=
}

dockerGeoStage() {
    local root directory stage
    [[ -z "${DOCKER_GEO_STAGE:-}" ]] || return 1
    root=$(dockerInstallRoot) || return 1
    directory="${root}/config/xray/geo"
    dockerTrafficSafePath "${root}" "${directory}" &&
        dockerTrafficSafePath "${root}" "${root}/compose.json" &&
        [[ -f "${root}/compose.json" && ! -L "${root}/compose.json" ]] || return 1
    [[ ! -e "${directory}" && ! -L "${directory}" ]] ||
        dockerGeoStateValidate "${directory}" || return 1
    stage=$(mktemp -d "${root}/.geo.XXXXXX") || return 1
    DOCKER_GEO_STAGE=${stage}
    DOCKER_GEO_SWITCHED=0
    DOCKER_GEO_RUNNING=0
    chmod 0700 "${stage}" &&
        cp -a -- "${root}/compose.json" "${stage}/compose.previous.json" || return 1
    [[ ! -d "${directory}" ]] || cp -a -- "${directory}" "${stage}/previous" || return 1
    mkdir -p -- "${stage}/config/xray"
}

dockerGeoResult() {
    local status=$1 version=$2 root file temp
    root=$(dockerInstallRoot) || return 1
    file="${root}/data/xray/geo-update.json"
    dockerTrafficSafePath "${root}" "${file}" &&
        mkdir -p -- "${root}/data/xray" || return 1
    temp=$(mktemp "${root}/data/xray/.geo-result.XXXXXX") || return 1
    if jq -n --arg status "${status}" --arg version "${version}" \
        '{status:$status,version:$version,finished_at:(now|todate)}' >"${temp}" &&
        chmod 0600 "${temp}" && chown 0:0 "${temp}" && mv -f -- "${temp}" "${file}"; then
        return 0
    fi
    rm -f -- "${temp}"
    return 1
}

dockerGeoUpdate() {
    local version=$1 root stage directory enabled=false file digest image ids
    local -a runner=()
    root=$(dockerInstallRoot) || return 1
    dockerRequireCommand curl && dockerRequireCommand sha256sum && dockerRequireCommand timeout &&
        dockerGeoStage || return 1
    stage=${DOCKER_GEO_STAGE}
    directory="${stage}/config/xray/geo"
    mkdir -- "${directory}" || return 1
    if [[ -z "${version}" ]]; then
        curl -LfSs --connect-timeout 15 --max-time 60 \
            'https://api.github.com/repos/Loyalsoldier/v2ray-rules-dat/releases/latest' \
            -o "${stage}/release.json" || return 1
        version=$(jq -ers 'if length == 1 then .[0].tag_name else empty end |
          select(type == "string" and length <= 128 and
            test("^[A-Za-z0-9][A-Za-z0-9._-]*$") and . != "latest")' \
            "${stage}/release.json") || return 1
    fi
    for file in geoip.dat geosite.dat; do
        curl -LfSs --connect-timeout 15 --max-time 180 --max-filesize 134217728 \
            "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/${file}" \
            -o "${directory}/${file}" &&
            curl -LfSs --connect-timeout 15 --max-time 60 --max-filesize 1024 \
                "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/download/${version}/${file}.sha256sum" \
                -o "${stage}/${file}.sha256sum" || return 1
        [[ -s "${directory}/${file}" ]] || return 1
        IFS= read -r digest <"${stage}/${file}.sha256sum" || return 1
        [[ "${digest}" =~ ^([0-9a-fA-F]{64})[[:space:]]+\*?${file//./\\.}$ &&
            "$(wc -l <"${stage}/${file}.sha256sum")" == 1 ]] || return 1
        digest=${BASH_REMATCH[1],,}
        [[ "$(sha256sum "${directory}/${file}" | cut -d ' ' -f1)" == "${digest}" ]] || {
            dockerError "Geo 摘要校验失败: ${file}"
            return 1
        }
    done
    [[ ! -d "${stage}/previous" ]] ||
        enabled=$(jq -r '.enabled' "${stage}/previous/state.json") || return 1
    jq -n --arg version "${version}" --argjson enabled "${enabled}" \
        --arg geoip "$(sha256sum "${directory}/geoip.dat" | cut -d ' ' -f1)" \
        --arg geosite "$(sha256sum "${directory}/geosite.dat" | cut -d ' ' -f1)" '
        {schema_version:1,version:$version,enabled:$enabled,
          sha256:{"geoip.dat":$geoip,"geosite.dat":$geosite}}
    ' >"${directory}/state.json" || return 1
    dockerGeoStateValidate "${directory}" || return 1
    cp -- "${root}/config/xray/config.json" "${stage}/config/xray/config.json" &&
        jq '.services.xray.environment.XRAY_LOCATION_ASSET = "/etc/padm/xray/geo"' \
            "${root}/compose.json" >"${stage}/compose.json" || return 1
    # 独立无网络探针强制加载两份数据，再验证当前配置，不触碰生产容器。
    jq -n '{outbounds:[{protocol:"freedom",tag:"direct"}],routing:{rules:[
      {type:"field",domain:["geosite:cn"],outboundTag:"direct"},
      {type:"field",ip:["geoip:cn"],outboundTag:"direct"}]}}' >"${stage}/probe.json" || return 1
    image=$(jq -er '.images.xray | select(test("@sha256:[0-9a-f]{64}$"))' "${root}/config/spec.json") || return 1
    chmod 0750 "${stage}/config/xray" "${directory}" &&
        chmod 0640 "${stage}/config/xray/config.json" "${directory}/"* "${stage}/probe.json" &&
        chown -R "0:${PADM_DOCKER_CONTAINER_GID}" "${stage}/config" "${stage}/probe.json" || return 1
    runner=(dockerRealityProbeRun 60 --network none --env XRAY_LOCATION_ASSET=/etc/padm/xray/geo
        --volume "${stage}/config/xray:/etc/padm/xray:ro" --volume "${stage}/probe.json:/probe.json:ro")
    if jq -e '.services.xray.volumes[]? | select(.target == "/etc/padm/secrets/tls")' \
        "${root}/compose.json" >/dev/null; then
        runner+=(--volume "${root}/secrets/tls:/etc/padm/secrets/tls:ro")
    fi
    "${runner[@]}" "${image}" -test -config /probe.json &&
        "${runner[@]}" "${image}" -test -config /etc/padm/xray/config.json || return 1
    ids=$(dockerComposeRun ps --status running -q xray) || return 1
    if [[ -n "${ids}" ]]; then
        dockerTrafficSnapshot xray || {
            dockerError 'Geo 更新前流量采集失败，已拒绝重建 Xray'
            return 1
        }
        DOCKER_GEO_RUNNING=1
    fi
    DOCKER_GEO_SWITCHED=1
    dockerRemoveManagedTree "${root}" "${root}/config/xray/geo" &&
        mv -- "${directory}" "${root}/config/xray/geo" &&
        cp -- "${stage}/compose.json" "${root}/compose.json" || return 1
    if [[ "${DOCKER_GEO_RUNNING}" == 1 ]]; then
        : >"${stage}/runtime-changed"
        dockerComposeRun up -d --no-deps --force-recreate --wait \
            --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" xray || return 1
    fi
    dockerGeoResult success "${version}" || return 1
    DOCKER_GEO_SWITCHED=0
    dockerGeoInterrupted || return 1
    printf 'Geo 数据已更新: %s\n' "${version}"
}

dockerGeoScheduleChange() {
    local action=$1 root stage enabled=false
    root=$(dockerInstallRoot) || return 1
    if [[ "${action}" == enable ]]; then enabled=true; fi
    dockerGeoStage || return 1
    stage=${DOCKER_GEO_STAGE}
    [[ -d "${stage}/previous" ]] || {
        dockerError '请先完成一次 Geo 更新，再启用调度'
        return 1
    }
    jq --argjson enabled "${enabled}" '.enabled = $enabled' \
        "${stage}/previous/state.json" >"${stage}/state.json" &&
        chmod 0640 "${stage}/state.json" && chown "0:${PADM_DOCKER_CONTAINER_GID}" "${stage}/state.json" || return 1
    # 先登记恢复窗口再改文件；调度失败时保留旧 Geo 和旧任务。
    DOCKER_GEO_SWITCHED=1
    if [[ "${action}" == enable ]]; then dockerGeoScheduleApply install;
    else dockerGeoScheduleApply remove; fi || return 1
    mv -- "${stage}/state.json" "${root}/config/xray/geo/state.json" || return 1
    dockerGeoScheduleCommit && dockerGeoInterrupted
}

dockerGeoScheduleRemove() {
    local unitDir=${PADM_DOCKER_SYSTEMD_DIR:-/etc/systemd/system} content
    if [[ ! -e "${unitDir}/padm-docker-geo.service" && ! -L "${unitDir}/padm-docker-geo.service" &&
        ! -e "${unitDir}/padm-docker-geo.timer" && ! -L "${unitDir}/padm-docker-geo.timer" ]]; then
        command -v crontab >/dev/null 2>&1 || return 0
        content=$(dockerTrafficReadCrontab) || return 1
        [[ "${content}" == *'# padm-docker Geo 自动更新'* ]] || return 0
    fi
    dockerGeoScheduleApply remove
}

dockerGeoScheduleInstall() {
    local root directory
    root=$(dockerInstallRoot) || return 1
    directory="${root}/config/xray/geo"
    dockerTrafficSafePath "${root}" "${directory}" || return 1
    if [[ -e "${directory}" || -L "${directory}" ]]; then
        dockerGeoStateValidate "${directory}" || return 1
        if jq -e '.enabled == true' "${directory}/state.json" >/dev/null; then
            dockerGeoScheduleApply install
            return $?
        fi
    fi
    dockerGeoScheduleRemove
}

dockerGeoCommand() {
    local action=${1:-status} version= schedule= root directory status=0
    [[ "$#" == 0 ]] || shift
    case "${action}" in
    update)
        if [[ "$#" != 0 ]]; then
            [[ "$#" == 2 && "$1" == --version && "${#2}" -le 128 &&
                "$2" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$2" != latest ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            version=$2
        fi
        ;;
    schedule)
        [[ "$#" == 1 ]] || return "${PADM_DOCKER_RC_USAGE}"
        schedule=$1
        case "${schedule}" in enable|disable|status) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
        ;;
    status|auto-update) [[ "$#" == 0 ]] || return "${PADM_DOCKER_RC_USAGE}" ;;
    *) return "${PADM_DOCKER_RC_USAGE}" ;;
    esac
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    directory="${root}/config/xray/geo"
    dockerTrafficSafePath "${root}" "${root}/config/spec.json" &&
        [[ -f "${root}/config/spec.json" ]] &&
        jq -e '[.core.type,.core.secondary_type] | index("xray") != null' \
            "${root}/config/spec.json" >/dev/null || {
        dockerError '当前部署不包含 Xray，不能管理 Geo 数据'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerTrafficSafePath "${root}" "${directory}" || return "${PADM_DOCKER_RC_STATE}"
    [[ ! -e "${directory}" && ! -L "${directory}" ]] ||
        dockerGeoStateValidate "${directory}" || return "${PADM_DOCKER_RC_STATE}"
    case "${action}" in
    status)
        if [[ -d "${directory}" ]]; then
            jq -r '"Geo version=\(.version) enabled=\(.enabled) source=managed"' "${directory}/state.json"
        else printf 'Geo source=image enabled=false\n'; fi
        ;;
    schedule)
        if [[ "${schedule}" == status ]]; then
            if [[ -d "${directory}" ]]; then jq -r '"Geo enabled=\(.enabled)"' "${directory}/state.json";
            else printf 'Geo enabled=false\n'; fi
        else dockerGeoScheduleChange "${schedule}" || status=${PADM_DOCKER_RC_STATE}; fi
        ;;
    update|auto-update)
        if [[ "${action}" == auto-update ]]; then
            [[ -d "${directory}" ]] &&
                jq -e '.enabled == true' "${directory}/state.json" >/dev/null || return 0
        fi
        dockerGeoUpdate "${version}" || {
            status=${PADM_DOCKER_RC_STATE}
            dockerGeoResult failure "${version}" || true
        }
        ;;
    esac
    return "${status}"
}
