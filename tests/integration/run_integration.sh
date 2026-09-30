#!/bin/bash
# ==============================================================================
# Run the integration checks against a real SecureTransport.
#
#   tests/integration/run_integration.sh            read only
#   tests/integration/run_integration.sh --write    also exercise the lifecycle
#   tests/integration/run_integration.sh --mock     run against the bundled mock
#
# Safety, in the order it is applied:
#
#   1. Without tests/local/integration.conf nothing runs. The suite reports a
#      skip and exits 0, so a clean clone is not a failure.
#   2. The config must say st_confirm_lab="yes". That is a deliberate statement
#      that the server is not production.
#   3. Anything that writes needs BOTH --write on the command line AND
#      st_allow_writes="yes" in the config.
#   4. Objects that get created carry st_object_prefix, default ZZTEST_, and are
#      deleted again even when a check fails.
#
# The config lives in tests/local, which git ignores, so credentials and the
# server address never reach the repository.
# ==============================================================================
cd "$(dirname "$0")" || exit 1
HERE="$(pwd)"
CONF="${HERE}/../local/integration.conf"

WRITE=""
MOCK=""
for arg in "$@"; do
    case "${arg}" in
        --write) WRITE="--write" ;;
        --mock)  MOCK="yes" ;;
        -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: ${arg}"; exit 2 ;;
    esac
done

MOCK_PID=""
cleanup() {
    if [ -n "${MOCK_PID}" ]; then
        kill "${MOCK_PID}" 2>/dev/null
        wait "${MOCK_PID}" 2>/dev/null   # suppress the shell's job termination notice
    fi
    [ -n "${MOCK_CONF_BACKUP}" ] && mv -f "${MOCK_CONF_BACKUP}" "${CONF}" 2>/dev/null
    [ -n "${MOCK}" ] && [ -z "${MOCK_CONF_BACKUP}" ] && rm -f "${CONF}"
}
trap cleanup EXIT

# --------------------------------------------------------------------------
# The mock: prove the harness without a real server
# --------------------------------------------------------------------------
if [ -n "${MOCK}" ]; then
    PORT="${MOCK_PORT:-18444}"
    echo "Starting the mock SecureTransport on port ${PORT}"

    mkdir -p "${HERE}/../local"
    if [ -f "${CONF}" ]; then
        MOCK_CONF_BACKUP="${CONF}.realbackup"
        mv "${CONF}" "${MOCK_CONF_BACKUP}"
    fi
    cat > "${CONF}" <<EOF
# Written by run_integration.sh --mock. Removed when the run finishes.
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
ALLOW=$(grep -E '^st_allow_writes=' "${CONF}" | head -1 | cut -d'"' -f2)
PREFIX=$(grep -E '^st_object_prefix=' "${CONF}" | head -1 | cut -d'"' -f2)

echo "######################################################################"
echo "# Integration tests"
echo "#   server : ${SERVER}"
if [ -n "${WRITE}" ] && [ "${ALLOW}" = "yes" ]; then
echo "#   mode   : READ AND WRITE, objects prefixed ${PREFIX:-ZZTEST_}"
elif [ -n "${WRITE}" ]; then
echo "#   mode   : read only, because st_allow_writes is not yes"
else
echo "#   mode   : read only"
fi
echo "######################################################################"
echo

PASSED=0
FAILED=0
SKIPPED=0
FAILED_NAMES=()

for check in $(find checks -name '[0-9]*' -type f | sort); do
    name=$(basename "${check}")
    echo "----------------------------------------------------------------------"
    out=$(python3 "${check}" ${WRITE} 2>&1)
    status=$?
    echo "${out}"
    if echo "${out}" | grep -q "  SKIP  "; then
        SKIPPED=$((SKIPPED + 1))
    elif [ "${status}" -eq 0 ]; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("${name}")
    fi
    echo
done

echo "######################################################################"
if [ "${FAILED}" -eq 0 ]; then
    echo "# INTEGRATION PASSED  (${PASSED} check(s), ${SKIPPED} skipped)"
    echo "######################################################################"
    exit 0
fi
echo "# ${FAILED} INTEGRATION CHECK(S) FAILED, ${PASSED} passed, ${SKIPPED} skipped"
for n in "${FAILED_NAMES[@]}"; do echo "#   ${n}"; done
echo "######################################################################"
exit 1
