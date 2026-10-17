#!/usr/bin/env bash

if [[ "${PADM_DOCKER_WIREGUARD_LOADED:-}" == 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_WIREGUARD_LOADED=1

dockerWireGuardConfigurationCheck() {
    local root spec path
    root=$(dockerInstallRoot) && spec=$(dockerAccountSpecFile) || return 1
    for path in deployment.json images.env compose.json secrets/net/wireguard/wg-padm.conf \
        data/net/wireguard/wireguard.state data/net/wireguard/wireguard/wg-padm.conf; do
        dockerTrafficSafePath "${root}" "${root}/${path}" || return 1
    done
    dockerComposeFile >/dev/null &&
        dockerManagedSpecMatchesDeployment "${spec}" "${root}/deployment.json" "${root}/images.env" &&
        cmp -s -- "${root}/compose.json" <(dockerGenerateCompose "${spec}" /dev/stdout "${root}") &&
        jq -e 'any(.host_integrations[]; .type == "wireguard")' "${spec}" >/dev/null &&
        dockerHostIntegrationInputsValidate "${spec}" &&
        [[ "$(stat -c '%u:%a:%h' "${root}/secrets/net/wireguard/wg-padm.conf")" == 0:600:1 ]] || {
        dockerError 'WireGuard 规格、部署、编排或配置权限漂移，未执行操作'
        return 1
    }
}

dockerWireGuardContainer() (
    local mode=${1:-running} health=${2:-1} root ids container image snapshot path
    [[ "$#" -le 2 && ( "${mode}" == running || "${mode}" == exited ) &&
        ( "${health}" == 0 || "${health}" == 1 ) ]] || return 1
    root=$(dockerInstallRoot) && dockerWireGuardConfigurationCheck || return 1
    ids=$(docker ps -aq --no-trunc --filter "label=com.docker.compose.project=${PADM_DOCKER_PROJECT}" \
        --filter label=com.docker.compose.service=net-wireguard \
        --filter label=com.docker.compose.oneoff=False) || return 1
    [[ "${ids}" =~ ^[a-f0-9]{64}$ ]] || return 1
    container=$(docker container inspect "${ids}") || return 1
    jq -e --arg root "${root}" --arg mode "${mode}" --arg id "${ids}" --arg health "${health}" \
        --slurpfile spec "${root}/config/spec.json" --slurpfile compose "${root}/compose.json" '
      length == 1 and (.[0] as $c | $c.Config.Labels as $labels |
        $compose[0].services["net-wireguard"] as $service |
        $c.Id == $id and
        $c.State.Paused == false and $c.State.Dead == false and
        (if $health == "0" and $mode == "running" then
           $c.State.Running == true and ($c.State.Status == "running" or $c.State.Status == "restarting")
         else
           $c.State.Restarting == false and $c.State.OOMKilled == false and $c.State.Error == "" and
           (if $mode == "running" then $c.State.Running == true and $c.State.Status == "running"
            else $c.State.Running == false and $c.State.Status == "exited" and
              ($health == "0" or $c.State.ExitCode == 0) end)
         end) and
        $labels["com.docker.compose.project"] == "padm-docker" and
        $labels["com.docker.compose.project.working_dir"] == $root and
        $labels["com.docker.compose.project.config_files"] == ($root + "/compose.json") and
        $labels["com.docker.compose.service"] == "net-wireguard" and
        $labels["com.docker.compose.oneoff"] == "False" and
        all($service.labels | to_entries[]; $labels[.key] == .value) and
        $c.Config.Image == $spec[0].images.net and $c.Config.Cmd == $service.command and
        $c.Config.Entrypoint == ["/usr/local/bin/padm-entrypoint"] and $c.Config.User == "0:0" and
        $c.Config.Healthcheck.Test == $service.healthcheck.test and
        $c.HostConfig.NetworkMode == "host" and $c.HostConfig.Init == $service.init and
        $c.HostConfig.RestartPolicy.Name == $service.restart and
        $c.HostConfig.ReadonlyRootfs == $service.read_only and $c.HostConfig.Privileged == false and
        $c.HostConfig.PidsLimit == $service.pids_limit and
        ($c.HostConfig.PortBindings // {} | length) == 0 and
        ($c.HostConfig.Devices // [] | length) == 0 and
        ($c.HostConfig.DeviceRequests // [] | length) == 0 and
        ($c.HostConfig.CapAdd | map(sub("^CAP_"; "")) | sort) == ($service.cap_add | sort) and
        ($c.HostConfig.CapDrop | map(sub("^CAP_"; "")) | sort) == ($service.cap_drop | sort) and
        $c.HostConfig.SecurityOpt == $service.security_opt and
        $c.HostConfig.LogConfig.Type == $service.logging.driver and
        $c.HostConfig.LogConfig.Config == $service.logging.options and
        all($c.Mounts[]; .Type == "bind") and
        ($c.HostConfig.Tmpfs // {}) ==
          ($service.tmpfs | map(capture("^(?<key>[^:]+):(?<value>.+)$")) | from_entries) and
        ($c.Mounts | map({source:.Source,target:.Destination,read_only:(.RW | not)}) | sort_by(.target)) ==
          ($service.volumes | map({source:(.source | sub("^\\$\\{PADM_NET_ROOT\\}"; $root)),
            target,read_only}) | sort_by(.target)))
    ' <<<"${container}" >/dev/null || {
        dockerError 'WireGuard 容器状态或归属漂移，未执行操作'
        return 1
    }
    if [[ "${mode}" == running && "${health}" == 1 ]]; then
        snapshot=${root}/data/net/wireguard/wireguard/wg-padm.conf
        [[ -d "${root}/data/net/wireguard/wireguard" &&
            "$(stat -c '%u:%a' "${root}/data/net/wireguard/wireguard")" == 0:700 &&
            -f "${snapshot}" && "$(stat -c '%u:%a:%h' "${snapshot}")" == 0:600:1 ]] &&
            cmp -s -- "${root}/secrets/net/wireguard/wg-padm.conf" "${snapshot}" &&
            docker exec "${ids}" /usr/local/bin/padm-entrypoint wireguard-health wg-padm </dev/null || {
            dockerError 'WireGuard 启动配置、接口或状态归属漂移，未执行操作'
            return 1
        }
    elif [[ "${mode}" == exited ]]; then
        for path in "${root}/data/net/wireguard/wireguard.state" "${root}/data/net/wireguard/wireguard"; do
            [[ ! -e "${path}" && ! -L "${path}" ]] || {
                dockerError 'WireGuard 停止后仍有恢复状态，保留现场'
                return 1
            }
        done
        image=$(jq -er '.images.net' "${root}/config/spec.json") || return 1
        docker run --rm --network host --read-only --cap-drop ALL \
            --security-opt no-new-privileges:true --pids-limit 16 --user 0:0 \
            --entrypoint /bin/sh "${image}" -ec \
            'ip -o link show >/dev/null && ! ip link show dev wg-padm >/dev/null 2>&1' </dev/null || {
            dockerError 'WireGuard 停止后接口仍存在或无法核实，保留现场'
            return 1
        }
    fi
    printf '%s\n' "${ids}"
)

dockerWireGuardService() (
    local action=${1:-} root spec ids container mode audited timeout deadline
    local attempted=0
    [[ "$#" == 1 && ( "${action}" == start || "${action}" == stop ) ]] ||
        return "${PADM_DOCKER_RC_USAGE}"
    root=$(dockerInstallRoot) && spec=$(dockerAccountSpecFile) &&
        dockerWireGuardConfigurationCheck || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${action}" == stop ]] &&
        ! jq -e '.control == null and .control_sync == null' "${spec}" >/dev/null; then
        dockerError '控制角色或控制同步依赖 WireGuard，不能单独停止'
        return "${PADM_DOCKER_RC_STATE}"
    fi
    ids=$(docker ps -aq --no-trunc --filter "label=com.docker.compose.project=${PADM_DOCKER_PROJECT}" \
        --filter label=com.docker.compose.service=net-wireguard \
        --filter label=com.docker.compose.oneoff=False) || return "${PADM_DOCKER_RC_STATE}"
    if [[ -z "${ids}" ]]; then
        if [[ "${action}" == start ]]; then
            dockerError 'WireGuard 容器缺失，将按原规格完整恢复所有服务'
            # 完整事务的回滚变量属于本子 shell，退出清理必须留在同一作用域。
            trap 'status=$?; trap - EXIT INT TERM; dockerConfigurationInterrupted; exit "${status}"' EXIT
            trap 'exit 130' INT
            trap 'exit 143' TERM
            dockerAccountApplyDraft "${spec}"
            return
        fi
        dockerError 'WireGuard 容器缺失，无法审计停止状态'
        return "${PADM_DOCKER_RC_STATE}"
    fi
    [[ "${ids}" =~ ^[a-f0-9]{64}$ ]] || return "${PADM_DOCKER_RC_STATE}"
    container=$(docker container inspect "${ids}") || return "${PADM_DOCKER_RC_STATE}"
    mode=$(jq -er --arg id "${ids}" '
      if length == 1 and .[0].Id == $id then
        if .[0].State.Running == true then "running"
        elif .[0].State.Running == false then "exited"
        else error("unknown container state") end
      else error("container identity changed") end
    ' <<<"${container}") || return "${PADM_DOCKER_RC_STATE}"
    audited=$(dockerWireGuardContainer "${mode}") && [[ "${audited}" == "${ids}" ]] ||
        return "${PADM_DOCKER_RC_STATE}"
    if [[ "${action}" == stop ]]; then
        [[ "${mode}" != running ]] || docker stop -t 30 "${ids}" >/dev/null ||
            return "${PADM_DOCKER_RC_COMPOSE}"
        audited=$(dockerWireGuardContainer exited) && [[ "${audited}" == "${ids}" ]] ||
            return "${PADM_DOCKER_RC_STATE}"
        return 0
    fi
    [[ "${mode}" != running ]] || return 0
    timeout=${PADM_DOCKER_HEALTH_TIMEOUT:-60}
    [[ "${timeout}" =~ ^[1-9][0-9]{0,3}$ && "${timeout}" -le 3600 ]] ||
        return "${PADM_DOCKER_RC_STATE}"
    # 只撤销本次尝试启动且仍通过归属审计的精确容器，资源清理由入口完成。
    trap '
        status=$?
        trap - EXIT INT TERM
        if [[ "${status}" != 0 && "${attempted}" == 1 ]]; then
            if audited=$(dockerWireGuardContainer running 0) && [[ "${audited}" == "${ids}" ]]; then
                if docker stop -t 30 "${ids}" >/dev/null; then
                    audited=$(dockerWireGuardContainer exited) && [[ "${audited}" == "${ids}" ]] ||
                        dockerError "WireGuard 启动失败后仍有接口或状态，保留容器和恢复现场"
                else
                    dockerError "WireGuard 启动失败且停止失败，保留容器和恢复现场"
                fi
            else
                dockerError "WireGuard 启动失败，容器已退出或归属变化，保留现场"
            fi
        fi
        exit "${status}"
    ' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    attempted=1
    docker start "${ids}" >/dev/null || return "${PADM_DOCKER_RC_COMPOSE}"
    deadline=$((SECONDS + timeout))
    while :; do
        if audited=$(dockerWireGuardContainer running 2>/dev/null) && [[ "${audited}" == "${ids}" ]]; then
            attempted=0
            return 0
        fi
        [[ "${SECONDS}" -lt "${deadline}" ]] || break
        sleep 1
    done
    dockerError 'WireGuard 启动后未通过健康和归属审计'
    return "${PADM_DOCKER_RC_COMPOSE}"
)
