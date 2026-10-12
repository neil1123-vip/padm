#!/usr/bin/env bash
set -Eeuo pipefail

# 复用可信发布和生产事务夹具，不重复祖先协议矩阵。
export PADM_DOCKER_TEST_FIXTURE_ONLY=1
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/reality.sh"
trap 'printf "docker-xhttp-regression-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
export PYTHONDONTWRITEBYTECODE=1
ASSET_ARGS=(--manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" --control-bundle "${CONFIGURE_CONTROL}")
XHTTP_SPEC="${TEST_ROOT}/xhttp.json"
ACCOUNT=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
GROUP='{"id":"share-cccccccccccccccc","name":"XHTTP-Team","enabled":true,
  "token":"xhttp-group-token","account_ids":["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"],
  "listener_ids":["entry-xhttp","entry-xhttp-other"]}'
jq --arg manifest "${CONFIGURE_MANIFEST_SHA}" --arg account "${ACCOUNT}" \
    --slurpfile ws "${TEST_ROOT}/v3.json" --slurpfile release "${CONFIGURE_MANIFEST}" '
  .release.manifest_sha256 = $manifest |
  .images = ($release[0].images | with_entries(.value = .value.reference)) |
  .subscription.enabled = true | .tls = $ws[0].tls |
  .core.protocols += [
    (.core.protocols[] | select(.id == 2) |
      .listener_id = "entry-xhttp-other" | .public_port = 25447 | .name = "Other-XHTTP"),
    ($ws[0].core.protocols[] | select(.id == 21))] |
  .port_aliases = [{listener_id:"entry-xhttp",public_port:35443,share_default:true}] |
  .accounts = [{id:$account,name:"Alice",enabled:true,
    uuid:"44444444-4444-4444-8444-444444444444",password:"Alice.-~@+=:Secret",
    shadowsocks_password:null,listeners:["entry-xhttp","entry-xhttp-other","vless-ws"]}]
' "${REALITY_SPEC}" >"${XHTTP_SPEC}"
chmod 0600 "${XHTTP_SPEC}"
dockerConfigureSpecValidate "${XHTTP_SPEC}" || fail 'XHTTP 共享账号、双入口发布夹具无效'

# Schema 负责形状，生产校验额外拒绝范围反转和字符串数值溢出。
python3 - "${PROJECT_ROOT}" "${TEST_ROOT}" <<'PY'
import copy
import json
import sys
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker

project, root = map(Path, sys.argv[1:])
base = json.loads((root / "xhttp.json").read_text())
schema = json.loads((project / "docker/contracts/configure.schema.json").read_text())
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema, format_checker=FormatChecker())
defaults = dict(maxConcurrency="16-32", hMaxRequestTimes="600-900", hMaxReusableSecs="1800-3000")
cases = []

def case(name, xmux, valid, schema_valid=None):
    value = copy.deepcopy(base)
    next(p for p in value["core"]["protocols"] if p["id"] == 2)["xhttp"]["xmux"] = xmux
    assert validator.is_valid(value) == (valid if schema_valid is None else schema_valid), name
    (root / f"case-{name}.json").write_text(json.dumps(value), encoding="utf-8")
    cases.append((name, int(valid)))

assert validator.is_valid(base), [(list(error.path), error.message) for error in validator.iter_errors(base)]
case("defaults", defaults, True)
case("integers", dict(maxConcurrency=1, hMaxRequestTimes=0, hMaxReusableSecs=2147483647), True)
case("ranges", dict(maxConcurrency="1-2147483647", hMaxRequestTimes="0-0",
                    hMaxReusableSecs="0-2147483647"), True)
for index, bad in enumerate((None, {}, [], True, "daily", dict(defaults, extra=1))):
    case(f"shape-{index}", bad, False)
for key in defaults:
    value = dict(defaults)
    del value[key]
    case(f"missing-{key}", value, False)
    for index, bad in enumerate((-1, 1.5, True, "1", "", "01-2", "1-02", "1-2\n",
                                 "1e2-200", "1-2-3", 2147483648)):
        case(f"{key}-{index}", dict(defaults, **{key: bad}), False)
    case(f"{key}-reversed", dict(defaults, **{key: "2-1"}), False, True)
    case(f"{key}-overflow", dict(defaults, **{key: "1-2147483648"}), False, True)
case("zero-concurrency", dict(defaults, maxConcurrency=0), False)
case("zero-concurrency-range", dict(defaults, maxConcurrency="0-1"), False)
for index, padding in enumerate((1, 4096, "1-4096", "100-1000")):
    value = copy.deepcopy(base)
    next(p for p in value["core"]["protocols"] if p["id"] == 2)["xhttp"]["xPaddingBytes"] = padding
    assert validator.is_valid(value), padding
    name = f"padding-valid-{index}"
    (root / f"case-{name}.json").write_text(json.dumps(value), encoding="utf-8")
    cases.append((name, 1))
for index, padding in enumerate((None, True, [], {}, 0, -1, 1.5, 4097, "0-0", "0-1",
                                 "01-2", "1-02", "1", "", "1-4097", "1-2\n", "2-1")):
    value = copy.deepcopy(base)
    next(p for p in value["core"]["protocols"] if p["id"] == 2)["xhttp"]["xPaddingBytes"] = padding
    assert validator.is_valid(value) == (padding == "2-1"), padding
    name = f"padding-invalid-{index}"
    (root / f"case-{name}.json").write_text(json.dumps(value), encoding="utf-8")
    cases.append((name, 0))
for key in ("noGRPCHeader", "noSSEHeader"):
    for index, header in enumerate((True, False, None, "true", "false", 0, 1, [], {})):
        value = copy.deepcopy(base)
        next(p for p in value["core"]["protocols"] if p["id"] == 2)["xhttp"][key] = header
        valid = type(header) is bool
        assert validator.is_valid(value) == valid, (key, header)
        name = f"header-{key}-{index}"
        (root / f"case-{name}.json").write_text(json.dumps(value), encoding="utf-8")
        cases.append((name, int(valid)))
value = copy.deepcopy(base)
next(p for p in value["core"]["protocols"] if p["id"] == 2)["xhttp"]["headers"] = {}
assert not validator.is_valid(value), "未支持的高级字段不能进入规格"
(root / "case-advanced-unknown.json").write_text(json.dumps(value), encoding="utf-8")
cases.append(("advanced-unknown", 0))
(root / "cases.tsv").write_text("".join(f"{name}\t{valid}\n" for name, valid in cases))
PY
while IFS=$'\t' read -r name valid; do
    actual=0
    dockerConfigureSpecValidate "${TEST_ROOT}/case-${name}.json" >"${STDOUT}" 2>"${STDERR}" || actual=$?
    [[ ( "${valid}" == 1 && "${actual}" == 0 ) || ( "${valid}" == 0 && "${actual}" != 0 ) ]] ||
        fail "生产 XHTTP 校验不匹配: ${name}"
done <"${TEST_ROOT}/cases.tsv"
dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${TEST_ROOT}/case-defaults.json" || fail '当前包拒绝 XMUX'
jq 'del(."x-padm-xhttp-xmux")' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${COMPAT_BUNDLE}/docker/contracts/configure.schema.json"
if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${TEST_ROOT}/case-defaults.json" 2>/dev/null; then
    fail '旧包接受不支持的显式 XMUX'
fi
dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${XHTTP_SPEC}" || fail '旧包误拒无显式 XMUX'
cp "${PROJECT_ROOT}/docker/contracts/configure.schema.json" "${COMPAT_BUNDLE}/docker/contracts/configure.schema.json"
dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${TEST_ROOT}/case-padding-valid-0.json" ||
    fail '当前包拒绝显式 Padding'
jq 'del(."x-padm-xhttp-padding")' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${COMPAT_BUNDLE}/docker/contracts/configure.schema.json"
if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${TEST_ROOT}/case-padding-valid-0.json" 2>/dev/null; then
    fail '旧包接受不支持的显式 Padding'
fi
dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${TEST_ROOT}/case-defaults.json" ||
    fail '缺 Padding 能力的旧包误拒只有 XMUX 的规格'
dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${XHTTP_SPEC}" || fail '旧包误拒缺省 Padding'
cp "${PROJECT_ROOT}/docker/contracts/configure.schema.json" "${COMPAT_BUNDLE}/docker/contracts/configure.schema.json"
for key in noGRPCHeader noSSEHeader; do
    for index in 0 1; do
        dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${TEST_ROOT}/case-header-${key}-${index}.json" ||
            fail "当前包拒绝显式 ${key}"
    done
done
jq 'del(."x-padm-xhttp-headers")' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${COMPAT_BUNDLE}/docker/contracts/configure.schema.json"
for key in noGRPCHeader noSSEHeader; do
    for index in 0 1; do
        if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${TEST_ROOT}/case-header-${key}-${index}.json" 2>/dev/null; then
            fail "旧包接受不支持的显式 ${key}，包括 false"
        fi
    done
done
for spec in "${XHTTP_SPEC}" "${TEST_ROOT}/case-defaults.json" "${TEST_ROOT}/case-padding-valid-0.json"; do
    dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${spec}" ||
        fail '缺 Header 能力的旧包误拒原 XHTTP/XMUX/Padding 子集'
done

newState xhttp "${XHTTP_SPEC}"
root=${PADM_DOCKER_INSTALL_DIR}
dockerSubscriptionStateWrite "${root}/config/share-groups.json" \
    "$(jq -cn --argjson group "${GROUP}" '{schema_version:1,groups:[$group]}')"
dockerSubscriptionRenderGroup "${root}/config/spec.json" "${GROUP}"
# 同 UUID 的额度过滤保持；调整客户端传输不能解封账号。
quota=$(jq --arg uuid "${UUID}" '.accounts[$uuid].limit_bytes = 1' "${root}/data/traffic/state.json")
printf '%s\n' "${quota}" | dockerTrafficWriteState
dockerTrafficPrepareCandidate "${root}"
: >"${FAKE_REALITY_FAIL_MARKER}"
cp "${root}/config/spec.json" "${TEST_ROOT}/installed-before.json"
cp "${root}/config/xray/users.base" "${TEST_ROOT}/xray-before.json"
cp "${root}/config/sing-box/users.base" "${TEST_ROOT}/sing-before.json"
cp "${root}/data/traffic/state.json" "${TEST_ROOT}/traffic-before.json"
cp "${root}/compose.json" "${TEST_ROOT}/compose-before.json"
cp "${root}/data/subscription/${TOKEN}" "${TEST_ROOT}/links-before.txt"
cp "${root}/data/subscription/xhttp-group-token" "${TEST_ROOT}/group-before.txt"

xhttpClean() {
    [[ ! -e "${root}/locks/deployment.lock" ]] || fail 'XHTTP 遗留部署锁'
    [[ -z "$(find "${root}" -maxdepth 1 \
        \( -name '.edit.*' -o -name '.candidate.*' -o -name '.protocol.*' \) -print -quit)" ]] ||
        fail 'XHTTP 遗留秘密草稿'
}

xhttpEdit() {
    local expected=$1 unchanged=$2 actual=0 before
    shift 2
    if [[ "${unchanged}" == unchanged ]]; then before=$(snapshot); fi
    : >"${EVENTS}"
    bash -u "${CLI}" edit "$@" "${ASSET_ARGS[@]}" </dev/null >"${STDOUT}" 2>"${STDERR}" || actual=$?
    [[ "${actual}" == "${expected}" ]] || fail "XHTTP edit $*: 预期 ${expected}，实际 ${actual}"
    xhttpClean
    [[ "${unchanged}" != unchanged || "$(snapshot)" == "${before}" ]] || fail 'XHTTP 未提交仍改变部署'
}

xhttpAssert() {
    local mode=$1 xmux=$2 padding=${3:-null} grpcHeader=${4:-null} sseHeader=${5:-null}
    jq -en --arg mode "${mode}" --argjson xmux "${xmux}" --argjson padding "${padding}" \
        --argjson grpc "${grpcHeader}" --argjson sse "${sseHeader}" \
        --slurpfile before "${TEST_ROOT}/installed-before.json" \
        --slurpfile after "${root}/config/spec.json" '
      def stable: .core.protocols |= map(if .listener_id == "entry-xhttp"
        then del(.xhttp.mode,.xhttp.xmux,.xhttp.xPaddingBytes,.xhttp.noGRPCHeader,.xhttp.noSSEHeader) else . end);
      ($before[0] | stable) == ($after[0] | stable) and
      any($after[0].core.protocols[]; .listener_id == "entry-xhttp" and
        .xhttp.mode == $mode and .xhttp.xmux == $xmux and .xhttp.xPaddingBytes == $padding and
        .xhttp.noGRPCHeader == $grpc and .xhttp.noSSEHeader == $sse and
        (if $xmux == null then (.xhttp | has("xmux") | not) else true end) and
        (if $padding == null then (.xhttp | has("xPaddingBytes") | not) else true end) and
        (.xhttp | has("noGRPCHeader")) == ($grpc != null) and
        (.xhttp | has("noSSEHeader")) == ($sse != null))
    ' >/dev/null || fail 'XHTTP 改写其它规格、账户或端口'
    jq -en --arg mode "${mode}" --argjson padding "${padding}" \
        --argjson grpc "${grpcHeader}" --argjson sse "${sseHeader}" \
        --slurpfile before "${TEST_ROOT}/xray-before.json" \
        --slurpfile after "${root}/config/xray/users.base" \
        --slurpfile live "${root}/config/xray/config.json" '
      def stable: .inbounds |= map(if .tag == "entry-xhttp"
        then del(.streamSettings.xhttpSettings.mode,.streamSettings.xhttpSettings.xPaddingBytes,
          .streamSettings.xhttpSettings.noGRPCHeader,.streamSettings.xhttpSettings.noSSEHeader) else . end);
      ($before[0] | stable) == ($after[0] | stable) and
      any($after[0].inbounds[]; .tag == "entry-xhttp" and
        .streamSettings.xhttpSettings.mode == $mode and
        .streamSettings.xhttpSettings.xPaddingBytes == $padding and
        .streamSettings.xhttpSettings.noGRPCHeader == $grpc and
        .streamSettings.xhttpSettings.noSSEHeader == $sse and
        (if $padding == null then (.streamSettings.xhttpSettings | has("xPaddingBytes") | not) else true end) and
        (.streamSettings.xhttpSettings | has("noGRPCHeader")) == ($grpc != null) and
        (.streamSettings.xhttpSettings | has("noSSEHeader")) == ($sse != null)) and
      [$after[0].inbounds[] | select(.tag == "entry-xhttp") | .streamSettings.xhttpSettings] ==
        [$live[0].inbounds[] | select(.tag == "entry-xhttp") | .streamSettings.xhttpSettings]
    ' >/dev/null || fail 'XHTTP 改写服务端固定 XMUX、其它核心入口或未同步 Padding/Header'
    for pair in 'sing-before.json config/sing-box/users.base' 'traffic-before.json data/traffic/state.json' \
        'compose-before.json compose.json'; do
        read -r original installed <<<"${pair}"
        cmp -s "${TEST_ROOT}/${original}" "${root}/${installed}" || fail "XHTTP 改变 ${installed}"
    done
    python3 - "${mode}" "${xmux}" "${padding}" "${grpcHeader}" "${sseHeader}" "${TEST_ROOT}" "${root}" "${TOKEN}" <<'PY'
import json
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

mode, encoded, encoded_padding, encoded_grpc, encoded_sse, temp, installed, token = sys.argv[1:]
xmux = json.loads(encoded)
padding = json.loads(encoded_padding)
grpc, sse = json.loads(encoded_grpc), json.loads(encoded_sse)
root, temp = Path(installed), Path(temp)
for before, after in ((temp / "links-before.txt", root / "data/subscription" / token),
                      (temp / "group-before.txt", root / "data/subscription/xhttp-group-token")):
    old, new = before.read_text().splitlines(), after.read_text().splitlines()
    assert len(old) == len(new) and old, (before, after)
    for first, second in zip(old, new):
        a, b = urlsplit(first), urlsplit(second)
        if a.port != 35443:
            assert first == second
            continue
        assert a._replace(query="") == b._replace(query="")
        query, actual = parse_qs(a.query), parse_qs(b.query)
        query["mode"] = [mode]
        extra = {}
        if xmux is not None:
            extra["xmux"] = xmux
        if padding is not None:
            extra["xPaddingBytes"] = padding
        if grpc is not None:
            extra["noGRPCHeader"] = grpc
        if sse is not None:
            extra["noSSEHeader"] = sse
        if extra:
            query["extra"] = [json.dumps(extra, separators=(",", ":"))]
            assert "extra=%7B" in second and json.loads(actual["extra"][0]) == extra
        assert actual == query, (actual, query)
PY
    dockerProtocolCommand links >"${STDOUT}"
    cmp -s "${STDOUT}" "${root}/data/subscription/${TOKEN}" || fail 'CLI 链接与主订阅不一致'
    runRead 0 xhttp-status dockerProtocolCommand xhttp-status entry-xhttp
    jq -e --arg mode "${mode}" --argjson xmux "${xmux}" --argjson padding "${padding}" \
        --argjson grpc "${grpcHeader}" --argjson sse "${sseHeader}" '
      .entries == [{listener_id:"entry-xhttp",protocol:2,mode:$mode,explicit:($xmux != null),
        xmux:($xmux // {maxConcurrency:"16-32",hMaxRequestTimes:"600-900",hMaxReusableSecs:"1800-3000"}),
        xPaddingBytes:($padding // "100-1000"),padding_explicit:($padding != null),
        noGRPCHeader:($grpc // false),noSSEHeader:($sse // false),
        grpc_header_explicit:($grpc != null),sse_header_explicit:($sse != null)}]
    ' "${STDOUT}" >/dev/null || fail 'XHTTP 状态没有区分缺省与显式参数'
    [[ "$(stat -c %a "${root}/config/spec.json")" == 600 &&
        "$(stat -c %a "${root}/data/subscription/${TOKEN}")" == 640 ]] || fail 'XHTTP 更新改变私有权限'
}

defaults='{"maxConcurrency":"16-32","hMaxRequestTimes":"600-900","hMaxReusableSecs":"1800-3000"}'
runRead 0 xhttp-all-status dockerProtocolCommand xhttp-status
jq -e '.entries | length == 2 and all(.[]; .explicit == false)' "${STDOUT}" >/dev/null
for preset in daily compatible stream single; do
    case "${preset}" in compatible) mode=packet-up ;; stream) mode=stream-up ;; *) mode=auto ;; esac
    xmux=${defaults}
    [[ "${preset}" != single ]] || xmux='{"maxConcurrency":1,"hMaxRequestTimes":"600-900","hMaxReusableSecs":"1800-3000"}'
    xhttpEdit 0 unchanged --xhttp-preset entry-xhttp "${preset}" --preview
    ! grep -Eq '^compose .* up -d ' "${EVENTS}" || fail '预览启动候选'
    xhttpEdit 0 changed --xhttp-preset entry-xhttp "${preset}" --confirm PADM-DOCKER-EDIT
    xhttpAssert "${mode}" "${xmux}"
done
xhttpEdit 0 changed --xhttp-xmux entry-xhttp 2-4 0 17 --confirm PADM-DOCKER-EDIT
xhttpAssert auto '{"maxConcurrency":"2-4","hMaxRequestTimes":0,"hMaxReusableSecs":17}'
xhttpEdit 0 changed --xhttp-xmux-clear entry-xhttp --confirm PADM-DOCKER-EDIT
xhttpAssert auto null
cmp -s "${TEST_ROOT}/links-before.txt" "${root}/data/subscription/${TOKEN}" || fail '清除 XMUX 没有恢复旧 URI'
cmp -s "${TEST_ROOT}/group-before.txt" "${root}/data/subscription/xhttp-group-token" || fail '清除 XMUX 没有恢复分享组'
# 双端 Padding 可以独立发布；预设与 XMUX 清除不能顺手丢弃它。
xhttpEdit 0 unchanged --xhttp-padding entry-xhttp 1 --preview
! grep -Eq '^compose .* up -d ' "${EVENTS}" || fail 'Padding 预览启动候选'
for padding in 1 4096 100-1000; do
    xhttpEdit 0 changed --xhttp-padding entry-xhttp "${padding}" --confirm PADM-DOCKER-EDIT
    expectedPadding=${padding}
    [[ "${padding}" != *-* ]] || expectedPadding="\"${padding}\""
    xhttpAssert auto null "${expectedPadding}"
done
xhttpEdit 0 changed --xhttp-xmux entry-xhttp 2 7-9 30-40 --confirm PADM-DOCKER-EDIT
xhttpAssert auto '{"maxConcurrency":2,"hMaxRequestTimes":"7-9","hMaxReusableSecs":"30-40"}' '"100-1000"'
xhttpEdit 0 changed --xhttp-preset entry-xhttp stream --confirm PADM-DOCKER-EDIT
xhttpAssert stream-up "${defaults}" '"100-1000"'
xhttpEdit 0 changed --xhttp-xmux-clear entry-xhttp --confirm PADM-DOCKER-EDIT
xhttpAssert stream-up null '"100-1000"'
xhttpEdit 0 changed --xhttp-padding-clear entry-xhttp --confirm PADM-DOCKER-EDIT
xhttpAssert stream-up null
xhttpEdit 0 changed --xhttp-preset entry-xhttp daily --confirm PADM-DOCKER-EDIT
xhttpEdit 0 changed --xhttp-xmux-clear entry-xhttp --confirm PADM-DOCKER-EDIT
xhttpAssert auto null
cmp -s "${TEST_ROOT}/links-before.txt" "${root}/data/subscription/${TOKEN}" ||
    fail '清除 Padding 没有恢复旧 URI'
# 显式 false 与缺省分开保存，只有两键也必须进入统一发布的 extra。
xhttpEdit 0 unchanged --xhttp-headers entry-xhttp true false --preview
! grep -Eq '^compose .* up -d ' "${EVENTS}" || fail 'Header 预览启动候选'
for headers in 'true false' 'false true' 'false false'; do
    read -r grpcHeader sseHeader <<<"${headers}"
    xhttpEdit 0 changed --xhttp-headers entry-xhttp "${grpcHeader}" "${sseHeader}" --confirm PADM-DOCKER-EDIT
    xhttpAssert auto null null "${grpcHeader}" "${sseHeader}"
done
xhttpEdit 0 changed --xhttp-preset entry-xhttp stream --confirm PADM-DOCKER-EDIT
xhttpAssert stream-up "${defaults}" null false false
xhttpEdit 0 changed --xhttp-xmux entry-xhttp 2 7-9 30-40 --confirm PADM-DOCKER-EDIT
xhttpAssert stream-up '{"maxConcurrency":2,"hMaxRequestTimes":"7-9","hMaxReusableSecs":"30-40"}' null false false
xhttpEdit 0 changed --xhttp-padding entry-xhttp 128-256 --confirm PADM-DOCKER-EDIT
xhttpAssert stream-up '{"maxConcurrency":2,"hMaxRequestTimes":"7-9","hMaxReusableSecs":"30-40"}' '"128-256"' false false
xhttpEdit 0 changed --xhttp-xmux-clear entry-xhttp --confirm PADM-DOCKER-EDIT
xhttpAssert stream-up null '"128-256"' false false
xhttpEdit 0 changed --xhttp-padding-clear entry-xhttp --confirm PADM-DOCKER-EDIT
xhttpAssert stream-up null null false false
xhttpEdit 0 changed --xhttp-headers-clear entry-xhttp --confirm PADM-DOCKER-EDIT
xhttpAssert stream-up null
xhttpEdit 0 changed --xhttp-preset entry-xhttp daily --confirm PADM-DOCKER-EDIT
xhttpEdit 0 changed --xhttp-xmux-clear entry-xhttp --confirm PADM-DOCKER-EDIT
xhttpAssert auto null
cmp -s "${TEST_ROOT}/links-before.txt" "${root}/data/subscription/${TOKEN}" &&
    cmp -s "${TEST_ROOT}/group-before.txt" "${root}/data/subscription/xhttp-group-token" ||
    fail '清除 Header 没有恢复缺省 URI 和分享组'
for listener in entry-missing vless-reality entry-grpc-sing; do
    runRead 15 "unsupported-${listener}" dockerProtocolCommand xhttp-status "${listener}"
    xhttpEdit 15 unchanged --xhttp-preset "${listener}" daily --preview
    xhttpEdit 15 unchanged --xhttp-padding "${listener}" 100-1000 --preview
    xhttpEdit 15 unchanged --xhttp-headers "${listener}" true false --preview
    xhttpEdit 15 unchanged --xhttp-headers-clear "${listener}" --preview
done
for bad in 0 0-0 -1 1.5 01 1e2 2-1 0-1 1-02 4097 1-4097 $'1\n' $'1-2\n'; do
    xhttpEdit 2 unchanged --xhttp-padding entry-xhttp "${bad}" --preview
done
xhttpEdit 2 unchanged --xhttp-padding entry-xhttp 100-1000 --xhttp-padding-clear entry-xhttp --preview
xhttpEdit 2 unchanged --xhttp-padding entry-xhttp 100-1000 --xhttp-preset entry-xhttp daily --preview
xhttpEdit 2 unchanged --xhttp-padding entry-xhttp 100-1000 --spec "${XHTTP_SPEC}" --preview
xhttpEdit 2 unchanged --xhttp-padding entry-xhttp 100-1000
for bad in '' TRUE False 0 1 null yes $'false\n'; do
    xhttpEdit 2 unchanged --xhttp-headers entry-xhttp "${bad}" false --preview
    xhttpEdit 2 unchanged --xhttp-headers entry-xhttp false "${bad}" --preview
done
xhttpEdit 2 unchanged --xhttp-headers entry-xhttp true --preview
xhttpEdit 2 unchanged --xhttp-headers entry-xhttp true false --xhttp-headers-clear entry-xhttp --preview
xhttpEdit 2 unchanged --xhttp-headers entry-xhttp true false --xhttp-padding entry-xhttp 64 --preview
xhttpEdit 2 unchanged --xhttp-headers entry-xhttp true false --spec "${XHTTP_SPEC}" --preview
xhttpEdit 2 unchanged --xhttp-headers entry-xhttp true false
for bad in 0 -1 1.5 01 1e2 2-1 0-1 1-02 2147483648 1-2147483648 $'1\n'; do
    xhttpEdit 2 unchanged --xhttp-xmux entry-xhttp "${bad}" 0 0 --preview
done
for mutation in \
    '(.core.protocols[] | select(.listener_id == "entry-xhttp") | .xhttp.xPaddingBytes) = 128' \
    '.core.protocols += [(.core.protocols[] | select(.id == 2) |
      .listener_id = "entry-new" | .public_port = 45443 | .xhttp.xPaddingBytes = 128)]'; do
    jq "${mutation}" "${root}/config/spec.json" >"${TEST_ROOT}/manual.json"
    chmod 0600 "${TEST_ROOT}/manual.json"
    xhttpEdit 15 unchanged --spec "${TEST_ROOT}/manual.json" --preview
done
for key in noGRPCHeader noSSEHeader; do
    for mutation in \
        '(.core.protocols[] | select(.listener_id == "entry-xhttp") | .xhttp[$key]) = false' \
        '.core.protocols += [(.core.protocols[] | select(.id == 2) |
          .listener_id = "entry-new" | .public_port = 45443 | .xhttp[$key] = false)]'; do
        jq --arg key "${key}" "${mutation}" "${root}/config/spec.json" >"${TEST_ROOT}/manual.json"
        chmod 0600 "${TEST_ROOT}/manual.json"
        xhttpEdit 15 unchanged --spec "${TEST_ROOT}/manual.json" --preview
    done
done
for bad in -1 1.5 01 2-1 2147483648 $'0-1\n'; do
    xhttpEdit 2 unchanged --xhttp-xmux entry-xhttp 1 "${bad}" 0 --preview
done
xhttpEdit 2 unchanged --xhttp-preset entry-xhttp unknown --preview
xhttpEdit 2 unchanged --xhttp-preset entry-xhttp daily --xhttp-xmux-clear entry-xhttp --preview
xhttpEdit 2 unchanged --xhttp-preset entry-xhttp daily --spec "${XHTTP_SPEC}" --preview
xhttpEdit 2 unchanged --xhttp-preset entry-xhttp daily --cdn-entry vless-ws edge.example.com --preview
xhttpEdit 2 unchanged --xhttp-preset entry-xhttp daily
for mutation in \
    '(.core.protocols[] | select(.listener_id == "entry-xhttp") | .xhttp.xmux) = $xmux' \
    '.core.protocols += [(.core.protocols[] | select(.id == 2) |
      .listener_id = "entry-new" | .public_port = 45443 | .xhttp.xmux = $xmux)]'; do
    jq --argjson xmux "${defaults}" "${mutation}" "${root}/config/spec.json" >"${TEST_ROOT}/manual.json"
    chmod 0600 "${TEST_ROOT}/manual.json"
    xhttpEdit 15 unchanged --spec "${TEST_ROOT}/manual.json" --preview
done
# 健康失败必须恢复完整旧部署，包括分享组、账号、累计流量和 TLS。
before=$(liveSnapshot)
rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
xhttpEdit 14 changed --xhttp-headers entry-xhttp true false --confirm PADM-DOCKER-EDIT
[[ -e "${FAKE_REALITY_FAIL_MARKER}" && "$(liveSnapshot)" == "${before}" ]] || fail 'XHTTP 健康失败未完整恢复'

for answer in n eof int term derive copy; do
    if [[ "${answer}" == derive || "${answer}" == copy ]]; then
        # 仅一个 Reality 来源才能证明派生不会借其它缺省入口绕过 XMUX 冻结。
        jq --argjson xmux "${defaults}" '
          .core.protocols |= map(select(.listener_id == "entry-xhttp") |
            .xhttp.xmux = $xmux | .xhttp.xPaddingBytes = "100-1000" |
            .xhttp.noGRPCHeader = true | .xhttp.noSSEHeader = false) |
          .core.secondary_type = null | .tls = null | .subscription.enabled = false |
          del(.accounts,.port_aliases)
        ' "${XHTTP_SPEC}" >"${TEST_ROOT}/single-xhttp.json"
        newState "xhttp-${answer}" "${TEST_ROOT}/single-xhttp.json"
        root=${PADM_DOCKER_INSTALL_DIR}
        commandArgs=(edit)
    else
        commandArgs=(edit --xhttp-headers entry-xhttp false true)
    fi
    before=$(snapshot)
    python3 - "${STDOUT}" "${answer}" bash -u "${CLI}" "${commandArgs[@]}" \
        "${ASSET_ARGS[@]}" <<'PY'
import errno
import os
import pty
import select
import signal
import subprocess
import sys
import time
from pathlib import Path

master, slave = pty.openpty()
process = subprocess.Popen(sys.argv[3:], stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
os.close(slave)
output = bytearray()
sent = False
editing = False
deadline = time.monotonic() + 60
try:
    while time.monotonic() < deadline:
        if select.select([master], [], [], 0.1)[0]:
            try:
                part = os.read(master, 65536)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                break
            if not part:
                break
            output.extend(part)
            if sys.argv[2] in ("derive", "copy") and not editing and "编辑项目: ".encode() in output:
                payload = b"11\nentry-xhttp\n\n\n45443\n8\n" if sys.argv[2] == "derive" \
                    else b"9\nentry-xhttp\n\n45443\n8\n"
                os.write(master, payload)
                editing = True
            if not sent and b"[y/N]: " in output:
                if sys.argv[2] in ("int", "term"):
                    os.kill(process.pid, signal.SIGINT if sys.argv[2] == "int" else signal.SIGTERM)
                else:
                    os.write(master, b"\x04" if sys.argv[2] == "eof" else
                             (b"y\n" if sys.argv[2] in ("derive", "copy") else b"n\n"))
                sent = True
        elif process.poll() is not None:
            break
    assert sent, output.decode(errors="replace")
    assert process.wait(timeout=10) == dict(int=130, term=143).get(sys.argv[2], 0), output.decode(errors="replace")
finally:
    if process.poll() is None:
        process.kill()
        process.wait()
    os.close(master)
    Path(sys.argv[1]).write_bytes(output)
PY
    xhttpClean
    if [[ "${answer}" == derive || "${answer}" == copy ]]; then
        expected_path=/padm/path-1
        [[ "${answer}" != derive ]] || expected_path=/entry-1xhttp
        jq -e --argjson xmux "${defaults}" --arg path "${expected_path}" '
          .core.protocols | length == 2 and all(.[]; .id == 2 and .xhttp.xmux == $xmux and
            .xhttp.xPaddingBytes == "100-1000" and
            .xhttp.noGRPCHeader == true and .xhttp.noSSEHeader == false and
            (.xhttp | has("noGRPCHeader") and has("noSSEHeader"))) and
          any(.[]; .listener_id == "entry-1" and .public_port == 45443 and
            .xhttp.mode == "auto" and .xhttp.path == $path)
        ' "${root}/config/spec.json" >/dev/null || fail '菜单复制或派生 XHTTP 丢失 XMUX/Padding/Header'
    else
        [[ "$(snapshot)" == "${before}" ]] || fail "XHTTP ${answer} 改变未提交部署"
    fi
done
jq '.core.protocols |= map(select(.id == 1)) | .core.secondary_type = null |
    .tls = null | .subscription.enabled = false | del(.accounts,.port_aliases)' \
    "${XHTTP_SPEC}" >"${TEST_ROOT}/no-xhttp.json"
newState xhttp-none "${TEST_ROOT}/no-xhttp.json"
root=${PADM_DOCKER_INSTALL_DIR}
runRead 0 no-xhttp-status dockerProtocolCommand xhttp-status
jq -e '.entries == []' "${STDOUT}" >/dev/null || fail '没有 XHTTP 入口时状态未返回空集合'
xhttpEdit 15 unchanged --xhttp-xmux-clear vless-reality --preview
xhttpEdit 15 unchanged --xhttp-padding-clear vless-reality --preview
xhttpEdit 15 unchanged --xhttp-headers-clear vless-reality --preview
printf 'docker-xhttp-regression-ok\n'
