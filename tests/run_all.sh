#!/bin/bash
# ==============================================================================
# Run every check in tests/checks.
#
# Everything runs offline: no SecureTransport server, no credentials, no
# network. It should pass on a fresh clone before anything is configured.
#
#   ./tests/run_all.sh            run everything
#   ./tests/run_all.sh hygiene    run only checks whose name contains 'hygiene'
#
# The checks write their scratch files under ST_TEST_OUTPUT. This script makes a
# folder of its own for it (tests/output/run.XXXXXX), so that two runs at once, or
# a run and a single check, do not delete each other's files. It is removed when
# everything passed and kept, with its path printed, when something failed. A check
# started by hand, with no ST_TEST_OUTPUT, uses tests/output/<its name>.
# ==============================================================================
cd "$(dirname "$0")" || exit 1

FILTER="${1:-}"
PASSED=0
FAILED=0
FAILED_NAMES=()

mkdir -p output
RUN_OUTPUT="$(mktemp -d "$(pwd)/output/run.XXXXXX")" || exit 1
export ST_TEST_OUTPUT="${RUN_OUTPUT}"

for check in $(find checks -type f \( -name 'check_*' -o -name 'test_*' \) | sort); do

    name=$(basename "${check}")
    if [ -n "${FILTER}" ] && [[ "${name}" != *"${FILTER}"* ]]; then
        continue
    fi

    echo "######################################################################"
    echo "# ${name}"
    echo "######################################################################"

    case "${check}" in
        *.py) python3 "${check}" ;;
        *)    bash "${check}" ;;
    esac

    if [ $? -eq 0 ]; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("${name}")
    fi
    echo
done

echo "######################################################################"
if [ "${FAILED}" -eq 0 ]; then
    rm -rf "${RUN_OUTPUT}"
    echo "# ALL CHECKS PASSED  (${PASSED})"
    echo "#"
    echo "# These all run offline. To check the examples against a real server:"
    echo "#   tests/integration/run_integration.sh --mock   try it with no server"
    echo "#   tests/integration/run_integration.sh          read only"
    echo "######################################################################"
    exit 0
fi

echo "# ${FAILED} CHECK(S) FAILED, ${PASSED} passed"
for n in "${FAILED_NAMES[@]}"; do
    echo "#   ${n}"
done
echo "#"
echo "# The files of this run are kept in ${RUN_OUTPUT}"
echo "######################################################################"
exit 1
