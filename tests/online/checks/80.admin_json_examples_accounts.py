#!/usr/bin/env python3
"""
WRITES TO THE SERVER (the accounts example_user, example_service and example_template, which it removes). Replays the Postman collection of
Admin/API 2.0/json for real, request by request, the way newman does, and checks what its README says.

Every request of the collection answers the status its test names, 25 of them in a row (the errors answered on purpose, 409, 400 and 404, among them),
and the three accounts are gone at the end. Read through the API and not through the collection: the PUT made the uid 1111 on the user and on
the service account, the patches left the notes and took the contact out again, the policy is back to default. And the README's warning: the Swagger body
pasted with its placeholder password is accepted (201).

Needs --write and st_allow_writes="yes". It does not run on the bundled mock.
"""
import base64
import json
import os
import re
import ssl
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "replay the accounts collection of Admin/API 2.0/json")

c = st_client.Checker("Admin/API 2.0/json: the accounts collection, replayed for real")
JSON = runner.path("Admin", "API 2.0", "json")
NAMES = ("example_user", "example_service", "example_template")
PASSWORD = "Ex1!" + os.urandom(6).hex()

admin = harness.connect(config, c, mock="the bundled mock does not model the address book of an account, which this check reads back; run it against a real server")
try:
    classes = admin.results("userClasses", {"fields": "className,userType,order"})
    template_class = sorted((k for k in classes if k.get("userType") != "real"), key=lambda k: k.get("order", 0))[0]["className"]
    environment = {"server": config["st_server"], "port": config["st_port"], "user": config["st_user"], "password": config["st_password"],
                   "accountPassword": PASSWORD, "templateClass": template_class}
    for name in NAMES:
        admin.delete("accounts/" + name)

    unverified = ssl.create_default_context()
    unverified.check_hostname = False
    unverified.verify_mode = ssl.CERT_NONE

    def send(method, url, headers, body, user=None, password=None):
        request = urllib.request.Request(url, data=body.encode("utf-8") if body else None, method=method)
        request.add_header("Authorization", "Basic " + base64.b64encode(("%s:%s" % (user, password)).encode()).decode())
        for key, value in headers.items():
            request.add_header(key, value)
        try:
            with urllib.request.urlopen(request, context=unverified, timeout=60) as answer:
                return answer.status, answer.headers
        except urllib.error.HTTPError as error:
            return error.code, error.headers

    def fill(text):
        return re.sub(r"\{\{([A-Za-z0-9_]+)\}\}", lambda m: environment[m.group(1)], text)

    collection = json.load(open(os.path.join(JSON, "postman", "ST-Admin-API-2.0.postman_collection.json"), encoding="utf-8"))
    auth = {e["key"]: fill(e["value"]) for e in collection["auth"]["basic"]}
    items = [i for topic in collection["item"] for i in topic["item"]]
    c.check("the collection has the 25 requests of the accounts", len(items) == 25, len(items))

    wrong = []
    for item in items:
        request = item["request"]
        url = fill(request["url"]["raw"])
        for variable in request["url"].get("variable", []):
            url = url.replace(":" + variable["key"], variable["value"])
        expected = int(re.search(r"have\.status\((\d+)\)", "".join(item["event"][0]["script"]["exec"])).group(1))
        status, headers = send(request["method"], url, {h["key"]: h["value"] for h in request["header"]},
                               fill(request["body"]["raw"]) if "body" in request else None, auth["username"], auth["password"])
        if status != expected:
            wrong.append((item["name"], status, expected))
        if request["method"] == "POST" and expected == 201:
            c.check("%s: the address of the new account is in Location" % item["name"],
                    "/api/v2.0/accounts/" in (headers.get("Location") or ""), headers.get("Location"))
        if item["name"].startswith("06.accounts_name_PATCH_6"):
            read = admin.get("accounts/example_user", {"type": "user", "fields": "notes,uid,addressBookSettings"}).json() or {}
            c.check("after the patches: the notes are set, the uid is the PUT's, the policy is default, no contact is left",
                    read.get("notes") == "Created by the JSON examples" and read.get("uid") == "1111"
                    and read["addressBookSettings"]["policy"] == "default" and not read["addressBookSettings"].get("contacts"), read)
            service = admin.get("accounts/example_service", {"fields": "uid"}).json() or {}
            c.check("the PUT of the service account made its uid 1111", service.get("uid") == "1111", service)
    c.check("every request answered the status its test names", not wrong, wrong)
    c.check("the three accounts are gone", not any(admin.exists("accounts/" + n) for n in NAMES))

    pasted = open(os.path.join(JSON, "swagger", "05.Accounts", "02.accounts_POST_user.body.json"), encoding="utf-8").read()
    status, _ = send("POST", "https://%s:%s/api/v2.0/accounts" % (config["st_server"], config["st_port"]),
                     {"Referer": "THIS_IS_A_RANDOM_TEXT", "Content-Type": "application/json"}, pasted, config["st_user"], config["st_password"])
    c.check("the Swagger body, pasted with its placeholder password, is accepted: 201 (what the README warns about)", status == 201, status)
finally:
    for name in NAMES:
        admin.delete("accounts/" + name)
    admin.logout()

sys.exit(c.done())
