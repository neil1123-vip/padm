#!/usr/bin/env bash

setupLocale() {
    if command -v locale >/dev/null 2>&1 && locale -a 2>/dev/null | grep -qi "^en_US\.utf8$"; then
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8
    else
        export LANG=C.UTF-8
        export LC_ALL=C.UTF-8
    fi
}

setupLocale

echoContent() {
    local color=$1
    local text=$2
    local code
    code=$(uiColorCode "${color}")
    if [[ -z "${code}" || -n "${PADM_NO_COLOR:-}" || -n "${NO_COLOR:-}" ]]; then
        ${echoType:-echo -e} "${printN:-}${text} "
        return
    fi
    ${echoType:-echo -e} "\033[${code}m${printN:-}${text} \033[0m"
}

uiColorCode() {
    case $1 in
    "red" | "error") printf '31' ;;
    "brightRed" | "danger") printf '1;31' ;;
    "skyBlue" | "cyan" | "title") printf '1;36' ;;
    "blue" | "number") printf '34' ;;
    "brightBlue") printf '1;34' ;;
    "green" | "ok") printf '32' ;;
    "brightGreen" | "recommended") printf '1;32' ;;
    "white" | "text") printf '37' ;;
    "brightWhite" | "value") printf '1;37' ;;
    "magenta" | "purple" | "section") printf '35' ;;
    "yellow" | "warn") printf '33' ;;
    "gray" | "muted") printf '90' ;;
    *) return 1 ;;
    esac
}

uiStyle() {
    local color=$1
    local text=$2
    local code
    code=$(uiColorCode "${color}")
    if [[ -z "${code}" || -n "${PADM_NO_COLOR:-}" || -n "${NO_COLOR:-}" ]]; then
        printf '%s' "${text}"
        return
    fi
    printf '\033[%sm%s\033[0m' "${code}" "${text}"
}

uiPrintLine() {
    printf '%b\n' "$1"
}

menuSection() {
    echoContent title "$1"
}

menuLine() {
    echoContent text "│ $1"
}

menuMutedLine() {
    echoContent muted "│ $1"
}

menuItemWithStyle() {
    local style=$1
    local number=$2
    local title=$3
    local desc=${4:-}
    printf -v number '%2s' "${number}"
    local line="│ $(uiStyle number "${number}.") $(uiStyle "${style}" "${title}")"
    if [[ -n "${desc}" ]]; then
        line+="  $(uiStyle value "${desc}")"
    fi
    uiPrintLine "${line}"
}

menuItem() { menuItemWithStyle text "$@"; }
menuRecommendedItem() { menuItemWithStyle recommended "$@"; }
menuReturnItem() { menuItemWithStyle cyan "$@"; }

menuDangerItem() {
    local number=$1
    local title=$2
    local desc=$3
    printf -v number '%2s' "${number}"
    uiPrintLine "│ $(uiStyle number "${number}.") $(uiStyle danger "${title}")  $(uiStyle warn "${desc}")"
}

statusCard() {
    local title=$1
    shift
    local color=${PADM_STATUS_CARD_COLOR:-title}
    printf '\r\033[K'
    echoContent "${color}" "\n┌─ ${title} ─────────────────────────────────────────"
    local line
    for line in "$@"; do
        menuLine "${line}"
    done
    menuClose
}

successCard() {
    PADM_STATUS_CARD_COLOR=ok statusCard "执行结果" "$@"
}

errorCard() {
    PADM_STATUS_CARD_COLOR=danger statusCard "错误" "$@"
}

warnCard() {
    PADM_STATUS_CARD_COLOR=warn statusCard "警告" "$@"
}

progressCard() {
    local step=$1
    local title=$2
    local total=${3:-${totalProgress}}
    echoContent title "\n┌─ ${title} ─────────────────────────────────────────"
    menuLine "进度 $(uiStyle recommended "${step}/${total}")"
    menuClose
}

menuClose() {
    echoContent title "└──────────────────────────────────────────────────"
}
