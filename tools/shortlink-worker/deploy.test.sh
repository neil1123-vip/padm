#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "${tmp}"' EXIT
fakeBin="${tmp}/bin"
project="${tmp}/worker project"
mkdir -p "${fakeBin}" "${project}"
export DEPLOY_TEST_REAL_NODE
DEPLOY_TEST_REAL_NODE=$(command -v node)
export CLOUDFLARE_API_TOKEN=test-cloudflare-token
export CLOUDFLARE_ACCOUNT_ID=0123456789abcdef0123456789abcdef
export PADM_INSTALL_DIR="${tmp}/padm"
cp -- "${root}/"{deploy.sh,worker.js,wrangler.toml,package.json,package-lock.json} "${project}/"
npm ci --prefix "${project}" --omit=dev --ignore-scripts --no-audit --no-fund
printf 'API_KEY=%064d\n' 0 >"${tmp}/dryrun.env"
WRANGLER_SEND_METRICS=false wrangler deploy --dry-run --config "${project}/wrangler.toml" \
    --outdir "${tmp}/bundle" --secrets-file "${tmp}/dryrun.env" --keep-vars
[[ -s "${tmp}/bundle/worker.js" ]]
! grep -q 'require("qr-image")' "${tmp}/bundle/worker.js"
"${DEPLOY_TEST_REAL_NODE}" "${root}/worker.runtime.test.mjs" "${project}"
export DEPLOY_TEST_LOG="${tmp}/calls"
cat >"${fakeBin}/npx" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == --yes && "$2" == wrangler@4.149.0 && "$3" == deploy ]]
shift 3
configFile= secretsFile= customDomain=
while (($#)); do
    case "$1" in
    --secrets-file) secretsFile=$2; shift 2 ;;
    --config) configFile=$2; shift 2 ;;
    --domains) customDomain=$2; shift 2 ;;
    --keep-vars) shift ;;
    *) printf 'unexpected option: %s\n' "$1" >&2; exit 90 ;;
    esac
done
[[ -f "${configFile}" && -f "${secretsFile}" && -f worker.js ]]
[[ -f package.json && -f package-lock.json ]]
[[ "${CLOUDFLARE_API_TOKEN}" == test-cloudflare-token ]]
[[ "${CLOUDFLARE_ACCOUNT_ID}" == 0123456789abcdef0123456789abcdef ]]
[[ "$(stat -c '%a' "${secretsFile}")" == 600 ]]
grep -q '^API_KEY=[0-9a-f]\{64\}$' "${secretsFile}"
printf 'deploy\n' >>"${DEPLOY_TEST_LOG}"
if [[ -n "${customDomain}" ]]; then
    [[ "${customDomain}" == go.example.com && "${CI:-}" == false ]]
    [[ -t 0 && -t 1 && -t 2 ]]
    printf 'domain=%s\n' "${customDomain}" >>"${DEPLOY_TEST_LOG}"
fi
[[ "${DEPLOY_TEST_MODE:-}" != failure ]] || { printf 'deploy failed\n' >&2; exit 17; }
if ! grep -q '^id =' "${configFile}"; then
    awk '{ print } /^binding = "KV"$/ { print "id = \"0123456789abcdef0123456789abcdef\"" }' \
        "${configFile}" >"${configFile}.tmp"
    mv -- "${configFile}.tmp" "${configFile}"
    printf 'created-kv\n' >>"${DEPLOY_TEST_LOG}"
fi
[[ "${DEPLOY_TEST_MODE:-}" != missing-url ]] || exit 0
targets='["https://padm-shortlink.example.workers.dev"]'
if [[ -n "${customDomain}" && "${DEPLOY_TEST_MODE:-}" != missing-domain ]]; then
    targets='["https://padm-shortlink.example.workers.dev","go.example.com (custom domain)"]'
fi
printf '{"type":"deploy","version":1,"targets":%s}\n' "${targets}" >"${WRANGLER_OUTPUT_FILE_PATH:?}"
SH
chmod 755 "${fakeBin}/npx"
cat >"${fakeBin}/npm" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == ci && "$2" == --prefix && "$4" == --omit=dev &&
   "$5" == --ignore-scripts && "$6" == --no-audit && "$7" == --no-fund ]]
[[ -f "$3/package.json" && -f "$3/package-lock.json" ]]
[[ "${DEPLOY_TEST_MODE:-}" != dependency-failure ]] || exit 19
SH
chmod 755 "${fakeBin}/npm"
printf '#!/usr/bin/env bash\nexit 0\n' >"${fakeBin}/qrencode"
chmod 755 "${fakeBin}/qrencode"
export PATH="${fakeBin}:${PATH}"
stateDir="${project}/.state"
bash -n "${root}/deploy.sh" "${root}/deploy.test.sh"
shellcheck --severity=error "${root}/deploy.sh" "${root}/deploy.test.sh"
bash "${project}/deploy.sh" >"${tmp}/output"
key=$(<"${stateDir}/api-key")
[[ "${key}" =~ ^[0-9a-f]{64}$ ]]
[[ "$(stat -c '%a' "${stateDir}/api-key")" == 600 ]]
[[ ! -e "${stateDir}/vps.env" && ! -e "${stateDir}/cloudflare.age" ]]
[[ "$(stat -c '%a' "${PADM_INSTALL_DIR}/qr-shortener.json")" == 600 ]]
[[ "$(stat -c '%a' "${PADM_INSTALL_DIR}")" == 755 ]]
[[ "$(jq -r .api_key "${PADM_INSTALL_DIR}/qr-shortener.json")" == "${key}" ]]
[[ "$(jq -r .url "${PADM_INSTALL_DIR}/qr-shortener.json")" == https://padm-shortlink.example.workers.dev ]]
[[ "$(stat -c '%a' "${stateDir}")" == 700 ]]
! grep -qF "${key}" "${tmp}/output"
grep -q 'https://padm-shortlink.example.workers.dev' "${tmp}/output"
! grep -q $'\033' "${tmp}/output"
grep -qF '[4/4] 保存配置' "${tmp}/output"
[[ -z "$(find "${stateDir}" -name '.tmp-deploy.*' -print -quit)" ]]
printf 'export PADM_QR_SHORTENER_URL=https://old.example.com\nexport PADM_QR_SHORTENER_API_KEY=%s\n' \
    "${key}" >"${tmp}/previous.env"
cp -- "${PADM_INSTALL_DIR}/qr-shortener.json" "${tmp}/previous.json"
# 新进程不继承短链环境变量，也能通过 padm 的实际输出入口使用部署配置。
env -u PADM_QR_SHORTENER_URL -u PADM_QR_SHORTENER_API_KEY \
    bash -c '
        set -euo pipefail
        source "$1/shell/core/bootstrap.sh"
        qrencode() { cat; }
        tput() { printf "80\n"; }
        warnCard() { printf "%s\n" "$*" >&2; return 1; }
        menuLine() { :; }
        curl() {
            while (($#)); do
                if [[ "$1" == -H && "$2" == @* ]]; then
                    [[ "$(<"${2#@}")" == "Authorization: Bearer $(jq -r .api_key "${PADM_INSTALL_DIR}/qr-shortener.json")" ]]
                fi
                shift
            done
            cat >/dev/null
            printf 201
        }
        result=$(showShareLinkQRCode "vless://test-node")
        [[ "${result}" =~ ^https://padm-shortlink.example.workers.dev/s/[0-9a-f]{32}$ ]]
    ' bash "${root}/../.."
chmod 644 "${stateDir}/api-key"
chmod 750 "${PADM_INSTALL_DIR}"
bash "${project}/deploy.sh" >"${tmp}/output"
[[ "$(stat -c '%a' "${PADM_INSTALL_DIR}")" == 750 ]]
[[ "$(<"${stateDir}/api-key")" == "${key}" ]]
[[ "$(stat -c '%a' "${stateDir}/api-key")" == 600 ]]
[[ "$(grep -c 'created-kv' "${DEPLOY_TEST_LOG}")" == 1 ]]
cp -- "${tmp}/previous.env" "${stateDir}/vps.env"
for mode in failure missing-url dependency-failure; do
    status=0
    DEPLOY_TEST_MODE="${mode}" bash "${project}/deploy.sh" >"${tmp}/output" 2>"${tmp}/error" || status=$?
    [[ "${status}" != 0 ]]
    grep -q '部署中止 · Worker 部署' "${tmp}/error"
    if [[ "${mode}" == failure ]]; then [[ "${status}" == 17 ]]; fi
    if [[ "${mode}" == dependency-failure ]]; then [[ "${status}" == 19 ]]; fi
    ! grep -q '部署完成' "${tmp}/output"
    cmp "${tmp}/previous.env" "${stateDir}/vps.env"
    cmp "${tmp}/previous.json" "${PADM_INSTALL_DIR}/qr-shortener.json"
    [[ "$(<"${stateDir}/api-key")" == "${key}" ]]
    [[ -z "$(find "${stateDir}" -name '.tmp-deploy.*' -print -quit)" ]]
done
# 配置目录不可写入时保留原配置及旧环境文件，不输出完成。
status=0
PADM_INSTALL_DIR="${PADM_INSTALL_DIR}/qr-shortener.json" \
    bash "${project}/deploy.sh" >"${tmp}/output" 2>"${tmp}/error" || status=$?
[[ "${status}" != 0 ]]
grep -q 'padm 配置保存失败' "${tmp}/error"
grep -q '部署中止 · 保存配置' "${tmp}/error"
cmp "${tmp}/previous.json" "${PADM_INSTALL_DIR}/qr-shortener.json"
cmp "${tmp}/previous.env" "${stateDir}/vps.env"
[[ -z "$(find "${PADM_INSTALL_DIR}" -name '.qr-shortener.*' -print -quit)" ]]
[[ -z "$(find "${stateDir}" -name '.tmp-deploy.*' -print -quit)" ]]
mv -- "${stateDir}/api-key" "${tmp}/saved-key"
status=0
bash "${project}/deploy.sh" >"${tmp}/output" 2>"${tmp}/error" || status=$?
[[ "${status}" != 0 && ! -e "${stateDir}/api-key" ]]
grep -q 'API Key 缺失' "${tmp}/error"
mv -- "${tmp}/saved-key" "${stateDir}/api-key"
printf 'invalid\n' >"${stateDir}/api-key"
status=0
bash "${project}/deploy.sh" >"${tmp}/output" 2>"${tmp}/error" || status=$?
[[ "${status}" != 0 ]]
grep -q 'API Key 文件无效' "${tmp}/error"
printf '%s\n' "${key}" >"${stateDir}/api-key"
for credentials in missing invalid; do
    status=0
    if [[ "${credentials}" == missing ]]; then
        CLOUDFLARE_API_TOKEN= CLOUDFLARE_ACCOUNT_ID= \
            setsid --wait bash "${project}/deploy.sh" >"${tmp}/output" 2>"${tmp}/error" || status=$?
        grep -q '无交互终端' "${tmp}/error"
    else
        CLOUDFLARE_ACCOUNT_ID=invalid \
            bash "${project}/deploy.sh" >"${tmp}/output" 2>"${tmp}/error" || status=$?
        grep -q 'Account ID 不是' "${tmp}/error"
    fi
    [[ "${status}" != 0 ]]
    cmp "${tmp}/previous.env" "${stateDir}/vps.env"
    [[ -z "$(find "${stateDir}" -name '.tmp-deploy.*' -print -quit)" ]]
done
getconf() { printf 'glibc 2.34\n'; }
export -f getconf
status=0
bash "${project}/deploy.sh" >"${tmp}/output" 2>"${tmp}/error" || status=$?
unset -f getconf
[[ "${status}" != 0 ]]
grep -q 'glibc 2.35+' "${tmp}/error"
grep -q '部署中止 · 环境准备' "${tmp}/error"
cmp "${tmp}/previous.env" "${stateDir}/vps.env"
[[ -z "$(find "${stateDir}" -name '.tmp-deploy.*' -print -quit)" ]]
bash "${project}/deploy.sh" >"${tmp}/output"
[[ ! -e "${stateDir}/vps.env" && ! -e "${stateDir}/cloudflare.age" ]]

# 真实 age 和 80 列终端检查凭据加密、解锁、失败保护及隐藏输入。
mkdir -p "${tmp}/prompt-project"
cp -- "${root}/"{deploy.sh,worker.js,wrangler.toml,package.json,package-lock.json} "${tmp}/prompt-project/"
python3 - "${tmp}/prompt-project" <<'PY'
import fcntl
import hashlib
import json
import os
import pathlib
import pty
import re
import select
import shutil
import signal
import subprocess
import sys
import tarfile
import termios
import time
import struct
import unicodedata

project = pathlib.Path(sys.argv[1])
token = b"test-cloudflare-token"
account = b"0123456789abcdef0123456789abcdef"
passphrase = b"test-age-passphrase-never-echo"
cipher = project / ".state/cloudflare.age"
config = pathlib.Path(os.environ["PADM_INSTALL_DIR"]) / "qr-shortener.json"
calls_file = pathlib.Path(os.environ["DEPLOY_TEST_LOG"])

def run_terminal(command, env, prompts, redirected=False, data=None):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    pipes = os.pipe() if data is not None else None
    pid = os.fork()
    if pid == 0:
        os.close(master)
        os.setsid()
        fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        for fd in range(3):
            os.dup2(slave, fd)
        os.close(slave)
        if pipes:
            os.close(pipes[1])
            os.dup2(pipes[0], 0)
            os.close(pipes[0])
        if redirected:
            fd = os.open(project / "redirected.log", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            os.dup2(fd, 1)
            os.dup2(fd, 2)
            os.close(fd)
        os.execvpe(command[0], command, env)
    os.close(slave)
    if pipes:
        os.close(pipes[0])
        os.write(pipes[1], data)
        os.close(pipes[1])
    output = b""
    try:
        cursor = 0
        for prompt, value in prompts:
            deadline = time.monotonic() + 20
            while prompt not in output[cursor:] or not output.endswith(b": "):
                assert time.monotonic() < deadline, f"prompt timed out: {command}: {output!r}"
                if select.select([master], [], [], 1)[0]:
                    output += os.read(master, 65536)
            cursor = len(output)
            os.write(master, value + b"\n")
        deadline = time.monotonic() + 20
        while True:
            assert time.monotonic() < deadline, f"process timed out: {command}"
            if select.select([master], [], [], 1)[0]:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                output += chunk
        _, status = os.waitpid(pid, 0)
        pid = None
        if redirected:
            output += (project / "redirected.log").read_bytes()
        return os.waitstatus_to_exitcode(status), output
    finally:
        os.close(master)
        if pid is not None:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)

cases = [(mode, "") for mode in ("color", "no-color", "dumb")]
cases += [("invalid", domain) for domain in (
    "https://go.example.com", "go.example.com/s", "go.example.com:443",
    "*.example.com", "go..example.com", "-go.example.com", "go.example.com?x=1",
    "user@go.example.com", "go example.com", "127.0.0.1", "a" * 64 + ".example.com",
)]
cases += [
    ("domain-failure", "go.example.com"),
    ("domain-missing", "go.example.com"),
    ("custom", "GO.Example.COM"),
    ("reuse", ""),
    ("custom-env", ""),
    ("custom-redirect", ""),
]
for mode, domain in cases:
    saved = {name: (project / ".state" / name).read_bytes()
             for name in ("cloudflare.age", "custom-domain") if (project / ".state" / name).exists()}
    previous_config = config.read_bytes()
    calls = calls_file.read_bytes()
    env = dict(os.environ, CLOUDFLARE_API_TOKEN=token.decode() if mode == "custom-env" else "",
               CLOUDFLARE_ACCOUNT_ID=account.decode() if mode == "custom-env" else "",
               TERM="dumb" if mode == "dumb" else "xterm-256color",
               NO_COLOR="1" if mode == "no-color" else "", PADM_NO_COLOR="", CI="true",
               DEPLOY_TEST_MODE={"domain-failure": "failure", "domain-missing": "missing-domain"}.get(mode, ""))
    if mode == "color":
        prompts = [(b"Cloudflare API Token", token), (b"Cloudflare Account ID: ", account),
                   (b"Enter passphrase", passphrase), (b"Confirm passphrase", passphrase)]
    elif mode == "custom-env":
        prompts = []
    else:
        prompts = [(b"Enter passphrase", passphrase)]
    prompts.append(("  自定义域名（".encode(), domain.encode()))
    status, output = run_terminal(["bash", str(project / "deploy.sh")], env, prompts,
                                  redirected=mode in ("custom-env", "custom-redirect"))
    expected_success = mode not in ("invalid", "domain-failure", "domain-missing")
    assert (status == 0) == expected_success, output.decode(errors="replace")
    assert token not in output, "deployment Token echoed"
    assert passphrase not in output, "age passphrase echoed"
    assert (b"\x1b[1;36m" in output) == (mode not in ("no-color", "dumb", "custom-env", "custom-redirect")), f"wrong color mode: {mode}"
    plain = re.sub(rb"\x1b\[[0-9;]*[A-Za-z]", b"", output).decode()
    instructions = (
        "https://dash.cloudflare.com/profile/api-tokens",
        "Create Token（创建令牌）",
        "Create Custom Token（创建自定义令牌）",
        "Account（账户）→ Workers Scripts（Workers 脚本）",
        "Workers KV Storage（Workers KV 存储）",
        "Account Resources（账户资源）：Include（包含）→ Specific account（指定账户）",
        "Continue to summary（继续查看摘要）",
        "Account Details（账户详情）",
        "只显示一次",
    ) if mode == "color" else ()
    for instruction in instructions:
        assert instruction in plain, f"missing authorization instruction: {instruction}"
    if mode not in ("color", "custom-env"):
        assert "Cloudflare API Token" not in plain
        assert output.count(b"Enter passphrase") == 1, "saved credentials not unlocked exactly once"
    if mode == "custom-env":
        assert b"Enter passphrase" not in output
    if expected_success:
        for number, title in enumerate(("环境准备", "Cloudflare 授权", "Worker 部署", "保存配置"), 1):
            assert f"[{number}/4] {title}" in plain
    for line in plain.splitlines():
        width = sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in line)
        if mode != "invalid":
            assert width <= 80, f"line exceeds 80 columns: {line!r}"
    if not expected_success:
        assert config.read_bytes() == previous_config, "failed deployment replaced VPS config"
        for name in ("cloudflare.age", "custom-domain"):
            path = project / ".state" / name
            assert path.read_bytes() == saved[name] if name in saved else not path.exists()
        assert "部署完成" not in plain
        if mode == "invalid":
            assert "自定义域名无效" in plain
            assert calls_file.read_bytes() == calls
        if mode == "domain-failure":
            assert status == 17
    elif mode in ("custom", "reuse", "custom-env", "custom-redirect"):
        assert (project / ".state/custom-domain").read_text().strip() == "go.example.com"
        assert json.loads(config.read_text())["url"] == "https://go.example.com"
        assert calls_file.read_bytes()[len(calls):].count(b"domain=go.example.com") == 1
    else:
        assert not (project / ".state/custom-domain").exists()
    assert cipher.is_file() and (cipher.stat().st_mode & 0o777) == 0o600
    assert cipher.read_bytes().startswith(b"age-encryption.org/v1\n")
    if "cloudflare.age" in saved:
        assert cipher.read_bytes() == saved["cloudflare.age"], "reused credentials were reencrypted"
    assert not (project / ".state/vps.env").exists()
    for path in (project / ".state").rglob("*"):
        if path.is_file():
            assert token not in path.read_bytes(), f"deployment Token saved to {path}"
            assert passphrase not in path.read_bytes(), f"age passphrase saved to {path}"
    if mode == "color":
        print("shortlink-terminal-preview-start", flush=True)
        sys.stdout.buffer.write(output.replace(account, b"<Account ID>"))
        sys.stdout.flush()
        print("shortlink-terminal-preview-end", flush=True)

saved_cipher = cipher.read_bytes()
previous_config = config.read_bytes()
calls = calls_file.read_bytes()
env = dict(os.environ, CLOUDFLARE_API_TOKEN="", CLOUDFLARE_ACCOUNT_ID="", TERM="dumb", CI="true")
for mode in ("wrong-passphrase", "corrupt", "invalid-json", "partial-env", "no-terminal"):
    cipher.write_bytes(saved_cipher)
    if mode == "corrupt":
        cipher.write_bytes(saved_cipher[:-1])
    elif mode == "invalid-json":
        status, output = run_terminal(["age", "-p", "-o", str(cipher)], env, [
            (b"Enter passphrase", passphrase), (b"Confirm passphrase", passphrase)],
            data=b'{"token":"bad token","account_id":"0123456789abcdef0123456789abcdef"}')
        assert status == 0, output
    before = cipher.read_bytes()
    if mode == "no-terminal":
        result = subprocess.run(["setsid", "--wait", "bash", str(project / "deploy.sh")],
                                env=env, capture_output=True, timeout=20)
        status, output = result.returncode, result.stdout + result.stderr
    else:
        prompts = [] if mode == "partial-env" else [
            (b"Enter passphrase", b"wrong-passphrase" if mode == "wrong-passphrase" else passphrase)]
        case_env = dict(env, CLOUDFLARE_API_TOKEN=token.decode()) if mode == "partial-env" else env
        status, output = run_terminal(["bash", str(project / "deploy.sh")], case_env, prompts)
    assert status != 0, f"invalid credential case accepted: {mode}"
    assert config.read_bytes() == previous_config
    assert cipher.read_bytes() == before
    assert calls_file.read_bytes() == calls, "invalid credentials reached Cloudflare"
    assert not any((project / ".state").glob(".tmp-deploy.*"))
    assert token not in output and passphrase not in output
    if mode == "no-terminal":
        assert "解锁 Cloudflare 凭据需要交互终端" in output.decode()
    elif mode == "partial-env":
        assert "两项 Cloudflare 环境变量须同时设置" in output.decode()
    elif mode == "invalid-json":
        assert "解密内容不是有效的 Cloudflare 凭据" in output.decode()
    else:
        assert "凭据解锁失败" in output.decode()
cipher.write_bytes(saved_cipher)

# 完整环境变量优先于损坏密文，不解锁也不覆盖已保存文件。
cipher.write_bytes(b"broken ciphertext\n")
env = dict(env, CLOUDFLARE_API_TOKEN=token.decode(), CLOUDFLARE_ACCOUNT_ID=account.decode())
status, output = run_terminal(["bash", str(project / "deploy.sh")], env,
                              [("  自定义域名（".encode(), b"")])
assert status == 0 and b"Enter passphrase" not in output, output
assert cipher.read_bytes() == b"broken ciphertext\n"
cipher.write_bytes(saved_cipher)

# 口令确认失败时不发布、不保留密文或临时文件。
failed_project = project.parent / "age-encryption-failure"
failed_project.mkdir()
for name in ("deploy.sh", "worker.js", "wrangler.toml", "package.json", "package-lock.json"):
    shutil.copy(project / name, failed_project / name)
calls = calls_file.read_bytes()
previous_config = config.read_bytes()
case_env = dict(env, CLOUDFLARE_API_TOKEN="", CLOUDFLARE_ACCOUNT_ID="")
status, output = run_terminal(["bash", str(failed_project / "deploy.sh")], case_env, [
    (b"Cloudflare API Token", token), (b"Cloudflare Account ID: ", account),
    (b"Enter passphrase", passphrase), (b"Confirm passphrase", b"different-passphrase")])
assert status != 0 and b"passphrases didn't match" in output, output
assert not (failed_project / ".state/cloudflare.age").exists()
assert not any((failed_project / ".state").glob(".tmp-deploy.*"))
assert calls_file.read_bytes() == calls and config.read_bytes() == previous_config
assert token not in output and passphrase not in output

# 缺少系统 age 时，通过真实 tar 与 SHA-256 检查私有安装及失败保护。
archive = project.parent / "age-fixture.tar.gz"
with tarfile.open(archive, "w:gz") as package:
    package.add(shutil.which("age"), arcname="age/age")
archive_hash = hashlib.sha256(archive.read_bytes()).hexdigest()
launcher = r'''
command() {
    if [[ "$1" == -v && "${2:-}" == age ]]; then return 1; fi
    builtin command "$@"
}
curl() {
    local output= url=
    while (($#)); do
        case "$1" in
        -o) output=$2; shift 2 ;;
        https://*) url=$1; shift ;;
        *) shift ;;
        esac
    done
    [[ "${url}" == https://github.com/FiloSottile/age/releases/download/v1.3.2/age-v1.3.2-linux-amd64.tar.gz ||
       "${url}" == https://github.com/FiloSottile/age/releases/download/v1.3.2/age-v1.3.2-linux-arm64.tar.gz ]]
    case "${DEPLOY_TEST_AGE_MODE}" in
    download-failure) return 22 ;;
    checksum-failure) printf 'corrupt archive\n' >"${output}" ;;
    *) cp -- "${DEPLOY_TEST_AGE_ARCHIVE}" "${output}" ;;
    esac
}
export -f command curl
exec bash "${DEPLOY_TEST_AGE_PROJECT}/deploy.sh"
'''
for mode in ("fresh", "reuse", "download-failure", "checksum-failure"):
    install_project = project.parent / ("age-install" if mode in ("fresh", "reuse") else f"age-{mode}")
    if mode != "reuse":
        install_project.mkdir()
        for name in ("deploy.sh", "worker.js", "wrangler.toml", "package.json", "package-lock.json"):
            shutil.copy(project / name, install_project / name)
        script = install_project / "deploy.sh"
        script.write_text(re.sub(r"ageHash=[0-9a-f]{64}", f"ageHash={archive_hash}", script.read_text()))
    case_env = dict(env, CLOUDFLARE_API_TOKEN="", CLOUDFLARE_ACCOUNT_ID="",
                    DEPLOY_TEST_AGE_PROJECT=str(install_project), DEPLOY_TEST_AGE_ARCHIVE=str(archive),
                    DEPLOY_TEST_AGE_MODE=mode)
    if mode == "reuse":
        prompts = [(b"Enter passphrase", passphrase), ("  自定义域名（".encode(), b"")]
    else:
        prompts = [(b"Cloudflare API Token", token), (b"Cloudflare Account ID: ", account)]
        if mode == "fresh":
            prompts += [(b"Enter passphrase", passphrase), (b"Confirm passphrase", passphrase),
                        ("  自定义域名（".encode(), b"")]
    calls = calls_file.read_bytes()
    previous_config = config.read_bytes()
    status, output = run_terminal(["bash", "-c", launcher], case_env, prompts)
    assert (status == 0) == (mode in ("fresh", "reuse")), output
    assert token not in output and passphrase not in output
    state = install_project / ".state"
    if mode in ("fresh", "reuse"):
        assert (state / "age-v1.3.2/age").is_file()
        assert (state / "age-v1.3.2").stat().st_mode & 0o777 == 0o700
        assert (state / "cloudflare.age").stat().st_mode & 0o777 == 0o600
    else:
        assert not (state / "cloudflare.age").exists()
        assert config.read_bytes() == previous_config
        assert calls_file.read_bytes() == calls
    assert not any(state.glob(".tmp-deploy.*"))
    for path in state.rglob("*"):
        if path.is_file():
            assert token not in path.read_bytes(), f"deployment Token saved to {path}"
            assert passphrase not in path.read_bytes(), f"age passphrase saved to {path}"
PY
cp -- "${PADM_INSTALL_DIR}/qr-shortener.json" "${tmp}/domain-previous.json"
status=0
setsid --wait bash "${tmp}/prompt-project/deploy.sh" >"${tmp}/output" 2>"${tmp}/error" || status=$?
[[ "${status}" != 0 ]]
grep -q '自定义域名部署需要交互终端' "${tmp}/error"
cmp "${tmp}/domain-previous.json" "${PADM_INSTALL_DIR}/qr-shortener.json"

# 模拟全新 VPS，用真实 tar 和 SHA-256 验证下载、安装及失败路径。
for arch in x64 arm64; do
    nodeName="node-v22.23.3-linux-${arch}"
    mkdir -p "${tmp}/archive/${nodeName}/bin"
    printf '#!/usr/bin/env bash\nexec "${DEPLOY_TEST_REAL_NODE}" "$@"\n' \
        >"${tmp}/archive/${nodeName}/bin/node"
    cp -- "${fakeBin}/"{npx,npm} "${tmp}/archive/${nodeName}/bin/"
    chmod 755 "${tmp}/archive/${nodeName}/bin/node"
    tar -cJf "${tmp}/node-${arch}.tar.xz" -C "${tmp}/archive" "${nodeName}"
done
export DEPLOY_TEST_ROOT="${root}" DEPLOY_TEST_TMP="${tmp}"
cat >"${fakeBin}/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
url= output=
while (($#)); do
    case "$1" in
    -o) output=$2; shift 2 ;;
    https://*) url=$1; shift ;;
    *) shift ;;
    esac
done
printf '%s\n' "${url}" >>"${DEPLOY_TEST_TMP}/downloads"
[[ "${DEPLOY_TEST_BOOTSTRAP_MODE:-}" != download-failure ]] || exit 22
case "${url}" in
https://nodejs.org/dist/v22.23.3/node-v22.23.3-linux-*.tar.xz)
    if [[ "${DEPLOY_TEST_BOOTSTRAP_MODE:-}" == checksum-failure ]]; then
        printf 'corrupt download\n' >"${output}"
    else
        cp -- "${DEPLOY_TEST_TMP}/node-${DEPLOY_TEST_ARCH}.tar.xz" "${output}"
    fi
    ;;
https://api.github.com/repos/neil1123-vip/padm/commits/main)
    printf '{"sha":"0123456789abcdef0123456789abcdef01234567"}\n' >"${output}" ;;
https://raw.githubusercontent.com/neil1123-vip/padm/0123456789abcdef0123456789abcdef01234567/tools/shortlink-worker/*)
    cp -- "${DEPLOY_TEST_ROOT}/${url##*/}" "${output}" ;;
*) printf 'unexpected URL: %s\n' "${url}" >&2; exit 91 ;;
esac
SH
for manager in apt-get dnf yum; do
    cat >"${fakeBin}/${manager}" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' "${0##*/}" "$*" >>"${DEPLOY_TEST_TMP}/packages"
[[ "${DEPLOY_TEST_BOOTSTRAP_MODE:-}" != install-failure || "$*" != *install* ]] || exit 18
touch "${DEPLOY_TEST_TMP}/packages-ready"
SH
done
chmod 755 "${fakeBin}/"{curl,apt-get,dnf,yum}
command() {
    if [[ "${DEPLOY_TEST_BOOTSTRAP:-}" == true && "$1" == -v ]]; then
        case "$2" in
        node | npx | npm)
            if [[ "${DEPLOY_TEST_BOOTSTRAP_MODE:-}" != old-node &&
                "${PATH}" != "${DEPLOY_TEST_PROJECT}/.state/node-v22.23.3-linux-"* ]]; then
                return 1
            fi
            ;;
        qrencode) [[ -f "${DEPLOY_TEST_TMP}/packages-ready" ]] || return 1 ;;
        apt-get | dnf | yum) [[ "$2" == "${DEPLOY_TEST_MANAGER}" ]] || return 1 ;;
        esac
    fi
    builtin command "$@"
}
node() {
    if [[ "${DEPLOY_TEST_BOOTSTRAP_MODE:-}" == old-node &&
        "${PATH}" != "${DEPLOY_TEST_PROJECT}/.state/node-v22.23.3-linux-"* ]]; then
        return 1
    fi
    builtin command node "$@"
}
uname() {
    case "${1:-}" in
    -s) printf 'Linux\n' ;;
    -m) if [[ "${DEPLOY_TEST_ARCH}" == arm64 ]]; then printf 'aarch64\n'; else printf 'x86_64\n'; fi ;;
    *) builtin command uname "$@" ;;
    esac
}
export -f command node uname
export DEPLOY_TEST_BOOTSTRAP=true
for spec in apt-get:fresh:x64 dnf:old-node:arm64 yum:standalone:x64 \
    apt-get:install-failure:x64 apt-get:download-failure:x64 apt-get:checksum-failure:x64; do
    IFS=: read -r DEPLOY_TEST_MANAGER DEPLOY_TEST_BOOTSTRAP_MODE DEPLOY_TEST_ARCH <<<"${spec}"
    export DEPLOY_TEST_MANAGER DEPLOY_TEST_BOOTSTRAP_MODE DEPLOY_TEST_ARCH
    export DEPLOY_TEST_PROJECT="${tmp}/${DEPLOY_TEST_MANAGER}-${DEPLOY_TEST_BOOTSTRAP_MODE}"
    export PADM_INSTALL_DIR="${DEPLOY_TEST_PROJECT}/padm"
    mkdir -p "${DEPLOY_TEST_PROJECT}"
    cp -- "${root}/deploy.sh" "${DEPLOY_TEST_PROJECT}/"
    if [[ "${DEPLOY_TEST_BOOTSTRAP_MODE}" != standalone ]]; then
        cp -- "${root}/"{worker.js,wrangler.toml,package.json,package-lock.json} "${DEPLOY_TEST_PROJECT}/"
    fi
    if [[ "${DEPLOY_TEST_BOOTSTRAP_MODE}" == *failure ]]; then
        mkdir -p "${DEPLOY_TEST_PROJECT}/.state"
        cp -- "${tmp}/previous.env" "${DEPLOY_TEST_PROJECT}/.state/vps.env"
        cp -- "${stateDir}/"{api-key,wrangler.toml} "${DEPLOY_TEST_PROJECT}/.state/"
        mkdir -p "${PADM_INSTALL_DIR}"
        cp -- "${tmp}/previous.json" "${PADM_INSTALL_DIR}/qr-shortener.json"
    fi
    fixtureHash=$(sha256sum "${tmp}/node-${DEPLOY_TEST_ARCH}.tar.xz")
    fixtureHash=${fixtureHash%% *}
    sed -i -E "s/nodeHash=[0-9a-f]{64}/nodeHash=${fixtureHash}/" "${DEPLOY_TEST_PROJECT}/deploy.sh"
    rm -f -- "${tmp}/packages-ready" "${tmp}/packages" "${tmp}/downloads"
    status=0
    bash "${DEPLOY_TEST_PROJECT}/deploy.sh" >"${tmp}/output" 2>"${tmp}/error" || status=$?
    grep -q "${DEPLOY_TEST_MANAGER} .*install.*qrencode" "${tmp}/packages"
    case "${DEPLOY_TEST_BOOTSTRAP_MODE}" in
    *failure)
        [[ "${status}" != 0 ]]
        cmp "${tmp}/previous.env" "${DEPLOY_TEST_PROJECT}/.state/vps.env"
        cmp "${stateDir}/api-key" "${DEPLOY_TEST_PROJECT}/.state/api-key"
        cmp "${stateDir}/wrangler.toml" "${DEPLOY_TEST_PROJECT}/.state/wrangler.toml"
        cmp "${tmp}/previous.json" "${PADM_INSTALL_DIR}/qr-shortener.json"
        ! grep -q '部署完成' "${tmp}/output"
        ;;
    *)
        [[ "${status}" == 0 && ! -e "${DEPLOY_TEST_PROJECT}/.state/vps.env" &&
            ! -e "${DEPLOY_TEST_PROJECT}/.state/cloudflare.age" ]]
        [[ "$(stat -c '%a' "${PADM_INSTALL_DIR}/qr-shortener.json")" == 600 ]]
        [[ -x "${DEPLOY_TEST_PROJECT}/.state/node-v22.23.3-linux-${DEPLOY_TEST_ARCH}/bin/node" ]]
        ! grep -qF "${CLOUDFLARE_API_TOKEN}" "${tmp}/output"
        ! grep -r -qF "${CLOUDFLARE_API_TOKEN}" "${DEPLOY_TEST_PROJECT}/.state"
        if [[ "${DEPLOY_TEST_BOOTSTRAP_MODE}" == standalone ]]; then
            grep -q '/0123456789abcdef0123456789abcdef01234567/tools/shortlink-worker/worker.js' "${tmp}/downloads"
            grep -q '/0123456789abcdef0123456789abcdef01234567/tools/shortlink-worker/wrangler.toml' "${tmp}/downloads"
            grep -q '/0123456789abcdef0123456789abcdef01234567/tools/shortlink-worker/package-lock.json' "${tmp}/downloads"
        fi
        ;;
    esac
    [[ -z "$(find "${DEPLOY_TEST_PROJECT}/.state" -name '.tmp-deploy.*' -print -quit)" ]]
done
unset DEPLOY_TEST_BOOTSTRAP DEPLOY_TEST_BOOTSTRAP_MODE
unset -f command node uname

# 非 Linux 部署交付同一 JSON 配置格式，不再生成重复的环境备份。
nonLinux="${tmp}/non-linux"
mkdir -p "${nonLinux}/.state"
cp -- "${root}/"{deploy.sh,worker.js,wrangler.toml,package.json,package-lock.json} "${nonLinux}/"
cp -- "${tmp}/previous.env" "${nonLinux}/.state/vps.env"
uname() {
    if [[ "${1:-}" == -s ]]; then printf 'Darwin\n'; else builtin command uname "$@"; fi
}
export -f uname
bash "${nonLinux}/deploy.sh" >"${tmp}/output"
unset -f uname
[[ "$(stat -c '%a' "${nonLinux}/.state/qr-shortener.json")" == 600 ]]
[[ "$(jq -r .url "${nonLinux}/.state/qr-shortener.json")" == https://padm-shortlink.example.workers.dev ]]
[[ "$(jq -r .api_key "${nonLinux}/.state/qr-shortener.json")" == "$(<"${nonLinux}/.state/api-key")" ]]
[[ ! -e "${nonLinux}/.state/vps.env" && ! -e "${nonLinux}/.state/cloudflare.age" ]]
grep -q 'VPS 配置文件' "${tmp}/output"
! grep -qF "${CLOUDFLARE_API_TOKEN}" "${tmp}/output"

# 直接验证文档里的一行入口，下载失败或为空时不得启动部署。
entry="${tmp}/start-from-vps.sh"
awk '/^```bash$/ { code=1; next } code && /^```$/ { exit } code { print }' \
    "${root}/README.md" | sed "s|/root/padm-shortlink|${tmp}/entry-project|g" >"${entry}"
[[ -s "${entry}" ]]
[[ "$(wc -l <"${entry}")" == 1 ]]
bash -n "${entry}"
shellcheck --shell=bash --severity=error "${entry}"
for mode in fresh repeat download-failure empty-download; do
    (
        export DEPLOY_TEST_ENTRY_MODE="${mode}"
        export DEPLOY_TEST_TMP="${tmp}/entry-${mode}"
        mkdir -p "${DEPLOY_TEST_TMP}"
        testEntry="${DEPLOY_TEST_TMP}/start.sh"
        sed "s|${tmp}/entry-project|${DEPLOY_TEST_TMP}/project|g" "${entry}" >"${testEntry}"
        if [[ "${mode}" != fresh ]]; then
            mkdir -p "${DEPLOY_TEST_TMP}/project/.state"
            printf 'saved-key\n' >"${DEPLOY_TEST_TMP}/project/.state/api-key"
            printf 'touch "${DEPLOY_TEST_TMP}/started"\n' >"${DEPLOY_TEST_TMP}/project/deploy.sh"
        fi
        wget() {
            [[ "$1" == -O && "$3" == https://raw.githubusercontent.com/neil1123-vip/padm/main/tools/shortlink-worker/deploy.sh ]]
            printf 'touch "${DEPLOY_TEST_TMP}/started"\n' >"$2"
            case "${DEPLOY_TEST_ENTRY_MODE}" in
            download-failure) return 22 ;;
            empty-download) : >"$2" ;;
            esac
        }
        export -f wget
        status=0
        bash "${testEntry}" >"${DEPLOY_TEST_TMP}/output" 2>"${DEPLOY_TEST_TMP}/error" || status=$?
        if [[ "${mode}" == fresh || "${mode}" == repeat ]]; then
            [[ "${status}" == 0 && -f "${DEPLOY_TEST_TMP}/started" ]]
            [[ "$(stat -c '%a' "${DEPLOY_TEST_TMP}/project/deploy.sh")" == 700 ]]
        else
            [[ "${status}" != 0 && ! -e "${DEPLOY_TEST_TMP}/started" ]]
        fi
        if [[ "${mode}" != fresh ]]; then
            [[ "$(<"${DEPLOY_TEST_TMP}/project/.state/api-key")" == saved-key ]]
        fi
    )
done
printf '%s\n' 'shortlink deploy script: passed'
