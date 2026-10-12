#!/usr/bin/env bash

if [[ "${PADM_STATIC_SITE_RENDERER_LOADED:-}" == 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_STATIC_SITE_RENDERER_LOADED=1

nginxStaticTemplateDefaults() {
    case "$1" in
    notes) staticSiteTitle=${staticSiteTitle:-Field Notes}; staticSiteAccent=${staticSiteAccent:-#28624b} ;;
    photos) staticSiteTitle=${staticSiteTitle:-Light and Distance}; staticSiteAccent=${staticSiteAccent:-#225e91} ;;
    docs) staticSiteTitle=${staticSiteTitle:-Pagekit}; staticSiteAccent=${staticSiteAccent:-#974338} ;;
    *) return 1 ;;
    esac
}

# 清单是随资源提交的合同；运行时不能用当前残缺目录重新生成“完整”清单。
nginxStaticTemplateAssetsValidate() {
    local root=$1 manifest line relative path unsafe theme
    local filePattern='^sites/(notes|photos|docs)/([a-z0-9][a-z0-9-]*\.html|assets/[a-z0-9][a-z0-9-]*\.(css|jpg|png))$'
    local linePattern="^([a-f0-9]{64})  (${filePattern#^})"
    local -A listed=()
    local -a paths=()
    manifest="${root}/sites.sha256"
    [[ -d "${root}" && ! -L "${root}" &&
        -d "${root}/sites" && ! -L "${root}/sites" &&
        -f "${manifest}" && ! -L "${manifest}" && -s "${manifest}" &&
        "$(stat -c %h -- "${manifest}")" == 1 ]] || return 1
    unsafe=$(find "${root}/sites" \( ! -type f ! -type d \) -print -quit) &&
        [[ -z "${unsafe}" ]] &&
        unsafe=$(find "${root}/sites" -type f -links +1 -print -quit) &&
        [[ -z "${unsafe}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" =~ ${linePattern} ]] || return 1
        relative=${BASH_REMATCH[2]}
        [[ -z "${listed[${relative}]:-}" &&
            -f "${root}/${relative}" && ! -L "${root}/${relative}" &&
            -s "${root}/${relative}" ]] || return 1
        listed["${relative}"]=1
        paths+=("${relative}")
    done <"${manifest}"
    for theme in notes photos docs; do
        for relative in "sites/${theme}/index.html" "sites/${theme}/404.html" \
            "sites/${theme}/about.html" "sites/${theme}/assets/style.css" \
            "sites/${theme}/assets/favicon.png"; do
            [[ -n "${listed[${relative}]:-}" ]] || return 1
        done
    done
    # 不允许未登记文件和私有目录混入公开主题，文件集合须与清单逐项一致。
    while IFS= read -r -d '' path; do
        relative=${path#"${root}/"}
        if [[ -d "${path}" ]]; then
            [[ "${relative}" =~ ^sites/(notes|photos|docs)(/assets)?$ ]] || return 1
        else
            [[ "${relative}" =~ ${filePattern} && -n "${listed[${relative}]:-}" ]] || return 1
        fi
    done < <(find "${root}/sites" -mindepth 1 -print0)
    (cd -- "${root}" && sha256sum --check --strict --status sites.sha256) || return 1
    printf '%s\n' "${paths[@]}"
}

# 站名写入 HTML 前转义，生成后的内容保持稳定，正文由主题自身提供。
renderNginxStaticTemplate() {
    local title=${staticSiteTitle:-} accent=${staticSiteAccent:-}
    [[ "${accent}" =~ ^#[0-9a-fA-F]{6}$ ]] &&
        jq -ne --arg title "${title}" '$title | length >= 2 and length <= 60 and
            test("[^[:space:]]") and (test("[[:cntrl:]]") | not)' >/dev/null || return 1
    title=$(printf '%s' "${title}" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' \
        -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g" -e 's/[&|\\]/\\&/g') || return 1
    local targetFile targetFiles placeholderStatus
    targetFiles=$(find "${nginxStaticPath}" -type f \( -name "*.html" -o -name "*.css" \)) || return 1
    while IFS= read -r targetFile; do
        [[ -f "${targetFile}" ]] || continue
        sed -i \
            -e "s|__SITE_TITLE__|${title}|g" \
            -e "s|__SITE_ACCENT__|${accent}|g" \
            "${targetFile}" || return 1
        placeholderStatus=0
        grep -Eq '__[A-Z_]+__' "${targetFile}" || placeholderStatus=$?
        [[ "${placeholderStatus}" == 1 ]] || return 1
    done <<<"${targetFiles}"
}
