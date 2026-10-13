#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-generation-metadata.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

fail() {
    printf 'docker-generation-metadata-regression-fail: %s\n' "$*" >&2
    exit 1
}

spec="${TEST_ROOT}/spec.json"
candidate="${TEST_ROOT}/candidate"
mkdir -p -- "${candidate}/config/xray" "${candidate}/config/sing-box"
jq -n '{
  core:{type:"xray",secondary_type:"sing-box",protocols:[
    {id:1,listener_id:"entry-one",public_port:24444,address_families:["ipv4"]}
  ]},
  release:{version:"fixture"},host_integrations:[],subscription:{enabled:false},
  routing:{},relay:{},tls:{http01:false}
}' >"${spec}"

for tlsMode in none xray both missing; do
    printf '{"inbounds":[]}\n' >"${candidate}/config/xray/config.json"
    printf '{"inbounds":[]}\n' >"${candidate}/config/sing-box/config.json"
    if [[ "${tlsMode}" == xray || "${tlsMode}" == both ]]; then
        jq -n '{inbounds:[{streamSettings:{security:"tls",tlsSettings:{certificates:[{
          certificateFile:"/etc/padm/secrets/tls/example.com.crt",
          keyFile:"/etc/padm/secrets/tls/example.com.key"
        }]}}}]}' >"${candidate}/config/xray/config.json"
    fi
    if [[ "${tlsMode}" == both ]]; then
        jq -n '{inbounds:[{tls:{enabled:true,
          certificate_path:"/etc/padm/secrets/tls/example.com.crt",
          key_path:"/etc/padm/secrets/tls/example.com.key"
        }}]}' >"${candidate}/config/sing-box/config.json"
    fi
    if [[ "${tlsMode}" == missing ]]; then
        rm -- "${candidate}/config/xray/config.json" "${candidate}/config/sing-box/config.json"
    fi
    dockerGenerateCompose "${spec}" "${candidate}/compose.json" || fail "生成失败: ${tlsMode}"
    jq -e --arg mode "${tlsMode}" '
      def tls_mount($core): [.services[$core].volumes[] |
        select(.target == "/etc/padm/secrets/tls")] | length;
      (tls_mount("xray") == (if $mode == "xray" or $mode == "both" then 1 else 0 end)) and
      (tls_mount("sing-box") == (if $mode == "both" then 1 else 0 end))
    ' "${candidate}/compose.json" >/dev/null || fail "TLS 挂载错误: ${tlsMode}"
done

(
    # 首轮读取规格后源文件发生变化，生成必须继续使用本次调用的私密快照。
    saved="${TEST_ROOT}/compose-snapshot.json"
    cp -- "${spec}" "${saved}"
    trap 'cp -- "${saved}" "${spec}"' EXIT
    printf '{"inbounds":[]}\n' >"${candidate}/config/xray/config.json"
    printf '{"inbounds":[]}\n' >"${candidate}/config/sing-box/config.json"
    flag="${TEST_ROOT}/compose-snapshot-mutated"
    jq() {
        command jq "$@"
        local status=$?
        if [[ "${status}" == 0 && ! -e "${flag}" &&
            "$*" == *'tojson'* && "$*" == *'host_integrations'* ]]; then
            : >"${flag}"
            printf '{invalid\n' >"${spec}"
        fi
        return "${status}"
    }
    dockerGenerateCompose "${spec}" "${TEST_ROOT}/snapshot-compose.json" "${candidate}" ||
        fail '规格快照在源文件变化后未完成生成'
    [[ -e "${flag}" ]] || fail '规格快照测试未注入源文件变化'
    jq -e '.services.xray.labels["io.padm.release"] == "fixture" and
        .services["sing-box"].labels["io.padm.release"] == "fixture"' \
        "${TEST_ROOT}/snapshot-compose.json" >/dev/null ||
        fail '生成结果读取了变化后的规格'
)

printf '{"inbounds":[{"streamSettings":{"security":"tls","tlsSettings":{"certificates":[]}}}]}\n' \
    >"${candidate}/config/xray/config.json"
if dockerGenerateCompose "${spec}" "${TEST_ROOT}/invalid-tls.json" "${candidate}" \
    >"${TEST_ROOT}/failure.log" 2>&1; then
    fail '无效核心 TLS 配置未被拒绝'
fi
[[ ! -e "${TEST_ROOT}/invalid-tls.json" ]] || fail '无效 TLS 仍写入候选'

(
    # 元数据即使已经输出，也必须传播 jq 的失败状态。
    jq() {
        command jq "$@" || return $?
        [[ "${1:-}" != -r ]] || return 17
    }
    if dockerGenerateCompose "${spec}" "${TEST_ROOT}/failed-metadata.json" "${candidate}" \
        >"${TEST_ROOT}/failure.log" 2>&1; then
        fail '核心元数据 jq 失败未传播'
    fi
    [[ ! -e "${TEST_ROOT}/failed-metadata.json" ]] || fail '元数据失败仍写入候选'
)
(
    # 基线分支元数据必须完整取得，不能用已经输出的字段掩盖解析失败。
    dockerInstallRoot() { printf '%s\n' "${TEST_ROOT}"; }
    dockerManagedSpecMatchesDeployment() { return 0; }
    jq() {
        command jq "$@" || return $?
        [[ "$*" != *'join("|")'* ]] || return 17
    }
    if dockerEditBaselineValidate "${spec}" "${TEST_ROOT}/failed-baseline" \
        >"${TEST_ROOT}/failure.log" 2>&1; then
        fail '基线元数据 jq 失败未传播'
    fi
    [[ ! -e "${TEST_ROOT}/failed-baseline" ]] || fail '元数据失败仍重建基线'
)
(
    # 发布输入只解析一次；无效字段或输出后失败都不能污染已准备的输入。
    releaseRoot="${TEST_ROOT}/release-reuse"
    mkdir -p -- "${releaseRoot}/config"
    dockerInstallRoot() { printf '%s\n' "${releaseRoot}"; }
    dockerRequireInstalledBundle() { :; }
    dockerPrivateFileIsRestricted() { :; }
    dockerManagedSpecMatchesDeployment() { :; }
    dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
    dockerBundleSupportsSpec() { :; }
    dockerCleanupStagedBundle() { :; }
    command jq -n '{
      release:{version:"fixture",manifest_sha256:("a" * 64),signature_identity:"fixture"},
      images:{net:"net",nginx:"nginx",ops:"ops","sing-box":"sing-box",xray:"xray"}
    }' >"${releaseRoot}/valid.json"
    calls="${releaseRoot}/jq.calls"
    jq() {
        printf 'call\n' >>"${calls}"
        command jq "$@" || return $?
        [[ "${failAfterOutput:-false}" != true ]] || return 17
    }
    cp -- "${releaseRoot}/valid.json" "${releaseRoot}/config/spec.json"
    dockerConfigureReleaseReuseInstalled || fail '有效发布输入未被复用'
    [[ "$(wc -l <"${calls}")" == 1 ]] || fail '发布输入没有合并成单次 jq'
    command jq -e --argjson inputs "${DOCKER_CONFIG_RELEASE_INPUTS}" \
        '. == $inputs' "${releaseRoot}/valid.json" >/dev/null || fail '复用发布输入发生变化'
    for change in '.release.manifest_sha256 = "invalid"' '.images |= del(.ops)'; do
        command jq "${change}" "${releaseRoot}/valid.json" >"${releaseRoot}/config/spec.json"
        DOCKER_CONFIG_RELEASE_INPUTS=sentinel DOCKER_STAGED_BUNDLE_PATH=sentinel
        if dockerConfigureReleaseReuseInstalled >"${releaseRoot}/failure.log" 2>&1; then
            fail '无效发布输入未被拒绝'
        fi
        [[ "${DOCKER_CONFIG_RELEASE_INPUTS}" == sentinel &&
            "${DOCKER_STAGED_BUNDLE_PATH}" == sentinel ]] || fail '失败污染了发布输入'
    done
    cp -- "${releaseRoot}/valid.json" "${releaseRoot}/config/spec.json"
    failAfterOutput=true
    if dockerConfigureReleaseReuseInstalled >"${releaseRoot}/failure.log" 2>&1; then
        fail '发布输入 jq 输出后失败未传播'
    fi
    [[ "${DOCKER_CONFIG_RELEASE_INPUTS}" == sentinel &&
        "${DOCKER_STAGED_BUNDLE_PATH}" == sentinel ]] || fail 'jq 失败污染了发布输入'
)
printf 'docker-generation-metadata-regression-ok\n'
