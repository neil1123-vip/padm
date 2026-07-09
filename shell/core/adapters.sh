#!/usr/bin/env bash

adapterTmpPath() {
    local template=$1
    padmFallbackTmpFilePath "${template}"
}

adapterNginxRepoTemplate() {
    adapterTmpPath padm-nginx-repo.XXXXXX
}

adapterNginxPinTemplate() {
    adapterTmpPath padm-nginx-pin.XXXXXX
}

adapterNginxYumRepoTemplate() {
    adapterTmpPath padm-nginx-yum-repo.XXXXXX
}

adapterManagedRollbackTemplate() {
    adapterTmpPath padm-package-managed-backup.XXXXXX
}

adapterInstallLogPath() {
    padmResolveManagedAbsolutePath "${PADM_INSTALL_LOG:-/etc/padm/install.log}"
}

adapterInstallLogRecoverPath() {
    local installLog
    installLog=$(adapterInstallLogPath) || return 1
    printf '%s.dpkg-recover\n' "${installLog}"
}

adapterNginxAptKeyringFile() {
    printf '%s\n' "${PADM_NGINX_APT_KEYRING_FILE:-/usr/share/keyrings/nginx-archive-keyring.gpg}"
}

adapterNginxAptRepoFile() {
    printf '%s\n' "${PADM_NGINX_APT_REPO_FILE:-/etc/apt/sources.list.d/nginx.list}"
}

adapterNginxAptPinFile() {
    printf '%s\n' "${PADM_NGINX_APT_PIN_FILE:-/etc/apt/preferences.d/99nginx}"
}

adapterNginxYumRepoFile() {
    local yumReposDir=$1
    printf '%s\n' "${yumReposDir%/}/nginx.repo"
}

PADM_PACKAGE_MANAGED_ROLLBACK_DIRS=()
PADM_PACKAGE_MANAGED_ROLLBACK_FAILURES=

refreshAptAfterRepoChange() {
    if [[ "${release}" != "ubuntu" && "${release}" != "debian" ]]; then
        return
    fi
    waitAptProcess || return 1
    runWithTimeout 300 "${upgrade} >/dev/null 2>&1"
}

installAptKeyringFromUrl() {
    local url=$1
    local targetFile=$2
    local displayName=$3
    local stagedFile

    targetFile=$(padmResolveManagedAbsolutePath "${targetFile}") || failPackageInstallTransaction "${displayName} apt key 路径异常"
    padmCreateTempFileForTarget stagedFile "${targetFile}" aptkey || failPackageInstallTransaction "${displayName} apt key 临时文件创建失败"
    if ! curl -fsSL "${url}" | gpg --dearmor >"${stagedFile}"; then
        padmRemoveCleanupPath "${stagedFile}"
        failPackageInstallTransaction "${displayName} apt key 安装失败"
    fi
    commitGeneratedFile "${stagedFile}" "${targetFile}" 644 || {
        padmRemoveCleanupPath "${stagedFile}"
        failPackageInstallTransaction "${displayName} apt key 提交失败"
    }
}

commitRepoFile() {
    local tmpFile=$1
    local targetFile=$2
    local mode=${3:-644}
    local targetDir

    if [[ ! -s "${tmpFile}" ]]; then
        padmRemoveCleanupPath "${tmpFile}"
        return 1
    fi

    targetFile=$(padmResolveManagedAbsolutePath "${targetFile}") || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    targetDir=$(dirname -- "${targetFile}")
    padmEnsureSafeDirectory "${targetDir}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    commitGeneratedFile "${tmpFile}" "${targetFile}" "${mode}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

adapterCreateManagedRollbackBackup() {
    local resultVar=$1
    shift
    local backupDir
    local manifest
    local targetPath
    local backupFile
    local backupIndex=0

    padmCreateTempPath backupDir -d "$(adapterManagedRollbackTemplate)" || return 1
    manifest="${backupDir}/manifest"
    : >"${manifest}" || {
        padmRemoveCleanupPath "${backupDir}"
        return 1
    }
    for targetPath in "$@"; do
        [[ -n "${targetPath}" ]] || continue
        targetPath=$(padmResolveManagedAbsolutePath "${targetPath}") || {
            padmRemoveCleanupPath "${backupDir}"
            return 1
        }
        [[ ! -e "${targetPath}" || -f "${targetPath}" || -d "${targetPath}" ]] || {
            padmRemoveCleanupPath "${backupDir}"
            return 1
        }
        if [[ -d "${targetPath}" ]]; then
            printf -v backupFile '%s/%06d.dir' "${backupDir}" "${backupIndex}"
            backupIndex=$((backupIndex + 1))
            mkdir -p "${backupFile}" || {
                padmRemoveCleanupPath "${backupDir}"
                return 1
            }
            cp -a "${targetPath}/." "${backupFile}/" || {
                padmRemoveCleanupPath "${backupDir}"
                return 1
            }
            printf '%s\t%s\tdir\n' "${backupFile}" "${targetPath}" >>"${manifest}" || {
                padmRemoveCleanupPath "${backupDir}"
                return 1
            }
        elif [[ -f "${targetPath}" ]]; then
            printf -v backupFile '%s/%06d.backup' "${backupDir}" "${backupIndex}"
            backupIndex=$((backupIndex + 1))
            backupManagedFileToPath "${targetPath}" "${backupFile}" 644 || {
                padmRemoveCleanupPath "${backupDir}"
                return 1
            }
            printf '%s\t%s\tfile\n' "${backupFile}" "${targetPath}" >>"${manifest}" || {
                padmRemoveCleanupPath "${backupDir}"
                return 1
            }
        else
            printf -- '-\t%s\tmissing\n' "${targetPath}" >>"${manifest}" || {
                padmRemoveCleanupPath "${backupDir}"
                return 1
            }
        fi
    done
    printf -v "${resultVar}" '%s' "${backupDir}"
}

adapterRestoreManagedRollbackDirectory() {
    local backupPath=$1
    local targetPath=$2
    local restoreStage
    local targetParent
    local rollbackDir
    local rollbackPath
    local targetName

    backupPath=$(padmResolveCleanupPath "${backupPath}") || return 1
    targetPath=$(padmRequireSafeAbsolutePath "${targetPath}") || return 1
    [[ -d "${backupPath}" ]] || return 1

    targetParent=$(dirname -- "${targetPath}")
    targetName=$(basename -- "${targetPath}")
    mkdir -p "${targetParent}" || return 1
    padmCreateTempPath restoreStage -d "${targetParent%/}/.${targetName}.restore.XXXXXX" || return 1
    if ! cp -a "${backupPath}/." "${restoreStage}/"; then
        padmRemoveCleanupPath "${restoreStage}"
        return 1
    fi
    if [[ -e "${targetPath}" ]]; then
        padmCreateTempPath rollbackDir -d "${targetParent%/}/.${targetName}.rollback.XXXXXX" || {
            padmRemoveCleanupPath "${restoreStage}"
            return 1
        }
        rollbackPath="${rollbackDir}/${targetName}"
        if ! mv "${targetPath}" "${rollbackPath}"; then
            padmRemoveCleanupPath "${restoreStage}"
            padmRemoveCleanupPath "${rollbackDir}"
            return 1
        fi
        if mv "${restoreStage}" "${targetPath}"; then
            padmForgetCleanupPath "${restoreStage}"
            padmRemoveCleanupPath "${rollbackDir}"
            return 0
        fi
        if ! mv "${rollbackPath}" "${targetPath}" >/dev/null 2>&1; then
            padmRemoveCleanupPath "${restoreStage}"
            padmForgetCleanupPath "${rollbackDir}"
            return 1
        fi
        padmRemoveCleanupPath "${restoreStage}"
        padmRemoveCleanupPath "${rollbackDir}"
        return 1
    fi
    mv "${restoreStage}" "${targetPath}" || { padmRemoveCleanupPath "${restoreStage}"; return 1; }
    padmForgetCleanupPath "${restoreStage}"
}

adapterRestoreManagedRollbackBackup() {
    local backupDir=$1
    local manifest
    local backupFile
    local targetPath
    local state
    local status=0

    manifest="${backupDir}/manifest"
    [[ -f "${manifest}" ]] || return 1
    while IFS=$'\t' read -r backupFile targetPath state; do
        [[ -n "${targetPath}" ]] || continue
        case "${state}" in
        file)
            restoreManagedFileFromBackup "${backupFile}" "${targetPath}" 644 || status=1
            ;;
        dir)
            adapterRestoreManagedRollbackDirectory "${backupFile}" "${targetPath}" || status=1
            ;;
        missing)
            removeManagedPathIfPresent "${targetPath}" || status=1
            ;;
        *)
            status=1
            ;;
        esac
    done <"${manifest}"
    return "${status}"
}

adapterRegisterPackageManagedRollback() {
    local backupDir=$1
    [[ -n "${backupDir}" ]] || return 0
    PADM_PACKAGE_MANAGED_ROLLBACK_DIRS+=("${backupDir}")
}

adapterClearPackageManagedRollback() {
    local backupDir
    for backupDir in "${PADM_PACKAGE_MANAGED_ROLLBACK_DIRS[@]}"; do
        [[ -n "${backupDir}" ]] || continue
        padmRemoveCleanupPath "${backupDir}"
    done
    PADM_PACKAGE_MANAGED_ROLLBACK_DIRS=()
    PADM_PACKAGE_MANAGED_ROLLBACK_FAILURES=
}

adapterRollbackPackageManagedFiles() {
    local failedDirs=()
    local backupDir
    local index
    local rc=0

    PADM_PACKAGE_MANAGED_ROLLBACK_FAILURES=
    for ((index = ${#PADM_PACKAGE_MANAGED_ROLLBACK_DIRS[@]} - 1; index >= 0; index--)); do
        backupDir=${PADM_PACKAGE_MANAGED_ROLLBACK_DIRS[$index]}
        [[ -n "${backupDir}" ]] || continue
        if adapterRestoreManagedRollbackBackup "${backupDir}"; then
            padmRemoveCleanupPath "${backupDir}"
        else
            padmForgetCleanupPath "${backupDir}"
            failedDirs+=("${backupDir}")
            rc=1
        fi
    done
    PADM_PACKAGE_MANAGED_ROLLBACK_DIRS=()
    PADM_PACKAGE_MANAGED_ROLLBACK_FAILURES="${failedDirs[*]}"
    return "${rc}"
}

packageInstalled() {
    local packageName=$1

    case "${packageManager}" in
    apt)
        dpkg -s "${packageName}" >/dev/null 2>&1
        ;;
    yum)
        rpm -q "${packageName}" >/dev/null 2>&1
        ;;
    apk)
        apk info -e "${packageName}" >/dev/null 2>&1
        ;;
    *)
        return 1
        ;;
    esac
}

writeMissingPackages() {
    local tmpFile=$1
    local packageName

    shift
    for packageName in "$@"; do
        if ! packageInstalled "${packageName}"; then
            printf '%s\n' "${packageName}" >>"${tmpFile}"
        fi
    done
}

trackInstalledPackagesFromFile() {
    local tmpFile=$1
    local packageName

    [[ -f "${tmpFile}" ]] || return 0
    while IFS= read -r packageName; do
        [[ -n "${packageName}" ]] || continue
        if packageInstalled "${packageName}"; then
            PADM_INSTALLED_PACKAGES="${PADM_INSTALLED_PACKAGES:-} ${packageName}"
        fi
    done <"${tmpFile}"
    padmRemoveCleanupPath "${tmpFile}"
}

beginPackageInstallTransaction() {
    if [[ "${PADM_PACKAGE_TRANSACTION_ACTIVE:-}" == "true" ]]; then
        PADM_PACKAGE_TRANSACTION_STARTED=false
        return 0
    fi

    PADM_PACKAGE_TRANSACTION_ACTIVE=true
    PADM_PACKAGE_TRANSACTION_STARTED=true
    PADM_INSTALLED_PACKAGES=
    PADM_PACKAGE_ROLLBACK_FAILURES=
    PADM_PACKAGE_MANAGED_ROLLBACK_DIRS=()
    PADM_PACKAGE_MANAGED_ROLLBACK_FAILURES=
}

endPackageInstallTransaction() {
    if [[ "$1" == "true" ]]; then
        adapterClearPackageManagedRollback
        PADM_INSTALLED_PACKAGES=
        PADM_PACKAGE_ROLLBACK_FAILURES=
        PADM_PACKAGE_TRANSACTION_ACTIVE=
    fi
}

rollbackPackageInstallTransaction() {
    local packageName
    local failedPackages=()
    local rc=0
    PADM_PACKAGE_ROLLBACK_FAILURES=

    if [[ -z "${PADM_INSTALLED_PACKAGES:-}" ]]; then
        return 0
    fi

    for packageName in ${PADM_INSTALLED_PACKAGES}; do
        if ! ${removeType} "${packageName}" >/dev/null 2>&1; then
            failedPackages+=("${packageName}")
            rc=1
        fi
    done
    PADM_INSTALLED_PACKAGES=
    PADM_PACKAGE_ROLLBACK_FAILURES="${failedPackages[*]}"
    return "${rc}"
}

failPackageInstallTransaction() {
    local managedRollbackStatus=0
    local rollbackStatus=0
    local managedRollbackCount=${#PADM_PACKAGE_MANAGED_ROLLBACK_DIRS[@]}
    local manualCheckMessage
    if [[ "${managedRollbackCount}" -gt 0 ]]; then
        adapterRollbackPackageManagedFiles || managedRollbackStatus=$?
    fi
    rollbackPackageInstallTransaction || rollbackStatus=$?
    if [[ "${managedRollbackCount}" -eq 0 && "${rollbackStatus}" -eq 0 ]]; then
        errorCard "$1，已尝试回滚本次新增软件包"
    elif [[ "${managedRollbackCount}" -eq 0 ]]; then
        coreSetManualCheckMessage manualCheckMessage "回滚部分软件包失败" "${PADM_PACKAGE_ROLLBACK_FAILURES}"
        errorCard "$1，${manualCheckMessage}"
    elif [[ "${managedRollbackStatus}" -eq 0 && "${rollbackStatus}" -eq 0 ]]; then
        errorCard "$1，已尝试回滚本次新增软件包和系统源改动"
    elif [[ "${managedRollbackStatus}" -eq 0 ]]; then
        coreSetManualCheckMessage manualCheckMessage "已尝试回滚系统源改动，但部分软件包回滚失败" "${PADM_PACKAGE_ROLLBACK_FAILURES}"
        errorCard "$1，${manualCheckMessage}"
    elif [[ "${rollbackStatus}" -eq 0 ]]; then
        coreSetManualCheckMessage manualCheckMessage "已回滚本次新增软件包，但系统源改动恢复失败" "${PADM_PACKAGE_MANAGED_ROLLBACK_FAILURES}"
        errorCard "$1，${manualCheckMessage}"
    else
        errorCard "$1，系统源改动和软件包回滚均存在失败" "软件包：${PADM_PACKAGE_ROLLBACK_FAILURES}" "系统源备份：${PADM_PACKAGE_MANAGED_ROLLBACK_FAILURES}"
    fi
    exit 1
}

nextInstallProgressTitle() {
    local title=$1
    if [[ -n "${PADM_INSTALL_STEP_TOTAL:-}" ]]; then
        PADM_INSTALL_STEP_INDEX=$((PADM_INSTALL_STEP_INDEX + 1))
        if [[ ${PADM_INSTALL_STEP_INDEX} -gt ${PADM_INSTALL_STEP_TOTAL} ]]; then
            PADM_INSTALL_STEP_TOTAL=${PADM_INSTALL_STEP_INDEX}
        fi
        PADM_INSTALL_PROGRESS_TITLE=$(printf '工具依赖 %d/%d：%s' "${PADM_INSTALL_STEP_INDEX}" "${PADM_INSTALL_STEP_TOTAL}" "${title}")
    else
        PADM_INSTALL_PROGRESS_TITLE="${title}"
    fi
}

printInstallProgressLine() {
    printf '\r\033[K%s\n' "$1"
}

countInstallStep() {
    PADM_INSTALL_STEP_TOTAL=$((PADM_INSTALL_STEP_TOTAL + 1))
}

initInstallProgress() {
    PADM_INSTALL_STEP_INDEX=0
    PADM_INSTALL_STEP_TOTAL=0

    local missingBaseTools=false
    [[ "${rhelLike:-}" != "true" ]] && countInstallStep
    ! command -v sudo >/dev/null 2>&1 && missingBaseTools=true
    ! command -v wget >/dev/null 2>&1 && missingBaseTools=true
    ! command -v curl >/dev/null 2>&1 && missingBaseTools=true
    ! command -v unzip >/dev/null 2>&1 && missingBaseTools=true
    ! command -v socat >/dev/null 2>&1 && missingBaseTools=true
    ! command -v tar >/dev/null 2>&1 && missingBaseTools=true
    ! command -v crontab >/dev/null 2>&1 && missingBaseTools=true
    ! command -v jq >/dev/null 2>&1 && missingBaseTools=true
    ! command -v ld >/dev/null 2>&1 && missingBaseTools=true
    ! command -v openssl >/dev/null 2>&1 && missingBaseTools=true
    if ! command -v ping6 >/dev/null 2>&1 && ! command -v ping >/dev/null 2>&1; then
        missingBaseTools=true
    fi
    if ! command -v lsb_release >/dev/null 2>&1 && [[ "${release}" != "centos" ]]; then
        missingBaseTools=true
    fi
    ! command -v lsof >/dev/null 2>&1 && missingBaseTools=true
    ! command -v dig >/dev/null 2>&1 && missingBaseTools=true
    ! command -v iptables-save >/dev/null 2>&1 && missingBaseTools=true
    [[ "${missingBaseTools}" == "true" ]] && countInstallStep
    if ! protocolSelectionSkipsNginx "${selectCustomInstallType}"; then
        if ! nginx >/dev/null 2>&1; then
            if [[ "${packageManager}" == "apt" || "${packageManager}" == "yum" ]]; then
                countInstallStep
            fi
            countInstallStep
        else
            local nginxMinorVersion
            nginxMinorVersion=$(nginx -v 2>&1 | awk -F "[n][g][i][n][x][/]" '{print $2}' | awk -F "[.]" '{print $2}')
            [[ ${nginxMinorVersion:-0} -lt 14 ]] && countInstallStep
        fi
    fi
}

runPackageCommandWithProgress() {
    local title=$1
    local timeoutSeconds=$2
    local commandString=$3
    local logFile=$4
    local progressFile="${logFile}.progress"
    local progressTitle
    local lastLogLine=
    local staleLogCount=0
    local currentLogLine=
    local status=0

    nextInstallProgressTitle "${title}"
    progressTitle=${PADM_INSTALL_PROGRESS_TITLE}
    printInstallProgressLine "${progressTitle} 正在执行；完整日志：${logFile}"
    rm -f "${progressFile}"
    if command -v timeout >/dev/null 2>&1; then
        if command -v setsid >/dev/null 2>&1; then
            timeout "${timeoutSeconds}s" setsid bash -lc "${commandString}" </dev/null >"${progressFile}" 2>&1 &
        else
            timeout "${timeoutSeconds}s" bash -lc "${commandString}" </dev/null >"${progressFile}" 2>&1 &
        fi
    elif command -v setsid >/dev/null 2>&1; then
        setsid bash -lc "${commandString}" </dev/null >"${progressFile}" 2>&1 &
    else
        bash -lc "${commandString}" </dev/null >"${progressFile}" 2>&1 &
    fi
    local commandPid=$!
    local elapsed=0
    while kill -0 "${commandPid}" >/dev/null 2>&1; do
        sleep 1
        elapsed=$((elapsed + 1))
        [[ $((elapsed % 10)) -eq 0 ]] || continue
        if [[ -s "${progressFile}" ]]; then
            currentLogLine=$(tail -n 1 "${progressFile}")
            if [[ "${currentLogLine}" == "${lastLogLine}" ]]; then
                staleLogCount=$((staleLogCount + 1))
            else
                staleLogCount=0
                lastLogLine=${currentLogLine}
            fi
            if [[ ${staleLogCount} -ge 6 ]]; then
                printInstallProgressLine "${progressTitle} 已执行 ${elapsed}s；日志 60s 未变化，可能卡住：${currentLogLine}"
            else
                printInstallProgressLine "${progressTitle} 已执行 ${elapsed}s；最新日志：${currentLogLine}"
            fi
        elif [[ ${elapsed} -ge 120 ]]; then
            printInstallProgressLine "${progressTitle} 已执行 ${elapsed}s；最新日志：暂无输出，请查看 ${logFile} 或检查 apt/yum 锁和软件源网络"
        else
            printInstallProgressLine "${progressTitle} 已执行 ${elapsed}s；最新日志：暂无输出"
        fi
    done

    wait "${commandPid}"
    status=$?
    cat "${progressFile}" >>"${logFile}"
    if [[ ${status} -eq 124 ]]; then
        if [[ -s "${progressFile}" ]]; then
            printInstallProgressLine "${progressTitle} 超时退出；最后日志：$(tail -n 1 "${progressFile}")"
        else
            printInstallProgressLine "${progressTitle} 超时退出；未产生安装日志"
        fi
    fi
    rm -f "${progressFile}"
    return ${status}
}

allPackagesInstalled() {
    local packageName

    for packageName in "$@"; do
        packageInstalled "${packageName}" || return 1
    done
    return 0
}

recoverAptInstallAfterTimeout() {
    local displayName=$1
    local recoverLog
    local recoverCommand
    shift

    [[ "${packageManager}" == "apt" ]] || return 1
    allPackagesInstalled "$@" || return 1
    recoverLog=$(adapterInstallLogRecoverPath) || return 1
    padmEnsureSafeDirectory "$(dirname -- "${recoverLog}")" || return 1
    printf -v recoverCommand 'DEBIAN_FRONTEND=noninteractive dpkg --configure -a >"%s" 2>&1' "${recoverLog}"

    statusCard "${displayName}安装收尾" "软件包已安装，apt/dpkg 收尾阶段可能卡住，正在尝试恢复"
    pkill -TERM -x mandb >/dev/null 2>&1 || true
    runWithTimeout 120 "${recoverCommand}" || {
        statusCard "${displayName}安装收尾" "dpkg 收尾失败，日志：${recoverLog}"
        return 1
    }
    statusCard "${displayName}安装收尾" "dpkg 收尾完成，继续后续流程"
    return 0
}

diagnosePackageInstallFailure() {
    local installLog
    if [[ "${packageManager}" != "apt" ]]; then
        return 0
    fi
    installLog=$(adapterInstallLogPath 2>/dev/null || printf '%s\n' "${PADM_INSTALL_LOG:-/etc/padm/install.log}")

    statusCard "软件包安装排障" \
        "可查看日志：${installLog}" \
        "可检查锁：lsof /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock" \
        "可检查未完成配置：dpkg --audit" \
        "若卡在 man-db trigger：ps -ef | grep '[m]andb\\|[d]pkg\\|[a]pt'"
}

installPackageTracked() {
    local displayName=$1
    shift
    local packages=("$@")
    local missingPackagesFile
    local installLog

    local packageTimeout=300

    installLog=$(adapterInstallLogPath) || failPackageInstallTransaction "${displayName}安装日志路径异常"
    padmEnsureSafeDirectory "$(dirname -- "${installLog}")" || failPackageInstallTransaction "${displayName}安装日志目录创建失败"
    padmCreateTempPath missingPackagesFile "$(adapterTmpPath padm-packages.XXXXXX)" || failPackageInstallTransaction "${displayName}安装状态记录失败"
    writeMissingPackages "${missingPackagesFile}" "${packages[@]}"
    [[ "${packageManager}" == "apt" && -s "${missingPackagesFile}" ]] && packageTimeout=900

    runPackageCommandWithProgress "安装${displayName}" "${packageTimeout}" "${installType} ${packages[*]}" "${installLog}" || {
        if recoverAptInstallAfterTimeout "${displayName}" "${packages[@]}"; then
            :
        else
            padmRemoveCleanupPath "${missingPackagesFile}"
            diagnosePackageInstallFailure
            failPackageInstallTransaction "${displayName}安装失败"
        fi
    }
    trackInstalledPackagesFromFile "${missingPackagesFile}"
}

installOptionalPackageTracked() {
    local displayName=$1
    shift
    local packages=("$@")
    local missingPackagesFile
    local installLog

    local packageTimeout=300

    installLog=$(adapterInstallLogPath) || return 1
    padmEnsureSafeDirectory "$(dirname -- "${installLog}")" || return 1
    padmCreateTempPath missingPackagesFile "$(adapterTmpPath padm-packages.XXXXXX)" || return 1
    writeMissingPackages "${missingPackagesFile}" "${packages[@]}"
    [[ "${packageManager}" == "apt" && -s "${missingPackagesFile}" ]] && packageTimeout=900

    if ! runPackageCommandWithProgress "安装${displayName}" "${packageTimeout}" "${installType} ${packages[*]}" "${installLog}"; then
        recoverAptInstallAfterTimeout "${displayName}" "${packages[@]}" || {
            padmRemoveCleanupPath "${missingPackagesFile}"
            diagnosePackageInstallFailure
            return 1
        }
    fi
    trackInstalledPackagesFromFile "${missingPackagesFile}"
}

installBasePackages() {
    local packages=()
    local displayName="基础工具"

    ! command -v sudo >/dev/null 2>&1 && packages+=(sudo)
    ! command -v wget >/dev/null 2>&1 && packages+=(wget)
    ! command -v curl >/dev/null 2>&1 && packages+=(curl)
    ! command -v unzip >/dev/null 2>&1 && packages+=(unzip)
    ! command -v socat >/dev/null 2>&1 && packages+=(socat)
    ! command -v tar >/dev/null 2>&1 && packages+=(tar)
    if ! command -v crontab >/dev/null 2>&1; then
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
            packages+=(cron)
        else
            packages+=(crontabs)
        fi
    fi
    ! command -v jq >/dev/null 2>&1 && packages+=(jq)
    ! command -v ld >/dev/null 2>&1 && packages+=(binutils)
    ! command -v openssl >/dev/null 2>&1 && packages+=(openssl)
    if ! command -v ping6 >/dev/null 2>&1 && ! command -v ping >/dev/null 2>&1; then
        if [[ "${release}" == "centos" ]]; then
            packages+=(iputils)
        else
            packages+=(inetutils-ping)
        fi
    fi
    if ! command -v lsb_release >/dev/null 2>&1; then
        if [[ "${release}" == "ubuntu" || "${release}" == "debian" || "${release}" != "centos" ]]; then
            packages+=(lsb-release)
        fi
    fi
    ! command -v lsof >/dev/null 2>&1 && packages+=(lsof)
    if ! command -v dig >/dev/null 2>&1; then
        if [[ "${packageManager}" == "apt" ]]; then
            packages+=(dnsutils)
        elif [[ "${packageManager}" == "yum" ]]; then
            packages+=(bind-utils)
        elif [[ "${packageManager}" == "apk" ]]; then
            packages+=(bind-tools)
        fi
    fi
    if ! command -v iptables-save >/dev/null 2>&1; then
        if [[ "${packageManager}" == "apt" ]]; then
            packages+=(iptables)
        elif [[ "${packageManager}" == "yum" ]]; then
            packages+=(iptables)
            [[ "${centosVersion:-}" != "10" ]] && packages+=(iptables-legacy)
        elif [[ "${packageManager}" == "apk" ]]; then
            packages+=(iptables)
        fi
    fi

    [[ ${#packages[@]} -eq 0 ]] && return 0
    installPackageTracked "${displayName}" "${packages[@]}"
}

# 安装工具包
installTools() {
    progressCard "$1" "安装工具"
    beginPackageInstallTransaction
    local packageTransactionOwner=${PADM_PACKAGE_TRANSACTION_STARTED}
    # 修复 apt/dpkg 中断状态
    if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]]; then
        runWithTimeout 120 "dpkg --configure -a"
    fi

    waitAptProcess || failPackageInstallTransaction "等待 apt/dpkg 锁释放失败"

    initInstallProgress
    successCard "检查、安装工具依赖【新机器会很慢，请根据工具依赖进度判断是否仍在执行】"

    local installLog
    installLog=$(adapterInstallLogPath) || failPackageInstallTransaction "安装日志路径异常"
    padmEnsureSafeDirectory "$(dirname -- "${installLog}")" || failPackageInstallTransaction "安装日志目录创建失败"
    : >"${installLog}"
    if [[ "${rhelLike:-}" == "true" ]]; then
        statusCard "系统更新" "RHEL-like/Fedora 基础安装跳过全量系统更新，仅安装所需依赖"
    else
        runPackageCommandWithProgress "检查、安装更新" 600 "${upgrade}" "${installLog}" || {
            diagnosePackageInstallFailure
            failPackageInstallTransaction "系统软件源刷新失败"
        }
    fi

    if grep <"${installLog}" -q "changed"; then
        runWithTimeout 300 "${updateReleaseInfoChange} >/dev/null 2>&1" || {
            diagnosePackageInstallFailure
            failPackageInstallTransaction "系统软件源 release 信息刷新失败"
        }
    fi

    if [[ "${rhelLike:-}" == "true" ]]; then
        statusCard "EPEL 仓库" "基础安装不启用 EPEL，避免第三方仓库元数据超时影响安装"
    fi

    installBasePackages

    if ! command -v qrencode >/dev/null 2>&1; then
        if [[ "${packageManager}" == "yum" ]]; then
            statusCard "安装qrencode" "默认仓库未提供 qrencode，跳过本地二维码输出"
        else
            successCard "安装qrencode"
            if ! installOptionalPackageTracked "qrencode" qrencode; then
                warnCard "qrencode 安装失败，跳过本地二维码输出；不影响节点安装和订阅链接"
            fi
        fi
    fi

    # 检查 Nginx 版本并确认是否重装
    if protocolSelectionSkipsNginx "${selectCustomInstallType}"; then
        successCard "检测到无需依赖Nginx的服务，跳过安装"
    else
        if ! nginx >/dev/null 2>&1; then
            successCard "安装nginx"
            installNginxTools
        else
            nginxVersion=$(nginx -v 2>&1)
            nginxVersion=$(echo "${nginxVersion}" | awk -F "[n][g][i][n][x][/]" '{print $2}' | awk -F "[.]" '{print $2}')
            if [[ ${nginxVersion} -lt 14 ]]; then
                autoRead nginx_grpc_reinstall "读取到当前的Nginx版本不支持gRPC，会导致安装失败，是否卸载Nginx后重新安装？[y/n]:" unInstallNginxStatus
                if [[ "${unInstallNginxStatus}" == "y" ]]; then
                    if ! ${removeType} nginx >/dev/null 2>&1; then
                        failPackageInstallTransaction "旧版Nginx卸载失败"
                    fi
                    statusCard "Nginx 状态" "nginx 卸载完成"
                    successCard "安装nginx"
                    installNginxTools || failPackageInstallTransaction "Nginx重装失败"
                else
                    exit 0
                fi
            fi
        fi
    fi

    if ! protocolSelectionNeedsLocalCertificate "${selectCustomInstallType}"; then
        successCard "检测到无需依赖本机 TLS 证书的服务，跳过安装 acme.sh"
    else
        if [[ ! -d "$HOME/.acme.sh" ]] || [[ -d "$HOME/.acme.sh" && -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
            successCard "安装acme.sh"
            local acmeInstallScript
            local acmeDownloadScript
            local acmeHomeDirPath
            local acmeBackupDir
            local acmeTmpDir
            acmeHomeDirPath=$(acmeSafeHomeDir) || failPackageInstallTransaction "acme目录路径异常"
            adapterCreateManagedRollbackBackup acmeBackupDir "${acmeHomeDirPath}" || failPackageInstallTransaction "acme目录备份失败"
            adapterRegisterPackageManagedRollback "${acmeBackupDir}"
            padmCreateTmpRootPath acmeTmpDir padm-tls.XXXXXX -d || failPackageInstallTransaction "acme安装脚本临时目录创建失败"
            acmeInstallScript="${acmeTmpDir}/acme.sh"
            padmCreateTempPath acmeDownloadScript "${acmeTmpDir}/acme.sh.download.XXXXXX" || { padmRemoveCleanupPath "${acmeTmpDir}"; failPackageInstallTransaction "acme安装脚本临时文件创建失败"; }
            if curl -fsSL --connect-timeout 10 --max-time 120 --max-filesize 1048576 -o "${acmeDownloadScript}" https://get.acme.sh && [[ -s "${acmeDownloadScript}" ]]; then
                if ! mv "${acmeDownloadScript}" "${acmeInstallScript}"; then
                    padmRemoveCleanupPath "${acmeTmpDir}"
                    failPackageInstallTransaction "acme安装脚本提交失败"
                fi
                padmForgetCleanupPath "${acmeDownloadScript}"
            else
                padmRemoveCleanupPath "${acmeTmpDir}"
                failPackageInstallTransaction "acme安装脚本下载失败"
            fi
            runWithTimeout 600 "sh \"${acmeInstallScript}\" >/etc/padm/tls/acme.log 2>&1" || { padmRemoveCleanupPath "${acmeTmpDir}"; failPackageInstallTransaction "acme.sh安装失败"; }

            if [[ ! -d "$HOME/.acme.sh" ]] || [[ -z $(find "$HOME/.acme.sh/acme.sh") ]]; then
                padmRemoveCleanupPath "${acmeTmpDir}"
                echoContent title "\n┌─ acme.sh 安装失败 ─────────────────────────────────"
                menuLine "安装日志：/etc/padm/tls/acme.log"
                menuClose
                tail -n 100 /etc/padm/tls/acme.log
                echoContent title "\n┌─ acme.sh 安装排障 ─────────────────────────────────"
                menuLine "获取 GitHub 文件失败时，请等待 GitHub 恢复后重试：https://www.githubstatus.com/"
                menuLine "acme.sh 脚本异常时，可查看 https://github.com/acmesh-official/acme.sh/issues"
                menuLine "纯 IPv6 机器请设置 NAT64；如仍不可用，请尝试更换其他 NAT64"
                menuLine "可尝试写入 NAT64 DNS："
                menuLine "sed -i \"1i\\nameserver 2a00:1098:2b::1\\nnameserver 2a00:1098:2c::1\\nnameserver 2a01:4f8:c2c:123f::1\\nnameserver 2a01:4f9:c010:3f02::1\" /etc/resolv.conf"
                menuClose
                failPackageInstallTransaction "acme.sh安装结果校验失败"
            fi
            padmRemoveCleanupPath "${acmeTmpDir}"
        fi
    fi

    endPackageInstallTransaction "${packageTransactionOwner}"
}

# 开机启动
bootStartup() {
    local serviceName=$1
    if [[ "${release}" == "alpine" ]]; then
        rc-update add "${serviceName}" default
    else
        systemctl daemon-reload && systemctl enable "${serviceName}"
    fi
}

# 安装 Nginx
installNginxTools() {
    beginPackageInstallTransaction
    local packageTransactionOwner=${PADM_PACKAGE_TRANSACTION_STARTED}

    if [[ "${release}" == "debian" ]]; then
        installPackageTracked "Nginx依赖" gnupg2 ca-certificates lsb-release
        local nginxRepoCodename
        local nginxKeyringFile nginxRepoTarget nginxPinTarget repoBackupDir
        nginxRepoCodename=$(lsb_release -cs)
        if curl -fsSL "https://nginx.org/packages/mainline/debian/dists/${nginxRepoCodename}/Release" >/dev/null 2>&1; then
            nginxKeyringFile=$(adapterNginxAptKeyringFile)
            nginxRepoTarget=$(adapterNginxAptRepoFile)
            nginxPinTarget=$(adapterNginxAptPinFile)
            adapterCreateManagedRollbackBackup repoBackupDir "${nginxKeyringFile}" "${nginxRepoTarget}" "${nginxPinTarget}" || failPackageInstallTransaction "Nginx apt 源备份失败"
            adapterRegisterPackageManagedRollback "${repoBackupDir}"
            installAptKeyringFromUrl https://nginx.org/keys/nginx_signing.key "${nginxKeyringFile}" Nginx
            local repoFile
            padmCreateTempPath repoFile "$(adapterNginxRepoTemplate)" || failPackageInstallTransaction "Nginx apt 源临时文件创建失败"
            printf 'deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/mainline/debian %s nginx\n' "${nginxRepoCodename}" >"${repoFile}"
            commitRepoFile "${repoFile}" "${nginxRepoTarget}" || failPackageInstallTransaction "Nginx apt 源提交失败"
            local pinFile
            padmCreateTempPath pinFile "$(adapterNginxPinTemplate)" || failPackageInstallTransaction "Nginx apt pin 临时文件创建失败"
            printf 'Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n\n' >"${pinFile}"
            commitRepoFile "${pinFile}" "${nginxPinTarget}" || failPackageInstallTransaction "Nginx apt pin 配置提交失败"
            refreshAptAfterRepoChange || failPackageInstallTransaction "Nginx apt 源刷新失败"
        fi

    elif [[ "${release}" == "ubuntu" ]]; then
        installPackageTracked "Nginx依赖" gnupg2 ca-certificates lsb-release
        local nginxRepoCodename
        local nginxKeyringFile nginxRepoTarget nginxPinTarget repoBackupDir
        nginxRepoCodename=$(lsb_release -cs)
        if curl -fsSL "https://nginx.org/packages/mainline/ubuntu/dists/${nginxRepoCodename}/Release" >/dev/null 2>&1; then
            nginxKeyringFile=$(adapterNginxAptKeyringFile)
            nginxRepoTarget=$(adapterNginxAptRepoFile)
            nginxPinTarget=$(adapterNginxAptPinFile)
            adapterCreateManagedRollbackBackup repoBackupDir "${nginxKeyringFile}" "${nginxRepoTarget}" "${nginxPinTarget}" || failPackageInstallTransaction "Nginx apt 源备份失败"
            adapterRegisterPackageManagedRollback "${repoBackupDir}"
            installAptKeyringFromUrl https://nginx.org/keys/nginx_signing.key "${nginxKeyringFile}" Nginx
            local repoFile
            padmCreateTempPath repoFile "$(adapterNginxRepoTemplate)" || failPackageInstallTransaction "Nginx apt 源临时文件创建失败"
            printf 'deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/mainline/ubuntu %s nginx\n' "${nginxRepoCodename}" >"${repoFile}"
            commitRepoFile "${repoFile}" "${nginxRepoTarget}" || failPackageInstallTransaction "Nginx apt 源提交失败"
            local pinFile
            padmCreateTempPath pinFile "$(adapterNginxPinTemplate)" || failPackageInstallTransaction "Nginx apt pin 临时文件创建失败"
            printf 'Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n\n' >"${pinFile}"
            commitRepoFile "${pinFile}" "${nginxPinTarget}" || failPackageInstallTransaction "Nginx apt pin 配置提交失败"
            refreshAptAfterRepoChange || failPackageInstallTransaction "Nginx apt 源刷新失败"
        fi

    elif [[ "${release}" == "centos" ]]; then
        installPackageTracked "yum-utils" yum-utils
        local yumReposDir=${PADM_YUM_REPOS_DIR:-/etc/yum.repos.d}
        local repoFile repoBackupDir nginxRepoTarget
        nginxRepoTarget=$(adapterNginxYumRepoFile "${yumReposDir}")
        adapterCreateManagedRollbackBackup repoBackupDir "${nginxRepoTarget}" || failPackageInstallTransaction "Nginx yum 源备份失败"
        adapterRegisterPackageManagedRollback "${repoBackupDir}"
        padmCreateTempPath repoFile "$(adapterNginxYumRepoTemplate)" || failPackageInstallTransaction "Nginx yum 源临时文件创建失败"
        cat <<EOF >"${repoFile}"
[nginx-stable]
name=nginx stable repo
baseurl=https://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=https://nginx.org/packages/mainline/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=0
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF
        mkdir -p "${yumReposDir}" || failPackageInstallTransaction "Nginx yum 源目录创建失败"
        commitRepoFile "${repoFile}" "${nginxRepoTarget}" || failPackageInstallTransaction "Nginx yum 源提交失败"
        sudo yum-config-manager --enable nginx-mainline >/dev/null 2>&1 || failPackageInstallTransaction "Nginx yum mainline 源启用失败"
    elif [[ "${release}" == "fedora" ]]; then
        statusCard "Nginx 源" "nginx.org 未提供 Fedora ${centosVersion} 仓库，使用系统默认仓库安装 Nginx"
    elif [[ "${release}" == "alpine" ]]; then
        local defaultNginxConf
        local repoBackupDir
        defaultNginxConf=$(nginxConfigFilePath default.conf) || failPackageInstallTransaction "Nginx 默认配置路径异常"
        adapterCreateManagedRollbackBackup repoBackupDir "${defaultNginxConf}" || failPackageInstallTransaction "Nginx 默认配置备份失败"
        adapterRegisterPackageManagedRollback "${repoBackupDir}"
        rm -f -- "${defaultNginxConf}" || failPackageInstallTransaction "Nginx 默认配置删除失败"
    fi
    installPackageTracked "nginx" nginx
    if nginxServiceInstalled; then
        bootStartup nginx || failPackageInstallTransaction "Nginx开机自启配置失败"
    else
        statusCard "Nginx 开机自启" "未发现 nginx systemd unit，跳过开机自启配置"
    fi
    endPackageInstallTransaction "${packageTransactionOwner}"
}
