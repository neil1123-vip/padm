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
    jq -r --arg endpoint "${endpoint}" '(.scheme + "://" + .host + ":" + (.port | tostring) + "/s/control/" + $endpoint)' <<<"${source}"
}

subscriptionRemoteControlToken() {
    local source=$1
    jq -r '.control_token // empty' <<<"${source}"
}

subscriptionRemoteSourceSelfReference() {
    local source=$1
    local sourceHost
    local sourcePort
    local selfHost
    sourceHost=$(jq -r '(.host // "") | ascii_downcase' <<<"${source}")
    sourcePort=$(jq -r '.port // 0 | tostring' <<<"${source}")
    if [[ -z "${subscribePort:-}" ]]; then
        readNginxSubscribe
    fi
    [[ -n "${subscribePort:-}" && "${sourcePort}" == "${subscribePort}" ]] || return 1
    for selfHost in "${currentHost:-}" "${subscribeDomain:-}"; do
        selfHost=$(tr 'A-Z' 'a-z' <<<"${selfHost}")
        [[ -n "${selfHost}" && "${sourceHost}" == "${selfHost}" ]] && return 0
    done
    [[ "${sourceHost}" == "127.0.0.1" || "${sourceHost}" == "localhost" ]]
}

subscriptionRemoteControlRequest() {
    local source=$1
    local endpoint=$2
    local payload=$3
    local token
    local url
    local maxTime
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
    curl -fsSL --connect-timeout 5 --max-time "${maxTime}" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${token}" \
        -X POST --data "${payload}" "${url}"
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

subscriptionRemoteControlHealth() {
    local source=$1
    local token
    local url
    local response
    local statusCode
    local body
    token=$(subscriptionRemoteControlToken "${source}")
    if [[ -z "${token}" ]]; then
        jq -n --arg id "$(jq -r '.id' <<<"${source}")" --arg name "$(jq -r '.name' <<<"${source}")" '{id:$id, name:$name, ok:false, status:"missing_token"}'
        return 0
    fi
    url=$(subscriptionRemoteControlUrl "${source}" health)
    response=$(curl -sS --connect-timeout 5 --max-time 15 -H "Authorization: Bearer ${token}" -w '\n%{http_code}' "${url}" 2>/dev/null) || {
        jq -n --arg id "$(jq -r '.id' <<<"${source}")" --arg name "$(jq -r '.name' <<<"${source}")" '{id:$id, name:$name, ok:false, status:"unreachable"}'
        return 0
    }
    statusCode=${response##*$'\n'}
    body=${response%$'\n'*}
    if [[ "${statusCode}" == "200" ]] && jq -e '.ok == true' <<<"${body}" >/dev/null 2>&1; then
        jq -c --arg id "$(jq -r '.id' <<<"${source}")" --arg name "$(jq -r '.name' <<<"${source}")" '. + {id:$id, name:$name, ok:true}' <<<"${body}"
        return 0
    fi
    if [[ "${statusCode}" == "401" ]]; then
        jq -n --arg id "$(jq -r '.id' <<<"${source}")" --arg name "$(jq -r '.name' <<<"${source}")" '{id:$id, name:$name, ok:false, status:"unauthorized"}'
        return 0
    fi
    jq -n --arg id "$(jq -r '.id' <<<"${source}")" --arg name "$(jq -r '.name' <<<"${source}")" --arg statusCode "${statusCode}" '{id:$id, name:$name, ok:false, status:"remote_error", status_code:$statusCode}'
}

subscriptionRemoteControlHealthAll() {
    local source
    local sources
    local tmpDir
    local outputFile
    local index=0
    local pids=()
    sources=$(subscriptionRemoteControlSources)
    tmpDir=$(mktemp -d /tmp/padm-remote-health.XXXXXX) || return 1
    while IFS= read -r source; do
        printf -v outputFile '%s/%06d.json' "${tmpDir}" "${index}"
        subscriptionRemoteControlHealth "${source}" >"${outputFile}" &
        pids+=("$!")
        index=$((index + 1))
    done < <(jq -c '.[]' <<<"${sources}")
    for pid in "${pids[@]}"; do
        wait "${pid}" 2>/dev/null || true
    done
    jq -s '.' "${tmpDir}"/*.json 2>/dev/null || jq -n '[]'
    rm -rf "${tmpDir}"
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
            errorMessage=$(jq -r '.error // "unknown_error"' <<<"${response}" 2>/dev/null || echo unknown_error)
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
    tmpDir=$(mktemp -d /tmp/padm-remote-plan.XXXXXX) || return 1
    while IFS= read -r source; do
        printf -v outputFile '%s/%06d.json' "${tmpDir}" "${index}"
        subscriptionRemoteSyncPlanForSource "${source}" >"${outputFile}" &
        pids+=("$!")
        index=$((index + 1))
    done < <(jq -c '.[]' <<<"${sources}")
    for pid in "${pids[@]}"; do
        wait "${pid}" 2>/dev/null || true
    done
    jq -s '.' "${tmpDir}"/*.json 2>/dev/null || jq -n '[]'
    rm -rf "${tmpDir}"
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
                errorMessage=$(jq -r '.error // "unknown_error"' <<<"${response}" 2>/dev/null || echo unknown_error)
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
    serverScript=$(subscriptionControlServerScript)
    scriptPath=$(subscriptionGroupSyncInstallScript)
    mkdir -p "$(dirname "${serverScript}")"
    cat >"${serverScript}" <<EOF
#!/usr/bin/env python3
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

SCRIPT_PATH = "${scriptPath}"
PORT = $(subscriptionControlPort)
MAX_BODY_SIZE = 256 * 1024

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

    def call_script(self, endpoint, payload=""):
        cmd = ["/bin/bash", SCRIPT_PATH, "SubscriptionControl", endpoint]
        if payload:
            cmd.append(payload)
        env = dict(os.environ)
        env["PADM_CONTROL_SERVER"] = "1"
        env["PADM_CONTROL_TOKEN"] = self.token()
        result = subprocess.run(cmd, text=True, capture_output=True, timeout=180, env=env)
        try:
            body = json.loads(result.stdout or "{}")
        except json.JSONDecodeError:
            body = {"ok": False, "error": "invalid_response"}
        return body

    def do_GET(self):
        endpoint = self.endpoint()
        if endpoint != "health":
            self.respond(404, {"ok": False, "error": "not_found"})
            return
        body = self.call_script(endpoint)
        self.respond(200 if body.get("ok") else 401, body)

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
        self.respond(200 if body.get("ok") else 400, body)

HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
EOF
    chmod +x "${serverScript}"
}

installSubscriptionControlService() {
    local serviceFile
    if ! command -v python3 >/dev/null 2>&1 || ! command -v systemctl >/dev/null 2>&1; then
        return 0
    fi
    subscriptionControlEnsureToken
    subscriptionGroupsSecureStateFiles
    writeSubscriptionControlServer
    serviceFile=$(subscriptionControlServiceFile)
    if ! cat >"${serviceFile}" <<EOF
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
    then
        return 0
    fi
    systemctl daemon-reload
    systemctl enable --now padm-subscription-control.service >/dev/null 2>&1 || true
    systemctl restart padm-subscription-control.service >/dev/null 2>&1 || true
    for ((i = 0; i < 10; i++)); do
        if curl -sS --connect-timeout 1 --max-time 1 http://127.0.0.1:$(subscriptionControlPort)/s/control/health >/dev/null 2>&1; then
            break
        fi
        sleep 0.2
    done
}

subscriptionControlTokenFile() {
    echo "$(subscriptionGroupsDir)/control.token"
}

subscriptionControlEnsureToken() {
    local tokenFile
    tokenFile=$(subscriptionControlTokenFile)
    mkdir -p "$(dirname "${tokenFile}")"
    chmod 700 "$(dirname "${tokenFile}")" 2>/dev/null || true
    if [[ ! -s "${tokenFile}" ]]; then
        if command -v openssl >/dev/null 2>&1; then
            openssl rand -hex 32 >"${tokenFile}"
        else
            tr -dc 'A-Za-z0-9' </dev/urandom | head -c 64 >"${tokenFile}"
            printf '\n' >>"${tokenFile}"
        fi
    fi
    chmod 600 "${tokenFile}" 2>/dev/null || true
}

subscriptionGroupsSecureStateFiles() {
    local groupsDir
    local groupsFile
    groupsDir=$(subscriptionGroupsDir)
    groupsFile=$(subscriptionGroupsFile)
    mkdir -p "${groupsDir}"
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

subscriptionControlApplySync() {
    local payload=$1
    local dryRun
    local desiredUsers
    local desiredAccounts
    local currentAccounts
    if ! jq -e 'type == "object" and (.desired_users? | type == "array")' <<<"${payload}" >/dev/null 2>&1; then
        jq -n '{ok:false, error:"invalid_payload"}'
        return 1
    fi
    dryRun=$(jq -r 'if has("dry_run") then .dry_run else true end' <<<"${payload}")
    desiredUsers=$(jq '[.desired_users[]? | select((.id // "") != "") | {id, uuid: (.uuid // "")}]' <<<"${payload}")
    desiredAccounts=$(jq -r '.[] | "sub_" + (.id | gsub("-"; "_"))' <<<"${desiredUsers}" | sort -u)
    currentAccounts=$(subscriptionSyncConfiguredManagedUsers)
    plan=$(jq -n --argjson desired "$(printf '%s\n' "${desiredAccounts}" | jq -R -s 'split("\n") | map(select(length > 0))')" --argjson current "$(printf '%s\n' "${currentAccounts}" | jq -R -s 'split("\n") | map(select(length > 0))')" '{create: ($desired - $current), remove: ($current - $desired)}')
    if jq -e '(.create | length == 0) and (.remove | length == 0)' <<<"${plan}" >/dev/null 2>&1; then
        jq -n --argjson plan "${plan}" --argjson dryRun "${dryRun}" '{ok:true, dry_run:$dryRun, changed:false, plan:$plan}'
        return 0
    fi
    if [[ "${dryRun}" == "true" ]]; then
        jq -n --argjson plan "${plan}" '{ok:true, dry_run:true, changed:true, plan:$plan}'
        return 0
    fi
    while IFS= read -r accountName; do
        subscriptionSyncRemoveAccount "${accountName}"
    done < <(jq -r '.remove[]?' <<<"${plan}")
    while IFS= read -r accountName; do
        local id
        local uuid
        id=$(subscriptionSyncAccountId "${accountName}")
        uuid=$(jq -r --arg id "${id}" '.[] | select(.id == $id) | .uuid // empty' <<<"${desiredUsers}")
        if [[ -n "${uuid}" ]]; then
            subscriptionGroupsStateWrite --arg groupId "$(activeSubscriptionGroupId)" --arg id "${id}" --arg uuid "${uuid}" '
              .groups |= map(if .id == $groupId then
                if any(.user_groups[]?; .id == $id) then .user_groups |= map(if .id == $id then .uuid = $uuid else . end) else .user_groups += [{id:$id, name:$id, enabled:true, allowed_sources:["main"], traffic_limit_gb:0, token:"", uuid:$uuid}] end
              else . end)'
        fi
        subscriptionSyncAppendLocalAccount "${accountName}"
    done < <(jq -r '.create[]?' <<<"${plan}")
    if [[ "${PADM_CONTROL_SERVER:-}" == "1" ]]; then
        jq -n --argjson plan "${plan}" '{ok:true, dry_run:false, changed:true, plan:$plan}'
        return 0
    fi
    reloadCore
    readNginxSubscribe
    installSubscriptionControlService
    if ensureSubscriptionControlNginxLocation; then
        serviceQueueRestart nginx
        serviceQueueApply
    fi
    if [[ -n "${subscribePort}" ]]; then
        subscribe false
    fi
    jq -n --argjson plan "${plan}" '{ok:true, dry_run:false, changed:true, plan:$plan}'
}

handleSubscriptionControl() {
    local endpoint=${1:-}
    local token=${2:-${PADM_CONTROL_TOKEN:-}}
    local payload=${3:-}
    ensureSubscriptionGroupsState
    if ! subscriptionControlAuthorized "${token}"; then
        jq -n '{ok:false, error:"unauthorized"}'
        return 1
    fi
    if [[ "${endpoint}" == "health" ]]; then
        jq -n --arg version "$(getScriptVersion)" '{ok:true, version:$version, capabilities:["health","sync"]}'
    elif [[ "${endpoint}" == "sync" ]]; then
        if [[ -z "${payload}" ]]; then
            payload=$(cat)
        fi
        if [[ -z "${payload}" ]]; then
            jq -n '{ok:false, error:"empty_payload"}'
            return 1
        fi
        subscriptionControlApplySync "${payload}"
    else
        jq -n '{ok:false, error:"unknown_endpoint"}'
        return 1
    fi
}
