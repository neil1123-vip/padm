#!/usr/bin/env bash
set -euo pipefail

# 复用已有 root 部署夹具，权限、锁、生成器和只读基线保持真实。
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/protocol.sh"
command -v python3 >/dev/null
IMAGE_DIGEST=$(printf '1%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/tests/configure-fixture.sh"
dockerConfigureTestFixture
REALITY_SPEC="${TEST_ROOT}/reality-v3.json"
jq --arg manifest "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" \
    --arg digest "${IMAGE_DIGEST}" '
  .release = {version:"3.1.8",manifest_sha256:$manifest,signature_identity:$identity} |
  .images |= with_entries(.value |= sub("sha256:[a-f0-9]{64}$"; "sha256:"+$digest)) |
  .tls = null | .subscription.enabled = false | .core.secondary_type = "sing-box" |
  .core.protocols |= map(select(.id == 1)) |
  .core.protocols += [
    (.core.protocols[0] | .id = 2 | .listener_id = "entry-xhttp" |
      .name = "Reality-XHTTP" | .public_port = 25443 |
      .xhttp = {path:"/padm/path-1",host:"www.example.com",mode:"auto"}),
    (.core.protocols[0] | .id = 26 | .listener_id = "entry-grpc-xray" |
      .name = "Reality-gRPC-Xray" | .public_port = 25444 |
      .grpc = {service_name:"padm-grpc_1"}),
    (.core.protocols[0] | .id = 26 | .listener_id = "entry-grpc-sing" | .core = "sing-box" |
      .name = "Reality-gRPC-sing" | .public_port = 25445 |
      .grpc = {service_name:"padm-grpc_2"})]
' "${TEST_ROOT}/v3.json" >"${REALITY_SPEC}"
if [[ "${PADM_DOCKER_TEST_FIXTURE_ONLY:-0}" != 1 ]]; then
dockerConfigureSpecValidate "${REALITY_SPEC}" || fail '新 Reality 合同不接受有效双核心夹具'
COMPAT_BUNDLE="${TEST_ROOT}/compat-bundle"
mkdir -p "${COMPAT_BUNDLE}/docker/contracts"
cp "${PROJECT_ROOT}/docker/contracts/"{configure.schema.json,features.json} \
    "${COMPAT_BUNDLE}/docker/contracts/"
dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${REALITY_SPEC}" || fail '当前 bundle 拒绝新增协议'
for unsupported in deferred missing core; do
    case "${unsupported}" in
    deferred) filter='(.protocols[] | select(.id == 2 or .id == 26) | .status) = "deferred"' ;;
    missing) filter='.protocols |= map(select(.id != 2 and .id != 26))' ;;
    core) filter='(.protocols[] | select(.id == 26) | .cores) = ["xray"]' ;;
    esac
    jq "${filter}" "${PROJECT_ROOT}/docker/contracts/features.json" \
        >"${COMPAT_BUNDLE}/docker/contracts/features.json"
    if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${REALITY_SPEC}" 2>/dev/null; then
        fail "旧 v3 bundle 接受不支持的协议或核心: ${unsupported}"
    fi
done
dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${TEST_ROOT}/v3.json" ||
    fail 'bundle 兼容门禁误拒现有协议'
for mode in auto packet-up stream-up; do
    jq --arg mode "${mode}" '(.core.protocols[] | select(.id == 2) | .xhttp.mode) = $mode' \
        "${REALITY_SPEC}" >"${TEST_ROOT}/mode.json"
    dockerConfigureSpecValidate "${TEST_ROOT}/mode.json" || fail "有效 XHTTP mode 被拒绝: ${mode}"
done

for mutation in \
    '(.core.protocols[] | select(.id == 2) | .xhttp.extra) = true' \
    '(.core.protocols[] | select(.id == 2) | .xhttp.mode) = "stream-one"' \
    '(.core.protocols[] | select(.id == 2) | .xhttp.path) = "/a\n"' \
    '(.core.protocols[] | select(.id == 2) | .xhttp.path) = "no-leading-slash"' \
    '(.core.protocols[] | select(.id == 2) | .xhttp.path) = "/"' \
    '(.core.protocols[] | select(.id == 2) | .xhttp.host) = "www.example.com\n"' \
    '(.core.protocols[] | select(.id == 2) | .core) = "sing-box"' \
    '(.core.protocols[] | select(.id == 26) | .grpc.extra) = true' \
    '(.core.protocols[] | select(.id == 26) | .grpc.service_name) = ""' \
    '(.core.protocols[] | select(.id == 26) | .grpc.service_name) = "padm/service"' \
    '(.core.protocols[] | select(.id == 26) | .grpc.service_name) = "padm\n"' \
    '(.core.protocols[] | select(.id == 26) | .grpc.service_name) = ("a"*65)' \
    '(.core.protocols[] | select(.id == 2) | .listener_id) = "vless-reality"' \
    '.core.protocols[1].public_port = .core.protocols[0].public_port' \
    '.core.protocols[1].public_port = 10085' \
    '.core.protocols[3].public_port = 10087'; do
    jq "${mutation}" "${REALITY_SPEC}" >"${TEST_ROOT}/invalid-reality.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-reality.json" 2>/dev/null; then
        fail "新 Reality 接受非法合同: ${mutation}"
    fi
done
for version in 1 2; do
    jq --argjson version "${version}" '.schema_version = $version | del(.core.secondary_type) |
      .core.protocols |= map(select(.id == 2) | del(.core) |
        if $version == 1 then del(.listener_id) else . end)' \
        "${REALITY_SPEC}" >"${TEST_ROOT}/old-reality.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/old-reality.json" 2>/dev/null; then
        fail "旧版本 ${version} 接受新增协议"
    fi
done

newState reality "${REALITY_SPEC}"
jq -e '
  [.inbounds[] | select(.protocol == "vless")] as $v |
  ($v | length) == 3 and
  any($v[]; .tag == "vless-reality" and .settings.clients[0].flow == "xtls-rprx-vision") and
  any($v[]; .tag == "entry-xhttp" and .streamSettings.network == "xhttp" and
    .streamSettings.xhttpSettings.path == "/padm/path-1" and
    .streamSettings.xhttpSettings.host == "www.example.com" and
    .streamSettings.xhttpSettings.mode == "auto" and (.settings.clients[0] | has("flow") | not)) and
  any($v[]; .tag == "entry-grpc-xray" and .streamSettings.network == "grpc" and
    .streamSettings.grpcSettings.serviceName == "padm-grpc_1" and
    (.settings.clients[0] | has("flow") | not))
' "${PADM_DOCKER_INSTALL_DIR}/config/xray/users.base" >/dev/null || fail 'Xray 新传输生成错误'
jq -e '.inbounds[0].tag == "entry-grpc-sing" and .inbounds[0].transport ==
  {type:"grpc",service_name:"padm-grpc_2"} and
  (.inbounds[0].users[0] | has("flow") | not)' \
    "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/users.base" >/dev/null || fail 'sing-box gRPC 生成错误'
jq -e '.services.xray.ports ==
  ["0.0.0.0:24443:24443/tcp","[::]:24443:24443/tcp",
   "0.0.0.0:25443:25443/tcp","[::]:25443:25443/tcp",
   "0.0.0.0:25444:25444/tcp","[::]:25444:25444/tcp"] and
  .services["sing-box"].ports == ["0.0.0.0:25445:25445/tcp","[::]:25445:25445/tcp"] and
  (.services | has("nginx") | not)' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
    fail '新 Reality 不是逐入口、逐核心双栈 TCP 映射'
jq -e '.core.protocol_ids == [1,2,26] and (.listeners | length) == 4 and
  all(.listeners[]; .transport == "tcp" and .public_port == .container_port)' \
    "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null || fail '新协议部署记录错误'
# 同 UUID 的各传输共享账号与额度，禁用账号不能改变传输参数。
quota=$(jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{
  ($uuid):{name:"shared",upload:1,download:0,limit_bytes:1,baseline:{}}}}')
for core in xray sing-box; do
    base="${PADM_DOCKER_INSTALL_DIR}/config/${core}/users.base"
    accounts=$(dockerTrafficAccounts "${core}")
    jq -e --arg uuid "${UUID}" 'length == 1 and .[0].account == $uuid' <<<"${accounts}" >/dev/null ||
        fail "${core}: 新传输重复创建共享账号"
    dockerTrafficRender "${core}" "${base}" "${quota}" >"${TEST_ROOT}/quota-${core}.json"
    jq -en --arg core "${core}" --slurpfile before "${base}" \
        --slurpfile after "${TEST_ROOT}/quota-${core}.json" '
      $after[0].inbounds | map(select(if $core == "xray" then .protocol == "vless"
        else .type == "vless" end)) | all(.[];
          . as $entry |
          (if $core == "xray" then .settings.clients else .users end) == [] and
          any($before[0].inbounds[];
            .tag == $entry.tag and .streamSettings == $entry.streamSettings and
            .transport == $entry.transport))
    ' >/dev/null || fail "${core}: 新传输未共享额度或额度改写传输参数"
done

XHTTP_URI="vless://${UUID}@[2001:db8::1]:25443?encryption=none&security=reality&sni=www.example.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=6ba85179e30d4fc2&type=xhttp&host=www.example.com&path=%2Fpadm%2Fpath-1&mode=auto#Reality-XHTTP"
GRPC_XRAY_URI="vless://${UUID}@[2001:db8::1]:25444?encryption=none&security=reality&sni=www.example.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=6ba85179e30d4fc2&type=grpc&alpn=h2&path=padm-grpc_1&serviceName=padm-grpc_1#Reality-gRPC-Xray"
GRPC_SING_URI="vless://${UUID}@[2001:db8::1]:25445?encryption=none&security=reality&sni=www.example.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=6ba85179e30d4fc2&type=grpc&alpn=h2&path=padm-grpc_2&serviceName=padm-grpc_2#Reality-gRPC-sing"
runRead 0 new-disabled-links dockerProtocolCommand links
[[ "$(<"${STDOUT}")" == "${REALITY_URI}"$'\n'"${XHTTP_URI}"$'\n'"${GRPC_XRAY_URI}"$'\n'"${GRPC_SING_URI}" ]] ||
    fail '新传输 URI 不精确、混入 Vision flow 或被发布开关屏蔽'
runRead 0 new-selected-xhttp dockerProtocolCommand links entry-xhttp
[[ "$(<"${STDOUT}")" == "${XHTTP_URI}" ]] || fail 'XHTTP 选择错误'
runRead 0 new-selected-grpc dockerProtocolCommand links entry-grpc-sing
[[ "$(<"${STDOUT}")" == "${GRPC_SING_URI}" ]] || fail '副核心 gRPC 选择错误'
cp "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${TEST_ROOT}/reality-deployment.json"
jq '.listeners[1].container_port += 1' "${TEST_ROOT}/reality-deployment.json" \
    >"${PADM_DOCKER_INSTALL_DIR}/deployment.json"
runRead 15 new-deployment-drift dockerProtocolCommand links
cp "${TEST_ROOT}/reality-deployment.json" "${PADM_DOCKER_INSTALL_DIR}/deployment.json"
fi

# 只模拟 Docker 和宿主服务；候选、可信发布校验、提交及回滚执行生产事务。
cat >"${MOCK_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${FAKE_PROTOCOL_EVENTS:?}"
case "${1:-}" in
info)
    case "${3:-}" in
    '{{.OSType}}') printf 'linux\n' ;;
    '{{.Architecture}}') printf '%s\n' "${FAKE_PROTOCOL_ARCH:?}" ;;
    '{{json .SecurityOptions}}') printf '["name=seccomp,profile=builtin"]\n' ;;
    esac ;;
context) printf 'unix:///var/run/docker.sock\n' ;;
ps|pull) ;;
compose)
    if [[ "${2:-}" == version ]]; then printf 'v2.29.1\n'; exit 0; fi
    if [[ " $* " == *' sing-box version '* ]]; then
        printf 'sing-box version 1.14.0\nTags: with_v2ray_api\n'
    fi
    if [[ " $* " == *' up -d '* && ! -e "${FAKE_REALITY_FAIL_MARKER:?}" ]]; then
        : >"${FAKE_REALITY_FAIL_MARKER}"
        exit 1
    fi ;;
run)
    previous=
    for argument in "$@"; do
        if [[ "${previous}" == -c && "${argument}" == *302e020100300506032b656e04220420* ]]; then
            exec python3 -c "${argument}"
        fi
        previous=${argument}
    done
    if [[ " $* " == *' tls ping '* ]]; then
        printf 'Pinging with SNI\n'
        if [[ " $* " == *' cloudflare.com:443 '* ]]; then
            printf 'Handshake failure: certificate does not match SNI\n'
        else printf 'Handshake succeeded\nTLS Version:\tTLS 1.3\n'; fi
    else printf '192.0.2.1\tAS64500\tExampleNet\n'; fi ;;
*) exit 1 ;;
esac
EOF
cat >"${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == --version ]] || exit 1
printf 'curl fixture\nFeatures: HTTP2\n'
EOF
printf '#!/usr/bin/env bash\nexit 0\n' >"${MOCK_BIN}/systemctl"
cp "${MOCK_BIN}/systemctl" "${MOCK_BIN}/nsenter"
chmod 0755 "${MOCK_BIN}/"{docker,curl,systemctl,nsenter}
export FAKE_REALITY_FAIL_MARKER="${TEST_ROOT}/failed-up"
export PADM_DOCKER_SYSTEMD_DIR="${TEST_ROOT}/systemd" PADM_DOCKER_BIN_DIR="${TEST_ROOT}/installed-bin"
mkdir -p "${PADM_DOCKER_SYSTEMD_DIR}" "${PADM_DOCKER_BIN_DIR}"
liveSnapshot() {
    find "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data" \
        "${PADM_DOCKER_INSTALL_DIR}/secrets" -type f -exec sha256sum {} + | LC_ALL=C sort
    sha256sum "${PADM_DOCKER_INSTALL_DIR}/"{deployment.json,compose.json,images.env}
}
# 派生测试依赖最终可信清单，但自行创建部署，不复用共同合同的事务状态。
if [[ "${PADM_DOCKER_TEST_FIXTURE_ONLY:-0}" == 1 ]]; then
    IMAGE_DIGEST=$(printf '2%.0s' {1..64})
    export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
    dockerConfigureTestFixture
    return 0
fi
before=$(liveSnapshot)
jq '(.core.protocols[] | select(.id == 2) | .public_port) = 26443' \
    "${REALITY_SPEC}" >"${TEST_ROOT}/changed-reality.json"
actual=0
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureReleasePrepare "${CONFIGURE_MANIFEST}" "${CONFIGURE_BUNDLE}" "${CONFIGURE_CONTROL}"
    dockerConfigureApply "${TEST_ROOT}/changed-reality.json" "" "" confirmed
) >"${STDOUT}" 2>"${STDERR}" || actual=$?
[[ "${actual}" == 14 ]] || fail "双核心启动失败未由完整事务返回 14: ${actual}"
[[ -e "${FAKE_REALITY_FAIL_MARKER}" ]] || fail '没有触发真实事务的 Docker 启动失败边界'
[[ "$(liveSnapshot)" == "${before}" ]] || fail '失败恢复改变旧核心、账号、流量或入口基线'
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail '失败恢复遗留锁'
[[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 -name '.candidate.*' -print -quit)" ]] ||
    fail '失败恢复遗留候选'

# 真正执行更新和回滚，只替换 Docker/签名边界，不改生产事务或校验器。
IMAGE_DIGEST=$(printf '2%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
(
    trap 'dockerCleanupConfigurationCandidate; dockerCleanupStagedBundle; dockerManifestCleanup; dockerReleaseDeploymentLock' EXIT
    dockerUpdateCommand --manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" \
        --control-bundle "${CONFIGURE_CONTROL}"
) >"${STDOUT}" 2>"${STDERR}" || fail '新 Reality 双核心更新失败'
jq -e '
  .core.protocols | map(.id) == [1,2,26,26]
' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >/dev/null || fail '更新丢失新传输入口'
jq -e --arg digest "${IMAGE_DIGEST}" '.images.xray | endswith("sha256:"+$digest)' \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >/dev/null || fail '更新没有切换镜像输入'
runRead 0 updated-new-links dockerProtocolCommand links
[[ "$(<"${STDOUT}")" == "${REALITY_URI}"$'\n'"${XHTTP_URI}"$'\n'"${GRPC_XRAY_URI}"$'\n'"${GRPC_SING_URI}" ]] ||
    fail '更新改变分享链接或协议参数'
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerRollbackCommand
) >"${STDOUT}" 2>"${STDERR}" || fail '新 Reality 双核心回滚失败'
[[ "$(liveSnapshot)" == "${before}" ]] || fail '更新回滚改变旧核心、账号、流量或传输入口'
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail '更新回滚遗留锁'
printf 'docker-reality-regression-ok\n'
