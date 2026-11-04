#!/usr/bin/env python3
"""
READ ONLY. Runs the two Admin API 1.4 path examples (Admin/API 1.4/bash/01.Validation) for real, and checks what the README of
that folder says about them, through the scripts' own output.

validPath: an absolute path is valid whether or not it exists (a path with a space too), a path with `..` is refused with
"relative path sequence", a relative one with "not absolute", a system folder with "unsafe paths list" (the default list of the
server); an empty path never reaches the server (exit 2). path: asking exist and isDirectory of /tmp gives true for both, of a
path that is not there gives false, a chosen question gives only its own field, and a path that is a file is not a directory.

Both calls change nothing on the server. It does not run on the bundled mock, which serves the 2.0 API only.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
c = st_client.Checker("Admin API 1.4 path validation, run for real")
TREE = runner.path("Admin", "API 1.4", "bash")
FOLDER = os.path.join(TREE, "01.Validation")

admin = harness.connect(config, c, mock="the bundled mock serves only the API 2.0; run this against a real server to exercise API 1.4")

try:
    with runner.real_credentials(TREE, config):
        valid = os.path.join(FOLDER, "01.validation_validPath_POST.sh")
        r = runner.run(valid, ["/tmp"])
        c.check("validPath /tmp: exit 0 and says it is a valid path", r.returncode == 0 and "/tmp is a valid path (HTTP 200)." in r.stdout, (r.returncode, r.stdout[-300:]))
        r = runner.run(valid, ["/no/such/example_dir"])
        c.check("validPath of a path that does not exist is valid too (the call checks the form of the path)", r.returncode == 0 and "is a valid path" in r.stdout, (r.returncode, r.stdout[-300:]))
        r = runner.run(valid, ["/tmp/example dir"])
        c.check("validPath of a path with a space is valid: it goes as one field", r.returncode == 0 and "is a valid path" in r.stdout, (r.returncode, r.stdout[-300:]))
        r = runner.run(valid, ["relative/dir"])
        c.check("validPath of a relative path: exit 1, 'Folder name is not absolute'", r.returncode == 1 and "HTTP 403" in r.stdout and "Folder name is not absolute" in r.stdout, (r.returncode, r.stdout[-300:]))
        r = runner.run(valid, ["/tmp/../etc"])
        c.check("validPath of a path with ..: exit 1, 'relative path sequence'", r.returncode == 1 and "relative path sequence" in r.stdout, (r.returncode, r.stdout[-300:]))
        r = runner.run(valid, ["/etc"])
        c.check("validPath of /etc: exit 1, 'unsafe paths list'", r.returncode == 1 and "Path cannot be in the unsafe paths list." in r.stdout, (r.returncode, r.stdout[-300:]))
        r = runner.run(valid, [])
        c.check("validPath with no path: exit 2 and the usage, nothing sent", r.returncode == 2 and "Usage: ./01.validation_validPath_POST.sh PATH" in r.stdout, (r.returncode, r.stdout[-200:]))

        path_op = os.path.join(FOLDER, "02.validation_path_POST.sh")
        r = runner.run(path_op, ["/tmp", "exist,isDirectory"])
        c.check("path /tmp exist,isDirectory: both true, and no isFile in the answer", r.returncode == 0 and "  isExist: true" in r.stdout and "  isDirectory: true" in r.stdout and "isFile" not in r.stdout, (r.returncode, r.stdout[-300:]))
        r = runner.run(path_op, ["/no/such/example_dir", "exist,isDirectory"])
        c.check("path of a path that is not there: isExist false, isDirectory false", r.returncode == 0 and "  isExist: false" in r.stdout and "  isDirectory: false" in r.stdout, (r.returncode, r.stdout[-300:]))
        r = runner.run(path_op, ["/tmp", "isFile"])
        c.check("path /tmp isFile: false (a folder is not a file)", r.returncode == 0 and "  isFile: false" in r.stdout, (r.returncode, r.stdout[-300:]))
        r = runner.run(path_op, ["/tmp", "validate"])
        c.check("path /tmp validate: isValid true, and nothing else is asked", r.returncode == 0 and "  isValid: true" in r.stdout and "isExist" not in r.stdout and "isDirectory" not in r.stdout, (r.returncode, r.stdout[-300:]))
        r = runner.run(path_op, ["/tmp", "bogus"])
        c.check("path with a question that does not exist: exit 2", r.returncode == 2 and "ASK has 'bogus'" in r.stdout, (r.returncode, r.stdout[-200:]))
finally:
    admin.logout()

sys.exit(c.done())
