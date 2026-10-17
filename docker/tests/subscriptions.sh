#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-subscriptions.XXXXXX")
trap '[[ "${PADM_TEST_KEEP:-0}" == 1 ]] || rm -rf -- "${TEST_ROOT}"' EXIT
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || {
    printf 'docker-subscriptions-regression requires Linux root\n' >&2
    exit 1
}

export PADM_DOCKER_SKIP_CHOWN=1
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
mkdir -p "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data/subscription"

# 分享组只依赖已有的 Docker 规格和渲染器，宿主动作全部替换为无副作用夹具。
source "${PROJECT_ROOT}/install-docker.sh"
dockerHostPreflight() { :; }
dockerLockInstalledDeployment() { :; }
dockerReleaseDeploymentLock() { :; }
dockerSetupCleanup() { :; }
dockerCleanupStagedBundle() { :; }
dockerManifestCleanup() { :; }
dockerEntryCleanup() { :; }

fail() {
    printf 'docker-subscriptions-regression-fail: %s\n' "$*" >&2
    exit 1
}

reject() {
    local status=0
    "$@" >"${TEST_ROOT}/reject.out" 2>&1 || status=$?
    if [[ "${status}" -eq 0 ]]; then
        fail "应拒绝: $*"
    fi
    return 0
}

ALICE=11111111-1111-4111-8111-111111111111
BOB=22222222-2222-4222-8222-222222222222
ALICE_UUID=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
BOB_UUID=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb
MAIN_TOKEN=0123456789abcdef0123456789abcdef
MAIN_UUID=33333333-3333-4333-8333-333333333333
SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"

jq -n --arg alice "${ALICE}" --arg bob "${BOB}" \
    --arg aliceUuid "${ALICE_UUID}" --arg bobUuid "${BOB_UUID}" \
    --arg token "${MAIN_TOKEN}" '
  {
    schema_version: 3,
    release: {version:"3.1.8", manifest_sha256:("1"*64), signature_identity:"fixture"},
    core: {type:"xray", secondary_type:null, protocols:[
      {id:1, core:"xray", server:"reality.example.com", public_port:443,
       address_families:["ipv4"], listener_id:"entry-reality", name:"Reality",
       uuid:"33333333-3333-4333-8333-333333333333",
       reality:{server_name:"reality.example.com", target_host:"reality.example.com",
         target_port:443, private_key:("A"*43), public_key:("B"*43), short_id:"1234abcd"}},
      {id:21, core:"xray", server:"ws.example.com", public_port:8443,
       address_families:["ipv4"], listener_id:"entry-ws", name:"WebSocket",
       uuid:"44444444-4444-4444-8444-444444444444",
        websocket:{domain:"ws.example.com", path:"padmtest",
         backend_port:31297, tls_port:8443}}
    ]},
    tls: {domain:"ws.example.com"},
    subscription: {enabled:true, token:$token},
    images: {
      xray:"ghcr.io/example/padm-xray:test@sha256:" + ("1"*64),
      "sing-box":"ghcr.io/example/padm-sing-box:test@sha256:" + ("1"*64),
      nginx:"ghcr.io/example/padm-nginx:test@sha256:" + ("1"*64),
      ops:"ghcr.io/example/padm-ops:test@sha256:" + ("1"*64),
      net:"ghcr.io/example/padm-net:test@sha256:" + ("1"*64)
    },
    host_integrations: [],
    accounts: [
      {id:$alice, name:"Alice", enabled:true, uuid:$aliceUuid,
       password:"Alice.-~@+=:Secret", shadowsocks_password:null,
       listeners:["entry-reality"]},
      {id:$bob, name:"Bob", enabled:true, uuid:$bobUuid,
       password:"Bob.-~@+=:Secret", shadowsocks_password:null,
       listeners:["entry-ws"]}
    ]
  }
' >"${SPEC}"
chmod 0600 "${SPEC}"
dockerConfigureSpecValidate "${SPEC}" || fail '初始订阅规格校验失败'
printf 'main subscription sentinel\n' >"${PADM_DOCKER_INSTALL_DIR}/data/subscription/${MAIN_TOKEN}"
chmod 0640 "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${MAIN_TOKEN}"
BASE_FILE="${TEST_ROOT}/base-subscription.txt"
dockerGenerateSubscription "${SPEC}" "${BASE_FILE}" || fail '主订阅生成失败'
grep -q "${MAIN_UUID}" "${BASE_FILE}" || fail '主订阅默认未包含入口 URI'

# 部署主订阅只读输出，不依赖分享组状态，也不能改写已有发布文件。
(
    export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/base-query"
    queryRoot="${PADM_DOCKER_INSTALL_DIR}"
    querySpec="${queryRoot}/config/spec.json"
    mkdir -p -- "${queryRoot}/config" "${queryRoot}/data/subscription"
    printf 'published sentinel\n' >"${queryRoot}/data/subscription/${MAIN_TOKEN}"
    dockerTrafficCollect() { fail '主订阅查询触发流量采集'; }
    baseQuerySnapshot() {
        (
            cd -- "${queryRoot}"
            find . -printf '%P|%y|%m|%u|%g\n' | LC_ALL=C sort
            find . -type f -print0 | sort -z | xargs -0 -r sha256sum
        )
    }
    for baseCase in published standard shared disabled-account disabled reality legacy; do
        authority=ws.example.com:8443
        case "${baseCase}" in
        published) filter='.' ;;
        standard)
            filter='(.core.protocols[] | select(.id == 21) | .public_port) = 443 |
              (.core.protocols[] | select(.id == 1) | .public_port) = 4443'
            authority=ws.example.com
            ;;
        shared)
            filter='.core.protocols |= map(.server = "proxy.example.com") |
              .reality_stream = {listener_id:"entry-reality",website_listener_id:"entry-ws"}'
            authority=ws.example.com
            ;;
        disabled-account) filter='.accounts[0].enabled = false' ;;
        disabled) filter='.subscription.enabled = false' ;;
        reality)
            filter='.subscription.enabled = false | .tls = null |
              .core.protocols |= map(select(.id == 1)) |
              .accounts |= map(select(.listeners == ["entry-reality"]))'
            ;;
        legacy)
            filter='.schema_version = 1 | del(.accounts, .core.secondary_type) |
              .core.protocols = [.core.protocols[] | select(.id == 21) |
                del(.core, .listener_id, .websocket.backend_port, .websocket.tls_port)]'
            ;;
        esac
        jq "${filter}" "${SPEC}" >"${querySpec}"
        chmod 0600 "${querySpec}"
        dockerConfigureSpecValidate "${querySpec}" || fail "${baseCase}: 主订阅查询夹具无效"
        jq '.subscription.enabled = true' "${querySpec}" >"${TEST_ROOT}/base-expected-spec.json"
        dockerGenerateSubscription "${TEST_ROOT}/base-expected-spec.json" "${TEST_ROOT}/base-expected.txt"
        before=$(baseQuerySnapshot)
        dockerMain subscription content --base >"${TEST_ROOT}/base-content.txt" ||
            fail "${baseCase}: 主订阅内容查询失败"
        cmp -s "${TEST_ROOT}/base-expected.txt" "${TEST_ROOT}/base-content.txt" ||
            fail "${baseCase}: 主订阅查询与现有生成器内容不同"
        case "${baseCase}" in
        published)
            cmp -s "${BASE_FILE}" "${TEST_ROOT}/base-content.txt" || fail '主订阅内容遗漏自用或启用账号'
            [[ "$(wc -l <"${TEST_ROOT}/base-content.txt")" == 4 ]] || fail '主订阅默认条目数错误'
            ;;
        disabled-account)
            [[ "$(wc -l <"${TEST_ROOT}/base-content.txt")" == 3 ]] || fail '主订阅启用账号过滤错误'
            ! grep -q "${ALICE_UUID}" "${TEST_ROOT}/base-content.txt" || fail '主订阅包含停用账号'
            ;;
        esac
        if [[ "${baseCase}" == disabled || "${baseCase}" == reality ]]; then
            reject dockerSubscriptionCommand links --base
        else
            [[ "$(dockerSubscriptionCommand links --base)" == "https://${authority}/subscriptions/${MAIN_TOKEN}" ]] ||
                fail "${baseCase}: 主订阅链接未使用实际公开端口"
        fi
        [[ "$(baseQuerySnapshot)" == "${before}" ]] || fail "${baseCase}: 主订阅查询修改状态或留下临时文件"
        [[ ! -e "${queryRoot}/config/share-groups.json" ]] || fail '主订阅查询创建分享组状态'
    done
    # include_base 仅为分享渲染的内部投影，受管规格继续拒绝保存该字段。
    jq '.subscription.enabled = false | .subscription.include_base = false' "${SPEC}" >"${querySpec}"
    before=$(baseQuerySnapshot)
    for action in content links; do reject dockerSubscriptionCommand "${action}" --base; done
    dockerGenerateSubscription "${querySpec}" "${TEST_ROOT}/base-content.txt" local ||
        fail '本地主订阅生成失败'
    [[ "$(wc -l <"${TEST_ROOT}/base-content.txt")" == 2 ]] || fail '本地生成器未保留 include_base=false'
    ! grep -q "${MAIN_UUID}" "${TEST_ROOT}/base-content.txt" || fail '本地生成器重新加入被关闭的自用条目'
    [[ "$(baseQuerySnapshot)" == "${before}" ]] || fail '内部主订阅投影修改状态'
    cp -p -- "${SPEC}" "${querySpec}"
    before=$(baseQuerySnapshot)
    for action in content links; do
        reject dockerSubscriptionCommand "${action}"
        reject dockerSubscriptionCommand "${action}" --base extra
        reject dockerSubscriptionCommand "${action}" --base --base
        reject dockerSubscriptionCommand "${action}" --base --json
    done
    [[ "$(baseQuerySnapshot)" == "${before}" ]] || fail '非法主订阅参数修改状态'
    chmod 0666 "${querySpec}"
    for action in content links; do reject dockerSubscriptionCommand "${action}" --base; done
    chmod 0600 "${querySpec}"
    mv -- "${querySpec}" "${querySpec}.real"
    ln -s "${querySpec}.real" "${querySpec}"
    for action in content links; do reject dockerSubscriptionCommand "${action}" --base; done
    rm -- "${querySpec}"
    mv -- "${querySpec}.real" "${querySpec}"
    mv -- "${queryRoot}/config" "${queryRoot}/config-real"
    ln -s "${queryRoot}/config-real" "${queryRoot}/config"
    for action in content links; do reject dockerSubscriptionCommand "${action}" --base; done
    rm -- "${queryRoot}/config"
    mv -- "${queryRoot}/config-real" "${queryRoot}/config"
    [[ "$(baseQuerySnapshot)" == "${before}" ]] || fail '拒绝恶意规格后未保持原状态'
)

STATE_FILE="${PADM_DOCKER_INSTALL_DIR}/config/share-groups.json"
for STATE_INPUT in '' null '{}' '{"schema_version":1,"groups":[]} {"schema_version":1,"groups":[]}'; do
    printf '%s\n' "${STATE_INPUT}" >"${STATE_FILE}"
    chmod 0600 "${STATE_FILE}"
    reject dockerSubscriptionStateValidate "${STATE_FILE}"
    reject dockerSubscriptionReadState
done
printf '%s\n' '{"schema_version":1,"groups":[]}' >"${STATE_FILE}"
[[ "$(dockerSubscriptionReadState)" == '{"schema_version":1,"groups":[]}' ]] ||
    fail '合并校验读取没有返回单个规范化分享组对象'
rm -- "${STATE_FILE}"

reject dockerSubscriptionCommand list --json extra
reject dockerSubscriptionCommand create --accounts "${ALICE},${ALICE}"
reject dockerSubscriptionCommand create --listeners entry-missing
reject dockerSubscriptionCommand create --accounts "${ALICE}" --listeners entry-ws
reject dockerSubscriptionCommand edit share-not-valid --name invalid

GROUP=$(dockerSubscriptionCommand create --name Team --accounts "${ALICE}" --listeners entry-reality)
GROUP_TOKEN=$(jq -er --arg id "${GROUP}" '.groups[] | select(.id == $id) | .token' \
    "${PADM_DOCKER_INSTALL_DIR}/config/share-groups.json")
SHARE_FILE="${PADM_DOCKER_INSTALL_DIR}/data/subscription/${GROUP_TOKEN}"
[[ -f "${SHARE_FILE}" && ! -L "${SHARE_FILE}" ]] || fail '创建分享组未生成 token 文件'
[[ "$(stat -c '%a' "${PADM_DOCKER_INSTALL_DIR}/config/share-groups.json")" == 600 ]] ||
    fail '分享组状态文件权限错误'
grep -q '^vless://' "${SHARE_FILE}" || fail '分享内容未生成 URI'
grep -q "${ALICE_UUID}" "${SHARE_FILE}" || fail '分享内容未包含选中账号'
! grep -q "${MAIN_UUID}" "${SHARE_FILE}" || fail '分享内容泄露主订阅自用 UUID'
! grep -q "${BOB_UUID}" "${SHARE_FILE}" || fail '分享内容包含未选账号'
grep -q 'reality.example.com' "${SHARE_FILE}" || fail '账号/入口过滤后内容缺失'
! grep -q 'ws.example.com' "${SHARE_FILE}" || fail '入口过滤未生效'
[[ "$(cat "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${MAIN_TOKEN}")" == 'main subscription sentinel' ]] ||
    fail '分享组操作改写了主订阅文件'

LIST_JSON=$(dockerSubscriptionCommand list --json)
jq -e --arg id "${GROUP}" '
  length == 1 and .[0].id == $id and
  (.[0] | has("token") | not) and
  .[0].account_ids == ["11111111-1111-4111-8111-111111111111"]
' <<<"${LIST_JSON}" >/dev/null || fail '分享组 JSON 列表泄露或内容错误'

CONTENT=$(dockerSubscriptionCommand content "${GROUP}")
[[ -n "${CONTENT}" ]] || fail '纯内容输出为空'
! grep -Eq '^(分享|https?://|[[:space:]]*$)' <<<"${CONTENT}" ||
    fail '纯内容输出混入说明或链接'
while IFS= read -r line; do
    [[ "${line}" =~ ^(vless|vmess|trojan|hysteria2|anytls|naive\+https|ss|tuic):// ]] ||
        fail "纯内容包含非 URI 行: ${line}"
done <<<"${CONTENT}"

LINK=$(dockerSubscriptionCommand links "${GROUP}")
[[ "${LINK}" == "https://ws.example.com:8443/subscriptions/${GROUP_TOKEN}" ]] ||
    fail '分享 HTTPS 链接错误'

# 分享服务使用实际发布入口，不能把内部 TLS 端口或空入口 ID 当成公网 443。
(
    portSpec="${TEST_ROOT}/port-spec.json"
    for portCase in standard legacy shared first; do
        case "${portCase}" in
        standard)
            filter='(.core.protocols[] | select(.id == 21) | .public_port) = 443 |
              (.core.protocols[] | select(.id == 1) | .public_port) = 4443'
            authority=ws.example.com
            ;;
        legacy)
            filter='.schema_version = 1 | del(.accounts, .core.secondary_type) |
              .core.protocols = [.core.protocols[] | select(.id == 21) |
                del(.core, .listener_id, .websocket.backend_port, .websocket.tls_port)]'
            authority=ws.example.com:8443
            ;;
        shared)
            filter='.core.protocols |= map(.server = "proxy.example.com") |
              .reality_stream = {listener_id:"entry-reality",website_listener_id:"entry-ws"}'
            authority=ws.example.com
            ;;
        first)
            filter='.core.protocols += [.core.protocols[] | select(.id == 21) |
              .listener_id = "entry-second" | .public_port = 9443 |
              .websocket.backend_port = 31298 | .websocket.tls_port = 8444]'
            authority=ws.example.com:8443
            ;;
        esac
        jq "${filter}" "${SPEC}" >"${portSpec}"
        dockerConfigureSpecValidate "${portSpec}" || fail "${portCase}: 发布端口夹具无效"
        [[ "$(dockerSubscriptionLinks "${portSpec}" "${STATE_FILE}" "${GROUP}")" == "https://${authority}/subscriptions/${GROUP_TOKEN}" ]] ||
            fail "${portCase}: 分享链接未使用实际公开端口"
    done
)

# 仅复用已有 TLS 网站入口；发布和本地内容分别验收，旧包能力仅限制新增拓扑。
(
    mkdir -p -- "${TEST_ROOT}/bundle"
    printf '%040d\n' 1 >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
    dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
    compat="${TEST_ROOT}/subscription-old-bundle"
    mkdir -p -- "${compat}/docker/contracts"
    cp -- "$(dockerFeatureMatrixFile)" "${compat}/docker/contracts/features.json"
    jq 'del(.["x-padm-subscription-nginx-tls"])' "$(dockerConfigureSchemaFile)" \
        >"${compat}/docker/contracts/configure.schema.json"
    dockerBundleSupportsSpec "${compat}" "${SPEC}" || fail '旧包拒绝原协议 21 发布子集'
    fallbackCompat="${TEST_ROOT}/subscription-old-fallback-bundle"
    mkdir -p -- "${fallbackCompat}/docker/contracts"
    cp -- "$(dockerFeatureMatrixFile)" "${fallbackCompat}/docker/contracts/features.json"
    jq 'del(.["x-padm-subscription-fallback-tls"])' "$(dockerConfigureSchemaFile)" \
        >"${fallbackCompat}/docker/contracts/configure.schema.json"
    share=$(jq -cn --arg token "${GROUP_TOKEN}" --arg account "${BOB}" '
      {token:$token,account_ids:[$account],listener_ids:["entry-ws"]}')
    for topology in 22:xray 23:xray 23:sing-box 24:xray 25:xray 27:xray 29:xray; do
        protocol=${topology%%:*}; core=${topology#*:}
        spec="${TEST_ROOT}/publish-${protocol}-${core}.json"
        jq --argjson protocol "${protocol}" --arg core "${core}" --arg account "${BOB}" '
          .core.type = $core | .core.secondary_type = null |
          .core.protocols = [.core.protocols[] | select(.id == 21) |
            .id = $protocol | .core = $core |
            if $protocol == 23 then .httpupgrade = .websocket | del(.websocket)
            elif $protocol == 24 or $protocol == 25 then
              .grpc_tls = (.websocket | del(.path) + {service_name:"subscriptions"}) | del(.websocket)
            elif $protocol == 27 or $protocol == 29 then
              .fallback_tls = {domain:.websocket.domain,http_port:31300,http2_port:31302} | del(.websocket)
            else . end] |
          .accounts |= map(select(.id == $account))
        ' "${SPEC}" >"${spec}"
        dockerConfigureSpecValidate "${spec}" || fail "${topology}: 独立发布规格被拒绝"
        dockerBundleSupportsSpec "${PROJECT_ROOT}" "${spec}" || fail "${topology}: 当前包拒绝发布"
        reject dockerBundleSupportsSpec "${compat}" "${spec}"
        if [[ "${protocol}" == 27 || "${protocol}" == 29 ]]; then
            reject dockerBundleSupportsSpec "${fallbackCompat}" "${spec}"
            jq --slurpfile original "${SPEC}" '
              .core.protocols += [$original[0].core.protocols[] | select(.id == 21) |
                .listener_id = "entry-second" | .public_port = 9443]
            ' "${spec}" >"${TEST_ROOT}/publish-mixed.json"
            dockerConfigureSpecValidate "${TEST_ROOT}/publish-mixed.json" || fail '混合发布夹具无效'
            reject dockerBundleSupportsSpec "${fallbackCompat}" "${TEST_ROOT}/publish-mixed.json"
            # 旧混合正文不含 fallback token 路由，兼容时仍须整份匹配。
            dockerGenerateNginxConfig "${TEST_ROOT}/publish-mixed.json" "${TEST_ROOT}/publish-legacy.conf" legacy-publish
            [[ "$(grep -cF 'proxy_pass http://subscription:8081/$padm_subscription_token;' \
                "${TEST_ROOT}/publish-legacy.conf")" == 1 ]] || fail '旧混合正文扩大 fallback 发布'
            dockerNginxConfigMatches "${TEST_ROOT}/publish-mixed.json" "${TEST_ROOT}/publish-legacy.conf" ||
                fail '旧混合发布正文被拒绝'
            printf '\n# drift\n' >>"${TEST_ROOT}/publish-legacy.conf"
            reject dockerNginxConfigMatches "${TEST_ROOT}/publish-mixed.json" "${TEST_ROOT}/publish-legacy.conf"
            # 上版普通 TLS 已有动态 resolver，只有 fallback 尚无 token 路由。
            for regularProtocol in 21 22; do
                jq --argjson protocol "${regularProtocol}" '.core.protocols[-1].id = $protocol' \
                    "${TEST_ROOT}/publish-mixed.json" >"${TEST_ROOT}/publish-previous.json"
                dockerConfigureSpecValidate "${TEST_ROOT}/publish-previous.json" || fail '上版混合发布夹具无效'
                dockerGenerateNginxConfig "${TEST_ROOT}/publish-previous.json" \
                    "${TEST_ROOT}/publish-previous.conf" legacy-fallback-publish
                [[ "$(grep -cF 'proxy_pass http://subscription:8081/$padm_subscription_token;' \
                    "${TEST_ROOT}/publish-previous.conf")" == 1 &&
                    "$(grep -cF 'resolver 127.0.0.11 ipv6=off valid=30s;' \
                        "${TEST_ROOT}/publish-previous.conf")" == 1 ]] || fail '上版混合正文丢失普通 TLS resolver'
                dockerNginxConfigMatches "${TEST_ROOT}/publish-previous.json" "${TEST_ROOT}/publish-previous.conf" ||
                    fail '上版混合发布正文被拒绝'
                printf '\n# drift\n' >>"${TEST_ROOT}/publish-previous.conf"
                reject dockerNginxConfigMatches "${TEST_ROOT}/publish-previous.json" "${TEST_ROOT}/publish-previous.conf"
            done
            reject dockerGenerateNginxConfig "${spec}" "${TEST_ROOT}/publish-previous.conf" legacy-fallback-publish
            for portCase in nonstandard standard first; do
                authority=ws.example.com:8443
                case "${portCase}" in
                nonstandard) cp -- "${spec}" "${TEST_ROOT}/publish-port.json" ;;
                standard)
                    jq '.core.protocols[0].public_port = 443' "${spec}" >"${TEST_ROOT}/publish-port.json"
                    authority=ws.example.com ;;
                first) cp -- "${TEST_ROOT}/publish-mixed.json" "${TEST_ROOT}/publish-port.json" ;;
                esac
                dockerConfigureSpecValidate "${TEST_ROOT}/publish-port.json" || fail 'fallback 发布端口夹具无效'
                [[ "$(dockerSubscriptionLinks "${TEST_ROOT}/publish-port.json" "${STATE_FILE}" "${GROUP}")" == \
                    "https://${authority}/subscriptions/${GROUP_TOKEN}" ]] || fail 'fallback 分享链接端口错误'
                (
                    dockerSubscriptionSpecFile() { printf '%s\n' "${TEST_ROOT}/publish-port.json"; }
                    [[ "$(dockerSubscriptionCommand links --base)" == "https://${authority}/subscriptions/${MAIN_TOKEN}" ]]
                ) || fail 'fallback 主订阅链接端口错误'
            done
        else
            dockerBundleSupportsSpec "${fallbackCompat}" "${spec}" || fail 'fallback 能力门禁误伤 Nginx TLS 发布'
        fi
        dockerGenerateCompose "${spec}" "${TEST_ROOT}/publish-compose.json"
        jq -e --arg core "${core}" --argjson protocol "${protocol}" '
          (.services | keys | map(select(. == "xray" or . == "sing-box"))) == [$core] and
          .services.subscription.profiles == ["subscription"] and
          (if $protocol == 27 or $protocol == 29 then
            (.services.nginx.depends_on | has($core) | not) and .services.nginx.ports == [] and
            .services[$core].ports == ["0.0.0.0:8443:8443/tcp"]
          else .services.nginx.depends_on[$core].condition == "service_healthy" and
            .services.nginx.ports == ["0.0.0.0:8443:8443/tcp"] end) and
          .services.nginx.depends_on.subscription.condition == "service_healthy" and
          .services.subscription.ports == null
        ' "${TEST_ROOT}/publish-compose.json" >/dev/null || fail "${topology}: 发布拓扑或核心依赖错误"
        dockerGenerateDeployment "${spec}" "${TEST_ROOT}/publish-deployment.json" ||
            fail "${topology}: 发布元数据生成失败"
        jq -e --arg core "${core}" '.compose.profiles == ["core-"+$core,"nginx","subscription"]' \
            "${TEST_ROOT}/publish-deployment.json" >/dev/null || fail "${topology}: 发布 profile 错误"
        dockerGenerateNginxConfig "${spec}" "${TEST_ROOT}/publish-nginx.conf"
        grep -qF 'proxy_pass http://subscription:8081/$padm_subscription_token;' \
            "${TEST_ROOT}/publish-nginx.conf" || fail "${topology}: Nginx 缺少订阅路由"
        if [[ "${protocol}" == 27 || "${protocol}" == 29 ]]; then
            [[ "$(grep -cF 'proxy_pass http://subscription:8081/$padm_subscription_token;' \
                "${TEST_ROOT}/publish-nginx.conf")" == 2 ]] &&
                grep -qF 'listen 31300 proxy_protocol;' "${TEST_ROOT}/publish-nginx.conf" &&
                grep -qF 'listen 31302 proxy_protocol;' "${TEST_ROOT}/publish-nginx.conf" &&
                grep -qF 'http2 on;' "${TEST_ROOT}/publish-nginx.conf" ||
                fail "${topology}: fallback 双后端路由或 PROXY/HTTP2 丢失"
        fi
        if [[ "${protocol}" == 24 || "${protocol}" == 25 ]]; then
            grep -qF 'location /subscriptions/ {' "${TEST_ROOT}/publish-nginx.conf" &&
                ! grep -qF 'location ^~ /subscriptions/ {' "${TEST_ROOT}/publish-nginx.conf" ||
                fail "${topology}: gRPC 服务名抢占订阅 token 路由"
        fi
        dockerGenerateSubscription "${spec}" "${TEST_ROOT}/publish-main.txt"
        [[ "$(wc -l <"${TEST_ROOT}/publish-main.txt")" == 2 ]] ||
            fail "${topology}: 主订阅遗漏自用或独立账号"
        dockerSubscriptionRender "${spec}" "${share}" "${TEST_ROOT}/publish-share.txt"
        [[ "$(wc -l <"${TEST_ROOT}/publish-share.txt")" == 1 ]] ||
            fail "${topology}: 分享组没有只输出选中账号"
        content=$(<"${TEST_ROOT}/publish-share.txt")
        if [[ "${protocol}" == 22 || "${protocol}" == 23 ]]; then
            printf '%s' "${content#vmess://}" | base64 -d |
                jq -e --arg uuid "${BOB_UUID}" --argjson protocol "${protocol}" '
                  .id == $uuid and .port == "8443" and .tls == "tls" and
                  .net == (if $protocol == 22 then "ws" else "httpupgrade" end)
                ' >/dev/null || fail "${topology}: 分享账号或传输错误"
        elif [[ "${protocol}" == 24 || "${protocol}" == 27 ]]; then
            [[ "${content}" == "vless://${BOB_UUID}@"* ]] || fail 'VLESS 分享账号错误'
        else
            [[ "${content}" == 'trojan://Bob.-~%40%2B%3D%3ASecret@'* ]] ||
                fail 'Trojan 分享账号错误'
        fi
        if [[ "${protocol}" == 27 || "${protocol}" == 29 ]]; then
            [[ "${content}" == *'@ws.example.com:8443?'* && "${content}" == *'&sni=ws.example.com&'* &&
                "${content}" == *'&type=tcp#'* ]] || fail 'fallback 内容域名、端口或传输错误'
        fi
        jq '.subscription.enabled = false' "${spec}" >"${TEST_ROOT}/publish-disabled.json"
        dockerBundleSupportsSpec "${compat}" "${TEST_ROOT}/publish-disabled.json" ||
            fail "${topology}: 旧包拒绝关闭发布的协议子集"
        dockerBundleSupportsSpec "${fallbackCompat}" "${TEST_ROOT}/publish-disabled.json" ||
            fail "${topology}: 缺 fallback 能力的旧包拒绝关闭发布"
        dockerSubscriptionRender "${TEST_ROOT}/publish-disabled.json" "${share}" "${TEST_ROOT}/publish-local.txt"
        cmp -s "${TEST_ROOT}/publish-share.txt" "${TEST_ROOT}/publish-local.txt" ||
            fail "${topology}: 关闭 HTTPS 发布改变本地分享内容"
        dockerGenerateNginxConfig "${TEST_ROOT}/publish-disabled.json" "${TEST_ROOT}/publish-disabled.conf"
        ! grep -qF 'padm_subscription_token' "${TEST_ROOT}/publish-disabled.conf" ||
            fail "${topology}: 关闭发布仍保留 token 路由"
        if [[ "${protocol}" == 24 || "${protocol}" == 25 ]]; then
            grep -qF 'location ^~ /subscriptions/ {' "${TEST_ROOT}/publish-disabled.conf" ||
                fail "${topology}: 关闭发布仍改变 gRPC 原路由优先级"
        fi
        reject dockerSubscriptionLinks "${TEST_ROOT}/publish-disabled.json" "${STATE_FILE}" "${GROUP}"
    done
)

dockerSubscriptionCommand edit "${GROUP}" --name Team-Renamed --listeners entry-reality >/dev/null
jq -e --arg id "${GROUP}" '.groups[] | select(.id == $id and .name == "Team-Renamed")' \
    "${PADM_DOCKER_INSTALL_DIR}/config/share-groups.json" >/dev/null || fail '编辑分享组失败'

dockerSubscriptionCommand rotate "${GROUP}" --yes >/dev/null
NEW_TOKEN=$(jq -er --arg id "${GROUP}" '.groups[] | select(.id == $id) | .token' \
    "${PADM_DOCKER_INSTALL_DIR}/config/share-groups.json")
[[ "${NEW_TOKEN}" != "${GROUP_TOKEN}" && -f "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${NEW_TOKEN}" ]] ||
    fail '轮换没有生成新 token 文件'
[[ ! -e "${SHARE_FILE}" ]] || fail '轮换未删除旧 token 文件'
GROUP_TOKEN="${NEW_TOKEN}"

dockerSubscriptionCommand disable "${GROUP}" >/dev/null
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${GROUP_TOKEN}" ]] ||
    fail '停用未删除 token 文件'
dockerSubscriptionCommand edit "${GROUP}" --name Disabled >/dev/null
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${GROUP_TOKEN}" ]] ||
    fail '编辑停用组错误生成 token 文件'
reject dockerSubscriptionCommand content "${GROUP}"
reject dockerSubscriptionCommand links "${GROUP}"

dockerSubscriptionCommand enable "${GROUP}" >/dev/null
[[ -f "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${GROUP_TOKEN}" ]] ||
    fail '启用未重新生成 token 文件'

DISABLED=$(dockerSubscriptionCommand create --name Disabled --disabled --accounts "${BOB}" --listeners entry-ws)
DISABLED_TOKEN=$(jq -er --arg id "${DISABLED}" '.groups[] | select(.id == $id) | .token' \
    "${PADM_DOCKER_INSTALL_DIR}/config/share-groups.json")
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${DISABLED_TOKEN}" ]] ||
    fail '禁用创建错误生成 token 文件'
dockerSubscriptionCommand delete "${DISABLED}" --yes >/dev/null
jq -e --arg id "${DISABLED}" 'any(.groups[]; .id == $id) | not' \
    "${PADM_DOCKER_INSTALL_DIR}/config/share-groups.json" >/dev/null || fail '删除分享组失败'

rm -f -- "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${GROUP_TOKEN}"
ln -s "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${MAIN_TOKEN}" \
    "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${GROUP_TOKEN}"
reject dockerSubscriptionCommand disable "${GROUP}"
rm -f -- "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${GROUP_TOKEN}"

NGINX="${TEST_ROOT}/nginx.conf"
dockerGenerateNginxConfig "${SPEC}" "${NGINX}"
grep -qF 'location ~ "^/subscriptions/(?<padm_subscription_token>[A-Za-z0-9_-]{16,128})$" {' "${NGINX}" ||
    fail 'Nginx 未生成受限 token 路由'
grep -qF 'proxy_pass http://subscription:8081/$padm_subscription_token;' "${NGINX}" ||
    fail 'Nginx token 代理路径错误'
grep -qF 'resolver 127.0.0.11 ipv6=off valid=30s;' "${NGINX}" || fail 'Nginx token 代理缺少 Docker DNS 解析'
grep -qF 'resolver_timeout 5s;' "${NGINX}" || fail 'Nginx token 代理缺少 DNS 超时'

# 达到组数上限后拒绝新增，不能写入后续管理入口无法读取的状态。
(
    state="${PADM_DOCKER_INSTALL_DIR}/config/share-groups.json"
    original="${TEST_ROOT}/share-groups-original.json"
    cp -p -- "${state}" "${original}"
    trap 'cp -p -- "${original}" "${state}"' EXIT
    jq -n --arg account "${ALICE}" '
      {schema_version:1,groups:[range(0;256) |
        ("0000000000000000" + tostring)[-16:] as $suffix |
        {id:("share-" + $suffix),name:("Limit-" + $suffix),enabled:false,
         token:("limit-token-" + $suffix),account_ids:[$account],listener_ids:["entry-reality"]}]}
    ' >"${state}"
    chmod 0600 "${state}"
    dockerSubscriptionStateValidate "${state}" || fail '上限夹具不合法'
    before=$(sha256sum "${state}")
    tokensBefore=$(find "${PADM_DOCKER_INSTALL_DIR}/data/subscription" -type f -print0 |
        sort -z | xargs -0 sha256sum)
    for mode in enabled disabled; do
        args=(subscription create --name Overflow --accounts "${ALICE}" --listeners entry-reality)
        [[ "${mode}" != disabled ]] || args+=(--disabled)
        reject dockerMain "${args[@]}"
        [[ "${before}" == "$(sha256sum "${state}")" ]] || fail '拒绝新增改写了分享状态'
        [[ "${tokensBefore}" == "$(find "${PADM_DOCKER_INSTALL_DIR}/data/subscription" -type f -print0 |
            sort -z | xargs -0 sha256sum)" ]] || fail '拒绝新增改写或遗留了 token 文件'
        jq -e 'length == 256' <<<"$(dockerMain subscription list --json)" >/dev/null ||
            fail '拒绝新增后原有分享组不可管理'
    done
)

printf 'docker-subscriptions-regression-ok\n'
