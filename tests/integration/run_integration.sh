#!/bin/bash
# ==============================================================================
# Run the integration checks against a real SecureTransport.
#
#   tests/integration/run_integration.sh            read only
#   tests/integration/run_integration.sh --write    also exercise the lifecycle
#   tests/integration/run_integration.sh --mock     run against the bundled mock
#   tests/integration/run_integration.sh 46 zones   only the checks whose file name has one of these words
#
# Safety, in the order it is applied:
#
#   1. Without tests/local/integration.conf nothing runs. The suite reports a
#      skip and exits 0, so a clean clone is not a failure.
#   2. The config must say st_confirm_lab="yes". That is a deliberate statement
#      that the server is not production.
#   3. Anything that writes needs BOTH --write on the command line AND
#      st_allow_writes="yes" in the config. Without the second, --write is not
#      even passed on to the checks (each check also repeats the gate itself).
#   4. Objects that get created carry st_object_prefix, default ZZTEST_, and are
#      deleted again even when a check fails.
#
# Each check gets ST_CHECK_TIMEOUT seconds (1800 when not set; 0 turns the limit
# off). A check that hangs is stopped, with SIGTERM so that it cleans up first
# (ST_CHECK_GRACE seconds, 120), and counted as FAILED. See lib/run_check.py.
#
# The config lives in tests/local, which git ignores, so credentials and the
# server address never reach the repository.
# ==============================================================================
cd "$(dirname "$0")" || exit 1
HERE="$(pwd)"
CONF="${ST_INTEGRATION_CONF:-${HERE}/../local/integration.conf}"

WRITE=""
MOCK=""
FILTERS=()
for arg in "$@"; do
    case "${arg}" in
        --write) WRITE="--write" ;;
        --mock)  MOCK="yes" ;;
        -h|--help) sed -n '2,28p' "${HERE}/$(basename "$0")" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "unknown option: ${arg}"; exit 2 ;;
        *) FILTERS+=("${arg}") ;;
    esac
done

MOCK_PID=""
cleanup() {
    if [ -n "${MOCK_PID}" ]; then
        kill "${MOCK_PID}" 2>/dev/null
        wait "${MOCK_PID}" 2>/dev/null   # suppress the shell's job termination notice
    fi
    [ -n "${MOCK_CONF}" ] && rm -f "${MOCK_CONF}"
}
trap cleanup EXIT

# --------------------------------------------------------------------------
# The mock: prove the harness without a real server
# --------------------------------------------------------------------------
if [ -n "${MOCK}" ]; then
    PORT="${MOCK_PORT:-18444}"
    echo "Starting the mock SecureTransport on port ${PORT}"

    # Its own config file, named to the checks by ST_INTEGRATION_CONF: your own
    # tests/local/integration.conf is never moved or touched.
    MOCK_CONF="$(mktemp)"
    CONF="${MOCK_CONF}"
    export ST_INTEGRATION_CONF="${CONF}"
    cat > "${CONF}" <<EOF
# Written by run_integration.sh --mock to a temporary file. Removed when the run finishes.
st_server="127.0.0.1"
st_port="${PORT}"
st_user="apiadmin"
st_password="s3cret"
st_confirm_lab="yes"
st_allow_writes="yes"
st_object_prefix="ZZTEST_"
EOF

    python3 "${HERE}/mock/mock_st.py" --port "${PORT}" >/dev/null 2>&1 &
    MOCK_PID=$!

    for _ in $(seq 1 50); do
        if bash -c "</dev/tcp/127.0.0.1/${PORT}" 2>/dev/null; then break; fi
        sleep 0.2
    done
    if ! bash -c "</dev/tcp/127.0.0.1/${PORT}" 2>/dev/null; then
        echo "the mock did not start"
        exit 1
    fi
    echo "Mock is up. Running the same checks that would run against a real server."
    echo
fi

# --------------------------------------------------------------------------
# Gate 1: is a server configured at all?
# --------------------------------------------------------------------------
if [ ! -f "${CONF}" ]; then
    echo "######################################################################"
    echo "# Integration tests SKIPPED"
    echo "######################################################################"
    echo "There is no tests/local/integration.conf, so no server is configured."
    echo
    echo "To run these against your own SecureTransport:"
    echo "  mkdir -p tests/local"
    echo "  cp tests/integration/integration.conf.example tests/local/integration.conf"
    echo "  \$EDITOR tests/local/integration.conf"
    echo
    echo "To try them with no server at all:"
    echo "  tests/integration/run_integration.sh --mock"
    exit 0
fi

# --------------------------------------------------------------------------
# Gate 2: the config must state that this is not production
# --------------------------------------------------------------------------
CONFIRM=$(grep -E '^st_confirm_lab=' "${CONF}" | head -1 | cut -d'"' -f2)
if [ "${CONFIRM}" != "yes" ]; then
    echo "Refusing to run."
    echo
    echo "tests/local/integration.conf must contain:"
    echo '    st_confirm_lab="yes"'
    echo
    echo "That line is a statement that the server named in the config is a lab"
    echo "system and not production. These checks log in, read objects and, with"
    echo "--write, create and delete an account."
    exit 1
fi

SERVER=$(grep -E '^st_server=' "${CONF}" | head -1 | cut -d'"' -f2)
ALLOW=$(grep -E '^st_allow_writes=' "${CONF}" | head -1 | cut -d'"' -f2 | tr '[:upper:]' '[:lower:]')
PREFIX=$(grep -E '^st_object_prefix=' "${CONF}" | head -1 | cut -d'"' -f2)

# --write reaches a check only when the config allows writing too (the checks accept yes, true or 1, so does this)
case "${ALLOW}" in
    yes|true|1) ALLOWED="yes" ;;
    *)          ALLOWED="" ;;
esac

echo "######################################################################"
echo "# Integration tests"
echo "#   server : ${SERVER}"
if [ -n "${WRITE}" ] && [ -n "${ALLOWED}" ]; then
echo "#   mode   : READ AND WRITE, objects prefixed ${PREFIX:-ZZTEST_}"
elif [ -n "${WRITE}" ]; then
echo "#   mode   : read only, because st_allow_writes is not yes"
WRITE=""
else
echo "#   mode   : read only"
fi
echo "######################################################################"
echo

PASSED=0
FAILED=0
SKIPPED=0
FAILED_NAMES=()
OUTPUT_FILE="$(mktemp)"
trap 'rm -f "${OUTPUT_FILE}"; cleanup' EXIT
START=${SECONDS}

# Only the numbered .py files directly in checks/, in number order (sort -n, so
# that 100 comes after 99). Python leaves compiled copies in checks/__pycache__,
# whose names also start with the number.
for check in $(find checks -maxdepth 1 -name '[0-9]*.py' -type f | sort -t. -k1,1n); do
    name=$(basename "${check}")
    if [ "${#FILTERS[@]}" -gt 0 ]; then
        wanted=""
        for word in "${FILTERS[@]}"; do [[ "${name}" == *"${word}"* ]] && wanted="yes"; done
        [ -z "${wanted}" ] && continue
    fi
    echo "----------------------------------------------------------------------"
    check_start=${SECONDS}
    # Shown as it happens, so a check of several minutes is not silent, and kept to be read
    python3 "${HERE}/lib/run_check.py" "${check}" ${WRITE} 2>&1 | tee "${OUTPUT_FILE}"
    status=${PIPESTATUS[0]}
    echo "  (${name}: $((SECONDS - check_start)) s)"
    # A failure counts whatever else was printed. Otherwise it is a pass only if
    # something was asserted: a check that skipped, or bailed out with 0 passed,
    # is a skip, which is not the same as a pass.
    passes=$(sed -n 's/^  \([0-9][0-9]*\) passed, .*/\1/p' "${OUTPUT_FILE}" | tail -n 1)
    if [ "${status}" -ne 0 ]; then
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("${name}")
    elif [ "${passes:-0}" -gt 0 ]; then
        PASSED=$((PASSED + 1))
    else
        SKIPPED=$((SKIPPED + 1))
    fi
    echo
done

echo "######################################################################"
if [ "${FAILED}" -eq 0 ]; then
    echo "# INTEGRATION PASSED  (${PASSED} check(s), ${SKIPPED} skipped, $((SECONDS - START)) s)"
    echo "######################################################################"
    exit 0
fi
echo "# ${FAILED} INTEGRATION CHECK(S) FAILED, ${PASSED} passed, ${SKIPPED} skipped, $((SECONDS - START)) s"
for n in "${FAILED_NAMES[@]}"; do echo "#   ${n}"; done
echo "######################################################################"
exit 1
