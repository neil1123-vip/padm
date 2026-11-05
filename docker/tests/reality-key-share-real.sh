#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
mode=${1:-keys}
[[ "$#" -le 1 && ( "${mode}" == keys || "${mode}" == handshake ) ]]
[[ "$(uname -s)" == Linux && -f /.dockerenv ]]
case "$(uname -m)" in
x86_64) arch=amd64 ;;
aarch64) arch=arm64 ;;
*) exit 1 ;;
esac
source "${PROJECT_ROOT}/shell/core/runtime.sh"
source "${PROJECT_ROOT}/shell/core/cores.sh"
source "${PROJECT_ROOT}/shell/core/singbox_build.sh"
padmCreateTempPath root -d "${TMPDIR}/reality-key-share.XXXXXX"
cache=/sing-box-build-cache
source_dir="${cache}/upstream-v1.14.4"
if [[ ! -f "${source_dir}/go.mod" || ! -f "${source_dir}/go.sum" ]]; then
    source_dir="${root}/source"
    downloadUrlToFileBounded \
        https://codeload.github.com/SagerNet/sing-box/tar.gz/c005f35300ce76427dc285481ec5695f5b179cd2 \
        "${root}/source.tar.gz" 52428800 300
    validateCoreTarArchive "${root}/source.tar.gz"
    mkdir -p "${source_dir}"
    tar -xzf "${root}/source.tar.gz" --strip-components=1 -C "${source_dir}"
fi
grep -Fxq $'\tgithub.com/metacubex/utls v1.8.7' "${source_dir}/go.mod"
go_bin="${cache}/go/bin"
if [[ ! -x "${go_bin}/go" ||
    "$("${go_bin}/go" version)" != "go version go1.25.5 linux/${arch}" ]]; then
    ensureSingBoxBuildGo "${source_dir}" "${root}" "${arch}" go_bin
fi
export GOTOOLCHAIN=local GOSUMDB=sum.golang.org
export GOPROXY="file://${cache}/gopath/pkg/mod/cache/download,https://proxy.golang.org"
export GOMODCACHE="${root}/modules" GOCACHE="${root}/build" GOPATH="${root}/gopath"
cp -- "${PROJECT_ROOT}/docker/tests/reality-key-share-real_test.go" "${root}/"
# 从实际补丁输出提取认证私钥选择，避免测试另写一份生产逻辑。
for version in v1.14.4-padm.1 v1.14.4-padm.2; do
    prepareSingBoxRealitySource "${source_dir}/common/tls/reality_client.go" "${root}/reality_client.go" "${version}"
    python3 - "${root}" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
source = (root / "reality_client.go").read_text()
start = source.index("\tkeyShareKeys := uConn.HandshakeState.State13.KeyShareKeys\n")
end = source.index("\tauthKey, err := ecdheKey.ECDH(publicKey)\n", start)
(root / "auth.go").write_text(
    'package reality\nimport ("crypto/ecdh"; E "errors"; utls "github.com/metacubex/utls")\n'
    'func realityAuthPrivateKey(uConn *utls.UConn) (*ecdh.PrivateKey, error) {\n'
    + source[start:end] + '\treturn ecdheKey, nil\n}\n')
PY
    cd -- "${source_dir}"
    if [[ "${version}" == v1.14.4-padm.1 ]]; then
        if "${go_bin}/go" test -mod=readonly -count=1 -v \
            "${root}/reality-key-share-real_test.go" "${root}/auth.go" >"${root}/baseline.log" 2>&1; then
            printf 'The published .1 unexpectedly accepted hybrid-only; recheck the candidate.\n' >&2
            exit 1
        fi
        cat "${root}/baseline.log"
        grep -Fq -- '--- FAIL: TestRealityKeySharePrivateKeys/hybrid-only' "${root}/baseline.log"
        grep -Fq -- 'nil ecdheKey' "${root}/baseline.log"
        grep -Fq -- '--- PASS: TestRealityKeySharePrivateKeys/dual' "${root}/baseline.log"
        grep -Fq -- '--- PASS: TestRealityKeySharePrivateKeys/x25519-only' "${root}/baseline.log"
    else
        "${go_bin}/go" test -mod=readonly -count=1 -v \
            "${root}/reality-key-share-real_test.go" "${root}/auth.go"
    fi
    if [[ "${mode}" == handshake ]]; then
        cp -- "${PROJECT_ROOT}/docker/tests/reality-hybrid-only-real_test.go" "${root}/"
        # 只替换 ClientHello 工厂，编译完整客户端源码，不摘抄认证或验签实现。
        python3 - "${source_dir}" "${root}" <<'PY'
import json
import pathlib
import sys

source_dir, root = map(pathlib.Path, sys.argv[1:])
source = (root / "reality_client.go").read_text()
factory = "utls.UClient(conn, uConfig, e.uClient.id)"
assert source.count(factory) == 1
(root / "handshake.go").write_text(source.replace(factory, "realityTestUClient(conn, uConfig, e.uClient.id)"))
(root / "overlay.json").write_text(json.dumps({"Replace": {
    str(source_dir / "common/tls/reality_client.go"): str(root / "handshake.go"),
    str(source_dir / "common/tls/reality_hybrid_only_test.go"): str(root / "reality-hybrid-only-real_test.go"),
}}))
PY
        baseline=0
        [[ "${version}" != v1.14.4-padm.1 ]] || baseline=1
        PADM_REALITY_BASELINE="${baseline}" "${go_bin}/go" test -mod=readonly \
            -overlay="${root}/overlay.json" -tags=with_utls -count=1 -v \
            -run '^TestRealityHybridOnlyHandshake$' ./common/tls
    fi
done
"${go_bin}/go" version
printf 'docker-reality-key-share-real-ok: utls=v1.8.7 baseline=hybrid-only-rejected candidate=all-keys-matched\n'
if [[ "${mode}" == handshake ]]; then
    printf 'docker-reality-hybrid-only-real-ok: full-client-source=patched xray=26.10.31 wire=dual+hybrid-only auth-refusals=public-key+short-id+uuid\n'
fi
