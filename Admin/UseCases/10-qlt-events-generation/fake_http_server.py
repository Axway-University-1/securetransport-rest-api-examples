#!/usr/bin/env python3
# ==============================================================================
# Script Name: fake_http_server.py
# Author: Plamen Milenkov
# Created: 2026-11-10
# Location: Sofia
# ==============================================================================
# Description:
# A fake HTTP server for the use case 10-qlt-events-generation. It stands in for the two servers SecureTransport talks to in the use case: the "another server" a Generic HTTP site pushes
# a file to, and Fusion. It accepts what SecureTransport sends, answers what SecureTransport accepts, and writes one line of JSON for each request to a log file, so that the use case
# can show what the server sent.
#
#   PUT or POST /upload   the file of a Generic HTTP site (a multipart form, the file in a part): answered 200 {"status": "received"}
#   POST /fusion          the request of a Send To Fusion step (a multipart form: metadata.json and the file): answered 200 with the file part as the body, which is what the integration
#                         expects when its Data Expected is PAYLOAD (the file Fusion sends back)
#   anything else         404 {"status": "not found"}
#
# Usage:
# python3 fake_http_server.py PORT LOG_FILE
#
#   PORT      the port to listen on, on every address of the machine
#   LOG_FILE  the file the requests are appended to, one JSON object a line: t (HH:MM:SS), method, path, bytes, contentType, file (the file name of the part that is not metadata.json), answer
#
# Risk: none
#
# Notes:
# - Only the Python 3 standard library. It keeps nothing: the files it is sent are dropped.
# - 04.fakeServer_start.sh starts it in the background and 99.cleanup_DELETE.sh stops it (by its process id, after checking the command).
# - Confirmed directly (SecureTransport 5.5-20261029): a Generic HTTP site sends the file with PUT to its upload path as multipart/form-data (the part is named `filename`), and a Send To
#   Fusion step with Data Sent ALL posts a multipart form with the part metadata.json (the attributes of the transfer, the same ones an event carries) and the file. The plain HTTP site type
#   expects more of a server (it logs in, asks with HEAD for the folder and the file) and is not what this server answers.
# ==============================================================================
import http.server
import json
import re
import sys
import time

if len(sys.argv) != 3 or not sys.argv[1].isdigit():
    print("Usage: fake_http_server.py PORT LOG_FILE")
    sys.exit(2)
PORT = int(sys.argv[1])
LOG_FILE = sys.argv[2]


def parts_of(content_type, body):
    """The parts of a multipart body: [(headers, content)]. Empty when it is not multipart."""
    found = re.search(r"boundary=([^;]+)", content_type or "")
    if not found:
        return []
    out = []
    for part in body.split(("--" + found.group(1).strip('"')).encode()):
        head, separator, content = part.partition(b"\r\n\r\n")
        if not separator or not content.strip(b"\r\n-"):
            continue
        out.append((head.decode("utf-8", "replace"), content.rsplit(b"\r\n", 1)[0] if content.endswith(b"\r\n") else content))
    return out


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def read_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            return self.rfile.read(length)
        if (self.headers.get("Transfer-Encoding") or "").lower() == "chunked":
            data = b""
            while True:
                size = int(self.rfile.readline().strip() or b"0", 16)
                if size == 0:
                    self.rfile.readline()
                    return data
                data += self.rfile.read(size)
                self.rfile.readline()
        return b""

    def handle_any(self):
        body = self.read_body()
        path = self.path.split("?")[0]
        status, answer, content_type, shown = 404, b'{"status": "not found"}', "application/json", None
        parts = parts_of(self.headers.get("Content-Type"), body)
        for head, content in parts:
            name = re.search(r'filename="([^"]*)"', head)
            if name and "metadata.json" not in head:
                shown = name.group(1)
        if self.command in ("PUT", "POST") and path == "/upload":
            status, answer = 200, b'{"status": "received"}'
        elif self.command == "POST" and path == "/fusion":
            for head, content in parts:
                if "metadata.json" not in head:
                    status, answer, content_type = 200, content, "application/octet-stream"
                    break
        with open(LOG_FILE, "a", encoding="utf-8") as log:
            log.write(json.dumps({"t": time.strftime("%H:%M:%S"), "method": self.command, "path": path, "bytes": len(body), "contentType": self.headers.get("Content-Type") or "",
                                  "file": shown, "answer": status}) + "\n")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(answer)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(answer)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = handle_any

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
