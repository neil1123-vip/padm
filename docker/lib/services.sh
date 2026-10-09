#!/usr/bin/env bash

# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/traffic.sh" || return 1
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/renewal.sh" || return 1
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/schedule.sh" || return 1
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/geo.sh" || return 1
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/control-sync.sh" || return 1
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/control.sh" || return 1

if [[ "${PADM_DOCKER_SERVICES_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_SERVICES_LOADED=1

readonly PADM_DOCKER_CONTAINER_UID=10001
readonly PADM_DOCKER_CONTAINER_GID=10001
readonly PADM_DOCKER_SUBSCRIPTION_PORT=8081
readonly PADM_DOCKER_REGION_DEFAULT_DOMAINS='["domain:dl.google.com","domain:apple.com","domain:bing.com","domain:microsoft.com","domain:gstatic.com","domain:xn--ngstr-lra8j.com","domain:googleapis.com","domain:googleapis.cn"]'

DOCKER_CONFIG_CANDIDATE=
DOCKER_CONFIG_BACKUP=
DOCKER_CONFIG_SWITCHED=0
DOCKER_CONFIG_STREAM_TRANSITION=0
DOCKER_CONFIG_STREAM_HOST_TRANSITION=0
DOCKER_CONFIG_RELEASE_INPUTS=
DOCKER_TLS_CANDIDATE=
DOCKER_TLS_BACKUP=
DOCKER_TLS_SWITCHED=0
DOCKER_ACME_STOPPED=()
DOCKER_ACME_CONTAINER=
DOCKER_ACME_PORT_PUBLISH=0
DOCKER_ACME_RECOVERY=
DOCKER_ACME_RUNNING=null
DOCKER_ACME_WEBROOT=
DOCKER_ACME_WEBROOT_INODE=

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
      def routing_selector:
        type == "string" and . == ascii_downcase and
        if startswith("full:") or startswith("domain:") then
          (split(":") as $parts | ($parts | length) == 2 and ($parts[1] | hostname))
        elif startswith("keyword:") then test("^keyword:[a-z0-9._-]{1,253}$")
        else test("^geosite:[a-z0-9][a-z0-9_-]{0,63}$") end;
      def ipv4: type == "string" and (split(".") as $parts |
        ($parts | length) == 4 and all($parts[]; test("^[0-9]{1,3}$") and (tonumber <= 255)));
      def ipv6: type == "string" and contains(":") and test("^[A-Fa-f0-9:]+$");
      def routing_ipv4:
        type == "string" and (split(".") as $parts |
          ($parts | length) == 4 and
          all($parts[]; test("^(0|[1-9][0-9]{0,2})$") and tonumber <= 255));
      def routing_ipv6:
        type == "string" and contains(":") and (test(":::") | not) and
        (split("::") as $halves |
          ($halves | length) <= 2 and
          all($halves[]; . == "" or test("^(?:[A-Fa-f0-9]{1,4}:)*[A-Fa-f0-9]{1,4}$")) and
          ([ $halves[] | split(":")[] | select(. != "") ] as $parts |
            if ($halves | length) == 2 then ($parts | length) < 8
            else ($parts | length) == 8 end));
      def routing_ip_selector:
        type == "string" and (. == "geoip:cn" or
          (split("/") as $parts | ($parts | length) <= 2 and
            ($parts[0] | routing_ipv4 or routing_ipv6) and
            if ($parts | length) == 2 then
              ($parts[1] | test("^(0|[1-9][0-9]{0,2})$") and
                tonumber <= (if ($parts[0] | contains(":")) then 128 else 32 end))
            else true end));
      # 宿主后端只接受可路由字面地址或 Docker 宿主别名，不能把容器回环当宿主。
      def host_address:
        . == "host.docker.internal" or
        (type == "string" and
          (if contains(":") then
            test("^(?:[23][A-Fa-f0-9]{3}|[fF][cCdD][A-Fa-f0-9]{2}):") and
            (split("::") as $halves |
              ($halves | length) <= 2 and
              all($halves[]; . == "" or test("^(?:[A-Fa-f0-9]{1,4}:)*[A-Fa-f0-9]{1,4}$")) and
              ([ $halves[] | split(":")[] | select(. != "") ] as $parts |
                all($parts[]; test("^[A-Fa-f0-9]{1,4}$")) and
                (if ($halves | length) == 2 then ($parts | length) < 8
                 else ($parts | length) == 8 end))) and
            (test(":::") | not)
           else
            split(".") as $parts |
            ($parts | length) == 4 and
            all($parts[]; test("^(0|[1-9][0-9]{0,2})$") and tonumber <= 255) and
            ($parts[0] | tonumber) > 0 and ($parts[0] | tonumber) < 224 and
            $parts[0] != "127" and ($parts[0:2] != ["169", "254"])
           end));
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
      exact(["schema_version", "release", "core", "tls", "subscription", "images", "host_integrations"] +
        (if has("reality_stream") then ["reality_stream"] else [] end) +
        (if has("accounts") then ["accounts"] else [] end) +
        (if has("control_sync") then ["control_sync"] else [] end) +
        (if has("control") then ["control"] else [] end) +
        (if has("routing") then ["routing"] else [] end) +
        (if has("site") then ["site"] else [] end)) and
      (.schema_version == 1 or .schema_version == 2 or .schema_version == 3) and
      (if has("routing") then
        .schema_version == 3 and
        (.routing | type == "object" and length >= 1 and
          exact((if has("socks5") then ["socks5"] else [] end) +
            (if has("dns") then ["dns"] else [] end) +
            (if has("hosts") then ["hosts"] else [] end) +
            (if has("direct") then ["direct"] else [] end) +
            (if has("block") then ["block"] else [] end) +
            (if has("block_ips") then ["block_ips"] else [] end) +
            (if has("block_bt") then ["block_bt"] else [] end) +
            (if has("region") then ["region"] else [] end)) and
          (if has("socks5") then
          (.socks5 | exact(["server", "port", "username", "password"] +
              if has("domains") then ["domains"] else [] end) and
            (.server | host_address and . != "host.docker.internal") and
            (.port | port) and
            (.username | type == "string" and length >= 1 and length <= 255 and
              (explode | all(. >= 33 and . <= 126))) and
            (.password | type == "string" and length >= 1 and length <= 255 and
              (explode | all(. >= 33 and . <= 126))) and
            (if has("domains") then
              (.domains | type == "array" and length >= 1 and length <= 256 and
                length == (unique | length) and all(.[]; routing_selector))
             else true end))
           else true end) and
          (if has("dns") then
            (.dns | exact(["server", "port", "domains"]) and
              (.server | host_address and . != "host.docker.internal") and (.port | port) and
              (.domains | type == "array" and length >= 1 and length <= 256 and
                length == (unique | length) and all(.[]; routing_selector)))
           else true end) and
          (if has("hosts") then
            (.hosts | type == "object" and length >= 1 and length <= 256 and
              all(to_entries[]; (.key | hostname and . == ascii_downcase) and
                (.value | host_address and . != "host.docker.internal")))
           else true end) and
          (. as $routing |
            all(["direct", "block"][]; . as $kind |
              ($routing | has($kind) | not) or
              ($routing[$kind] | exact(["domains"]) and
                (.domains | type == "array" and length >= 1 and length <= 256 and
                  length == (unique | length) and all(.[]; routing_selector))))) and
          (if has("block_ips") then
            (.block_ips | exact(["ips"]) and
              (.ips | type == "array" and length >= 1 and length <= 256 and
                length == (unique | length) and all(.[]; routing_ip_selector)))
           else true end) and
          (if has("block_bt") then .block_bt == true else true end) and
          (if has("region") then
            (.region | exact(["mode", "allow_domains"]) and
              (.mode == "both" or .mode == "domain" or .mode == "ip") and
              (.allow_domains | type == "array" and length <= 256 and
                length == (unique | length) and all(.[]; routing_selector)))
           else true end)) and
        all(.host_integrations[]; .type != "tun" and .type != "tproxy")
       else true end) and
      (if has("site") then
        .schema_version == 3 and
        any(.core.protocols[]; .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 or .id == 27 or .id == 29) and
        (.site |
          if .mode == "default" or .mode == "static" then exact(["mode"])
          elif .mode == "redirect" then exact(["mode", "url"]) and
            (.url | type == "string" and length <= 2048 and
              test("^https?://(?:[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?|\\[[A-Fa-f0-9:]+\\])(?::(?:[1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5]))?(?:[/?#][A-Za-z0-9._~:/?#@!&(),%+=-]*)?$"))
          else false end)
       else true end) and
      (if has("accounts") then
        .schema_version == 3 and
        (.accounts | type == "array" and length >= 1 and length <= 256 and
          ([.[].id] | unique | length) == length and
          ([.[].uuid] | unique | length) == length and
          ([.[].password] | unique | length) == length and
          ([.[].shadowsocks_password | select(. != null)] |
            length == (unique | length))) and
        all(.accounts[];
          . as $account |
          exact(["id", "name", "enabled", "uuid", "password", "shadowsocks_password", "listeners"]) and
          (.id | uuid) and (.uuid | uuid) and
          all($request.accounts[]; .id == $account.id or .id != $account.uuid) and
          (.name | type == "string" and length >= 1 and length <= 64) and
          (.enabled | type == "boolean") and
          (.password | type == "string" and test("^[A-Za-z0-9._~@+=:-]{16,128}$")) and
          all($request.core.protocols[];
            .uuid != $account.id and .uuid != $account.uuid and .uuid != $account.password and
            (.id != 30 or (.shadowsocks.user_password != $account.shadowsocks_password and
              .shadowsocks.server_password != $account.shadowsocks_password))) and
          (.listeners | type == "array" and length >= 1 and length <= 16 and
            length == (unique | length) and
            all(.[]; . as $id | any($request.core.protocols[]; .listener_id == $id))) and
          (if any($request.core.protocols[]; .id == 30 and
            (.listener_id as $id | $account.listeners | index($id)) != null) then
            (.shadowsocks_password | ss_key)
           else .shadowsocks_password == null end))
       else true end) and
      (if has("reality_stream") then .schema_version == 3 else true end) and
      (if .reality_stream != null then
        [.core.protocols[] | select(.listener_id == $request.reality_stream.listener_id)] as $realities |
        [.core.protocols[] | select(.listener_id == $request.reality_stream.website_listener_id)] as $websites |
        $realities[0] as $reality | $websites[0] as $website |
          (.reality_stream | .listener_id | type == "string") and
          ($realities | length) == 1 and
        $reality.core == "xray" and ($reality.id == 1 or $reality.id == 2) and
          (if .reality_stream | has("host_website") then
            (.reality_stream | exact(["listener_id", "host_website"]) and
              (.host_website | exact(["domains", "address", "port"] +
                  if has("network_mode") then ["network_mode"] else [] end) and
                (if has("network_mode") then
                  .network_mode == "host" and (.address == "127.0.0.1" or .address == "::1")
                 else (.address | host_address) end) and
                (.port | port) and .port != 443 and .port != 15443 and
                (.domains | type == "array" and length >= 1 and length <= 16 and
                  (unique | length) == length and
                  all(.[]; hostname and . == ascii_downcase)))) and
            all(.reality_stream.host_website.domains[];
              . != ($reality.reality.server_name | ascii_downcase)) and
            all(.core.protocols[]; .public_port != $request.reality_stream.host_website.port) and
            (if .reality_stream.host_website.network_mode == "host" then
              all(.core.protocols[]; .public_port != 15443 or .listener_id == $reality.listener_id)
             else true end) and
            # 同一 SNI 不得同时指向宿主站点和受管 TLS，避免悄悄绕过协议/订阅入口。
            all(.core.protocols[] | select(.id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25);
              ((.websocket // .httpupgrade // .grpc_tls).domain | ascii_downcase) as $domain |
              ($request.reality_stream.host_website.domains | index($domain)) == null)
           else
            (.reality_stream | exact(["listener_id", "website_listener_id"]) and
              (.website_listener_id | type == "string")) and
            ($websites | length) == 1 and
            ($website.id == 21 or $website.id == 22 or $website.id == 23 or $website.id == 24 or $website.id == 25) and
            ($reality.server | ascii_downcase) == ($website.server | ascii_downcase) and
            ($reality.address_families | sort) == ($website.address_families | sort) and
            ($reality.reality.server_name | ascii_downcase) !=
              (($website.websocket // $website.httpupgrade // $website.grpc_tls).domain | ascii_downcase)
           end) and
        .host_integrations == [] and
        all(.core.protocols[]; .public_port != 443 or
          .listener_id == $reality.listener_id or .listener_id == $website.listener_id)
       else true end) and
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
        elif .id == 27 or .id == 29 then
          $request.schema_version == 3 and .core == "xray" and
          exact(["id", "core", "listener_id", "server", "public_port", "address_families", "name", "uuid", "fallback_tls"]) and
          (.fallback_tls | exact(["domain", "http_port", "http2_port"] +
              if has("alpn") then ["alpn"] else [] end) and
            (.domain | hostname) and (.http_port | port) and (.http2_port | port) and
            .http_port != .http2_port and
            (if has("alpn") then
              .alpn == ["h2", "http/1.1"] or .alpn == ["http/1.1", "h2"] or .alpn == ["http/1.1"]
             else true end))
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
        elif .id == 24 or .id == 25 then
          $request.schema_version == 3 and .core == "xray" and
          exact(["id", "core", "listener_id", "server", "public_port", "address_families", "name", "uuid", "grpc_tls"]) and
          (.grpc_tls | exact(["domain", "service_name", "backend_port", "tls_port"]) and
            (.domain | hostname) and
            (.service_name | type == "string" and test("^[A-Za-z0-9_-]{1,64}$")) and
            (.backend_port | port) and (.tls_port | port) and .tls_port != 8080)
        elif .id == 21 or .id == 22 or .id == 23 then
          (if .id == 22 then $request.schema_version == 3 and .core == "xray"
           elif .id == 23 then $request.schema_version == 3 else true end) and
          exact(["id", "server", "public_port", "address_families", "name", "uuid"] +
            (if .id == 23 then ["httpupgrade"] else ["websocket"] end) +
            if $request.schema_version >= 2 then ["listener_id"] else [] end +
            if $request.schema_version == 3 then ["core"] else [] end) and
          ((.websocket // .httpupgrade) | exact(["domain", "path"] +
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
      (.tls == null or (.tls | exact(["domain"] +
          if has("http01") then ["http01"] else [] end) and (.domain | hostname) and
        (if has("http01") then .http01 == true else true end))) and
      (if .tls.http01 == true then
        .schema_version == 3 and
        any(.core.protocols[]; .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 or .id == 27 or .id == 29) and
        all(.core.protocols[]; .public_port != 80 or .id == 3 or .id == 31) and
        all(.host_integrations[] | select(.type == "tproxy"); .settings.port != 80)
       else true end) and
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
      if any(.core.protocols[]; .id == 3 or .id == 4 or .id == 5 or .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 or .id == 27 or .id == 28 or .id == 29 or .id == 31) then
        .tls != null and
        all(.core.protocols[] | select(.id == 21 or .id == 22); (.core // $request.core.type) == "xray") and
        all(.core.protocols[] | select(.id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25); (.websocket // .httpupgrade // .grpc_tls).domain == $request.tls.domain) and
        all(.core.protocols[] | select(.id == 3); .hy2.domain == $request.tls.domain) and
        all(.core.protocols[] | select(.id == 4); .anytls.domain == $request.tls.domain) and
        all(.core.protocols[] | select(.id == 5); .naive.domain == $request.tls.domain) and
        all(.core.protocols[] | select(.id == 27 or .id == 29); .fallback_tls.domain == $request.tls.domain) and
        all(.core.protocols[] | select(.id == 28); .trojan.domain == $request.tls.domain) and
        all(.core.protocols[] | select(.id == 31); .tuic.domain == $request.tls.domain)
      else
        .tls == null and .subscription.enabled == false
      end and
      if .subscription.enabled then any(.core.protocols[]; .id == 21) else true end and
      if any(.core.protocols[]; .id == 3 or .id == 4 or .id == 5 or .id == 22 or .id == 23 or .id == 24 or .id == 25 or .id == 27 or .id == 28 or .id == 29 or .id == 30 or .id == 31) then .host_integrations == [] else true end and
      if any(.host_integrations[]; .type == "fail2ban") then
        any(.core.protocols[]; .id == 21) and
        all(.host_integrations[] | select(.type == "fail2ban") | .settings.ports[];
          . as $port | any($request.core.protocols[]; .id == 21 and .public_port == $port))
      else true end and
      if any(.host_integrations[]; .type == "tun") then .core.type == "sing-box" else true end and
      if any(.host_integrations[]; .type == "tun" or .type == "tproxy") then
        all(.core.protocols[]; .id != 21 and .id != 22 and .id != 23 and .id != 24 and .id != 25)
      else true end and
      all(.host_integrations[] | select(.type == "tproxy");
        .settings.port as $port | all($request.core.protocols[]; .public_port != $port)) and
      # 内部监听按实际核心网络空间检查，公开端口仍在宿主全局唯一。
      (all([.core.type, .core.secondary_type] | map(select(. != null))[];
        . as $core |
        ([$request.core.protocols[] | select((.core // $request.core.type) == $core) |
            if .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 then
              ((.websocket // .httpupgrade // .grpc_tls).backend_port // 31297) else .public_port end] +
          [$request.host_integrations[] | select(.type == "tproxy") | .settings.port] +
          [if $core == "xray" then 10085 else 10087 end]) as $corePorts |
        ($corePorts | unique | length) == ($corePorts | length)) and
      (([.core.protocols[] | select(.id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25) |
          ((.websocket // .httpupgrade // .grpc_tls).tls_port // 8443)] +
        ([.core.protocols[] | select(.id == 27 or .id == 29) |
          [.fallback_tls.http_port, .fallback_tls.http2_port]] | unique | flatten) +
        [8080] + [if .tls.http01 == true then 8088 else empty end] +
        [if .reality_stream != null then 15443 else empty end]) as $tlsPorts |
      ($tlsPorts | unique | length) == ($tlsPorts | length)))
    ' "${specFile}" >/dev/null 2>&1 || {
        dockerError '配置规格不满足阶段 4 schema、支持矩阵或拓扑约束'
        return 1
    }
    dockerControlSyncSpecValidate "${specFile}" || {
        dockerError '被控同步角色、归属或入口映射不合法'
        return 1
    }
    dockerControlSpecValidate "${specFile}" || {
        dockerError '主控角色、监听、授权或版本元数据不合法'
        return 1
    }
}

dockerControlSpecValidate() {
    jq -e '
      def exact($keys): type == "object" and ((keys_unsorted | sort) == ($keys | sort));
      def uuid: type == "string" and
        test("^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$");
      def count: type == "number" and floor == . and . >= 0 and . <= 9007199254740991;
      def private_address: type == "string" and
        (split(".") as $parts | ($parts | length) == 4 and
         all($parts[]; test("^(0|[1-9][0-9]{0,2})$") and tonumber <= 255)) and
        test("^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.)");
      . as $spec |
      if has("control") then
        .schema_version == 3 and (has("control_sync") | not) and
        any(.host_integrations[]; .type == "wireguard") and
        (.control |
          exact(["schema_version","role","node_id","listen","peer","revision","last_digest"]) and
          .schema_version == 1 and .role == "main" and (.node_id | uuid) and
          (.listen | exact(["interface","address","port"]) and .interface == "wg-padm" and
            (.address | private_address) and
            (.port | count and . >= 1024 and . <= 65535)) and
          (.peer | exact(["id","address","enabled","expires_at","token_sha256"]) and
            (.id | uuid) and (.address | private_address) and (.enabled | type == "boolean") and
            (.expires_at | count and . > 0) and
            (.token_sha256 | type == "string" and test("^[a-f0-9]{64}$"))) and
          .node_id != .peer.id and .listen.address != .peer.address and
          (.revision | count) and
          (if .last_digest == null then .revision == 0
           else (.last_digest | type == "string" and test("^[a-f0-9]{64}$")) end)) and
        all(.core.protocols[]; .public_port != $spec.control.listen.port) and
        all(.host_integrations[] | select(.type == "tproxy"); .settings.port != $spec.control.listen.port)
      else true end
    ' "$1" >/dev/null 2>&1
}

dockerControlTransitionValidate() {
    local source=$1 root
    root=$(dockerInstallRoot) || return 1
    dockerTrafficSafePath "${root}" "${root}/config/spec.json" || return 1
    if [[ -f "${root}/config/spec.json" ]] &&
        jq -e 'has("control")' "${root}/config/spec.json" >/dev/null; then
        dockerManagedSpecMatchesDeployment "${root}/config/spec.json" \
            "${root}/deployment.json" "${root}/images.env" || return 1
    fi
    [[ "${DOCKER_CONTROL_TRANSACTION:-0}" != 1 ]] || return 0
    if [[ -f "${root}/config/spec.json" ]]; then
        jq -en --slurpfile current "${root}/config/spec.json" --slurpfile next "${source}" \
            '$current[0].control == $next[0].control' >/dev/null 2>&1 && return 0
    else
        jq -e 'has("control") | not' "${source}" >/dev/null 2>&1 && return 0
    fi
    dockerError '主控身份、监听、授权和发布元数据只能通过控制事务修改'
    return 1
}

dockerControlPlan() {
    local directory=$1 image=$2
    shift 2
    dockerRealityProbeRun 30 --user 0:0 --network none \
        --tmpfs /tmp:rw,noexec,nosuid,nodev,size=8m \
        --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
        --mount "type=bind,src=${directory},dst=/input,readonly" \
        --entrypoint python3 "${image}" /opt/padm/control_state.py --spec /input/spec.json "$@"
}

dockerControlStateCheck() (
    local directory=$1 input image metadata mode hasControl parent
    dockerTrafficSafePath "${directory}" "${directory}/config/spec.json" || return 1
    hasControl=$(jq -er 'if type == "object" then has("control") | tostring
        else error("invalid spec") end' "${directory}/config/spec.json") || return 1
    if [[ -e "${directory}/config/control" || -L "${directory}/config/control" ]]; then
        dockerTrafficSafePath "${directory}" "${directory}/config/control" &&
            [[ -d "${directory}/config/control" ]] || return 1
        metadata=$(stat -c '%u:%a' "${directory}/config/control") || return 1
        [[ "${metadata}" == 0:* ]] || return 1
        mode=${metadata#*:}
        (( (8#${mode} & 8#022) == 0 )) || return 1
    fi
    if [[ "${hasControl}" == false ]]; then
        [[ ! -d "${directory}/config/control" ||
            -z "$(find "${directory}/config/control" -mindepth 1 -print -quit)" ]]
        return $?
    fi
    # 复制到私有输入前检查受管根内的父目录，避免安全副本掩盖原目录可被替换。
    for parent in "${directory}" "${directory}/config"; do
        [[ -d "${parent}" ]] || return 1
        metadata=$(stat -c '%u:%a' "${parent}") || return 1
        [[ "${metadata}" == 0:* ]] || return 1
        mode=${metadata#*:}
        (( (8#${mode} & 8#022) == 0 )) || return 1
    done
    [[ -f "${directory}/config/spec.json" && -O "${directory}/config/spec.json" ]] &&
        dockerPrivateFileIsRestricted "${directory}/config/spec.json" || return 1
    dockerTrafficSafePath "${directory}" "${directory}/config/control/state.json" &&
        [[ -f "${directory}/config/control/state.json" &&
            -z "$(find "${directory}/config/control" -mindepth 1 \
                ! -path "${directory}/config/control/state.json" -print -quit)" ]] || return 1
    metadata=$(stat -c '%u:%a' "${directory}/config/control/state.json") || return 1
    [[ "${metadata}" == 0:* ]] || return 1
    mode=${metadata#*:}
    (( (8#${mode} & ~8#640) == 0 )) || return 1
    input=$(mktemp -d "${directory}/.control-check.XXXXXX") || return 1
    trap 'dockerRemoveManagedTree "$directory" "$input"' EXIT
    chmod 0700 "${input}" &&
        cp -- "${directory}/config/spec.json" "${input}/spec.json" &&
        cp -- "${directory}/config/control/state.json" "${input}/state.json" &&
        chmod 0600 "${input}/spec.json" "${input}/state.json" || return 1
    image=$(jq -er '.images.ops' "${input}/spec.json") || return 1
    if [[ "${2:-}" == revoke ]]; then
        dockerRealityProbeRun 30 --user 0:0 --network none \
            --tmpfs /tmp:rw,noexec,nosuid,nodev,size=8m \
            --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
            --mount "type=bind,src=${input},dst=/input,readonly" \
            --entrypoint python3 "${image}" -c '
import sys
sys.path.insert(0, "/opt/padm")
from control_state import published_state
from control_api import MAX_STATE_BYTES, validate_state
from control_sync import read_input
try:
    expected = published_state(read_input(sys.argv[1], 16 * MAX_STATE_BYTES))
    actual = validate_state(read_input(sys.argv[2], MAX_STATE_BYTES))
    # 撤销中断只补齐开关与有效期；严格解析后的身份、摘要及账号仍须一致。
    if not actual["peer"]["enabled"] and actual["peer"]["expires_at"] == 1:
        expected["peer"].update(enabled=False, expires_at=1)
    if actual != expected:
        raise ValueError("state mismatch")
except (OSError, ValueError, KeyError, TypeError, AttributeError, RecursionError):
    sys.exit("主控状态、账号摘要或发布版本不一致")
' /input/spec.json /input/state.json
    else
        dockerControlPlan "${input}" "${image}" --check-state /input/state.json
    fi
)

dockerControlRecoveryCheck() {
    local root directory plan mode=${1:-}
    if [[ "${mode}" != current && "${DOCKER_CONFIG_SWITCHED:-0}" == 1 ]]; then
        dockerError "配置恢复未完成，拒绝新发布: ${DOCKER_CONFIG_CANDIDATE:-当前事务}"
        return 1
    fi
    root=$(dockerInstallRoot) || return 1
    for directory in "${root}"/.candidate.* "${root}"/.update.*; do
        [[ -e "${directory}" || -L "${directory}" ]] || continue
        dockerTrafficSafePath "${root}" "${directory}" && [[ -d "${directory}" ]] || return 1
        [[ "${directory}" != "${DOCKER_CONFIG_CANDIDATE:-}" ]] || continue
        # 新进程没有事务变量，遗留版本计划不能被低版本在线规格掩盖。
        for plan in "${directory}/control-plan.json" "${directory}/control-restore/control-plan.json"; do
            dockerTrafficSafePath "${root}" "${plan}" || return 1
            [[ -e "${plan}" || -L "${plan}" ]] || continue
            dockerError "发现未完成的主控恢复计划，拒绝新发布，请先恢复并检查: ${directory}"
            return 1
        done
    done
}

dockerControlPrepareCandidate() (
    local source=$1 candidate=$2 previous=${3:-} input image
    local -a previousArgs=()
    [[ "${source}" == "${candidate}/config/spec.json" ]] ||
        cp -- "${source}" "${candidate}/config/spec.json" || return 1
    chmod 0600 "${candidate}/config/spec.json" || return 1
    jq -e 'has("control")' "${source}" >/dev/null || return 0
    input=$(mktemp -d "${candidate}/.control-input.XXXXXX") || return 1
    trap 'dockerRemoveManagedTree "$candidate" "$input"' EXIT
    chmod 0700 "${input}" &&
        cp -- "${source}" "${input}/spec.json" &&
        chmod 0600 "${input}/spec.json" || return 1
    if [[ -n "${previous}" ]]; then
        [[ -f "${previous}" && ! -L "${previous}" ]] &&
            dockerConfigureSpecValidate "${previous}" &&
            cp -- "${previous}" "${input}/previous.json" &&
            chmod 0600 "${input}/previous.json" || return 1
        previousArgs=(--previous /input/previous.json)
    fi
    image=$(jq -er '.images.ops' "${source}") || return 1
    (umask 077; dockerControlPlan "${input}" "${image}" "${previousArgs[@]}" >"${candidate}/control-plan.json") &&
        jq '.spec' "${candidate}/control-plan.json" >"${candidate}/config/spec.json" &&
        mkdir -p "${candidate}/config/control" &&
        jq '.state' "${candidate}/control-plan.json" >"${candidate}/config/control/state.json" &&
        chmod 0600 "${candidate}/config/spec.json" "${candidate}/control-plan.json" &&
        chmod 0640 "${candidate}/config/control/state.json" &&
        dockerConfigureSpecValidate "${candidate}/config/spec.json" || return 1
)

dockerControlRestorePrepare() {
    local backup=$1 root candidate directory
    DOCKER_CONTROL_RESTORE_PLAN=
    [[ -f "${backup}/config/spec.json" ]] &&
        jq -e 'has("control")' "${backup}/config/spec.json" >/dev/null || return 0
    root=$(dockerInstallRoot) || return 1
    if [[ -z "${DOCKER_CONFIG_CANDIDATE:-}" ]]; then
        DOCKER_CONFIG_CANDIDATE=$(mktemp -d "${root}/.candidate.XXXXXX") || return 1
    fi
    candidate=${DOCKER_CONFIG_CANDIDATE}
    dockerTrafficSafePath "${root}" "${candidate}" &&
        [[ -d "${candidate}" && ! -L "${candidate}" ]] || return 1
    directory="${candidate}/control-restore"
    mkdir -p -- "${directory}/config/control" &&
        chmod 0700 "${directory}" || return 1
    (
        local input source image index=0
        local -a floors=()
        input=$(mktemp -d "${candidate}/.control-restore-input.XXXXXX") || return 1
        trap 'dockerRemoveManagedTree "$candidate" "$input"' EXIT
        chmod 0700 "${input}" &&
            jq '.control.peer.enabled = false | .control.peer.expires_at = 1' \
                "${backup}/config/spec.json" >"${input}/spec.json" &&
            chmod 0600 "${input}/spec.json" || return 1
        source="${root}/config/spec.json"
        if [[ -e "${source}" || -L "${source}" ]]; then
            dockerTrafficSafePath "${root}" "${source}" &&
                [[ -f "${source}" && ! -L "${source}" && -O "${source}" ]] &&
                dockerPrivateFileIsRestricted "${source}" &&
                dockerConfigureSpecValidate "${source}" &&
                jq -e 'has("control")' "${source}" >/dev/null &&
                cp -- "${source}" "${input}/previous.json" &&
                chmod 0600 "${input}/previous.json" || return 1
            floors+=(--previous /input/previous.json)
        fi
        # 恢复可能先复制旧规格；重试仍须综合未完成候选与此前恢复计划的最高版本。
        for source in "${candidate}/control-plan.json" "${directory}/control-plan.json"; do
            [[ -e "${source}" || -L "${source}" ]] || continue
            dockerTrafficSafePath "${candidate}" "${source}" &&
                [[ -f "${source}" && ! -L "${source}" && -O "${source}" ]] &&
                dockerPrivateFileIsRestricted "${source}" &&
                cp -- "${source}" "${input}/plan${index}.json" &&
                chmod 0600 "${input}/plan${index}.json" &&
                jq '.spec' "${source}" >"${input}/floor-spec.json" &&
                chmod 0600 "${input}/floor-spec.json" &&
                dockerConfigureSpecValidate "${input}/floor-spec.json" &&
                jq -e 'has("control")' "${input}/floor-spec.json" >/dev/null || return 1
            floors+=(--plan-floor "/input/plan${index}.json")
            index=$((index + 1))
        done
        [[ "${#floors[@]}" -gt 0 ]] || {
            dockerError '在线主控版本与候选恢复版本均缺失，保留现场并拒绝降低版本'
            return 1
        }
        image=$(jq -er '.images.ops' "${input}/spec.json") || return 1
        (umask 077; dockerControlPlan "${input}" "${image}" "${floors[@]}" >"${directory}/control-plan.next.json") &&
            jq '.spec' "${directory}/control-plan.next.json" >"${directory}/config/spec.json" &&
            jq '.state' "${directory}/control-plan.next.json" >"${directory}/config/control/state.json" &&
            chmod 0600 "${directory}/config/spec.json" &&
            chmod 0640 "${directory}/config/control/state.json" &&
            dockerConfigureSpecValidate "${directory}/config/spec.json" &&
            mv -- "${directory}/control-plan.next.json" "${directory}/control-plan.json" || return 1
    ) || return 1
    DOCKER_CONTROL_RESTORE_PLAN=${directory}
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
    DOCKER_CONFIG_RELEASE_INPUTS=
    dockerManifestPrepare "${1:-}" "${2:-}" "${3:-}" || return "${PADM_DOCKER_RC_MANIFEST}"
    dockerStageReleaseBundle >&2 || return "${PADM_DOCKER_RC_BUNDLE}"
    dockerPullManifestImages >&2 || return "${PADM_DOCKER_RC_COMPOSE}"
}

dockerConfigureReleaseReuseInstalled() {
    local root specFile bundlePath inputs
    root=$(dockerInstallRoot) || return 1
    dockerRequireInstalledBundle || return "${PADM_DOCKER_RC_STATE}"
    specFile="${root}/config/spec.json"
    [[ -f "${specFile}" && ! -L "${specFile}" && -O "${specFile}" ]] || {
        dockerError '当前 Docker 服务尚未接入完整配置规格'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerPrivateFileIsRestricted "${specFile}" || return "${PADM_DOCKER_RC_STATE}"
    dockerManagedSpecMatchesDeployment "${specFile}" \
        "${root}/deployment.json" "${root}/images.env" || {
        dockerError '当前 spec、deployment.json 或 images.env 不一致，拒绝复用发布输入'
        return "${PADM_DOCKER_RC_STATE}"
    }
    bundlePath=$(dockerCurrentBundlePath) || return "${PADM_DOCKER_RC_BUNDLE}"
    dockerBundleSupportsSpec "${bundlePath}" "${specFile}" || return "${PADM_DOCKER_RC_BUNDLE}"
    inputs=$(jq -c '
      {release: .release, images: .images}
    ' "${specFile}") || return "${PADM_DOCKER_RC_STATE}"
    jq -e '
      (.release | type == "object" and
        (.version | type == "string" and length > 0) and
        (.manifest_sha256 | type == "string" and test("^[a-f0-9]{64}$")) and
        (.signature_identity | type == "string" and length > 0)) and
      (.images | type == "object" and
        (keys | sort) == ["net", "nginx", "ops", "sing-box", "xray"] and
        all(.[]; type == "string"))
    ' <<<"${inputs}" >/dev/null 2>&1 || return "${PADM_DOCKER_RC_STATE}"
    dockerCleanupStagedBundle || return "${PADM_DOCKER_RC_BUNDLE}"
    DOCKER_STAGED_BUNDLE_PATH=${bundlePath}
    DOCKER_CONFIG_RELEASE_INPUTS=${inputs}
}

dockerConfigureReleaseValidate() {
    local specFile=$1 inputs
    if [[ -n "${DOCKER_CONFIG_RELEASE_INPUTS:-}" ]]; then
        inputs=${DOCKER_CONFIG_RELEASE_INPUTS}
    else
        inputs=$(dockerManifestConfigurationInputs)
    fi
    [[ -n "${inputs}" ]] || {
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
    local specFile=$1 deployment=$2 imagesEnv=$3
    dockerConfigureSpecValidate "${specFile}" || return 1
    [[ -f "${deployment}" && ! -L "${deployment}" &&
        -f "${imagesEnv}" && ! -L "${imagesEnv}" ]] || return 1
    jq -e --slurpfile deployment "${deployment}" --rawfile imagesEnv "${imagesEnv}" '
      $deployment[0] as $d |
      . as $request |
      .release.version == $d.padm_version and
      .release.manifest_sha256 == $d.manifest.sha256 and
      .release.signature_identity == $d.manifest.signature_identity and
      .core.type == $d.core.type and
      (if .schema_version == 3 then
        ($d.core | has("secondary_type")) and .core.secondary_type == $d.core.secondary_type
       else ($d.core | has("secondary_type") | not) end) and
      (([.core.type, .core.secondary_type] | map(select(. != null) | "core-\(.)")) +
        [if (.reality_stream != null and .reality_stream.host_website.network_mode != "host") or
          any(.core.protocols[]; .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 or .id == 27 or .id == 29) then "nginx" else empty end] +
        [if .reality_stream.host_website.network_mode == "host" then "nginx-stream" else empty end] +
        [if .subscription.enabled then "subscription" else empty end] +
        [if .control != null then "control" else empty end] +
        [.host_integrations[].profile] | sort) == ($d.compose.profiles | sort) and
      (.host_integrations | sort_by(.type)) == ($d.host_integrations | sort_by(.type)) and
      ([.core.protocols[].id] | unique) == ($d.core.protocol_ids | sort) and
      (if .schema_version >= 2 then
        [.core.protocols[] |
          (if .id == 30 then "tcp", "udp" elif .id == 3 or .id == 31 then "udp" else "tcp" end) as $transport |
          (if $request.reality_stream != null and
            (.listener_id == $request.reality_stream.listener_id or .listener_id == $request.reality_stream.website_listener_id)
           then {listener_id, service:(if $request.reality_stream.host_website.network_mode == "host" then "nginx-stream" else "nginx" end),
             public_port:443, container_port:(if $request.reality_stream.host_website.network_mode == "host" then 443 else 15443 end)}
           else {listener_id, service: (if .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 then "nginx" else (.core // $d.core.type) end),
            public_port, container_port: (if .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 then (.websocket // .httpupgrade // .grpc_tls).tls_port else .public_port end)} end) +
          {
          transport: $transport, address_families}] | sort_by(.listener_id, .transport) as $expected |
        $expected == ([$d.listeners[] | select(.listener_id | startswith("host-") | not)] | sort_by(.listener_id, .transport))
       else true end) and
      ([$d.listeners[] | select(.listener_id == "host-control")] ==
        [if .control != null then {
          listener_id: "host-control", service: "control",
          public_port: .control.listen.port, container_port: .control.listen.port,
          transport: "tcp", address_families: ["ipv4"]
        } else empty end]) and
      ([$d.listeners[] | select(.listener_id == "host-acme-http")] ==
        [if .tls.http01 == true then {
          listener_id: "host-acme-http", service: "nginx",
          public_port: 80, container_port: 8088,
          transport: "tcp", address_families: ["ipv4", "ipv6"]
        } else empty end]) and
      all(.images | to_entries[];
        (.value | split("@") | last) == $d.images[.key].index_digest) and
      all([
        ["PADM_XRAY_IMAGE", "xray"], ["PADM_SINGBOX_IMAGE", "sing-box"],
        ["PADM_NGINX_IMAGE", "nginx"], ["PADM_OPS_IMAGE", "ops"], ["PADM_NET_IMAGE", "net"]
      ][]; . as [$key, $name] |
        [$imagesEnv | split("\n")[] | select(startswith($key + "="))] ==
          [$key + "=" + $request.images[$name]])
    ' "${specFile}" >/dev/null 2>&1 || return 1
}

dockerEditBaselineValidate() {
    local specFile=$1 workspace=$2 alpnListener=${3:-} root baseline core directory state token
    root=$(dockerInstallRoot) || return 1
    [[ -z "${alpnListener}" ]] || jq -e --arg listener "${alpnListener}" '
      [.core.protocols[] | select(.listener_id == $listener and .core == "xray" and
        (.id == 27 or .id == 29))] | length == 1
    ' "${specFile}" >/dev/null 2>&1 || return 1
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
    if jq -e '.tls.http01 == true' "${specFile}" >/dev/null; then
        dockerAcmeWebrootTreeValidate "${root}" "${root}/data/acme-webroot" || return 1
    fi
    baseline="${workspace}/baseline"
    mkdir -p -- "${baseline}/config/"{xray,sing-box,nginx,control,net/fail2ban,net/transparent} \
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
        dockerGenerateRealityStreamConfig "${specFile}" "${baseline}/config/nginx/stream/reality.conf" &&
        dockerGenerateRealityStreamMain "${specFile}" "${baseline}/config/nginx/stream/host-main" &&
        dockerGenerateFail2banConfig "${specFile}" "${baseline}" || return 1
    dockerGeoPrepareCandidate "${root}" "${baseline}" || return 1
    dockerControlPrepareCandidate "${specFile}" "${baseline}" || return 1
    if jq -e '.subscription.enabled' "${specFile}" >/dev/null; then
        token=$(jq -r '.subscription.token' "${specFile}") || return 1
        dockerGenerateSubscription "${specFile}" "${baseline}/data/subscription/${token}" || return 1
    fi
    # 整目录替换前核对所有受影响的输入，不把额外账号、路由或手写配置默默丢弃。
    for directory in config/xray config/sing-box config/nginx config/net config/control data/subscription; do
        if [[ "${directory}" == config/control && ! -e "${root}/${directory}" ]]; then
            [[ -z "$(find "${baseline}/${directory}" -mindepth 1 -print -quit)" ]] && continue
        fi
        dockerTrafficSafePath "${root}" "${root}/${directory}" &&
            [[ -d "${root}/${directory}" &&
                -z "$(find "${root}/${directory}" ! -type f ! -type d -print -quit)" ]] || return 1
        if [[ -f "${baseline}/${directory}/config.json" ]]; then
            while IFS= read -r token; do
                [[ "${token}" == "${root}/${directory}/config.json" ||
                    "${token}" == "${root}/${directory}/users.base" ||
                    ( "${directory}" == config/xray &&
                        ( "${token}" == "${root}/config/xray/geo" ||
                        "${token}" == "${root}/config/xray/geo/geoip.dat" ||
                        "${token}" == "${root}/config/xray/geo/geosite.dat" ||
                        "${token}" == "${root}/config/xray/geo/state.json" ) ) ]] || {
                    dockerError '核心含未纳入完整规格的文件，不能无损接入编辑'
                    return 1
                }
            done < <(find "${root}/${directory}" -mindepth 1 -print)
            for token in config.json users.base; do
                [[ -e "${baseline}/${directory}/${token}" ]] || continue
                [[ -f "${root}/${directory}/${token}" ]] &&
                    jq -e -n --arg alpn "${alpnListener}" --arg directory "${directory}" \
                        --slurpfile expected "${baseline}/${directory}/${token}" \
                        --slurpfile actual "${root}/${directory}/${token}" \
                        '
                          # ALPN 专项仅忽略选中入站字段，完整账号输入与运行配置都要核对。
                          def comparable:
                            if $alpn != "" and $directory == "config/xray" then
                              .inbounds |= map(if .tag == $alpn then
                                del(.streamSettings.tlsSettings.alpn) else . end)
                            else . end;
                          ($expected | map(comparable)) == ($actual | map(comparable))
                        ' >/dev/null 2>&1 || {
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

dockerFallbackAlpnStatus() {
    local specFile=$1 workspace=$2 listener=${3:-} root selected key repairable nginxMatches=false token
    root=$(dockerInstallRoot) || return 1
    for token in config/xray/config.json config/nginx; do
        dockerTrafficSafePath "${root}" "${root}/${token}" || return 1
    done
    [[ -f "${root}/config/xray/config.json" && -d "${root}/config/nginx" &&
        -z "$(find "${root}/config/nginx" ! -type f ! -type d -print -quit)" ]] || return 1
    jq -es 'length == 1 and (.[0] | type == "object" and (.inbounds | type == "array"))' \
        "${root}/config/xray/config.json" >/dev/null 2>&1 || {
        dockerError '实际 Xray 配置缺失或损坏，不能读取 ALPN'
        return 1
    }
    selected="${workspace}/alpn-selected.json"
    jq --arg listener "${listener}" '
      [.core.protocols[] | select((.id == 27 or .id == 29) and
        ($listener == "" or .listener_id == $listener))] |
      if length > 0 then . else error("没有匹配的传统 TLS fallback 入口") end
    ' "${specFile}" >"${selected}" 2>/dev/null || {
        dockerError '没有匹配的传统 TLS fallback 入口'
        return 1
    }
    mkdir -p -- "${workspace}/alpn-nginx" || return 1
    dockerGenerateNginxConfig "${specFile}" "${workspace}/alpn-nginx/default.conf" &&
        dockerGenerateRealityStreamConfig "${specFile}" "${workspace}/alpn-nginx/stream/reality.conf" &&
        dockerGenerateRealityStreamMain "${specFile}" "${workspace}/alpn-nginx/stream/host-main" || return 1
    diff -qr -- "${workspace}/alpn-nginx" "${root}/config/nginx" >/dev/null 2>&1 &&
        nginxMatches=true
    : >"${workspace}/alpn-status.jsonl"
    while IFS= read -r key; do
        repairable=false
        dockerEditBaselineValidate "${specFile}" "${workspace}" "${key}" >/dev/null 2>&1 &&
            repairable=true
        jq -en --arg listener "${key}" --argjson repairable "${repairable}" \
            --argjson nginx "${nginxMatches}" --slurpfile entries "${selected}" \
            --slurpfile actual "${root}/config/xray/config.json" '
          ($entries[0][] | select(.listener_id == $listener)) as $entry |
          [$actual[0].inbounds[] | select(.tag == $listener)] as $inbounds |
          if ($inbounds | length) != 1 then error("入站缺失或重复") else
            $inbounds[0] as $inbound |
            ($entry.fallback_tls.alpn // ["h2","http/1.1"]) as $configured |
            $inbound.streamSettings.tlsSettings.alpn as $running |
            {listener_id:$listener, protocol:$entry.id,
             configured_alpn:$configured,
             running_alpn:(if ($running | type) == "array" then
               if ($running | length <= 3 and all(.[]; . == "h2" or . == "http/1.1"))
               then $running else null end
               else null end),
             recommended_alpn:["h2","http/1.1"],
             runtime_matches_spec:($running == $configured),
             recommended:($running == ["h2","http/1.1"]),
             h2_fallback:($inbound.settings.fallbacks == [
               {dest:("nginx:" + ($entry.fallback_tls.http_port | tostring)),xver:1},
               {alpn:"h2",dest:("nginx:" + ($entry.fallback_tls.http2_port | tostring)),xver:1}]),
             nginx_matches_spec:$nginx, repairable:$repairable}
          end
        ' >>"${workspace}/alpn-status.jsonl" 2>/dev/null || {
            dockerError '实际 Xray 入站缺失、重复或损坏，无法诊断 ALPN'
            return 1
        }
    done < <(jq -r '.[].listener_id' "${selected}")
    jq -s '.' "${workspace}/alpn-status.jsonl"
}

dockerRealityProbeRun() (
    local seconds=$1 directory cidFile status=0 cid=
    shift
    directory=$(mktemp -d "${TMPDIR:-/tmp}/padm-reality-probe.XXXXXX") || return 1
    cidFile="${directory}/cid"
    trap 'status=$?; if [[ -f "${cidFile}" && ! -L "${cidFile}" ]]; then cid=$(<"${cidFile}"); fi; if [[ "${cid}" =~ ^[a-f0-9]{64}$ ]]; then docker rm -f "${cid}" >/dev/null 2>&1 || true; fi; rm -f -- "${cidFile}"; rmdir -- "${directory}"; exit "${status}"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    # 保留终端信号组；私有 cidfile 仅用于退出时清理本次容器。
    timeout --foreground -k 2 "${seconds}" docker run --rm --cidfile "${cidFile}" --read-only \
        --cap-drop ALL --security-opt no-new-privileges "$@" || status=$?
    return "${status}"
)

dockerRealityTargetNetworkRecords() {
    local opsImage=$1 host=$2
    dockerRealityProbeRun 60 --entrypoint python3 "${opsImage}" -c '
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
    org = " ".join(org.split())
    org = "".join(char for char in org if ord(char) >= 32 and ord(char) != 127)[:256]
    print(ip, asn or "unknown", org or "unknown", sep="\t")
' "${host}"
}

dockerRealityTargetTlsPing() {
    local xrayImage=$1 ip=$2 sni=$3 port=$4
    local timeoutSeconds=${PADM_DOCKER_REALITY_TLS_TIMEOUT:-20}
    [[ "${timeoutSeconds}" =~ ^[0-9]+$ && "${timeoutSeconds}" -gt 0 ]] || timeoutSeconds=20
    dockerRealityProbeRun "${timeoutSeconds}" "${xrayImage}" tls ping -ip "${ip}" "${sni}:${port}" 2>&1 || true
}

dockerRealityTargetsValidate() {
    local specFile=$1
    jq -e 'any(.core.protocols[]; .id == 1 or .id == 2 or .id == 26)' "${specFile}" >/dev/null || return 0
    # 安全门与菜单复用当前原生评分和风险算法，只读验证不更新目标库。
    source "${DOCKER_BUNDLE_SOURCE_ROOT}/docker/lib/reality-targets.sh" || return 1
    dockerRealityTargetAction "${specFile}" validate
}

dockerCurrentOwnsPort() {
    local root port transport=${2:-tcp}
    root=$(dockerInstallRoot) || return 1
    port=$1
    [[ -f "${root}/deployment.json" && ! -L "${root}/deployment.json" ]] || return 1
    if jq -e --argjson port "${port}" --arg transport "${transport}" \
        'any(.listeners[]?; .public_port == $port and .transport == $transport)' \
        "${root}/deployment.json" >/dev/null 2>&1; then
        return 0
    fi
    [[ "${port}" == 15443 && "${transport}" == tcp ]] &&
        jq -e '.reality_stream.host_website.network_mode == "host"' \
            "${root}/config/spec.json" >/dev/null 2>&1
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
          . as $request |
          ([.core.protocols[] |
              (if .id == 30 then "tcp", "udp" elif .id == 3 or .id == 31 then "udp" else "tcp" end) as $transport |
              if $request.reality_stream != null and
                (.listener_id == $request.reality_stream.listener_id or .listener_id == $request.reality_stream.website_listener_id)
              then .public_port = 443 else . end |
              "\(.public_port)|\($transport)"] +
          [.host_integrations[] | select(.type == "tproxy") |
            "\(.settings.port)|tcp", "\(.settings.port)|udp"] +
          [if .tls.http01 == true then "80|tcp" else empty end] +
          [if .reality_stream.host_website.network_mode == "host" then "15443|tcp" else empty end]) | unique[]
        ' "${specFile}"
        if jq -e 'any(.host_integrations[]; .type == "wireguard")' "${specFile}" >/dev/null; then
            wireguardPort=$(dockerWireGuardListenPort) || exit 1
            printf '%s|udp\n' "${wireguardPort}"
        fi
        jq -r 'if .control != null then "\(.control.listen.port)|tcp" else empty end' "${specFile}"
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
        config/xray config/sing-box config/nginx config/control config/net/fail2ban config/net/transparent \
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
    DOCKER_CONFIG_STREAM_TRANSITION=0
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
    jq -n --slurpfile request "${specFile}" --argjson region_defaults "${PADM_DOCKER_REGION_DEFAULT_DOMAINS}" '
      # 区域预设只在生成时展开，关闭不会删除用户手工配置的相同规则。
      ($request[0] | if .routing.region != null then
        .routing.region as $region |
        .routing.direct.domains = ((.routing.direct.domains // []) +
          $region_defaults + $region.allow_domains | unique) |
        if $region.mode == "both" or $region.mode == "domain" then
          .routing.block.domains = ((.routing.block.domains // []) + ["geosite:cn"] | unique)
        else . end |
        if $region.mode == "both" or $region.mode == "ip" then
          .routing.block_ips.ips = ((.routing.block_ips.ips // []) + ["geoip:cn"] | unique)
        else . end
      else . end) as $r |
      (($r.routing.socks5 // {}) | has("domains")) as $selective |
      (($r.routing.socks5.domains // []) | map(
        if startswith("keyword:") then ltrimstr("keyword:") else . end)) as $domains |
      ($r.routing.dns != null or $r.routing.hosts != null) as $resolve |
      (($r.routing.dns.domains // []) | map(
        if startswith("keyword:") then ltrimstr("keyword:") else . end)) as $dns_domains |
      (($r.routing.direct.domains // []) | map(
        if startswith("keyword:") then ltrimstr("keyword:") else . end)) as $direct_domains |
      (($r.routing.block.domains // []) | map(
        if startswith("keyword:") then ltrimstr("keyword:") else . end)) as $block_domains |
      ($r.routing.block_ips.ips // []) as $block_ips |
      ($r.routing.block_bt == true) as $block_bt |
      ($r.routing.direct != null or $r.routing.block != null or $r.routing.block_ips != null or $block_bt) as $actions |
      ({protocol: "freedom", tag: "direct"} +
        if $resolve then {settings: {domainStrategy: "ForceIP"}} else {} end) as $direct |
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
          } elif .id == 27 or .id == 28 or .id == 29 then {
            listen: "::",
            port: .public_port,
            protocol: (if .id == 27 then "vless" else "trojan" end),
            tag: .listener_id,
            settings: ((if .id == 27 then {
              clients: [{id: .uuid, email: .name, flow: "xtls-rprx-vision"}], decryption: "none"
            } else {clients: [{password: .uuid, email: .uuid}]} end) +
              if .id == 27 or .id == 29 then {fallbacks: [
                {dest: ("nginx:" + (.fallback_tls.http_port | tostring)), xver: 1},
                {alpn: "h2", dest: ("nginx:" + (.fallback_tls.http2_port | tostring)), xver: 1}
              ]} else {} end),
            streamSettings: {
              network: "tcp",
              security: "tls",
              tlsSettings: {
                serverName: (.fallback_tls // .trojan).domain,
                alpn: (if .id == 28 then ["http/1.1"] else .fallback_tls.alpn // ["h2", "http/1.1"] end),
                rejectUnknownSni: true,
                minVersion: "1.2",
                certificates: [{
                  certificateFile: "/etc/padm/secrets/tls/\((.fallback_tls // .trojan).domain).crt",
                  keyFile: "/etc/padm/secrets/tls/\((.fallback_tls // .trojan).domain).key"
                }]
              }
            }
          } elif .id == 24 or .id == 25 then {
            listen: "0.0.0.0",
            port: .grpc_tls.backend_port,
            protocol: (if .id == 24 then "vless" else "trojan" end),
            tag: .listener_id,
            settings: (if .id == 24 then {
              clients: [{id: .uuid, email: .name}], decryption: "none"
            } else {clients: [{password: .uuid, email: .uuid}]} end),
            streamSettings: {
              network: "grpc", security: "none",
              grpcSettings: {serviceName: .grpc_tls.service_name}
            }
          } elif .id == 21 or .id == 22 or .id == 23 then {
            listen: "0.0.0.0",
            port: ((.websocket // .httpupgrade).backend_port // 31297),
            protocol: (if .id == 21 then "vless" else "vmess" end),
            tag: (.listener_id // "vless-ws"),
            settings: ({
              clients: [{id: .uuid, email: .name} +
                if .id == 22 or .id == 23 then {alterId: 0} else {} end]
            } + (if .id == 21 then {decryption: "none"} else {} end)),
            streamSettings: ({
              network: (if .id == 23 then "httpupgrade" else "ws" end),
              security: "none"
            } + (if .id == 23 then {
              httpupgradeSettings: {path: ("/" + .httpupgrade.path), host: .httpupgrade.domain}
            } else {wsSettings: {path: "/\(.websocket.path)ws"}} end))
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
          (if $selective then $direct else empty end),
          (if $r.routing.socks5 != null then {
            protocol: "socks", tag: "padm-socks5",
            settings: {servers: [{
              address: $r.routing.socks5.server,
              port: $r.routing.socks5.port,
              users: [{user: $r.routing.socks5.username, pass: $r.routing.socks5.password}]
            }]}
          } else empty end),
          (if $selective then empty else $direct end),
          {protocol: "blackhole", tag: "blocked"}
        ]
      } + (if $resolve then {
        dns: {tag: "padm-dns", disableFallbackIfMatch: true,
          hosts: (($r.routing.hosts // {}) | with_entries(.key = "full:" + .key)),
          servers: ([(if $r.routing.dns != null then {
            address: $r.routing.dns.server, port: $r.routing.dns.port,
            domains: $dns_domains, skipFallback: true, finalQuery: true
          } else empty end), "localhost"])}
      } else {} end) +
      (if $r.routing.socks5 != null or $resolve or $actions then {
        routing: ({rules: ((if $resolve then [
          {type: "field", inboundTag: ["padm-dns"], outboundTag: "direct"}
        ] else [] end) +
        (if ($direct_domains | length) > 0 then [
          {type: "field", domain: $direct_domains, outboundTag: "direct"}
        ] else [] end) +
        (if ($block_domains | length) > 0 then [
          {type: "field", domain: $block_domains, outboundTag: "blocked"}
        ] else [] end) +
        (if ($block_ips | length) > 0 then [
          {type: "field", ip: $block_ips, outboundTag: "blocked"}
        ] else [] end) +
        (if $block_bt then [
          {type: "field", protocol: ["bittorrent"], outboundTag: "blocked"}
        ] else [] end) + (if $selective then [
          {type: "field", domain: $domains, network: "udp", outboundTag: "blocked"},
          {type: "field", domain: $domains, network: "tcp", outboundTag: "padm-socks5"}
        ] elif $r.routing.socks5 != null then [
          {type: "field", network: "udp", outboundTag: "blocked"}
        ] else [] end))} +
          # 仅匹配客户端字面目的 IP，不能为 IP 阻断本地解析 SOCKS 域名。
          if ($block_ips | length) > 0 then {domainStrategy: "AsIs"} else {} end)
      } else {} end) |
      if $selective or $actions then
        .inbounds |= map(.sniffing = {enabled: true, destOverride: ["http", "tls", "quic"], routeOnly: true})
      else . end |
      if $r.accounts != null then
        # 独立账号按入口关联；统计身份不随认证凭据轮换。
        .inbounds |= map(. as $inbound |
          [$r.core.protocols[] | select(.listener_id == $inbound.tag)] as $entries |
          if ($entries | length) == 1 and .settings.clients != null then
            .settings.clients += [
              $r.accounts[] | select(.listeners | index($inbound.tag) != null) | . as $account |
              $inbound.settings.clients[0] +
                {padm_account:$account.id, padm_enabled:$account.enabled, padm_name:$account.name, email:$account.name} |
              if has("password") then .password = $account.password else .id = $account.uuid end
            ]
          else . end)
      else . end
    ' >"${target}"
}

dockerGenerateSingBoxConfig() {
    local specFile=$1 target=$2
    jq -n --slurpfile request "${specFile}" --argjson region_defaults "${PADM_DOCKER_REGION_DEFAULT_DOMAINS}" '
      def domain_matches($rules):
        {
          domain: [$rules[] | select(startswith("full:")) | ltrimstr("full:")],
          domain_suffix: [$rules[] | select(startswith("domain:")) | ltrimstr("domain:")],
          domain_keyword: [$rules[] | select(startswith("keyword:")) | ltrimstr("keyword:")],
          rule_set: [$rules[] | select(startswith("geosite:")) | "padm-geosite-" + ltrimstr("geosite:")]
        } | to_entries | map(select(.value | length > 0) | {(.key): .value});
      def exclude_direct($match; $direct):
        if ($direct | length) > 0 then
          {type: "logical", mode: "and", rules: [$match,
            {type: "logical", mode: "or", rules: $direct, invert: true}]}
        else $match end;
      # 区域预设只在生成时展开，关闭不会删除用户手工配置的相同规则。
      ($request[0] | if .routing.region != null then
        .routing.region as $region |
        .routing.direct.domains = ((.routing.direct.domains // []) +
          $region_defaults + $region.allow_domains | unique) |
        if $region.mode == "both" or $region.mode == "domain" then
          .routing.block.domains = ((.routing.block.domains // []) + ["geosite:cn"] | unique)
        else . end |
        if $region.mode == "both" or $region.mode == "ip" then
          .routing.block_ips.ips = ((.routing.block_ips.ips // []) + ["geoip:cn"] | unique)
        else . end
      else . end) as $r |
      (($r.routing.socks5 // {}) | has("domains")) as $selective |
      ($r.routing.socks5.domains // []) as $domains |
      (domain_matches($domains)) as $matches |
      (domain_matches($r.routing.dns.domains // [])) as $dns_matches |
      (domain_matches($r.routing.direct.domains // [])) as $direct_matches |
      (domain_matches($r.routing.block.domains // [])) as $block_matches |
      ($r.routing.block_ips.ips // []) as $block_ips |
      ($block_ips | index("geoip:cn") != null) as $geoip_cn |
      ([({ip_cidr: [$block_ips[] | select(. != "geoip:cn")]} | select(.ip_cidr | length > 0)),
        (if $geoip_cn then {rule_set: ["padm-geoip-cn"]} else empty end)]) as $ip_matches |
      ($r.routing.block_bt == true) as $block_bt |
      ($r.routing.direct != null or $r.routing.block != null or $r.routing.block_ips != null or $block_bt) as $actions |
      (($r.routing.hosts // {}) | keys) as $host_domains |
      ($r.routing.dns != null or $r.routing.hosts != null) as $resolve |
      (($domains + ($r.routing.dns.domains // []) +
        ($r.routing.direct.domains // []) + ($r.routing.block.domains // [])) |
        map(select(startswith("geosite:")) | ltrimstr("geosite:")) | unique) as $sets |
      {
        log: {disabled: false, level: "warn", timestamp: true},
        inbounds: ([
          $r.core.protocols[] | select((.core // $r.core.type) == "sing-box") |
          if .id == 23 then {
            type: "vmess",
            tag: .listener_id,
            listen: "::",
            listen_port: .httpupgrade.backend_port,
            users: [{uuid: .uuid, name: .name, alterId: 0}],
            transport: {type: "httpupgrade", host: .httpupgrade.domain, path: ("/" + .httpupgrade.path)}
          }
          elif .id == 28 then {
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
        outbounds: [
          (if $r.routing.socks5 != null then {
            type: "socks", tag: "padm-socks5",
            server: $r.routing.socks5.server, server_port: $r.routing.socks5.port,
            version: "5", username: $r.routing.socks5.username, password: $r.routing.socks5.password
          } else empty end),
          {type: "direct", tag: "direct"}
        ],
        route: ({final: (if $r.routing.socks5 != null and ($selective | not) then "padm-socks5" else "direct" end),
          auto_detect_interface: true} +
          (if $r.routing.socks5 != null or $resolve or $actions then
            # 先排除直连例外再阻断或代理；例外在 hosts/DNS 解析后选路，避免跳过解析。
            {rules: ((if $selective or $actions then [{action: "sniff", timeout: "1s"}]
                else [] end) +
              [$block_matches[] | exclude_direct(.; $direct_matches) + {action: "reject"}] +
              [$ip_matches[] | exclude_direct(.; $direct_matches) + {action: "reject"}] +
              (if $block_bt then [
                exclude_direct({protocol: ["bittorrent"]}; $direct_matches) + {action: "reject"}
              ] else [] end) +
              (if $selective then
              [$matches[] | exclude_direct(. + {network: "udp"}; $direct_matches) + {action: "reject"}] +
              [$matches[] | exclude_direct(. + {network: "tcp"}; $direct_matches) +
                {action: "route", outbound: "padm-socks5"}]
             elif $r.routing.socks5 != null then
               [exclude_direct({network: "udp"}; $direct_matches) + {action: "reject"}] +
               if $resolve or ($direct_matches | length) > 0 then
                 [exclude_direct({network: "tcp"}; $direct_matches) +
                   {action: "route", outbound: "padm-socks5"}] else [] end
             else [] end) +
              (if ($host_domains | length) > 0 then [
                {domain: $host_domains, action: "resolve", server: "padm-hosts"},
                {domain: $host_domains, action: "route", outbound: "direct"}
              ] else [] end) +
              [$dns_matches[] | . + {action: "resolve", server: "padm-dns"}] +
              [$direct_matches[] | . + {action: "route", outbound: "direct"}])}
           else {} end) +
          (if $resolve then {default_domain_resolver: "padm-local"} else {} end) +
          if ($sets | length) > 0 or $geoip_cn then
              {rule_set: ([$sets[] |
                {tag: ("padm-geosite-" + .), type: "remote", format: "binary",
                  url: ("https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-" + . + ".srs"),
                  http_client: {engine: "go"}}] +
                if $geoip_cn then [{
                  tag: "padm-geoip-cn", type: "remote", format: "binary",
                  url: "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs",
                  http_client: {engine: "go"}
                }] else [] end)}
          else {} end)
      } + (if $resolve then {
        dns: {servers: [{type: "local", tag: "padm-local"},
          (if $r.routing.hosts != null then
            {type: "hosts", tag: "padm-hosts", predefined: $r.routing.hosts} else empty end),
          (if $r.routing.dns != null then {type: "udp", tag: "padm-dns",
            server: $r.routing.dns.server, server_port: $r.routing.dns.port} else empty end)],
          final: "padm-local"}
      } else {} end) |
      if $r.accounts != null then
        .inbounds |= map(. as $inbound |
          if .users != null then
            .users += [
              $r.accounts[] | select(.listeners | index($inbound.tag) != null) | . as $account |
              $inbound.users[0] +
                {padm_account:$account.id, padm_enabled:$account.enabled, padm_name:$account.name} |
              (if has("username") then .username = $account.id else .name = $account.name end) |
              (if has("uuid") then .uuid = $account.uuid else . end) |
              if has("password") then
                .password = (if $inbound.type == "shadowsocks" then $account.shadowsocks_password else $account.password end)
              else . end
            ]
          else . end)
      else . end
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

dockerSiteTreeValidate() {
    local directory=$1 unsafe
    [[ -d "${directory}" && ! -L "${directory}" ]] &&
        unsafe=$(find "${directory}" \( ! -type f ! -type d \) -print -quit) &&
        [[ -z "${unsafe}" ]] &&
        unsafe=$(find "${directory}" -type f -links +1 -print -quit) &&
        [[ -z "${unsafe}" ]]
}

dockerSiteSourceValidate() {
    local source=$1 root path mode relative file
    while [[ "${source}" == */ ]]; do source=${source%/}; done
    [[ -n "${source}" ]] || return 1
    [[ "${source}" == /* ]] || source="${PWD}/${source}"
    dockerPathIsSafeAbsolute "${source}" && [[ -d "${source}" ]] || return 1
    path=${source}
    while [[ "${path}" != / ]]; do
        [[ -d "${path}" && ! -L "${path}" ]] &&
            [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" == 1 || -O "${path}" ]] || return 1
        mode=$(stat -c %a -- "${path}") || return 1
        # root 所有的 sticky 临时目录不能被其它用户重命名；下级仍须禁止外部写入。
        (( (8#${mode} & 022) == 0 || (8#${mode} & 01000) != 0 )) || return 1
        path=$(dirname -- "${path}")
    done
    source=$(cd -- "${source}" && pwd -P) || return 1
    mode=$(stat -c %a -- "${source}") || return 1
    (( (8#${mode} & 022) == 0 )) || return 1
    root=$(dockerInstallRoot) || return 1
    [[ "${source}" != "${root}" && "${source}" != "${root%/}/"* &&
        "${root}" != "${source%/}/"* ]] || return 1
    dockerSiteTreeValidate "${source}" &&
        [[ -f "${source}/index.html" && -s "${source}/index.html" ]] || return 1
    while IFS= read -r -d '' file; do
        [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" == 1 || -O "${file}" ]] || return 1
        mode=$(stat -c %a -- "${file}") || return 1
        (( (8#${mode} & 022) == 0 )) || return 1
        relative=${file#"${source}/"}
        [[ "${relative}" =~ ^[A-Za-z0-9_-][A-Za-z0-9._~@+=,-]*(/[A-Za-z0-9_-][A-Za-z0-9._~@+=,-]*)*$ ]] || return 1
        case "/${relative,,}/" in
        */secrets/*|*/acme/*|*/control/*|*/spec.json/*|*/state.json/*|*/deployment.json/*|*/accounts.json/*) return 1 ;;
        esac
        if [[ -f "${file}" ]]; then
            case "${file##*.}" in
            html|htm|css|js|mjs|json|txt|xml|svg|png|jpg|jpeg|gif|webp|avif|ico|woff|woff2|ttf|otf|eot|wasm|pdf|mp3|mp4|webm|map) ;;
            *) return 1 ;;
            esac
            # 静态资源也不能包含可识别的 PEM 私钥，不能把公开扩展名当保密证明。
            if grep -aqE -- '-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY-----' "${file}"; then
                return 1
            elif [[ "$?" -ne 1 ]]; then
                return 1
            fi
        fi
    done < <(find "${source}" -mindepth 1 -print0)
    printf '%s\n' "${source}"
}

dockerSiteStateValidate() {
    local specFile=$1 directory=$2
    dockerSiteTreeValidate "${directory}/data/static" || return 1
    if jq -e '.site.mode == "static"' "${specFile}" >/dev/null; then
        [[ -f "${directory}/data/static/index.html" && -s "${directory}/data/static/index.html" ]] || return 1
    fi
}

dockerStageSiteFiles() {
    local specFile=$1 candidate=$2 source=${3:-} root
    root=$(dockerInstallRoot) || return 1
    if [[ -n "${source}" ]]; then
        jq -e '.site.mode == "static"' "${specFile}" >/dev/null &&
            source=$(dockerSiteSourceValidate "${source}") || return 1
    else
        source="${root}/data/static"
    fi
    if [[ -e "${source}" || -L "${source}" ]]; then
        dockerSiteTreeValidate "${source}" &&
            cp -a -- "${source}/." "${candidate}/data/static/" || return 1
    fi
    dockerSiteStateValidate "${specFile}" "${candidate}"
}

dockerGenerateSiteLocations() {
    local specFile=$1 target=$2 legacy=${3:-tls} mode url
    mode=$(jq -r '.site.mode // "legacy"' "${specFile}") || return 1
    [[ "${mode}" != legacy || "${legacy}" == fallback ]] || return 0
    if [[ "${legacy}" == fallback ]]; then
        [[ "${mode}" != legacy ]] || printf '    root /srv/padm;\n' >>"${target}" || return 1
        printf '    access_log /var/log/nginx/access.log padm_fallback;\n' >>"${target}" || return 1
    fi
    if [[ "${mode}" == redirect ]]; then
        url=$(jq -er '.site.url' "${specFile}") || return 1
        printf '\n    location / {\n        return 302 "%s";\n    }\n' "${url}" >>"${target}"
    elif [[ "${mode}" == default ]]; then
        cat >>"${target}" <<'EOF'

    location / {
        default_type text/html;
        return 200 '<!doctype html><title>Welcome</title><h1>Welcome</h1>';
    }
EOF
    else
        if [[ "${mode}" == static ]]; then
            cat >>"${target}" <<'EOF'
    root /srv/padm;

    location ~ (^|/)\. {
        return 404;
    }
EOF
        fi
        cat >>"${target}" <<'EOF'

    location = / {
        try_files /index.html @padm_fallback;
    }

    location / {
        try_files $uri =404;
    }
EOF
        if [[ "${mode}" == static ]]; then
            printf '\n    location @padm_fallback {\n        return 404;\n    }\n' >>"${target}"
        else
            cat >>"${target}" <<'EOF'

    location @padm_fallback {
        default_type text/html;
        return 200 '<!doctype html><title>Welcome</title><h1>Welcome</h1>';
    }
EOF
        fi
    fi
}

dockerGenerateNginxConfig() {
    local specFile=$1 target=$2 domain path token subscriptionEnabled fail2banEnabled backendPort tlsPort backendCore protocolId hostHeader
    local httpPort http2Port
    jq -e '.reality_stream != null or any(.core.protocols[]; .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 or .id == 27 or .id == 29)' "${specFile}" >/dev/null || return 0
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
    if jq -e '.tls.http01 == true' "${specFile}" >/dev/null; then
        cat >>"${target}" <<EOF

server {
    listen 8088;
    listen [::]:8088;
    server_name ${domain};
    root /srv/padm-acme/active;
    disable_symlinks on;
    autoindex off;
    default_type text/plain;

    if (\$host != ${domain,,}) { return 404; }
    if (\$request_uri !~ "^/\\.well-known/acme-challenge/[A-Za-z0-9_-]{1,128}\$") { return 404; }

    location ~ "^/\\.well-known/acme-challenge/[A-Za-z0-9_-]{1,128}\$" {
        try_files \$uri =404;
    }

    location / { return 404; }
}
EOF
    fi
    if jq -e 'any(.core.protocols[]; .id == 27 or .id == 29)' "${specFile}" >/dev/null; then
        cat >>"${target}" <<'EOF'

log_format padm_fallback '$proxy_protocol_addr - $remote_user [$time_local] "$request" '
                         '$status $body_bytes_sent "$http_referer" "$http_user_agent"';
EOF
    fi
    while IFS=$'\t' read -r httpPort http2Port; do
        cat >>"${target}" <<EOF

server {
    listen ${httpPort} proxy_protocol;
    listen [::]:${httpPort} proxy_protocol;
    server_name ${domain};
EOF
        dockerGenerateSiteLocations "${specFile}" "${target}" fallback || return 1
        cat >>"${target}" <<EOF
}

server {
    listen ${http2Port} proxy_protocol;
    listen [::]:${http2Port} proxy_protocol;
    http2 on;
    server_name ${domain};
EOF
        dockerGenerateSiteLocations "${specFile}" "${target}" fallback || return 1
        cat >>"${target}" <<EOF
}
EOF
    done < <(jq -r '[.core.protocols[] | select(.id == 27 or .id == 29) |
      [.fallback_tls.http_port, .fallback_tls.http2_port]] | unique[] | @tsv' "${specFile}")
    while IFS=$'\t' read -r path backendPort tlsPort backendCore protocolId; do
        hostHeader='$host'
        [[ "${protocolId}" != 23 ]] || hostHeader=${domain}
        cat >>"${target}" <<EOF

server {
    listen ${tlsPort} ssl;
    listen [::]:${tlsPort} ssl;
    server_name ${domain};

    ssl_certificate /etc/padm/secrets/tls/${domain}.crt;
    ssl_certificate_key /etc/padm/secrets/tls/${domain}.key;
    ssl_protocols TLSv1.2 TLSv1.3;
EOF
    if [[ "${protocolId}" == 24 || "${protocolId}" == 25 ]]; then
        printf '    http2 on;\n' >>"${target}" || return 1
    fi
    if [[ "${fail2banEnabled}" == "true" ]]; then
        printf '    access_log /var/log/nginx/access.log combined;\n\n' >>"${target}" || return 1
    fi
    if [[ "${protocolId}" == 24 || "${protocolId}" == 25 ]]; then
        cat >>"${target}" <<EOF
    location ^~ ${path} {
        grpc_pass grpc://${backendCore}:${backendPort};
        grpc_set_header Host ${domain};
        client_max_body_size 0;
        client_body_timeout 5d;
        grpc_read_timeout 5d;
        grpc_send_timeout 5d;
    }
EOF
    else
        cat >>"${target}" <<EOF
    location = ${path} {
        proxy_pass http://${backendCore}:${backendPort};
        proxy_http_version 1.1;
        proxy_read_timeout 5d;
        proxy_set_header Host ${hostHeader};
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
EOF
    fi
    if [[ "${subscriptionEnabled}" == "true" ]]; then
        cat >>"${target}" <<EOF

    location ~ "^/subscriptions/(?<padm_subscription_token>[A-Za-z0-9_-]{16,128})\$" {
        access_log off;
        proxy_pass http://subscription:${PADM_DOCKER_SUBSCRIPTION_PORT}/\$padm_subscription_token;
        proxy_pass_request_headers off;
    }
EOF
    fi
        dockerGenerateSiteLocations "${specFile}" "${target}" || return 1
        printf '}\n' >>"${target}" || return 1
    done < <(jq -r '.core.type as $core |
      .core.protocols[] | select(.id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25) |
      (.websocket // .httpupgrade // .grpc_tls) as $transport |
      [(if .id == 24 or .id == 25 then "/" + $transport.service_name + "/"
        else "/" + $transport.path + (if .id == 23 then "" else "ws" end) end),
       ($transport.backend_port // 31297), ($transport.tls_port // 8443), (.core // $core), .id] | @tsv' "${specFile}")
}

dockerGenerateRealityStreamConfig() {
    local specFile=$1 target=$2 domains address tlsPort realityPort domain backend=xray listenPort=15443 families
    jq -e '.reality_stream != null' "${specFile}" >/dev/null || return 0
    IFS=$'\t' read -r domains address tlsPort realityPort < <(jq -er '
      .reality_stream as $split |
      [.core.protocols[] | select(.listener_id == $split.listener_id)][0] as $reality |
      [.core.protocols[] | select(.listener_id == $split.website_listener_id)][0] as $website |
      ($website.websocket // $website.httpupgrade // $website.grpc_tls) as $tls |
      [($split.host_website.domains // [$tls.domain] | join(",")),
       ($split.host_website.address // "127.0.0.1"),
       ($split.host_website.port // $tls.tls_port), $reality.public_port] | @tsv
    ' "${specFile}") || return 1
    [[ "${address}" != *:* ]] || address="[${address}]"
    if jq -e '.reality_stream.host_website.network_mode == "host"' "${specFile}" >/dev/null; then
        backend=127.0.0.1 realityPort=15443 listenPort=443
    fi
    mkdir -p -- "$(dirname -- "${target}")" || return 1
    cat >"${target}" <<EOF
stream {
    upstream padm_website {
        server ${address}:${tlsPort};
    }
    upstream padm_reality {
        server ${backend}:${realityPort};
    }
    map \$ssl_preread_server_name \$padm_backend {
EOF
    while IFS= read -r domain; do
        printf '        %s padm_website;\n' "${domain}" >>"${target}" || return 1
    done < <(printf '%s\n' "${domains}" | tr ',' '\n')
    cat >>"${target}" <<'EOF'
        default padm_reality;
    }
    server {
EOF
    if [[ "${listenPort}" == 443 ]]; then
        families=$(jq -c '.reality_stream.listener_id as $id |
          .core.protocols[] | select(.listener_id == $id) | .address_families' "${specFile}") || return 1
        if jq -e 'index("ipv4") != null' <<<"${families}" >/dev/null; then
            printf '        listen 0.0.0.0:443;\n' >>"${target}" || return 1
        fi
        if jq -e 'index("ipv6") != null' <<<"${families}" >/dev/null; then
            printf '        listen [::]:443 ipv6only=on;\n' >>"${target}" || return 1
        fi
    else
        printf '        listen 15443;\n        listen [::]:15443;\n' >>"${target}" || return 1
    fi
    cat >>"${target}" <<'EOF'
        ssl_preread on;
        proxy_connect_timeout 10s;
        proxy_timeout 5d;
        proxy_pass $padm_backend;
    }
}
EOF
}

dockerGenerateRealityStreamMain() {
    local specFile=$1 target=$2
    jq -e '.reality_stream.host_website.network_mode == "host"' "${specFile}" >/dev/null || return 0
    mkdir -p -- "$(dirname -- "${target}")" || return 1
    # 专用宿主入口不加载 HTTP 配置，不占宿主 8080 或扩大其它监听。
    cat >"${target}" <<'EOF'
load_module /usr/lib/nginx/modules/ngx_stream_module.so;
user padm padm;
worker_processes auto;
error_log /dev/stderr notice;
pid /tmp/nginx.pid;
events { worker_connections 1024; }
include /etc/nginx/stream.d/reality.conf;
EOF
}

dockerGenerateSubscription() {
    local specFile=$1 target=$2
    jq -e '.subscription.enabled == true' "${specFile}" >/dev/null || return 0
    jq -r '
      def authority: if contains(":") then "[\(.)]" else . end;
      . as $request |
      .core.protocols[] | . as $entry |
      ((if ($request.subscription.include_base != false) then . else empty end),
       (if $request.accounts != null then
        $request.accounts[] | select(.enabled and (.listeners | index($entry.listener_id) != null)) |
        . as $account | $entry + {
          uuid: (if ($entry.id == 3 or $entry.id == 4 or $entry.id == 28 or $entry.id == 25 or $entry.id == 29)
            then $account.password else $account.uuid end),
          account_id:$account.id, account_password:$account.password,
          name: ($entry.name + "-" + $account.name)} |
        if .id == 30 then .shadowsocks.user_password = $account.shadowsocks_password else . end
       else empty end)) |
      if $request.reality_stream != null and
        (.listener_id == $request.reality_stream.listener_id or .listener_id == $request.reality_stream.website_listener_id)
      then .public_port = 443 else . end |
      if .id == 1 then
        "vless://\(.uuid)@\(.server | authority):\(.public_port)?encryption=none&flow=xtls-rprx-vision&security=reality&sni=\(.reality.server_name | @uri)&fp=chrome&pbk=\(.reality.public_key | @uri)&sid=\(.reality.short_id)&type=tcp#\(.name | @uri)"
      elif .id == 2 then
        "vless://\(.uuid)@\(.server | authority):\(.public_port)?encryption=none&security=reality&sni=\(.reality.server_name | @uri)&fp=chrome&pbk=\(.reality.public_key | @uri)&sid=\(.reality.short_id)&type=xhttp&host=\(.xhttp.host | @uri)&path=\(.xhttp.path | @uri)&mode=\(.xhttp.mode)#\(.name | @uri)"
      elif .id == 26 then
        "vless://\(.uuid)@\(.server | authority):\(.public_port)?encryption=none&security=reality&sni=\(.reality.server_name | @uri)&fp=chrome&pbk=\(.reality.public_key | @uri)&sid=\(.reality.short_id)&type=grpc&alpn=h2&path=\(.grpc.service_name | @uri)&serviceName=\(.grpc.service_name | @uri)#\(.name | @uri)"
      elif .id == 28 then
        "trojan://\(.uuid | @uri)@\(.server | authority):\(.public_port)?peer=\(.trojan.domain | @uri)&fp=chrome&sni=\(.trojan.domain | @uri)&alpn=\("http/1.1" | @uri)#\(.name | @uri)"
      elif .id == 27 then
        "vless://\(.uuid)@\(.server | authority):\(.public_port)?encryption=none&flow=xtls-rprx-vision&security=tls&sni=\(.fallback_tls.domain | @uri)&fp=chrome&alpn=\((.fallback_tls.alpn // ["h2", "http/1.1"]) | join(",") | @uri)&type=tcp#\(.name | @uri)"
      elif .id == 29 then
        "trojan://\(.uuid | @uri)@\(.server | authority):\(.public_port)?peer=\(.fallback_tls.domain | @uri)&security=tls&fp=chrome&sni=\(.fallback_tls.domain | @uri)&alpn=\((.fallback_tls.alpn // ["h2", "http/1.1"]) | join(",") | @uri)&type=tcp#\(.name | @uri)"
      elif .id == 3 then
        # 服务端上行对应客户端下行，分享链接需要交换带宽方向。
        "hysteria2://\(.uuid | @uri)@\(.server | authority):\(.public_port)?peer=\(.hy2.domain | @uri)&insecure=0&sni=\(.hy2.domain | @uri)&alpn=h3" +
          (if .hy2.bandwidth_mode == "brutal" then "&upmbps=\(.hy2.down_mbps)&downmbps=\(.hy2.up_mbps)" else "" end) +
          (if .hy2.obfs != null then "&obfs=\(.hy2.obfs.type | @uri)&obfs-password=\(.hy2.obfs.password | @uri)" else "" end) +
          "#\(.name | @uri)"
      elif .id == 4 then
        "anytls://\(.uuid | @uri)@\(.server | authority):\(.public_port)?security=tls&sni=\(.anytls.domain | @uri)#\(.name | @uri)"
      elif .id == 5 then
        "naive+https://\((.account_id // .uuid) | @uri):\((.account_password // .uuid) | @uri)@\(.server | authority):\(.public_port)?padding=true#\(.name | @uri)"
      elif .id == 30 then
        # SIP002 的 AEAD-2022 凭据必须分别百分号编码，不整段 Base64。
        "ss://\(.shadowsocks.method | @uri):\((.shadowsocks.server_password + ":" + .shadowsocks.user_password) | @uri)@\(.server | authority):\(.public_port)#\(.name | @uri)"
      elif .id == 31 then
        "tuic://\(.uuid | @uri):\((.account_password // .uuid) | @uri)@\(.server | authority):\(.public_port)?congestion_control=\(.tuic.congestion_control | @uri)&alpn=h3&sni=\(.tuic.domain | @uri)&udp_relay_mode=native&allow_insecure=0#\(.name | @uri)"
      elif .id == 21 then
        "vless://\(.uuid)@\(.server | authority):\(.public_port)?encryption=none&security=tls&sni=\(.websocket.domain | @uri)&type=ws&host=\(.websocket.domain | @uri)&path=\("/" + .websocket.path + "ws" | @uri)#\(.name | @uri)"
      elif .id == 24 then
        "vless://\(.uuid)@\(.server | authority):\(.public_port)?encryption=none&security=tls&sni=\(.grpc_tls.domain | @uri)&type=grpc&alpn=h2&serviceName=\(.grpc_tls.service_name | @uri)#\(.name | @uri)"
      elif .id == 25 then
        "trojan://\(.uuid | @uri)@\(.server | authority):\(.public_port)?peer=\(.grpc_tls.domain | @uri)&fp=chrome&sni=\(.grpc_tls.domain | @uri)&type=grpc&alpn=h2&serviceName=\(.grpc_tls.service_name | @uri)#\(.name | @uri)"
      elif .id == 22 or .id == 23 then
        (.websocket // .httpupgrade) as $transport |
        "vmess://" + ({
          v: "2", ps: .name, add: .server, port: (.public_port | tostring), id: .uuid,
          aid: "0", scy: "auto", net: (if .id == 23 then "httpupgrade" else "ws" end),
          type: "none", host: $transport.domain,
          path: ("/" + $transport.path + (if .id == 23 then "" else "ws" end)),
          tls: "tls", sni: $transport.domain
        } | tojson | @base64)
      else empty end
    ' "${specFile}" >"${target}"
}

dockerGenerateImagesEnv() {
    local specFile=$1 target=$2 rootValue=$3 netRootValue=${4:-$3}
    jq -r '.images |
      "PADM_XRAY_IMAGE=\(.xray)", "PADM_SINGBOX_IMAGE=\(."sing-box")",
      "PADM_NGINX_IMAGE=\(.nginx)", "PADM_OPS_IMAGE=\(.ops)", "PADM_NET_IMAGE=\(.net)"
    ' "${specFile}" >>"${target}" || return 1
    printf 'PADM_DOCKER_ROOT=%s\n' "${rootValue}" >>"${target}"
    printf 'PADM_NET_ROOT=%s\n' "${netRootValue}" >>"${target}"
}

dockerGenerateCompose() {
    local specFile=$1 target=$2 core domains directory=${3:-} tlsCores='[]'
    [[ -n "${directory}" ]] || directory=$(dirname -- "${target}")
    while IFS= read -r core; do
        [[ -e "${directory}/config/${core}/config.json" ]] || continue
        domains=$(dockerCoreTlsDomains "${core}" "${directory}/config/${core}/config.json") || return 1
        if [[ "${domains}" != '[]' ]]; then
            tlsCores=$(jq -c --arg core "${core}" '. + [$core]' <<<"${tlsCores}") || return 1
        fi
    done < <(jq -r '[.core.type, .core.secondary_type] | .[] | select(. != null)' "${specFile}")
    local managedGeo=false
    if [[ -e "${directory}/config/xray/geo" || -L "${directory}/config/xray/geo" ]]; then
        dockerGeoStateValidate "${directory}/config/xray/geo" || return 1
        managedGeo=true
    fi
    jq -n --slurpfile request "${specFile}" --argjson tlsCores "${tlsCores}" --argjson managedGeo "${managedGeo}" '
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
      ($r.core.protocols | map(select(.id == 1 or .id == 2 or .id == 3 or .id == 4 or .id == 5 or .id == 26 or .id == 27 or .id == 28 or .id == 29 or .id == 30 or .id == 31))) as $direct |
      ($r.core.protocols | map(select(.id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25))) as $websocket |
      ($r.core.protocols | map(select(.id == 27 or .id == 29))) as $fallback |
      ($r.host_integrations | map(select(.type == "wireguard"))) as $wireguard |
      ($r.host_integrations | map(select(.type == "fail2ban"))) as $fail2ban |
      ($r.host_integrations | map(select(.type == "tun"))) as $tun |
      ($r.host_integrations | map(select(.type == "tproxy"))) as $tproxy |
        ($r.reality_stream.host_website.network_mode == "host") as $hostStream |
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
            ports: ([$direct[] | select((.core // $r.core.type) == "xray" and
              ($r.reality_stream == null or .listener_id != $r.reality_stream.listener_id)) |
                . as $protocol | ports($protocol; $protocol.public_port)[]] +
                [if $hostStream then $r.core.protocols[] | select(.listener_id == $r.reality_stream.listener_id) |
                  "127.0.0.1:15443:\(.public_port)/tcp" else empty end]),
            tmpfs: ["/tmp:rw,noexec,nosuid,nodev,size=16m"],
            healthcheck: {
              test: ["CMD", "/usr/local/bin/xray", "-test", "-confdir", "/etc/padm/xray"],
              interval: "30s", timeout: "5s", start_period: "5s", retries: 3
            }
          } + if $managedGeo then {environment:{XRAY_LOCATION_ASSET:"/etc/padm/xray/geo"}} else {} end)
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
      | if (($websocket | length) + ($fallback | length)) > 0 or ($r.reality_stream != null and ($hostStream | not)) then
          .services.nginx = (defaults + {
            image: "${PADM_NGINX_IMAGE:?PADM_NGINX_IMAGE is required}",
            profiles: ["nginx"],
            labels: labels("nginx"),
            depends_on: (reduce ($websocket[] | (.core // $r.core.type)) as $core
              ({}; .[$core] = {condition: "service_healthy"}) +
                if $r.reality_stream != null and ($hostStream | not) then {xray:{condition:"service_healthy"}} else {} end),
            volumes: (mounts("config/nginx"; "/etc/nginx/http.d"; true) +
              (if $r.reality_stream != null and ($hostStream | not) then
                mounts("config/nginx/stream"; "/etc/nginx/stream.d"; true) else [] end) +
              mounts("data/static"; "/srv/padm"; true) +
              (if $r.tls.http01 == true then mounts("data/acme-webroot"; "/srv/padm-acme"; true) else [] end) +
              (if ($websocket | length) > 0 then mounts("secrets/tls"; "/etc/padm/secrets/tls"; true) else [] end) +
              mounts("logs/nginx"; "/var/log/nginx"; false)),
            ports: ([$websocket[] | select($r.reality_stream == null or
                .listener_id != $r.reality_stream.website_listener_id) | . as $protocol |
                ports($protocol; (($protocol.websocket // $protocol.httpupgrade // $protocol.grpc_tls).tls_port // 8443))[]] +
              [if $r.reality_stream != null and ($hostStream | not) then
                $r.core.protocols[] | select(.listener_id == $r.reality_stream.listener_id) |
                .public_port = 443 | ports(.; 15443)[] else empty end] +
              [if $r.tls.http01 == true then "0.0.0.0:80:8088/tcp", "[::]:80:8088/tcp" else empty end]),
            tmpfs: ["/tmp:rw,noexec,nosuid,nodev,size=32m"]
          } + if $r.reality_stream.host_website.address == "host.docker.internal" then
            {extra_hosts: ["host.docker.internal:host-gateway"]} else {} end)
        else . end
      | if $hostStream then
          .services["nginx-stream"] = (defaults + {
            image: "${PADM_NGINX_IMAGE:?PADM_NGINX_IMAGE is required}",
            profiles: ["nginx-stream"],
            labels: labels("nginx-stream"),
            network_mode: "host",
            user: "0:0",
            cap_add: ["NET_BIND_SERVICE", "SETGID", "SETUID", "KILL"],
            depends_on: {xray:{condition:"service_healthy"}},
            volumes: mounts("config/nginx/stream"; "/etc/nginx/stream.d"; true),
            command: ["-c", "/etc/nginx/stream.d/host-main", "-g", "daemon off;"],
            tmpfs: ["/tmp:rw,noexec,nosuid,nodev,size=16m"],
            healthcheck: {
              test: ["CMD", "/usr/sbin/nginx", "-t", "-c", "/etc/nginx/stream.d/host-main"],
              interval: "30s", timeout: "5s", start_period: "5s", retries: 3
            }
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
      | if $r.control != null then
          .services.control = (defaults + {
            image: "${PADM_OPS_IMAGE:?PADM_OPS_IMAGE is required}",
            profiles: ["control"],
            user: "10001:10001",
            network_mode: "host",
            command: ["control", "--state", "/etc/padm/control/state.json"],
            labels: labels("control"),
            depends_on: {"net-wireguard": {condition: "service_healthy"}},
            volumes: mounts("config/control"; "/etc/padm/control"; true),
            tmpfs: ["/tmp:rw,noexec,nosuid,nodev,size=8m"],
            healthcheck: {
              test: ["CMD", "/usr/local/bin/padm-entrypoint", "control-health",
                "--state", "/etc/padm/control/state.json"],
              interval: "30s", timeout: "8s", start_period: "5s", retries: 3
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
        [if ($r.reality_stream != null and $r.reality_stream.host_website.network_mode != "host") or
          any($r.core.protocols[]; .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 or .id == 27 or .id == 29) then "nginx" else empty end] +
        [if $r.reality_stream.host_website.network_mode == "host" then "nginx-stream" else empty end] +
        [if $r.subscription.enabled then "subscription" else empty end] +
        [if $r.control != null then "control" else empty end] +
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
          ((if $r.reality_stream != null and
            (.listener_id == $r.reality_stream.listener_id or .listener_id == $r.reality_stream.website_listener_id)
           then {service:(if $r.reality_stream.host_website.network_mode == "host" then "nginx-stream" else "nginx" end),
             public_port:443, container_port:(if $r.reality_stream.host_website.network_mode == "host" then 443 else 15443 end)}
           else {
            service: (if .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 then "nginx" else (.core // $r.core.type) end),
            public_port: .public_port,
            container_port: (if .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 then
              ((.websocket // .httpupgrade // .grpc_tls).tls_port // 8443) else .public_port end)
           } end) + {
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
          ] + [if $r.control != null then {
            listener_id: "host-control", service: "control",
            public_port: $r.control.listen.port, container_port: $r.control.listen.port,
            transport: "tcp", address_families: ["ipv4"]
          } else empty end] + [if $r.tls.http01 == true then {
            listener_id: "host-acme-http", service: "nginx",
            public_port: 80, container_port: 8088,
            transport: "tcp", address_families: ["ipv4", "ipv6"]
          } else empty end]
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
            test("^(entry-[a-z0-9][a-z0-9-]{0,47}|vless-reality|vless-ws|host-wireguard|host-tproxy-tcp|host-tproxy-udp|host-control|host-acme-http)$"))
         else true end)) and
      all(.listeners[] | select(.listener_id == "host-acme-http");
        .service == "nginx" and .public_port == 80 and .container_port == 8088 and
        .transport == "tcp" and .address_families == ["ipv4", "ipv6"]) and
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
    local candidate=$1 directory privateFile
    [[ -d "${candidate}" && ! -L "${candidate}" &&
        -z "$(find "${candidate}" -type l -print -quit)" ]] || {
        dockerError '候选权限准备拒绝符号链接'
        return 1
    }
    dockerSiteTreeValidate "${candidate}/data/static" || return 1
    if jq -e '.tls.http01 == true' "${candidate}/config/spec.json" >/dev/null 2>&1; then
        [[ -d "${candidate}/data/acme-webroot" && ! -L "${candidate}/data/acme-webroot" ]] || return 1
        chmod 0750 "${candidate}/data/acme-webroot" || return 1
        [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" == "1" ]] ||
            chown "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" "${candidate}/data/acme-webroot" || return 1
        dockerAcmeWebrootTreeValidate "${candidate}" "${candidate}/data/acme-webroot" true || return 1
    fi
    if [[ -e "${candidate}/config/spec.json" || -L "${candidate}/config/spec.json" ]]; then
        [[ -f "${candidate}/config/spec.json" && ! -L "${candidate}/config/spec.json" ]] || return 1
        chmod 0600 "${candidate}/config/spec.json" || return 1
    fi
    find "${candidate}/config" "${candidate}/data" "${candidate}/logs" -type d -exec chmod 0750 {} + || return 1
    find "${candidate}/config" "${candidate}/data" "${candidate}/logs" -type f \
        ! -path "${candidate}/config/spec.json" ! -name share-groups.json ! -name users.base -exec chmod 0640 {} + || return 1
    find "${candidate}/secrets" -type d -exec chmod 0750 {} + || return 1
    find "${candidate}/secrets" -type f -exec chmod 0640 {} + || return 1
    chmod 0640 "${candidate}/deployment.json" "${candidate}/compose.json" \
        "${candidate}/images.env" "${candidate}/images.runtime.env" || return 1
    if [[ -f "${candidate}/secrets/net/wireguard/wg-padm.conf" ]]; then
        chmod 0600 "${candidate}/secrets/net/wireguard/wg-padm.conf" || return 1
    fi
    if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != "1" ]]; then
        find "${candidate}/config" ! -path "${candidate}/config/spec.json" ! -name share-groups.json ! -name users.base \
            -exec chown "0:${PADM_DOCKER_CONTAINER_GID}" {} + || return 1
        chown -R "0:${PADM_DOCKER_CONTAINER_GID}" "${candidate}/data/subscription" "${candidate}/data/static" \
            "${candidate}/logs" "${candidate}/secrets" || return 1
        chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" \
            "${candidate}/logs/nginx" || return 1
        for directory in "${candidate}/data/xray" "${candidate}/data/sing-box" "${candidate}/data/acme"; do
            chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" "${directory}" || return 1
        done
    fi
    # 完整输入含停用账号凭据，只允许宿主 root 读取，不交给容器组。
    for privateFile in config/spec.json config/share-groups.json config/xray/users.base config/sing-box/users.base; do
        [[ -e "${candidate}/${privateFile}" || -L "${candidate}/${privateFile}" ]] || continue
        [[ -f "${candidate}/${privateFile}" && ! -L "${candidate}/${privateFile}" ]] || return 1
        chmod 0600 "${candidate}/${privateFile}" || return 1
        [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" == "1" ]] ||
            chown 0:0 "${candidate}/${privateFile}" || return 1
    done
    dockerTlsRuntimePermissions "${candidate}/secrets/tls"
}

dockerGenerateCandidate() {
    local specFile=$1 candidate=$2 tlsSource=${3:-} acmeSource=${4:-} businessSource=${5:-} siteSource=${6:-} root core token sharesSource=''
    root=$(dockerInstallRoot) || return 1
    local previous=
    if jq -e 'has("control")' "${specFile}" >/dev/null &&
        [[ -e "${root}/config/spec.json" || -L "${root}/config/spec.json" ]]; then
        dockerControlStateCheck "${root}" || return 1
        previous="${root}/config/spec.json"
    fi
    dockerControlPrepareCandidate "${specFile}" "${candidate}" "${previous}" || return 1
    specFile="${candidate}/config/spec.json"
    if jq -e '.tls.http01 == true' "${specFile}" >/dev/null; then
        mkdir -p -- "${candidate}/data/acme-webroot" || return 1
    fi
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
    dockerStageSiteFiles "${specFile}" "${candidate}" "${siteSource}" || return 1
    dockerGenerateNginxConfig "${specFile}" "${candidate}/config/nginx/default.conf" || return 1
    dockerGenerateRealityStreamConfig "${specFile}" "${candidate}/config/nginx/stream/reality.conf" || return 1
    dockerGenerateRealityStreamMain "${specFile}" "${candidate}/config/nginx/stream/host-main" || return 1
    if jq -e '.subscription.enabled == true' "${specFile}" >/dev/null; then
        token=$(jq -r '.subscription.token' "${specFile}") || return 1
        dockerGenerateSubscription "${specFile}" "${candidate}/data/subscription/${token}" || return 1
    fi
    if [[ -n "${businessSource}" ]]; then
        sharesSource="${candidate}/business-shares.json"
        jq '.shares' "${businessSource}" >"${sharesSource}" &&
            chmod 0600 "${sharesSource}" || return 1
    fi
    dockerSubscriptionPrepareCandidate "${specFile}" "${candidate}" "${sharesSource}" || return 1
    dockerGeoPrepareCandidate "${root}" "${candidate}" || return 1
    : >"${candidate}/images.env"
    : >"${candidate}/images.runtime.env"
    dockerGenerateImagesEnv "${specFile}" "${candidate}/images.env" "${candidate}" || return 1
    dockerGenerateImagesEnv "${specFile}" "${candidate}/images.runtime.env" "${root}" || return 1
    dockerGenerateCompose "${specFile}" "${candidate}/compose.json" || return 1
    dockerGenerateDeployment "${specFile}" "${candidate}/deployment.json" || return 1
    if [[ -n "${businessSource}" ]]; then
        dockerBusinessPrepareCandidate "${businessSource}" "${candidate}" || return 1
    else
        dockerTrafficPrepareCandidate "${candidate}" || return 1
    fi
    dockerPrepareCandidatePermissions "${candidate}"
}

dockerCandidateCompose() (
    local candidate=$1
    shift
    # 候选只使用已验证的 env-file，宿主导出变量不能覆盖镜像和挂载根。
    unset PADM_DOCKER_ROOT PADM_NET_ROOT PADM_XRAY_IMAGE PADM_SINGBOX_IMAGE \
        PADM_NGINX_IMAGE PADM_OPS_IMAGE PADM_NET_IMAGE
    docker compose --project-name "${DOCKER_ASSESS_PROJECT:-${PADM_DOCKER_PROJECT}}" \
        --project-directory "${candidate}" --env-file "${candidate}/images.env" \
        --file "${candidate}/compose.json" --profile '*' "$@" </dev/null
)

dockerCurrentOwnsHostIntegration() {
    local type=$1 root
    root=$(dockerInstallRoot) || return 1
    [[ -f "${root}/deployment.json" && ! -L "${root}/deployment.json" ]] || return 1
    jq -e --arg type "${type}" 'any(.host_integrations[]?; .type == $type)' \
        "${root}/deployment.json" >/dev/null 2>&1
}

dockerValidateHostIntegrations() {
    local specFile=$1 candidate=$2 ownership port mark ports root
    if jq -e 'any(.host_integrations[]; .type == "wireguard")' "${specFile}" >/dev/null; then
        ownership=unowned
        local -a ownershipMount=()
        if dockerCurrentOwnsHostIntegration wireguard; then
            root=$(dockerInstallRoot) || return 1
            dockerTrafficSafePath "${root}" "${root}/data/net/wireguard" || return 1
            [[ -d "${root}/data/net/wireguard" ]] || return 1
            ownership=owned
            # 候选保持自己的配置，只读核对在线接口的当前归属。
            ownershipMount=(--volume "${root}/data/net/wireguard:/run/padm-wireguard-owner:ro")
        fi
        dockerCandidateCompose "${candidate}" run --rm --no-deps "${ownershipMount[@]}" net-wireguard \
            preflight wireguard /etc/wireguard/wg-padm.conf wg-padm "${ownership}" \
            /run/padm-wireguard-owner >/dev/null || {
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
    local nginxCheckFile="${2}/compose.nginx-check.json" nginxStatus=0
    local -a nginxCheckArgs=()
    if jq -e '.tls.http01 == true' "${specFile}" >/dev/null; then
        dockerAcmeWebrootTreeValidate "${candidate}" "${candidate}/data/acme-webroot" true || {
            dockerError '候选 ACME webroot 目录不安全或非空'
            return 1
        }
    fi
    if [[ -e "${candidate}/data/static" || -L "${candidate}/data/static" ]] ||
        jq -e 'has("site")' "${specFile}" >/dev/null; then
        dockerSiteStateValidate "${specFile}" "${candidate}" || {
            dockerError '候选站点目录或静态首页无效'
            return 1
        }
    fi
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
    dockerControlStateCheck "${candidate}" || {
        dockerError '候选主控状态、账号摘要或发布版本不一致'
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
        # 仅解析候选配置，不启动候选核心；实际后端仍由项目网络解析。
        jq '{services:{nginx:{extra_hosts:
          ((.services.nginx.extra_hosts // []) +
            [.services.nginx.depends_on | keys[] | . + ":127.0.0.1"])}}}' \
            "${candidate}/compose.json" >"${nginxCheckFile}" || return 1
        nginxCheckArgs=(--file "${nginxCheckFile}")
        dockerCandidateCompose "${candidate}" "${nginxCheckArgs[@]}" run --rm --no-deps nginx -t \
            >/dev/null || nginxStatus=$?
        rm -f -- "${nginxCheckFile}" || return 1
        [[ "${nginxStatus}" == 0 ]] || {
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
    if jq -e 'has("control")' "${specFile}" >/dev/null; then
        dockerCandidateCompose "${candidate}" run --rm --no-deps control \
            control --state /etc/padm/control/state.json --check >/dev/null || {
            dockerError '主控私网服务候选配置校验失败'
            return 1
        }
    fi
    if jq -e '.services | has("nginx-stream")' "${candidate}/compose.json" >/dev/null; then
        dockerCandidateCompose "${candidate}" run --rm --no-deps nginx-stream \
            -t -c /etc/nginx/stream.d/host-main >/dev/null || {
            dockerError '宿主分流入口候选配置校验失败'
            return 1
        }
        dockerRealityStreamHostProbe "${specFile}" backend || return 1
    fi
}

dockerRealityStreamHostProbe() {
    local specFile=$1 mode=$2 image address port domains families
    jq -e '.reality_stream.host_website.network_mode == "host"' "${specFile}" >/dev/null || return 0
    dockerRealityStreamHostRuntimeCheck || return 1
    case "${mode}" in backend|ports) ;; *) return 1 ;; esac
    image=$(jq -er '.images.ops' "${specFile}") &&
        address=$(jq -er '.reality_stream.host_website.address' "${specFile}") &&
        port=$(jq -er '.reality_stream.host_website.port' "${specFile}") &&
        domains=$(jq -c '.reality_stream.host_website.domains' "${specFile}") &&
        families=$(jq -c '.reality_stream.listener_id as $id |
          .core.protocols[] | select(.listener_id == $id) | .address_families' "${specFile}") || return 1
    # 同一宿主网络实测回环 TLS；释放旧拥有者之后才检测新入口的真实绑定。
    dockerRealityProbeRun 45 --network host --user 0:0 --cap-add NET_BIND_SERVICE \
        --entrypoint python3 "${image}" -c '
import json
import socket
import ssl
import sys

mode, address, port, domains, families = sys.argv[1:]
if mode == "backend":
    context = ssl.create_default_context()
    for domain in json.loads(domains):
        with socket.create_connection((address, int(port)), timeout=5) as connection:
            with context.wrap_socket(connection, server_hostname=domain):
                pass
else:
    sockets = []
    try:
        for family in json.loads(families):
            ip_family = socket.AF_INET if family == "ipv4" else socket.AF_INET6
            connection = socket.socket(ip_family, socket.SOCK_STREAM)
            sockets.append(connection)
            connection.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            if ip_family == socket.AF_INET6:
                connection.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            connection.bind(("0.0.0.0" if family == "ipv4" else "::", 443))
            connection.listen(1)
        connection = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sockets.append(connection)
        connection.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        connection.bind(("127.0.0.1", 15443))
        connection.listen(1)
    finally:
        for connection in sockets:
            connection.close()
' "${mode}" "${address}" "${port}" "${domains}" "${families}" || {
        dockerError "宿主回环网站 TLS 或 host 网络端口检查失败: ${mode}"
        return 1
    }
}

dockerRealityStreamHostRuntimeCheck() {
    local version
    version=$(docker info --format '{{.ServerVersion}}') || return 1
    # 仅宿主回环拓扑要求新版 Engine，避免旧版本的 loopback 发布隔离缺口。
    if [[ ! "${version}" =~ ^([0-9]+)[.] || "${BASH_REMATCH[1]}" -lt 28 ]]; then
        dockerError '宿主回环网站要求 Docker Engine 28 或更新版本'
        return 1
    fi
}

dockerBackupConfiguration() {
    local root backup relative source bundlePath prefix=${1:-configure}
    root=$(dockerInstallRoot) || return 1
    [[ "${prefix}" =~ ^[a-z][a-z0-9_-]*$ ]] || return 1
    dockerControlRecoveryCheck || return 1
    if [[ -e "${root}/data/static" || -L "${root}/data/static" ]]; then
        dockerSiteTreeValidate "${root}/data/static" || return 1
    fi
    if [[ -e "${root}/data/acme-webroot" || -L "${root}/data/acme-webroot" ]]; then
        dockerAcmeWebrootTreeValidate "${root}" "${root}/data/acme-webroot" || return 1
    fi
    if [[ -e "${root}/config/spec.json" || -L "${root}/config/spec.json" ]]; then
        dockerTrafficSafePath "${root}" "${root}/config/spec.json" || return 1
        if jq -e 'has("control")' "${root}/config/spec.json" >/dev/null; then
            dockerControlStateCheck "${root}" || return 1
        fi
    fi
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
config/control
config/spec.json
config/share-groups.json
data/subscription
data/static
secrets/tls
data/acme
EOF
    if [[ "${prefix}" == business ]]; then
        mkdir -p -- "${backup}/data/traffic" || return 1
        dockerTrafficReadState >"${backup}/data/traffic/state.json" || return 1
        printf '%s\n' data/traffic/state.json >>"${backup}/present" || return 1
    fi
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
    dockerControlRecoveryCheck || return 1
    DOCKER_CONFIG_CANDIDATE=
    candidate=$(mktemp -d "${root}/.update.XXXXXX") || return 1
    dockerManagedPathIsSafe "${root}" "${candidate}" || {
        dockerRemoveManagedTree "${root}" "${candidate}" || true
        return 1
    }
    DOCKER_CONFIG_CANDIDATE=${candidate}
    for relative in \
        config/xray config/sing-box config/nginx config/net config/control data/subscription \
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
        chmod 0600 "${candidate}/config/spec.json" || return 1
        dockerConfigureSpecValidate "${candidate}/config/spec.json" &&
            dockerConfigureReleaseValidate "${candidate}/config/spec.json" &&
            dockerControlStateCheck "${root}" &&
            dockerControlStateCheck "${candidate}" || return 1
        dockerControlPrepareCandidate "${candidate}/config/spec.json" "${candidate}" \
            "${root}/config/spec.json" || return 1
        if jq -e '.tls.http01 == true' "${candidate}/config/spec.json" >/dev/null; then
            dockerAcmeWebrootTreeValidate "${root}" "${root}/data/acme-webroot" &&
                mkdir -p -- "${candidate}/data/acme-webroot" || return 1
        fi
    fi
    if [[ -e "${root}/config/share-groups.json" || -L "${root}/config/share-groups.json" ]]; then
        dockerSubscriptionReadState >"${candidate}/config/share-groups.json" || return 1
        chmod 0600 "${candidate}/config/share-groups.json" || return 1
    fi
    dockerTrafficPrepareCandidate "${candidate}" || return 1
    dockerPrepareCandidatePermissions "${candidate}" || return 1
    DOCKER_CONFIG_CANDIDATE=${candidate}
}

dockerValidateUpdateCandidate() {
    local candidate=$1
    dockerDeploymentFileValidate "${candidate}/deployment.json" || return 1
    if [[ -f "${candidate}/config/spec.json" ]]; then
        dockerBundleSupportsSpec "${DOCKER_STAGED_BUNDLE_PATH}" "${candidate}/config/spec.json" &&
            dockerControlStateCheck "${candidate}" || return 1
    fi
    if [[ -f "${candidate}/config/spec.json" ]] &&
        jq -e '.reality_stream != null or .tls.http01 == true' "${candidate}/config/spec.json" >/dev/null; then
        dockerBundleSupportsSpec "${DOCKER_STAGED_BUNDLE_PATH}" "${candidate}/config/spec.json" &&
            dockerValidateCandidate "${candidate}/config/spec.json" "${candidate}"
        return $?
    fi
    dockerCandidateCompose "${candidate}" config --format json >/dev/null 2>&1 || return 1
}

dockerRemoveConfigurationTargets() {
    local root relative target includeStatic=${1:-1}
    root=$(dockerInstallRoot) || return 1
    while IFS= read -r relative; do
        [[ "${relative}" != data/static || "${includeStatic}" == 1 ]] || continue
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
config/control
config/spec.json
config/share-groups.json
data/subscription
data/static
secrets/tls
data/acme
EOF
}

dockerInstallCandidate() {
    local candidate=$1 backup=$2 root relative source target
    root=$(dockerInstallRoot) || return 1
    dockerRealityStreamDeploymentCheck "${candidate}/config/spec.json" "${root}/config/spec.json" || return 1
    if [[ -f "${candidate}/config/spec.json" ]] &&
        jq -e '.tls.http01 == true' "${candidate}/config/spec.json" >/dev/null; then
        # 挑战根独立于配置事务，不能移动候选空目录或替换在线 inode。
        dockerAcmeWebrootEnsure "${root}" || return 1
    fi
    DOCKER_CONFIG_SWITCHED=1
    if [[ -f "${candidate}/business-traffic.json" ]]; then
        dockerTrafficWriteState <"${candidate}/business-traffic.json" || return 1
    fi
    dockerRealityStreamTransitionPrepare "${candidate}/config/spec.json" || return 1
    dockerRemoveConfigurationTargets || return 1
    if grep -qxF deployment.json "${backup}/present"; then
        cp -- "${backup}/deployment.json" "${root}/deployment.previous.json" || return 1
        chmod 0640 "${root}/deployment.previous.json" || return 1
    fi
    for relative in config/xray config/sing-box config/nginx config/net config/control data/subscription data/static secrets/tls data/acme; do
        source="${candidate}/${relative}"
        target="${root}/${relative}"
        mkdir -p -- "$(dirname -- "${target}")" || return 1
        mv -- "${source}" "${target}" || return 1
    done
    if [[ -f "${candidate}/config/spec.json" && ! -L "${candidate}/config/spec.json" ]]; then
        mv -- "${candidate}/config/spec.json" "${root}/config/spec.json" || return 1
    fi
    if [[ -f "${candidate}/config/share-groups.json" && ! -L "${candidate}/config/share-groups.json" ]]; then
        mv -- "${candidate}/config/share-groups.json" "${root}/config/share-groups.json" || return 1
    fi
    mv -- "${candidate}/compose.json" "${root}/compose.json" || return 1
    mv -- "${candidate}/images.runtime.env" "${root}/images.env" || return 1
    mv -- "${candidate}/deployment.json" "${root}/deployment.json" || return 1
    chmod 0640 "${root}/compose.json" "${root}/images.env" "${root}/deployment.json" || return 1
}

dockerEnsureRuntimeDataPermissions() {
    local root directory privateFile
    root=$(dockerInstallRoot) || return 1
    if jq -e '.tls.http01 == true' "${root}/config/spec.json" >/dev/null 2>&1; then
        dockerAcmeWebrootEnsure "${root}" || return 1
    fi
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
    dockerSiteTreeValidate "${root}/data/static" &&
        find "${root}/data/static" -type d -exec chmod 0750 {} + &&
        find "${root}/data/static" -type f -exec chmod 0640 {} + || return 1
    for directory in config data/subscription; do
        [[ -d "${root}/${directory}" && ! -L "${root}/${directory}" ]] || return 1
        [[ -z "$(find "${root}/${directory}" -type l -print -quit)" ]] || return 1
        find "${root}/${directory}" -type d -exec chmod 0750 {} + || return 1
        find "${root}/${directory}" -type f ! -path "${root}/config/spec.json" ! -name share-groups.json ! -name users.base \
            -exec chmod 0640 {} + || return 1
    done
    if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != "1" ]]; then
        chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" \
            "${root}/data/xray" "${root}/data/sing-box" "${root}/data/acme" || return 1
        find "${root}/config" ! -path "${root}/config/spec.json" ! -name share-groups.json ! -name users.base \
            -exec chown "0:${PADM_DOCKER_CONTAINER_GID}" {} + || return 1
        chown -R "0:${PADM_DOCKER_CONTAINER_GID}" "${root}/data/static" \
            "${root}/logs/subscription" "${root}/logs/acme" \
            "${root}/data/subscription" || return 1
        chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" \
            "${root}/logs/nginx" || return 1
        chown -R 0:0 "${root}/data/net" || return 1
    fi
    for privateFile in config/spec.json config/share-groups.json config/xray/users.base config/sing-box/users.base; do
        [[ -e "${root}/${privateFile}" || -L "${root}/${privateFile}" ]] || continue
        [[ -f "${root}/${privateFile}" && ! -L "${root}/${privateFile}" ]] || return 1
        chmod 0600 "${root}/${privateFile}" || return 1
        [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" == "1" ]] ||
            chown 0:0 "${root}/${privateFile}" || return 1
    done
    dockerTlsRuntimePermissions "${root}/secrets/tls"
}

dockerRestoreConfiguration() {
    local root backup=${DOCKER_CONFIG_BACKUP:-} relative core bundleTarget= savedTraffic currentTraffic restoredTraffic includeStatic=0
    local alpnListener=${DOCKER_CONFIG_RESTORE_ALPN_LISTENER:-} alpnTemporary=
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
    if jq -e '.tls.http01 == true' "${backup}/config/spec.json" >/dev/null 2>&1; then
        dockerAcmeWebrootEnsure "${root}" || return 1
    fi
    dockerControlRestorePrepare "${backup}" || return 1
    # 当前配置可能只安装了一部分，恢复授权只取自已验证的备份。
    dockerRealityStreamDeploymentCheck "${backup}/config/spec.json" || return 1
    if grep -qxF data/traffic/state.json "${backup}/present"; then
        dockerTrafficBeforeChange
        savedTraffic=$(jq -c . "${backup}/data/traffic/state.json") &&
            currentTraffic=$(dockerTrafficReadState) &&
            restoredTraffic=$(dockerBusinessMergeTraffic "${savedTraffic}" "${currentTraffic}") &&
            dockerTrafficWriteState <<<"${restoredTraffic}" || return 1
    fi
    if [[ -f "${backup}/deployment.json" ]] &&
        { [[ "${DOCKER_CONFIG_STREAM_TRANSITION:-0}" == 1 ]] ||
        { [[ -f "${backup}/config/spec.json" ]] &&
            jq -e '.reality_stream != null' "${backup}/config/spec.json" >/dev/null; } ||
        { [[ -f "${root}/config/spec.json" ]] &&
            jq -e '.reality_stream != null' "${root}/config/spec.json" >/dev/null; }; }; then
        # 仅释放交接相关服务；部分安装失败时用受管标签找到已有容器。
        if [[ "${DOCKER_CONFIG_STREAM_HOST_TRANSITION:-0}" == 1 ]] ||
            jq -e '.reality_stream.host_website.network_mode == "host"' "${backup}/config/spec.json" >/dev/null 2>&1 ||
            jq -e '.reality_stream.host_website.network_mode == "host"' "${root}/config/spec.json" >/dev/null 2>&1; then
            dockerRealityStreamStopServices nginx xray nginx-stream || return 1
        else
            dockerRealityStreamStopServices nginx xray || return 1
        fi
    else
        dockerComposeRun down >/dev/null 2>&1 || true
    fi
    # 旧快照未记录站点内容时保留现有目录，不能把它当作空站点删除。
    grep -qxF data/static "${backup}/present" && includeStatic=1
    dockerRemoveConfigurationTargets "${includeStatic}" || return 1
    while IFS= read -r relative; do
        # 业务恢复点已恢复额度并合并最新累计，不能再用旧文件覆盖账目。
        [[ "${relative}" != data/traffic/state.json ]] || continue
        # 旧授权不能先复制再覆盖，存活的控制进程可能在窗口内接受已撤销凭据。
        if [[ -n "${DOCKER_CONTROL_RESTORE_PLAN:-}" &&
            ( "${relative}" == config/spec.json || "${relative}" == config/control ) ]]; then
            continue
        fi
        [[ -e "${backup}/${relative}" ]] || return 1
        mkdir -p -- "${root}/$(dirname -- "${relative}")" || return 1
        cp -a -- "${backup}/${relative}" "${root}/${relative}" || return 1
    done <"${backup}/present"
    if [[ -n "${DOCKER_CONTROL_RESTORE_PLAN:-}" ]]; then
        mkdir -p -- "${root}/config/control" &&
            cp -- "${DOCKER_CONTROL_RESTORE_PLAN}/config/spec.json" "${root}/config/spec.json" &&
            cp -- "${DOCKER_CONTROL_RESTORE_PLAN}/config/control/state.json" \
                "${root}/config/control/state.json" || return 1
    fi
    [[ -z "${bundleTarget}" ]] || dockerActivateBundle "${bundleTarget}" || return 1
    if [[ -f "${root}/deployment.json" && -f "${root}/compose.json" && -f "${root}/images.env" ]]; then
        if [[ -f "${root}/config/xray/users.base" || -f "${root}/config/sing-box/users.base" ||
            -f "${root}/data/traffic/state.json" ]]; then
            dockerTrafficPrepareCandidate "${root}" || return 1
        fi
        if [[ -n "${alpnListener}" ]]; then
            # 额度重渲染会覆盖运行配置，专项恢复要保留原先仅运行文件里的 ALPN 漂移。
            alpnTemporary=$(mktemp "${root}/config/xray/.alpn-restore.XXXXXX") || return 1
            jq -e --arg listener "${alpnListener}" \
                --slurpfile saved "${backup}/config/xray/config.json" '
              ($saved[0].inbounds[] | select(.tag == $listener) |
                .streamSettings.tlsSettings) as $tls |
              .inbounds |= map(if .tag == $listener then
                if $tls | has("alpn") then .streamSettings.tlsSettings.alpn = $tls.alpn
                else del(.streamSettings.tlsSettings.alpn) end
              else . end)
            ' "${root}/config/xray/config.json" >"${alpnTemporary}" &&
                mv -f -- "${alpnTemporary}" "${root}/config/xray/config.json" || {
                rm -f -- "${alpnTemporary}"
                return 1
            }
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
    dockerRenewalScheduleInstall && dockerGeoScheduleInstall || return 1
    DOCKER_CONFIG_SWITCHED=0
    DOCKER_CONFIG_STREAM_TRANSITION=0
    DOCKER_CONFIG_STREAM_HOST_TRANSITION=0
    [[ -z "${DOCKER_CONTROL_RESTORE_PLAN:-}" ]] ||
        printf '主控恢复完成，Peer 授权已禁用，请重新生成邀请。\n' >&2
    DOCKER_CONTROL_RESTORE_PLAN=
}

dockerCleanupConfigurationCandidate() {
    local root candidate=${DOCKER_CONFIG_CANDIDATE:-}
    [[ -n "${candidate}" ]] || return 0
    if [[ "${DOCKER_CONFIG_SWITCHED:-0}" == 1 &&
        ( -e "${candidate}/control-plan.json" ||
          -L "${candidate}/control-plan.json" ||
          -e "${candidate}/control-restore/control-plan.json" ||
          -L "${candidate}/control-restore/control-plan.json" ) ]]; then
        dockerError "配置恢复未完成，保留候选和版本计划: ${candidate}"
        return 1
    fi
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

dockerRealityStreamDeploymentCheck() {
    local specFile
    for specFile in "$@"; do
        [[ -e "${specFile}" || -L "${specFile}" ]] || continue
        if ! [[ -f "${specFile}" && ! -L "${specFile}" ]] ||
            ! jq -es 'length == 1 and (.[0] | type == "object")' \
                "${specFile}" >/dev/null 2>&1; then
            dockerError '受管配置规格损坏或不安全，拒绝部署'
            return 1
        fi
        if jq -e '.reality_stream != null' "${specFile}" >/dev/null; then
            dockerConfigureSpecValidate "${specFile}" || return 1
            jq -e '.["x-padm-reality-stream-deployment"] == true' \
                "$(dockerConfigureSchemaFile)" >/dev/null || return 1
            if jq -e '.reality_stream.host_website != null' "${specFile}" >/dev/null; then
                jq -e '.["x-padm-reality-stream-host-website"] == true' \
                    "$(dockerConfigureSchemaFile)" >/dev/null || return 1
            fi
            if jq -e '.reality_stream.host_website.network_mode == "host"' "${specFile}" >/dev/null; then
                jq -e '.["x-padm-reality-stream-host-network"] == true' \
                    "$(dockerConfigureSchemaFile)" >/dev/null || return 1
                dockerRealityStreamHostRuntimeCheck || return 1
            fi
        fi
    done
}

dockerRealityStreamStopServices() {
    local service ids id
    local -a containers=()
    # 使用项目和服务双标签限定已有容器，不依赖可能安装到一半的 Compose 文件。
    for service in "$@"; do
        case "${service}" in xray|nginx|nginx-stream) ;; *) return 1 ;; esac
        ids=$(docker ps -q --filter "label=com.docker.compose.project=${PADM_DOCKER_PROJECT}" \
            --filter "label=com.docker.compose.service=${service}") || return 1
        while IFS= read -r id; do
            [[ -n "${id}" ]] || continue
            [[ "${id}" =~ ^[a-f0-9]{12,64}$ ]] || return 1
            containers+=("${id}")
        done <<<"${ids}"
    done
    [[ "${#containers[@]}" -eq 0 ]] || docker stop "${containers[@]}" >/dev/null
}

dockerRealityStreamTransitionPrepare() {
    local sourceSpec=$1 root currentSpec services service
    local -a owners=()
    root=$(dockerInstallRoot) || return 1
    currentSpec="${root}/config/spec.json"
    if ! jq -e '.reality_stream != null' "${sourceSpec}" >/dev/null 2>&1 &&
        ! { [[ -f "${currentSpec}" ]] && jq -e '.reality_stream != null' "${currentSpec}" >/dev/null; }; then
        return 0
    fi
    DOCKER_CONFIG_STREAM_TRANSITION=1
    if jq -e '.reality_stream.host_website.network_mode == "host"' "${sourceSpec}" >/dev/null 2>&1 ||
        jq -e '.reality_stream.host_website.network_mode == "host"' "${currentSpec}" >/dev/null 2>&1; then
        DOCKER_CONFIG_STREAM_HOST_TRANSITION=1
    fi
    if [[ ! -f "${root}/deployment.json" ]]; then
        dockerRealityStreamHostProbe "${sourceSpec}" ports
        return $?
    fi
    services=$(jq -r '[.listeners[] | select(.public_port == 443 and .transport == "tcp") | .service] |
      unique | .[]' "${root}/deployment.json") || {
        return 1
    }
    while IFS= read -r service; do
        [[ -n "${service}" ]] || continue
        case "${service}" in xray|nginx|nginx-stream) owners+=("${service}") ;; *) return 1 ;; esac
    done <<<"${services}"
    if [[ "${DOCKER_CONFIG_STREAM_HOST_TRANSITION}" == 1 ]]; then
        # 中继端口也由 Xray 发布，网络切换不能只停止公开 443 拥有者。
        dockerRealityStreamStopServices nginx xray nginx-stream || return 1
    elif [[ "${#owners[@]}" -gt 0 ]]; then
        dockerRealityStreamStopServices "${owners[@]}" || return 1
    fi
    dockerRealityStreamHostProbe "${sourceSpec}" ports
}

dockerConfigureApply() {
    local sourceSpec=$1 tlsSource=${2:-} acmeSource=${3:-} mode=${4:-configure} businessSource=${5:-} siteSource=${6:-}
    local specFile candidate backup answer root backupPrefix=configure
    [[ -z "${businessSource}" ]] || backupPrefix=business
    case "${mode}" in configure|preview|interactive|confirmed) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
    dockerControlRecoveryCheck || return "${PADM_DOCKER_RC_STATE}"
    dockerConfigureSpecValidate "${sourceSpec}" || return "${PADM_DOCKER_RC_STATE}"
    dockerAcmeWebrootTransitionValidate "${sourceSpec}" || return "${PADM_DOCKER_RC_CONFLICT}"
    dockerControlSyncTransitionValidate "${sourceSpec}" || return "${PADM_DOCKER_RC_CONFLICT}"
    dockerControlTransitionValidate "${sourceSpec}" || return "${PADM_DOCKER_RC_CONFLICT}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerRealityStreamDeploymentCheck "${sourceSpec}" "${root}/config/spec.json" ||
        return "${PADM_DOCKER_RC_STATE}"
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
    if ! dockerGenerateCandidate "${specFile}" "${candidate}" "${tlsSource}" "${acmeSource}" "${businessSource}" "${siteSource}"; then
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    fi
    specFile="${candidate}/config/spec.json"
    if ! dockerValidateCandidate "${specFile}" "${candidate}"; then
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
        if [[ -n "${businessSource}" ]]; then
            dockerBusinessPrepareCandidate "${businessSource}" "${candidate}"
        else
            dockerTrafficPrepareCandidate "${candidate}"
        fi &&
            dockerPrepareCandidatePermissions "${candidate}" &&
            dockerValidateCandidate "${specFile}" "${candidate}" || {
            dockerCleanupConfigurationCandidate || true
            return "${PADM_DOCKER_RC_STATE}"
        }
    fi
    dockerBackupConfiguration "${backupPrefix}" || {
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    }
    backup=${DOCKER_CONFIG_BACKUP}
    if ! dockerInstallCandidate "${candidate}" "${backup}" ||
        ! dockerEnsureRuntimeDataPermissions ||
        ! dockerComposeRun up -d --force-recreate --wait --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" ||
        ! dockerTrafficScheduleInstall ||
        ! dockerRenewalScheduleInstall ||
        ! dockerGeoScheduleInstall; then
        dockerError '候选部署启动或健康检查失败，正在恢复旧配置'
        if ! dockerRestoreConfiguration; then
            dockerError "旧配置恢复失败，请检查备份: ${backup}"
        fi
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_COMPOSE}"
    fi
    DOCKER_CONFIG_SWITCHED=0
    DOCKER_CONFIG_STREAM_TRANSITION=0
    DOCKER_CONFIG_STREAM_HOST_TRANSITION=0
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
    dockerAcmeWebrootTransitionValidate "${specFile}" || return "${PADM_DOCKER_RC_CONFLICT}"
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
    [[ "${#DOCKER_ACME_STOPPED[@]}" == 0 && -z "${DOCKER_ACME_CONTAINER:-}" &&
        -z "${DOCKER_ACME_WEBROOT:-}" ]] || {
        dockerError 'ACME 服务尚未恢复，保留候选账户以便重试'
        return 1
    }
    [[ -n "${candidate}" ]] || return 0
    root=$(dockerInstallRoot) || return 1
    [[ ! -d "${candidate}" ]] || dockerRemoveManagedTree "${root}" "${candidate}" || return 1
    DOCKER_TLS_CANDIDATE=
    DOCKER_ACME_RUNNING=null
}

dockerTlsValidateCandidate() {
    local image=$1 candidate=$2 domain=$3
    local -a runner=(docker run --rm --read-only --cap-drop ALL --security-opt no-new-privileges)
    [[ -z "${DOCKER_ASSESS_PROJECT:-}" ]] || runner=(dockerRealityProbeRun 30)
    "${runner[@]}" --tmpfs /tmp:rw,noexec,nosuid,nodev,size=8m \
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
    "${runner[@]}" --tmpfs /tmp:rw,noexec,nosuid,nodev,size=8m \
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
    local nginxTlsExpected=true specFile
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
        if [[ "${core}" == xray && -d "${root}/config/xray/geo" ]]; then
            dockerGeoStateValidate "${root}/config/xray/geo" || return 1
        fi
        [[ -z "$(find "${root}/config/${core}" -name '*.json' ! -name config.json \
            ! -path "${root}/config/xray/geo/state.json" -print -quit)" ]] || return 1
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
    specFile="${root}/config/spec.json"
    if [[ -f "${specFile}" ]] &&
        jq -e '.reality_stream.host_website.network_mode == "host"' "${specFile}" >/dev/null; then
        dockerTrafficSafePath "${root}" "${specFile}" &&
            dockerConfigureSpecValidate "${specFile}" &&
            dockerManagedSpecMatchesDeployment "${specFile}" "${root}/deployment.json" "${root}/images.env" &&
            dockerTrafficSafePath "${root}" "${root}/config/nginx/stream/host-main" &&
            [[ -z "$(find "${root}/config/nginx" ! -type f ! -type d -print -quit)" ]] &&
            cmp -s -- "${root}/config/nginx/stream/host-main" \
                <(dockerGenerateRealityStreamMain "${specFile}" /dev/stdout) &&
            cmp -s -- "${root}/config/nginx/stream/reality.conf" \
                <(dockerGenerateRealityStreamConfig "${specFile}" /dev/stdout) &&
            jq -e --slurpfile expected <(dockerGenerateCompose "${specFile}" /dev/stdout "${root}") '
              def stream: .services["nginx-stream"] | .labels |= del(."io.padm.release");
              stream == ($expected[0] | stream) and
              .services.xray.ports == $expected[0].services.xray.ports and
              .services.xray.network_mode == $expected[0].services.xray.network_mode
            ' "${root}/compose.json" >/dev/null || return 1
    elif jq -e '.services | has("nginx-stream")' "${root}/compose.json" >/dev/null; then
        return 1
    fi
    if jq -e '.compose.profiles | index("nginx") != null' "${root}/deployment.json" >/dev/null; then
        jq -e '[.services.nginx.volumes[]? |
          select(.target == "/etc/nginx/http.d" or (.target | startswith("/etc/nginx/http.d/")))] |
          length == 1 and .[0].type == "bind" and .[0].read_only == true and
          .[0].target == "/etc/nginx/http.d" and .[0].source == "${PADM_DOCKER_ROOT}/config/nginx"
        ' "${root}/compose.json" >/dev/null || return 1
        dockerTrafficSafePath "${root}" "${root}/config/nginx/default.conf" || return 1
        [[ -f "${root}/config/nginx/default.conf" && ! -L "${root}/config/nginx/default.conf" ]] || return 1
        [[ -z "$(find "${root}/config/nginx" ! -type f ! -type d -print -quit)" ]] || return 1
        specFile="${root}/config/spec.json"
        if [[ -e "${specFile}" || -L "${specFile}" ]]; then
            dockerTrafficSafePath "${root}" "${specFile}" &&
                dockerConfigureSpecValidate "${specFile}" || return 1
            nginxTlsExpected=$(jq -r 'any(.core.protocols[];
              .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25)' "${specFile}") || return 1
        fi
        if [[ -f "${specFile}" ]] && jq -e '.reality_stream != null' "${specFile}" >/dev/null; then
            [[ -z "$(find "${root}/config/nginx" -name '*.conf' ! -name default.conf \
                ! -path "${root}/config/nginx/stream/reality.conf" -print -quit)" ]] &&
                cmp -s -- "${root}/config/nginx/stream/reality.conf" \
                    <(dockerGenerateRealityStreamConfig "${specFile}" /dev/stdout) &&
                cmp -s -- "${root}/config/nginx/default.conf" \
                    <(dockerGenerateNginxConfig "${specFile}" /dev/stdout) &&
                jq -e --slurpfile expected <(dockerGenerateCompose "${specFile}" /dev/stdout "${root}") '
                  (.services.nginx.volumes | sort_by(.target)) ==
                    ($expected[0].services.nginx.volumes | sort_by(.target)) and
                  .services.nginx.extra_hosts == $expected[0].services.nginx.extra_hosts and
                  .services.nginx.network_mode == null' \
                    "${root}/compose.json" >/dev/null || return 1
        else
            [[ -z "$(find "${root}/config/nginx" -name '*.conf' ! -name default.conf -print -quit)" ]] || return 1
        fi
        if [[ "${nginxTlsExpected}" == true ]]; then
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
        elif ! jq -e '.reality_stream != null' "${specFile}" >/dev/null; then
            # 明文 fallback 只接受受管生成结果和固定挂载，拒绝配置漂移及主配置覆盖。
            cmp -s -- "${root}/config/nginx/default.conf" \
                <(dockerGenerateNginxConfig "${specFile}" /dev/stdout) &&
                jq -e --slurpfile expected <(dockerGenerateCompose "${specFile}" /dev/stdout "${root}") '
                  (.services.nginx.volumes | sort_by(.target)) ==
                    ($expected[0].services.nginx.volumes | sort_by(.target))' \
                    "${root}/compose.json" >/dev/null || return 1
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
    if [[ "${DOCKER_ACME_RUNNING}" != null ]]; then
        consumers=$(jq -c --argjson running "${DOCKER_ACME_RUNNING}" \
            '[.[] | select(. as $service | $running | index($service) != null)]' <<<"${consumers}") || return 1
    fi
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

dockerAcmeWebrootParentValidate() {
    local root=$1 directory=$2 cursor mode
    [[ "${directory}" == "${root}/data/acme-webroot" ]] &&
        dockerTrafficSafePath "${root}" "${directory}" || return 1
    cursor=${directory%/*}
    while [[ -n "${cursor}" ]]; do
        [[ -d "${cursor}" && ! -L "${cursor}" ]] || return 1
        [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" == 1 || "$(stat -c %u -- "${cursor}")" == 0 ]] || return 1
        mode=$(stat -c %a -- "${cursor}") || return 1
        # root 所有的 sticky 临时目录保护下级归属，部署目录仍禁止外部写入。
        (( (8#${mode} & 022) == 0 || (8#${mode} & 01000) != 0 )) || return 1
        [[ "${cursor}" != / ]] || break
        cursor=${cursor%/*}
        [[ -n "${cursor}" ]] || cursor=/
    done
}

dockerAcmeWebrootTreeValidate() {
    local root=$1 directory=$2 empty=${3:-false} entry relative owner mode value
    dockerAcmeWebrootParentValidate "${root}" "${directory}" &&
        [[ -d "${directory}" ]] || return 1
    [[ -z "$(find "${directory}" ! -type d ! -type f -print -quit)" ]] || return 1
    if [[ "${empty}" == true ]]; then
        [[ -z "$(find "${directory}" -mindepth 1 -print -quit)" ]] || return 1
    fi
    while IFS= read -r -d '' entry; do
        relative=${entry#"${directory}"}
        owner=$(stat -c %u:%g -- "${entry}") &&
            mode=$(stat -c %a -- "${entry}") || return 1
        [[ "${owner}" == "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" ||
            "${PADM_DOCKER_SKIP_CHOWN:-0}" == 1 ]] || return 1
        (( (8#${mode} & 022) == 0 )) || return 1
        if [[ -d "${entry}" ]]; then
            case "${relative}" in ''|/active|/active/.well-known|/active/.well-known/acme-challenge) ;; *) return 1 ;; esac
        else
            [[ "${relative}" =~ ^/active/\.well-known/acme-challenge/[A-Za-z0-9_-]{1,128}$ &&
                "$(stat -c %h -- "${entry}")" == 1 &&
                "$(stat -c %s -- "${entry}")" -le 512 ]] || return 1
            value=$(<"${entry}")
            [[ "${value}" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]] || return 1
            # 原始字节只允许 key authorization 和最多一个换行，不能接受 Bash 丢弃的 NUL。
            { cmp -s -- "${entry}" <(printf '%s' "${value}") ||
                cmp -s -- "${entry}" <(printf '%s\n' "${value}"); } || return 1
        fi
    done < <(find "${directory}" -print0)
}

dockerAcmeWebrootEnsure() {
    local root=$1 directory="${1}/data/acme-webroot" intTrap termTrap pending=0 status=1
    dockerAcmeWebrootParentValidate "${root}" "${directory}" || return 1
    if [[ ! -e "${directory}" && ! -L "${directory}" ]]; then
        # 首次根目录也须完成权限初始化后才处理信号，不能遗留不可接管的半成品。
        intTrap=$(trap -p INT)
        termTrap=$(trap -p TERM)
        trap 'pending=130' INT
        trap 'pending=143' TERM
        if mkdir -- "${directory}" && chmod 0750 "${directory}" &&
            { [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" == 1 ]] ||
                chown "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" "${directory}"; }; then
            status=0
        fi
        if [[ -n "${intTrap}" ]]; then eval "${intTrap}"; else trap - INT; fi
        if [[ -n "${termTrap}" ]]; then eval "${termTrap}"; else trap - TERM; fi
        if [[ "${pending}" != 0 ]]; then
            if [[ "${pending}" == 130 ]]; then kill -INT "${BASHPID}"; else kill -TERM "${BASHPID}"; fi
            return 1
        fi
        [[ "${status}" == 0 ]] || return 1
    fi
    dockerAcmeWebrootTreeValidate "${root}" "${directory}"
}

dockerAcmeWebrootCleanup() {
    local root directory=${DOCKER_ACME_WEBROOT:-}
    [[ -n "${directory}" ]] || return 0
    root=$(dockerInstallRoot) || return 1
    [[ "${directory}" == "${root}/data/acme-webroot/active" &&
        "$(stat -c %d:%i -- "${directory}")" == "${DOCKER_ACME_WEBROOT_INODE}" ]] &&
        dockerAcmeWebrootTreeValidate "${root}" "${root}/data/acme-webroot" &&
        dockerRemoveManagedTree "${root}" "${directory}" || {
        dockerError '本次 ACME webroot 清理失败，保留候选与挑战目录'
        return 1
    }
    DOCKER_ACME_WEBROOT=
    DOCKER_ACME_WEBROOT_INODE=
}

dockerAcmeChallengeRestore() {
    local id ids failed=0
    local -a pending=()
    if [[ -n "${DOCKER_ACME_CONTAINER:-}" ]]; then
        ids=$(docker ps -aq --filter "label=io.padm.challenge=${DOCKER_ACME_CONTAINER}" \
            --filter "label=io.padm.project=${PADM_DOCKER_PROJECT}") || return 1
        while IFS= read -r id; do
            [[ -n "${id}" ]] || continue
            [[ "${id}" =~ ^[a-f0-9]{12,64}$ ]] &&
                docker rm -f "${id}" >/dev/null || failed=1
        done <<<"${ids}"
        if [[ "${failed}" != 0 ]]; then
            dockerError "ACME 挑战容器清理失败，恢复记录: ${DOCKER_ACME_RECOVERY:-}"
        fi
        [[ "${failed}" != 0 ]] || DOCKER_ACME_CONTAINER=
    fi
    # 挑战容器仍占端口时不能启动原服务，也不能丢弃恢复记录。
    [[ "${failed}" == 0 ]] || return 1
    dockerAcmeWebrootCleanup || return 1
    for id in "${DOCKER_ACME_STOPPED[@]}"; do
        if ! docker start "${id}" >/dev/null ||
            ! docker container inspect "${id}" | jq -e '
              length == 1 and .[0].State.Running == true and .[0].State.Restarting != true
            ' >/dev/null; then
            pending+=("${id}")
            failed=1
        fi
    done
    DOCKER_ACME_STOPPED=("${pending[@]}")
    if [[ "${failed}" == 0 ]]; then
        [[ -z "${DOCKER_ACME_RECOVERY}" ]] || rm -f -- "${DOCKER_ACME_RECOVERY}" || return 1
        DOCKER_ACME_RECOVERY=
        DOCKER_ACME_STOPPED=()
        DOCKER_ACME_PORT_PUBLISH=0
    else
        dockerError "ACME 挑战服务恢复失败，已保留容器恢复记录: ${DOCKER_ACME_RECOVERY:-}"
    fi
    return "${failed}"
}

dockerAcmeRuntimeSnapshot() {
    local root ids containers consumers
    local -a runningIds=()
    root=$(dockerInstallRoot) || return 1
    consumers=$(dockerTlsConsumers "${1}") || return 1
    ids=$(docker ps -q) || return 1
    while IFS= read -r id; do
        [[ -n "${id}" ]] || continue
        [[ "${id}" =~ ^[a-f0-9]{12,64}$ ]] || return 1
        runningIds+=("${id}")
    done <<<"${ids}"
    DOCKER_ACME_RUNNING='[]'
    [[ "${#runningIds[@]}" -gt 0 ]] || return 0
    containers=$(docker container inspect "${runningIds[@]}") || return 1
    DOCKER_ACME_RUNNING=$(jq -ce --arg root "${root}" --argjson consumers "${consumers}" '
      map(select(.Config.Labels["com.docker.compose.project"] == "padm-docker" and
        .Config.Labels["com.docker.compose.project.working_dir"] == $root)) |
      if all(.[]; .State.Running == true and
        .Config.Labels["io.padm.mode"] == "docker" and
        .Config.Labels["io.padm.project"] == "padm-docker")
      then [.[] | .Config.Labels["com.docker.compose.service"] |
        select(. as $service | $consumers | index($service) != null)] | unique
      else error("运行容器归属漂移") end
    ' <<<"${containers}") || return 1
}

dockerAcmePortOwners() {
    local ids id containers
    local -a runningIds=()
    ids=$(docker ps -q) || return 1
    while IFS= read -r id; do
        [[ -n "${id}" ]] || continue
        [[ "${id}" =~ ^[a-f0-9]{12,64}$ ]] || return 1
        runningIds+=("${id}")
    done <<<"${ids}"
    [[ "${#runningIds[@]}" -gt 0 ]] || { printf '[]\n'; return 0; }
    containers=$(docker container inspect "${runningIds[@]}") || return 1
    # Docker 的 publish 过滤不是宿主端口证明，必须读取实际 HostPort。
    jq -ce 'map(select(.State.Running == true and
      any(.HostConfig.PortBindings // {} | to_entries[];
        (.key | endswith("/tcp")) and any(.value[]?; .HostPort == "80"))))' <<<"${containers}"
}

dockerAcmeHostPortOwned() {
    local owners=$1 listeners line pid arguments ip port
    dockerTcpPortIsListening 80 || return 0
    command -v ss >/dev/null || {
        dockerError '缺少 ss，不能确认宿主 80 端口进程归属'
        return 1
    }
    listeners=$(ss -H -ltnp 'sport = :80') || return 1
    [[ -n "${listeners}" ]] || return 1
    while IFS= read -r line; do
        [[ "${line}" =~ users:\(\(\"docker-proxy\",pid=([0-9]+),fd=[0-9]+\)\)$ ]] || return 1
        pid=${BASH_REMATCH[1]}
        [[ -f "/proc/${pid}/cmdline" ]] || return 1
        arguments=$(tr '\0' '\n' <"/proc/${pid}/cmdline") || return 1
        [[ "$(sed -n '/^-proto$/{n;p;}' <<<"${arguments}")" == tcp &&
            "$(sed -n '/^-host-port$/{n;p;}' <<<"${arguments}")" == 80 ]] || return 1
        ip=$(sed -n '/^-container-ip$/{n;p;}' <<<"${arguments}") || return 1
        port=$(sed -n '/^-container-port$/{n;p;}' <<<"${arguments}") || return 1
        jq -e --arg ip "${ip}" --arg port "${port}/tcp" '
          any(.[]; any(.NetworkSettings.Networks[]; .IPAddress == $ip or .GlobalIPv6Address == $ip) and
            any(.HostConfig.PortBindings[$port][]?; .HostPort == "80"))
        ' <<<"${owners}" >/dev/null || return 1
    done <<<"${listeners}"
}

dockerAcmeOwnersValidate() {
    local owners=$1 root container service image
    root=$(dockerInstallRoot) || return 1
    dockerTrafficSafePath "${root}" "${root}/config/spec.json" &&
        dockerTrafficSafePath "${root}" "${root}/compose.json" &&
        dockerTrafficSafePath "${root}" "${root}/deployment.json" &&
        dockerConfigureSpecValidate "${root}/config/spec.json" &&
        dockerManagedSpecMatchesDeployment "${root}/config/spec.json" \
            "${root}/deployment.json" "${root}/images.env" &&
        cmp -s -- "${root}/compose.json" \
            <(dockerGenerateCompose "${root}/config/spec.json" /dev/stdout "${root}") || return 1
    while IFS= read -r container; do
        [[ -n "${container}" ]] || continue
        container="[${container}]"
        jq -e 'length == 1 and .[0].State.Running == true and .[0].State.Restarting != true' \
            <<<"${container}" >/dev/null || return 1
        service=$(jq -er '.[0].Config.Labels["com.docker.compose.service"]' <<<"${container}") || return 1
        case "${service}" in xray|sing-box|nginx) ;; *) return 1 ;; esac
        image=$(jq -er --arg service "${service}" '.images[$service]' "${root}/config/spec.json") || return 1
        jq -e --arg root "${root}" --arg service "${service}" --arg image "${image}" \
            --slurpfile deployment "${root}/deployment.json" --slurpfile compose "${root}/compose.json" '
          .[0] as $c | $c.Config.Labels as $labels |
          $labels["com.docker.compose.project"] == "padm-docker" and
          $labels["com.docker.compose.project.working_dir"] == $root and
          $labels["com.docker.compose.project.config_files"] == ($root + "/compose.json") and
          $labels["io.padm.mode"] == "docker" and $labels["io.padm.project"] == "padm-docker" and
          $labels["io.padm.component"] == $service and $c.Config.Image == $image and
          $c.HostConfig.NetworkMode != "host" and
          all($c.Mounts[]; .Type == "bind") and
          (($c.HostConfig.Tmpfs // {}) | keys | sort) ==
            ([$compose[0].services[$service].tmpfs[]? | split(":")[0]] | sort) and
          any($deployment[0].listeners[]; .service == $service and .public_port == 80 and .transport == "tcp") and
          ([$c.HostConfig.PortBindings | to_entries[] | . as $binding | .value[] |
            ((if (.HostIp | contains(":")) then "[" + .HostIp + "]"
              else (if .HostIp == "" then "0.0.0.0" else .HostIp // "0.0.0.0" end) end) +
              ":" + .HostPort + ":" + $binding.key)] | sort) ==
            ($compose[0].services[$service].ports | sort) and
          ($c.Mounts | map(select(.Type == "bind") | {source:.Source,target:.Destination,read_only:(.RW | not)}) |
            sort_by(.target)) ==
          ($compose[0].services[$service].volumes |
            map({source:(.source | sub("^\\$\\{PADM_DOCKER_ROOT\\}"; $root)),target,read_only}) | sort_by(.target))
        ' <<<"${container}" >/dev/null || {
            dockerError '80 端口容器不属于当前受管部署，未停止任何服务'
            return 1
        }
    done < <(jq -c '.[]' <<<"${owners}")
    dockerAcmeHostPortOwned "${owners}" || {
        dockerError '宿主 80 端口存在外部或无法归属的监听，未停止任何服务'
        return 1
    }
}

dockerAcmeWebrootDeploymentCheck() {
    local domain=$1 root owners
    root=$(dockerInstallRoot) || return 1
    dockerTrafficSafePath "${root}" "${root}/config/spec.json" &&
        [[ -f "${root}/config/spec.json" ]] &&
        jq -e --arg domain "${domain}" '.tls.http01 == true and .tls.domain == $domain' \
            "${root}/config/spec.json" >/dev/null || {
        dockerError 'webroot 需要先显式启用该域名的受管 HTTP 挑战入口'
        return 1
    }
    dockerAcmeWebrootTreeValidate "${root}" "${root}/data/acme-webroot" &&
        dockerTrafficSafePath "${root}" "${root}/config/nginx/default.conf" &&
        [[ -f "${root}/config/nginx/default.conf" &&
            -z "$(find "${root}/config/nginx" ! -type f ! -type d -print -quit)" ]] &&
        cmp -s -- "${root}/config/nginx/default.conf" \
            <(dockerGenerateNginxConfig "${root}/config/spec.json" /dev/stdout) || return 1
    owners=$(dockerAcmePortOwners) || return 1
    jq -e 'length == 1 and .[0].Config.Labels["com.docker.compose.service"] == "nginx"' \
        <<<"${owners}" >/dev/null && dockerAcmeOwnersValidate "${owners}" || {
        dockerError 'webroot 需要正在运行且归属、挂载和双栈端口均一致的受管 Nginx'
        return 1
    }
}

dockerAcmeWebrootPrepare() {
    local domain=$1 candidate=$2 root directory intTrap termTrap pending=0 status=1
    root=$(dockerInstallRoot) || return 1
    directory="${root}/data/acme-webroot"
    [[ -z "${DOCKER_ACME_WEBROOT}" && -z "${DOCKER_ACME_CONTAINER}" ]] &&
        dockerTrafficSafePath "${root}" "${candidate}" && [[ -d "${candidate}" ]] &&
        dockerAcmeWebrootDeploymentCheck "${domain}" &&
        dockerAcmeWebrootTreeValidate "${root}" "${directory}" true || {
        dockerError 'ACME webroot 未就绪或已有未完成挑战，本次未修改服务'
        return 1
    }
    # 初始化完成后才处理信号，清理必须看到本次 inode 和可验证的归属。
    intTrap=$(trap -p INT)
    termTrap=$(trap -p TERM)
    trap 'pending=130' INT
    trap 'pending=143' TERM
    if mkdir -- "${directory}/active"; then
        DOCKER_ACME_WEBROOT="${directory}/active"
        if DOCKER_ACME_WEBROOT_INODE=$(stat -c %d:%i -- "${DOCKER_ACME_WEBROOT}") &&
            chmod 0750 "${DOCKER_ACME_WEBROOT}" &&
            mkdir -p -- "${DOCKER_ACME_WEBROOT}/.well-known/acme-challenge" &&
            find "${DOCKER_ACME_WEBROOT}" -type d -exec chmod 0750 {} + &&
            { [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" == 1 ]] ||
                chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" "${DOCKER_ACME_WEBROOT}"; } &&
            dockerAcmeWebrootTreeValidate "${root}" "${directory}"; then
            status=0
        fi
    fi
    if [[ -n "${intTrap}" ]]; then eval "${intTrap}"; else trap - INT; fi
    if [[ -n "${termTrap}" ]]; then eval "${termTrap}"; else trap - TERM; fi
    if [[ "${pending}" != 0 ]]; then
        if [[ "${pending}" == 130 ]]; then kill -INT "${BASHPID}"; else kill -TERM "${BASHPID}"; fi
        return 1
    fi
    return "${status}"
}

dockerAcmeChallengePrepare() {
    local provider=$1 candidate=$2 root owners
    if [[ "${provider}" == webroot ]]; then
        dockerAcmeWebrootPrepare "${3}" "${candidate}"
        return $?
    fi
    [[ "${provider}" == standalone ]] || return 0
    [[ "${#DOCKER_ACME_STOPPED[@]}" == 0 && "${DOCKER_ACME_PORT_PUBLISH}" == 0 ]] || return 1
    root=$(dockerInstallRoot) || return 1
    dockerTrafficSafePath "${root}" "${candidate}" &&
        [[ -d "${candidate}" && ! -L "${candidate}" ]] || return 1
    owners=$(dockerAcmePortOwners) || return 1
    # 首次 standalone 没有部署，只有发现拥有者时才要求受管配置证明。
    if [[ "${owners}" != '[]' ]]; then
        dockerAcmeOwnersValidate "${owners}" || return 1
    else
        dockerAcmeHostPortOwned "${owners}" || return 1
    fi
    if [[ "$(jq 'length' <<<"${owners}")" != 0 ]]; then
        printf 'HTTP-01 临时暂停 80 端口服务: %s；同容器其它端口也会短暂停机。\n' \
            "$(jq -r 'map(.Config.Labels["com.docker.compose.service"]) | unique | join(",")' <<<"${owners}")"
        # 停止前登记，部分停止失败或信号到达时仍恢复全部原运行容器。
        DOCKER_ACME_RECOVERY="${candidate}/challenge.json"
        jq '[.[] | {id:.Id,service:.Config.Labels["com.docker.compose.service"]}]' \
            <<<"${owners}" >"${DOCKER_ACME_RECOVERY}" &&
            chmod 0600 "${DOCKER_ACME_RECOVERY}" || return 1
        mapfile -t DOCKER_ACME_STOPPED < <(jq -r '.[].Id' <<<"${owners}")
        docker stop "${DOCKER_ACME_STOPPED[@]}" >/dev/null || {
            dockerAcmeChallengeRestore || true
            return 1
        }
    fi
    owners=$(dockerAcmePortOwners) || {
        dockerAcmeChallengeRestore || true
        return 1
    }
    if dockerTcpPortIsListening 80 || [[ "${owners}" != '[]' ]]; then
        dockerError '挑战前 80 端口未完全释放，正在恢复原运行容器'
        dockerAcmeChallengeRestore || true
        return 1
    fi
    DOCKER_ACME_PORT_PUBLISH=1
}

dockerAcmeRenewProbe() {
    local image=$1 credentials=$2 account=$3 output=$4 domain=$5 config hook status=0
    shift 5
    config="${account}/${domain}/${domain}.conf"
    [[ -f "${config}" ]] || config="${account}/${domain}_ecc/${domain}.conf"
    [[ -f "${config}" && ! -L "${config}" &&
        "$(grep -c '^Le_PreHook=' "${config}")" -le 1 ]] || return 1
    hook=$(grep '^Le_PreHook=' "${config}" || true)
    # 用工具自己的到期及 ARI 判断，只在真正进入挑战时留下无秘密标记。
    sed '/^Le_PreHook=/d' "${config}" >"${output}/renew-probe.conf" || return 1
    printf "Le_PreHook='printf due > /var/lib/padm/tls-output/renew.due; exit 1'\n" \
        >>"${output}/renew-probe.conf" || return 1
    cp -- "${output}/renew-probe.conf" "${config}" || return 1
    if dockerAcmeRun "${image}" "${credentials}" "${account}" "${output}" \
        --renew -d "${domain}" "$@" >/dev/null 2>&1; then status=0; else status=$?; fi
    sed '/^Le_PreHook=/d' "${config}" >"${output}/renew-probe.conf" || return 1
    [[ -z "${hook}" ]] || printf '%s\n' "${hook}" >>"${output}/renew-probe.conf" || return 1
    cp -- "${output}/renew-probe.conf" "${config}" &&
        rm -f -- "${output}/renew-probe.conf" || return 1
    if [[ -f "${output}/renew.due" && ! -L "${output}/renew.due" &&
        "$(<"${output}/renew.due")" == due && "${status}" != 0 ]]; then
        rm -f -- "${output}/renew.due" || return 1
        return 0
    fi
    [[ "${status}" != 2 ]] || return 2
    return 1
}

dockerAcmeRun() {
    local image=$1 credentials=$2 acmeData=$3 output=$4
    local status input=/dev/null
    local -a ports=() containerArgs=() webrootMount=()
    shift 4
    if [[ -n "${credentials}" ]]; then
        dockerRenewalCredentialsValidate "${credentials}" || return 1
        input=${credentials}
    fi
    if [[ "${DOCKER_ACME_PORT_PUBLISH}" == 1 ]]; then
        ports=(--publish 0.0.0.0:80:8080/tcp --publish '[::]:80:8080/tcp')
    fi
    if [[ -n "${DOCKER_ACME_WEBROOT}" ]]; then
        webrootMount=(--volume "${DOCKER_ACME_WEBROOT}:/var/lib/padm/acme-webroot")
    fi
    if [[ "${DOCKER_ACME_PORT_PUBLISH}" == 1 || -n "${DOCKER_ACME_WEBROOT}" ]]; then
        DOCKER_ACME_CONTAINER="padm-acme-${BASHPID:-$$}-${RANDOM}"
        containerArgs=(--name "${DOCKER_ACME_CONTAINER}" --label "io.padm.challenge=${DOCKER_ACME_CONTAINER}")
    fi
    if docker run --rm -i --read-only --cap-drop ALL "${ports[@]}" "${containerArgs[@]}" \
        --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,nodev,size=16m \
        --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
        --volume "${acmeData}:/var/lib/padm/acme" \
        --volume "${output}:/var/lib/padm/tls-output" \
        "${webrootMount[@]}" \
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
' "$@" <"${input}"; then status=0; else status=$?; fi
    return "${status}"
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
        --dns) [[ "$#" -ge 2 && -z "${provider}" && "$2" =~ ^dns_[a-z0-9_]+$ ]] || return "${PADM_DOCKER_RC_USAGE}"; provider=$2; shift 2 ;;
        --standalone) [[ -z "${provider}" ]] || return "${PADM_DOCKER_RC_USAGE}"; provider=standalone; shift ;;
        --webroot) [[ -z "${provider}" ]] || return "${PADM_DOCKER_RC_USAGE}"; provider=webroot; shift ;;
        --credentials) [[ "$#" -ge 2 ]] || return "${PADM_DOCKER_RC_USAGE}"; credentials=$2; shift 2 ;;
        --ops-image) [[ "$#" -ge 2 ]] || return "${PADM_DOCKER_RC_USAGE}"; requestedImage=$2; shift 2 ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    dockerDomainIsValid "${domain}" && dockerEmailIsValid "${email}" &&
        { [[ "${provider}" =~ ^dns_[a-z0-9_]+$ && -n "${credentials}" ]] ||
            [[ ( "${provider}" == standalone || "${provider}" == webroot ) && -z "${credentials}" ]]; } || {
        dockerError 'acme 需要合法 domain/email 与互斥的 --dns/--credentials、--standalone 或 --webroot'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    if [[ "${provider}" =~ ^dns_ ]]; then
        credentials=$(dockerResolveRegularFile "${credentials}") || return "${PADM_DOCKER_RC_USAGE}"
        dockerRenewalCredentialsValidate "${credentials}" || {
            dockerError 'DNS 凭据必须为仅持有者读取的 NAME=value 文件，不得改写工具运行环境'
            return "${PADM_DOCKER_RC_STATE}"
        }
    fi
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
    local -a keyArgs=() issueKeyArgs=(--keylength 2048) challengeArgs=(--dns "${provider}")
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${action}" == renew &&
        -f "${root}/data/acme/${domain}_ecc/${domain}.conf" &&
        ! -f "${root}/data/acme/${domain}/${domain}.conf" ]]; then
        keyArgs=(--ecc)
    fi
    if [[ "${action}" == issue && ! -f "${root}/data/acme/${domain}/${domain}.conf" ]]; then
        keyArgs=(--ecc)
        issueKeyArgs=(--keylength ec-256)
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
    if [[ "${provider}" == standalone || "${provider}" == webroot ]]; then
        dockerAcmeRuntimeSnapshot "${domain}" || return "${PADM_DOCKER_RC_STATE}"
        if [[ "${provider}" == standalone ]]; then
            challengeArgs=(--standalone --httpport 8080)
        else
            challengeArgs=(--webroot /var/lib/padm/acme-webroot)
        fi
        if [[ "${action}" == renew ]]; then
            dockerRenewalAccountCheck "${root}" "${domain}" "${provider}" || return "${PADM_DOCKER_RC_STATE}"
            if dockerAcmeRenewProbe "${image}" "${credentials}" "${candidate}/acme" "${candidate}" \
                "${domain}" "${keyArgs[@]}"; then status=0; else status=$?; fi
            if [[ "${status}" != 0 ]]; then
                dockerCleanupTlsCandidate || return "${PADM_DOCKER_RC_STATE}"
                [[ "${status}" != 2 ]] || return 2
                dockerError '候选 ACME 续期预检失败，服务未暂停'
                return "${PADM_DOCKER_RC_STATE}"
            fi
        fi
    fi
    dockerAcmeChallengePrepare "${provider}" "${candidate}" "${domain}" || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${action}" == "issue" ]]; then
        dockerAcmeRun "${image}" "${credentials}" "${candidate}/acme" "${candidate}" \
            --issue "${challengeArgs[@]}" "${issueKeyArgs[@]}" -d "${domain}" --accountemail "${email}" >/dev/null 2>&1 || {
            dockerError '候选 ACME 申请失败，现有证书和 ACME 账户未修改'
            dockerAcmeChallengeRestore || return "${PADM_DOCKER_RC_STATE}"
            dockerCleanupTlsCandidate || true
            return "${PADM_DOCKER_RC_STATE}"
        }
    else
        challengeArgs=()
        [[ "${provider}" != standalone ]] || challengeArgs=(--httpport 8080)
        if dockerAcmeRun "${image}" "${credentials}" "${candidate}/acme" "${candidate}" \
            --renew -d "${domain}" "${keyArgs[@]}" "${challengeArgs[@]}" >/dev/null 2>&1; then
            status=0
        else
            status=$?
        fi
        if [[ "${status}" != 0 ]]; then
            dockerAcmeChallengeRestore || return "${PADM_DOCKER_RC_STATE}"
            dockerCleanupTlsCandidate || return "${PADM_DOCKER_RC_STATE}"
            [[ "${status}" != 2 ]] || return 2
            dockerError '候选 ACME 续期失败，现有证书和 ACME 账户未修改'
            return "${PADM_DOCKER_RC_STATE}"
        fi
    fi
    dockerAcmeChallengeRestore || return "${PADM_DOCKER_RC_STATE}"
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
