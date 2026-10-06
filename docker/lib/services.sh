#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/traffic.sh" || return 1
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/renewal.sh" || return 1

if [[ "${PADM_DOCKER_SERVICES_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_SERVICES_LOADED=1

readonly PADM_DOCKER_CONTAINER_UID=10001
readonly PADM_DOCKER_CONTAINER_GID=10001
readonly PADM_DOCKER_SUBSCRIPTION_PORT=8081

DOCKER_CONFIG_CANDIDATE=
DOCKER_CONFIG_BACKUP=
DOCKER_CONFIG_SWITCHED=0
DOCKER_TLS_CANDIDATE=
DOCKER_TLS_BACKUP=
DOCKER_TLS_SWITCHED=0

dockerConfigureSchemaFile() {
    printf '%s\n' "${DOCKER_BUNDLE_SOURCE_ROOT}/docker/contracts/configure.schema.json"
}

dockerFeatureMatrixFile() {
    printf '%s\n' "${DOCKER_BUNDLE_SOURCE_ROOT}/docker/contracts/features.json"
}

dockerConfigureSpecValidate() {
    local specFile=$1 schemaFile matrixFile
    schemaFile=$(dockerConfigureSchemaFile) || return 1
    matrixFile=$(dockerFeatureMatrixFile) || return 1
    [[ -f "${specFile}" && ! -L "${specFile}" && -s "${specFile}" ]] || {
        dockerError "配置规格不是安全的普通文件: ${specFile}"
        return 1
    }
    jq empty "${schemaFile}" "${matrixFile}" "${specFile}" >/dev/null 2>&1 || {
        dockerError '配置规格或阶段 4 契约不是有效 JSON'
        return 1
    }
    jq -es 'length == 1 and (.[0] | type == "object")' "${specFile}" >/dev/null 2>&1 || {
        dockerError '配置规格必须是单个 JSON 对象'
        return 1
    }
    jq -e --slurpfile matrix "${matrixFile}" '
      def exact($keys): type == "object" and ((keys_unsorted | sort) == ($keys | sort));
      def port: type == "number" and floor == . and . >= 1 and . <= 65535;
      def hostname: type == "string" and test("^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z]{2,63}$");
      def ipv4: type == "string" and (split(".") as $parts |
        ($parts | length) == 4 and all($parts[]; test("^[0-9]{1,3}$") and (tonumber <= 255)));
      def ipv6: type == "string" and contains(":") and test("^[A-Fa-f0-9:]+$");
      def server: hostname or ipv4 or ipv6;
      def uuid: type == "string" and length == 36 and test("^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$");
      def name: type == "string" and test("^[A-Za-z0-9._~@+=:-]{1,64}$");
      def families: type == "array" and length >= 1 and length <= 2 and
        (unique | length) == length and all(.[]; . == "ipv4" or . == "ipv6");
      def image: type == "string" and test("^[a-z0-9][a-z0-9._/:@-]*:[A-Za-z0-9._-]+@sha256:[a-f0-9]{64}$");
      def safe_names($max): type == "array" and length <= $max and
        (unique | length) == length and all(.[]; type == "string" and test("^[A-Za-z0-9._:/-]{1,128}$"));
      def protocol_base: (.server | server) and (.public_port | port) and
        (.address_families | families) and (.name | name) and (.uuid | uuid);
      def listener_id: type == "string" and test("^entry-[a-z0-9][a-z0-9-]{0,47}$");
      def ss_key: type == "string" and length == 24 and test("^[A-Za-z0-9+/]{21}[AQgw]==$");
      def bandwidth: type == "number" and floor == . and . >= 1 and . <= 1000000;
      def duration: type == "string" and test("^[1-9][0-9]{0,5}(ms|s|m|h)$") and
        (explode | all(. > 32 and . != 127));
      def masquerade: type == "string" and length <= 2048 and
        (. == "" or (test("^https://(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z]{2,63}(?:/[A-Za-z0-9._~/-]*)?$") and
          (ltrimstr("https://") | split("/")[0] | hostname))) and
        (explode | all(. > 32 and . != 127));
      . as $request |
      ($matrix[0]) as $features |
      ([.. | strings] | all(.[]; explode | all(. >= 32 and . != 127))) and
      exact(["schema_version", "release", "core", "tls", "subscription", "images", "host_integrations"]) and
      (.schema_version == 1 or .schema_version == 2 or .schema_version == 3) and
      (.release | exact(["version", "manifest_sha256", "signature_identity"]) and
        (.version | type == "string" and length > 0) and
        (.manifest_sha256 | test("^[a-f0-9]{64}$")) and
        (.signature_identity | type == "string" and length > 0)) and
      (.core | exact(["type", "protocols"] +
          if $request.schema_version == 3 then ["secondary_type"] else [] end) and
        (.type == "xray" or .type == "sing-box") and
        (.protocols | type == "array" and length >= 1 and
          (if $request.schema_version == 1 then length <= 2 and
            ([.[].id] | unique | length) == length
           else length <= 16 and ([.[].listener_id] | unique | length) == length end) and
          ([.[].public_port] | unique | length) == length)) and
      (if .schema_version == 3 then
        (.core.secondary_type == null or
          (.core.secondary_type != .core.type and
            (.core.secondary_type == "xray" or .core.secondary_type == "sing-box"))) and
        any(.core.protocols[]; .core == $request.core.type) and
        (if .core.secondary_type != null then
          any(.core.protocols[]; .core == $request.core.secondary_type) and .host_integrations == []
         else true end) and
        all(.core.protocols[]; .core == $request.core.type or
          ($request.core.secondary_type != null and .core == $request.core.secondary_type))
       else true end) and
      all(.core.protocols[];
        protocol_base and
        (if $request.schema_version >= 2 then
          (.listener_id | listener_id) or
          (.id == 1 and .listener_id == "vless-reality") or
          (.id == 21 and .listener_id == "vless-ws")
         else true end) and
        if .id == 1 or .id == 2 or .id == 26 then
          exact(["id", "server", "public_port", "address_families", "name", "uuid", "reality"] +
            if $request.schema_version >= 2 then ["listener_id"] else [] end +
            if $request.schema_version == 3 then ["core"] else [] end +
            if .id == 2 then ["xhttp"] elif .id == 26 then ["grpc"] else [] end) and
          (if .id == 1 then true else $request.schema_version == 3 end) and
          (.reality | exact(["server_name", "target_host", "target_port", "private_key", "public_key", "short_id"]) and
            (.server_name | hostname) and (.target_host | hostname) and (.target_port | port) and
            (.private_key | test("^[A-Za-z0-9_-]{43}$")) and
            (.public_key | test("^[A-Za-z0-9_-]{43}$")) and
            (.short_id | test("^(?:[a-f0-9]{2}){1,8}$"))) and
          (if .id == 2 then
             .core == "xray" and
             (.xhttp | exact(["path", "host", "mode"]) and
               (.path | type == "string" and test("^/[A-Za-z0-9._~/-]{1,128}$") and
                 (explode | all(. > 32 and . != 127))) and
               (.host | hostname and (explode | all(. > 32 and . != 127))) and
               (.mode == "auto" or .mode == "packet-up" or .mode == "stream-up"))
           elif .id == 26 then
             (.grpc | exact(["service_name"]) and
               (.service_name | type == "string" and test("^[A-Za-z0-9._-]{1,64}$") and
                 (explode | all(. > 32 and . != 127))))
           else true end)
        elif .id == 28 then
          $request.schema_version == 3 and
          (.core == "xray" or .core == "sing-box") and
          exact(["id", "core", "listener_id", "server", "public_port", "address_families", "name", "uuid", "trojan"]) and
          (.trojan | exact(["domain"]) and
            (.domain | hostname and (explode | all(. > 32 and . != 127))))
        elif .id == 3 then
          $request.schema_version == 3 and .core == "sing-box" and
          exact(["id", "core", "listener_id", "server", "public_port", "address_families", "name", "uuid", "hy2"]) and
          (.hy2 | exact(["domain", "bandwidth_mode", "up_mbps", "down_mbps", "obfs", "masquerade"]) and
            (.domain | hostname and (explode | all(. > 32 and . != 127))) and
            (.bandwidth_mode == "bbr" or .bandwidth_mode == "brutal") and
            (.up_mbps | bandwidth) and (.down_mbps | bandwidth) and
            (.obfs == null or (.obfs | exact(["type", "password"]) and .type == "salamander" and
              (.password | type == "string" and test("^[A-Za-z0-9_-]{16,128}$") and
                (explode | all(. > 32 and . != 127))))) and
            (.masquerade | masquerade))
        elif .id == 4 then
          $request.schema_version == 3 and .core == "sing-box" and
          exact(["id", "core", "listener_id", "server", "public_port", "address_families", "name", "uuid", "anytls"]) and
          (.anytls | exact(["domain"]) and
            (.domain | hostname and (explode | all(. > 32 and . != 127))))
        elif .id == 5 then
          $request.schema_version == 3 and .core == "sing-box" and
          exact(["id", "core", "listener_id", "server", "public_port", "address_families", "name", "uuid", "naive"]) and
          (.naive | exact(["domain"]) and
            (.domain | hostname and (explode | all(. > 32 and . != 127)))) and
          .server == .naive.domain
        elif .id == 30 then
          $request.schema_version == 3 and .core == "sing-box" and
          exact(["id", "core", "listener_id", "server", "public_port", "address_families", "name", "uuid", "shadowsocks"]) and
          (.shadowsocks | exact(["method", "server_password", "user_password"]) and
            .method == "2022-blake3-aes-128-gcm" and
            (.server_password | ss_key) and (.user_password | ss_key))
        elif .id == 31 then
          $request.schema_version == 3 and .core == "sing-box" and
          exact(["id", "core", "listener_id", "server", "public_port", "address_families", "name", "uuid", "tuic"]) and
          (.tuic | exact(["domain", "congestion_control", "auth_timeout", "heartbeat", "zero_rtt_handshake"]) and
            (.domain | hostname and (explode | all(. > 32 and . != 127))) and
            (.congestion_control == "cubic" or .congestion_control == "new_reno" or .congestion_control == "bbr") and
            (.auth_timeout | duration) and (.heartbeat | duration) and
            (.zero_rtt_handshake | type == "boolean"))
        elif .id == 21 or .id == 22 then
          (if .id == 22 then $request.schema_version == 3 and .core == "xray" else true end) and
          exact(["id", "server", "public_port", "address_families", "name", "uuid", "websocket"] +
            if $request.schema_version >= 2 then ["listener_id"] else [] end +
            if $request.schema_version == 3 then ["core"] else [] end) and
          (.websocket | exact(["domain", "path"] +
            if $request.schema_version >= 2 then ["backend_port", "tls_port"] else [] end) and
            (if $request.schema_version >= 2 then
              (.backend_port | port) and (.tls_port | port) and .tls_port != 8080
             else true end) and (.domain | hostname) and
            (.path | test("^[A-Za-z0-9_-]{8,64}$")))
        else false end) and
      all(.core.protocols[];
        . as $protocol |
        any($features.protocols[];
          .id == $protocol.id and .status == "supported" and
          (.cores | index($protocol.core // $request.core.type)) != null)) and
      (.tls == null or (.tls | exact(["domain"]) and (.domain | hostname))) and
      (.subscription | exact(["enabled", "token"]) and (.enabled | type == "boolean") and
        (.token | test("^[A-Za-z0-9_-]{16,128}$"))) and
      (.images | exact(["xray", "sing-box", "nginx", "ops", "net"]) and
        all(.[]; image)) and
      (.host_integrations | type == "array" and length <= 3 and
        ([.[].type] | unique | length) == length and
        ([.[] | select(.type == "tun" or .type == "tproxy")] | length) <= 1) and
      all(.host_integrations[];
        exact(["type", "profile", "firewall_rules", "devices", "schedules", "settings"]) and
        (.firewall_rules | safe_names(16)) and (.devices | safe_names(4)) and
        (.schedules | safe_names(4)) and
        if .type == "wireguard" then
          .profile == "net-wireguard" and .firewall_rules == [] and
          .devices == ["wg-padm"] and .schedules == [] and
          (.settings | exact(["config_file", "interface"]) and
            .config_file == "wg-padm.conf" and .interface == "wg-padm")
        elif .type == "fail2ban" then
          .profile == "net-fail2ban" and .firewall_rules == ["DOCKER-USER"] and
          .devices == [] and .schedules == [] and
          (.settings | exact(["log_file", "ports", "max_retry", "find_time", "ban_time"]) and
            .log_file == "access.log" and
            (.ports | type == "array" and length >= 1 and length <= 16 and
              (unique | length) == length and all(.[]; port)) and
            (.max_retry | type == "number" and floor == . and . >= 1 and . <= 20) and
            (.find_time | type == "number" and floor == . and . >= 60 and . <= 86400) and
            (.ban_time | type == "number" and floor == . and . >= 60 and . <= 604800))
        elif .type == "tun" then
          .profile == "net-transparent" and
          .firewall_rules == ["sing-box-auto-redirect"] and
          .devices == ["/dev/net/tun"] and .schedules == [] and
          (.settings | exact(["interface", "address"]) and
            .interface == "padm-tun" and .address == "198.18.0.1/30")
        elif .type == "tproxy" then
          .profile == "net-transparent" and .firewall_rules == ["padm-tproxy"] and
          .devices == [] and .schedules == [] and
          (.settings | exact(["port", "mark"]) and (.port | port) and
            (.mark | type == "number" and floor == . and . >= 1 and . <= 2147483647))
        else false end) and
      if any(.core.protocols[]; .id == 3 or .id == 4 or .id == 5 or .id == 21 or .id == 22 or .id == 28 or .id == 31) then
        .tls != null and
        all(.core.protocols[] | select(.id == 21 or .id == 22); (.core // $request.core.type) == "xray") and
        all(.core.protocols[] | select(.id == 21 or .id == 22); .websocket.domain == $request.tls.domain) and
        all(.core.protocols[] | select(.id == 3); .hy2.domain == $request.tls.domain) and
        all(.core.protocols[] | select(.id == 4); .anytls.domain == $request.tls.domain) and
        all(.core.protocols[] | select(.id == 5); .naive.domain == $request.tls.domain) and
        all(.core.protocols[] | select(.id == 28); .trojan.domain == $request.tls.domain) and
        all(.core.protocols[] | select(.id == 31); .tuic.domain == $request.tls.domain)
      else
        .tls == null and .subscription.enabled == false
      end and
      if .subscription.enabled then any(.core.protocols[]; .id == 21) else true end and
      if any(.core.protocols[]; .id == 3 or .id == 4 or .id == 5 or .id == 22 or .id == 28 or .id == 30 or .id == 31) then .host_integrations == [] else true end and
      if any(.host_integrations[]; .type == "fail2ban") then
        any(.core.protocols[]; .id == 21) and
        all(.host_integrations[] | select(.type == "fail2ban") | .settings.ports[];
          . as $port | any($request.core.protocols[]; .id == 21 and .public_port == $port))
      else true end and
      if any(.host_integrations[]; .type == "tun") then .core.type == "sing-box" else true end and
      if any(.host_integrations[]; .type == "tun" or .type == "tproxy") then
        all(.core.protocols[]; .id != 21 and .id != 22)
      else true end and
      all(.host_integrations[] | select(.type == "tproxy");
        .settings.port as $port | all($request.core.protocols[]; .public_port != $port)) and
      # 内部监听按实际核心网络空间检查，公开端口仍在宿主全局唯一。
      (all([.core.type, .core.secondary_type] | map(select(. != null))[];
        . as $core |
        ([$request.core.protocols[] | select((.core // $request.core.type) == $core) |
            if .id == 21 or .id == 22 then (.websocket.backend_port // 31297) else .public_port end] +
          [$request.host_integrations[] | select(.type == "tproxy") | .settings.port] +
          [if $core == "xray" then 10085 else 10087 end]) as $corePorts |
        ($corePorts | unique | length) == ($corePorts | length)) and
      (([.core.protocols[] | select(.id == 21 or .id == 22) | (.websocket.tls_port // 8443)] + [8080]) as $tlsPorts |
      ($tlsPorts | unique | length) == ($tlsPorts | length)))
    ' "${specFile}" >/dev/null 2>&1 || {
        dockerError '配置规格不满足阶段 4 schema、支持矩阵或拓扑约束'
        return 1
    }
}

dockerConfigureSpecMigrate() {
    local source=$1 target=$2
    dockerConfigureSpecValidate "${source}" || return 1
    jq '
      (if .schema_version == 1 then
        .schema_version = 2 |
        .core.protocols |= map(
          .listener_id = (if .id == 1 then "vless-reality" else "vless-ws" end) |
          if .id == 21 then .websocket += {backend_port: 31297, tls_port: 8443} else . end)
       else . end) |
      if .schema_version == 2 then
        .schema_version = 3 | .core.type as $core |
        .core.secondary_type = null | .core.protocols |= map(.core = $core)
      else . end
    ' "${source}" >"${target}" &&
        chmod 0600 "${target}" && dockerConfigureSpecValidate "${target}"
}

dockerConfigureReleasePrepare() {
    dockerManifestPrepare "${1:-}" "${2:-}" "${3:-}" || return "${PADM_DOCKER_RC_MANIFEST}"
    dockerStageReleaseBundle >&2 || return "${PADM_DOCKER_RC_BUNDLE}"
    dockerPullManifestImages >&2 || return "${PADM_DOCKER_RC_COMPOSE}"
}

dockerConfigureReleaseValidate() {
    local specFile=$1 inputs
    inputs=$(dockerManifestConfigurationInputs) || {
        dockerError '可信发布输入缺失或已变更，拒绝配置'
        return 1
    }
    jq -e --argjson trusted "${inputs}" '
      .release == $trusted.release and .images == $trusted.images
    ' "${specFile}" >/dev/null 2>&1 || {
        dockerError '配置中的版本、签名摘要或镜像与已验证发布清单不一致'
        return 1
    }
    dockerBundleSupportsSpec "${DOCKER_STAGED_BUNDLE_PATH}" "${specFile}" || return 1
    dockerBundleSupportsSpec "$(dockerCurrentBundlePath)" "${specFile}"
}

dockerManagedSpecMatchesDeployment() {
    local specFile=$1 deployment=$2 imagesEnv=$3 key value expected count name
    dockerConfigureSpecValidate "${specFile}" || return 1
    [[ -f "${deployment}" && ! -L "${deployment}" &&
        -f "${imagesEnv}" && ! -L "${imagesEnv}" ]] || return 1
    jq -e --slurpfile deployment "${deployment}" '
      $deployment[0] as $d |
      .release.version == $d.padm_version and
      .release.manifest_sha256 == $d.manifest.sha256 and
      .release.signature_identity == $d.manifest.signature_identity and
      .core.type == $d.core.type and
      (if .schema_version == 3 then
        ($d.core | has("secondary_type")) and .core.secondary_type == $d.core.secondary_type
       else ($d.core | has("secondary_type") | not) end) and
      (([.core.type, .core.secondary_type] | map(select(. != null) | "core-\(.)")) +
        [if any(.core.protocols[]; .id == 21 or .id == 22) then "nginx" else empty end] +
        [if .subscription.enabled then "subscription" else empty end] +
        [.host_integrations[].profile] | sort) == ($d.compose.profiles | sort) and
      (.host_integrations | sort_by(.type)) == ($d.host_integrations | sort_by(.type)) and
      ([.core.protocols[].id] | unique) == ($d.core.protocol_ids | sort) and
      (if .schema_version >= 2 then
        [.core.protocols[] |
          (if .id == 30 then "tcp", "udp" elif .id == 3 or .id == 31 then "udp" else "tcp" end) as $transport |
          {listener_id, service: (if .id == 21 or .id == 22 then "nginx" else (.core // $d.core.type) end),
          public_port, container_port: (if .id == 21 or .id == 22 then .websocket.tls_port else .public_port end),
          transport: $transport, address_families}] | sort_by(.listener_id, .transport) as $expected |
        $expected == ([$d.listeners[] | select(.listener_id | startswith("host-") | not)] | sort_by(.listener_id, .transport))
       else true end) and
      all(.images | to_entries[];
        (.value | split("@") | last) == $d.images[.key].index_digest)
    ' "${specFile}" >/dev/null 2>&1 || return 1
    while IFS='|' read -r key name; do
        count=$(grep -c "^${key}=" "${imagesEnv}" 2>/dev/null || true)
        [[ "${count}" == 1 ]] || return 1
        value=$(sed -n "s/^${key}=//p" "${imagesEnv}") || return 1
        expected=$(jq -er --arg name "${name}" '.images[$name]' "${specFile}") || return 1
        [[ "${value}" == "${expected}" ]] || return 1
    done <<'EOF'
PADM_XRAY_IMAGE|xray
PADM_SINGBOX_IMAGE|sing-box
PADM_NGINX_IMAGE|nginx
PADM_OPS_IMAGE|ops
PADM_NET_IMAGE|net
EOF
}

dockerEditBaselineValidate() {
    local specFile=$1 workspace=$2 root baseline core directory state token
    root=$(dockerInstallRoot) || return 1
    for token in config data/subscription data/xray data/sing-box data/static data/acme data/net \
        secrets/tls secrets/net/wireguard logs/nginx logs/subscription logs/acme \
        compose.json deployment.json images.env; do
        dockerTrafficSafePath "${root}" "${root}/${token}" || return 1
        if [[ -e "${root}/${token}" ]]; then
            [[ -z "$(find "${root}/${token}" ! -type f ! -type d -print -quit)" ]] || return 1
        fi
    done
    dockerManagedSpecMatchesDeployment "${specFile}" "${root}/deployment.json" "${root}/images.env" || {
        dockerError '完整原始规格与部署记录不一致，不能接入编辑'
        return 1
    }
    baseline="${workspace}/baseline"
    mkdir -p -- "${baseline}/config/"{xray,sing-box,nginx,net/fail2ban,net/transparent} \
        "${baseline}/data/subscription" "${baseline}/logs/nginx" || return 1
    state=$(dockerTrafficReadState) || return 1
    while IFS= read -r core; do
        case "${core}" in
        xray) dockerGenerateXrayConfig "${specFile}" "${baseline}/config/xray/config.json" || return 1 ;;
        sing-box) dockerGenerateSingBoxConfig "${specFile}" "${baseline}/config/sing-box/config.json" || return 1 ;;
        *) return 1 ;;
        esac
        if [[ -e "${root}/config/${core}/users.base" ]]; then
            cp -- "${baseline}/config/${core}/config.json" "${baseline}/config/${core}/users.base" || return 1
            dockerTrafficRender "${core}" "${baseline}/config/${core}/users.base" "${state}" \
                >"${baseline}/config/${core}/config.json" || return 1
        elif [[ -e "${root}/data/traffic/state.json" ]]; then
            dockerError '旧部署有流量记录但缺少完整账号输入，不能无损接入编辑'
            return 1
        fi
    done < <(jq -r '[.core.type, .core.secondary_type] | .[] | select(. != null)' "${specFile}")
    dockerGenerateNginxConfig "${specFile}" "${baseline}/config/nginx/default.conf" &&
        dockerGenerateFail2banConfig "${specFile}" "${baseline}" || return 1
    if jq -e '.subscription.enabled' "${specFile}" >/dev/null; then
        token=$(jq -r '.subscription.token' "${specFile}") || return 1
        dockerGenerateSubscription "${specFile}" "${baseline}/data/subscription/${token}" || return 1
    fi
    # 整目录替换前核对所有受影响的输入，不把额外账号、路由或手写配置默默丢弃。
    for directory in config/xray config/sing-box config/nginx config/net data/subscription; do
        dockerTrafficSafePath "${root}" "${root}/${directory}" &&
            [[ -d "${root}/${directory}" &&
                -z "$(find "${root}/${directory}" ! -type f ! -type d -print -quit)" ]] || return 1
        if [[ -f "${baseline}/${directory}/config.json" ]]; then
            while IFS= read -r token; do
                [[ "${token}" == "${root}/${directory}/config.json" ||
                    "${token}" == "${root}/${directory}/users.base" ]] || {
                    dockerError '核心含未纳入完整规格的文件，不能无损接入编辑'
                    return 1
                }
            done < <(find "${root}/${directory}" -mindepth 1 -print)
            for token in config.json users.base; do
                [[ -e "${baseline}/${directory}/${token}" ]] || continue
                [[ -f "${root}/${directory}/${token}" ]] &&
                    jq -e -n --slurpfile expected "${baseline}/${directory}/${token}" \
                        --slurpfile actual "${root}/${directory}/${token}" \
                        '$expected == $actual' >/dev/null 2>&1 || {
                    dockerError '核心账号或参数与完整规格不一致，不能无损接入编辑'
                    return 1
                }
            done
        else
            diff -qr -- "${baseline}/${directory}" "${root}/${directory}" >/dev/null 2>&1 || {
                dockerError '存在完整规格之外的站点、订阅或宿主配置，不能无损接入编辑'
                return 1
            }
        fi
    done
    dockerGenerateCompose "${specFile}" "${baseline}/compose.json" &&
        dockerGenerateDeployment "${specFile}" "${baseline}/deployment.json" || return 1
    : >"${baseline}/images.env"
    dockerGenerateImagesEnv "${specFile}" "${baseline}/images.env" "${root}" || return 1
    LC_ALL=C sort "${root}/images.env" >"${baseline}/images.actual.env" &&
        LC_ALL=C sort "${baseline}/images.env" >"${baseline}/images.expected.env" &&
        cmp -s -- "${baseline}/images.expected.env" "${baseline}/images.actual.env" || {
        dockerError '镜像环境文件或挂载根路径与部署不一致，已拒绝编辑'
        return 1
    }
    jq -en --slurpfile expected "${baseline}/compose.json" --slurpfile actual "${root}/compose.json" '
      def comparable: .services |= with_entries(.value.labels |= del(."io.padm.release"));
      ($actual | length) == 1 and ($expected[0] | comparable) == ($actual[0] | comparable)
    ' >/dev/null 2>&1 &&
        jq -en --slurpfile expected "${baseline}/deployment.json" \
            --slurpfile actual "${root}/deployment.json" '
          def input: {core: (.core | .protocol_ids |= sort),
            listeners: (.listeners | sort_by(.service, .public_port, .transport)),
            profiles: (.compose.profiles | sort), host_integrations, formats};
          ($actual | length) == 1 and ($expected[0] | input) == ($actual[0] | input)
        ' >/dev/null 2>&1 || {
        dockerError '监听器、编排或宿主集成不能从完整规格无损重建，已拒绝编辑'
        return 1
    }
}

dockerRealityTlsPingState() {
    local output=$1
    printf '%s\n' "${output}" | awk '
      /Pinging with SNI/ {inSni = 1; next}
      inSni && /Handshake succeeded/ {success = 1}
      inSni && /Handshake failure/ {rejected = 1}
      END {
        if (success) print "success"
        else if (rejected) print "rejected"
        else print "unknown"
      }
    '
}

dockerRealityTlsPingHasTls13() {
    local output=$1
    printf '%s\n' "${output}" | awk '
      /Pinging with SNI/ {inSni = 1; next}
      inSni && /TLS Version:[[:space:]]*TLS 1\.3/ {found = 1}
      END {exit found ? 0 : 1}
    '
}

dockerRealityTargetNetworkRecords() {
    local opsImage=$1 host=$2
    docker run --rm --entrypoint python3 "${opsImage}" -c '
import json
import socket
import sys
import urllib.parse
import urllib.request

host = sys.argv[1]
addresses = []
missing_codes = {socket.EAI_NONAME}
if hasattr(socket, "EAI_NODATA"):
    missing_codes.add(socket.EAI_NODATA)
for family in (socket.AF_INET, socket.AF_INET6):
    try:
        records = socket.getaddrinfo(host, None, family, socket.SOCK_STREAM)
    except socket.gaierror as error:
        if error.errno not in missing_codes:
            raise
        continue
    for record in records:
        ip = record[4][0]
        if ip not in addresses:
            addresses.append(ip)
if not addresses:
    raise SystemExit(2)

for ip in addresses:
    asn = org = ""
    encoded = urllib.parse.quote(ip, safe="")
    request = urllib.request.Request(
        "https://api.bgpview.io/ip/" + encoded,
        headers={"User-Agent": "padm-reality-check/1"},
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            prefixes = json.load(response).get("data", {}).get("prefixes") or []
        if prefixes:
            data = prefixes[0].get("asn") or {}
            if data.get("asn"):
                asn = "AS" + str(data["asn"])
                org = str(data.get("name") or "")
    except Exception:
        pass
    if not asn:
        request = urllib.request.Request(
            "https://ipinfo.io/" + encoded + "/org",
            headers={"User-Agent": "padm-reality-check/1"},
        )
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                value = response.read(4096).decode("utf-8", "replace").strip()
            fields = value.split(maxsplit=1)
            if fields and fields[0].startswith("AS") and fields[0][2:].isdigit():
                asn = fields[0]
                org = fields[1] if len(fields) > 1 else ""
        except Exception:
            pass
    print(ip, asn or "unknown", org or "unknown", sep="\t")
' "${host}"
}

dockerRealityTargetTlsPing() {
    local xrayImage=$1 ip=$2 sni=$3 port=$4
    local timeoutSeconds=${PADM_DOCKER_REALITY_TLS_TIMEOUT:-20}
    [[ "${timeoutSeconds}" =~ ^[0-9]+$ && "${timeoutSeconds}" -gt 0 ]] || timeoutSeconds=20
    timeout -k 2 "${timeoutSeconds}" docker run --rm "${xrayImage}" tls ping -ip "${ip}" "${sni}:${port}" 2>&1 || true
}

dockerRealityTargetsValidate() {
    local specFile=$1 xrayImage opsImage host port sni records ip asn _org
    local targetResult targetState cfResult cfState incomplete=false
    jq -e 'any(.core.protocols[]; .id == 1 or .id == 2 or .id == 26)' "${specFile}" >/dev/null || return 0
    command -v timeout >/dev/null 2>&1 || {
        dockerError '缺少 timeout，无法限制 REALITY 目标站探测时长'
        return 1
    }
    xrayImage=$(jq -r '.images.xray' "${specFile}") || return 1
    opsImage=$(jq -r '.images.ops' "${specFile}") || return 1
    while IFS=$'\t' read -r host port sni; do
        incomplete=false
        case "${host,,}" in
        java.com | *.java.com | riotcdn.net | *.riotcdn.net)
            dockerError "REALITY 目标命中已知 CDN 中继风险域名: ${host}"
            return 1
            ;;
        esac
        records=$(dockerRealityTargetNetworkRecords "${opsImage}" "${host}" 2>/dev/null) || {
            dockerError "REALITY 目标地址解析失败: ${host}"
            return 1
        }
        [[ -n "${records}" ]] || {
            dockerError "REALITY 目标没有 A/AAAA 记录: ${host}"
            return 1
        }
        while IFS=$'\t' read -r ip asn _org; do
            [[ -n "${ip}" ]] || continue
            if [[ "${asn}" == "AS13335" ]]; then
                dockerError "REALITY 目标命中 Cloudflare AS13335: ${host} -> ${ip}"
                return 1
            fi
            [[ "${asn}" != "unknown" ]] || incomplete=true
            targetResult=$(dockerRealityTargetTlsPing "${xrayImage}" "${ip}" "${sni}" "${port}")
            targetState=$(dockerRealityTlsPingState "${targetResult}")
            if [[ "${targetState}" != "success" ]] || ! dockerRealityTlsPingHasTls13 "${targetResult}"; then
                incomplete=true
                continue
            fi
            cfResult=$(dockerRealityTargetTlsPing "${xrayImage}" "${ip}" cloudflare.com "${port}")
            cfState=$(dockerRealityTlsPingState "${cfResult}")
            case "${cfState}" in
            success)
                dockerError "REALITY 目标可响应 cloudflare.com SNI，存在中继风险: ${host} -> ${ip}"
                return 1
                ;;
            rejected) ;;
            *) incomplete=true ;;
            esac
        done <<<"${records}"
        if [[ "${incomplete}" == "true" ]]; then
            dockerError "REALITY 目标风险检测不完整，已拒绝部署: ${host}:${port}"
            return 1
        fi
    done < <(jq -r '[.core.protocols[] | select(.id == 1 or .id == 2 or .id == 26) |
      [.reality.target_host, (.reality.target_port | tostring), .reality.server_name]] | unique[] | @tsv' "${specFile}")
}

dockerCurrentOwnsPort() {
    local root port transport=${2:-tcp}
    root=$(dockerInstallRoot) || return 1
    port=$1
    [[ -f "${root}/deployment.json" && ! -L "${root}/deployment.json" ]] || return 1
    jq -e --argjson port "${port}" --arg transport "${transport}" \
        'any(.listeners[]?; .public_port == $port and .transport == $transport)' \
        "${root}/deployment.json" >/dev/null 2>&1
}

dockerTcpPortIsListening() {
    local port=$1 hexPort
    hexPort=$(printf '%04X' "${port}") || return 1
    awk -v port=":${hexPort}" '
      $2 ~ port "$" && $4 == "0A" { found = 1 }
      END { exit(found ? 0 : 1) }
    ' /proc/net/tcp /proc/net/tcp6 2>/dev/null
}

dockerConfigurePortsAvailable() {
    local specFile=$1 port transport projects wireguardPort key
    local -A desiredPorts=()
    while IFS='|' read -r port transport; do
        key="${port}|${transport}"
        if [[ -n "${desiredPorts[${key}]+x}" ]]; then
            dockerError "配置内重复使用 ${transport^^} 端口: ${port}"
            return 1
        fi
        desiredPorts[${key}]=1
        dockerCurrentOwnsPort "${port}" "${transport}" && continue
        if { [[ "${transport}" == "tcp" ]] && dockerTcpPortIsListening "${port}"; } ||
            { [[ "${transport}" == "udp" ]] && dockerUdpPortIsListening "${port}"; }; then
            dockerError "宿主 ${transport^^} 端口已被占用: ${port}"
            return 1
        fi
        projects=$(docker ps --filter "publish=${port}/${transport}" \
            --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null) || return 1
        if [[ -n "${projects//[[:space:]]/}" ]]; then
            dockerError "Docker 已发布宿主端口: ${port}"
            return 1
        fi
    done < <(
        jq -r '
          ([.core.protocols[] |
              (if .id == 30 then "tcp", "udp" elif .id == 3 or .id == 31 then "udp" else "tcp" end) as $transport |
              "\(.public_port)|\($transport)"] +
          [.host_integrations[] | select(.type == "tproxy") |
            "\(.settings.port)|tcp", "\(.settings.port)|udp"]) | unique[]
        ' "${specFile}"
        if jq -e 'any(.host_integrations[]; .type == "wireguard")' "${specFile}" >/dev/null; then
            wireguardPort=$(dockerWireGuardListenPort) || exit 1
            printf '%s|udp\n' "${wireguardPort}"
        fi
    )
}

dockerUdpPortIsListening() {
    local port=$1 hexPort
    hexPort=$(printf '%04X' "${port}") || return 1
    awk -v port=":${hexPort}" '
      $2 ~ port "$" && $4 == "07" { found = 1 }
      END { exit(found ? 0 : 1) }
    ' /proc/net/udp /proc/net/udp6 2>/dev/null
}

dockerCreateConfigurationCandidate() {
    local root candidate directory
    root=$(dockerInstallRoot) || return 1
    candidate=$(mktemp -d "${root}/.candidate.XXXXXX") || return 1
    dockerManagedPathIsSafe "${root}" "${candidate}" || return 1
    for directory in \
        config/xray config/sing-box config/nginx config/net/fail2ban config/net/transparent \
        data/xray data/sing-box data/static data/subscription data/acme \
        data/net/wireguard data/net/fail2ban data/net/transparent \
        secrets/tls secrets/net/wireguard logs/nginx logs/subscription logs/acme; do
        mkdir -p -- "${candidate}/${directory}" || {
            dockerRemoveManagedTree "${root}" "${candidate}" || true
            return 1
        }
    done
    chmod 0750 "${candidate}" || return 1
    DOCKER_CONFIG_BACKUP=
    DOCKER_CONFIG_SWITCHED=0
    DOCKER_CONFIG_CANDIDATE=${candidate}
}

dockerWireGuardConfigFile() {
    local root
    root=$(dockerInstallRoot) || return 1
    printf '%s\n' "${root}/secrets/net/wireguard/wg-padm.conf"
}

dockerWireGuardListenPort() {
    local configFile port
    configFile=$(dockerWireGuardConfigFile) || return 1
    port=$(awk -F= '
      /^[[:space:]]*ListenPort[[:space:]]*=/ {
        value=$2; gsub(/[[:space:]]/, "", value); print value
      }
    ' "${configFile}") || return 1
    [[ "${port}" =~ ^[0-9]+$ && "${port}" -ge 1 && "${port}" -le 65535 ]] || return 1
    [[ "$(grep -Ec '^[[:space:]]*ListenPort[[:space:]]*=' "${configFile}")" == "1" ]] || return 1
    printf '%s\n' "${port}"
}

dockerHostIntegrationInputsValidate() {
    local specFile=$1 configFile
    jq -e 'any(.host_integrations[]; .type == "wireguard")' "${specFile}" >/dev/null || return 0
    configFile=$(dockerWireGuardConfigFile) || return 1
    [[ -f "${configFile}" && ! -L "${configFile}" && -O "${configFile}" ]] &&
        dockerPrivateFileIsRestricted "${configFile}" || {
        dockerError "WireGuard 配置必须是 root 持有且组/其他用户无权限的普通文件: ${configFile}"
        return 1
    }
    if grep -Eiq '^[[:space:]]*(PreUp|PostUp|PreDown|PostDown|SaveConfig|DNS)[[:space:]]*=' "${configFile}" ||
        [[ "$(grep -Ec '^[[:space:]]*\[Interface\][[:space:]]*$' "${configFile}")" != "1" ]] ||
        [[ "$(grep -Ec '^[[:space:]]*PrivateKey[[:space:]]*=' "${configFile}")" != "1" ]] ||
        ! dockerWireGuardListenPort >/dev/null; then
        dockerError 'WireGuard 配置无效，或包含不允许在容器中执行的 hook/DNS/SaveConfig'
        return 1
    fi
}

dockerStageHostIntegrationFiles() {
    local specFile=$1 candidate=$2 configFile
    jq -e 'any(.host_integrations[]; .type == "wireguard")' "${specFile}" >/dev/null || return 0
    configFile=$(dockerWireGuardConfigFile) || return 1
    cp -- "${configFile}" "${candidate}/secrets/net/wireguard/wg-padm.conf" &&
        chmod 0600 "${candidate}/secrets/net/wireguard/wg-padm.conf"
}

dockerGenerateFail2banConfig() {
    local specFile=$1 candidate=$2 ports maxRetry findTime banTime allowIPv6
    jq -e 'any(.host_integrations[]; .type == "fail2ban")' "${specFile}" >/dev/null || return 0
    ports=$(jq -r '.host_integrations[] | select(.type == "fail2ban") | .settings.ports | join(",")' "${specFile}") || return 1
    maxRetry=$(jq -r '.host_integrations[] | select(.type == "fail2ban") | .settings.max_retry' "${specFile}") || return 1
    findTime=$(jq -r '.host_integrations[] | select(.type == "fail2ban") | .settings.find_time' "${specFile}") || return 1
    banTime=$(jq -r '.host_integrations[] | select(.type == "fail2ban") | .settings.ban_time' "${specFile}") || return 1
    allowIPv6=$(jq -r '
      [.host_integrations[] | select(.type == "fail2ban") | .settings.ports[]] as $ports |
      if any(.core.protocols[]; .id == 21 and
        (.public_port as $port | ($ports | index($port)) != null) and
        (.address_families | index("ipv6")) != null) then "yes" else "no" end
    ' "${specFile}") || return 1
    cat >"${candidate}/config/net/fail2ban/padm-nginx.conf" <<'EOF'
[Definition]
failregex = ^<HOST> - .* "(GET|POST|HEAD) /(?:\.env(?:\.[^/?"]+)?|\.git|wp-login\.php|wp-admin|phpmyadmin|cgi-bin|manager/html|actuator|boaform)(?:/[^ ?"]*)?(?:\?[^ "]*)? HTTP/[^"]*" (40[34]|444)\b
ignoreregex =
EOF
    cat >"${candidate}/config/net/fail2ban/padm-docker-user.conf" <<'EOF'
[INCLUDES]
before = iptables.conf

[Definition]
actionstart = <iptables> -N padm-f2b || exit 1
              for port in $(echo '<port>' | tr ',' ' '); do <iptables> -I DOCKER-USER 1 -p <protocol> -m conntrack --ctstate NEW --ctorigdstport "$port" -j padm-f2b || { <actionstop>; exit 1; }; done
actionstop = for port in $(echo '<port>' | tr ',' ' '); do <iptables> -D DOCKER-USER -p <protocol> -m conntrack --ctstate NEW --ctorigdstport "$port" -j padm-f2b || true; done
             <actionflush>
             <iptables> -X padm-f2b
actionflush = <iptables> -F padm-f2b
actioncheck = for port in $(echo '<port>' | tr ',' ' '); do <iptables> -C DOCKER-USER -p <protocol> -m conntrack --ctstate NEW --ctorigdstport "$port" -j padm-f2b || exit 1; done
actionban = <iptables> -I padm-f2b 1 -s <ip> -j DROP
actionunban = <iptables> -D padm-f2b -s <ip> -j DROP
EOF
    cat >"${candidate}/config/net/fail2ban/padm.local" <<EOF
[DEFAULT]
backend = polling
bantime = ${banTime}
findtime = ${findTime}
maxretry = ${maxRetry}

[sshd]
enabled = false

[sshd-ddos]
enabled = false

[padm-nginx]
enabled = true
filter = padm-nginx
logpath = /var/log/padm/nginx/access.log
port = ${ports}
action = padm-docker-user[port="${ports}", protocol=tcp]
EOF
    cat >"${candidate}/config/net/fail2ban/fail2ban.local" <<EOF
[Definition]
allowipv6 = ${allowIPv6}
logtarget = STDOUT
socket = /run/fail2ban/fail2ban.sock
pidfile = /run/fail2ban/fail2ban.pid
dbfile = /var/lib/padm/net/fail2ban.sqlite3
EOF
    : >"${candidate}/logs/nginx/access.log"
}

dockerGenerateXrayConfig() {
    local specFile=$1 target=$2
    jq -n --slurpfile request "${specFile}" '
      $request[0] as $r |
      {
        log: {loglevel: "warning"},
        inbounds: ([
          $r.core.protocols[] | select((.core // $r.core.type) == "xray") |
          if .id == 1 or .id == 2 or .id == 26 then {
            listen: "0.0.0.0",
            port: .public_port,
            protocol: "vless",
            tag: (.listener_id // "vless-reality"),
            settings: {
              clients: [{id: .uuid, email: .name} +
                if .id == 1 then {flow: "xtls-rprx-vision"} else {} end],
              decryption: "none"
            },
            streamSettings: ({
              network: (if .id == 1 then "tcp" elif .id == 2 then "xhttp" else "grpc" end),
              security: "reality",
              realitySettings: {
                show: false,
                target: "\(.reality.target_host):\(.reality.target_port)",
                xver: 0,
                serverNames: [.reality.server_name],
                privateKey: .reality.private_key,
                shortIds: ["", .reality.short_id]
              }
            } + (if .id == 2 then {
              xhttpSettings: {path: .xhttp.path, host: .xhttp.host, mode: .xhttp.mode,
                xmux: {maxConcurrency: "16-32", hMaxRequestTimes: "600-900", hMaxReusableSecs: "1800-3000"}}
            } elif .id == 26 then {grpcSettings: {serviceName: .grpc.service_name}} else {} end)),
            sniffing: {enabled: true, destOverride: ["http", "tls", "quic"], routeOnly: true}
          } elif .id == 28 then {
            listen: "::",
            port: .public_port,
            protocol: "trojan",
            tag: .listener_id,
            settings: {clients: [{password: .uuid, email: .uuid}]},
            streamSettings: {
              network: "tcp",
              security: "tls",
              tlsSettings: {
                serverName: .trojan.domain,
                alpn: ["http/1.1"],
                rejectUnknownSni: true,
                minVersion: "1.2",
                certificates: [{
                  certificateFile: "/etc/padm/secrets/tls/\(.trojan.domain).crt",
                  keyFile: "/etc/padm/secrets/tls/\(.trojan.domain).key"
                }]
              }
            }
          } elif .id == 21 or .id == 22 then {
            listen: "0.0.0.0",
            port: (.websocket.backend_port // 31297),
            protocol: (if .id == 22 then "vmess" else "vless" end),
            tag: (.listener_id // "vless-ws"),
            settings: ({
              clients: [{id: .uuid, email: .name} +
                if .id == 22 then {alterId: 0} else {} end]
            } + (if .id == 21 then {decryption: "none"} else {} end)),
            streamSettings: {
              network: "ws",
              security: "none",
              wsSettings: {path: "/\(.websocket.path)ws"}
            }
          } else empty end
        ] + [
          $r.host_integrations[] |
          select(.type == "tproxy") |
          {
            listen: "0.0.0.0",
            port: .settings.port,
            protocol: "dokodemo-door",
            tag: "tproxy-in",
            settings: {network: "tcp,udp", followRedirect: true},
            streamSettings: {sockopt: {tproxy: "tproxy"}},
            sniffing: {enabled: true, destOverride: ["http", "tls", "quic"], routeOnly: true}
          }
        ]),
        outbounds: [
          {protocol: "freedom", tag: "direct"},
          {protocol: "blackhole", tag: "blocked"}
        ]
      }
    ' >"${target}"
}

dockerGenerateSingBoxConfig() {
    local specFile=$1 target=$2
    jq -n --slurpfile request "${specFile}" '
      $request[0] as $r |
      {
        log: {disabled: false, level: "warn", timestamp: true},
        inbounds: ([
          $r.core.protocols[] | select((.core // $r.core.type) == "sing-box") |
          if .id == 28 then {
            type: "trojan",
            tag: .listener_id,
            listen: "::",
            listen_port: .public_port,
            users: [{name: .uuid, password: .uuid}],
            tls: {
              enabled: true,
              server_name: .trojan.domain,
              alpn: ["http/1.1"],
              certificate_path: "/etc/padm/secrets/tls/\(.trojan.domain).crt",
              key_path: "/etc/padm/secrets/tls/\(.trojan.domain).key"
            }
          }
          elif .id == 3 then {
            type: "hysteria2",
            tag: .listener_id,
            listen: "::",
            listen_port: .public_port,
            # 密码和统计名称都固定为 UUID，使多入口共享现有流量账号。
            users: [{name: .uuid, password: .uuid}],
            tls: {
              enabled: true,
              server_name: .hy2.domain,
              alpn: ["h3"],
              certificate_path: "/etc/padm/secrets/tls/\(.hy2.domain).crt",
              key_path: "/etc/padm/secrets/tls/\(.hy2.domain).key"
            }
          } + (if .hy2.bandwidth_mode == "bbr" then {ignore_client_bandwidth: true}
            else {up_mbps: .hy2.up_mbps, down_mbps: .hy2.down_mbps} end) +
            (if .hy2.obfs != null then {obfs: .hy2.obfs} else {} end) +
            (if .hy2.masquerade != "" then {masquerade: .hy2.masquerade} else {} end)
          elif .id == 4 then {
            type: "anytls",
            tag: .listener_id,
            listen: "::",
            listen_port: .public_port,
            users: [{name: .uuid, password: .uuid}],
            tls: {
              enabled: true,
              server_name: .anytls.domain,
              certificate_path: "/etc/padm/secrets/tls/\(.anytls.domain).crt",
              key_path: "/etc/padm/secrets/tls/\(.anytls.domain).key"
            }
          }
          elif .id == 5 then {
            type: "naive",
            tag: .listener_id,
            listen: "::",
            listen_port: .public_port,
            network: "tcp",
            users: [{username: .uuid, password: .uuid}],
            tls: {
              enabled: true,
              server_name: .naive.domain,
              certificate_path: "/etc/padm/secrets/tls/\(.naive.domain).crt",
              key_path: "/etc/padm/secrets/tls/\(.naive.domain).key"
            }
          }
          elif .id == 30 then {
            type: "shadowsocks",
            tag: .listener_id,
            listen: "::",
            listen_port: .public_port,
            method: .shadowsocks.method,
            password: .shadowsocks.server_password,
            users: [{name: .uuid, password: .shadowsocks.user_password}]
          }
          elif .id == 31 then {
            type: "tuic",
            tag: .listener_id,
            listen: "::",
            listen_port: .public_port,
            users: [{name: .uuid, uuid: .uuid, password: .uuid}],
            congestion_control: .tuic.congestion_control,
            auth_timeout: .tuic.auth_timeout,
            heartbeat: .tuic.heartbeat,
            zero_rtt_handshake: .tuic.zero_rtt_handshake,
            tls: {
              enabled: true,
              server_name: .tuic.domain,
              alpn: ["h3"],
              certificate_path: "/etc/padm/secrets/tls/\(.tuic.domain).crt",
              key_path: "/etc/padm/secrets/tls/\(.tuic.domain).key"
            }
          }
          else {
            type: "vless",
            tag: (.listener_id // "vless-reality"),
            listen: "::",
            listen_port: .public_port,
            users: [{uuid: .uuid, name: .name} +
              if .id == 1 then {flow: "xtls-rprx-vision"} else {} end],
            tls: {
              enabled: true,
              server_name: .reality.server_name,
              reality: {
                enabled: true,
                handshake: {server: .reality.target_host, server_port: .reality.target_port},
                private_key: .reality.private_key,
                short_id: ["", .reality.short_id]
              }
            }
          } + (if .id == 26 then {transport: {type: "grpc", service_name: .grpc.service_name}} else {} end) end
        ] + [
          $r.host_integrations[] |
          if .type == "tun" then {
            type: "tun",
            tag: "tun-in",
            interface_name: .settings.interface,
            address: [.settings.address],
            dns_mode: "disabled",
            auto_route: true,
            auto_redirect: true,
            strict_route: true,
            stack: "system"
          } elif .type == "tproxy" then {
            type: "tproxy",
            tag: "tproxy-in",
            listen: "0.0.0.0",
            listen_port: .settings.port
          } else empty end
        ]),
        outbounds: [{type: "direct", tag: "direct"}],
        route: {final: "direct", auto_detect_interface: true}
      }
    ' >"${target}"
}

dockerStageTlsFiles() {
    local specFile=$1 candidate=$2 sourceDir=${3:-} root domain extension
    root=$(dockerInstallRoot) || return 1
    [[ -z "${sourceDir}" || ( -d "${sourceDir}" && ! -L "${sourceDir}" ) ]] || return 1
    [[ -n "${sourceDir}" ]] || sourceDir="${root}/secrets/tls"
    if [[ -e "${sourceDir}" || -L "${sourceDir}" ]]; then
        dockerManagedPathIsSafe "${root}" "${sourceDir}" &&
            [[ -d "${sourceDir}" && ! -L "${sourceDir}" ]] &&
            [[ -z "$(find "${sourceDir}" -type l -print -quit)" ]] || return 1
        cp -a -- "${sourceDir}/." "${candidate}/secrets/tls/" || return 1
    fi
    jq -e '.tls != null' "${specFile}" >/dev/null || return 0
    domain=$(jq -r '.tls.domain' "${specFile}") || return 1
    for extension in crt key; do
        [[ -f "${candidate}/secrets/tls/${domain}.${extension}" &&
            ! -L "${candidate}/secrets/tls/${domain}.${extension}" ]] || {
            dockerError "候选 TLS 文件缺失: ${domain}.${extension}"
            return 1
        }
    done
}

dockerGenerateNginxConfig() {
    local specFile=$1 target=$2 domain path token subscriptionEnabled fail2banEnabled backendPort tlsPort
    jq -e 'any(.core.protocols[]; .id == 21 or .id == 22)' "${specFile}" >/dev/null || return 0
    domain=$(jq -r '.tls.domain' "${specFile}") || return 1
    token=$(jq -r '.subscription.token' "${specFile}") || return 1
    subscriptionEnabled=$(jq -r '.subscription.enabled' "${specFile}") || return 1
    fail2banEnabled=$(jq -r 'any(.host_integrations[]; .type == "fail2ban")' "${specFile}") || return 1
    cat >"${target}" <<EOF
server {
    listen 8080;
    listen [::]:8080;
    server_name _;

    location = /healthz {
        access_log off;
        default_type text/plain;
        return 200 "ok\n";
    }
}
EOF
    while IFS=$'\t' read -r path backendPort tlsPort; do
        cat >>"${target}" <<EOF

server {
    listen ${tlsPort} ssl;
    listen [::]:${tlsPort} ssl;
    server_name ${domain};

    ssl_certificate /etc/padm/secrets/tls/${domain}.crt;
    ssl_certificate_key /etc/padm/secrets/tls/${domain}.key;
    ssl_protocols TLSv1.2 TLSv1.3;
EOF
    if [[ "${fail2banEnabled}" == "true" ]]; then
        printf '    access_log /var/log/nginx/access.log combined;\n\n' >>"${target}" || return 1
    fi
    cat >>"${target}" <<EOF
    location = /${path}ws {
        proxy_pass http://xray:${backendPort};
        proxy_http_version 1.1;
        proxy_read_timeout 5d;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
EOF
    if [[ "${subscriptionEnabled}" == "true" ]]; then
        cat >>"${target}" <<EOF

    location = /subscriptions/${token} {
        access_log off;
        proxy_pass http://subscription:${PADM_DOCKER_SUBSCRIPTION_PORT}/${token};
        proxy_pass_request_headers off;
    }
EOF
    fi
        printf '}\n' >>"${target}" || return 1
    done < <(jq -r '.core.protocols[] | select(.id == 21 or .id == 22) |
      [.websocket.path, (.websocket.backend_port // 31297), (.websocket.tls_port // 8443)] | @tsv' "${specFile}")
}

dockerGenerateSubscription() {
    local specFile=$1 target=$2
    jq -e '.subscription.enabled == true' "${specFile}" >/dev/null || return 0
    jq -r '
      def authority: if contains(":") then "[\(.)]" else . end;
      .core.protocols[] |
      if .id == 1 then
        "vless://\(.uuid)@\(.server | authority):\(.public_port)?encryption=none&flow=xtls-rprx-vision&security=reality&sni=\(.reality.server_name | @uri)&fp=chrome&pbk=\(.reality.public_key | @uri)&sid=\(.reality.short_id)&type=tcp#\(.name | @uri)"
      elif .id == 2 then
        "vless://\(.uuid)@\(.server | authority):\(.public_port)?encryption=none&security=reality&sni=\(.reality.server_name | @uri)&fp=chrome&pbk=\(.reality.public_key | @uri)&sid=\(.reality.short_id)&type=xhttp&host=\(.xhttp.host | @uri)&path=\(.xhttp.path | @uri)&mode=\(.xhttp.mode)#\(.name | @uri)"
      elif .id == 26 then
        "vless://\(.uuid)@\(.server | authority):\(.public_port)?encryption=none&security=reality&sni=\(.reality.server_name | @uri)&fp=chrome&pbk=\(.reality.public_key | @uri)&sid=\(.reality.short_id)&type=grpc&alpn=h2&path=\(.grpc.service_name | @uri)&serviceName=\(.grpc.service_name | @uri)#\(.name | @uri)"
      elif .id == 28 then
        "trojan://\(.uuid | @uri)@\(.server | authority):\(.public_port)?peer=\(.trojan.domain | @uri)&fp=chrome&sni=\(.trojan.domain | @uri)&alpn=\("http/1.1" | @uri)#\(.name | @uri)"
      elif .id == 3 then
        # 服务端上行对应客户端下行，分享链接需要交换带宽方向。
        "hysteria2://\(.uuid | @uri)@\(.server | authority):\(.public_port)?peer=\(.hy2.domain | @uri)&insecure=0&sni=\(.hy2.domain | @uri)&alpn=h3" +
          (if .hy2.bandwidth_mode == "brutal" then "&upmbps=\(.hy2.down_mbps)&downmbps=\(.hy2.up_mbps)" else "" end) +
          (if .hy2.obfs != null then "&obfs=\(.hy2.obfs.type | @uri)&obfs-password=\(.hy2.obfs.password | @uri)" else "" end) +
          "#\(.name | @uri)"
      elif .id == 4 then
        "anytls://\(.uuid | @uri)@\(.server | authority):\(.public_port)?security=tls&sni=\(.anytls.domain | @uri)#\(.name | @uri)"
      elif .id == 5 then
        "naive+https://\(.uuid | @uri):\(.uuid | @uri)@\(.server | authority):\(.public_port)?padding=true#\(.name | @uri)"
      elif .id == 30 then
        # SIP002 的 AEAD-2022 凭据必须分别百分号编码，不整段 Base64。
        "ss://\(.shadowsocks.method | @uri):\((.shadowsocks.server_password + ":" + .shadowsocks.user_password) | @uri)@\(.server | authority):\(.public_port)#\(.name | @uri)"
      elif .id == 31 then
        "tuic://\(.uuid | @uri):\(.uuid | @uri)@\(.server | authority):\(.public_port)?congestion_control=\(.tuic.congestion_control | @uri)&alpn=h3&sni=\(.tuic.domain | @uri)&udp_relay_mode=native&allow_insecure=0#\(.name | @uri)"
      elif .id == 21 then
        "vless://\(.uuid)@\(.server | authority):\(.public_port)?encryption=none&security=tls&sni=\(.websocket.domain | @uri)&type=ws&host=\(.websocket.domain | @uri)&path=\("/" + .websocket.path + "ws" | @uri)#\(.name | @uri)"
      elif .id == 22 then
        "vmess://" + ({
          v: "2", ps: .name, add: .server, port: (.public_port | tostring), id: .uuid,
          aid: "0", scy: "auto", net: "ws", type: "none", host: .websocket.domain,
          path: ("/" + .websocket.path + "ws"), tls: "tls", sni: .websocket.domain
        } | tojson | @base64)
      else empty end
    ' "${specFile}" >"${target}"
}

dockerGenerateImagesEnv() {
    local specFile=$1 target=$2 rootValue=$3 netRootValue=${4:-$3} key jsonKey value
    while IFS='|' read -r key jsonKey; do
        value=$(jq -r --arg key "${jsonKey}" '.images[$key]' "${specFile}") || return 1
        printf '%s=%s\n' "${key}" "${value}" >>"${target}" || return 1
    done <<'EOF'
PADM_XRAY_IMAGE|xray
PADM_SINGBOX_IMAGE|sing-box
PADM_NGINX_IMAGE|nginx
PADM_OPS_IMAGE|ops
PADM_NET_IMAGE|net
EOF
    printf 'PADM_DOCKER_ROOT=%s\n' "${rootValue}" >>"${target}"
    printf 'PADM_NET_ROOT=%s\n' "${netRootValue}" >>"${target}"
}

dockerGenerateCompose() {
    local specFile=$1 target=$2 core domains directory tlsCores='[]'
    directory=$(dirname -- "${target}")
    while IFS= read -r core; do
        [[ -e "${directory}/config/${core}/config.json" ]] || continue
        domains=$(dockerCoreTlsDomains "${core}" "${directory}/config/${core}/config.json") || return 1
        if [[ "${domains}" != '[]' ]]; then
            tlsCores=$(jq -c --arg core "${core}" '. + [$core]' <<<"${tlsCores}") || return 1
        fi
    done < <(jq -r '[.core.type, .core.secondary_type] | .[] | select(. != null)' "${specFile}")
    jq -n --slurpfile request "${specFile}" --argjson tlsCores "${tlsCores}" '
      $request[0] as $r |
      def defaults: {
        init: true,
        read_only: true,
        restart: "unless-stopped",
        cap_drop: ["ALL"],
        security_opt: ["no-new-privileges:true"],
        pids_limit: 256,
        ulimits: {nofile: {soft: 65536, hard: 65536}},
        logging: {driver: "json-file", options: {"max-size": "10m", "max-file": "3"}}
      };
      def labels($component): {
        "io.padm.mode": "docker",
        "io.padm.project": "padm-docker",
        "io.padm.component": $component,
        "io.padm.release": $r.release.version
      };
      def mounts($name; $target; $readonly): [{
        type: "bind",
        source: "${PADM_DOCKER_ROOT}/\($name)",
        target: $target,
        read_only: $readonly
      }];
      def net_mounts($name; $target; $readonly): [{
        type: "bind",
        source: "${PADM_NET_ROOT}/\($name)",
        target: $target,
        read_only: $readonly
      }];
      def ports($protocol; $containerPort): [
        $protocol.address_families[] |
        (if $protocol.id == 30 then "tcp", "udp" elif $protocol.id == 3 or $protocol.id == 31 then "udp" else "tcp" end) as $transport |
        if . == "ipv4" then "0.0.0.0:\($protocol.public_port):\($containerPort)/\($transport)"
        else "[::]:\($protocol.public_port):\($containerPort)/\($transport)" end
      ];
      [$r.core.type, $r.core.secondary_type] | map(select(. != null)) as $cores |
      ($r.core.protocols | map(select(.id == 1 or .id == 2 or .id == 3 or .id == 4 or .id == 5 or .id == 26 or .id == 28 or .id == 30 or .id == 31))) as $direct |
      ($r.core.protocols | map(select(.id == 21 or .id == 22))) as $websocket |
      ($r.host_integrations | map(select(.type == "wireguard"))) as $wireguard |
      ($r.host_integrations | map(select(.type == "fail2ban"))) as $fail2ban |
      ($r.host_integrations | map(select(.type == "tun"))) as $tun |
      ($r.host_integrations | map(select(.type == "tproxy"))) as $tproxy |
      (($tun | length) + ($tproxy | length) == 1) as $transparent |
      ({
        name: "padm-docker",
        services: {},
        networks: {
          default: {
            name: "padm-docker",
            labels: {"io.padm.mode": "docker", "io.padm.project": "padm-docker"}
          }
        }
      }
      | if ($cores | index("xray")) != null then
          .services.xray = (defaults + {
            image: "${PADM_XRAY_IMAGE:?PADM_XRAY_IMAGE is required}",
            profiles: ["core-xray"],
            labels: labels("xray"),
            volumes: (mounts("config/xray"; "/etc/padm/xray"; true) +
                mounts("data/xray"; "/var/lib/padm/xray"; false) +
                if ($tlsCores | index("xray")) != null then
                  mounts("secrets/tls"; "/etc/padm/secrets/tls"; true) else [] end),
            ports: [$direct[] | select((.core // $r.core.type) == "xray") |
              . as $protocol | ports($protocol; $protocol.public_port)[]],
            tmpfs: ["/tmp:rw,noexec,nosuid,nodev,size=16m"],
            healthcheck: {
              test: ["CMD", "/usr/local/bin/xray", "-test", "-confdir", "/etc/padm/xray"],
              interval: "30s", timeout: "5s", start_period: "5s", retries: 3
            }
          })
        else . end
      | if ($cores | index("sing-box")) != null then
          .services["sing-box"] = (defaults + {
            image: "${PADM_SINGBOX_IMAGE:?PADM_SINGBOX_IMAGE is required}",
            profiles: ["core-sing-box"],
            labels: labels("sing-box"),
            volumes: (mounts("config/sing-box"; "/etc/padm/sing-box"; true) +
                mounts("data/sing-box"; "/var/lib/padm/sing-box"; false) +
                if ($tlsCores | index("sing-box")) != null then
                  mounts("secrets/tls"; "/etc/padm/secrets/tls"; true) else [] end),
            ports: [$direct[] | select((.core // $r.core.type) == "sing-box") |
              . as $protocol | ports($protocol; $protocol.public_port)[]],
            tmpfs: ["/tmp:rw,noexec,nosuid,nodev,size=16m"],
            healthcheck: {
              test: ["CMD", "/usr/local/bin/sing-box", "check", "-D", "/var/lib/padm/sing-box", "-c", "/etc/padm/sing-box/config.json"],
              interval: "30s", timeout: "5s", start_period: "5s", retries: 3
            }
          })
        else . end
      | if $transparent then
          .services[$r.core.type].profiles += ["net-transparent"]
          | .services[$r.core.type].network_mode = "host"
          | .services[$r.core.type].user = "0:0"
          | .services[$r.core.type].cap_add = ["NET_ADMIN"]
          | del(.services[$r.core.type].ports)
          | if ($tun | length) == 1 then
              .services[$r.core.type].devices = [{
                source: "/dev/net/tun", target: "/dev/net/tun", permissions: "rwm"
              }]
            else . end
        else . end
      | if ($websocket | length) > 0 then
          .services.nginx = (defaults + {
            image: "${PADM_NGINX_IMAGE:?PADM_NGINX_IMAGE is required}",
            profiles: ["nginx"],
            labels: labels("nginx"),
            depends_on: {xray: {condition: "service_healthy"}},
            volumes: (mounts("config/nginx"; "/etc/nginx/http.d"; true) +
              mounts("data/static"; "/srv/padm"; true) +
              mounts("secrets/tls"; "/etc/padm/secrets/tls"; true) +
              mounts("logs/nginx"; "/var/log/nginx"; false)),
            ports: [$websocket[] as $protocol | ports($protocol; ($protocol.websocket.tls_port // 8443))[]],
            tmpfs: ["/tmp:rw,noexec,nosuid,nodev,size=32m"]
          })
        else . end
      | if $r.subscription.enabled then
          .services.subscription = (defaults + {
            image: "${PADM_OPS_IMAGE:?PADM_OPS_IMAGE is required}",
            profiles: ["subscription"],
            command: ["subscription", "--bind", "0.0.0.0", "--port", "8081"],
            labels: labels("subscription"),
            volumes: mounts("data/subscription"; "/var/lib/padm/subscription"; true),
            tmpfs: ["/tmp:rw,noexec,nosuid,nodev,size=16m"],
            healthcheck: {
              test: ["CMD", "/usr/local/bin/padm-entrypoint", "subscription-health"],
              interval: "30s", timeout: "5s", start_period: "5s", retries: 3
            }
          })
          | .services.nginx.depends_on.subscription = {condition: "service_healthy"}
        else . end
      | .services.acme = (defaults + {
          image: "${PADM_OPS_IMAGE:?PADM_OPS_IMAGE is required}",
          profiles: ["acme"],
          command: ["acme", "--version"],
          restart: "no",
          labels: labels("acme"),
          volumes: (mounts("data/acme"; "/var/lib/padm/acme"; false) +
            mounts("secrets/tls"; "/etc/padm/secrets/tls"; true)),
          tmpfs: ["/tmp:rw,noexec,nosuid,nodev,size=16m"]
        })
      | if ($wireguard | length) == 1 then
          .services["net-wireguard"] = (defaults + {
            image: "${PADM_NET_IMAGE:?PADM_NET_IMAGE is required}",
            profiles: ["net-wireguard"],
            command: ["wireguard", "/etc/wireguard/wg-padm.conf", "wg-padm"],
            network_mode: "host",
            cap_add: ["NET_ADMIN"],
            labels: labels("net-wireguard"),
            volumes: (net_mounts("secrets/net/wireguard/wg-padm.conf"; "/etc/wireguard/wg-padm.conf"; true) +
              net_mounts("data/net/wireguard"; "/var/lib/padm/net"; false)),
            tmpfs: ["/run:rw,nosuid,nodev,size=16m", "/tmp:rw,noexec,nosuid,nodev,size=16m"],
            healthcheck: {
              test: ["CMD", "/usr/local/bin/padm-entrypoint", "wireguard-health", "wg-padm"],
              interval: "30s", timeout: "5s", start_period: "5s", retries: 3
            }
          })
        else . end
      | if ($fail2ban | length) == 1 then
          .services["net-fail2ban"] = (defaults + {
            image: "${PADM_NET_IMAGE:?PADM_NET_IMAGE is required}",
            profiles: ["net-fail2ban"],
            command: ["fail2ban", ($fail2ban[0].settings.ports | join(","))],
            network_mode: "host",
            cap_add: ["NET_ADMIN"],
            labels: labels("net-fail2ban"),
            depends_on: {nginx: {condition: "service_started"}},
            volumes: (net_mounts("config/net/fail2ban/padm.local"; "/etc/fail2ban/jail.d/padm.local"; true) +
              net_mounts("config/net/fail2ban/fail2ban.local"; "/etc/fail2ban/fail2ban.local"; true) +
              net_mounts("config/net/fail2ban/padm-nginx.conf"; "/etc/fail2ban/filter.d/padm-nginx.conf"; true) +
              net_mounts("config/net/fail2ban/padm-docker-user.conf"; "/etc/fail2ban/action.d/padm-docker-user.conf"; true) +
              net_mounts("logs/nginx"; "/var/log/padm/nginx"; true) +
              net_mounts("data/net/fail2ban"; "/var/lib/padm/net"; false)),
            tmpfs: ["/run:rw,nosuid,nodev,size=16m", "/tmp:rw,noexec,nosuid,nodev,size=16m"],
            healthcheck: {
              test: ["CMD", "/usr/local/bin/padm-entrypoint", "fail2ban-health"],
              interval: "30s", timeout: "5s", start_period: "5s", retries: 3
            }
          })
        else . end
      | if ($tproxy | length) == 1 then
          .services["net-transparent"] = (defaults + {
            image: "${PADM_NET_IMAGE:?PADM_NET_IMAGE is required}",
            profiles: ["net-transparent"],
            command: ["tproxy", ($tproxy[0].settings.port | tostring), ($tproxy[0].settings.mark | tostring)],
            network_mode: "host",
            cap_add: ["NET_ADMIN"],
            labels: labels("net-transparent"),
            depends_on: {($r.core.type): {condition: "service_healthy"}},
            volumes: net_mounts("data/net/transparent"; "/var/lib/padm/net"; false),
            tmpfs: ["/run:rw,nosuid,nodev,size=16m", "/tmp:rw,noexec,nosuid,nodev,size=16m"],
            healthcheck: {
              test: ["CMD", "/usr/local/bin/padm-entrypoint", "tproxy-health",
                ($tproxy[0].settings.port | tostring), ($tproxy[0].settings.mark | tostring)],
              interval: "30s", timeout: "5s", start_period: "5s", retries: 3
            }
          })
        else . end
      | if ($tun | length) == 1 then
          .services["net-tun-check"] = (defaults + {
            image: "${PADM_NET_IMAGE:?PADM_NET_IMAGE is required}",
            profiles: ["net-check"],
            command: ["idle"],
            restart: "no",
            network_mode: "host",
            cap_add: ["NET_ADMIN"],
            devices: [{source: "/dev/net/tun", target: "/dev/net/tun", permissions: "rwm"}],
            labels: labels("net-tun-check"),
            tmpfs: ["/run:rw,nosuid,nodev,size=16m", "/tmp:rw,noexec,nosuid,nodev,size=16m"]
          })
        else . end
      )
    ' >"${target}"
}

dockerGenerateDeployment() {
    local specFile=$1 target=$2 bundlePath bundleVersion previous= wireguardPort=0
    local root
    bundlePath=$(dockerCurrentBundlePath) || return 1
    bundleVersion=$(<"${bundlePath}/${PADM_DOCKER_BUNDLE_REF}") || return 1
    root=$(dockerInstallRoot) || return 1
    if [[ -f "${root}/deployment.json" && ! -L "${root}/deployment.json" ]]; then
        previous=$(jq -r '.manifest.sha256 // empty' "${root}/deployment.json" 2>/dev/null || true)
    fi
    if jq -e 'any(.host_integrations[]; .type == "wireguard")' "${specFile}" >/dev/null; then
        wireguardPort=$(dockerWireGuardListenPort) || return 1
    fi
    jq -n --slurpfile request "${specFile}" --arg bundle "${bundleVersion}" \
        --arg previous "${previous}" --argjson wireguardPort "${wireguardPort}" '
      $request[0] as $r |
      def digest: capture("@(?<value>sha256:[a-f0-9]{64})$").value;
      def profiles:
        ([[$r.core.type, $r.core.secondary_type][] | select(. != null) | "core-\(.)"] +
        [if any($r.core.protocols[]; .id == 21 or .id == 22) then "nginx" else empty end] +
        [if $r.subscription.enabled then "subscription" else empty end] +
        [$r.host_integrations[].profile]);
      {
        schema_version: 1,
        mode: "docker",
        padm_version: $r.release.version,
        bundle_version: $bundle,
        manifest: {
          sha256: $r.release.manifest_sha256,
          signature_identity: $r.release.signature_identity
        },
        compose: {project: "padm-docker", profiles: profiles},
        core: ({type: $r.core.type, protocol_ids: ([$r.core.protocols[].id] | unique)} +
          if $r.schema_version == 3 then {secondary_type: $r.core.secondary_type} else {} end),
        listeners: (
          [
          $r.core.protocols[] |
          (if .id == 30 then "tcp", "udp" elif .id == 3 or .id == 31 then "udp" else "tcp" end) as $transport |
          ({
            service: (if .id == 21 or .id == 22 then "nginx" else (.core // $r.core.type) end),
            public_port: .public_port,
            container_port: (if .id == 21 or .id == 22 then (.websocket.tls_port // 8443) else .public_port end),
            transport: $transport,
            address_families: .address_families
          } + if $r.schema_version >= 2 then {listener_id: .listener_id} else {} end)
          ] + [
          $r.host_integrations[] |
          if .type == "wireguard" then {
            service: "net-wireguard", public_port: $wireguardPort,
            container_port: $wireguardPort, transport: "udp",
            address_families: ["ipv4", "ipv6"]
          } + if $r.schema_version >= 2 then {listener_id: "host-wireguard"} else {} end
          elif .type == "tproxy" then
            ({service: $r.core.type, public_port: .settings.port,
              container_port: .settings.port, transport: "tcp", address_families: ["ipv4"]} +
              if $r.schema_version >= 2 then {listener_id: "host-tproxy-tcp"} else {} end),
            ({service: $r.core.type, public_port: .settings.port,
              container_port: .settings.port, transport: "udp", address_families: ["ipv4"]} +
              if $r.schema_version >= 2 then {listener_id: "host-tproxy-udp"} else {} end)
          else empty end
          ]
        ),
        images: {
          xray: {index_digest: ($r.images.xray | digest)},
          "sing-box": {index_digest: ($r.images["sing-box"] | digest)},
          nginx: {index_digest: ($r.images.nginx | digest)},
          ops: {index_digest: ($r.images.ops | digest)},
          net: {index_digest: ($r.images.net | digest)}
        },
        formats: {compose: 1, config: 1, data: 1},
        previous_manifest_sha256: (if $previous == "" then null else $previous end),
        host_integrations: [$r.host_integrations[] | {
          type, profile, firewall_rules, devices, schedules, settings
        }]
      }
    ' >"${target}"
}

dockerDeploymentFileValidate() {
    jq -e '
      def exact($keys): type == "object" and ((keys_unsorted | sort) == ($keys | sort));
      type == "object" and .schema_version == 1 and .mode == "docker" and
      .compose.project == "padm-docker" and
      (.compose.profiles | type == "array" and (unique | length) == length) and
      (.core.type == "xray" or .core.type == "sing-box") and
      (if .core.secondary_type != null then
        (.core.secondary_type == "xray" or .core.secondary_type == "sing-box") and
        .core.secondary_type != .core.type and .host_integrations == [] and
        (.compose.profiles | index("core-xray")) != null and
        (.compose.profiles | index("core-sing-box")) != null
       else true end) and
      (.core.protocol_ids | type == "array" and length >= 1 and (unique | length) == length) and
      (.listeners | type == "array" and length >= 1 and
        all(.[]; (.public_port | type == "number" and floor == . and . >= 1 and . <= 65535) and
          (.container_port | type == "number" and floor == . and . >= 1 and . <= 65535) and
          (.transport == "tcp" or .transport == "udp")) and
        (if any(.[]; has("listener_id")) then
          ([.[] | [.listener_id, .transport]] | unique | length) == length and
          all(.[]; .listener_id | type == "string" and
            test("^(entry-[a-z0-9][a-z0-9-]{0,47}|vless-reality|vless-ws|host-wireguard|host-tproxy-tcp|host-tproxy-udp)$"))
         else true end)) and
      (.images | keys | sort) == (["xray", "sing-box", "nginx", "ops", "net"] | sort) and
      all(.images[]; .index_digest | test("^sha256:[a-f0-9]{64}$")) and
      (.host_integrations | type == "array" and length <= 3 and
        ([.[].type] | unique | length) == length) and
      (. as $deployment | all(.host_integrations[];
        exact(["type", "profile", "firewall_rules", "devices", "schedules", "settings"]) and
        (.profile as $profile | ($deployment.compose.profiles | index($profile)) != null) and
        if .type == "wireguard" then
          .profile == "net-wireguard" and .firewall_rules == [] and .devices == ["wg-padm"] and
          (.settings.config_file == "wg-padm.conf" and .settings.interface == "wg-padm")
        elif .type == "fail2ban" then
          .profile == "net-fail2ban" and .firewall_rules == ["DOCKER-USER"] and .devices == []
        elif .type == "tun" then
          .profile == "net-transparent" and .devices == ["/dev/net/tun"]
        elif .type == "tproxy" then
          .profile == "net-transparent" and .firewall_rules == ["padm-tproxy"] and .devices == []
        else false end))
    ' "$1" >/dev/null 2>&1
}

dockerTlsRuntimePermissions() {
    local directory=$1
    [[ -e "${directory}" || -L "${directory}" ]] || return 0
    [[ -d "${directory}" && ! -L "${directory}" ]] &&
        [[ -z "$(find "${directory}" -type l -print -quit)" ]] || return 1
    find "${directory}" -type d -exec chmod 0750 {} + || return 1
    find "${directory}" -type f ! -name '*.key' -exec chmod 0640 {} + || return 1
    find "${directory}" -type f -name '*.key' -exec chmod 0600 {} + || return 1
    if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != "1" ]]; then
        find "${directory}" ! -name '*.key' \
            -exec chown "0:${PADM_DOCKER_CONTAINER_GID}" {} + || return 1
        # 私钥仅供实际运行的容器用户读取，不赋予整个容器组读取权限。
        find "${directory}" -type f -name '*.key' \
            -exec chown "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" {} + || return 1
    fi
}

dockerPrepareCandidatePermissions() {
    local candidate=$1 directory
    if [[ -e "${candidate}/config/spec.json" || -L "${candidate}/config/spec.json" ]]; then
        [[ -f "${candidate}/config/spec.json" && ! -L "${candidate}/config/spec.json" ]] || return 1
        chmod 0600 "${candidate}/config/spec.json" || return 1
    fi
    find "${candidate}/config" "${candidate}/data" "${candidate}/logs" -type d -exec chmod 0750 {} + || return 1
    find "${candidate}/config" "${candidate}/data" "${candidate}/logs" -type f \
        ! -path "${candidate}/config/spec.json" -exec chmod 0640 {} + || return 1
    find "${candidate}/secrets" -type d -exec chmod 0750 {} + || return 1
    find "${candidate}/secrets" -type f -exec chmod 0640 {} + || return 1
    chmod 0640 "${candidate}/deployment.json" "${candidate}/compose.json" \
        "${candidate}/images.env" "${candidate}/images.runtime.env" || return 1
    if [[ -f "${candidate}/secrets/net/wireguard/wg-padm.conf" ]]; then
        chmod 0600 "${candidate}/secrets/net/wireguard/wg-padm.conf" || return 1
    fi
    if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != "1" ]]; then
        find "${candidate}/config" ! -path "${candidate}/config/spec.json" \
            -exec chown "0:${PADM_DOCKER_CONTAINER_GID}" {} + || return 1
        chown -R "0:${PADM_DOCKER_CONTAINER_GID}" "${candidate}/data/subscription" \
            "${candidate}/logs" "${candidate}/secrets" || return 1
        chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" \
            "${candidate}/logs/nginx" || return 1
        for directory in "${candidate}/data/xray" "${candidate}/data/sing-box" "${candidate}/data/acme"; do
            chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" "${directory}" || return 1
        done
    fi
    # 完整规格包含所有协议秘密，只允许宿主 root 读取，不交给容器组。
    if [[ -e "${candidate}/config/spec.json" || -L "${candidate}/config/spec.json" ]]; then
        [[ -f "${candidate}/config/spec.json" && ! -L "${candidate}/config/spec.json" ]] || return 1
        chmod 0600 "${candidate}/config/spec.json" || return 1
        [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" == "1" ]] ||
            chown 0:0 "${candidate}/config/spec.json" || return 1
    fi
    dockerTlsRuntimePermissions "${candidate}/secrets/tls"
}

dockerGenerateCandidate() {
    local specFile=$1 candidate=$2 tlsSource=${3:-} acmeSource=${4:-} root core token
    root=$(dockerInstallRoot) || return 1
    while IFS= read -r core; do
        case "${core}" in
        xray) dockerGenerateXrayConfig "${specFile}" "${candidate}/config/xray/config.json" || return 1 ;;
        sing-box) dockerGenerateSingBoxConfig "${specFile}" "${candidate}/config/sing-box/config.json" || return 1 ;;
        *) return 1 ;;
        esac
    done < <(jq -r '[.core.type, .core.secondary_type] | .[] | select(. != null)' "${specFile}")
    dockerStageHostIntegrationFiles "${specFile}" "${candidate}" || return 1
    dockerGenerateFail2banConfig "${specFile}" "${candidate}" || return 1
    dockerStageTlsFiles "${specFile}" "${candidate}" "${tlsSource}" || return 1
    [[ -z "${acmeSource}" || ( -d "${acmeSource}" && ! -L "${acmeSource}" ) ]] || return 1
    [[ -n "${acmeSource}" ]] || acmeSource="${root}/data/acme"
    if [[ -e "${acmeSource}" || -L "${acmeSource}" ]]; then
        dockerManagedPathIsSafe "${root}" "${acmeSource}" &&
            [[ -d "${acmeSource}" && ! -L "${acmeSource}" ]] &&
            [[ -z "$(find "${acmeSource}" -type l -print -quit)" ]] || return 1
        cp -a -- "${acmeSource}/." "${candidate}/data/acme/" || return 1
    fi
    cp -- "${specFile}" "${candidate}/config/spec.json" || return 1
    chmod 0600 "${candidate}/config/spec.json" || return 1
    dockerGenerateNginxConfig "${specFile}" "${candidate}/config/nginx/default.conf" || return 1
    if jq -e '.subscription.enabled == true' "${specFile}" >/dev/null; then
        token=$(jq -r '.subscription.token' "${specFile}") || return 1
        dockerGenerateSubscription "${specFile}" "${candidate}/data/subscription/${token}" || return 1
    fi
    : >"${candidate}/images.env"
    : >"${candidate}/images.runtime.env"
    dockerGenerateImagesEnv "${specFile}" "${candidate}/images.env" "${candidate}" || return 1
    dockerGenerateImagesEnv "${specFile}" "${candidate}/images.runtime.env" "${root}" || return 1
    dockerGenerateCompose "${specFile}" "${candidate}/compose.json" || return 1
    dockerGenerateDeployment "${specFile}" "${candidate}/deployment.json" || return 1
    dockerTrafficPrepareCandidate "${candidate}" || return 1
    dockerPrepareCandidatePermissions "${candidate}"
}

dockerCandidateCompose() {
    local candidate=$1
    shift
    docker compose --project-name "${PADM_DOCKER_PROJECT}" \
        --project-directory "${candidate}" --env-file "${candidate}/images.env" \
        --file "${candidate}/compose.json" --profile '*' "$@"
}

dockerCurrentOwnsHostIntegration() {
    local type=$1 root
    root=$(dockerInstallRoot) || return 1
    [[ -f "${root}/deployment.json" && ! -L "${root}/deployment.json" ]] || return 1
    jq -e --arg type "${type}" 'any(.host_integrations[]?; .type == $type)' \
        "${root}/deployment.json" >/dev/null 2>&1
}

dockerValidateHostIntegrations() {
    local specFile=$1 candidate=$2 ownership port mark ports
    if jq -e 'any(.host_integrations[]; .type == "wireguard")' "${specFile}" >/dev/null; then
        ownership=unowned
        dockerCurrentOwnsHostIntegration wireguard && ownership=owned
        dockerCandidateCompose "${candidate}" run --rm --no-deps net-wireguard \
            preflight wireguard /etc/wireguard/wg-padm.conf wg-padm "${ownership}" >/dev/null || {
            dockerError 'WireGuard 内核、配置或接口前置检查失败'
            return 1
        }
    fi
    if jq -e 'any(.host_integrations[]; .type == "fail2ban")' "${specFile}" >/dev/null; then
        ports=$(jq -r '.host_integrations[] | select(.type == "fail2ban") | .settings.ports | join(",")' "${specFile}") || return 1
        dockerCandidateCompose "${candidate}" run --rm --no-deps net-fail2ban \
            preflight fail2ban "${ports}" >/dev/null || {
            dockerError 'Fail2ban 配置、DOCKER-USER 链或日志前置检查失败'
            return 1
        }
    fi
    if jq -e 'any(.host_integrations[]; .type == "tun")' "${specFile}" >/dev/null; then
        dockerCandidateCompose "${candidate}" run --rm --no-deps net-tun-check \
            preflight tun >/dev/null || {
            dockerError 'TUN 设备或内核前置检查失败'
            return 1
        }
    fi
    if jq -e 'any(.host_integrations[]; .type == "tproxy")' "${specFile}" >/dev/null; then
        port=$(jq -r '.host_integrations[] | select(.type == "tproxy") | .settings.port' "${specFile}") || return 1
        mark=$(jq -r '.host_integrations[] | select(.type == "tproxy") | .settings.mark' "${specFile}") || return 1
        ownership=unowned
        dockerCurrentOwnsHostIntegration tproxy && ownership=owned
        dockerCandidateCompose "${candidate}" run --rm --no-deps net-transparent \
            preflight tproxy "${port}" "${mark}" "${ownership}" >/dev/null || {
            dockerError 'TProxy 转发、路由或防火墙前置检查失败'
            return 1
        }
    fi
}

dockerValidateCandidate() {
    local specFile=$1 candidate=$2 core domain jsonFile image tlsDomains='[]' domains
    while IFS= read -r jsonFile; do
        [[ -s "${jsonFile}" ]] && jq empty "${jsonFile}" >/dev/null 2>&1 || {
            dockerError "候选 JSON 配置无效: ${jsonFile}"
            return 1
        }
    done < <(find "${candidate}/config" -type f -name '*.json' -print)
    [[ -s "${candidate}/compose.json" && -s "${candidate}/deployment.json" ]] &&
        jq empty "${candidate}/compose.json" "${candidate}/deployment.json" 2>/dev/null || {
        dockerError '候选 JSON 配置无效'
        return 1
    }
    dockerDeploymentFileValidate "${candidate}/deployment.json" || {
        dockerError '候选 deployment.json 无效'
        return 1
    }
    dockerCandidateCompose "${candidate}" config --format json >/dev/null || {
        dockerError '候选 Compose 配置校验失败'
        return 1
    }
    dockerValidateHostIntegrations "${specFile}" "${candidate}" || return 1
    while IFS= read -r core; do
        domains=$(dockerCoreTlsDomains "${core}" "${candidate}/config/${core}/config.json") || return 1
        tlsDomains=$(jq -c --argjson domains "${domains}" '. + $domains | unique' <<<"${tlsDomains}") || return 1
        case "${core}" in
        xray)
            dockerCandidateCompose "${candidate}" run --rm --no-deps xray \
                -test -confdir /etc/padm/xray >/dev/null || {
                dockerError 'Xray 候选配置校验失败'
                return 1
            }
            ;;
        sing-box)
            dockerCandidateCompose "${candidate}" run --rm --no-deps sing-box \
                check -D /var/lib/padm/sing-box -c /etc/padm/sing-box/config.json >/dev/null || {
                dockerError 'sing-box 候选配置校验失败'
                return 1
            }
            ;;
        *) return 1 ;;
        esac
    done < <(jq -r '[.core.type, .core.secondary_type] | .[] | select(. != null)' "${specFile}")
    if jq -e '.tls != null' "${specFile}" >/dev/null; then
        domain=$(jq -r '.tls.domain' "${specFile}") || return 1
        tlsDomains=$(jq -c --arg domain "${domain}" '. + [$domain] | unique' <<<"${tlsDomains}") || return 1
    fi
    image=$(jq -r '.images.ops' "${specFile}") || return 1
    while IFS= read -r domain; do
        dockerTlsValidateCandidate "${image}" "${candidate}/secrets/tls" "${domain}" || {
            dockerError 'TLS 证书、私钥或域名校验失败'
            return 1
        }
    done < <(jq -r '.[]' <<<"${tlsDomains}")
    if jq -e '.services | has("nginx")' "${candidate}/compose.json" >/dev/null; then
        dockerCandidateCompose "${candidate}" run --rm --no-deps nginx -t >/dev/null || {
            dockerError 'Nginx 候选配置校验失败'
            return 1
        }
    fi
    if jq -e '.subscription.enabled == true' "${specFile}" >/dev/null; then
        dockerCandidateCompose "${candidate}" run --rm --no-deps subscription \
            subscription --check >/dev/null || {
            dockerError '订阅控制服务候选配置校验失败'
            return 1
        }
    fi
}

dockerBackupConfiguration() {
    local root backup relative source bundlePath prefix=${1:-configure}
    root=$(dockerInstallRoot) || return 1
    [[ "${prefix}" =~ ^[a-z][a-z0-9_-]*$ ]] || return 1
    backup=$(mktemp -d "${root}/backups/${prefix}.XXXXXX") || return 1
    if [[ "${prefix}" == update || "${prefix}" == rollback ]]; then
        bundlePath=$(dockerCurrentBundlePath) || return 1
        printf '%s\n' "${bundlePath#"${root}/"}" >"${backup}/bundle.target" || return 1
    fi
    : >"${backup}/present"
    while IFS= read -r relative; do
        source="${root}/${relative}"
        [[ -e "${source}" || -L "${source}" ]] || continue
        [[ ! -L "${source}" ]] || return 1
        [[ -z "$(find "${source}" -type l -print -quit 2>/dev/null)" ]] || return 1
        mkdir -p -- "${backup}/$(dirname -- "${relative}")" || return 1
        cp -a -- "${source}" "${backup}/${relative}" || return 1
        printf '%s\n' "${relative}" >>"${backup}/present" || return 1
    done <<'EOF'
deployment.json
deployment.previous.json
images.env
compose.json
config/xray
config/sing-box
config/nginx
config/net
config/spec.json
data/subscription
secrets/tls
data/acme
EOF
    chmod -R go-rwx "${backup}" || return 1
    # 备份是宿主 root 的私有快照，运行时属主在恢复后按目录用途重建。
    [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" == "1" ]] || chown -R 0:0 "${backup}" || return 1
    if [[ -e "${backup}/deployment.json" || -L "${backup}/deployment.json" ]]; then
        dockerValidateConfigurationBackup "${backup}" || return 1
    fi
    DOCKER_CONFIG_BACKUP=${backup}
}

dockerUpdateRenderImagesEnv() {
    local source=$1 target=$2 rootValue=$3
    local xray singBox nginx ops net
    [[ -f "${source}" && ! -L "${source}" ]] || return 1
    xray=$(dockerManifestImageReference xray) || return 1
    singBox=$(dockerManifestImageReference sing-box) || return 1
    nginx=$(dockerManifestImageReference nginx) || return 1
    ops=$(dockerManifestImageReference ops) || return 1
    net=$(dockerManifestImageReference net) || return 1
    awk -v xray="${xray}" -v singBox="${singBox}" -v nginx="${nginx}" \
        -v ops="${ops}" -v net="${net}" -v rootValue="${rootValue}" '
      BEGIN { FS = "="; OFS = "=" }
      /^PADM_XRAY_IMAGE=/ { print "PADM_XRAY_IMAGE", xray; seen["xray"] = 1; next }
      /^PADM_SINGBOX_IMAGE=/ { print "PADM_SINGBOX_IMAGE", singBox; seen["sing-box"] = 1; next }
      /^PADM_NGINX_IMAGE=/ { print "PADM_NGINX_IMAGE", nginx; seen["nginx"] = 1; next }
      /^PADM_OPS_IMAGE=/ { print "PADM_OPS_IMAGE", ops; seen["ops"] = 1; next }
      /^PADM_NET_IMAGE=/ { print "PADM_NET_IMAGE", net; seen["net"] = 1; next }
      /^PADM_DOCKER_ROOT=/ { print "PADM_DOCKER_ROOT", rootValue; seen["root"] = 1; next }
      /^PADM_NET_ROOT=/ { print "PADM_NET_ROOT", rootValue; seen["netroot"] = 1; next }
      { print }
      END {
        if (!seen["xray"] || !seen["sing-box"] || !seen["nginx"] || !seen["ops"] ||
            !seen["net"] || !seen["root"] || !seen["netroot"]) exit 1
      }
    ' "${source}" >"${target}"
}

dockerCreateUpdateCandidate() {
    local root candidate relative source target version manifestSha previous
    root=$(dockerInstallRoot) || return 1
    DOCKER_CONFIG_CANDIDATE=
    candidate=$(mktemp -d "${root}/.update.XXXXXX") || return 1
    dockerManagedPathIsSafe "${root}" "${candidate}" || {
        dockerRemoveManagedTree "${root}" "${candidate}" || true
        return 1
    }
    DOCKER_CONFIG_CANDIDATE=${candidate}
    for relative in \
        config/xray config/sing-box config/nginx config/net data/subscription \
        data/xray data/sing-box data/static data/acme \
        data/net/wireguard data/net/fail2ban data/net/transparent \
        secrets/tls secrets/net/wireguard logs/nginx logs/subscription logs/acme; do
        source="${root}/${relative}"
        target="${candidate}/${relative}"
        if [[ -e "${source}" || -L "${source}" ]]; then
            [[ -d "${source}" && ! -L "${source}" ]] || return 1
            mkdir -p -- "$(dirname -- "${target}")" && cp -a -- "${source}" "${target}" || return 1
        else
            mkdir -p -- "${target}" || return 1
        fi
    done
    [[ -f "${root}/compose.json" && ! -L "${root}/compose.json" &&
        -f "${root}/images.env" && ! -L "${root}/images.env" &&
        -f "${root}/deployment.json" && ! -L "${root}/deployment.json" ]] || return 1
    cp -- "${root}/compose.json" "${candidate}/compose.json" || return 1
    dockerUpdateRenderImagesEnv "${root}/images.env" "${candidate}/images.env" "${candidate}" || return 1
    dockerUpdateRenderImagesEnv "${root}/images.env" "${candidate}/images.runtime.env" "${root}" || return 1
    version=$(dockerManifestReleaseVersion) || return 1
    manifestSha=${PADM_DOCKER_MANIFEST_SHA256:-}
    [[ "${manifestSha}" =~ ^[0-9a-f]{64}$ ]] || return 1
    previous=$(jq -r '.manifest.sha256 // empty' "${root}/deployment.json") || return 1
    jq -n --slurpfile deployment "${root}/deployment.json" \
        --arg version "${version}" --arg manifestSha "${manifestSha}" \
        --arg bundleRef "$(jq -er '.release.commit' "${PADM_DOCKER_MANIFEST_FILE}")" \
        --arg identity "${PADM_DOCKER_MANIFEST_SIGNATURE_IDENTITY}" \
        --arg previous "${previous}" \
        --arg xray "$(dockerManifestImageDigest xray)" \
        --arg singBox "$(dockerManifestImageDigest sing-box)" \
        --arg nginx "$(dockerManifestImageDigest nginx)" \
        --arg ops "$(dockerManifestImageDigest ops)" \
        --arg net "$(dockerManifestImageDigest net)" '
      $deployment[0] |
      .padm_version = $version |
      .bundle_version = $bundleRef |
      .manifest = {sha256: $manifestSha, signature_identity: $identity} |
      .previous_manifest_sha256 = (if $previous == "" then null else $previous end) |
      .images.xray.index_digest = $xray |
      .images["sing-box"].index_digest = $singBox |
      .images.nginx.index_digest = $nginx |
      .images.ops.index_digest = $ops |
      .images.net.index_digest = $net
    ' >"${candidate}/deployment.json" || return 1
    if [[ -e "${root}/config/spec.json" || -L "${root}/config/spec.json" ]]; then
        [[ -f "${root}/config/spec.json" && ! -L "${root}/config/spec.json" ]] || return 1
        dockerManagedSpecMatchesDeployment "${root}/config/spec.json" \
            "${root}/deployment.json" "${root}/images.env" || return 1
        jq --argjson inputs "$(dockerManifestConfigurationInputs)" '
          .release = $inputs.release | .images = $inputs.images
        ' "${root}/config/spec.json" >"${candidate}/config/spec.json" || return 1
        dockerConfigureSpecValidate "${candidate}/config/spec.json" &&
            dockerConfigureReleaseValidate "${candidate}/config/spec.json" || return 1
    fi
    dockerTrafficPrepareCandidate "${candidate}" || return 1
    dockerPrepareCandidatePermissions "${candidate}" || return 1
    DOCKER_CONFIG_CANDIDATE=${candidate}
}

dockerValidateUpdateCandidate() {
    local candidate=$1
    dockerDeploymentFileValidate "${candidate}/deployment.json" || return 1
    dockerCandidateCompose "${candidate}" config --format json >/dev/null 2>&1 || return 1
}

dockerRemoveConfigurationTargets() {
    local root relative target
    root=$(dockerInstallRoot) || return 1
    while IFS= read -r relative; do
        target="${root}/${relative}"
        [[ -e "${target}" || -L "${target}" ]] || continue
        [[ ! -L "${target}" ]] || return 1
        if [[ -d "${target}" ]]; then
            dockerRemoveManagedTree "${root}" "${target}" || return 1
        else
            dockerManagedPathIsSafe "${root}" "${target}" || return 1
            rm -f -- "${target}" || return 1
        fi
    done <<'EOF'
deployment.json
deployment.previous.json
images.env
compose.json
config/xray
config/sing-box
config/nginx
config/net
config/spec.json
data/subscription
secrets/tls
data/acme
EOF
}

dockerInstallCandidate() {
    local candidate=$1 backup=$2 root relative source target
    root=$(dockerInstallRoot) || return 1
    DOCKER_CONFIG_SWITCHED=1
    dockerRemoveConfigurationTargets || return 1
    if grep -qxF deployment.json "${backup}/present"; then
        cp -- "${backup}/deployment.json" "${root}/deployment.previous.json" || return 1
        chmod 0640 "${root}/deployment.previous.json" || return 1
    fi
    for relative in config/xray config/sing-box config/nginx config/net data/subscription secrets/tls data/acme; do
        source="${candidate}/${relative}"
        target="${root}/${relative}"
        mkdir -p -- "$(dirname -- "${target}")" || return 1
        mv -- "${source}" "${target}" || return 1
    done
    if [[ -f "${candidate}/config/spec.json" && ! -L "${candidate}/config/spec.json" ]]; then
        mv -- "${candidate}/config/spec.json" "${root}/config/spec.json" || return 1
    fi
    mv -- "${candidate}/compose.json" "${root}/compose.json" || return 1
    mv -- "${candidate}/images.runtime.env" "${root}/images.env" || return 1
    mv -- "${candidate}/deployment.json" "${root}/deployment.json" || return 1
    chmod 0640 "${root}/compose.json" "${root}/images.env" "${root}/deployment.json" || return 1
}

dockerEnsureRuntimeDataPermissions() {
    local root directory
    root=$(dockerInstallRoot) || return 1
    for directory in \
        data/xray data/sing-box data/static data/acme \
        data/net/wireguard data/net/fail2ban data/net/transparent \
        logs/nginx logs/subscription logs/acme; do
        if [[ -e "${root}/${directory}" || -L "${root}/${directory}" ]]; then
            [[ -d "${root}/${directory}" && ! -L "${root}/${directory}" ]] || return 1
        else
            mkdir -p -- "${root}/${directory}" || return 1
        fi
        chmod 0750 "${root}/${directory}" || return 1
    done
    for directory in config data/subscription; do
        [[ -d "${root}/${directory}" && ! -L "${root}/${directory}" ]] || return 1
        [[ -z "$(find "${root}/${directory}" -type l -print -quit)" ]] || return 1
        find "${root}/${directory}" -type d -exec chmod 0750 {} + || return 1
        find "${root}/${directory}" -type f ! -path "${root}/config/spec.json" \
            -exec chmod 0640 {} + || return 1
    done
    if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != "1" ]]; then
        chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" \
            "${root}/data/xray" "${root}/data/sing-box" "${root}/data/acme" || return 1
        find "${root}/config" ! -path "${root}/config/spec.json" \
            -exec chown "0:${PADM_DOCKER_CONTAINER_GID}" {} + || return 1
        chown -R "0:${PADM_DOCKER_CONTAINER_GID}" "${root}/data/static" \
            "${root}/logs/subscription" "${root}/logs/acme" \
            "${root}/data/subscription" || return 1
        chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" \
            "${root}/logs/nginx" || return 1
        chown -R 0:0 "${root}/data/net" || return 1
    fi
    if [[ -e "${root}/config/spec.json" || -L "${root}/config/spec.json" ]]; then
        [[ -f "${root}/config/spec.json" && ! -L "${root}/config/spec.json" ]] || return 1
        chmod 0600 "${root}/config/spec.json" || return 1
        [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" == "1" ]] ||
            chown 0:0 "${root}/config/spec.json" || return 1
    fi
    dockerTlsRuntimePermissions "${root}/secrets/tls"
}

dockerRestoreConfiguration() {
    local root backup=${DOCKER_CONFIG_BACKUP:-} relative core bundleTarget=
    [[ "${DOCKER_CONFIG_SWITCHED:-0}" == "1" && -n "${backup}" ]] || return 0
    root=$(dockerInstallRoot) || return 1
    if [[ -e "${backup}/bundle.target" || -L "${backup}/bundle.target" ]]; then
        [[ -f "${backup}/bundle.target" && ! -L "${backup}/bundle.target" && -O "${backup}/bundle.target" ]] || return 1
        bundleTarget=$(<"${backup}/bundle.target")
        dockerBundlePathForTarget "${bundleTarget}" >/dev/null || return 1
    fi
    # 已配置快照须先验证完整输入，损坏恢复点不能先停止现有服务。
    if [[ -e "${backup}/deployment.json" || -L "${backup}/deployment.json" ]] ||
        grep -qxF deployment.json "${backup}/present"; then
        dockerValidateConfigurationBackup "${backup}" || return 1
    fi
    dockerComposeRun down >/dev/null 2>&1 || true
    dockerRemoveConfigurationTargets || return 1
    while IFS= read -r relative; do
        [[ -e "${backup}/${relative}" ]] || return 1
        mkdir -p -- "${root}/$(dirname -- "${relative}")" || return 1
        cp -a -- "${backup}/${relative}" "${root}/${relative}" || return 1
    done <"${backup}/present"
    [[ -z "${bundleTarget}" ]] || dockerActivateBundle "${bundleTarget}" || return 1
    if [[ -f "${root}/deployment.json" && -f "${root}/compose.json" && -f "${root}/images.env" ]]; then
        if [[ -f "${root}/config/xray/users.base" || -f "${root}/config/sing-box/users.base" ||
            -f "${root}/data/traffic/state.json" ]]; then
            dockerTrafficPrepareCandidate "${root}" || return 1
        fi
        dockerEnsureRuntimeDataPermissions || return 1
        dockerComposeRun up -d --force-recreate --wait --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" >/dev/null 2>&1 || return 1
    else
        dockerTlsRuntimePermissions "${root}/secrets/tls" || return 1
        if [[ -e "${root}/data/acme" || -L "${root}/data/acme" ]]; then
            [[ -d "${root}/data/acme" && ! -L "${root}/data/acme" ]] &&
                [[ -z "$(find "${root}/data/acme" -type l -print -quit)" ]] || return 1
            [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" == "1" ]] ||
                chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" "${root}/data/acme" || return 1
        fi
        dockerTrafficScheduleRemove || return 1
    fi
    dockerRenewalScheduleInstall || return 1
    DOCKER_CONFIG_SWITCHED=0
}

dockerCleanupConfigurationCandidate() {
    local root candidate=${DOCKER_CONFIG_CANDIDATE:-}
    [[ -n "${candidate}" ]] || return 0
    root=$(dockerInstallRoot) || return 1
    if [[ -d "${candidate}" ]]; then
        dockerRemoveManagedTree "${root}" "${candidate}" || return 1
    fi
    DOCKER_CONFIG_CANDIDATE=
}

dockerConfigurationInterrupted() {
    dockerRestoreConfiguration || true
    dockerCleanupConfigurationCandidate || true
    dockerRestoreTlsFiles || true
    dockerCleanupTlsCandidate || true
}

dockerConfigureApply() {
    local sourceSpec=$1 tlsSource=${2:-} acmeSource=${3:-} mode=${4:-configure} specFile candidate backup answer
    case "${mode}" in configure|preview|interactive|confirmed) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
    dockerConfigureSpecValidate "${sourceSpec}" || return "${PADM_DOCKER_RC_STATE}"
    dockerTrafficRuntimeCheck "$(jq -r '[.core.type, .core.secondary_type] | .[] | select(. != null)' "${sourceSpec}")" ||
        return "${PADM_DOCKER_RC_HOST}"
    [[ "${mode}" != configure ]] || dockerTrafficBeforeChange
    dockerCreateConfigurationCandidate || return "${PADM_DOCKER_RC_STATE}"
    candidate=${DOCKER_CONFIG_CANDIDATE}
    specFile="${candidate}/request.json"
    cp -- "${sourceSpec}" "${specFile}" && chmod 0600 "${specFile}" || {
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerConfigureSpecValidate "${specFile}" || {
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerConfigureReleaseValidate "${specFile}" || {
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_MANIFEST}"
    }
    dockerRealityTargetsValidate "${specFile}" || {
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerHostIntegrationInputsValidate "${specFile}" || {
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerConfigurePortsAvailable "${specFile}" || {
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_CONFLICT}"
    }
    if ! dockerGenerateCandidate "${specFile}" "${candidate}" "${tlsSource}" "${acmeSource}" ||
        ! dockerValidateCandidate "${specFile}" "${candidate}"; then
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    fi
    if [[ "${mode}" == preview ]]; then
        printf '候选配置校验通过，预览未提交。\n'
        dockerCleanupConfigurationCandidate || return "${PADM_DOCKER_RC_STATE}"
        return 0
    fi
    if [[ "${mode}" == interactive ]]; then
        dockerSetupRead answer '候选配置已验证，确认提交？[y/N]: ' n || answer=n
        case "${answer}" in
        y|Y|yes|YES) ;;
        *)
            printf '已取消配置编辑。\n'
            dockerCleanupConfigurationCandidate || return "${PADM_DOCKER_RC_STATE}"
            return 0
            ;;
        esac
    fi
    if [[ "${mode}" != configure ]]; then
        # 确认后才采集旧核心，并以最新额度状态重渲染候选账号。
        dockerTrafficBeforeChange
        dockerTrafficPrepareCandidate "${candidate}" &&
            dockerPrepareCandidatePermissions "${candidate}" &&
            dockerValidateCandidate "${specFile}" "${candidate}" || {
            dockerCleanupConfigurationCandidate || true
            return "${PADM_DOCKER_RC_STATE}"
        }
    fi
    dockerBackupConfiguration || {
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    }
    backup=${DOCKER_CONFIG_BACKUP}
    if ! dockerInstallCandidate "${candidate}" "${backup}" ||
        ! dockerEnsureRuntimeDataPermissions ||
        ! dockerComposeRun up -d --force-recreate --wait --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" ||
        ! dockerTrafficScheduleInstall ||
        ! dockerRenewalScheduleInstall; then
        dockerError '候选部署启动或健康检查失败，正在恢复旧配置'
        if ! dockerRestoreConfiguration; then
            dockerError "旧配置恢复失败，请检查备份: ${backup}"
        fi
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_COMPOSE}"
    fi
    DOCKER_CONFIG_SWITCHED=0
    dockerCleanupConfigurationCandidate || return "${PADM_DOCKER_RC_STATE}"
    printf 'Docker 配置已提交，回滚快照: %s\n' "${backup}"
}

dockerConfigureCommand() {
    local specFile= manifest= bundle= controlBundle=
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --spec)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* ]] || return "${PADM_DOCKER_RC_USAGE}"
            specFile=$2
            shift 2
            ;;
        --manifest|--bundle|--control-bundle)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* ]] || return "${PADM_DOCKER_RC_USAGE}"
            case "$1" in
            --manifest) manifest=$2 ;;
            --bundle) bundle=$2 ;;
            --control-bundle) controlBundle=$2 ;;
            esac
            shift 2
            ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    [[ -n "${specFile}" ]] || {
        dockerError 'configure 需要 --spec <JSON 文件>'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    specFile=$(cd -- "$(dirname -- "${specFile}")" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$(basename -- "${specFile}")") ||
        return "${PADM_DOCKER_RC_USAGE}"
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    dockerConfigureSpecValidate "${specFile}" || return "${PADM_DOCKER_RC_STATE}"
    dockerConfigureReleasePrepare "${manifest}" "${bundle}" "${controlBundle}" || return $?
    dockerConfigureReleaseValidate "${specFile}" || return "${PADM_DOCKER_RC_MANIFEST}"
    dockerConfigureApply "${specFile}"
}

dockerDomainIsValid() {
    jq -en --arg value "$1" '
      $value | test("^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z]{2,63}$")
    ' >/dev/null 2>&1
}

dockerEmailIsValid() {
    local regex=$'^[A-Za-z0-9.!#$%&\'*+/=?^_\x60{|}~-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,63}$'
    [[ "$1" =~ ${regex} ]]
}

dockerImageReferenceIsValid() {
    [[ "$1" =~ ^[a-z0-9][a-z0-9._/:@-]*:[A-Za-z0-9._-]+@sha256:[a-f0-9]{64}$ ]]
}

dockerResolveOpsImage() {
    local requested=${1:-} root value count
    root=$(dockerInstallRoot) || return 1
    dockerTrafficSafePath "${root}" "${root}/deployment.json" &&
        dockerTrafficSafePath "${root}" "${root}/config/spec.json" &&
        dockerTrafficSafePath "${root}" "${root}/images.env" || return 1
    if [[ -n "${requested}" && ! -e "${root}/deployment.json" ]]; then
        dockerImageReferenceIsValid "${requested}" || return 1
        printf '%s\n' "${requested}"
        return 0
    fi
    [[ -f "${root}/images.env" && ! -L "${root}/images.env" ]] || return 1
    count=$(grep -c '^PADM_OPS_IMAGE=' "${root}/images.env" 2>/dev/null || true)
    [[ "${count}" == "1" ]] || return 1
    value=$(sed -n 's/^PADM_OPS_IMAGE=//p' "${root}/images.env") || return 1
    dockerImageReferenceIsValid "${value}" || return 1
    [[ -z "${requested}" || "${requested}" == "${value}" ]] || return 1
    if [[ -e "${root}/deployment.json" ]]; then
        padmDockerDeploymentIdentityValid "${root}/deployment.json" &&
            jq -e --arg digest "${value##*@}" '.images.ops.index_digest == $digest' \
                "${root}/deployment.json" >/dev/null || return 1
        if [[ -e "${root}/config/spec.json" ]]; then
            dockerManagedSpecMatchesDeployment "${root}/config/spec.json" \
                "${root}/deployment.json" "${root}/images.env" || return 1
        fi
    fi
    printf '%s\n' "${value}"
}

dockerResolveRegularFile() {
    local path=$1 resolved
    [[ -f "${path}" && ! -L "${path}" ]] || return 1
    resolved=$(cd -- "$(dirname -- "${path}")" 2>/dev/null &&
        printf '%s/%s\n' "$(pwd -P)" "$(basename -- "${path}")") || return 1
    [[ -f "${resolved}" && ! -L "${resolved}" ]] || return 1
    printf '%s\n' "${resolved}"
}

dockerPrivateFileIsRestricted() {
    local path=$1 mode
    mode=$(stat --format=%a -- "${path}" 2>/dev/null) || return 1
    [[ "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
    (( (8#${mode} & 077) == 0 ))
}

dockerCreateTlsCandidate() {
    local root candidate
    root=$(dockerInstallRoot) || return 1
    candidate=$(mktemp -d "${root}/.tls.XXXXXX") || return 1
    DOCKER_TLS_CANDIDATE=${candidate}
    dockerManagedPathIsSafe "${root}" "${candidate}" || return 1
    chmod 0750 "${candidate}" || return 1
    if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != "1" ]]; then
        chown "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" "${candidate}" || return 1
    fi
    DOCKER_TLS_BACKUP=
    DOCKER_TLS_SWITCHED=0
}

dockerCleanupTlsCandidate() {
    local root candidate=${DOCKER_TLS_CANDIDATE:-}
    [[ -n "${candidate}" ]] || return 0
    root=$(dockerInstallRoot) || return 1
    [[ ! -d "${candidate}" ]] || dockerRemoveManagedTree "${root}" "${candidate}" || return 1
    DOCKER_TLS_CANDIDATE=
}

dockerTlsValidateCandidate() {
    local image=$1 candidate=$2 domain=$3
    docker run --rm --read-only --cap-drop ALL \
        --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,nodev,size=8m \
        --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
        --volume "${candidate}:/candidate:ro" --entrypoint python3 "${image}" -c '
import ssl
import subprocess
import sys
import time

path = sys.argv[1]
text = subprocess.run(
    ["openssl", "x509", "-in", path, "-noout", "-startdate", "-enddate"],
    check=True, capture_output=True, text=True,
).stdout.splitlines()
values = {}
for line in text:
    name, value = line.split("=", 1)
    values[name] = ssl.cert_time_to_seconds(value)
now = time.time()
if not (values["notBefore"] <= now < values["notAfter"]):
    raise SystemExit(1)
' "/candidate/${domain}.crt" >/dev/null || {
        dockerError '候选证书尚未生效或已过期'
        return 1
    }
    docker run --rm --read-only --cap-drop ALL \
        --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,nodev,size=8m \
        --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
        --volume "${candidate}:/candidate:ro" "${image}" tls-check \
        "/candidate/${domain}.crt" "/candidate/${domain}.key" "${domain}" >/dev/null || {
        dockerError '候选证书、私钥或域名校验失败'
        return 1
    }
}

dockerCoreTlsDomains() {
    local core=$1 config=$2
    [[ "${core}" == xray || "${core}" == sing-box ]] &&
        [[ -f "${config}" && ! -L "${config}" ]] || return 1
    jq -ces --arg core "${core}" '
      def domain: type == "string" and test("^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z]{2,63}$");
      def pair:
        if (.cert | type) != "string" or (.key | type) != "string" then
          error("核心 TLS 必须使用受管文件")
        else
          . as $pair |
          ($pair.cert | ltrimstr("/etc/padm/secrets/tls/") | rtrimstr(".crt")) as $d |
          if ($d | domain) and
            $pair.cert == ("/etc/padm/secrets/tls/" + $d + ".crt") and
            $pair.key == ("/etc/padm/secrets/tls/" + $d + ".key") then $d
          else error("核心 TLS 证书和私钥必须属于同一受管域名") end
        end;
      if length != 1 or (.[0] | type) != "object" or (.[0].inbounds | type) != "array" then
        error("核心 TLS 输入必须是单个核心配置")
      else .[0] end |
      [if $core == "xray" then
        .inbounds[] | select(.streamSettings.security == "tls") |
        .streamSettings.tlsSettings.certificates |
        if type != "array" or length == 0 then error("Xray TLS 缺少证书") else .[] end |
        select((.usage // "encipherment") == "encipherment") |
        {cert: .certificateFile, key: .keyFile} | pair
       else
        .inbounds[] | select(.tls.enabled == true and .tls.reality.enabled != true) |
        {cert: .tls.certificate_path, key: .tls.key_path} | pair
       end] | unique
    ' "${config}"
}

dockerTlsConsumers() {
    local domain=$1 root core cores domains consumers='[]' image config nginxDomain count imageKey
    root=$(dockerInstallRoot) || return 1
    dockerDomainIsValid "${domain}" &&
        dockerTrafficSafePath "${root}" "${root}/deployment.json" || return 1
    [[ -e "${root}/deployment.json" ]] || { printf '[]\n'; return 0; }
    dockerTrafficSafePath "${root}" "${root}/compose.json" &&
        dockerTrafficSafePath "${root}" "${root}/images.env" &&
        [[ -f "${root}/compose.json" && ! -L "${root}/compose.json" ]] &&
        dockerDeploymentFileValidate "${root}/deployment.json" || return 1
    [[ -f "${root}/images.env" && ! -L "${root}/images.env" ]] || return 1
    count=$(grep -c '^PADM_DOCKER_ROOT=' "${root}/images.env" || true)
    [[ "${count}" == 1 && "$(sed -n 's/^PADM_DOCKER_ROOT=//p' "${root}/images.env")" == "${root}" ]] || return 1
    cores=$(dockerTrafficCore) || return 1
    while IFS= read -r core; do
        config="${root}/config/${core}/config.json"
        jq -e --arg core "${core}" '
          [.services[$core].volumes[]? |
            select(.target == ("/etc/padm/" + $core) or
              (.target | startswith("/etc/padm/" + $core + "/")))] |
          length == 1 and .[0].target == ("/etc/padm/" + $core) and
          .[0].type == "bind" and .[0].read_only == true and
          .[0].source == ("${PADM_DOCKER_ROOT}/config/" + $core)
        ' "${root}/compose.json" >/dev/null || return 1
        dockerTrafficSafePath "${root}" "${config}" &&
            [[ -z "$(find "${root}/config/${core}" ! -type f ! -type d -print -quit)" ]] || return 1
        [[ -z "$(find "${root}/config/${core}" -name '*.json' ! -name config.json -print -quit)" ]] || return 1
        domains=$(dockerCoreTlsDomains "${core}" "${config}") || return 1
        jq -e --arg domain "${domain}" 'index($domain) != null' <<<"${domains}" >/dev/null || continue
        jq -e --arg core "${core}" '.compose.profiles | index("core-" + $core) != null' \
            "${root}/deployment.json" >/dev/null || return 1
        if [[ "${core}" == xray ]]; then
            image='${PADM_XRAY_IMAGE:?PADM_XRAY_IMAGE is required}'
        else
            image='${PADM_SINGBOX_IMAGE:?PADM_SINGBOX_IMAGE is required}'
        fi
        jq -e --arg core "${core}" --arg image "${image}" '
          .services[$core] |
          .image == $image and (.profiles | index("core-" + $core)) != null and
          ([.volumes[]? | select(.target == "/etc/padm/secrets/tls" or
              (.target | startswith("/etc/padm/secrets/tls/")))] |
            length == 1 and .[0].type == "bind" and .[0].read_only == true and
            .[0].target == "/etc/padm/secrets/tls" and
            .[0].source == "${PADM_DOCKER_ROOT}/secrets/tls")
        ' "${root}/compose.json" >/dev/null || return 1
        consumers=$(jq -c --arg core "${core}" '. + [$core]' <<<"${consumers}") || return 1
    done <<<"${cores}"
    if jq -e '.compose.profiles | index("nginx") != null' "${root}/deployment.json" >/dev/null; then
        jq -e '[.services.nginx.volumes[]? |
          select(.target == "/etc/nginx/http.d" or (.target | startswith("/etc/nginx/http.d/")))] |
          length == 1 and .[0].type == "bind" and .[0].read_only == true and
          .[0].target == "/etc/nginx/http.d" and .[0].source == "${PADM_DOCKER_ROOT}/config/nginx"
        ' "${root}/compose.json" >/dev/null || return 1
        dockerTrafficSafePath "${root}" "${root}/config/nginx/default.conf" || return 1
        [[ -f "${root}/config/nginx/default.conf" && ! -L "${root}/config/nginx/default.conf" ]] || return 1
        [[ -z "$(find "${root}/config/nginx" ! -type f ! -type d -print -quit)" &&
            -z "$(find "${root}/config/nginx" -name '*.conf' ! -name default.conf -print -quit)" ]] || return 1
        nginxDomain=$(awk '
          $1 == "ssl_certificate" {
            if ($2 !~ /^\/etc\/padm\/secrets\/tls\/[A-Za-z0-9.-]+\.crt;$/) bad=1
            else { value=$2; sub(/^\/etc\/padm\/secrets\/tls\//, "", value); sub(/\.crt;$/, "", value);
              if (cert != "" && cert != value) bad=1; cert=value }
          }
          $1 == "ssl_certificate_key" {
            if ($2 !~ /^\/etc\/padm\/secrets\/tls\/[A-Za-z0-9.-]+\.key;$/) bad=1
            else { value=$2; sub(/^\/etc\/padm\/secrets\/tls\//, "", value); sub(/\.key;$/, "", value);
              if (key != "" && key != value) bad=1; key=value }
          }
          END { if (bad || cert == "" || key == "" || cert != key) exit 1; print cert }
        ' "${root}/config/nginx/default.conf") || return 1
        dockerDomainIsValid "${nginxDomain}" || return 1
        if [[ "${domain}" == "${nginxDomain}" ]]; then
            jq -e '.services.nginx |
              .image == "${PADM_NGINX_IMAGE:?PADM_NGINX_IMAGE is required}" and
              (.profiles | index("nginx")) != null and
              ([.volumes[]? | select(.target == "/etc/padm/secrets/tls" or
                  (.target | startswith("/etc/padm/secrets/tls/")))] |
                length == 1 and .[0].type == "bind" and .[0].read_only == true and
                .[0].target == "/etc/padm/secrets/tls" and
                .[0].source == "${PADM_DOCKER_ROOT}/secrets/tls")
            ' "${root}/compose.json" >/dev/null || return 1
            consumers=$(jq -c '. + ["nginx"]' <<<"${consumers}") || return 1
        fi
    fi
    while IFS= read -r core; do
        [[ -n "${core}" ]] || continue
        case "${core}" in
        xray) imageKey=PADM_XRAY_IMAGE ;;
        sing-box) imageKey=PADM_SINGBOX_IMAGE ;;
        nginx) imageKey=PADM_NGINX_IMAGE ;;
        esac
        count=$(grep -c "^${imageKey}=" "${root}/images.env" || true)
        image=$(sed -n "s/^${imageKey}=//p" "${root}/images.env") || return 1
        [[ "${count}" == 1 ]] && dockerImageReferenceIsValid "${image}" &&
            jq -e --arg core "${core}" --arg digest "${image##*@}" \
                '.images[$core].index_digest == $digest' "${root}/deployment.json" >/dev/null || return 1
    done < <(jq -r '.[]' <<<"${consumers}")
    printf '%s\n' "${consumers}"
}

dockerReloadTlsConsumers() {
    local backup=$1 restore=${2:-} service failed=0 consumers
    consumers=$(jq -r '.[]' "${backup}/consumers") || return 1
    [[ -n "${consumers}" ]] || return 0
    # 所有核心先校验，再重建；恢复时不因首个服务失败遗漏其它消费者。
    while IFS= read -r service; do
        case "${service}" in
        xray) dockerComposeRun run --rm --no-deps xray -test -confdir /etc/padm/xray >/dev/null || failed=1 ;;
        sing-box) dockerComposeRun run --rm --no-deps sing-box check -D /var/lib/padm/sing-box -c /etc/padm/sing-box/config.json >/dev/null || failed=1 ;;
        nginx) dockerComposeRun exec -T nginx nginx -e /dev/stderr -t >/dev/null || failed=1 ;;
        *) return 1 ;;
        esac
    done <<<"${consumers}"
    [[ "${failed}" == 0 || "${restore}" == restore ]] || return 1
    while IFS= read -r service; do
        if [[ "${service}" == nginx ]]; then
            dockerComposeRun exec -T nginx nginx -e /dev/stderr -s reload >/dev/null &&
                dockerComposeRun up -d --no-deps --wait --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" nginx >/dev/null || failed=1
        else
            dockerComposeRun up -d --force-recreate --no-deps --wait \
                --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" "${service}" >/dev/null || failed=1
        fi
        [[ "${failed}" == 0 || "${restore}" == restore ]] || return 1
    done <<<"${consumers}"
    [[ "${failed}" == 0 ]]
}

dockerBackupTlsFiles() {
    local domain=$1 candidate=${2:-} root backup extension source consumers
    root=$(dockerInstallRoot) || return 1
    consumers=$(dockerTlsConsumers "${domain}") || return 1
    dockerTrafficSafePath "${root}" "${root}/secrets/tls" &&
        dockerTrafficSafePath "${root}" "${root}/backups" || return 1
    backup=$(mktemp -d "${root}/backups/tls.XXXXXX") || return 1
    : >"${backup}/present"
    printf '%s\n' "${domain}" >"${backup}/domain" || return 1
    printf '%s\n' "${consumers}" >"${backup}/consumers" || return 1
    for extension in crt key; do
        source="${root}/secrets/tls/${domain}.${extension}"
        [[ -e "${source}" || -L "${source}" ]] || continue
        [[ -f "${source}" && ! -L "${source}" ]] || return 1
        cp -- "${source}" "${backup}/${domain}.${extension}" || return 1
        printf '%s\n' "${extension}" >>"${backup}/present" || return 1
    done
    if [[ -n "${candidate}" && -d "${candidate}/acme" ]]; then
        source="${root}/data/acme"
        dockerTrafficSafePath "${root}" "${source}" || return 1
        if [[ -e "${source}" ]]; then
            [[ -d "${source}" &&
                -z "$(find "${source}" ! -type f ! -type d -print -quit)" ]] || return 1
            cp -a -- "${source}" "${backup}/acme" || return 1
            printf 'present\n' >"${backup}/acme.changed" || return 1
        else
            printf 'absent\n' >"${backup}/acme.changed" || return 1
        fi
    fi
    [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" == 1 ]] || chown -R 0:0 "${backup}" || return 1
    chmod -R go-rwx "${backup}" || return 1
    DOCKER_TLS_BACKUP=${backup}
}

dockerCommitTlsCandidate() {
    local candidate=$1 domain=$2 root targetDir extension tempFile
    root=$(dockerInstallRoot) || return 1
    targetDir="${root}/secrets/tls"
    dockerDomainIsValid "${domain}" &&
        dockerTrafficSafePath "${root}" "${candidate}" &&
        dockerTrafficSafePath "${root}" "${targetDir}" || return 1
    [[ -d "${candidate}" && ! -L "${candidate}" &&
        -z "$(find "${candidate}" ! -type f ! -type d -print -quit)" ]] || return 1
    if [[ -e "${targetDir}" || -L "${targetDir}" ]]; then
        [[ -d "${targetDir}" && ! -L "${targetDir}" &&
            -z "$(find "${targetDir}" ! -type f ! -type d -print -quit)" ]] || return 1
    else
        mkdir -- "${targetDir}" || return 1
    fi
    for extension in crt key; do
        tempFile="${targetDir}/.${domain}.${extension}.${BASHPID:-$$}"
        [[ ! -e "${tempFile}" && ! -L "${tempFile}" ]] || return 1
    done
    chmod 0750 "${targetDir}" || return 1
    if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != "1" ]]; then
        chown "0:${PADM_DOCKER_CONTAINER_GID}" "${targetDir}" || return 1
    fi
    dockerBackupTlsFiles "${domain}" "${candidate}" || return 1
    if jq -e 'any(.[]; . == "xray" or . == "sing-box")' "${DOCKER_TLS_BACKUP}/consumers" >/dev/null; then
        dockerTrafficSnapshot || {
            dockerError '核心 TLS 轮换前流量采集失败，已拒绝替换证书'
            return 1
        }
    fi
    DOCKER_TLS_SWITCHED=1
    for extension in crt key; do
        tempFile="${targetDir}/.${domain}.${extension}.${BASHPID:-$$}"
        [[ ! -e "${tempFile}" && ! -L "${tempFile}" ]] || {
            dockerRestoreTlsFiles || true
            return 1
        }
        cp -- "${candidate}/${domain}.${extension}" "${tempFile}" || {
            dockerRestoreTlsFiles || true
            return 1
        }
        if [[ "${extension}" == "key" ]]; then
            chmod 0600 "${tempFile}" || { dockerRestoreTlsFiles || true; return 1; }
        else
            chmod 0640 "${tempFile}" || { dockerRestoreTlsFiles || true; return 1; }
        fi
        if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != "1" ]]; then
            chown "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" "${tempFile}" || {
                dockerRestoreTlsFiles || true
                return 1
            }
        fi
        mv -f -- "${tempFile}" "${targetDir}/${domain}.${extension}" || {
            dockerRestoreTlsFiles || true
            return 1
        }
    done
    dockerTlsRuntimePermissions "${targetDir}" || { dockerRestoreTlsFiles || true; return 1; }
    if [[ -d "${candidate}/acme" ]]; then
        dockerRemoveManagedTree "${root}" "${root}/data/acme" &&
            cp -a -- "${candidate}/acme" "${root}/data/acme" || {
            dockerRestoreTlsFiles || true
            return 1
        }
    fi
    if ! dockerReloadTlsConsumers "${DOCKER_TLS_BACKUP}"; then
        dockerError 'TLS 消费者校验、重载或健康检查失败，正在恢复旧证书与 ACME 状态'
        dockerRestoreTlsFiles || return 1
        return 1
    fi
    DOCKER_TLS_SWITCHED=0
    printf 'TLS 证书已安装，回滚快照: %s\n' "${DOCKER_TLS_BACKUP}"
}

dockerRestoreTlsFiles() {
    local root backup=${DOCKER_TLS_BACKUP:-} domain extension target
    [[ "${DOCKER_TLS_SWITCHED:-0}" == "1" && -n "${backup}" ]] || return 0
    root=$(dockerInstallRoot) || return 1
    dockerTrafficSafePath "${root}" "${backup}" &&
        dockerTrafficSafePath "${root}" "${root}/secrets/tls" &&
        dockerTrafficSafePath "${root}" "${root}/data/acme" || return 1
    [[ "${backup}" == "${root}/backups/tls."* && -d "${backup}" && -O "${backup}" &&
        -z "$(find "${backup}" ! -type f ! -type d -print -quit)" &&
        -f "${backup}/present" && ! -L "${backup}/present" &&
        -f "${backup}/consumers" ]] || return 1
    jq -es 'length == 1 and (.[0] | type == "array" and
      length == (unique | length) and all(.[]; . == "xray" or . == "sing-box" or . == "nginx"))' \
        "${backup}/consumers" >/dev/null || return 1
    [[ -f "${backup}/domain" && ! -L "${backup}/domain" ]] || return 1
    domain=$(<"${backup}/domain")
    dockerDomainIsValid "${domain}" || return 1
    [[ -z "$(grep -vxE 'crt|key' "${backup}/present")" &&
        -z "$(sort "${backup}/present" | uniq -d)" ]] || return 1
    [[ -z "$(find "${root}/secrets/tls" ! -type f ! -type d -print -quit)" ]] || return 1
    # 先检查整份备份，缺失私钥或账户不能触发部分恢复。
    for extension in crt key; do
        target="${root}/secrets/tls/${domain}.${extension}"
        [[ ! -e "${target}" || -f "${target}" ]] && [[ ! -L "${target}" ]] || return 1
        if grep -qxF "${extension}" "${backup}/present"; then
            [[ -f "${backup}/${domain}.${extension}" ]] || return 1
        fi
    done
    if [[ -e "${backup}/acme.changed" ]]; then
        [[ -f "${backup}/acme.changed" ]] || return 1
        case "$(<"${backup}/acme.changed")" in
        present) [[ -d "${backup}/acme" ]] || return 1 ;;
        absent) [[ ! -e "${backup}/acme" ]] || return 1 ;;
        *) return 1 ;;
        esac
    else
        [[ ! -e "${backup}/acme" ]] || return 1
    fi
    if jq -e 'any(.[]; . == "xray" or . == "sing-box")' "${backup}/consumers" >/dev/null; then
        dockerTrafficSnapshot || dockerError 'TLS 恢复前采集失败，已保留累计流量并继续恢复服务'
    fi
    for extension in crt key; do
        target="${root}/secrets/tls/${domain}.${extension}"
        [[ ! -L "${target}" ]] || return 1
        rm -f -- "${root}/secrets/tls/.${domain}.${extension}.${BASHPID:-$$}" || return 1
        if grep -qxF "${extension}" "${backup}/present"; then
            [[ -f "${backup}/${domain}.${extension}" ]] || return 1
            cp -- "${backup}/${domain}.${extension}" "${target}" || return 1
            if [[ "${extension}" == "key" ]]; then
                chmod 0600 "${target}" || return 1
            else
                chmod 0640 "${target}" || return 1
            fi
            if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != "1" ]]; then
                chown "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" "${target}" || return 1
            fi
        else
            rm -f -- "${target}" || return 1
        fi
    done
    dockerTlsRuntimePermissions "${root}/secrets/tls" || return 1
    if [[ -f "${backup}/acme.changed" ]]; then
        dockerRemoveManagedTree "${root}" "${root}/data/acme" || return 1
        if [[ -d "${backup}/acme" ]]; then
            cp -a -- "${backup}/acme" "${root}/data/acme" || return 1
            if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != 1 ]]; then
                chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" "${root}/data/acme" || return 1
            fi
            find "${root}/data/acme" -type d -exec chmod 0750 {} + &&
                find "${root}/data/acme" -type f -exec chmod 0600 {} + || return 1
        fi
    fi
    dockerReloadTlsConsumers "${backup}" restore || return 1
    DOCKER_TLS_SWITCHED=0
}

dockerTlsValidateCommand() {
    local domain= root image
    [[ "$#" -eq 2 && "$1" == --domain ]] || return "${PADM_DOCKER_RC_USAGE}"
    domain=$2
    dockerDomainIsValid "${domain}" || return "${PADM_DOCKER_RC_USAGE}"
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    image=$(dockerResolveOpsImage) || return "${PADM_DOCKER_RC_STATE}"
    dockerTrafficSafePath "${root}" "${root}/secrets/tls" &&
        [[ -f "${root}/secrets/tls/${domain}.crt" && ! -L "${root}/secrets/tls/${domain}.crt" &&
            -f "${root}/secrets/tls/${domain}.key" && ! -L "${root}/secrets/tls/${domain}.key" ]] &&
        dockerTlsValidateCandidate "${image}" "${root}/secrets/tls" "${domain}" ||
        return "${PADM_DOCKER_RC_STATE}"
    printf '受管 TLS 证书校验通过: %s\n' "${domain}"
}

dockerTlsInstallCommand() {
    local domain= certFile= keyFile= requestedImage= image candidate
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --domain) [[ "$#" -ge 2 ]] || return "${PADM_DOCKER_RC_USAGE}"; domain=$2; shift 2 ;;
        --cert) [[ "$#" -ge 2 ]] || return "${PADM_DOCKER_RC_USAGE}"; certFile=$2; shift 2 ;;
        --key) [[ "$#" -ge 2 ]] || return "${PADM_DOCKER_RC_USAGE}"; keyFile=$2; shift 2 ;;
        --ops-image) [[ "$#" -ge 2 ]] || return "${PADM_DOCKER_RC_USAGE}"; requestedImage=$2; shift 2 ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    dockerDomainIsValid "${domain}" && [[ -n "${certFile}" && -n "${keyFile}" ]] || {
        dockerError 'tls install 需要合法的 --domain、--cert 和 --key'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    certFile=$(dockerResolveRegularFile "${certFile}") || return "${PADM_DOCKER_RC_USAGE}"
    keyFile=$(dockerResolveRegularFile "${keyFile}") || return "${PADM_DOCKER_RC_USAGE}"
    dockerPrivateFileIsRestricted "${keyFile}" || {
        dockerError '私钥文件不能允许 group/other 读取'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    image=$(dockerResolveOpsImage "${requestedImage}") || {
        dockerError '缺少有效的 ops tag@digest 镜像引用'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerCreateTlsCandidate || return "${PADM_DOCKER_RC_STATE}"
    candidate=${DOCKER_TLS_CANDIDATE}
    cp -- "${certFile}" "${candidate}/${domain}.crt" &&
        cp -- "${keyFile}" "${candidate}/${domain}.key" || return "${PADM_DOCKER_RC_STATE}"
    chmod 0640 "${candidate}/${domain}.crt" && chmod 0600 "${candidate}/${domain}.key" ||
        return "${PADM_DOCKER_RC_STATE}"
    if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != "1" ]]; then
        chown "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" \
            "${candidate}/${domain}.crt" "${candidate}/${domain}.key" || return "${PADM_DOCKER_RC_STATE}"
    fi
    if ! dockerTlsValidateCandidate "${image}" "${candidate}" "${domain}" ||
        ! dockerCommitTlsCandidate "${candidate}" "${domain}"; then
        dockerCleanupTlsCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    fi
    dockerCleanupTlsCandidate || return "${PADM_DOCKER_RC_STATE}"
}

dockerAcmeRun() {
    local image=$1 credentials=$2 acmeData=$3 output=$4
    shift 4
    dockerRenewalCredentialsValidate "${credentials}" || return 1
    docker run --rm -i --read-only --cap-drop ALL \
        --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,nodev,size=16m \
        --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
        --volume "${acmeData}:/var/lib/padm/acme" \
        --volume "${output}:/var/lib/padm/tls-output" \
        --entrypoint python3 "${image}" -c '
import os
import re
import sys

env = os.environ.copy()
seen = set()
for line in sys.stdin.read().splitlines():
    if not line or line.startswith("#"):
        continue
    name, value = line.split("=", 1)
    if (not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name) or "\0" in value
        or name in seen or name in {
            "PATH", "HOME", "ENV", "BASH_ENV", "IFS", "SHELLOPTS", "BASHOPTS",
            "CDPATH", "GLOBIGNORE", "PS4", "DEBUG", "TMPDIR"}
        or name.startswith(("PYTHON", "LD_", "PADM_", "LE_", "ACME_", "Le_"))):
        raise SystemExit(1)
    seen.add(name)
    env[name] = value
os.execvpe("/opt/acme/acme.sh",
    ["acme.sh", "--home", "/var/lib/padm/acme", *sys.argv[1:]], env)
' "$@" <"${credentials}"
}

dockerAcmeCommand() {
    local action=${1:-} domain= email= provider= credentials= requestedImage=
    local image status
    [[ "$#" -gt 0 ]] && shift
    [[ "${action}" == "issue" || "${action}" == "renew" ]] || return "${PADM_DOCKER_RC_USAGE}"
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --domain) [[ "$#" -ge 2 ]] || return "${PADM_DOCKER_RC_USAGE}"; domain=$2; shift 2 ;;
        --email) [[ "$#" -ge 2 ]] || return "${PADM_DOCKER_RC_USAGE}"; email=$2; shift 2 ;;
        --dns) [[ "$#" -ge 2 ]] || return "${PADM_DOCKER_RC_USAGE}"; provider=$2; shift 2 ;;
        --credentials) [[ "$#" -ge 2 ]] || return "${PADM_DOCKER_RC_USAGE}"; credentials=$2; shift 2 ;;
        --ops-image) [[ "$#" -ge 2 ]] || return "${PADM_DOCKER_RC_USAGE}"; requestedImage=$2; shift 2 ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    dockerDomainIsValid "${domain}" && dockerEmailIsValid "${email}" &&
        [[ "${provider}" =~ ^dns_[a-z0-9_]+$ ]] && [[ -n "${credentials}" ]] || {
        dockerError 'acme 仅支持合法 domain/email 的 DNS-01，provider 必须为 dns_*'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    credentials=$(dockerResolveRegularFile "${credentials}") || return "${PADM_DOCKER_RC_USAGE}"
    dockerRenewalCredentialsValidate "${credentials}" || {
        dockerError 'DNS 凭据必须为仅持有者读取的 NAME=value 文件，不得改写工具运行环境'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    image=$(dockerResolveOpsImage "${requestedImage}") || {
        dockerError '缺少有效的 ops tag@digest 镜像引用'
        return "${PADM_DOCKER_RC_STATE}"
    }
    if dockerAcmeApply "${action}" "${domain}" "${email}" "${provider}" "${credentials}" "${image}"; then
        return 0
    else
        status=$?
        [[ "${status}" != 2 ]] || { printf '证书未到续期时间: %s\n' "${domain}"; return 0; }
        return "${status}"
    fi
}

dockerAcmeApply() {
    local action=$1 domain=$2 email=$3 provider=$4 credentials=$5 image=$6
    local root candidate status
    local -a keyArgs=()
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${action}" == renew &&
        -f "${root}/data/acme/${domain}_ecc/${domain}.conf" &&
        ! -f "${root}/data/acme/${domain}/${domain}.conf" ]]; then
        keyArgs=(--ecc)
    fi
    dockerCreateTlsCandidate || return "${PADM_DOCKER_RC_STATE}"
    candidate=${DOCKER_TLS_CANDIDATE}
    # ACME 工具只能改候选账户，校验和重载失败时旧账户与其它域名不受影响。
    dockerTrafficSafePath "${root}" "${root}/data/acme" || return "${PADM_DOCKER_RC_STATE}"
    mkdir -- "${candidate}/acme" || return "${PADM_DOCKER_RC_STATE}"
    if [[ -e "${root}/data/acme" ]]; then
        [[ -d "${root}/data/acme" &&
            -z "$(find "${root}/data/acme" ! -type f ! -type d -print -quit)" ]] ||
            return "${PADM_DOCKER_RC_STATE}"
        cp -a -- "${root}/data/acme/." "${candidate}/acme/" || return "${PADM_DOCKER_RC_STATE}"
    fi
    find "${candidate}/acme" -type d -exec chmod 0750 {} + &&
        find "${candidate}/acme" -type f -exec chmod 0600 {} + || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != 1 ]]; then
        chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" "${candidate}/acme" ||
            return "${PADM_DOCKER_RC_STATE}"
    fi
    if [[ "${action}" == "issue" ]]; then
        dockerAcmeRun "${image}" "${credentials}" "${candidate}/acme" "${candidate}" \
            --issue --dns "${provider}" -d "${domain}" --accountemail "${email}" >/dev/null 2>&1 || {
            dockerError '候选 DNS-01 申请失败，现有证书和 ACME 账户未修改'
            dockerCleanupTlsCandidate || true
            return "${PADM_DOCKER_RC_STATE}"
        }
    else
        if dockerAcmeRun "${image}" "${credentials}" "${candidate}/acme" "${candidate}" \
            --renew -d "${domain}" "${keyArgs[@]}" >/dev/null 2>&1; then
            status=0
        else
            status=$?
        fi
        if [[ "${status}" != 0 ]]; then
            dockerCleanupTlsCandidate || return "${PADM_DOCKER_RC_STATE}"
            [[ "${status}" != 2 ]] || return 2
            dockerError '候选 DNS-01 续期失败，现有证书和 ACME 账户未修改'
            return "${PADM_DOCKER_RC_STATE}"
        fi
    fi
    dockerAcmeRun "${image}" "${credentials}" "${candidate}/acme" "${candidate}" \
        --install-cert -d "${domain}" "${keyArgs[@]}" \
        --fullchain-file "/var/lib/padm/tls-output/${domain}.crt" \
        --key-file "/var/lib/padm/tls-output/${domain}.key" >/dev/null 2>&1 || {
        dockerError '候选证书导出失败，现有证书和 ACME 账户未修改'
        dockerCleanupTlsCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    }
    # acme.sh 可能创建宽权限文件，提交前恢复最小账户读取权限。
    [[ -z "$(find "${candidate}/acme" ! -type f ! -type d -print -quit)" ]] &&
        find "${candidate}/acme" -type d -exec chmod 0750 {} + &&
        find "${candidate}/acme" -type f -exec chmod 0600 {} + || return "${PADM_DOCKER_RC_STATE}"
    if ! dockerTlsValidateCandidate "${image}" "${candidate}" "${domain}" ||
        ! dockerCommitTlsCandidate "${candidate}" "${domain}"; then
        dockerCleanupTlsCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    fi
    dockerCleanupTlsCandidate || return "${PADM_DOCKER_RC_STATE}"
}

dockerValidateInstalledCommand() {
    local root core integration port mark ports
    [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerComposeFile >/dev/null || return "${PADM_DOCKER_RC_COMPOSE}"
    dockerComposeRun config --format json >/dev/null || return "${PADM_DOCKER_RC_COMPOSE}"
    while IFS= read -r core; do
        case "${core}" in
        xray)
            dockerComposeRun run --rm --no-deps xray -test -confdir /etc/padm/xray >/dev/null ||
                return "${PADM_DOCKER_RC_STATE}"
            ;;
        sing-box)
            dockerComposeRun run --rm --no-deps sing-box \
                check -D /var/lib/padm/sing-box -c /etc/padm/sing-box/config.json >/dev/null ||
                return "${PADM_DOCKER_RC_STATE}"
            ;;
        *) return "${PADM_DOCKER_RC_STATE}" ;;
        esac
    done < <(jq -r '[.core.type, .core.secondary_type] | .[] | select(. != null)' "${root}/deployment.json")
    if jq -e '.compose.profiles | index("nginx") != null' "${root}/deployment.json" >/dev/null; then
        dockerComposeRun run --rm --no-deps nginx -t >/dev/null || return "${PADM_DOCKER_RC_STATE}"
    fi
    if jq -e '.compose.profiles | index("subscription") != null' "${root}/deployment.json" >/dev/null; then
        dockerComposeRun run --rm --no-deps subscription subscription --check >/dev/null ||
            return "${PADM_DOCKER_RC_STATE}"
    fi
    while IFS= read -r integration; do
        case "${integration}" in
        wireguard)
            dockerComposeRun run --rm --no-deps net-wireguard \
                preflight wireguard /etc/wireguard/wg-padm.conf wg-padm owned >/dev/null ||
                return "${PADM_DOCKER_RC_STATE}"
            ;;
        fail2ban)
            ports=$(jq -r '.host_integrations[] | select(.type == "fail2ban") | .settings.ports | join(",")' \
                "${root}/deployment.json") || return "${PADM_DOCKER_RC_STATE}"
            dockerComposeRun run --rm --no-deps net-fail2ban preflight fail2ban "${ports}" >/dev/null ||
                return "${PADM_DOCKER_RC_STATE}"
            ;;
        tun)
            dockerComposeRun run --rm --no-deps net-tun-check preflight tun >/dev/null ||
                return "${PADM_DOCKER_RC_STATE}"
            ;;
        tproxy)
            port=$(jq -r '.host_integrations[] | select(.type == "tproxy") | .settings.port' \
                "${root}/deployment.json") || return "${PADM_DOCKER_RC_STATE}"
            mark=$(jq -r '.host_integrations[] | select(.type == "tproxy") | .settings.mark' \
                "${root}/deployment.json") || return "${PADM_DOCKER_RC_STATE}"
            dockerComposeRun run --rm --no-deps net-transparent \
                preflight tproxy "${port}" "${mark}" owned >/dev/null ||
                return "${PADM_DOCKER_RC_STATE}"
            ;;
        *) return "${PADM_DOCKER_RC_STATE}" ;;
        esac
    done < <(jq -r '.host_integrations[].type' "${root}/deployment.json")
    printf 'Docker 部署配置校验通过\n'
}
