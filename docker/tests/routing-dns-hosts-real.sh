#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-routing-dns-hosts-real.XXXXXX")
cleanup() {
    local status=$? file
    if [[ "${status}" -ne 0 ]]; then
        for file in "${TEST_ROOT}"/*.log; do
            [[ -f "${file}" ]] || continue
            printf '\nrouting-fixture-log: %s\n' "${file##*/}" >&2
            cat -- "${file}" >&2
        done
    fi
    rm -rf -- "${TEST_ROOT}"
    return "${status}"
}
trap cleanup EXIT
[[ "$(id -u)" == 0 && "$(uname -s)" == Linux ]] || exit 1
for tool in jq python3 setpriv; do command -v "${tool}" >/dev/null; done
[[ -f /routing-cores/xray && -f /routing-cores/sing-box ]] || {
    printf 'routing-dns-hosts-real: 缺少本机镜像传入的两核心程序\n' >&2
    exit 1
}
chmod 0755 /routing-cores/xray /routing-cores/sing-box
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
for family in ipv4 ipv6; do
    suffix=v4
    [[ "${family}" != ipv6 ]] || suffix=v6
    jq -n --arg suffix "${suffix}" '
      def entry($core; $port): {
        id:1,core:$core,listener_id:("entry-"+$core),server:"proxy.example.com",public_port:$port,
        address_families:["ipv4"],name:$core,uuid:"11111111-1111-4111-8111-111111111111",
        reality:{server_name:"www.debian.org",target_host:"www.debian.org",target_port:443,
          private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
          public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",short_id:"1234"}};
      {schema_version:3,release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"fixture"},
       core:{type:"xray",secondary_type:"sing-box",protocols:[entry("xray";35441),entry("sing-box";35442)]},
       tls:null,subscription:{enabled:false,token:"0123456789abcdef"},
       images:(["xray","sing-box","nginx","ops","net"] | map({key:.,value:
         ("ghcr.io/example/padm-"+.+":test@sha256:"+("a"*64))}) | from_entries),host_integrations:[],
       routing:{
         socks5:{server:"192.0.2.1",port:1080,username:"fixture-user",password:"fixture-password",
           domains:[("full:proxy-"+$suffix+".padm.invalid")]},
         dns:{server:"192.0.2.53",port:5353,domains:[
           ("full:full-"+$suffix+".padm.invalid"),("domain:suffix-"+$suffix+".padm.invalid"),
           ("keyword:keyword-"+$suffix),"geosite:test",("full:hosts-"+$suffix+".padm.invalid"),
           ("full:proxy-"+$suffix+".padm.invalid"),("full:error-"+$suffix+".padm.invalid"),
           ("full:timeout-"+$suffix+".padm.invalid")]},
         hosts:{("hosts-"+$suffix+".padm.invalid"):"203.0.113.80",
           ("proxy-"+$suffix+".padm.invalid"):"203.0.113.81"}}}
    ' >"${TEST_ROOT}/${family}.spec.json"
    dockerConfigureSpecValidate "${TEST_ROOT}/${family}.spec.json"
    dockerGenerateXrayConfig "${TEST_ROOT}/${family}.spec.json" "${TEST_ROOT}/xray.${family}.base"
    dockerGenerateSingBoxConfig "${TEST_ROOT}/${family}.spec.json" "${TEST_ROOT}/sing-box.${family}.base"
    for core in xray sing-box; do
        dockerTrafficRender "${core}" "${TEST_ROOT}/${core}.${family}.base" \
            '{"schema_version":1,"accounts":{}}' >"${TEST_ROOT}/${core}.${family}.json"
    done
    if [[ "${PADM_ROUTING_REAL_SCOPE:-}" == ips ]]; then
        modes=(ip-control ip-literal ip-cidr ip-geoip)
    elif [[ "${PADM_ROUTING_REAL_SCOPE:-}" == bt ]]; then
        modes=(bt-control bt)
        [[ "${family}" != ipv4 ]] || modes+=(bt-global)
    elif [[ "${PADM_ROUTING_REAL_SCOPE:-}" == region ]]; then
        modes=(region-control region-both)
        [[ "${family}" != ipv4 ]] || modes+=(region-domain region-ip region-off)
    else
        modes=(policy-control policy)
        [[ "${family}" != ipv4 ]] || modes+=(global resolve policy-global)
    fi
    for mode in "${modes[@]}"; do
        if [[ "${mode}" == global ]]; then
            jq 'del(.routing.socks5.domains)' "${TEST_ROOT}/${family}.spec.json"
        elif [[ "${mode}" == resolve ]]; then
            jq 'del(.routing.socks5)' "${TEST_ROOT}/${family}.spec.json"
        elif [[ "${mode}" == ip-* ]]; then
            address=127.0.0.1
            network=127.0.0.0/8
            [[ "${family}" != ipv6 ]] || { address=::1; network=::/64; }
            jq --arg suffix "${suffix}" --arg mode "${mode}" --arg address "${address}" --arg network "${network}" '
              .routing.direct = {domains:[("full:allowip-"+$suffix+".padm.invalid")]} |
              if $mode == "ip-control" then .
              else .routing.block_ips = {ips:[
                if $mode == "ip-literal" then $address
                elif $mode == "ip-cidr" then $network
                else "geoip:cn" end]} end
            ' "${TEST_ROOT}/${family}.spec.json"
        elif [[ "${mode}" == bt* ]]; then
            jq --arg suffix "${suffix}" --arg mode "${mode}" '
              ("full:allowbt-"+$suffix+".padm.invalid") as $allow |
              .routing.direct = {domains:[$allow]} |
              .routing.dns.domains += [$allow] |
              .routing.socks5.domains += [$allow] |
              if $mode == "bt-control" then .
              else .routing.block_bt = true end |
              if $mode == "bt-global" then del(.routing.socks5.domains) else . end
            ' "${TEST_ROOT}/${family}.spec.json"
        elif [[ "${mode}" == region-* ]]; then
            jq --arg mode "${mode}" '
              ["cn-region.padm.invalid","allow-region.padm.invalid","dl.google.com"] as $names |
              .routing.block = {domains:["full:persist-region.padm.invalid"]} |
              .routing.dns.domains += ($names | map("full:"+.)) |
              .routing.socks5.domains += (($names + ["persist-region.padm.invalid"]) | map("full:"+.)) |
              if $mode == "region-control" or $mode == "region-off" then .
              else .routing.region = {mode:($mode | ltrimstr("region-")),
                allow_domains:["full:allow-region.padm.invalid"]} end
            ' "${TEST_ROOT}/${family}.spec.json"
        else
            jq --arg suffix "${suffix}" --arg mode "${mode}" '
              .routing.direct = {domains:[
                ("full:full-"+$suffix+".padm.invalid"),("domain:suffix-"+$suffix+".padm.invalid"),
                ("keyword:only-keyword-"+$suffix),"geosite:test",
                ("full:hosts-"+$suffix+".padm.invalid"),("full:proxy-"+$suffix+".padm.invalid")]} |
              .routing.block = {domains:[
                ("full:block-full-"+$suffix+".padm.invalid"),("domain:block-suffix-"+$suffix+".padm.invalid"),
                ("keyword:block-keyword-"+$suffix),"geosite:block",
                ("full:full-"+$suffix+".padm.invalid")]} |
              .routing.dns.domains = ((.routing.dns.domains + .routing.block.domains) | unique) |
              .routing.hosts[("block-full-"+$suffix+".padm.invalid")] = "203.0.113.82" |
              .routing.socks5.domains = ["domain:padm.invalid"] |
              if $mode == "policy-control" then del(.routing.socks5,.routing.direct,.routing.block)
              elif $mode == "policy-global" then del(.routing.socks5.domains)
              else . end
            ' "${TEST_ROOT}/${family}.spec.json"
        fi >"${TEST_ROOT}/${family}.${mode}.spec.json"
        dockerConfigureSpecValidate "${TEST_ROOT}/${family}.${mode}.spec.json"
        dockerGenerateXrayConfig "${TEST_ROOT}/${family}.${mode}.spec.json" \
            "${TEST_ROOT}/xray.${family}.${mode}.base"
        dockerGenerateSingBoxConfig "${TEST_ROOT}/${family}.${mode}.spec.json" \
            "${TEST_ROOT}/sing-box.${family}.${mode}.base"
        for core in xray sing-box; do
            dockerTrafficRender "${core}" "${TEST_ROOT}/${core}.${family}.${mode}.base" \
                '{"schema_version":1,"accounts":{}}' >"${TEST_ROOT}/${core}.${family}.${mode}.json"
        done
    done
done
# 生产生成和流量渲染不变；仅将外部地址换成隔离容器的本地 DNS/HTTP/SOCKS fixture。
python3 "${PROJECT_ROOT}/docker/tests/routing-dns-hosts-real.py" "${TEST_ROOT}"
printf 'docker-routing-dns-hosts-real-ok\n'
