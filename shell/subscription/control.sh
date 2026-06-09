#!/usr/bin/env bash

subscriptionRemoteControlSources() {
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateRead --arg groupId "${groupId}" '
      .groups[] | select(.id == $groupId) |
      [.sources[]? | select(.role != "main" and .enabled == true)]'
}

subscriptionRemoteDesiredUsers() {
    local sourceId=$1
    local groupId
    groupId=$(activeSubscriptionGroupId)
    subscriptionGroupsStateRead --arg groupId "${groupId}" --arg sourceId "${sourceId}" '
      .groups[] | select(.id == $groupId) |
      [.user_groups[]?
        | select(.enabled == true)
        | select((.allowed_sources | index($sourceId)) or (.allowed_sources | index("*")))
        | {id, name, account: ("sub_" + (.id | gsub("-"; "_"))), uuid: (.uuid // ""), traffic_limit_gb: (.traffic_limit_gb // 0)}]'
}

subscriptionRemoteControlUrl() {
    local source=$1
    local endpoint=$2
    subscriptionWireGuardControlUrl "${source}" "${endpoint}"
}

subscriptionRemoteControlToken() {
    local source=$1
    jq -r '.control_token // empty' <<<"${source}"
}

subscriptionRemoteSourceSelfReference() {
    local source=$1
    local sourceHost
    local selfHost
    sourceHost=$(jq -r '(.host // "") | ascii_downcase' <<<"${source}")
    selfHost=$(subscriptionWireGuardReadState | jq -r '.address // empty' | head -n 1)
    selfHost=$(subscriptionWireGuardAddressHost "${selfHost}")
    selfHost=$(tr 'A-Z' 'a-z' <<<"${selfHost}")
    [[ -n "${selfHost}" && "${sourceHost}" == "${selfHost}" ]]
}

subscriptionRemoteControlRequest() {
    local source=$1
    local endpoint=$2
    local payload=$3
    local token
    local url
    local maxTime
    local response
    local statusCode
    local body
    token=$(subscriptionRemoteControlToken "${source}")
    if [[ -z "${token}" ]]; then
        return 2
    fi
    url=$(subscriptionRemoteControlUrl "${source}" "${endpoint}")
    if [[ "${endpoint}" == "sync" ]]; then
        maxTime=180
    else
        maxTime=15
    fi
    response=$(curl -sS --connect-timeout 5 --max-time "${maxTime}" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${token}" \
        -X POST --data "${payload}" -w '\n%{http_code}' "${url}") || return 1
    statusCode=${response##*$'\n'}
    body=${response%$'\n'*}
    if ! body=$(jq -c . <<<"${body}" 2>/dev/null); then
        jq -n --arg statusCode "${statusCode}" '{ok:false, error:"invalid_response", error_detail:{type:"invalid_response", message:"远端响应不是合法 JSON"}, http_status: ($statusCode | tonumber? // 0)}'
        return 0
    fi
    if [[ ! "${statusCode}" =~ ^2 ]]; then
        body=$(jq -c --arg statusCode "${statusCode}" '
          if .ok == true then
            .ok = false | .error = (.error // "http_error")
          else
            .
          end | . + {http_status: ($statusCode | tonumber? // 0)}
        ' <<<"${body}") || return 1
    fi
    printf '%s\n' "${body}"
}

subscriptionRemoteControlPayload() {
    local source=$1
    local dryRun=$2
    local sourceId
    local users
    sourceId=$(jq -r '.id' <<<"${source}")
    users=$(subscriptionRemoteDesiredUsers "${sourceId}")
    jq -n --arg sourceId "${sourceId}" --arg groupId "$(activeSubscriptionGroupId)" --argjson dryRun "${dryRun}" --argjson users "${users}" '{version:1, group_id:$groupId, source_id:$sourceId, dry_run:$dryRun, desired_users:$users}'
}

subscriptionRemoteResponseErrorMessage() {
    local response=$1
    local errorMessage
    local httpStatus
    errorMessage=$(jq -r 'if ((.error_detail.message // "") | length) > 0 then .error_detail.message else (.error // "unknown_error") end' <<<"${response}" 2>/dev/null || echo unknown_error)
    httpStatus=$(jq -r '.http_status // empty' <<<"${response}" 2>/dev/null || true)
    if [[ -n "${httpStatus}" && "${httpStatus}" != "null" ]]; then
        errorMessage="${errorMessage} (HTTP ${httpStatus})"
    fi
    printf '%s\n' "${errorMessage}"
}

subscriptionRemoteControlHealth() {
    local source=$1
    local token
    local url
    local response
    local statusCode
    local body
    local errorMessage
    token=$(subscriptionRemoteControlToken "${source}")
    if [[ -z "${token}" ]]; then
        jq -n --arg id "$(jq -r '.id' <<<"${source}")" --arg name "$(jq -r '.name' <<<"${source}")" '{id:$id, name:$name, ok:false, status:"missing_token", error_detail:{type:"missing_token", message:"未配置控制 token"}}'
        return 0
    fi
    url=$(subscriptionRemoteControlUrl "${source}" health)
    response=$(curl -sS --connect-timeout 5 --max-time 15 -H "Authorization: Bearer ${token}" -w '\n%{http_code}' "${url}" 2>/dev/null) || {
        jq -n --arg id "$(jq -r '.id' <<<"${source}")" --arg name "$(jq -r '.name' <<<"${source}")" '{id:$id, name:$name, ok:false, status:"unreachable", error_detail:{type:"unreachable", message:"不可达或健康检查失败"}}'
        return 0
    }
    statusCode=${response##*$'\n'}
    body=${response%$'\n'*}
    if [[ "${statusCode}" == "200" ]] && jq -e '.ok == true' <<<"${body}" >/dev/null 2>&1; then
        jq -c --arg id "$(jq -r '.id' <<<"${source}")" --arg name "$(jq -r '.name' <<<"${source}")" '. + {id:$id, name:$name, ok:true}' <<<"${body}"
        return 0
    fi
    if [[ "${statusCode}" == "401" ]]; then
        jq -n --arg id "$(jq -r '.id' <<<"${source}")" --arg name "$(jq -r '.name' <<<"${source}")" --arg statusCode "${statusCode}" '{id:$id, name:$name, ok:false, status:"unauthorized", status_code:$statusCode, error_detail:{type:"unauthorized", message:"控制 token 验证失败"}}'
        return 0
    fi
    if jq -c . <<<"${body}" >/dev/null 2>&1; then
        errorMessage=$(subscriptionRemoteResponseErrorMessage "${body}")
        [[ -n "${statusCode}" && "${statusCode}" != "null" ]] && errorMessage="${errorMessage} (HTTP ${statusCode})"
        jq -n --arg id "$(jq -r '.id' <<<"${source}")" --arg name "$(jq -r '.name' <<<"${source}")" --arg statusCode "${statusCode}" --arg errorMessage "${errorMessage}" '{id:$id, name:$name, ok:false, status:"remote_error", status_code:$statusCode, error:$errorMessage, error_detail:{type:"remote_error", message:$errorMessage}}'
        return 0
    fi
    jq -n --arg id "$(jq -r '.id' <<<"${source}")" --arg name "$(jq -r '.name' <<<"${source}")" --arg statusCode "${statusCode}" '{id:$id, name:$name, ok:false, status:"remote_error", status_code:$statusCode}'
}

subscriptionRemoteInternalErrorResult() {
    local source=$1
    local mode=$2
    local id
    local name
    id=$(jq -r '.id // "unknown"' <<<"${source}" 2>/dev/null || echo unknown)
    name=$(jq -r '.name // .id // "unknown"' <<<"${source}" 2>/dev/null || echo unknown)
    if [[ "${mode}" == "health" ]]; then
        jq -n --arg id "${id}" --arg name "${name}" '{id:$id, name:$name, ok:false, status:"internal_error", error_detail:{type:"internal_error", message:"健康检查结果生成失败"}}'
    else
        jq -n --arg sourceId "${id}" '{source_id:$sourceId, status:"internal_error", dry_run:true, error_detail:{type:"internal_error", message:"远程同步计划生成失败"}}'
    fi
}

subscriptionRemoteWriteCheckedResult() {
    local source=$1
    local mode=$2
    local outputFile=$3
    local result
    if [[ "${mode}" == "health" ]]; then
        result=$(subscriptionRemoteControlHealth "${source}" 2>/dev/null) || result=
    else
        result=$(subscriptionRemoteSyncPlanForSource "${source}" 2>/dev/null) || result=
    fi
    if [[ -n "${result}" ]] && jq -e . <<<"${result}" >/dev/null 2>&1; then
        printf '%s\n' "${result}" >"${outputFile}"
    else
        subscriptionRemoteInternalErrorResult "${source}" "${mode}" >"${outputFile}"
    fi
}

subscriptionRemoteCollectCheckedResults() {
    local tmpDir=$1
    local mode=$2
    local sources=$3
    local -a sourceList=()
    local -a resultList=()
    local index
    local source
    local outputFile
    local result
    mapfile -t sourceList < <(jq -c '.[]' <<<"${sources}")
    if [[ "${#sourceList[@]}" == "0" ]]; then
        jq -n '[]'
        return 0
    fi
    for index in "${!sourceList[@]}"; do
        source=${sourceList[$index]}
        printf -v outputFile '%s/%06d.json' "${tmpDir}" "${index}"
        if [[ -f "${outputFile}" ]] && result=$(jq -c . "${outputFile}" 2>/dev/null); then
            resultList+=("${result}")
        else
            result=$(subscriptionRemoteInternalErrorResult "${source}" "${mode}") || return 1
            resultList+=("${result}")
        fi
    done
    printf '%s\n' "${resultList[@]}" | jq -s '.'
}

subscriptionRemoteControlHealthAll() {
    local source
    local sources
    local tmpDir
    local outputFile
    local index=0
    local pids=()
    sources=$(subscriptionRemoteControlSources)
    padmCreateTempPath tmpDir -d /tmp/padm-remote-health.XXXXXX || return 1
    while IFS= read -r source; do
        printf -v outputFile '%s/%06d.json' "${tmpDir}" "${index}"
        subscriptionRemoteWriteCheckedResult "${source}" health "${outputFile}" &
        pids+=("$!")
        index=$((index + 1))
    done < <(jq -c '.[]' <<<"${sources}")
    for pid in "${pids[@]}"; do
        wait "${pid}" 2>/dev/null || true
    done
    subscriptionRemoteCollectCheckedResults "${tmpDir}" health "${sources}"
    padmRemoveCleanupPath "${tmpDir}"
}

subscriptionRemoteSyncPlanForSource() {
    local source=$1
    local sourceId
    local payload
    local response
    local token
    local errorMessage

    sourceId=$(jq -r '.id' <<<"${source}")
    payload=$(subscriptionRemoteControlPayload "${source}" true)
    token=$(subscriptionRemoteControlToken "${source}")
    if subscriptionRemoteSourceSelfReference "${source}"; then
        jq -n --arg sourceId "${sourceId}" --argjson payload "${payload}" '{source_id:$sourceId, status:"self_reference", error_detail:{type:"self_reference", message:"服务器源指向当前订阅服务，已跳过以避免递归同步"}, dry_run:true, request:$payload}'
    elif [[ -z "${token}" ]]; then
        jq -n --arg sourceId "${sourceId}" --argjson payload "${payload}" '{source_id:$sourceId, status:"missing_token", error_detail:{type:"missing_token", message:"未配置控制 token"}, dry_run:true, request:$payload}'
    elif response=$(subscriptionRemoteControlRequest "${source}" sync "${payload}" 2>/dev/null); then
        if jq -e '.ok == true' <<<"${response}" >/dev/null 2>&1; then
            jq -n --arg sourceId "${sourceId}" --argjson payload "${payload}" --argjson response "${response}" '{source_id:$sourceId, status:"success", dry_run:true, request:$payload, response:$response}'
        else
            errorMessage=$(subscriptionRemoteResponseErrorMessage "${response}")
            jq -n --arg sourceId "${sourceId}" --arg errorMessage "${errorMessage}" --argjson payload "${payload}" --argjson response "${response}" '{source_id:$sourceId, status:"remote_error", error:$errorMessage, error_detail:{type:"remote_error", message:$errorMessage}, dry_run:true, request:$payload, response:$response}'
        fi
    else
        jq -n --arg sourceId "${sourceId}" --argjson payload "${payload}" '{source_id:$sourceId, status:"unreachable", error_detail:{type:"unreachable", message:"不可达或同步请求失败"}, dry_run:true, request:$payload}'
    fi
}

subscriptionRemoteSyncPlan() {
    local source
    local sources
    local tmpDir
    local outputFile
    local index=0
    local pids=()
    sources=$(subscriptionRemoteControlSources)
    padmCreateTempPath tmpDir -d /tmp/padm-remote-plan.XXXXXX || return 1
    while IFS= read -r source; do
        printf -v outputFile '%s/%06d.json' "${tmpDir}" "${index}"
        subscriptionRemoteWriteCheckedResult "${source}" plan "${outputFile}" &
        pids+=("$!")
        index=$((index + 1))
    done < <(jq -c '.[]' <<<"${sources}")
    for pid in "${pids[@]}"; do
        wait "${pid}" 2>/dev/null || true
    done
    subscriptionRemoteCollectCheckedResults "${tmpDir}" plan "${sources}"
    padmRemoveCleanupPath "${tmpDir}"
}

runSubscriptionRemoteSync() {
    local source
    local sources
    local sourceId
    local payload
    local response
    local token
    local errorMessage
    local failures='[]'
    sources=$(subscriptionRemoteControlSources)
    while IFS= read -r source; do
        sourceId=$(jq -r '.id' <<<"${source}")
        if subscriptionRemoteSourceSelfReference "${source}"; then
            setSubscriptionSourceSyncFailure "${sourceId}" self_reference "服务器源指向当前订阅服务，已跳过以避免递归同步"
            failures=$(jq --arg sourceId "${sourceId}" '. + ["远程服务器源 " + $sourceId + " 指向当前订阅服务，已跳过"]' <<<"${failures}")
            continue
        fi
        token=$(subscriptionRemoteControlToken "${source}")
        if [[ -z "${token}" ]]; then
            setSubscriptionSourceSyncFailure "${sourceId}" missing_token "未配置控制 token"
            failures=$(jq --arg sourceId "${sourceId}" '. + ["远程服务器源 " + $sourceId + " 未配置控制 token"]' <<<"${failures}")
            continue
        fi
        payload=$(subscriptionRemoteControlPayload "${source}" false)
        if response=$(subscriptionRemoteControlRequest "${source}" sync "${payload}" 2>/dev/null); then
            if jq -e '.ok == true' <<<"${response}" >/dev/null 2>&1; then
                setSubscriptionSourceSyncStatus "${sourceId}" success "$(jq -r 'if has("changed") then .changed else true end' <<<"${response}")" "$(jq -c '.plan // {create: [], remove: []}' <<<"${response}")"
            else
                errorMessage=$(subscriptionRemoteResponseErrorMessage "${response}")
                setSubscriptionSourceSyncFailure "${sourceId}" remote_error "${errorMessage}"
                failures=$(jq --arg sourceId "${sourceId}" --arg errorMessage "${errorMessage}" '. + ["远程服务器源 " + $sourceId + " 拒绝同步: " + $errorMessage]' <<<"${failures}")
            fi
        else
            setSubscriptionSourceSyncFailure "${sourceId}" unreachable "不可达或同步请求失败"
            failures=$(jq --arg sourceId "${sourceId}" '. + ["远程服务器源 " + $sourceId + " 不可达或同步请求失败"]' <<<"${failures}")
        fi
    done < <(jq -c '.[]' <<<"${sources}")
    echo "${failures}"
}

subscriptionGroupSyncInstallScript() {
    if [[ -f /etc/padm/install.sh ]]; then
        echo /etc/padm/install.sh
    else
        echo "${PROJECT_ROOT}/install.sh"
    fi
}


subscriptionControlPort() {
    echo 10086
}

subscriptionControlServerScript() {
    echo "$(subscriptionGroupsDir)/control_server.py"
}

subscriptionControlServiceFile() {
    echo /etc/systemd/system/padm-subscription-control.service
}

writeSubscriptionControlServer() {
    local serverScript
    local scriptPath
    local tmpFile
    serverScript=$(subscriptionControlServerScript)
    scriptPath=$(subscriptionGroupSyncInstallScript)
    padmCreateTempFileForTarget tmpFile "${serverScript}" control-server || return 1
    cat >"${tmpFile}" <<EOF || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
#!/usr/bin/env python3
import json
import os
import shutil
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

SCRIPT_PATH = "${scriptPath}"
PORT = $(subscriptionControlPort)
MAX_BODY_SIZE = 256 * 1024
try:
    SCRIPT_TIMEOUT = max(1, int(os.environ.get("PADM_CONTROL_SCRIPT_TIMEOUT", "180") or "180"))
except ValueError:
    SCRIPT_TIMEOUT = 180

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        return

    def respond(self, code, payload):
        data = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def token(self):
        auth = self.headers.get("Authorization", "")
        if auth.startswith("Bearer "):
            return auth[7:]
        return ""

    def endpoint(self):
        prefix = "/s/control/"
        if not self.path.startswith(prefix):
            return ""
        return self.path[len(prefix):].split("?", 1)[0]

    def parse_script_response(self, stdout, returncode):
        output = (stdout or "").strip()
        parsed = []
        decoder = json.JSONDecoder()
        if output:
            for index, char in enumerate(output):
                if char != "{":
                    continue
                try:
                    value, _ = decoder.raw_decode(output[index:])
                except json.JSONDecodeError:
                    continue
                if isinstance(value, dict):
                    parsed.append(value)
        body = None
        for candidate in reversed(parsed):
            if "ok" in candidate:
                body = candidate
                break
        if body is None and parsed:
            body = parsed[-1]
        if isinstance(body, dict):
            if returncode != 0:
                body = dict(body)
                body.setdefault("exit_code", returncode)
                if body.get("ok") is not False:
                    body["ok"] = False
                    body.setdefault("error", "script_failed")
                body.setdefault("error_detail", {"type": "script_failed", "message": f"脚本退出码 {returncode}"})
            return body
        if returncode != 0:
            return {"ok": False, "error": "script_failed", "exit_code": returncode, "error_detail": {"type": "script_failed", "message": f"脚本退出码 {returncode}"}}
        return {"ok": False, "error": "invalid_response", "error_detail": {"type": "invalid_response", "message": "脚本输出不是合法 JSON"}}

    def response_status(self, endpoint, body):
        if not isinstance(body, dict):
            return 500
        if body.get("ok") is True:
            return 200
        error = body.get("error", "")
        if error == "unauthorized":
            return 401
        if endpoint == "sync" and error in ("invalid_payload", "empty_payload"):
            return 400
        if endpoint == "health":
            return 503
        if error in ("script_timeout", "script_failed", "script_exec_failed", "invalid_response"):
            return 503
        if endpoint == "sync":
            return 503
        return 500

    def call_script(self, endpoint, payload=""):
        bash_bin = shutil.which("bash.exe") or shutil.which("bash") or "/bin/bash"
        cmd = [bash_bin, SCRIPT_PATH, "SubscriptionControl", endpoint]
        env = dict(os.environ)
        env["PADM_CONTROL_SERVER"] = "1"
        env["PADM_CONTROL_TOKEN"] = self.token()
        env["PADM_SKIP_REMOTE_REF_CHECK"] = "1"
        try:
            result = subprocess.run(cmd, input=payload, text=True, capture_output=True, timeout=SCRIPT_TIMEOUT, env=env)
        except subprocess.TimeoutExpired:
            return {"ok": False, "error": "script_timeout", "error_detail": {"type": "script_timeout", "message": "脚本执行超时"}}
        except OSError:
            return {"ok": False, "error": "script_exec_failed", "error_detail": {"type": "script_exec_failed", "message": "脚本无法执行"}}
        return self.parse_script_response(result.stdout, result.returncode)

    def do_GET(self):
        endpoint = self.endpoint()
        if endpoint != "health":
            self.respond(404, {"ok": False, "error": "not_found"})
            return
        body = self.call_script(endpoint)
        self.respond(self.response_status(endpoint, body), body)

    def do_POST(self):
        endpoint = self.endpoint()
        if endpoint != "sync":
            self.respond(404, {"ok": False, "error": "not_found"})
            return
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length > MAX_BODY_SIZE:
            self.respond(413, {"ok": False, "error": "payload_too_large"})
            return
        payload = self.rfile.read(length).decode() if length > 0 else ""
        body = self.call_script(endpoint, payload)
        self.respond(self.response_status(endpoint, body), body)

HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
EOF
    commitGeneratedFile "${tmpFile}" "${serverScript}" 755 || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

subscriptionControlHealthCheck() {
    local token=$1
    local port
    port=$(subscriptionControlPort)
    [[ -n "${token}" && -n "${port}" ]] || return 1
    PADM_CONTROL_HEALTH_TOKEN="${token}" PADM_CONTROL_HEALTH_PORT="${port}" python3 <<'PY'
import json
import os
import sys
import urllib.request

token = os.environ.get("PADM_CONTROL_HEALTH_TOKEN", "")
port = os.environ.get("PADM_CONTROL_HEALTH_PORT", "")
if not token or not port:
    sys.exit(1)
request = urllib.request.Request(
    f"http://127.0.0.1:{port}/s/control/health",
    headers={"Authorization": f"Bearer {token}"},
)
try:
    with urllib.request.urlopen(request, timeout=1) as response:
        payload = json.loads(response.read().decode() or "{}")
except Exception:
    sys.exit(1)
sys.exit(0 if payload.get("ok") is True else 1)
PY
}

installSubscriptionControlService() {
    local serviceFile
    local tmpFile
    local token
    local i
    if ! command -v python3 >/dev/null 2>&1 || ! command -v systemctl >/dev/null 2>&1; then
        return 0
    fi
    subscriptionControlEnsureToken || return 1
    token=$(subscriptionControlToken) || return 1
    [[ -n "${token}" ]] || return 1
    subscriptionGroupsSecureStateFiles || return 1
    writeSubscriptionControlServer || return 1
    serviceFile=$(subscriptionControlServiceFile)
    padmCreateTempFileForTarget tmpFile "${serviceFile}" service || return 1
    cat >"${tmpFile}" <<EOF || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
[Unit]
Description=padm subscription control
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/env python3 $(subscriptionControlServerScript)
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    commitGeneratedFile "${tmpFile}" "${serviceFile}" 644 || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    systemctl daemon-reload || return 1
    if systemctl is-active --quiet padm-subscription-control.service; then
        systemctl restart padm-subscription-control.service >/dev/null 2>&1 || return 1
    else
        systemctl enable --now padm-subscription-control.service >/dev/null 2>&1 || return 1
    fi
    for ((i = 0; i < 20; i++)); do
        if subscriptionControlHealthCheck "${token}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.25
    done
    return 1
}

subscriptionControlTokenFile() {
    echo "$(subscriptionGroupsDir)/control.token"
}

subscriptionControlEnsureToken() {
    local tokenFile
    local tokenValue
    tokenFile=$(subscriptionControlTokenFile)
    mkdir -p "$(dirname "${tokenFile}")" || return 1
    chmod 700 "$(dirname "${tokenFile}")" 2>/dev/null || true
    if [[ ! -s "${tokenFile}" ]]; then
        if command -v openssl >/dev/null 2>&1; then
            openssl rand -hex 32 >"${tokenFile}" || return 1
        else
            tokenValue=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 64 || true)
            [[ "${#tokenValue}" -ge 64 ]] || return 1
            printf '%s\n' "${tokenValue}" >"${tokenFile}" || return 1
        fi
    fi
    [[ -s "${tokenFile}" ]] || return 1
    chmod 600 "${tokenFile}" 2>/dev/null || true
}

subscriptionGroupsSecureStateFiles() {
    local groupsDir
    local groupsFile
    groupsDir=$(subscriptionGroupsDir)
    groupsFile=$(subscriptionGroupsFile)
    mkdir -p "${groupsDir}" || return 1
    chmod 700 "${groupsDir}" 2>/dev/null || true
    [[ -f "${groupsFile}" ]] && chmod 600 "${groupsFile}" 2>/dev/null || true
}

subscriptionControlToken() {
    local tokenFile
    tokenFile=$(subscriptionControlTokenFile)
    if [[ ! -f "${tokenFile}" ]]; then
        subscriptionControlEnsureToken
    fi
    tr -d '[:space:]' <"${tokenFile}"
}

subscriptionControlAuthorized() {
    local token=$1
    local currentToken
    currentToken=$(subscriptionControlToken 2>/dev/null || true)
    [[ -n "${currentToken}" && "${token}" == "${currentToken}" ]]
}

subscriptionControlValidateSyncPayload() {
    local payload=$1
    jq -e '
      def valid_id: type == "string" and length > 0 and test("^[A-Za-z0-9_-]+$");
      type == "object" and
      (.desired_users? | type == "array") and
      ((has("dry_run") | not) or (.dry_run | type == "boolean")) and
      all(.desired_users[]?; type == "object" and
        (.id | valid_id) and
        ((has("uuid") | not) or (.uuid | type == "string")) and
        ((has("name") | not) or (.name | type == "string")) and
        ((has("account") | not) or (.account | type == "string")) and
        ((has("traffic_limit_gb") | not) or ((.traffic_limit_gb | type) as $type | $type == "number" or $type == "string"))) and
      ([.desired_users[]?.id] | length) == ([.desired_users[]?.id] | unique | length)
    ' <<<"${payload}" >/dev/null 2>&1
}

subscriptionControlDesiredUsers() {
    local payload=$1
    jq '[.desired_users[]? | {id, uuid: (.uuid // "")}]' <<<"${payload}"
}

subscriptionControlSyncPlan() {
    local desiredUsers=$1
    local ids
    local desiredAccounts
    ids=$(jq -r '.[].id' <<<"${desiredUsers}") || return 1
    desiredAccounts=$(while IFS= read -r id; do
        [[ -n "${id}" ]] && subscriptionSyncAccountName "${id}"
    done <<<"${ids}" | sort -u) || return 1
    subscriptionSyncPlanFromAccounts "${desiredAccounts}"
}

subscriptionControlUpdateDesiredUserState() {
    local desiredUsers=$1
    local createAccounts=$2
    local createUsers
    local accountNames
    local accountName
    local id
    local uuid
    createUsers='[]'
    accountNames=$(jq -r '.[]' <<<"${createAccounts}") || return 1
    while IFS= read -r accountName; do
        [[ -n "${accountName}" ]] || continue
        id=$(subscriptionSyncAccountId "${accountName}")
        uuid=$(jq -r --arg id "${id}" '.[] | select(.id == $id) | .uuid // empty' <<<"${desiredUsers}") || return 1
        [[ -n "${uuid}" ]] || continue
        createUsers=$(jq --arg id "${id}" --arg uuid "${uuid}" '. + [{id:$id, uuid:$uuid}]' <<<"${createUsers}") || return 1
    done <<<"${accountNames}"
    if jq -e 'length > 0' <<<"${createUsers}" >/dev/null 2>&1; then
        subscriptionGroupsStateWrite --arg groupId "$(activeSubscriptionGroupId)" --argjson users "${createUsers}" '
          .groups |= map(if .id == $groupId then
            reduce $users[] as $user (.;
              if any(.user_groups[]?; .id == $user.id) then
                .user_groups |= map(if .id == $user.id then .uuid = $user.uuid else . end)
              else
                .user_groups += [{id:$user.id, name:$user.id, enabled:true, allowed_sources:["main"], traffic_limit_gb:0, token:"", uuid:$user.uuid}]
              end)
          else . end)'
    fi
}

subscriptionControlApplyAccountPlan() {
    local plan=$1
    local desiredUsers=$2
    local createAccounts
    local previousGroupsState
    subscriptionSyncValidateAccountPlan "${plan}" || return 1
    previousGroupsState=$(subscriptionGroupsStateRead -c '.') || return 1
    createAccounts=$(jq -c '.create' <<<"${plan}") || return 1
    if ! subscriptionControlUpdateDesiredUserState "${desiredUsers}" "${createAccounts}"; then
        subscriptionGroupsStateWrite --argjson previousGroupsState "${previousGroupsState}" '$previousGroupsState' >/dev/null 2>&1 || true
        return 1
    fi
    if ! subscriptionSyncApplyAccountPlanTransaction "${plan}"; then
        subscriptionGroupsStateWrite --argjson previousGroupsState "${previousGroupsState}" '$previousGroupsState' >/dev/null 2>&1 || true
        return 1
    fi
}

subscriptionControlRestoreAppliedPlan() {
    local previousGroupsState=$1
    local configBackupDir=$2
    local outputBackupDir=${3:-}
    subscriptionGroupsStateWrite --argjson previousGroupsState "${previousGroupsState}" '$previousGroupsState' >/dev/null 2>&1 || true
    if [[ -n "${configBackupDir}" ]]; then
        subscriptionSyncRestoreConfigBackups "${configBackupDir}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${outputBackupDir}" ]]; then
        subscriptionSyncRestoreSubscribeOutputBackups "${outputBackupDir}" >/dev/null 2>&1 || true
    fi
}

subscriptionControlRefreshPublishedSubscriptions() {
    subscribe false false >/dev/null 2>&1
}

subscriptionControlApplySync() {
    local payload=$1
    local dryRun
    local desiredUsers
    local plan
    local previousGroupsState
    local configBackupDir=
    local outputBackupDir=
    if ! subscriptionControlValidateSyncPayload "${payload}"; then
        jq -n '{ok:false, error:"invalid_payload", error_detail:{type:"invalid_payload", message:"同步请求体格式不正确"}}'
        return 1
    fi
    dryRun=$(jq -r 'if has("dry_run") then .dry_run else true end' <<<"${payload}")
    desiredUsers=$(subscriptionControlDesiredUsers "${payload}") || {
        jq -n '{ok:false, error:"invalid_payload", error_detail:{type:"invalid_payload", message:"同步请求体格式不正确"}}'
        return 1
    }
    if ! plan=$(subscriptionControlSyncPlan "${desiredUsers}"); then
        jq -n '{ok:false, error:"plan_failed", error_detail:{type:"plan_failed", message:"同步计划生成失败"}}'
        return 1
    fi
    if ! subscriptionSyncValidateAccountPlan "${plan}"; then
        if jq -e . <<<"${plan}" >/dev/null 2>&1; then
            jq -n --argjson plan "${plan}" '{ok:false, error:"plan_failed", error_detail:{type:"plan_failed", message:"同步计划格式无效"}, plan:$plan}'
        else
            jq -n '{ok:false, error:"plan_failed", error_detail:{type:"plan_failed", message:"同步计划格式无效"}}'
        fi
        return 1
    fi
    if jq -e '(.create | length == 0) and (.remove | length == 0)' <<<"${plan}" >/dev/null 2>&1; then
        jq -n --argjson plan "${plan}" --argjson dryRun "${dryRun}" '{ok:true, dry_run:$dryRun, changed:false, plan:$plan}'
        return 0
    fi
    if [[ "${dryRun}" == "true" ]]; then
        jq -n --argjson plan "${plan}" '{ok:true, dry_run:true, changed:true, plan:$plan}'
        return 0
    fi
    previousGroupsState=$(subscriptionGroupsStateRead -c '.') || return 1
    configBackupDir=$(subscriptionSyncCreateConfigBackups) || return 1
    outputBackupDir=$(subscriptionSyncCreateSubscribeOutputBackups) || { padmRemoveCleanupPath "${configBackupDir}"; return 1; }
    if ! subscriptionControlApplyAccountPlan "${plan}" "${desiredUsers}"; then
        padmRemoveCleanupPath "${configBackupDir}"
        padmRemoveCleanupPath "${outputBackupDir}"
        jq -n --argjson plan "${plan}" '{ok:false, changed:true, dry_run:false, error:"apply_plan_failed", error_detail:{type:"apply_plan_failed", message:"同步计划应用失败"}, plan:$plan}'
        return 1
    fi
    if [[ "${PADM_CONTROL_SERVER:-}" != "1" ]]; then
        if ! subscriptionSyncReconcileLocalServices; then
            subscriptionControlRestoreAppliedPlan "${previousGroupsState}" "${configBackupDir}" "${outputBackupDir}"
            padmRemoveCleanupPath "${configBackupDir}"
            padmRemoveCleanupPath "${outputBackupDir}"
            jq -n --argjson plan "${plan}" '{ok:false, changed:true, dry_run:false, error:"reconcile_failed", error_detail:{type:"reconcile_failed", message:"本机服务重建失败"}, plan:$plan}'
            return 1
        fi
    else
        if ! subscriptionControlRefreshPublishedSubscriptions; then
            subscriptionControlRestoreAppliedPlan "${previousGroupsState}" "${configBackupDir}" "${outputBackupDir}"
            padmRemoveCleanupPath "${configBackupDir}"
            padmRemoveCleanupPath "${outputBackupDir}"
            jq -n --argjson plan "${plan}" '{ok:false, changed:true, dry_run:false, error:"refresh_failed", error_detail:{type:"refresh_failed", message:"订阅发布刷新失败"}, plan:$plan}'
            return 1
        fi
    fi
    padmRemoveCleanupPath "${configBackupDir}"
    padmRemoveCleanupPath "${outputBackupDir}"
    jq -n --argjson plan "${plan}" '{ok:true, dry_run:false, changed:true, plan:$plan}'
}

handleSubscriptionControl() {
    local endpoint=${1:-}
    local token=${2:-${PADM_CONTROL_TOKEN:-}}
    local payload=${3:-}
    ensureSubscriptionGroupsState
    if ! subscriptionControlAuthorized "${token}"; then
        jq -n '{ok:false, error:"unauthorized", error_detail:{type:"unauthorized", message:"控制 token 验证失败"}}'
        return 1
    fi
    if [[ "${endpoint}" == "health" ]]; then
        jq -n --arg version "$(getScriptVersion)" '{ok:true, version:$version, capabilities:["health","sync"]}'
    elif [[ "${endpoint}" == "sync" ]]; then
        if [[ -z "${payload}" ]]; then
            payload=$(cat)
        fi
        if [[ -z "${payload}" ]]; then
            jq -n '{ok:false, error:"empty_payload", error_detail:{type:"empty_payload", message:"同步请求体为空"}}'
            return 1
        fi
        subscriptionControlApplySync "${payload}"
    else
        jq -n '{ok:false, error:"unknown_endpoint", error_detail:{type:"unknown_endpoint", message:"未知控制端点"}}'
        return 1
    fi
}
