#!/usr/bin/env python3
"""
WRITES TO THE SERVER (two throwaway users with a name that is new on every run, example_mbx_*, which it removes, and the messages and folders they make, which it deletes first: the mailbox of
a user outlives his account, and the messages of a deleted account cannot be deleted any more). Runs the End User API 1.4 mailbox examples (EndUser/API 1.4/bash/01.Mailbox) for real, one user as
the sender and one as the recipient, each with a settings file of his own (ST_ENDUSER_LOCAL_VARIABLES).

It proves what the README of that folder says, through the examples' own output: a draft is made (the call answers 500 and the draft is saved: the example finds it), a draft is in Drafts with the
level EXISTING_ACCOUNT, a message to oneself is sent and stays in the sender's Sent folder (it is not in his Inbox), a message that is sent reaches the recipient's Inbox with the same id, reading it does not mark it read and the property
isRead does, a folder is made, a message is moved into it, a folder that is not empty is refused and an empty one is deleted, a message is deleted, and the history of the message says that the
recipient opened it. The text, the search and the attachment are the things the README says are not confirmed: the check only asks that the examples end in a clear answer.

Needs --write and st_allow_writes="yes", and the End User port. It does not run on the bundled mock, which has no API 1.4.
"""
import os
import re
import sys
import tempfile
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the End User API 1.4 mailbox examples for real")

c = st_client.Checker("End User API 1.4 mailbox examples, run for real")
FOLDER = runner.path("EndUser", "API 1.4", "bash", "01.Mailbox")
PASSWORD = "Ex1!mailbox-Pass-77"
STAMP = str(int(time.time()))[-7:]
SENDER, RECIPIENT = "example_mbx_s%s" % STAMP, "example_mbx_r%s" % STAMP
PORT = harness.ports(config).enduser
settings = {}

admin = harness.connect(config, c, mock="the bundled mock has no API 1.4; run this against a real server to exercise it")


def settings_file(user):
    fd, path = tempfile.mkstemp(prefix="st_mailbox_", suffix=".sh")
    with os.fdopen(fd, "w") as f:
        f.write('#!/bin/bash\nexport ST_SERVER="%s"\nexport ST_PORT="%s"\nexport ST_USER="%s"\nexport ST_PASSWORD="%s"\n' % (config["st_server"], PORT, user, PASSWORD))
    return path


def run(user, script, *args):
    return runner.run(os.path.join(FOLDER, script), list(args), timeout=90, env={"ST_ENDUSER_LOCAL_VARIABLES": settings[user]})


def ids(output):
    return re.findall(r"^  ([0-9a-f]{32})", output, re.M)


def purge(user):
    """Delete the messages of the user, then his folders that are not system ones."""
    for folder in ("Inbox", "Sent", "Drafts", "Archive"):
        for message_id in ids(run(user, "04.mailbox_folders_name_GET.sh", folder, "100").stdout):
            run(user, "12.mailbox_messages_id_DELETE.sh", message_id)
    run(user, "13.mailbox_folders_name_DELETE.sh", "Archive")


def make_user(name, uid):
    r = admin.post("accounts", {"name": name, "type": "user", "homeFolder": "/home/" + name, "uid": str(uid), "gid": str(uid), "contact": {"email": name + "@example.com"},
                                "user": {"name": name, "passwordCredentials": {"password": PASSWORD}}})
    return r.status


made = []
try:
    for name, uid in ((SENDER, 58601), (RECIPIENT, 58602)):
        status = make_user(name, uid)
        c.check("the throwaway user %s is made (201)" % name, status == 201, status)
        if status == 201:
            made.append(name)
        settings[name] = settings_file(name)
    if len(made) != 2:
        raise SystemExit(c.done())

    # -- the reads --------------------------------------------------------------------------------------------
    r = run(SENDER, "01.mailbox_myself_GET.sh")
    c.check("01: exit 0, the mailbox user has the email of the account", r.returncode == 0 and "email: %s@example.com" % SENDER in r.stdout, r.stdout[-300:])
    r = run(SENDER, "02.mailbox_folders_GET.sh")
    c.check("02: a new user has Inbox, Sent and Drafts, all empty", r.returncode == 0 and all("  %s: 0 messages, 0 unread" % f in r.stdout for f in ("Inbox", "Sent", "Drafts")), r.stdout[-300:])
    r = run(RECIPIENT, "03.mailbox_folders_POST.sh", "Archive")
    c.check("03: a folder is made (204)", r.returncode == 0 and "was made (HTTP 204)" in r.stdout, (r.returncode, r.stdout[-300:]))
    r = run(RECIPIENT, "02.mailbox_folders_GET.sh")
    c.check("02: and it is listed", "  Archive: 0 messages" in r.stdout, r.stdout[-300:])

    # -- a draft, a message to oneself, a message to the other ------------------------------------------------
    r = run(SENDER, "05.mailbox_messages_POST_draft.sh", SENDER + "@example.com", "To myself", "x")
    own = (re.findall(r"Its id: ([0-9a-f]{32})", r.stdout) or [None])[0]
    c.check("05: a draft is made and its id is printed (the call answers 500 and the draft is saved, or it answers 200)", r.returncode == 0 and own is not None, (r.returncode, r.stdout[-400:]))
    if own:
        r = run(SENDER, "07.mailbox_messages_id_send_PUT.sh", own)
        c.check("07: a message to oneself is sent (200)", r.returncode == 0 and "HTTP 200: Your message has been sent." in r.stdout, (r.returncode, r.stdout[-300:]))
        stays = harness.wait_until(lambda: own in ids(run(SENDER, "04.mailbox_folders_name_GET.sh", "Sent").stdout), timeout=20, interval=2)
        c.check("04: it is in the Sent folder of the sender, and not in his Inbox", bool(stays) and own not in ids(run(SENDER, "04.mailbox_folders_name_GET.sh").stdout))
        run(SENDER, "12.mailbox_messages_id_DELETE.sh", own)

    r = run(SENDER, "05.mailbox_messages_POST_draft.sh", RECIPIENT + "@example.com", "Hello recipient", "The text")
    message = (re.findall(r"Its id: ([0-9a-f]{32})", r.stdout) or [None])[0]
    c.check("05: the draft to the recipient has an id", message is not None, r.stdout[-400:])
    if message is None:
        raise SystemExit(c.done())
    r = run(SENDER, "06.mailbox_messages_id_GET.sh", message)
    c.check("06: the draft is in Drafts, with the level EXISTING_ACCOUNT, to the recipient", r.returncode == 0 and "  folder: Drafts" in r.stdout and "  security: EXISTING_ACCOUNT" in r.stdout
            and "  to: %s@example.com" % RECIPIENT in r.stdout and "  draft: true" in r.stdout, r.stdout[-500:])
    r = run(SENDER, "07.mailbox_messages_id_send_PUT.sh", message)
    c.check("07: the draft is sent (200)", r.returncode == 0 and "HTTP 200: Your message has been sent." in r.stdout, (r.returncode, r.stdout[-300:]))
    arrived = harness.wait_until(lambda: message in ids(run(RECIPIENT, "04.mailbox_folders_name_GET.sh").stdout), timeout=30, interval=2)
    c.check("04: the message reaches the Inbox of the recipient, with the SAME id", bool(arrived))

    # -- the recipient reads it -------------------------------------------------------------------------------
    r = run(RECIPIENT, "06.mailbox_messages_id_GET.sh", message)
    c.check("06: in the Inbox, unread, from the sender", r.returncode == 0 and "  folder: Inbox" in r.stdout and "  unread: true" in r.stdout and "  from: %s@example.com" % SENDER in r.stdout, r.stdout[-500:])
    r = run(RECIPIENT, "09.mailbox_messages_id_customProperties_GET.sh", message)
    c.check("09: isRead is false: reading the message did not mark it", "  isRead: false" in r.stdout, r.stdout[-300:])
    streams = re.findall(r"text streams: ([0-9a-f]{32})", run(RECIPIENT, "06.mailbox_messages_id_GET.sh", message).stdout)
    if streams:
        r = run(RECIPIENT, "08.mailbox_messages_id_content_GET.sh", message, streams[0])
        c.check("08: the text ends in a clear answer (the lab stores an empty one: not confirmed)", r.returncode == 0 and r.stdout.strip() != "", (r.returncode, r.stdout[-300:]))
    r = run(RECIPIENT, "10.mailbox_messages_id_customProperties_PUT_read.sh", message)
    c.check("10: isRead true (204)", r.returncode == 0 and "isRead is true (HTTP 204)." in r.stdout, (r.returncode, r.stdout[-300:]))
    r = run(RECIPIENT, "06.mailbox_messages_id_GET.sh", message)
    c.check("06: now the message is not unread", "  unread: false" in r.stdout, r.stdout[-400:])
    r = run(SENDER, "15.mailbox_messageHistory_GET.sh", message)
    c.check("15: the sender reads the history: both lists, and the recipient opened it", r.returncode == 0 and "download:" in r.stdout and "firstAccess:" in r.stdout and RECIPIENT in r.stdout, (r.returncode, r.stdout[-500:]))
    r = run(RECIPIENT, "14.mailbox_search_GET.sh", "Hello")
    c.check("14: the search ends in a clear answer (the lab finds nothing: not confirmed)", r.returncode == 0 and "messages found" in r.stdout, (r.returncode, r.stdout[-300:]))
    r = run(SENDER, "16.mailbox_attachments_POST.sh", message, os.path.join(FOLDER, "01.mailbox_myself_GET.sh"))
    c.check("16: the attachment ends in a clear answer (the lab answers 422: not confirmed)", r.returncode in (0, 1) and ("was attached" in r.stdout or "Could not attach the file" in r.stdout), (r.returncode, r.stdout[-300:]))

    # -- folders ----------------------------------------------------------------------------------------------
    r = run(RECIPIENT, "11.mailbox_messages_id_folder_PUT.sh", message, "Archive")
    c.check("11: the message is moved to Archive (204)", r.returncode == 0 and "is in Archive now (HTTP 204)." in r.stdout, (r.returncode, r.stdout[-300:]))
    c.check("04: Archive lists it, and the Inbox does not",
            message in ids(run(RECIPIENT, "04.mailbox_folders_name_GET.sh", "Archive").stdout) and message not in ids(run(RECIPIENT, "04.mailbox_folders_name_GET.sh").stdout))
    r = run(RECIPIENT, "13.mailbox_folders_name_DELETE.sh", "Archive")
    c.check("13: a folder that is not empty is refused", r.returncode == 1 and "because it is not empty" in r.stdout, (r.returncode, r.stdout[-300:]))
    r = run(RECIPIENT, "12.mailbox_messages_id_DELETE.sh", message)
    c.check("12: the message is deleted (200)", r.returncode == 0 and "HTTP 200: Deletion was successful" in r.stdout, (r.returncode, r.stdout[-300:]))
    r = run(RECIPIENT, "13.mailbox_folders_name_DELETE.sh", "Archive")
    c.check("13: the empty folder is deleted (200)", r.returncode == 0 and "HTTP 200: Deletion was successful" in r.stdout, (r.returncode, r.stdout[-300:]))
    r = run(RECIPIENT, "11.mailbox_messages_id_folder_PUT.sh", message, "Nowhere")
    c.check("11: a message that is gone cannot be moved: exit 1 with the reason", r.returncode == 1 and "Could not move the message" in r.stdout, (r.returncode, r.stdout[-300:]))
finally:
    for name in made:
        try:
            purge(name)
        except Exception as e:  # the purge is best effort: the account is removed below all the same
            c.info("could not purge the mailbox of %s: %s" % (name, e))
    for name in made:
        admin.delete("accounts/" + name)
    c.check("no user named example_mbx_* is left on the server", not [n for n in (SENDER, RECIPIENT) if admin.exists("accounts/" + n)])
    for path in settings.values():
        if os.path.exists(path):
            os.remove(path)
    admin.logout()

sys.exit(c.done())
