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
    case $1 in
    "red")
        ${echoType} "\033[31m${printN}$2 \033[0m"
        ;;
    "skyBlue")
        ${echoType} "\033[1;36m${printN}$2 \033[0m"
        ;;
    "green")
        ${echoType} "\033[32m${printN}$2 \033[0m"
        ;;
    "white")
        ${echoType} "\033[37m${printN}$2 \033[0m"
        ;;
    "magenta")
        ${echoType} "\033[31m${printN}$2 \033[0m"
        ;;
    "yellow")
        ${echoType} "\033[33m${printN}$2 \033[0m"
        ;;
    esac
}

menuLine() {
    echoContent skyBlue "│ $1"
}

menuItem() {
    local number=$1
    local title=$2
    local desc=$3
    printf -v number '%2s' "${number}"
    echoContent yellow "│ ${number}. ${title}  ${desc}"
}

menuDangerItem() {
    local number=$1
    local title=$2
    local desc=$3
    printf -v number '%2s' "${number}"
    echoContent red "│ ${number}. ${title}  ${desc}"
}

menuClose() {
    echoContent skyBlue "└──────────────────────────────────────────────────"
}
