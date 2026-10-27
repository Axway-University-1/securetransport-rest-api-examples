#!/usr/bin/env python3
"""Features/Guidance/moving-files-end-user-api.md: the sections are there, the facts tried on the lab are written in it, and the code in it runs
(the checksum line gives the base64 of the binary MD5, the chunk loop sends the pieces in order with the right Content-Range, the curl examples go to the right paths)."""
import base64
import hashlib
import json
import os
import re
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
import guide_checks as g  # noqa: E402

failed = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else "  (%s)" % (detail,)))
    if not ok:
        failed.append(label)


text = g.read("moving-files-end-user-api.md")
heads = re.findall(r"^## (.+)$", text, re.M)
for h in ("Before you start", "Upload with a multipart form", "Check the file: the checksum", "Text and binary", "Upload in chunks",
          "Upload to a file operation with a form", "Download, rename and delete", "When an upload answers 500", "Share a folder", "Checklist"):
    check("section: %s" % h, h in heads, heads)
check("the facts tried on the lab are in it: replace on 201, a folder in the name, wrong MD5 500 with the file stored, out of order 500, rename 403, delete 403",
      all(t in text for t in ("answers 201 again, and the file is **replaced**", "stores the file in the home folder as `nested.txt`", "the answer was 500, and the file **was stored**",
                              "answers **403**, not 404", "(directory is not empty)", "A chunk out of order")))
check("ASCII removes the CR: the two byte strings are in the table", "`61 0d 0a 62 0d 0a`" in text and "`61 0a 62 0a`" in text)
check("share rights 1, 3 and 7 are in the table with what each can do", all(t in text for t in ("| 1 | read.", "| 3 | read and upload", "| 7 | read, upload and delete")))
check("the checksum is said to be base64 of the binary value, and an operation's status is said not to be the file's",
      "base64 of the binary value" in text and "The status is the status of the operation, not of the file" in text)
check("the shipped examples are named and exist", all((g.ROOT / p).exists() for p in ("EndUser/API 2.0/bash/02.Files", "EndUser/API 2.0/bash/04.FileOperations",
      "EndUser/UseCases/03-files-and-folders", "EndUser/UseCases/04-larger-files", "EndUser/UseCases/06-sharing-a-folder")))

blocks = g.blocks(text)
# the MD5 line gives what the header wants: base64 of the binary md5, not hex
md5_block = next(code for lang, code in blocks if lang == "bash" and code.startswith("MD5="))
d = tempfile.mkdtemp(prefix="guide_files_")
data = b"hello world\n"
Path(d, "report.txt").write_bytes(data)
import subprocess
r = subprocess.run(["bash", "-c", "cd %s && %s\nprintf %%s \"$MD5\"" % (d, md5_block)], capture_output=True, text=True)
check("the MD5 line gives the base64 of the binary MD5", r.stdout == base64.b64encode(hashlib.md5(data).digest()).decode(), r.stdout)

# the upload with the header: the header is sent
md5_up = next(c for c in g.curl_examples(text) if "Content-MD5" in c)
r = g.run_curl(md5_up, env={"MD5": "abc=="})
check("the upload with the checksum sends Content-MD5 to /files/docs", "HEADER: Content-MD5: abc==" in r.stderr and "/files/docs" in r.stderr and "METHOD: POST" in r.stderr, r.stderr[-300:])
mode = next(c for c in g.curl_examples(text) if "transferMode=ASCII" in c)
r = g.run_curl(mode)
check("the text upload asks for transferMode=ASCII", "transferMode=ASCII" in r.stderr, r.stderr[-300:])
rename = next(c for c in g.curl_examples(text) if "/newFilePath" in c)
r = g.run_curl(rename)
payload = json.loads(base64.b64decode(re.search(r"PAYLOAD_B64: (\S+)", r.stderr).group(1)))
check("the rename is a PATCH that adds /newFilePath", "METHOD: PATCH" in r.stderr and payload == [{"op": "add", "path": "/newFilePath", "value": "/docs/renamed.txt"}], r.stderr[-300:])
share = next(c for c in g.curl_examples(text) if "sharedDirectoryProperties" in c)
r = g.run_curl(share)
payload = json.loads(base64.b64decode(re.search(r"PAYLOAD_B64: (\S+)", r.stderr).group(1)))
check("the share adds /sharedDirectoryProperties with the rights and the collaborator", payload[0]["path"] == "/sharedDirectoryProperties"
      and payload[0]["value"]["shareRights"] == 1 and payload[0]["value"]["collaborators"] == ["other.user@example.com"], payload)

# the chunk loop: a file of 2,500,000 bytes goes up in three pieces, in order, with the right Content-Range
loop = next(code for lang, code in blocks if lang == "bash" and code.startswith("# Upload big.bin in pieces"))
Path(d, "post.json").write_text('{"id": "op1", "status": "IN_PROGRESS"}')
code = "cd %s && head -c 2500000 /dev/zero > big.bin\n%s" % (d, loop)
r = g.run_curl(code, env={"STUB_CURL_POST_BODY": str(Path(d, "post.json")), "ST_ENDUSER_PORT": "8443"})
ranges = re.findall(r"HEADER: Content-Range: (bytes \S+)", r.stderr)
check("the chunk loop sends three pieces, in order, with the right Content-Range",
      ranges == ["bytes 0-999999/2500000", "bytes 1000000-1999999/2500000", "bytes 2000000-2499999/2500000"], (ranges, r.stderr[-300:]))
check("the operation is made first (POST /fileOperations with an Upload body) and the pieces go to its id",
      re.findall(r"^METHOD: (\w+)", r.stderr, re.M) == ["POST", "PUT", "PUT", "PUT"] and r.stderr.count("/fileOperations/op1") == 3, r.stderr[-400:])
print("test_guidance_moving_files_end_user_api: " + ("FAIL" if failed else "PASS"))
sys.exit(1 if failed else 0)
