#!/bin/bash
# ==============================================================================
# The quick offline run, for before a commit: about 2 minutes, against about 8 for run_all.sh.
#
#   ./tests/offline/run_fast.sh            the quick checks, and the slow ones that cover what you changed
#   ./tests/offline/run_fast.sh --list     only say what it would run, and why
#
# It runs every check except the slow ones (tests/offline/lib/fast_plan.py has the list), plus the slow check that names a script you changed,
# a slow check you changed, and the slow checks that use a tool or a stub you changed. run_all.sh still runs everything: it is what has to pass
# before the work is done, and what CI runs.
# ==============================================================================
cd "$(dirname "$0")" || exit 1

if [ "$1" = "--list" ]; then
    python3 lib/fast_plan.py --why
    exit 0
fi

mkdir -p output
RUN_OUTPUT="$(mktemp -d "$(pwd)/output/run.XXXXXX")" || exit 1
export ST_TEST_OUTPUT="${RUN_OUTPUT}"
START=${SECONDS}
PASSED=0
FAILED=0
FAILED_NAMES=()

while IFS= read -r check; do
    name=$(basename "${check}")
    printf '# %s\n' "${name}"
    case "${check}" in
        *.py) python3 "${check}" ;;
        *)    bash "${check}" ;;
    esac
    if [ $? -eq 0 ]; then PASSED=$((PASSED + 1)); else FAILED=$((FAILED + 1)); FAILED_NAMES+=("${name}"); fi
done < <(python3 lib/fast_plan.py --why)

echo "######################################################################"
if [ "${FAILED}" -eq 0 ]; then
    rm -rf "${RUN_OUTPUT}"
    echo "# QUICK RUN PASSED  (${PASSED} checks, $((SECONDS - START)) s). This is not the whole suite: run ./tests/offline/run_all.sh before you call it done."
    echo "######################################################################"
    exit 0
fi
echo "# ${FAILED} CHECK(S) FAILED, ${PASSED} passed ($((SECONDS - START)) s)"
for n in "${FAILED_NAMES[@]}"; do echo "#   ${n}"; done
echo "# The files of this run are kept in ${RUN_OUTPUT}"
echo "######################################################################"
exit 1
