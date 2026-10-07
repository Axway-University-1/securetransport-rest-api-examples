#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified 29.MailTemplates examples 01 to
06 against throwaway mail templates: "example_mail.xhtml", "EXAMPLE_MAIL.xhtml"
(the same name in capitals: the server keeps them apart) and "example other.xhtml"
(a space in the name). Each effect is read back through the API: the template's
description, and its content, which is compared with the file that was uploaded.

It shows what the examples teach and the reference does not say:
  - a file that is not named *.xhtml still goes up, because the script sends it
    under the template's name;
  - a name with a / is refused by the script (the server would accept it, and
    then the template could not be addressed or deleted);
  - a PUT with no description clears it, so 05 reads it first and sends it back;
  - a PUT on a name that does not exist CREATES the template (204), so 05 looks
    first and refuses; the raw PUT is made here, once, to show it.

Never touches a template it did not create: it refuses to start when any of the
three names exists, and removes them in a finally block, whatever happens. The
server's own templates are only listed and read, never changed. Needs --write and
st_allow_writes="yes".
"""
import os
import sys
import tempfile
import urllib.error
import urllib.request
from urllib.parse import quote

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    st_client.skip("no tests/local/integration.conf, so there is no server to talk to")
if "--write" not in sys.argv:
    st_client.skip("read only run, pass --write to run the mail template examples for real")
if config.get("st_allow_writes", "no").lower() not in ("yes", "true", "1"):
    st_client.skip('st_allow_writes is not "yes" in integration.conf')

c = st_client.Checker("Mail templates, run for real from Admin/API 2.0/bash/29.MailTemplates (01 to 06)")
FOLDER = os.path.join(runner.path("Admin", "API 2.0", "bash"), "29.MailTemplates")
LOWER, UPPER, SPACED = "example_mail.xhtml", "EXAMPLE_MAIL.xhtml", "example other.xhtml"
NAMES = (LOWER, UPPER, SPACED)
WORK = tempfile.mkdtemp(prefix="st_mail_")


def mail_path(name):
    return "mailTemplates/" + quote(name, safe="")


def script(name, args=None, expect_rc=0):
    result = runner.run(os.path.join(FOLDER, name), args, timeout=60)
    out = result.stdout + result.stderr
    c.check("%s %s exits %s" % (name, " ".join(args or []), expect_rc), result.returncode == expect_rc,
            out.strip()[-300:])
    return out


def listed(name):
    """The list entry of one template, by exact name, or None."""
    result = (admin.get("mailTemplates", params={"name": name}).json() or {}).get("result") or []
    return result[0] if result else None


def content(name):
    return admin.get(mail_path(name)).text


def write(name, text):
    path = os.path.join(WORK, name)
    with open(path, "w") as handle:
        handle.write(text)
    return path


def raw_put(name, text, description):
    """A PUT of a form with nothing in front of it, to see what the server does."""
    boundary = "----example"
    parts = ('--%s\r\nContent-Disposition: form-data; name="file"; filename="%s"\r\nContent-Type: application/xhtml+xml\r\n\r\n%s\r\n'
             % (boundary, name, text))
    if description is not None:
        parts += '--%s\r\nContent-Disposition: form-data; name="description"\r\n\r\n%s\r\n' % (boundary, description)
    parts += "--%s--\r\n" % boundary
    headers = {"Referer": admin.referer, "Content-Type": "multipart/form-data; boundary=" + boundary}
    if admin._csrf:
        headers["csrfToken"] = admin._csrf
    request = urllib.request.Request(admin.base + mail_path(name), data=parts.encode(), headers=headers, method="PUT")
    try:
        return admin._opener.open(request, timeout=admin.timeout).status
    except urllib.error.HTTPError as e:
        return e.code


admin = st_client.connect(config, c)
if st_client.is_mock(admin):
    c.info("the bundled mock does not implement /mailTemplates")
    admin.logout()
    sys.exit(c.done())
if any(listed(name) for name in NAMES):
    c.check("%s do not exist yet" % ", ".join(NAMES), False, "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

TOKEN = os.urandom(4).hex()
SLASHED = "example_%s/b.xhtml" % TOKEN  # the server would take it, and then it could never be deleted
ORIGINAL = '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><body><p>original %s</p></body></html>\n' % TOKEN
REPLACED = '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><body><p>replaced %s</p></body></html>\n' % TOKEN
PLAIN = "this is plain text, not xhtml, %s\n" % TOKEN
before = (admin.get("mailTemplates", params={"limit": 1, "fields": "name"}).json() or {}).get("resultSet", {}).get("totalCount")
server_own = sorted(e["name"] for e in (admin.get("mailTemplates", params={"limit": 100, "fields": "name"}).json() or {}).get("result", []))

try:
    with runner.real_credentials(runner.path("Admin", "API 2.0", "bash"), config):
        # 02 POST
        out = script("02.mailTemplates_POST.sh")
        c.check("02 with no arguments, the sample is created with the default description",
                (listed(LOWER) or {}).get("description") == "Created by 29.MailTemplates", out[-200:])
        c.check("02 the sample the script wrote is what the server holds", "$MESSAGE" in content(LOWER), content(LOWER)[:200])
        out = script("02.mailTemplates_POST.sh", [LOWER], expect_rc=1)
        c.check("02 a name that exists is refused, and says so", "already exists" in out, out[-200:])
        out = script("02.mailTemplates_POST.sh", [SPACED, write("plain.txt", PLAIN), "a <b> & @x description"])
        c.check("02 a file not named .xhtml goes up under the template's name, content untouched",
                content(SPACED) == PLAIN, content(SPACED)[:100])
        c.check("02 the description is stored as typed (< & @ included)",
                (listed(SPACED) or {}).get("description") == "a <b> & @x description")
        script("02.mailTemplates_POST.sh", [UPPER, write("original.xhtml", ORIGINAL), ""])
        c.check("02 the same name in capitals is another template", content(UPPER) == ORIGINAL and listed(LOWER) is not None)
        c.check("02 an empty description is stored empty", (listed(UPPER) or {}).get("description") == "")
        for bad in (SLASHED, "example_mail.txt"):
            script("02.mailTemplates_POST.sh", [bad], expect_rc=2)
        c.check("02 nothing was created by the refused names",
                listed(SLASHED) is None and listed("example_mail.txt") is None)

        # 01 GET
        out = script("01.mailTemplates_GET.sh", [SPACED, "Created by 29.MailTemplates"])
        c.check("01 the count says how many there are", "Mail templates: %s" % (before + 3) in out, out[:120])
        c.check("01 lists the templates with their descriptions", "  %s  Created by 29.MailTemplates" % LOWER in out, out[-400:])
        c.check("01 the name filter finds the one with a space", out.count("  %s  " % SPACED) >= 2, out[-400:])
        out = script("01.mailTemplates_GET.sh", ["example*"])
        c.check("01 name= has no wildcard: the pattern finds nothing", out.split("Named example*:")[-1].strip() == "", out[-200:])

        # 03 HEAD
        out = script("03.mailTemplates_name_HEAD.sh", [SPACED])
        c.check("03 finds a template with a space in its name", "The mail template %s exists." % SPACED in out, out[-200:])
        admin.delete(mail_path(UPPER))
        out = script("03.mailTemplates_name_HEAD.sh", [UPPER], expect_rc=1)
        c.check("03 says so for a name that does not exist", "does not exist (HTTP 404)" in out, out[-200:])
        script("03.mailTemplates_name_HEAD.sh", [SLASHED], expect_rc=2)

        # 04 GET
        saved = os.path.join(WORK, "saved.xhtml")
        out = script("04.mailTemplates_name_GET.sh", [SPACED, saved])
        c.check("04 prints the description", "a <b> & @x description" in out, out[-300:])
        c.check("04 saves the file exactly as uploaded", os.path.exists(saved) and open(saved).read() == PLAIN)
        out = script("04.mailTemplates_name_GET.sh", [UPPER, os.path.join(WORK, "gone.xhtml")], expect_rc=1)
        c.check("04 an unknown name is refused with the server's reason, and no file is left",
                "HTTP 404" in out and not os.path.exists(os.path.join(WORK, "gone.xhtml")), out[-200:])
        own = next((n for n in server_own if "/" not in n), None)
        if own:
            out = script("04.mailTemplates_name_GET.sh", [own, os.path.join(WORK, "own.xhtml")])
            c.check("04 reads one of the server's own templates (it is not changed)", "Written to" in out, out[-200:])

        # 05 PUT
        out = script("05.mailTemplates_name_PUT.sh", [LOWER, write("replaced.xhtml", REPLACED)])
        c.check("05 the content is replaced", content(LOWER) == REPLACED, content(LOWER)[:200])
        c.check("05 and the description is kept (a bare PUT would clear it)",
                (listed(LOWER) or {}).get("description") == "Created by 29.MailTemplates")
        script("05.mailTemplates_name_PUT.sh", [LOWER, os.path.join(WORK, "replaced.xhtml"), "New description"])
        c.check("05 a description given replaces the old", (listed(LOWER) or {}).get("description") == "New description")
        script("05.mailTemplates_name_PUT.sh", [LOWER, os.path.join(WORK, "replaced.xhtml"), ""])
        c.check("05 an empty one clears it, to an empty string", (listed(LOWER) or {}).get("description") == "")
        out = script("05.mailTemplates_name_PUT.sh", [UPPER, os.path.join(WORK, "replaced.xhtml")], expect_rc=1)
        c.check("05 a template that is not there is not created", "There is no mail template" in out and listed(UPPER) is None, out[-200:])
        script("05.mailTemplates_name_PUT.sh", [SLASHED, os.path.join(WORK, "replaced.xhtml")], expect_rc=2)
        # What the script guards against: the server's own PUT creates, and clears a missing description
        c.check("the raw PUT of a missing name answers 204 and creates it (the reference says 404)",
                raw_put(UPPER, REPLACED, "raw") == 204 and (listed(UPPER) or {}).get("description") == "raw")
        c.check("the raw PUT with no description sets it to null",
                raw_put(LOWER, REPLACED, None) == 204 and (listed(LOWER) or {}).get("description") is None)

        # 06 DELETE
        for name in (UPPER, LOWER, SPACED):
            out = script("06.mailTemplates_name_DELETE.sh", [name])
            c.check("06 deleted %s" % name, listed(name) is None and "HTTP 204" in out, out[-200:])
        out = script("06.mailTemplates_name_DELETE.sh", [LOWER], expect_rc=1)
        c.check("06 a second delete is a 404, with the server's reason", "HTTP 404" in out and "not found" in out, out[-200:])
        script("06.mailTemplates_name_DELETE.sh", [SLASHED], expect_rc=2)
finally:
    for name in NAMES:
        if admin.exists(mail_path(name)):
            admin.delete(mail_path(name))
    after = sorted(e["name"] for e in (admin.get("mailTemplates", params={"limit": 100, "fields": "name"}).json() or {}).get("result", []))
    c.check("nothing is left behind: the server's own templates are exactly as before", after == server_own,
            "before %s, after %s" % (server_own, after))
    admin.logout()

sys.exit(c.done())
