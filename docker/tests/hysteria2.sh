#!/usr/bin/env bash
set -euo pipefail

# 包含协议与 Reality 基线，CI 只运行本入口，避免重复回归。
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/reality.sh"
IMAGE_DIGEST=$(printf '1%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
HY2_SPEC="${TEST_ROOT}/hysteria2.json"
jq --arg manifest "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" '
  .release = {version:"3.1.8",manifest_sha256:$manifest,signature_identity:$identity} |
  .core.type = "sing-box" | .core.secondary_type = null |
  .core.protocols = [(.core.protocols[0] |
    del(.reality) | .id = 3 | .core = "sing-box" | .listener_id = "entry-hy2" |
    .public_port = 27443 | .name = "Hysteria2" |
    .hy2 = {domain:"ws.example.com",bandwidth_mode:"bbr",up_mbps:100,down_mbps:50,
      obfs:null,masquerade:""})] |
  .tls = {domain:"ws.example.com"}
' "${REALITY_SPEC}" >"${HY2_SPEC}"
dockerConfigureSpecValidate "${HY2_SPEC}" || fail 'Hysteria2 有效合同被拒绝'

udpManagementEdit() {
    local expected=$1 unchanged=$2 actual=0 before
    shift 2
    [[ "${unchanged}" != unchanged ]] || before=$(snapshot)
    : >"${EVENTS}"
    bash -u "${CLI}" edit "$@" --manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" \
        --control-bundle "${CONFIGURE_CONTROL}" </dev/null >"${STDOUT}" 2>"${STDERR}" || actual=$?
    if [[ "${actual}" != "${expected}" ]]; then
        cat "${STDERR}" >&2
        fail "UDP 参数编辑 $*: 预期 ${expected}，实际 ${actual}"
    fi
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" &&
        -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 \
          \( -name '.edit.*' -o -name '.candidate.*' -o -name '.protocol.*' \) -print -quit)" ]] ||
        fail 'UDP 参数编辑遗留锁或私密草稿'
    [[ "${unchanged}" != unchanged || "$(snapshot)" == "${before}" ]] ||
        fail 'UDP 参数预览、拒绝或取消改变部署'
}

if [[ "${PADM_DOCKER_TRADITIONAL_TLS_SCOPE:-full}" == base &&
    -n "${PADM_DOCKER_TRADITIONAL_TLS_BASE_GROUP:-}" &&
    "${PADM_DOCKER_TRADITIONAL_TLS_BASE_GROUP}" != hy2-anytls ]]; then
    return 0
fi

for mutation in \
    '.core.protocols[0].core = "xray" | .core.type = "xray"' \
    '.tls = null' \
    '.core.protocols[0].hy2.domain = "other.example.com"' \
    '.core.protocols[0].uuid += "\n"' \
    '.core.protocols[0].hy2.extra = true' \
    '.core.protocols[0].hy2.bandwidth_mode = "auto"' \
    '.core.protocols[0].hy2.up_mbps = 0' \
    '.core.protocols[0].hy2.down_mbps = 1.5' \
    '.core.protocols[0].hy2.up_mbps = 1000001' \
    '.core.protocols[0].hy2.obfs = {type:"unknown",password:"0123456789abcdef"}' \
    '.core.protocols[0].hy2.obfs = {type:"salamander",password:"short"}' \
    '.core.protocols[0].hy2.obfs = {type:"salamander",password:"0123456789abcde\n"}' \
    '.core.protocols[0].hy2.obfs = {type:"salamander",password:"0123456789abcdef",extra:true}' \
    '.core.protocols[0].hy2.obfs = {type:"gecko",password:"short"}' \
    '.core.protocols[0].hy2.obfs = {type:"gecko",password:"0123456789abcdef",min_packet_size:128}' \
    '.core.protocols[0].hy2.obfs = {type:"gecko",password:"0123456789abcdef",max_packet_size:1280}' \
    '.core.protocols[0].hy2.masquerade = "http://www.example.com/"' \
    '.core.protocols[0].hy2.masquerade = "https://user@www.example.com/"' \
    '.core.protocols[0].hy2.masquerade = "https://www.example.com/\n"' \
    '.core.protocols[0].hy2.masquerade = "https://www.example.com/?token=secret"' \
    '.subscription.enabled = true' \
    '.core.protocols[0].public_port = 10087'; do
    jq "${mutation}" "${HY2_SPEC}" >"${TEST_ROOT}/invalid-hy2.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-hy2.json" 2>/dev/null; then
        fail "Hysteria2 接受非法合同: ${mutation}"
    fi
done
for version in 1 2; do
    jq --argjson version "${version}" '.schema_version = $version |
      del(.core.secondary_type) | .core.protocols |= map(del(.core) |
        if $version == 1 then del(.listener_id) else . end)' \
        "${HY2_SPEC}" >"${TEST_ROOT}/invalid-hy2.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-hy2.json" 2>/dev/null; then
        fail "旧版本 ${version} 接受 Hysteria2"
    fi
done

for topology in single secondary primary; do
    jq --arg topology "${topology}" --slurpfile reality "${REALITY_SPEC}" '
      if $topology == "single" then .
      else
        .core.secondary_type = "xray" |
        .core.protocols += [$reality[0].core.protocols[0]] |
        if $topology == "secondary" then
          .core.type = "xray" | .core.secondary_type = "sing-box"
        else . end
      end
    ' "${HY2_SPEC}" >"${TEST_ROOT}/topology-hy2.json"
    newState "hy2-${topology}" "${TEST_ROOT}/topology-hy2.json"
    jq -e '.services["sing-box"].ports ==
      ["0.0.0.0:27443:27443/udp","[::]:27443:27443/udp"] and
      any(.services["sing-box"].volumes[];
        .target == "/etc/padm/secrets/tls" and .read_only == true) and
      (.services | has("nginx") | not)' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail "${topology}: UDP 双栈、TLS 挂载或 Nginx 拓扑错误"
    jq -e 'any(.listeners[]; .listener_id == "entry-hy2" and .service == "sing-box" and
      .transport == "udp" and .public_port == .container_port)' \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null ||
        fail "${topology}: Hysteria2 未记录 UDP 监听"
    dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" ||
        fail "${topology}: UDP 部署基线不匹配"
done

BASE="${PADM_DOCKER_INSTALL_DIR}/config/sing-box/users.base"
jq -e --arg uuid "${UUID}" '.inbounds[] | select(.type == "hysteria2") |
  .users == [{name:$uuid,password:$uuid}] and .ignore_client_bandwidth == true and
  (has("up_mbps") or has("down_mbps") or has("obfs") or has("masquerade") | not) and
  .tls == {enabled:true,server_name:"ws.example.com",alpn:["h3"],
    certificate_path:"/etc/padm/secrets/tls/ws.example.com.crt",
    key_path:"/etc/padm/secrets/tls/ws.example.com.key"}' "${BASE}" >/dev/null ||
    fail 'Hysteria2 BBR 配置或账号/TLS 生成错误'
HY2_URI="hysteria2://${UUID}@[2001:db8::1]:27443?peer=ws.example.com&insecure=0&sni=ws.example.com&alpn=h3#Hysteria2"
# 本地网页仅改变服务端伪装，账号、TLS 与分享 URI 保持原值。
jq '.site = {mode:"static"} | .core.protocols[0].hy2.masquerade = "local"' \
    "${HY2_SPEC}" >"${TEST_ROOT}/file-hy2.json"
dockerConfigureSpecValidate "${TEST_ROOT}/file-hy2.json"
dockerGenerateSingBoxConfig "${TEST_ROOT}/file-hy2.json" "${TEST_ROOT}/file-hy2-core.json"
jq -e --arg uuid "${UUID}" '.inbounds[0] |
  .masquerade == "file:///srv/padm/" and (has("obfs") | not) and
  .users == [{name:$uuid,password:$uuid}] and .tls.alpn == ["h3"]' \
    "${TEST_ROOT}/file-hy2-core.json" >/dev/null || fail 'Hy2 local 改变账号/TLS 或固定伪装路径'
jq '.subscription.enabled = true' "${TEST_ROOT}/file-hy2.json" >"${TEST_ROOT}/file-hy2-share.json"
dockerGenerateSubscription "${TEST_ROOT}/file-hy2-share.json" "${TEST_ROOT}/file-hy2-link.txt"
[[ "$(<"${TEST_ROOT}/file-hy2-link.txt")" == "${HY2_URI}" ]] || fail 'Hy2 local 改变分享 URI'
runRead 0 hy2-links dockerProtocolCommand links entry-hy2
[[ "$(<"${STDOUT}")" == "${HY2_URI}" ]] || fail 'Hysteria2 单链接不精确或泄漏额外输出'
runRead 0 hy2-list dockerProtocolCommand list
grep -Fq 'sing-box  Hysteria2' "${STDOUT}" || fail '概览没有 Hysteria2 标签'
! grep -Fq "${UUID}" "${STDOUT}" || fail 'Hysteria2 概览暴露 UUID/密码'

jq '.core.protocols[0].hy2 |= (.bandwidth_mode = "brutal" |
  .obfs = {type:"salamander",password:"0123456789abcdef"} |
  .masquerade = "https://www.example.com/path-1")' \
    "${HY2_SPEC}" >"${TEST_ROOT}/brutal-hy2.json"
dockerConfigureSpecValidate "${TEST_ROOT}/brutal-hy2.json"
dockerGenerateSingBoxConfig "${TEST_ROOT}/brutal-hy2.json" "${TEST_ROOT}/brutal-core.json"
jq -e '.inbounds[0] | .up_mbps == 100 and .down_mbps == 50 and
  (has("ignore_client_bandwidth") | not) and
  .obfs == {type:"salamander",password:"0123456789abcdef"} and
  .masquerade == "https://www.example.com/path-1"' "${TEST_ROOT}/brutal-core.json" >/dev/null ||
    fail 'Hysteria2 Brutal/混淆/伪装生成错误'
jq '.subscription.enabled = true' "${TEST_ROOT}/brutal-hy2.json" >"${TEST_ROOT}/local-hy2.json"
dockerGenerateSubscription "${TEST_ROOT}/local-hy2.json" "${STDOUT}"
[[ "$(<"${STDOUT}")" == "${HY2_URI//#Hysteria2/}&upmbps=50&downmbps=100&obfs=salamander&obfs-password=0123456789abcdef#Hysteria2" ]] ||
    fail 'Hysteria2 带宽方向或混淆链接不精确'

# Gecko 只改变混淆字段，账号、TLS、带宽与伪装沿用现有配置。
dockerGenerateSingBoxConfig "${HY2_SPEC}" "${TEST_ROOT}/bbr-core.json"
HY2_COMPAT_BUNDLE="${TEST_ROOT}/hy2-compat-bundle"
mkdir -p "${HY2_COMPAT_BUNDLE}/docker/contracts"
cp "${PROJECT_ROOT}/docker/contracts/"{configure.schema.json,features.json} \
    "${HY2_COMPAT_BUNDLE}/docker/contracts/"
for mode in bbr brutal; do
    sourceSpec=${HY2_SPEC}
    [[ "${mode}" != brutal ]] || sourceSpec="${TEST_ROOT}/brutal-hy2.json"
    jq '.core.protocols[0].hy2.obfs = {type:"gecko",password:"gecko-0123456789abcdef"}' \
        "${sourceSpec}" >"${TEST_ROOT}/gecko-${mode}.json"
    dockerConfigureSpecValidate "${TEST_ROOT}/gecko-${mode}.json" ||
        fail "Gecko ${mode} 合同被拒绝"
    dockerGenerateSingBoxConfig "${TEST_ROOT}/gecko-${mode}.json" "${TEST_ROOT}/gecko-${mode}-core.json"
    jq -e --slurpfile expected "${TEST_ROOT}/${mode}-core.json" '.inbounds[0] |
      .obfs == {type:"gecko",password:"gecko-0123456789abcdef"} and
      del(.obfs) == ($expected[0].inbounds[0] | del(.obfs))' \
        "${TEST_ROOT}/gecko-${mode}-core.json" >/dev/null ||
        fail "Gecko ${mode} 改变认证、TLS、带宽或伪装"
    jq '.subscription.enabled = true' "${TEST_ROOT}/gecko-${mode}.json" \
        >"${TEST_ROOT}/gecko-share.json"
    dockerGenerateSubscription "${TEST_ROOT}/gecko-share.json" "${STDOUT}"
    bandwidthQuery=
    [[ "${mode}" != brutal ]] || bandwidthQuery='&upmbps=50&downmbps=100'
    [[ "$(<"${STDOUT}")" == "${HY2_URI//#Hysteria2/}${bandwidthQuery}&obfs=gecko&obfs-password=gecko-0123456789abcdef#Hysteria2" ]] ||
        fail "Gecko ${mode} 分享链接不精确"
    dockerBundleSupportsSpec "${HY2_COMPAT_BUNDLE}" "${TEST_ROOT}/gecko-${mode}.json" ||
        fail "当前 bundle 拒绝 Gecko ${mode}"
done
jq 'del(."x-padm-hy2-gecko")' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${HY2_COMPAT_BUNDLE}/docker/contracts/configure.schema.json"
for mode in bbr brutal; do
    if dockerBundleSupportsSpec "${HY2_COMPAT_BUNDLE}" "${TEST_ROOT}/gecko-${mode}.json" 2>/dev/null; then
        fail "旧 bundle 接受 Gecko ${mode}"
    fi
done
dockerBundleSupportsSpec "${HY2_COMPAT_BUNDLE}" "${HY2_SPEC}" || fail '旧 bundle 误拒无混淆 Hy2'
dockerBundleSupportsSpec "${HY2_COMPAT_BUNDLE}" "${TEST_ROOT}/brutal-hy2.json" ||
    fail '旧 bundle 误拒 Salamander Hy2'
quota=$(jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{
  ($uuid):{name:"shared",upload:1,download:0,limit_bytes:1,baseline:{}}}}')
dockerTrafficRender sing-box "${BASE}" "${quota}" >"${TEST_ROOT}/quota-hy2.json"
jq -e 'all(.inbounds[] | select(.type == "hysteria2"); .users == [])' \
    "${TEST_ROOT}/quota-hy2.json" >/dev/null || fail 'Hysteria2 未执行共享账号额度'
accounts=$(dockerTrafficAccounts sing-box)
jq -e --arg uuid "${UUID}" 'length == 1 and .[0].account == $uuid' <<<"${accounts}" >/dev/null ||
    fail 'Hysteria2 为同 UUID 重建独立统计账号'

# UDP 占用不能漏报，属于当前部署的 UDP 监听仍可在事务中复用。
(
    dockerCurrentOwnsPort() { return 1; }
    dockerTcpPortIsListening() { return 1; }
    dockerUdpPortIsListening() { [[ "$1" == 27443 ]]; }
    if dockerConfigurePortsAvailable "${HY2_SPEC}" 2>/dev/null; then
        fail 'Hysteria2 漏检 UDP 占用'
    fi
    dockerCurrentOwnsPort() { [[ "$1" == 27443 && "$2" == udp ]]; }
    dockerConfigurePortsAvailable "${HY2_SPEC}" || fail '自有 UDP 监听不能被复用'
)

liveSnapshot() {
    find "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data" \
        "${PADM_DOCKER_INSTALL_DIR}/secrets" -type f -exec sha256sum {} + | LC_ALL=C sort
    sha256sum "${PADM_DOCKER_INSTALL_DIR}/"{deployment.json,compose.json,images.env}
}

# 独立混淆夹具覆盖专项事务，不改后续更新与回滚的双核心基线。
(
    newState hy2-management "${TEST_ROOT}/gecko-brutal.json"
    hy2PrivateRoot=$(mktemp -d /root/.padm-hy2.XXXXXX)
    trap 'rm -rf -- "${hy2PrivateRoot}"' EXIT
    hy2Secret="${hy2PrivateRoot}/password.json"
    printf '{"password":"hy2-private-secret-marker"}\n' >"${hy2Secret}"
    chmod 0600 "${hy2Secret}"
    : >"${FAKE_REALITY_FAIL_MARKER}"
    cp "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${TEST_ROOT}/hy2-management-before.json"
    cp "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json" "${TEST_ROOT}/hy2-management-traffic.json"
    (
        protocolKind=hy2 protocolListener=entry-hy2
        protocolPatch='{"bandwidth_mode":"brutal","up_mbps":250,"down_mbps":125}'
        jq '.core.protocols |= map(if .listener_id == "entry-hy2" then
          .hy2.bandwidth_mode = "brutal" | .hy2.up_mbps = 250 | .hy2.down_mbps = 125
          else . end)' "${TEST_ROOT}/hy2-management-before.json" >"${TEST_ROOT}/hy2-management-expected.json"
        dockerEditCompatibilityValidate "${TEST_ROOT}/hy2-management-before.json" \
            "${TEST_ROOT}/hy2-management-expected.json" || fail 'Hy2 速率专项兼容门禁误拒'
        jq '.core.protocols[0].hy2.obfs.password = "tampered"' \
            "${TEST_ROOT}/hy2-management-expected.json" >"${TEST_ROOT}/hy2-management-tampered.json"
        if dockerEditCompatibilityValidate "${TEST_ROOT}/hy2-management-before.json" \
            "${TEST_ROOT}/hy2-management-tampered.json" 2>/dev/null; then
            fail 'Hy2 速率专项兼容门禁接受混淆篡改'
        fi
    )
    runRead 0 hy2-status bash -u "${CLI}" protocol hy2-status entry-hy2
    jq -e '.entries == [{listener_id:"entry-hy2",protocol:3,public_port:27443,
      bandwidth_mode:"brutal",up_mbps:100,down_mbps:50,obfs_type:"gecko",
      masquerade:"https://www.example.com/path-1"}]' "${STDOUT}" >/dev/null ||
        fail 'Hy2 状态遗漏速率或暴露混淆密码'
    udpManagementEdit 0 unchanged --hy2-bandwidth entry-hy2 brutal 250 125 --preview
    ! grep -Eq '^compose .* up -d ' "${EVENTS}" || fail 'Hy2 带宽预览启动候选'
    for mode in brutal bbr; do
        bandwidthArgs=(entry-hy2 "${mode}")
        [[ "${mode}" != brutal ]] || bandwidthArgs+=(250 125)
        udpManagementEdit 0 changed --hy2-bandwidth "${bandwidthArgs[@]}" --confirm PADM-DOCKER-EDIT
        jq -en --arg mode "${mode}" --slurpfile old "${TEST_ROOT}/hy2-management-before.json" \
            --slurpfile actual "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" '
          def stable: .core.protocols |= map(if .listener_id == "entry-hy2"
            then del(.hy2.bandwidth_mode,.hy2.up_mbps,.hy2.down_mbps) else . end);
          ($old[0] | stable) == ($actual[0] | stable) and
          any($actual[0].core.protocols[]; .listener_id == "entry-hy2" and
            .hy2.bandwidth_mode == $mode and .hy2.up_mbps == 250 and .hy2.down_mbps == 125)
        ' >/dev/null || fail 'Hy2 专项丢失速率或改变混淆、伪装和身份'
        for config in users.base config.json; do
            jq -e --arg mode "${mode}" '.inbounds[] | select(.type == "hysteria2") |
              .obfs == {type:"gecko",password:"gecko-0123456789abcdef"} and
              .masquerade == "https://www.example.com/path-1" and
              (if $mode == "bbr" then .ignore_client_bandwidth == true and
                (has("up_mbps") or has("down_mbps") | not)
               else .up_mbps == 250 and .down_mbps == 125 and
                 (has("ignore_client_bandwidth") | not) end)
            ' "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/${config}" >/dev/null ||
                fail "Hy2 ${mode} 未投影到 ${config}"
        done
        runRead 0 hy2-status-after bash -u "${CLI}" protocol hy2-status
        jq -e --arg mode "${mode}" '.entries | length == 1 and
          .[0].bandwidth_mode == $mode and .[0].up_mbps == 250 and .[0].down_mbps == 125' \
            "${STDOUT}" >/dev/null || fail 'Hy2 状态没有保留 BBR 隐藏速率'
        runRead 0 hy2-links-after dockerProtocolCommand links entry-hy2
        if [[ "${mode}" == bbr ]]; then
            ! grep -Fq upmbps "${STDOUT}" || fail 'Hy2 BBR 链接仍发布 Brutal 速率'
        else
            grep -Fq '&upmbps=125&downmbps=250&obfs=gecko' "${STDOUT}" ||
                fail 'Hy2 Brutal 客户端带宽方向错误'
        fi
    done
    cmp -s "${TEST_ROOT}/hy2-management-traffic.json" "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json" ||
        fail 'Hy2 带宽专项改变累计或额度'
    runRead 15 hy2-missing bash -u "${CLI}" protocol hy2-status missing
    runRead 15 hy2-other bash -u "${CLI}" protocol tuic-status entry-hy2
    for args in 'entry-hy2 auto' 'entry-hy2 bbr 100 50' 'entry-hy2 brutal 0 50' \
        'entry-hy2 brutal 01 50' 'entry-hy2 brutal 100 1000001'; do
        read -r -a bandwidthArgs <<<"${args}"
        udpManagementEdit 2 unchanged --hy2-bandwidth "${bandwidthArgs[@]}" --preview
    done
    udpManagementEdit 15 unchanged --hy2-bandwidth missing bbr --preview
    udpManagementEdit 2 unchanged --hy2-bandwidth entry-hy2 bbr --spec "${HY2_SPEC}" --preview
    udpManagementEdit 2 unchanged --hy2-bandwidth entry-hy2 bbr --tuic-defaults entry-hy2 --preview
    # 通用编辑继续隐藏密码，空输入保留旧值，无旧值时只调用既有随机生成器。
    (
        read() {
            local argument silent=0
            for argument in "$@"; do
                [[ "${argument}" != -s ]] || silent=1
            done
            [[ "${silent}" == 1 ]] || fail '混淆密码未使用静默输入'
            builtin read "$@"
        }
        secret=
        dockerEditHy2PasswordRead secret "${TEST_ROOT}/gecko-brutal.json" entry-hy2 <<<'' >"${STDOUT}"
        [[ "${secret}" == gecko-0123456789abcdef ]] || fail '空密码未保留旧值'
        dockerResolveOpsImage() { printf '%s\n' "${OPS_IMAGE}"; }
        dockerSetupRandomHex() { printf '0123456789abcdef0123456789abcdef\n'; }
        dockerEditHy2PasswordRead secret "${HY2_SPEC}" entry-hy2 <<<'' >>"${STDOUT}"
        [[ "${secret}" == 0123456789abcdef0123456789abcdef ]] || fail '空密码未生成新值'
        for input in zero eof; do
            actual=0
            if [[ "${input}" == zero ]]; then
                dockerEditHy2PasswordRead secret "${HY2_SPEC}" entry-hy2 <<<0 >>"${STDOUT}" || actual=$?
            else
                dockerEditHy2PasswordRead secret "${HY2_SPEC}" entry-hy2 </dev/null >>"${STDOUT}" || actual=$?
            fi
            [[ "${actual}" == 3 ]] || fail '混淆密码 0/EOF 没有取消'
        done
        ! grep -Eq 'gecko-0123456789abcdef|0123456789abcdef0123456789abcdef' "${STDOUT}" ||
            fail '混淆密码回显到终端'
    )
    cp "${TEST_ROOT}/gecko-brutal.json" "${TEST_ROOT}/hy2-generic.json"
    printf '13\nentry-hy2\n4\n2\n\n8\n' |
        dockerEditFields "${TEST_ROOT}/hy2-generic.json" >"${STDOUT}"
    jq -e '.core.protocols[0].hy2.obfs ==
      {type:"salamander",password:"gecko-0123456789abcdef"}' "${TEST_ROOT}/hy2-generic.json" >/dev/null ||
        fail '通用混淆编辑未保留原密码'
    printf '13\nentry-hy2\n4\n1\n8\n' |
        dockerEditFields "${TEST_ROOT}/hy2-generic.json" >"${STDOUT}"
    jq -e '.core.protocols[0].hy2.obfs == null' "${TEST_ROOT}/hy2-generic.json" >/dev/null &&
        ! grep -Fq '混淆密码' "${STDOUT}" || fail '关闭混淆仍读取密码'

    # 私密 JSON 复用公共权限校验，仅补新类型的结构和秘密传递边界。
    for content in '{"password":"short"}' '{"password":7}' \
        '{"password":"0123456789abcdef","extra":true}' \
        '{"password":"0123456789abcdef\n"}' '[]' \
        '{"password":"0123456789abcdef"} {}'; do
        printf '%s\n' "${content}" >"${hy2PrivateRoot}/invalid.json"
        chmod 0600 "${hy2PrivateRoot}/invalid.json"
        if dockerEditPrivateInputCopy "${hy2PrivateRoot}/invalid.json" "${hy2PrivateRoot}/copy.json" hy2_obfs; then
            fail 'Hy2 私密 JSON 接受非法密码或结构'
        fi
    done
    chmod 0644 "${hy2Secret}"
    udpManagementEdit 15 unchanged --hy2-obfs entry-hy2 salamander "${hy2Secret}" --preview
    chmod 0600 "${hy2Secret}"
    udpManagementEdit 2 unchanged --hy2-obfs entry-hy2 salamander --preview
    udpManagementEdit 2 unchanged --hy2-obfs entry-hy2 off "${hy2Secret}" --preview
    udpManagementEdit 2 unchanged --hy2-obfs entry-hy2 off --hy2-masquerade entry-hy2 off --preview
    udpManagementEdit 2 unchanged --hy2-masquerade entry-hy2 off --spec "${HY2_SPEC}" --preview
    udpManagementEdit 15 unchanged --hy2-obfs missing salamander "${hy2Secret}" --preview
    udpManagementEdit 15 unchanged --hy2-masquerade entry-hy2 http://www.example.com/ --preview
    udpManagementEdit 15 unchanged --hy2-masquerade entry-hy2 local --preview
    (
        protocolKind=hy2 protocolListener=entry-hy2 protocolPatch='{"obfs":null}'
        jq '.core.protocols[0].hy2.obfs = null' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
            >"${TEST_ROOT}/hy2-obfs-expected.json"
        dockerEditCompatibilityValidate "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
            "${TEST_ROOT}/hy2-obfs-expected.json" || fail 'Hy2 混淆专项兼容门禁误拒'
        jq '.core.protocols[0].hy2.masquerade = ""' "${TEST_ROOT}/hy2-obfs-expected.json" \
            >"${TEST_ROOT}/hy2-obfs-tampered.json"
        if dockerEditCompatibilityValidate "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
            "${TEST_ROOT}/hy2-obfs-tampered.json" 2>/dev/null; then
            fail 'Hy2 混淆专项允许改变伪装'
        fi
    )
    # 记录实际 jq 参数，私密密码只能经文件读取；同一夹具完成切换、关闭和投影。
    export HY2_JQ_ARGS="${hy2PrivateRoot}/jq-args"
    jq() { printf '%s\n' "$@" >>"${HY2_JQ_ARGS}"; command jq "$@"; }
    export -f jq
    udpManagementEdit 0 unchanged --hy2-obfs entry-hy2 salamander "${hy2Secret}" --preview
    ! grep -Fq hy2-private-secret-marker "${STDOUT}" "${STDERR}" "${EVENTS}" ||
        fail 'Hy2 混淆预览暴露密码'
    for mode in salamander gecko off; do
        obfsArgs=(--hy2-obfs entry-hy2 "${mode}")
        [[ "${mode}" == off ]] || obfsArgs+=("${hy2Secret}")
        cp "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${TEST_ROOT}/hy2-obfs-before.json"
        udpManagementEdit 0 changed "${obfsArgs[@]}" --confirm PADM-DOCKER-EDIT
        jq -en --arg mode "${mode}" --slurpfile secret "${hy2Secret}" \
            --slurpfile old "${TEST_ROOT}/hy2-obfs-before.json" \
            --slurpfile actual "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" '
          def stable: .core.protocols[0].hy2 |= del(.obfs);
          ($old[0] | stable) == ($actual[0] | stable) and
          $actual[0].core.protocols[0].hy2.obfs ==
            (if $mode == "off" then null else {type:$mode,password:$secret[0].password} end)
        ' >/dev/null || fail "Hy2 ${mode} 改变非混淆字段或未提交"
        for config in users.base config.json; do
            jq -e --arg mode "${mode}" --slurpfile secret "${hy2Secret}" '
              .inbounds[] | select(.type == "hysteria2") |
              if $mode == "off" then has("obfs") | not
              else .obfs == {type:$mode,password:$secret[0].password} end
            ' "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/${config}" >/dev/null ||
                fail "Hy2 ${mode} 未投影到 ${config}"
        done
        ! grep -Fq hy2-private-secret-marker "${STDOUT}" "${STDERR}" "${EVENTS}" ||
            fail 'Hy2 混淆编辑暴露密码'
        runRead 0 hy2-obfs-status bash -u "${CLI}" protocol hy2-status entry-hy2
        ! grep -Fq hy2-private-secret-marker "${STDOUT}" || fail 'Hy2 状态暴露混淆密码'
    done
    ! grep -Fq hy2-private-secret-marker "${HY2_JQ_ARGS}" || fail 'Hy2 密码进入 jq 参数'
    unset -f jq
    unset HY2_JQ_ARGS
    for masquerade in off https://www.example.com/new-path; do
        cp "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${TEST_ROOT}/hy2-masquerade-before.json"
        udpManagementEdit 0 changed --hy2-masquerade entry-hy2 "${masquerade}" --confirm PADM-DOCKER-EDIT
        jq -en --arg value "${masquerade}" --slurpfile old "${TEST_ROOT}/hy2-masquerade-before.json" \
            --slurpfile actual "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" '
          def stable: .core.protocols[0].hy2 |= del(.masquerade);
          ($old[0] | stable) == ($actual[0] | stable) and
          $actual[0].core.protocols[0].hy2.masquerade == (if $value == "off" then "" else $value end)
        ' >/dev/null || fail 'Hy2 伪装编辑改变其它字段或未提交'
    done
    udpManagementEdit 0 changed --site-template notes --confirm PADM-DOCKER-EDIT
    staticBefore=$(find "${PADM_DOCKER_INSTALL_DIR}/data/static" -type f -exec sha256sum {} + | LC_ALL=C sort)
    udpManagementEdit 0 changed --hy2-masquerade entry-hy2 local --confirm PADM-DOCKER-EDIT
    jq -e '.inbounds[] | select(.type == "hysteria2") |
      .masquerade == "file:///srv/padm/" and (has("obfs") | not)' \
        "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/users.base" >/dev/null ||
        fail 'Hy2 local 专项没有生成固定网页路径'
    [[ "$(find "${PADM_DOCKER_INSTALL_DIR}/data/static" -type f -exec sha256sum {} + | LC_ALL=C sort)" == "${staticBefore}" ]] ||
        fail 'Hy2 local 专项改写已发布网页'
    udpManagementEdit 15 unchanged --hy2-obfs entry-hy2 salamander "${hy2Secret}" --preview
    cmp -s "${TEST_ROOT}/hy2-management-traffic.json" "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json" ||
        fail 'Hy2 混淆/伪装专项改变累计或额度'
    before=$(liveSnapshot)
    rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
    udpManagementEdit 14 changed --hy2-masquerade entry-hy2 off --confirm PADM-DOCKER-EDIT
    [[ -e "${FAKE_REALITY_FAIL_MARKER}" && "$(liveSnapshot)" == "${before}" ]] ||
        fail 'Hy2 专项健康失败未恢复配置、凭据和累计'
)

before=$(liveSnapshot)
rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
jq '(.core.protocols[] | select(.id == 3) | .public_port) = 27444' \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${TEST_ROOT}/changed-hy2.json"
actual=0
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureReleasePrepare "${CONFIGURE_MANIFEST}" "${CONFIGURE_BUNDLE}" "${CONFIGURE_CONTROL}"
    dockerConfigureApply "${TEST_ROOT}/changed-hy2.json" "" "" confirmed
) >"${STDOUT}" 2>"${STDERR}" || actual=$?
[[ "${actual}" == 14 ]] || fail "Hysteria2 双核心失败事务返回 ${actual}，预期 14"
[[ "$(liveSnapshot)" == "${before}" ]] || fail 'Hysteria2 失败恢复改变证书、配置或累计流量'

IMAGE_DIGEST=$(printf '3%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
(
    trap 'dockerCleanupConfigurationCandidate; dockerCleanupStagedBundle; dockerManifestCleanup; dockerReleaseDeploymentLock' EXIT
    dockerUpdateCommand --manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" \
        --control-bundle "${CONFIGURE_CONTROL}"
) >"${STDOUT}" 2>"${STDERR}" || fail 'Hysteria2 混合双核心更新失败'
runRead 0 hy2-updated-links dockerProtocolCommand links entry-hy2
[[ "$(<"${STDOUT}")" == "${HY2_URI}" ]] || fail '更新改变 Hysteria2 链接'
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerRollbackCommand
) >"${STDOUT}" 2>"${STDERR}" || fail 'Hysteria2 混合双核心回滚失败'
[[ "$(liveSnapshot)" == "${before}" ]] || fail 'Hysteria2 更新回滚改变配置或统计状态'
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'Hysteria2 回归遗留部署锁'
printf 'docker-hysteria2-regression-ok\n'
