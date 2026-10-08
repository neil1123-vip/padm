#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Linux ]]; then
    printf 'docker-tls-regression-skip: Linux root is required\n'
    exit 0
fi
[[ "$(id -u)" == 0 ]] || { printf 'docker-tls-regression-fail: run as root\n' >&2; exit 1; }
for tool in jq python3 openssl setpriv stat chown chmod mkfifo; do
    command -v "${tool}" >/dev/null || { printf 'missing tool: %s\n' "${tool}" >&2; exit 1; }
done
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-tls.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
export PADM_DOCKER_SKIP_CHOWN=0 PADM_DOCKER_LOCK_TIMEOUT=1 PADM_DOCKER_HEALTH_TIMEOUT=1
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/bootstrap.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/bundle.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/manifest.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/services.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/traffic.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/lifecycle.sh"

ACME_RUN_IMPLEMENTATION=$(declare -f dockerAcmeRun)
DOMAIN=example.com
MODE=ok
RAW_ACME_RUN=0
RUNNING_ID=$(printf 'a%.0s' {1..64})
STOPPED_ID=$(printf 'b%.0s' {1..64})
HTTPS_ID=$(printf 'c%.0s' {1..64})
CHALLENGE_ID=$(printf 'd%.0s' {1..64})
UNRELATED_ID=$(printf 'e%.0s' {1..64})
OPS_IMAGE="ghcr.io/example/padm-ops:3.2.0@sha256:$(printf 'a%.0s' {1..64})"
CERT_FILE=${TEST_ROOT}/new.crt
KEY_FILE=${TEST_ROOT}/new.key
CREDENTIALS=${TEST_ROOT}/dns.env
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=${DOMAIN}" \
    -addext "subjectAltName=DNS:${DOMAIN}" -keyout "${KEY_FILE}" -out "${CERT_FILE}" >/dev/null 2>&1
openssl req -x509 -new -key "${KEY_FILE}" -days 2 -set_serial 1 -subj "/CN=${DOMAIN}" \
    -addext "subjectAltName=DNS:${DOMAIN}" -out "${TEST_ROOT}/old.crt" >/dev/null 2>&1
printf 'DNS_API_TOKEN=private-dns-token\n' >"${CREDENTIALS}"
chmod 0600 "${KEY_FILE}" "${CREDENTIALS}"

fail() {
    printf 'docker-tls-regression-fail: %s\n' "$*" >&2
    [[ ! -f "${TEST_ROOT}/control.log" ]] || cat "${TEST_ROOT}/control.log" >&2
    exit 1
}
reject() { if "$@" >"${TEST_ROOT}/rejected.log" 2>&1; then fail "应拒绝: $*"; fi; }
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { [[ "$(<"${PADM_DOCKER_INSTALL_DIR}/mode")" == docker ]]; }
dockerSetupCleanup() { :; }
dockerEntryCleanup() { :; }
dockerTcpPortIsListening() {
    [[ "$1" == 80 ]] || fail '挑战检查了非 80 端口'
    [[ "${MODE}" == external-80 ||
        ( "${MODE}" == port-release-fail && -f "${TEST_ROOT}/stopped-once" ) ]]
}
ss() { printf 'LISTEN 0 128 0.0.0.0:80 0.0.0.0:* users:(("external",pid=1,fd=3))\n'; }
cp() {
    command cp "$@" || return $?
    if [[ "${MODE}" == term-copy &&
        "${*: -1}" == "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/.${DOMAIN}.crt.${BASHPID}" ]]; then
        kill -TERM "${BASHPID}"
    fi
}

# 保留实际候选校验，Docker 只映射 bind 路径到本测试目录。
docker() {
    local candidate='' script='' previous='' argument last='' state
    case "$1" in
    ps)
        case "$*" in
        'ps -q')
            jq -r '.[] | select(.State.Running) | .Id' "${TEST_ROOT}/containers.json"
            ;;
        'ps -aq --filter label=io.padm.challenge=fixture-challenge --filter label=io.padm.project=padm-docker')
            [[ ! -f "${TEST_ROOT}/challenge-container" ]] || printf '%s\n' "${CHALLENGE_ID}"
            ;;
        *) fail '运行容器发现依赖 Docker 端口过滤或挑战清理缺少 label' ;;
        esac
        return 0
        ;;
    container)
        [[ "${2:-}" == inspect ]] || fail '意外的容器命令'
        state=$(jq -c --argjson ids "$(printf '%s\n' "${@:3}" | jq -Rsc 'split("\n")|map(select(length>0))')" \
            '[.[] | select(.Id as $id | $ids | index($id) != null)]' "${TEST_ROOT}/containers.json")
        [[ "$(jq 'length' <<<"${state}")" == $(("$#" - 2)) ]] || return 1
        printf '%s\n' "${state}"
        return 0
        ;;
    stop|start)
        printf '%s\n' "$*" >>"${TEST_ROOT}/challenge.log"
        [[ -d "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail '暂停或恢复服务未持有部署锁'
        [[ "$#" == 2 && "$2" == "${RUNNING_ID}" ]] || fail '挑战修改了原停容器或无关 443 容器'
        [[ -f "${DOCKER_ACME_RECOVERY}" && "$(stat -c '%a' "${DOCKER_ACME_RECOVERY}")" == 600 ]] ||
            fail '暂停或恢复服务没有保留私有恢复记录'
        if [[ "$1" == start && "${MODE}" == restore-fail && ! -f "${TEST_ROOT}/restore-failed" ]]; then
            : >"${TEST_ROOT}/restore-failed"
            # start 成功不代表容器已运行，恢复必须检查实际状态。
            return 0
        fi
        state=false
        if [[ "$1" == start ]]; then state=true; else : >"${TEST_ROOT}/stopped-once"; fi
        jq --arg id "$2" --argjson running "${state}" 'map(if .Id == $id then .State.Running=$running else . end)' \
            "${TEST_ROOT}/containers.json" >"${TEST_ROOT}/containers.next"
        mv -- "${TEST_ROOT}/containers.next" "${TEST_ROOT}/containers.json"
        return 0
        ;;
    rm)
        printf '%s\n' "$*" >>"${TEST_ROOT}/challenge.log"
        [[ "$*" == "rm -f ${CHALLENGE_ID}" ]] || fail '恢复删除了非本轮挑战容器'
        rm -f -- "${TEST_ROOT}/challenge-container"
        return 0
        ;;
    esac
    [[ "$1" == run ]] || fail '意外的 Docker 命令'
    if [[ "${RAW_ACME_RUN}" == 1 ]]; then
        printf '%s\n' "$*" >>"${TEST_ROOT}/acme-docker.args"
        [[ -z "$(cat)" ]] || fail 'HTTP 验证向工具注入了 DNS 凭据'
        return 0
    fi
    printf 'validate\n' >>"${TEST_ROOT}/ops.log"
    for argument in "$@"; do
        if [[ "${previous}" == --volume && "${argument}" == *:/candidate:ro ]]; then
            candidate=${argument%:/candidate:ro}
        elif [[ "${previous}" == -c ]]; then
            script=${argument}
        fi
        previous=${argument}
        last=${argument}
    done
    [[ -n "${candidate}" ]] || fail '证书校验缺少只读 bind'
    if [[ -n "${script}" ]]; then
        [[ "${MODE}" != validity-fail ]] || return 1
        python3 -c "${script}" "${candidate}/${last#/candidate/}"
    else
        [[ "${MODE}" != match-fail ]] || return 1
        bash -c '
            trap '\''rm -f -- "/tmp/padm-cert-public.$$" "/tmp/padm-key-public.$$"'\'' EXIT
            source "$1" tls-check "$2" "$3" "$4"
        ' _ "${PROJECT_ROOT}/docker/images/ops/entrypoint.sh" \
            "${candidate}/${DOMAIN}.crt" "${candidate}/${DOMAIN}.key" "${last}"
    fi
}

dockerAcmeRun() {
    local image=$1 credentials=$2 account=$3 output=$4 action=$5 configDir=${DOMAIN} webroot=dns_test
    local http01=0 challenge
    [[ "${image}" == "${OPS_IMAGE}" && ( "${credentials}" == "${CREDENTIALS}" || -z "${credentials}" ) &&
        "${account}" == "${PADM_DOCKER_INSTALL_DIR}/.tls."*/acme &&
        "${output}" == "${account%/acme}" ]] || fail 'ACME 未隔离候选账户'
    [[ "$(stat -c '%u %g' "${account}")" == '10001 10001' ]] || fail '候选账户不能由容器读取'
    [[ "$(<"${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json")" == history ]] || fail 'ACME 修改了累计流量'
    printf '%s\n' "${*:5}" >>"${TEST_ROOT}/acme.args"
    if [[ "${action}" == --issue ]]; then
        if [[ -f "${PADM_DOCKER_INSTALL_DIR}/data/acme/${DOMAIN}/${DOMAIN}.conf" ]]; then
            [[ " ${*:5} " == *' --keylength 2048 '* && " ${*:5} " != *' --keylength ec-256 '* ]] ||
                fail '已有 RSA 申请没有明确保持 2048 位密钥'
        else
            [[ " ${*:5} " == *' --keylength ec-256 '* && " ${*:5} " != *' --keylength 2048 '* ]] ||
                fail '新 ACME 申请没有明确使用默认 ECC 密钥'
            configDir=${DOMAIN}_ecc
        fi
    elif [[ "${action}" == --renew || "${action}" == --install-cert ]]; then
        if [[ -f "${account}/${DOMAIN}/${DOMAIN}.conf" ]]; then
            [[ " ${*:5} " != *' --ecc '* ]] || fail '已有 RSA 账户被误用 ECC 续期或导出'
        elif [[ -f "${account}/${DOMAIN}_ecc/${DOMAIN}.conf" ]]; then
            [[ " ${*:5} " == *' --ecc '* ]] || fail 'ECC 账户续期或导出缺少 --ecc'
            configDir=${DOMAIN}_ecc
        fi
    fi
    if [[ -z "${credentials}" ]]; then
        webroot=no
        if jq -e '.tls.http01 == true' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >/dev/null; then
            http01=1
            webroot=/var/lib/padm/acme-webroot
        fi
        if [[ "${action}" == --renew &&
            "$(grep '^Le_PreHook=' "${account}/${configDir}/${DOMAIN}.conf")" == *renew.due* ]]; then
            [[ "${DOCKER_ACME_PORT_PUBLISH}" == 0 && "${#DOCKER_ACME_STOPPED[@]}" == 0 ]] ||
                fail '续期预检暂停了服务或发布了端口'
            printf 'probe\n' >>"${TEST_ROOT}/acme.log"
            [[ "${MODE}" != renew-skip ]] || return 2
            printf due >"${output}/renew.due"
            return 1
        fi
        if [[ "${http01}" == 1 && ( "${action}" == --issue || "${action}" == --renew ) ]]; then
            [[ "${DOCKER_ACME_PORT_PUBLISH}" == 0 && "${#DOCKER_ACME_STOPPED[@]}" == 0 &&
                -z "${DOCKER_ACME_CONTAINER}" ]] || fail 'webroot 仍暂停服务或发布临时端口'
            [[ "${action}" != --issue || " ${*:5} " == *' --webroot /var/lib/padm/acme-webroot '* ]] ||
                fail 'webroot 申请未使用固定容器路径'
            [[ "${action}" != --renew ||
                "$(grep '^Le_Webroot=' "${account}/${configDir}/${DOMAIN}.conf")" == "Le_Webroot='/var/lib/padm/acme-webroot'" ]] ||
                fail 'webroot 续期没有沿用固定账户路径'
            [[ "${DOCKER_ACME_WEBROOT:-}" == "${PADM_DOCKER_INSTALL_DIR}/data/acme-webroot/active" ]] ||
                fail 'webroot 未隔离本轮挑战子目录'
            challenge=${DOCKER_ACME_WEBROOT}/.well-known/acme-challenge
            [[ -d "${challenge}" && "$(stat -c '%u %g' "${challenge}")" == '10001 10001' ]] ||
                fail '挑战 token 目录不能由 ops UID 写入'
            (
                cd "${challenge}"
                setpriv --reuid 10001 --regid 10001 --clear-groups -- sh -c \
                    'printf "Padm_token-123.thumbprint_456\n" >Padm_token-123'
            ) || fail 'ops UID 不能写挑战 token'
            [[ "${MODE}" != renew-skip || "${action}" != --renew ]] || return 2
        elif [[ "${action}" == --issue || "${action}" == --renew ]]; then
            [[ "${DOCKER_ACME_PORT_PUBLISH}" == 1 && " ${*:5} " == *' --httpport 8080 '* ]] ||
                fail 'HTTP 验证未准备宿主端口或未用容器 8080'
            [[ "${action}" != --issue || " ${*:5} " == *' --standalone '* ]] ||
                fail 'HTTP 申请仍使用 DNS 验证'
            [[ "$(dockerAcmePortOwners)" == '[]' ]] || fail 'HTTP 工具运行时旧宿主 80 端口仍占用'
            [[ "${action}" != --renew ||
                "$(grep '^Le_PreHook=' "${account}/${configDir}/${DOMAIN}.conf")" == "Le_PreHook='printf original-hook'" ]] ||
                fail '真正续期没有恢复原 ACME prehook'
            DOCKER_ACME_CONTAINER=fixture-challenge
            : >"${TEST_ROOT}/challenge-container"
        elif [[ "${action}" == --install-cert ]]; then
            [[ "${DOCKER_ACME_PORT_PUBLISH}" == 0 && ! -f "${TEST_ROOT}/challenge-container" ]] ||
                fail '导出前没有清理挑战并恢复服务'
            [[ "${http01}" == 0 || ! -e "${PADM_DOCKER_INSTALL_DIR}/data/acme-webroot/active" ]] ||
                fail 'webroot 导出前没有清理本轮挑战'
        fi
    fi
    printf '%s\n' "${action}" >>"${TEST_ROOT}/acme.log"
    (
        cd "${account}"
        setpriv --reuid 10001 --regid 10001 --clear-groups -- sh -c '
            printf "new-account-%s\n" "$1" >account.conf
            mkdir -p "$2"
            printf "new-domain-state\n" >"$2/domain.conf"
            if [ "$1" = --issue ] && [ ! -f "$2/$3.conf" ]; then
                printf "Le_Domain='\''%s'\''\nLe_Webroot='\''%s'\''\nLe_HTTPPort='\''8080'\''\n" "$3" "$4" >"$2/$3.conf"
            fi
        ' _ "${action}" "${configDir}" "${DOMAIN}" "${webroot}"
    ) || fail '容器 UID 不能更新候选账户'
    if [[ ( "${MODE}" == issue-fail && "${action}" == --issue ) ||
        ( "${MODE}" == renew-fail && "${action}" == --renew ) ||
        ( "${MODE}" == export-fail && "${action}" == --install-cert ) ]]; then return 1; fi
    if [[ "${MODE}" == term-issue && "${action}" == --issue ]]; then kill -TERM "${BASHPID}"; fi
    if [[ "${MODE}" == int-issue && "${action}" == --issue ]]; then kill -INT "${BASHPID}"; fi
    if [[ "${action}" == --install-cert ]]; then
        cp -- "${CERT_FILE}" "${output}/${DOMAIN}.crt"
        cp -- "${KEY_FILE}" "${output}/${DOMAIN}.key"
    fi
}

dockerComposeRun() {
    local generation=old
    case "$1" in stop|down|restart) fail 'TLS 事务扩大为 Compose 全项目停启' ;; esac
    cmp -s "${CERT_FILE}" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt" && generation=new
    printf '%s\n' "$*" >>"${TEST_ROOT}/compose.log"
    printf '%s:%s\n' "${generation}" "$*" >>"${TEST_ROOT}/events.log"
    [[ -d "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'TLS 重载未持有部署锁'
    if [[ "${MODE}" == core-check-fail && "$1" == run && "$4" == sing-box ]]; then return 1; fi
    if [[ "$1" == up && "${*: -1}" == sing-box && ! -e "${TEST_ROOT}/failed-once" &&
        ( "${MODE}" == second-core-fail || "${MODE}" == restore-first-fail ) ]]; then
        : >"${TEST_ROOT}/failed-once"
        return 1
    fi
    if [[ "${MODE}" == restore-first-fail && "$1" == up && "${*: -1}" == xray &&
        -e "${TEST_ROOT}/failed-once" ]]; then return 1; fi
    if [[ "${MODE}" == term-core && "$1" == up && "${*: -1}" == sing-box &&
        ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"
        kill -TERM "${BASHPID}"
    fi
    if [[ ! -e "${TEST_ROOT}/failed-once" ]]; then
        if [[ ( "${MODE}" == nginx-test-fail && "$*" == 'exec -T nginx nginx -e /dev/stderr -t' ) ||
            ( "${MODE}" == reload-fail && "$*" == 'exec -T nginx nginx -e /dev/stderr -s reload' ) ||
            ( "${MODE}" == health-fail && "$1" == up ) ]]; then
            : >"${TEST_ROOT}/failed-once"
            return 1
        fi
        if [[ "${MODE}" == term-reload && "$*" == 'exec -T nginx nginx -e /dev/stderr -s reload' ]]; then
            : >"${TEST_ROOT}/failed-once"
            kill -TERM "${BASHPID}"
        fi
    fi
}

dockerTrafficSnapshot() {
    local generation=old
    cmp -s "${CERT_FILE}" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt" && generation=new
    printf 'snapshot-%s\n' "${generation}" >>"${TEST_ROOT}/compose.log"
    [[ "${MODE}" != snapshot-fail ]]
}

dockerCandidateCompose() {
    shift
    dockerComposeRun "$@"
}

newState() {
    export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/$1"
    dockerInitializeStateRoot
    mkdir -p "${PADM_DOCKER_INSTALL_DIR}/secrets/tls" "${PADM_DOCKER_INSTALL_DIR}/data/acme/other.example.com" \
        "${PADM_DOCKER_INSTALL_DIR}/data/traffic"
    cp -- "${TEST_ROOT}/old.crt" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt"
    cp -- "${KEY_FILE}" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.key"
    printf 'other-certificate\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/other.example.com.crt"
    printf 'other-key\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/other.example.com.key"
    dockerTlsRuntimePermissions "${PADM_DOCKER_INSTALL_DIR}/secrets/tls"
    printf 'old-account\n' >"${PADM_DOCKER_INSTALL_DIR}/data/acme/account.conf"
    printf 'other-domain\n' >"${PADM_DOCKER_INSTALL_DIR}/data/acme/other.example.com/domain.conf"
    chown -R 10001:10001 "${PADM_DOCKER_INSTALL_DIR}/data/acme"
    find "${PADM_DOCKER_INSTALL_DIR}/data/acme" -type d -exec chmod 0750 {} +
    find "${PADM_DOCKER_INSTALL_DIR}/data/acme" -type f -exec chmod 0600 {} +
    printf 'history\n' >"${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json"
    jq -n --arg ops "${OPS_IMAGE}" '
      def ref($name): $ops | sub("padm-ops"; "padm-" + $name);
      {schema_version:1,release:{version:"3.2.0",manifest_sha256:("a"*64),signature_identity:"test"},
       core:{type:"xray",protocols:[{id:21,server:"proxy.example.com",public_port:24443,
         address_families:["ipv4"],name:"main",uuid:"11111111-1111-4111-8111-111111111111",
         websocket:{domain:"example.com",path:"abcdefgh"}}]},
       tls:{domain:"example.com"},subscription:{enabled:false,token:("a"*32)},
       images:{xray:ref("xray"),"sing-box":ref("sing-box"),nginx:ref("nginx"),ops:$ops,net:ref("net")},
       host_integrations:[]}
    ' >"${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    jq -n --slurpfile spec "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" '
      $spec[0] as $s |
      {schema_version:1,mode:"docker",padm_version:$s.release.version,bundle_version:"fixture",
       manifest:{sha256:$s.release.manifest_sha256,signature_identity:$s.release.signature_identity},
       compose:{project:"padm-docker",profiles:["core-xray","nginx"]},core:{type:"xray",protocol_ids:[21]},
       listeners:[{service:"nginx",public_port:24443,container_port:8443,transport:"tcp",address_families:["ipv4"]}],
       images:($s.images|with_entries(.value={index_digest:(.value|split("@")|last)})),
       formats:{compose:1,config:1,data:1},previous_manifest_sha256:null,host_integrations:[]}
    ' >"${PADM_DOCKER_INSTALL_DIR}/deployment.json"
    : >"${PADM_DOCKER_INSTALL_DIR}/images.env"
    dockerGenerateImagesEnv "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/images.env" "${PADM_DOCKER_INSTALL_DIR}"
    dockerDeploymentFileValidate "${PADM_DOCKER_INSTALL_DIR}/deployment.json" || fail '部署夹具格式错误'
    dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" || fail '规格夹具不一致'
    mkdir -p "${PADM_DOCKER_INSTALL_DIR}/config/xray" "${PADM_DOCKER_INSTALL_DIR}/config/nginx"
    dockerGenerateXrayConfig "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json"
    dockerGenerateNginxConfig "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf"
    dockerGenerateCompose "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/compose.json"
    MODE=ok
    rm -f -- "${TEST_ROOT}/failed-once" "${TEST_ROOT}/stopped-once" "${TEST_ROOT}/restore-failed" \
        "${TEST_ROOT}/challenge-container"
    printf '[]\n' >"${TEST_ROOT}/containers.json"
    DOCKER_ACME_STOPPED=()
    DOCKER_ACME_CONTAINER=
    DOCKER_ACME_PORT_PUBLISH=0
    DOCKER_ACME_RECOVERY=
    DOCKER_ACME_RUNNING=null
    DOCKER_ACME_WEBROOT=
    : >"${TEST_ROOT}/compose.log"
    : >"${TEST_ROOT}/events.log"
    : >"${TEST_ROOT}/acme.log"
    : >"${TEST_ROOT}/acme.args"
    : >"${TEST_ROOT}/challenge.log"
    : >"${TEST_ROOT}/ops.log"
}

standaloneState() {
    newState "$1"
    jq '.core.protocols[0].public_port=80' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        >"${TEST_ROOT}/standalone-spec.json"
    cp -- "${TEST_ROOT}/standalone-spec.json" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    jq '.listeners[0].public_port=80' "${PADM_DOCKER_INSTALL_DIR}/deployment.json" \
        >"${TEST_ROOT}/standalone-deployment.json"
    cp -- "${TEST_ROOT}/standalone-deployment.json" "${PADM_DOCKER_INSTALL_DIR}/deployment.json"
    dockerGenerateCompose "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${PADM_DOCKER_INSTALL_DIR}/compose.json"
    mkdir -- "${PADM_DOCKER_INSTALL_DIR}/data/acme/${DOMAIN}"
    printf "Le_Domain='%s'\nLe_Webroot='no'\nLe_HTTPPort='8080'\nLe_PreHook='printf original-hook'\n" "${DOMAIN}" \
        >"${PADM_DOCKER_INSTALL_DIR}/data/acme/${DOMAIN}/${DOMAIN}.conf"
    chown -R 10001:10001 "${PADM_DOCKER_INSTALL_DIR}/data/acme/${DOMAIN}"
    chmod 0750 "${PADM_DOCKER_INSTALL_DIR}/data/acme/${DOMAIN}"
    chmod 0600 "${PADM_DOCKER_INSTALL_DIR}/data/acme/${DOMAIN}/${DOMAIN}.conf"
    jq -n --arg root "${PADM_DOCKER_INSTALL_DIR}" --arg running "${RUNNING_ID}" \
        --arg stopped "${STOPPED_ID}" --arg https "${HTTPS_ID}" --arg unrelated "${UNRELATED_ID}" \
        --slurpfile spec "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        --slurpfile compose "${PADM_DOCKER_INSTALL_DIR}/compose.json" '
      {Id:$running,State:{Running:true,Restarting:false},Config:{Image:$spec[0].images.nginx,Labels:{
        "com.docker.compose.project":"padm-docker","com.docker.compose.service":"nginx",
        "com.docker.compose.project.working_dir":$root,
        "com.docker.compose.project.config_files":($root+"/compose.json"),
        "io.padm.mode":"docker","io.padm.project":"padm-docker","io.padm.component":"nginx"}},
       HostConfig:{NetworkMode:"padm-docker_default",PortBindings:{"8443/tcp":[{HostIp:"0.0.0.0",HostPort:"80"}]},
         Tmpfs:{"/tmp":"rw,noexec,nosuid,nodev,size=32m"}},
       Mounts:($compose[0].services.nginx.volumes|map(
         {Type:"bind",Source:(.source|sub("^\\$\\{PADM_DOCKER_ROOT\\}";$root)),Destination:.target,RW:(.read_only|not)})),
       NetworkSettings:{Networks:{default:{IPAddress:"172.28.0.2",GlobalIPv6Address:""}}}} as $container |
      [$container,($container|.Id=$stopped|.State.Running=false),
       ($container|.Id=$https|.Config.Image=$spec[0].images.xray|
         .Config.Labels["com.docker.compose.service"]="xray"|.Config.Labels["io.padm.component"]="xray"|
         .HostConfig.PortBindings={"443/tcp":[{HostIp:"0.0.0.0",HostPort:"443"}]}),
       ($container|.Id=$unrelated|.Config.Labels={}|.Config.Image="unrelated:fixture"|
         .HostConfig.PortBindings={"80/tcp":[{HostIp:"0.0.0.0",HostPort:"8081"}]})]
    ' >"${TEST_ROOT}/containers.json"
    cp -- "${TEST_ROOT}/containers.json" "${TEST_ROOT}/containers.before"
}

webrootState() {
    local name=$1 protocol=${2:-21}
    newState "${name}"
    jq --argjson protocol "${protocol}" '
      .schema_version=3 | .core.secondary_type=null | .tls.http01=true |
      .core.protocols[0] += {core:"xray",listener_id:"entry-webroot"} |
      if $protocol == 21 then .core.protocols[0].websocket += {backend_port:31297,tls_port:8443}
      else .core.protocols[0] |= (del(.websocket) + {id:$protocol,
        fallback_tls:{domain:"example.com",http_port:31300,http2_port:31302}}) end
    ' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${TEST_ROOT}/webroot-spec.json"
    cp -- "${TEST_ROOT}/webroot-spec.json" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    jq --argjson protocol "${protocol}" '
      .core += {secondary_type:null,protocol_ids:[$protocol]} |
      .listeners[0] += {listener_id:"entry-webroot",
        service:(if $protocol == 21 then "nginx" else "xray" end),
        container_port:(if $protocol == 21 then 8443 else 24443 end)} |
      .listeners += [{listener_id:"host-acme-http",service:"nginx",public_port:80,
        container_port:8088,transport:"tcp",address_families:["ipv4","ipv6"]}]
    ' "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >"${TEST_ROOT}/webroot-deployment.json"
    cp -- "${TEST_ROOT}/webroot-deployment.json" "${PADM_DOCKER_INSTALL_DIR}/deployment.json"
    dockerGenerateXrayConfig "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json"
    dockerGenerateNginxConfig "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf"
    dockerGenerateCompose "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${PADM_DOCKER_INSTALL_DIR}/compose.json"
    dockerConfigureSpecValidate "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" &&
        dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
            "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" ||
        fail 'webroot 夹具没有使用有效的真实部署合同'
    mkdir -p "${PADM_DOCKER_INSTALL_DIR}/data/acme-webroot" "${PADM_DOCKER_INSTALL_DIR}/data/acme/${DOMAIN}"
    chmod 0750 "${PADM_DOCKER_INSTALL_DIR}/data/acme-webroot"
    chown 10001:10001 "${PADM_DOCKER_INSTALL_DIR}/data/acme-webroot"
    WEBROOT_INODE=$(stat -c '%d:%i' "${PADM_DOCKER_INSTALL_DIR}/data/acme-webroot")
    printf "Le_Domain='%s'\nLe_Webroot='/var/lib/padm/acme-webroot'\nLe_PreHook='printf original-hook'\n" \
        "${DOMAIN}" >"${PADM_DOCKER_INSTALL_DIR}/data/acme/${DOMAIN}/${DOMAIN}.conf"
    chown -R 10001:10001 "${PADM_DOCKER_INSTALL_DIR}/data/acme/${DOMAIN}"
    chmod 0750 "${PADM_DOCKER_INSTALL_DIR}/data/acme/${DOMAIN}"
    chmod 0600 "${PADM_DOCKER_INSTALL_DIR}/data/acme/${DOMAIN}/${DOMAIN}.conf"
    jq -n --arg root "${PADM_DOCKER_INSTALL_DIR}" --arg running "${RUNNING_ID}" \
        --arg stopped "${STOPPED_ID}" --arg https "${HTTPS_ID}" \
        --slurpfile spec "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        --slurpfile compose "${PADM_DOCKER_INSTALL_DIR}/compose.json" '
      def container($id; $service; $running; $ports):
        {Id:$id,State:{Running:$running,Restarting:false},Config:{Image:$spec[0].images[$service],Labels:{
          "com.docker.compose.project":"padm-docker","com.docker.compose.service":$service,
          "com.docker.compose.project.working_dir":$root,
          "com.docker.compose.project.config_files":($root+"/compose.json"),
          "io.padm.mode":"docker","io.padm.project":"padm-docker","io.padm.component":$service}},
         HostConfig:{NetworkMode:"padm-docker_default",PortBindings:$ports,
           Tmpfs:{"/tmp":"rw,noexec,nosuid,nodev,size=32m"}},
         Mounts:($compose[0].services[$service].volumes|map(
           {Type:"bind",Source:(.source|sub("^\\$\\{PADM_DOCKER_ROOT\\}";$root)),
            Destination:.target,RW:(.read_only|not)})),
         NetworkSettings:{Networks:{default:{IPAddress:"172.28.0.2",GlobalIPv6Address:""}}}};
      {"8088/tcp":[{HostIp:"0.0.0.0",HostPort:"80"},{HostIp:"::",HostPort:"80"}]} as $http |
      [$http + (if $spec[0].core.protocols[0].id == 21 then
          {"8443/tcp":[{HostIp:"0.0.0.0",HostPort:"24443"}]} else {} end) |
        container($running;"nginx";true;.)] +
      [container($stopped;"nginx";false;$http),
       container($https;"xray";true;{"24443/tcp":[{HostIp:"0.0.0.0",HostPort:"24443"}]})]
    ' >"${TEST_ROOT}/containers.json"
    cp -- "${TEST_ROOT}/containers.json" "${TEST_ROOT}/containers.before"
}

assertWebrootRestored() {
    assertChallengeRestored
    [[ ! -s "${TEST_ROOT}/challenge.log" &&
        ! -e "${PADM_DOCKER_INSTALL_DIR}/data/acme-webroot/active" &&
        "$(stat -c '%d:%i' "${PADM_DOCKER_INSTALL_DIR}/data/acme-webroot")" == "${WEBROOT_INODE}" ]] ||
        fail 'webroot 清理停启了服务、遗留挑战或替换了在线挂载根'
}

assertChallengeRestored() {
    cmp -s "${TEST_ROOT}/containers.json" "${TEST_ROOT}/containers.before" ||
        fail '挑战没有恢复原运行状态或启动了原停/无关服务'
    [[ ! -e "${TEST_ROOT}/challenge-container" ]] || fail '本轮挑战容器未清理'
    [[ "$(<"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/other.example.com.crt")" == other-certificate &&
        "$(<"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/other.example.com.key")" == other-key &&
        "$(<"${PADM_DOCKER_INSTALL_DIR}/data/acme/other.example.com/domain.conf")" == other-domain ]] ||
        fail 'HTTP 验证修改了其它域名材料'
}

coreTlsState() {
    local name=$1 core=$2 nginx=${3:-false}
    newState "${name}"
    # 内部 TLS 底座夹具直接构造核心配置；不放宽菜单的协议规格。
    if [[ "${core}" == both ]]; then
        jq '
          .schema_version = 3 | .core.secondary_type = "sing-box" |
          .core.protocols |= map(. + {listener_id:"entry-ws",core:"xray"} |
            .websocket += {backend_port:31297,tls_port:8443}) |
          .core.protocols += [{id:1,listener_id:"entry-sing",core:"sing-box",server:"proxy.example.com",
            public_port:24444,address_families:["ipv4"],name:"sing",uuid:"11111111-1111-4111-8111-111111111111",
            reality:{server_name:"www.example.com",target_host:"www.example.com",target_port:443,
              private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
              public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",short_id:"6ba85179e30d4fc2"}}]
        ' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${TEST_ROOT}/core-spec.json"
        cp -- "${TEST_ROOT}/core-spec.json" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
        jq '.core += {secondary_type:"sing-box",protocol_ids:[1,21]} |
          .compose.profiles += ["core-sing-box"] |
          .listeners[0] += {listener_id:"entry-ws"} |
          .listeners += [{listener_id:"entry-sing",service:"sing-box",public_port:24444,container_port:24444,
            transport:"tcp",address_families:["ipv4"]}]' \
            "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >"${TEST_ROOT}/core-deployment.json"
        cp -- "${TEST_ROOT}/core-deployment.json" "${PADM_DOCKER_INSTALL_DIR}/deployment.json"
        mkdir -p "${PADM_DOCKER_INSTALL_DIR}/config/sing-box"
        dockerGenerateSingBoxConfig "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
            "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json"
    fi
    jq --arg domain "${DOMAIN}" '.inbounds += [
      {tag:"internal-tls",port:25443,protocol:"trojan",settings:{clients:[]},
       streamSettings:{network:"tcp",security:"tls",tlsSettings:{certificates:[
         {certificateFile:("/etc/padm/secrets/tls/"+$domain+".crt"),
          keyFile:("/etc/padm/secrets/tls/"+$domain+".key")},
         {certificateFile:("/etc/padm/secrets/tls/"+$domain+".crt"),
          keyFile:("/etc/padm/secrets/tls/"+$domain+".key")}]}}}]' \
        "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json" >"${TEST_ROOT}/core-config.json"
    cp -- "${TEST_ROOT}/core-config.json" "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json"
    if [[ "${core}" == both ]]; then
        jq --arg domain "${DOMAIN}" '.inbounds += [
          {type:"trojan",tag:"internal-tls",listen_port:25444,users:[],
           tls:{enabled:true,certificate_path:("/etc/padm/secrets/tls/"+$domain+".crt"),
             key_path:("/etc/padm/secrets/tls/"+$domain+".key")}}]' \
            "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json" >"${TEST_ROOT}/core-config.json"
        cp -- "${TEST_ROOT}/core-config.json" "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json"
    fi
    if [[ "${nginx}" == false ]]; then
        jq '.compose.profiles -= ["nginx"]' "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >"${TEST_ROOT}/core-deployment.json"
        cp -- "${TEST_ROOT}/core-deployment.json" "${PADM_DOCKER_INSTALL_DIR}/deployment.json"
        rm -- "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf"
    fi
    dockerGenerateCompose "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${PADM_DOCKER_INSTALL_DIR}/compose.json"
    if [[ "${nginx}" == false ]]; then
        jq 'del(.services.nginx, .services.subscription)' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >"${TEST_ROOT}/core-compose.json"
        cp -- "${TEST_ROOT}/core-compose.json" "${PADM_DOCKER_INSTALL_DIR}/compose.json"
    fi
}

runCoreCommit() {
    local expected=$1 status
    if (
        trap 'dockerCommandInterrupted 143' TERM
        dockerAcquireDeploymentLock
        dockerCreateTlsCandidate
        cp -- "${CERT_FILE}" "${DOCKER_TLS_CANDIDATE}/${DOMAIN}.crt"
        cp -- "${KEY_FILE}" "${DOCKER_TLS_CANDIDATE}/${DOMAIN}.key"
        if dockerCommitTlsCandidate "${DOCKER_TLS_CANDIDATE}" "${DOMAIN}"; then status=0; else status=$?; fi
        dockerRestoreTlsFiles || true
        dockerCleanupTlsCandidate
        dockerReleaseDeploymentLock
        exit "${status}"
    ) >"${TEST_ROOT}/control.log" 2>&1; then status=0; else status=$?; fi
    if [[ "${expected}" == failure ]]; then
        [[ "${status}" != 0 ]] || fail '核心 TLS 失败场景被接受'
    elif [[ "${status}" != "${expected}" ]]; then
        cat "${TEST_ROOT}/control.log" >&2
        fail "核心 TLS 预期 ${expected}，实际 ${status}"
    fi
    assertClean
}

materials() (
    cd "${PADM_DOCKER_INSTALL_DIR}"
    find secrets/tls data/acme -type f -print0 | sort -z | xargs -0 -r sha256sum
)

assertClean() {
    local root=${PADM_DOCKER_INSTALL_DIR}
    [[ ! -e "${root}/locks/deployment.lock" ]] || fail '部署锁未释放'
    [[ -z "$(find "${root}" -maxdepth 1 -name '.tls.*' -print -quit)" ]] || fail 'TLS 候选未清理'
    [[ -z "$(find "${root}/secrets/tls" -maxdepth 1 -name '.*' -type f -print -quit)" ]] || fail '临时证书未清理'
    [[ "$(<"${root}/data/traffic/state.json")" == history ]] || fail 'TLS 修改了历史累计'
}

runControl() {
    local expected=$1 status
    shift
    if (dockerMain "$@") >"${TEST_ROOT}/control.log" 2>&1; then status=0; else status=$?; fi
    if [[ "${status}" != "${expected}" ]]; then cat "${TEST_ROOT}/control.log" >&2; fail "$*: 预期 ${expected}，实际 ${status}"; fi
    assertClean
}

assertPermissions() {
    local root=${PADM_DOCKER_INSTALL_DIR}
    [[ "$(stat -c '%a %u %g' "${root}/secrets/tls/${DOMAIN}.key")" == '600 10001 10001' &&
        "$(stat -c '%a %u %g' "${root}/secrets/tls/${DOMAIN}.crt")" == '640 0 10001' ]] || fail '证书运行权限不正确'
    (
        cd "${root}/secrets/tls"
        setpriv --reuid 10001 --regid 10001 --clear-groups -- sh -c \
            'test -r example.com.key && test -r example.com.crt'
    ) || fail '容器 UID 不能读取证书'
    (
        cd "${root}/data/acme"
        setpriv --reuid 10001 --regid 10001 --clear-groups -- sh -c \
            'test -r account.conf && test -w account.conf && test -w .'
    ) || fail '容器 UID 不能使用 ACME 账户'
}

for ACTION in issue renew; do
    newState "${ACTION}-success"
    runControl 0 acme "${ACTION}" --domain "${DOMAIN}" --email admin@example.com --dns dns_test --credentials "${CREDENTIALS}"
    cmp -s "${CERT_FILE}" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt" || fail '申请或续期未安装新证书'
    grep -qxF 'new-account---install-cert' "${PADM_DOCKER_INSTALL_DIR}/data/acme/account.conf" || fail '候选账户未提交'
    [[ "$(<"${PADM_DOCKER_INSTALL_DIR}/data/acme/other.example.com/domain.conf")" == other-domain &&
        "$(<"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/other.example.com.crt")" == other-certificate &&
        "$(<"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/other.example.com.key")" == other-key ]] || fail '修改了其它域名'
    [[ "$(head -n 2 "${TEST_ROOT}/compose.log")" == $'exec -T nginx nginx -e /dev/stderr -t\nexec -T nginx nginx -e /dev/stderr -s reload' ]] ||
        fail '重载未先校验 Nginx'
    assertPermissions
    before=$(materials)
    : >"${TEST_ROOT}/compose.log"
    runControl 0 tls validate --domain "${DOMAIN}"
    [[ "$(materials)" == "${before}" && ! -s "${TEST_ROOT}/compose.log" ]] || fail '证书校验写入或重启了部署'
done

for MODE_CASE in issue-fail renew-fail export-fail validity-fail match-fail nginx-test-fail reload-fail health-fail \
    term-issue term-copy term-reload; do
    newState "${MODE_CASE}"
    before=$(materials)
    MODE=${MODE_CASE}
    ACTION=issue
    [[ "${MODE}" != renew-fail ]] || ACTION=renew
    EXPECTED=15
    [[ "${MODE}" != term-* ]] || EXPECTED=143
    runControl "${EXPECTED}" acme "${ACTION}" --domain "${DOMAIN}" --email admin@example.com --dns dns_test --credentials "${CREDENTIALS}"
    [[ "$(materials)" == "${before}" ]] || fail "${MODE}: 失败或中断未恢复证书与账户"
    assertPermissions
done

# HTTP 专项只覆盖新增停启合同；材料提交和失败回滚继续复用上面的 TLS 断言。
for ACTION in issue renew; do
    standaloneState "standalone-${ACTION}"
    dockerAcmePortOwners | jq -e --arg id "${RUNNING_ID}" '
      length == 1 and .[0].Id == $id and .[0].HostConfig.PortBindings["8443/tcp"][0].HostPort == "80"
    ' >/dev/null || fail '未检出宿主 80 到 8443，或误选宿主 8081 到容器 80'
    runControl 0 acme "${ACTION}" --domain "${DOMAIN}" --email admin@example.com --standalone
    cmp -s "${CERT_FILE}" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt" || fail 'HTTP 验证未提交新证书'
    [[ "$(<"${TEST_ROOT}/challenge.log")" == "stop ${RUNNING_ID}"$'\n'"rm -f ${CHALLENGE_ID}"$'\n'"start ${RUNNING_ID}" ]] ||
        fail 'HTTP 验证没有按本轮 ID 暂停、清理和恢复'
    if [[ "${ACTION}" == renew ]]; then
        [[ "$(head -n 2 "${TEST_ROOT}/acme.log")" == $'probe\n--renew' ]] ||
            fail 'HTTP 续期未先使用工具预检到期'
    else
        grep -Eq '^--issue .* --keylength 2048( |$)' "${TEST_ROOT}/acme.args" ||
            fail 'RSA 申请没有显式密钥参数'
        ! grep -Eq '^--install-cert .* --ecc( |$)' "${TEST_ROOT}/acme.args" ||
            fail 'RSA 证书导出错误使用 ECC 账户'
    fi
    assertChallengeRestored
    assertPermissions
done

for MODE_CASE in external-80 ownership-drift port-release-fail issue-fail restore-fail int-issue term-issue; do
    standaloneState "standalone-${MODE_CASE}"
    before=$(materials)
    MODE=${MODE_CASE}
    EXPECTED=15
    case "${MODE}" in
    ownership-drift)
        jq '.[0].Config.Labels["com.docker.compose.project.working_dir"]="/outside/deployment"' \
            "${TEST_ROOT}/containers.json" >"${TEST_ROOT}/containers.next"
        mv -- "${TEST_ROOT}/containers.next" "${TEST_ROOT}/containers.json"
        cp -- "${TEST_ROOT}/containers.json" "${TEST_ROOT}/containers.before"
        ;;
    int-issue) EXPECTED=130 ;;
    term-issue) EXPECTED=143 ;;
    esac
    runControl "${EXPECTED}" acme issue --domain "${DOMAIN}" --email admin@example.com --standalone
    [[ "$(materials)" == "${before}" ]] || fail "${MODE}: HTTP 失败没有保留证书与账户"
    assertChallengeRestored
    assertPermissions
    case "${MODE}" in
    external-80|ownership-drift)
        [[ ! -s "${TEST_ROOT}/challenge.log" && ! -s "${TEST_ROOT}/acme.log" &&
            ! -s "${TEST_ROOT}/compose.log" ]] || fail '外部占用或归属漂移仍暂停或执行挑战'
        ;;
    port-release-fail)
        [[ "$(<"${TEST_ROOT}/challenge.log")" == "stop ${RUNNING_ID}"$'\n'"start ${RUNNING_ID}" &&
            ! -s "${TEST_ROOT}/acme.log" ]] || fail '端口未释放仍执行挑战或没有恢复'
        ;;
    restore-fail)
        [[ "$(grep -c "^start ${RUNNING_ID}$" "${TEST_ROOT}/challenge.log")" == 2 &&
            "$(<"${TEST_ROOT}/acme.log")" == --issue ]] ||
            fail '恢复首次失败没有再次恢复或仍提交了证书'
        grep -Fq '挑战服务恢复失败' "${TEST_ROOT}/control.log" || fail '恢复失败没有明确错误'
        ;;
    *)
        [[ "$(grep -c "^stop ${RUNNING_ID}$" "${TEST_ROOT}/challenge.log")" == 1 &&
            "$(grep -c "^start ${RUNNING_ID}$" "${TEST_ROOT}/challenge.log")" == 1 ]] ||
            fail '挑战失败或中断未恢复本轮暂停服务'
        ;;
    esac
done

standaloneState standalone-originally-stopped
jq '.[0].State.Running=false' "${TEST_ROOT}/containers.json" >"${TEST_ROOT}/containers.next"
mv -- "${TEST_ROOT}/containers.next" "${TEST_ROOT}/containers.json"
cp -- "${TEST_ROOT}/containers.json" "${TEST_ROOT}/containers.before"
rm -- "${PADM_DOCKER_INSTALL_DIR}/data/acme/${DOMAIN}/${DOMAIN}.conf"
runControl 0 acme issue --domain "${DOMAIN}" --email admin@example.com --standalone
cmp -s "${CERT_FILE}" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt" ||
    fail '原停部署的 HTTP 申请没有提交材料'
[[ "$(<"${TEST_ROOT}/challenge.log")" == "rm -f ${CHALLENGE_ID}" && ! -s "${TEST_ROOT}/compose.log" ]] ||
    fail '成功挑战启动或重载了原本已停止的消费者'
[[ -f "${PADM_DOCKER_INSTALL_DIR}/data/acme/${DOMAIN}_ecc/${DOMAIN}.conf" ]] &&
    grep -Eq '^--issue .* --keylength ec-256( |$)' "${TEST_ROOT}/acme.args" &&
    grep -Eq '^--install-cert .* --ecc( |$)' "${TEST_ROOT}/acme.args" ||
    fail '新域名没有保存 ECC 账户或申请/导出密钥参数不一致'
assertChallengeRestored

standaloneState standalone-renew-skip
before=$(materials)
MODE=renew-skip
runControl 0 acme renew --domain "${DOMAIN}" --email admin@example.com --standalone
[[ "$(materials)" == "${before}" && "$(<"${TEST_ROOT}/acme.log")" == probe &&
    ! -s "${TEST_ROOT}/challenge.log" && ! -s "${TEST_ROOT}/compose.log" && ! -s "${TEST_ROOT}/ops.log" ]] ||
    fail '未到期 HTTP 续期修改材料、暂停或重载了服务'
grep -Fq '证书未到续期时间' "${TEST_ROOT}/control.log" || fail '工具 skip=2 未保持 CLI 跳过语义'
assertChallengeRestored

newState standalone-cli-validation
for ARGS in '--standalone --dns dns_test' '--dns dns_test --standalone' \
    "--standalone --credentials ${CREDENTIALS}"; do
    read -r -a OPTIONS <<<"${ARGS}"
    runControl 2 acme issue --domain "${DOMAIN}" --email admin@example.com "${OPTIONS[@]}"
done
[[ ! -s "${TEST_ROOT}/acme.log" && ! -s "${TEST_ROOT}/challenge.log" ]] ||
    fail '互斥验证方式仍执行了 ACME'

# webroot 使用真实归属和目录校验，ACME 工具只模拟候选账户及标准 key authorization。
for ACTION in issue renew; do
    webrootState "webroot-${ACTION}"
    runControl 0 acme "${ACTION}" --domain "${DOMAIN}" --email admin@example.com --webroot
    cmp -s "${CERT_FILE}" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt" ||
        fail 'webroot 没有提交新证书'
    grep -Fq "Le_Webroot='/var/lib/padm/acme-webroot'" \
        "${PADM_DOCKER_INSTALL_DIR}/data/acme/${DOMAIN}/${DOMAIN}.conf" ||
        fail 'webroot 账户保存了宿主或本轮路径'
    [[ "${ACTION}" != renew || "$(head -n 2 "${TEST_ROOT}/acme.log")" == $'probe\n--renew' ]] ||
        fail 'webroot 续期未先判断到期'
    assertWebrootRestored
    assertPermissions
done
for ACTION in issue renew; do
    webrootState "webroot-ecc-${ACTION}" 27
    if [[ "${ACTION}" == issue ]]; then
        rm -- "${PADM_DOCKER_INSTALL_DIR}/data/acme/${DOMAIN}/${DOMAIN}.conf"
    else
        mv -- "${PADM_DOCKER_INSTALL_DIR}/data/acme/${DOMAIN}" \
            "${PADM_DOCKER_INSTALL_DIR}/data/acme/${DOMAIN}_ecc"
    fi
    runControl 0 acme "${ACTION}" --domain "${DOMAIN}" --email admin@example.com --webroot
    [[ -f "${PADM_DOCKER_INSTALL_DIR}/data/acme/${DOMAIN}_ecc/${DOMAIN}.conf" ]] &&
        grep -Eq '^--install-cert .* --ecc( |$)' "${TEST_ROOT}/acme.args" ||
        fail 'webroot 新/ECC 账户申请、续期与导出不一致'
    grep -q '^up -d --force-recreate --no-deps --wait --wait-timeout 1 xray$' "${TEST_ROOT}/compose.log" ||
        fail 'webroot fallback TLS 消费者没有定向更新'
    ! grep -Eq '^up .* nginx$' "${TEST_ROOT}/compose.log" ||
        fail '只服务 webroot 的 Nginx 被当作 fallback TLS 消费者重建'
    assertWebrootRestored
    assertPermissions
done
webrootState webroot-renew-skip
before=$(materials)
MODE=renew-skip
runControl 0 acme renew --domain "${DOMAIN}" --email admin@example.com --webroot
[[ "$(materials)" == "${before}" && "$(<"${TEST_ROOT}/acme.log")" == probe &&
    ! -s "${TEST_ROOT}/compose.log" && ! -s "${TEST_ROOT}/ops.log" ]] ||
    fail 'webroot skip=2 改了账户、证书或服务'
assertWebrootRestored

for MODE_CASE in issue-fail renew-fail export-fail nginx-test-fail reload-fail health-fail int-issue term-issue; do
    webrootState "webroot-${MODE_CASE}"
    before=$(materials)
    MODE=${MODE_CASE}
    ACTION=issue
    [[ "${MODE}" != renew-fail ]] || ACTION=renew
    EXPECTED=15
    [[ "${MODE}" != int-issue ]] || EXPECTED=130
    [[ "${MODE}" != term-issue ]] || EXPECTED=143
    runControl "${EXPECTED}" acme "${ACTION}" --domain "${DOMAIN}" --email admin@example.com --webroot
    [[ "$(materials)" == "${before}" ]] || fail "${MODE}: webroot 失败未保留账户和材料"
    assertWebrootRestored
done

# 准备阶段的信号须在归属初始化后重放，不能留下 root 所有的本轮挑战目录。
for boundary in mkdir-int chmod-term; do
    webrootState "webroot-prepare-${boundary}"
    before=$(materials)
    : >"${TEST_ROOT}/webroot-signal.log"
    EXPECTED=130
    [[ "${boundary}" != chmod-term ]] || EXPECTED=143
    (
        injected=0
        mkdir() {
            command mkdir "$@" || return $?
            if [[ "${boundary}" == mkdir-int && "${injected}" == 0 &&
                "$#" == 2 && "$1" == -- &&
                "$2" == "${PADM_DOCKER_INSTALL_DIR}/data/acme-webroot/active" ]]; then
                injected=1
                printf 'mkdir:INT\n' >>"${TEST_ROOT}/webroot-signal.log"
                kill -INT "${BASHPID}"
            fi
        }
        chmod() {
            command chmod "$@" || return $?
            if [[ "${boundary}" == chmod-term && "${injected}" == 0 &&
                "$#" == 2 && "$1" == 0750 &&
                "$2" == "${PADM_DOCKER_INSTALL_DIR}/data/acme-webroot/active" ]]; then
                injected=1
                printf 'chmod:TERM\n' >>"${TEST_ROOT}/webroot-signal.log"
                kill -TERM "${BASHPID}"
            fi
        }
        runControl "${EXPECTED}" acme issue --domain "${DOMAIN}" --email admin@example.com --webroot
    )
    [[ "$(wc -l <"${TEST_ROOT}/webroot-signal.log")" == 1 &&
        "$(materials)" == "${before}" && ! -s "${TEST_ROOT}/acme.log" &&
        ! -s "${TEST_ROOT}/compose.log" ]] ||
        fail "${boundary}: webroot 准备信号未注入一次或仍执行 ACME、修改材料和服务"
    assertClean
    assertWebrootRestored
done

for boundary in external-80 stopped-nginx ownership image port mount named-volume tmpfs compose nginx domain; do
    webrootState "webroot-reject-${boundary}"
    case "${boundary}" in
    external-80) MODE=external-80 ;;
    stopped-nginx)
        jq '.[0].State.Running=false' "${TEST_ROOT}/containers.json" >"${TEST_ROOT}/containers.next"
        ;;
    ownership)
        jq '.[0].Config.Labels["com.docker.compose.project.working_dir"]="/outside/deployment"' \
            "${TEST_ROOT}/containers.json" >"${TEST_ROOT}/containers.next"
        ;;
    image)
        jq '.[0].Config.Image="unrelated:fixture"' "${TEST_ROOT}/containers.json" >"${TEST_ROOT}/containers.next"
        ;;
    port)
        jq '.[0].HostConfig.PortBindings["8088/tcp"][1].HostPort="8081"' \
            "${TEST_ROOT}/containers.json" >"${TEST_ROOT}/containers.next"
        ;;
    mount)
        jq '.[0].Mounts |= map(if .Destination == "/srv/padm-acme" then .RW=true else . end)' \
            "${TEST_ROOT}/containers.json" >"${TEST_ROOT}/containers.next"
        ;;
    named-volume)
        jq '.[0].Mounts += [{Type:"volume",Name:"foreign-challenge",Source:"/var/lib/docker/volumes/foreign/_data",
          Destination:"/srv/padm-acme/active",RW:true}]' \
            "${TEST_ROOT}/containers.json" >"${TEST_ROOT}/containers.next"
        ;;
    tmpfs)
        jq '.[0].HostConfig.Tmpfs["/srv/padm-acme/active"]="rw"' \
            "${TEST_ROOT}/containers.json" >"${TEST_ROOT}/containers.next"
        ;;
    compose)
        jq '(.services.nginx.volumes[] | select(.target == "/srv/padm-acme") | .read_only)=false' \
            "${PADM_DOCKER_INSTALL_DIR}/compose.json" >"${TEST_ROOT}/webroot-unsafe-compose.json"
        cp -- "${TEST_ROOT}/webroot-unsafe-compose.json" "${PADM_DOCKER_INSTALL_DIR}/compose.json"
        ;;
    nginx) printf '\n# fixture drift\n' >>"${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf" ;;
    domain)
        jq '.tls.domain="other.example.com"' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
            >"${TEST_ROOT}/webroot-unsafe-spec.json"
        cp -- "${TEST_ROOT}/webroot-unsafe-spec.json" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
        ;;
    esac
    if [[ -f "${TEST_ROOT}/containers.next" ]]; then
        mv -- "${TEST_ROOT}/containers.next" "${TEST_ROOT}/containers.json"
        cp -- "${TEST_ROOT}/containers.json" "${TEST_ROOT}/containers.before"
    fi
    before=$(materials)
    runControl 15 acme issue --domain "${DOMAIN}" --email admin@example.com --webroot
    [[ "$(materials)" == "${before}" && ! -s "${TEST_ROOT}/acme.log" &&
        ! -s "${TEST_ROOT}/compose.log" ]] || fail "${boundary}: webroot 拒绝前运行了工具或修改材料"
    assertWebrootRestored
done

# 首次创建必须先拒绝危险父目录，不能留下再校验失败的半成品。
for boundary in data-link writable-parent wrong-owner; do
    newState "webroot-ensure-${boundary}"
    data=${PADM_DOCKER_INSTALL_DIR}/data
    webroot=${data}/acme-webroot
    case "${boundary}" in
    data-link)
        mv -- "${data}" "${data}.real"
        ln -s data.real "${data}"
        ;;
    writable-parent) chmod 0777 "${data}" ;;
    wrong-owner) chown 10002:10002 "${data}" ;;
    esac
    parentBefore=$(stat -c '%a %u %g' "${data}")
    reject dockerAcmeWebrootEnsure "${PADM_DOCKER_INSTALL_DIR}"
    [[ ! -e "${webroot}" && ! -L "${webroot}" &&
        "$(stat -c '%a %u %g' "${data}")" == "${parentBefore}" ]] ||
        fail "${boundary}: webroot 首次创建前未拒绝或修改了危险父目录"
    case "${boundary}" in
    data-link)
        rm -- "${data}"
        mv -- "${data}.real" "${data}"
        ;;
    writable-parent) chmod 0700 "${data}" ;;
    wrong-owner) chown 0:0 "${data}" ;;
    esac
    dockerAcmeWebrootEnsure "${PADM_DOCKER_INSTALL_DIR}" ||
        fail "${boundary}: 修复父目录后仍不能创建 webroot"
    [[ "$(stat -c '%a %u %g' "${webroot}")" == '750 10001 10001' &&
        -z "$(find "${webroot}" -mindepth 1 -print -quit)" ]] ||
        fail 'webroot 首次创建权限、属主或空目录合同不正确'
done

# 首次根目录初始化期间收到信号时，必须先完成最小权限，再重放信号。
for boundary in mkdir-int chmod-term; do
    newState "webroot-ensure-${boundary}-signal"
    data=${PADM_DOCKER_INSTALL_DIR}/data
    webroot=${data}/acme-webroot
    expected=130
    [[ "${boundary}" != chmod-term ]] || expected=143
    actual=0
    (
        trap 'exit 130' INT
        trap 'exit 143' TERM
        injected=0
        mkdir() {
            command mkdir "$@" || return $?
            if [[ "${boundary}" == mkdir-int && "${injected}" == 0 &&
                "$#" == 2 && "$1" == -- && "$2" == "${webroot}" ]]; then
                injected=1
                kill -INT "${BASHPID}"
            fi
        }
        chmod() {
            command chmod "$@" || return $?
            if [[ "${boundary}" == chmod-term && "${injected}" == 0 &&
                "$#" == 2 && "$1" == 0750 && "$2" == "${webroot}" ]]; then
                injected=1
                kill -TERM "${BASHPID}"
            fi
        }
        dockerAcmeWebrootEnsure "${PADM_DOCKER_INSTALL_DIR}"
    ) >"${TEST_ROOT}/ensure-signal.log" 2>&1 || actual=$?
    [[ "${actual}" == "${expected}" ]] ||
        fail "${boundary}: Ensure 信号退出码预期 ${expected}，实际 ${actual}"
    [[ -d "${webroot}" && ! -L "${webroot}" &&
        "$(stat -c '%a %u %g' "${webroot}")" == '750 10001 10001' &&
        -z "$(find "${webroot}" -mindepth 1 -print -quit)" ]] ||
        fail "${boundary}: Ensure 中断后未留下可接管的空私有根"
    inode=$(stat -c '%d:%i' "${webroot}")
    dockerAcmeWebrootEnsure "${PADM_DOCKER_INSTALL_DIR}" ||
        fail "${boundary}: Ensure 中断后不能被后续调用接管"
    [[ "$(stat -c '%d:%i' "${webroot}")" == "${inode}" ]] ||
        fail "${boundary}: 后续 Ensure 替换了已初始化根目录"
done

for boundary in active-existing root-link parent-link fifo hardlink writable-parent wrong-owner; do
    webrootState "webroot-tree-${boundary}"
    webroot=${PADM_DOCKER_INSTALL_DIR}/data/acme-webroot
    case "${boundary}" in
    active-existing)
        mkdir -p "${webroot}/active/.well-known/acme-challenge"
        printf 'Existing_token.thumbprint\n' >"${webroot}/active/.well-known/acme-challenge/Existing_token"
        chown -R 10001:10001 "${webroot}/active"
        find "${webroot}/active" -type d -exec chmod 0750 {} +
        chmod 0640 "${webroot}/active/.well-known/acme-challenge/Existing_token"
        ;;
    root-link)
        mv -- "${webroot}" "${webroot}.real"
        ln -s acme-webroot.real "${webroot}"
        ;;
    parent-link)
        mv -- "${PADM_DOCKER_INSTALL_DIR}/data" "${PADM_DOCKER_INSTALL_DIR}/data.real"
        ln -s data.real "${PADM_DOCKER_INSTALL_DIR}/data"
        ;;
    fifo) mkfifo "${webroot}/unsafe" ;;
    hardlink)
        printf 'Keep_token.thumbprint\n' >"${TEST_ROOT}/outside-token"
        ln "${TEST_ROOT}/outside-token" "${webroot}/unsafe"
        ;;
    writable-parent) chmod 0777 "${PADM_DOCKER_INSTALL_DIR}/data" ;;
    wrong-owner) chown 10002:10002 "${webroot}" ;;
    esac
    treeBefore=$(find "${webroot}/" -printf '%P %y %m %U %G %i\n' | sort)
    before=$(materials)
    runControl 15 acme issue --domain "${DOMAIN}" --email admin@example.com --webroot
    [[ "$(materials)" == "${before}" && ! -s "${TEST_ROOT}/acme.log" &&
        ! -s "${TEST_ROOT}/compose.log" &&
        "$(find "${webroot}/" -printf '%P %y %m %U %G %i\n' | sort)" == "${treeBefore}" ]] ||
        fail "${boundary}: webroot 拒绝改变了既有挑战树或材料"
    [[ ! -s "${TEST_ROOT}/challenge.log" ]] || fail 'webroot 目录拒绝仍停启服务'
    if [[ "${boundary}" == active-existing ]]; then
        grep -qxF 'Existing_token.thumbprint' "${webroot}/active/.well-known/acme-challenge/Existing_token" ||
            fail '准备拒绝删除了已有合法挑战 token'
    elif [[ "${boundary}" == hardlink ]]; then
        grep -qxF 'Keep_token.thumbprint' "${TEST_ROOT}/outside-token" ||
            fail '准备拒绝删除或改写了外部硬链接文件'
    fi
done

webrootState webroot-token-validation
webroot=${PADM_DOCKER_INSTALL_DIR}/data/acme-webroot
challenge=${webroot}/active/.well-known/acme-challenge
mkdir -p "${challenge}"
chown -R 10001:10001 "${webroot}/active"
find "${webroot}/active" -type d -exec chmod 0750 {} +
for boundary in symlink hardlink fifo invalid-name private-key empty bad-character multiline double-newline nul oversized writable wrong-owner; do
    tokenFile=${challenge}/Padm_token-123
    printf 'Padm_token-123.thumbprint_456\n' >"${tokenFile}"
    chown 10001:10001 "${tokenFile}"
    chmod 0640 "${tokenFile}"
    dockerAcmeWebrootTreeValidate "${PADM_DOCKER_INSTALL_DIR}" "${webroot}" ||
        fail 'webroot 目录拒绝合法 key authorization'
    case "${boundary}" in
    symlink)
        rm -- "${tokenFile}"
        ln -s "${CERT_FILE}" "${tokenFile}"
        ;;
    hardlink)
        rm -- "${tokenFile}"
        printf 'Padm_token-123.thumbprint_456\n' >"${TEST_ROOT}/outside-token"
        chown 10001:10001 "${TEST_ROOT}/outside-token"
        chmod 0640 "${TEST_ROOT}/outside-token"
        ln "${TEST_ROOT}/outside-token" "${tokenFile}"
        ;;
    fifo)
        rm -- "${tokenFile}"
        mkfifo "${tokenFile}"
        ;;
    invalid-name)
        mv -- "${tokenFile}" "${challenge}/.hidden"
        tokenFile=${challenge}/.hidden
        ;;
    private-key) printf '%s\n' '-----BEGIN PRIVATE KEY-----' fixture >"${tokenFile}" ;;
    empty) : >"${tokenFile}" ;;
    bad-character) printf 'Padm_token-123.thumbprint/456\n' >"${tokenFile}" ;;
    multiline) printf 'Padm_token-123.thumbprint_456\nSecond_token.thumbprint\n' >"${tokenFile}" ;;
    double-newline) printf 'Padm_token-123.thumbprint_456\n\n' >"${tokenFile}" ;;
    nul) printf 'Padm_token-123.\0thumbprint_456\n' >"${tokenFile}" ;;
    oversized) printf '%s.thumbprint\n' "$(printf 'a%.0s' {1..512})" >"${tokenFile}" ;;
    writable) chmod 0660 "${tokenFile}" ;;
    wrong-owner) chown 10002:10002 "${tokenFile}" ;;
    esac
    reject dockerAcmeWebrootTreeValidate "${PADM_DOCKER_INSTALL_DIR}" "${webroot}"
    [[ -e "${tokenFile}" || -L "${tokenFile}" ]] || fail 'webroot 目录校验删除了已有文件'
    rm -- "${tokenFile}"
done
printf 'Padm_token-123.thumbprint_456' >"${tokenFile}"
chown 10001:10001 "${tokenFile}"
chmod 0640 "${tokenFile}"
dockerAcmeWebrootTreeValidate "${PADM_DOCKER_INSTALL_DIR}" "${webroot}" ||
    fail '无换行 key authorization 被错误拒绝'
rm -- "${tokenFile}"

newState webroot-cli-validation
for ARGS in '--webroot /outside/root' '--webroot --standalone' '--standalone --webroot' \
    '--webroot --dns dns_test' '--dns dns_test --webroot' \
    "--webroot --credentials ${CREDENTIALS}" '--webroot --webroot'; do
    read -r -a OPTIONS <<<"${ARGS}"
    runControl 2 acme issue --domain "${DOMAIN}" --email admin@example.com "${OPTIONS[@]}"
done
runControl 15 acme issue --domain "${DOMAIN}" --email admin@example.com --webroot
[[ ! -s "${TEST_ROOT}/acme.log" && ! -s "${TEST_ROOT}/challenge.log" ]] ||
    fail 'webroot 参数无效或未开启仍执行 ACME'

# 单次恢复真实运行器，检查空凭据和双栈映射，不重复完整事务矩阵。
newState standalone-runner
dockerCreateTlsCandidate
mkdir -- "${DOCKER_TLS_CANDIDATE}/acme"
ACME_RUN_TEST_IMPLEMENTATION=$(declare -f dockerAcmeRun)
eval "${ACME_RUN_IMPLEMENTATION}"
RAW_ACME_RUN=1
: >"${TEST_ROOT}/acme-docker.args"
dockerAcmeRun "${OPS_IMAGE}" '' "${DOCKER_TLS_CANDIDATE}/acme" "${DOCKER_TLS_CANDIDATE}" --renew -d "${DOMAIN}"
! grep -Fq -- '--publish' "${TEST_ROOT}/acme-docker.args" || fail '未准备挑战时运行器发布了宿主端口'
: >"${TEST_ROOT}/acme-docker.args"
DOCKER_ACME_PORT_PUBLISH=1
dockerAcmeRun "${OPS_IMAGE}" '' "${DOCKER_TLS_CANDIDATE}/acme" "${DOCKER_TLS_CANDIDATE}" \
    --issue --standalone --httpport 8080 -d "${DOMAIN}"
grep -Fq -- '--publish 0.0.0.0:80:8080/tcp --publish [::]:80:8080/tcp' "${TEST_ROOT}/acme-docker.args" ||
    fail 'HTTP 运行器未将双栈宿主 80 映射到容器 8080'
grep -Fq -- '--name padm-acme-' "${TEST_ROOT}/acme-docker.args" || fail '挑战容器未登记唯一名称'
grep -Fq -- '--label io.padm.challenge=padm-acme-' "${TEST_ROOT}/acme-docker.args" ||
    fail '挑战容器未登记本轮清理 label'
RAW_ACME_RUN=0
DOCKER_ACME_CONTAINER=
DOCKER_ACME_PORT_PUBLISH=0
eval "${ACME_RUN_TEST_IMPLEMENTATION}"
dockerCleanupTlsCandidate
assertClean

# 真实运行器仅给 ops 本轮 active 读写挂载，Nginx 挂载根与宿主端口保持不变。
webrootState webroot-runner
dockerAcquireDeploymentLock
dockerCreateTlsCandidate
mkdir -- "${DOCKER_TLS_CANDIDATE}/acme"
chown 10001:10001 "${DOCKER_TLS_CANDIDATE}/acme"
dockerAcmeWebrootPrepare "${DOMAIN}" "${DOCKER_TLS_CANDIDATE}"
eval "${ACME_RUN_IMPLEMENTATION}"
RAW_ACME_RUN=1
: >"${TEST_ROOT}/acme-docker.args"
dockerAcmeRun "${OPS_IMAGE}" '' "${DOCKER_TLS_CANDIDATE}/acme" "${DOCKER_TLS_CANDIDATE}" \
    --issue --webroot /var/lib/padm/acme-webroot -d "${DOMAIN}"
grep -Fq -- "--volume ${PADM_DOCKER_INSTALL_DIR}/data/acme-webroot/active:/var/lib/padm/acme-webroot" \
    "${TEST_ROOT}/acme-docker.args" || fail 'webroot 运行器未读写挂载专属 active'
! grep -Fq -- '/var/lib/padm/acme-webroot:ro' "${TEST_ROOT}/acme-docker.args" ||
    fail 'webroot ops 挂载不能写挑战 token'
! grep -Eq -- '--publish|--network host|--cap-add' "${TEST_ROOT}/acme-docker.args" ||
    fail 'webroot 运行器发布了宿主端口或扩大网络权限'
grep -Fq -- '--label io.padm.challenge=padm-acme-' "${TEST_ROOT}/acme-docker.args" ||
    fail 'webroot 工具容器未登记本轮清理 label'
RAW_ACME_RUN=0
DOCKER_ACME_CONTAINER=
eval "${ACME_RUN_TEST_IMPLEMENTATION}"
dockerAcmeChallengeRestore
dockerCleanupTlsCandidate
dockerReleaseDeploymentLock
assertClean
assertWebrootRestored

newState import-success
accountBefore=$(find "${PADM_DOCKER_INSTALL_DIR}/data/acme" -type f -print0 | sort -z | xargs -0 sha256sum)
runControl 0 tls install --domain "${DOMAIN}" --cert "${CERT_FILE}" --key "${KEY_FILE}"
[[ "$(find "${PADM_DOCKER_INSTALL_DIR}/data/acme" -type f -print0 | sort -z | xargs -0 sha256sum)" == "${accountBefore}" &&
    ! -s "${TEST_ROOT}/acme.log" ]] || fail '证书导入修改了 ACME 账户'
assertPermissions
before=$(materials)
MODE=match-fail
runControl 15 tls install --domain "${DOMAIN}" --cert "${CERT_FILE}" --key "${KEY_FILE}"
[[ "$(materials)" == "${before}" ]] || fail '无效导入修改了部署'
MODE=ok
runControl 15 tls validate --domain wrong.example.com
[[ "$(materials)" == "${before}" ]] || fail '证书域名校验失败修改了部署'
MODE=match-fail
runControl 15 tls validate --domain "${DOMAIN}"
[[ "$(materials)" == "${before}" ]] || fail '证书校验失败修改了部署'
MODE=ok

# 已配置部署不允许改写镜像文件或显式换用其它 ops 镜像。
newState image-validation
before=$(materials)
OTHER_IMAGE="ghcr.io/example/padm-ops:3.2.0@sha256:$(printf 'b%.0s' {1..64})"
printf 'PADM_OPS_IMAGE=%s\n' "${OTHER_IMAGE}" >"${PADM_DOCKER_INSTALL_DIR}/images.env"
runControl 15 tls validate --domain "${DOMAIN}"
printf 'PADM_OPS_IMAGE=%s\nPADM_OPS_IMAGE=%s\n' "${OPS_IMAGE}" "${OPS_IMAGE}" >"${PADM_DOCKER_INSTALL_DIR}/images.env"
runControl 15 tls validate --domain "${DOMAIN}"
printf 'PADM_OPS_IMAGE=%s\n' "${OPS_IMAGE}" >"${PADM_DOCKER_INSTALL_DIR}/images.env"
runControl 15 tls install --domain "${DOMAIN}" --cert "${CERT_FILE}" --key "${KEY_FILE}" --ops-image "${OTHER_IMAGE}"
runControl 15 acme issue --domain "${DOMAIN}" --email admin@example.com --dns dns_test \
    --credentials "${CREDENTIALS}" --ops-image "${OTHER_IMAGE}"
[[ "$(materials)" == "${before}" && ! -s "${TEST_ROOT}/ops.log" && ! -s "${TEST_ROOT}/acme.log" ]] ||
    fail '镜像门禁失败前运行了工具或修改了部署'
rm -- "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
runControl 0 tls install --domain "${DOMAIN}" --cert "${CERT_FILE}" --key "${KEY_FILE}" --ops-image "${OPS_IMAGE}"
newState spec-validation
before=$(materials)
jq '.images.ops |= sub("sha256:a"; "sha256:b")' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${TEST_ROOT}/invalid-spec.json"
cp -- "${TEST_ROOT}/invalid-spec.json" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
runControl 15 tls validate --domain "${DOMAIN}"
[[ "$(materials)" == "${before}" && ! -s "${TEST_ROOT}/ops.log" ]] || fail '规格不一致时执行了证书工具'
newState legacy-no-spec
rm -- "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
runControl 0 tls install --domain "${DOMAIN}" --cert "${CERT_FILE}" --key "${KEY_FILE}"
[[ "$(head -n 2 "${TEST_ROOT}/compose.log")" == $'exec -T nginx nginx -e /dev/stderr -t\nexec -T nginx nginx -e /dev/stderr -s reload' ]] ||
    fail '旧部署缺少规格文件时未重载实际 Nginx 消费者'

# 校验复用真实 openssl，覆盖错域名、错私钥与损坏证书，不能只相信模拟退出码。
newState invalid-materials
dockerCreateTlsCandidate
candidate=${DOCKER_TLS_CANDIDATE}
cp -- "${CERT_FILE}" "${candidate}/${DOMAIN}.crt"
cp -- "${KEY_FILE}" "${candidate}/${DOMAIN}.key"
reject dockerTlsValidateCandidate "${OPS_IMAGE}" "${candidate}" wrong.example.com
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "${candidate}/${DOMAIN}.key" >/dev/null 2>&1
reject dockerTlsValidateCandidate "${OPS_IMAGE}" "${candidate}" "${DOMAIN}"
printf 'invalid-certificate\n' >"${candidate}/${DOMAIN}.crt"
reject dockerTlsValidateCandidate "${OPS_IMAGE}" "${candidate}" "${DOMAIN}"
dockerCleanupTlsCandidate
assertClean

# 新域名与不存在的 ACME 账户同样需要在重载失败时恢复缺失状态。
newState absent-state
rm -f -- "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.key"
rm -rf -- "${PADM_DOCKER_INSTALL_DIR}/data/acme"
MODE=health-fail
runControl 15 acme issue --domain "${DOMAIN}" --email admin@example.com --dns dns_test --credentials "${CREDENTIALS}"
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/data/acme" &&
    ! -e "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt" &&
    ! -e "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.key" ]] || fail '失败事务没有恢复缺失状态'

# 备份损坏与路径跳转必须在任何恢复写入前拒绝。
newState backup-validation
dockerBackupTlsFiles "${DOMAIN}"
BACKUP=${DOCKER_TLS_BACKUP}
DOCKER_TLS_SWITCHED=1
cp -- "${CERT_FILE}" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt"
before=$(materials)
printf 'unexpected\n' >>"${BACKUP}/present"
reject dockerRestoreTlsFiles
[[ "$(materials)" == "${before}" ]] || fail '坏备份导致部分恢复'
printf 'crt\nkey\n' >"${BACKUP}/present"
rm -- "${BACKUP}/${DOMAIN}.key"
reject dockerRestoreTlsFiles
[[ "$(materials)" == "${before}" ]] || fail '缺失私钥备份导致部分恢复'
cp -- "${KEY_FILE}" "${BACKUP}/${DOMAIN}.key"
mv "${BACKUP}/${DOMAIN}.crt" "${BACKUP}/${DOMAIN}.crt.real"
ln -s "${DOMAIN}.crt.real" "${BACKUP}/${DOMAIN}.crt"
reject dockerRestoreTlsFiles
[[ "$(materials)" == "${before}" ]] || fail '备份符号链接导致恢复写入'
DOCKER_TLS_SWITCHED=0

newState account-backup-validation
dockerCreateTlsCandidate
mkdir "${DOCKER_TLS_CANDIDATE}/acme"
cp -a -- "${PADM_DOCKER_INSTALL_DIR}/data/acme/." "${DOCKER_TLS_CANDIDATE}/acme/"
dockerBackupTlsFiles "${DOMAIN}" "${DOCKER_TLS_CANDIDATE}"
BACKUP=${DOCKER_TLS_BACKUP}
DOCKER_TLS_SWITCHED=1
cp -- "${CERT_FILE}" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt"
before=$(materials)
rm -rf -- "${BACKUP}/acme"
reject dockerRestoreTlsFiles
[[ "$(materials)" == "${before}" ]] || fail '缺失 ACME 备份导致部分恢复'
printf 'invalid\n' >"${BACKUP}/acme.changed"
reject dockerRestoreTlsFiles
[[ "$(materials)" == "${before}" ]] || fail '无效 ACME 状态标记导致部分恢复'
DOCKER_TLS_SWITCHED=0
dockerCleanupTlsCandidate
assertClean

newState symlink-validation
dockerCreateTlsCandidate
cp -- "${CERT_FILE}" "${DOCKER_TLS_CANDIDATE}/${DOMAIN}.crt"
cp -- "${KEY_FILE}" "${DOCKER_TLS_CANDIDATE}/${DOMAIN}.key"
printf 'outside-key\n' >"${TEST_ROOT}/outside-key"
tempKey="${PADM_DOCKER_INSTALL_DIR}/secrets/tls/.${DOMAIN}.key.${BASHPID}"
ln -s "${TEST_ROOT}/outside-key" "${tempKey}"
before=$(materials)
reject dockerCommitTlsCandidate "${DOCKER_TLS_CANDIDATE}" "${DOMAIN}"
[[ "$(materials)" == "${before}" && "$(<"${TEST_ROOT}/outside-key")" == outside-key &&
    "${DOCKER_TLS_SWITCHED}" == 0 && -L "${tempKey}" ]] || fail '私钥临时链接导致部分提交或外部写入'
rm -- "${tempKey}"
dockerCleanupTlsCandidate
assertClean
mv "${PADM_DOCKER_INSTALL_DIR}/data/acme" "${PADM_DOCKER_INSTALL_DIR}/data/acme.real"
ln -s acme.real "${PADM_DOCKER_INSTALL_DIR}/data/acme"
runControl 15 acme issue --domain "${DOMAIN}" --email admin@example.com --dns dns_test --credentials "${CREDENTIALS}"
[[ ! -s "${TEST_ROOT}/acme.log" ]] || fail 'ACME 接受了账户符号链接'
rm -- "${PADM_DOCKER_INSTALL_DIR}/data/acme"
mv "${PADM_DOCKER_INSTALL_DIR}/data/acme.real" "${PADM_DOCKER_INSTALL_DIR}/data/acme"
mv "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.key" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.key.real"
ln -s "${DOMAIN}.key.real" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.key"
runControl 15 tls validate --domain "${DOMAIN}"
runControl 15 tls install --domain "${DOMAIN}" --cert "${CERT_FILE}" --key "${KEY_FILE}"
[[ -L "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.key" ]] || fail '覆盖了私钥符号链接'

# 解析只认入站普通 TLS，忽略客户端出站、Reality 与 Xray verify 证书。
PARSER=${TEST_ROOT}/core-parser.json
jq -n '{inbounds:[{streamSettings:{security:"tls",tlsSettings:{certificates:[
  {certificateFile:"/etc/padm/secrets/tls/example.com.crt",keyFile:"/etc/padm/secrets/tls/example.com.key"},
  {certificateFile:"/etc/padm/secrets/tls/other.example.com.crt",keyFile:"/etc/padm/secrets/tls/other.example.com.key"},
  {certificateFile:"/etc/padm/secrets/tls/example.com.crt",keyFile:"/etc/padm/secrets/tls/example.com.key"}]}}}]}' >"${PARSER}"
[[ "$(dockerCoreTlsDomains xray "${PARSER}")" == '["example.com","other.example.com"]' ]] || fail 'Xray TLS 多域解析或去重错误'
cp -- "${PARSER}" "${TEST_ROOT}/valid-xray-parser.json"
for CHANGE in \
    '.inbounds[0].streamSettings.tlsSettings.certificates[0].keyFile = "/etc/padm/secrets/tls/other.example.com.key"' \
    '.inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile = "/tmp/example.com.crt"' \
    '.inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile = "/etc/padm/secrets/tls/../example.com.crt"' \
    'del(.inbounds[0].streamSettings.tlsSettings.certificates[0].keyFile)'; do
    jq "${CHANGE}" "${TEST_ROOT}/valid-xray-parser.json" >"${PARSER}"
    if dockerCoreTlsDomains xray "${PARSER}" >"${TEST_ROOT}/rejected.log" 2>&1; then
        fail "非法 Xray TLS 路径被接受: ${CHANGE}"
    fi
done
jq -n '{inbounds:[
  {streamSettings:{security:"reality",tlsSettings:{certificates:[{certificateFile:"/outside.crt"}]}}},
  {streamSettings:{security:"tls",tlsSettings:{certificates:[{usage:"verify",certificateFile:"/outside.crt"}]}}}],
  outbounds:[{streamSettings:{security:"tls",tlsSettings:{certificates:[{certificateFile:"/outside.crt"}]}}}]}' >"${PARSER}"
[[ "$(dockerCoreTlsDomains xray "${PARSER}")" == '[]' ]] || fail 'Xray 将出站、Reality 或 verify 当成服务端 TLS'
jq -n '{inbounds:[
  {tls:{enabled:true,certificate_path:"/etc/padm/secrets/tls/example.com.crt",key_path:"/etc/padm/secrets/tls/example.com.key"}},
  {tls:{enabled:true,certificate_path:"/etc/padm/secrets/tls/example.com.crt",key_path:"/etc/padm/secrets/tls/example.com.key"}}]}' >"${PARSER}"
[[ "$(dockerCoreTlsDomains sing-box "${PARSER}")" == '["example.com"]' ]] || fail 'sing-box TLS 解析或去重错误'
cp -- "${PARSER}" "${TEST_ROOT}/valid-sing-parser.json"
for CHANGE in \
    '.inbounds[0].tls.key_path = "/etc/padm/secrets/tls/other.example.com.key"' \
    '.inbounds[0].tls.certificate_path = "/tmp/example.com.crt"' \
    '.inbounds[0].tls.certificate_path = "/etc/padm/secrets/tls/../example.com.crt"' \
    'del(.inbounds[0].tls.key_path)'; do
    jq "${CHANGE}" "${TEST_ROOT}/valid-sing-parser.json" >"${PARSER}"
    if dockerCoreTlsDomains sing-box "${PARSER}" >"${TEST_ROOT}/rejected.log" 2>&1; then
        fail "非法 sing-box TLS 路径被接受: ${CHANGE}"
    fi
done
jq -n '{inbounds:[{tls:{enabled:true,reality:{enabled:true},certificate_path:"/outside.crt"}},
  {tls:{enabled:false,certificate_path:"/outside.crt"}}],
  outbounds:[{tls:{enabled:true,certificate_path:"/outside.crt"}}]}' >"${PARSER}"
[[ "$(dockerCoreTlsDomains sing-box "${PARSER}")" == '[]' ]] || fail 'sing-box 将出站、Reality 或关闭 TLS 当成消费者'
printf '{"inbounds":\n' >"${PARSER}"
reject dockerCoreTlsDomains xray "${PARSER}"
reject dockerCoreTlsDomains sing-box "${PARSER}"
reject dockerCoreTlsDomains unknown "${PARSER}"

coreTlsState core-only xray
[[ "$(dockerTlsConsumers "${DOMAIN}")" == '["xray"]' ]] || fail '核心独立消费者识别错误'
[[ "$(dockerTlsConsumers unused.example.com)" == '[]' ]] || fail '未使用域名误选消费者'
(
    dockerAcquireDeploymentLock
    dockerValidateCandidate "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${PADM_DOCKER_INSTALL_DIR}" ||
        fail '核心独立 TLS 候选验证失败'
    if grep -q ' nginx' "${TEST_ROOT}/compose.log"; then fail '核心独立候选验证调用了 Nginx'; fi
    printf 'corrupt-certificate\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt"
    reject dockerValidateCandidate "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${PADM_DOCKER_INSTALL_DIR}"
    if grep -q '^up ' "${TEST_ROOT}/compose.log"; then fail '候选证书验证触发了服务启动'; fi
    cp -- "${TEST_ROOT}/old.crt" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt"
    dockerReleaseDeploymentLock
)
: >"${TEST_ROOT}/compose.log"
: >"${TEST_ROOT}/events.log"
dockerBackupTlsFiles unused.example.com
dockerReloadTlsConsumers "${DOCKER_TLS_BACKUP}"
[[ ! -s "${TEST_ROOT}/compose.log" ]] || fail '无人使用的证书触发了消费者动作'
runCoreCommit 0
grep -q '^snapshot-old$' "${TEST_ROOT}/compose.log" || fail '核心换证前未采样'
grep -q '^up -d --force-recreate --no-deps --wait --wait-timeout 1 xray$' "${TEST_ROOT}/compose.log" ||
    fail '核心换证未定向重建'
if grep -Eq ' nginx( |$)| sing-box( |$)' "${TEST_ROOT}/compose.log"; then fail '核心换证启动了无关消费者'; fi
assertPermissions

coreTlsState both-nginx both true
dockerTlsConsumers "${DOMAIN}" | jq -e 'sort == ["nginx","sing-box","xray"]' >/dev/null ||
    fail '双核与 Nginx 消费者识别错误'
runCoreCommit 0
for CORE in xray sing-box; do
    grep -q "^up -d --force-recreate --no-deps --wait --wait-timeout 1 ${CORE}$" "${TEST_ROOT}/compose.log" ||
        fail "${CORE}: TLS 换证未定向重建"
done
grep -q '^up -d --no-deps --wait --wait-timeout 1 nginx$' "${TEST_ROOT}/compose.log" ||
    fail 'Nginx 换证健康检查扩大到其他服务'
awk '/^run / {if (started) exit 1} /^up / {started=1} END {if (!started) exit 1}' "${TEST_ROOT}/compose.log" ||
    fail '核心配置没有全部先校验再重建'
assertPermissions

for MODE_CASE in core-check-fail snapshot-fail second-core-fail restore-first-fail term-core; do
    coreTlsState "core-${MODE_CASE}" both true
    before=$(materials)
    MODE=${MODE_CASE}
    EXPECTED=failure
    [[ "${MODE}" != term-core ]] || EXPECTED=143
    runCoreCommit "${EXPECTED}"
    [[ "$(materials)" == "${before}" ]] || fail "${MODE}: 核心 TLS 失败没有整体恢复证书和账户"
    if [[ "${MODE}" == snapshot-fail ]]; then
        if grep -Eq '^up |^run ' "${TEST_ROOT}/compose.log"; then fail '采样失败仍校验或重建消费者'; fi
        [[ "$(cat "${TEST_ROOT}/compose.log")" == snapshot-old ]] || fail '采样失败发生在证书切换之后'
    elif [[ "${MODE}" == core-check-fail ]]; then
        if grep -q '^new:up ' "${TEST_ROOT}/events.log"; then fail '候选核心校验失败仍然重建了新证书服务'; fi
        grep -q '^old:up -d --force-recreate --no-deps --wait --wait-timeout 1 xray$' "${TEST_ROOT}/events.log" &&
            grep -q '^old:up -d --force-recreate --no-deps --wait --wait-timeout 1 sing-box$' "${TEST_ROOT}/events.log" ||
            fail '恢复校验失败后没有尝试恢复所有核心'
    else
        [[ "$(grep -c '^up -d --force-recreate --no-deps --wait --wait-timeout 1 xray$' "${TEST_ROOT}/compose.log")" -ge 2 &&
            "$(grep -c '^up -d --force-recreate --no-deps --wait --wait-timeout 1 sing-box$' "${TEST_ROOT}/compose.log")" -ge 2 ]] ||
            fail '第二核失败或恢复第一核失败后没有尝试恢复全部核心'
    fi
done

coreTlsState bad-consumers both true
dockerBackupTlsFiles "${DOMAIN}"
BACKUP=${DOCKER_TLS_BACKUP}
DOCKER_TLS_SWITCHED=1
cp -- "${CERT_FILE}" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt"
before=$(materials)
for CONSUMERS in '["ops"]' '["xray","xray"]' '{}' '["xray",false]'; do
    printf '%s\n' "${CONSUMERS}" >"${BACKUP}/consumers"
    reject dockerRestoreTlsFiles
    [[ "$(materials)" == "${before}" ]] || fail '坏消费者元数据导致部分恢复'
done
rm -- "${BACKUP}/consumers"
reject dockerRestoreTlsFiles
[[ "$(materials)" == "${before}" ]] || fail '消费者元数据缺失导致部分恢复'
DOCKER_TLS_SWITCHED=0

coreTlsState unsafe-consumers both true
cp -- "${PADM_DOCKER_INSTALL_DIR}/compose.json" "${TEST_ROOT}/valid-consumer-compose.json"
for CHANGE in \
    '.services.xray.image = "untrusted:latest"' \
    '.services.xray.profiles = []' \
    '(.services.xray.volumes[] | select(.target == "/etc/padm/secrets/tls") | .read_only) = false' \
    '.services.xray.volumes |= map(select(.target != "/etc/padm/secrets/tls"))' \
    '(.services.xray.volumes[] | select(.target == "/etc/padm/xray") | .source) = "/outside/config"' \
    '.services.xray.volumes += [{type:"bind",source:"/outside/config.json",target:"/etc/padm/xray/config.json",read_only:true}]' \
    '.services.xray.volumes += [{type:"bind",source:"/outside/key",target:"/etc/padm/secrets/tls/example.com.key",read_only:true}]' \
    '(.services.nginx.volumes[] | select(.target == "/etc/nginx/http.d") | .source) = "/outside/nginx"' \
    '.services.nginx.volumes += [{type:"bind",source:"/outside/nginx.conf",target:"/etc/nginx/http.d/default.conf",read_only:true}]' \
    '.services.nginx.volumes += [{type:"bind",source:"/outside/key",target:"/etc/padm/secrets/tls/example.com.key",read_only:true}]'; do
    jq "${CHANGE}" "${TEST_ROOT}/valid-consumer-compose.json" >"${PADM_DOCKER_INSTALL_DIR}/compose.json"
    if dockerTlsConsumers "${DOMAIN}" >"${TEST_ROOT}/rejected.log" 2>&1; then fail "不安全消费者被接受: ${CHANGE}"; fi
done
cp -- "${TEST_ROOT}/valid-consumer-compose.json" "${PADM_DOCKER_INSTALL_DIR}/compose.json"
cp -- "${PADM_DOCKER_INSTALL_DIR}/images.env" "${TEST_ROOT}/valid-consumer-images.env"
sed 's|^PADM_DOCKER_ROOT=.*|PADM_DOCKER_ROOT=/outside/root|' "${TEST_ROOT}/valid-consumer-images.env" \
    >"${PADM_DOCKER_INSTALL_DIR}/images.env"
reject dockerTlsConsumers "${DOMAIN}"
cp -- "${TEST_ROOT}/valid-consumer-images.env" "${PADM_DOCKER_INSTALL_DIR}/images.env"
mv "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json" "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.real"
ln -s config.real "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json"
reject dockerTlsConsumers "${DOMAIN}"
rm -- "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json"
mv "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.real" "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json"
sed 's|/etc/padm/secrets/tls/example.com.key|/etc/padm/secrets/tls/wrong.example.com.key|' \
    "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf" >"${TEST_ROOT}/bad-nginx.conf"
cp -- "${TEST_ROOT}/bad-nginx.conf" "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf"
reject dockerTlsConsumers "${DOMAIN}"
for CORE in xray sing-box nginx; do
    coreTlsState "unsafe-image-${CORE}" both true
    rm -- "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    case "${CORE}" in
    xray) IMAGE_KEY=PADM_XRAY_IMAGE ;;
    sing-box) IMAGE_KEY=PADM_SINGBOX_IMAGE ;;
    nginx) IMAGE_KEY=PADM_NGINX_IMAGE ;;
    esac
    BAD_IMAGE="ghcr.io/example/padm-${CORE}:3.2.0@sha256:$(printf 'b%.0s' {1..64})"
    sed "s|^${IMAGE_KEY}=.*|${IMAGE_KEY}=${BAD_IMAGE}|" "${PADM_DOCKER_INSTALL_DIR}/images.env" \
        >"${TEST_ROOT}/unsafe-consumer-images.env"
    cp -- "${TEST_ROOT}/unsafe-consumer-images.env" "${PADM_DOCKER_INSTALL_DIR}/images.env"
    before=$(materials)
    runCoreCommit failure
    [[ "$(materials)" == "${before}" && ! -s "${TEST_ROOT}/compose.log" ]] ||
        fail "${CORE}: 无规格时镜像漂移仍触发证书切换或重建"
done
printf 'docker-tls-regression-ok\n'
