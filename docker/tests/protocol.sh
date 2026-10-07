#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Linux || "$(id -u)" != 0 ]]; then
    printf 'docker-protocol-regression-skip: Linux root is required\n'
    exit 0
fi
for tool in jq stat chown chmod curl sha256sum tar diff find; do
    command -v "${tool}" >/dev/null 2>&1 || { printf 'missing tool: %s\n' "${tool}" >&2; exit 1; }
done
find . -maxdepth 0 -printf '' 2>/dev/null ||
    { printf 'docker-protocol-regression requires find with -printf\n' >&2; exit 1; }
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-protocol.XXXXXX")
MOCK_BIN="${TEST_ROOT}/bin"
SOURCE_ROOT="${TEST_ROOT}/source"
EVENTS="${TEST_ROOT}/events"
STDOUT="${TEST_ROOT}/stdout"
STDERR="${TEST_ROOT}/stderr"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
mkdir -p "${MOCK_BIN}" "${SOURCE_ROOT}/docker" "${SOURCE_ROOT}/shell/core"
export FAKE_PROTOCOL_EVENTS="${EVENTS}" FAKE_PROTOCOL_ARCH
FAKE_PROTOCOL_ARCH=$(uname -m)

fail() {
    printf 'docker-protocol-regression-fail: %s\n' "$*" >&2
    [[ ! -f "${STDERR}" ]] || cat "${STDERR}" >&2
    exit 1
}

# 仅隔离宿主边界；文件权限、部署锁、规格迁移和基线校验仍执行生产实现。
cat >"${MOCK_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${FAKE_PROTOCOL_EVENTS:?}"
case "${1:-}" in
info)
    [[ "${2:-}" == --format ]] || exit 0
    case "${3:-}" in
    '{{.OSType}}') printf 'linux\n' ;;
    '{{.Architecture}}') printf '%s\n' "${FAKE_PROTOCOL_ARCH:?}" ;;
    '{{json .SecurityOptions}}') printf '["name=seccomp,profile=builtin"]\n' ;;
    *) exit 1 ;;
    esac
    ;;
context) printf 'unix:///var/run/docker.sock\n' ;;
ps) ;;
compose) [[ "${2:-}" == version ]] || exit 1; printf 'v2.29.1\n' ;;
*) exit 1 ;;
esac
EOF
cat >"${MOCK_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == -m ]]; then printf '%s\n' "${FAKE_PROTOCOL_ARCH:?}"; else printf 'Linux\n'; fi
EOF
cat >"${MOCK_BIN}/id" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == -u ]] && printf '0\n'
EOF
cat >"${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
printf 'unexpected-download\n' >>"${FAKE_PROTOCOL_EVENTS:?}"
exit 1
EOF
chmod 0755 "${MOCK_BIN}/"*
export PATH="${MOCK_BIN}:${PATH}" DOCKER_HOST=
export PADM_DOCKER_LOCK_TIMEOUT=0 PADM_DOCKER_SKIP_CHOWN=0
source "${PROJECT_ROOT}/install-docker.sh"
cp "${PROJECT_ROOT}/install-docker.sh" "${SOURCE_ROOT}/install-docker.sh"
cp -R "${PROJECT_ROOT}/docker/lib" "${SOURCE_ROOT}/docker/lib"
cp -R "${PROJECT_ROOT}/docker/contracts" "${SOURCE_ROOT}/docker/contracts"
cp "${PROJECT_ROOT}/shell/core/"{deployment_mode.sh,stats_grpc.sh,runtime.sh,reality_targets.sh} "${SOURCE_ROOT}/shell/core/"

UUID=11111111-1111-4111-8111-111111111111
PUBLIC_KEY=hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo
PRIVATE_KEY=dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo
TOKEN=0123456789abcdef0123456789abcdef
REALITY_URI="vless://${UUID}@[2001:db8::1]:24443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.example.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=6ba85179e30d4fc2&type=tcp#Primary-Reality"
WS_URI="vless://${UUID}@proxy.example.com:24444?encryption=none&security=tls&sni=ws.example.com&type=ws&host=ws.example.com&path=%2Fabcdefghws#Main%3AWS"
SING_URI="vless://${UUID}@secondary.example.com:24445?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.example.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=6ba85179e30d4fc2&type=tcp#Secondary-Reality"
SPEC="${TEST_ROOT}/spec.json"
jq -n --arg uuid "${UUID}" --arg private "${PRIVATE_KEY}" --arg public "${PUBLIC_KEY}" --arg token "${TOKEN}" '
  def image($name): "ghcr.io/example/padm-" + $name + ":test@sha256:" + ("a" * 64);
  {schema_version:1,
   release:{version:"3.2.0",manifest_sha256:("a" * 64),signature_identity:"fixture"},
   core:{type:"xray",protocols:[
     {id:1,server:"2001:db8::1",public_port:24443,address_families:["ipv4","ipv6"],
      name:"Primary-Reality",uuid:$uuid,
      reality:{server_name:"www.example.com",target_host:"www.example.com",target_port:443,
        private_key:$private,public_key:$public,short_id:"6ba85179e30d4fc2"}},
     {id:21,server:"proxy.example.com",public_port:24444,address_families:["ipv4"],
      name:"Main:WS",uuid:$uuid,websocket:{domain:"ws.example.com",path:"abcdefgh"}}]},
   tls:{domain:"ws.example.com"},subscription:{enabled:true,token:$token},
   images:{xray:image("xray"),"sing-box":image("sing-box"),nginx:image("nginx"),ops:image("ops"),net:image("net")},
   host_integrations:[]}
' >"${SPEC}"
chmod 0600 "${SPEC}"

newState() {
    local name=$1 spec=$2 candidate
    export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/${name}"
    dockerInitializeStateRoot
    dockerStageBundle "${SOURCE_ROOT}" ffffffffffffffffffffffffffffffffffffffff
    dockerActivateStagedBundle
    dockerCleanupStagedBundle
    dockerConfigureSpecValidate "${spec}" || fail '非法规格夹具'
    mkdir -p "${PADM_DOCKER_INSTALL_DIR}/secrets/tls"
    if jq -e '.tls != null' "${spec}" >/dev/null; then
        printf 'fixture-certificate\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/ws.example.com.crt"
        printf 'fixture-private-key\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/ws.example.com.key"
    fi
    jq -n --arg uuid "${UUID}" '{schema_version:1,accounts:{
      ($uuid):{name:"Existing",upload:17,download:23,limit_bytes:100,
        baseline:{xray:{upload:{generation:"old-xray",value:7}},
          "sing-box":{download:{generation:"old-sing",value:9}}}}}}' |
        dockerTrafficWriteState
    dockerCreateConfigurationCandidate
    candidate=${DOCKER_CONFIG_CANDIDATE}
    dockerGenerateCandidate "${spec}" "${candidate}" || fail '真实候选生成失败'
    cp -a "${candidate}/config/." "${PADM_DOCKER_INSTALL_DIR}/config/"
    cp -a "${candidate}/data/." "${PADM_DOCKER_INSTALL_DIR}/data/"
    cp -a "${candidate}/logs/." "${PADM_DOCKER_INSTALL_DIR}/logs/"
    cp -a "${candidate}/secrets/." "${PADM_DOCKER_INSTALL_DIR}/secrets/"
    cp "${candidate}/compose.json" "${candidate}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/"
    cp "${candidate}/images.runtime.env" "${PADM_DOCKER_INSTALL_DIR}/images.env"
    dockerCleanupConfigurationCandidate
    CLI="${PADM_DOCKER_INSTALL_DIR}/bundle/install-docker.sh"
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail '夹具残留部署锁'
}

snapshot() (
    cd "${PADM_DOCKER_INSTALL_DIR}"
    find . -path './.bundles' -prune -o -mindepth 1 -printf '%P %y %m %u %g %l\n' | LC_ALL=C sort
    find . -path './.bundles' -prune -o -type f -exec sha256sum {} + | LC_ALL=C sort
)

runRead() {
    local expected=$1 name=$2 actual=0 before
    shift 2
    before=$(snapshot)
    : >"${EVENTS}"
    "$@" </dev/null >"${STDOUT}" 2>"${STDERR}" || actual=$?
    [[ "${actual}" == "${expected}" ]] || fail "${name}: 预期 ${expected}，实际 ${actual}"
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail "${name}: 部署锁未释放"
    [[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 -name '.protocol.*' -print -quit)" ]] ||
        fail "${name}: 私密工作目录未清理"
    [[ "$(snapshot)" == "${before}" ]] || fail "${name}: 修改了规格、运行文件、权限或流量状态"
    ! grep -Ev '^(info($| --format )|context |ps |compose version )' "${EVENTS}" >/dev/null ||
        fail "${name}: 执行了修改服务、下载或采集动作"
    if [[ "${expected}" != 0 ]]; then
        [[ ! -s "${STDOUT}" ]] || fail "${name}: 失败时仍输出节点数据"
    fi
}

protocolSignalRead() (
    local signal=$1
    shift
    # 仅注入子进程信号，验证命令中断后的锁和私密目录清理。
    dockerEditBaselineValidate() { kill -s "${signal}" "${BASHPID}"; }
    dockerProtocolCommand "$@"
)

newState v1 "${SPEC}"
runRead 0 v1-list dockerProtocolCommand list
[[ "$(<"${STDOUT}")" == $'vless-reality  xray  Reality Vision  [2001:db8::1]:24443  [ipv4,ipv6]  Primary-Reality\nvless-ws  xray  WS TLS  proxy.example.com:24444  [ipv4]  Main:WS' ]] ||
    fail 'v1 列表未保留稳定入口 ID、核心或概要'
for secret in "${UUID}" "${PRIVATE_KEY}" "${PUBLIC_KEY}" "${TOKEN}" abcdefgh; do
    ! grep -Fq "${secret}" "${STDOUT}" || fail '列表暴露了协议秘密'
done
runRead 0 v1-cli-links bash -u "${CLI}" protocol links
[[ "$(<"${STDOUT}")" == "${REALITY_URI}"$'\n'"${WS_URI}" ]] || fail 'CLI 全部链接不精确或混入说明'
runRead 0 v1-selected-ws dockerProtocolCommand links vless-ws
[[ "$(<"${STDOUT}")" == "${WS_URI}" ]] || fail '选择单个 WS 入口仍输出其它节点'
runRead 15 unknown-listener dockerProtocolCommand links entry-missing
runRead 15 numeric-listener dockerProtocolCommand links 21
runRead 2 no-action dockerProtocolCommand
runRead 2 unknown-action dockerProtocolCommand remove
runRead 2 list-extra dockerProtocolCommand list vless-ws
runRead 2 links-extra dockerProtocolCommand links vless-ws extra
runRead 2 links-option dockerProtocolCommand links --spec
runRead 2 cli-no-action bash -u "${CLI}" protocol

# 所有失败路径都从真实已配置部署出发，不能靠伪造校验器返回码通过。
cp "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${TEST_ROOT}/saved-spec.json"
chmod 0640 "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
runRead 15 permissions dockerProtocolCommand links
chmod 0600 "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
chown 10001:10001 "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
runRead 15 owner dockerProtocolCommand list
chown 0:0 "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
rm "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
runRead 15 missing-spec dockerProtocolCommand links
ln -s "${TEST_ROOT}/saved-spec.json" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
runRead 15 linked-spec dockerProtocolCommand list
rm "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
cp "${TEST_ROOT}/saved-spec.json" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
chmod 0600 "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
cp "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json" "${TEST_ROOT}/saved-core.json"
jq '.inbounds[0].port += 1' "${TEST_ROOT}/saved-core.json" >"${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json"
runRead 15 core-drift dockerProtocolCommand links
cp "${TEST_ROOT}/saved-core.json" "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json"
printf 'unexpected-node\n' >>"${PADM_DOCKER_INSTALL_DIR}/data/subscription/${TOKEN}"
runRead 15 subscription-drift dockerProtocolCommand list
dockerGenerateSubscription "${SPEC}" "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${TOKEN}"
cp "${PADM_DOCKER_INSTALL_DIR}/compose.json" "${TEST_ROOT}/saved-compose.json"
jq '.services.xray.ports += ["0.0.0.0:29999:29999/tcp"]' "${TEST_ROOT}/saved-compose.json" >"${PADM_DOCKER_INSTALL_DIR}/compose.json"
runRead 15 compose-drift dockerProtocolCommand links
cp "${TEST_ROOT}/saved-compose.json" "${PADM_DOCKER_INSTALL_DIR}/compose.json"
runRead 0 restored-baseline dockerProtocolCommand links vless-reality
[[ "$(<"${STDOUT}")" == "${REALITY_URI}" ]] || fail '恢复夹具后无法查看原有 Reality 链接'
runRead 130 int-cleanup protocolSignalRead INT links
runRead 143 term-cleanup protocolSignalRead TERM list

# HTTPS 发布开关不应控制只读节点导出，且读取旧版本不能悄悄落盘迁移。
jq '.core.protocols |= map(select(.id == 1)) | .tls = null | .subscription.enabled = false' \
    "${SPEC}" >"${TEST_ROOT}/v1-reality.json"
newState v1-reality "${TEST_ROOT}/v1-reality.json"
runRead 0 disabled-reality-links dockerProtocolCommand links
[[ "$(<"${STDOUT}")" == "${REALITY_URI}" ]] || fail '关闭 HTTPS 订阅后丢失 Reality 节点链接'
dockerConfigureSpecMigrate "${SPEC}" "${TEST_ROOT}/v3.json"
jq '.core.secondary_type = "sing-box" | .subscription.enabled = false |
  .core.protocols += [(.core.protocols[] | select(.id == 1) |
    .listener_id = "entry-secondary" | .core = "sing-box" | .server = "secondary.example.com" |
    .public_port = 24445 | .name = "Secondary-Reality")]' \
    "${TEST_ROOT}/v3.json" >"${TEST_ROOT}/dual.json"
newState dual "${TEST_ROOT}/dual.json"
runRead 0 dual-cli-list bash -u "${CLI}" protocol list
[[ "$(wc -l <"${STDOUT}")" == 3 ]] &&
    grep -qxF 'entry-secondary  sing-box  Reality Vision  secondary.example.com:24445  [ipv4,ipv6]  Secondary-Reality' "${STDOUT}" ||
    fail 'v3 双核心列表丢失副核心入口'
runRead 0 disabled-dual-links dockerProtocolCommand links
[[ "$(<"${STDOUT}")" == "${REALITY_URI}"$'\n'"${WS_URI}"$'\n'"${SING_URI}" ]] ||
    fail '关闭 HTTPS 订阅后丢失 WS 或双核心链接'
runRead 0 selected-secondary bash -u "${CLI}" protocol links entry-secondary
[[ "$(<"${STDOUT}")" == "${SING_URI}" ]] || fail '副核心选择没有精确筛选 URI'
runRead 0 selected-ws dockerProtocolCommand links vless-ws
[[ "$(<"${STDOUT}")" == "${WS_URI}" ]] || fail '关闭 HTTPS 订阅后无法单独读取 WS 链接'
runRead 15 dual-unknown dockerProtocolCommand links entry-missing

printf 'docker-protocol-regression-ok\n'
