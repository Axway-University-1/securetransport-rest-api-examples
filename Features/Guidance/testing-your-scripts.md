# Testing your own scripts against the SecureTransport REST API

**For:** engineers and support staff who write scripts or programs that call the REST API. They want to know that the scripts work before they run them against a server that people use.
**Checked on:** SecureTransport 5.5-20260924 (for the facts about the lab). The method itself does not depend on a release. The tools named here are in this repository
(`tests/offline/lib/stub_curl`, `tools/mutation_probe.py`, `tools/script_coverage.py`, `tools/measure_coverage.py`) and you can copy them.

## Summary

A script that calls an API fails in two ways. It sends the wrong call, or it reads the answer wrongly. You can find the first kind with no server. Put a stand-in
for `curl` in front of the script and look at what it would send. You find the second kind with a lab server. This guide shows both, a small test you can run now, and a way to
check that your tests would notice a broken script.

- [Two places to test](#two-places-to-test)
- [A lab that is not production](#a-lab-that-is-not-production)
- [A test with no server: a stand-in for curl](#a-test-with-no-server-a-stand-in-for-curl)
- [What a test should check](#what-a-test-should-check)
- [Would your test notice a broken script?](#would-your-test-notice-a-broken-script)
- [Counting what is covered](#counting-what-is-covered)
- [Test the days that go wrong](#test-the-days-that-go-wrong)
- [Checklist](#checklist)

## Two places to test

| Where | What it finds | What it cannot find |
| ----- | ------------- | ------------------- |
| **No server** (a stand-in for `curl`) | The wrong method, path, header or body. The wrong exit code. A message that is missing. | What the server really answers. |
| **A lab server** | The real answers: the status codes, the shape of the body, the timing. | It is slow, and it can leave objects behind. |

Do both. The offline test is fast and you can run it on every change. The lab test confirms the assumptions that the offline test is built on. When the lab shows that an answer
is not what you assumed, change the offline test to match. Then the next change is checked against what the server really does.

## A lab that is not production

Use a server that nobody depends on. A test that writes can leave a changed setting, a locked account or a stopped service behind.

- **Throwaway names.** Give everything the test makes a prefix, for example `ZZTEST_`, and a random tail: `ZZTEST_files_k3x9`. Never use a name a person uses.
- **Read, change, look, put back, compare.** Before a test changes something that already exists, read it and keep a copy. Change it. Read it again and check that it changed. Put it
  back, read it again, and compare with the copy. A test that does not compare has not proved that it left the server as it was.
- **Remove what you made, even when the test fails.** Make the clean-up run in a `finally` or a `trap`.
- **Do not run what changes the whole server for good.** Do not test maintenance mode, the keystore password or the database connection on a server you want to keep.
- **Keep the server and the credentials out of the repository.** Read them from a file that git ignores.
- **Look for leftovers after a run.** List the objects that carry your prefix. This repository's online checks end with "nothing is left behind".

## A test with no server: a stand-in for curl

`curl` is found by name. If a file named `curl` comes first on `PATH`, your script runs that one. A stand-in that sends nothing and prints what it was asked to do lets a test read the call.

Here is a small one. It prints the method, the URL, each header and the body to the error output. It **refuses a call with no `Referer` header**: the API asks for one on every call (see
[Authentication and sessions](authentication-and-sessions.md)). The stand-in of this repository (`tests/offline/lib/stub_curl`) also refuses a JSON body sent with no `Content-Type` header. It answers with the status in `STUB_STATUS` (201 by default):

```bash
#!/bin/bash
# stubs/curl: a stand-in for curl. It sends nothing. Put its folder first on PATH.
method=GET; url=""; referer=0; write=""; payload=""
while [ $# -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    -H) echo "HEADER: $2" >&2; case "$2" in Referer:*|referer:*) referer=1 ;; esac; shift 2 ;;
    -d) payload="$2"; shift 2 ;;
    -w) write="$2"; shift 2 ;;
    https://*|http://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
[ "${referer}" = 1 ] || { echo "STUB_ERROR: no Referer header on ${url}" >&2; exit 22; }
echo "METHOD: ${method}" >&2
echo "URL: ${url}" >&2
[ -n "${payload}" ] && echo "PAYLOAD: ${payload}" >&2
[ -n "${write}" ] && printf '%s' "${write//%\{http_code\}/${STUB_STATUS:-201}}"
exit 0
```

The stand-in of this repository, `tests/offline/lib/stub_curl`, does the same and more. It echoes the body as base64, because a body can have quotes and new lines. It serves a file as the
answer to a `GET`. It answers different statuses to different methods, and it can follow a list of answers one by one.

### A script to test

A small script. It makes a folder in the home folder of an end user and checks the answer:

```bash
#!/bin/bash
# create_folder.sh NAME: makes the folder NAME in the home folder of the end user
NAME="$1"
[ -n "${NAME}" ] || { echo "Usage: ./create_folder.sh NAME"; exit 2; }
CODE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_ENDUSER_PORT}/api/v2.0/files/${NAME}" \
  -H "Content-Type: application/json" -H "Referer: x" -d '{"isDirectory": true}' -o /dev/null -w '%{http_code}')
[ "${CODE}" = "201" ] || { echo "The server answered ${CODE}."; exit 1; }
echo "Created ${NAME}."
```

### Its test

Put the three files in one folder: `create_folder.sh`, `test_create_folder.sh` and `stubs/curl` (make them executable). The test runs the script with the stand-in first on `PATH`
and reads what it printed:

```bash
#!/bin/bash
# test_create_folder.sh: run it with ./test_create_folder.sh
cd "$(dirname "$0")" || exit 1
export PATH="${PWD}/stubs:${PATH}" ST_USER=u ST_PASSWORD=p ST_SERVER=st.example.com ST_ENDUSER_PORT=8443
FAILED=0
expect() { if [ "$2" = "$3" ]; then echo "  PASS  $1"; else echo "  FAIL  $1 (expected '$3', got '$2')"; FAILED=1; fi; }

OUT=$(./create_folder.sh reports 2>&1); RC=$?
expect "a 201 is exit 0" "${RC}" "0"
expect "the method is POST" "$(echo "${OUT}" | sed -n 's/^METHOD: //p')" "POST"
expect "the path is the folder in /files" "$(echo "${OUT}" | sed -n 's/^URL: //p')" "https://st.example.com:8443/api/v2.0/files/reports"
expect "the body says that it is a folder" "$(echo "${OUT}" | sed -n 's/^PAYLOAD: //p')" '{"isDirectory": true}'
expect "the Referer header is sent" "$(echo "${OUT}" | grep -c '^HEADER: Referer: ')" "1"

OUT=$(STUB_STATUS=409 ./create_folder.sh reports 2>&1); RC=$?
expect "a 409 is exit 1" "${RC}" "1"
expect "and the message says the status" "$(echo "${OUT}" | grep -c 'The server answered 409')" "1"

OUT=$(./create_folder.sh 2>&1); RC=$?
expect "no name is exit 2, and nothing is sent" "${RC}:$(echo "${OUT}" | grep -c '^METHOD:')" "2:0"
exit ${FAILED}
```

It prints one `PASS` or `FAIL` line for each check, and ends with exit 0 when all pass. It was run as shown, and all eight checks pass.

## What a test should check

For each script, check what a person looking at the call would check:

| Check | Why |
| ----- | --- |
| The **method** | `PUT` and `PATCH` do different things to an object. |
| The **path**, with the names in it | A wrong word in the path is a different resource. The stand-in answers any URL, so only a test notices. |
| The **body**, field by field | A field with another name, or a missing one, is accepted by some resources and ignored by others. |
| The **headers**: `Referer`, the content type, the credential | The server may refuse a call without them, and a lab may not. |
| The **exit code** for each answer the script knows: success, refused, not found, no answer | A script that exits 0 after a refusal tells the next script that all is well. |
| The **message** a person reads | A message that says what was wrong and what to do is part of the script. |
| What is **not** sent | A script given a bad parameter must stop before it calls the server. Check that no call was made. |

Do not check only the exit code. The test above checks eight things. A test that checked only the first would pass for a script that sends the wrong method.

## Would your test notice a broken script?

A test that passes does not tell you that it would fail. The way to find out is **mutation testing**: break the script on purpose, in one small way, run the test, and see whether it fails. If the test
still passes, it would not have noticed that bug.

Try it by hand on the script above. Make a copy, change one thing, and run the test on the copy. Here are six changes. They were tried against the test above and against a weak test
that only checks that the exit code is 0 for a 201:

| Change | The test above | A test that only checks the exit code |
| ------ | -------------- | ------------------------------------- |
| `-X POST` becomes `-X PUT` | fails (the method) | passes |
| The `Referer` header is removed | fails (the stand-in refuses the call, and the script exits 1) | fails |
| `files/` becomes `file/` in the path | fails (the path) | passes |
| `"201"` becomes `"299"` | fails (a 201 is not exit 0) | fails |
| `exit 1` after the refusal becomes `exit 0` | fails (a 409 is exit 1) | passes |
| `exit 2` in the usage check becomes `exit 0` | fails (no name is exit 2) | passes |

The weak test misses four of the six. All six were tried.

**This repository has a tool that does it for you:** `tools/mutation_probe.py SCRIPT`. It works in a scratch copy of the repository, so your files are not touched. It makes the changes below, one at
a time, and runs the checks that name the script, and the house rules check of the repository. It lists the **survivors**, the changes that no check noticed:

| Change | What it does |
| ------ | ------------ |
| method | Swaps the HTTP method of a call (`POST` becomes `PUT`, `DELETE` becomes `GET`). |
| exit | Makes a refusal that stops the script not stop it (`exit 1`, `exit 2` and `return 1` become `exit 0` or `return 0`). |
| status | Changes the status code the script waits for (200, 201 and 204 become 299). |
| header | Drops a `Content-Type` or `Referer` header. |
| url | Adds a wrong letter to a path segment of the URL. |
| key | Sends a name in the body under another name. |
| compare | Turns a comparison round (`-eq` and `-ne`, `-gt` and `-le`, `-lt` and `-ge`). |
| output | Removes a line that the script prints. Reported apart: a test may rightly not read every line. |

Some survivors are not a gap. A change that nobody could see (two headers swapped) is an "equivalent" change. Read each survivor and decide. When the survivor is a real gap, write the test
that fails on the mutant, and then see it pass on the real script. Copy the tool, and change its list of tests to find the tests of your own scripts.

## Counting what is covered

Two more tools of this repository, if you have many scripts:

- **`tools/script_coverage.py`** runs your tests with a tracer. It lists the scripts that **no test ran**, and the scripts that ran but **never made a call** (a test tried only
  their usage message). The tracer is two small hooks. For bash, it is a trap that writes the name of each script that starts (the trap is read from the variable `BASH_ENV`). For python, it is a
  `sitecustomize` that writes the name of the script when the interpreter ends. A copy of the `curl` stand-in that writes the script that called it tells the second list.
- **`tools/measure_coverage.py`** puts the numbers on one screen. It counts the operations of the API reference that your scripts call, and the scripts that the tests run. It also counts how many of those make a call, and how many
  of the mutations your tests catch. It adds the date of each measure and the change since the last report.

A script that no test runs has no protection. A script that the tests run but never call has only half. A script whose test would pass after a mutation has less than it seems.

## Test the days that go wrong

Some bugs wait for a date. A script that works out a day as 86,400 seconds is right on most days of the year. Test it with a time zone whose clocks changed yesterday, as shown in
[Time formats in the SecureTransport REST API, and daylight saving time](time-formats.md#how-to-test-your-script-without-waiting-for-the-date). The same idea fits other conditions
that a normal run does not meet. Examples are a full disk, a very long name, a name with a space or a quote, and an empty answer.

## Checklist

- [ ] The tests run with no server, and they are fast enough to run on every change.
- [ ] A test checks the method, the path, the body, the headers, the exit code and the message.
- [ ] A bad parameter is tested for "nothing was sent".
- [ ] The lab test uses a prefix, restores what it changed, compares with the copy, and cleans up even when it fails.
- [ ] You have broken the script on purpose and seen the test fail, at least for the method, the path and the exit codes.
- [ ] A script no test runs is on a list, with a reason.
- [ ] The tests include the days that go wrong.
