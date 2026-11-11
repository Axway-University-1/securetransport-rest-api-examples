#!/usr/bin/env python3
"""
Build the Swagger, Postman and Bruno files of "Admin/API 2.0/json" from one source.

The source is one small JSON file per example in "Admin/API 2.0/json/examples/<topic>/".
Everything else in that folder is made from it, so the three tools cannot drift apart:

    python3 tools/build_json_examples.py            write the files
    python3 tools/build_json_examples.py --check    write nothing; exit 1 if a file is not what the
                                                    source gives (the offline test runs this)

A source file:
    name         the request's title in Postman and Bruno
    bash         the bash example that makes the same call, under Admin/API 2.0/bash
    description  what it does, in one or two sentences
    method       GET, POST...
    path         the path after /api/v2.0; a part in braces, like {name}, is a path parameter
    pathParams   (optional) the value of each path parameter
    query        (optional) the query parameters, name to value, as strings
    body         (optional) the JSON body; "{{name}}" is a variable
    variables    (optional) for each variable of the body, the text that stands for it in the
                 Swagger file, which has no variables. It must not be a real value.
    expect       the status the call answers

Output, all under "Admin/API 2.0/json":
    swagger/<topic>/<example>.body.json         a body, to paste into the Request body box of "Try it out"
    swagger/<topic>/<example>.parameters.json   the values to type into the parameter fields (a GET has no body)
    postman/ST-Admin-API-2.0.postman_collection.json, postman/lab.postman_environment.json
    bruno/                                      a Bruno collection (bruno.json, collection.bru, environments/lab.bru, the folders)

No credential and no real address is written: the host and the passwords are variables of the environment.
"""
import glob
import json
import os
import re
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
BASE = os.path.join(REPO, "Admin", "API 2.0", "json")
API_PATH = "/api/v2.0"
REFERER = "THIS_IS_A_RANDOM_TEXT"
COLLECTION_NAME = "SecureTransport Admin API 2.0 examples"
SCHEMA = "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
VARIABLE = re.compile(r"\{\{([A-Za-z0-9_]+)\}\}")

# The environment of both tools: the same names as the bash set_variables.local.sh, in lower case
ENVIRONMENT = (("server", "your-securetransport-host", False), ("port", "8444", False), ("user", "your-admin-account", False),
               ("templateClass", "your-user-class", False), ("password", "", True), ("accountPassword", "", True))


def dump(value):
    return json.dumps(value, indent=2, ensure_ascii=False) + "\n"


def load_examples():
    """[(topic, file stem, source dict)], in the order of the file names."""
    found = []
    for path in sorted(glob.glob(os.path.join(BASE, "examples", "*", "*.json"))):
        topic = os.path.basename(os.path.dirname(path))
        stem = os.path.splitext(os.path.basename(path))[0]
        with open(path, encoding="utf-8") as handle:
            found.append((topic, stem, json.load(handle)))
    return found


def number(text):
    return int(re.match(r"\d+", text).group(0))


def tool_path(path):
    """The path as Postman and Bruno write a path parameter: :name, not {name}."""
    return re.sub(r"\{([A-Za-z0-9_]+)\}", r":\1", path)


def raw_url(path, query):
    url = "https://{{server}}:{{port}}" + API_PATH + tool_path(path)
    if query:
        url += "?" + "&".join("%s=%s" % pair for pair in query.items())
    return url


def swagger_body(source):
    """The body as it is pasted: a variable is replaced by the text the source gives for it."""
    variables = source.get("variables", {})
    return VARIABLE.sub(lambda m: variables[m.group(1)], json.dumps(source["body"], indent=2, ensure_ascii=False)) + "\n"


def swagger_files(examples):
    files = {}
    for topic, stem, source in examples:
        if "body" in source:
            files["swagger/%s/%s.body.json" % (topic, stem)] = swagger_body(source)
        parameters = dict(source.get("pathParams", {}), **source.get("query", {}))
        if parameters:
            files["swagger/%s/%s.parameters.json" % (topic, stem)] = dump(parameters)
    return files


def postman_request(source):
    query = source.get("query", {})
    request = {
        "method": source["method"],
        "header": [{"key": "Referer", "value": REFERER, "type": "text"}],
        "url": {
            "raw": raw_url(source["path"], query),
            "protocol": "https",
            "host": ["{{server}}"],
            "port": "{{port}}",
            "path": API_PATH.strip("/").split("/") + tool_path(source["path"]).strip("/").split("/"),
        },
    }
    if source.get("pathParams"):
        request["url"]["variable"] = [{"key": key, "value": value} for key, value in source["pathParams"].items()]
    if query:
        request["url"]["query"] = [{"key": key, "value": value} for key, value in query.items()]
    if "body" in source:
        request["header"].append({"key": "Content-Type", "value": "application/json", "type": "text"})
        request["body"] = {"mode": "raw", "raw": json.dumps(source["body"], indent=2, ensure_ascii=False),
                           "options": {"raw": {"language": "json"}}}
    request["description"] = "%s\n\nThe same call as Admin/API 2.0/bash/%s." % (source["description"], source["bash"])
    return request


def postman_files(examples):
    topics = []
    for topic, stem, source in examples:
        if not topics or topics[-1]["name"] != topic:
            topics.append({"name": topic, "item": []})
        topics[-1]["item"].append({
            "name": "%s - %s" % (stem, source["name"]),
            "event": [{"listen": "test", "script": {"type": "text/javascript", "exec": [
                'pm.test("answers %d", function () { pm.response.to.have.status(%d); });' % (source["expect"], source["expect"])]}}],
            "request": postman_request(source),
            "response": [],
        })
    collection = {
        "info": {"name": COLLECTION_NAME, "schema": SCHEMA,
                 "description": "Made by tools/build_json_examples.py: do not edit by hand. Choose the environment 'ST lab' and fill in its values."},
        "auth": {"type": "basic", "basic": [{"key": "username", "value": "{{user}}", "type": "string"},
                                            {"key": "password", "value": "{{password}}", "type": "string"}]},
        "item": topics,
    }
    environment = {
        "name": "ST lab",
        "values": [{"key": key, "value": value, "type": "secret" if secret else "default", "enabled": True}
                   for key, value, secret in ENVIRONMENT],
        "_postman_variable_scope": "environment",
    }
    return {"postman/ST-Admin-API-2.0.postman_collection.json": dump(collection),
            "postman/lab.postman_environment.json": dump(environment)}


def bru_block(name, lines):
    return name + " {\n" + "".join(("  %s\n" % line).rstrip(" ") if line else "\n" for line in lines) + "}\n"


def bruno_request(stem, source, position):
    query = source.get("query", {})
    parts = [bru_block("meta", ["name: %s - %s" % (stem, source["name"]), "type: http", "seq: %d" % position]),
             bru_block(source["method"].lower(), ["url: " + raw_url(source["path"], query),
                                                  "body: " + ("json" if "body" in source else "none"), "auth: inherit"])]
    if source.get("pathParams"):
        parts.append(bru_block("params:path", ["%s: %s" % pair for pair in source["pathParams"].items()]))
    if query:
        parts.append(bru_block("params:query", ["%s: %s" % pair for pair in query.items()]))
    if "body" in source:
        parts.append(bru_block("headers", ["Content-Type: application/json"]))
        parts.append(bru_block("body:json", json.dumps(source["body"], indent=2, ensure_ascii=False).split("\n")))
    parts.append(bru_block("assert", ["res.status: eq %d" % source["expect"]]))
    parts.append(bru_block("docs", ["%s" % source["description"], "", "The same call as Admin/API 2.0/bash/%s." % source["bash"]]))
    return "\n".join(parts)


def bruno_files(examples):
    files = {
        "bruno/bruno.json": dump({"version": "1", "name": COLLECTION_NAME, "type": "collection", "ignore": ["node_modules", ".git"]}),
        "bruno/collection.bru": "\n".join([
            bru_block("headers", ["Referer: " + REFERER]),
            bru_block("auth", ["mode: basic"]),
            bru_block("auth:basic", ["username: {{user}}", "password: {{password}}"])]),
        "bruno/environments/lab.bru": "\n".join([
            bru_block("vars", ["%s: %s" % (key, value) for key, value, secret in ENVIRONMENT if not secret]),
            "vars:secret [\n" + ",\n".join("  " + key for key, value, secret in ENVIRONMENT if secret) + "\n]\n"]),
    }
    position = {}
    for topic, stem, source in examples:
        position[topic] = position.get(topic, 0) + 1
        files["bruno/%s/folder.bru" % topic] = bru_block("meta", ["name: " + topic, "seq: %d" % number(topic)])
        files["bruno/%s/%s.bru" % (topic, stem)] = bruno_request(stem, source, position[topic])
    return files


def build():
    examples = load_examples()
    files = {}
    for part in (swagger_files, postman_files, bruno_files):
        files.update(part(examples))
    return files


def main(argv):
    if len(argv) > 1 and argv[1] != "--check" or len(argv) > 2:
        print("Usage: build_json_examples.py [--check]")
        return 2
    check = len(argv) == 2
    stale = []
    for relative, text in sorted(build().items()):
        path = os.path.join(BASE, relative)
        current = open(path, encoding="utf-8").read() if os.path.exists(path) else None
        if current == text:
            continue
        stale.append(relative)
        if not check:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(text)
    for relative in stale:
        print(("stale: " if check else "wrote: ") + relative)
    return 1 if check and stale else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
