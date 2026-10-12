#!/usr/bin/env bash

regressionStaticSiteFixture() {
    local root=$1
    # 恢复 bootstrap 覆盖过的真实文件操作，只在独立子 shell 中调用。
    source "${PROJECT_ROOT}/shell/core/runtime.sh"
    padmInstallCleanupTrap
    SCRIPT_DIR="${PROJECT_ROOT}"
    release=debian
    packageManager=apt
    nginxStaticPath="${root}/public"
    export PADM_STATIC_SITE_STATE_FILE="${root}/private/static-site.json"
    export PADM_STATIC_SITE_BACKUP_DIR="${root}/private/site-backups"
    mkdir -p "${root}/private"
}

regressionStaticSiteImportSource() {
    local path=$1
    mkdir -p "${path}/articles" "${path}/assets"
    printf '%s\n' '<!doctype html><title>My archive</title><h1>My archive</h1>' \
        '<a href="articles/entry.html">Read an entry</a><img src="assets/photo.png" alt="Landscape">' \
        '<script>window.original = "__SITE_TITLE__";</script>' >"${path}/index.html"
    printf '<title>Original entry</title>\r\n<p>Original text &amp; punctuation.</p>\r\n' \
        >"${path}/articles/entry.html"
    printf 'body { color: #123456; } /* __SITE_ACCENT__ */\n' >"${path}/assets/site.css"
    cp "${PROJECT_ROOT}/assets/static-sites/sites/notes/assets/favicon.png" "${path}/assets/photo.png"
}

regressionStaticSiteNginxDefaultSource() {
    local path=$1 index=${2:-index.html}
    local fixtures="${PROJECT_ROOT}/shell/regression/nginx-defaults"
    mkdir -p "${path}"
    cp "${fixtures}/${index}.txt" "${path}/index.html"
    cp "${fixtures}/50x.html.txt" "${path}/50x.html"
}

runStaticSiteAssetsRegression() (
    set -euo pipefail
    python3 "${PROJECT_ROOT}/shell/regression/static-site-assets.py" "${PROJECT_ROOT}"

    local root="${TMP_DIR}/static-site-assets-negative" broken
    mkdir -p "${root}"
    cp -a "${PROJECT_ROOT}/assets/static-sites/sites/notes" "${root}/valid"
    sed -i -e 's/__SITE_TITLE__/Reading Notes/g' -e 's/__SITE_ACCENT__/#28634e/g' \
        "${root}/valid/"*.html "${root}/valid/assets/style.css"
    python3 "${PROJECT_ROOT}/shell/regression/static-site-assets.py" \
        "${PROJECT_ROOT}" --installed "${root}/valid"
    for broken in missing-resource escape-resource remote-resource placeholder marker; do
        cp -a "${root}/valid" "${root}/${broken}"
        case "${broken}" in
        missing-resource) rm "${root}/${broken}/about.html" ;;
        escape-resource) printf '\n<img alt="" src="../outside.png">\n' >>"${root}/${broken}/index.html" ;;
        remote-resource) printf '\n<script src="https://example.invalid/runtime.js"></script>\n' >>"${root}/${broken}/index.html" ;;
        placeholder) printf '\n__UNSUPPORTED__\n' >>"${root}/${broken}/index.html" ;;
        marker) : >"${root}/${broken}/check" ;;
        esac
        regressionExpectFailure python3 "${PROJECT_ROOT}/shell/regression/static-site-assets.py" \
            "${PROJECT_ROOT}" --installed "${root}/${broken}" >"${root}/${broken}.log" 2>&1
    done
)

runStaticSiteToolsRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/static-site-tools" toolsInstalled=false missingBasePackages=() path
    regressionStaticSiteFixture "${root}"
    find() {
        if [[ "${toolsInstalled}" != true && "$*" == *-regextype* ]]; then
            return 1
        fi
        command find "$@"
    }
    realpath() {
        [[ "${toolsInstalled}" == true ]] || return 1
        command realpath "$@"
    }
    installPackageTracked() {
        [[ "$*" == "静态站点工具 coreutils findutils" ]]
        toolsInstalled=true
        printf 'package progress must not enter paths\n'
    }
    collectMissingBasePackages missingBasePackages
    [[ " ${missingBasePackages[*]} " == *" coreutils "* && " ${missingBasePackages[*]} " == *" findutils "* ]]
    path=$(nginxStaticSafePath)
    [[ "${path}" == "${nginxStaticPath}/" ]]
    # 路径校验在子 shell 中补依赖；直接 file:// 输入也须独立补齐。
    hysteria2ValidateMasquerade "file://${PROJECT_ROOT}/assets/static-sites/sites/notes/"
    [[ "${toolsInstalled}" == true ]]
    installPackageTracked() { return 99; }
    installNginxStaticTemplate notes
    nginxStaticSiteManaged
    toolsInstalled=false
    regressionExpectFailure nginxStaticSiteValidateDirectory "${nginxStaticPath}"
)

runStaticSiteStableInstallationRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/static-site-stable" before theme invalid
    regressionStaticSiteFixture "${root}"
    installNginxStaticTemplate notes
    nginxStaticSiteManaged
    [[ "$(nginxStaticSiteStateFile)" == "${PADM_STATIC_SITE_STATE_FILE}" ]]
    [[ "$(stat -c %a "${PADM_STATIC_SITE_STATE_FILE}")" == 600 ]]
    [[ "$(stat -c %a "${nginxStaticPath}")" == 755 ]]
    jq -e --arg path "${nginxStaticPath}" '
        .version == 1 and (.path | rtrimstr("/")) == $path and .theme == "notes" and
        (.title | type == "string" and length > 0) and
        (.accent | test("^#[0-9a-fA-F]{6}$")) and (.digest | test("^[0-9a-f]{64}$"))
    ' "${PADM_STATIC_SITE_STATE_FILE}" >/dev/null
    [[ ! -e "${nginxStaticPath}/check" && ! -e "${nginxStaticPath}/static-site.json" ]]
    before=$(cat "${PADM_STATIC_SITE_STATE_FILE}")
    installNginxStaticTemplate notes
    [[ "$(cat "${PADM_STATIC_SITE_STATE_FILE}")" == "${before}" ]]
    nginxBlog </dev/null
    [[ "$(cat "${PADM_STATIC_SITE_STATE_FILE}")" == "${before}" ]]
    for theme in photos docs; do
        installNginxStaticTemplate "${theme}"
        nginxStaticSiteManaged
        jq -e --arg theme "${theme}" '.theme == $theme' "${PADM_STATIC_SITE_STATE_FILE}" >/dev/null
        python3 "${PROJECT_ROOT}/shell/regression/static-site-assets.py" \
            "${PROJECT_ROOT}" --installed "${nginxStaticPath}"
    done
    before=$(cat "${PADM_STATIC_SITE_STATE_FILE}")
    for invalid in 1 unknown ../notes; do
        regressionExpectFailure installNginxStaticTemplate "${invalid}"
        nginxStaticSiteManaged
        [[ "$(cat "${PADM_STATIC_SITE_STATE_FILE}")" == "${before}" ]]
    done
)

runStaticSiteTitleRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/static-site-title" title invalid before theme title60 title61 stateBefore digestBefore
    regressionStaticSiteFixture "${root}"
    title='书与路 & <script>alert("x")</script> | \'
    for theme in notes photos docs; do
        installNginxStaticTemplate "${theme}" false "${title}"
        nginxStaticSiteManaged
        jq -e --arg title "${title}" '.title == $title' "${PADM_STATIC_SITE_STATE_FILE}" >/dev/null
        python3 - "${nginxStaticPath}" "${title}" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import sys

class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.text = []
        self.scripts = 0
    def handle_data(self, data):
        self.text.append(data)
    def handle_starttag(self, tag, attrs):
        self.scripts += tag == "script"

for path in Path(sys.argv[1]).glob("*.html"):
    page = Page()
    page.feed(path.read_text(encoding="utf-8"))
    assert sys.argv[2] in "".join(page.text), path
    assert page.scripts == 0, path
PY
        before=$(cat "${PADM_STATIC_SITE_STATE_FILE}")
        installNginxStaticTemplate "${theme}"
        [[ "$(cat "${PADM_STATIC_SITE_STATE_FILE}")" == "${before}" ]]
    done
    title60=$(python3 -c 'print("中" * 60)')
    installNginxStaticTemplate notes false "${title60}"
    nginxStaticSiteManaged
    jq -e --arg title "${title60}" '.title == $title and (.title | length) == 60' \
        "${PADM_STATIC_SITE_STATE_FILE}" >/dev/null
    stateBefore=$(cat "${PADM_STATIC_SITE_STATE_FILE}")
    digestBefore=$(nginxStaticSiteDigest "${nginxStaticPath}")
    title61=$(python3 -c 'print("中" * 61)')
    for invalid in '   ' "${title61}"; do
        regressionExpectFailure installNginxStaticTemplate notes false "${invalid}"
        [[ "$(cat "${PADM_STATIC_SITE_STATE_FILE}")" == "${stateBefore}" &&
            "$(nginxStaticSiteDigest "${nginxStaticPath}")" == "${digestBefore}" ]]
        nginxStaticSiteManaged
    done
    before=$(nginxStaticSiteDigest "${nginxStaticPath}")
    for invalid in x "$(printf '%061d' 0)" $'bad\nname' $'bad\tname'; do
        regressionExpectFailure installNginxStaticTemplate notes false "${invalid}"
        [[ "$(nginxStaticSiteDigest "${nginxStaticPath}")" == "${before}" ]]
        nginxStaticSiteManaged
        jq -e --arg title "${title60}" '.theme == "notes" and .title == $title' \
            "${PADM_STATIC_SITE_STATE_FILE}" >/dev/null
    done
)

runStaticSiteRendererValidationRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/static-site-renderer-validation" before stateBefore
    regressionStaticSiteFixture "${root}"
    installNginxStaticTemplate notes
    before=$(nginxStaticSiteDigest "${nginxStaticPath}")
    stateBefore=$(cat "${PADM_STATIC_SITE_STATE_FILE}")
    SCRIPT_DIR="${root}/source"
    mkdir -p "${SCRIPT_DIR}/assets/static-sites/sites"
    cp -a "${PROJECT_ROOT}/assets/static-sites/sites/photos" "${SCRIPT_DIR}/assets/static-sites/sites/"
    printf '\n__UNSUPPORTED__\n' >>"${SCRIPT_DIR}/assets/static-sites/sites/photos/index.html"
    regressionExpectFailure installNginxStaticTemplate photos
    SCRIPT_DIR="${PROJECT_ROOT}"
    grep() {
        [[ "$2" != '__[A-Z_]+__' ]] || return 2
        command grep "$@"
    }
    regressionExpectFailure installNginxStaticTemplate photos
    [[ "$(nginxStaticSiteDigest "${nginxStaticPath}")" == "${before}" &&
        "$(cat "${PADM_STATIC_SITE_STATE_FILE}")" == "${stateBefore}" ]]
    nginxStaticSiteManaged
)

runStaticSiteImportRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/static-site-import" source before backup stateBefore
    regressionStaticSiteFixture "${root}"
    source="${root}/source"
    regressionStaticSiteImportSource "${source}"
    before=$(nginxStaticSiteDigest "${source}")
    installNginxStaticTemplate "${source}"
    diff -r -- "${source}" "${nginxStaticPath}"
    [[ "$(nginxStaticSiteDigest "${source}")" == "${before}" ]]
    [[ "$(stat -c %a "${PADM_STATIC_SITE_STATE_FILE}")" == 600 ]]
    jq -e --arg path "${nginxStaticPath}" --arg digest "${before}" '
        .version == 1 and .path == $path and .theme == "custom" and
        .title == "" and .accent == "" and .digest == $digest
    ' "${PADM_STATIC_SITE_STATE_FILE}" >/dev/null
    regressionExpectFailure nginxStaticSiteManaged
    stateBefore=$(cat "${PADM_STATIC_SITE_STATE_FILE}")
    regressionExpectFailure installNginxStaticTemplate notes
    [[ "$(cat "${PADM_STATIC_SITE_STATE_FILE}")" == "${stateBefore}" ]]
    diff -r -- "${source}" "${nginxStaticPath}"
    hysteria2Masquerade=local
    hysteria2PrepareLocalSite
    [[ "${hysteria2Masquerade}" == "file://${nginxStaticPath}/" ]]
    diff -r -- "${source}" "${nginxStaticPath}"
    nginxStaticSiteRemove
    [[ ! -e "${PADM_STATIC_SITE_STATE_FILE}" ]]
    diff -r -- "${source}" "${nginxStaticPath}"
    installNginxStaticTemplate docs true
    [[ "$(stat -c %a "${PADM_STATIC_SITE_BACKUP_DIR}")" == 700 ]]
    backup=$(find "${PADM_STATIC_SITE_BACKUP_DIR}" -mindepth 1 -maxdepth 1 -type d -print)
    [[ -n "${backup}" && "${backup}" != *$'\n'* ]]
    diff -r -- "${source}" "${backup}"
    [[ "$(nginxStaticSiteDigest "${source}")" == "${before}" ]]
)

runStaticSiteImportBoundaryRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/static-site-import-boundary" source invalid unsafe before stateBefore sourceBefore
    regressionStaticSiteFixture "${root}"
    source="${root}/source"
    regressionStaticSiteImportSource "${source}"
    installNginxStaticTemplate notes
    before=$(nginxStaticSiteDigest "${nginxStaticPath}")
    stateBefore=$(cat "${PADM_STATIC_SITE_STATE_FILE}")
    sourceBefore=$(nginxStaticSiteDigest "${source}")
    for unsafe in hidden symlink hardlink fifo filename marker state missing-index; do
        invalid="${root}/${unsafe}"
        cp -a "${source}" "${invalid}"
        case "${unsafe}" in
        hidden) printf 'private setting\n' >"${invalid}/assets/.env" ;;
        symlink) ln -s "${source}/index.html" "${invalid}/assets/link.html" ;;
        hardlink) ln "${source}/index.html" "${invalid}/assets/link.html" ;;
        fifo) mkfifo "${invalid}/assets/pipe" ;;
        filename) printf 'unsafe filename\n' >"${invalid}/assets/two words.txt" ;;
        marker) : >"${invalid}/assets/check" ;;
        state) printf '{}\n' >"${invalid}/assets/static-site.json" ;;
        missing-index) rm "${invalid}/index.html" ;;
        esac
        regressionExpectFailure installNginxStaticTemplate "${invalid}" true
        [[ "$(nginxStaticSiteDigest "${nginxStaticPath}")" == "${before}" &&
            "$(cat "${PADM_STATIC_SITE_STATE_FILE}")" == "${stateBefore}" ]]
        diff -r -- "${source}/articles" "${invalid}/articles"
    done
    rm "${root}/hardlink/assets/link.html"
    [[ "$(nginxStaticSiteDigest "${source}")" == "${sourceBefore}" ]]

    regressionExpectFailure installNginxStaticTemplate "${nginxStaticPath}" true
    regressionStaticSiteImportSource "${nginxStaticPath}/nested"
    before=$(nginxStaticSiteDigest "${nginxStaticPath}")
    regressionExpectFailure installNginxStaticTemplate "${nginxStaticPath}/nested" true
    [[ "$(nginxStaticSiteDigest "${nginxStaticPath}")" == "${before}" &&
        "$(cat "${PADM_STATIC_SITE_STATE_FILE}")" == "${stateBefore}" ]]
    nginxStaticPath="${source}/public"
    installNginxStaticTemplate notes
    before=$(nginxStaticSiteDigest "${source}")
    stateBefore=$(cat "${PADM_STATIC_SITE_STATE_FILE}")
    regressionExpectFailure installNginxStaticTemplate "${source}" true
    [[ "$(nginxStaticSiteDigest "${source}")" == "${before}" &&
        "$(cat "${PADM_STATIC_SITE_STATE_FILE}")" == "${stateBefore}" ]]

    nginxStaticPath="${root}/independent"
    PADM_STATIC_SITE_STATE_FILE="${source}/private-state.json"
    printf 'private state bytes\n' >"${PADM_STATIC_SITE_STATE_FILE}"
    before=$(nginxStaticSiteDigest "${source}")
    regressionExpectFailure installNginxStaticTemplate "${source}"
    [[ ! -e "${nginxStaticPath}" && "$(<"${PADM_STATIC_SITE_STATE_FILE}")" == "private state bytes" &&
        "$(nginxStaticSiteDigest "${source}")" == "${before}" ]]
    PADM_STATIC_SITE_STATE_FILE="${root}/private/independent-state.json"
    regressionStaticSiteImportSource "${nginxStaticPath}"
    before=$(nginxStaticSiteDigest "${nginxStaticPath}")
    PADM_STATIC_SITE_BACKUP_DIR="${source}/old-backups"
    mkdir -p "${PADM_STATIC_SITE_BACKUP_DIR}"
    printf 'private original backup\n' >"${PADM_STATIC_SITE_BACKUP_DIR}/original.html"
    sourceBefore=$(nginxStaticSiteDigest "${source}")
    regressionExpectFailure installNginxStaticTemplate "${source}" true
    [[ "$(nginxStaticSiteDigest "${nginxStaticPath}")" == "${before}" &&
        "$(nginxStaticSiteDigest "${source}")" == "${sourceBefore}" && ! -e "${PADM_STATIC_SITE_STATE_FILE}" ]]
    nginxStaticPath="${root}/fresh-before-backup"
    regressionExpectFailure installNginxStaticTemplate "${source}" true
    [[ ! -e "${nginxStaticPath}" && ! -e "${PADM_STATIC_SITE_STATE_FILE}" &&
        "$(nginxStaticSiteDigest "${source}")" == "${sourceBefore}" ]]
)

runStaticSiteImportRollbackRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/static-site-import-rollback" source replacement sourceBefore stateBefore
    local failStateCommit=true originalCommit
    regressionStaticSiteFixture "${root}"
    source="${root}/source"
    replacement="${root}/replacement"
    regressionStaticSiteImportSource "${source}"
    cp -a "${source}" "${replacement}"
    printf 'Another original page\n' >"${replacement}/articles/other.html"
    sourceBefore=$(nginxStaticSiteDigest "${replacement}")
    installNginxStaticTemplate "${source}"
    stateBefore=$(cat "${PADM_STATIC_SITE_STATE_FILE}")
    originalCommit=$(declare -f commitGeneratedFile)
    eval "${originalCommit/commitGeneratedFile/regressionStaticSiteOriginalCommit}"
    commitGeneratedFile() {
        if [[ "$2" == "${PADM_STATIC_SITE_STATE_FILE}" && "${failStateCommit}" == true ]]; then
            failStateCommit=false
            return 1
        fi
        regressionStaticSiteOriginalCommit "$@"
    }
    regressionExpectFailure installNginxStaticTemplate "${replacement}" true
    diff -r -- "${source}" "${nginxStaticPath}"
    [[ "$(cat "${PADM_STATIC_SITE_STATE_FILE}")" == "${stateBefore}" &&
        "$(stat -c %a "${PADM_STATIC_SITE_STATE_FILE}")" == 600 &&
        "$(nginxStaticSiteDigest "${replacement}")" == "${sourceBefore}" ]]
    regressionExpectFailure nginxStaticSiteManaged
    ! compgen -G "${root}/.padm-site.*" >/dev/null

    nginxStaticPath="${root}/fresh"
    PADM_STATIC_SITE_STATE_FILE="${root}/private/fresh-state.json"
    failStateCommit=true
    regressionExpectFailure installNginxStaticTemplate "${replacement}"
    [[ ! -e "${nginxStaticPath}" && ! -e "${PADM_STATIC_SITE_STATE_FILE}" &&
        "$(nginxStaticSiteDigest "${replacement}")" == "${sourceBefore}" ]]
    ! compgen -G "${root}/.padm-site.*" >/dev/null
)

runStaticSiteOwnershipRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/static-site-ownership" before mode
    regressionStaticSiteFixture "${root}"
    installNginxStaticTemplate notes
    nginxStaticSiteRemove
    [[ ! -e "${nginxStaticPath}/index.html" && ! -e "${PADM_STATIC_SITE_STATE_FILE}" ]]

    for mode in changed added; do
        installNginxStaticTemplate notes
        if [[ "${mode}" == changed ]]; then
            printf '\n<!-- personal revision -->\n' >>"${nginxStaticPath}/index.html"
        else
            printf 'personal file\n' >"${nginxStaticPath}/personal.txt"
        fi
        before=$(sha256sum "${nginxStaticPath}/index.html")
        regressionExpectFailure nginxStaticSiteManaged
        regressionExpectFailure installNginxStaticTemplate photos
        [[ "$(sha256sum "${nginxStaticPath}/index.html")" == "${before}" ]]
        nginxStaticSiteRemove
        [[ -s "${nginxStaticPath}/index.html" && ! -e "${PADM_STATIC_SITE_STATE_FILE}" ]]
        [[ "${mode}" != added || "$(<"${nginxStaticPath}/personal.txt")" == "personal file" ]]
        rm -rf -- "${nginxStaticPath}"
    done

    mkdir -p "${nginxStaticPath}"
    printf '<!doctype html><title>My site</title>\n' >"${nginxStaticPath}/index.html"
    : >"${nginxStaticPath}/check"
    before=$(sha256sum "${nginxStaticPath}/index.html")
    nginxBlog </dev/null
    regressionExpectFailure installNginxStaticTemplate docs
    nginxStaticSiteRemove
    [[ "$(sha256sum "${nginxStaticPath}/index.html")" == "${before}" ]]
    [[ -e "${nginxStaticPath}/check" && ! -e "${PADM_STATIC_SITE_STATE_FILE}" ]]
)

runStaticSiteOwnershipBoundaryRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/static-site-ownership-boundary" before backup
    regressionStaticSiteFixture "${root}"
    PADM_STATIC_SITE_STATE_FILE="${nginxStaticPath}/static-site.json"
    regressionExpectFailure installNginxStaticTemplate notes
    [[ ! -e "${nginxStaticPath}" ]]
    PADM_STATIC_SITE_STATE_FILE="${root}/private/static-site.json"
    installNginxStaticTemplate notes
    cp -a "${nginxStaticPath}" "${root}/personal"
    nginxStaticPath="${root}/personal"
    before=$(sha256sum "${nginxStaticPath}/index.html")
    regressionExpectFailure nginxStaticSiteManaged
    nginxStaticSiteRemove
    [[ "$(sha256sum "${nginxStaticPath}/index.html")" == "${before}" ]]
    [[ -s "${root}/public/index.html" && -e "${PADM_STATIC_SITE_STATE_FILE}" ]]

    nginxStaticPath="${root}/custom"
    PADM_STATIC_SITE_STATE_FILE="${root}/private/custom-state.json"
    mkdir -p "${nginxStaticPath}/assets"
    printf '<!doctype html><title>My site</title>\n' >"${nginxStaticPath}/index.html"
    printf 'body { color: #123456; }\n' >"${nginxStaticPath}/assets/style.css"
    cp "${nginxStaticPath}/assets/style.css" "${root}/private/original.css"
    before=$(sha256sum "${nginxStaticPath}/index.html")
    nginxBlog </dev/null
    [[ "$(sha256sum "${nginxStaticPath}/index.html")" == "${before}" ]]
    [[ ! -e "${nginxStaticPath}/check" && ! -e "${PADM_STATIC_SITE_STATE_FILE}" ]]
    regressionExpectFailure nginxStaticSiteManaged
    nginxStaticSiteRemove
    [[ "$(sha256sum "${nginxStaticPath}/index.html")" == "${before}" ]]

    installNginxStaticTemplate docs true
    nginxStaticSiteManaged
    jq -e '.theme == "docs"' "${PADM_STATIC_SITE_STATE_FILE}" >/dev/null
    [[ "$(stat -c %a "${PADM_STATIC_SITE_BACKUP_DIR}")" == 700 ]]
    backup=$(find "${PADM_STATIC_SITE_BACKUP_DIR}" -mindepth 1 -maxdepth 1 -type d -print)
    [[ -n "${backup}" && "${backup}" != *$'\n'* ]]
    [[ "$(sha256sum "${backup}/index.html" | cut -d ' ' -f1)" == "${before%% *}" ]]
    cmp "${backup}/assets/style.css" "${root}/private/original.css"
)

runStaticSiteNginxDefaultRegression() (
    set -euo pipefail
    local base="${TMP_DIR}/static-site-nginx-default" root index errorPage before
    for index in index.html index-legacy.html; do
        for errorPage in present absent; do
            root="${base}/${index%.html}-${errorPage}"
            regressionStaticSiteFixture "${root}"
            regressionStaticSiteNginxDefaultSource "${nginxStaticPath}" "${index}"
            [[ "${errorPage}" != absent ]] || rm "${nginxStaticPath}/50x.html"
            nginxStaticSiteDefault
            before=$(nginxStaticSiteDigest "${nginxStaticPath}")
            nginxBlog </dev/null
            hysteria2Masquerade=local
            hysteria2PrepareLocalSite
            [[ "${hysteria2Masquerade}" == "file://${nginxStaticPath}/" &&
                "$(nginxStaticSiteDigest "${nginxStaticPath}")" == "${before}" &&
                ! -e "${PADM_STATIC_SITE_STATE_FILE}" ]]
            hysteria2Masquerade=docs
            hysteria2PrepareLocalSite
            [[ "${hysteria2Masquerade}" == "file://${nginxStaticPath}/" ]]
            nginxStaticSiteManaged
            jq -e '.theme == "docs"' "${PADM_STATIC_SITE_STATE_FILE}" >/dev/null
            [[ ! -e "${nginxStaticPath}/50x.html" && ! -e "${PADM_STATIC_SITE_BACKUP_DIR}" ]]
        done
    done
)

runStaticSiteNginxDefaultBoundaryRegression() (
    set -euo pipefail
    local base="${TMP_DIR}/static-site-nginx-default-boundary" root invalid
    for invalid in changed-index changed-error extra-file extra-directory hidden \
        named-directory extra-link index-link index-hardlink state broken-state; do
        root="${base}/${invalid}"
        regressionStaticSiteFixture "${root}"
        regressionStaticSiteNginxDefaultSource "${nginxStaticPath}"
        case "${invalid}" in
        changed-index) printf '\n<!-- Personal page -->\n' >>"${nginxStaticPath}/index.html" ;;
        changed-error) printf '\n<!-- Personal error page -->\n' >>"${nginxStaticPath}/50x.html" ;;
        extra-file) printf 'personal data\n' >"${nginxStaticPath}/personal.txt" ;;
        extra-directory) mkdir "${nginxStaticPath}/assets" ;;
        hidden) printf 'private setting\n' >"${nginxStaticPath}/.env" ;;
        named-directory)
            rm "${nginxStaticPath}/50x.html"
            mkdir "${nginxStaticPath}/50x.html"
            ;;
        extra-link) ln -s index.html "${nginxStaticPath}/linked.html" ;;
        index-link)
            rm "${nginxStaticPath}/index.html"
            ln -s "${PROJECT_ROOT}/shell/regression/nginx-defaults/index.html.txt" "${nginxStaticPath}/index.html"
            ;;
        index-hardlink) ln "${nginxStaticPath}/index.html" "${root}/original-hardlink.html" ;;
        state) printf '{"personal":"state"}\n' >"${PADM_STATIC_SITE_STATE_FILE}" ;;
        broken-state) ln -s "${root}/missing-state.json" "${PADM_STATIC_SITE_STATE_FILE}" ;;
        esac
        cp -a "${nginxStaticPath}" "${root}/original-site"
        cp -a "${root}/private" "${root}/original-private"
        regressionExpectFailure nginxStaticSiteDefault
        hysteria2Masquerade=photos
        regressionExpectFailure hysteria2PrepareLocalSite
        [[ "${hysteria2Masquerade}" == photos ]]
        diff -r --no-dereference -- "${root}/original-site" "${nginxStaticPath}"
        diff -r --no-dereference -- "${root}/original-private" "${root}/private"
        [[ "${invalid}" != index-hardlink || "$(stat -c %h "${nginxStaticPath}/index.html")" == 2 ]]
    done
)

runStaticSiteStateFailureRollbackRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/static-site-state-rollback" stateBefore siteBefore originalCommit
    local failStateCommit=true
    regressionStaticSiteFixture "${root}"
    installNginxStaticTemplate notes
    stateBefore=$(cat "${PADM_STATIC_SITE_STATE_FILE}")
    siteBefore=$(find "${nginxStaticPath}" -type f -print0 | sort -z | xargs -0 sha256sum)
    originalCommit=$(declare -f commitGeneratedFile)
    eval "${originalCommit/commitGeneratedFile/regressionStaticSiteOriginalCommit}"
    commitGeneratedFile() {
        if [[ "$2" == "${PADM_STATIC_SITE_STATE_FILE}" && "${failStateCommit}" == true ]]; then
            failStateCommit=false
            return 1
        fi
        regressionStaticSiteOriginalCommit "$@"
    }
    regressionExpectFailure installNginxStaticTemplate photos
    [[ "$(cat "${PADM_STATIC_SITE_STATE_FILE}")" == "${stateBefore}" ]]
    [[ "$(stat -c %a "${PADM_STATIC_SITE_STATE_FILE}")" == 600 ]]
    [[ "$(stat -c %a "${nginxStaticPath}")" == 755 ]]
    [[ "$(find "${nginxStaticPath}" -type f -print0 | sort -z | xargs -0 sha256sum)" == "${siteBefore}" ]]
    nginxStaticSiteManaged
    ! compgen -G "${root}/.padm-site.*" >/dev/null

    nginxStaticPath="${root}/fresh"
    PADM_STATIC_SITE_STATE_FILE="${root}/private/fresh-state.json"
    failStateCommit=true
    regressionExpectFailure installNginxStaticTemplate docs
    [[ ! -e "${nginxStaticPath}" && ! -e "${PADM_STATIC_SITE_STATE_FILE}" ]]
    ! compgen -G "${root}/.padm-site.*" >/dev/null

    nginxStaticPath="${root}/nginx-default"
    PADM_STATIC_SITE_STATE_FILE="${root}/private/nginx-default-state.json"
    regressionStaticSiteNginxDefaultSource "${nginxStaticPath}"
    cp -a "${nginxStaticPath}" "${root}/original-default"
    failStateCommit=true
    regressionExpectFailure installNginxStaticTemplate notes
    diff -r -- "${root}/original-default" "${nginxStaticPath}"
    [[ ! -e "${PADM_STATIC_SITE_STATE_FILE}" && ! -L "${PADM_STATIC_SITE_STATE_FILE}" ]]
    nginxStaticSiteDefault
    ! compgen -G "${root}/.padm-site.*" >/dev/null
)

runStaticSitePartialRollbackRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/static-site-partial-rollback" backup
    regressionStaticSiteFixture "${root}"
    installNginxStaticTemplate notes
    adapterCreateManagedRollbackBackup backup "${nginxStaticPath}" "${PADM_STATIC_SITE_STATE_FILE}"
    adapterRestoreManagedRollbackDirectory() { return 1; }
    local -A PADM_STATIC_SITE_ROLLBACK=(
        [active]=true [backup]="${backup}" [state]="${PADM_STATIC_SITE_STATE_FILE}"
    )
    regressionExpectFailure rollbackStaticSiteInstall
    [[ "$(stat -c %a "${PADM_STATIC_SITE_STATE_FILE}")" == 600 && -d "${backup}" ]]
    chmod 644 "${PADM_STATIC_SITE_STATE_FILE}"
    regressionExpectFailure restoreStaticSiteBackup "${backup}" "${PADM_STATIC_SITE_STATE_FILE}"
    [[ "$(stat -c %a "${PADM_STATIC_SITE_STATE_FILE}")" == 600 && -d "${backup}" ]]
)

runStaticSiteCoreTransactionRollbackRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/static-site-core-transaction" stateBefore siteBefore
    regressionStaticSiteFixture "${root}"
    installNginxStaticTemplate notes
    stateBefore=$(cat "${PADM_STATIC_SITE_STATE_FILE}")
    siteBefore=$(find "${nginxStaticPath}" -type f -print0 | sort -z | xargs -0 sha256sum)

    coreTemplateConfigBackupCreate() {
        local resultVar=$1
        local backup="${root}/core-config-backup"
        mkdir -p "${backup}"
        printf -v "${resultVar}" '%s' "${backup}"
    }
    checkLogBackupRestore() { return 0; }
    xrayRunning() { return 1; }
    singBoxRunning() { return 1; }
    nginxRunning() { return 1; }
    singBoxInstalled() { return 1; }
    coreStartupServiceEnabled() { return 1; }
    coreTemplateRestoreServiceState() { return 0; }
    coreTransactionInstallThenFail() {
        installNginxStaticTemplate photos || return 1
        jq -e '.theme == "photos"' "${PADM_STATIC_SITE_STATE_FILE}" >/dev/null || return 1
        [[ "$(cat "${PADM_STATIC_SITE_STATE_FILE}")" != "${stateBefore}" ]] || return 1
        return 77
    }

    regressionExpectStatus 77 coreTemplateConfigTransaction xray coreTransactionInstallThenFail
    [[ "$(cat "${PADM_STATIC_SITE_STATE_FILE}")" == "${stateBefore}" ]]
    [[ "$(stat -c %a "${PADM_STATIC_SITE_STATE_FILE}")" == 600 ]]
    [[ "$(stat -c %a "${nginxStaticPath}")" == 755 ]]
    [[ "$(find "${nginxStaticPath}" -type f -print0 | sort -z | xargs -0 sha256sum)" == "${siteBefore}" ]]
    nginxStaticSiteManaged
    ! compgen -G "${root}/.padm-site.*" >/dev/null
    [[ ! -e "${root}/core-config-backup" ]]

    nginxStaticPath="${root}/nginx-default"
    PADM_STATIC_SITE_STATE_FILE="${root}/private/nginx-default-state.json"
    regressionStaticSiteNginxDefaultSource "${nginxStaticPath}" index-legacy.html
    cp -a "${nginxStaticPath}" "${root}/original-default"
    regressionExpectStatus 77 coreTemplateConfigTransaction sing-box coreTransactionInstallThenFail
    diff -r -- "${root}/original-default" "${nginxStaticPath}"
    [[ ! -e "${PADM_STATIC_SITE_STATE_FILE}" && ! -L "${PADM_STATIC_SITE_STATE_FILE}" ]]
    nginxStaticSiteDefault
    ! compgen -G "${root}/.padm-site.*" >/dev/null
    [[ ! -e "${root}/core-config-backup" ]]
)

runStaticSiteHysteria2Regression() (
    set -euo pipefail
    local root="${TMP_DIR}/static-site-hysteria2" invalid before unsafe
    regressionStaticSiteFixture "${root}"
    hysteria2Masquerade=local
    hysteria2ValidateMasquerade "${hysteria2Masquerade}" true
    regressionExpectFailure hysteria2ValidateMasquerade "${hysteria2Masquerade}"
    hysteria2PrepareLocalSite
    [[ "${hysteria2Masquerade}" == "file://${nginxStaticPath%/}/" ]]
    hysteria2ValidateMasquerade "${hysteria2Masquerade}"
    nginxStaticSiteManaged
    hysteria2Masquerade=photos
    hysteria2PrepareLocalSite
    jq -e '.theme == "photos"' "${PADM_STATIC_SITE_STATE_FILE}" >/dev/null
    hysteria2ValidateMasquerade "https://example.com/"
    hysteria2ValidateMasquerade "http://example.com/"
    for invalid in "file://${root}/missing/" "file:///etc/" "file://example.com/tmp/" \
        "file://${nginxStaticPath}/../" "ftp://example.com/" "https://" "unknown"; do
        regressionExpectFailure hysteria2ValidateMasquerade "${invalid}"
    done
    mkdir -p "${root}/linked"
    ln -s "${nginxStaticPath}/index.html" "${root}/linked/index.html"
    regressionExpectFailure hysteria2ValidateMasquerade "file://${root}/linked/"
    for unsafe in hidden asset-link hard-link; do
        mkdir -p "${root}/${unsafe}"
        printf '<title>A personal site</title>\n' >"${root}/${unsafe}/index.html"
        case "${unsafe}" in
        hidden) printf 'private setting\n' >"${root}/${unsafe}/.env" ;;
        asset-link) ln -s "${nginxStaticPath}/assets/style.css" "${root}/${unsafe}/style.css" ;;
        hard-link) ln "${nginxStaticPath}/index.html" "${root}/${unsafe}/article.html" ;;
        esac
        regressionExpectFailure hysteria2ValidateMasquerade "file://${root}/${unsafe}/"
    done

    nginxStaticPath="${root}/custom"
    mkdir -p "${nginxStaticPath}"
    printf 'custom content\n' >"${nginxStaticPath}/index.html"
    before=$(sha256sum "${nginxStaticPath}/index.html")
    hysteria2Masquerade=local
    hysteria2PrepareLocalSite
    [[ "${hysteria2Masquerade}" == "file://${nginxStaticPath}/" &&
        "$(sha256sum "${nginxStaticPath}/index.html")" == "${before}" ]]
    hysteria2Masquerade=docs
    regressionExpectFailure hysteria2PrepareLocalSite
    [[ "${hysteria2Masquerade}" == docs &&
        "$(sha256sum "${nginxStaticPath}/index.html")" == "${before}" ]]
)

runStaticSiteSignalRollbackRegression() (
    set -euo pipefail
    local base="${TMP_DIR}/static-site-signals" root signal phase stateBefore siteBefore status
    for signal in INT TERM; do
        for phase in directory state transaction; do
            root="${base}/${signal}-${phase}"
            regressionStaticSiteFixture "${root}"
            installNginxStaticTemplate notes
            stateBefore=$(cat "${PADM_STATIC_SITE_STATE_FILE}")
            siteBefore=$(nginxStaticSiteDigest "${nginxStaticPath}")
            status=0
            (
                padmInstallCleanupTrap
                if [[ "${phase}" == directory ]]; then
                    mv() {
                        command mv "$@" || return
                        [[ "$2" != "${nginxStaticPath%/}" ]] || kill -"${signal}" "${BASHPID}"
                    }
                    installNginxStaticTemplate photos
                elif [[ "${phase}" == state ]]; then
                    eval "$(declare -f commitGeneratedFile | sed '1s/commitGeneratedFile/staticSiteOriginalCommit/')"
                    commitGeneratedFile() {
                        staticSiteOriginalCommit "$@" || return
                        [[ "$2" != "${PADM_STATIC_SITE_STATE_FILE}" ]] || kill -"${signal}" "${BASHPID}"
                    }
                    installNginxStaticTemplate photos
                else
                    coreTemplateConfigBackupCreate() {
                        mkdir -p "${root}/core"
                        printf -v "$1" '%s' "${root}/core"
                    }
                    checkLogBackupRestore() { return 0; }
                    xrayRunning() { return 1; }
                    singBoxRunning() { return 1; }
                    coreTemplateRestoreServiceState() { return 0; }
                    staticSiteTransactionInterrupted() {
                        installNginxStaticTemplate photos || return 1
                        kill -"${signal}" "${BASHPID}"
                    }
                    coreTemplateConfigTransaction xray staticSiteTransactionInterrupted
                fi
            ) >"${root}/signal.log" 2>&1 || status=$?
            [[ "${status}" == "$([[ "${signal}" == INT ]] && printf 130 || printf 143)" ]] ||
                { cat "${root}/signal.log"; return 1; }
            [[ "$(cat "${PADM_STATIC_SITE_STATE_FILE}")" == "${stateBefore}" &&
                "$(nginxStaticSiteDigest "${nginxStaticPath}")" == "${siteBefore}" &&
                "$(stat -c %a "${nginxStaticPath}")" == 755 &&
                "$(stat -c %a "${PADM_STATIC_SITE_STATE_FILE}")" == 600 ]]
            nginxStaticSiteManaged
            ! compgen -G "${root}/.padm-site.*" >/dev/null
        done
    done
)

runStaticSiteNginxHttpRegression() (
    set -euo pipefail
    local root port theme status getLength headLength
    local nginxPid=
    # 独立夹具放在可遍历的 /tmp 下，不能修改 CI 宿主父目录的权限。
    root=$(mktemp -d /tmp/padm-static-site-http.XXXXXXXX)
    regressionStaticSiteFixture "${root}"
    padmRegisterCleanupPath "${root}"
    trap 'status=$?; [[ -z "${nginxPid}" ]] || { kill "${nginxPid}" 2>/dev/null || :; wait "${nginxPid}" 2>/dev/null || :; }; padmCleanupTempPaths "" "${status}"' EXIT
    command -v nginx >/dev/null
    command -v curl >/dev/null
    port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
    printf '%s\n' \
        'user nobody nogroup;' \
        'worker_processes 1;' \
        "pid ${root}/nginx.pid;" \
        "error_log ${root}/nginx.log;" \
        'events { worker_connections 32; }' \
        'http {' \
        '  include /etc/nginx/mime.types;' \
        '  access_log off;' \
        "  server { listen 127.0.0.1:${port}; root ${nginxStaticPath}; index index.html;" \
        '    error_page 404 /404.html;' \
        '    location / { try_files $uri $uri/ =404; }' \
        '  }' \
        '}' >"${root}/nginx.conf"
    nginx -t -p "${root}/" -c "${root}/nginx.conf"
    installNginxStaticTemplate notes
    # root 启动时仍由 nobody worker 验收，实际站点权限由安装器设置。
    chmod o+x "${root}"
    nginx -p "${root}/" -c "${root}/nginx.conf" -g 'daemon off;' &
    nginxPid=$!
    for theme in notes photos docs; do
        installNginxStaticTemplate "${theme}"
        curl --silent --show-error --fail --retry 10 --retry-connrefused --retry-delay 0 \
            --max-time 5 -D "${root}/get.headers" "http://127.0.0.1:${port}/" >"${root}/body"
        cmp "${root}/body" "${nginxStaticPath}/index.html"
        curl --silent --show-error --fail --head --max-time 5 \
            "http://127.0.0.1:${port}/" >"${root}/head.headers"
        grep -qi '^Content-Type: text/html' "${root}/get.headers"
        getLength=$(awk 'tolower($1) == "content-length:" {gsub("\r", "", $2); print $2}' "${root}/get.headers")
        headLength=$(awk 'tolower($1) == "content-length:" {gsub("\r", "", $2); print $2}' "${root}/head.headers")
        [[ "${getLength}" == "$(wc -c <"${nginxStaticPath}/index.html" | tr -d ' ')" &&
            "${getLength}" == "${headLength}" ]]
        curl --silent --show-error --fail --max-time 5 "http://127.0.0.1:${port}/assets/style.css" \
            >"${root}/stylesheet"
        cmp "${root}/stylesheet" "${nginxStaticPath}/assets/style.css"
        curl --silent --show-error --fail --max-time 5 -D "${root}/favicon.headers" \
            "http://127.0.0.1:${port}/assets/favicon.png" >"${root}/favicon"
        cmp "${root}/favicon" "${nginxStaticPath}/assets/favicon.png"
        grep -qi '^Content-Type: image/png' "${root}/favicon.headers"
        status=$(curl --silent --show-error --max-time 5 -o "${root}/missing.body" \
            -w '%{http_code}' "http://127.0.0.1:${port}/nested/absent")
        [[ "${status}" == 404 ]]
        cmp "${root}/missing.body" "${nginxStaticPath}/404.html"
        status=$(curl --silent --show-error --max-time 5 -o /dev/null -w '%{http_code}' \
            "http://127.0.0.1:${port}/check")
        [[ "${status}" == 404 ]]
        status=$(curl --silent --show-error --max-time 5 -o /dev/null -w '%{http_code}' \
            "http://127.0.0.1:${port}/static-site.json")
        [[ "${status}" == 404 ]]
    done
    regressionStaticSiteImportSource "${root}/source"
    installNginxStaticTemplate "${root}/source"
    local resource
    for resource in index.html articles/entry.html assets/site.css assets/photo.png; do
        curl --silent --show-error --fail --max-time 5 \
            "http://127.0.0.1:${port}/${resource}" >"${root}/import.body"
        cmp "${root}/import.body" "${root}/source/${resource}"
    done
    curl --silent --show-error --fail --head --max-time 5 \
        "http://127.0.0.1:${port}/" >"${root}/import.head"
    grep -qi '^Content-Type: text/html' "${root}/import.head"
    headLength=$(awk 'tolower($1) == "content-length:" {gsub("\r", "", $2); print $2}' "${root}/import.head")
    [[ "${headLength}" == "$(wc -c <"${root}/source/index.html" | tr -d ' ')" ]]
    status=$(curl --silent --show-error --max-time 5 -o "${root}/import.missing" \
        -w '%{http_code}' "http://127.0.0.1:${port}/nested/absent")
    [[ "${status}" == 404 ]]
    grep -q '404 Not Found' "${root}/import.missing"
    diff -r -- "${root}/source" "${nginxStaticPath}"
)

runStaticSitesRegression() {
    runRegressionStep static-site-assets runStaticSiteAssetsRegression
    runRegressionStep static-site-tools runStaticSiteToolsRegression
    runRegressionStep static-site-stable-install runStaticSiteStableInstallationRegression
    runRegressionStep static-site-title runStaticSiteTitleRegression
    runRegressionStep static-site-renderer-validation runStaticSiteRendererValidationRegression
    runRegressionStep static-site-import runStaticSiteImportRegression
    runRegressionStep static-site-import-boundary runStaticSiteImportBoundaryRegression
    runRegressionStep static-site-import-rollback runStaticSiteImportRollbackRegression
    runRegressionStep static-site-ownership runStaticSiteOwnershipRegression
    runRegressionStep static-site-ownership-boundary runStaticSiteOwnershipBoundaryRegression
    runRegressionStep static-site-nginx-default runStaticSiteNginxDefaultRegression
    runRegressionStep static-site-nginx-default-boundary runStaticSiteNginxDefaultBoundaryRegression
    runRegressionStep static-site-state-rollback runStaticSiteStateFailureRollbackRegression
    runRegressionStep static-site-partial-rollback runStaticSitePartialRollbackRegression
    runRegressionStep static-site-core-transaction-rollback runStaticSiteCoreTransactionRollbackRegression
    runRegressionStep static-site-hysteria2 runStaticSiteHysteria2Regression
    runRegressionStep static-site-signal-rollback runStaticSiteSignalRollbackRegression
    runRegressionStep static-site-nginx-http runStaticSiteNginxHttpRegression
}
