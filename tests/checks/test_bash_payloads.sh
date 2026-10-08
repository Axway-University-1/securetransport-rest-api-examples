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
           "06.TransferSites/02.sites_POST_ssh.sh" \
           "07.Subscriptions/02.subscriptions_POST.sh" \
           "07.Subscriptions/03.subscriptions_POST_triggerfile.sh" \
           "09.CompositeRoutes/03.routes_POST_simple_compress.sh" \
           "09.CompositeRoutes/04.routes_POST_simple_decompress.sh" \
           "09.CompositeRoutes/05.routes_POST_composite_subscription.sh" \
           "15.Transfers/01.transfers_operations_POST_pull.sh" \
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

    # An example that reads a response before sending one needs a body to read. The older
    # examples that were made safe to run bare need their arguments, or their environment, and
    # a stub that answers with the status they check (STUB_CURL_PRINT_CODE makes it print -w).
    GET_BODY=""
    ARGS=()
    EXTRA_ENV=("STUB_CURL_PRINT_CODE=1" "STUB_CURL_STATUS_GET=200" "STUB_CURL_STATUS=204")
    case "${base}" in
        07.servers_POST.sh|10.servers_name_PUT.sh)
            GET_BODY="${TESTS_DIR}/fixtures/server_ssh.json" ;;
        05.routes_POST_composite_subscription.sh)
            GET_BODY="${TESTS_DIR}/fixtures/lookup_result.json" ;;
        01.configurations_PATCH.sh)
            GET_BODY="${TESTS_DIR}/fixtures/option_values.json"; ARGS=(true) ;;
        02.configurations_PATCH_UsageReporting.sh)
            GET_BODY="${TESTS_DIR}/fixtures/option_values.json"
            EXTRA_ENV+=("ST_USAGE_CLIENT_ID=example-client" "ST_USAGE_CLIENT_SECRET=example-secret" "ST_USAGE_ENVIRONMENT_ID=example-env-id"
                        "ST_USAGE_ENVIRONMENT_NAME=Example Env" "ST_USAGE_FILE_PATH=/example/reports" "ST_USAGE_NETWORK_ZONE=example-zone"
                        "ST_USAGE_PLATFORM_API=https://platform.example.com/api" "ST_USAGE_PLATFORM_AUTHENTICATION=https://login.example.com/token"
                        "ST_USAGE_SCHEMA_ID=https://platform.example.com/schema.json" "ST_USAGE_DAYS_TO_INCLUDE=3") ;;
        02.accounts_POST.sh)
            GET_BODY="${TESTS_DIR}/fixtures/user_classes.json"; EXTRA_ENV+=("STUB_CURL_STATUS=201") ;;
        06.accounts_name_PATCH.sh)
            GET_BODY="${TESTS_DIR}/fixtures/account_address_book.json" ;;
        02.applications_POST.sh)
            GET_BODY="${TESTS_DIR}/fixtures/applications_none.json"; ARGS=(once); EXTRA_ENV+=("STUB_CURL_STATUS=201") ;;
        06.applications_name_PATCH.sh)
            GET_BODY="${TESTS_DIR}/fixtures/application_schedule.json" ;;
    esac

    out="${WORK}/${base}.out"
    ( cd "${WORK}/run/sub" && env "${EXTRA_ENV[@]}" PATH="${WORK}/bin:${PATH}" \
        STUB_CURL_GET_BODY="${GET_BODY}" bash "./${base}" "${ARGS[@]}" ) > "${out}" 2>&1

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
        # A shell variable left unexpanded. ${stenv.target} and the like are
        # Expression Language, meant for SecureTransport, and do not match.
        if grep -qE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "${p}"; then
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
           | sed 's#.*/options/##; s#?.*##' | sort -u | wc -l | tr -d ' ')
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
echo "=== The subscription, transfer and route bodies ==="

# The bodies the examples send that SecureTransport is particular about: the
# types it expects, the Expression Language that must reach it untouched, and
# the ids a composite route links together.
python3 - "${WORK}" <<'PY'
import json, os, sys
work = sys.argv[1]
failed = 0

def body(example, n):
    with open(os.path.join(work, example + ".payloads", "payload_%d.json" % n)) as f:
        return json.load(f)

def check(label, ok, got=None):
    global failed
    print(("  PASS  " if ok else "  FAIL  ") + label + ("" if ok or got is None else "  got: %r" % (got,)))
    failed += 0 if ok else 1

try:
    pull, push = body("02.sites_POST_ssh.sh", 1), body("02.sites_POST_ssh.sh", 2)
    check("SSH site: usePassword is a boolean", pull.get("usePassword") is True, pull.get("usePassword"))
    check("SSH site: the port is a string", pull.get("port") == "8022", pull.get("port"))
    check("SSH site: the host is ST_SERVER", pull.get("host") == "st.example.com", pull.get("host"))
    check("SSH pull site: renames on receive, with EL left for ST",
          pull.get("postTransmissionActions") == {"doAsIn": "${stenv.target}_PULLED"},
          pull.get("postTransmissionActions"))
    check("SSH push site: renames on send",
          push.get("postTransmissionActions") == {"doAsOut": "${stenv.target}_PUSHED"},
          push.get("postTransmissionActions"))
    check("SSH push site: has an upload folder and no download folder",
          push.get("uploadFolder") == "/delivered" and "downloadFolder" not in push)

    app, sub = body("02.subscriptions_POST.sh", 1), body("02.subscriptions_POST.sh", 2)
    check("the application is an Advanced Routing one", app.get("type") == "AdvancedRouting", app)
    check("the subscription uses that application", sub.get("application") == app.get("name"))
    check("the subscription pulls with SSH_PULL, inbound",
          sub.get("transferConfigurations") == [{"tag": "PARTNER-IN", "outbound": False, "site": "SSH_PULL"}],
          sub.get("transferConfigurations"))

    trig = body("03.subscriptions_POST_triggerfile.sh", 1)
    pta = trig.get("postTransmissionActions", {})
    cond = pta.get("triggerOnConditionExpression", "")
    check("the trigger condition holds exactly two backslashes",
          cond == "${stenv['target'].matches('.*\\\\.trigger')?1:0}", cond)
    check("the trigger file name is EL with a date",
          trig.get("createFilesList") == {"createFilesListEnabled": True,
                                          "createFilesListFilename": "file_${date('yyyyddMMHHmmss')}.trigger"},
          trig.get("createFilesList"))
    check("routing waits for the trigger file",
          pta.get("submitFilterType") == "TRIGGER_FILE_CONTENT" and pta.get("triggerOnConditionEnabled") is True, pta)

    for example, first in (("03.routes_POST_simple_compress.sh", "Compress"),
                           ("04.routes_POST_simple_decompress.sh", "Decompress")):
        route = body(example, 1)
        steps = route.get("steps", [])
        check(example + ": %s, then SendToPartner" % first,
              [s.get("type") for s in steps] == [first, "SendToPartner"], [s.get("type") for s in steps])
        check(example + ": only the step's own output is sent",
              len(steps) == 2 and steps[1].get("usePrecedingStepFiles") is True
              and steps[1].get("transferSiteExpression") == "SSH_PUSH#!#CVD#!#")
    compress = body("03.routes_POST_simple_compress.sh", 1)["steps"][0]
    check("Compress builds a single ZIP archive",
          compress.get("singleArchiveEnabled") is True and compress.get("compressionType") == "ZIP"
          and compress.get("singleArchiveName") == "compressed_files.zip", compress)
    decompress = body("04.routes_POST_simple_decompress.sh", 1)["steps"][0]
    check("Decompress overwrites a file of the same name",
          decompress.get("filenameCollisionResolutionType") == "OVERWRITE", decompress)

    comp = body("05.routes_POST_composite_subscription.sh", 1)
    check("the composite route inherits the template it looked up", comp.get("routeTemplate") == "obj-1", comp)
    check("the composite route lists the subscription it looked up", comp.get("subscriptions") == ["obj-1"], comp)
    check("the composite route runs the simple route it looked up",
          comp.get("steps") == [{"type": "ExecuteRoute", "status": "ENABLED", "autostart": False, "executeRoute": "obj-1"}],
          comp.get("steps"))

    pull_op = body("01.transfers_operations_POST_pull.sh", 1)
    check("the pull names the account, site and folder, and does not wait",
          pull_op == {"accountName": "john", "site": "SSH_PULL", "destinationDirectory": "/inbox", "awaitResult": False},
          pull_op)
except (OSError, ValueError, KeyError, IndexError) as e:
    check("every expected body was sent", False, e)

sys.exit(1 if failed else 0)
PY
[ $? -ne 0 ] && FAILED=1

if grep -q '^URL: .*/transfers/operations?operation=pull$' "${WORK}/01.transfers_operations_POST_pull.sh.out"; then
    pass "the pull goes to /transfers/operations?operation=pull"
else
    fail "the pull did not go to /transfers/operations?operation=pull"
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
