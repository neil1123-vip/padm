#!/usr/bin/env bash

if [[ "${PADM_DOCKER_SERVICES_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_SERVICES_LOADED=1

readonly PADM_DOCKER_CONTAINER_UID=10001
readonly PADM_DOCKER_CONTAINER_GID=10001
readonly PADM_DOCKER_WS_BACKEND_PORT=31297
readonly PADM_DOCKER_NGINX_TLS_PORT=8443
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
    jq -e --slurpfile matrix "${matrixFile}" '
      def exact($keys): type == "object" and ((keys_unsorted | sort) == ($keys | sort));
      def port: type == "number" and floor == . and . >= 1 and . <= 65535;
      def hostname: type == "string" and test("^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.)+[A-Za-z]{2,63}$");
      def ipv4: type == "string" and (split(".") as $parts |
        ($parts | length) == 4 and all($parts[]; test("^[0-9]{1,3}$") and (tonumber <= 255)));
      def ipv6: type == "string" and contains(":") and test("^[A-Fa-f0-9:]+$");
      def server: hostname or ipv4 or ipv6;
      def uuid: type == "string" and test("^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$");
      def name: type == "string" and test("^[A-Za-z0-9._~@+=:-]{1,64}$");
      def families: type == "array" and length >= 1 and length <= 2 and
        (unique | length) == length and all(.[]; . == "ipv4" or . == "ipv6");
      def image: type == "string" and test("^[a-z0-9][a-z0-9._/:@-]*:[A-Za-z0-9._-]+@sha256:[a-f0-9]{64}$");
      def safe_names($max): type == "array" and length <= $max and
        (unique | length) == length and all(.[]; type == "string" and test("^[A-Za-z0-9._:/-]{1,128}$"));
      def protocol_base: (.server | server) and (.public_port | port) and
        (.address_families | families) and (.name | name) and (.uuid | uuid);
      . as $request |
      ($matrix[0]) as $features |
      exact(["schema_version", "release", "core", "tls", "subscription", "images", "host_integrations"]) and
      .schema_version == 1 and
      (.release | exact(["version", "manifest_sha256", "signature_identity"]) and
        (.version | type == "string" and length > 0) and
        (.manifest_sha256 | test("^[a-f0-9]{64}$")) and
        (.signature_identity | type == "string" and length > 0)) and
      (.core | exact(["type", "protocols"]) and
        (.type == "xray" or .type == "sing-box") and
        (.protocols | type == "array" and length >= 1 and length <= 2 and
          ([.[].id] | unique | length) == length and
          ([.[].public_port] | unique | length) == length)) and
      all(.core.protocols[];
        protocol_base and
        if .id == 1 then
          exact(["id", "server", "public_port", "address_families", "name", "uuid", "reality"]) and
          (.reality | exact(["server_name", "target_host", "target_port", "private_key", "public_key", "short_id"]) and
            (.server_name | hostname) and (.target_host | hostname) and (.target_port | port) and
            (.private_key | test("^[A-Za-z0-9_-]{43}$")) and
            (.public_key | test("^[A-Za-z0-9_-]{43}$")) and
            (.short_id | test("^(?:[a-f0-9]{2}){1,8}$")))
        elif .id == 21 then
          exact(["id", "server", "public_port", "address_families", "name", "uuid", "websocket"]) and
          (.websocket | exact(["domain", "path"]) and (.domain | hostname) and
            (.path | test("^[A-Za-z0-9_-]{8,64}$")))
        else false end) and
      all(.core.protocols[];
        . as $protocol |
        any($features.protocols[];
          .id == $protocol.id and .status == "supported" and
          (.cores | index($request.core.type)) != null)) and
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
      if any(.core.protocols[]; .id == 21) then
        .core.type == "xray" and .tls != null and
        all(.core.protocols[] | select(.id == 21); .websocket.domain == $request.tls.domain)
      else
        .tls == null and .subscription.enabled == false
      end and
      if .subscription.enabled then any(.core.protocols[]; .id == 21) else true end and
      if any(.host_integrations[]; .type == "fail2ban") then
        any(.core.protocols[]; .id == 21) and
        all(.host_integrations[] | select(.type == "fail2ban") | .settings.ports[];
          . as $port | any($request.core.protocols[]; .id == 21 and .public_port == $port))
      else true end and
      if any(.host_integrations[]; .type == "tun") then .core.type == "sing-box" else true end and
      if any(.host_integrations[]; .type == "tun" or .type == "tproxy") then
        all(.core.protocols[]; .id != 21)
      else true end and
      all(.host_integrations[] | select(.type == "tproxy");
        .settings.port as $port | all($request.core.protocols[]; .public_port != $port))
    ' "${specFile}" >/dev/null 2>&1 || {
        dockerError '配置规格不满足阶段 4 schema、支持矩阵或拓扑约束'
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
    jq -e 'any(.core.protocols[]; .id == 1)' "${specFile}" >/dev/null || return 0
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
    done < <(jq -r '.core.protocols[] | select(.id == 1) | [.reality.target_host, (.reality.target_port | tostring), .reality.server_name] | @tsv' "${specFile}")
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
          ([.core.protocols[] | "\(.public_port)|tcp"] +
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
    local specFile=$1 candidate=$2 ports maxRetry findTime banTime
    jq -e 'any(.host_integrations[]; .type == "fail2ban")' "${specFile}" >/dev/null || return 0
    ports=$(jq -r '.host_integrations[] | select(.type == "fail2ban") | .settings.ports | join(",")' "${specFile}") || return 1
    maxRetry=$(jq -r '.host_integrations[] | select(.type == "fail2ban") | .settings.max_retry' "${specFile}") || return 1
    findTime=$(jq -r '.host_integrations[] | select(.type == "fail2ban") | .settings.find_time' "${specFile}") || return 1
    banTime=$(jq -r '.host_integrations[] | select(.type == "fail2ban") | .settings.ban_time' "${specFile}") || return 1
    cat >"${candidate}/config/net/fail2ban/padm-nginx.conf" <<'EOF'
[Definition]
failregex = ^<HOST> - .* "(GET|POST|HEAD) /(?:\.env(?:\.[^/?"]+)?|\.git|wp-login\.php|wp-admin|phpmyadmin|cgi-bin|manager/html|actuator|boaform)(?:/[^ ?"]*)?(?:\?[^ "]*)? HTTP/[^"]*" (40[34]|444)\b
ignoreregex =
EOF
    cat >"${candidate}/config/net/fail2ban/padm-docker-user.conf" <<'EOF'
[INCLUDES]
before = iptables-common.conf

[Definition]
actionstart = <iptables> -N padm-f2b
              <iptables> -I DOCKER-USER 1 -p <protocol> -m conntrack --ctstate NEW --ctorigdstport <port> -j padm-f2b
actionstop = <iptables> -D DOCKER-USER -p <protocol> -m conntrack --ctstate NEW --ctorigdstport <port> -j padm-f2b
             <iptables> -F padm-f2b
             <iptables> -X padm-f2b
actioncheck = <iptables> -n -L padm-f2b
actionban = <iptables> -I padm-f2b 1 -s <ip> -j DROP
actionunban = <iptables> -D padm-f2b -s <ip> -j DROP
EOF
    cat >"${candidate}/config/net/fail2ban/padm.local" <<EOF
[DEFAULT]
backend = polling
bantime = ${banTime}
findtime = ${findTime}
maxretry = ${maxRetry}

[padm-nginx]
enabled = true
filter = padm-nginx
logpath = /var/log/padm/nginx/access.log
port = ${ports}
action = padm-docker-user[port="${ports}", protocol=tcp]
EOF
    cat >"${candidate}/config/net/fail2ban/fail2ban.local" <<'EOF'
[Definition]
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
          $r.core.protocols[] |
          if .id == 1 then {
            listen: "0.0.0.0",
            port: .public_port,
            protocol: "vless",
            tag: "vless-reality",
            settings: {
              clients: [{id: .uuid, email: .name, flow: "xtls-rprx-vision"}],
              decryption: "none"
            },
            streamSettings: {
              network: "tcp",
              security: "reality",
              realitySettings: {
                show: false,
                target: "\(.reality.target_host):\(.reality.target_port)",
                xver: 0,
                serverNames: [.reality.server_name],
                privateKey: .reality.private_key,
                shortIds: ["", .reality.short_id]
              }
            },
            sniffing: {enabled: true, destOverride: ["http", "tls", "quic"], routeOnly: true}
          } elif .id == 21 then {
            listen: "0.0.0.0",
            port: 31297,
            protocol: "vless",
            tag: "vless-ws",
            settings: {
              clients: [{id: .uuid, email: .name}],
              decryption: "none"
            },
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
          $r.core.protocols[] |
          {
            type: "vless",
            tag: "vless-reality",
            listen: "::",
            listen_port: .public_port,
            users: [{uuid: .uuid, name: .name, flow: "xtls-rprx-vision"}],
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
          }
        ] + [
          $r.host_integrations[] |
          if .type == "tun" then {
            type: "tun",
            tag: "tun-in",
            interface_name: .settings.interface,
            address: [.settings.address],
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
    local specFile=$1 candidate=$2 root domain sourceDir
    jq -e '.tls != null' "${specFile}" >/dev/null || return 0
    root=$(dockerInstallRoot) || return 1
    domain=$(jq -r '.tls.domain' "${specFile}") || return 1
    sourceDir="${root}/secrets/tls"
    for extension in crt key; do
        [[ -f "${sourceDir}/${domain}.${extension}" &&
            ! -L "${sourceDir}/${domain}.${extension}" ]] || {
            dockerError "TLS 文件缺失，请先执行 tls install 或 acme issue: ${domain}.${extension}"
            return 1
        }
        cp -- "${sourceDir}/${domain}.${extension}" "${candidate}/secrets/tls/${domain}.${extension}" || return 1
    done
}

dockerGenerateNginxConfig() {
    local specFile=$1 target=$2 domain path token subscriptionEnabled fail2banEnabled
    jq -e 'any(.core.protocols[]; .id == 21)' "${specFile}" >/dev/null || return 0
    domain=$(jq -r '.tls.domain' "${specFile}") || return 1
    path=$(jq -r '.core.protocols[] | select(.id == 21) | .websocket.path' "${specFile}") || return 1
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

server {
    listen ${PADM_DOCKER_NGINX_TLS_PORT} ssl;
    listen [::]:${PADM_DOCKER_NGINX_TLS_PORT} ssl;
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
        proxy_pass http://xray:${PADM_DOCKER_WS_BACKEND_PORT};
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
    printf '}\n' >>"${target}"
}

dockerGenerateSubscription() {
    local specFile=$1 target=$2
    jq -e '.subscription.enabled == true' "${specFile}" >/dev/null || return 0
    jq -r '
      def authority: if contains(":") then "[\(.)]" else . end;
      .core.protocols[] |
      if .id == 1 then
        "vless://\(.uuid)@\(.server | authority):\(.public_port)?encryption=none&flow=xtls-rprx-vision&security=reality&sni=\(.reality.server_name | @uri)&fp=chrome&pbk=\(.reality.public_key | @uri)&sid=\(.reality.short_id)&type=tcp#\(.name | @uri)"
      elif .id == 21 then
        "vless://\(.uuid)@\(.server | authority):\(.public_port)?encryption=none&security=tls&sni=\(.websocket.domain | @uri)&type=ws&host=\(.websocket.domain | @uri)&path=\("/" + .websocket.path + "ws" | @uri)#\(.name | @uri)"
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
    local specFile=$1 target=$2
    jq -n --slurpfile request "${specFile}" '
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
        if . == "ipv4" then "0.0.0.0:\($protocol.public_port):\($containerPort)/tcp"
        else "[::]:\($protocol.public_port):\($containerPort)/tcp" end
      ];
      ($r.core.protocols | map(select(.id == 1))) as $direct |
      ($r.core.protocols | map(select(.id == 21))) as $websocket |
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
      | if $r.core.type == "xray" then
          .services.xray = (defaults + {
            image: "${PADM_XRAY_IMAGE:?PADM_XRAY_IMAGE is required}",
            profiles: ["core-xray"],
            labels: labels("xray"),
            volumes: (mounts("config/xray"; "/etc/padm/xray"; true) +
              mounts("data/xray"; "/var/lib/padm/xray"; false)),
            ports: [$direct[] as $protocol | ports($protocol; $protocol.public_port)[]],
            tmpfs: ["/tmp:rw,noexec,nosuid,nodev,size=16m"],
            healthcheck: {
              test: ["CMD", "/usr/local/bin/xray", "-test", "-confdir", "/etc/padm/xray"],
              interval: "30s", timeout: "5s", start_period: "5s", retries: 3
            }
          })
        else
          .services["sing-box"] = (defaults + {
            image: "${PADM_SINGBOX_IMAGE:?PADM_SINGBOX_IMAGE is required}",
            profiles: ["core-sing-box"],
            labels: labels("sing-box"),
            volumes: (mounts("config/sing-box"; "/etc/padm/sing-box"; true) +
              mounts("data/sing-box"; "/var/lib/padm/sing-box"; false)),
            ports: [$direct[] as $protocol | ports($protocol; $protocol.public_port)[]],
            tmpfs: ["/tmp:rw,noexec,nosuid,nodev,size=16m"],
            healthcheck: {
              test: ["CMD", "/usr/local/bin/sing-box", "check", "-D", "/var/lib/padm/sing-box", "-c", "/etc/padm/sing-box/config.json"],
              interval: "30s", timeout: "5s", start_period: "5s", retries: 3
            }
          })
        end
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
      | if ($websocket | length) == 1 then
          .services.nginx = (defaults + {
            image: "${PADM_NGINX_IMAGE:?PADM_NGINX_IMAGE is required}",
            profiles: ["nginx"],
            labels: labels("nginx"),
            depends_on: {xray: {condition: "service_healthy"}},
            volumes: (mounts("config/nginx"; "/etc/nginx/http.d"; true) +
              mounts("data/static"; "/srv/padm"; true) +
              mounts("secrets"; "/etc/padm/secrets"; true) +
              mounts("logs/nginx"; "/var/log/nginx"; false)),
            ports: [ports($websocket[0]; 8443)[]],
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
            mounts("secrets"; "/etc/padm/secrets"; true)),
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
        ([if $r.core.type == "xray" then "core-xray" else "core-sing-box" end] +
        [if any($r.core.protocols[]; .id == 21) then "nginx" else empty end] +
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
        core: {type: $r.core.type, protocol_ids: [$r.core.protocols[].id]},
        listeners: (
          [
          $r.core.protocols[] |
          {
            service: (if .id == 21 then "nginx" else $r.core.type end),
            public_port: .public_port,
            container_port: (if .id == 21 then 8443 else .public_port end),
            transport: "tcp",
            address_families: .address_families
          }
          ] + [
          $r.host_integrations[] |
          if .type == "wireguard" then {
            service: "net-wireguard", public_port: $wireguardPort,
            container_port: $wireguardPort, transport: "udp",
            address_families: ["ipv4", "ipv6"]
          } elif .type == "tproxy" then
            ({service: $r.core.type, public_port: .settings.port,
              container_port: .settings.port, transport: "tcp", address_families: ["ipv4"]}),
            ({service: $r.core.type, public_port: .settings.port,
              container_port: .settings.port, transport: "udp", address_families: ["ipv4"]})
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
      (.core.protocol_ids | type == "array" and length >= 1 and (unique | length) == length) and
      (.listeners | type == "array" and length >= 1 and
        all(.[]; (.public_port >= 1 and .public_port <= 65535) and
          (.container_port >= 1 and .container_port <= 65535) and
          (.transport == "tcp" or .transport == "udp"))) and
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

dockerPrepareCandidatePermissions() {
    local candidate=$1 directory
    find "${candidate}/config" "${candidate}/data" "${candidate}/logs" -type d -exec chmod 0750 {} + || return 1
    find "${candidate}/config" "${candidate}/data" "${candidate}/logs" -type f -exec chmod 0640 {} + || return 1
    find "${candidate}/secrets" -type d -exec chmod 0750 {} + || return 1
    find "${candidate}/secrets" -type f -exec chmod 0640 {} + || return 1
    chmod 0640 "${candidate}/deployment.json" "${candidate}/compose.json" \
        "${candidate}/images.env" "${candidate}/images.runtime.env" || return 1
    if [[ -f "${candidate}/secrets/net/wireguard/wg-padm.conf" ]]; then
        chmod 0600 "${candidate}/secrets/net/wireguard/wg-padm.conf" || return 1
    fi
    if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != "1" ]]; then
        chown -R "0:${PADM_DOCKER_CONTAINER_GID}" \
            "${candidate}/config" "${candidate}/data/subscription" \
            "${candidate}/logs" "${candidate}/secrets" || return 1
        chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" \
            "${candidate}/logs/nginx" || return 1
        for directory in "${candidate}/data/xray" "${candidate}/data/sing-box" "${candidate}/data/acme"; do
            chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" "${directory}" || return 1
        done
    fi
}

dockerGenerateCandidate() {
    local specFile=$1 candidate=$2 root core token
    root=$(dockerInstallRoot) || return 1
    core=$(jq -r '.core.type' "${specFile}") || return 1
    case "${core}" in
    xray) dockerGenerateXrayConfig "${specFile}" "${candidate}/config/xray/config.json" || return 1 ;;
    sing-box) dockerGenerateSingBoxConfig "${specFile}" "${candidate}/config/sing-box/config.json" || return 1 ;;
    *) return 1 ;;
    esac
    dockerStageHostIntegrationFiles "${specFile}" "${candidate}" || return 1
    dockerGenerateFail2banConfig "${specFile}" "${candidate}" || return 1
    dockerStageTlsFiles "${specFile}" "${candidate}" || return 1
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
    local specFile=$1 candidate=$2 core domain jsonFile
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
    core=$(jq -r '.core.type' "${specFile}") || return 1
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
    esac
    if jq -e '.tls != null' "${specFile}" >/dev/null; then
        domain=$(jq -r '.tls.domain' "${specFile}") || return 1
        dockerCandidateCompose "${candidate}" run --rm --no-deps acme tls-check \
            "/etc/padm/secrets/tls/${domain}.crt" "/etc/padm/secrets/tls/${domain}.key" \
            "${domain}" >/dev/null || {
            dockerError 'TLS 证书、私钥或域名校验失败'
            return 1
        }
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
    local root backup relative source prefix=${1:-configure}
    root=$(dockerInstallRoot) || return 1
    [[ "${prefix}" =~ ^[a-z][a-z0-9_-]*$ ]] || return 1
    backup=$(mktemp -d "${root}/backups/${prefix}.XXXXXX") || return 1
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
data/subscription
EOF
    chmod -R go-rwx "${backup}" || return 1
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
        --arg identity "${PADM_DOCKER_MANIFEST_SIGNATURE_IDENTITY}" \
        --arg previous "${previous}" \
        --arg xray "$(dockerManifestImageDigest xray)" \
        --arg singBox "$(dockerManifestImageDigest sing-box)" \
        --arg nginx "$(dockerManifestImageDigest nginx)" \
        --arg ops "$(dockerManifestImageDigest ops)" \
        --arg net "$(dockerManifestImageDigest net)" '
      $deployment[0] |
      .padm_version = $version |
      .manifest = {sha256: $manifestSha, signature_identity: $identity} |
      .previous_manifest_sha256 = (if $previous == "" then null else $previous end) |
      .images.xray.index_digest = $xray |
      .images["sing-box"].index_digest = $singBox |
      .images.nginx.index_digest = $nginx |
      .images.ops.index_digest = $ops |
      .images.net.index_digest = $net
    ' >"${candidate}/deployment.json" || return 1
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
data/subscription
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
    for relative in config/xray config/sing-box config/nginx config/net data/subscription; do
        source="${candidate}/${relative}"
        target="${root}/${relative}"
        mkdir -p -- "$(dirname -- "${target}")" || return 1
        mv -- "${source}" "${target}" || return 1
    done
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
    if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != "1" ]]; then
        chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" \
            "${root}/data/xray" "${root}/data/sing-box" "${root}/data/acme" || return 1
        chown -R "0:${PADM_DOCKER_CONTAINER_GID}" "${root}/data/static" \
            "${root}/logs/subscription" "${root}/logs/acme" || return 1
        chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" \
            "${root}/logs/nginx" || return 1
        chown -R 0:0 "${root}/data/net" || return 1
    fi
}

dockerRestoreConfiguration() {
    local root backup=${DOCKER_CONFIG_BACKUP:-} relative
    [[ "${DOCKER_CONFIG_SWITCHED:-0}" == "1" && -n "${backup}" ]] || return 0
    root=$(dockerInstallRoot) || return 1
    dockerComposeRun down >/dev/null 2>&1 || true
    dockerRemoveConfigurationTargets || return 1
    while IFS= read -r relative; do
        [[ -e "${backup}/${relative}" ]] || return 1
        mkdir -p -- "${root}/$(dirname -- "${relative}")" || return 1
        cp -a -- "${backup}/${relative}" "${root}/${relative}" || return 1
    done <"${backup}/present"
    DOCKER_CONFIG_SWITCHED=0
    if [[ -f "${root}/deployment.json" && -f "${root}/compose.json" && -f "${root}/images.env" ]]; then
        dockerComposeRun up -d --wait --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" >/dev/null 2>&1 || return 1
    fi
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
    local sourceSpec=$1 specFile candidate backup
    dockerConfigureSpecValidate "${sourceSpec}" || return "${PADM_DOCKER_RC_STATE}"
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
    if ! dockerGenerateCandidate "${specFile}" "${candidate}" ||
        ! dockerValidateCandidate "${specFile}" "${candidate}"; then
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    fi
    dockerBackupConfiguration || {
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    }
    backup=${DOCKER_CONFIG_BACKUP}
    if ! dockerInstallCandidate "${candidate}" "${backup}" ||
        ! dockerEnsureRuntimeDataPermissions ||
        ! dockerComposeRun up -d --wait --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}"; then
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
    local specFile=
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --spec)
            [[ "$#" -ge 2 && -n "$2" ]] || return "${PADM_DOCKER_RC_USAGE}"
            specFile=$2
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
    if [[ -n "${requested}" ]]; then
        dockerImageReferenceIsValid "${requested}" || return 1
        printf '%s\n' "${requested}"
        return 0
    fi
    root=$(dockerInstallRoot) || return 1
    [[ -f "${root}/images.env" && ! -L "${root}/images.env" ]] || return 1
    count=$(grep -c '^PADM_OPS_IMAGE=' "${root}/images.env" 2>/dev/null || true)
    [[ "${count}" == "1" ]] || return 1
    value=$(sed -n 's/^PADM_OPS_IMAGE=//p' "${root}/images.env") || return 1
    dockerImageReferenceIsValid "${value}" || return 1
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
    dockerManagedPathIsSafe "${root}" "${candidate}" || return 1
    chmod 0750 "${candidate}" || return 1
    if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != "1" ]]; then
        chown "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" "${candidate}" || return 1
    fi
    DOCKER_TLS_BACKUP=
    DOCKER_TLS_SWITCHED=0
    DOCKER_TLS_CANDIDATE=${candidate}
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
        --volume "${candidate}:/candidate:ro" "${image}" tls-check \
        "/candidate/${domain}.crt" "/candidate/${domain}.key" "${domain}" >/dev/null || {
        dockerError '候选证书、私钥或域名校验失败'
        return 1
    }
}

dockerBackupTlsFiles() {
    local domain=$1 root backup extension source
    root=$(dockerInstallRoot) || return 1
    backup=$(mktemp -d "${root}/backups/tls.XXXXXX") || return 1
    : >"${backup}/present"
    printf '%s\n' "${domain}" >"${backup}/domain" || return 1
    for extension in crt key; do
        source="${root}/secrets/tls/${domain}.${extension}"
        [[ -e "${source}" || -L "${source}" ]] || continue
        [[ -f "${source}" && ! -L "${source}" ]] || return 1
        cp -- "${source}" "${backup}/${domain}.${extension}" || return 1
        printf '%s\n' "${extension}" >>"${backup}/present" || return 1
    done
    chmod -R go-rwx "${backup}" || return 1
    DOCKER_TLS_BACKUP=${backup}
}

dockerReloadNginxAfterTlsChange() {
    local root enabled
    root=$(dockerInstallRoot) || return 1
    [[ -e "${root}/deployment.json" || -L "${root}/deployment.json" ]] || return 0
    [[ -f "${root}/deployment.json" && ! -L "${root}/deployment.json" ]] || return 1
    jq -e '.compose.profiles | type == "array"' "${root}/deployment.json" >/dev/null 2>&1 || return 1
    enabled=$(jq -r '.compose.profiles | index("nginx") != null' "${root}/deployment.json") || return 1
    [[ "${enabled}" == "true" ]] || return 0
    dockerComposeRun exec -T nginx nginx -s reload >/dev/null &&
        dockerComposeRun up -d --wait --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" >/dev/null
}

dockerCommitTlsCandidate() {
    local candidate=$1 domain=$2 root targetDir extension tempFile
    root=$(dockerInstallRoot) || return 1
    targetDir="${root}/secrets/tls"
    if [[ -e "${targetDir}" || -L "${targetDir}" ]]; then
        [[ -d "${targetDir}" && ! -L "${targetDir}" ]] || return 1
    else
        mkdir -- "${targetDir}" || return 1
    fi
    chmod 0750 "${targetDir}" || return 1
    if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != "1" ]]; then
        chown "0:${PADM_DOCKER_CONTAINER_GID}" "${targetDir}" || return 1
    fi
    dockerBackupTlsFiles "${domain}" || return 1
    DOCKER_TLS_SWITCHED=1
    for extension in crt key; do
        tempFile="${targetDir}/.${domain}.${extension}.${BASHPID:-$$}"
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
    if ! dockerReloadNginxAfterTlsChange; then
        dockerError 'Nginx reload 或健康检查失败，正在恢复旧证书'
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
    [[ -f "${backup}/domain" && ! -L "${backup}/domain" ]] || return 1
    domain=$(<"${backup}/domain")
    dockerDomainIsValid "${domain}" || return 1
    for extension in crt key; do
        target="${root}/secrets/tls/${domain}.${extension}"
        if grep -qxF "${extension}" "${backup}/present"; then
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
    DOCKER_TLS_SWITCHED=0
    dockerReloadNginxAfterTlsChange
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
    docker run --rm --read-only --cap-drop ALL \
        --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,nodev,size=16m \
        --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
        --env-file "${credentials}" \
        --volume "${acmeData}:/var/lib/padm/acme" \
        --volume "${output}:/var/lib/padm/tls-output" \
        "${image}" acme "$@"
}

dockerAcmeCommand() {
    local action=${1:-} domain= email= provider= credentials= requestedImage=
    local root image candidate
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
    dockerPrivateFileIsRestricted "${credentials}" || {
        dockerError 'DNS 凭据文件不能允许 group/other 读取'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    image=$(dockerResolveOpsImage "${requestedImage}") || {
        dockerError '缺少有效的 ops tag@digest 镜像引用'
        return "${PADM_DOCKER_RC_STATE}"
    }
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    mkdir -p -- "${root}/data/acme" || return "${PADM_DOCKER_RC_STATE}"
    chmod 0750 "${root}/data/acme" || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != "1" ]]; then
        chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" "${root}/data/acme" ||
            return "${PADM_DOCKER_RC_STATE}"
    fi
    dockerCreateTlsCandidate || return "${PADM_DOCKER_RC_STATE}"
    candidate=${DOCKER_TLS_CANDIDATE}
    if [[ "${action}" == "issue" ]]; then
        dockerAcmeRun "${image}" "${credentials}" "${root}/data/acme" "${candidate}" \
            --issue --dns "${provider}" -d "${domain}" --accountemail "${email}" || {
            dockerCleanupTlsCandidate || true
            return "${PADM_DOCKER_RC_STATE}"
        }
    else
        dockerAcmeRun "${image}" "${credentials}" "${root}/data/acme" "${candidate}" \
            --renew -d "${domain}" || {
            dockerCleanupTlsCandidate || true
            return "${PADM_DOCKER_RC_STATE}"
        }
    fi
    dockerAcmeRun "${image}" "${credentials}" "${root}/data/acme" "${candidate}" \
        --install-cert -d "${domain}" \
        --fullchain-file "/var/lib/padm/tls-output/${domain}.crt" \
        --key-file "/var/lib/padm/tls-output/${domain}.key" || {
        dockerCleanupTlsCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    }
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
    core=$(jq -er '.core.type' "${root}/deployment.json") || return "${PADM_DOCKER_RC_STATE}"
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
