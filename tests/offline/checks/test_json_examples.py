#!/usr/bin/env python3
"""
Check "Admin/API 2.0/json": the Swagger, Postman and Bruno files made by tools/build_json_examples.py.

They are made from one source, so the checks are: no file differs from what the source gives, the
generator notices when one does, every file is well formed for its tool, the calls are the ones of the
bash examples, and nothing in them is a credential or a real address.

Runs offline. Exit code 0 means clean.
"""
import glob
import json
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tools"))
import build_json_examples as gen  # noqa: E402

BASE = os.path.join(REPO, "Admin", "API 2.0", "json")
BASH = os.path.join(REPO, "Admin", "API 2.0", "bash")
failed = 0


def check(label, ok, got=None):
    global failed
    print(("  PASS  " if ok else "  FAIL  ") + label + ("" if ok or got is None else "  got: %r" % (got,)))
    failed += 0 if ok else 1


def read(*parts):
    with open(os.path.join(BASE, *parts), encoding="utf-8") as handle:
        return handle.read()


def files_under(root):
    return sorted(os.path.relpath(os.path.join(d, f), root) for d, _, names in os.walk(root) for f in names)


print("=== the files are what the source gives ===")
built = gen.build()
check("no file is stale (python3 tools/build_json_examples.py would change nothing)",
      all(os.path.isfile(os.path.join(BASE, r)) and read(r) == t for r, t in built.items()),
      [r for r, t in built.items() if not os.path.isfile(os.path.join(BASE, r)) or read(r) != t])
check("no file is left over: every file under swagger, postman and bruno is made from a source",
      [f for f in files_under(BASE) if not f.startswith(("examples", "README"))] == sorted(built), files_under(BASE))

work = tempfile.mkdtemp(prefix="json_examples_", dir=os.environ.get("ST_TEST_OUTPUT") or None)
saved = gen.BASE
try:
    gen.BASE = os.path.join(work, "json")
    shutil.copytree(os.path.join(BASE, "examples"), os.path.join(gen.BASE, "examples"))
    check("--check on an empty folder finds every file stale and writes nothing", gen.main(["x", "--check"]) == 1
          and not os.path.exists(os.path.join(gen.BASE, "postman")))
    check("without --check it writes them, and --check is then clean", gen.main(["x"]) == 0 and gen.main(["x", "--check"]) == 0)
    victim = os.path.join(gen.BASE, "postman", "ST-Admin-API-2.0.postman_collection.json")
    with open(victim, "a", encoding="utf-8") as handle:
        handle.write(" ")
    check("a file changed by hand is found", gen.main(["x", "--check"]) == 1)
    source = os.path.join(gen.BASE, "examples", "05.Accounts", "01.accounts_GET.json")
    with open(source, encoding="utf-8") as handle:
        data = json.load(handle)
    data["query"]["limit"] = "7"
    with open(source, "w", encoding="utf-8") as handle:
        json.dump(data, handle)
    gen.main(["x"])
    check("a change of the source reaches all three tools",
          all("7" in open(os.path.join(gen.BASE, r), encoding="utf-8").read() for r in
              ("swagger/05.Accounts/01.accounts_GET.parameters.json", "bruno/05.Accounts/01.accounts_GET.bru",
               "postman/ST-Admin-API-2.0.postman_collection.json")))
    check("a wrong argument is a usage error", gen.main(["x", "--nope"]) == 2)
finally:
    gen.BASE = saved
    shutil.rmtree(work, ignore_errors=True)

print("=== the source files ===")
sources = [(os.path.splitext(os.path.basename(p))[0], json.load(open(p, encoding="utf-8"))) for p in sorted(glob.glob(os.path.join(BASE, "examples", "*", "*.json")))]
by_stem = dict(sources)
METHOD_OF = re.compile(r"_(GET|HEAD|POST|PUT|PATCH|DELETE)(_|\.)")
check("there are examples, and the topic is 05.Accounts", len(sources) >= 20 and os.listdir(os.path.join(BASE, "examples")) == ["05.Accounts"], len(sources))
all_bash = ""
for stem, data in sources:
    check("%s has what the generator reads" % stem, all(k in data for k in ("name", "bash", "description", "method", "path", "expect")))
    check("%s: the bash example it names exists, and is the one of its method" % stem,
          os.path.isfile(os.path.join(BASH, data["bash"])) and METHOD_OF.search(os.path.basename(data["bash"])).group(1) == data["method"]
          or data["method"] == "PATCH" and "PATCH" in data["bash"], data["bash"])
    names = set(re.findall(r"\{\{([A-Za-z0-9_]+)\}\}", json.dumps(data.get("body", {}))))
    check("%s: each variable of the body has its Swagger text, and that is not a real value" % stem,
          names == set(data.get("variables", {})) and all(re.fullmatch(r"[A-Z_]+", v) for v in data.get("variables", {}).values()),
          (names, data.get("variables")))
    check("%s: each {parameter} of the path is given a value, and a body has a method that takes one" % stem,
          set(re.findall(r"\{(\w+)\}", data["path"])) == set(data.get("pathParams", {}))
          and ("body" not in data or data["method"] in ("POST", "PUT", "PATCH")), data["path"])
    check("%s: the statuses are those of its method (GET and HEAD 200, POST 201, PUT, PATCH and DELETE 204), or an error on purpose" % stem,
          data["expect"] in ({"POST": 201, "PUT": 204, "PATCH": 204, "DELETE": 204}.get(data["method"], 200), 400, 404, 409), data["expect"])
for script in sorted(glob.glob(os.path.join(BASH, "05.Accounts", "0[1-7].*.sh"))):
    all_bash += open(script, encoding="utf-8").read()
bash_names = {os.path.basename(script) for script in glob.glob(os.path.join(BASH, "05.Accounts", "*.sh"))}
used = {data["bash"].split("/")[1] for _, data in sources}
left_out = sorted(bash_names - used)
check("every bash example of 05.Accounts has JSON examples, but the ones the README says it leaves out",
      left_out == ["06.accounts_name_PATCH_secretQuestion.sh"], left_out)
check("the order is the order to run them: 02 user before its duplicate, the PUT before the patches, the deletes last",
      [s for s, _ in sources] == sorted(s for s, _ in sources) and [s for s, _ in sources].index("02.accounts_POST_user") < [s for s, _ in sources].index("02.accounts_POST_user_duplicate")
      and [s for s, _ in sources][-3:] == ["07.accounts_name_DELETE_service", "07.accounts_name_DELETE_template", "07.accounts_name_DELETE_user"])

print("=== the calls are those of the bash examples ===")
get = by_stem["01.accounts_GET"]
post = by_stem["02.accounts_POST_user"]
bash_get = open(os.path.join(BASH, "05.Accounts", "01.accounts_GET.sh"), encoding="utf-8").read()
bash_post = open(os.path.join(BASH, "05.Accounts", "02.accounts_POST.sh"), encoding="utf-8").read()
query = "&".join("%s=%s" % pair for pair in get["query"].items())
check("the GET: the bash example makes this very call (path and query)", "https://${ST_SERVER}:${ST_PORT}/api/v2.0%s?%s" % (get["path"], query) in bash_get, query)
for kind in ("user", "service", "template"):
    body = by_stem["02.accounts_POST_" + kind]["body"]
    check("the POST of the %s: name, type, home folder, uid and gid are the bash example's" % kind,
          'name: $name, type: "%s", homeFolder: ("/home/" + $name), uid: "%s", gid: "%s"' % (kind, body["uid"], body["gid"]) in bash_post
          and body["name"] == "example_" + kind and body["homeFolder"] == "/home/" + body["name"], body)
patch_text = all_bash + open(os.path.join(BASH, "05.Accounts", "06.patch_body", "stPatchAccountNotes.json"), encoding="utf-8").read()
check("the PUT makes the uid 1111, as the bash example does by default", by_stem["05.accounts_name_PUT_user"]["body"]["uid"] == "1111"
      and by_stem["05.accounts_name_PUT_service"]["body"]["uid"] == "1111" and '${2:-1111}' in all_bash)
check("each path of a patch is one that a bash example patches (the contact removed by its position is the one made up by the script)",
      all('"%s"' % op["path"] in patch_text for s, d in sources if d["method"] == "PATCH" for op in d["body"] if not op["path"].endswith("contacts/0")),
      [op["path"] for s, d in sources if d["method"] == "PATCH" for op in d["body"] if '"%s"' % op["path"] not in patch_text])
check("the examples that answer an error are the ones the bash examples explain: the duplicate (409), the type missing (400), the name missing (404)",
      [(s, d["expect"]) for s, d in sources if d["expect"] >= 400] ==
      [("02.accounts_POST_user_duplicate", 409), ("03.accounts_name_HEAD_missing", 404), ("04.accounts_name_GET_fields_without_type", 400)])

print("=== Swagger ===")
body = post["body"]
pasted = json.loads(read("swagger", "05.Accounts", "02.accounts_POST_user.body.json"))
check("the body is the source body, with the placeholder in place of the variable",
      pasted["user"]["passwordCredentials"]["password"] == post["variables"]["accountPassword"]
      and {k: v for k, v in pasted.items() if k != "user"} == {k: v for k, v in body.items() if k != "user"})
check("a body file for each example with a body, a parameters file for each with a path parameter or a query, and no other",
      sorted(f for f in built if f.startswith("swagger/")) == sorted(
          ["swagger/05.Accounts/%s.%s.json" % (s, kind) for s, d in sources for kind, present in
           (("body", "body" in d), ("parameters", bool(d.get("pathParams") or d.get("query")))) if present]))
check("the parameters are the path parameters and the query of the source, in one object",
      json.loads(read("swagger", "05.Accounts", "04.accounts_name_GET_fields.parameters.json")) == {"name": "example_user", "fields": "name,homeFolder,uid"})
check("a patch is pasted as the list it is", isinstance(json.loads(read("swagger", "05.Accounts", "06.accounts_name_PATCH_1_replace_policy.body.json")), list))
check("no Swagger file has a {{variable}}, which Swagger would send as it is", not any("{{" in read(f) for f in built if f.startswith("swagger/")))

print("=== Postman ===")
collection = json.loads(read("postman", "ST-Admin-API-2.0.postman_collection.json"))
environment = json.loads(read("postman", "lab.postman_environment.json"))
check("a v2.1 collection, with Basic auth from variables",
      collection["info"]["schema"].endswith("/v2.1.0/collection.json") and collection["auth"]["type"] == "basic"
      and {e["key"]: e["value"] for e in collection["auth"]["basic"]} == {"username": "{{user}}", "password": "{{password}}"})
requests = [i for topic in collection["item"] for i in topic["item"]]
check("one request for each source, in order, under its topic", [r["name"].split(" - ")[0] for r in requests] == [s for s, _ in sources]
      and [t["name"] for t in collection["item"]] == ["05.Accounts"])
for item, (stem, source) in zip(requests, sources):
    request = item["request"]
    check("%s: method, address, the Referer the server expects, and a test of the status %d" % (stem, source["expect"]),
          request["method"] == source["method"] and request["url"]["raw"].startswith("https://{{server}}:{{port}}/api/v2.0" + gen.tool_path(source["path"]))
          and {"key": "Referer", "value": "THIS_IS_A_RANDOM_TEXT", "type": "text"} in request["header"]
          and "have.status(%d)" % source["expect"] in "".join(item["event"][0]["script"]["exec"]), request)
    check("%s: the path parameters are variables of the request, and the query is as the source gives it" % stem,
          {v["key"]: v["value"] for v in request["url"].get("variable", [])} == source.get("pathParams", {})
          and [(q["key"], q["value"]) for q in request["url"].get("query", [])] == list(source.get("query", {}).items()))
    if "body" in source:
        check("%s: the body is the source body as JSON, with a Content-Type, the variables left in" % stem,
              json.loads(request["body"]["raw"]) == source["body"] and request["body"]["options"]["raw"]["language"] == "json"
              and {"key": "Content-Type", "value": "application/json", "type": "text"} in request["header"])
    else:
        check("%s: no body" % stem, "body" not in request)
values = {v["key"]: v for v in environment["values"]}
check("the environment has the six names; the two passwords are secret and empty",
      set(values) == {"server", "port", "user", "templateClass", "password", "accountPassword"}
      and all(values[k]["type"] == "secret" and values[k]["value"] == "" for k in ("password", "accountPassword")))

print("=== Bruno ===")
collection_bru = read("bruno", "collection.bru")
check("the collection has the Referer and Basic auth from variables", "Referer: THIS_IS_A_RANDOM_TEXT" in collection_bru
      and "mode: basic" in collection_bru and "username: {{user}}" in collection_bru and "password: {{password}}" in collection_bru)
check("bruno.json names a collection", json.loads(read("bruno", "bruno.json"))["type"] == "collection")
env_bru = read("bruno", "environments", "lab.bru")
check("the environment has the four plain values and lists the two passwords as secret",
      all(k + ":" in env_bru.split("vars:secret")[0] for k in ("server", "port", "user", "templateClass")) and re.search(r"vars:secret \[\s*password,\s*accountPassword\s*\]", env_bru))
seqs = []
for position, (stem, source) in enumerate(sources, 1):
    text = read("bruno", "05.Accounts", stem + ".bru")
    method = source["method"].lower()
    check("%s: method and address as in Postman, auth from the collection, the status asserted" % stem,
          re.search(r"^%s \{\n  url: %s\n" % (method, re.escape(gen.raw_url(source["path"], source.get("query")))), text, re.M)
          and "auth: inherit" in text and "res.status: eq %d" % source["expect"] in text, text)
    seqs.append(int(re.search(r"seq: (\d+)", text).group(1)))
    check("%s: path parameters and query listed as Bruno wants them" % stem,
          all("  %s: %s\n" % pair in text.split("params:path {")[1].split("}")[0] for pair in source.get("pathParams", {}).items())
          and all("  %s: %s\n" % pair in text.split("params:query {")[1].split("}")[0] for pair in source.get("query", {}).items()))
    if "body" in source:
        bru_body = re.search(r"body:json \{\n(.*?)\n\}\n", text, re.S).group(1)
        check("%s: the body is the source body, as JSON" % stem, json.loads(bru_body) == source["body"])
check("seq runs 1, 2, 3... in the order of the examples, so that Bruno runs them in that order", seqs == list(range(1, len(sources) + 1)), seqs)
check("the folder has its number", "seq: 5\n" in read("bruno", "05.Accounts", "folder.bru"))

print("=== nothing of ours in them ===")
text_of_all = "\n".join(read(f) for f in files_under(BASE) if f != "README.md")
check("no address of a real server, and no plain http", not re.search(r"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b|http://", text_of_all))
check("no password value other than the placeholder: the only password of a body is a variable or the placeholder",
      set(re.findall(r'"password": "([^"]*)"', text_of_all)) <= {"{{accountPassword}}", "{{password}}", "REPLACE_WITH_A_PASSWORD"})

print("=== the README ===")
readme = read("README.md")
check("the README says the placeholder is accepted, that the duplicate answers 409, and what is left out",
      "The placeholder password is accepted" in readme and "409" in readme and "06.accounts_name_PATCH_secretQuestion.sh" in readme)
check("the README says what was not tried: the apps, a browser, Bruno importing Postman", "were not opened" in readme and "not tried here" in readme)
check("the README lists every example, each with its status", all("| `%s` |" % s in readme for s, _ in sources) and readme.count("| `0") >= len(sources))
check("the README names the number of examples as the folder has them", "%d examples" % len(sources) in readme, len(sources))
check("every file it names under bash/ exists", all(os.path.exists(os.path.join(BASE, p)) for p in re.findall(r"\]\((\.\./bash/[^)#]+)\)", readme)))
check("the Admin README and CONTRIBUTING.md name the folder and the tool",
      "json/README.md" in open(os.path.join(REPO, "Admin", "API 2.0", "README.md"), encoding="utf-8").read()
      and "build_json_examples.py" in open(os.path.join(REPO, "CONTRIBUTING.md"), encoding="utf-8").read())

print()
print("test_json_examples: %s" % ("PASS" if not failed else "FAIL"))
sys.exit(1 if failed else 0)
