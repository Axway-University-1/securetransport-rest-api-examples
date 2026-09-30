#!/bin/bash
# ==============================================================================
# Run the curl examples against a stub curl and check what they would send.
#
# This is how a payload bug gets caught without a server. It finds the two
# failure modes that look fine in the source:
#
#   - a single quoted payload, so ${ST_SERVER} is sent as a literal
#   - a payload that is not valid JSON once the shell has expanded it
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd .. && pwd)"

WORK="${TESTS_DIR}/output/bash_payloads"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/run/sub"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }

# The stub has to be named curl and be first on PATH
cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/curl"
chmod +x "${WORK}/bin/curl"

# A set_variables the copied examples will find, with values we can recognise.
# The examples look for it one directory above themselves.
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/run/set_variables.sh"

# Decode the bodies an example emitted, one per file
decode_payloads() {
    local out="$1" dir="$2" i=0
    rm -rf "${dir}" && mkdir -p "${dir}"
    while IFS= read -r b64; do
        i=$((i + 1))
        printf '%s' "${b64}" | base64 -d > "${dir}/payload_${i}.json" 2>/dev/null
    done < <(sed -n 's/^PAYLOAD_B64: //p' "${out}")
    echo "${i}"
}

echo "=== Payloads emitted by the admin bash examples ==="

TOTAL=0

for rel in "06.TransferSites/01.sites_POST.sh" \
           "12.BusinessUnits/01.businessUnits_POST.sh" \
           "13.Configurations/01.configurations_PATCH.sh" \
           "13.Configurations/02.configurations_PATCH_UsageReporting.sh" \
           "05.Accounts/02.accounts_POST.sh" \
           "05.Accounts/06.accounts_name_PATCH.sh" \
           "04.Applications/02.applications_POST.sh" \
           "04.Applications/06.applications_name_PATCH.sh" \
           "03.Connect/07.servers_POST.sh"; do

    src="${REPO}/Admin/API 2.0/bash/${rel}"
    [ -f "${src}" ] || { fail "missing example: ${rel}"; continue; }

    base=$(basename "${rel}")
    cp "${src}" "${WORK}/run/sub/${base}"

    # An example that reads a response before sending one needs a body to read
    GET_BODY=""
    case "${base}" in
        07.servers_POST.sh|10.servers_name_PUT.sh)
            GET_BODY="${TESTS_DIR}/fixtures/server_ssh.json" ;;
    esac

    out="${WORK}/${base}.out"
    ( cd "${WORK}/run/sub" && PATH="${WORK}/bin:${PATH}" \
        STUB_CURL_GET_BODY="${GET_BODY}" bash "./${base}" ) > "${out}" 2>&1

    dir="${WORK}/${base}.payloads"
    n=$(decode_payloads "${out}" "${dir}")
    bad=0

    for p in "${dir}"/payload_*.json; do
        [ -f "${p}" ] || continue
        TOTAL=$((TOTAL + 1))
        if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "${p}" 2>/dev/null; then
            fail "${rel}: $(basename "${p}") is not valid JSON"
            sed 's/^/        /' "${p}" | head -5
            bad=1
        fi
        if grep -q '\${' "${p}"; then
            fail "${rel}: $(basename "${p}") contains an unexpanded \${...}"
            grep -o '\${[A-Za-z_][A-Za-z0-9_]*}' "${p}" | sort -u | sed 's/^/        /'
            bad=1
        fi
    done

    if grep -q 'URL: .*\${' "${out}"; then
        fail "${rel}: a URL contains an unexpanded \${...}"
        bad=1
    fi

    [ "${bad}" -eq 0 ] && pass "${rel}  (${n} payload(s))"
done

echo
echo "=== Variables really were substituted ==="

# The transfer sites example puts the server into the body. Were the payload
# single quoted, this would be the literal string instead of the value.
if grep -q '"host":"st.example.com"' "${WORK}/01.sites_POST.sh.payloads/payload_1.json" 2>/dev/null; then
    pass "01.sites_POST.sh expanded ST_SERVER into the body"
else
    fail "01.sites_POST.sh did not expand ST_SERVER into the body"
fi

# Every call must carry the credentials from set_variables, in the URL host
if grep -q "URL: https://st.example.com:8444/" "${WORK}/01.sites_POST.sh.out"; then
    pass "the URL is built from ST_SERVER and ST_PORT"
else
    fail "the URL was not built from ST_SERVER and ST_PORT"
fi

# The usage reporting example must patch a different option each iteration
DISTINCT=$(grep '^URL: ' "${WORK}/02.configurations_PATCH_UsageReporting.sh.out" \
           | sed 's#.*/options/##' | sort -u | wc -l | tr -d ' ')
if [ "${DISTINCT}" -eq 10 ]; then
    pass "usage reporting patches 10 distinct options"
else
    fail "usage reporting patches ${DISTINCT} distinct options, expected 10"
fi

# The PATCH examples must send a JSON Patch document: a list of operations
for f in "${WORK}/06.accounts_name_PATCH.sh.payloads"/payload_*.json \
         "${WORK}/06.applications_name_PATCH.sh.payloads"/payload_*.json; do
    [ -f "${f}" ] || continue
    python3 - "${f}" <<'PY' || FAILED=1
import json, sys
doc = json.load(open(sys.argv[1]))
assert isinstance(doc, list), "a JSON Patch body must be a list"
for op in doc:
    assert op.get("op") in ("add", "replace", "remove"), op.get("op")
    assert str(op.get("path", "")).startswith("/"), op.get("path")
PY
done
pass "PATCH bodies are well formed JSON Patch documents"

# The GET, edit, POST example must send back the object it read, with only the
# intended fields changed. This is the regression guard for the text
# substitution bug described in .claude/skills/st-api-gotchas/SKILL.md.
EDITED="${WORK}/07.servers_POST.sh.payloads/payload_2.json"
if [ -f "${EDITED}" ]; then
    python3 - "${EDITED}" <<'PY'
import json, sys
o = json.load(open(sys.argv[1]))
checks = [
    ("serverName was changed",        o.get("serverName") == "SSH_TEST_SERVER_2"),
    # The example picks 8022 + RANDOM % 10, so asserting "not 8022" would fail
    # about one run in ten. Assert the range instead.
    ("port is in the generated range", isinstance(o.get("port"), int)
                                       and 8022 <= o.get("port") <= 8031),
    ("clientPasswordAuth was set",    o.get("clientPasswordAuth") == "default"),
    ("the nested object survived",    o.get("advanced") == {"port": 9999, "proxyPort": 1080}),
    ("unrelated text was untouched",  o.get("notes") == "SSH_TEST_SERVER_1 is the primary"),
]
bad = [label for label, ok in checks if not ok]
for label, ok in checks:
    print(("  PASS  07.servers_POST.sh: " if ok else "  FAIL  07.servers_POST.sh: ") + label)
sys.exit(1 if bad else 0)
PY
    [ $? -ne 0 ] && FAILED=1
else
    fail "07.servers_POST.sh produced no edited payload to check"
fi

echo
echo "  ${TOTAL} payloads checked"
echo
if [ "${FAILED}" -eq 0 ]; then
    echo "test_bash_payloads: PASS"
else
    echo "test_bash_payloads: FAIL"
fi
exit "${FAILED}"
