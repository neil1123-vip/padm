#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 6 ]]; then
    printf 'Usage: %s <version> <commit> <arch> <source-dir> <output-dir> <upstream-sha256>\n' "$0" >&2
    exit 2
fi
version=$1
commit=$2
arch=$3
source_dir=$(realpath -- "$4")
output_dir=$(realpath -m -- "$5")
upstream_sha256=$6
[[ "${version}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$ ]]
[[ "${commit}" =~ ^[0-9a-f]{40}$ && "${upstream_sha256}" =~ ^[0-9a-f]{64}$ ]]
case "$(uname -s):$(uname -m):${arch}" in
Linux:x86_64:amd64 | Linux:aarch64:arm64) ;;
*) printf 'Build and smoke tests require a matching native Linux runner.\n' >&2; exit 2 ;;
esac
[[ "$(git -C "${source_dir}" rev-parse HEAD)" == "${commit}" ]]
[[ -z "$(git -C "${source_dir}" status --porcelain --untracked-files=normal)" ]]
for file in go.mod go.sum LICENSE release/DEFAULT_BUILD_TAGS release/LDFLAGS .github/CRONET_GO_VERSION; do
    [[ -s "${source_dir}/${file}" && ! -L "${source_dir}/${file}" ]]
done

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d "${project_root}/.tmp-sing-box-build.XXXXXX")
server_pid=
http_pid=
cleanup() {
    local status=$?
    local pid file
    trap - EXIT
    for pid in "${server_pid}" "${http_pid}"; do
        [[ -n "${pid}" ]] || continue
        kill "${pid}" 2>/dev/null || true
        wait "${pid}" 2>/dev/null || true
    done
    if ((status != 0)); then
        for file in server.log http.log stats.json; do
            [[ ! -f "${tmp_dir}/${file}" ]] || cat "${tmp_dir}/${file}" >&2
        done
    fi
    rm -rf -- "${tmp_dir}"
    exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

package="sing-box-${version#v}-linux-${arch}"
package_dir="${tmp_dir}/${package}"
mkdir -p -- "${package_dir}" "${output_dir}" "${tmp_dir}/conf"
curl --fail --location --retry 3 --connect-timeout 15 --max-time 300 --proto '=https' --proto-redir '=https' \
    --output "${tmp_dir}/upstream.tar.gz" \
    "https://github.com/SagerNet/sing-box/releases/download/${version}/${package}.tar.gz"
printf '%s  %s\n' "${upstream_sha256}" "${tmp_dir}/upstream.tar.gz" | sha256sum --check --strict -
# Extract only the matching library; the upstream binary is never installed.
library_listing=$(tar -tvzf "${tmp_dir}/upstream.tar.gz" "${package}/libcronet.so")
[[ "${library_listing:0:1}" == '-' && "${library_listing}" != *$'\n'* ]]
tar -xOzf "${tmp_dir}/upstream.tar.gz" "${package}/libcronet.so" >"${package_dir}/libcronet.so"
[[ -s "${package_dir}/libcronet.so" ]]
chmod 644 "${package_dir}/libcronet.so"

build_tags="$(<"${source_dir}/release/DEFAULT_BUILD_TAGS"),with_purego,with_v2ray_api"
ldflags="-X github.com/sagernet/sing-box/constant.Version=${version#v} $(<"${source_dir}/release/LDFLAGS") -s -w -buildid="
(
    cd -- "${source_dir}"
    GOTOOLCHAIN=local CGO_ENABLED=0 GOOS=linux GOARCH="${arch}" \
        go build -mod=readonly -trimpath -buildvcs=false -tags "${build_tags}" \
        -ldflags "${ldflags}" -o "${package_dir}/sing-box" ./cmd/sing-box
)
binary="${package_dir}/sing-box"
version_output=$("${binary}" version)
printf '%s\n' "${version_output}"
[[ "${version_output%%$'\n'*}" == "sing-box version ${version#v}" ]]
grep -Eq '(^|[^[:alnum:]_])with_v2ray_api([^[:alnum:]_]|$)' <<<"${version_output}"

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=localhost \
    -addext subjectAltName=DNS:localhost -keyout "${tmp_dir}/key.pem" \
    -out "${tmp_dir}/cert.pem" >"${tmp_dir}/certificate.log" 2>&1 || {
    cat "${tmp_dir}/certificate.log" >&2
    exit 1
}
jq -n --arg cert "${tmp_dir}/cert.pem" --arg key "${tmp_dir}/key.pem" '{
    log: {level: "info", timestamp: false},
    dns: {servers: [{type: "local", tag: "local"}]},
    route: {final: "direct", default_domain_resolver: "local", rules: [
        {inbound: ["socks-hy2"], action: "route", outbound: "hy2-client"},
        {inbound: ["socks-tuic"], action: "route", outbound: "tuic-client"}
    ]},
    inbounds: ([
        {type: "hysteria2", tag: "hy2", listen: "127.0.0.1", listen_port: 35401,
         users: [{name: "padm-hy2", password: "padm-build-smoke"}]},
        {type: "tuic", tag: "tuic", listen: "127.0.0.1", listen_port: 35402,
         users: [{name: "padm-tuic", uuid: "00000000-0000-4000-8000-000000000001", password: "padm-build-smoke"}]}
    ] | map(. + {tls: {enabled: true, server_name: "localhost", alpn: ["h3"], certificate_path: $cert, key_path: $key}})) + [
        {type: "socks", tag: "socks-hy2", listen: "127.0.0.1", listen_port: 35403},
        {type: "socks", tag: "socks-tuic", listen: "127.0.0.1", listen_port: 35404}
    ],
    outbounds: [
        {type: "direct", tag: "direct"},
        {type: "naive", tag: "cronet-smoke", server: "127.0.0.1", server_port: 9,
         username: "padm-build", password: "padm-build-smoke", tls: {enabled: true, server_name: "localhost"}},
        {type: "hysteria2", tag: "hy2-client", server: "127.0.0.1", server_port: 35401,
         password: "padm-build-smoke", tls: {enabled: true, server_name: "localhost", certificate_path: $cert}},
        {type: "tuic", tag: "tuic-client", server: "127.0.0.1", server_port: 35402,
         uuid: "00000000-0000-4000-8000-000000000001", password: "padm-build-smoke",
         tls: {enabled: true, server_name: "localhost", alpn: ["h3"], certificate_path: $cert}}
    ]
}' >"${tmp_dir}/conf/01_protocols.json"
jq -n '{experimental: {v2ray_api: {listen: "127.0.0.1:0", stats: {
    enabled: true, users: ["padm-hy2", "padm-tuic"]
}}}}' >"${tmp_dir}/conf/14_stats_api.json"
"${binary}" merge "${tmp_dir}/config.json" -C "${tmp_dir}/conf"
"${binary}" check -c "${tmp_dir}/config.json"
"${binary}" run -c "${tmp_dir}/config.json" >"${tmp_dir}/server.log" 2>&1 &
server_pid=$!
api_port=
for _ in {1..100}; do
    kill -0 "${server_pid}"
    api_port=$(sed -n 's/.*grpc server started at 127\.0\.0\.1:\([0-9][0-9]*\).*/\1/p' "${tmp_dir}/server.log")
    [[ "${api_port}" =~ ^[0-9]+$ ]] && break
    sleep 0.1
done
[[ "${api_port}" =~ ^[0-9]+$ ]]
grep -q 'NaiveProxy started, version:' "${tmp_dir}/server.log"

head -c 65536 /dev/zero >"${tmp_dir}/payload.bin"
python3 -u -c 'import functools, http.server, sys
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=sys.argv[1])
server = http.server.HTTPServer(("127.0.0.1", 0), handler)
print(server.server_port, flush=True)
server.serve_forever()' "${tmp_dir}" >"${tmp_dir}/http.log" 2>&1 &
http_pid=$!
http_port=
for _ in {1..100}; do
    kill -0 "${http_pid}"
    http_port=$(sed -n '1p' "${tmp_dir}/http.log")
    [[ "${http_port}" =~ ^[0-9]+$ ]] && break
    sleep 0.1
done
[[ "${http_port}" =~ ^[0-9]+$ ]]
for socks_port in 35403 35404; do
    curl --fail --silent --show-error --max-time 15 --noproxy '' \
        --socks5-hostname "127.0.0.1:${socks_port}" --output "${tmp_dir}/received.bin" \
        "http://127.0.0.1:${http_port}/payload.bin"
    cmp "${tmp_dir}/payload.bin" "${tmp_dir}/received.bin"
done
# An empty QueryStats message is a five-byte gRPC frame.
printf '\0\0\0\0\0' >"${tmp_dir}/request.bin"
curl --fail --silent --show-error --http2-prior-knowledge --max-time 10 --noproxy '*' \
    --header 'content-type: application/grpc' --header 'TE: trailers' --data-binary "@${tmp_dir}/request.bin" \
    --dump-header "${tmp_dir}/headers" --output "${tmp_dir}/response.bin" \
    "http://127.0.0.1:${api_port}/v2ray.core.app.stats.command.StatsService/QueryStats"
awk '{ sub(/\r$/, ""); if (tolower($0) == "grpc-status: 0") ok=1 } END { exit !ok }' "${tmp_dir}/headers"
# shellcheck source=/dev/null
source "${project_root}/shell/subscription/traffic.sh"
singBoxGrpcResponseToStatsJson "${tmp_dir}/response.bin" >"${tmp_dir}/stats.json"
for user in padm-hy2 padm-tuic; do
    jq -e --arg user "${user}" '.stat |
        any(.[]; .name == ("user>>>" + $user + ">>>traffic>>>uplink") and .value > 0) and
        any(.[]; .name == ("user>>>" + $user + ">>>traffic>>>downlink") and .value >= 65536)' \
        "${tmp_dir}/stats.json" >/dev/null
done
kill -0 "${server_pid}"
kill "${server_pid}"
wait "${server_pid}"
server_pid=

cp -- "${source_dir}/LICENSE" "${package_dir}/LICENSE"
cronet_commit=$(tr -d '\r\n' <"${source_dir}/.github/CRONET_GO_VERSION")
[[ "${cronet_commit}" =~ ^[0-9a-f]{40}$ ]]
jq -n --arg version "${version}" --arg commit "${commit}" --arg tags "${build_tags}" \
    --arg ldflags "${ldflags}" --arg go "$(go version)" --arg arch "${arch}" \
    --arg upstream_sha256 "${upstream_sha256}" --arg source_asset "sing-box-${version#v}-source.tar.gz" \
    --arg cronet_sha256 "$(sha256sum "${package_dir}/libcronet.so" | cut -d ' ' -f 1)" --arg cronet_commit "${cronet_commit}" \
    '{upstream: "https://github.com/SagerNet/sing-box", version: $version, commit: $commit,
      source_asset: $source_asset, build_tags: $tags, ldflags: $ldflags, go: $go,
      goos: "linux", goarch: $arch, cgo_enabled: false,
      upstream_asset_sha256: $upstream_sha256, libcronet_sha256: $cronet_sha256,
      cronet_source: ("https://github.com/SagerNet/cronet-go/tree/" + $cronet_commit),
      checks: ["version", "merge", "check", "hysteria2-tuic-user-traffic", "cronet-start", "v2ray-query-stats"]}' \
    >"${package_dir}/BUILD_INFO.json"
source_epoch=$(git -C "${source_dir}" show -s --format=%ct "${commit}")
tar --sort=name --mtime="@${source_epoch}" --owner=0 --group=0 --numeric-owner \
    -C "${tmp_dir}" -cf - "${package}" | gzip -n >"${output_dir}/${package}.tar.gz"
if [[ "${arch}" == amd64 ]]; then
    git -C "${source_dir}" archive --format=tar --prefix="sing-box-${version#v}/" "${commit}" |
        gzip -n >"${output_dir}/sing-box-${version#v}-source.tar.gz"
fi
printf 'Built and verified %s\n' "${output_dir}/${package}.tar.gz"
