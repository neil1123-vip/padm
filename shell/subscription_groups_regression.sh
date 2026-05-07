#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

export PADM_SUBSCRIPTION_GROUPS_DIR="${TMP_DIR}/subscribe_groups"
export PADM_SUBSCRIBE_LOCAL_DIR="${TMP_DIR}/subscribe_local"

# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/protocols.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/runtime.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/protocol_runtime.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/groups.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/subscription.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/control.sh"

echoContent() {
    return 0
}

jq() {
    if [[ "$#" -eq 0 ]]; then
        command jq . >/dev/null
    else
        command jq "$@"
    fi
}

SUBSCRIBE_CAPTURE_DIR="${TMP_DIR}/subscribe_local"
appendDefaultSubscribeLine() {
    local user=$1
    local line=$2
    mkdir -p "${SUBSCRIBE_CAPTURE_DIR}/default"
    printf '%s\n' "${line}" >>"${SUBSCRIBE_CAPTURE_DIR}/default/${user}"
}

appendClashMetaSubscribeBlock() {
    local user=$1
    local block=$2
    mkdir -p "${SUBSCRIBE_CAPTURE_DIR}/clashMeta"
    printf '%s\n' "${block}" >>"${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${user}"
}

appendSingBoxSubscribeLocalConfig() {
    local user=$1
    local jqFilter=$2
    local targetPath="${SUBSCRIBE_CAPTURE_DIR}/sing-box/${user}"
    mkdir -p "${SUBSCRIBE_CAPTURE_DIR}/sing-box"
    [[ -f "${targetPath}" ]] || printf '[]\n' >"${targetPath}"
    jq -r "${jqFilter}" "${targetPath}" | jq . >"${targetPath}.tmp"
    mv "${targetPath}.tmp" "${targetPath}"
}

assertCapturedSubscribeOutputs() {
    local user=$1
    local expectedDefault=$2
    local expectedServer=$3
    local expectedSNI=$4
    local expectedNetwork=$5
    local expectedType=$6

    grep -qxF "${expectedDefault}" "${SUBSCRIBE_CAPTURE_DIR}/default/${user}"
    grep -qx "    server: ${expectedServer}" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${user}"
    if grep -q "^    servername:" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${user}"; then
        grep -qx "    servername: ${expectedSNI}" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${user}"
    elif grep -q "^    sni:" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${user}"; then
        grep -qx "    sni: ${expectedSNI}" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${user}"
    fi
    jq -e --arg server "${expectedServer}" --arg sni "${expectedSNI}" --arg network "${expectedNetwork}" --arg type "${expectedType}" '
      .[0].type == $type and
      .[0].server == $server and
      .[0].tls.server_name == $sni and
      (if $network == "tcp" then (.[0].transport | not) else .[0].transport.type == $network end)
    ' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/${user}" >/dev/null
}

visionLink=$(serializeVlessRealityVisionLink "uuid-a" "node.example.com" "443" "www.microsoft.com" "pubkey" "pqv" "user-a")
[[ "${visionLink}" == "vless://uuid-a@node.example.com:443?encryption=none&security=reality&pqv=pqv&type=tcp&sni=www.microsoft.com&fp=chrome&pbk=pubkey&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision#user-a" ]]
grpcLink=$(serializeVlessRealityGrpcLink "uuid-a" "node.example.com" "8443" "www.microsoft.com" "pubkey" "pqv" "user-a")
[[ "${grpcLink}" == "vless://uuid-a@node.example.com:8443?encryption=none&security=reality&pqv=pqv&type=grpc&sni=www.microsoft.com&fp=chrome&pbk=pubkey&sid=6ba85179e30d4fc2&path=grpc&serviceName=grpc#user-a" ]]
domain=tls.example.com
currentHost=
collectTLSProfile
[[ "${tlsCertDomain}" == "tls.example.com" ]]
[[ "${tlsSNI}" == "tls.example.com" ]]
protocolMeta 7 security | grep -qx reality
protocolMeta 7 transport | grep -qx tcp
protocolSelectionNeedsReality 7
protocolSelectionNeedsCertificate 0
protocolSelectionNeedsUdp 6
protocolSelectionTransportHas 7 tcp
protocolSelectionSecurityHas 7 reality

parseInstallArgs --install-type custom --core xray --protocols 7 --domain node.example.com --reality-target www.microsoft.com:443 --reality-server-name www.microsoft.com --entry-host node.example.com --reuse-last no
[[ "${AUTO_REALITY_TARGET}" == "www.microsoft.com:443" ]]
[[ "${AUTO_REALITY_SERVER_NAME}" == "www.microsoft.com" ]]
[[ "${AUTO_ENTRY_HOST}" == "node.example.com" ]]
[[ "$(autoValueForKey reality_target)" == "www.microsoft.com:443" ]]

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
coreInstallType=1
currentHost="tls.example.com"
realityEntryHost="node.example.com"
xrayVLESSRealitySNI="www.microsoft.com"
currentRealityPublicKey="pubkey"
currentRealityMldsa65Verify="pqv"
defaultBase64Code vlessReality 443 user-a-main uuid-a "" ""
expectedVisionLink=$(serializeVlessRealityVisionLink "uuid-a" "node.example.com" "443" "www.microsoft.com" "pubkey" "pqv" "user-a-main")
assertCapturedSubscribeOutputs "user" "${expectedVisionLink}" "node.example.com" "www.microsoft.com" "tcp" "vless"
jq -e '.[0].flow == "xtls-rprx-vision" and .[0].tls.reality.public_key == "pubkey"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
defaultBase64Code vlessRealityGRPC 8443 user-a-grpc uuid-a "" ""
expectedGrpcLink=$(serializeVlessRealityGrpcLink "uuid-a" "node.example.com" "8443" "www.microsoft.com" "pubkey" "pqv" "user-a-grpc")
assertCapturedSubscribeOutputs "user" "${expectedGrpcLink}" "node.example.com" "www.microsoft.com" "grpc" "vless"
jq -e '.[0].transport.service_name == "grpc" and .[0].tls.reality.short_id == "6ba85179e30d4fc2"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code vlesstcp 443 tls-user uuid-tls "" ""
assertCapturedSubscribeOutputs "tls" "vless://uuid-tls@tls.example.com:443?encryption=none&security=tls&type=tcp&host=tls.example.com&fp=chrome&headerType=none&sni=tls.example.com&flow=xtls-rprx-vision#tls-user" "tls.example.com" "tls.example.com" "tcp" "vless"
jq -e '.[0].flow == "xtls-rprx-vision" and (.[0].tls.reality | not)' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code vlessws 443 tls-ws-user uuid-ws "edge.example.com" "/ws-path"
assertCapturedSubscribeOutputs "tls" "vless://uuid-ws@edge.example.com:443?encryption=none&security=tls&type=ws&host=tls.example.com&sni=tls.example.com&fp=chrome&path=/ws-path#tls-ws-user" "edge.example.com" "tls.example.com" "ws" "vless"
jq -e '.[0].transport.path == "/ws-path" and .[0].transport.headers.Host == "tls.example.com" and .[0].multiplex.enabled == false' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
currentPath="svc-"
defaultBase64Code vlessgrpc 443 tls-grpc-user uuid-grpc "edge.example.com" ""
assertCapturedSubscribeOutputs "tls" "vless://uuid-grpc@edge.example.com:443?encryption=none&security=tls&type=grpc&host=tls.example.com&path=svc-grpc&serviceName=svc-grpc&fp=chrome&alpn=h2&sni=tls.example.com#tls-grpc-user" "edge.example.com" "tls.example.com" "grpc" "vless"
jq -e '.[0].transport.service_name == "svc-grpc" and .[0].packet_encoding == "xudp"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code vmessws 443 tls-vmess-user uuid-vmess "edge.example.com" "/vmess-ws"
vmessWsLink=$(sed -n '1p' "${SUBSCRIBE_CAPTURE_DIR}/default/tls")
[[ "${vmessWsLink}" == vmess://* ]]
assertCapturedSubscribeOutputs "tls" "${vmessWsLink}" "edge.example.com" "tls.example.com" "ws" "vmess"
jq -e '.[0].alter_id == 0 and .[0].transport.max_early_data == 2048 and .[0].packet_encoding == "packetaddr"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code trojan 443 tls-trojan-user pass-trojan "" ""
assertCapturedSubscribeOutputs "tls" "trojan://pass-trojan@tls.example.com:443?peer=tls.example.com&fp=chrome&sni=tls.example.com&alpn=http/1.1#tls-trojan-user_Trojan" "tls.example.com" "tls.example.com" "tcp" "trojan"
jq -e '.[0].password == "pass-trojan" and .[0].tls.alpn[0] == "http/1.1"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
currentPath="svc-"
defaultBase64Code trojangrpc 443 tls-trojan-grpc-user pass-trojan-grpc "edge.example.com" ""
assertCapturedSubscribeOutputs "tls" "trojan://pass-trojan-grpc@edge.example.com:443?encryption=none&peer=tls.example.com&security=tls&type=grpc&fp=chrome&sni=tls.example.com&alpn=h2&path=svc-trojangrpc&serviceName=svc-trojangrpc#tls-trojan-grpc-user" "edge.example.com" "tls.example.com" "grpc" "trojan"
jq -e '.[0].transport.service_name == "svc-trojangrpc" and .[0].tls.insecure == true and .[0].multiplex.enabled == false' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code vmessHTTPUpgrade 443 tls-httpupgrade-user uuid-http "edge.example.com" "/upgrade"
httpUpgradeLink=$(sed -n '1p' "${SUBSCRIBE_CAPTURE_DIR}/default/tls")
[[ "${httpUpgradeLink}" == "   vmess://"* ]]
assertCapturedSubscribeOutputs "tls" "${httpUpgradeLink}" "edge.example.com" "tls.example.com" "httpupgrade" "vmess"
jq -e '.[0].security == "auto" and .[0].transport.path == "/upgrade" and .[0].packet_encoding == "packetaddr"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
singBoxAnyTLSPort=8443
defaultBase64Code anytls 443 tls-any-user pass-any "" ""
assertCapturedSubscribeOutputs "tls" "anytls://pass-any@tls.example.com:8443?peer=tls.example.com&insecure=0&sni=tls.example.com#tls-any-user" "tls.example.com" "tls.example.com" "tcp" "anytls"
jq -e '.[0].password == "pass-any" and .[0].server_port == 8443' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
singBoxHysteria2Port=9443
hysteria2ClientUploadSpeed=100
hysteria2ClientDownloadSpeed=200
defaultBase64Code hysteria 8443 tls-hysteria-user pass-hysteria "" ""
assertCapturedSubscribeOutputs "tls" "hysteria2://pass-hysteria@tls.example.com:9443?peer=tls.example.com&insecure=0&sni=tls.example.com&alpn=h3#tls-hysteria-user" "tls.example.com" "tls.example.com" "tcp" "hysteria2"
jq -e '.[0].password == "pass-hysteria" and .[0].up_mbps == 100 and .[0].down_mbps == 200 and .[0].tls.alpn[0] == "h3"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
tuicAlgorithm="bbr"
defaultBase64Code tuic 9443 tls-tuic-user uuid-tuic_pass-tuic "" ""
grep -qxF "tuic://uuid-tuic:pass-tuic@tls.example.com:9443?congestion_control=bbr&alpn=h3&sni=tls.example.com&udp_relay_mode=native&allow_insecure=0#tls-tuic-user" "${SUBSCRIBE_CAPTURE_DIR}/default/tls"
grep -qx "    server: tls.example.com" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls"
grep -qx "    udp-relay-mode: native" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls"
grep -qx "    disable-sni: false" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls"
grep -qx "    sni: tls.example.com" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls"
jq -e '.[0].type == "tuic" and .[0].server == "tls.example.com" and .[0].tls.server_name == "tls.example.com"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null
jq -e '.[0].uuid == "uuid-tuic" and .[0].password == "pass-tuic" and .[0].congestion_control == "bbr" and .[0].tls.alpn[0] == "h3"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code naive 443 tls-naive-user pass-naive "" ""
grep -qxF "naive+https://tls-naive-user:pass-naive@tls.example.com:443?padding=true#tls-naive-user" "${SUBSCRIBE_CAPTURE_DIR}/default/tls"
[[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls" ]]
jq -e '. == []' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls" >/dev/null

ensureSubscriptionGroupsState
jq -e '.version == 2 and .active_group == "default" and (.groups | length == 1)' "$(subscriptionGroupsFile)" >/dev/null

cat >"$(subscriptionGroupsFile)" <<'JSON'
{
  "version": 1,
  "active_group": "edge-group",
  "groups": [
    {
      "id": "edge-group",
      "name": "Edge Group",
      "sources": [
        {"id": "edge", "name": "Edge", "scheme": "https", "host": "example.com", "port": "443", "enabled": true, "sync_status": "failed", "last_sync_error": {"type": "unreachable", "message": "old"}}
      ],
      "user_groups": [
        {"id": "team-a", "name": "Team A", "enabled": true, "allowed_sources": ["edge"], "traffic_limit_gb": "1", "uuid": "11111111-1111-1111-1111-111111111111"}
      ],
      "sync": {"enabled": true},
      "traffic": {"user_groups": {"team-a": {"upload": 1, "download": 2, "sources": {"edge": {"upload": 1, "download": 2}}}}, "sources": {"edge": {"upload": 1, "download": 2}}, "admin": {"sources": {"edge": {"upload": 0, "download": 0}}}}
    }
  ]
}
JSON

ensureSubscriptionGroupsState
jq -e '
  .version == 2 and
  .active_group == "edge-group" and
  (.groups[0].sync.remote_enabled == true) and
  (.groups[0].sync.quota_auto_apply == false) and
  any(.groups[0].sources[]; .id == "main" and .role == "main") and
  any(.groups[0].sources[]; .id == "edge" and .port == 443) and
  (.groups[0].user_groups[0].traffic_limit_gb == 1)
' "$(subscriptionGroupsFile)" >/dev/null

setSubscriptionSourceEnabled edge false
jq -e '.groups[0].sources[] | select(.id == "edge" and .enabled == false)' "$(subscriptionGroupsFile)" >/dev/null
setSubscriptionSourceEnabled main false
jq -e '.groups[0].sources[] | select(.id == "main" and .enabled == true)' "$(subscriptionGroupsFile)" >/dev/null
clearSubscriptionSourceSyncError edge
jq -e '(.groups[0].sources[] | select(.id == "edge") | has("last_sync_error")) | not' "$(subscriptionGroupsFile)" >/dev/null
removeSubscriptionSourceState edge
jq -e '(.groups[0].sources | map(.id) | index("edge") | not) and (.groups[0].traffic.sources | has("edge") | not) and (.groups[0].traffic.user_groups["team-a"].sources | has("edge") | not)' "$(subscriptionGroupsFile)" >/dev/null

currentHost="self.example.com"
subscribeDomain="self.example.com"
subscribePort=39778
addSubscriptionSourceState self-ref SelfRef https self.example.com 39778
setSubscriptionSourceControlToken self-ref token
setUserSubscriptionSources team-a '["self-ref"]'
subscriptionRemoteSyncPlan | jq -e '.[] | select(.source_id == "self-ref" and .status == "self_reference" and .error_detail.type == "self_reference")' >/dev/null
runSubscriptionRemoteSync | jq -e '.[] | contains("self-ref")' >/dev/null
subscriptionGroupsStateRead -e '.groups[0].sources[] | select(.id == "self-ref" and .sync_status == "failed" and .last_sync_error.type == "self_reference")' >/dev/null

echo "subscription-groups-regression-ok"
