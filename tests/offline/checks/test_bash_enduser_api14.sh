#!/bin/bash
# ==============================================================================
# Run the End User API 1.4 mailbox examples (EndUser/API 1.4/bash/01.Mailbox) against a stub curl, and check the call each one makes: the method, the
# URL (the /api/v1.4/mailbox base), the form fields or the JSON body, the credentials (Basic authentication, no session), the headers, what it prints
# for an answer, and its exit code.
#
# 01 to 04 the reads (the folder listing always sends limit and offset); 05 the draft: the 500 "Draft was not saved" that still saved it (the draft that is
# new in the Drafts folder is the one), no new draft, a plain 200, another refusal, the security levels; 06 to 09 the reads of a message; 07 the send with
# and without the notification, the refusals of the server; 10 the JSON body of isRead; 11 to 13 the move and the deletes; 14 the search; 15 the history;
# 16 and 17 the attachment, a file that is not there, a file that exists is not overwritten. All of them: wrong use is exit 2 with nothing sent, a missing
# settings file is exit 1 with nothing sent, a refusal is exit 1 with the reason of the mailbox ({error, errorDescription}).
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd ../.. && pwd)"
API14="${REPO}/EndUser/API 1.4/bash"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_enduser_api14"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/tree/API 1.4"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }
has() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then pass "$1"; else fail "$1  (no '$2' in the output)"; fi; }
hasnt() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then fail "$1  ('$2' is in the output)"; else pass "$1"; fi; }

cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/stub_curl_real" && chmod +x "${WORK}/bin/stub_curl_real"
cp "${TESTS_DIR}/lib/stub_curl_by_method" "${WORK}/bin/curl" && chmod +x "${WORK}/bin/curl"
cp -R "${API14}" "${WORK}/tree/API 1.4/"
TREE="${WORK}/tree/API 1.4/bash"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${TREE}/set_variables.local.sh"
BASE="https://st.example.com:8444/api/v1.4/mailbox"
MID="0123456789abcdef0123456789abcdef"
SID="fedcba9876543210fedcba9876543210"

body() { printf '%s\n' "$2" > "${WORK}/$1.json"; echo "${WORK}/$1.json"; }
# run SCRIPT [PARAMS]: GET_BODY, POST_BODY and OTHER_BODY are the files served; GET_STATUS, POST_STATUS, PUT_STATUS and DELETE_STATUS the codes
run() {
    local rel="$1"; shift
    rm -rf "${WORK}/seq"; [ -n "${SEQ:-}" ] && cp -R "${SEQ}" "${WORK}/seq"
    OUT=$(cd "${TREE}/01.Mailbox" && env -u ST_ENDUSER_LOCAL_VARIABLES PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${GET_BODY:-}" STUB_CURL_POST_BODY="${POST_BODY:-}" STUB_CURL_OTHER_BODY="${OTHER_BODY:-}" \
          STUB_CURL_GET_SEQUENCE="$([ -n "${SEQ:-}" ] && echo "${WORK}/seq")" STUB_STATUS_GET="${GET_STATUS:-200}" STUB_STATUS_POST="${POST_STATUS:-200}" STUB_STATUS_PUT="${PUT_STATUS:-200}" \
          STUB_STATUS_DELETE="${DELETE_STATUS:-200}" STUB_CURL_STATUS=200 STUB_CURL_PRINT_CODE=1 bash "./${rel}" "$@" 2>&1)
    RC=$?
}
calls() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
ncalls() { calls | wc -l | tr -d ' '; }
fields() { printf '%s\n' "${OUT}" | sed -n 's/^FORM_FIELD: //p' | tr '\n' ' '; }
payload() { printf '%s\n' "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | sed -n "${1}p" | base64 -d; }
ERR_JSON="$(body err '{"error":"Draft was not saved.","errorDescription":"Internal error","errorCode":"internalError"}')"
NOMSG="$(body nomsg '{"error":"The message you have requested is not available","errorDescription":"Requested message is not available"}')"
# a usage check: the same call with the wrong parameters is exit 2, nothing sent
usage() { run "$1" "${@:2}"; expect "$1: ${USAGE_LABEL} is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"; }
# a refusal: exit 1 with the reason in both of its fields
refused() {   # SCRIPT STATUSVAR PARAMS...: the answer is a refusal (403) with the mailbox's error body
    local s="$1" var="$2"; shift 2
    printf -v "${var}" '%s' 403
    GET_BODY="${NOMSG}" POST_BODY="${NOMSG}" OTHER_BODY="${NOMSG}" run "${s}" "$@"
    unset "${var}"
    expect "${s}: a refusal is exit 1" "${RC}" "1"
    has "${s}: and it prints the error and its description" "The message you have requested is not available - Requested message is not available"
}

echo "=== 01 myself ==="
GET_BODY="$(body me '{"username":"john","email":"john@example.com","displayName":"John","unlicensed":false}')" run 01.mailbox_myself_GET.sh
expect "01: exit 0, one GET of /api/v1.4/mailbox/myself" "${RC}:$(calls | grep -c "^GET ${BASE}/myself$")" "0:1"
has "01: as the user, Basic authentication" "BASIC_AUTH: apiadmin:"
has "01: with a Referer and an accept header" "HEADER: Referer:"
has "01: it prints each field" "  email: john@example.com"
usage 01.mailbox_myself_GET.sh x
refused 01.mailbox_myself_GET.sh GET_STATUS

echo "=== 02 folders ==="
GET_BODY="$(body f1 '[{"name":"Inbox","nMessages":2,"nUnreadMessages":1,"isInbox":true},{"name":"Sent","nMessages":0,"nUnreadMessages":0}]')" run 02.mailbox_folders_GET.sh
expect "02: exit 0, one GET of /mailbox/folders" "${RC}:$(calls | grep -c "^GET ${BASE}/folders$")" "0:1"
has "02: it prints each folder with its counts" "  Inbox: 2 messages, 1 unread"
usage 02.mailbox_folders_GET.sh x
refused 02.mailbox_folders_GET.sh GET_STATUS

echo "=== 03 folder POST ==="
POST_STATUS=204 run 03.mailbox_folders_POST.sh Archive
expect "03: exit 0, one POST to /mailbox/folders" "${RC}:$(calls | grep -c "^POST ${BASE}/folders$")" "0:1"
expect "03: the name is a form field" "$(fields)" "name=Archive "
hasnt "03: and no JSON body is sent" "PAYLOAD_B64"
has "03: it says so" "The folder Archive was made (HTTP 204)."
run 03.mailbox_folders_POST.sh "My folder"
expect "03: a name with a space is one field" "$(fields)" "name=My folder "
POST_STATUS=200 run 03.mailbox_folders_POST.sh Archive
expect "03: an answer that is not 204 is exit 1" "${RC}" "1"
refused 03.mailbox_folders_POST.sh POST_STATUS Archive
USAGE_LABEL="no NAME" usage 03.mailbox_folders_POST.sh
USAGE_LABEL="an empty NAME" usage 03.mailbox_folders_POST.sh ""
USAGE_LABEL="two names" usage 03.mailbox_folders_POST.sh a b

echo "=== 04 folder messages ==="
LIST="$(body l1 '{"nRecords":2,"nDisplayRecords":2,"data":[{"id":"'${MID}'","subject":"Hello","unread":true,"sender":{"address":"a@example.com"}},{"id":"'${SID}'","subject":"Again","unread":false,"sender":{"address":"b@example.com"}}]}')"
GET_BODY="${LIST}" run 04.mailbox_folders_name_GET.sh
expect "04: exit 0, the Inbox, with limit and offset (without them the server lists nothing)" "${RC}:$(calls | grep -c "^GET ${BASE}/folders/Inbox?limit=10&offset=0$")" "0:1"
has "04: the count and what was listed" "Inbox: 2 messages, 2 listed."
has "04: each message with its id, read or unread, sender and subject" "  ${MID}  unread  from a@example.com  Hello"
has "04: a read one" "  ${SID}  read  from b@example.com  Again"
GET_BODY="${LIST}" run 04.mailbox_folders_name_GET.sh "Sent items" 50
expect "04: another folder with a space is encoded, and the limit is the one given" "$(calls | grep -c "^GET ${BASE}/folders/Sent%20items?limit=50&offset=0$")" "1"
GET_BODY="$(body l0 '{"nRecords":0,"nDisplayRecords":0,"data":[]}')" run 04.mailbox_folders_name_GET.sh
has "04: an empty folder is 0 messages" "Inbox: 0 messages, 0 listed."
for bad in "Inbox 0" "Inbox x" "Inbox -1"; do USAGE_LABEL="a LIMIT '${bad#Inbox }'" usage 04.mailbox_folders_name_GET.sh ${bad}; done
USAGE_LABEL="three parameters" usage 04.mailbox_folders_name_GET.sh a 1 c
refused 04.mailbox_folders_name_GET.sh GET_STATUS

echo "=== 05 the draft ==="
mkdir -p "${WORK}/seqA" "${WORK}/seqB" "${WORK}/seqC"
printf '%s\n' '{"nRecords":1,"data":[{"id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]}' > "${WORK}/seqA/1.json"; printf '%s\n' '{"nRecords":2,"data":[{"id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},{"id":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}' > "${WORK}/seqA/2.json"
SEQ="${WORK}/seqA" POST_BODY="${ERR_JSON}" POST_STATUS=500 run 05.mailbox_messages_POST_draft.sh "r@example.com" "A subject" "The text"
expect "05: a 500 that saved the draft is exit 0: two reads of Drafts, one POST between them" "${RC}:$(calls | grep -c '^GET'):$(calls | grep -c '^POST')" "0:2:1"
expect "05: the reads are the Drafts folder, with limit and offset" "$(calls | grep -c "^GET ${BASE}/folders/Drafts?limit=100&offset=0$")" "2"
expect "05: the POST is to /mailbox/messages with the form fields, security EXISTING_ACCOUNT by default" "$(calls | grep -c "^POST ${BASE}/messages$"):$(fields)" "1:to=r@example.com subject=A subject message=The text security=EXISTING_ACCOUNT "
has "05: it says the server answered 500 and the draft is there" "The server answered 500 (Draft was not saved. - Internal error), but the draft is in the Drafts folder."
has "05: and prints the id of the NEW draft" "Its id: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
printf '%s\n' '{"nRecords":1,"data":[{"id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]}' > "${WORK}/seqB/1.json"
SEQ="${WORK}/seqB" POST_BODY="${ERR_JSON}" POST_STATUS=500 run 05.mailbox_messages_POST_draft.sh "r@example.com" "A subject"
expect "05: a 500 and no new draft is exit 1" "${RC}" "1"
has "05: it says nothing can be said about the id" "The Drafts folder holds no single new draft"
printf '%s\n' '{"nRecords":1,"data":[]}' > "${WORK}/seqC/1.json"; printf '%s\n' '{"nRecords":3,"data":[{"id":"cccccccccccccccccccccccccccccccc"},{"id":"dddddddddddddddddddddddddddddddd"}]}' > "${WORK}/seqC/2.json"
SEQ="${WORK}/seqC" POST_BODY="${ERR_JSON}" POST_STATUS=500 run 05.mailbox_messages_POST_draft.sh "r@example.com" "A subject"
expect "05: two new drafts are not one: exit 1" "${RC}" "1"
POST_BODY="$(body ok '{"messageId":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}')" POST_STATUS=200 run 05.mailbox_messages_POST_draft.sh "r@example.com" "A subject"
expect "05: a 200 is exit 0 with the id from the answer" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'Its id: eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee')" "0:1"
POST_BODY="$(body e4 '{"error":"Message recipient may not be empty."}')" POST_STATUS=400 run 05.mailbox_messages_POST_draft.sh "r@example.com" "A subject"
expect "05: any other refusal is exit 1 with its reason" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'Could not make the draft (HTTP 400): Message recipient may not be empty.')" "1:1"
run 05.mailbox_messages_POST_draft.sh "a@example.com,b@example.com" "S" "" ENROLL_LICENSED
expect "05: several recipients go as one field, and the security given is sent" "$(fields)" "to=a@example.com,b@example.com subject=S message= security=ENROLL_LICENSED "
USAGE_LABEL="one parameter" usage 05.mailbox_messages_POST_draft.sh a@b
USAGE_LABEL="an empty SUBJECT" usage 05.mailbox_messages_POST_draft.sh a@b ""
USAGE_LABEL="a SECURITY that does not exist" usage 05.mailbox_messages_POST_draft.sh a@b s t BOGUS
USAGE_LABEL="five parameters" usage 05.mailbox_messages_POST_draft.sh a b c d e

echo "=== 06 a message ==="
MSG='{"subject":"Hello","folder":"Inbox","isDraft":false,"unread":true,"security":"EXISTING_ACCOUNT","size":0,"sender":{"address":"a@example.com"},"recipients":[{"address":"r@example.com","category":"to"},{"address":"c@example.com","category":"cc"}],"content":[{"streamId":"'${SID}'","type":"text/plain","size":0}],"attachments":[{"streamId":"abcdabcdabcdabcdabcdabcdabcdabcd","filename":"att.txt","size":0}]}'
GET_BODY="$(body m1 "${MSG}")" run 06.mailbox_messages_id_GET.sh "${MID}"
expect "06: exit 0, one GET of the message" "${RC}:$(calls | grep -c "^GET ${BASE}/messages/${MID}$")" "0:1"
has "06: subject, folder, from" "  subject: Hello"
has "06: only the recipients of the to category" "  to: r@example.com"
has "06: unread" "  unread: true"
has "06: the text stream, with its type and size" "  text streams: ${SID} (text/plain, 0 bytes)"
has "06: the attachment, with its stream id and name" "  attachments: abcdabcdabcdabcdabcdabcdabcdabcd att.txt (0 bytes)"
USAGE_LABEL="no id" usage 06.mailbox_messages_id_GET.sh
USAGE_LABEL="an id with a slash" usage 06.mailbox_messages_id_GET.sh "a/b"
USAGE_LABEL="an id with a space" usage 06.mailbox_messages_id_GET.sh "a b"
refused 06.mailbox_messages_id_GET.sh GET_STATUS "${MID}"

echo "=== 07 send ==="
OTHER_BODY="$(body sent '{"info":"Your message has been sent.","messageId":"'${MID}'"}')" run 07.mailbox_messages_id_send_PUT.sh "${MID}"
expect "07: exit 0, one PUT of /send, the delivery notification switched off by default" "${RC}:$(calls | grep -c "^PUT ${BASE}/messages/${MID}/send?disableDeliveryNotification=true$")" "0:1"
has "07: it prints what the server says" "HTTP 200: Your message has been sent."
OTHER_BODY="$(body sent2 '{"info":"Your message has been sent."}')" run 07.mailbox_messages_id_send_PUT.sh "${MID}" yes
expect "07: NOTIFY yes sends no such parameter" "$(calls | grep -c "^PUT ${BASE}/messages/${MID}/send$")" "1"
PUT_STATUS=400 OTHER_BODY="$(body e7 '{"error":"Message security level may not be empty."}')" run 07.mailbox_messages_id_send_PUT.sh "${MID}"
expect "07: a refusal is exit 1 with its reason" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'Could not send the message (HTTP 400): Message security level may not be empty.')" "1:1"
USAGE_LABEL="no id" usage 07.mailbox_messages_id_send_PUT.sh
USAGE_LABEL="a NOTIFY that is not yes or no" usage 07.mailbox_messages_id_send_PUT.sh "${MID}" maybe
USAGE_LABEL="three parameters" usage 07.mailbox_messages_id_send_PUT.sh "${MID}" yes x

echo "=== 08 the text ==="
GET_BODY="$(body txt 'Hello text')" run 08.mailbox_messages_id_content_GET.sh "${MID}" "${SID}"
expect "08: exit 0, one GET of the content stream, asking for text/plain" "${RC}:$(calls | grep -c "^GET ${BASE}/messages/${MID}/content/${SID}$"):$(printf '%s\n' "${OUT}" | grep -c '^HEADER: accept: text/plain')" "0:1:1"
has "08: it prints the text" "Hello text"
GET_BODY="$(body empty '[]')" run 08.mailbox_messages_id_content_GET.sh "${MID}" "${SID}"
expect "08: the empty list the lab answers is said to be an empty text, exit 0" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'HTTP 200, and the text is empty.')" "0:1"
USAGE_LABEL="one parameter" usage 08.mailbox_messages_id_content_GET.sh "${MID}"
USAGE_LABEL="a STREAM_ID with a slash" usage 08.mailbox_messages_id_content_GET.sh "${MID}" "a/b"
refused 08.mailbox_messages_id_content_GET.sh GET_STATUS "${MID}" "${SID}"

echo "=== 09 the properties ==="
GET_BODY="$(body cp '{"packageCustomProperties":[{"name":"isRead","value":"false"}]}')" run 09.mailbox_messages_id_customProperties_GET.sh "${MID}"
expect "09: exit 0, one GET of customProperties" "${RC}:$(calls | grep -c "^GET ${BASE}/messages/${MID}/customProperties$")" "0:1"
has "09: it prints each property" "  isRead: false"
USAGE_LABEL="no id" usage 09.mailbox_messages_id_customProperties_GET.sh
refused 09.mailbox_messages_id_customProperties_GET.sh GET_STATUS "${MID}"

echo "=== 10 mark read ==="
PUT_STATUS=204 run 10.mailbox_messages_id_customProperties_PUT_read.sh "${MID}"
expect "10: exit 0, one PUT of customProperties, JSON" "${RC}:$(calls | grep -c "^PUT ${BASE}/messages/${MID}/customProperties$"):$(printf '%s\n' "${OUT}" | grep -c '^HEADER: Content-Type: application/json')" "0:1:1"
expect "10: the body is isRead true by default" "$(payload 1 | jq -c .)" '{"packageCustomProperties":[{"name":"isRead","value":"true"}]}'
PUT_STATUS=204 run 10.mailbox_messages_id_customProperties_PUT_read.sh "${MID}" false
expect "10: false is sent as the text false" "$(payload 1 | jq -r '.packageCustomProperties[0].value')" "false"
has "10: it says so" "isRead is false (HTTP 204)."
PUT_STATUS=200 run 10.mailbox_messages_id_customProperties_PUT_read.sh "${MID}"
expect "10: an answer that is not 204 is exit 1" "${RC}" "1"
USAGE_LABEL="a READ that is not true or false" usage 10.mailbox_messages_id_customProperties_PUT_read.sh "${MID}" yes
USAGE_LABEL="no id" usage 10.mailbox_messages_id_customProperties_PUT_read.sh

echo "=== 11 move ==="
PUT_STATUS=204 run 11.mailbox_messages_id_folder_PUT.sh "${MID}" "My folder"
expect "11: exit 0, one PUT of /folder, the name as a form field" "${RC}:$(calls | grep -c "^PUT ${BASE}/messages/${MID}/folder$"):$(fields)" "0:1:name=My folder "
has "11: it says so" "The message is in My folder now (HTTP 204)."
PUT_STATUS=500 OTHER_BODY="$(body e11 '{"error":"Unable to move message. General failure.","errorDescription":"Internal error"}')" run 11.mailbox_messages_id_folder_PUT.sh "${MID}" Nowhere
expect "11: a folder that is not there is exit 1 with the reason" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'Unable to move message. General failure. - Internal error')" "1:1"
USAGE_LABEL="no folder" usage 11.mailbox_messages_id_folder_PUT.sh "${MID}"
USAGE_LABEL="an empty folder" usage 11.mailbox_messages_id_folder_PUT.sh "${MID}" ""

echo "=== 12 delete a message, 13 delete a folder ==="
OTHER_BODY="$(body del '{"info":"Deletion was successful"}')" run 12.mailbox_messages_id_DELETE.sh "${MID}"
expect "12: exit 0, one DELETE of the message" "${RC}:$(calls | grep -c "^DELETE ${BASE}/messages/${MID}$")" "0:1"
has "12: it prints what the server says" "HTTP 200: Deletion was successful"
DELETE_STATUS=404 OTHER_BODY="${NOMSG}" run 12.mailbox_messages_id_DELETE.sh "${MID}"
expect "12: a message that is not there is exit 1 with the reason" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'HTTP 404): The message you have requested is not available')" "1:1"
USAGE_LABEL="no id" usage 12.mailbox_messages_id_DELETE.sh
OTHER_BODY="${NOMSG}" run 13.mailbox_folders_name_DELETE.sh "My folder"
expect "13: the DELETE of a folder encodes its name" "$(calls | grep -c "^DELETE ${BASE}/folders/My%20folder$")" "1"
OTHER_BODY="$(body del2 '{"info":"Deletion was successful"}')" run 13.mailbox_folders_name_DELETE.sh Archive
expect "13: exit 0 and what the server says" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'HTTP 200: Deletion was successful')" "0:1"
DELETE_STATUS=403 OTHER_BODY="$(body e13 '{"error":"Unable to remove folder because it is not empty.","errorDescription":"Mailbox folder is not empty."}')" run 13.mailbox_folders_name_DELETE.sh Archive
expect "13: a folder that is not empty is exit 1 with the reason" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'because it is not empty. - Mailbox folder is not empty.')" "1:1"
USAGE_LABEL="no NAME" usage 13.mailbox_folders_name_DELETE.sh
USAGE_LABEL="an empty NAME" usage 13.mailbox_folders_name_DELETE.sh ""

echo "=== 14 search ==="
GET_BODY="$(body se '{"nRecords":1,"nDisplayRecords":1,"data":[{"id":"'${MID}'","folder":"Inbox","subject":"Hello"}]}')" run 14.mailbox_search_GET.sh Hello 5
expect "14: exit 0, the subject, the limit and offset 0" "${RC}:$(calls | grep -c "^GET ${BASE}/search?subject=Hello&limit=5&offset=0$")" "0:1"
has "14: it prints the hit" "  ${MID}  Inbox  Hello"
GET_BODY="${LIST}" run 14.mailbox_search_GET.sh
expect "14: with no subject the query is limit and offset only" "$(calls | grep -c "^GET ${BASE}/search?limit=10&offset=0$")" "1"
USAGE_LABEL="a LIMIT of 0" usage 14.mailbox_search_GET.sh x 0
USAGE_LABEL="three parameters" usage 14.mailbox_search_GET.sh a 1 c
refused 14.mailbox_search_GET.sh GET_STATUS

echo "=== 15 history ==="
GET_BODY="$(body hi '{"recipientsAccessHistory":[{"accessHistory":{"userName":"r","protocol":"http"}}]}')" run 15.mailbox_messageHistory_GET.sh "${MID}"
expect "15: exit 0, one GET of download and one of firstAccess" "${RC}:$(calls | grep -c "^GET ${BASE}/messageHistory/${MID}/download$"):$(calls | grep -c "^GET ${BASE}/messageHistory/${MID}/firstAccess$")" "0:1:1"
has "15: it counts the entries and prints them" "firstAccess: 1 entries"
has "15: ... as JSON" '"userName":"r"'
GET_BODY="$(body hi0 '{"recipientsDownloadHistory":[]}')" run 15.mailbox_messageHistory_GET.sh "${MID}"
has "15: nothing opened is 0 entries" "download: 0 entries"
USAGE_LABEL="no id" usage 15.mailbox_messageHistory_GET.sh
refused 15.mailbox_messageHistory_GET.sh GET_STATUS "${MID}"

echo "=== 16 attach ==="
printf 'attachment text\n' > "${WORK}/att.txt"
run 16.mailbox_attachments_POST.sh "${MID}" "${WORK}/att.txt"
expect "16: exit 0, one POST of the file as the field file" "${RC}:$(calls | grep -c "^POST ${BASE}/messages/${MID}/attachments$"):$(printf '%s\n' "${OUT}" | grep -c "^FORM: file=@${WORK}/att.txt")" "0:1:1"
has "16: it says so" "The file was attached (HTTP 200)."
POST_STATUS=422 POST_BODY="$(body e16 '{"error":"Failed to process item upload.","errorCode":"internalError"}')" run 16.mailbox_attachments_POST.sh "${MID}" "${WORK}/att.txt"
expect "16: the 422 the lab answers is exit 1 with its reason" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'Could not attach the file (HTTP 422): Failed to process item upload.')" "1:1"
USAGE_LABEL="a file that is not there" usage 16.mailbox_attachments_POST.sh "${MID}" "${WORK}/nothing.txt"
USAGE_LABEL="a folder as the file" usage 16.mailbox_attachments_POST.sh "${MID}" "${WORK}"
USAGE_LABEL="one parameter" usage 16.mailbox_attachments_POST.sh "${MID}"

echo "=== 17 the attachment ==="
rm -f "${WORK}/got.txt"
GET_BODY="${WORK}/att.txt" run 17.mailbox_attachments_GET.sh "${MID}" "${SID}" "my att.txt" "${WORK}/got.txt"
expect "17: exit 0, one GET of the attachment, the file name encoded" "${RC}:$(calls | grep -c "^GET ${BASE}/messages/${MID}/attachments/${SID}/my%20att.txt$")" "0:1"
expect "17: the file is saved, with the content" "$(cat "${WORK}/got.txt" 2>/dev/null)" "attachment text"
has "17: it says so" "Saved ${WORK}/got.txt (16 bytes)."
GET_BODY="${WORK}/att.txt" run 17.mailbox_attachments_GET.sh "${MID}" "${SID}" att.txt "${WORK}/got.txt"
expect "17: a file that exists is not overwritten: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
rm -f "${WORK}/got.txt"
GET_STATUS=500 GET_BODY="$(body e17 '{"error":"Error validating request"}')" run 17.mailbox_attachments_GET.sh "${MID}" "${SID}" att.txt "${WORK}/got.txt"
expect "17: a refusal is exit 1 and no file is left" "${RC}:$(test -e "${WORK}/got.txt" && echo file || echo none)" "1:none"
has "17: with the reason" "Could not download the attachment (HTTP 500): Error validating request"
USAGE_LABEL="a FILENAME with a slash" usage 17.mailbox_attachments_GET.sh "${MID}" "${SID}" "a/b"
USAGE_LABEL="two parameters" usage 17.mailbox_attachments_GET.sh "${MID}" "${SID}"

echo "=== no settings file ==="
rm "${TREE}/set_variables.local.sh"
for f in $(cd "${API14}/01.Mailbox" && ls [0-9][0-9].*.sh); do
    case "${f}" in
        03.*|04.*) params=(a) ;; 05.*) params=(a b) ;; 06.*|07.*|09.*|10.*|12.*|15.*) params=("${MID}") ;; 08.*) params=("${MID}" "${SID}") ;; 11.*) params=("${MID}" a) ;;
        13.*) params=(a) ;; 16.*) params=("${MID}" "${WORK}/att.txt") ;; 17.*) params=("${MID}" "${SID}" f "${WORK}/never.txt") ;; *) params=() ;;
    esac
    run "${f}" "${params[@]}"
    expect "${f}: no settings file is exit 1, nothing sent" "${RC}:$(ncalls)" "1:0"
done
has "(the last one) it says to copy the example file" "Copy set_variables.local.example.sh to set_variables.local.sh"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${TREE}/set_variables.local.sh"

echo "=== the folder and the README ==="
EXPECTED_N=17
expect "the folder holds ${EXPECTED_N} numbered examples" "$(cd "${API14}/01.Mailbox" && ls [0-9][0-9].*.sh | wc -l | tr -d ' ')" "${EXPECTED_N}"
for f in $(cd "${API14}/01.Mailbox" && ls [0-9][0-9].*.sh); do [ -x "${API14}/01.Mailbox/${f}" ] && pass "${f} is executable" || fail "${f} is not executable"; done
for f in 01 02 04 06 08 09 14 15 17; do grep -q "^# Risk: read" "${API14}/01.Mailbox/${f}."*.sh && pass "${f}: Risk read" || fail "${f}: Risk is not read"; done
for f in 03 05 07 10 11 12 13 16; do grep -q "^# Risk: write" "${API14}/01.Mailbox/${f}."*.sh && pass "${f}: Risk write" || fail "${f}: Risk is not write"; done
[ -f "${API14}/set_variables.local.example.sh" ] && pass "the example settings file is there" || fail "no set_variables.local.example.sh"
python3 - "${REPO}/EndUser/API 1.4/README.md" "${API14}/01.Mailbox" <<'PY' && pass "README: the sections, every example is named, and the claims it makes" || fail "README: see above"
import os, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
folder = sys.argv[2]
for heading in ("## What 1.4 has and 2.0 has not", "## The mailbox examples", "## What the mailbox did on the lab", "## In 2.0 under another name", "## Not covered"):
    assert heading in text, heading
for f in sorted(os.listdir(folder)):
    if re.match(r"\d\d\..*\.sh$", f):
        assert f in text and f[:-3] in text, "README does not name " + f
for needle in ("Draft was not saved", "limit", "offset", "EXISTING_ACCOUNT", "Message security level may not be empty", "recipient may not be empty", "Can not get package item input stream",
               "survives the account", "404", "isRead", "Permission denied", "Not implemented", "passwordPolicy", "addressBook", "Basic authentication", "ST_ENDUSER_LOCAL_VARIABLES"):
    assert needle.lower() in text.lower(), needle
PY

echo
if [ "${FAILED}" -eq 0 ]; then echo "test_bash_enduser_api14: PASS"; else echo "test_bash_enduser_api14: FAIL"; fi
exit "${FAILED}"
