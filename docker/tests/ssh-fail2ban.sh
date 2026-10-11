#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-ssh-fail2ban.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "docker-ssh-fail2ban-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
export PYTHONDONTWRITEBYTECODE=1
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

spec="${TEST_ROOT}/spec.json"
candidate="${TEST_ROOT}/candidate"
TEST_DEPLOYMENT_ROOT="${TEST_ROOT}/state"
mkdir -p "${TEST_DEPLOYMENT_ROOT}/config" "${candidate}/data/net"
python3 - "${PROJECT_ROOT}" "${spec}" <<'PY'
import json
import sys
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker

project, path = map(Path, sys.argv[1:])
spec = {
    "schema_version": 3,
    "release": {"version": "3.1.8", "manifest_sha256": "1" * 64, "signature_identity": "fixture"},
    "core": {"type": "xray", "secondary_type": None, "protocols": [{
        "id": 1, "core": "xray", "server": "reality.example.com", "public_port": 443,
        "address_families": ["ipv4"], "listener_id": "entry-reality", "name": "main",
        "uuid": "00000009-1111-4111-8111-000000000009",
        "reality": {"server_name": "reality.example.com", "target_host": "reality.example.com",
                    "target_port": 443, "private_key": "A" * 43,
                    "public_key": "B" * 43, "short_id": "1234abcd"}
    }]},
    "tls": None, "subscription": {"enabled": False, "token": "ssh-fail2ban-token"},
    "images": {name: f"ghcr.io/example/padm-{name}:test@sha256:" + "1" * 64
               for name in ("xray", "sing-box", "nginx", "ops", "net")},
    "host_integrations": [{
        "type": "fail2ban-ssh", "profile": "net-fail2ban-ssh",
        "firewall_rules": ["INPUT"], "devices": [], "schedules": [],
        "settings": {"unit": "ssh.service", "target": "192.0.2.10", "port": 2222,
                     "max_retry": 3, "find_time": 600, "ban_time": 3600}
    }],
}
schema = json.loads((project / "docker/contracts/configure.schema.json").read_text())
Draft202012Validator.check_schema(schema)
Draft202012Validator(schema, format_checker=FormatChecker()).validate(spec)
path.write_text(json.dumps(spec), encoding="utf-8")
PY
dockerConfigureSpecValidate "${spec}"
dockerGenerateSshFail2banConfig "${spec}" "${candidate}"
directory="${candidate}/config/net/ssh-fail2ban"
[[ "$(find "${directory}" -type f | wc -l)" == 4 &&
    ! -e "${candidate}/data/net/ssh-collector/auth.log" &&
    ! -e "${candidate}/data/net/ssh-collector/guard.json" ]]
grep -qxF 'failregex = ^padm-ssh source=<HOST>$' "${directory}/padm-ssh.conf"
grep -qxF 'logpath = /run/padm/ssh-collector/auth.log' "${directory}/padm.local"
grep -qxF 'dbfile = None' "${directory}/fail2ban.local"
grep -qxF 'allowipv6 = no' "${directory}/fail2ban.local"
grep -qxF 'actionstart_on_demand = false' "${directory}/padm-ssh-input.conf"
grep -qF '$PADM_FAIL2BAN_SSH_TOKEN' "${directory}/padm-ssh-input.conf"
[[ "$(grep -c '^enabled = true$' "${directory}/padm.local")" == 1 ]]
! grep -RqE 'DOCKER-USER|PADM_FAIL2BAN_CONTROL_TOKEN|padm-nginx|sqlite3' "${directory}"

# 同时核验日期剥离和锚定，原始 MESSAGE 或附加字段不能成为封禁输入。
printf '2026-10-12 10:00:00 padm-ssh source=198.51.100.20\n' >"${TEST_ROOT}/auth.log"
printf '2026-10-12 10:00:01 Failed password for root from 198.51.100.21 port 50000 ssh2\n' >>"${TEST_ROOT}/auth.log"
printf '2026-10-12 10:00:02 padm-ssh source=198.51.100.22 extra=true\n' >>"${TEST_ROOT}/auth.log"
fail2ban-regex "${TEST_ROOT}/auth.log" "${directory}/padm-ssh.conf" >"${TEST_ROOT}/regex.out"
grep -Eq 'Lines: 3 lines, 0 ignored, 1 matched, 2 missed' "${TEST_ROOT}/regex.out"

dockerGenerateCompose "${spec}" "${candidate}/compose.json"
jq -e '.services["net-fail2ban-ssh"] |
  .restart == "no" and .network_mode == "host" and .cap_add == ["NET_ADMIN"] and
  .profiles == ["net-fail2ban-ssh"] and
  .command == ["fail2ban-ssh","ssh.service","192.0.2.10","2222"] and
  .environment == {
    PADM_SSH_COLLECTOR_TOKEN:"${PADM_SSH_COLLECTOR_TOKEN:-}",
    PADM_SSH_COLLECTOR_UNIT:"ssh.service",PADM_SSH_COLLECTOR_TARGET:"192.0.2.10",
    PADM_SSH_COLLECTOR_PORT:"2222"} and
  .healthcheck.test == ["CMD","/usr/local/bin/padm-entrypoint","fail2ban-ssh-health"] and
  (.volumes | any(.source == "${PADM_NET_ROOT}/data/net/ssh-collector" and
    .target == "/run/padm/ssh-collector" and .read_only)) and
  (.volumes | all(.source | contains("/var/log/auth.log") | not))
' "${candidate}/compose.json" >/dev/null
mkdir -p "${TEST_ROOT}/bundle"
printf '%040d\n' 1 >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
dockerInstallRoot() { printf '%s\n' "${TEST_DEPLOYMENT_ROOT}"; }
dockerGenerateDeployment "${spec}" "${candidate}/deployment.json"
dockerDeploymentFileValidate "${candidate}/deployment.json"
python3 - "${PROJECT_ROOT}" "${candidate}/deployment.json" <<'PY'
import json
import sys
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker

project, path = map(Path, sys.argv[1:])
schema = json.loads((project / "docker/contracts/deployment.schema.json").read_text())
Draft202012Validator.check_schema(schema)
Draft202012Validator(schema, format_checker=FormatChecker()).validate(json.loads(path.read_text()))
PY

# 配置生成前拒绝越界输入，不留下半份可加载配置。
for mutation in \
    '.host_integrations[0].settings.unit = "ssh.socket"' \
    '.host_integrations[0].settings.unit = "ssh.service\n[sshd]"' \
    '.host_integrations[0].settings.target = "127.0.0.1"' \
    '.host_integrations[0].settings.target = "192.000.2.10"' \
    '.host_integrations[0].settings.target = "::ffff:192.0.2.10"' \
    '.host_integrations[0].settings.port = 0' \
    '.host_integrations[0].settings.port = "2222"' \
    '.host_integrations[0].settings.max_retry = 21' \
    '.host_integrations[0].settings.find_time = 59' \
    '.host_integrations[0].settings.ban_time = 604801' \
    '.host_integrations[0].settings.extra = true' \
    '.host_integrations[0].firewall_rules = ["DOCKER-USER"]' \
    '.host_integrations += [.host_integrations[0] | .type = "fail2ban-control"]'; do
    jq "${mutation}" "${spec}" >"${TEST_ROOT}/bad.json"
    if dockerSshFail2banSpecValidate "${TEST_ROOT}/bad.json" >/dev/null 2>&1; then
        printf 'SSH 校验误接受: %s\n' "${mutation}" >&2
        exit 1
    fi
    if dockerGenerateSshFail2banConfig "${TEST_ROOT}/bad.json" "${TEST_ROOT}/rejected" >/dev/null 2>&1; then
        printf 'SSH 配置生成误接受: %s\n' "${mutation}" >&2
        exit 1
    fi
    [[ ! -e "${TEST_ROOT}/rejected" ]]
done
jq '.host_integrations[0].settings.target = "2001:db8::10"' "${spec}" >"${TEST_ROOT}/ipv6.json"
dockerConfigureSpecValidate "${TEST_ROOT}/ipv6.json"
dockerGenerateSshFail2banConfig "${TEST_ROOT}/ipv6.json" "${TEST_ROOT}/ipv6"
grep -qxF 'allowipv6 = yes' "${TEST_ROOT}/ipv6/config/net/ssh-fail2ban/fail2ban.local"

# 无 jail 也不能绕过 collector 残留归属核验；未验证 owner 不执行停服。
jq '.host_integrations = []' "${spec}" >"${TEST_DEPLOYMENT_ROOT}/config/spec.json"
mkdir -p "${TEST_DEPLOYMENT_ROOT}/data/net/ssh-collector"
docker() { [[ "$1" == ps ]] || return 1; }
dockerSshCollectorStop() { printf 'collector-stop\n' >>"${TEST_ROOT}/stop.log"; return 7; }
status=0
dockerSshFail2banDisablePrepare "${TEST_DEPLOYMENT_ROOT}/config/spec.json" || status=$?
[[ "${status}" == 1 && "$(cat "${TEST_ROOT}/stop.log")" == collector-stop ]]
printf 'docker-ssh-fail2ban-contract-regression-ok\n'
