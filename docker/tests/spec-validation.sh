#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-spec-validation.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "docker-spec-validation-regression-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

fail() {
    printf 'docker-spec-validation-regression-fail: %s\n' "$*" >&2
    exit 1
}

# 只在测试中重组全部静态块，作为未剪枝的原谓词差分基线。
python3 - "${PROJECT_ROOT}" "${TEST_ROOT}" <<'PY'
import copy
import hashlib
import json
from pathlib import Path
import re
import sys

project, output = map(Path, sys.argv[1:])
source = (project / "docker/lib/services.sh").read_text()
function = source.split("dockerConfigureSpecValidate() {", 1)[1].split(
    "\ndockerSshFail2banSpecValidate()", 1
)[0]
blocks = re.findall(
    r'validationFilter(?:\+)?=(?P<prefix>"\$\{protocolPrefix\}")?'
    r"'(?P<body>\n.*?)\n    '",
    function, re.S,
)
if len(blocks) != 28 or sum(bool(prefix) for prefix, _ in blocks) != 10:
    raise RuntimeError("all static validation blocks must be included")
baseline = ""
protocol_prefix = "if"
for prefix, body in blocks:
    if prefix:
        baseline += "\n" + protocol_prefix
        protocol_prefix = "elif"
    baseline += body
# 摘要锁定含指定 UID 透明转发和解析后 IP 出站组合的完整谓词，仅忽略拼接空白。
if hashlib.sha256(re.sub(r"\s+", "", baseline).encode()).hexdigest() != (
    "b5cf3ffda219ae601278f8ae353dc23e317bcc69a00f64841331768e3449641e"
):
    raise RuntimeError("static blocks differ from the original full predicate")
(output / "baseline.jq").write_text(baseline)
cases = {}
reality = json.loads((project / "docker/configure.example.json").read_bytes())
websocket = json.loads((project / "docker/configure-nginx.example.json").read_bytes())
cases["reality-v1"] = reality
cases["websocket-v1"] = websocket
for version in (2, 3):
    for name, value in (("reality", reality), ("websocket", websocket)):
        value = copy.deepcopy(value)
        value["schema_version"] = version
        entry = value["core"]["protocols"][0]
        entry["listener_id"] = f"entry-{name}"
        if entry["id"] == 21:
            entry["websocket"].update(backend_port=31297, tls_port=8443)
        if version == 3:
            value["core"]["secondary_type"] = None
            entry["core"] = "xray"
        cases[f"{name}-v{version}"] = value
mixed = copy.deepcopy(cases["websocket-v3"])
second = copy.deepcopy(cases["reality-v3"]["core"]["protocols"][0])
second["public_port"] = 4443
mixed["core"]["protocols"].append(second)
cases["mixed"] = mixed
# 每个支持协议独立有效，再覆盖不同静态组共存，不能只让两个实现共同拒绝。
protocol_ids = (1, 2, 3, 4, 5, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31)
for protocol_id in protocol_ids:
    spec = copy.deepcopy(cases["reality-v3"])
    core = "sing-box" if protocol_id in (3, 4, 5, 30, 31) else "xray"
    spec["core"]["type"] = core
    entry = {
        key: copy.deepcopy(value)
        for key, value in spec["core"]["protocols"][0].items()
        if key != "reality"
    }
    entry.update(id=protocol_id, core=core, listener_id=f"entry-p{protocol_id}")
    domain = "proxy.example.com"
    if protocol_id in (1, 2, 26):
        entry["reality"] = copy.deepcopy(reality["core"]["protocols"][0]["reality"])
        if protocol_id == 2:
            entry["xhttp"] = {"path": "/xhttp", "host": domain, "mode": "auto"}
        elif protocol_id == 26:
            entry["grpc"] = {"service_name": "fixture"}
    elif protocol_id in (21, 22, 23):
        field = "httpupgrade" if protocol_id == 23 else "websocket"
        entry[field] = {
            "domain": domain, "path": "fixture_path", "backend_port": 31297, "tls_port": 8443,
        }
    elif protocol_id in (24, 25):
        entry["grpc_tls"] = {
            "domain": domain, "service_name": "fixture", "backend_port": 31297, "tls_port": 8443,
        }
    elif protocol_id in (27, 29):
        entry["fallback_tls"] = {"domain": domain, "http_port": 8081, "http2_port": 8082}
    elif protocol_id == 28:
        entry["trojan"] = {"domain": domain}
    elif protocol_id == 3:
        entry["hy2"] = {
            "domain": domain, "bandwidth_mode": "bbr", "up_mbps": 100, "down_mbps": 100,
            "obfs": None, "masquerade": "",
        }
    elif protocol_id == 4:
        entry["anytls"] = {"domain": domain}
    elif protocol_id == 5:
        entry["naive"] = {"domain": domain}
    elif protocol_id == 30:
        entry["shadowsocks"] = {
            "method": "2022-blake3-aes-128-gcm",
            "server_password": "A" * 22 + "==", "user_password": "B" * 21 + "A==",
        }
    elif protocol_id == 31:
        entry["tuic"] = {
            "domain": domain, "congestion_control": "bbr", "auth_timeout": "3s",
            "heartbeat": "10s", "zero_rtt_handshake": False,
        }
    spec["core"]["protocols"] = [entry]
    spec["tls"] = None if protocol_id in (1, 2, 26, 30) else {"domain": domain}
    cases[f"valid-protocol-{protocol_id}"] = spec
spec = copy.deepcopy(cases["valid-protocol-3"])
spec["core"]["protocols"][0]["address_families"] = ["ipv4", "ipv6"]
spec["port_hopping"] = {
    "listener_id": "entry-p3", "range_start": 36000, "range_end": 36002,
    "ipv4": "198.18.1.1", "ipv6": "2001:db8:1::1",
}
cases["valid-port-hopping"] = spec
for field, value in (("range_start", 36003), ("ipv4", "127.0.0.1"), ("extra", True)):
    invalid = copy.deepcopy(spec)
    invalid["port_hopping"][field] = value
    cases[f"invalid-port-hopping-{field}"] = invalid
spec = copy.deepcopy(cases["valid-protocol-4"])
spec["routing"] = {"block_ips": {"ips": ["192.0.2.1"], "resolve_domains": True}}
cases["valid-block-ips-resolved"] = spec
for field, value in (("false", False), ("null", None), ("number", 1)):
    invalid = copy.deepcopy(spec)
    invalid["routing"]["block_ips"]["resolve_domains"] = value
    cases[f"invalid-block-ips-resolved-{field}"] = invalid
invalid = copy.deepcopy(cases["reality-v3"])
invalid["routing"] = copy.deepcopy(spec["routing"])
cases["invalid-block-ips-resolved-xray"] = invalid
ipv6 = dict(mode="selective", domains=["full:ipv6.example.com"])
warp = dict(mode="selective", family="ipv4",
            private_key="AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=",
            peer_public_key="ISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A=",
            ipv6_address="2606:4700:110:8a10::2", reserved=[1, 2, 255],
            domains=["full:warp.example.com"])
for name, family in (("ipv6", None), ("warp4", "ipv4"), ("warp6", "ipv6")):
    combined = copy.deepcopy(cases["valid-block-ips-resolved"])
    combined["routing"]["ipv6"] = copy.deepcopy(ipv6)
    if family:
        combined["routing"]["warp"] = copy.deepcopy(warp)
        combined["routing"]["warp"]["family"] = family
    cases[f"valid-block-ips-resolved-{name}"] = combined
for field in ("ipv6", "warp"):
    combined = copy.deepcopy(cases["valid-block-ips-resolved"])
    combined["routing"][field] = copy.deepcopy(ipv6 if field == "ipv6" else warp)
    combined["routing"][field].update(mode="global", domains=[])
    cases[f"valid-block-ips-resolved-{field}-global"] = combined
invalid = copy.deepcopy(cases["valid-block-ips-resolved-warp-global"])
invalid["routing"]["ipv6"] = dict(mode="global", domains=[])
cases["invalid-block-ips-resolved-dual-global"] = invalid
invalid = copy.deepcopy(cases["valid-block-ips-resolved-warp4"])
invalid["core"]["secondary_type"] = "xray"
cases["invalid-block-ips-resolved-secondary"] = invalid
for name, ids in (("xray", (1, 21, 27, 28)), ("sing-box", (3, 4, 5, 30, 31))):
    spec = copy.deepcopy(cases[f"valid-protocol-{ids[1]}"])
    spec["core"]["protocols"] = []
    for index, protocol_id in enumerate(ids):
        entry = copy.deepcopy(cases[f"valid-protocol-{protocol_id}"]["core"]["protocols"][0])
        entry["public_port"] = 24440 + index
        spec["core"]["protocols"].append(entry)
    cases[f"valid-multi-group-{name}"] = spec
optional = {
    "site": {"mode": "static"},
    "routing": {"direct": {"domains": ["full:example.com"]}},
    "cdn_entries": [{"listener_id": "entry-websocket", "addresses": ["cdn.example.com"]}],
    "port_aliases": [{"listener_id": "entry-websocket", "public_port": 444}],
    "relay": {"http": {
        "core": "xray", "port": 4433, "address_families": ["ipv4"],
        "username": "relay-user", "password": "relay-password",
        "source_ips": ["192.0.2.1"],
    }},
    "accounts": [{
        "id": "33333333-3333-4333-8333-333333333333",
        "name": "test", "enabled": True,
        "uuid": "44444444-4444-4444-8444-444444444444",
        "password": "account_password_123456",
        "shadowsocks_password": None, "listeners": ["entry-websocket"],
    }],
}
for field, value in optional.items():
    spec = copy.deepcopy(cases["websocket-v3"])
    spec[field] = value
    cases[f"optional-{field}"] = spec
    for name, invalid in (("null", None), ("false", False), ("empty", [])):
        spec = copy.deepcopy(cases["websocket-v3"])
        spec[field] = invalid
        cases[f"invalid-{field}-{name}"] = spec
all_optional = copy.deepcopy(mixed)
all_optional.update(optional)
cases["all-six-optionals"] = all_optional
for field in ("reality_stream", "control", "control_sync"):
    spec = copy.deepcopy(all_optional)
    spec[field] = None
    cases[f"all-optionals-{field}"] = spec
all_keys = copy.deepcopy(all_optional)
all_keys.update(reality_stream=None, control=None, control_sync=None)
cases["all-optional-keys"] = all_keys
ssh = copy.deepcopy(cases["reality-v3"])
ssh["host_integrations"] = [{
    "type": "fail2ban-ssh", "profile": "net-fail2ban-ssh",
    "firewall_rules": ["INPUT"], "devices": [], "schedules": [],
    "settings": {
        "unit": "sshd-padm.service", "target": "192.0.2.10", "port": 2222,
        "max_retry": 6, "find_time": 600, "ban_time": 3600,
    },
}]
cases["ssh"] = ssh
wireguard = {
    "type": "wireguard", "profile": "net-wireguard", "firewall_rules": [],
    "devices": ["wg-padm"], "schedules": [],
    "settings": {"config_file": "wg-padm.conf", "interface": "wg-padm"},
}
spec = copy.deepcopy(cases["reality-v3"])
spec["host_integrations"] = [wireguard]
cases["valid-host-wireguard"] = spec
spec = copy.deepcopy(cases["reality-v3"])
spec["host_integrations"] = [{
    "type": "tproxy", "profile": "net-transparent", "firewall_rules": ["padm-tproxy"],
    "devices": [], "schedules": [], "settings": {"port": 31298, "mark": 129},
}]
cases["valid-host-tproxy"] = spec
for family in ("ipv4", "ipv6", "dual"):
    valid = copy.deepcopy(spec)
    valid["host_integrations"][0]["settings"]["family"] = family
    cases[f"valid-host-tproxy-{family}"] = valid
    valid = copy.deepcopy(valid)
    valid["host_integrations"][0]["settings"]["output_uid"] = 65534
    cases[f"valid-host-tproxy-output-{family}"] = valid
for uid in (1, 2147483647):
    valid = copy.deepcopy(spec)
    valid["host_integrations"][0]["settings"]["output_uid"] = uid
    cases[f"valid-host-tproxy-output-{uid}"] = valid
for uid in (0, -1, 10001, 2147483648, "65534", None, 1.5, True):
    invalid = copy.deepcopy(spec)
    invalid["host_integrations"][0]["settings"]["output_uid"] = uid
    cases[f"invalid-tproxy-output-{len(cases)}"] = invalid
for family in ("", "IPv4", "all", None, 4, []):
    invalid = copy.deepcopy(spec)
    invalid["host_integrations"][0]["settings"]["family"] = family
    cases[f"invalid-tproxy-family-{len(cases)}"] = invalid
for mark in (253, 254, 255):
    invalid = copy.deepcopy(spec)
    invalid["host_integrations"][0]["settings"]["mark"] = mark
    cases[f"invalid-tproxy-mark-{mark}"] = invalid
invalid = copy.deepcopy(spec)
invalid["core"]["secondary_type"] = "sing-box"
cases["invalid-tproxy-secondary"] = invalid
spec = copy.deepcopy(cases["reality-v3"])
spec["core"]["type"] = spec["core"]["protocols"][0]["core"] = "sing-box"
spec["core"]["protocols"][0]["address_families"] = ["ipv4"]
spec["host_integrations"] = [{
    "type": "tun", "profile": "net-transparent", "firewall_rules": ["sing-box-auto-redirect"],
    "devices": ["/dev/net/tun"], "schedules": [],
    "settings": {"interface": "padm-tun", "address": "198.18.0.1/30"},
}]
cases["valid-host-tun"] = spec
invalid = copy.deepcopy(spec)
invalid["core"]["protocols"][0]["address_families"].append("ipv6")
cases["invalid-tun-ipv6"] = invalid
invalid = copy.deepcopy(spec)
invalid["core"]["type"] = invalid["core"]["protocols"][0]["core"] = "xray"
cases["invalid-tun-xray"] = invalid
invalid = copy.deepcopy(spec)
invalid["host_integrations"].append(wireguard)
cases["invalid-tun-shared"] = invalid
spec = copy.deepcopy(cases["websocket-v3"])
spec["host_integrations"] = [{
    "type": "fail2ban", "profile": "net-fail2ban", "firewall_rules": ["DOCKER-USER"],
    "devices": [], "schedules": [],
    "settings": {
        "log_file": "access.log", "ports": [443], "max_retry": 6,
        "find_time": 600, "ban_time": 3600,
    },
}]
cases["valid-host-fail2ban"] = spec
spec = copy.deepcopy(cases["reality-v3"])
spec["reality_stream"] = {
    "listener_id": "entry-reality",
    "host_website": {"domains": ["website.example.com"], "address": "192.0.2.10", "port": 8443},
}
cases["valid-reality-stream-host"] = spec
spec = copy.deepcopy(mixed)
spec["core"]["protocols"][0]["public_port"] = 4443
spec["core"]["protocols"][1]["public_port"] = 443
spec["reality_stream"] = {
    "listener_id": "entry-reality", "website_listener_id": "entry-websocket",
}
cases["valid-reality-stream-managed"] = spec
spec = copy.deepcopy(cases["websocket-v3"])
spec["tls"]["http01"] = True
cases["valid-tls-http01"] = spec
for fixture in ("reality-v1", "websocket-v1", "reality-v3", "websocket-v3"):
    for field, values in (
        ("host_integrations", (None, False, {}, "", 1, [None], [{}])),
        ("reality_stream", (None, False, {}, "", 1, [])),
        ("tls", (None, False, {}, "", 1, [], {"http01": True})),
    ):
        for index, value in enumerate(values):
            spec = copy.deepcopy(cases[fixture])
            spec[field] = value
            cases[f"shape-{fixture}-{field}-{index}"] = spec
    for field in ("host_integrations", "tls"):
        spec = copy.deepcopy(cases[fixture])
        del spec[field]
        cases[f"shape-{fixture}-missing-{field}"] = spec
for protocol_id in (1, 2, 3, 4, 5, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 999, "1", None):
    spec = copy.deepcopy(mixed)
    spec["core"]["protocols"][1]["id"] = protocol_id
    cases[f"mixed-id-{protocol_id!r}"] = spec
for name, value in (("scalar", 1), ("object", {}), ("null", None)):
    spec = copy.deepcopy(mixed)
    spec["core"]["protocols"] = value
    cases[f"protocols-{name}"] = spec
for name, value in (("scalar", 1), ("string", "bad"), ("null", None)):
    spec = copy.deepcopy(mixed)
    spec["core"] = value
    cases[f"core-{name}"] = spec
    spec = copy.deepcopy(mixed)
    spec["core"]["protocols"][1] = value
    cases[f"protocol-entry-{name}"] = spec
for name, value in cases.items():
    (output / f"{name}.json").write_text(json.dumps(value))
(output / "malformed.json").write_bytes(b'{"core":')
(output / "null.json").write_bytes(b"null")
(output / "two-objects.json").write_text(json.dumps(reality) + "\n" + json.dumps(websocket))
(output / "literal-nul.json").write_bytes(
    json.dumps(reality).encode().replace(b"replace_with_random_token", b"bad\0token")
)
(output / "escaped-nul.json").write_bytes(
    json.dumps(reality).encode().replace(b"replace_with_random_token", b"bad\\u0000token")
)
PY

baselineValidate() {
    local file=$1 flags hasSync hasMain hasSsh
    flags=$(command jq -ers --slurpfile schema "$(dockerConfigureSchemaFile)" \
        --slurpfile matrix "$(dockerFeatureMatrixFile)" \
        -f "${TEST_ROOT}/baseline.jq" "${file}" 2>/dev/null) || return 1
    IFS='|' read -r hasSync hasMain hasSsh <<<"${flags}"
    if command jq -e 'has("port_hopping")' "${file}" >/dev/null; then
        dockerPortHoppingAddressesValidate \
            "$(command jq -er '.port_hopping.ipv4' "${file}")" \
            "$(command jq -er '.port_hopping.ipv6' "${file}")" || return 1
    fi
    [[ "${hasSync}" == false ]] || dockerControlSyncSpecValidate "${file}" || return 1
    [[ "${hasMain}" == false ]] || dockerControlSpecValidate "${file}" || return 1
    [[ "${hasSsh}" == false ]] || dockerSshFail2banSpecValidate "${file}" || return 1
}

count=0
for file in "${TEST_ROOT}"/*.json; do
    expected=0 actual=0
    baselineValidate "${file}" || expected=1
    dockerConfigureSpecValidate "${file}" >"${TEST_ROOT}/validation.log" 2>&1 || actual=1
    [[ "${actual}" == "${expected}" ]] || {
        cat "${TEST_ROOT}/validation.log" >&2
        fail "差分结果不一致: ${file##*/}"
    }
    if [[ "${file##*/}" == valid-* && "${actual}" != 0 ]]; then
        cat "${TEST_ROOT}/validation.log" >&2
        fail "有效协议规格被拒绝: ${file##*/}"
    fi
    [[ ( "${file##*/}" != invalid-tproxy-* && "${file##*/}" != invalid-block-ips-resolved-* ) ||
        "${actual}" != 0 ]] || fail "无效透明/解析后 IP 规格被接受: ${file##*/}"
    count=$((count + 1))
done
for file in mixed all-six-optionals ssh; do
    dockerConfigureSpecValidate "${TEST_ROOT}/${file}.json" ||
        fail "有效混合规格被拒绝: ${file}"
done

# 规范化后改写源文件，主校验和多次读取的辅助校验仍须看到最初输入。
cp -- "${TEST_ROOT}/websocket-v3.json" "${TEST_ROOT}/changing.json"
export PADM_SPEC_CHANGE_SOURCE="${TEST_ROOT}/changing.json"
export PADM_SPEC_CHANGE_REPLACEMENT="${TEST_ROOT}/malformed.json"
jq() {
    local status=0 argument canonical=0
    for argument in "$@"; do
        [[ "${argument}" != *'($spec | tojson)'* ]] || canonical=1
    done
    command jq "$@" || status=$?
    if [[ "${canonical}" == 1 && "${status}" == 0 ]]; then
        cp -- "${PADM_SPEC_CHANGE_REPLACEMENT}" "${PADM_SPEC_CHANGE_SOURCE}" || return 1
    fi
    return "${status}"
}
dockerConfigureSpecValidate "${TEST_ROOT}/changing.json" ||
    fail '规范化后源文件变化影响了主校验'
(
    command jq '.control={role:"snapshot-marker"}' "${TEST_ROOT}/websocket-v3.json" \
        >"${TEST_ROOT}/changing.json"
    dockerControlSpecValidate() {
        printf '%s\n' "$1" >"${TEST_ROOT}/snapshot-path"
        [[ "$1" != "${PADM_SPEC_CHANGE_SOURCE}" && "$(stat -c %a "$1")" == 600 ]] &&
            command jq -e '.control.role == "snapshot-marker"' "$1" >/dev/null &&
            command jq -e '.control.role == "snapshot-marker"' "$1" >/dev/null
    }
    dockerConfigureSpecValidate "${TEST_ROOT}/changing.json" ||
        fail '辅助校验未读取同一规范化快照'
    [[ ! -e "$(<"${TEST_ROOT}/snapshot-path")" ]] ||
        fail '辅助校验快照未清理'
)
cp -- "${TEST_ROOT}/ssh.json" "${TEST_ROOT}/changing.json"
dockerConfigureSpecValidate "${TEST_ROOT}/changing.json" ||
    fail 'SSH 多次辅助读取未使用同一快照'
unset -f jq

# 使用文件入口保留原生缓存路径，核对进程数量、矩阵晚读及完整输出后的失败。
(
    nativeBin="${TEST_ROOT}/native-bin"
    mkdir -- "${nativeBin}"
    export PADM_SPEC_REAL_JQ PADM_SPEC_JQ_CALLS="${TEST_ROOT}/native-jq.calls"
    PADM_SPEC_REAL_JQ=$(type -P jq)
    cat >"${nativeBin}/jq" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$1" >>"${PADM_SPEC_JQ_CALLS:?}"
"${PADM_SPEC_REAL_JQ:?}" "$@" || exit $?
if [[ "$1" == -enrc && -n "${PADM_SPEC_MATRIX_CHANGE:-}" ]]; then
    printf 'invalid json\n' >"${PADM_SPEC_MATRIX_CHANGE}" || exit 17
fi
[[ "$1" != -ers || "${PADM_SPEC_FAIL_FLAGS:-0}" != 1 ]] || exit 17
SH
    chmod 0755 "${nativeBin}/jq"
    export PATH="${nativeBin}:${PATH}"
    cp -- "$(dockerFeatureMatrixFile)" "${TEST_ROOT}/native-matrix.json"
    dockerFeatureMatrixFile() { printf '%s\n' "${TEST_ROOT}/native-matrix.json"; }
    DOCKER_SPEC_VALIDATED_JSON=
    DOCKER_SPEC_VALIDATED_MATRIX=
    DOCKER_SPEC_VALIDATED_FLAGS=
    : >"${PADM_SPEC_JQ_CALLS}"
    dockerConfigureSpecValidate "${TEST_ROOT}/reality-v3.json"
    [[ "$(<"${PADM_SPEC_JQ_CALLS}")" == $'-enrc\n-ers' ]] ||
        fail '首次原生校验未合并矩阵读取'
    : >"${PADM_SPEC_JQ_CALLS}"
    dockerConfigureSpecValidate "${TEST_ROOT}/reality-v3.json"
    [[ "$(<"${PADM_SPEC_JQ_CALLS}")" == $'-enrc\n-nc' ]] ||
        fail '暖缓存未重读规格、schema 和矩阵'
    savedJson=${DOCKER_SPEC_VALIDATED_JSON}
    savedMatrix=${DOCKER_SPEC_VALIDATED_MATRIX}
    savedFlags=${DOCKER_SPEC_VALIDATED_FLAGS}
    "${PADM_SPEC_REAL_JQ}" '.protocols |=
      map(if .id == 1 then .status="deferred" else . end)' \
        "${TEST_ROOT}/native-matrix.json" >"${TEST_ROOT}/native-matrix.next.json"
    mv -- "${TEST_ROOT}/native-matrix.next.json" "${TEST_ROOT}/native-matrix.json"
    : >"${PADM_SPEC_JQ_CALLS}"
    ! dockerConfigureSpecValidate "${TEST_ROOT}/reality-v3.json" >/dev/null 2>&1 ||
        fail '矩阵变化后错误复用成功结果'
    [[ "$(<"${PADM_SPEC_JQ_CALLS}")" == $'-enrc\n-nc\n-ers' ]] ||
        fail '矩阵变化后没有执行完整谓词'
    printf '%s\n' "${savedMatrix}" | "${PADM_SPEC_REAL_JQ}" '.[]' \
        >"${TEST_ROOT}/native-matrix.json"
    export PADM_SPEC_FAIL_FLAGS=1
    ! dockerConfigureSpecValidate "${TEST_ROOT}/websocket-v3.json" >/dev/null 2>&1 ||
        fail '首次原生校验忽略完整输出后的 jq 失败'
    [[ "${DOCKER_SPEC_VALIDATED_JSON}" == "${savedJson}" &&
        "${DOCKER_SPEC_VALIDATED_MATRIX}" == "${savedMatrix}" &&
        "${DOCKER_SPEC_VALIDATED_FLAGS}" == "${savedFlags}" ]] ||
        fail '失败原生校验改变了成功缓存'
    unset PADM_SPEC_FAIL_FLAGS
    for cacheMode in cold warm; do
        printf '%s\n' "${savedMatrix}" | "${PADM_SPEC_REAL_JQ}" '.[]' \
            >"${TEST_ROOT}/native-matrix.json"
        [[ "${cacheMode}" != cold ]] || DOCKER_SPEC_VALIDATED_FLAGS=
        export PADM_SPEC_MATRIX_CHANGE="${TEST_ROOT}/native-matrix.json"
        ! dockerConfigureSpecValidate "${TEST_ROOT}/reality-v3.json" >/dev/null 2>&1 ||
            fail "原生矩阵晚读失败被忽略: ${cacheMode}"
        unset PADM_SPEC_MATRIX_CHANGE
        DOCKER_SPEC_VALIDATED_FLAGS=${savedFlags}
    done
)

# 成功复用仍读取当前规格、支持矩阵和 schema，失败不能保留旧输入的授权。
(
    cp -- "$(dockerFeatureMatrixFile)" "${TEST_ROOT}/matrix.json"
    cp -- "$(dockerConfigureSchemaFile)" "${TEST_ROOT}/schema.json"
    dockerFeatureMatrixFile() { printf '%s\n' "${TEST_ROOT}/matrix.json"; }
    dockerConfigureSchemaFile() { printf '%s\n' "${TEST_ROOT}/schema.json"; }
    cp -- "${TEST_ROOT}/reality-v3.json" "${TEST_ROOT}/cached.json"
    dockerConfigureSpecValidate "${TEST_ROOT}/cached.json"
    [[ "${DOCKER_SPEC_VALIDATED_JSON}" == "$(command jq -c . "${TEST_ROOT}/cached.json")" &&
        "${DOCKER_SPEC_VALIDATED_MATRIX}" == "$(command jq -sc . "${TEST_ROOT}/matrix.json")" &&
        "${DOCKER_SPEC_VALIDATED_FLAGS}" == 'false|false|false' ]] ||
        fail '纯谓词成功未保存完整输入'
    dockerConfigureSpecValidate "${TEST_ROOT}/cached.json"
    savedJson=${DOCKER_SPEC_VALIDATED_JSON}
    savedMatrix=${DOCKER_SPEC_VALIDATED_MATRIX}
    ! export -p | grep -E 'DOCKER_SPEC_VALIDATED_(JSON|MATRIX|FLAGS)=' ||
        fail '规格缓存泄露到子进程环境'
    command jq '.core.protocols[0].public_port=0' "${TEST_ROOT}/reality-v3.json" \
        >"${TEST_ROOT}/cached.json"
    ! dockerConfigureSpecValidate "${TEST_ROOT}/cached.json" >/dev/null 2>&1 ||
        fail '相同路径规格变化仍使用旧校验'
    [[ "${DOCKER_SPEC_VALIDATED_JSON}" == "${savedJson}" ]] ||
        fail '失败纯谓词写入成功缓存'
    cp -- "${TEST_ROOT}/reality-v3.json" "${TEST_ROOT}/cached.json"
    ln -s "${TEST_ROOT}/cached.json" "${TEST_ROOT}/cached-link.json"
    ! dockerConfigureSpecValidate "${TEST_ROOT}/cached-link.json" >/dev/null 2>&1 ||
        fail '暖缓存绕过规格普通文件门禁'
    printf 'invalid json\n' >"${TEST_ROOT}/matrix.json"
    ! dockerConfigureSpecValidate "${TEST_ROOT}/cached.json" >/dev/null 2>&1 ||
        fail '暖缓存绕过矩阵 JSON 解析'
    printf '%s\n' "${savedMatrix}" | command jq '.[] | .protocols |=
      map(if .id == 1 then .status="deferred" else . end)' >"${TEST_ROOT}/matrix.json"
    ! dockerConfigureSpecValidate "${TEST_ROOT}/cached.json" >/dev/null 2>&1 ||
        fail '暖缓存忽略矩阵支持状态变化'
    printf '%s\n' "${savedMatrix}" | command jq '.[]' >"${TEST_ROOT}/matrix.json"
    printf 'invalid json\n' >"${TEST_ROOT}/schema.json"
    ! dockerConfigureSpecValidate "${TEST_ROOT}/cached.json" >/dev/null 2>&1 ||
        fail '暖缓存绕过 schema JSON 解析'
)

# 同次调用保留矩阵的晚读时点，辅助校验每次执行且使用私有快照。
(
    cp -- "$(dockerFeatureMatrixFile)" "${TEST_ROOT}/matrix-late.json"
    dockerFeatureMatrixFile() { printf '%s\n' "${TEST_ROOT}/matrix-late.json"; }
    jq() {
        command jq "$@" || return $?
        if [[ "${1:-}" == -enrc ]]; then
            printf 'invalid json\n' >"${TEST_ROOT}/matrix-late.json"
        fi
    }
    ! dockerConfigureSpecValidate "${TEST_ROOT}/reality-v3.json" >/dev/null 2>&1 ||
        fail '矩阵晚读失败被忽略'
)
(
    command jq '.control={role:"snapshot-marker"}' "${TEST_ROOT}/websocket-v3.json" \
        >"${TEST_ROOT}/aux-cached.json"
    dockerControlSpecValidate() {
        printf '%s\n' "$1" >>"${TEST_ROOT}/aux-calls"
        [[ "$1" != "${TEST_ROOT}/aux-cached.json" && "$(stat -c %a "$1")" == 600 ]] &&
            command jq -e '.control.role == "snapshot-marker"' "$1" >/dev/null
    }
    dockerConfigureSpecValidate "${TEST_ROOT}/aux-cached.json"
    dockerConfigureSpecValidate "${TEST_ROOT}/aux-cached.json"
    [[ "$(wc -l <"${TEST_ROOT}/aux-calls")" -eq 2 ]] ||
        fail '纯谓词命中跳过辅助校验'
    while IFS= read -r snapshotPath; do
        [[ ! -e "${snapshotPath}" ]] || fail '辅助校验复用遗留快照'
    done <"${TEST_ROOT}/aux-calls"
    dockerControlSpecValidate() { return 1; }
    ! dockerConfigureSpecValidate "${TEST_ROOT}/aux-cached.json" >/dev/null 2>&1 ||
        fail '纯谓词命中忽略辅助失败'
)

# 主谓词即使已输出正常标记，仍须传播该次工具失败。
for jqStage in -enrc -ers; do
    (
        jq() {
            command jq "$@" || return $?
            [[ "${1:-}" != "${jqStage}" ]] || return 17
        }
        ! dockerConfigureSpecValidate "${TEST_ROOT}/reality-v3.json" ||
            fail "规格校验忽略工具非零退出: ${jqStage}"
    )
done

printf 'docker-spec-validation-regression-ok:%s-differential-cases\n' "${count}"
