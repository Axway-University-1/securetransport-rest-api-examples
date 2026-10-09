#!/bin/bash
# ==============================================================================
# The two optional settings of the Admin examples, ST_EXAMPLE_ACCOUNT and
# ST_SSH_PORT.
#
# 28 Admin examples need an account that already exists: "john". Four of them
# also name the partner's SSH port: 8022. A lab with no john, or another SSH
# port, used to mean editing dozens of files. Now:
#
#   ST_EXAMPLE_ACCOUNT  the account those examples use (default john)
#   ST_SSH_PORT         the SSH port those four use (default 8022)
#
# both read from the environment or from set_variables.local.sh, and neither is
# required. This file runs every one of those scripts against a stub curl and
# checks, for each:
#
#   - without the setting it does exactly what it always did (john, 8022);
#   - with the setting, the account (or port) in the URL or the body is the
#     setting, and john (or 8022) is nowhere in what was sent;
#   - an argument given on the command line still wins over the setting.
#
# The committed set_variables files must not set or require the settings. The bat
# twins cannot run here: their text is checked at the end (the setting is read
# with a default, through a quoted SET, and no raw john or 8022 is left in code).
# The same text check runs on the bash scripts, so a new example that hard-codes
# john again is found here.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd .. && pwd)"
ADMIN_TREE="${REPO}/Admin/API 2.0/bash"
BAT_TREE="${REPO}/Admin/API 2.0/bat"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_example_settings"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/admin" "${WORK}/tmp"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }
sent_has() { if printf '%s\n' "${SENT}" | grep -qE -- "$2"; then pass "$1"; else fail "$1  (nothing sent matches '$2'; sent: $(printf '%s' "${SENT}" | tr '\n' ' ' | cut -c1-300))"; fi; }
sent_hasnt() { if printf '%s\n' "${SENT}" | grep -qE -- "$2"; then fail "$1  ('$2' was sent)"; else pass "$1"; fi; }

# curl: the stub, with a status of its own for each method (see stub_curl_by_method)
cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/stub_curl_real" && chmod +x "${WORK}/bin/stub_curl_real"
cp "${TESTS_DIR}/lib/stub_curl_by_method" "${WORK}/bin/curl" && chmod +x "${WORK}/bin/curl"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/admin/set_variables.sh"

# An empty list answers every look-up, so that a script goes on to the call that names the account
printf '%s' '{"resultSet": {"returnCount": 0, "totalCount": 0}, "result": []}' > "${WORK}/empty.json"

OTHER="zz_other_acct"   # what the setting is set to: it must not look like john, or like what an argument gives
ARG="zz_arg_acct"

# What the look-ups of 09.CompositeRoutes need to answer for the script to go on: a template, a subscription on /inbox, a simple
# route (any one object will do), and for the two scripts that pick a composite route by its account, one of john's and one of OTHER's
printf '%s' '{"resultSet": {"returnCount": 1, "totalCount": 1}, "result": [{"id": "obj-1", "name": "x", "folder": "/inbox"}]}' > "${WORK}/one.json"
printf '%s' '{"resultSet": {"returnCount": 2, "totalCount": 2}, "result": [{"id": "route-john", "name": "CompositeRoute_Subscription", "account": "john", "routeTemplate": "t", "subscriptions": []}, {"id": "route-'"${OTHER}"'", "name": "CompositeRoute_Subscription", "account": "'"${OTHER}"'", "routeTemplate": "t", "subscriptions": []}]}' > "${WORK}/two_accounts.json"

# run REL ARGS...: the script runs with ST_EXAMPLE_ACCOUNT as SET_ACCOUNT and ST_SSH_PORT as SET_PORT (not set at all when empty,
# whatever the caller's own environment holds). SENT is what the stub was asked for: every URL and every body, decoded.
run() {
    local rel="$1" assign=() line
    shift
    [ -n "${SET_ACCOUNT}" ] && assign+=("ST_EXAMPLE_ACCOUNT=${SET_ACCOUNT}")
    [ -n "${SET_PORT}" ] && assign+=("ST_SSH_PORT=${SET_PORT}")
    mkdir -p "${WORK}/admin/$(dirname "${rel}")"
    cp "${ADMIN_TREE}/${rel}" "${WORK}/admin/${rel}"
    rm -f "${WORK}/counter."*
    ( cd "${WORK}/admin/$(dirname "${rel}")" && env -u ST_EXAMPLE_ACCOUNT -u ST_SSH_PORT "${assign[@]}" \
        PATH="${WORK}/bin:${PATH}" TMPDIR="${WORK}/tmp" STUB_COUNTER="${WORK}/counter" STUB_CURL_PRINT_CODE=1 \
        STUB_CURL_GET_BODY="${GET_BODY:-${WORK}/empty.json}" STUB_CURL_LOCATION_ID="id-1" \
        STUB_STATUS_GET=200 STUB_STATUS_POST=201 STUB_STATUS_PUT=204 STUB_STATUS_DELETE=204 STUB_STATUS_HEAD=200 \
        PARTNER_PASSWORD="Pw-1x" SITE_PASSWORD="Pw-1x" \
        bash "./$(basename "${rel}")" "$@" ) > "${WORK}/stdout.txt" 2> "${WORK}/stderr.txt"
    RC=$?
    SENT=$( { sed -n 's/^URL: //p' "${WORK}/stderr.txt"
              sed -n 's/^PAYLOAD_B64: //p' "${WORK}/stderr.txt" | while read -r line; do printf '%s' "${line}" | base64 -d; echo; done; } )
}

# --- the scripts that take the account as their first argument ----------------
ARG_SCRIPTS=(
    "06.TransferSites/05.sites_id_HEAD.sh" "06.TransferSites/06.sites_id_GET.sh"
    "06.TransferSites/09.sites_operations_POST_test.sh" "06.TransferSites/10.sites_operations_POST_test_new.sh"
    "06.TransferSites/11.sites_operations_POST_list.sh"
    "07.Subscriptions/05.subscriptions_id_HEAD.sh" "07.Subscriptions/06.subscriptions_id_GET.sh"
    "07.Subscriptions/12.subscriptions_POST_types.sh" "07.Subscriptions/13.subscriptions_id_DELETE_types.sh"
    "15.Transfers/01.transfers_operations_POST_pull.sh" "16.TransferLogs/01.logs_transfers_GET.sh"
    "35.TransferProfiles/02.transferProfiles_POST.sh" "35.TransferProfiles/03.transferProfiles_id_HEAD.sh"
    "35.TransferProfiles/04.transferProfiles_id_GET.sh"
)
# --- the scripts that always used john, with no argument for it ---------------
FIXED_SCRIPTS=(
    "06.TransferSites/01.sites_POST.sh" "06.TransferSites/02.sites_POST_ssh.sh" "06.TransferSites/03.sites_GET.sh"
    "06.TransferSites/04.sites_id_DELETE.sh"
    "07.Subscriptions/01.subscriptions_GET.sh" "07.Subscriptions/02.subscriptions_POST.sh"
    "07.Subscriptions/03.subscriptions_POST_triggerfile.sh" "07.Subscriptions/04.subscriptions_id_DELETE.sh"
    "09.CompositeRoutes/02.routes_POST.sh" "09.CompositeRoutes/05.routes_POST_composite_subscription.sh"
    "09.CompositeRoutes/06.routes_GET.sh" "09.CompositeRoutes/07.routes_id_DELETE.sh"
    "14.ExpressionLanguage/07.transferSites_downloadPattern.sh" "14.ExpressionLanguage/08.transferSites_dynamicProperties.sh"
)

echo "=== ST_EXAMPLE_ACCOUNT: the scripts that take the account as an argument ==="
for rel in "${ARG_SCRIPTS[@]}"; do
    name="${rel#*/}"
    SET_ACCOUNT="" SET_PORT="" run "${rel}"
    sent_has "${name}: without the setting it uses john" '\bjohn\b'
    sent_hasnt "${name}: ... and nothing else" "${OTHER}|${ARG}"
    SET_ACCOUNT="${OTHER}" SET_PORT="" run "${rel}"
    sent_has "${name}: with ST_EXAMPLE_ACCOUNT it uses that account" "${OTHER}"
    sent_hasnt "${name}: ... and no john" '\bjohn\b'
    SET_ACCOUNT="${OTHER}" SET_PORT="" run "${rel}" "${ARG}"
    sent_has "${name}: an argument wins over the setting" "${ARG}"
    sent_hasnt "${name}: ... and neither the setting nor john is sent" "${OTHER}|\bjohn\b"
done

echo
echo "=== ST_EXAMPLE_ACCOUNT: the scripts that always used john ==="
for rel in "${FIXED_SCRIPTS[@]}"; do
    name="${rel#*/}"
    case "${rel}" in
        09.CompositeRoutes/06.*) continue ;;   # below: it sends nothing with the account in it, it picks the account's routes
        09.CompositeRoutes/07.*) export GET_BODY="${WORK}/two_accounts.json" ;;
        09.CompositeRoutes/*)    export GET_BODY="${WORK}/one.json" ;;
        *)                       unset GET_BODY ;;
    esac
    SET_ACCOUNT="" SET_PORT="" run "${rel}"
    sent_has "${name}: without the setting it uses john" '\bjohn\b'
    SET_ACCOUNT="${OTHER}" SET_PORT="" run "${rel}"
    sent_has "${name}: with ST_EXAMPLE_ACCOUNT it uses that account" "${OTHER}"
    sent_hasnt "${name}: ... and no john" '\bjohn\b'
done
unset GET_BODY
# 09/06 lists the composite routes of the account: of two routes, the account's own is the one it prints
export GET_BODY="${WORK}/two_accounts.json"
SET_ACCOUNT="" SET_PORT="" run "09.CompositeRoutes/06.routes_GET.sh"
expect "06.routes_GET.sh: without the setting it lists john's route, not the other's" \
    "$(grep -c '^route-john ' "${WORK}/stdout.txt"):$(grep -c "^route-${OTHER} " "${WORK}/stdout.txt")" "1:0"
SET_ACCOUNT="${OTHER}" SET_PORT="" run "09.CompositeRoutes/06.routes_GET.sh"
expect "06.routes_GET.sh: with ST_EXAMPLE_ACCOUNT it lists that account's route, not john's" \
    "$(grep -c '^route-john ' "${WORK}/stdout.txt"):$(grep -c "^route-${OTHER} " "${WORK}/stdout.txt")" "0:1"
unset GET_BODY

echo
echo "=== ST_EXAMPLE_ACCOUNT: the login of the SSH sites is the account too ==="
SET_ACCOUNT="${OTHER}" SET_PORT="" run "06.TransferSites/02.sites_POST_ssh.sh"
expect "02: both sites are of the account, and log in as it" "$(printf '%s\n' "${SENT}" | grep -c "\"account\": *\"${OTHER}\".*\"userName\": *\"${OTHER}\"\|\"userName\": *\"${OTHER}\".*\"account\": *\"${OTHER}\"")" "2"
SET_ACCOUNT="${OTHER}" SET_PORT="" run "06.TransferSites/01.sites_POST.sh"
sent_has "01: the HTTP site is of the account and logs in as it" "\"account\": *\"${OTHER}\".*\"userName\": *\"${OTHER}\"|\"userName\": *\"${OTHER}\".*\"account\": *\"${OTHER}\""
SET_ACCOUNT="${OTHER}" SET_PORT="" run "14.ExpressionLanguage/08.transferSites_dynamicProperties.sh"
sent_has "14/08: the account of the site, and its login, are the setting" "\"account\": *\"${OTHER}\""
sent_has "14/08: ... both" "\"userName\": *\"${OTHER}\""
SET_ACCOUNT="${OTHER}" SET_PORT="" run "14.ExpressionLanguage/07.transferSites_downloadPattern.sh"
sent_has "14/07: the account of the site, and its login, are the setting" "\"account\": *\"${OTHER}\""
sent_has "14/07: ... both" "\"userName\": *\"${OTHER}\""
SET_ACCOUNT="${OTHER}" SET_PORT="" run "06.TransferSites/10.sites_operations_POST_test_new.sh"
sent_has "06/10: the login is the account, as before, when no USER is given" "\"username\": *\"${OTHER}\""
SET_ACCOUNT="${OTHER}" SET_PORT="" run "15.Transfers/01.transfers_operations_POST_pull.sh"
sent_has "15/01: the pull is for the account" "\"accountName\": *\"${OTHER}\""
SET_ACCOUNT="" SET_PORT="" run "15.Transfers/01.transfers_operations_POST_pull.sh"
sent_has "15/01: without the setting it is john's" "\"accountName\": *\"john\""
SET_ACCOUNT="${OTHER}" SET_PORT="" run "15.Transfers/01.transfers_operations_POST_pull.sh" "${ARG}"
sent_has "15/01: with an argument it is the argument's" "\"accountName\": *\"${ARG}\""
SET_ACCOUNT="${OTHER}" SET_PORT="" run "06.TransferSites/05.sites_id_HEAD.sh"
sent_has "06/05: the HEAD looks for the site of the account" "account=${OTHER}&"

echo
echo "=== ST_SSH_PORT: the four scripts that name the SSH port ==="
SET_ACCOUNT="" SET_PORT="" run "06.TransferSites/02.sites_POST_ssh.sh"
expect "06/02: without the setting both sites are on 8022" "$(printf '%s\n' "${SENT}" | grep -cE '"port": ?"8022"')" "2"
SET_ACCOUNT="" SET_PORT="2222" run "06.TransferSites/02.sites_POST_ssh.sh"
expect "06/02: with ST_SSH_PORT both sites are on it" "$(printf '%s\n' "${SENT}" | grep -cE '"port": ?"2222"')" "2"
sent_hasnt "06/02: ... and not on 8022" '8022'
SET_ACCOUNT="" SET_PORT="2222" run "06.TransferSites/02.sites_POST_ssh.sh" 3333
expect "06/02: a PORT argument wins over the setting" "$(printf '%s\n' "${SENT}" | grep -cE '"port": ?"3333"')" "2"
SET_ACCOUNT="" SET_PORT="notaport" run "06.TransferSites/02.sites_POST_ssh.sh"
expect "06/02: a setting that is not a port is exit 2, nothing sent" "${RC}:$(printf '%s' "${SENT}" | grep -c .)" "2:0"

SET_ACCOUNT="" SET_PORT="" run "06.TransferSites/10.sites_operations_POST_test_new.sh"
sent_has "06/10: without the setting the partner port is 8022" '"port": ?"8022"'
SET_ACCOUNT="" SET_PORT="2222" run "06.TransferSites/10.sites_operations_POST_test_new.sh"
sent_has "06/10: with ST_SSH_PORT it is that port" '"port": ?"2222"'
sent_hasnt "06/10: ... and not 8022" '8022'
SET_ACCOUNT="" SET_PORT="2222" run "06.TransferSites/10.sites_operations_POST_test_new.sh" "${ARG}" ssh st.example.com 3333
sent_has "06/10: a PORT argument wins over the setting" '"port": ?"3333"'
sent_hasnt "06/10: ... and the setting is not sent" '2222'

for rel in "18.AccountSetup/01.accountSetup_POST.sh" "18.AccountSetup/03.accountSetup_POST_existing.sh"; do
    name="${rel#*/}"
    SET_ACCOUNT="" SET_PORT="" run "${rel}"
    sent_has "${name}: without the setting the site is on 8022" '"port": ?"8022"'
    SET_ACCOUNT="" SET_PORT="2222" run "${rel}"
    sent_has "${name}: with ST_SSH_PORT the site is on it" '"port": ?"2222"'
    sent_hasnt "${name}: ... and not on 8022" '8022'
done

echo
echo "=== the committed set_variables files do not set or require them ==="
seen=$(cd "${ADMIN_TREE}" && env -u ST_EXAMPLE_ACCOUNT -u ST_SSH_PORT ST_ADMIN_LOCAL_VARIABLES=/nonexistent bash -c 'source ./set_variables.sh; echo "rc=$? account=${ST_EXAMPLE_ACCOUNT-unset} port=${ST_SSH_PORT-unset}"' 2>&1 | tail -1)
expect "bash: sourcing set_variables.sh sets neither and does not fail" "${seen}" "rc=0 account=unset port=unset"
( cd "${ADMIN_TREE}" || exit 1
  printf '%s\n' 'export ST_EXAMPLE_ACCOUNT="from_local"' 'export ST_SSH_PORT="2299"' > "${WORK}/local_vars.sh"
  env -u ST_EXAMPLE_ACCOUNT -u ST_SSH_PORT ST_ADMIN_LOCAL_VARIABLES="${WORK}/local_vars.sh" bash -c 'source ./set_variables.sh; echo "account=${ST_EXAMPLE_ACCOUNT} port=${ST_SSH_PORT}"' ) > "${WORK}/local_seen.txt" 2>&1
expect "bash: set_variables.local.sh can set them" "$(cat "${WORK}/local_seen.txt")" "account=from_local port=2299"
SET_ACCOUNT="" SET_PORT=""
bat_vars="${BAT_TREE}/set_variables.bat"
expect "bat: set_variables.bat does not set either (the lines are comments)" "$(tr -d '\r' < "${bat_vars}" | grep -v -i '^ *REM' | grep -c 'ST_EXAMPLE_ACCOUNT\|ST_SSH_PORT')" "0"
for f in "${ADMIN_TREE}/set_variables.sh" "${ADMIN_TREE}/set_variables.local.example.sh" \
         "${BAT_TREE}/set_variables.bat" "${BAT_TREE}/set_variables.local.example.bat"; do
    for var in ST_EXAMPLE_ACCOUNT ST_SSH_PORT; do
        if tr -d '\r' < "${f}" | grep -qE "^(#|REM) *(export |set )?${var}="; then
            pass "$(basename "${f}") shows ${var} as a commented-out line with its default"
        else
            fail "$(basename "${f}") has no commented-out line for ${var}"
        fi
    done
    expect "$(basename "${f}") sets neither for real" "$(tr -d '\r' < "${f}" | grep -cE '^(export |set )(ST_EXAMPLE_ACCOUNT|ST_SSH_PORT)=')" "0"
done
expect "the defaults shown are john and 8022" "$(tr -d '\r' < "${ADMIN_TREE}/set_variables.sh" | grep -cE '^# *(export )?(ST_EXAMPLE_ACCOUNT="john"|ST_SSH_PORT="8022")')" "2"

echo
echo "=== no raw john or 8022 in the code of the bash scripts; the setting is read with a default ==="
ALL_SCRIPTS=("${ARG_SCRIPTS[@]}" "${FIXED_SCRIPTS[@]}")
for rel in "${ALL_SCRIPTS[@]}"; do
    f="${ADMIN_TREE}/${rel}"
    left=$(grep -v '^ *#' "${f}" | sed 's/${ST_EXAMPLE_ACCOUNT:-john}//g; s/${ST_SSH_PORT:-8022}//g' | grep -ciE 'john|8022')
    expect "${rel#*/}: no john or 8022 in its code except as a default" "${left}" "0"
    grep -q 'ST_EXAMPLE_ACCOUNT:-john' "${f}" && pass "${rel#*/}: reads ST_EXAMPLE_ACCOUNT with the default john" \
        || fail "${rel#*/}: does not read ST_EXAMPLE_ACCOUNT with the default john"
done
for rel in 06.TransferSites/02.sites_POST_ssh.sh 06.TransferSites/10.sites_operations_POST_test_new.sh \
           18.AccountSetup/01.accountSetup_POST.sh 18.AccountSetup/03.accountSetup_POST_existing.sh; do
    f="${ADMIN_TREE}/${rel}"
    grep -q 'ST_SSH_PORT:-8022' "${f}" && pass "${rel#*/}: reads ST_SSH_PORT with the default 8022" \
        || fail "${rel#*/}: does not read ST_SSH_PORT with the default 8022"
    expect "${rel#*/}: no 8022 in its code except as a default" "$(grep -v '^ *#' "${f}" | sed 's/${ST_SSH_PORT:-8022}//g' | grep -c 8022)" "0"
done
# Every Admin script of the tree: john is a default, nowhere else, in code (a new example that hard-codes it again is found here)
extra=$(cd "${ADMIN_TREE}" && grep -rlE --include='*.sh' 'john' . | sort | while read -r f; do
    if [ "${f#./set_variables}" != "${f}" ]; then continue; fi
    if grep -v '^ *#' "${f}" | sed 's/${ST_EXAMPLE_ACCOUNT:-john}//g' | grep -qi 'john'; then echo "${f}"; fi
done)
expect "no Admin bash script has john in its code except as the default of ST_EXAMPLE_ACCOUNT" "${extra}" ""

echo
echo "=== the bat twins read the settings the same way (their text: they cannot run here) ==="
bat_code() { tr -d '\r' < "$1" | grep -v -i '^ *REM'; }
for rel in "${ALL_SCRIPTS[@]}"; do
    [ -f "${BAT_TREE}/${rel%.sh}.bat" ] || { [[ "${rel}" == 14.* ]] && continue; fail "${rel#*/}: has a bat twin"; continue; }
    b="${BAT_TREE}/${rel%.sh}.bat"
    n="${rel#*/}"; n="${n%.sh}.bat"
    bat_code "${b}" | grep -qE 'SET "[A-Z_]+=%ST_EXAMPLE_ACCOUNT%"' && pass "${n}: reads ST_EXAMPLE_ACCOUNT, with a quoted SET" \
        || fail "${n}: does not read ST_EXAMPLE_ACCOUNT with a quoted SET"
    bat_code "${b}" | grep -qE '^(IF "%[A-Z_]+%"=="" )?SET "[A-Z_]+=john"$' && pass "${n}: john is the default, when it is still empty" \
        || fail "${n}: has no default john"
    expect "${n}: no john in its code except as that default" "$(bat_code "${b}" | grep -i john | grep -cvE '^(IF "%[A-Z_]+%"=="" )?SET "[A-Z_]+=john"$')" "0"
    # the default must come after the setting is read, or the setting would never win
    expect "${n}: the setting is read before the default is applied" \
        "$(bat_code "${b}" | awk '/ST_EXAMPLE_ACCOUNT%"/ && !r {r=NR} /=john"$/ && !d {d=NR} END {print (r && d && r < d) ? "ok" : "wrong order"}')" "ok"
done
for rel in 06.TransferSites/02.sites_POST_ssh 06.TransferSites/10.sites_operations_POST_test_new \
           18.AccountSetup/01.accountSetup_POST 18.AccountSetup/03.accountSetup_POST_existing; do
    b="${BAT_TREE}/${rel}.bat"
    n="${rel#*/}.bat"
    bat_code "${b}" | grep -qE 'SET "[A-Z_]+=%ST_SSH_PORT%"' && pass "${n}: reads ST_SSH_PORT, with a quoted SET" \
        || fail "${n}: does not read ST_SSH_PORT with a quoted SET"
    bat_code "${b}" | grep -qE '^(IF "%[A-Z_]+%"=="" )?SET "[A-Z_]+=8022"$' && pass "${n}: 8022 is the default, when it is still empty" \
        || fail "${n}: has no default 8022"
    expect "${n}: no 8022 in its code except as that default" "$(bat_code "${b}" | grep 8022 | grep -cvE '^(IF "%[A-Z_]+%"=="" )?SET "[A-Z_]+=8022"$')" "0"
done
# the bat twins of 18 hand the port to PowerShell from the environment, not as text in the command
for rel in 18.AccountSetup/01.accountSetup_POST 18.AccountSetup/03.accountSetup_POST_existing; do
    bat_code "${BAT_TREE}/${rel}.bat" | grep -q 'port=\$env:SSH_PORT' && pass "${rel#*/}.bat: the site's port is read from SSH_PORT" \
        || fail "${rel#*/}.bat: the site's port is not read from SSH_PORT"
done

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "test_bash_example_settings: PASS"
    exit 0
fi
echo "test_bash_example_settings: FAIL"
exit 1
