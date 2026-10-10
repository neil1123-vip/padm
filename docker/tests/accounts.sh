#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-accounts.XXXXXX")
trap '[[ "${PADM_TEST_KEEP:-0}" == 1 ]] || rm -rf -- "${TEST_ROOT}"' EXIT
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || {
    printf 'docker-accounts-regression requires Linux root\n' >&2
    exit 1
}
export PADM_DOCKER_SKIP_CHOWN=0
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
export PADM_DOCKER_SYSTEMD_DIR="${TEST_ROOT}/systemd"
mkdir -p "${PADM_DOCKER_SYSTEMD_DIR}"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

docker() {
    [[ "$*" != "ps -aq --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=net-fail2ban --filter label=com.docker.compose.oneoff=False" ]] || return 0
    command docker "$@"
}
fail() { printf 'docker-accounts-regression-fail: %s\n' "$*" >&2; exit 1; }
reject() {
    if "$@" >"${TEST_ROOT}/rejected.log" 2>&1; then fail "应拒绝: $*"; fi
}
mutateReject() {
    jq "$1" "${SPEC}" >"${TEST_ROOT}/invalid.json"
    reject dockerConfigureSpecValidate "${TEST_ROOT}/invalid.json"
}
generateRaw() {
    dockerGenerateXrayConfig "$1" "${TEST_ROOT}/$2-xray.json"
    dockerGenerateSingBoxConfig "$1" "${TEST_ROOT}/$2-sing-box.json"
}

SELF=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
ALICE=11111111-1111-4111-8111-111111111111
BOB=22222222-2222-4222-8222-222222222222
DISABLED=33333333-3333-4333-8333-333333333333
LEGACY="${TEST_ROOT}/legacy.json"
SPEC="${TEST_ROOT}/accounts.json"

# 16 个支持协议共用原自用账号，新增账号使用不同的稳定 ID 和认证 UUID。
jq -n --arg self "${SELF}" --arg alice "${ALICE}" --arg bob "${BOB}" --arg disabled "${DISABLED}" '
  def entry($id):
    {id:$id, core:(if [3,4,5,30,31] | index($id) != null then "sing-box" else "xray" end),
      listener_id:("entry-" + ($id | tostring)), server:"2001:db8::1",
      public_port:(30000+$id), address_families:["ipv4","ipv6"],
      name:("protocol-" + ($id | tostring)), uuid:$self} +
    if [1,2,26] | index($id) != null then
      {reality:{server_name:"reality.example.com",target_host:"reality.example.com",target_port:443,
        private_key:("A"*43),public_key:("B"*43),short_id:"1234abcd"}} +
      if $id == 2 then {xhttp:{path:"/account-xhttp",host:"reality.example.com",mode:"auto"}}
      elif $id == 26 then {grpc:{service_name:"account-grpc"}} else {} end
    elif [21,22,23] | index($id) != null then
      {(if $id == 23 then "httpupgrade" else "websocket" end):
        {domain:"tls.example.com",path:("account-path"+($id|tostring)),
          backend_port:(40000+$id),tls_port:(41000+$id)}}
    elif $id == 24 or $id == 25 then
      {grpc_tls:{domain:"tls.example.com",service_name:("service"+($id|tostring)),
        backend_port:(40000+$id),tls_port:(41000+$id)}}
    elif $id == 27 or $id == 29 then
      {fallback_tls:{domain:"tls.example.com",http_port:(42000+$id),http2_port:(43000+$id)}}
    elif $id == 28 then {trojan:{domain:"tls.example.com"}}
    elif $id == 3 then {hy2:{domain:"tls.example.com",bandwidth_mode:"bbr",
      up_mbps:100,down_mbps:50,obfs:null,masquerade:""}}
    elif $id == 4 then {anytls:{domain:"tls.example.com"}}
    elif $id == 5 then {server:"tls.example.com",naive:{domain:"tls.example.com"}}
    elif $id == 30 then {shadowsocks:{method:"2022-blake3-aes-128-gcm",
      server_password:"AAECAwQFBgcICQoLDA0ODw==",user_password:"+/v7+/v7+/v7+/v7+/v7+w=="}}
    else {tuic:{domain:"tls.example.com",congestion_control:"cubic",
      auth_timeout:"3s",heartbeat:"10s",zero_rtt_handshake:false}} end;
  [1,2,3,4,5,21,22,23,24,25,26,27,28,29,30,31] as $ids |
  {schema_version:3,
    release:{version:"3.1.8",manifest_sha256:("1"*64),signature_identity:"fixture"},
    core:{type:"xray",secondary_type:"sing-box",protocols:[$ids[] | entry(.)]},
    tls:{domain:"tls.example.com"},subscription:{enabled:true,token:"account-regression-token"},
    images:([ "xray","sing-box","nginx","ops","net" ] |
      map({key:.,value:("ghcr.io/example/padm-"+.+":test@sha256:"+("1"*64))}) | from_entries),
    host_integrations:[],
    accounts:[
      {id:$alice,name:"\u6d4b\u8bd5 A",enabled:true,uuid:"44444444-4444-4444-8444-444444444444",
        password:"Alice.-~@+=:Secret",shadowsocks_password:"AQEBAQEBAQEBAQEBAQEBAQ==",
        listeners:[$ids[] | "entry-"+tostring]},
      {id:$bob,name:"Bob",enabled:true,uuid:"55555555-5555-4555-8555-555555555555",
        password:"Bob.-~@+=:SecretPass",shadowsocks_password:null,
        listeners:["entry-1","entry-3","entry-5","entry-23","entry-31"]},
      {id:$disabled,name:"disabled",enabled:false,uuid:"66666666-6666-4666-8666-666666666666",
        password:"Disabled.SecretPass",shadowsocks_password:"AgICAgICAgICAgICAgICAg==",
        listeners:[$ids[] | "entry-"+tostring]}]}
' >"${SPEC}"
jq 'del(.accounts)' "${SPEC}" >"${LEGACY}"
dockerConfigureSpecValidate "${SPEC}" || fail '追加账号规格被拒绝'
dockerConfigureSpecValidate "${LEGACY}" || fail '旧规格被拒绝'
jq -e --slurpfile matrix "${PROJECT_ROOT}/docker/contracts/features.json" '
  [.core.protocols[].id] | sort ==
    ([$matrix[0].protocols[] | select(.status == "supported") | .id] | sort)
' "${SPEC}" >/dev/null || fail '账号测试没有覆盖完整支持协议集合'

# 精确字段、边界、重复、悬空引用和自用身份碰撞均在真实入口拒绝。
for mutation in \
    '.accounts = null' '.accounts = {}' '.accounts = []' \
    '.accounts += [.accounts[0]]' '.accounts[0].extra = true' \
    'del(.accounts[0].uuid)' '.accounts[0].enabled = 1' \
    '.accounts[0].id = "AAAAAAAA-aaaa-4aaa-8aaa-aaaaaaaaaaab"' \
    '.accounts[0].uuid = "AAAAAAAA-aaaa-4aaa-8aaa-aaaaaaaaaaab"' \
    '.accounts[0].id = "not-a-uuid"' '.accounts[0].name = ""' \
    '.accounts[0].name = ("a"*65)' '.accounts[0].name += "\n"' \
    '.accounts[0].name += "\u007f"' '.accounts[0].password = ("a"*15)' \
    '.accounts[0].password = ("a"*129)' '.accounts[0].password += "/"' \
    '.accounts[0].password += "\n"' '.accounts[0].listeners = []' \
    '.accounts[0].listeners = ["entry-missing"]' \
    '.accounts[0].listeners += [.accounts[0].listeners[0]]' \
    '.accounts[1].id = .accounts[0].id' '.accounts[1].uuid = .accounts[0].uuid' \
    '.accounts[1].password = .accounts[0].password' \
    '.accounts[2].shadowsocks_password = .accounts[0].shadowsocks_password' \
    '.accounts[0].shadowsocks_password = null' \
    '.accounts[1].shadowsocks_password = "AQEBAQEBAQEBAQEBAQEBAQ=="' \
    '.accounts[0].shadowsocks_password = "AQEBAQEBAQEBAQEBAQEBAx=="' \
    '.accounts[0].shadowsocks_password += "\n"' \
    '.accounts[0].id = .core.protocols[0].uuid' \
    '.accounts[0].uuid = .core.protocols[0].uuid' \
    '.accounts[0].password = .core.protocols[0].uuid' \
    '.accounts[0].shadowsocks_password = (.core.protocols[] | select(.id == 30) | .shadowsocks.user_password)' \
    '.accounts[0].shadowsocks_password = (.core.protocols[] | select(.id == 30) | .shadowsocks.server_password)'; do
    mutateReject "${mutation}"
done
for version in 1 2; do
    jq --argjson version "${version}" '.schema_version = $version |
      .core.protocols |= map(select(.id == 1 or .id == 21) | del(.core) |
        if $version == 1 then del(.listener_id) | del(.websocket.backend_port,.websocket.tls_port) else . end) |
      del(.core.secondary_type)' "${SPEC}" >"${TEST_ROOT}/invalid.json"
    reject dockerConfigureSpecValidate "${TEST_ROOT}/invalid.json"
done
for count in 256 257; do
    jq --argjson count "${count}" '.accounts = [range(0;$count) | . as $n |
      ("00000000-0000-4000-8000-" + ((100000000000+$n)|tostring)) as $id |
      {id:$id,uuid:$id,name:"bulk",enabled:true,password:("BulkPassword-"+($n|tostring)+"-End"),
        shadowsocks_password:null,listeners:["entry-1"]}]' "${SPEC}" >"${TEST_ROOT}/boundary.json"
    if [[ "${count}" == 256 ]]; then
        dockerConfigureSpecValidate "${TEST_ROOT}/boundary.json" || fail '256 个账号边界被拒绝'
    else reject dockerConfigureSpecValidate "${TEST_ROOT}/boundary.json"; fi
done
jq '.accounts = [.accounts[1]]' "${SPEC}" >"${TEST_ROOT}/unassigned.json"
dockerConfigureSpecValidate "${TEST_ROOT}/unassigned.json" || fail '未关联分享账号的自用入口被拒绝'
jq '.accounts |= map(.enabled = false)' "${SPEC}" >"${TEST_ROOT}/disabled.json"
dockerConfigureSpecValidate "${TEST_ROOT}/disabled.json" || fail '全禁用分享账号规格被拒绝'
for version in 1 2; do
    jq --argjson version "${version}" '.schema_version = $version |
      .core.protocols |= map(select(.id == 1 or .id == 21) | del(.core) |
        if $version == 1 then del(.listener_id) | del(.websocket.backend_port,.websocket.tls_port) else . end) |
      del(.core.secondary_type)' "${LEGACY}" >"${TEST_ROOT}/old.json"
    dockerConfigureSpecMigrate "${TEST_ROOT}/old.json" "${TEST_ROOT}/migrated.json"
    jq -e '.schema_version == 3 and (has("accounts") | not)' "${TEST_ROOT}/migrated.json" >/dev/null ||
        fail '迁移旧规格自动添加账号'
done

COMPAT="${TEST_ROOT}/compat/docker/contracts"
mkdir -p "${COMPAT}"
cp "${PROJECT_ROOT}/docker/contracts/"{configure.schema.json,features.json} "${COMPAT}/"
dockerBundleSupportsSpec "${TEST_ROOT}/compat" "${SPEC}" || fail '当前 bundle 拒绝账号规格'
jq 'del(."x-padm-accounts")' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" >"${COMPAT}/configure.schema.json"
reject dockerBundleSupportsSpec "${TEST_ROOT}/compat" "${SPEC}"
dockerBundleSupportsSpec "${TEST_ROOT}/compat" "${LEGACY}" || fail '旧 bundle 拒绝无 accounts 规格'

generateRaw "${LEGACY}" legacy
generateRaw "${SPEC}" accounts
# 不从实现文本找字符串：逐入口比较原自用模板和追加账号认证对象。
assertRaw() {
    local core=$1 spec=$2 prefix=$3 legacy=$4
    jq -e --arg core "${core}" --slurpfile spec "${spec}" --slurpfile legacy "${TEST_ROOT}/${legacy}-${core}.json" '
      def users: if $core == "xray" then .settings.clients else .users end;
      all(.inbounds[]; . as $inbound |
        [$spec[0].accounts[] | select(.listeners | index($inbound.tag) != null)] as $accounts |
        [$legacy[0].inbounds[] | select(.tag == $inbound.tag) | users][0] as $self |
        (users[0:1]) == $self and (users | length) == (1+($accounts|length)) and
        all($accounts[]; . as $account |
          [$inbound | users[] | select(.padm_account == $account.id)] as $found |
          ($found | length) == 1 and
          ($found[0] | .padm_enabled == $account.enabled and .padm_name == $account.name and
            (if $core == "xray" then
              .email == $account.name and
              if $inbound.protocol == "trojan" then .password == $account.password and (has("id")|not)
              else .id == $account.uuid and (has("password")|not) end
             elif $inbound.type == "naive" then
              .username == $account.id and .password == $account.password and (has("name")|not)
             elif $inbound.type == "shadowsocks" then
              .name == $account.name and .password == $account.shadowsocks_password and (has("uuid")|not)
             elif $inbound.type == "tuic" then
              .name == $account.name and .uuid == $account.uuid and .password == $account.password
             elif $inbound.type == "vless" or $inbound.type == "vmess" then
              .name == $account.name and .uuid == $account.uuid and (has("password")|not)
             else .name == $account.name and .password == $account.password and (has("uuid")|not) end))))
    ' "${TEST_ROOT}/${prefix}-${core}.json" >/dev/null || fail "${core}: 自用保留或认证形状错误"
}
for core in xray sing-box; do
    assertRaw "${core}" "${SPEC}" accounts legacy
    jq -e 'all(.. | objects; (has("padm_account") or has("padm_enabled") or has("padm_name")) | not)' \
        "${TEST_ROOT}/legacy-${core}.json" >/dev/null || fail '旧配置加入账号标记'
done
# 共享协议的另一个支持核心同样验证，不只验证每个协议的默认核心。
jq '(.core.protocols[] | select(.id == 1 or .id == 23 or .id == 26 or .id == 28) | .core) = "sing-box"' \
    "${SPEC}" >"${TEST_ROOT}/alternate.json"
jq 'del(.accounts)' "${TEST_ROOT}/alternate.json" >"${TEST_ROOT}/alternate-legacy.json"
dockerConfigureSpecValidate "${TEST_ROOT}/alternate.json"
generateRaw "${TEST_ROOT}/alternate-legacy.json" alternate-legacy
generateRaw "${TEST_ROOT}/alternate.json" alternate
for core in xray sing-box; do
    assertRaw "${core}" "${TEST_ROOT}/alternate.json" alternate alternate-legacy
done
jq -e --slurpfile legacy "${TEST_ROOT}/legacy-sing-box.json" '
  (.inbounds[] | select(.type == "shadowsocks") | .password) ==
    ($legacy[0].inbounds[] | select(.type == "shadowsocks") | .password)
' "${TEST_ROOT}/accounts-sing-box.json" >/dev/null || fail '追加账号改变 SS 服务器密钥'

assertLinks() {
    dockerGenerateSubscription "$1" "${TEST_ROOT}/links"
    python3 - "$1" "${TEST_ROOT}/links" <<'PY'
import base64
import json
import sys
from urllib.parse import parse_qs, unquote, urlsplit

spec = json.load(open(sys.argv[1], encoding="utf-8"))
lines = open(sys.argv[2], encoding="utf-8").read().splitlines()
expected = []
for entry in spec["core"]["protocols"]:
    expected.append((entry, None))
    expected.extend((entry, account) for account in spec.get("accounts", [])
                    if account["enabled"] and entry["listener_id"] in account["listeners"])
assert len(lines) == len(expected), (len(lines), len(expected))
for line, (entry, account) in zip(lines, expected):
    protocol = entry["id"]
    uuid = account["uuid"] if account else entry["uuid"]
    password = account["password"] if account else entry["uuid"]
    account_id = account["id"] if account else entry["uuid"]
    name = entry["name"] + ("-" + account["name"] if account else "")
    port = entry["public_port"]
    if spec.get("reality_stream") and entry["listener_id"] in (
            spec["reality_stream"]["listener_id"], spec["reality_stream"].get("website_listener_id")):
        port = 443
    if protocol in (22, 23):
        assert line.startswith("vmess://")
        node = json.loads(base64.b64decode(line.removeprefix("vmess://")))
        transport = entry["websocket"] if protocol == 22 else entry["httpupgrade"]
        assert (node["id"], node["ps"], node["add"], int(node["port"])) == (uuid, name, entry["server"], port)
        assert (node["net"], node["sni"], node["host"], node["path"]) == (
            "ws" if protocol == 22 else "httpupgrade", transport["domain"], transport["domain"],
            "/" + transport["path"] + ("ws" if protocol == 22 else ""))
        continue
    parsed = urlsplit(line)
    query = parse_qs(parsed.query)
    assert (parsed.hostname, parsed.port, unquote(parsed.fragment)) == (entry["server"], port, name), line
    credentials = (unquote(parsed.username or ""), unquote(parsed.password or ""))
    if protocol == 30:
        user_key = account["shadowsocks_password"] if account else entry["shadowsocks"]["user_password"]
        assert parsed.scheme == "ss" and credentials == (
            entry["shadowsocks"]["method"], entry["shadowsocks"]["server_password"] + ":" + user_key), line
    elif protocol == 5:
        assert parsed.scheme == "naive+https" and credentials == (account_id, password), line
    elif protocol == 31:
        assert parsed.scheme == "tuic" and credentials == (uuid, password), line
    else:
        credential = password if protocol in (3, 4, 25, 28, 29) else uuid
        assert credentials == (credential, ""), line
    if protocol in (1, 2, 26):
        assert query["sni"] == [entry["reality"]["server_name"]] and query["security"] == ["reality"], line
        assert query["type"] == [{1: "tcp", 2: "xhttp", 26: "grpc"}[protocol]], line
    elif protocol != 5 and protocol != 30:
        tls = next(entry[key] for key in ("websocket", "grpc_tls", "fallback_tls", "trojan", "hy2", "anytls", "tuic")
                   if key in entry)
        assert query["sni"] == [tls["domain"]], line
    if protocol == 21:
        assert query["type"] == ["ws"] and query["path"] == ["/" + entry["websocket"]["path"] + "ws"], line
    elif protocol in (24, 25, 26):
        transport = entry.get("grpc_tls", entry.get("grpc"))
        assert query["serviceName"] == [transport["service_name"]] and query["type"] == ["grpc"], line
    elif protocol == 2:
        assert query["path"] == [entry["xhttp"]["path"]] and query["host"] == [entry["xhttp"]["host"]], line
PY
}
assertLinks "${LEGACY}"
cp "${TEST_ROOT}/links" "${TEST_ROOT}/legacy-links"
assertLinks "${SPEC}"
assertLinks "${TEST_ROOT}/alternate.json"
assertLinks "${TEST_ROOT}/disabled.json"
cmp -s "${TEST_ROOT}/links" "${TEST_ROOT}/legacy-links" || fail '全禁用分享改变原自用链接'
jq '.core.secondary_type = null | .core.protocols |= map(select(.id == 1 or .id == 21)) |
  .accounts |= map(.listeners = ["entry-1","entry-21"] | .shadowsocks_password = null) |
  .reality_stream = {listener_id:"entry-1",website_listener_id:"entry-21"}' "${SPEC}" >"${TEST_ROOT}/stream.json"
dockerConfigureSpecValidate "${TEST_ROOT}/stream.json"
assertLinks "${TEST_ROOT}/stream.json"

# 双核心采样只替换外部统计 API，实际稳定 ID 累加和状态写入由生产函数执行。
dockerInitializeStateRoot
dockerInstallBundle "${PROJECT_ROOT}" "$(printf 'a%.0s' {1..40})"
mkdir -p "${PADM_DOCKER_INSTALL_DIR}/secrets/tls"
printf 'fixture certificate\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/tls.example.com.crt"
printf 'fixture key\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/tls.example.com.key"
dockerCreateConfigurationCandidate
CANDIDATE=${DOCKER_CONFIG_CANDIDATE}
dockerGenerateCandidate "${SPEC}" "${CANDIDATE}"
cmp -s "${SPEC}" "${CANDIDATE}/config/spec.json" || fail '候选没有逐字保存 accounts 规格'
for core in xray sing-box; do
    cmp -s "${TEST_ROOT}/accounts-${core}.json" "${CANDIDATE}/config/${core}/users.base" ||
        fail '候选丢失禁用账号或改变 raw 认证'
    [[ "$(stat -c '%u:%g:%a' "${CANDIDATE}/config/${core}/users.base")" == 0:0:600 ]] ||
        fail '候选 users.base 不是 root 私有'
done
[[ "$(stat -c '%u:%g:%a' "${CANDIDATE}/config/spec.json")" == 0:0:600 ]] ||
    fail '候选 accounts 规格不是 root 私有'
dockerBackupConfiguration
dockerInstallCandidate "${CANDIDATE}" "${DOCKER_CONFIG_BACKUP}"
dockerCleanupConfigurationCandidate
DOCKER_CONFIG_SWITCHED=0
for core in xray sing-box; do
    dockerTrafficAccounts "${core}" | jq -e --arg self "${SELF}" --slurpfile spec "${SPEC}" '
      ([.[].account] | sort) == ([$self] + [$spec[0].accounts[].id] | sort) and
      all(.[]; . as $found | if .account == $self then true else
        any($spec[0].accounts[]; .id == $found.account and .name == $found.name) end)
    ' >/dev/null || fail "${core}: 统计使用凭据而非稳定 ID 或丢失 disabled"
    jq -e --arg disabled "${DISABLED}" '
      all(.. | objects; (has("padm_account") or has("padm_enabled") or has("padm_name")) | not) and
      all(.inbounds[]; all((.settings.clients // .users // [])[];
        (.email // .name // .username) != $disabled))
    ' "${PADM_DOCKER_INSTALL_DIR}/config/${core}/config.json" >/dev/null ||
        fail "${core}: 运行配置保留标记或 disabled"
done
SAMPLE=1
dockerTrafficContainerState() { jq -cn --arg core "$1" '{id:$core,started_at:"stable",pid:1234}'; }
dockerTrafficQuery() {
    local up=100 down=200
    [[ "$1" == xray ]] || { up=10; down=20; }
    jq -cn --arg id "${ALICE}" --argjson up "$((up*SAMPLE))" --argjson down "$((down*SAMPLE))" '
      {stat:[{name:("user>>>"+$id+">>>traffic>>>uplink"),value:$up},
             {name:("user>>>"+$id+">>>traffic>>>downlink"),value:$down}]}'
}
dockerTrafficSnapshot
STATE="${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json"
jq -e --arg id "${ALICE}" '.accounts[$id] |
  .upload == 110 and .download == 220 and (.baseline|keys) == ["sing-box","xray"]' "${STATE}" >/dev/null ||
    fail '双核心共享账号未累加'
dockerTrafficSnapshot
jq -e --arg id "${ALICE}" '.accounts[$id].upload == 110 and .accounts[$id].download == 220' "${STATE}" >/dev/null ||
    fail '相同采样重复累计'
cp "${STATE}" "${TEST_ROOT}/before-flow"

# 同一稳定 ID 轮换 UUID、密码和入口关联，不改原累计；失败恢复保留完整旧规格。
dockerBackupConfiguration
BACKUP=${DOCKER_CONFIG_BACKUP}
jq '.accounts[0].uuid = "77777777-7777-4777-8777-777777777777" |
  .accounts[0].password = "Rotated.SecretPass" |
  .accounts[1].listeners = ["entry-21","entry-4","entry-5","entry-31"]' "${SPEC}" >"${TEST_ROOT}/rotated.json"
dockerConfigureSpecValidate "${TEST_ROOT}/rotated.json"
dockerCreateConfigurationCandidate
DOCKER_CONFIG_BACKUP=${BACKUP}
CANDIDATE=${DOCKER_CONFIG_CANDIDATE}
dockerGenerateCandidate "${TEST_ROOT}/rotated.json" "${CANDIDATE}"
cmp -s "${STATE}" "${TEST_ROOT}/before-flow" || fail '候选生成修改累计'
dockerInstallCandidate "${CANDIDATE}" "${BACKUP}"
dockerCleanupConfigurationCandidate
cmp -s "${TEST_ROOT}/rotated.json" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" ||
    fail '轮换安装没有保存完整 accounts'
assertLinks "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
SAMPLE=2
dockerTrafficSnapshot
jq -e --arg id "${ALICE}" '.accounts[$id] | .upload == 220 and .download == 440' "${STATE}" >/dev/null ||
    fail '轮换凭据改变稳定 ID 累计'
cp "${STATE}" "${TEST_ROOT}/latest-flow"
dockerComposeRun() { printf '%s\n' "$*" >>"${TEST_ROOT}/compose.log"; }
dockerComposeExecute() {
    [[ "$*" == down ]] || fail "意外恢复启停参数: $*"
    dockerComposeRun "$@"
}
dockerRenewalScheduleInstall() { :; }
dockerRestoreConfiguration
cmp -s "${SPEC}" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" || fail '恢复没有保留原 accounts 规格'
cmp -s "${STATE}" "${TEST_ROOT}/latest-flow" || fail '恢复回退最新累计'
for core in xray sing-box; do
    cmp -s "${TEST_ROOT}/accounts-${core}.json" "${PADM_DOCKER_INSTALL_DIR}/config/${core}/users.base" ||
        fail '恢复没有保留原 raw 账号'
done

# 新账号关闭不影响自用；SS/Naive 所有自用及分享账号耗尽时必须移除入站。
quota=$(jq -cn --arg self "${SELF}" --slurpfile spec "${SPEC}" '
  {schema_version:1,accounts:([$self] + [$spec[0].accounts[].id] |
    map({key:.,value:{name:"quota",upload:1,download:0,limit_bytes:1,baseline:{}}}) | from_entries)}')
for core in xray sing-box; do
    base="${PADM_DOCKER_INSTALL_DIR}/config/${core}/users.base"
    dockerTrafficRender "${core}" "${base}" "${quota}" >"${TEST_ROOT}/quota-${core}.json"
    jq -e --arg core "${core}" '
      all(.inbounds[]; (.settings.clients // .users // []) | length == 0) and
      (if $core == "sing-box" then all(.inbounds[]; .type != "shadowsocks" and .type != "naive") else true end)
    ' "${TEST_ROOT}/quota-${core}.json" >/dev/null || fail "${core}: 额度未关闭账号或 SS/Naive 空用户入站残留"
    jq '
      .inbounds |= map(if .settings.clients != null then .settings.clients |= map(
        if has("padm_account") then .padm_enabled = false else . end)
        elif .users != null then .users |= map(
          if has("padm_account") then .padm_enabled = false else . end) else . end)
    ' "${base}" >"${TEST_ROOT}/disabled-base.json"
    dockerTrafficRender "${core}" "${TEST_ROOT}/disabled-base.json" '{"schema_version":1,"accounts":{}}' \
        >"${TEST_ROOT}/disabled-${core}.json"
    dockerTrafficRender "${core}" "${TEST_ROOT}/legacy-${core}.json" '{"schema_version":1,"accounts":{}}' \
        >"${TEST_ROOT}/legacy-runtime-${core}.json"
    if [[ "${core}" == sing-box ]]; then
        jq 'del(.experimental.v2ray_api.stats.users)' "${TEST_ROOT}/disabled-${core}.json" >"${TEST_ROOT}/compare-disabled"
        jq 'del(.experimental.v2ray_api.stats.users)' "${TEST_ROOT}/legacy-runtime-${core}.json" >"${TEST_ROOT}/compare-legacy"
    else
        cp "${TEST_ROOT}/disabled-${core}.json" "${TEST_ROOT}/compare-disabled"
        cp "${TEST_ROOT}/legacy-runtime-${core}.json" "${TEST_ROOT}/compare-legacy"
    fi
    cmp -s "${TEST_ROOT}/compare-disabled" "${TEST_ROOT}/compare-legacy" ||
        fail "${core}: 禁用分享账号改变自用认证"
done
[[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 -name '.candidate.*' -print -quit)" ]] ||
    fail '回归遗留候选'
printf 'docker-accounts-regression-ok\n'
