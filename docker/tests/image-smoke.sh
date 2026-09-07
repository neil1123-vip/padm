#!/usr/bin/env bash
set -euo pipefail

image=${1:?image reference required}
name=${2:?image name required}

case "${name}" in
xray)
    docker run --rm --pull=never "${image}" version >/dev/null
    ;;
sing-box)
    version_output=$(docker run --rm --pull=never "${image}" version)
    grep -Eq '(^|[^[:alnum:]_])with_v2ray_api([^[:alnum:]_]|$)' <<<"${version_output}" || {
        printf 'sing-box image lacks with_v2ray_api: %s\n' "${version_output}" >&2
        exit 1
    }
    [[ "$(docker image inspect --format '{{.Config.User}}' "${image}")" == 10001:10001 ]]
    tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/padm-sing-box-image-smoke.XXXXXX")
    container_id=
    cleanup() {
        local status=$?
        if [[ -n "${container_id}" ]]; then
            if [[ "${status}" -ne 0 ]]; then
                docker logs "${container_id}" >&2 || true
            fi
            docker rm --force "${container_id}" >/dev/null || true
        fi
        rm -rf -- "${tmp_dir}"
        exit "${status}"
    }
    trap cleanup EXIT
    openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=localhost \
        -addext subjectAltName=DNS:localhost -keyout "${tmp_dir}/key.pem" \
        -out "${tmp_dir}/cert.pem" >"${tmp_dir}/certificate.log" 2>&1 || {
        cat "${tmp_dir}/certificate.log" >&2
        exit 1
    }
    jq -n '{
        log: {level: "info", timestamp: false},
        inbounds: ([
            {type: "hysteria2", tag: "hy2", listen: "127.0.0.1", listen_port: 35401,
             users: [{name: "padm-hy2", password: "padm-image-smoke"}]},
            {type: "tuic", tag: "tuic", listen: "127.0.0.1", listen_port: 35402,
             users: [{name: "padm-tuic", uuid: "00000000-0000-4000-8000-000000000001", password: "padm-image-smoke"}]}
        ] | map(. + {tls: {enabled: true, server_name: "localhost", alpn: ["h3"],
                           certificate_path: "/etc/padm/sing-box/cert.pem", key_path: "/etc/padm/sing-box/key.pem"}})),
        outbounds: [
            {type: "direct", tag: "direct"},
            {type: "naive", tag: "cronet-smoke", server: "127.0.0.1", server_port: 9,
             username: "padm-image", password: "padm-image-smoke", tls: {enabled: true, server_name: "localhost"}}
        ],
        route: {final: "direct"},
        experimental: {v2ray_api: {listen: "0.0.0.0:8080", stats: {
            enabled: true, users: ["padm-hy2", "padm-tuic"]
        }}}
    }' >"${tmp_dir}/config.json"
    chmod 755 "${tmp_dir}"
    chmod 644 "${tmp_dir}/config.json" "${tmp_dir}/cert.pem" "${tmp_dir}/key.pem"
    run_args=(--pull=never --read-only --cap-drop=ALL --security-opt=no-new-privileges \
        --tmpfs /tmp --tmpfs '/var/lib/padm/sing-box:uid=10001,gid=10001,mode=0755' \
        --mount "type=bind,source=${tmp_dir},target=/etc/padm/sing-box,readonly")
    docker run --rm "${run_args[@]}" "${image}" check \
        -D /var/lib/padm/sing-box -c /etc/padm/sing-box/config.json
    container_id=$(docker run --detach "${run_args[@]}" --publish 127.0.0.1::8080 "${image}")
    api_port=$(docker port "${container_id}" 8080/tcp | sed -n 's/^127\.0\.0\.1:\([0-9][0-9]*\)$/\1/p')
    [[ "${api_port}" =~ ^[0-9]+$ ]]
    for _ in {1..120}; do
        [[ "$(docker inspect --format '{{.State.Running}}' "${container_id}")" == true ]]
        docker logs "${container_id}" >"${tmp_dir}/server.log" 2>&1
        grep -q 'grpc server started at' "${tmp_dir}/server.log" && break
        sleep 0.5
    done
    grep -q 'grpc server started at' "${tmp_dir}/server.log"
    grep -q 'NaiveProxy started, version:' "${tmp_dir}/server.log"
    grep -q 'inbound/hysteria2\[hy2\].*udp server started at' "${tmp_dir}/server.log"
    grep -q 'inbound/tuic\[tuic\].*udp server started at' "${tmp_dir}/server.log"
    # 空 QueryStats 请求使用 5 字节的 gRPC 帧。
    printf '\0\0\0\0\0' >"${tmp_dir}/request.bin"
    curl --fail --silent --show-error --http2-prior-knowledge --max-time 10 --noproxy '*' \
        --header 'content-type: application/grpc' --header 'TE: trailers' --data-binary "@${tmp_dir}/request.bin" \
        --dump-header "${tmp_dir}/headers" --output "${tmp_dir}/response.bin" \
        "http://127.0.0.1:${api_port}/v2ray.core.app.stats.command.StatsService/QueryStats"
    awk '{ sub(/\r$/, ""); if (tolower($0) == "grpc-status: 0") ok=1 } END { exit !ok }' "${tmp_dir}/headers"
    [[ "$(docker inspect --format '{{.State.Running}}' "${container_id}")" == true ]]
    ;;
nginx)
    docker run --rm --pull=never "${image}" -t >/dev/null
    ;;
ops|net)
    docker run --rm --pull=never "${image}" health >/dev/null
    ;;
*)
    printf 'unknown image: %s\n' "${name}" >&2
    exit 2
    ;;
esac

printf 'docker-image-smoke-ok: %s\n' "${name}"
