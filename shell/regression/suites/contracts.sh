#!/usr/bin/env bash

runRegressionDispatcherRegistryOnlyContract() {
    local dispatcherFile="${PROJECT_ROOT}/shell/subscription_groups_regression.sh"
    local registryFile="${PROJECT_ROOT}/shell/regression/framework/registry.sh"

    ! grep -q 'subscription_groups_legacy\.sh' "${dispatcherFile}"
    ! grep -q 'subscription_groups_fast\.sh' "${dispatcherFile}"
    ! grep -q 'subscription_groups_remote_control\.sh' "${dispatcherFile}"
    ! grep -q 'subscription_groups_subscription_state\.sh' "${dispatcherFile}"
    grep -q 'regression/framework/env\.sh' "${dispatcherFile}"
    grep -q 'regression/framework/runtime\.sh' "${dispatcherFile}"
    grep -q 'regression/framework/registry\.sh' "${dispatcherFile}"
    grep -q 'runRegisteredRegressionMain' "${dispatcherFile}"

    ! grep -q '^registerRegressionScriptLeaf() {' "${registryFile}"
    ! grep -q '^declare -Ag PADM_REGRESSION_SELECTOR_SCRIPT=' "${registryFile}"
    ! grep -q '^    script)$' "${registryFile}"
}

runRegressionRegistryRetiresScriptSelectorKindContract() {
    local registryFile="${PROJECT_ROOT}/shell/regression/framework/registry.sh"

    ! grep -q 'PADM_REGRESSION_SELECTOR_KIND\["\${selector}"\]=script' "${registryFile}"
    ! grep -q 'PADM_REGRESSION_SELECTOR_SCRIPT\["\${selector}"\]=' "${registryFile}"
    ! grep -q 'PADM_REGRESSION_SUPPRESS_DONE=1 PADM_REGRESSION_INTERNAL_CLI=1 bash "\${scriptPath}" "\${runner}"' "${registryFile}"
}

runRegressionFunctionLeafSupportsRunnerArgsContract() (
    local selector="function-leaf-runner-args-fixture"
    local callLog="${TMP_DIR}/function-leaf-runner-args.log"

    : >"${callLog}"

    runFixtureCompatHelper() {
        local runner=$1
        printf 'compat:%s\n' "${runner}" >>"${callLog}"
        "${runner}"
    }

    runFixtureLeaf() {
        printf 'leaf\n' >>"${callLog}"
    }

    registerRegressionFunctionLeaf "${selector}" runFixtureCompatHelper runFixtureLeaf
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain "${selector}"

    cat <<'EOF' >"${TMP_DIR}/function-leaf-runner-args.expected.log"
compat:runFixtureLeaf
leaf
EOF

    cmp -s "${TMP_DIR}/function-leaf-runner-args.expected.log" "${callLog}"
)

runRegressionAggregateRunnerSupportsRunnerArgsContract() (
    local selector="aggregate-runner-args-fixture"
    local callLog="${TMP_DIR}/aggregate-runner-args.log"

    : >"${callLog}"

    listFixtureAggregateRunnerChildren() {
        printf '%s\n' \
            alpha \
            beta
    }

    runFixtureAggregateRunnerWithArgs() {
        local selectorListFn=$1
        printf 'runner:%s\n' "${selectorListFn}" >>"${callLog}"
        "${selectorListFn}" >>"${callLog}"
    }

    registerRegressionFunctionLeaf alpha runFixtureCompatHelper runFixtureLeaf
    registerRegressionFunctionLeaf beta runFixtureCompatHelper runFixtureLeaf
    registerRegressionAggregateRunnerSequentialWithArgs \
        "${selector}" \
        runFixtureAggregateRunnerWithArgs \
        listFixtureAggregateRunnerChildren \
        -- \
        $(listFixtureAggregateRunnerChildren)
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain "${selector}"

    cat <<'EOF' >"${TMP_DIR}/aggregate-runner-args.expected.log"
runner:listFixtureAggregateRunnerChildren
alpha
beta
EOF

    cmp -s "${TMP_DIR}/aggregate-runner-args.expected.log" "${callLog}"
)

runRegressionParallelAggregateRunnerSupportsRunnerArgsContract() (
    local selector="parallel-aggregate-runner-args-fixture"
    local callLog="${TMP_DIR}/parallel-aggregate-runner-args.log"

    : >"${callLog}"

    listFixtureParallelAggregateRunnerChildren() {
        printf '%s\n' \
            alpha \
            beta
    }

    runFixtureParallelAggregateRunnerWithArgs() {
        local orchestrationRoot=$1
        local selectorListFn=$2
        printf 'runner:%s:%s\n' "${orchestrationRoot}" "${selectorListFn}" >>"${callLog}"
        "${selectorListFn}" >>"${callLog}"
    }

    registerRegressionFunctionLeaf alpha runFixtureCompatHelper runFixtureLeaf
    registerRegressionFunctionLeaf beta runFixtureCompatHelper runFixtureLeaf
    registerRegressionAggregateRunnerParallelWithArgs \
        "${selector}" \
        runFixtureParallelAggregateRunnerWithArgs \
        "${TMP_DIR}/parallel-aggregate-runner-args-fixture" \
        listFixtureParallelAggregateRunnerChildren \
        -- \
        $(listFixtureParallelAggregateRunnerChildren)
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain "${selector}"

    cat <<EOF >"${TMP_DIR}/parallel-aggregate-runner-args.expected.log"
runner:${TMP_DIR}/parallel-aggregate-runner-args-fixture:listFixtureParallelAggregateRunnerChildren
alpha
beta
EOF

    cmp -s "${TMP_DIR}/parallel-aggregate-runner-args.expected.log" "${callLog}"
)

runLegacyPublicSelectorRetirementAssertions() (
    local legacyFile=$1
    shift
    local usageLine
    local usageSelectors
    local selector

    usageLine=$(grep -F 'usage: %s [' "${legacyFile}" || true)
    usageSelectors="${usageLine#*[}"
    usageSelectors="${usageSelectors%%]*}"

    for selector in "$@"; do
        [[ -n "${selector}" ]] || continue
        ! awk -v sel="${selector}" '
            {
                line = $0
                sub(/^[[:space:]]+/, "", line)
                if (line == sel ")") {
                    found = 1
                }
            }
            END { exit(found ? 0 : 1) }
        ' "${legacyFile}" || return 1
        [[ -z "${usageLine}" || "|${usageSelectors}|" != *"|${selector}|"* ]] || return 1
    done
)

runAggregateRunnerRegistrationAssertions() {
    local selector=$1
    local mode=$2
    local runner=$3
    local expectedChildren=$4
    local actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["${selector}"]:-}

    [[ "${PADM_REGRESSION_SELECTOR_KIND["${selector}"]:-}" == "aggregate-runner" ]] || return 1
    [[ "${PADM_REGRESSION_SELECTOR_MODE["${selector}"]:-}" == "${mode}" ]] || return 1
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["${selector}"]:-}" == "${runner}" ]] || return 1
    [[ "${actualChildren}" == "${expectedChildren}" ]] || return 1
}

runAggregateRunnerRunnerArgsAssertions() {
    local selector=$1
    local expectedArgs=$2
    local actualArgs=${PADM_REGRESSION_SELECTOR_RUNNER_ARGS["${selector}"]:-}

    [[ "${actualArgs}" == "${expectedArgs}" ]] || return 1
}

runAggregateRunnerRunnerArgsPatternAssertions() {
    local selector=$1
    shift
    local actualArgs=${PADM_REGRESSION_SELECTOR_RUNNER_ARGS["${selector}"]:-}
    local pattern

    for pattern in "$@"; do
        grep -Eq "${pattern}" <<<"${actualArgs}" || return 1
    done
}

runAggregateRunnerUsesSuiteLocalHelperAssertions() (
    local selector=$1
    local callLog=$2
    local expectedSuiteLine=$3
    local forbiddenLegacyLine=$4

    : >"${callLog}"
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain "${selector}"

    grep -qx "${expectedSuiteLine}" "${callLog}" || return 1
    ! grep -q "^${forbiddenLegacyLine}$" "${callLog}" || return 1
)

runAggregateRunnerUsesFrameworkSelectorHelperAssertions() (
    local callLog=$1
    local expectedFrameworkLine=$2
    shift 2

    : >"${callLog}"
    "$@"

    grep -qx "${expectedFrameworkLine}" "${callLog}" || return 1
    ! grep -q '^legacy-helper:' "${callLog}" || return 1
)

runAggregateRunnerUsesFrameworkSelectorHelperPatternAssertions() (
    local callLog=$1
    local expectedFrameworkPattern=$2
    shift 2

    : >"${callLog}"
    "$@"

    grep -Eq "${expectedFrameworkPattern}" "${callLog}" || return 1
    ! grep -q '^legacy-helper:' "${callLog}" || return 1
)

runAggregateRunnerUsesFrameworkSelectorHelperMultiLineAssertions() (
    local callLog=$1
    local runnerFn=$2
    shift 2
    local expectedFrameworkLine

    : >"${callLog}"
    "${runnerFn}"

    for expectedFrameworkLine in "$@"; do
        grep -qx "${expectedFrameworkLine}" "${callLog}" || return 1
    done
    ! grep -q '^legacy-helper:' "${callLog}" || return 1
)

runAggregateRunnerDispatchesChildrenInOrderAssertions() (
    local callLog=$1
    shift
    local expectedLine
    local expectedCount=$#
    local previousLineNumber=0
    local currentLineNumber

    for expectedLine in "$@"; do
        grep -qx "${expectedLine}" "${callLog}" || return 1

        currentLineNumber=$(awk -v expected="${expectedLine}" '
            $0 == expected {
                print NR
                exit
            }
        ' "${callLog}")

        [[ -n "${currentLineNumber}" ]] || return 1
        (( currentLineNumber > previousLineNumber )) || return 1
        previousLineNumber=${currentLineNumber}
    done

    [[ "$(wc -l <"${callLog}")" -eq "${expectedCount}" ]]
)

runLegacyFunctionSelectorRetirementAssertions() (
    local legacyFile=$1
    local functionName=$2
    local selectorToken=$3
    local usageToken=$4

    ! grep -Eq "^${functionName}\\(\\)[[:space:]]*[({]" "${legacyFile}" || return 1
    ! grep -Eq "^[[:space:]]*${selectorToken}\\)$" "${legacyFile}" || return 1
    ! grep -Fq "${usageToken}" "${legacyFile}" || return 1
)

runLegacyFunctionRetirementBatchAssertions() (
    local legacyFile=$1
    shift
    local functionName

    for functionName in "$@"; do
        ! grep -Eq "^${functionName}\\(\\)[[:space:]]*[({]" "${legacyFile}" || return 1
    done
)

runSubscriptionStateCliRetirementAssertions() {
    local scriptFile=$1
    local usageLine
    local usageSelectors
    local selector

    grep -q 'if \[\[ "\${PADM_REGRESSION_SOURCE_ONLY:-}" == "1" \]\]; then' "${scriptFile}" || return 1
    grep -q "printf 'use shell/subscription_groups_regression.sh <selector>\\\\n' >&2" "${scriptFile}" || return 1
    ! grep -q 'regressionName=' "${scriptFile}" || return 1
    ! grep -q 'runRegressionStep "total:\${regressionName}" "\${regressionRunner}"' "${scriptFile}" || return 1
    ! grep -q 'subscription-groups-regression-ok:' "${scriptFile}" || return 1

    usageLine=$(grep -F 'usage: %s [' "${scriptFile}" || true)
    usageSelectors="${usageLine#*[}"
    usageSelectors="${usageSelectors%%]*}"
    [[ -z "${usageLine}" ]] || return 1
    [[ -z "${usageSelectors}" ]] || return 1

    for selector in subscription-state subscription-state-core; do
        ! awk -v sel="${selector}" '
            {
                line = $0
                sub(/^[[:space:]]+/, "", line)
                if (line == sel ")") {
                    found = 1
                }
            }
            END { exit(found ? 0 : 1) }
        ' "${scriptFile}" || return 1
    done

    ! grep -Eq '^[[:space:]]*subscription-state-.*\)$' "${scriptFile}" || return 1
    ! grep -Eq '^[[:space:]]*subscription-sync-.*\)$' "${scriptFile}" || return 1
    ! grep -Eq '^[[:space:]]*subscription-group-sync-.*\)$' "${scriptFile}" || return 1
}

runRegressionStepSequenceAssertions() {
    local sourceFile=$1
    local functionName=$2
    shift 2
    local functionBody
    local -a actualSteps=()
    local -a expectedSteps=("$@")
    local idx

    functionBody=$(sed -n "/^${functionName}() {$/,/^}$/p" "${sourceFile}")
    [[ -n "${functionBody}" ]] || return 1

    mapfile -t actualSteps < <(
        awk '/^[[:space:]]*runRegressionStep / { print $2 }' <<<"${functionBody}"
    )

    [[ "${#actualSteps[@]}" -eq "${#expectedSteps[@]}" ]] || return 1

    for idx in "${!expectedSteps[@]}"; do
        [[ "${actualSteps[idx]}" == "${expectedSteps[idx]}" ]] || return 1
    done
}

runSequentialSelectorListUsesFrameworkHelperAssertions() {
    local callLog=$1
    local expectedCall=$2
    shift 2

    : >"${callLog}"
    "$@"

    grep -qx "${expectedCall}" "${callLog}" || return 1
    ! grep -q '^legacy-helper:' "${callLog}" || return 1
}

runRegressionDispatcherStepCoverageAssertions() {
    local sourceFile=$1
    local selector=$2
    local runner=$3
    local dispatcherBody

    dispatcherBody=$(sed -n '/^runRegressionDispatcherContracts() {$/,/^}$/p' "${sourceFile}")
    [[ -n "${dispatcherBody}" ]] || return 1

    grep -q "runRegressionStep ${selector} ${runner}" <<<"${dispatcherBody}"
}

runContractHelperAdoptionAssertions() {
    local sourceFile=$1
    local functionName=$2
    local helperName=$3

    awk -v fn="${functionName}" -v helper="${helperName}" '
        $0 == fn "() {" || $0 == fn "() (" { in_fn = 1 }
        in_fn && index($0, helper " ") { found = 1 }
        in_fn && ($0 == "}" || $0 == ")") { exit(found ? 0 : 1) }
    ' "${sourceFile}"
}

runRegressionStepSequenceAssertionContract() (
    local fixtureFile="${TMP_DIR}/regression-step-sequence-assertion-fixture.sh"

    cat <<'EOF' >"${fixtureFile}"
runFixtureRegressionSequence() {
    runRegressionStep first runFixtureFirst &&
        runRegressionStep second runFixtureSecond
}
EOF

    runRegressionStepSequenceAssertions "${fixtureFile}" runFixtureRegressionSequence first second

    if runRegressionStepSequenceAssertions "${fixtureFile}" runFixtureRegressionSequence second first; then
        return 1
    fi
)

runRegressionDispatcherStepCoverageAssertionContract() (
    local fixtureFile="${TMP_DIR}/regression-dispatcher-step-coverage-fixture.sh"

    cat <<'EOF' >"${fixtureFile}"
runRegressionDispatcherContracts() {
    runRegressionStep alpha runFixtureAlpha &&
        runRegressionStep beta runFixtureBeta
}
EOF

    runRegressionDispatcherStepCoverageAssertions "${fixtureFile}" alpha runFixtureAlpha
    runRegressionDispatcherStepCoverageAssertions "${fixtureFile}" beta runFixtureBeta

    if runRegressionDispatcherStepCoverageAssertions "${fixtureFile}" gamma runFixtureGamma; then
        return 1
    fi
)

runContractHelperAdoptionAssertionContract() (
    local braceFixture="${TMP_DIR}/contract-helper-adoption-brace-fixture.sh"
    local subshellFixture="${TMP_DIR}/contract-helper-adoption-subshell-fixture.sh"

    cat <<'EOF' >"${braceFixture}"
runBraceFixtureContract() {
    runFixtureAssertions alpha
}
EOF

    cat <<'EOF' >"${subshellFixture}"
runSubshellFixtureContract() (
    runFixtureAssertions beta
)
EOF

    runContractHelperAdoptionAssertions "${braceFixture}" runBraceFixtureContract runFixtureAssertions
    runContractHelperAdoptionAssertions "${subshellFixture}" runSubshellFixtureContract runFixtureAssertions

    if runContractHelperAdoptionAssertions "${braceFixture}" runBraceFixtureContract runMissingAssertions; then
        return 1
    fi
)

runLegacyPublicSelectorRetirementAssertionContract() (
    local helperFile="${TMP_DIR}/legacy-public-selector-retirement-helper.sh"
    local selectorsFile="${TMP_DIR}/legacy-public-selector-retirement-selectors.txt"

    cat <<'EOF' >"${helperFile}"
usage: %s [alpha|delta]
case "$1" in
    alpha)
        ;;
    beta)
        ;;
esac
EOF

    cat <<'EOF' >"${selectorsFile}"
alpha
delta
EOF

    runLegacyPublicSelectorRetirementAssertions "${helperFile}" alpha delta
    runLegacyPublicSelectorRetirementAssertions "${helperFile}" $(<"${selectorsFile}")
    if runLegacyPublicSelectorRetirementAssertions "${helperFile}" beta; then
        return 1
    fi
)

runAggregateRunnerRegistrationAssertionContract() (
    local selector="aggregate-runner-registration-fixture"
    PADM_REGRESSION_SELECTOR_KIND["${selector}"]=aggregate-runner
    PADM_REGRESSION_SELECTOR_MODE["${selector}"]=parallel
    PADM_REGRESSION_SELECTOR_RUNNER["${selector}"]=runFixtureAggregateRunner
    PADM_REGRESSION_SELECTOR_CHILDREN["${selector}"]=$'alpha\nbeta'

    runAggregateRunnerRegistrationAssertions \
        "${selector}" \
        parallel \
        runFixtureAggregateRunner \
        $'alpha\nbeta'

    if runAggregateRunnerRegistrationAssertions \
        "${selector}" \
        sequential \
        runFixtureAggregateRunner \
        $'alpha\nbeta'; then
        return 1
    fi
)

runAggregateRunnerUsesSuiteLocalHelperAssertionContract() (
    local callLog="${TMP_DIR}/aggregate-suite-local-helper.log"

    runRegressionTls() {
        printf 'legacy-tls\n' >>"${callLog}"
        return 97
    }

    runRegressionTlsSuiteRoot() {
        printf 'suite-tls\n' >>"${callLog}"
    }

    runAggregateRunnerUsesSuiteLocalHelperAssertions tls "${callLog}" 'suite-tls' 'legacy-tls'

    if runAggregateRunnerUsesSuiteLocalHelperAssertions tls "${callLog}" 'suite-runtime' 'legacy-tls'; then
        return 1
    fi
)

runAggregateRunnerRunnerArgsAssertionContract() (
    local selector="aggregate-runner-runner-args-fixture"

    PADM_REGRESSION_SELECTOR_RUNNER_ARGS["${selector}"]='alpha
beta'
    runAggregateRunnerRunnerArgsAssertions "${selector}" $'alpha\nbeta'

    if runAggregateRunnerRunnerArgsAssertions "${selector}" 'alpha'; then
        return 1
    fi
)

runAggregateRunnerUsesFrameworkSelectorHelperAssertionContract() (
    local callLog="${TMP_DIR}/aggregate-framework-helper.log"

    runFixtureFrameworkAggregate() {
        printf 'framework:fixture\n' >>"${callLog}"
    }

    runFixtureFrameworkAggregateWithLegacyFallback() {
        printf 'framework:fixture\n' >>"${callLog}"
        printf 'legacy-helper:fixture\n' >>"${callLog}"
    }

    runAggregateRunnerUsesFrameworkSelectorHelperAssertions "${callLog}" 'framework:fixture' runFixtureFrameworkAggregate

    if runAggregateRunnerUsesFrameworkSelectorHelperAssertions "${callLog}" 'framework:other' runFixtureFrameworkAggregate; then
        return 1
    fi

    if runAggregateRunnerUsesFrameworkSelectorHelperAssertions "${callLog}" 'framework:fixture' runFixtureFrameworkAggregateWithLegacyFallback; then
        return 1
    fi
)

runAggregateRunnerUsesFrameworkSelectorHelperMultiLineAssertionContract() (
    local callLog="${TMP_DIR}/aggregate-framework-helper-multiline.log"

    runFixtureFrameworkAggregateMultiLine() {
        printf 'framework:first\n' >>"${callLog}"
        printf 'framework:second\n' >>"${callLog}"
    }

    runFixtureFrameworkAggregateMultiLineWithLegacyFallback() {
        printf 'framework:first\n' >>"${callLog}"
        printf 'framework:second\n' >>"${callLog}"
        printf 'legacy-helper:fixture\n' >>"${callLog}"
    }

    runAggregateRunnerUsesFrameworkSelectorHelperMultiLineAssertions \
        "${callLog}" \
        runFixtureFrameworkAggregateMultiLine \
        'framework:first' \
        'framework:second'

    if runAggregateRunnerUsesFrameworkSelectorHelperMultiLineAssertions \
        "${callLog}" \
        runFixtureFrameworkAggregateMultiLine \
        'framework:first' \
        'framework:other'; then
        return 1
    fi

    if runAggregateRunnerUsesFrameworkSelectorHelperMultiLineAssertions \
        "${callLog}" \
        runFixtureFrameworkAggregateMultiLineWithLegacyFallback \
        'framework:first' \
        'framework:second'; then
        return 1
    fi
)

runAggregateRunnerRegistrationHelperAdoptionContract() {
    local contractsFile="${PROJECT_ROOT}/shell/regression/suites/contracts.sh"

    for functionName in \
        runFastRealityAggregateRunnerRegistrationContract \
        runFastAggregateRunnerRegistrationContract \
        runFastOnlyAggregateRunnerRegistrationContract \
        runFastOnlyOutputAggregateRunnerRegistrationContract \
        runRuntimeAggregateRunnerRegistrationContract \
        runTlsAggregateRunnerRegistrationContract \
        runAllAggregateRunnerRegistrationContract \
        runSubscriptionAggregateRunnerRegistrationContract \
        runSubscriptionRemoteAggregateRunnerRegistrationContract \
        runSubscriptionTxAggregateRunnerRegistrationContract \
        runUiAggregateRunnerRegistrationContract \
        runRoutingAggregateRunnerRegistrationContract \
        runRealityCandidatesAggregateRunnerRegistrationContract \
        runRealityStreamAggregateRunnerRegistrationContract \
        runTransactionCoreAggregateRunnerRegistrationContract \
        runTransactionAggregateRunnerRegistrationContract \
        runTransactionSystemAggregateRunnerRegistrationContract; do
        runContractHelperAdoptionAssertions \
            "${contractsFile}" \
            "${functionName}" \
            runAggregateRunnerRegistrationAssertions || return 1
    done
}

runAggregateRunnerUsesSuiteLocalHelperAdoptionContract() {
    local contractsFile="${PROJECT_ROOT}/shell/regression/suites/contracts.sh"

    for functionName in \
        runUiAggregateRunnerUsesSuiteLocalHelperContract \
        runRoutingAggregateRunnerUsesSuiteLocalHelperContract \
        runRuntimeAggregateRunnerUsesSuiteLocalHelperContract; do
        runContractHelperAdoptionAssertions \
            "${contractsFile}" \
            "${functionName}" \
            runAggregateRunnerUsesSuiteLocalHelperAssertions || return 1
    done
}

runAggregateRunnerUsesFrameworkSelectorHelperAdoptionContract() {
    local contractsFile="${PROJECT_ROOT}/shell/regression/suites/contracts.sh"

    for functionName in \
        runAllAggregateRunnerUsesFrameworkSelectorHelperContract \
        runTransactionAggregateRunnerUsesFrameworkSelectorHelperContract; do
        runContractHelperAdoptionAssertions \
            "${contractsFile}" \
            "${functionName}" \
            runAggregateRunnerUsesFrameworkSelectorHelperAssertions || return 1
    done
}

runAggregateRunnerUsesFrameworkSelectorHelperMultiLineAdoptionContract() {
    local contractsFile="${PROJECT_ROOT}/shell/regression/suites/contracts.sh"

    for functionName in \
        runUiAggregateRunnerUsesFrameworkSelectorHelperContract \
        runRuntimeAggregateRunnerUsesFrameworkSelectorHelperContract \
        runRoutingAggregateRunnerUsesFrameworkSelectorHelperContract \
        runTransactionCoreAggregateRunnerUsesFrameworkSelectorHelperContract; do
        runContractHelperAdoptionAssertions \
            "${contractsFile}" \
            "${functionName}" \
            runAggregateRunnerUsesFrameworkSelectorHelperMultiLineAssertions || return 1
    done
}

runContractFunctionDefinitionsUniqueContract() {
    local contractsFile="${PROJECT_ROOT}/shell/regression/suites/contracts.sh"
    local duplicates

    duplicates=$(awk '
        /^run[A-Za-z0-9]+Contract\(\)[[:space:]]*\{$/ || /^run[A-Za-z0-9]+Contract\(\)[[:space:]]*\($/ {
            name = $0
            sub(/\(.*/, "", name)
            count[name]++
        }
        END {
            for (name in count) {
                if (count[name] > 1) {
                    print name
                }
            }
        }
    ' "${contractsFile}")

    [[ -z "${duplicates}" ]]
}

runRegressionStepSequenceHelperAdoptionContract() {
    local contractsFile="${PROJECT_ROOT}/shell/regression/suites/contracts.sh"

    for functionName in \
        runPlatformRefreshChildStepsContract \
        runPlatformUpdateChildStepsContract \
        runPlatformRestChildStepsContract \
        runFastOnlyOutputAutoInstallChildStepsContract \
        runFastOnlySafetyChildStepsContract \
        runFastOnlyOutputRestChildStepsContract \
        runFastOnlyCoreChildStepsContract \
        runTargetedBatchHelpersChildStepsContract; do
        runContractHelperAdoptionAssertions \
            "${contractsFile}" \
            "${functionName}" \
            runRegressionStepSequenceAssertions || return 1
    done

    awk '
        /^runRealitySuiteChildStepsContract\(\) \{$/ { in_fn = 1 }
        in_fn && /runSequentialSelectorListUsesFrameworkHelperAssertions / { count++ }
        in_fn && /^}$/ { exit(count == 2 ? 0 : 1) }
    ' "${contractsFile}" || return 1

    for functionName in \
        runRemoteControlSmokeCoreChildStepsContract \
        runSubscriptionStateSupportChildStepsContract \
        runSubscriptionStateSerialChildStepsContract \
        runPlatformIoChildStepsContract \
        runTlsSuiteChildStepsContract \
        runTransactionSubscriptionChildStepsContract; do
        runContractHelperAdoptionAssertions \
            "${contractsFile}" \
            "${functionName}" \
            runSequentialSelectorListUsesFrameworkHelperAssertions || return 1
    done
}

runRegisteredChildSelectorsAlignedHelperAdoptionContract() {
    local contractsFile="${PROJECT_ROOT}/shell/regression/suites/contracts.sh"

    for functionName in \
        runTransactionCoreRegisteredChildSelectorsAlignedContract \
        runTransactionSubscriptionRegisteredChildSelectorsAlignedContract \
        runSubscriptionRemoteRegisteredChildSelectorsAlignedContract \
        runSubscriptionTxRegisteredChildSelectorsAlignedContract; do
        runContractHelperAdoptionAssertions \
            "${contractsFile}" \
            "${functionName}" \
            runRegisteredChildSelectorsAlignedAssertions || return 1
    done
}

runAggregateRunnerDispatchesChildrenInOrderHelperAdoptionContract() {
    local contractsFile="${PROJECT_ROOT}/shell/regression/suites/contracts.sh"

    for functionName in \
        runFastRealityAggregateRunnerDispatchesChildrenInOrderContract \
        runRealityCandidatesAggregateRunnerDispatchesChildrenInOrderContract \
        runRealityStreamAggregateRunnerDispatchesChildrenInOrderContract; do
        runContractHelperAdoptionAssertions \
            "${contractsFile}" \
            "${functionName}" \
            runAggregateRunnerDispatchesChildrenInOrderAssertions || return 1
    done
}

runLegacyFunctionSelectorRetirementHelperAdoptionContract() {
    local contractsFile="${PROJECT_ROOT}/shell/regression/suites/contracts.sh"

    for functionName in \
        runFastLegacyRetirementContract \
        runFastRealityLegacyRetirementContract \
        runTargetedBatchHelpersLegacyRetirementContract \
        runTlsLegacyRetirementContract \
        runTargetedSubscriptionRestoreRetirementContract \
        runSubscriptionOutputLegacyRetirementContract \
        runUiSmokeLegacyWrapperRetirementContract \
        runUiFullLegacyWrapperRetirementContract; do
        runContractHelperAdoptionAssertions \
            "${contractsFile}" \
            "${functionName}" \
            runLegacyFunctionSelectorRetirementAssertions || return 1
    done
}

runLegacyFunctionRetirementBatchHelperAdoptionContract() {
    local contractsFile="${PROJECT_ROOT}/shell/regression/suites/contracts.sh"

    for functionName in \
        runUiFullSubscriptionMainLegacyWrapperRetirementContract \
        runUiWireGuardLegacyWrapperRetirementContract; do
        runContractHelperAdoptionAssertions \
            "${contractsFile}" \
            "${functionName}" \
            runLegacyFunctionRetirementBatchAssertions || return 1
    done
}

runSubscriptionStateCliRetirementHelperAdoptionContract() {
    local contractsFile="${PROJECT_ROOT}/shell/regression/suites/contracts.sh"

    for functionName in \
        runSubscriptionStateShimPublicCliRetirementContract \
        runSubscriptionStateFullPublicCliRetirementContract; do
        runContractHelperAdoptionAssertions \
            "${contractsFile}" \
            "${functionName}" \
            runSubscriptionStateCliRetirementAssertions || return 1
    done
}

runSubscriptionStateCliRetirementHelperAdoptionCoveredByDispatcherContract() {
    local contractsFile="${PROJECT_ROOT}/shell/regression/suites/contracts.sh"
    runRegressionDispatcherStepCoverageAssertions \
        "${contractsFile}" \
        subscription-state-cli-retirement-helper-adoption \
        runSubscriptionStateCliRetirementHelperAdoptionContract
}

runRegressionDispatcherStepCoverageHelperAdoptionContract() {
    local contractsFile="${PROJECT_ROOT}/shell/regression/suites/contracts.sh"

    for functionName in \
        runSubscriptionStateCliRetirementHelperAdoptionCoveredByDispatcherContract \
        runSubscriptionStateNestedAggregateRunnerRegistrationCoveredByDispatcherContract; do
        runContractHelperAdoptionAssertions \
            "${contractsFile}" \
            "${functionName}" \
            runRegressionDispatcherStepCoverageAssertions || return 1
    done
}

runContractHelperAdoptionHelperAdoptionContract() {
    local contractsFile="${PROJECT_ROOT}/shell/regression/suites/contracts.sh"

    for functionName in \
        runRegressionStepSequenceHelperAdoptionContract \
        runAggregateRunnerRegistrationHelperAdoptionContract \
        runAggregateRunnerUsesSuiteLocalHelperAdoptionContract \
        runAggregateRunnerUsesFrameworkSelectorHelperAdoptionContract \
        runAggregateRunnerUsesFrameworkSelectorHelperMultiLineAdoptionContract \
        runRegisteredChildSelectorsAlignedHelperAdoptionContract \
        runAggregateRunnerDispatchesChildrenInOrderHelperAdoptionContract \
        runLegacyFunctionSelectorRetirementHelperAdoptionContract \
        runLegacyFunctionRetirementBatchHelperAdoptionContract \
        runLegacyPublicSelectorRetirementHelperAdoptionContract \
        runSubscriptionStateCliRetirementHelperAdoptionContract \
        runRegressionDispatcherStepCoverageHelperAdoptionContract; do
        runContractHelperAdoptionAssertions \
            "${contractsFile}" \
            "${functionName}" \
            runContractHelperAdoptionAssertions || return 1
    done
}

runLegacyPublicSelectorRetirementHelperAdoptionContract() {
    local contractsFile="${PROJECT_ROOT}/shell/regression/suites/contracts.sh"

    for functionName in \
        runSubscriptionLegacyPublicSelectorRetirementContract \
        runRoutingLegacyPublicSelectorRetirementContract \
        runUiLegacyPublicSelectorRetirementContract; do
        runContractHelperAdoptionAssertions \
            "${contractsFile}" \
            "${functionName}" \
            runLegacyPublicSelectorRetirementAssertions || return 1
    done
}

runPreLegacySuitesAvoidLegacyFunctionNameCollisionsContract() (
    local dispatcherFile="${PROJECT_ROOT}/shell/subscription_groups_regression.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local helperDir="${TMP_DIR}/pre-legacy-suite-collision-check"
    local legacyNamesFile="${helperDir}/legacy.names"
    local suiteFilesFile="${helperDir}/pre-legacy-suites.txt"
    local collisionsFile="${helperDir}/collisions.txt"
    local relativeSuiteFile=
    local suiteFile=
    local functionName=

    mkdir -p "${helperDir}"

    grep -E '^(runRegression|listRegression)[A-Za-z0-9_]+\(\)' "${legacyFile}" |
        sed -E 's/\(\).*$//' |
        sort -u >"${legacyNamesFile}"

    awk '
        /regression\/suites\/legacy\.sh/ { exit }
        match($0, /source "\$\{SCRIPT_DIR\}\/(regression\/suites\/[^"]+)"/, capture) {
            print capture[1]
        }
    ' "${dispatcherFile}" >"${suiteFilesFile}"

    : >"${collisionsFile}"
    while IFS= read -r relativeSuiteFile; do
        [[ -n "${relativeSuiteFile}" ]] || continue
        suiteFile="${PROJECT_ROOT}/shell/${relativeSuiteFile}"
        while IFS= read -r functionName; do
            [[ -n "${functionName}" ]] || continue
            if grep -qx "${functionName}" "${legacyNamesFile}"; then
                printf '%s:%s\n' "${relativeSuiteFile}" "${functionName}" >>"${collisionsFile}"
            fi
        done < <(
            grep -E '^(runRegression|listRegression)[A-Za-z0-9_]+\(\)' "${suiteFile}" |
                sed -E 's/\(\).*$//' |
                sort -u
        )
    done <"${suiteFilesFile}"

    ! grep -q '^regression/suites/legacy\.sh$' "${suiteFilesFile}"
    [[ ! -s "${collisionsFile}" ]]
)

runSubscriptionStateNoImplicitFullFallbackContract() {
    local stateShim="${PROJECT_ROOT}/shell/regression/subscription_groups_subscription_state.sh"

    ! grep -q 'exec bash "\${SUBSCRIPTION_STATE_FULL_SCRIPT_PATH}" "\$@"' "${stateShim}"
}

runSubscriptionStateShimUsesSourceOnlyFullContract() {
    local stateShim="${PROJECT_ROOT}/shell/regression/subscription_groups_subscription_state.sh"

    ! grep -q 'sourceSubscriptionStateHotSection' "${stateShim}"
    ! grep -q 'awk ' "${stateShim}"
    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${SUBSCRIPTION_STATE_FULL_SCRIPT_PATH}"' "${stateShim}"
    grep -q 'if \[\[ "\${PADM_REGRESSION_SOURCE_ONLY:-}" == "1" \]\]; then' "${stateShim}"
}

runSubscriptionStateShimStaysThinContract() {
    local stateShim="${PROJECT_ROOT}/shell/regression/subscription_groups_subscription_state.sh"

    ! grep -q '^runParallelSubscriptionStateModes()' "${stateShim}" || return 1
    ! grep -q '^runRegressionSubscriptionStateCore()' "${stateShim}" || return 1
    ! grep -q '^runRegressionSubscriptionStateStructure()' "${stateShim}" || return 1
    ! grep -q '^runRegressionSubscriptionStateQuota()' "${stateShim}" || return 1
    ! grep -q '^runRegressionSubscriptionStateRemoteRestore()' "${stateShim}" || return 1
    ! grep -q '^runRegressionSubscriptionStateSupport()' "${stateShim}" || return 1
    ! grep -q '^runRegressionSubscriptionStateSyncRollback()' "${stateShim}" || return 1
    ! grep -Eq '^[[:space:]]*subscription-state\)$' "${stateShim}" || return 1
    ! grep -Eq '^[[:space:]]*subscription-state-core\)$' "${stateShim}" || return 1
}

runSubscriptionStateShimPublicCliRetirementContract() {
    local stateShim="${PROJECT_ROOT}/shell/regression/subscription_groups_subscription_state.sh"
    runSubscriptionStateCliRetirementAssertions "${stateShim}"
}

runSubscriptionStateSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription_state.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_subscription_state_full.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q 'source "${REGRESSION_SUBSCRIPTION_STATE_SUITE_DIR}/../framework/runtime.sh"' "${suiteFile}"
    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_SUBSCRIPTION_STATE_SUITE_DIR}/../subscription_groups_subscription_state_full.sh"' "${suiteFile}"
    grep -Eq '^runRegressionSubscriptionStateCore\(\)[[:space:]]*[({]' "${suiteFile}"
    grep -Eq '^runRegressionSubscriptionState\(\)[[:space:]]*[({]' "${suiteFile}"
    ! grep -Eq '^runRegressionSubscriptionStateCoreSuiteRoot\(\)[[:space:]]*[({]' "${suiteFile}"
    ! grep -Eq '^runRegressionSubscriptionStateSuiteRoot\(\)[[:space:]]*[({]' "${suiteFile}"
    grep -Eq '^runRegressionSubscriptionStateStructureFoundation\(\)[[:space:]]*[({]' "${suiteFile}"
    grep -Eq '^runRegressionSubscriptionStateStructure\(\)[[:space:]]*[({]' "${suiteFile}"
    grep -Eq '^runRegressionSubscriptionStateQuota\(\)[[:space:]]*[({]' "${suiteFile}"
    grep -Eq '^runRegressionSubscriptionStateRemoteRestore\(\)[[:space:]]*[({]' "${suiteFile}"
    grep -Eq '^runRegressionSubscriptionStateSyncRollback\(\)[[:space:]]*[({]' "${suiteFile}"
    grep -Eq '^runRegressionSubscriptionStateSupport\(\)[[:space:]]*[({]' "${suiteFile}"
    grep -Eq '^runRegressionSubscriptionStateSerial\(\)[[:space:]]*[({]' "${suiteFile}"
    ! grep -Eq '^runRegressionSubscriptionStateCore\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionSubscriptionState\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionSubscriptionStateStructureFoundation\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionSubscriptionStateStructure\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionSubscriptionStateQuota\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionSubscriptionStateRemoteRestore\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionSubscriptionStateSyncRollback\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionSubscriptionStateSupport\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionSubscriptionStateSerial\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionSubscriptionState\(\)[[:space:]]*[({]' "${legacyFile}"
    ! grep -q 'registerRegressionScriptLeaf .*subscription_groups_subscription_state_full\.sh' "${suiteFile}"
    ! grep -q '^while read -r selector runner; do$' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-state-structure runRegressionSubscriptionStateStructure \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-state-structure-foundation runRegressionSubscriptionStateStructureFoundation \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-state-quota runRegressionSubscriptionStateQuota \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-state-remote-restore runRegressionSubscriptionStateRemoteRestore \\' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf subscription-state-support runRegressionSubscriptionStateSupport$' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-state-sync-rollback runRegressionSubscriptionStateSyncRollback \\' "${suiteFile}"
}

runSubscriptionStateNoEmptyAggregateWrapperFunctionsContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription_state.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_subscription_state_full.sh"

    ! grep -Eq '^runRegressionSubscriptionStateCoreSuiteRoot\(\)[[:space:]]*[({]' "${suiteFile}" || return 1
    ! grep -Eq '^runRegressionSubscriptionStateSuiteRoot\(\)[[:space:]]*[({]' "${suiteFile}" || return 1
    ! grep -Eq '^runRegressionSubscriptionStateCoreSuiteRoot\(\)[[:space:]]*[({]' "${scriptFile}" || return 1
    ! grep -Eq '^runRegressionSubscriptionStateSuiteRoot\(\)[[:space:]]*[({]' "${scriptFile}" || return 1
}

runSubscriptionStateSelectorHelpersStayAlignedContract() (
    local helperDir="${TMP_DIR}/subscription-state-selector-helpers"

    mkdir -p "${helperDir}"

    declare -F listRegressionSubscriptionStateCoreChildSelectors >/dev/null
    declare -F listRegressionSubscriptionStateChildSelectors >/dev/null
    declare -F listRegressionSubscriptionStateStructureFoundationChildSelectors >/dev/null
    declare -F listRegressionSubscriptionStateStructureChildSelectors >/dev/null
    declare -F listRegressionSubscriptionStateStructureMigrationChildSelectors >/dev/null
    declare -F listRegressionSubscriptionStateStructureSourceChildSelectors >/dev/null
    declare -F listRegressionSubscriptionStateQuotaChildSelectors >/dev/null
    declare -F listRegressionSubscriptionStateQuotaTrafficChildSelectors >/dev/null
    declare -F listRegressionSubscriptionStateQuotaMenuTransactionChildSelectors >/dev/null
    declare -F listRegressionSubscriptionStateQuotaPartialSyncChildSelectors >/dev/null
    declare -F listRegressionSubscriptionStateSupportChildSelectors >/dev/null
    declare -F listRegressionSubscriptionStateSerialChildSelectors >/dev/null
    declare -F listRegressionSubscriptionStateRemoteRestoreSelfReferenceChildSelectors >/dev/null
    declare -F listRegressionSubscriptionStateRemoteRestoreSerialChildSelectors >/dev/null
    declare -F listRegressionSubscriptionStateRemoteRestoreChildSelectors >/dev/null
    declare -F listRegressionSubscriptionStateSyncRollbackFailureSerialChildSelectors >/dev/null
    declare -F listRegressionSubscriptionStateSyncRollbackFailureChildSelectors >/dev/null

    subscriptionStateAssertSelectorList() {
        local helperFn=$1
        local helperName=$2
        shift 2
        local actualFile="${helperDir}/${helperName}.actual.txt"
        local expectedFile="${helperDir}/${helperName}.expected.txt"
        local sortedFile="${helperDir}/${helperName}.sorted.txt"
        local uniqueFile="${helperDir}/${helperName}.unique.txt"

        "${helperFn}" >"${actualFile}"
        printf '%s\n' "$@" >"${expectedFile}"

        cmp -s "${expectedFile}" "${actualFile}"
        sort "${actualFile}" >"${sortedFile}"
        sort -u "${actualFile}" >"${uniqueFile}"
        cmp -s "${sortedFile}" "${uniqueFile}"
    }

    subscriptionStateAssertSelectorList listRegressionSubscriptionStateCoreChildSelectors core \
        subscription-state-structure \
        subscription-state-quota \
        subscription-state-remote-restore
    subscriptionStateAssertSelectorList listRegressionSubscriptionStateChildSelectors default \
        subscription-state-core \
        subscription-state-support \
        subscription-state-sync-rollback
    subscriptionStateAssertSelectorList listRegressionSubscriptionStateStructureFoundationChildSelectors structure-foundation \
        subscription-state-structure-foundation-add-remove \
        subscription-state-structure-foundation-credential \
        subscription-state-structure-foundation-normalize \
        subscription-state-structure-foundation-init-transaction
    subscriptionStateAssertSelectorList listRegressionSubscriptionStateStructureChildSelectors structure \
        subscription-state-structure-foundation \
        subscription-state-structure-migration \
        subscription-state-structure-source
    subscriptionStateAssertSelectorList listRegressionSubscriptionStateStructureMigrationChildSelectors structure-migration \
        subscription-state-structure-migration-serial
    subscriptionStateAssertSelectorList listRegressionSubscriptionStateStructureSourceChildSelectors structure-source \
        subscription-state-structure-source-credential \
        subscription-state-structure-source-status \
        subscription-state-structure-source-remove \
        subscription-state-structure-source-serial
    subscriptionStateAssertSelectorList listRegressionSubscriptionStateQuotaChildSelectors quota \
        subscription-state-quota-traffic \
        subscription-state-quota-menu-tx \
        subscription-state-quota-partial-sync
    subscriptionStateAssertSelectorList listRegressionSubscriptionStateQuotaTrafficChildSelectors quota-traffic \
        subscription-state-quota-traffic-summary \
        subscription-state-quota-traffic-invalid-input \
        subscription-state-quota-traffic-apply \
        subscription-state-quota-traffic-serial
    subscriptionStateAssertSelectorList listRegressionSubscriptionStateQuotaMenuTransactionChildSelectors quota-menu-tx \
        subscription-state-quota-menu-preview-fail \
        subscription-state-quota-menu-tx-rollback \
        subscription-state-quota-menu-tx-serial
    subscriptionStateAssertSelectorList listRegressionSubscriptionStateQuotaPartialSyncChildSelectors quota-partial-sync \
        subscription-state-quota-partial-sync-apply-failure \
        subscription-state-quota-partial-sync-plan \
        subscription-state-quota-partial-sync-config \
        subscription-state-quota-partial-sync-serial
    subscriptionStateAssertSelectorList listRegressionSubscriptionStateSupportChildSelectors support \
        subscription-sync-tempdir \
        subscription-sync-restore-pair-failure-message \
        subscription-sync-append-restore-failure-detail \
        subscription-sync-single-restore-result-message \
        subscription-sync-rollback-result-message \
        subscription-sync-reconcile-early-exit \
        subscription-group-sync-publish-refresh-inline \
        subscription-groups-restore-failure
    subscriptionStateAssertSelectorList listRegressionSubscriptionStateSerialChildSelectors serial \
        subscription-state \
        subscription-sync-tempdir \
        subscription-sync-restore-pair-failure-message \
        subscription-sync-append-restore-failure-detail \
        subscription-sync-single-restore-result-message \
        subscription-sync-rollback-result-message \
        subscription-sync-rollback-failure-serial \
        subscription-sync-reconcile-early-exit \
        subscription-groups-restore-failure
    subscriptionStateAssertSelectorList listRegressionSubscriptionStateRemoteRestoreSelfReferenceChildSelectors remote-restore-self-reference \
        subscription-state-remote-restore-self-reference-plan \
        subscription-state-remote-restore-self-reference-sync
    subscriptionStateAssertSelectorList listRegressionSubscriptionStateRemoteRestoreSerialChildSelectors remote-restore-serial \
        subscription-state-remote-restore-self-reference \
        subscription-state-remote-restore-state-write \
        subscription-state-remote-restore-legacy-menu
    subscriptionStateAssertSelectorList listRegressionSubscriptionStateRemoteRestoreChildSelectors remote-restore \
        subscription-state-remote-restore-self-reference \
        subscription-state-remote-restore-state-write \
        subscription-state-remote-restore-legacy-menu
    subscriptionStateAssertSelectorList listRegressionSubscriptionStateSyncRollbackFailureSerialChildSelectors sync-rollback-failure-serial \
        subscription-sync-rollback-config-restore-failure \
        subscription-sync-restore-dir-failure \
        subscription-sync-reload-rollback \
        subscription-group-sync-rollback-serial
    subscriptionStateAssertSelectorList listRegressionSubscriptionStateSyncRollbackFailureChildSelectors sync-rollback-failure \
        subscription-sync-rollback-config-restore-failure \
        subscription-sync-restore-dir-failure \
        subscription-sync-reload-rollback \
        subscription-group-sync-rollback
)

runSubscriptionStateNestedSelectorHelpersAreSuiteOwnedContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription_state.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_subscription_state_full.sh"
    local functionName

    for functionName in \
        runSubscriptionStateParallelChildRegressionIsolated \
        listRegressionSubscriptionStateStructureFoundationChildSelectors \
        runRegressionSubscriptionStateStructureFoundation \
        runRegressionSubscriptionStateStructureFoundationIsolated \
        listRegressionSubscriptionStateStructureMigrationChildSelectors \
        runRegressionSubscriptionStateStructureMigrationIsolated \
        listRegressionSubscriptionStateStructureSourceChildSelectors \
        runRegressionSubscriptionStateStructureSourceIsolated \
        listRegressionSubscriptionStateStructureChildSelectors \
        runRegressionSubscriptionStateStructureSelector \
        runRegressionSubscriptionStateStructure \
        listRegressionSubscriptionStateQuotaChildSelectors \
        listRegressionSubscriptionStateQuotaTrafficChildSelectors \
        listRegressionSubscriptionStateQuotaMenuTransactionChildSelectors \
        listRegressionSubscriptionStateQuotaPartialSyncChildSelectors \
        runRegressionSubscriptionStateQuota \
        listRegressionSubscriptionStateSupportChildSelectors \
        listRegressionSubscriptionStateSerialChildSelectors \
        listRegressionSubscriptionStateRemoteRestoreSelfReferenceChildSelectors \
        listRegressionSubscriptionStateRemoteRestoreSerialChildSelectors \
        runRegressionSubscriptionStateRemoteRestoreSelfReferenceIsolated \
        runRegressionSubscriptionStateRemoteRestoreStateWriteIsolated \
        runRegressionSubscriptionStateRemoteRestoreLegacyMenuIsolated \
        listRegressionSubscriptionStateRemoteRestoreChildSelectors \
        listRegressionSubscriptionStateSyncRollbackFailureSerialChildSelectors \
        runRegressionSubscriptionStateRemoteRestoreSelector \
        runRegressionSubscriptionStateRemoteRestore \
        runRegressionSubscriptionSyncRollbackConfigRestoreFailureIsolated \
        runRegressionSubscriptionSyncRollbackRestoreDirFailureIsolated \
        runRegressionSubscriptionSyncRollbackReloadRollbackIsolated \
        runRegressionSubscriptionGroupSyncRollbackIsolated \
        listRegressionSubscriptionStateSyncRollbackFailureChildSelectors \
        runRegressionSubscriptionStateSyncRollbackFailureSelector \
        runRegressionSubscriptionStateSyncRollback \
        runRegressionSubscriptionStateSupport \
        runRegressionSubscriptionStateSerial
    do
        grep -Eq "^${functionName}\(\)[[:space:]]*[({]" "${suiteFile}" || return 1
        ! grep -Eq "^${functionName}\(\)[[:space:]]*[({]" "${scriptFile}" || return 1
    done
}

runSubscriptionStateSupportChildStepsContract() {
    local callLog="${TMP_DIR}/subscription-state-support-sequential-helper.log"

    runRegisteredRegressionMain() {
        printf 'dispatch:%s\n' "$1" >>"${callLog}"
    }

    runSequentialSelectorListUsesFrameworkHelperAssertions \
        "${callLog}" \
        'dispatch:subscription-sync-tempdir' \
        runFrameworkSequentialRegressionSelectorList \
        listRegressionSubscriptionStateSupportChildSelectors
    grep -qx 'dispatch:subscription-sync-restore-pair-failure-message' "${callLog}"
    grep -qx 'dispatch:subscription-sync-append-restore-failure-detail' "${callLog}"
    grep -qx 'dispatch:subscription-sync-single-restore-result-message' "${callLog}"
    grep -qx 'dispatch:subscription-sync-rollback-result-message' "${callLog}"
    grep -qx 'dispatch:subscription-sync-reconcile-early-exit' "${callLog}"
    grep -qx 'dispatch:subscription-group-sync-publish-refresh-inline' "${callLog}"
    grep -qx 'dispatch:subscription-groups-restore-failure' "${callLog}"
}

runSubscriptionStateSerialChildStepsContract() {
    local callLog="${TMP_DIR}/subscription-state-serial-sequential-helper.log"

    runRegisteredRegressionMain() {
        printf 'dispatch:%s\n' "$1" >>"${callLog}"
    }

    runSequentialSelectorListUsesFrameworkHelperAssertions \
        "${callLog}" \
        'dispatch:subscription-state' \
        runFrameworkSequentialRegressionSelectorList \
        listRegressionSubscriptionStateSerialChildSelectors
    grep -qx 'dispatch:subscription-sync-tempdir' "${callLog}"
    grep -qx 'dispatch:subscription-sync-restore-pair-failure-message' "${callLog}"
    grep -qx 'dispatch:subscription-sync-append-restore-failure-detail' "${callLog}"
    grep -qx 'dispatch:subscription-sync-single-restore-result-message' "${callLog}"
    grep -qx 'dispatch:subscription-sync-rollback-result-message' "${callLog}"
    grep -qx 'dispatch:subscription-sync-rollback-failure-serial' "${callLog}"
    grep -qx 'dispatch:subscription-sync-reconcile-early-exit' "${callLog}"
    grep -qx 'dispatch:subscription-groups-restore-failure' "${callLog}"
}

runSubscriptionStateStructureSourceChildStepsContract() {
    local callLog="${TMP_DIR}/subscription-state-structure-source-sequential-helper.log"

    runRegisteredRegressionMain() {
        printf 'dispatch:%s\n' "$1" >>"${callLog}"
    }

    runSequentialSelectorListUsesFrameworkHelperAssertions \
        "${callLog}" \
        'dispatch:subscription-state-structure-source-credential' \
        runFrameworkSequentialRegressionSelectorList \
        listRegressionSubscriptionStateStructureSourceChildSelectors
    grep -qx 'dispatch:subscription-state-structure-source-status' "${callLog}"
    grep -qx 'dispatch:subscription-state-structure-source-remove' "${callLog}"
    grep -qx 'dispatch:subscription-state-structure-source-serial' "${callLog}"
}

runSubscriptionStateStructureMigrationChildStepsContract() {
    local callLog="${TMP_DIR}/subscription-state-structure-migration-sequential-helper.log"

    runRegisteredRegressionMain() {
        printf 'dispatch:%s\n' "$1" >>"${callLog}"
    }

    runSequentialSelectorListUsesFrameworkHelperAssertions \
        "${callLog}" \
        'dispatch:subscription-state-structure-migration-serial' \
        runFrameworkSequentialRegressionSelectorList \
        listRegressionSubscriptionStateStructureMigrationChildSelectors
}

runSubscriptionStateQuotaTrafficChildStepsContract() {
    local callLog="${TMP_DIR}/subscription-state-quota-traffic-sequential-helper.log"

    runRegisteredRegressionMain() {
        printf 'dispatch:%s\n' "$1" >>"${callLog}"
    }

    runSequentialSelectorListUsesFrameworkHelperAssertions \
        "${callLog}" \
        'dispatch:subscription-state-quota-traffic-summary' \
        runFrameworkSequentialRegressionSelectorList \
        listRegressionSubscriptionStateQuotaTrafficChildSelectors
    grep -qx 'dispatch:subscription-state-quota-traffic-invalid-input' "${callLog}"
    grep -qx 'dispatch:subscription-state-quota-traffic-apply' "${callLog}"
    grep -qx 'dispatch:subscription-state-quota-traffic-serial' "${callLog}"
}

runSubscriptionStateQuotaMenuTransactionChildStepsContract() {
    local callLog="${TMP_DIR}/subscription-state-quota-menu-tx-sequential-helper.log"

    runRegisteredRegressionMain() {
        printf 'dispatch:%s\n' "$1" >>"${callLog}"
    }

    runSequentialSelectorListUsesFrameworkHelperAssertions \
        "${callLog}" \
        'dispatch:subscription-state-quota-menu-preview-fail' \
        runFrameworkSequentialRegressionSelectorList \
        listRegressionSubscriptionStateQuotaMenuTransactionChildSelectors
    grep -qx 'dispatch:subscription-state-quota-menu-tx-rollback' "${callLog}"
    grep -qx 'dispatch:subscription-state-quota-menu-tx-serial' "${callLog}"
}

runSubscriptionStateQuotaPartialSyncChildStepsContract() {
    local callLog="${TMP_DIR}/subscription-state-quota-partial-sync-sequential-helper.log"

    runRegisteredRegressionMain() {
        printf 'dispatch:%s\n' "$1" >>"${callLog}"
    }

    runSequentialSelectorListUsesFrameworkHelperAssertions \
        "${callLog}" \
        'dispatch:subscription-state-quota-partial-sync-apply-failure' \
        runFrameworkSequentialRegressionSelectorList \
        listRegressionSubscriptionStateQuotaPartialSyncChildSelectors
    grep -qx 'dispatch:subscription-state-quota-partial-sync-plan' "${callLog}"
    grep -qx 'dispatch:subscription-state-quota-partial-sync-config' "${callLog}"
    grep -qx 'dispatch:subscription-state-quota-partial-sync-serial' "${callLog}"
}

runSubscriptionStateRemoteRestoreSelfReferenceChildStepsContract() {
    local callLog="${TMP_DIR}/subscription-state-remote-restore-self-reference-sequential-helper.log"

    runRegisteredRegressionMain() {
        printf 'dispatch:%s\n' "$1" >>"${callLog}"
    }

    runSequentialSelectorListUsesFrameworkHelperAssertions \
        "${callLog}" \
        'dispatch:subscription-state-remote-restore-self-reference-plan' \
        runFrameworkSequentialRegressionSelectorList \
        listRegressionSubscriptionStateRemoteRestoreSelfReferenceChildSelectors
    grep -qx 'dispatch:subscription-state-remote-restore-self-reference-sync' "${callLog}"
}

runSubscriptionStateRemoteRestoreSerialChildStepsContract() {
    local callLog="${TMP_DIR}/subscription-state-remote-restore-serial-sequential-helper.log"

    runRegisteredRegressionMain() {
        printf 'dispatch:%s\n' "$1" >>"${callLog}"
    }

    runSequentialSelectorListUsesFrameworkHelperAssertions \
        "${callLog}" \
        'dispatch:subscription-state-remote-restore-self-reference' \
        runFrameworkSequentialRegressionSelectorList \
        listRegressionSubscriptionStateRemoteRestoreSerialChildSelectors
    grep -qx 'dispatch:subscription-state-remote-restore-state-write' "${callLog}"
    grep -qx 'dispatch:subscription-state-remote-restore-legacy-menu' "${callLog}"
}

runSubscriptionStateSyncRollbackFailureSerialChildStepsContract() {
    local callLog="${TMP_DIR}/subscription-state-sync-rollback-failure-serial-sequential-helper.log"

    runRegisteredRegressionMain() {
        printf 'dispatch:%s\n' "$1" >>"${callLog}"
    }

    runSequentialSelectorListUsesFrameworkHelperAssertions \
        "${callLog}" \
        'dispatch:subscription-sync-rollback-config-restore-failure' \
        runFrameworkSequentialRegressionSelectorList \
        listRegressionSubscriptionStateSyncRollbackFailureSerialChildSelectors
    grep -qx 'dispatch:subscription-sync-restore-dir-failure' "${callLog}"
    grep -qx 'dispatch:subscription-sync-reload-rollback' "${callLog}"
    grep -qx 'dispatch:subscription-group-sync-rollback-serial' "${callLog}"
}

runSubscriptionStateCoreAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription_state.sh"
    local expectedChildren

    ! grep -q '^registerRegressionFunctionLeaf subscription-state-core ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateParallel subscription-state-core \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-state-core runRegressionSubscriptionStateCore \\' "${suiteFile}"
    expectedChildren=$(listRegressionSubscriptionStateCoreChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        subscription-state-core \
        parallel \
        runRegressionSubscriptionStateCore \
        "${expectedChildren}"
}

runSubscriptionStateAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription_state.sh"
    local expectedChildren

    ! grep -q '^registerRegressionFunctionLeaf subscription-state ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateParallel subscription-state \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription-state runRegressionSubscriptionState \\' "${suiteFile}"
    expectedChildren=$(listRegressionSubscriptionStateChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        subscription-state \
        parallel \
        runRegressionSubscriptionState \
        "${expectedChildren}"
}

runSubscriptionStateNestedAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription_state.sh"

    ! grep -q '^registerRegressionFunctionLeaf subscription-state-structure ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf subscription-state-structure-foundation ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf subscription-state-quota ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf subscription-state-remote-restore ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf subscription-state-sync-rollback ' "${suiteFile}" || return 1

    grep -q '^registerRegressionAggregateRunnerParallel subscription-state-structure runRegressionSubscriptionStateStructure \\' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallel subscription-state-structure-foundation runRegressionSubscriptionStateStructureFoundation \\' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallel subscription-state-quota runRegressionSubscriptionStateQuota \\' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallel subscription-state-remote-restore runRegressionSubscriptionStateRemoteRestore \\' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallel subscription-state-sync-rollback runRegressionSubscriptionStateSyncRollback \\' "${suiteFile}" || return 1

    runAggregateRunnerRegistrationAssertions \
        subscription-state-structure \
        parallel \
        runRegressionSubscriptionStateStructure \
        "$(listRegressionSubscriptionStateStructureChildSelectors)"
    runAggregateRunnerRegistrationAssertions \
        subscription-state-structure-foundation \
        parallel \
        runRegressionSubscriptionStateStructureFoundation \
        "$(listRegressionSubscriptionStateStructureFoundationChildSelectors)"
    runAggregateRunnerRegistrationAssertions \
        subscription-state-quota \
        parallel \
        runRegressionSubscriptionStateQuota \
        "$(listRegressionSubscriptionStateQuotaChildSelectors)"
    runAggregateRunnerRegistrationAssertions \
        subscription-state-remote-restore \
        parallel \
        runRegressionSubscriptionStateRemoteRestore \
        "$(listRegressionSubscriptionStateRemoteRestoreChildSelectors)"
    runAggregateRunnerRegistrationAssertions \
        subscription-state-sync-rollback \
        parallel \
        runRegressionSubscriptionStateSyncRollback \
        "$(listRegressionSubscriptionStateSyncRollbackFailureChildSelectors)"
}

runSubscriptionStateNestedAggregateRunnerRegistrationCoveredByDispatcherContract() {
    local contractsFile="${PROJECT_ROOT}/shell/regression/suites/contracts.sh"
    runRegressionDispatcherStepCoverageAssertions \
        "${contractsFile}" \
        subscription-state-nested-aggregate-runner-registration \
        runSubscriptionStateNestedAggregateRunnerRegistrationContract
}

runSubscriptionStateFullUsesFrameworkParallelHelperContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription_state.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_subscription_state_full.sh"
    local coreBody
    local stateBody
    local structureFoundationBody
    local structureBody
    local quotaBody
    local remoteRestoreBody
    local syncRollbackBody

    ! grep -q 'PADM_SECTION_BEGIN: subscription-state-hot-regressions' "${scriptFile}"
    ! grep -q 'PADM_SECTION_END: subscription-state-hot-regressions' "${scriptFile}"
    ! grep -q '^runParallelSubscriptionStateModes()' "${scriptFile}"
    grep -q 'source "${REGRESSION_SUBSCRIPTION_STATE_SUITE_DIR}/../framework/runtime.sh"' "${suiteFile}"
    ! grep -q 'source "${REGRESSION_ENTRY_DIR}/regression/framework/runtime.sh"' "${scriptFile}"
    ! grep -Eq '^runRegressionSubscriptionStateCore\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionSubscriptionState\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^[[:space:]]*subscription-state\)$' "${scriptFile}"
    ! grep -Eq '^[[:space:]]*subscription-state-core\)$' "${scriptFile}"
    ! grep -q '^listRegressionSubscriptionStateStructureFoundationChildSelectors() {$' "${scriptFile}"
    ! grep -q '^listRegressionSubscriptionStateStructureChildSelectors() {$' "${scriptFile}"
    ! grep -q '^listRegressionSubscriptionStateQuotaChildSelectors() {$' "${scriptFile}"
    ! grep -q '^listRegressionSubscriptionStateRemoteRestoreChildSelectors() {$' "${scriptFile}"
    ! grep -q '^listRegressionSubscriptionStateSyncRollbackFailureChildSelectors() {$' "${scriptFile}"
    ! grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-structure-foundation"' "${scriptFile}"
    ! grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-structure"' "${scriptFile}"
    ! grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-quota"' "${scriptFile}"
    ! grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-remote-restore"' "${scriptFile}"
    ! grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-sync-rollback-failure"' "${scriptFile}"

    coreBody=$(sed -n '/^runRegressionSubscriptionStateCore() {$/,/^}$/p' "${suiteFile}")
    stateBody=$(sed -n '/^runRegressionSubscriptionState() {$/,/^}$/p' "${suiteFile}")
    structureFoundationBody=$(sed -n '/^runRegressionSubscriptionStateStructureFoundation() {$/,/^}$/p' "${suiteFile}")
    structureBody=$(sed -n '/^runRegressionSubscriptionStateStructure() {$/,/^}$/p' "${suiteFile}")
    quotaBody=$(sed -n '/^runRegressionSubscriptionStateQuota() {$/,/^}$/p' "${suiteFile}")
    remoteRestoreBody=$(sed -n '/^runRegressionSubscriptionStateRemoteRestore() {$/,/^}$/p' "${suiteFile}")
    syncRollbackBody=$(sed -n '/^runRegressionSubscriptionStateSyncRollback() {$/,/^}$/p' "${suiteFile}")

    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-core-' <<<"${coreBody}"
    ! grep -q 'runParallelSubscriptionStateModes' <<<"${coreBody}"
    ! grep -q 'PADM_REGRESSION_INTERNAL_CLI=1 bash' <<<"${coreBody}"
    grep -q 'listRegressionSubscriptionStateCoreChildSelectors' <<<"${coreBody}"

    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-default-' <<<"${stateBody}"
    ! grep -q 'runParallelSubscriptionStateModes' <<<"${stateBody}"
    ! grep -q 'PADM_REGRESSION_INTERNAL_CLI=1 bash' <<<"${stateBody}"
    grep -q 'listRegressionSubscriptionStateChildSelectors' <<<"${stateBody}"

    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-structure-foundation"' <<<"${structureFoundationBody}"
    grep -q 'listRegressionSubscriptionStateStructureFoundationChildSelectors' <<<"${structureFoundationBody}"

    grep -q 'PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionSubscriptionStateStructureSelector' <<<"${structureBody}"
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-structure"' <<<"${structureBody}"
    grep -q 'listRegressionSubscriptionStateStructureChildSelectors' <<<"${structureBody}"

    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-quota"' <<<"${quotaBody}"
    grep -q 'listRegressionSubscriptionStateQuotaChildSelectors' <<<"${quotaBody}"

    grep -q 'PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionSubscriptionStateRemoteRestoreSelector' <<<"${remoteRestoreBody}"
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-state-remote-restore"' <<<"${remoteRestoreBody}"
    grep -q 'listRegressionSubscriptionStateRemoteRestoreChildSelectors' <<<"${remoteRestoreBody}"

    grep -q 'PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionSubscriptionStateSyncRollbackFailureSelector' <<<"${syncRollbackBody}"
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-sync-rollback-failure"' <<<"${syncRollbackBody}"
    grep -q 'listRegressionSubscriptionStateSyncRollbackFailureChildSelectors' <<<"${syncRollbackBody}"
}

runSubscriptionStateFullPublicCliRetirementContract() {
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_subscription_state_full.sh"
    runSubscriptionStateCliRetirementAssertions "${scriptFile}"
}

runSubscriptionStateAggregatesSupportSourceOnlyExecutionContract() (
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription_state.sh"
    local callsFile="${TMP_DIR}/subscription-state-aggregate-runner-calls"
    local -a calls=()

    if ! declare -F runRegressionSubscriptionStateCore >/dev/null; then
        PADM_REGRESSION_SOURCE_ONLY=1 source "${suiteFile}"
    fi

    runParallelRegressionSelectors() {
        printf 'subscription-state aggregate should not require selector registry in source-only mode\n' >&2
        return 97
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:%s\n' "$*" >>"${callsFile}"
    }

    runParallelRegressionRunners() {
        printf 'legacy-runner:%s\n' "$*" >>"${callsFile}"
        return 97
    }

    : >"${callsFile}"
    runRegressionSubscriptionStateCore
    runRegressionSubscriptionState
    runRegressionSubscriptionStateStructureFoundation
    runRegressionSubscriptionStateStructure
    runRegressionSubscriptionStateQuota
    runRegressionSubscriptionStateRemoteRestore
    runRegressionSubscriptionStateSyncRollback

    mapfile -t calls <"${callsFile}"
    [[ "${#calls[@]}" -eq 7 ]]
    [[ "${calls[0]}" == framework:"${TMP_DIR}/subscription-state-core-"* ]]
    [[ "${calls[1]}" == framework:"${TMP_DIR}/subscription-state-default-"* ]]
    [[ "${calls[0]}" == *' subscription-state-structure subscription-state-structure subscription-state-quota subscription-state-quota subscription-state-remote-restore subscription-state-remote-restore' ]]
    [[ "${calls[1]}" == *' subscription-state-core subscription-state-core subscription-state-support subscription-state-support subscription-state-sync-rollback subscription-state-sync-rollback' ]]
    [[ "${calls[2]}" == "framework:${TMP_DIR}/subscription-state-structure-foundation subscription-state-structure-foundation-add-remove subscription-state-structure-foundation-add-remove subscription-state-structure-foundation-credential subscription-state-structure-foundation-credential subscription-state-structure-foundation-normalize subscription-state-structure-foundation-normalize subscription-state-structure-foundation-init-transaction subscription-state-structure-foundation-init-transaction" ]]
    [[ "${calls[3]}" == "framework:${TMP_DIR}/subscription-state-structure subscription-state-structure-foundation subscription-state-structure-foundation subscription-state-structure-migration subscription-state-structure-migration subscription-state-structure-source subscription-state-structure-source" ]]
    [[ "${calls[4]}" == "framework:${TMP_DIR}/subscription-state-quota subscription-state-quota-traffic subscription-state-quota-traffic subscription-state-quota-menu-tx subscription-state-quota-menu-tx subscription-state-quota-partial-sync subscription-state-quota-partial-sync" ]]
    [[ "${calls[5]}" == "framework:${TMP_DIR}/subscription-state-remote-restore subscription-state-remote-restore-self-reference subscription-state-remote-restore-self-reference subscription-state-remote-restore-state-write subscription-state-remote-restore-state-write subscription-state-remote-restore-legacy-menu subscription-state-remote-restore-legacy-menu" ]]
    [[ "${calls[6]}" == "framework:${TMP_DIR}/subscription-sync-rollback-failure subscription-sync-rollback-config-restore-failure subscription-sync-rollback-config-restore-failure subscription-sync-restore-dir-failure subscription-sync-restore-dir-failure subscription-sync-reload-rollback subscription-sync-reload-rollback subscription-group-sync-rollback subscription-group-sync-rollback" ]]
    ! grep -q '^legacy-runner:' "${callsFile}"
)

runRemoteControlSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/remote_control.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_remote_control.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q 'source "${REGRESSION_REMOTE_CONTROL_SUITE_DIR}/../framework/runtime.sh"' "${suiteFile}"
    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_REMOTE_CONTROL_SUITE_DIR}/../subscription_groups_remote_control.sh"' "${suiteFile}"
    grep -Eq '^runRegressionRemoteControlSmokeCore\(\)[[:space:]]*[({]' "${suiteFile}"
    grep -q '^runRegressionRemoteControlLegacyLeafWithCompat() ($' "${suiteFile}"
    grep -q '^runRegressionRemoteControlLegacyTmpDirIsolationRegression() ($' "${suiteFile}"
    ! grep -Eq '^runRegressionRemoteControl\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionRemoteControlSmokeRefresh\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionRemoteControlSmokeRefreshApply\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionRemoteControlSmoke\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionRemoteControlContract\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionRemoteControlContractServiceInstall\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionRemoteControlSmokeCore\(\)[[:space:]]*[({]' "${scriptFile}"
    ! grep -Eq '^runRegressionRemoteControl\(\)[[:space:]]*[({]' "${legacyFile}"
    ! grep -q 'registerRegressionScriptLeaf .*subscription_groups_remote_control\.sh' "${suiteFile}"
    ! grep -q '^while read -r selector runner; do$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-smoke-core runRegressionRemoteControlSmokeCore$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-concurrency runRegressionRemoteControlConcurrency$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-aggregation-failure runRegressionRemoteControlAggregationFailure$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-inline-aggregation-helpers runRegressionRemoteControlInlineAggregationHelpers$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-health runRegressionRemoteControlHealth$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-inline-request-helpers runRegressionRemoteControlInlineRequestHelpers$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-inline-wireguard-peer-helpers runRegressionRemoteControlInlineWireGuardPeerHelpers$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-inline-token-consumers runRegressionRemoteControlInlineTokenConsumers$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-inline-sync-runner runRegressionRemoteControlInlineSyncRunner$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-handle-inline-helpers runRegressionRemoteControlHandleInlineHelpers$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-smoke-refresh-apply-basic runRegressionRemoteControlSmokeRefreshApplyBasic$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-smoke-refresh-apply-prepare runRegressionRemoteControlSmokeRefreshApplyPrepare$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-smoke-refresh-apply-failure runRegressionRemoteControlSmokeRefreshApplyFailure$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-smoke-refresh-restore runRegressionRemoteControlSmokeRefreshRestore$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-smoke-refresh-reconcile runRegressionRemoteControlSmokeRefreshReconcile$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-contract-service-install-success runRegressionRemoteControlContractServiceInstallSuccess$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-contract-service-install-systemctl-fail runRegressionRemoteControlContractServiceInstallSystemctlFail$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-contract-service-install-health-fail runRegressionRemoteControlContractServiceInstallHealthFail$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-contract-service-install-health-rollback runRegressionRemoteControlContractServiceInstallHealthRollback$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-contract-service-install-token-transaction runRegressionRemoteControlContractServiceInstallTokenTransaction$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-contract-server-response runRegressionRemoteControlLegacyLeafWithCompat runRegressionRemoteControlContractServerResponse$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf remote-control-deep runRegressionRemoteControlLegacyLeafWithCompat runRegressionRemoteControlDeep$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf regression-remote-control-legacy-tmpdir-isolation runRegressionRemoteControlLegacyTmpDirIsolationRegression$' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateParallel remote-control-smoke \\' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateParallel remote-control-contract \\' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateParallel remote-control \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallelWithArgs \\' "${suiteFile}"
    ! grep -q '^registerRegressionAlias remote-control-light remote-control$' "${suiteFile}"

    ! grep -q '^runParallelRemoteControlModes()' "${scriptFile}"
    ! grep -q '^runParallelRemoteControlTotals()' "${scriptFile}"
    ! grep -q 'PADM_REGRESSION_SUPPRESS_DONE=1 PADM_REGRESSION_INTERNAL_CLI=1 bash "\${REMOTE_CONTROL_SCRIPT_PATH}"' "${scriptFile}"
    grep -q '^listRegressionRemoteControlSmokeRefreshApplyChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionRemoteControlSmokeRefreshChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionRemoteControlSmokeChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionRemoteControlContractServiceInstallChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionRemoteControlContractChildSelectors() {$' "${suiteFile}"
    ! grep -q '^listRegressionRemoteControlSmokeRefreshApplyChildSelectors() {$' "${scriptFile}"
    ! grep -q '^listRegressionRemoteControlSmokeRefreshChildSelectors() {$' "${scriptFile}"
    ! grep -q '^listRegressionRemoteControlSmokeChildSelectors() {$' "${scriptFile}"
    ! grep -q '^listRegressionRemoteControlContractServiceInstallChildSelectors() {$' "${scriptFile}"
    ! grep -q '^listRegressionRemoteControlContractChildSelectors() {$' "${scriptFile}"
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/remote-control-smoke-refresh"' "${suiteFile}"
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/remote-control-smoke-refresh-apply"' "${suiteFile}"
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/remote-control-smoke"' "${suiteFile}"
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/remote-control-contract"' "${suiteFile}"
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/remote-control-contract-service-install"' "${suiteFile}"
    ! grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/remote-control-smoke-refresh"' "${scriptFile}"
    ! grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/remote-control-smoke-refresh-apply"' "${scriptFile}"
    ! grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/remote-control-smoke"' "${scriptFile}"
    ! grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/remote-control-contract"' "${scriptFile}"
    ! grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/remote-control-contract-service-install"' "${scriptFile}"
    grep -q 'remote-control-smoke-refresh-apply-basic' "${suiteFile}"
    grep -q 'remote-control-contract-service-install-token-transaction' "${suiteFile}"
}

runRemoteControlPublicSelectorRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/remote_control.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_remote_control.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local usageLine
    local usageSelectors
    local selector

    ! grep -q '^registerRegressionAlias remote-control-light remote-control$' "${suiteFile}" || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["remote-control"]:-}" == "aggregate-runner" ]] || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["remote-control-smoke"]:-}" == "aggregate-runner" ]] || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["remote-control-contract"]:-}" == "aggregate-runner" ]] || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["remote-control-smoke-refresh"]:-}" == "aggregate-runner" ]] || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["remote-control-smoke-refresh-apply"]:-}" == "aggregate-runner" ]] || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["remote-control-contract-service-install"]:-}" == "aggregate-runner" ]] || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["remote-control-deep"]:-}" == "function" ]] || return 1
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["remote-control-light"]:-}" ]] || return 1

    usageLine=$(grep -F 'usage: %s [' "${scriptFile}" || true)
    usageSelectors="${usageLine#*[}"
    usageSelectors="${usageSelectors%%]*}"

    for selector in "${!PADM_REGRESSION_SELECTOR_KIND[@]}"; do
        [[ "${selector}" == remote-control* ]] || continue
        [[ -n "${selector}" ]] || continue
        ! awk -v sel="${selector}" '
            {
                line = $0
                sub(/^[[:space:]]+/, "", line)
                if (line == sel ")") {
                    found = 1
                }
            }
            END { exit(found ? 0 : 1) }
        ' "${scriptFile}" || return 1
        [[ -z "${usageLine}" || "|${usageSelectors}|" != *"|${selector}|"* ]] || return 1
    done

    ! grep -Eq '^[[:space:]]*remote-control-light\)$' "${scriptFile}" || return 1
    ! grep -Fq 'remote-control-light|' "${scriptFile}" || return 1
    ! grep -Eq '^[[:space:]]*remote-control\)$' "${legacyFile}" || return 1
}

runLegacyRetiresSuiteOwnedWrappersContract() {
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local status=0

    grep -Eq '^runRegressionSubscriptionState\(\)[[:space:]]*[({]' "${legacyFile}" && status=1
    grep -Eq '^runRegressionRemoteControl\(\)[[:space:]]*[({]' "${legacyFile}" && status=1
    grep -Eq '^[[:space:]]*subscription-state\)$' "${legacyFile}" && status=1
    grep -Eq '^[[:space:]]*remote-control\)$' "${legacyFile}" && status=1
    grep -Fq '|subscription-state|' "${legacyFile}" && status=1
    grep -Fq '|remote-control|' "${legacyFile}" && status=1

    return "${status}"
}

runRemoteControlAggregatesSupportSourceOnlyExecutionContract() (
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/remote_control.sh"
    local callsFile="${TMP_DIR}/remote-control-aggregate-runner-calls"
    local -a calls=()

    if [[ "${PADM_REGRESSION_SELECTOR_KIND["remote-control"]:-}" != "aggregate-runner" ]]; then
        PADM_REGRESSION_SOURCE_ONLY=1 source "${suiteFile}"
    fi

    runParallelRegressionSelectors() {
        printf 'remote-control aggregate should not require selector registry in source-only mode\n' >&2
        return 97
    }

    runParallelRegressionRunners() {
        printf 'legacy-runner:%s\n' "$*" >>"${callsFile}"
        return 97
    }

    runFrameworkParallelRegressionSelectorList() {
        local orchestrationRoot=$1
        local selectorListFn=$2
        shift 2
        local -a selectors=()

        mapfile -t selectors < <("${selectorListFn}" "$@")
        printf 'framework:list:%s:%s:%s\n' \
            "${orchestrationRoot}" \
            "${selectorListFn}" \
            "${selectors[*]}" >>"${callsFile}"
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:selectors:%s\n' "$*" >>"${callsFile}"
        return 97
    }

    : >"${callsFile}"
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain remote-control
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain remote-control-smoke-refresh
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain remote-control-smoke-refresh-apply
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain remote-control-smoke
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain remote-control-contract
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain remote-control-contract-service-install

    mapfile -t calls <"${callsFile}"
    [[ "${#calls[@]}" -eq 6 ]] || return 1
    [[ "${calls[0]}" =~ ^framework:list:.*/remote-control-default-[0-9]+:listRegressionRemoteControlChildSelectors:remote-control-smoke\ remote-control-contract\ remote-control-deep$ ]] || return 1
    [[ "${calls[1]}" =~ ^framework:list:.*/remote-control-smoke-refresh:listRegressionRemoteControlSmokeRefreshChildSelectors:remote-control-smoke-refresh-apply\ remote-control-smoke-refresh-restore\ remote-control-smoke-refresh-reconcile$ ]] || return 1
    [[ "${calls[2]}" =~ ^framework:list:.*/remote-control-smoke-refresh-apply:listRegressionRemoteControlSmokeRefreshApplyChildSelectors:remote-control-smoke-refresh-apply-basic\ remote-control-smoke-refresh-apply-prepare\ remote-control-smoke-refresh-apply-failure$ ]] || return 1
    [[ "${calls[3]}" =~ ^framework:list:.*/remote-control-smoke:listRegressionRemoteControlSmokeChildSelectors:remote-control-smoke-core\ remote-control-smoke-refresh$ ]] || return 1
    [[ "${calls[4]}" =~ ^framework:list:.*/remote-control-contract:listRegressionRemoteControlContractChildSelectors:remote-control-contract-service-install\ remote-control-contract-server-response$ ]] || return 1
    [[ "${calls[5]}" =~ ^framework:list:.*/remote-control-contract-service-install:listRegressionRemoteControlContractServiceInstallChildSelectors:remote-control-contract-service-install-success\ remote-control-contract-service-install-systemctl-fail\ remote-control-contract-service-install-health-fail\ remote-control-contract-service-install-health-rollback\ remote-control-contract-service-install-token-transaction$ ]] || return 1
    ! grep -q '^legacy-runner:' "${callsFile}" || return 1
    ! grep -q '^framework:selectors:' "${callsFile}" || return 1
)

runRemoteControlSelectorHelpersStayAlignedContract() (
    local helperDir="${TMP_DIR}/remote-control-selector-helpers"

    mkdir -p "${helperDir}"

    declare -F listRegressionRemoteControlChildSelectors >/dev/null
    declare -F listRegressionRemoteControlSmokeRefreshApplyChildSelectors >/dev/null
    declare -F listRegressionRemoteControlSmokeRefreshChildSelectors >/dev/null
    declare -F listRegressionRemoteControlSmokeChildSelectors >/dev/null
    declare -F listRegressionRemoteControlSmokeCoreChildSelectors >/dev/null
    declare -F listRegressionRemoteControlContractServiceInstallChildSelectors >/dev/null
    declare -F listRegressionRemoteControlContractChildSelectors >/dev/null

    remoteControlAssertSelectorList() {
        local helperFn=$1
        local helperName=$2
        shift 2
        local actualFile="${helperDir}/${helperName}.actual.txt"
        local expectedFile="${helperDir}/${helperName}.expected.txt"
        local sortedFile="${helperDir}/${helperName}.sorted.txt"
        local uniqueFile="${helperDir}/${helperName}.unique.txt"

        "${helperFn}" >"${actualFile}"
        printf '%s\n' "$@" >"${expectedFile}"

        cmp -s "${expectedFile}" "${actualFile}"
        sort "${actualFile}" >"${sortedFile}"
        sort -u "${actualFile}" >"${uniqueFile}"
        cmp -s "${sortedFile}" "${uniqueFile}"
    }

    remoteControlAssertSelectorList listRegressionRemoteControlChildSelectors default \
        remote-control-smoke \
        remote-control-contract \
        remote-control-deep
    remoteControlAssertSelectorList listRegressionRemoteControlSmokeRefreshApplyChildSelectors smoke-refresh-apply \
        remote-control-smoke-refresh-apply-basic \
        remote-control-smoke-refresh-apply-prepare \
        remote-control-smoke-refresh-apply-failure
    remoteControlAssertSelectorList listRegressionRemoteControlSmokeRefreshChildSelectors smoke-refresh \
        remote-control-smoke-refresh-apply \
        remote-control-smoke-refresh-restore \
        remote-control-smoke-refresh-reconcile
    remoteControlAssertSelectorList listRegressionRemoteControlSmokeChildSelectors smoke \
        remote-control-smoke-core \
        remote-control-smoke-refresh
    remoteControlAssertSelectorList listRegressionRemoteControlSmokeCoreChildSelectors smoke-core \
        remote-control-concurrency \
        remote-control-aggregation-failure \
        remote-control-inline-aggregation-helpers \
        remote-control-health \
        remote-control-inline-request-helpers \
        remote-control-inline-wireguard-peer-helpers \
        remote-control-inline-token-consumers \
        remote-control-inline-sync-runner \
        remote-control-handle-inline-helpers
    remoteControlAssertSelectorList listRegressionRemoteControlContractServiceInstallChildSelectors contract-service-install \
        remote-control-contract-service-install-success \
        remote-control-contract-service-install-systemctl-fail \
        remote-control-contract-service-install-health-fail \
        remote-control-contract-service-install-health-rollback \
        remote-control-contract-service-install-token-transaction
    remoteControlAssertSelectorList listRegressionRemoteControlContractChildSelectors contract \
        remote-control-contract-service-install \
        remote-control-contract-server-response
)

runRemoteControlNestedSelectorHelpersAreSuiteOwnedContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/remote_control.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_remote_control.sh"
    local functionName

    for functionName in \
        listRegressionRemoteControlSmokeCoreChildSelectors \
        listRegressionRemoteControlSmokeRefreshApplyChildSelectors \
        listRegressionRemoteControlSmokeRefreshChildSelectors \
        listRegressionRemoteControlSmokeChildSelectors \
        listRegressionRemoteControlContractServiceInstallChildSelectors \
        listRegressionRemoteControlContractChildSelectors \
        runRegressionRemoteControlSmokeCore
    do
        grep -Eq "^${functionName}\(\)[[:space:]]*[({]" "${suiteFile}" || return 1
        ! grep -Eq "^${functionName}\(\)[[:space:]]*[({]" "${scriptFile}" || return 1
    done
}

runRemoteControlLeavesUseCompatHelperContract() (
    local callLog="${TMP_DIR}/remote-control-compat-helper.log"

    : >"${callLog}"

    runRegressionRemoteControlLegacyLeafWithCompat() {
        printf '%s\n' "$1" >>"${callLog}"
    }

    for selector in \
        remote-control-contract-server-response \
        remote-control-deep; do
        PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain "${selector}"
    done

    cat <<'EOF' >"${TMP_DIR}/remote-control-compat-helper.expected.log"
runRegressionRemoteControlContractServerResponse
runRegressionRemoteControlDeep
EOF

    cmp -s "${TMP_DIR}/remote-control-compat-helper.expected.log" "${callLog}"
)

runRemoteControlNoCompatWrapperFunctionsContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/remote_control.sh"
    local status=0

    while read -r wrapperName; do
        ! grep -q "^${wrapperName}() { runRegressionRemoteControlLegacyLeafWithCompat " "${suiteFile}" || status=1
    done <<'EOF'
runRemoteControlContractServerResponseCompatRegression
runRemoteControlDeepCompatRegression
EOF

    return "${status}"
}

runRemoteControlSmokeCoreNoCompatHelperContract() (
    local callLog="${TMP_DIR}/remote-control-smoke-core-no-compat.log"

    : >"${callLog}"

    runRegressionRemoteControlLegacyLeafWithCompat() {
        printf '%s\n' "$1" >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain remote-control-smoke-core

    [[ ! -s "${callLog}" ]]
)

runRemoteControlSmokeRefreshNoCompatHelperContract() (
    local callLog="${TMP_DIR}/remote-control-smoke-refresh-no-compat.log"

    : >"${callLog}"

    runRegressionRemoteControlLegacyLeafWithCompat() {
        printf '%s\n' "$1" >>"${callLog}"
    }

    local selector
    for selector in \
        remote-control-smoke-refresh-apply-basic \
        remote-control-smoke-refresh-apply-prepare \
        remote-control-smoke-refresh-apply-failure \
        remote-control-smoke-refresh-restore \
        remote-control-smoke-refresh-reconcile
    do
        PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain "${selector}"
    done

    [[ ! -s "${callLog}" ]]
)

runRemoteControlContractServiceInstallNoCompatHelperContract() (
    local callLog="${TMP_DIR}/remote-control-contract-service-install-no-compat.log"

    : >"${callLog}"

    runRegressionRemoteControlLegacyLeafWithCompat() {
        printf '%s\n' "$1" >>"${callLog}"
    }

    local selector
    for selector in \
        remote-control-contract-service-install-success \
        remote-control-contract-service-install-systemctl-fail \
        remote-control-contract-service-install-health-fail \
        remote-control-contract-service-install-health-rollback \
        remote-control-contract-service-install-token-transaction
    do
        PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain "${selector}"
    done

    [[ ! -s "${callLog}" ]]
)

runRemoteControlLegacyTmpDirIsolationGuardRegisteredContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/remote_control.sh"

    grep -q '^runRegressionRemoteControlLegacyTmpDirIsolationRegression() ($' "${suiteFile}" || return 1
    grep -q '^    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain remote-control-contract-server-response$' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf regression-remote-control-legacy-tmpdir-isolation runRegressionRemoteControlLegacyTmpDirIsolationRegression$' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionAggregateRunnerParallel remote-control .*regression-remote-control-legacy-tmpdir-isolation' "${suiteFile}" || return 1
}

runRemoteControlSmokeCoreChildStepsContract() {
    local callLog="${TMP_DIR}/remote-control-smoke-core-sequential-helper.log"

    runRegisteredRegressionMain() {
        printf 'dispatch:%s\n' "$1" >>"${callLog}"
    }

    runSequentialSelectorListUsesFrameworkHelperAssertions \
        "${callLog}" \
        'dispatch:remote-control-concurrency' \
        runFrameworkSequentialRegressionSelectorList \
        listRegressionRemoteControlSmokeCoreChildSelectors
    grep -qx 'dispatch:remote-control-aggregation-failure' "${callLog}"
    grep -qx 'dispatch:remote-control-inline-aggregation-helpers' "${callLog}"
    grep -qx 'dispatch:remote-control-health' "${callLog}"
    grep -qx 'dispatch:remote-control-inline-request-helpers' "${callLog}"
    grep -qx 'dispatch:remote-control-inline-wireguard-peer-helpers' "${callLog}"
    grep -qx 'dispatch:remote-control-inline-token-consumers' "${callLog}"
    grep -qx 'dispatch:remote-control-inline-sync-runner' "${callLog}"
    grep -qx 'dispatch:remote-control-handle-inline-helpers' "${callLog}"
}

runRemoteControlAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/remote_control.sh"
    local expectedChildren

    ! grep -q '^registerRegressionFunctionLeaf remote-control ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateParallel remote-control \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallelWithArgs \\' "${suiteFile}"
    expectedChildren=$(listRegressionRemoteControlChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        remote-control \
        parallel \
        runFrameworkParallelRegressionSelectorList \
        "${expectedChildren}"
    runAggregateRunnerRunnerArgsPatternAssertions \
        remote-control \
        '/remote-control-default-[0-9]+$' \
        '^listRegressionRemoteControlChildSelectors$'
}

runRemoteControlNestedAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/remote_control.sh"

    ! grep -q '^registerRegressionAggregateParallel remote-control-smoke-refresh-apply \\' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionAggregateParallel remote-control-smoke-refresh \\' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionAggregateParallel remote-control-smoke \\' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionAggregateParallel remote-control-contract-service-install \\' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionAggregateParallel remote-control-contract \\' "${suiteFile}" || return 1

    runAggregateRunnerRegistrationAssertions \
        remote-control-smoke-refresh-apply \
        parallel \
        runFrameworkParallelRegressionSelectorList \
        "$(listRegressionRemoteControlSmokeRefreshApplyChildSelectors)"
    runAggregateRunnerRunnerArgsPatternAssertions \
        remote-control-smoke-refresh-apply \
        '/remote-control-smoke-refresh-apply$' \
        '^listRegressionRemoteControlSmokeRefreshApplyChildSelectors$'
    runAggregateRunnerRegistrationAssertions \
        remote-control-smoke-refresh \
        parallel \
        runFrameworkParallelRegressionSelectorList \
        "$(listRegressionRemoteControlSmokeRefreshChildSelectors)"
    runAggregateRunnerRunnerArgsPatternAssertions \
        remote-control-smoke-refresh \
        '/remote-control-smoke-refresh$' \
        '^listRegressionRemoteControlSmokeRefreshChildSelectors$'
    runAggregateRunnerRegistrationAssertions \
        remote-control-smoke \
        parallel \
        runFrameworkParallelRegressionSelectorList \
        "$(listRegressionRemoteControlSmokeChildSelectors)"
    runAggregateRunnerRunnerArgsPatternAssertions \
        remote-control-smoke \
        '/remote-control-smoke$' \
        '^listRegressionRemoteControlSmokeChildSelectors$'
    runAggregateRunnerRegistrationAssertions \
        remote-control-contract-service-install \
        parallel \
        runFrameworkParallelRegressionSelectorList \
        "$(listRegressionRemoteControlContractServiceInstallChildSelectors)"
    runAggregateRunnerRunnerArgsPatternAssertions \
        remote-control-contract-service-install \
        '/remote-control-contract-service-install$' \
        '^listRegressionRemoteControlContractServiceInstallChildSelectors$'
    runAggregateRunnerRegistrationAssertions \
        remote-control-contract \
        parallel \
        runFrameworkParallelRegressionSelectorList \
        "$(listRegressionRemoteControlContractChildSelectors)"
    runAggregateRunnerRunnerArgsPatternAssertions \
        remote-control-contract \
        '/remote-control-contract$' \
        '^listRegressionRemoteControlContractChildSelectors$'
}

runRemoteControlAggregateRunnerUsesFrameworkSelectorHelperContract() (
    local callLog="${TMP_DIR}/remote-control-framework-helper-dispatch.log"

    : >"${callLog}"

    listRegressionRemoteControlChildSelectors() {
        printf '%s\n' \
            remote-control-smoke \
            remote-control-deep
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:%s\n' "$*" >>"${callLog}"
    }

    runParallelRegressionSelectors() {
        printf 'legacy-helper:%s\n' "$*" >>"${callLog}"
        return 97
    }

    runRemoteControlAggregateRunnerUsesFrameworkSelectorHelperRunner() {
        PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain remote-control
    }

    runRemoteControlAggregateRunnerUsesFrameworkSelectorHelperRunner

    grep -Eq '^framework:.*/remote-control-default-[0-9][0-9]* remote-control-smoke remote-control-smoke remote-control-deep remote-control-deep$' "${callLog}" || return 1
    ! grep -q '^legacy-helper:' "${callLog}" || return 1
)

runRemoteControlTopLevelNoSuiteSelectorRunnerContract() (
    local callLog="${TMP_DIR}/remote-control-top-level-no-suite-selector-runner.log"

    : >"${callLog}"

    runFrameworkParallelRegressionSelectorList() {
        printf 'runner=%s args=%s\n' \
            "${PADM_REGRESSION_SELECTOR_RUNNER["remote-control"]:-}" \
            "$*" >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain remote-control

    grep -Eq '^runner=runFrameworkParallelRegressionSelectorList args=.*/remote-control-default-[0-9][0-9]* listRegressionRemoteControlChildSelectors$' "${callLog}"
)

runFastSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/fast.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_fast.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_FAST_SUITE_DIR}/../subscription_groups_fast.sh"' "${suiteFile}"
    grep -q '^listRegressionFastChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionFastOnlyChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionFastOnlyOutputChildSelectors() {$' "${suiteFile}"
    grep -q '^runRegressionFastOnlyCoreSuiteRoot() {$' "${suiteFile}"
    ! grep -q '^runRegressionFastUiSmokeLightSuiteRoot() {$' "${suiteFile}"
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/fast-parallel-' "${suiteFile}"
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/fast-only-parallel-' "${suiteFile}"
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/fast-only-output-parallel-' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf fast ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf fast ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallelWithArgs \\' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf fast-only ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf fast-only ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallelWithArgs \\' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf fast-only-output ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf fast-only-output ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallelWithArgs \\' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf fast-only-safety runRegressionFastOnlySafety$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf fast-only-output-auto-install runRegressionFastOnlyOutputAutoInstall$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf fast-only-output-rest runRegressionFastOnlyOutputRest$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf fast-only-core runRegressionFastOnlyCoreSuiteRoot$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf regression-fast-parallel-composition runRegressionFastParallelCompositionRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf regression-fast-only-parallel-composition runRegressionFastOnlyParallelCompositionRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf regression-fast-only-output-parallel-composition runRegressionFastOnlyOutputParallelCompositionRegression$' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf fast-reality ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf fast-reality ' "${suiteFile}"
    ! grep -q '^runRegressionFastRealitySuiteRoot() {$' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequentialWithArgs \\' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf platform-hot ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf platform-hot ' "${suiteFile}"
    ! grep -q 'declare -f runRegressionFast' "${suiteFile}"
    ! grep -q '^eval ' "${suiteFile}"
    grep -q 'runRegressionStep ui-smoke-light runRegressionUiSmokeSuiteRoot' "${suiteFile}"
    grep -q 'if \[\[ "\${PADM_REGRESSION_SOURCE_ONLY:-}" == "1" \]\]; then' "${scriptFile}"
}

runFastNoEmptyLocalWrapperFunctionsContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/fast.sh"
    ! grep -q '^runRegressionFastUiSmokeLightSuiteRoot() {$' "${suiteFile}" || return 1
}

runPlatformSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/platform.sh"
    local status=0

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_PLATFORM_SUITE_DIR}/../subscription_groups_fast.sh"' "${suiteFile}"
    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_PLATFORM_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    grep -q '^runRegressionPlatformFastLeafWithCompat() ($' "${suiteFile}"
    grep -q '^listRegressionPlatformHotChildSelectors() {$' "${suiteFile}"
    grep -q '^runRegressionPlatformSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionPlatformIoSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionPlatformUpdateSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionPlatformRefreshSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionPlatformRestSuiteRoot() {$' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf platform-hot ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf platform-io ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf platform-hot ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallelWithArgs \\' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf platform-io runRegressionPlatformIoSuiteRoot$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf platform-update runRegressionPlatformUpdateSuiteRoot$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf platform-refresh runRegressionPlatformRefreshSuiteRoot$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf platform-rest runRegressionPlatformRestSuiteRoot$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf regression-platform-hot-parallel-composition runRegressionPlatformHotParallelCompositionRegression$' "${suiteFile}"
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/platform-hot-parallel-' "${suiteFile}"
    ! grep -q 'declare -f runRegressionPlatform' "${suiteFile}"
    ! grep -q 'declare -f runRegressionPlatformIo' "${suiteFile}"
    ! grep -q '^eval ' "${suiteFile}"

    while read -r selector helper regression; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${helper} ${regression}\$" "${suiteFile}" || status=1
    done <<'EOF'
install-tools-certificate-dependency runRegressionPlatformLegacyLeafWithCompat runInstallToolsCertificateDependencyRegression
install-tools-acme-result-failure runRegressionPlatformLegacyLeafWithCompat runInstallToolsAcmeResultFailureRegression
install-tools-acme-commit-failure runRegressionPlatformLegacyLeafWithCompat runInstallToolsAcmeCommitFailureRegression
install-tools-configured-log runRegressionPlatformLegacyLeafWithCompat runInstallToolsUsesConfiguredInstallLogRegression
install-tools-update-failure runRegressionPlatformLegacyLeafWithCompat runInstallToolsUpdateFailureRegression
install-tools-release-info-failure runRegressionPlatformLegacyLeafWithCompat runInstallToolsReleaseInfoFailureRegression
install-tools-nginx-reinstall-failure runRegressionPlatformLegacyLeafWithCompat runInstallToolsNginxReinstallFailureRegression
apt-key-install-failure runRegressionPlatformLegacyLeafWithCompat runAptKeyInstallFailureRegression
nginx-apt-refresh-rollback runRegressionPlatformLegacyLeafWithCompat runNginxAptRepoRefreshRollbackRegression
nginx-alpine-default-conf-rollback runRegressionPlatformLegacyLeafWithCompat runNginxAlpineDefaultConfRollbackRegression
nginx-yum-mainline-enable-failure runRegressionPlatformLegacyLeafWithCompat runNginxYumMainlineEnableFailureRegression
base-package-batch runRegressionPlatformLegacyLeafWithCompat runBasePackageBatchRegression
package-rollback-failure runRegressionPlatformLegacyLeafWithCompat runPackageRollbackFailureRegression
package-command-stdin runRegressionPlatformLegacyLeafWithCompat runPackageCommandStdinRegression
reality-scanner-unsafe-dir runRegressionPlatformLegacyLeafWithCompat runRealityScannerRejectsUnsafeDirRegression
reality-scanner-binary runRegressionPlatformLegacyLeafWithCompat runRealityScannerBinaryRegression
reality-scanner-download-failure runRegressionPlatformLegacyLeafWithCompat runRealityScannerDownloadFailureKeepsExistingDirRegression
EOF

    return "${status}"
}

runPlatformPublicSelectorRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/platform.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^registerRegressionAggregateRunnerParallelWithArgs \\' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf platform-io runRegressionPlatformIoSuiteRoot$' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf platform runRegressionPlatformSuiteRoot$' "${suiteFile}"
    ! grep -Eq '^runRegressionPlatform\(\)[[:space:]]*[({]' "${legacyFile}"
    ! grep -Eq '^runRegressionPlatformIo\(\)[[:space:]]*[({]' "${legacyFile}"
    ! grep -Eq '^[[:space:]]*platform\)$' "${legacyFile}"
    ! grep -Eq '^[[:space:]]*platform-hot\)$' "${legacyFile}"
    ! grep -Eq '^[[:space:]]*platform-io\)$' "${legacyFile}"
    ! grep -Fq '[platform-hot|' "${legacyFile}"
    ! grep -Fq '|platform-io|' "${legacyFile}"
}

runFastRealitySelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/fast-reality-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/fast-reality-default-selectors.sorted.txt"
    local expectedDefaultSelectorsFile="${TMP_DIR}/fast-reality-default-selectors.expected.txt"

    declare -F listRegressionFastRealityChildSelectors >/dev/null

    listRegressionFastRealityChildSelectors >"${defaultSelectorsFile}"

    cat <<'EOF' >"${expectedDefaultSelectorsFile}"
fast
reality-candidates-fast
EOF

    cmp -s "${expectedDefaultSelectorsFile}" "${defaultSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/fast-reality-default-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/fast-reality-default-selectors.unique.txt"
)

runPlatformHotSelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/platform-hot-default-selectors.txt"
    local expectedDefaultSelectorsFile="${TMP_DIR}/platform-hot-default-selectors.expected.txt"
    local defaultSortedFile="${TMP_DIR}/platform-hot-default-selectors.sorted.txt"

    declare -F listRegressionPlatformHotChildSelectors >/dev/null

    listRegressionPlatformHotChildSelectors >"${defaultSelectorsFile}"

    cat <<'EOF' >"${expectedDefaultSelectorsFile}"
platform-update
platform-refresh
platform-rest
EOF

    cmp -s "${expectedDefaultSelectorsFile}" "${defaultSelectorsFile}"
    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/platform-hot-default-selectors.unique.txt"
    cmp -s "${defaultSortedFile}" "${TMP_DIR}/platform-hot-default-selectors.unique.txt"
)

runPlatformHotAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/platform.sh"
    local expectedChildren

    ! grep -q '^registerRegressionScriptLeaf platform-hot ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf platform-hot ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallelWithArgs \\' "${suiteFile}"
    expectedChildren=$(listRegressionPlatformHotChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        platform-hot \
        parallel \
        runFrameworkParallelRegressionSelectorList \
        "${expectedChildren}"
    runAggregateRunnerRunnerArgsPatternAssertions \
        platform-hot \
        '/platform-hot-parallel-[0-9]+$' \
        '^listRegressionPlatformHotChildSelectors$'
}

runPlatformHotLeavesUseFastCompatHelperContract() (
    local callLog="${TMP_DIR}/platform-hot-fast-compat-helper.log"

    : >"${callLog}"

    runRegressionStep() { :; }
    runRegressionPlatformFastLeafWithCompat() {
        printf '%s\n' "$1" >>"${callLog}"
    }

    runRegressionPlatformUpdateSuiteRoot
    runRegressionPlatformRefreshSuiteRoot
    runRegressionPlatformRestSuiteRoot
    runRegressionPlatformSuiteRoot

    cat <<'EOF' >"${TMP_DIR}/platform-hot-fast-compat-helper.expected.log"
runRegressionPlatformUpdate
runRegressionPlatformRefresh
runRegressionPlatformRest
runRegressionPlatform
EOF

    cmp -s "${TMP_DIR}/platform-hot-fast-compat-helper.expected.log" "${callLog}"
)

runPlatformIoLeavesUseLegacyCompatHelperContract() (
    local callLog="${TMP_DIR}/platform-io-legacy-compat-helper.log"

    : >"${callLog}"

    runRegressionStep() {
        local _name=$1
        shift
        "$@"
    }

    runRegressionPlatformLegacyLeafWithCompat() {
        printf '%s\n' "$1" >>"${callLog}"
    }

    runRegressionPlatformIoSuiteRoot

    cat <<'EOF' >"${TMP_DIR}/platform-io-legacy-compat-helper.expected.log"
runInstallToolsCertificateDependencyRegression
runInstallToolsAcmeResultFailureRegression
runInstallToolsAcmeCommitFailureRegression
runInstallToolsUsesConfiguredInstallLogRegression
runInstallToolsUpdateFailureRegression
runInstallToolsReleaseInfoFailureRegression
runInstallToolsNginxReinstallFailureRegression
runAptKeyInstallFailureRegression
runNginxAptRepoRefreshRollbackRegression
runNginxAlpineDefaultConfRollbackRegression
runNginxYumMainlineEnableFailureRegression
runBasePackageBatchRegression
runPackageRollbackFailureRegression
runPackageCommandStdinRegression
runRealityScannerRejectsUnsafeDirRegression
runRealityScannerBinaryRegression
runRealityScannerDownloadFailureKeepsExistingDirRegression
EOF

    cmp -s "${TMP_DIR}/platform-io-legacy-compat-helper.expected.log" "${callLog}"
)

runPlatformIoNoCompatWrapperFunctionsContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/platform.sh"
    local status=0

    while read -r wrapperName; do
        ! grep -q "^${wrapperName}() { runRegressionPlatformLegacyLeafWithCompat " "${suiteFile}" || status=1
    done <<'EOF'
runInstallToolsCertificateDependencyCompatRegression
runInstallToolsAcmeResultFailureCompatRegression
runInstallToolsAcmeCommitFailureCompatRegression
runInstallToolsConfiguredLogCompatRegression
runInstallToolsUpdateFailureCompatRegression
runInstallToolsReleaseInfoFailureCompatRegression
runInstallToolsNginxReinstallFailureCompatRegression
runAptKeyInstallFailureCompatRegression
runNginxAptRefreshRollbackCompatRegression
runNginxAlpineDefaultConfRollbackCompatRegression
runNginxYumMainlineEnableFailureCompatRegression
runBasePackageBatchCompatRegression
runPackageRollbackFailureCompatRegression
runPackageCommandStdinCompatRegression
runRealityScannerUnsafeDirCompatRegression
runRealityScannerBinaryCompatRegression
runRealityScannerDownloadFailureCompatRegression
EOF

    return "${status}"
}

runPlatformFastHelperIsolationGuardRegisteredContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/platform.sh"
    local fastFile="${PROJECT_ROOT}/shell/regression/subscription_groups_fast.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^runRegressionPlatformFastHelperIsolationRegression() ($' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf regression-platform-fast-helper-isolation runRegressionPlatformFastHelperIsolationRegression$' "${suiteFile}" || return 1
    grep -q '^runUpdatePadmVersionPromptRegression() {$' "${fastFile}" || return 1
    grep -q '^runUpdatePadmVersionPromptRegression() {$' "${legacyFile}" || return 1
    ! grep -q '^registerRegressionAggregateRunnerParallel platform-hot .*regression-platform-fast-helper-isolation' "${suiteFile}" || return 1
}

runPlatformRefreshChildStepsContract() {
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_fast.sh"
    runRegressionStepSequenceAssertions "${scriptFile}" runRegressionPlatformRefresh \
        install-refresh-fallback-main \
        install-refresh-keep-ref-on-lookup-fail \
        install-refresh-rejects-unsafe-script-dir \
        install-refresh-rejects-unsafe-archive \
        install-refresh-rejects-unsupported-archive-entry \
        install-refresh-restore \
        install-refresh-single-archive-guard
}

runPlatformUpdateChildStepsContract() {
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_fast.sh"
    runRegressionStepSequenceAssertions "${scriptFile}" runRegressionPlatformUpdate \
        update-padm-version-prompt
}

runPlatformRestChildStepsContract() {
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_fast.sh"
    runRegressionStepSequenceAssertions "${scriptFile}" runRegressionPlatformRest \
        release-workflow-version \
        version-helpers \
        regression-bootstrap-local-env-fallback \
        cleanup-trap \
        cleanup-trap-relative-path \
        clean-directory-safety \
        managed-file-backup-manifest \
        managed-file-backup-manifest-validator \
        remove-managed-files-ignore-failure \
        remove-managed-path-ignore-failure \
        check-log-backup-restore \
        remote-control-systemctl-stub-default-stop-disable \
        regression-fast-parallel-composition \
        regression-fast-only-parallel-composition \
        regression-fast-only-output-parallel-composition \
        regression-platform-hot-parallel-composition \
        remote-control-function-stub-default-stop-disable \
        tuic-protocol-single-default-branch \
        tls-dns-api-single-default-branch \
        tls-ca-single-default-branch \
        reality-target-single-default-branch \
        auto-install-type-single-custom-branch \
        subscription-menu-wrapper-count \
        subscription-menu-dead-entry-count \
        unused-helper-function-count \
        legacy-users-module-removed \
        install-entry-refresh \
        install-module-paths \
        install-early-capability-list \
        install-menu-recommended-ids \
        validate-install-loads-runtime \
        validate-install-temp-root-parent-shell \
        install-entry-symlink \
        alias-install-metadata \
        alias-install-same-target \
        alias-install-rejects-unsafe-target \
        alias-install-rejects-unsafe-home \
        xray-stats-jq \
        local-traffic-accounts \
        dpkg-installed-pattern \
        dpkg-query-installed-pattern \
        rhel-like-detection \
        fedora-detection \
        port-hopping-without-persistent \
        port-hopping-menu-command-lookup
}

runPlatformIoChildStepsContract() {
    local callLog="${TMP_DIR}/platform-io-sequential-helper.log"

    runRegisteredRegressionMain() {
        printf 'dispatch:%s\n' "$1" >>"${callLog}"
    }

    runSequentialSelectorListUsesFrameworkHelperAssertions \
        "${callLog}" \
        'dispatch:install-tools-certificate-dependency' \
        runFrameworkSequentialRegressionSelectorList \
        listRegressionPlatformIoChildSelectors
    grep -qx 'dispatch:install-tools-acme-result-failure' "${callLog}"
    grep -qx 'dispatch:install-tools-acme-commit-failure' "${callLog}"
    grep -qx 'dispatch:install-tools-configured-log' "${callLog}"
    grep -qx 'dispatch:install-tools-update-failure' "${callLog}"
    grep -qx 'dispatch:install-tools-release-info-failure' "${callLog}"
    grep -qx 'dispatch:install-tools-nginx-reinstall-failure' "${callLog}"
    grep -qx 'dispatch:apt-key-install-failure' "${callLog}"
    grep -qx 'dispatch:nginx-apt-refresh-rollback' "${callLog}"
    grep -qx 'dispatch:nginx-alpine-default-conf-rollback' "${callLog}"
    grep -qx 'dispatch:nginx-yum-mainline-enable-failure' "${callLog}"
    grep -qx 'dispatch:base-package-batch' "${callLog}"
    grep -qx 'dispatch:package-rollback-failure' "${callLog}"
    grep -qx 'dispatch:package-command-stdin' "${callLog}"
    grep -qx 'dispatch:reality-scanner-unsafe-dir' "${callLog}"
    grep -qx 'dispatch:reality-scanner-binary' "${callLog}"
    grep -qx 'dispatch:reality-scanner-download-failure' "${callLog}"
}

runFastOnlyOutputAutoInstallChildStepsContract() {
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_fast.sh"
    runRegressionStepSequenceAssertions "${scriptFile}" runRegressionFastOnlyOutputAutoInstall \
        auto-install-generated-identity \
        auto-install-empty-defaults \
        auto-install-missing-required-no-stdin \
        auto-install-tls-domain-missing-returns \
        auto-install-two-digit-single-protocol
}

runFastOnlySafetyChildStepsContract() {
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_fast.sh"
    runRegressionStepSequenceAssertions "${scriptFile}" runRegressionFastOnlySafety \
        commit-generated-file-directory-target \
        restore-managed-file-directory-target \
        github-release-direct-fallback \
        download-arg-missing-value \
        github-release-arg-missing-value \
        remove-install-path-retry \
        remove-install-path-file-mode \
        uninstall-padm-root-scope \
        remove-install-path-safety \
        remove-nginx-default-conf-safety \
        clean-agent-nginx-conf-safety \
        uninstall-subscribe-nginx-path-safety \
        check-port-open-nginx-path-safety \
        write-subscribe-nginx-path-safety \
        write-wireguard-control-nginx-path-safety \
        write-alone-nginx-path-safety \
        clean-last-installation-nginx-safety \
        install-nginx-alpine-default-path-safety \
        install-nginx-static-unsafe-path \
        install-nginx-static-unzip-failure \
        clean-last-installation-static-safety \
        subscription-sync-path-safety \
        subscription-sync-config-directory-target \
        subscription-sync-create-local-apply-backups-rollback \
        subscription-sync-config-unmanaged-target \
        subscription-sync-missing-restore-scope
}

runFastOnlyOutputRestChildStepsContract() {
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_fast.sh"
    runRegressionStepSequenceAssertions "${scriptFile}" runRegressionFastOnlyOutputRest \
        client-name-suffix-preserves-random-prefix \
        subscribe-local-cleanup \
        subscription-output-random-user \
        show-accounts-optional-step \
        show-accounts-xray-singbox-assist \
        show-accounts-singbox-reality-grpc \
        trojan-grpc-account-template-filename \
        trojan-fallback-subscribe-entry \
        trojan-fallback-template-frontend \
        parse-install-args-missing-value \
        locale-unset-printN \
        httpupgrade-incremental-starts-nginx \
        httpupgrade-rejects-unsafe-nginx-path \
        allow-port-optional-protocol \
        core-client-optional-args
}

runFastOnlyCoreChildStepsContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/fast.sh"
    runRegressionStepSequenceAssertions "${suiteFile}" runRegressionFastOnlyCoreSuiteRoot \
        singbox-mainpid-template \
        check-gfw-status-service-wait \
        service-wait-state \
        core-running-service-state \
        warp-config-generation-failure \
        fail2ban-profile \
        fail2ban-sshd-systemd-backend \
        fail2ban-menu \
        xray-strict-validation \
        xray-compat-audit \
        xray-prerelease-dry-run \
        singbox-compat-audit \
        singbox-prerelease-dry-run \
        services-proc-race \
        singbox-ignore-client-proc \
        nginx-blog-auto-install \
        ui-smoke-light
}

runRealitySuiteChildStepsContract() {
    local callLog="${TMP_DIR}/reality-sequential-helper.log"

    runRegisteredRegressionMain() {
        printf 'dispatch:%s\n' "$1" >>"${callLog}"
    }

    runSequentialSelectorListUsesFrameworkHelperAssertions \
        "${callLog}" \
        'dispatch:reality-candidates-fast' \
        runFrameworkSequentialRegressionSelectorList \
        listRegressionRealitySuiteCandidatesChildSelectors
    grep -qx 'dispatch:reality-asn-scan-plan' "${callLog}"
    grep -qx 'dispatch:reality-candidates-full' "${callLog}"

    runSequentialSelectorListUsesFrameworkHelperAssertions \
        "${callLog}" \
        'dispatch:reality-stream-enable' \
        runFrameworkSequentialRegressionSelectorList \
        listRegressionRealitySuiteStreamChildSelectors
    grep -qx 'dispatch:reality-stream-disable' "${callLog}"
}

runRuntimeSuiteChildStepsContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/runtime.sh"
    local runtimeBody

    runtimeBody=$(sed -n '/^runRegressionRuntimeSuiteRoot() {$/,/^}$/p' "${suiteFile}")
    [[ -n "${runtimeBody}" ]] || return 1

    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/runtime-parallel-' <<<"${runtimeBody}" || return 1
    grep -q 'listRegressionRuntimeChildSelectors' <<<"${runtimeBody}" || return 1
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/runtime-parallel-light-' <<<"${runtimeBody}" || return 1
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/runtime-parallel-heavy-' <<<"${runtimeBody}" || return 1
}

runTlsSuiteChildStepsContract() {
    local callLog="${TMP_DIR}/tls-sequential-helper.log"

    runRegisteredRegressionMain() {
        printf 'dispatch:%s\n' "$1" >>"${callLog}"
    }

    runSequentialSelectorListUsesFrameworkHelperAssertions \
        "${callLog}" \
        'dispatch:tls-failure-return' \
        runFrameworkSequentialRegressionSelectorList \
        listRegressionTlsChildSelectors
    grep -qx 'dispatch:tls-reinstall-rollback' "${callLog}"
    grep -qx 'dispatch:tls-renew-failure-propagation' "${callLog}"
}

runTransactionSubscriptionChildStepsContract() {
    local callLog="${TMP_DIR}/transaction-subscription-sequential-helper.log"

    runRegisteredRegressionMain() {
        printf 'dispatch:%s\n' "$1" >>"${callLog}"
    }

    runSequentialSelectorListUsesFrameworkHelperAssertions \
        "${callLog}" \
        'dispatch:cdn-address-write-transaction' \
        runFrameworkSequentialRegressionSelectorList \
        listRegressionTransactionSubscriptionChildSelectors
    grep -qx 'dispatch:subscribe-server-name' "${callLog}"
    grep -qx 'dispatch:subscribe-nginx-config-write' "${callLog}"
    grep -qx 'dispatch:subscribe-nginx-service-failure' "${callLog}"
    grep -qx 'dispatch:subscribe-salt-write-transaction' "${callLog}"
    grep -qx 'dispatch:subscribe-user-output-transaction' "${callLog}"
    grep -qx 'dispatch:remove-user-subscription-menu-failure' "${callLog}"
    grep -qx 'dispatch:user-subscription-menu-mutation-failure' "${callLog}"
    grep -qx 'dispatch:remote-subscribe-fetch' "${callLog}"
}

runTransactionSuiteChildStepsContract() {
    local callLog="${TMP_DIR}/transaction-sequential-helper.log"

    runRegisteredRegressionMain() {
        printf 'dispatch:%s\n' "$1" >>"${callLog}"
    }

    runSequentialSelectorListUsesFrameworkHelperAssertions \
        "${callLog}" \
        'dispatch:transaction-core' \
        runFrameworkSequentialRegressionSelectorList \
        listRegressionTransactionChildSelectors
    grep -qx 'dispatch:transaction-subscription' "${callLog}"
    grep -qx 'dispatch:transaction-system' "${callLog}"
}

runFastRealityAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/fast.sh"
    local expectedChildren

    ! grep -q '^registerRegressionScriptLeaf fast-reality ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf fast-reality ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateSequential fast-reality \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequentialWithArgs \\' "${suiteFile}"
    expectedChildren=$(listRegressionFastRealityChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        fast-reality \
        sequential \
        runFrameworkSequentialRegressionSelectorList \
        "${expectedChildren}"
    runAggregateRunnerRunnerArgsAssertions fast-reality 'listRegressionFastRealityChildSelectors'
}

runFastSelectorHelpersStayAlignedContract() (
    local fastSelectorsFile="${TMP_DIR}/fast-default-selectors.txt"
    local fastExpectedFile="${TMP_DIR}/fast-default-selectors.expected.txt"
    local fastOnlySelectorsFile="${TMP_DIR}/fast-only-default-selectors.txt"
    local fastOnlyExpectedFile="${TMP_DIR}/fast-only-default-selectors.expected.txt"
    local fastOnlyOutputSelectorsFile="${TMP_DIR}/fast-only-output-default-selectors.txt"
    local fastOnlyOutputExpectedFile="${TMP_DIR}/fast-only-output-default-selectors.expected.txt"

    declare -F listRegressionFastChildSelectors >/dev/null
    declare -F listRegressionFastOnlyChildSelectors >/dev/null
    declare -F listRegressionFastOnlyOutputChildSelectors >/dev/null

    listRegressionFastChildSelectors >"${fastSelectorsFile}"
    listRegressionFastOnlyChildSelectors >"${fastOnlySelectorsFile}"
    listRegressionFastOnlyOutputChildSelectors >"${fastOnlyOutputSelectorsFile}"

    cat <<'EOF' >"${fastExpectedFile}"
platform-hot
fast-only
EOF

    cat <<'EOF' >"${fastOnlyExpectedFile}"
fast-only-safety
fast-only-output
fast-only-core
EOF

    cat <<'EOF' >"${fastOnlyOutputExpectedFile}"
fast-only-output-auto-install
fast-only-output-rest
EOF

    cmp -s "${fastExpectedFile}" "${fastSelectorsFile}"
    cmp -s "${fastOnlyExpectedFile}" "${fastOnlySelectorsFile}"
    cmp -s "${fastOnlyOutputExpectedFile}" "${fastOnlyOutputSelectorsFile}"
)

runFastAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/fast.sh"
    local expectedChildren

    ! grep -q '^registerRegressionScriptLeaf fast ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf fast ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallelWithArgs \\' "${suiteFile}"
    expectedChildren=$(listRegressionFastChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        fast \
        parallel \
        runFrameworkParallelRegressionSelectorList \
        "${expectedChildren}"
    runAggregateRunnerRunnerArgsPatternAssertions \
        fast \
        '/fast-parallel-[0-9]+$' \
        '^listRegressionFastChildSelectors$'
}

runFastOnlyAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/fast.sh"
    local expectedChildren

    ! grep -q '^registerRegressionScriptLeaf fast-only ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf fast-only ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallelWithArgs \\' "${suiteFile}"
    expectedChildren=$(listRegressionFastOnlyChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        fast-only \
        parallel \
        runFrameworkParallelRegressionSelectorList \
        "${expectedChildren}"
    runAggregateRunnerRunnerArgsPatternAssertions \
        fast-only \
        '/fast-only-parallel-[0-9]+$' \
        '^listRegressionFastOnlyChildSelectors$'
}

runFastOnlyOutputAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/fast.sh"
    local expectedChildren

    ! grep -q '^registerRegressionScriptLeaf fast-only-output ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf fast-only-output ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallelWithArgs \\' "${suiteFile}"
    expectedChildren=$(listRegressionFastOnlyOutputChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        fast-only-output \
        parallel \
        runFrameworkParallelRegressionSelectorList \
        "${expectedChildren}"
    runAggregateRunnerRunnerArgsPatternAssertions \
        fast-only-output \
        '/fast-only-output-parallel-[0-9]+$' \
        '^listRegressionFastOnlyOutputChildSelectors$'
}

runFastRealityLegacyRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/fast.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^registerRegressionAggregateRunnerSequentialWithArgs \\' "${suiteFile}" || return 1
    runLegacyFunctionSelectorRetirementAssertions \
        "${legacyFile}" \
        runRegressionFastReality \
        fast-reality \
        '|fast-reality|'
}

runFastLegacyRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/fast.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    ! grep -q '^registerRegressionFunctionLeaf fast ' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallelWithArgs \\' "${suiteFile}" || return 1
    runLegacyFunctionSelectorRetirementAssertions \
        "${legacyFile}" \
        runRegressionFast \
        fast \
        'usage: %s [fast|'
}

runFastPublicCliRetirementContract() {
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_fast.sh"
    local usageLine

    grep -q 'if \[\[ "\${PADM_REGRESSION_SOURCE_ONLY:-}" == "1" \]\]; then' "${scriptFile}" || return 1
    grep -q "printf 'use shell/subscription_groups_regression.sh <selector>\\\\n' >&2" "${scriptFile}" || return 1
    grep -q '^exit 2$' "${scriptFile}" || return 1
    ! grep -q '^if \[\[ "\${PADM_REGRESSION_INTERNAL_CLI:-}" != "1" \]\]; then$' "${scriptFile}" || return 1
    ! grep -q '^regressionName=' "${scriptFile}" || return 1
    ! grep -Eq '^[[:space:]]*fast\)$' "${scriptFile}" || return 1
    ! grep -Eq '^[[:space:]]*platform\)$' "${scriptFile}" || return 1
    ! grep -Fq 'subscription-groups-regression-ok:' "${scriptFile}" || return 1

    usageLine=$(grep -F 'usage: %s [' "${scriptFile}" || true)
    [[ -z "${usageLine}" ]] || return 1
}

runFastPlatformSourceOnlyExecutionContract() (
    local platformSuite="${PROJECT_ROOT}/shell/regression/suites/platform.sh"
    local fastSuite="${PROJECT_ROOT}/shell/regression/suites/fast.sh"

    registerRegressionFunctionLeaf() { :; }
    registerRegressionAggregateRunnerSequential() { :; }
    registerRegressionAggregateRunnerParallel() { :; }
    registerRegressionAggregateRunnerSequentialWithArgs() { :; }
    registerRegressionAggregateRunnerParallelWithArgs() { :; }
    registerRegressionAggregateSequential() { :; }
    registerRegressionAggregateParallel() { :; }
    registerRegressionAlias() { :; }

    PADM_REGRESSION_SOURCE_ONLY=1 source "${platformSuite}"
    PADM_REGRESSION_SOURCE_ONLY=1 source "${fastSuite}"
    declare -F runRegressionPlatformSuiteRoot >/dev/null
    declare -F runRegressionPlatformIoSuiteRoot >/dev/null
    ! declare -F _platform_hot_suite_def >/dev/null
    ! declare -F _platform_io_suite_def >/dev/null
    ! declare -F _fast_root_suite_def >/dev/null
)

runFastRealityAggregateRunnerDispatchesChildrenInOrderContract() (
    local callLog="${TMP_DIR}/fast-reality-aggregate-dispatch.log"

    : >"${callLog}"

    PADM_REGRESSION_SELECTOR_RUNNER["fast"]=runFastRealityAggregateFastFixture
    PADM_REGRESSION_SELECTOR_RUNNER_ARGS["fast"]=

    runRegressionRealityLegacyLeafWithCompat() {
        "$1"
    }

    runFastRealityAggregateFastFixture() {
        printf 'fast\n' >>"${callLog}"
    }

    runRealityCandidateFastRegression() {
        printf 'reality-candidates-fast\n' >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain fast-reality

    runAggregateRunnerDispatchesChildrenInOrderAssertions \
        "${callLog}" \
        fast \
        reality-candidates-fast
)

runFastRealityUsesRealityCompatHelperContract() (
    local callLog="${TMP_DIR}/fast-reality-compat-helper.log"

    : >"${callLog}"

    runRegressionRealityLegacyLeafWithCompat() {
        printf 'compat:%s\n' "$1" >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain fast-reality

    cat <<'EOF' >"${TMP_DIR}/fast-reality-compat-helper.expected.log"
compat:runRealityCandidateFastRegression
EOF

    cmp -s "${TMP_DIR}/fast-reality-compat-helper.expected.log" "${callLog}"
)

runFastSuiteUsesSuiteLocalHelperContract() (
    local callLog="${TMP_DIR}/fast-suite-root-dispatch.log"

    : >"${callLog}"

    runMenuSmokeLightRegression() {
        printf 'legacy-ui-smoke-light\n' >>"${callLog}"
        return 97
    }

    runRegressionUiSmokeSuiteRoot() {
        printf 'suite-ui-smoke-light\n' >>"${callLog}"
    }

    runRegressionStep() {
        local label=$1
        local runner=$2

        if [[ "${label}" == "ui-smoke-light" ]]; then
            "${runner}"
            return $?
        fi

        return 0
    }

    runRegressionFastOnlyCoreSuiteRoot

    grep -qx 'suite-ui-smoke-light' "${callLog}"
    ! grep -q '^legacy-ui-smoke-light$' "${callLog}"
)

runRegisteredChildSelectorsAlignedAssertions() (
    local selectorListFn=$1
    local filePrefix=$2
    local expectedSelectorsFile="${filePrefix}.expected.txt"
    local actualSelectorsFile="${filePrefix}.actual.txt"
    local selector

    while IFS= read -r selector; do
        [[ -n "${selector}" ]] || continue
        if [[ -n "${PADM_REGRESSION_SELECTOR_KIND["${selector}"]:-}" ]]; then
            printf '%s\n' "${selector}"
        fi
    done < <("${selectorListFn}") >"${actualSelectorsFile}"

    cat >"${expectedSelectorsFile}"

    cmp -s "${expectedSelectorsFile}" "${actualSelectorsFile}"
)

runAllSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/all.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    ! grep -q 'subscription_groups_legacy\.sh' "${suiteFile}" || return 1
    grep -q 'source "\${REGRESSION_ALL_SUITE_DIR}/../framework/runtime.sh"' "${suiteFile}" || return 1
    ! grep -q '^REGRESSION_ENTRY_SCRIPT_PATH=' "${suiteFile}" || return 1
    grep -q '^listRegressionAllParallelChildSelectors() {$' "${suiteFile}" || return 1
    grep -q '^runRegressionAllSelector() {$' "${suiteFile}" || return 1
    grep -q '^runRegressionAllSelectorSuiteRoot() ($' "${suiteFile}" || return 1
    grep -Eq '^runRegressionAllSuiteRoot\(\) \($|^runRegressionAllSuiteRoot\(\) {$' "${suiteFile}" || return 1
    ! grep -Eq '^runRegressionAll\(\) \($|^runRegressionAll\(\) {$' "${suiteFile}" || return 1
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/all-parallel-' "${suiteFile}" || return 1
    ! grep -q '^runRegressionAllSelector() {$' "${legacyScriptFile}" || return 1
    ! grep -Eq '^runRegressionAll\(\) \($|^runRegressionAll\(\) {$' "${legacyScriptFile}" || return 1
    ! grep -q '^registerRegressionScriptLeaf all ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf all ' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerSequential all runRegressionAllSuiteRoot \\' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionAlias full all$' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionAlias ci all$' "${suiteFile}" || return 1
}

runAllNoEmptyAggregateWrapperFunctionsContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/all.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    ! grep -Eq '^runRegressionAll\(\) \($|^runRegressionAll\(\) {$' "${suiteFile}" || return 1
    ! grep -Eq '^runRegressionAll\(\) \($|^runRegressionAll\(\) {$' "${legacyScriptFile}" || return 1
}

runAllPublicSelectorRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/all.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    ! grep -q '^registerRegressionAlias full all$' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionAlias ci all$' "${suiteFile}" || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["all"]:-}" == "aggregate-runner" ]] || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["regression-all-composition"]:-}" == "function" ]] || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["regression-all-child-parallel-budget-composition"]:-}" == "function" ]] || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["regression-all-resource-layer-composition"]:-}" == "function" ]] || return 1
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["full"]:-}" ]] || return 1
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["ci"]:-}" ]] || return 1

    runLegacyPublicSelectorRetirementAssertions "${legacyFile}" \
        all \
        regression-all-composition \
        regression-all-child-parallel-budget-composition \
        regression-all-resource-layer-composition \
        full \
        ci
}

runLegacySuiteUsesFunctionRegistryContract() (
    set -euo pipefail
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local scriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local expectedChildren actualChildren

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_LEGACY_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    grep -q '^runRegressionTargetedBatchHelpers() {$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf targeted-batch-helpers runRegressionTargetedBatchHelpers$' "${suiteFile}"
    ! grep -q '^REGRESSION_LEGACY_SCRIPT=' "${suiteFile}"
    ! grep -q '^while read -r selector runner; do$' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateRunnerSequential transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateRunnerParallel transaction-system ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf platform-io ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf platform-io ' "${suiteFile}"
    grep -q 'if \[\[ "\${PADM_REGRESSION_SOURCE_ONLY:-}" == "1" \]\]; then' "${scriptFile}"
    ! grep -q '^runRegressionTargetedBatchHelpers() {$' "${scriptFile}"
    declare -F listRegressionTransactionSystemChildSelectors >/dev/null
    declare -F listRegressionTransactionChildSelectors >/dev/null
    expectedChildren=$(listRegressionTransactionSystemChildSelectors)
    actualChildren=${PADM_REGRESSION_SELECTOR_CHILDREN["transaction-system"]:-}
    [[ -n "${expectedChildren}" ]]
    [[ "${actualChildren}" == "${expectedChildren}" ]]
)

runTargetedBatchHelpersLegacyRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^runRegressionTargetedBatchHelpers() {$' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf targeted-batch-helpers runRegressionTargetedBatchHelpers$' "${suiteFile}" || return 1
    runLegacyFunctionSelectorRetirementAssertions \
        "${legacyFile}" \
        runRegressionTargetedBatchHelpers \
        targeted-batch-helpers \
        '|targeted-batch-helpers|'
}

runTargetedBatchHelpersChildStepsContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    runRegressionStepSequenceAssertions "${suiteFile}" runRegressionTargetedBatchHelpers \
        core-invalid-input-retry-menu \
        core-selection-retry-action \
        sync-configured-managed-users-helper \
        sync-append-local-user-batch \
        traffic-configured-accounts-helper \
        traffic-account-id-map-helper \
        subscription-remote-sources-no-reverse-decode \
        core-rollback-result-message \
        config-transaction \
        padm-bbr-managed-cleanup \
        alone-nginx-backup-manual-check
}

runPlatformSuiteUsesSuiteLocalHelpersContract() (
    local callLog="${TMP_DIR}/platform-suite-root-dispatch.log"

    : >"${callLog}"

    runRegressionPlatform() {
        printf 'legacy-platform-hot\n' >>"${callLog}"
        return 97
    }

    runRegressionPlatformSuiteRoot() {
        printf 'suite-platform-hot\n' >>"${callLog}"
    }

    runRegressionPlatformIo() {
        printf 'legacy-platform-io\n' >>"${callLog}"
        return 97
    }

    runRegressionPlatformIoSuiteRoot() {
        printf 'suite-platform-io\n' >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain platform-hot
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain platform-io

    grep -qx 'suite-platform-hot' "${callLog}"
    grep -qx 'suite-platform-io' "${callLog}"
    ! grep -q '^legacy-platform-hot$' "${callLog}"
    ! grep -q '^legacy-platform-io$' "${callLog}"
)

runTlsSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/tls.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_TLS_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    ! grep -q '^runRegressionTlsSuiteRoot() {$' "${suiteFile}"
    ! grep -q '^while read -r selector runner; do$' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf tls ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf tls ' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf tls-failure-return runRegressionTlsLegacyLeafWithCompat runTlsFailureReturnRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf tls-reinstall-rollback runRegressionTlsLegacyLeafWithCompat runTlsReinstallRollbackRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf tls-renew-failure-propagation runRegressionTlsLegacyLeafWithCompat runTlsRenewalFailurePropagationRegression$' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequentialWithArgs \\' "${suiteFile}"
}

runTlsSelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/tls-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/tls-default-selectors.sorted.txt"
    local expectedDefaultSelectorsFile="${TMP_DIR}/tls-default-selectors.expected.txt"

    declare -F listRegressionTlsChildSelectors >/dev/null

    listRegressionTlsChildSelectors >"${defaultSelectorsFile}"

    cat <<'EOF' >"${expectedDefaultSelectorsFile}"
tls-failure-return
tls-reinstall-rollback
tls-renew-failure-propagation
EOF

    cmp -s "${expectedDefaultSelectorsFile}" "${defaultSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/tls-default-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/tls-default-selectors.unique.txt"
)

runTlsAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/tls.sh"
    local expectedChildren

    ! grep -q '^registerRegressionScriptLeaf tls ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf tls ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateSequential tls \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequentialWithArgs \\' "${suiteFile}"
    expectedChildren=$(listRegressionTlsChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        tls \
        sequential \
        runFrameworkSequentialRegressionSelectorList \
        "${expectedChildren}"
    runAggregateRunnerRunnerArgsAssertions tls 'listRegressionTlsChildSelectors'
}

runTlsLegacyRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/tls.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^registerRegressionAggregateRunnerSequentialWithArgs \\' "${suiteFile}" || return 1
    runLegacyFunctionSelectorRetirementAssertions \
        "${legacyFile}" \
        runRegressionTls \
        tls \
        '|tls|'
}

runTlsLegacyPublicSelectorRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/tls.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^registerRegressionAggregateRunnerSequentialWithArgs \\' "${suiteFile}" || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["tls-failure-return"]:-}" == "function" ]] || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["tls-reinstall-rollback"]:-}" == "function" ]] || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["tls-renew-failure-propagation"]:-}" == "function" ]] || return 1

    runLegacyPublicSelectorRetirementAssertions "${legacyFile}" \
        tls-failure-return \
        tls-reinstall-rollback \
        tls-renew-failure-propagation
}

runTlsNoEmptyAggregateWrapperFunctionsContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/tls.sh"
    ! grep -q '^runRegressionTlsSuiteRoot() {$' "${suiteFile}" || return 1
}

runTlsLeavesUseCompatHelperContract() (
    local callLog="${TMP_DIR}/tls-compat-helper.log"

    : >"${callLog}"

    runRegressionTlsLegacyLeafWithCompat() {
        printf '%s\n' "$1" >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain tls-failure-return
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain tls-reinstall-rollback
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain tls-renew-failure-propagation

    cat <<'EOF' >"${TMP_DIR}/tls-compat-helper.expected.log"
runTlsFailureReturnRegression
runTlsReinstallRollbackRegression
runTlsRenewalFailurePropagationRegression
EOF

    cmp -s "${TMP_DIR}/tls-compat-helper.expected.log" "${callLog}"
)

runTlsLegacyTmpDirIsolationGuardRegisteredContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/tls.sh"

    grep -q '^runRegressionTlsLegacyTmpDirIsolationRegression() ($' "${suiteFile}" || return 1
    grep -q '^    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain tls-renew-failure-propagation$' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf regression-tls-legacy-tmpdir-isolation runRegressionTlsLegacyTmpDirIsolationRegression$' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionAggregateRunnerSequentialWithArgs .*regression-tls-legacy-tmpdir-isolation' "${suiteFile}" || return 1
}

runLegacyDirectLeafSelectorsUseFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"

    ! grep -q '^registerRegressionScriptLeaf targeted-batch-helpers ' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf targeted-batch-helpers runRegressionTargetedBatchHelpers$' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf transaction ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf platform-io ' "${suiteFile}" || return 1
}

runCompositionLeafSelectorsUseSuiteLocalRegistryContract() {
    local status=0
    local selector
    local runner
    local suiteFile
    local legacySuiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    while read -r selector runner suiteFile; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${runner}\$" "${suiteFile}" || status=1
        grep -Eq "^${runner}\\(\\)[[:space:]]*[({]" "${suiteFile}" || status=1
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${legacySuiteFile}" || status=1
        ! grep -q "^registerRegressionFunctionLeaf ${selector} " "${legacySuiteFile}" || status=1
        ! grep -Eq "^${runner}\\(\\)[[:space:]]*[({]" "${legacyScriptFile}" || status=1
        [[ "${PADM_REGRESSION_SELECTOR_KIND["${selector}"]:-}" == "function" ]] || status=1
    done <<EOF
regression-all-composition runRegressionAllCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/all.sh
regression-all-child-parallel-budget-composition runRegressionAllChildParallelBudgetCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/all.sh
regression-all-resource-layer-composition runRegressionAllResourceLayerCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/all.sh
regression-fast-parallel-composition runRegressionFastParallelCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/fast.sh
regression-fast-only-parallel-composition runRegressionFastOnlyParallelCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/fast.sh
regression-fast-only-output-parallel-composition runRegressionFastOnlyOutputParallelCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/fast.sh
regression-routing-parallel-composition runRegressionRoutingParallelCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/routing.sh
regression-runtime-parallel-composition runRegressionRuntimeParallelCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/runtime.sh
regression-transaction-core-parallel-composition runRegressionTransactionCoreParallelCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/transaction.sh
regression-transaction-system-parallel-composition runRegressionTransactionSystemParallelCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/transaction.sh
regression-ui-parallel-composition runRegressionUiParallelCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/ui.sh
regression-ui-long-tail-split-composition runRegressionUiLongTailSplitCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/ui.sh
regression-selector-dispatch-composition runRegressionSelectorDispatchCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/contracts.sh
regression-parallel-selector-limit-composition runRegressionParallelSelectorLimitCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/contracts.sh
regression-parallel-selector-slot-refill-composition runRegressionParallelSelectorSlotRefillCompositionRegression ${PROJECT_ROOT}/shell/regression/suites/contracts.sh
EOF

    return "${status}"
}

runCompositionLeafSelectorsLegacyPublicRetirementContract() {
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local selector
    local usageLine
    local usageSelectors

    usageLine=$(grep -F 'usage: %s [' "${legacyScriptFile}" || true)
    usageSelectors="${usageLine#*[}"
    usageSelectors="${usageSelectors%%]*}"

    while read -r selector; do
        [[ -n "${selector}" ]] || continue
        [[ "${PADM_REGRESSION_SELECTOR_KIND["${selector}"]:-}" == "function" ]] || return 1
        ! awk -v sel="${selector}" '
            {
                line = $0
                sub(/^[[:space:]]+/, "", line)
                if (line == sel ")") {
                    found = 1
                }
            }
            END { exit(found ? 0 : 1) }
        ' "${legacyScriptFile}" || return 1
        [[ -z "${usageLine}" || "|${usageSelectors}|" != *"|${selector}|"* ]] || return 1
    done <<'EOF'
regression-all-composition
regression-all-child-parallel-budget-composition
regression-all-resource-layer-composition
regression-fast-parallel-composition
regression-fast-only-parallel-composition
regression-fast-only-output-parallel-composition
regression-routing-parallel-composition
regression-runtime-parallel-composition
regression-transaction-core-parallel-composition
regression-transaction-system-parallel-composition
regression-subscription-state-remote-restore-parallel-isolation-composition
regression-subscription-state-structure-parallel-isolation-composition
regression-subscription-state-sync-rollback-parallel-isolation-composition
regression-ui-parallel-composition
regression-ui-long-tail-split-composition
regression-selector-dispatch-composition
regression-parallel-selector-limit-composition
regression-parallel-selector-slot-refill-composition
EOF
}

runTransactionDirectLeafSelectorsUseFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
    local legacySuiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local status=0

    while read -r selector runner args; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${runner}${args:+ ${args}}\$" "${suiteFile}" || status=1
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${legacySuiteFile}" || status=1
        ! grep -q "^registerRegressionFunctionLeaf ${selector} " "${legacySuiteFile}" || status=1
        [[ "${PADM_REGRESSION_SELECTOR_KIND["${selector}"]:-}" == "function" ]] || status=1
    done <<'EOF'
cdn-address-write-transaction runRegressionTransactionLegacyLeafWithCompat runCdnAddressTransactionRegression
subscribe-server-name runRegressionTransactionLegacyLeafWithCompat runSubscribeServerNameRegression
subscribe-nginx-config-write runRegressionTransactionLegacyLeafWithCompat runSubscribeNginxConfigWriteRegression
subscribe-nginx-service-failure runRegressionTransactionLegacyLeafWithCompat runSubscribeNginxServiceFailureRegression
subscribe-salt-write-transaction runRegressionTransactionLegacyLeafWithCompat runSubscribeSaltWriteTransactionRegression
subscribe-user-output-transaction runRegressionTransactionLegacyLeafWithCompat runSubscribeUserOutputTransactionRegression
remove-user-subscription-menu-failure runRegressionTransactionLegacyLeafWithCompat runRemoveUserSubscriptionMenuFailureRegression
user-subscription-menu-mutation-failure runRegressionTransactionLegacyLeafWithCompat runUserSubscriptionMenuMutationFailureRegression
remote-subscribe-fetch runRegressionTransactionLegacyLeafWithCompat runRemoteSubscribeFetchRegression
nginx-service-failure runNginxServiceFailureRegression
uninstall-nginx-cleanup runUninstallNginxCleanupRegression
clean-agent-nginx-managed-remove runCleanAgentNginxManagedRemovalRegression
fail2ban-managed-cleanup runFail2banManagedCleanupRegression
fail2ban-apply-transaction runFail2banApplyTransactionRegression
uninstall-wireguard-cleanup runUninstallWireGuardCleanupRegression
wireguard-key-transaction runWireGuardKeyTransactionRegression
wireguard-control-safe-dir runWireGuardControlSafeDirRegression
warp-config-safe-dir runWarpConfigSafeDirRegression
warp-config-file-cleanup runWarpConfigFileCleanupRegression
uninstall-service-stop-failure runUninstallServiceStopFailureRegression
clean-last-installation-failure runCleanLastInstallationConfigFailureRegression
clean-last-installation-acme-home runCleanLastInstallationConfigAcmeHomeFailureRegression
clean-last-installation-acme-relative-home runCleanLastInstallationConfigResolvesRelativeAcmeHomeRegression
alone-nginx-write-transaction runAloneNginxConfigWriteTransactionRegression
alone-nginx-update-transaction runAloneNginxUpdateTransactionRegression
EOF

    return "${status}"
}

runTransactionNoCompatWrapperFunctionsContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
    local status=0

    while read -r wrapperName; do
        ! grep -q "^${wrapperName}() { runRegressionTransactionLegacyLeafWithCompat " "${suiteFile}" || status=1
    done <<'EOF'
runCdnAddressTransactionCompatRegression
runSubscribeServerNameCompatRegression
runSubscribeNginxConfigWriteCompatRegression
runSubscribeNginxServiceFailureCompatRegression
runSubscribeSaltWriteTransactionCompatRegression
runSubscribeUserOutputTransactionCompatRegression
runRemoveUserSubscriptionMenuFailureCompatRegression
runUserSubscriptionMenuMutationFailureCompatRegression
runRemoteSubscribeFetchCompatRegression
EOF

    return "${status}"
}

runTransactionSubscriptionLeavesUseCompatHelperContract() (
    local callLog="${TMP_DIR}/transaction-subscription-compat-helper.log"

    : >"${callLog}"

    runRegressionTransactionLegacyLeafWithCompat() {
        printf '%s\n' "$1" >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain transaction-subscription

    cat <<'EOF' >"${TMP_DIR}/transaction-subscription-compat-helper.expected.log"
runCdnAddressTransactionRegression
runSubscribeServerNameRegression
runSubscribeNginxConfigWriteRegression
runSubscribeNginxServiceFailureRegression
runSubscribeSaltWriteTransactionRegression
runSubscribeUserOutputTransactionRegression
runRemoveUserSubscriptionMenuFailureRegression
runUserSubscriptionMenuMutationFailureRegression
runRemoteSubscribeFetchRegression
EOF

    cmp -s "${TMP_DIR}/transaction-subscription-compat-helper.expected.log" "${callLog}"
)

runTransactionCoreDirectLeafSelectorsUseFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
    local legacySuiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local status=0

    while read -r selector runner; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${runner}\$" "${suiteFile}" || status=1
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${legacySuiteFile}" || status=1
        ! grep -q "^registerRegressionFunctionLeaf ${selector} " "${legacySuiteFile}" || status=1
        [[ "${PADM_REGRESSION_SELECTOR_KIND["${selector}"]:-}" == "function" ]] || status=1
    done <<'EOF'
core-rollback-result-message runCoreRollbackResultMessageRegression
config-transaction runConfigTransactionRegression
core-port-file-transaction runCorePortFileTransactionRegression
core-port-unsafe-config-dir runCorePortRejectsUnsafeConfigDirRegression
entry-helper-config runEntryHelperConfigRegression
user-config-write runUserConfigWriteRegression
remove-user runRemoveUserRegression
check-port-open-nginx-directory-target runCheckPortOpenNginxRejectsDirectoryTargetRegression
alone-nginx-directory-target runAloneNginxRejectsDirectoryTargetRegression
sing-box-managed-cleanup runSingBoxManagedCleanupRegression
xray-reality-port-failure runXrayRealityPortFailureRegression
sing-box-reality-key-transaction runSingBoxRealityKeyTransactionRegression
core-template-managed-remove runCoreTemplateManagedConfigRemovalRegression
core-template-return-failure runCoreTemplateReturnFailureRegression
core-binary-install-copy-failure runCoreBinaryInstallCopyFailureRegression
sing-box-cronet-rollback runSingBoxCronetRollbackRegression
finalize-sing-box-rollback runFinalizeSingBoxBinaryInstallRollbackRegression
service-queue-apply-propagation runServiceQueueApplyPropagationRegression
core-install-service-action-failure runCoreInstallServiceActionFailureRegression
sing-box-merge-start-failure runSingBoxMergeStartFailureRegression
sing-box-uninstall-rejects-unsafe-config-path runSingBoxUninstallRejectsUnsafeConfigPathRegression
sing-box-uninstall-failure-propagation runSingBoxUninstallFailurePropagationRegression
sing-box-protocol-reload-failure runSingBoxProtocolReloadFailureRegression
geo-update-reload-failure runGeoUpdateReloadFailureRegression
core-cleanup-failure-propagation runCoreCleanupFailurePropagationRegression
sing-box-log-transaction runSingBoxLogTransactionRegression
core-upgrade-directory-target runCoreUpgradeRejectsDirectoryTargetRegression
legacy-core-upgrade-keeps-existing runLegacyCoreUpgradeKeepsExistingBinaryRegression
core-first-install-failure-clean runCoreFirstInstallLeavesNoLiveArtifactsOnFailureRegression
core-install-unsafe-binary-path runCoreInstallRejectsUnsafeBinaryPathRegression
core-first-install-commit-rollback runCoreFirstInstallCommitFailureRollbackRegression
sing-box-download-artifacts-cleanup runSingBoxDownloadArtifactsCleanupRegression
network-check-return-failure runNetworkCheckReturnFailureRegression
sing-box-merge-config-transaction runSingBoxMergeConfigTransactionRegression
reload-core-propagation runReloadCorePropagationRegression
EOF

    return "${status}"
}

runPlatformIoDirectLeafSelectorsUseFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/platform.sh"
    local legacySuiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local status=0

    while read -r selector helper regression; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${helper} ${regression}\$" "${suiteFile}" || status=1
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${legacySuiteFile}" || status=1
        ! grep -q "^registerRegressionFunctionLeaf ${selector} " "${legacySuiteFile}" || status=1
        [[ "${PADM_REGRESSION_SELECTOR_KIND["${selector}"]:-}" == "function" ]] || status=1
    done <<'EOF'
install-tools-certificate-dependency runRegressionPlatformLegacyLeafWithCompat runInstallToolsCertificateDependencyRegression
install-tools-acme-result-failure runRegressionPlatformLegacyLeafWithCompat runInstallToolsAcmeResultFailureRegression
install-tools-acme-commit-failure runRegressionPlatformLegacyLeafWithCompat runInstallToolsAcmeCommitFailureRegression
install-tools-configured-log runRegressionPlatformLegacyLeafWithCompat runInstallToolsUsesConfiguredInstallLogRegression
install-tools-update-failure runRegressionPlatformLegacyLeafWithCompat runInstallToolsUpdateFailureRegression
install-tools-release-info-failure runRegressionPlatformLegacyLeafWithCompat runInstallToolsReleaseInfoFailureRegression
install-tools-nginx-reinstall-failure runRegressionPlatformLegacyLeafWithCompat runInstallToolsNginxReinstallFailureRegression
apt-key-install-failure runRegressionPlatformLegacyLeafWithCompat runAptKeyInstallFailureRegression
nginx-apt-refresh-rollback runRegressionPlatformLegacyLeafWithCompat runNginxAptRepoRefreshRollbackRegression
nginx-alpine-default-conf-rollback runRegressionPlatformLegacyLeafWithCompat runNginxAlpineDefaultConfRollbackRegression
nginx-yum-mainline-enable-failure runRegressionPlatformLegacyLeafWithCompat runNginxYumMainlineEnableFailureRegression
base-package-batch runRegressionPlatformLegacyLeafWithCompat runBasePackageBatchRegression
package-rollback-failure runRegressionPlatformLegacyLeafWithCompat runPackageRollbackFailureRegression
package-command-stdin runRegressionPlatformLegacyLeafWithCompat runPackageCommandStdinRegression
reality-scanner-unsafe-dir runRegressionPlatformLegacyLeafWithCompat runRealityScannerRejectsUnsafeDirRegression
reality-scanner-binary runRegressionPlatformLegacyLeafWithCompat runRealityScannerBinaryRegression
reality-scanner-download-failure runRegressionPlatformLegacyLeafWithCompat runRealityScannerDownloadFailureKeepsExistingDirRegression
EOF

    return "${status}"
}

runSubscriptionDirectLeafSelectorsUseFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local status=0

    while read -r selector runner args; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${runner}${args:+ ${args}}\$" "${suiteFile}" || status=1
    done <<'EOF'
subscription-output runRegressionSubscriptionLegacyLeafWithCompat runRegressionSubscriptionOutput
subscription-output-profile-and-reality runRegressionSubscriptionLegacyLeafWithCompat runSubscriptionOutputProfileAndRealityRegression
subscription-output-publish-accounts-and-remote-hint runRegressionSubscriptionLegacyLeafWithCompat runSubscriptionOutputPublishAccountsAndRemoteHintRegression
subscription-output-tls-vless-vmess-trojan runRegressionSubscriptionLegacyLeafWithCompat runSubscriptionOutputTlsVlessVmessTrojanRegression
subscription-output-tls-any-hysteria-tuic-naive runRegressionSubscriptionLegacyLeafWithCompat runSubscriptionOutputTlsAnyHysteriaTuicNaiveRegression
subscription-remote-unique runRegressionSubscriptionLegacyLeafWithCompat runRemoteSubscribeFetchUniqueRegression
subscription-remote-rollback runRegressionSubscriptionLegacyLeafWithCompat runRemoteSubscribeFetchRollbackRegression
subscription-remote-merge runRegressionSubscriptionLegacyLeafWithCompat runRemoteSubscribeFetchMergeRegression
subscription-remote-controlled runRegressionSubscriptionLegacyLeafWithCompat runRemoteSubscribeFetchControlledRegression
subscription-remote-append-failure runRegressionSubscriptionLegacyLeafWithCompat runRemoteSubscribeFetchAppendFailureRegression
subscription-remote-commit-failure runRegressionSubscriptionLegacyLeafWithCompat runRemoteSubscribeFetchCommitFailureRegression
subscription-remote-idempotent runRegressionSubscriptionLegacyLeafWithCompat runRemoteSubscribeFetchIdempotentRegression
sing-box-subscribe-write runRegressionSubscriptionLegacyLeafWithCompat runSingBoxSubscribeWriteRegression
subscribe-local-output-transaction runSubscribeLocalOutputTransactionRegression
sing-box-port-failure runSingBoxPortFailureRegression
subscribe-local-rollback runSubscribeLocalRollbackRegression
subscription-groups-migration-backup runSubscriptionGroupsMigrationBackupRegression
subscription-groups-backup-failure runSubscriptionGroupsBackupFailureRegression
refresh-local-subscriptions-rollback runRefreshLocalSubscriptionsRollbackRegression
subscribe-return-failure runSubscribeReturnFailureRegression
EOF

    return "${status}"
}

runSubscriptionNoCompatWrapperFunctionsContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local status=0

    while read -r wrapperName; do
        ! grep -q "^${wrapperName}() { runRegressionSubscriptionLegacyLeafWithCompat " "${suiteFile}" || status=1
    done <<'EOF'
runRegressionSubscriptionOutputCompatRegression
runRegressionSubscriptionOutputProfileAndRealityCompatRegression
runRegressionSubscriptionOutputPublishAccountsAndRemoteHintCompatRegression
runRegressionSubscriptionOutputTlsVlessVmessTrojanCompatRegression
runRegressionSubscriptionOutputTlsAnyHysteriaTuicNaiveCompatRegression
runRemoteSubscribeFetchUniqueCompatRegression
runRemoteSubscribeFetchRollbackCompatRegression
runRemoteSubscribeFetchMergeCompatRegression
runRemoteSubscribeFetchControlledCompatRegression
runRemoteSubscribeFetchAppendFailureCompatRegression
runRemoteSubscribeFetchCommitFailureCompatRegression
runRemoteSubscribeFetchIdempotentCompatRegression
runSingBoxSubscribeWriteCompatRegression
EOF

    return "${status}"
}

runSubscriptionCompositionLeafSelectorsUseFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local legacySuiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local status=0

    while read -r selector runner; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${runner}\$" "${suiteFile}" || status=1
        grep -Eq "^${runner}\\(\\)[[:space:]]*[({]" "${suiteFile}" || status=1
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${legacySuiteFile}" || status=1
        ! grep -q "^registerRegressionFunctionLeaf ${selector} " "${legacySuiteFile}" || status=1
        ! grep -Eq "^${runner}\\(\\)[[:space:]]*[({]" "${legacyScriptFile}" || status=1
        [[ "${PADM_REGRESSION_SELECTOR_KIND["${selector}"]:-}" == "function" ]] || status=1
    done <<'EOF'
regression-subscription-parallel-composition runRegressionSubscriptionParallelCompositionRegression
regression-subscription-tx-parallel-composition runRegressionSubscriptionTxParallelCompositionRegression
regression-subscription-remote-parallel-composition runRegressionSubscriptionRemoteParallelCompositionRegression
EOF

    return "${status}"
}

runSubscriptionStateCompositionLeafSelectorsUseFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription_state.sh"
    local legacySuiteFile="${PROJECT_ROOT}/shell/regression/suites/legacy.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local status=0

    while read -r selector runner; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${runner}\$" "${suiteFile}" || status=1
        grep -Eq "^${runner}\\(\\)[[:space:]]*[({]" "${suiteFile}" || status=1
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${legacySuiteFile}" || status=1
        ! grep -q "^registerRegressionFunctionLeaf ${selector} " "${legacySuiteFile}" || status=1
        ! grep -Eq "^${runner}\\(\\)[[:space:]]*[({]" "${legacyScriptFile}" || status=1
        [[ "${PADM_REGRESSION_SELECTOR_KIND["${selector}"]:-}" == "function" ]] || status=1
    done <<'EOF'
regression-subscription-state-remote-restore-parallel-isolation-composition runRegressionSubscriptionStateRemoteRestoreParallelIsolationCompositionRegression
regression-subscription-state-structure-parallel-isolation-composition runRegressionSubscriptionStateStructureParallelIsolationCompositionRegression
regression-subscription-state-sync-rollback-parallel-isolation-composition runRegressionSubscriptionStateSyncRollbackParallelIsolationCompositionRegression
EOF

    return "${status}"
}

runSubscriptionSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q 'source "\${REGRESSION_SUBSCRIPTION_SUITE_DIR}/../framework/runtime.sh"' "${suiteFile}"
    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_SUBSCRIPTION_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    grep -q '^runRegressionSubscriptionOutput() {$' "${suiteFile}"
    grep -q '^runRegressionSubscriptionSuiteRoot() {$' "${suiteFile}"
    ! grep -q '^runRegressionSubscriptionRemoteSuiteRoot() {$' "${suiteFile}"
    ! grep -q '^runRegressionSubscriptionTxSuiteRoot() {$' "${suiteFile}"
    ! grep -q '^runRegressionSubscriptionOutputSuiteRoot() {$' "${suiteFile}"
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/subscription-' "${suiteFile}"
    ! grep -q '^runRegressionSubscription() {$' "${suiteFile}"
    ! grep -q '^runRegressionSubscriptionRemote() {$' "${suiteFile}"
    ! grep -q '^runRegressionSubscriptionTx() {$' "${suiteFile}"
    ! grep -q '^runRegressionSubscription() {$' "${legacyScriptFile}"
    ! grep -q '^runRegressionSubscriptionRemote() {$' "${legacyScriptFile}"
    ! grep -q '^runRegressionSubscriptionTx() {$' "${legacyScriptFile}"
    ! grep -q '^runRegressionSubscriptionOutput() {$' "${legacyScriptFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription-remote ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-remote ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription-tx ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-tx ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription-remote-fetch ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-remote-fetch ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-remote-fetch-' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription-write-transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-write-transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf regression-subscription-write-transaction-' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf subscription-output runRegressionSubscriptionLegacyLeafWithCompat runRegressionSubscriptionOutput$' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription runRegressionSubscriptionSuiteRoot \\' "${suiteFile}"
    [[ "${PADM_REGRESSION_SELECTOR_KIND["subscription"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_KIND["subscription-remote"]:-}" == "aggregate-runner" ]]
    [[ "${PADM_REGRESSION_SELECTOR_KIND["subscription-tx"]:-}" == "aggregate-runner" ]]
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["subscription-remote-fetch"]:-}" ]]
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["subscription-write-transaction"]:-}" ]]
}

runSubscriptionNoEmptyAggregateWrapperFunctionsContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local status=0

    while read -r wrapperName; do
        ! grep -q "^${wrapperName}() {$" "${suiteFile}" || status=1
        ! grep -q "^${wrapperName}() {$" "${legacyScriptFile}" || status=1
    done <<'EOF'
runRegressionSubscription
runRegressionSubscriptionRemote
runRegressionSubscriptionTx
EOF

    return "${status}"
}

runSubscriptionLegacyPublicSelectorRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local subscriptionRemoteLeafLine

    grep -q '^registerRegressionAggregateRunnerParallel subscription runRegressionSubscriptionSuiteRoot \\' "${suiteFile}" || return 1
    [[ "$(grep -c '^registerRegressionAggregateRunnerParallelWithArgs \\' "${suiteFile}")" -ge 2 ]] || return 1

    subscriptionRemoteLeafLine=$(grep -F 'subscription remote leaf selectors: ' "${legacyScriptFile}" || true)
    [[ -z "${subscriptionRemoteLeafLine}" ]] || return 1

    runLegacyPublicSelectorRetirementAssertions "${legacyScriptFile}" \
        subscription \
        subscription-remote \
        subscription-tx \
        subscription-output-profile-and-reality \
        subscription-output-publish-accounts-and-remote-hint \
        subscription-output-tls-vless-vmess-trojan \
        subscription-output-tls-any-hysteria-tuic-naive \
        subscription-remote-unique \
        subscription-remote-rollback \
        subscription-remote-merge \
        subscription-remote-controlled \
        subscription-remote-append-failure \
        subscription-remote-commit-failure \
        subscription-remote-idempotent \
        sing-box-subscribe-write \
        cdn-address-write-transaction \
        subscribe-local-output-transaction \
        subscribe-salt-write-transaction \
        subscribe-server-name \
        subscribe-nginx-config-write \
        subscribe-nginx-service-failure \
        sing-box-port-failure \
        subscribe-user-output-transaction \
        subscribe-local-rollback \
        subscription-groups-migration-backup \
        subscription-groups-backup-failure \
        refresh-local-subscriptions-rollback \
        subscribe-return-failure \
        remove-user-subscription-menu-failure \
        user-subscription-menu-mutation-failure \
        regression-subscription-parallel-composition \
        regression-subscription-output-parallel-composition \
        regression-subscription-tx-parallel-composition \
        regression-subscription-remote-parallel-composition
}

runUiPublicSelectorsUseFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/ui.sh"
    local status=0

    ! grep -q '^registerRegressionScriptLeaf menu-smoke ' "${suiteFile}" || status=1
    ! grep -q '^registerRegressionFunctionLeaf menu-smoke ' "${suiteFile}" || status=1
    ! grep -q '^registerRegressionScriptLeaf menu-smoke-full ' "${suiteFile}" || status=1
    ! grep -q '^registerRegressionFunctionLeaf menu-smoke-full ' "${suiteFile}" || status=1

    while read -r selector runner; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${runner}\$" "${suiteFile}" || status=1
    done <<'EOF'
ui-smoke runRegressionUiSmokeSuiteRoot
ui-full-core runMenuSmokeFullCoreCompatRegression
ui-full-subscription-main-entry runMenuSmokeFullSubscriptionMainEntryCompatRegression
ui-full-subscription-main-publish-service runMenuSmokeFullSubscriptionMainPublishServiceCompatRegression
ui-full-subscription-main-publish-user-empty runMenuSmokeFullSubscriptionMainPublishUserEmptyCompatRegression
ui-full-subscription-main-publish-user-create runMenuSmokeFullSubscriptionMainPublishUserCreateCompatRegression
ui-full-subscription-main-publish-user-inspect runMenuSmokeFullSubscriptionMainPublishUserInspectCompatRegression
ui-full-subscription-main-publish-sync-skip runMenuSmokeFullSubscriptionMainPublishSyncSkipCompatRegression
ui-full-subscription-main-publish-sync-enable runMenuSmokeFullSubscriptionMainPublishSyncEnableCompatRegression
ui-full-subscription-main-maintenance runMenuSmokeFullSubscriptionMainMaintenanceCompatRegression
ui-full-subscription-controlled runMenuSmokeFullSubscriptionControlledCompatRegression
ui-full-core-maintenance runMenuSmokeFullCoreMaintenanceCompatRegression
wireguard-menu-flow-bootstrap runSubscriptionWireGuardMenuFlowBootstrapCompatRegression
wireguard-menu-flow-peer-add-update runSubscriptionWireGuardMenuFlowPeerAddUpdateCompatRegression
wireguard-menu-flow-peer-rollback-apply-service runSubscriptionWireGuardMenuFlowPeerRollbackApplyServiceCompatRegression
wireguard-menu-flow-peer-rollback-apply-restore runSubscriptionWireGuardMenuFlowPeerRollbackApplyRestoreCompatRegression
wireguard-menu-flow-peer-rollback-source runSubscriptionWireGuardMenuFlowPeerRollbackSourceCompatRegression
wireguard-menu-flow-peer-rollback-credential-write runSubscriptionWireGuardMenuFlowPeerRollbackCredentialWriteCompatRegression
wireguard-menu-flow-peer-rollback-credential-groups-restore runSubscriptionWireGuardMenuFlowPeerRollbackCredentialGroupsRestoreCompatRegression
wireguard-menu-flow-peer-source-control-toggle runSubscriptionWireGuardMenuFlowPeerSourceControlToggleCompatRegression
wireguard-menu-flow-peer-source-control-clear-error runSubscriptionWireGuardMenuFlowPeerSourceControlClearErrorCompatRegression
wireguard-menu-flow-peer-source-control-status runSubscriptionWireGuardMenuFlowPeerSourceControlStatusCompatRegression
wireguard-menu-flow-control-restore runSubscriptionWireGuardMenuFlowControlRestoreCompatRegression
wireguard-restore-runner runSubscriptionWireGuardRestoreRunnerCompatRegression
EOF

    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui-smoke"]:-}" == "function" ]] || status=1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui-full"]:-}" == "aggregate-runner" ]] || status=1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui-full-subscription-main"]:-}" == "aggregate-runner" ]] || status=1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui-full-subscription-main-publish"]:-}" == "aggregate-runner" ]] || status=1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui-full-subscription-main-publish-user"]:-}" == "aggregate-runner" ]] || status=1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui-full-subscription-main-publish-sync"]:-}" == "aggregate-runner" ]] || status=1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["wireguard-menu-flow"]:-}" == "aggregate-runner" ]] || status=1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["wireguard-menu-flow-peer-transaction"]:-}" == "aggregate-runner" ]] || status=1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["wireguard-menu-flow-peer-rollback"]:-}" == "aggregate-runner" ]] || status=1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["wireguard-menu-flow-peer-rollback-apply"]:-}" == "aggregate-runner" ]] || status=1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["wireguard-menu-flow-peer-rollback-credential"]:-}" == "aggregate-runner" ]] || status=1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["wireguard-menu-flow-peer-source-control"]:-}" == "aggregate-runner" ]] || status=1
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["menu-smoke"]:-}" ]] || status=1
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["menu-smoke-full"]:-}" ]] || status=1

    return "${status}"
}

runUiSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/ui.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q 'source "\${REGRESSION_UI_SUITE_DIR}/../framework/runtime.sh"' "${suiteFile}" || return 1
    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_UI_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}" || return 1
    grep -q '^runRegressionMenuSmokeFull() {$' "${suiteFile}" || return 1
    grep -q '^runRegressionWireGuardMenuFlow() {$' "${suiteFile}" || return 1
    grep -q '^runSubscriptionWireGuardMenuFlowPeerTransactionRegression() {$' "${suiteFile}" || return 1
    grep -q '^runSubscriptionWireGuardMenuFlowPeerRollbackRegression() {$' "${suiteFile}" || return 1
    grep -q '^runSubscriptionWireGuardMenuFlowPeerRollbackApplyRegression() {$' "${suiteFile}" || return 1
    grep -q '^runSubscriptionWireGuardMenuFlowPeerRollbackCredentialRegression() {$' "${suiteFile}" || return 1
    grep -q '^runSubscriptionWireGuardMenuFlowPeerSourceControlRegression() {$' "${suiteFile}" || return 1
    grep -q '^listRegressionUiChildSelectors() {$' "${suiteFile}" || return 1
    grep -q '^listRegressionUiAllProfileChildSelectors() {$' "${suiteFile}" || return 1
    grep -q '^runRegressionUiSmokeSuiteRoot() {$' "${suiteFile}" || return 1
    grep -q '^runRegressionUiSuiteRoot() {$' "${suiteFile}" || return 1
    grep -q '^runRegressionUiParallelCompositionRegression() ' "${suiteFile}" || return 1
    grep -q '^runRegressionUiLongTailSplitCompositionRegression() ' "${suiteFile}" || return 1
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/ui-parallel-' "${suiteFile}" || return 1
    ! grep -q '^listRegressionUiChildSelectors() {$' "${legacyScriptFile}" || return 1
    ! grep -q '^listRegressionUiAllProfileChildSelectors() {$' "${legacyScriptFile}" || return 1
    ! grep -q '^runRegressionUi() {$' "${legacyScriptFile}" || return 1
    ! grep -q '^runRegressionUiParallelCompositionRegression() ' "${legacyScriptFile}" || return 1
    ! grep -q '^runRegressionUiLongTailSplitCompositionRegression() ' "${legacyScriptFile}" || return 1
    ! grep -q '^runRegressionWireGuardMenuFlow() {$' "${legacyScriptFile}" || return 1
    ! grep -q '^runSubscriptionWireGuardMenuFlowPeerTransactionRegression() {$' "${legacyScriptFile}" || return 1
    ! grep -q '^runSubscriptionWireGuardMenuFlowPeerRollbackRegression() {$' "${legacyScriptFile}" || return 1
    ! grep -q '^runSubscriptionWireGuardMenuFlowPeerRollbackApplyRegression() {$' "${legacyScriptFile}" || return 1
    ! grep -q '^runSubscriptionWireGuardMenuFlowPeerRollbackCredentialRegression() {$' "${legacyScriptFile}" || return 1
    ! grep -q '^runSubscriptionWireGuardMenuFlowPeerSourceControlRegression() {$' "${legacyScriptFile}" || return 1
    ! grep -q '^registerRegressionScriptLeaf ui ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf ui ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionScriptLeaf menu-smoke ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf menu-smoke ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionScriptLeaf menu-smoke-full ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf menu-smoke-full ' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf ui-smoke runRegressionUiSmokeSuiteRoot$' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallel ui-full runRegressionMenuSmokeFull \\' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallel ui runRegressionUiSuiteRoot \\' "${suiteFile}" || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui-smoke"]:-}" == "function" ]] || return 1
    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui-full"]:-}" == "aggregate-runner" ]] || return 1
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["menu-smoke"]:-}" ]] || return 1
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["menu-smoke-full"]:-}" ]] || return 1
}

runUiSmokeLegacyWrapperRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/ui.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^registerRegressionFunctionLeaf ui-smoke runRegressionUiSmokeSuiteRoot$' "${suiteFile}" || return 1
    runLegacyFunctionSelectorRetirementAssertions \
        "${legacyScriptFile}" \
        runRegressionMenuSmoke \
        ui-smoke \
        '|ui-smoke|'
}

runUiFullLegacyWrapperRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/ui.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^runRegressionMenuSmokeFull() {$' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallel ui-full runRegressionMenuSmokeFull \\' "${suiteFile}" || return 1
    runLegacyFunctionSelectorRetirementAssertions \
        "${legacyScriptFile}" \
        runRegressionMenuSmokeFull \
        ui-full \
        '|ui-full|'
}

runUiFullSubscriptionMainLegacyWrapperRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/ui.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^runRegressionUiFullSubscriptionMain() {$' "${suiteFile}" || return 1
    grep -q '^runRegressionUiFullSubscriptionMainPublish() {$' "${suiteFile}" || return 1
    grep -q '^runRegressionUiFullSubscriptionMainPublishUser() {$' "${suiteFile}" || return 1
    grep -q '^runRegressionUiFullSubscriptionMainPublishSync() {$' "${suiteFile}" || return 1

    runLegacyFunctionRetirementBatchAssertions \
        "${legacyScriptFile}" \
        runMenuSmokeFullSubscriptionMainRegression \
        runMenuSmokeFullSubscriptionMainPublishRegression \
        runMenuSmokeFullSubscriptionMainPublishUserRegression \
        runMenuSmokeFullSubscriptionMainPublishSyncRegression
}

runUiWireGuardLegacyWrapperRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/ui.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local selector

    grep -q '^runRegressionWireGuardMenuFlow() {$' "${suiteFile}" || return 1
    grep -q '^runSubscriptionWireGuardMenuFlowPeerTransactionRegression() {$' "${suiteFile}" || return 1
    grep -q '^runSubscriptionWireGuardMenuFlowPeerRollbackRegression() {$' "${suiteFile}" || return 1
    grep -q '^runSubscriptionWireGuardMenuFlowPeerRollbackApplyRegression() {$' "${suiteFile}" || return 1
    grep -q '^runSubscriptionWireGuardMenuFlowPeerRollbackCredentialRegression() {$' "${suiteFile}" || return 1
    grep -q '^runSubscriptionWireGuardMenuFlowPeerSourceControlRegression() {$' "${suiteFile}" || return 1

    runLegacyFunctionRetirementBatchAssertions \
        "${legacyScriptFile}" \
        runRegressionWireGuardMenuFlow \
        runSubscriptionWireGuardMenuFlowPeerTransactionRegression \
        runSubscriptionWireGuardMenuFlowPeerRollbackRegression \
        runSubscriptionWireGuardMenuFlowPeerRollbackApplyRegression \
        runSubscriptionWireGuardMenuFlowPeerRollbackCredentialRegression \
        runSubscriptionWireGuardMenuFlowPeerSourceControlRegression

    for selector in \
        wireguard-menu-flow \
        wireguard-menu-flow-peer-transaction \
        wireguard-menu-flow-peer-rollback \
        wireguard-menu-flow-peer-rollback-apply \
        wireguard-menu-flow-peer-rollback-credential \
        wireguard-menu-flow-peer-source-control; do
        ! grep -Eq "^[[:space:]]*${selector}\)$" "${legacyScriptFile}" || return 1
        ! grep -Eq "[\\[|]${selector}[|\\]]" "${legacyScriptFile}" || return 1
    done
}

runUiLegacyPublicSelectorRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/ui.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local selector
    local uiLeafLine
    local uiLeafSelectors

    grep -q '^registerRegressionAggregateRunnerParallel ui runRegressionUiSuiteRoot \\' "${suiteFile}" || return 1

    uiLeafLine=$(grep -F 'ui leaf selectors: ' "${legacyScriptFile}" || true)
    uiLeafSelectors="${uiLeafLine#*: }"
    uiLeafSelectors="${uiLeafSelectors%%\\n*}"

    runLegacyPublicSelectorRetirementAssertions "${legacyScriptFile}" \
        ui \
        ui-full-core \
        ui-full-subscription-main \
        ui-full-subscription-main-entry \
        ui-full-subscription-main-publish \
        ui-full-subscription-main-publish-service \
        ui-full-subscription-main-publish-user \
        ui-full-subscription-main-publish-user-empty \
        ui-full-subscription-main-publish-user-create \
        ui-full-subscription-main-publish-user-inspect \
        ui-full-subscription-main-publish-sync \
        ui-full-subscription-main-publish-sync-skip \
        ui-full-subscription-main-publish-sync-enable \
        ui-full-subscription-main-maintenance \
        ui-full-subscription-controlled \
        ui-full-core-maintenance \
        wireguard-menu-flow-bootstrap \
        wireguard-menu-flow-peer-add-update \
        wireguard-menu-flow-peer-rollback-apply-service \
        wireguard-menu-flow-peer-rollback-apply-restore \
        wireguard-menu-flow-peer-rollback-source \
        wireguard-menu-flow-peer-rollback-credential-write \
        wireguard-menu-flow-peer-rollback-credential-groups-restore \
        wireguard-menu-flow-peer-source-control-toggle \
        wireguard-menu-flow-peer-source-control-clear-error \
        wireguard-menu-flow-peer-source-control-status \
        wireguard-menu-flow-control-restore \
        wireguard-restore-runner \
        regression-ui-parallel-composition \
        regression-ui-long-tail-split-composition

    for selector in \
        ui \
        ui-full-core \
        ui-full-subscription-main \
        ui-full-subscription-main-entry \
        ui-full-subscription-main-publish \
        ui-full-subscription-main-publish-service \
        ui-full-subscription-main-publish-user \
        ui-full-subscription-main-publish-user-empty \
        ui-full-subscription-main-publish-user-create \
        ui-full-subscription-main-publish-user-inspect \
        ui-full-subscription-main-publish-sync \
        ui-full-subscription-main-publish-sync-skip \
        ui-full-subscription-main-publish-sync-enable \
        ui-full-subscription-main-maintenance \
        ui-full-subscription-controlled \
        ui-full-core-maintenance \
        wireguard-menu-flow-bootstrap \
        wireguard-menu-flow-peer-add-update \
        wireguard-menu-flow-peer-rollback-apply-service \
        wireguard-menu-flow-peer-rollback-apply-restore \
        wireguard-menu-flow-peer-rollback-source \
        wireguard-menu-flow-peer-rollback-credential-write \
        wireguard-menu-flow-peer-rollback-credential-groups-restore \
        wireguard-menu-flow-peer-source-control-toggle \
        wireguard-menu-flow-peer-source-control-clear-error \
        wireguard-menu-flow-peer-source-control-status \
        wireguard-menu-flow-control-restore \
        wireguard-restore-runner \
        regression-ui-parallel-composition \
        regression-ui-long-tail-split-composition; do
        [[ -z "${uiLeafLine}" || "|${uiLeafSelectors}|" != *"|${selector}|"* ]] || return 1
    done
}

runUiSelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/ui-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/ui-default-selectors.sorted.txt"
    local allProfileSelectorsFile="${TMP_DIR}/ui-all-profile-selectors.txt"
    local allProfileSortedFile="${TMP_DIR}/ui-all-profile-selectors.sorted.txt"
    local expectedDefaultSelectorsFile="${TMP_DIR}/ui-default-selectors.expected.txt"
    local expectedAllProfileSelectorsFile="${TMP_DIR}/ui-all-profile-selectors.expected.txt"

    declare -F listRegressionUiChildSelectors >/dev/null
    declare -F listRegressionUiAllProfileChildSelectors >/dev/null

    listRegressionUiChildSelectors >"${defaultSelectorsFile}"
    listRegressionUiAllProfileChildSelectors >"${allProfileSelectorsFile}"

    cat <<'EOF' >"${expectedDefaultSelectorsFile}"
ui-full-subscription-main-publish-sync-enable
wireguard-menu-flow-peer-rollback-apply-service
wireguard-menu-flow-peer-rollback-credential-write
wireguard-menu-flow-peer-rollback-source
ui-full-subscription-main-publish-sync-skip
wireguard-menu-flow-peer-rollback-apply-restore
wireguard-menu-flow-peer-rollback-credential-groups-restore
ui-full-subscription-main-publish-user-inspect
wireguard-menu-flow-peer-source-control-toggle
ui-full-subscription-main-publish-user-create
ui-full-subscription-main-publish-service
wireguard-menu-flow-peer-add-update
wireguard-menu-flow-peer-source-control-clear-error
wireguard-menu-flow-peer-source-control-status
ui-full-subscription-main-publish-user-empty
ui-full-subscription-main-maintenance
wireguard-menu-flow-control-restore
wireguard-menu-flow-bootstrap
ui-full-subscription-main-entry
ui-full-subscription-controlled
ui-full-core
ui-full-core-maintenance
ui-smoke
wireguard-restore-runner
EOF

    cat <<'EOF' >"${expectedAllProfileSelectorsFile}"
ui-full-subscription-main-publish-sync
wireguard-menu-flow-peer-rollback-apply
wireguard-menu-flow-peer-rollback-credential
wireguard-menu-flow-peer-rollback-source
ui-full-subscription-main-publish-user
ui-full-subscription-main-publish-service
wireguard-menu-flow-peer-add-update
wireguard-menu-flow-peer-source-control
ui-full-subscription-main-maintenance
wireguard-menu-flow-control-restore
wireguard-menu-flow-bootstrap
ui-full-subscription-main-entry
ui-full-subscription-controlled
ui-full-core
ui-full-core-maintenance
ui-smoke
wireguard-restore-runner
EOF

    cmp -s "${expectedDefaultSelectorsFile}" "${defaultSelectorsFile}"
    cmp -s "${expectedAllProfileSelectorsFile}" "${allProfileSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/ui-default-selectors.unique.txt"
    sort "${allProfileSelectorsFile}" >"${allProfileSortedFile}"
    sort -u "${allProfileSelectorsFile}" >"${TMP_DIR}/ui-all-profile-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/ui-default-selectors.unique.txt"
    cmp -s "${allProfileSortedFile}" "${TMP_DIR}/ui-all-profile-selectors.unique.txt"
)

runUiNestedAggregateRunnersUseSharedSuiteHelpersContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/ui.sh"
    local functionName

    grep -q '^runUiSelectorListRegression() {$' "${suiteFile}" || return 1
    grep -q '^runUiLeafSelectorListRegression() {$' "${suiteFile}" || return 1

    for functionName in \
        runRegressionMenuSmokeFull \
        runRegressionUiFullSubscriptionMain \
        runRegressionUiFullSubscriptionMainPublish \
        runRegressionWireGuardMenuFlow \
        runSubscriptionWireGuardMenuFlowPeerTransactionRegression \
        runSubscriptionWireGuardMenuFlowPeerRollbackRegression; do
        runContractHelperAdoptionAssertions \
            "${suiteFile}" \
            "${functionName}" \
            runUiSelectorListRegression || return 1
    done

    for functionName in \
        runRegressionUiFullSubscriptionMainPublishUser \
        runRegressionUiFullSubscriptionMainPublishSync \
        runSubscriptionWireGuardMenuFlowPeerRollbackApplyRegression \
        runSubscriptionWireGuardMenuFlowPeerRollbackCredentialRegression \
        runSubscriptionWireGuardMenuFlowPeerSourceControlRegression; do
        runContractHelperAdoptionAssertions \
            "${suiteFile}" \
            "${functionName}" \
            runUiLeafSelectorListRegression || return 1
    done
}

runUiLeavesUseCompatHelperContract() (
    local callLog="${TMP_DIR}/ui-compat-helper.log"

    : >"${callLog}"

    runRegressionUiLegacyLeafWithCompat() {
        printf '%s\n' "$1" >>"${callLog}"
    }

    for selector in \
        ui-full-core \
        ui-full-subscription-main-entry \
        ui-full-subscription-main-publish-service \
        ui-full-subscription-main-publish-user-empty \
        ui-full-subscription-main-publish-user-create \
        ui-full-subscription-main-publish-user-inspect \
        ui-full-subscription-main-publish-sync-skip \
        ui-full-subscription-main-publish-sync-enable \
        ui-full-subscription-main-maintenance \
        ui-full-subscription-controlled \
        ui-full-core-maintenance \
        wireguard-menu-flow-bootstrap \
        wireguard-menu-flow-peer-add-update \
        wireguard-menu-flow-peer-rollback-apply-service \
        wireguard-menu-flow-peer-rollback-apply-restore \
        wireguard-menu-flow-peer-rollback-source \
        wireguard-menu-flow-peer-rollback-credential-write \
        wireguard-menu-flow-peer-rollback-credential-groups-restore \
        wireguard-menu-flow-peer-source-control-toggle \
        wireguard-menu-flow-peer-source-control-clear-error \
        wireguard-menu-flow-peer-source-control-status \
        wireguard-menu-flow-control-restore \
        wireguard-restore-runner; do
        PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain "${selector}"
    done

    cat <<'EOF' >"${TMP_DIR}/ui-compat-helper.expected.log"
runMenuSmokeFullCoreRegression
runMenuSmokeFullSubscriptionMainEntryRegression
runMenuSmokeFullSubscriptionMainPublishServiceRegression
runMenuSmokeFullSubscriptionMainPublishUserEmptyRegression
runMenuSmokeFullSubscriptionMainPublishUserCreateRegression
runMenuSmokeFullSubscriptionMainPublishUserInspectRegression
runMenuSmokeFullSubscriptionMainPublishSyncSkipRegression
runMenuSmokeFullSubscriptionMainPublishSyncEnableRegression
runMenuSmokeFullSubscriptionMainMaintenanceRegression
runMenuSmokeFullSubscriptionControlledRegression
runMenuSmokeFullCoreMaintenanceRegression
runSubscriptionWireGuardMenuFlowBootstrapRegression
runSubscriptionWireGuardMenuFlowPeerAddUpdateRegression
runSubscriptionWireGuardMenuFlowPeerRollbackApplyServiceRegression
runSubscriptionWireGuardMenuFlowPeerRollbackApplyRestoreRegression
runSubscriptionWireGuardMenuFlowPeerRollbackSourceRegression
runSubscriptionWireGuardMenuFlowPeerRollbackCredentialWriteRegression
runSubscriptionWireGuardMenuFlowPeerRollbackCredentialGroupsRestoreRegression
runSubscriptionWireGuardMenuFlowPeerSourceControlToggleRegression
runSubscriptionWireGuardMenuFlowPeerSourceControlClearErrorRegression
runSubscriptionWireGuardMenuFlowPeerSourceControlStatusRegression
runSubscriptionWireGuardMenuFlowControlRestoreRegression
runSubscriptionWireGuardRestoreRunnerRegression
EOF

    cmp -s "${TMP_DIR}/ui-compat-helper.expected.log" "${callLog}"
)

runUiLegacyTmpDirIsolationGuardRegisteredContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/ui.sh"

    grep -q '^runRegressionUiLegacyTmpDirIsolationRegression() ($' "${suiteFile}" || return 1
    grep -q '^    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain ui-full-subscription-main-entry$' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf regression-ui-legacy-tmpdir-isolation runRegressionUiLegacyTmpDirIsolationRegression$' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionAggregateRunnerParallel ui .*regression-ui-legacy-tmpdir-isolation' "${suiteFile}" || return 1
}

runUiAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/ui.sh"
    local expectedChildren

    ! grep -q '^ui ui$' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf ui ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf menu-smoke ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf menu-smoke-full ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel ui runRegressionUiSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionUiChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        ui \
        parallel \
        runRegressionUiSuiteRoot \
        "${expectedChildren}"
    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui-smoke"]:-}" == "function" ]]
    [[ "${PADM_REGRESSION_SELECTOR_KIND["ui-full"]:-}" == "aggregate-runner" ]]
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["menu-smoke"]:-}" ]]
    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["menu-smoke-full"]:-}" ]]
}

runUiNestedAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/ui.sh"

    ! grep -q '^registerRegressionFunctionLeaf ui-full ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf ui-full-subscription-main ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf ui-full-subscription-main-publish ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf ui-full-subscription-main-publish-user ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf ui-full-subscription-main-publish-sync ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf wireguard-menu-flow ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf wireguard-menu-flow-peer-transaction ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-apply ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf wireguard-menu-flow-peer-rollback-credential ' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionFunctionLeaf wireguard-menu-flow-peer-source-control ' "${suiteFile}" || return 1

    grep -q '^registerRegressionAggregateRunnerParallel ui-full runRegressionMenuSmokeFull \\' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallel ui-full-subscription-main runRegressionUiFullSubscriptionMain \\' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallel ui-full-subscription-main-publish runRegressionUiFullSubscriptionMainPublish \\' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallel ui-full-subscription-main-publish-user runRegressionUiFullSubscriptionMainPublishUser \\' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallel ui-full-subscription-main-publish-sync runRegressionUiFullSubscriptionMainPublishSync \\' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallel wireguard-menu-flow runRegressionWireGuardMenuFlow \\' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallel wireguard-menu-flow-peer-transaction runSubscriptionWireGuardMenuFlowPeerTransactionRegression \\' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallel wireguard-menu-flow-peer-rollback runSubscriptionWireGuardMenuFlowPeerRollbackRegression \\' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallel wireguard-menu-flow-peer-rollback-apply runSubscriptionWireGuardMenuFlowPeerRollbackApplyRegression \\' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallel wireguard-menu-flow-peer-rollback-credential runSubscriptionWireGuardMenuFlowPeerRollbackCredentialRegression \\' "${suiteFile}" || return 1
    grep -q '^registerRegressionAggregateRunnerParallel wireguard-menu-flow-peer-source-control runSubscriptionWireGuardMenuFlowPeerSourceControlRegression \\' "${suiteFile}" || return 1

    runAggregateRunnerRegistrationAssertions \
        ui-full \
        parallel \
        runRegressionMenuSmokeFull \
        "$(listRegressionUiFullChildSelectors)"
    runAggregateRunnerRegistrationAssertions \
        ui-full-subscription-main \
        parallel \
        runRegressionUiFullSubscriptionMain \
        "$(listRegressionUiFullSubscriptionMainChildSelectors)"
    runAggregateRunnerRegistrationAssertions \
        ui-full-subscription-main-publish \
        parallel \
        runRegressionUiFullSubscriptionMainPublish \
        "$(listRegressionUiFullSubscriptionMainPublishChildSelectors)"
    runAggregateRunnerRegistrationAssertions \
        ui-full-subscription-main-publish-user \
        parallel \
        runRegressionUiFullSubscriptionMainPublishUser \
        "$(listRegressionUiFullSubscriptionMainPublishUserChildSelectors)"
    runAggregateRunnerRegistrationAssertions \
        ui-full-subscription-main-publish-sync \
        parallel \
        runRegressionUiFullSubscriptionMainPublishSync \
        "$(listRegressionUiFullSubscriptionMainPublishSyncChildSelectors)"
    runAggregateRunnerRegistrationAssertions \
        wireguard-menu-flow \
        parallel \
        runRegressionWireGuardMenuFlow \
        "$(listRegressionWireGuardMenuFlowChildSelectors)"
    runAggregateRunnerRegistrationAssertions \
        wireguard-menu-flow-peer-transaction \
        parallel \
        runSubscriptionWireGuardMenuFlowPeerTransactionRegression \
        "$(listRegressionWireGuardMenuFlowPeerTransactionChildSelectors)"
    runAggregateRunnerRegistrationAssertions \
        wireguard-menu-flow-peer-rollback \
        parallel \
        runSubscriptionWireGuardMenuFlowPeerRollbackRegression \
        "$(listRegressionWireGuardMenuFlowPeerRollbackChildSelectors)"
    runAggregateRunnerRegistrationAssertions \
        wireguard-menu-flow-peer-rollback-apply \
        parallel \
        runSubscriptionWireGuardMenuFlowPeerRollbackApplyRegression \
        "$(listRegressionWireGuardMenuFlowPeerRollbackApplyChildSelectors)"
    runAggregateRunnerRegistrationAssertions \
        wireguard-menu-flow-peer-rollback-credential \
        parallel \
        runSubscriptionWireGuardMenuFlowPeerRollbackCredentialRegression \
        "$(listRegressionWireGuardMenuFlowPeerRollbackCredentialChildSelectors)"
    runAggregateRunnerRegistrationAssertions \
        wireguard-menu-flow-peer-source-control \
        parallel \
        runSubscriptionWireGuardMenuFlowPeerSourceControlRegression \
        "$(listRegressionWireGuardMenuFlowPeerSourceControlChildSelectors)"
}

runUiAggregateRunnerUsesSuiteLocalHelperContract() (
    local callLog="${TMP_DIR}/ui-aggregate-suite-root-dispatch.log"

    runRegressionUi() {
        printf 'legacy-ui\n' >>"${callLog}"
        return 97
    }

    runRegressionUiSuiteRoot() {
        printf 'suite-ui\n' >>"${callLog}"
    }

    runAggregateRunnerUsesSuiteLocalHelperAssertions ui "${callLog}" 'suite-ui' 'legacy-ui'
)

runUiAggregateRunnerUsesFrameworkSelectorHelperContract() (
    local callLog="${TMP_DIR}/ui-framework-helper-dispatch.log"

    listRegressionUiChildSelectors() {
        printf '%s\n' \
            ui-smoke \
            ui-full-core
    }

    listRegressionUiAllProfileChildSelectors() {
        printf '%s\n' \
            ui-smoke \
            wireguard-restore-runner
    }

    runFrameworkParallelRegressionSelectorList() {
        local orchestrationRoot=$1
        local selectorListFn=$2
        shift 2
        local -a selectors=()

        mapfile -t selectors < <("${selectorListFn}" "$@")
        printf 'framework:list:%s:%s:%s\n' \
            "${orchestrationRoot}" \
            "${selectorListFn}" \
            "${selectors[*]}" >>"${callLog}"
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:selectors:%s\n' "$*" >>"${callLog}"
        return 97
    }

    runParallelRegressionSelectors() {
        printf 'legacy-helper:%s\n' "$*" >>"${callLog}"
        return 97
    }

    listRegressionUiFullSubscriptionMainChildSelectors() {
        printf '%s\n' \
            ui-full-subscription-main-entry \
            ui-full-subscription-main-publish-service \
            ui-full-subscription-main-publish-user \
            ui-full-subscription-main-publish-sync \
            ui-full-subscription-main-maintenance
    }

    listRegressionUiFullSubscriptionMainPublishChildSelectors() {
        printf '%s\n' \
            ui-full-subscription-main-publish-service \
            ui-full-subscription-main-publish-user \
            ui-full-subscription-main-publish-sync
    }

    listRegressionUiFullSubscriptionMainPublishUserChildSelectors() {
        printf '%s\n' \
            ui-full-subscription-main-publish-user-empty \
            ui-full-subscription-main-publish-user-create \
            ui-full-subscription-main-publish-user-inspect
    }

    listRegressionUiFullSubscriptionMainPublishSyncChildSelectors() {
        printf '%s\n' \
            ui-full-subscription-main-publish-sync-skip \
            ui-full-subscription-main-publish-sync-enable
    }

    runUiAggregateRunnerUsesFrameworkSelectorHelperRunner() {
        runRegressionUiSuiteRoot
        PADM_REGRESSION_UI_RESOURCE_PROFILE=all runRegressionUiSuiteRoot
        runRegressionUiFullSubscriptionMain
        runRegressionUiFullSubscriptionMainPublish
        runRegressionUiFullSubscriptionMainPublishUser
        runRegressionUiFullSubscriptionMainPublishSync
    }

    runAggregateRunnerUsesFrameworkSelectorHelperMultiLineAssertions \
        "${callLog}" \
        runUiAggregateRunnerUsesFrameworkSelectorHelperRunner \
        'framework:list:'"${TMP_DIR}"'/ui-parallel-[0-9][0-9]*:listRegressionUiChildSelectors:ui-smoke ui-full-core' \
        'framework:list:'"${TMP_DIR}"'/ui-parallel-[0-9][0-9]*:listRegressionUiAllProfileChildSelectors:ui-smoke wireguard-restore-runner' \
        'framework:list:'"${TMP_DIR}"'/ui-full-subscription-main-parallel-[0-9][0-9]*:listRegressionUiFullSubscriptionMainChildSelectors:ui-full-subscription-main-entry ui-full-subscription-main-publish-service ui-full-subscription-main-publish-user ui-full-subscription-main-publish-sync ui-full-subscription-main-maintenance' \
        'framework:list:'"${TMP_DIR}"'/ui-full-subscription-main-publish-parallel-[0-9][0-9]*:listRegressionUiFullSubscriptionMainPublishChildSelectors:ui-full-subscription-main-publish-service ui-full-subscription-main-publish-user ui-full-subscription-main-publish-sync' \
        'framework:list:'"${TMP_DIR}"'/ui-full-subscription-main-publish-user-parallel-[0-9][0-9]*:listRegressionUiFullSubscriptionMainPublishUserChildSelectors:ui-full-subscription-main-publish-user-empty ui-full-subscription-main-publish-user-create ui-full-subscription-main-publish-user-inspect' \
        'framework:list:'"${TMP_DIR}"'/ui-full-subscription-main-publish-sync-parallel-[0-9][0-9]*:listRegressionUiFullSubscriptionMainPublishSyncChildSelectors:ui-full-subscription-main-publish-sync-skip ui-full-subscription-main-publish-sync-enable'
)

runRoutingLegacyPublicSelectorRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/routing.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local routingLeafLine

    grep -q '^registerRegressionAggregateRunnerParallel routing runRegressionRoutingSuiteRoot \\' "${suiteFile}" || return 1

    routingLeafLine=$(grep -F 'routing leaf selectors: ' "${legacyScriptFile}" || true)
    [[ -z "${routingLeafLine}" ]] || return 1

    runLegacyPublicSelectorRetirementAssertions "${legacyScriptFile}" \
        routing \
        routing-core \
        routing-core-unsafe-config-dir \
        routing-socks5-udp-associate \
        routing-access-control-config-transaction \
        routing-access-control-unsafe-backup-dir \
        routing-access-control-unsafe-config-dir \
        routing-access-control-failure-return \
        routing-bt-failure-return \
        routing-ipv6-failure-return \
        routing-warp-failure-return \
        routing-socks5-failure-return \
        routing-dns-failure-return \
        routing-dns-unsafe-backup-dir \
        routing-dns-unsafe-config-dir \
        routing-dns-restore-scope \
        routing-port-panel \
        regression-routing-parallel-composition
}

runRoutingSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/routing.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local status=0

    grep -q 'source "\${REGRESSION_ROUTING_SUITE_DIR}/../framework/runtime.sh"' "${suiteFile}" || status=1
    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_ROUTING_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}" || status=1
    grep -q '^listRegressionRoutingCoreChildSelectors() {$' "${suiteFile}" || status=1
    grep -q '^listRegressionRoutingHeavyChildSelectors() {$' "${suiteFile}" || status=1
    grep -q '^listRegressionRoutingLightChildSelectors() {$' "${suiteFile}" || status=1
    grep -q '^listRegressionRoutingChildSelectors() {$' "${suiteFile}" || status=1
    grep -q '^runRegressionRoutingSuiteRoot() {$' "${suiteFile}" || status=1
    grep -q '^runRegressionRoutingParallelCompositionRegression() ' "${suiteFile}" || status=1
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/routing-parallel-' "${suiteFile}" || status=1
    ! grep -q '^listRegressionRoutingCoreChildSelectors() {$' "${legacyScriptFile}" || status=1
    ! grep -q '^listRegressionRoutingHeavyChildSelectors() {$' "${legacyScriptFile}" || status=1
    ! grep -q '^listRegressionRoutingLightChildSelectors() {$' "${legacyScriptFile}" || status=1
    ! grep -q '^listRegressionRoutingChildSelectors() {$' "${legacyScriptFile}" || status=1
    ! grep -q '^runRegressionRouting() {$' "${legacyScriptFile}" || status=1
    ! grep -q '^runRegressionRoutingParallelCompositionRegression() ' "${legacyScriptFile}" || status=1
    ! grep -q '^registerRegressionScriptLeaf routing ' "${suiteFile}" || status=1
    ! grep -q '^registerRegressionFunctionLeaf routing ' "${suiteFile}" || status=1
    grep -q '^registerRegressionAggregateRunnerParallel routing runRegressionRoutingSuiteRoot \\' "${suiteFile}" || status=1

    while read -r selector helper regression; do
        ! grep -q "^registerRegressionScriptLeaf ${selector} " "${suiteFile}" || status=1
        grep -q "^registerRegressionFunctionLeaf ${selector} ${helper} ${regression}\$" "${suiteFile}" || status=1
    done <<'EOF'
routing-socks5-udp-associate runRegressionRoutingLegacyLeafWithCompat runSocks5UdpAssociateRegression
routing-core runRegressionRoutingLegacyLeafWithCompat runRoutingRegression
routing-core-unsafe-config-dir runRegressionRoutingLegacyLeafWithCompat runRoutingCoreRejectsUnsafeConfigDirRegression
routing-access-control-config-transaction runRegressionRoutingLegacyLeafWithCompat runAccessControlConfigTransactionRegression
routing-access-control-unsafe-backup-dir runRegressionRoutingLegacyLeafWithCompat runAccessControlRejectsUnsafeBackupDirRegression
routing-access-control-unsafe-config-dir runRegressionRoutingLegacyLeafWithCompat runAccessControlRejectsUnsafeConfigDirRegression
routing-access-control-failure-return runRegressionRoutingLegacyLeafWithCompat runAccessControlFailureReturnRegression
routing-bt-failure-return runRegressionRoutingLegacyLeafWithCompat runBTRoutingFailureReturnRegression
routing-ipv6-failure-return runRegressionRoutingLegacyLeafWithCompat runIPv6RoutingFailureReturnRegression
routing-warp-failure-return runRegressionRoutingLegacyLeafWithCompat runWARPRoutingFailureReturnRegression
routing-socks5-failure-return runRegressionRoutingLegacyLeafWithCompat runSocks5RoutingFailureReturnRegression
routing-dns-failure-return runRegressionRoutingLegacyLeafWithCompat runDNSRoutingFailureReturnRegression
routing-dns-unsafe-backup-dir runRegressionRoutingLegacyLeafWithCompat runDNSRoutingRejectsUnsafeBackupDirRegression
routing-dns-unsafe-config-dir runRegressionRoutingLegacyLeafWithCompat runDNSRoutingRejectsUnsafeConfigDirRegression
routing-dns-restore-scope runRegressionRoutingLegacyLeafWithCompat runDNSRoutingRestoreKeepsUnmanagedSingBoxFilesRegression
routing-port-panel runRegressionRoutingLegacyLeafWithCompat runPortAndPanelHelperRegression
EOF

    return "${status}"
}

runRoutingSelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/routing-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/routing-default-selectors.sorted.txt"
    local waveSelectorsFile="${TMP_DIR}/routing-wave-selectors.txt"
    local waveSortedFile="${TMP_DIR}/routing-wave-selectors.sorted.txt"

    declare -F listRegressionRoutingChildSelectors >/dev/null
    declare -F listRegressionRoutingCoreChildSelectors >/dev/null
    declare -F listRegressionRoutingHeavyChildSelectors >/dev/null
    declare -F listRegressionRoutingLightChildSelectors >/dev/null

    listRegressionRoutingChildSelectors >"${defaultSelectorsFile}"
    {
        listRegressionRoutingCoreChildSelectors
        listRegressionRoutingHeavyChildSelectors
        listRegressionRoutingLightChildSelectors
    } >"${waveSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/routing-default-selectors.unique.txt"
    sort "${waveSelectorsFile}" >"${waveSortedFile}"
    sort -u "${waveSelectorsFile}" >"${TMP_DIR}/routing-wave-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/routing-default-selectors.unique.txt"
    cmp -s "${waveSortedFile}" "${TMP_DIR}/routing-wave-selectors.unique.txt"
    cmp -s "${TMP_DIR}/routing-default-selectors.unique.txt" "${TMP_DIR}/routing-wave-selectors.unique.txt"
)

runRoutingAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/routing.sh"
    local expectedChildren

    ! grep -q '^registerRegressionScriptLeaf routing ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf routing ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel routing runRegressionRoutingSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionRoutingChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        routing \
        parallel \
        runRegressionRoutingSuiteRoot \
        "${expectedChildren}"
}

runRoutingAggregateRunnerUsesSuiteLocalHelperContract() (
    local callLog="${TMP_DIR}/routing-aggregate-suite-root-dispatch.log"

    runRegressionRouting() {
        printf 'legacy-routing\n' >>"${callLog}"
        return 97
    }

    runRegressionRoutingSuiteRoot() {
        printf 'suite-routing\n' >>"${callLog}"
    }

    runAggregateRunnerUsesSuiteLocalHelperAssertions routing "${callLog}" 'suite-routing' 'legacy-routing'
)

runRoutingAggregateRunnerUsesFrameworkSelectorHelperContract() (
    local callLog="${TMP_DIR}/routing-framework-helper-dispatch.log"

    listRegressionRoutingChildSelectors() {
        printf '%s\n' \
            routing-core \
            routing-port-panel
    }

    listRegressionRoutingCoreChildSelectors() {
        printf '%s\n' \
            routing-core
    }

    listRegressionRoutingHeavyChildSelectors() {
        printf '%s\n' \
            routing-access-control-config-transaction \
            routing-dns-failure-return
    }

    listRegressionRoutingLightChildSelectors() {
        printf '%s\n' \
            routing-port-panel \
            routing-core-unsafe-config-dir
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:jobs=%s:%s\n' "${PADM_REGRESSION_PARALLEL_JOBS:-}" "$*" >>"${callLog}"
    }

    runParallelRegressionSelectors() {
        printf 'legacy-helper:%s\n' "$*" >>"${callLog}"
        return 97
    }

    runRoutingAggregateRunnerUsesFrameworkSelectorHelperRunner() {
        runRegressionRoutingSuiteRoot
        PADM_REGRESSION_ROUTING_RESOURCE_PROFILE=all runRegressionRoutingSuiteRoot
    }

    runAggregateRunnerUsesFrameworkSelectorHelperMultiLineAssertions \
        "${callLog}" \
        runRoutingAggregateRunnerUsesFrameworkSelectorHelperRunner \
        'framework:jobs='"${PADM_REGRESSION_ROUTING_PARALLEL_JOBS:-4}"':'"${TMP_DIR}"'/routing-parallel-[0-9][0-9]* routing-core routing-core routing-port-panel routing-port-panel' \
        'framework:jobs=:'"${TMP_DIR}"'/routing-parallel-core-[0-9][0-9]* routing-core routing-core' \
        'framework:jobs='"${PADM_REGRESSION_ROUTING_WAVE_PARALLEL_JOBS:-2}"':'"${TMP_DIR}"'/routing-parallel-heavy-[0-9][0-9]* routing-access-control-config-transaction routing-access-control-config-transaction routing-dns-failure-return routing-dns-failure-return' \
        'framework:jobs='"${PADM_REGRESSION_ROUTING_LIGHT_PARALLEL_JOBS:-${PADM_REGRESSION_ROUTING_WAVE_PARALLEL_JOBS:-4}}"':'"${TMP_DIR}"'/routing-parallel-light-[0-9][0-9]* routing-port-panel routing-port-panel routing-core-unsafe-config-dir routing-core-unsafe-config-dir'
)

runRoutingLegacyLeavesUseCompatHelperContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/routing.sh"
    local status=0

    while read -r selector helper regression; do
        grep -q "^registerRegressionFunctionLeaf ${selector} ${helper} ${regression}\$" "${suiteFile}" || status=1
    done <<'EOF'
routing-socks5-udp-associate runRegressionRoutingLegacyLeafWithCompat runSocks5UdpAssociateRegression
routing-core runRegressionRoutingLegacyLeafWithCompat runRoutingRegression
routing-core-unsafe-config-dir runRegressionRoutingLegacyLeafWithCompat runRoutingCoreRejectsUnsafeConfigDirRegression
routing-access-control-config-transaction runRegressionRoutingLegacyLeafWithCompat runAccessControlConfigTransactionRegression
routing-access-control-unsafe-backup-dir runRegressionRoutingLegacyLeafWithCompat runAccessControlRejectsUnsafeBackupDirRegression
routing-access-control-unsafe-config-dir runRegressionRoutingLegacyLeafWithCompat runAccessControlRejectsUnsafeConfigDirRegression
routing-access-control-failure-return runRegressionRoutingLegacyLeafWithCompat runAccessControlFailureReturnRegression
routing-bt-failure-return runRegressionRoutingLegacyLeafWithCompat runBTRoutingFailureReturnRegression
routing-ipv6-failure-return runRegressionRoutingLegacyLeafWithCompat runIPv6RoutingFailureReturnRegression
routing-warp-failure-return runRegressionRoutingLegacyLeafWithCompat runWARPRoutingFailureReturnRegression
routing-socks5-failure-return runRegressionRoutingLegacyLeafWithCompat runSocks5RoutingFailureReturnRegression
routing-dns-failure-return runRegressionRoutingLegacyLeafWithCompat runDNSRoutingFailureReturnRegression
routing-dns-unsafe-backup-dir runRegressionRoutingLegacyLeafWithCompat runDNSRoutingRejectsUnsafeBackupDirRegression
routing-dns-unsafe-config-dir runRegressionRoutingLegacyLeafWithCompat runDNSRoutingRejectsUnsafeConfigDirRegression
routing-dns-restore-scope runRegressionRoutingLegacyLeafWithCompat runDNSRoutingRestoreKeepsUnmanagedSingBoxFilesRegression
routing-port-panel runRegressionRoutingLegacyLeafWithCompat runPortAndPanelHelperRegression
EOF

    return "${status}"
}

runRoutingNoCompatWrapperFunctionsContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/routing.sh"
    local status=0

    while read -r wrapperName; do
        ! grep -q "^${wrapperName}() { runRegressionRoutingLegacyLeafWithCompat " "${suiteFile}" || status=1
    done <<'EOF'
runRoutingCoreCompatRegression
runRoutingCoreUnsafeConfigDirCompatRegression
runRoutingSocks5UdpAssociateCompatRegression
runRoutingAccessControlFailureReturnCompatRegression
runRoutingAccessControlConfigTransactionCompatRegression
runRoutingAccessControlUnsafeBackupDirCompatRegression
runRoutingAccessControlUnsafeConfigDirCompatRegression
runRoutingBTFailureReturnCompatRegression
runRoutingIPv6FailureReturnCompatRegression
runRoutingWarpFailureReturnCompatRegression
runRoutingSocks5FailureReturnCompatRegression
runRoutingDNSFailureReturnCompatRegression
runRoutingDNSUnsafeBackupDirCompatRegression
runRoutingDNSUnsafeConfigDirCompatRegression
runRoutingDNSRestoreScopeCompatRegression
runRoutingPortPanelCompatRegression
EOF

    return "${status}"
}

runRoutingLegacyReadInstallTypeIsolationGuardRegisteredContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/routing.sh"

    grep -q '^runRegressionRoutingLegacyReadInstallTypeIsolationRegression() ($' "${suiteFile}" || return 1
    grep -q '^    runRegressionRoutingLegacyLeafWithCompat runRegressionRoutingLegacyReadInstallTypeIsolationProbe$' "${suiteFile}" || return 1
    grep -q '^runRegressionRoutingLegacyReadInstallTypeIsolationProbe() {$' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf regression-routing-legacy-read-install-type-isolation runRegressionRoutingLegacyReadInstallTypeIsolationRegression$' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionAggregateRunnerParallel routing .*regression-routing-legacy-read-install-type-isolation' "${suiteFile}" || return 1
}

runTransactionLegacyTmpDirIsolationGuardRegisteredContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"

    grep -q '^runRegressionTransactionLegacyTmpDirIsolationRegression() ($' "${suiteFile}" || return 1
    grep -q '^    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain subscribe-user-output-transaction$' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf regression-transaction-legacy-tmpdir-isolation runRegressionTransactionLegacyTmpDirIsolationRegression$' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionAggregateRunnerSequential transaction .*regression-transaction-legacy-tmpdir-isolation' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionAggregateRunnerSequential transaction-subscription .*regression-transaction-legacy-tmpdir-isolation' "${suiteFile}" || return 1
}

runTransactionCoreSelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/transaction-core-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/transaction-core-default-selectors.sorted.txt"
    local waveSelectorsFile="${TMP_DIR}/transaction-core-wave-selectors.txt"
    local waveSortedFile="${TMP_DIR}/transaction-core-wave-selectors.sorted.txt"

    declare -F listRegressionTransactionCoreChildSelectors >/dev/null
    declare -F listRegressionTransactionCoreHeavyChildSelectors >/dev/null
    declare -F listRegressionTransactionCoreMediumChildSelectors >/dev/null
    declare -F listRegressionTransactionCoreLightChildSelectors >/dev/null

    listRegressionTransactionCoreChildSelectors >"${defaultSelectorsFile}"
    {
        listRegressionTransactionCoreHeavyChildSelectors
        listRegressionTransactionCoreMediumChildSelectors
        listRegressionTransactionCoreLightChildSelectors
    } >"${waveSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/transaction-core-default-selectors.unique.txt"
    sort "${waveSelectorsFile}" >"${waveSortedFile}"
    sort -u "${waveSelectorsFile}" >"${TMP_DIR}/transaction-core-wave-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/transaction-core-default-selectors.unique.txt"
    cmp -s "${waveSortedFile}" "${TMP_DIR}/transaction-core-wave-selectors.unique.txt"
    cmp -s "${TMP_DIR}/transaction-core-default-selectors.unique.txt" "${TMP_DIR}/transaction-core-wave-selectors.unique.txt"
)

runTransactionCoreRegisteredChildSelectorsAlignedContract() (
    runRegisteredChildSelectorsAlignedAssertions \
        listRegressionTransactionCoreChildSelectors \
        "${TMP_DIR}/transaction-core-registered-child-selectors" <<'EOF'
core-rollback-result-message
config-transaction
core-port-file-transaction
core-port-unsafe-config-dir
entry-helper-config
check-port-open-nginx-directory-target
alone-nginx-directory-target
xray-reality-port-failure
reality-profile-failure
sing-box-reality-key-transaction
core-template-return-failure
core-template-managed-remove
core-binary-install-copy-failure
sing-box-cronet-rollback
finalize-sing-box-rollback
core-upgrade-directory-target
legacy-core-upgrade-keeps-existing
core-first-install-failure-clean
core-first-install-commit-rollback
core-install-unsafe-binary-path
sing-box-download-artifacts-cleanup
network-check-return-failure
tls-failure-return
tls-reinstall-rollback
tls-renew-failure-propagation
service-queue-apply-propagation
core-install-service-action-failure
sing-box-merge-start-failure
sing-box-merge-config-transaction
sing-box-uninstall-failure-propagation
sing-box-uninstall-rejects-unsafe-config-path
sing-box-managed-cleanup
sing-box-protocol-reload-failure
geo-update-reload-failure
core-cleanup-failure-propagation
reload-core-propagation
sing-box-log-transaction
user-config-write
remove-user
EOF
)

runTransactionCoreAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
    local expectedChildren

    ! grep -q '^registerRegressionScriptLeaf transaction-core ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction-core ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel transaction-core runRegressionTransactionCoreSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionTransactionCoreChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        transaction-core \
        parallel \
        runRegressionTransactionCoreSuiteRoot \
        "${expectedChildren}"
}

runTransactionSelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/transaction-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/transaction-default-selectors.sorted.txt"
    local expectedDefaultSelectorsFile="${TMP_DIR}/transaction-default-selectors.expected.txt"
    local systemSelectorsFile="${TMP_DIR}/transaction-system-selectors.txt"
    local systemSortedFile="${TMP_DIR}/transaction-system-selectors.sorted.txt"

    declare -F listRegressionTransactionChildSelectors >/dev/null
    declare -F listRegressionTransactionSystemChildSelectors >/dev/null

    listRegressionTransactionChildSelectors >"${defaultSelectorsFile}"
    listRegressionTransactionSystemChildSelectors >"${systemSelectorsFile}"

    cat <<'EOF' >"${expectedDefaultSelectorsFile}"
transaction-core
transaction-subscription
transaction-system
EOF

    cmp -s "${expectedDefaultSelectorsFile}" "${defaultSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/transaction-default-selectors.unique.txt"
    sort "${systemSelectorsFile}" >"${systemSortedFile}"
    sort -u "${systemSelectorsFile}" >"${TMP_DIR}/transaction-system-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/transaction-default-selectors.unique.txt"
    cmp -s "${systemSortedFile}" "${TMP_DIR}/transaction-system-selectors.unique.txt"
)

runTransactionSubscriptionRegisteredChildSelectorsAlignedContract() (
    runRegisteredChildSelectorsAlignedAssertions \
        listRegressionTransactionSubscriptionChildSelectors \
        "${TMP_DIR}/transaction-subscription-registered-child-selectors" <<'EOF'
cdn-address-write-transaction
subscribe-server-name
subscribe-nginx-config-write
subscribe-nginx-service-failure
subscribe-salt-write-transaction
subscribe-user-output-transaction
remove-user-subscription-menu-failure
user-subscription-menu-mutation-failure
remote-subscribe-fetch
EOF
)

runTransactionAggregateRunnerRegistrationContract() (
    set -euo pipefail
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
    local expectedChildren

    ! grep -q '^registerRegressionScriptLeaf transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateSequential transaction \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequentialWithArgs \\' "${suiteFile}"
    expectedChildren=$(listRegressionTransactionChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        transaction \
        sequential \
        runFrameworkSequentialRegressionSelectorList \
        "${expectedChildren}"
    runAggregateRunnerRunnerArgsAssertions transaction 'listRegressionTransactionChildSelectors'
)

runTransactionSubscriptionAggregateRunnerRegistrationContract() (
    set -euo pipefail
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
    local expectedChildren

    ! grep -q '^registerRegressionScriptLeaf transaction-subscription ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction-subscription ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateSequential transaction-subscription \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequentialWithArgs \\' "${suiteFile}"
    expectedChildren=$(listRegressionTransactionSubscriptionChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        transaction-subscription \
        sequential \
        runFrameworkSequentialRegressionSelectorList \
        "${expectedChildren}"
    runAggregateRunnerRunnerArgsAssertions transaction-subscription 'listRegressionTransactionSubscriptionChildSelectors'
)

runTransactionSystemAggregateRunnerRegistrationContract() (
    set -euo pipefail
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
    local expectedChildren

    ! grep -q '^registerRegressionScriptLeaf transaction-system ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction-system ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateParallel transaction-system \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel transaction-system runRegressionTransactionSystemSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionTransactionSystemChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        transaction-system \
        parallel \
        runRegressionTransactionSystemSuiteRoot \
        "${expectedChildren}"
)

runTransactionSuiteUsesFunctionRegistryContract() (
    set -euo pipefail
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q 'source "\${REGRESSION_TRANSACTION_SUITE_DIR}/../framework/runtime.sh"' "${suiteFile}"
    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_TRANSACTION_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    grep -q '^listRegressionTransactionChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionTransactionSubscriptionChildSelectors() {$' "${suiteFile}"
    ! grep -q '^runRegressionTransactionSubscriptionSuiteRoot() {$' "${suiteFile}"
    grep -q '^listRegressionTransactionCoreSelectorEntries() {$' "${suiteFile}"
    grep -q '^listRegressionTransactionCoreSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionTransactionCoreChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionTransactionCoreHeavyChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionTransactionCoreMediumChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionTransactionCoreLightChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionTransactionSystemChildSelectors() {$' "${suiteFile}"
    ! grep -q '^runRegressionTransactionSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionTransactionCoreSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionTransactionSystemSuiteRoot() {$' "${suiteFile}"
    ! grep -q '^runRegressionTransactionSubscription() {$' "${suiteFile}"
    grep -q '^runRegressionTransactionCoreParallelCompositionRegression() ' "${suiteFile}"
    grep -q '^runRegressionTransactionSystemParallelCompositionRegression() ' "${suiteFile}"
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/transaction-core-parallel-' "${suiteFile}"
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/transaction-system-parallel-' "${suiteFile}"
    ! grep -q '^runRegressionTransactionCore() {$' "${legacyScriptFile}"
    ! grep -q '^runRegressionTransactionSubscription() {$' "${legacyScriptFile}"
    ! grep -q '^runRegressionTransactionSubscriptionSuiteRoot() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionTransactionCoreSelectorEntries() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionTransactionCoreSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionTransactionCoreChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionTransactionCoreHeavyChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionTransactionCoreMediumChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionTransactionCoreLightChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionTransactionSubscriptionChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionTransactionSystemChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^runRegressionTransactionSystem() {$' "${legacyScriptFile}"
    ! grep -q '^runRegressionTransactionCoreParallelCompositionRegression() ' "${legacyScriptFile}"
    ! grep -q '^runRegressionTransactionSystemParallelCompositionRegression() ' "${legacyScriptFile}"
    ! grep -q '^runRegressionTransaction() {$' "${legacyScriptFile}"
    ! grep -q '^registerRegressionScriptLeaf transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf transaction-core ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction-core ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf transaction-subscription ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction-subscription ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf transaction-system ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf transaction-system ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel transaction-core runRegressionTransactionCoreSuiteRoot \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequentialWithArgs \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel transaction-system runRegressionTransactionSystemSuiteRoot \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequentialWithArgs \\' "${suiteFile}"
)

runTransactionNoEmptyAggregateWrapperFunctionsContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    ! grep -q '^runRegressionTransactionSubscription() {$' "${suiteFile}" || return 1
    ! grep -q '^runRegressionTransactionSubscriptionSuiteRoot() {$' "${suiteFile}" || return 1
    ! grep -q '^runRegressionTransactionSuiteRoot() {$' "${suiteFile}" || return 1
    ! grep -q '^runRegressionTransactionSubscription() {$' "${legacyScriptFile}" || return 1
}

runTransactionLegacyPublicSelectorRetirementContract() (
    set -euo pipefail
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local selector
    local -a selectors=()

    while read -r selector; do
        [[ -n "${selector}" ]] || continue
        selectors+=("${selector}")
    done < <(
        awk '
            /^registerRegressionFunctionLeaf / { print $2 }
            /^registerRegressionAggregateRunnerSequential / { print $2 }
            /^registerRegressionAggregateRunnerParallel / { print $2 }
        ' "${suiteFile}"
    )

    runLegacyPublicSelectorRetirementAssertions "${legacyScriptFile}" "${selectors[@]}"
)

runTransactionSequentialAggregatesUseFrameworkSelectorHelperArgsContract() {
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["transaction"]:-}" == "runFrameworkSequentialRegressionSelectorList" ]] || return 1
    [[ "${PADM_REGRESSION_SELECTOR_RUNNER["transaction-subscription"]:-}" == "runFrameworkSequentialRegressionSelectorList" ]] || return 1
    runAggregateRunnerRunnerArgsAssertions transaction 'listRegressionTransactionChildSelectors'
    runAggregateRunnerRunnerArgsAssertions transaction-subscription 'listRegressionTransactionSubscriptionChildSelectors'
}

runTransactionCoreAggregateRunnerUsesFrameworkSelectorHelperContract() (
    local callLog="${TMP_DIR}/transaction-core-framework-helper-dispatch.log"

    listRegressionTransactionCoreChildSelectors() {
        printf '%s\n' \
            core-rollback-result-message \
            config-transaction
    }

    listRegressionTransactionCoreHeavyChildSelectors() {
        printf '%s\n' \
            core-install-service-action-failure \
            core-port-file-transaction
    }

    listRegressionTransactionCoreMediumChildSelectors() {
        printf '%s\n' \
            config-transaction \
            entry-helper-config
    }

    listRegressionTransactionCoreLightChildSelectors() {
        printf '%s\n' \
            core-rollback-result-message \
            service-queue-apply-propagation
    }

    runFrameworkParallelRegressionSelectorList() {
        local orchestrationRoot=$1
        local selectorListFn=$2
        shift 2
        local -a selectors=()

        mapfile -t selectors < <("${selectorListFn}" "$@")
        printf 'framework:list:jobs=%s:%s:%s:%s\n' \
            "${PADM_REGRESSION_PARALLEL_JOBS:-}" \
            "${orchestrationRoot}" \
            "${selectorListFn}" \
            "${selectors[*]}" >>"${callLog}"
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:selectors:%s\n' "$*" >>"${callLog}"
        return 97
    }

    runParallelRegressionSelectors() {
        printf 'legacy-helper:%s\n' "$*" >>"${callLog}"
        return 97
    }

    runTransactionCoreAggregateRunnerUsesFrameworkSelectorHelperRunner() {
        runRegressionTransactionCoreSuiteRoot
        PADM_REGRESSION_TRANSACTION_CORE_RESOURCE_PROFILE=all runRegressionTransactionCoreSuiteRoot
    }

    runAggregateRunnerUsesFrameworkSelectorHelperMultiLineAssertions \
        "${callLog}" \
        runTransactionCoreAggregateRunnerUsesFrameworkSelectorHelperRunner \
        'framework:list:jobs=:'"${TMP_DIR}"'/transaction-core-parallel-[0-9][0-9]*:listRegressionTransactionCoreChildSelectors:core-rollback-result-message config-transaction' \
        'framework:list:jobs='"${PADM_REGRESSION_TRANSACTION_CORE_HEAVY_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-2}}"':'"${TMP_DIR}"'/transaction-core-parallel-heavy-[0-9][0-9]*:listRegressionTransactionCoreHeavyChildSelectors:core-install-service-action-failure core-port-file-transaction' \
        'framework:list:jobs='"${PADM_REGRESSION_TRANSACTION_CORE_MEDIUM_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-3}}"':'"${TMP_DIR}"'/transaction-core-parallel-medium-[0-9][0-9]*:listRegressionTransactionCoreMediumChildSelectors:config-transaction entry-helper-config' \
        'framework:list:jobs='"${PADM_REGRESSION_TRANSACTION_CORE_LIGHT_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}"':'"${TMP_DIR}"'/transaction-core-parallel-light-[0-9][0-9]*:listRegressionTransactionCoreLightChildSelectors:core-rollback-result-message service-queue-apply-propagation'
)

runTransactionAggregateRunnerUsesFrameworkSelectorHelperContract() (
    local callLog="${TMP_DIR}/transaction-framework-helper-dispatch.log"

    listRegressionTransactionSystemChildSelectors() {
        printf '%s\n' \
            nginx-service-failure \
            fail2ban-apply-transaction
    }

    runFrameworkParallelRegressionSelectorList() {
        local orchestrationRoot=$1
        local selectorListFn=$2
        shift 2
        local -a selectors=()

        mapfile -t selectors < <("${selectorListFn}" "$@")
        printf 'framework:list:jobs=%s:%s:%s:%s\n' \
            "${PADM_REGRESSION_PARALLEL_JOBS:-}" \
            "${orchestrationRoot}" \
            "${selectorListFn}" \
            "${selectors[*]}" >>"${callLog}"
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:selectors:%s\n' "$*" >>"${callLog}"
        return 97
    }

    runParallelRegressionSelectors() {
        printf 'legacy-helper:%s\n' "$*" >>"${callLog}"
        return 97
    }

    runAggregateRunnerUsesFrameworkSelectorHelperAssertions \
        "${callLog}" \
        'framework:list:jobs='"${PADM_REGRESSION_TRANSACTION_SYSTEM_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}"':'"${TMP_DIR}"'/transaction-system-parallel-[0-9][0-9]*:listRegressionTransactionSystemChildSelectors:nginx-service-failure fail2ban-apply-transaction' \
        runRegressionTransactionSystemSuiteRoot
)

runAllSelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/all-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/all-default-selectors.sorted.txt"
    local expectedDefaultSelectorsFile="${TMP_DIR}/all-default-selectors.expected.txt"
    local parallelSelectorsFile="${TMP_DIR}/all-parallel-selectors.txt"
    local parallelExpectedFile="${TMP_DIR}/all-parallel-selectors.expected.txt"

    declare -F listRegressionAllChildSelectors >/dev/null
    declare -F listRegressionAllParallelChildSelectors >/dev/null

    listRegressionAllChildSelectors >"${defaultSelectorsFile}"
    listRegressionAllParallelChildSelectors >"${parallelSelectorsFile}"

    cat <<'EOF' >"${expectedDefaultSelectorsFile}"
routing
subscription
runtime
transaction
remote-control
ui
EOF
    cat <<'EOF' >"${parallelExpectedFile}"
subscription
ui
transaction-core
routing
runtime
remote-control-smoke
remote-control-contract-service-install
EOF

    cmp -s "${expectedDefaultSelectorsFile}" "${defaultSelectorsFile}"
    cmp -s "${parallelExpectedFile}" "${parallelSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/all-default-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/all-default-selectors.unique.txt"
)

runAllSuiteChildStepsContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/all.sh"
    local allBody
    local parallelLine
    local transactionSystemLine
    local remoteControlLine

    allBody=$(sed -n '/^runRegressionAllSuiteRoot() ($/,/^)$/p' "${suiteFile}")
    [[ -n "${allBody}" ]] || return 1

    parallelLine=$(awk '/runFrameworkParallelRegressionSelectorList "\$\{TMP_DIR\}\/all-parallel-/ { print NR; exit }' <<<"${allBody}")
    transactionSystemLine=$(awk '/^[[:space:]]*runRegressionStep transaction-system / { print NR; exit }' <<<"${allBody}")
    remoteControlLine=$(awk '/^[[:space:]]*runRegressionStep remote-control-contract-server-response / { print NR; exit }' <<<"${allBody}")

    [[ -n "${parallelLine}" ]] || return 1
    [[ -n "${transactionSystemLine}" ]] || return 1
    [[ -n "${remoteControlLine}" ]] || return 1

    grep -q 'listRegressionAllParallelChildSelectors$' <<<"${allBody}" || return 1

    (( parallelLine < transactionSystemLine )) || return 1
    (( transactionSystemLine < remoteControlLine )) || return 1
}

runAllAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/all.sh"
    local expectedChildren

    ! grep -q '^registerRegressionScriptLeaf all ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf all ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateSequential all \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequential all runRegressionAllSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionAllChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        all \
        sequential \
        runRegressionAllSuiteRoot \
        "${expectedChildren}"
}

runAllAggregateRunnerUsesSuiteLocalDispatchHelperContract() (
    local callLog="${TMP_DIR}/all-aggregate-suite-root-dispatch.log"

    : >"${callLog}"

    listRegressionAllParallelChildSelectors() {
        printf '%s\n' \
            subscription \
            ui \
            transaction-core \
            routing \
            runtime \
            remote-control-smoke \
            remote-control-contract-service-install
    }

    runFrameworkParallelRegressionSelectorList() {
        local orchestrationRoot=$1
        local selectorListFn=$2
        shift 2
        local -a selectors=()

        mapfile -t selectors < <("${selectorListFn}" "$@")
        printf 'parallel:list:%s:%s:%s\n' "${orchestrationRoot}" "${selectorListFn}" "${selectors[*]}" >>"${callLog}"
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'parallel:selectors:%s\n' "$*" >>"${callLog}"
        return 97
    }

    runRegressionAllSelector() {
        printf 'legacy-helper:%s\n' "$1" >>"${callLog}"
        return 97
    }

    runRegressionAllSelectorSuiteRoot() {
        printf 'suite-helper:%s\n' "$1" >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain all

    grep -qx 'parallel:list:'"${TMP_DIR}"'/all-parallel-[0-9][0-9]*:listRegressionAllParallelChildSelectors:subscription ui transaction-core routing runtime remote-control-smoke remote-control-contract-service-install' "${callLog}"
    grep -qx 'suite-helper:transaction-system' "${callLog}"
    grep -qx 'suite-helper:remote-control-contract-server-response' "${callLog}"
    ! grep -q '^legacy-helper:' "${callLog}"
    ! grep -q '^parallel:selectors:' "${callLog}"
)

runAllSelectorDispatchAvoidsEntryScriptSpawnContract() (
    local callLog="${TMP_DIR}/all-selector-dispatch-no-entry-spawn.log"

    : >"${callLog}"

    bash() {
        printf 'bash:%s\n' "$*" >>"${callLog}"
        return 97
    }

    runRegisteredRegressionMain() {
        local selector=$1
        printf 'dispatch:%s jobs=%s ui_profile=%s subscription_profile=%s routing_profile=%s runtime_profile=%s transaction_core_profile=%s suppress=%s\n' \
            "${selector}" \
            "${PADM_REGRESSION_PARALLEL_JOBS:-}" \
            "${PADM_REGRESSION_UI_RESOURCE_PROFILE:-}" \
            "${PADM_REGRESSION_SUBSCRIPTION_RESOURCE_PROFILE:-}" \
            "${PADM_REGRESSION_ROUTING_RESOURCE_PROFILE:-}" \
            "${PADM_REGRESSION_RUNTIME_RESOURCE_PROFILE:-}" \
            "${PADM_REGRESSION_TRANSACTION_CORE_RESOURCE_PROFILE:-}" \
            "${PADM_REGRESSION_SUPPRESS_DONE:-}" >>"${callLog}"
    }

    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 PADM_REGRESSION_SUBSCRIPTION_RESOURCE_PROFILE=all runRegressionAllSelector subscription
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 PADM_REGRESSION_UI_RESOURCE_PROFILE=all runRegressionAllSelector ui
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 PADM_REGRESSION_TRANSACTION_CORE_RESOURCE_PROFILE=all runRegressionAllSelector transaction-core
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 PADM_REGRESSION_ROUTING_RESOURCE_PROFILE=all runRegressionAllSelector routing
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 PADM_REGRESSION_RUNTIME_RESOURCE_PROFILE=all runRegressionAllSelector runtime
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 runRegressionAllSelector transaction-system
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 runRegressionAllSelector remote-control-smoke
    PADM_REGRESSION_CHILD_PARALLEL_JOBS=4 runRegressionAllSelector remote-control-contract-server-response

    grep -qx 'dispatch:subscription jobs=4 ui_profile= subscription_profile=all routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'dispatch:ui jobs=4 ui_profile=all subscription_profile= routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'dispatch:transaction-core jobs=4 ui_profile= subscription_profile= routing_profile= runtime_profile= transaction_core_profile=all suppress=1' "${callLog}"
    grep -qx 'dispatch:routing jobs=4 ui_profile= subscription_profile= routing_profile=all runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'dispatch:runtime jobs=4 ui_profile= subscription_profile= routing_profile= runtime_profile=all transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'dispatch:transaction-system jobs=4 ui_profile= subscription_profile= routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'dispatch:remote-control-smoke jobs=4 ui_profile= subscription_profile= routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    grep -qx 'dispatch:remote-control-contract-server-response jobs=1 ui_profile= subscription_profile= routing_profile= runtime_profile= transaction_core_profile= suppress=1' "${callLog}"
    ! grep -q '^bash:' "${callLog}"
)

runAllAggregateRunnerUsesFrameworkSelectorHelperContract() (
    local callLog="${TMP_DIR}/all-framework-helper-dispatch.log"

    listRegressionAllParallelChildSelectors() {
        printf '%s\n' \
            subscription \
            ui \
            transaction-core \
            routing \
            runtime \
            remote-control-smoke \
            remote-control-contract-service-install
    }

    runFrameworkParallelRegressionSelectorList() {
        local orchestrationRoot=$1
        local selectorListFn=$2
        shift 2
        local -a selectors=()

        mapfile -t selectors < <("${selectorListFn}" "$@")
        printf 'framework:list:jobs=%s:%s:%s:%s\n' \
            "${PADM_REGRESSION_PARALLEL_JOBS:-}" \
            "${orchestrationRoot}" \
            "${selectorListFn}" \
            "${selectors[*]}" >>"${callLog}"
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:selectors:%s\n' "$*" >>"${callLog}"
        return 97
    }

    runParallelRegressionSelectors() {
        printf 'legacy-helper:%s\n' "$*" >>"${callLog}"
        return 97
    }

    runAggregateRunnerUsesFrameworkSelectorHelperAssertions \
        "${callLog}" \
        'framework:list:jobs='"${PADM_REGRESSION_ALL_PARALLEL_JOBS:-5}"':'"${TMP_DIR}"'/all-parallel-[0-9][0-9]*:listRegressionAllParallelChildSelectors:subscription ui transaction-core routing runtime remote-control-smoke remote-control-contract-service-install' \
        runRegressionAllSuiteRoot
)

runFrameworkParallelSelectorSupportsSelectorOnlyLimitContract() (
    set -euo pipefail
    local callLog="${TMP_DIR}/framework-parallel-selector-limit.log"

    : >"${callLog}"

    runRegisteredRegressionMain() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        [[ "${selector}" == "first" ]] && sleep 0.1
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }
    PADM_REGRESSION_SELECTOR_KIND[second]=function
    PADM_REGRESSION_SELECTOR_KIND[fourth]=function

    PADM_REGRESSION_PARALLEL_JOBS=1 PADM_REGRESSION_PARALLEL_SELECTOR_MODE=selectors \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/framework-parallel-selector-limit" \
        first \
        second \
        third \
        fourth

    grep -qx 'first-start' "${callLog}"
    grep -qx 'first-finish' "${callLog}"
    grep -qx 'second-start' "${callLog}"
    grep -qx 'second-finish' "${callLog}"
    grep -qx 'third-start' "${callLog}"
    grep -qx 'third-finish' "${callLog}"
    grep -qx 'fourth-start' "${callLog}"
    grep -qx 'fourth-finish' "${callLog}"
    awk '
        $0 == "first-finish" { firstFinish = NR }
        $0 == "second-start" { secondStart = NR }
        $0 == "second-finish" { secondFinish = NR }
        $0 == "third-start" { thirdStart = NR }
        $0 == "third-finish" { thirdFinish = NR }
        $0 == "fourth-start" { fourthStart = NR }
        END { exit !(firstFinish && secondStart && secondFinish && thirdStart && thirdFinish && fourthStart && firstFinish < secondStart && secondFinish < thirdStart && thirdFinish < fourthStart) }
    ' "${callLog}"
)

runFrameworkParallelSelectorSupportsSelectorOnlySlotRefillContract() (
    set -euo pipefail
    local callLog="${TMP_DIR}/framework-parallel-selector-slot-refill.log"
    local thirdStarted="${TMP_DIR}/framework-parallel-selector-third-started"

    : >"${callLog}"
    rm -f "${thirdStarted}"

    runRegisteredRegressionMain() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        case "${selector}" in
        first)
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${thirdStarted}" ]] && break
                sleep 0.05
            done
            ;;
        second) sleep 0.02 ;;
        third) : >"${thirdStarted}" ;;
        esac
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_JOBS=2 PADM_REGRESSION_PARALLEL_SELECTOR_MODE=selectors \
        runFrameworkParallelRegressionSelectors "${TMP_DIR}/framework-parallel-selector-slot-refill" \
        first \
        second \
        third

    grep -qx 'first-start' "${callLog}"
    grep -qx 'first-finish' "${callLog}"
    grep -qx 'second-start' "${callLog}"
    grep -qx 'second-finish' "${callLog}"
    grep -qx 'third-start' "${callLog}"
    grep -qx 'third-finish' "${callLog}"
    awk '
        $0 == "first-finish" { firstFinish = NR }
        $0 == "second-finish" { secondFinish = NR }
        $0 == "third-start" { thirdStart = NR }
        END { exit !(secondFinish && thirdStart && firstFinish && secondFinish < thirdStart && thirdStart < firstFinish) }
    ' "${callLog}"
)

runFrameworkParallelSelectorListBuildsPairDispatchContract() (
    set -euo pipefail
    local callLog="${TMP_DIR}/framework-parallel-selector-list.log"

    : >"${callLog}"

    listFrameworkParallelSelectorListFixtures() {
        [[ "${1:-}" == "wave-a" ]]
        printf '%s\n' \
            alpha \
            beta \
            gamma
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:mode=%s:%s\n' "${PADM_REGRESSION_PARALLEL_SELECTOR_MODE:-}" "$*" >>"${callLog}"
    }

    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/framework-parallel-selector-list-root" listFrameworkParallelSelectorListFixtures wave-a

    grep -qx 'framework:mode=pairs:'"${TMP_DIR}"'/framework-parallel-selector-list-root alpha alpha beta beta gamma gamma' "${callLog}"
)

runFrameworkSequentialSelectorListBuildsSequentialDispatchContract() (
    set -euo pipefail
    local callLog="${TMP_DIR}/framework-sequential-selector-list.log"

    : >"${callLog}"

    listFrameworkSequentialSelectorListFixtures() {
        [[ "${1:-}" == "wave-a" ]]
        printf '%s\n' \
            alpha \
            beta \
            gamma
    }

    runRegisteredRegressionMain() {
        printf 'dispatch:%s suppress=%s\n' "$1" "${PADM_REGRESSION_SUPPRESS_DONE:-}" >>"${callLog}"
    }

    runFrameworkSequentialRegressionSelectorList listFrameworkSequentialSelectorListFixtures wave-a

    runAggregateRunnerDispatchesChildrenInOrderAssertions \
        "${callLog}" \
        'dispatch:alpha suppress=1' \
        'dispatch:beta suppress=1' \
        'dispatch:gamma suppress=1'
)

runRuntimeSuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/runtime.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q 'source "\${REGRESSION_RUNTIME_SUITE_DIR}/../framework/runtime.sh"' "${suiteFile}"
    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_RUNTIME_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    grep -q '^listRegressionRuntimeLightChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionRuntimeHeavyChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionRuntimeChildSelectors() {$' "${suiteFile}"
    grep -q '^runRegressionRuntimeSuiteRoot() {$' "${suiteFile}"
    grep -q '^runRegressionRuntimeParallelCompositionRegression() ' "${suiteFile}"
    grep -q 'runFrameworkParallelRegressionSelectorList "${TMP_DIR}/runtime-parallel-' "${suiteFile}"
    ! grep -q '^listRegressionRuntimeLightChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionRuntimeHeavyChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionRuntimeChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^runRegressionRuntime() {$' "${legacyScriptFile}"
    ! grep -q '^runRegressionRuntimeParallelCompositionRegression() ' "${legacyScriptFile}"
    ! grep -q '^registerRegressionScriptLeaf runtime ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf runtime ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel runtime runRegressionRuntimeSuiteRoot \\' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf runtime-core runRegressionRuntimeLegacyLeafWithCompat runRuntimeAndRealityRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf runtime-autoread-unset-auto-install runRegressionRuntimeLegacyLeafWithCompat runAutoReadUnsetAutoInstallRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf runtime-auto-install-reality-route runRegressionRuntimeLegacyLeafWithCompat runAutoInstallRealityRouteRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf runtime-tempdir runRegressionRuntimeLegacyLeafWithCompat runRuntimeTempDirRegression$' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-candidates-fast ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-asn-scan-plan ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-candidates-full ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-stream-enable ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-stream-disable ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-config ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-profile-failure ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateRunnerSequential reality-candidates ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateRunnerSequential reality-stream ' "${suiteFile}"
}

runRuntimeLeavesUseCompatHelperContract() (
    local callLog="${TMP_DIR}/runtime-compat-helper.log"

    : >"${callLog}"

    runRegressionRuntimeLegacyLeafWithCompat() {
        printf '%s\n' "$1" >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain runtime-core
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain runtime-autoread-unset-auto-install
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain runtime-auto-install-reality-route
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain runtime-tempdir

    cat <<'EOF' >"${TMP_DIR}/runtime-compat-helper.expected.log"
runRuntimeAndRealityRegression
runAutoReadUnsetAutoInstallRegression
runAutoInstallRealityRouteRegression
runRuntimeTempDirRegression
EOF

    cmp -s "${TMP_DIR}/runtime-compat-helper.expected.log" "${callLog}"
)

runRuntimeLegacyTmpDirIsolationGuardRegisteredContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/runtime.sh"

    grep -q '^runRegressionRuntimeLegacyTmpDirIsolationRegression() ($' "${suiteFile}" || return 1
    grep -q '^    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain runtime-auto-install-reality-route$' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf regression-runtime-legacy-tmpdir-isolation runRegressionRuntimeLegacyTmpDirIsolationRegression$' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionAggregateRunnerParallel runtime .*regression-runtime-legacy-tmpdir-isolation' "${suiteFile}" || return 1
}

runRuntimeLegacyPublicSelectorRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/runtime.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^registerRegressionAggregateRunnerParallel runtime runRegressionRuntimeSuiteRoot \\' "${suiteFile}" || return 1

    runLegacyPublicSelectorRetirementAssertions "${legacyScriptFile}" \
        runtime \
        runtime-core \
        runtime-autoread-unset-auto-install \
        runtime-auto-install-reality-route \
        runtime-tempdir \
        regression-runtime-parallel-composition
}

runRealitySuiteUsesFunctionRegistryContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/reality.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q 'PADM_REGRESSION_SOURCE_ONLY=1 source "\${REGRESSION_REALITY_SUITE_DIR}/../subscription_groups_legacy.sh"' "${suiteFile}"
    ! grep -q '^runRegressionRealityCandidatesSuiteRoot() {$' "${suiteFile}"
    ! grep -q '^runRegressionRealityStreamSuiteRoot() {$' "${suiteFile}"
    grep -q '^listRegressionRealitySuiteCandidatesChildSelectors() {$' "${suiteFile}"
    grep -q '^listRegressionRealitySuiteStreamChildSelectors() {$' "${suiteFile}"
    ! grep -Eq '^runRegressionRealityCandidates\(\)[[:space:]]*[({]' "${legacyScriptFile}"
    ! grep -Eq '^runRegressionRealityStream\(\)[[:space:]]*[({]' "${legacyScriptFile}"
    ! grep -q '^listRegressionRealitySuiteCandidatesChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^listRegressionRealitySuiteStreamChildSelectors() {$' "${legacyScriptFile}"
    ! grep -q '^registerRegressionScriptLeaf reality-candidates ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-candidates ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf reality-stream ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-stream ' "${suiteFile}"
    ! grep -q '^while read -r selector runner; do$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf reality-candidates-fast runRegressionRealityLegacyLeafWithCompat runRealityCandidateFastRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf reality-asn-scan-plan runRegressionRealityLegacyLeafWithCompat runRealityAsnScanPlanRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf reality-candidates-full runRegressionRealityLegacyLeafWithCompat runRealityCandidateFullRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf reality-stream-enable runRegressionRealityLegacyLeafWithCompat runRealityStreamEnableRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf reality-stream-disable runRegressionRealityLegacyLeafWithCompat runRealityStreamDisableRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf reality-config runRegressionRealityLegacyLeafWithCompat runRealityConfigRegression$' "${suiteFile}"
    grep -q '^registerRegressionFunctionLeaf reality-profile-failure runRegressionRealityLegacyLeafWithCompat runRealityProfileFailureRegression$' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequentialWithArgs \\' "${suiteFile}"
}

runRealityLegacyPublicSelectorRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/reality.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^registerRegressionAggregateRunnerSequentialWithArgs \\' "${suiteFile}" || return 1

    runLegacyPublicSelectorRetirementAssertions "${legacyScriptFile}" \
        reality-candidates \
        reality-candidates-fast \
        reality-asn-scan-plan \
        reality-candidates-full \
        reality-config \
        reality-stream \
        reality-profile-failure
}

runSubscriptionSelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/subscription-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/subscription-default-selectors.sorted.txt"
    local waveSelectorsFile="${TMP_DIR}/subscription-wave-selectors.txt"
    local waveSortedFile="${TMP_DIR}/subscription-wave-selectors.sorted.txt"

    declare -F listRegressionSubscriptionChildSelectors >/dev/null
    declare -F listRegressionSubscriptionLightChildSelectors >/dev/null
    declare -F listRegressionSubscriptionHeavyChildSelectors >/dev/null

    listRegressionSubscriptionChildSelectors >"${defaultSelectorsFile}"
    {
        listRegressionSubscriptionLightChildSelectors
        listRegressionSubscriptionHeavyChildSelectors
    } >"${waveSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/subscription-default-selectors.unique.txt"
    sort "${waveSelectorsFile}" >"${waveSortedFile}"
    sort -u "${waveSelectorsFile}" >"${TMP_DIR}/subscription-wave-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/subscription-default-selectors.unique.txt"
    cmp -s "${waveSortedFile}" "${TMP_DIR}/subscription-wave-selectors.unique.txt"
    cmp -s "${TMP_DIR}/subscription-default-selectors.unique.txt" "${TMP_DIR}/subscription-wave-selectors.unique.txt"
)

runSubscriptionRemoteRegisteredChildSelectorsAlignedContract() (
    runRegisteredChildSelectorsAlignedAssertions \
        listRegressionSubscriptionRemoteChildSelectors \
        "${TMP_DIR}/subscription-remote-registered-child-selectors" <<'EOF'
subscription-remote-unique
subscription-remote-rollback
subscription-remote-merge
subscription-remote-controlled
subscription-remote-append-failure
subscription-remote-commit-failure
subscription-remote-idempotent
EOF
)

runSubscriptionTxRegisteredChildSelectorsAlignedContract() (
    runRegisteredChildSelectorsAlignedAssertions \
        listRegressionSubscriptionTxChildSelectors \
        "${TMP_DIR}/subscription-tx-registered-child-selectors" <<'EOF'
sing-box-subscribe-write
cdn-address-write-transaction
subscribe-local-output-transaction
subscribe-salt-write-transaction
subscribe-server-name
subscribe-nginx-config-write
subscribe-nginx-service-failure
sing-box-port-failure
subscribe-user-output-transaction
subscribe-local-rollback
subscription-groups-migration-backup
subscription-groups-backup-failure
refresh-local-subscriptions-rollback
subscribe-return-failure
remove-user-subscription-menu-failure
user-subscription-menu-mutation-failure
EOF
)

runSubscriptionAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local expectedChildren

    ! grep -q '^registerRegressionScriptLeaf subscription ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel subscription runRegressionSubscriptionSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionSubscriptionChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        subscription \
        parallel \
        runRegressionSubscriptionSuiteRoot \
        "${expectedChildren}"
}

runSubscriptionRemoteAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local expectedChildren

    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["subscription-remote-fetch"]:-}" ]]
    ! grep -q '^registerRegressionScriptLeaf subscription-remote ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-remote ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription-remote-fetch ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-remote-fetch ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-remote-fetch-' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallelWithArgs \\' "${suiteFile}"
    expectedChildren=$(listRegressionSubscriptionRemoteChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        subscription-remote \
        parallel \
        runSubscriptionSelectorListRegression \
        "${expectedChildren}"
    runAggregateRunnerRunnerArgsPatternAssertions \
        subscription-remote \
        '^subscription-remote-parallel$' \
        '^listRegressionSubscriptionRemoteChildSelectors$' \
        '^4$' \
        '^PADM_REGRESSION_SUBSCRIPTION_REMOTE_PARALLEL_JOBS$'
}

runSubscriptionTxAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local expectedChildren

    [[ -z "${PADM_REGRESSION_SELECTOR_KIND["subscription-write-transaction"]:-}" ]]
    ! grep -q '^registerRegressionScriptLeaf subscription-tx ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-tx ' "${suiteFile}"
    ! grep -q '^registerRegressionScriptLeaf subscription-write-transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf subscription-write-transaction ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf regression-subscription-write-transaction-' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallelWithArgs \\' "${suiteFile}"
    expectedChildren=$(listRegressionSubscriptionTxChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        subscription-tx \
        parallel \
        runSubscriptionSelectorListRegression \
        "${expectedChildren}"
    runAggregateRunnerRunnerArgsPatternAssertions \
        subscription-tx \
        '^subscription-tx-parallel$' \
        '^listRegressionSubscriptionTxChildSelectors$'
}

runTargetedSubscriptionRestoreRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/transaction.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^registerRegressionFunctionLeaf subscribe-user-output-transaction runRegressionTransactionLegacyLeafWithCompat runSubscribeUserOutputTransactionRegression$' "${suiteFile}" || return 1
    runLegacyFunctionSelectorRetirementAssertions \
        "${legacyFile}" \
        runRegressionTargetedSubscriptionRestore \
        targeted-subscription-restore \
        '|targeted-subscription-restore|'
}

runSubscriptionOutputLegacyRetirementContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^runRegressionSubscriptionOutput() {$' "${suiteFile}" || return 1
    ! grep -q '^runRegressionSubscriptionOutputSuiteRoot() {$' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf subscription-output runRegressionSubscriptionLegacyLeafWithCompat runRegressionSubscriptionOutput$' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf subscription-output-profile-and-reality runRegressionSubscriptionLegacyLeafWithCompat runSubscriptionOutputProfileAndRealityRegression$' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf subscription-output-publish-accounts-and-remote-hint runRegressionSubscriptionLegacyLeafWithCompat runSubscriptionOutputPublishAccountsAndRemoteHintRegression$' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf subscription-output-tls-vless-vmess-trojan runRegressionSubscriptionLegacyLeafWithCompat runSubscriptionOutputTlsVlessVmessTrojanRegression$' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf subscription-output-tls-any-hysteria-tuic-naive runRegressionSubscriptionLegacyLeafWithCompat runSubscriptionOutputTlsAnyHysteriaTuicNaiveRegression$' "${suiteFile}" || return 1
    runLegacyFunctionSelectorRetirementAssertions \
        "${legacyFile}" \
        runRegressionSubscriptionOutput \
        subscription-output \
        '|subscription-output|'
}

runSubscriptionSelectorHelpersAreSuiteOwnedContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local legacyFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"

    grep -q '^listRegressionSubscriptionRemoteChildSelectors() {$' "${suiteFile}" || return 1
    grep -q '^listRegressionSubscriptionTxChildSelectors() {$' "${suiteFile}" || return 1
    grep -q '^listRegressionSubscriptionLightChildSelectors() {$' "${suiteFile}" || return 1
    grep -q '^listRegressionSubscriptionHeavyChildSelectors() {$' "${suiteFile}" || return 1
    grep -q '^listRegressionSubscriptionChildSelectors() {$' "${suiteFile}" || return 1

    ! grep -q '^listRegressionSubscriptionRemoteChildSelectors() {$' "${legacyFile}" || return 1
    ! grep -q '^listRegressionSubscriptionTxChildSelectors() {$' "${legacyFile}" || return 1
    ! grep -q '^listRegressionSubscriptionLightChildSelectors() {$' "${legacyFile}" || return 1
    ! grep -q '^listRegressionSubscriptionHeavyChildSelectors() {$' "${legacyFile}" || return 1
    ! grep -q '^listRegressionSubscriptionChildSelectors() {$' "${legacyFile}" || return 1
}

runSubscriptionOutputChildStepsContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local outputBody
    local -a actualSteps=()
    local helperLine
    local stepLine

    outputBody=$(sed -n '/^runRegressionSubscriptionOutput() {$/,/^}$/p' "${suiteFile}")
    [[ -n "${outputBody}" ]] || return 1

    helperLine=$(awk '/runSubscriptionSelectorListRegression/ { print NR; exit }' <<<"${outputBody}")
    [[ -n "${helperLine}" ]] || return 1

    mapfile -t actualSteps < <(
        awk '/^[[:space:]]*runRegressionStep / { print $2 }' <<<"${outputBody}"
    )

    [[ "${#actualSteps[@]}" -eq 1 ]] || return 1
    [[ "${actualSteps[0]}" == "subscription-remote-sources-no-reverse-decode" ]] || return 1

    stepLine=$(awk '/^[[:space:]]*runRegressionStep subscription-remote-sources-no-reverse-decode / { print NR; exit }' <<<"${outputBody}")
    [[ -n "${stepLine}" ]] || return 1
    (( helperLine < stepLine )) || return 1
}

runSubscriptionAggregateRunnersUseSuiteLocalHelpersContract() (
    local status=0
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/subscription.sh"
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local callLog="${TMP_DIR}/subscription-suite-root-dispatch.log"

    : >"${callLog}"

    ! grep -Eq '^runRegressionSubscription\(\)[[:space:]]*[({]' "${suiteFile}" || status=1
    ! grep -Eq '^runRegressionSubscriptionRemote\(\)[[:space:]]*[({]' "${suiteFile}" || status=1
    ! grep -Eq '^runRegressionSubscriptionTx\(\)[[:space:]]*[({]' "${suiteFile}" || status=1
    ! grep -Eq '^runRegressionSubscriptionRemoteSuiteRoot\(\)[[:space:]]*[({]' "${suiteFile}" || status=1
    ! grep -Eq '^runRegressionSubscriptionTxSuiteRoot\(\)[[:space:]]*[({]' "${suiteFile}" || status=1
    ! grep -Eq '^runRegressionSubscription\(\)[[:space:]]*[({]' "${legacyScriptFile}" || status=1
    ! grep -Eq '^runRegressionSubscriptionRemote\(\)[[:space:]]*[({]' "${legacyScriptFile}" || status=1
    ! grep -Eq '^runRegressionSubscriptionTx\(\)[[:space:]]*[({]' "${legacyScriptFile}" || status=1

    runRegressionSubscription() {
        printf 'legacy-subscription\n' >>"${callLog}"
        return 97
    }

    runRegressionSubscriptionSuiteRoot() {
        printf 'suite-subscription\n' >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain subscription

    grep -qx 'suite-subscription' "${callLog}" || status=1
    ! grep -q '^legacy-subscription$' "${callLog}" || status=1

    return "${status}"
)

runSubscriptionAggregateRunnersUseFrameworkSelectorHelperContract() (
    local callLog="${TMP_DIR}/subscription-framework-helper-dispatch.log"

    : >"${callLog}"

    runRegressionSubscriptionLegacyLeafWithCompat() {
        "$@"
    }

    listRegressionSubscriptionOutputChildSelectors() {
        printf '%s\n' \
            subscription-output-profile-and-reality \
            subscription-output-publish-accounts-and-remote-hint \
            subscription-output-tls-vless-vmess-trojan \
            subscription-output-tls-any-hysteria-tuic-naive
    }

    listRegressionSubscriptionRemoteChildSelectors() {
        printf '%s\n' \
            subscription-remote-unique \
            subscription-remote-merge
    }

    listRegressionSubscriptionTxChildSelectors() {
        printf '%s\n' \
            sing-box-subscribe-write \
            subscribe-user-output-transaction
    }

    listRegressionSubscriptionLightChildSelectors() {
        printf '%s\n' \
            subscription-output \
            subscription-state
    }

    listRegressionSubscriptionHeavyChildSelectors() {
        printf '%s\n' \
            subscription-tx \
            subscription-remote
    }

    listRegressionSubscriptionChildSelectors() {
        printf '%s\n' \
            subscription-output \
            subscription-state \
            subscription-remote \
            subscription-tx
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:jobs=%s:%s\n' "${PADM_REGRESSION_PARALLEL_JOBS:-}" "$*" >>"${callLog}"
    }

    runParallelRegressionSelectors() {
        printf 'legacy-helper:%s\n' "$*" >>"${callLog}"
        return 97
    }

    runRemoteSubscribeSourcesAvoidReverseDecodeRegression() { :; }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain subscription-remote
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain subscription-tx
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain subscription-output
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain subscription
    PADM_REGRESSION_SUPPRESS_DONE=1 PADM_REGRESSION_SUBSCRIPTION_RESOURCE_PROFILE=all runRegisteredRegressionMain subscription

    grep -qx 'framework:jobs='"${PADM_REGRESSION_SUBSCRIPTION_OUTPUT_PARALLEL_JOBS:-2}"':'"${TMP_DIR}"'/subscription-output-parallel-[0-9][0-9]* subscription-output-profile-and-reality subscription-output-profile-and-reality subscription-output-publish-accounts-and-remote-hint subscription-output-publish-accounts-and-remote-hint subscription-output-tls-vless-vmess-trojan subscription-output-tls-vless-vmess-trojan subscription-output-tls-any-hysteria-tuic-naive subscription-output-tls-any-hysteria-tuic-naive' "${callLog}"
    grep -qx 'framework:jobs='"${PADM_REGRESSION_SUBSCRIPTION_REMOTE_PARALLEL_JOBS:-4}"':'"${TMP_DIR}"'/subscription-remote-parallel-[0-9][0-9]* subscription-remote-unique subscription-remote-unique subscription-remote-merge subscription-remote-merge' "${callLog}"
    grep -qx 'framework:jobs=:'"${TMP_DIR}"'/subscription-tx-parallel-[0-9][0-9]* sing-box-subscribe-write sing-box-subscribe-write subscribe-user-output-transaction subscribe-user-output-transaction' "${callLog}"
    grep -qx 'framework:jobs=:'"${TMP_DIR}"'/subscription-parallel-[0-9][0-9]* subscription-output subscription-output subscription-state subscription-state subscription-remote subscription-remote subscription-tx subscription-tx' "${callLog}"
    grep -qx 'framework:jobs=:'"${TMP_DIR}"'/subscription-parallel-light-[0-9][0-9]* subscription-output subscription-output subscription-state subscription-state' "${callLog}"
    grep -qx 'framework:jobs=:'"${TMP_DIR}"'/subscription-parallel-heavy-[0-9][0-9]* subscription-tx subscription-tx subscription-remote subscription-remote' "${callLog}"
    ! grep -q '^legacy-helper:' "${callLog}"
)

runRealityCandidatesAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/reality.sh"
    local expectedChildren

    ! grep -q '^registerRegressionScriptLeaf reality-candidates ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-candidates ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateSequential reality-candidates \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequentialWithArgs \\' "${suiteFile}"
    expectedChildren=$(listRegressionRealitySuiteCandidatesChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        reality-candidates \
        sequential \
        runFrameworkSequentialRegressionSelectorList \
        "${expectedChildren}"
    runAggregateRunnerRunnerArgsAssertions reality-candidates 'listRegressionRealitySuiteCandidatesChildSelectors'
}

runRealityCandidatesAggregateRunnerDispatchesChildrenInOrderContract() (
    local callLog="${TMP_DIR}/reality-candidates-aggregate-dispatch.log"

    : >"${callLog}"

    runRegressionRealityLegacyLeafWithCompat() {
        "$1"
    }

    runRealityCandidateFastRegression() {
        printf 'reality-candidates-fast\n' >>"${callLog}"
    }

    runRealityAsnScanPlanRegression() {
        printf 'reality-asn-scan-plan\n' >>"${callLog}"
    }

    runRealityCandidateFullRegression() {
        printf 'reality-candidates-full\n' >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain reality-candidates

    runAggregateRunnerDispatchesChildrenInOrderAssertions \
        "${callLog}" \
        reality-candidates-fast \
        reality-asn-scan-plan \
        reality-candidates-full
)

runRealityStreamAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/reality.sh"
    local expectedChildren

    ! grep -q '^registerRegressionScriptLeaf reality-stream ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf reality-stream ' "${suiteFile}"
    ! grep -q '^registerRegressionAggregateSequential reality-stream \\' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerSequentialWithArgs \\' "${suiteFile}"
    expectedChildren=$(listRegressionRealitySuiteStreamChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        reality-stream \
        sequential \
        runFrameworkSequentialRegressionSelectorList \
        "${expectedChildren}"
    runAggregateRunnerRunnerArgsAssertions reality-stream 'listRegressionRealitySuiteStreamChildSelectors'
}

runRealityStreamAggregateRunnerDispatchesChildrenInOrderContract() (
    local callLog="${TMP_DIR}/reality-stream-aggregate-dispatch.log"

    : >"${callLog}"

    runRegressionRealityLegacyLeafWithCompat() {
        "$1"
    }

    runRealityStreamEnableRegression() {
        printf 'reality-stream-enable\n' >>"${callLog}"
    }

    runRealityStreamDisableRegression() {
        printf 'reality-stream-disable\n' >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain reality-stream

    runAggregateRunnerDispatchesChildrenInOrderAssertions \
        "${callLog}" \
        reality-stream-enable \
        reality-stream-disable
)

runRealityLeavesUseCompatHelperContract() (
    local callLog="${TMP_DIR}/reality-compat-helper.log"

    : >"${callLog}"

    runRegressionRealityLegacyLeafWithCompat() {
        printf '%s\n' "$1" >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain reality-candidates-fast
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain reality-asn-scan-plan
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain reality-candidates-full
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain reality-stream-enable
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain reality-stream-disable
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain reality-config
    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain reality-profile-failure

    cat <<'EOF' >"${TMP_DIR}/reality-compat-helper.expected.log"
runRealityCandidateFastRegression
runRealityAsnScanPlanRegression
runRealityCandidateFullRegression
runRealityStreamEnableRegression
runRealityStreamDisableRegression
runRealityConfigRegression
runRealityProfileFailureRegression
EOF

    cmp -s "${TMP_DIR}/reality-compat-helper.expected.log" "${callLog}"
)

runRealityLegacyTmpDirIsolationGuardRegisteredContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/reality.sh"

    grep -q '^runRegressionRealityLegacyTmpDirIsolationRegression() ($' "${suiteFile}" || return 1
    grep -q '^    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain reality-config$' "${suiteFile}" || return 1
    grep -q '^registerRegressionFunctionLeaf regression-reality-legacy-tmpdir-isolation runRegressionRealityLegacyTmpDirIsolationRegression$' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionAggregateRunnerSequential reality-candidates .*regression-reality-legacy-tmpdir-isolation' "${suiteFile}" || return 1
    ! grep -q '^registerRegressionAggregateRunnerSequential reality-stream .*regression-reality-legacy-tmpdir-isolation' "${suiteFile}" || return 1
}

runRuntimeSelectorHelpersStayAlignedContract() (
    local defaultSelectorsFile="${TMP_DIR}/runtime-default-selectors.txt"
    local defaultSortedFile="${TMP_DIR}/runtime-default-selectors.sorted.txt"
    local waveSelectorsFile="${TMP_DIR}/runtime-wave-selectors.txt"
    local waveSortedFile="${TMP_DIR}/runtime-wave-selectors.sorted.txt"

    declare -F listRegressionRuntimeChildSelectors >/dev/null
    declare -F listRegressionRuntimeLightChildSelectors >/dev/null
    declare -F listRegressionRuntimeHeavyChildSelectors >/dev/null

    listRegressionRuntimeChildSelectors >"${defaultSelectorsFile}"
    {
        listRegressionRuntimeLightChildSelectors
        listRegressionRuntimeHeavyChildSelectors
    } >"${waveSelectorsFile}"

    sort "${defaultSelectorsFile}" >"${defaultSortedFile}"
    sort -u "${defaultSelectorsFile}" >"${TMP_DIR}/runtime-default-selectors.unique.txt"
    sort "${waveSelectorsFile}" >"${waveSortedFile}"
    sort -u "${waveSelectorsFile}" >"${TMP_DIR}/runtime-wave-selectors.unique.txt"

    cmp -s "${defaultSortedFile}" "${TMP_DIR}/runtime-default-selectors.unique.txt"
    cmp -s "${waveSortedFile}" "${TMP_DIR}/runtime-wave-selectors.unique.txt"
    cmp -s "${TMP_DIR}/runtime-default-selectors.unique.txt" "${TMP_DIR}/runtime-wave-selectors.unique.txt"
)

runRuntimeAggregateRunnerRegistrationContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/runtime.sh"
    local expectedChildren

    ! grep -q '^registerRegressionScriptLeaf runtime ' "${suiteFile}"
    ! grep -q '^registerRegressionFunctionLeaf runtime ' "${suiteFile}"
    grep -q '^registerRegressionAggregateRunnerParallel runtime runRegressionRuntimeSuiteRoot \\' "${suiteFile}"
    expectedChildren=$(listRegressionRuntimeChildSelectors)
    runAggregateRunnerRegistrationAssertions \
        runtime \
        parallel \
        runRegressionRuntimeSuiteRoot \
        "${expectedChildren}"
}

runRuntimeAggregateRunnerUsesSuiteLocalHelperContract() (
    local callLog="${TMP_DIR}/runtime-aggregate-suite-root-dispatch.log"

    runRegressionRuntime() {
        printf 'legacy-runtime\n' >>"${callLog}"
        return 97
    }

    runRegressionRuntimeSuiteRoot() {
        printf 'suite-runtime\n' >>"${callLog}"
    }

    runAggregateRunnerUsesSuiteLocalHelperAssertions runtime "${callLog}" 'suite-runtime' 'legacy-runtime'
)

runRuntimeAggregateRunnerUsesFrameworkSelectorHelperContract() (
    local callLog="${TMP_DIR}/runtime-framework-helper-dispatch.log"

    : >"${callLog}"

    listRegressionRuntimeChildSelectors() {
        printf '%s\n' \
            runtime-core \
            runtime-tempdir \
            reality-candidates \
            reality-config
    }

    listRegressionRuntimeLightChildSelectors() {
        printf '%s\n' \
            runtime-core \
            runtime-tempdir
    }

    listRegressionRuntimeHeavyChildSelectors() {
        printf '%s\n' \
            reality-candidates \
            reality-config
    }

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:jobs=%s:%s\n' "${PADM_REGRESSION_PARALLEL_JOBS:-}" "$*" >>"${callLog}"
    }

    runParallelRegressionSelectors() {
        printf 'legacy-helper:%s\n' "$*" >>"${callLog}"
        return 97
    }

    runRuntimeAggregateRunnerUsesFrameworkSelectorHelperRunner() {
        runRegressionRuntimeSuiteRoot
        PADM_REGRESSION_RUNTIME_RESOURCE_PROFILE=all runRegressionRuntimeSuiteRoot
    }

    runAggregateRunnerUsesFrameworkSelectorHelperMultiLineAssertions \
        "${callLog}" \
        runRuntimeAggregateRunnerUsesFrameworkSelectorHelperRunner \
        'framework:jobs=:'"${TMP_DIR}"'/runtime-parallel-[0-9][0-9]* runtime-core runtime-core runtime-tempdir runtime-tempdir reality-candidates reality-candidates reality-config reality-config' \
        'framework:jobs='"${PADM_REGRESSION_RUNTIME_LIGHT_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}"':'"${TMP_DIR}"'/runtime-parallel-light-[0-9][0-9]* runtime-core runtime-core runtime-tempdir runtime-tempdir' \
        'framework:jobs='"${PADM_REGRESSION_RUNTIME_HEAVY_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-2}}"':'"${TMP_DIR}"'/runtime-parallel-heavy-[0-9][0-9]* reality-candidates reality-candidates reality-config reality-config'
)

runRealityNoEmptyAggregateWrapperFunctionsContract() {
    local suiteFile="${PROJECT_ROOT}/shell/regression/suites/reality.sh"
    ! grep -q '^runRegressionRealityCandidatesSuiteRoot() {$' "${suiteFile}" || return 1
    ! grep -q '^runRegressionRealityStreamSuiteRoot() {$' "${suiteFile}" || return 1
}

runParallelSelectorCollectsExitedChildWithoutRcContract() (
    local root="${TMP_DIR}/parallel-selector-exit-without-rc"
    local callLog="${root}/call.log"

    mkdir -p "${root}"
    : >"${callLog}"

    runRegressionAllSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        case "${selector}" in
        exit-fast)
            exit 1
            ;;
        finish)
            sleep 0.1
            ;;
        esac
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    set +e
    PADM_REGRESSION_PARALLEL_JOBS=2 \
        PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector \
        PADM_REGRESSION_PARALLEL_SELECTOR_MODE=selectors \
        runParallelRegressionSelectors "${root}/orchestration" exit-fast finish
    [[ "$?" == "1" ]]
    grep -qx 'finish-start' "${callLog}"
    grep -qx 'finish-finish' "${callLog}"
)

runTransactionCoreCompatibleDispatcherLeavesExecutionContract() (
    local selector

    while IFS= read -r selector; do
        [[ -n "${selector}" ]] || continue
        PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain "${selector}"
    done <<'EOF'
core-rollback-result-message
core-port-file-transaction
entry-helper-config
user-config-write
remove-user
EOF
)

runTransactionSystemAggregateDispatchesChildrenExactlyOnceContract() (
    local callLog="${TMP_DIR}/transaction-system-aggregate-dispatch.log"
    local selector

    : >"${callLog}"

    runFrameworkParallelRegressionSelectors() {
        printf 'framework:%s\n' "$*" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_JOBS=1 PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain transaction-system

    grep -q '^framework:'"${TMP_DIR}"'/transaction-system-parallel-[0-9][0-9]* ' "${callLog}"
    while IFS= read -r selector; do
        [[ -n "${selector}" ]] || continue
        grep -q " ${selector} ${selector}\(\|$\)" "${callLog}"
        [[ "$(grep -o " ${selector} ${selector}" "${callLog}" | wc -l)" == "1" ]]
    done < <(listRegressionTransactionSystemChildSelectors)
)

runLegacyRealityStubsSurviveSuiteLoadContract() {
    declare -f realityTargetDetector | grep -q "fake-xray"
    declare -f currentRealityNetworkProfile | grep -q "203.0.113.10"
    declare -f resolveRealityTargetIPv4 | grep -q "192.0.2.1"
    declare -f lookupRealityTargetAsn | grep -q "AS64501"
}

runLegacyRegressionScriptsRequireDispatcherContract() {
    local root="${TMP_DIR}/legacy-entry-contract"
    local scriptPath
    local outputFile
    local status

    mkdir -p "${root}"
    while IFS= read -r scriptPath; do
        outputFile="${root}/$(basename -- "${scriptPath}").log"
        set +e
        bash "${scriptPath}" "__contract__" >"${outputFile}" 2>&1
        status=$?
        set -e
        [[ "${status}" -eq 2 ]]
        grep -q 'use shell/subscription_groups_regression.sh <selector>' "${outputFile}"
    done <<EOF
${PROJECT_ROOT}/shell/regression/subscription_groups_fast.sh
${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh
${PROJECT_ROOT}/shell/regression/subscription_groups_remote_control.sh
${PROJECT_ROOT}/shell/regression/subscription_groups_subscription_state.sh
${PROJECT_ROOT}/shell/regression/subscription_groups_subscription_state_full.sh
EOF
}

runLegacyRegressionScriptsRetireInternalCliContract() {
    local legacyScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh"
    local remoteControlScriptFile="${PROJECT_ROOT}/shell/regression/subscription_groups_remote_control.sh"

    ! grep -q '^if \[\[ "\${PADM_REGRESSION_INTERNAL_CLI:-}" != "1" \]\]; then$' "${legacyScriptFile}"
    ! grep -q '^if \[\[ "\${PADM_REGRESSION_INTERNAL_CLI:-}" != "1" \]\]; then$' "${remoteControlScriptFile}"
    ! grep -q '^printf '\''legacy public selectors retired; use shell/subscription_groups_regression.sh <selector>\\n'\'' >&2$' "${legacyScriptFile}"
    ! grep -q '^printf '\''remote control public selectors retired; use shell/subscription_groups_regression.sh <selector>\\n'\'' >&2$' "${remoteControlScriptFile}"
}

runRegressionSelectorDispatchCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-selector-dispatch-composition.log"

    : >"${callLog}"

    runRegisteredRegressionMain() {
        printf 'selector=%s suppress=%s jobs=%s ui_profile=%s subscription_profile=%s routing_profile=%s runtime_profile=%s transaction_core_profile=%s\n' \
            "$1" \
            "${PADM_REGRESSION_SUPPRESS_DONE:-}" \
            "${PADM_REGRESSION_PARALLEL_JOBS:-}" \
            "${PADM_REGRESSION_UI_RESOURCE_PROFILE:-}" \
            "${PADM_REGRESSION_SUBSCRIPTION_RESOURCE_PROFILE:-}" \
            "${PADM_REGRESSION_ROUTING_RESOURCE_PROFILE:-}" \
            "${PADM_REGRESSION_RUNTIME_RESOURCE_PROFILE:-}" \
            "${PADM_REGRESSION_TRANSACTION_CORE_RESOURCE_PROFILE:-}" >>"${callLog}"
    }

    runRegressionAllSelector subscription-state
    runRegressionAllSelector remote-control
    runRegressionAllSelector routing

    grep -qx 'selector=subscription-state suppress=1 jobs= ui_profile= subscription_profile= routing_profile= runtime_profile= transaction_core_profile=' "${callLog}"
    grep -qx 'selector=remote-control suppress=1 jobs= ui_profile= subscription_profile= routing_profile= runtime_profile= transaction_core_profile=' "${callLog}"
    grep -qx 'selector=routing suppress=1 jobs= ui_profile= subscription_profile= routing_profile= runtime_profile= transaction_core_profile=' "${callLog}"
    ! grep -q '^legacy-helper:' "${callLog}"
)

runRegressionParallelSelectorLimitCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-parallel-selector-limit-composition.log"

    : >"${callLog}"

    runRegressionAllSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        [[ "${selector}" == "first" ]] && sleep 0.1
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_JOBS=1 runParallelRegressionSelectors "${TMP_DIR}/parallel-selector-limit-composition" \
        first \
        second \
        third

    grep -qx 'first-start' "${callLog}"
    grep -qx 'first-finish' "${callLog}"
    grep -qx 'second-start' "${callLog}"
    grep -qx 'second-finish' "${callLog}"
    grep -qx 'third-start' "${callLog}"
    grep -qx 'third-finish' "${callLog}"
    awk '
        $0 == "first-finish" { firstFinish = NR }
        $0 == "second-start" { secondStart = NR }
        $0 == "second-finish" { secondFinish = NR }
        $0 == "third-start" { thirdStart = NR }
        END { exit !(firstFinish && secondStart && secondFinish && thirdStart && firstFinish < secondStart && secondFinish < thirdStart) }
    ' "${callLog}"
)

runRegressionParallelSelectorSlotRefillCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-parallel-selector-slot-refill-composition.log"
    local thirdStarted="${TMP_DIR}/regression-parallel-selector-slot-refill-third-started"

    : >"${callLog}"

    runRegressionAllSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        case "${selector}" in
        first)
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${thirdStarted}" ]] && break
                sleep 0.05
            done
            ;;
        second) sleep 0.02 ;;
        third) : >"${thirdStarted}" ;;
        esac
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_PARALLEL_JOBS=2 runParallelRegressionSelectors "${TMP_DIR}/parallel-selector-slot-refill-composition" \
        first \
        second \
        third

    grep -qx 'first-start' "${callLog}"
    grep -qx 'first-finish' "${callLog}"
    grep -qx 'second-start' "${callLog}"
    grep -qx 'second-finish' "${callLog}"
    grep -qx 'third-start' "${callLog}"
    grep -qx 'third-finish' "${callLog}"
    awk '
        $0 == "first-finish" { firstFinish = NR }
        $0 == "second-finish" { secondFinish = NR }
        $0 == "third-start" { thirdStart = NR }
        END { exit !(secondFinish && thirdStart && firstFinish && secondFinish < thirdStart && thirdStart < firstFinish) }
    ' "${callLog}"
)

runRegressionDispatcherContracts() {
    runRegressionStep regression-dispatcher-registry-only runRegressionDispatcherRegistryOnlyContract &&
        runRegressionStep regression-step-sequence-assertion runRegressionStepSequenceAssertionContract &&
        runRegressionStep regression-dispatcher-step-coverage-assertion runRegressionDispatcherStepCoverageAssertionContract &&
        runRegressionStep contract-helper-adoption-assertion runContractHelperAdoptionAssertionContract &&
        runRegressionStep regression-registry-retires-script-selector-kind runRegressionRegistryRetiresScriptSelectorKindContract &&
        runRegressionStep regression-function-leaf-supports-runner-args runRegressionFunctionLeafSupportsRunnerArgsContract &&
        runRegressionStep regression-aggregate-runner-supports-runner-args runRegressionAggregateRunnerSupportsRunnerArgsContract &&
        runRegressionStep regression-parallel-aggregate-runner-supports-runner-args runRegressionParallelAggregateRunnerSupportsRunnerArgsContract &&
        runRegressionStep aggregate-runner-registration-assertion runAggregateRunnerRegistrationAssertionContract &&
        runRegressionStep aggregate-runner-runner-args-assertion runAggregateRunnerRunnerArgsAssertionContract &&
        runRegressionStep aggregate-runner-registration-helper-adoption runAggregateRunnerRegistrationHelperAdoptionContract &&
        runRegressionStep aggregate-runner-uses-suite-local-helper-assertion runAggregateRunnerUsesSuiteLocalHelperAssertionContract &&
        runRegressionStep aggregate-runner-uses-suite-local-helper-adoption runAggregateRunnerUsesSuiteLocalHelperAdoptionContract &&
        runRegressionStep aggregate-runner-uses-framework-selector-helper-assertion runAggregateRunnerUsesFrameworkSelectorHelperAssertionContract &&
        runRegressionStep aggregate-runner-uses-framework-selector-helper-adoption runAggregateRunnerUsesFrameworkSelectorHelperAdoptionContract &&
        runRegressionStep aggregate-runner-uses-framework-selector-helper-multiline-assertion runAggregateRunnerUsesFrameworkSelectorHelperMultiLineAssertionContract &&
        runRegressionStep aggregate-runner-uses-framework-selector-helper-multiline-adoption runAggregateRunnerUsesFrameworkSelectorHelperMultiLineAdoptionContract &&
        runRegressionStep contract-function-definitions-unique runContractFunctionDefinitionsUniqueContract &&
        runRegressionStep legacy-public-selector-retirement-assertion runLegacyPublicSelectorRetirementAssertionContract &&
        runRegressionStep legacy-public-selector-retirement-helper-adoption runLegacyPublicSelectorRetirementHelperAdoptionContract &&
        runRegressionStep regression-step-sequence-helper-adoption runRegressionStepSequenceHelperAdoptionContract &&
        runRegressionStep regression-dispatcher-step-coverage-helper-adoption runRegressionDispatcherStepCoverageHelperAdoptionContract &&
        runRegressionStep contract-helper-adoption-helper-adoption runContractHelperAdoptionHelperAdoptionContract &&
        runRegressionStep aggregate-runner-dispatches-children-in-order-helper-adoption runAggregateRunnerDispatchesChildrenInOrderHelperAdoptionContract &&
        runRegressionStep legacy-function-selector-retirement-helper-adoption runLegacyFunctionSelectorRetirementHelperAdoptionContract &&
        runRegressionStep legacy-function-retirement-batch-helper-adoption runLegacyFunctionRetirementBatchHelperAdoptionContract &&
        runRegressionStep subscription-state-cli-retirement-helper-adoption runSubscriptionStateCliRetirementHelperAdoptionContract &&
        runRegressionStep subscription-state-cli-retirement-helper-adoption-covered-by-dispatcher runSubscriptionStateCliRetirementHelperAdoptionCoveredByDispatcherContract &&
        runRegressionStep pre-legacy-suites-avoid-legacy-function-collisions runPreLegacySuitesAvoidLegacyFunctionNameCollisionsContract &&
        runRegressionStep subscription-state-no-implicit-full-fallback runSubscriptionStateNoImplicitFullFallbackContract &&
        runRegressionStep subscription-state-shim-uses-source-only-full runSubscriptionStateShimUsesSourceOnlyFullContract &&
        runRegressionStep subscription-state-shim-stays-thin runSubscriptionStateShimStaysThinContract &&
        runRegressionStep subscription-state-shim-public-cli-retirement runSubscriptionStateShimPublicCliRetirementContract &&
        runRegressionStep legacy-regression-scripts-require-dispatcher runLegacyRegressionScriptsRequireDispatcherContract &&
        runRegressionStep legacy-regression-scripts-retire-internal-cli runLegacyRegressionScriptsRetireInternalCliContract &&
        runRegressionStep subscription-state-suite-uses-function-registry runSubscriptionStateSuiteUsesFunctionRegistryContract &&
        runRegressionStep subscription-state-no-empty-aggregate-wrapper-functions runSubscriptionStateNoEmptyAggregateWrapperFunctionsContract &&
        runRegressionStep subscription-state-selector-helpers-stay-aligned runSubscriptionStateSelectorHelpersStayAlignedContract &&
        runRegressionStep subscription-state-nested-selector-helpers-are-suite-owned runSubscriptionStateNestedSelectorHelpersAreSuiteOwnedContract &&
        runRegressionStep subscription-state-support-child-steps runSubscriptionStateSupportChildStepsContract &&
        runRegressionStep subscription-state-serial-child-steps runSubscriptionStateSerialChildStepsContract &&
        runRegressionStep subscription-state-structure-source-child-steps runSubscriptionStateStructureSourceChildStepsContract &&
        runRegressionStep subscription-state-structure-migration-child-steps runSubscriptionStateStructureMigrationChildStepsContract &&
        runRegressionStep subscription-state-quota-traffic-child-steps runSubscriptionStateQuotaTrafficChildStepsContract &&
        runRegressionStep subscription-state-quota-menu-tx-child-steps runSubscriptionStateQuotaMenuTransactionChildStepsContract &&
        runRegressionStep subscription-state-quota-partial-sync-child-steps runSubscriptionStateQuotaPartialSyncChildStepsContract &&
        runRegressionStep subscription-state-remote-restore-self-reference-child-steps runSubscriptionStateRemoteRestoreSelfReferenceChildStepsContract &&
        runRegressionStep subscription-state-remote-restore-serial-child-steps runSubscriptionStateRemoteRestoreSerialChildStepsContract &&
        runRegressionStep subscription-state-sync-rollback-failure-serial-child-steps runSubscriptionStateSyncRollbackFailureSerialChildStepsContract &&
        runRegressionStep subscription-state-core-aggregate-runner-registration runSubscriptionStateCoreAggregateRunnerRegistrationContract &&
        runRegressionStep subscription-state-aggregate-runner-registration runSubscriptionStateAggregateRunnerRegistrationContract &&
        runRegressionStep subscription-state-nested-aggregate-runner-registration runSubscriptionStateNestedAggregateRunnerRegistrationContract &&
        runRegressionStep subscription-state-full-uses-framework-parallel-helper runSubscriptionStateFullUsesFrameworkParallelHelperContract &&
        runRegressionStep subscription-state-full-public-cli-retirement runSubscriptionStateFullPublicCliRetirementContract &&
        runRegressionStep subscription-state-aggregates-support-source-only runSubscriptionStateAggregatesSupportSourceOnlyExecutionContract &&
        runRegressionStep remote-control-suite-uses-function-registry runRemoteControlSuiteUsesFunctionRegistryContract &&
        runRegressionStep remote-control-public-selector-retirement runRemoteControlPublicSelectorRetirementContract &&
        runRegressionStep legacy-retires-suite-owned-wrappers runLegacyRetiresSuiteOwnedWrappersContract &&
        runRegressionStep remote-control-aggregates-support-source-only runRemoteControlAggregatesSupportSourceOnlyExecutionContract &&
        runRegressionStep remote-control-selector-helpers-stay-aligned runRemoteControlSelectorHelpersStayAlignedContract &&
        runRegressionStep remote-control-nested-selector-helpers-are-suite-owned runRemoteControlNestedSelectorHelpersAreSuiteOwnedContract &&
        runRegressionStep remote-control-leaves-use-compat-helper runRemoteControlLeavesUseCompatHelperContract &&
        runRegressionStep remote-control-no-compat-wrapper-functions runRemoteControlNoCompatWrapperFunctionsContract &&
        runRegressionStep remote-control-smoke-core-no-compat-helper runRemoteControlSmokeCoreNoCompatHelperContract &&
        runRegressionStep remote-control-smoke-refresh-no-compat-helper runRemoteControlSmokeRefreshNoCompatHelperContract &&
        runRegressionStep remote-control-contract-service-install-no-compat-helper runRemoteControlContractServiceInstallNoCompatHelperContract &&
        runRegressionStep remote-control-legacy-tmpdir-isolation-guard-registered runRemoteControlLegacyTmpDirIsolationGuardRegisteredContract &&
        runRegressionStep remote-control-smoke-core-child-steps runRemoteControlSmokeCoreChildStepsContract &&
        runRegressionStep remote-control-aggregate-runner-registration runRemoteControlAggregateRunnerRegistrationContract &&
        runRegressionStep remote-control-nested-aggregate-runner-registration runRemoteControlNestedAggregateRunnerRegistrationContract &&
        runRegressionStep remote-control-aggregate-runner-uses-framework-selector-helper runRemoteControlAggregateRunnerUsesFrameworkSelectorHelperContract &&
        runRegressionStep remote-control-top-level-no-suite-selector-runner runRemoteControlTopLevelNoSuiteSelectorRunnerContract &&
        runRegressionStep fast-suite-uses-function-registry runFastSuiteUsesFunctionRegistryContract &&
        runRegressionStep fast-no-empty-local-wrapper-functions runFastNoEmptyLocalWrapperFunctionsContract &&
        runRegressionStep fast-legacy-retirement runFastLegacyRetirementContract &&
        runRegressionStep fast-public-cli-retirement runFastPublicCliRetirementContract &&
        runRegressionStep fast-reality-selector-helpers-stay-aligned runFastRealitySelectorHelpersStayAlignedContract &&
        runRegressionStep fast-selector-helpers-stay-aligned runFastSelectorHelpersStayAlignedContract &&
        runRegressionStep fast-aggregate-runner-registration runFastAggregateRunnerRegistrationContract &&
        runRegressionStep fast-only-aggregate-runner-registration runFastOnlyAggregateRunnerRegistrationContract &&
        runRegressionStep fast-only-safety-child-steps runFastOnlySafetyChildStepsContract &&
        runRegressionStep fast-only-output-aggregate-runner-registration runFastOnlyOutputAggregateRunnerRegistrationContract &&
        runRegressionStep fast-only-output-auto-install-child-steps runFastOnlyOutputAutoInstallChildStepsContract &&
        runRegressionStep fast-only-output-rest-child-steps runFastOnlyOutputRestChildStepsContract &&
        runRegressionStep fast-only-core-child-steps runFastOnlyCoreChildStepsContract &&
        runRegressionStep fast-reality-aggregate-runner-registration runFastRealityAggregateRunnerRegistrationContract &&
        runRegressionStep fast-reality-legacy-retirement runFastRealityLegacyRetirementContract &&
        runRegressionStep fast-reality-aggregate-runner-dispatches-children-in-order runFastRealityAggregateRunnerDispatchesChildrenInOrderContract &&
        runRegressionStep fast-reality-uses-reality-compat-helper runFastRealityUsesRealityCompatHelperContract &&
        runRegressionStep fast-suite-uses-suite-local-helper runFastSuiteUsesSuiteLocalHelperContract &&
        runRegressionStep platform-suite-uses-function-registry runPlatformSuiteUsesFunctionRegistryContract &&
        runRegressionStep platform-public-selector-retirement runPlatformPublicSelectorRetirementContract &&
        runRegressionStep platform-hot-selector-helpers-stay-aligned runPlatformHotSelectorHelpersStayAlignedContract &&
        runRegressionStep platform-hot-aggregate-runner-registration runPlatformHotAggregateRunnerRegistrationContract &&
        runRegressionStep platform-hot-leaves-use-fast-compat-helper runPlatformHotLeavesUseFastCompatHelperContract &&
        runRegressionStep platform-io-leaves-use-legacy-compat-helper runPlatformIoLeavesUseLegacyCompatHelperContract &&
        runRegressionStep platform-fast-helper-isolation-guard-registered runPlatformFastHelperIsolationGuardRegisteredContract &&
        runRegressionStep platform-update-child-steps runPlatformUpdateChildStepsContract &&
        runRegressionStep platform-refresh-child-steps runPlatformRefreshChildStepsContract &&
        runRegressionStep platform-rest-child-steps runPlatformRestChildStepsContract &&
        runRegressionStep platform-io-child-steps runPlatformIoChildStepsContract &&
        runRegressionStep all-suite-uses-function-registry runAllSuiteUsesFunctionRegistryContract &&
        runRegressionStep all-no-empty-aggregate-wrapper-functions runAllNoEmptyAggregateWrapperFunctionsContract &&
        runRegressionStep all-public-selector-retirement runAllPublicSelectorRetirementContract &&
        runRegressionStep framework-parallel-selector-supports-selector-only-limit runFrameworkParallelSelectorSupportsSelectorOnlyLimitContract &&
        runRegressionStep framework-parallel-selector-supports-selector-only-slot-refill runFrameworkParallelSelectorSupportsSelectorOnlySlotRefillContract &&
        runRegressionStep framework-parallel-selector-list-builds-pair-dispatch runFrameworkParallelSelectorListBuildsPairDispatchContract &&
        runRegressionStep fast-platform-supports-source-only runFastPlatformSourceOnlyExecutionContract &&
        runRegressionStep legacy-suite-uses-function-registry runLegacySuiteUsesFunctionRegistryContract &&
        runRegressionStep targeted-batch-helpers-legacy-retirement runTargetedBatchHelpersLegacyRetirementContract &&
        runRegressionStep targeted-batch-helpers-child-steps runTargetedBatchHelpersChildStepsContract &&
        runRegressionStep platform-suite-uses-suite-local-helpers runPlatformSuiteUsesSuiteLocalHelpersContract &&
        runRegressionStep tls-suite-uses-function-registry runTlsSuiteUsesFunctionRegistryContract &&
        runRegressionStep tls-legacy-retirement runTlsLegacyRetirementContract &&
        runRegressionStep tls-legacy-public-selector-retirement runTlsLegacyPublicSelectorRetirementContract &&
        runRegressionStep tls-suite-child-steps runTlsSuiteChildStepsContract &&
        runRegressionStep tls-selector-helpers-stay-aligned runTlsSelectorHelpersStayAlignedContract &&
        runRegressionStep tls-aggregate-runner-registration runTlsAggregateRunnerRegistrationContract &&
        runRegressionStep tls-no-empty-aggregate-wrapper-functions runTlsNoEmptyAggregateWrapperFunctionsContract &&
        runRegressionStep tls-leaves-use-compat-helper runTlsLeavesUseCompatHelperContract &&
        runRegressionStep tls-legacy-tmpdir-isolation-guard-registered runTlsLegacyTmpDirIsolationGuardRegisteredContract &&
        runRegressionStep legacy-direct-leaf-selectors-use-function-registry runLegacyDirectLeafSelectorsUseFunctionRegistryContract &&
        runRegressionStep composition-leaf-selectors-use-suite-local-registry runCompositionLeafSelectorsUseSuiteLocalRegistryContract &&
        runRegressionStep composition-leaf-selectors-legacy-public-retirement runCompositionLeafSelectorsLegacyPublicRetirementContract &&
        runRegressionStep transaction-direct-leaf-selectors-use-function-registry runTransactionDirectLeafSelectorsUseFunctionRegistryContract &&
        runRegressionStep transaction-no-compat-wrapper-functions runTransactionNoCompatWrapperFunctionsContract &&
        runRegressionStep transaction-subscription-leaves-use-compat-helper runTransactionSubscriptionLeavesUseCompatHelperContract &&
        runRegressionStep transaction-core-direct-leaf-selectors-use-function-registry runTransactionCoreDirectLeafSelectorsUseFunctionRegistryContract &&
        runRegressionStep subscription-direct-leaf-selectors-use-function-registry runSubscriptionDirectLeafSelectorsUseFunctionRegistryContract &&
        runRegressionStep subscription-composition-leaf-selectors-use-function-registry runSubscriptionCompositionLeafSelectorsUseFunctionRegistryContract &&
        runRegressionStep subscription-state-composition-leaf-selectors-use-function-registry runSubscriptionStateCompositionLeafSelectorsUseFunctionRegistryContract &&
        runRegressionStep targeted-subscription-restore-retirement runTargetedSubscriptionRestoreRetirementContract &&
        runRegressionStep subscription-output-legacy-retirement runSubscriptionOutputLegacyRetirementContract &&
        runRegressionStep subscription-selector-helpers-are-suite-owned runSubscriptionSelectorHelpersAreSuiteOwnedContract &&
        runRegressionStep ui-suite-uses-function-registry runUiSuiteUsesFunctionRegistryContract &&
        runRegressionStep ui-smoke-legacy-wrapper-retirement runUiSmokeLegacyWrapperRetirementContract &&
        runRegressionStep ui-full-legacy-wrapper-retirement runUiFullLegacyWrapperRetirementContract &&
        runRegressionStep ui-full-subscription-main-legacy-wrapper-retirement runUiFullSubscriptionMainLegacyWrapperRetirementContract &&
        runRegressionStep ui-wireguard-legacy-wrapper-retirement runUiWireGuardLegacyWrapperRetirementContract &&
        runRegressionStep ui-legacy-public-selector-retirement runUiLegacyPublicSelectorRetirementContract &&
        runRegressionStep ui-public-selectors-use-function-registry runUiPublicSelectorsUseFunctionRegistryContract &&
        runRegressionStep ui-selector-helpers-stay-aligned runUiSelectorHelpersStayAlignedContract &&
        runRegressionStep ui-nested-aggregate-runners-use-shared-suite-helpers runUiNestedAggregateRunnersUseSharedSuiteHelpersContract &&
        runRegressionStep ui-leaves-use-compat-helper runUiLeavesUseCompatHelperContract &&
        runRegressionStep ui-legacy-tmpdir-isolation-guard-registered runUiLegacyTmpDirIsolationGuardRegisteredContract &&
        runRegressionStep ui-aggregate-runner-registration runUiAggregateRunnerRegistrationContract &&
        runRegressionStep ui-aggregate-runner-uses-suite-local-helper runUiAggregateRunnerUsesSuiteLocalHelperContract &&
        runRegressionStep ui-aggregate-runner-uses-framework-selector-helper runUiAggregateRunnerUsesFrameworkSelectorHelperContract &&
        runRegressionStep routing-suite-uses-function-registry runRoutingSuiteUsesFunctionRegistryContract &&
        runRegressionStep routing-legacy-public-selector-retirement runRoutingLegacyPublicSelectorRetirementContract &&
        runRegressionStep routing-selector-helpers-stay-aligned runRoutingSelectorHelpersStayAlignedContract &&
        runRegressionStep routing-aggregate-runner-registration runRoutingAggregateRunnerRegistrationContract &&
        runRegressionStep routing-aggregate-runner-uses-suite-local-helper runRoutingAggregateRunnerUsesSuiteLocalHelperContract &&
        runRegressionStep routing-aggregate-runner-uses-framework-selector-helper runRoutingAggregateRunnerUsesFrameworkSelectorHelperContract &&
        runRegressionStep routing-legacy-leaves-use-compat-helper runRoutingLegacyLeavesUseCompatHelperContract &&
        runRegressionStep routing-legacy-read-install-type-isolation-guard-registered runRoutingLegacyReadInstallTypeIsolationGuardRegisteredContract &&
        runRegressionStep transaction-suite-uses-function-registry runTransactionSuiteUsesFunctionRegistryContract &&
        runRegressionStep transaction-no-empty-aggregate-wrapper-functions runTransactionNoEmptyAggregateWrapperFunctionsContract &&
        runRegressionStep transaction-legacy-tmpdir-isolation-guard-registered runTransactionLegacyTmpDirIsolationGuardRegisteredContract &&
        runRegressionStep transaction-legacy-public-selector-retirement runTransactionLegacyPublicSelectorRetirementContract &&
        runRegressionStep transaction-subscription-child-steps runTransactionSubscriptionChildStepsContract &&
        runRegressionStep transaction-suite-child-steps runTransactionSuiteChildStepsContract &&
        runRegressionStep transaction-core-selector-helpers-stay-aligned runTransactionCoreSelectorHelpersStayAlignedContract &&
        runRegressionStep transaction-core-registered-child-selectors-aligned runTransactionCoreRegisteredChildSelectorsAlignedContract &&
        runRegressionStep transaction-core-aggregate-runner-registration runTransactionCoreAggregateRunnerRegistrationContract &&
        runRegressionStep transaction-selector-helpers-stay-aligned runTransactionSelectorHelpersStayAlignedContract &&
        runRegressionStep transaction-aggregate-runner-registration runTransactionAggregateRunnerRegistrationContract &&
        runRegressionStep transaction-system-aggregate-runner-registration runTransactionSystemAggregateRunnerRegistrationContract &&
        runRegressionStep transaction-sequential-aggregates-use-framework-selector-helper-args runTransactionSequentialAggregatesUseFrameworkSelectorHelperArgsContract &&
        runRegressionStep transaction-core-aggregate-runner-uses-framework-selector-helper runTransactionCoreAggregateRunnerUsesFrameworkSelectorHelperContract &&
        runRegressionStep all-selector-helpers-stay-aligned runAllSelectorHelpersStayAlignedContract &&
        runRegressionStep all-suite-child-steps runAllSuiteChildStepsContract &&
        runRegressionStep all-aggregate-runner-registration runAllAggregateRunnerRegistrationContract &&
        runRegressionStep all-aggregate-runner-uses-suite-local-dispatch-helper runAllAggregateRunnerUsesSuiteLocalDispatchHelperContract &&
        runRegressionStep all-selector-dispatch-avoids-entry-script-spawn runAllSelectorDispatchAvoidsEntryScriptSpawnContract &&
        runRegressionStep all-aggregate-runner-uses-framework-selector-helper runAllAggregateRunnerUsesFrameworkSelectorHelperContract &&
        runRegressionStep subscription-suite-uses-function-registry runSubscriptionSuiteUsesFunctionRegistryContract &&
        runRegressionStep subscription-legacy-public-selector-retirement runSubscriptionLegacyPublicSelectorRetirementContract &&
        runRegressionStep subscription-no-empty-aggregate-wrapper-functions runSubscriptionNoEmptyAggregateWrapperFunctionsContract &&
        runRegressionStep subscription-selector-helpers-stay-aligned runSubscriptionSelectorHelpersStayAlignedContract &&
        runRegressionStep subscription-output-child-steps runSubscriptionOutputChildStepsContract &&
        runRegressionStep subscription-remote-registered-child-selectors-aligned runSubscriptionRemoteRegisteredChildSelectorsAlignedContract &&
        runRegressionStep subscription-tx-registered-child-selectors-aligned runSubscriptionTxRegisteredChildSelectorsAlignedContract &&
        runRegressionStep subscription-aggregate-runner-registration runSubscriptionAggregateRunnerRegistrationContract &&
        runRegressionStep subscription-remote-aggregate-runner-registration runSubscriptionRemoteAggregateRunnerRegistrationContract &&
        runRegressionStep subscription-tx-aggregate-runner-registration runSubscriptionTxAggregateRunnerRegistrationContract &&
        runRegressionStep subscription-aggregate-runners-use-suite-local-helpers runSubscriptionAggregateRunnersUseSuiteLocalHelpersContract &&
        runRegressionStep subscription-aggregate-runners-use-framework-selector-helper runSubscriptionAggregateRunnersUseFrameworkSelectorHelperContract &&
        runRegressionStep reality-suite-uses-function-registry runRealitySuiteUsesFunctionRegistryContract &&
        runRegressionStep reality-legacy-public-selector-retirement runRealityLegacyPublicSelectorRetirementContract &&
        runRegressionStep reality-suite-child-steps runRealitySuiteChildStepsContract &&
        runRegressionStep reality-candidates-aggregate-runner-registration runRealityCandidatesAggregateRunnerRegistrationContract &&
        runRegressionStep reality-candidates-aggregate-runner-dispatches-children-in-order runRealityCandidatesAggregateRunnerDispatchesChildrenInOrderContract &&
        runRegressionStep reality-stream-aggregate-runner-registration runRealityStreamAggregateRunnerRegistrationContract &&
        runRegressionStep reality-stream-aggregate-runner-dispatches-children-in-order runRealityStreamAggregateRunnerDispatchesChildrenInOrderContract &&
        runRegressionStep reality-leaves-use-compat-helper runRealityLeavesUseCompatHelperContract &&
        runRegressionStep reality-legacy-tmpdir-isolation-guard-registered runRealityLegacyTmpDirIsolationGuardRegisteredContract &&
        runRegressionStep runtime-suite-uses-function-registry runRuntimeSuiteUsesFunctionRegistryContract &&
        runRegressionStep runtime-legacy-public-selector-retirement runRuntimeLegacyPublicSelectorRetirementContract &&
        runRegressionStep runtime-suite-child-steps runRuntimeSuiteChildStepsContract &&
        runRegressionStep runtime-selector-helpers-stay-aligned runRuntimeSelectorHelpersStayAlignedContract &&
        runRegressionStep runtime-aggregate-runner-registration runRuntimeAggregateRunnerRegistrationContract &&
        runRegressionStep runtime-aggregate-runner-uses-suite-local-helper runRuntimeAggregateRunnerUsesSuiteLocalHelperContract &&
        runRegressionStep runtime-aggregate-runner-uses-framework-selector-helper runRuntimeAggregateRunnerUsesFrameworkSelectorHelperContract &&
        runRegressionStep runtime-leaves-use-compat-helper runRuntimeLeavesUseCompatHelperContract &&
        runRegressionStep runtime-legacy-tmpdir-isolation-guard-registered runRuntimeLegacyTmpDirIsolationGuardRegisteredContract &&
        runRegressionStep reality-no-empty-aggregate-wrapper-functions runRealityNoEmptyAggregateWrapperFunctionsContract &&
        runRegressionStep parallel-selector-collects-exited-child-without-rc runParallelSelectorCollectsExitedChildWithoutRcContract &&
        runRegressionStep transaction-core-compatible-dispatcher-leaves-execute runTransactionCoreCompatibleDispatcherLeavesExecutionContract &&
        runRegressionStep transaction-system-aggregate-dispatches-children-once runTransactionSystemAggregateDispatchesChildrenExactlyOnceContract &&
        runRegressionStep legacy-reality-stubs-survive-suite-load runLegacyRealityStubsSurviveSuiteLoadContract
}

registerRegressionFunctionLeaf regression-dispatcher-contract runRegressionDispatcherContracts
registerRegressionFunctionLeaf regression-selector-dispatch-composition runRegressionSelectorDispatchCompositionRegression
registerRegressionFunctionLeaf regression-parallel-selector-limit-composition runRegressionParallelSelectorLimitCompositionRegression
registerRegressionFunctionLeaf regression-parallel-selector-slot-refill-composition runRegressionParallelSelectorSlotRefillCompositionRegression
