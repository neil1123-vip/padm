#!/usr/bin/env bash
set -euo pipefail

scriptDir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
stateDir="${scriptDir}/.state"
keyFile="${stateDir}/api-key"
configFile="${stateDir}/wrangler.toml"
domainFile="${stateDir}/custom-domain"
credentialsFile="${stateDir}/cloudflare.age"
legacyEnvFile="${stateDir}/vps.env"
wrangler=(npx --yes wrangler@4.149.0)

deployLine() {
    local color=$1
    local text=$2
    if [[ -t 1 && "${TERM:-dumb}" != dumb && -z "${NO_COLOR:-}" && -z "${PADM_NO_COLOR:-}" ]]; then
        printf '\033[%sm%s\033[0m\n' "${color}" "${text}"
    else
        printf '%s\n' "${text}"
    fi
}

deployStage() {
    currentStage=$2
    printf '\n'
    deployLine '1;36' "  [$1/4] ${currentStage}"
}

runDir=
currentStage=初始化
deployCleanup() {
    local status=$?
    [[ -z "${runDir}" ]] || rm -rf -- "${runDir}"
    if ((status != 0)); then
        printf '\n' >&2
        deployLine '1;31' "  部署中止 · ${currentStage}" >&2
        printf '%s\n' '  请检查上方错误，修正后重新运行。' >&2
    fi
    return "${status}"
}
trap deployCleanup EXIT

printf '\n'
deployLine '1;36' '┌─ padm 短链部署 ──────────────────────────────'
deployLine '90' '│ Cloudflare Worker + KV'
deployLine '90' '└─────────────────────────────────────────────'
deployStage 1 环境准备

umask 077
[[ ! -L "${stateDir}" && ! -L "${keyFile}" && ! -L "${configFile}" &&
    ! -L "${domainFile}" && ! -L "${credentialsFile}" && ! -L "${legacyEnvFile}" ]] || {
    deployLine '1;31' '  .state 及其配置、凭据文件不能是符号链接' >&2
    exit 1
}
for file in "${credentialsFile}" "${legacyEnvFile}"; do
    [[ ! -e "${file}" || -f "${file}" ]] || {
        deployLine '1;31' '  凭据或旧环境配置路径不是普通文件' >&2
        exit 1
    }
done
mkdir -p "${stateDir}"
chmod 700 "${stateDir}"
runDir=$(mktemp -d "${stateDir}/.tmp-deploy.XXXXXX")

nodeReady() {
    command -v node >/dev/null 2>&1 &&
        command -v npx >/dev/null 2>&1 &&
        command -v npm >/dev/null 2>&1 &&
        node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)' >/dev/null 2>&1
}

system=$(uname -s)
privilege=()
if [[ "${system}" == Linux ]]; then
    glibcVersion=$(getconf GNU_LIBC_VERSION 2>/dev/null) || glibcVersion=
    if [[ ! "${glibcVersion}" =~ ^glibc[[:space:]]([0-9]+)\.([0-9]+)$ ]] ||
        ! ((BASH_REMATCH[1] > 2 || (BASH_REMATCH[1] == 2 && BASH_REMATCH[2] >= 35))); then
        deployLine '1;31' '  Wrangler 需要 glibc 2.35+，请用 Debian 12+/Ubuntu 22.04+ 部署。' >&2
        printf '%s\n' '  也可在另一台电脑部署，再传入 VPS 配置。' >&2
        exit 1
    fi
    case "$(uname -m)" in
    x86_64 | amd64)
        nodeArch=x64
        nodeHash=df450af89261115ef9f9e3830c3eeb2cc9213b63c720b1af623cb5dcbe2e02de
        ageArch=amd64
        ageHash=cbe24006683f8eb669266162894b9a522a1af52f2665fbc63a4bb032ed26ac10
        ;;
    aarch64 | arm64)
        nodeArch=arm64
        nodeHash=a44aeb94849a299b22df10b9e622ec2f605c2183501bc40590705131de7c740f
        ageArch=arm64
        ageHash=6b8dc4333c53a5a57c9e5834e3a48f92605d7154014cd07269ff3327db5d37f4
        ;;
    *) deployLine '1;31' '  自动部署支持 Linux x86_64 和 ARM64' >&2; exit 1 ;;
    esac
    if ((EUID != 0)); then
        command -v sudo >/dev/null 2>&1 || {
            deployLine '1;31' '  安装依赖及保存 padm 配置需要 root 或 sudo' >&2
            exit 1
        }
        privilege=(sudo)
    fi
    nodeName="node-v22.23.3-linux-${nodeArch}"
    # 私有运行时只影响本次部署，不替换 VPS 上已有的 Node.js。
    if [[ -d "${stateDir}/${nodeName}" ]]; then
        export PATH="${stateDir}/${nodeName}/bin:${PATH}"
    fi
    missing=false
    for tool in curl tar gzip xz openssl sha256sum qrencode; do
        command -v "${tool}" >/dev/null 2>&1 || missing=true
    done
    if [[ "${missing}" == true ]] || ! nodeReady ||
        [[ ! -s /etc/ssl/certs/ca-certificates.crt && ! -s /etc/pki/tls/certs/ca-bundle.crt ]]; then
        deployLine '90' '  安装部署依赖和终端二维码工具…'
        if command -v apt-get >/dev/null 2>&1; then
            "${privilege[@]}" apt-get update
            "${privilege[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
                -o DPkg::Lock::Timeout=120 \
                ca-certificates curl tar gzip xz-utils openssl coreutils libstdc++6 libatomic1 qrencode
        elif command -v dnf >/dev/null 2>&1; then
            "${privilege[@]}" dnf install -y \
                ca-certificates curl tar gzip xz openssl coreutils libstdc++ libatomic qrencode
        elif command -v yum >/dev/null 2>&1; then
            "${privilege[@]}" yum install -y \
                ca-certificates curl tar gzip xz openssl coreutils libstdc++ libatomic qrencode
        else
            deployLine '1;31' '  自动安装支持 apt-get、dnf 或 yum' >&2
            exit 1
        fi
    fi
    if ! nodeReady; then
        deployLine '90' '  下载并校验官方 Node.js 22.23.3…'
        nodeArchive="${nodeName}.tar.xz"
        curl -q --proto '=https' --proto-redir '=https' -fLsS --retry 2 --connect-timeout 10 --max-time 180 \
            "https://nodejs.org/dist/v22.23.3/${nodeArchive}" -o "${runDir}/${nodeArchive}"
        (cd -- "${runDir}"; printf '%s  %s\n' "${nodeHash}" "${nodeArchive}" | sha256sum -c -)
        tar -xJf "${runDir}/${nodeArchive}" -C "${runDir}"
        [[ ! -e "${stateDir}/${nodeName}" && ! -L "${stateDir}/${nodeName}" ]] || {
            deployLine '1;31' '  已有私有 Node.js 目录但无法运行，请检查文件和系统兼容性' >&2
            exit 1
        }
        mv -- "${runDir}/${nodeName}" "${stateDir}/${nodeName}"
        export PATH="${stateDir}/${nodeName}/bin:${PATH}"
    fi
fi
nodeReady || {
    deployLine '1;31' '  Node.js 无法运行，需要 Node.js 22+ 和 npm' >&2
    printf '%s\n' '  Linux 还需兼容的 glibc/libstdc++。' >&2
    exit 1
}
command -v openssl >/dev/null 2>&1 || {
    deployLine '1;31' '  缺少 openssl，请先安装 openssl' >&2
    exit 1
}
prepareAge() {
    if command -v age >/dev/null 2>&1; then
        ageCommand=$(command -v age)
        return
    fi
    local ageDir="${stateDir}/age-v1.3.2"
    [[ ! -L "${ageDir}" && ! -L "${ageDir}/age" ]] || {
        deployLine '1;31' '  私有 age 路径不能是符号链接' >&2
        return 1
    }
    if [[ ! -x "${ageDir}/age" ]]; then
        deployLine '90' '  下载并校验官方 age 1.3.2…'
        local archive="age-v1.3.2-linux-${ageArch}.tar.gz"
        curl -q --proto '=https' --proto-redir '=https' -fLsS --retry 2 --connect-timeout 10 --max-time 180 \
            "https://github.com/FiloSottile/age/releases/download/v1.3.2/${archive}" -o "${runDir}/${archive}" || return
        (cd -- "${runDir}"; printf '%s  %s\n' "${ageHash}" "${archive}" | sha256sum -c -) || return
        tar -xzf "${runDir}/${archive}" -C "${runDir}" age/age || return
        mkdir -p "${ageDir}"
        chmod 700 "${ageDir}"
        mv -- "${runDir}/age/age" "${ageDir}/age"
    fi
    ageCommand="${ageDir}/age"
}
deployStage 2 'Cloudflare 授权'
terminalReady=false
if { exec 3<>/dev/tty; } 2>/dev/null; then
    terminalReady=true
fi
if [[ "${system}" == Linux ]]; then
    saveCredentials=false
    if [[ -f "${credentialsFile}" && ( -z "${CLOUDFLARE_API_TOKEN:-}" || -z "${CLOUDFLARE_ACCOUNT_ID:-}" ) ]]; then
        [[ -z "${CLOUDFLARE_API_TOKEN:-}" && -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]] || {
            deployLine '1;31' '  两项 Cloudflare 环境变量须同时设置，或全部清除后解锁' >&2
            exit 1
        }
        [[ "${terminalReady}" == true ]] || {
            deployLine '1;31' '  解锁 Cloudflare 凭据需要交互终端，或同时设置两项环境变量' >&2
            exit 1
        }
        prepareAge
        printf '%s\n' '  已保存 Cloudflare 凭据，输入 age 口令解锁。' >&3
        if ! credentials=$("${ageCommand}" -d "${credentialsFile}"); then
            deployLine '1;31' '  凭据解锁失败；请检查口令或恢复 cloudflare.age，原配置保留' >&2
            exit 1
        fi
        if ! credentials=$(printf '%s' "${credentials}" | node -e '
let data = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => { data += chunk; });
process.stdin.on("end", () => {
  try {
    const value = JSON.parse(data);
    if (!/^[A-Za-z0-9_-]+$/.test(value.token) || typeof value.token !== "string" ||
        !/^[0-9a-fA-F]{32}$/.test(value.account_id) || typeof value.account_id !== "string")
      throw new Error("invalid credentials");
    process.stdout.write(`${value.token}\t${value.account_id}`);
  } catch {
    console.error("解密内容不是有效的 Cloudflare 凭据");
    process.exitCode = 1;
  }
});'); then
            exit 1
        fi
        IFS=$'\t' read -r CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID <<<"${credentials}"
        unset credentials
        chmod 600 "${credentialsFile}"
    fi
    if [[ -z "${CLOUDFLARE_API_TOKEN:-}" || -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
        if [[ "${terminalReady}" != true ]]; then
            deployLine '1;31' '  无交互终端，请设置 CLOUDFLARE_API_TOKEN 和 CLOUDFLARE_ACCOUNT_ID' >&2
            exit 1
        fi
        saveCredentials=true
        printf '%s\n' \
            '  获取 Token：打开 https://dash.cloudflare.com/profile/api-tokens' \
            '  选择 Create Token（创建令牌）→ Create Custom Token（创建自定义令牌）' \
            '  名称填 padm-shortlink' \
            '  权限 1：Account（账户）→ Workers Scripts（Workers 脚本）' \
            '  → Edit（编辑）' \
            '  权限 2：Account（账户）→ Workers KV Storage（Workers KV 存储）' \
            '  → Edit（编辑）' \
            '  Account Resources（账户资源）：Include（包含）→ Specific account（指定账户）' \
            '  → 目标 Cloudflare 账户' \
            '  Continue to summary（继续查看摘要）→ Create Token（创建令牌）' \
            '  复制 Token（只显示一次）' \
            '  Account ID：Workers & Pages（Workers 与 Pages）→ Account Details（账户详情）' \
            '  → Account ID（账户 ID）' >&3
        if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
            printf '%s' '  Cloudflare API Token（隐藏输入）: ' >&3
            read -r -s -u 3 CLOUDFLARE_API_TOKEN
            printf '\n' >&3
        fi
        if [[ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
            printf '%s' '  Cloudflare Account ID: ' >&3
            read -r -u 3 CLOUDFLARE_ACCOUNT_ID
        fi
    fi
    [[ "${CLOUDFLARE_API_TOKEN}" =~ ^[A-Za-z0-9_-]+$ &&
        "${CLOUDFLARE_ACCOUNT_ID}" =~ ^[0-9a-fA-F]{32}$ ]] || {
        deployLine '1;31' '  Cloudflare Token 为空或含非法字符，或 Account ID 不是 32 位十六进制' >&2
        exit 1
    }
    export CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID
    if [[ "${saveCredentials}" == true ]]; then
        prepareAge
        printf '%s\n' \
            '  用 age 加密保存部署凭据；设置口令后再次输入确认。' \
            '  直接回车会生成口令，请记下终端显示的口令。' \
            '  仅再次部署需要解锁，运行 padm 不需要口令。' >&3
        # 明文只通过管道传递；加密成功后原子替换，失败保留原密文。
        node -e 'process.stdout.write(JSON.stringify({
          token: process.env.CLOUDFLARE_API_TOKEN, account_id: process.env.CLOUDFLARE_ACCOUNT_ID
        }))' | "${ageCommand}" -p -o "${runDir}/cloudflare.age"
        chmod 600 "${runDir}/cloudflare.age"
        mv -- "${runDir}/cloudflare.age" "${credentialsFile}"
    fi
fi
customDomain=
if [[ -e "${domainFile}" ]]; then
    [[ -f "${domainFile}" ]] || { deployLine '1;31' '  自定义域名路径不是普通文件' >&2; exit 1; }
    customDomain=$(<"${domainFile}")
fi
if [[ "${terminalReady}" == true ]]; then
    printf '%s\n' \
        '  可选：填写当前 Cloudflare 账户下已激活域名的专用子域名' \
        '  例如 go.example.com；无需手动添加 DNS 或证书' >&3
    if [[ -n "${customDomain}" ]]; then
        printf '  已保存域名：%s\n' "${customDomain}" >&3
        printf '%s' '  自定义域名（回车复用）: ' >&3
    else
        printf '%s' '  自定义域名（可选，回车使用 workers.dev）: ' >&3
    fi
    read -r -u 3 domainInput
    customDomain=${domainInput:-${customDomain}}
fi
if [[ -n "${customDomain}" ]]; then
    customDomain=$(node - "${customDomain}" <<'NODE'
const domain = process.argv[2].toLowerCase();
const labels = domain.split(".");
if (domain.length > 253 || labels.length < 2 ||
    !labels.every((label) => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label)) ||
    !/[a-z]/.test(labels.at(-1))) {
  console.error("自定义域名无效：仅填写域名，不含协议、路径、端口或通配符");
  process.exit(1);
}
process.stdout.write(domain);
NODE
    )
    [[ "${terminalReady}" == true ]] || {
        deployLine '1;31' '  自定义域名部署需要交互终端，请在 SSH 终端重新运行' >&2
        exit 1
    }
fi

deployStage 3 'Worker 部署'
sourceDir=${scriptDir}
if [[ ! -f "${scriptDir}/worker.js" || ! -f "${scriptDir}/wrangler.toml" ||
      ! -f "${scriptDir}/package.json" || ! -f "${scriptDir}/package-lock.json" ]]; then
    deployLine '90' '  下载 Worker 源码和部署模板…'
    curl -q --proto '=https' --proto-redir '=https' -fLsS --retry 2 --connect-timeout 10 --max-time 60 \
        https://api.github.com/repos/neil1123-vip/padm/commits/main -o "${runDir}/commit.json"
    sourceRef=$(node -e 'const s = require(process.argv[1]).sha; if (!/^[0-9a-f]{40}$/.test(s)) process.exit(1); process.stdout.write(s)' \
        "${runDir}/commit.json")
    # 源码、模板和依赖锁定到同一提交，避免下载期间分支更新导致混用版本。
    for sourceFile in worker.js wrangler.toml package.json package-lock.json; do
        curl -q --proto '=https' --proto-redir '=https' -fLsS --retry 2 --connect-timeout 10 --max-time 60 \
            "https://raw.githubusercontent.com/neil1123-vip/padm/${sourceRef}/tools/shortlink-worker/${sourceFile}" \
            -o "${runDir}/${sourceFile}"
        [[ -s "${runDir}/${sourceFile}" ]] || { deployLine '1;31' "  下载文件为空：${sourceFile}" >&2; exit 1; }
    done
    sourceDir=${runDir}
fi
if [[ -e "${keyFile}" ]]; then
    [[ -f "${keyFile}" ]] || { deployLine '1;31' '  API Key 路径不是普通文件' >&2; exit 1; }
    apiKey=$(<"${keyFile}")
    deployLine '90' '  复用已有 API Key 和部署绑定'
else
    [[ ! -e "${configFile}" ]] || {
        deployLine '1;31' '  已有部署配置但 API Key 缺失，请恢复 .state/api-key 后重试' >&2
        exit 1
    }
    apiKey=$(openssl rand -hex 32)
    deployLine '90' '  创建 API Key 和部署绑定'
fi
[[ "${apiKey}" =~ ^[A-Za-z0-9_-]{32,128}$ ]] || {
    deployLine '1;31' "  API Key 文件无效：${keyFile}" >&2
    exit 1
}
if [[ ! -e "${keyFile}" ]]; then
    (set -o noclobber; printf '%s\n' "${apiKey}" >"${keyFile}")
fi
chmod 600 "${keyFile}"
if [[ ! -e "${configFile}" ]]; then
    cp -- "${sourceDir}/wrangler.toml" "${configFile}"
fi
cp -- "${sourceDir}/"{worker.js,package.json,package-lock.json} "${stateDir}/"
deployLine '90' '  安装 PNG 二维码依赖…'
npm ci --prefix "${stateDir}" --omit=dev --ignore-scripts --no-audit --no-fund
secretsFile="${runDir}/secrets.env"
outputFile="${runDir}/wrangler-output.jsonl"
printf 'API_KEY=%s\n' "${apiKey}" >"${secretsFile}"
: >"${outputFile}"

deployLine '90' '  发布 Worker，下面显示 Cloudflare 部署输出'
deployArgs=(deploy --config "${configFile}" --secrets-file "${secretsFile}" --keep-vars)
[[ -z "${customDomain}" ]] || deployArgs+=(--domains "${customDomain}")
(
    cd -- "${stateDir}"
    # Wrangler 负责浏览器授权或读取 CLOUDFLARE_API_TOKEN，不解析登录日志。
    if [[ -n "${customDomain}" ]]; then
        # 域名冲突必须由终端确认，防止重定向输出或 CI 默认覆盖已有绑定。
        CI=false WRANGLER_OUTPUT_FILE_PATH="${outputFile}" \
            "${wrangler[@]}" "${deployArgs[@]}" <&3 >&3 2>&3
    else
        WRANGLER_OUTPUT_FILE_PATH="${outputFile}" "${wrangler[@]}" "${deployArgs[@]}"
    fi
)

workerUrl=$(
    node - "${outputFile}" "${customDomain}" <<'NODE'
const fs = require("node:fs");
const entries = fs.readFileSync(process.argv[2], "utf8").split(/\r?\n/).filter(Boolean).map(JSON.parse);
const deployment = entries.reverse().find((entry) => entry.type === "deploy" && entry.version === 1);
const domain = process.argv[3];
const url = domain
  ? (deployment?.targets?.includes(`${domain} (custom domain)`) ? `https://${domain}` : undefined)
  : deployment?.targets?.find((value) =>
      /^https:\/\/[A-Za-z0-9][A-Za-z0-9.-]*(?::[0-9]{1,5})?\/?$/.test(value));
if (!url) {
  console.error("Worker 已部署，但未确认目标地址；请到 Cloudflare 控制台确认，原 VPS 配置保留");
  process.exit(1);
}
process.stdout.write(url.replace(/\/$/, ""));
NODE
)

deployStage 4 保存配置
if [[ "${system}" == Linux ]]; then
    padmConfigDir=${PADM_INSTALL_DIR:-/etc/padm}
    padmConfigDir=${padmConfigDir%/}
else
    padmConfigDir=${stateDir}
fi
# 在目标目录原子替换，保存失败时保留原配置；密钥不进入命令参数。
"${privilege[@]}" "$(command -v node)" - "${padmConfigDir}" "${workerUrl}" "${keyFile}" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const [dir, url, keyFile] = process.argv.slice(2);
let tempDir;
try {
  if (!path.isAbsolute(dir) || path.resolve(dir) !== dir || dir === "/") throw new Error("invalid directory");
  const created = fs.mkdirSync(dir, { recursive: true, mode: 0o755 });
  if (fs.realpathSync(dir) !== dir) throw new Error("symlink directory");
  if (created) fs.chmodSync(dir, 0o755);
  const target = path.join(dir, "qr-shortener.json");
  if (fs.existsSync(target) && !fs.lstatSync(target).isFile()) throw new Error("invalid config file");
  tempDir = fs.mkdtempSync(path.join(dir, ".qr-shortener."));
  const temp = path.join(tempDir, "config.json");
  fs.writeFileSync(temp, JSON.stringify({ url, api_key: fs.readFileSync(keyFile, "utf8").trim() }) + "\n", { mode: 0o600 });
  fs.renameSync(temp, target);
} catch {
  console.error("Worker 已部署，但 padm 配置保存失败；请检查目录权限后重试，原配置保留");
  process.exitCode = 1;
} finally {
  if (tempDir) fs.rmSync(tempDir, { recursive: true, force: true });
}
NODE
[[ ! -f "${legacyEnvFile}" ]] || rm -- "${legacyEnvFile}"
if [[ -n "${customDomain}" ]]; then
    printf '%s\n' "${customDomain}" >"${runDir}/custom-domain"
    mv -- "${runDir}/custom-domain" "${domainFile}"
fi
printf '\n'
deployLine '1;32' '┌─ 部署完成 ──────────────────────────────────'
printf '│ Worker 地址\n│ %s\n' "${workerUrl}"
if [[ "${system}" == Linux ]]; then
    printf '│ padm 配置\n│ %s/qr-shortener.json\n' "${padmConfigDir}"
    printf '│\n'
    deployLine '1;32' '│ 下一步：已安装 padm 时，运行 padm 查看二维码'
    printf '%s\n' '│ 重连 SSH 后仍自动生效'
else
    printf '│ VPS 配置文件\n│ %s/qr-shortener.json\n' "${stateDir}"
    printf '│\n'
    printf '%s\n' '│ 下一步：将配置传入 VPS 后启用，步骤见 README'
fi
deployLine '90' '└─────────────────────────────────────────────'
printf '\n'
deployLine '33' '  请保留 .state，里面含部署绑定和密钥，不要公开或提交。'
