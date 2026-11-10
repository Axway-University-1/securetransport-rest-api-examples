#!/usr/bin/env python3
"""
Check Admin/UseCases/10-qlt-events-generation/fake_http_server.py: the fake server of the use case. It is started on the loopback address and sent what SecureTransport sends it: a PUT of a
file as a multipart form to /upload (also in chunks, as the Generic HTTP site sends it), a POST to /fusion with metadata.json and the file (the answer is the file), and requests it does not answer.
Every request must be one line of JSON in the log, and nothing it is sent is kept.

Runs offline: only the loopback address. Exit code 0 means clean.
"""
import http.client
import json
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SERVER = os.path.join(REPO, "Admin", "UseCases", "10-qlt-events-generation", "fake_http_server.py")
failed = 0


def check(label, ok, got=None):
    global failed
    print(("  PASS  " if ok else "  FAIL  ") + label + ("" if ok or got is None else "  got: %r" % (got,)))
    failed += 0 if ok else 1


def multipart(parts):
    boundary = "----test-boundary-42"
    body = b""
    for name, filename, content_type, content in parts:
        body += ("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n" % (boundary, name, filename, content_type)).encode() + content + b"\r\n"
    return "multipart/form-data; boundary=" + boundary, body + ("--%s--\r\n" % boundary).encode()


def free_port():
    import socket
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


work = tempfile.mkdtemp(prefix="fake_server_", dir=os.environ.get("ST_TEST_OUTPUT") or None)
log = os.path.join(work, "requests.log")
port = free_port()
process = subprocess.Popen([sys.executable, SERVER, str(port), log], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    connection = None
    for _ in range(50):
        try:
            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            connection.request("GET", "/")
            connection.getresponse().read()
            break
        except OSError:
            time.sleep(0.1)
    check("the server answers on the port it was given", connection is not None)

    def request(method, path, body=None, headers=None, chunked=False):
        c = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        c.request(method, path, body=body, headers=headers or {}, encode_chunked=chunked)
        r = c.getresponse()
        return r.status, r.read(), r.getheader("Content-Type")

    content_type, body = multipart([("filename", "report_1.txt", "application/octet-stream", b"hello file\n")])
    status, answer, _ = request("PUT", "/upload", body, {"Content-Type": content_type})
    check("PUT /upload: 200 and says it received the file", status == 200 and json.loads(answer) == {"status": "received"}, (status, answer))
    status, answer, _ = request("POST", "/upload", body, {"Content-Type": content_type})
    check("POST /upload is taken too: 200", status == 200, status)
    status, answer, _ = request("PUT", "/upload", iter([body[:40], body[40:]]), {"Content-Type": content_type, "Transfer-Encoding": "chunked"}, chunked=True)
    check("PUT /upload in chunks (as the Generic HTTP site sends it): 200", status == 200, (status, answer))

    content_type, body = multipart([("metadata.json", "metadata.json", "application/json", b'{"STATE":"RECEIVED"}'), ("file", "fusion_1.txt", "application/octet-stream", b"the payload\n")])
    status, answer, kind = request("POST", "/fusion", body, {"Content-Type": content_type})
    check("POST /fusion: 200, and the answer is the file part, not the metadata", status == 200 and answer == b"the payload\n" and kind == "application/octet-stream", (status, answer, kind))
    content_type, body = multipart([("metadata.json", "metadata.json", "application/json", b"{}")])
    status, answer, _ = request("POST", "/fusion", body, {"Content-Type": content_type})
    check("POST /fusion with no file part: 404, there is nothing to send back", status == 404, status)
    status, _, _ = request("GET", "/upload")
    check("GET /upload: 404 (only PUT and POST take a file)", status == 404, status)
    status, _, _ = request("HEAD", "/anything")
    check("HEAD of a path it does not know: 404, with no body", status == 404, status)
    status, answer, _ = request("DELETE", "/upload")
    check("DELETE: 404 and the status in JSON", status == 404 and json.loads(answer)["status"] == "not found", (status, answer))

    lines = [json.loads(line) for line in open(log, encoding="utf-8").read().splitlines()]
    check("every request is one line of JSON in the log: the root, three uploads, two fusion calls and three more", len(lines) == 9, len(lines))
    uploads = [line for line in lines if line["path"] == "/upload" and line["method"] in ("PUT", "POST")]
    check("the log says method, path, bytes, the file name of the part and the answer", [(u["method"], u["file"], u["answer"]) for u in uploads] == [("PUT", "report_1.txt", 200), ("POST", "report_1.txt", 200), ("PUT", "report_1.txt", 200)]
          and all(u["bytes"] > 0 and u["t"].count(":") == 2 for u in uploads), uploads)
    fusion = [line for line in lines if line["path"] == "/fusion"]
    check("a fusion call is logged with the file name of the part that is not metadata.json", [f["file"] for f in fusion] == ["fusion_1.txt", None] and [f["answer"] for f in fusion] == [200, 404], fusion)
    check("nothing it is sent is kept: only the log is in the folder", sorted(os.listdir(work)) == ["requests.log"], os.listdir(work))
finally:
    process.terminate()
    process.wait(timeout=10)

check("the server stops when it is told to", process.returncode is not None)
bad = subprocess.run([sys.executable, SERVER], capture_output=True, text=True)
check("without its parameters it says the usage and exits 2", bad.returncode == 2 and "Usage: fake_http_server.py PORT LOG_FILE" in bad.stdout, (bad.returncode, bad.stdout))
bad = subprocess.run([sys.executable, SERVER, "port", log], capture_output=True, text=True)
check("a port that is not a number is exit 2", bad.returncode == 2, bad.returncode)

print()
print("test_qlt_fake_server: %s" % ("PASS" if not failed else "FAIL"))
sys.exit(1 if failed else 0)
