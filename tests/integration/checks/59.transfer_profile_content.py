#!/usr/bin/env python3
"""
WRITES TO THE SERVER. What a transfer profile does to the CONTENT of a file, on real PeSIT
pulls over the lab's own PeSIT server, one pull per case. The profile is the one the
35.TransferProfiles examples create; check 58 runs those examples, this check uses the profiles'
settings.

Two PeSIT accounts per worker (a sender and a receiver, each with a PeSIT site named after the
other, the sender's default profile naming the file, the receiver's profile named in the pull).
For every case four stages are looked at:

  generated  the file as uploaded to the sender through the EndUser API (read back, byte for byte)
  sent       the bytes the sender put on the wire, captured by a CapturingProxy
             (tests/integration/lib/dummy_servers.py) that the RECEIVER's site points at and that
             forwards to ST's own PeSIT port. tests/integration/lib/pesit_wire.py reads the DTF
             data and the announced data coding (PI 16) from the capture
  received   the same bytes: in a pull, what the sender sends is what the receiver receives, and
             the one capture sits on that link. The receiver's own conversion happens AFTER it,
             so it can only be seen in the stored file. (A pull has no other link to watch.)
  stored     the final file in the receiver's home folder, downloaded through the EndUser API and
             compared with the bytes the test expects (written out in the case, not computed from
             the server). The sender's own file is read again after the pull: it must be untouched

Each case asserts either the change a setting promises (or what the lab does instead: then it is a
finding, named so) or NO change at all (bytes identical). Two levels: CORE cases use
advancedSettings (callerTranscoding is the sender's "sending" side, receiverTranscoding the
receiver's), ADDITIONAL cases use the plain transferMode / recordFormat / recordLength /
paddingStripEnabled fields, with advancedSettings off.

Every check is named "<file type>: <setting> -> <the change, or: unchanged>" and prefixed with
the side it tests (sender / receiver) and the level.

Each case is one pull, so each adds ONE transfer log entry on the receiver and one on the sender's
side of the same transfer; entries cannot be removed. A run adds about one hundred. A failure that
is expected (a record too long) is also an entry. Cases run on three workers at once, each with
its own accounts and proxy. Names and user ids are new on every run; the connection is cut after
every pull because a PeSIT connection that is kept open carries the previous transfer's record
format with it (a changed profile then gives a different answer on a connection that was reused).

Needs --write, st_allow_writes="yes" and st_callback_host (this machine as the server sees it:
the capture needs the server to connect here). Without st_callback_host the cases still run, the
receiver's site points at the server's PeSIT port and the "sent" stage is not checked.

Not covered, and why:
  - receiverMessage.receiverMessageDirectory: it is about PeSIT MESSAGES (a message FPDU), not files
  - sendingAcknowledgmentEnabled: an acknowledgment, not content (check 32 shows acknowledgments)
  - multiSelect: a sendMapping with a wildcard did not find a file over PeSIT on this lab (the pull failed), so
    there is no second file to compare
  - custom_table: needs a server configuration option PeSIT.Custom.Transcoding.Registry.<name> holding a table;
    creating one changes the server's configuration, so only the refusal is checked. ascii_custom_table and
    ebcdic_custom_table (an inline table) are accepted but the transfer fails: asserted as it is
  - the stages "sent" and "received" are one capture (see above); a push would be the same link

Progress notes for whoever resumes: the decoder (pesit_wire.py), CapturingProxy and their offline tests are done; the cases
below are expectations written from what the lab did, and all pass; a case that starts to fail is a finding to look at, not
a number to adjust (read st-api-gotchas, "What a transfer profile does to the bytes of a file").
"""
import base64
import concurrent.futures
import os
import random
import sys
import threading
import time
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import dummy_servers  # noqa: E402
import pesit_wire  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the transfer profile content check for real")

c = st_client.Checker("Transfer profiles at work: the content of a file, sent, received and stored")

N = random.randint(1000, 9999)
WORKERS = 3
UID = str(40000 + N)
PASSWORD = harness.new_password()
HOST = config["st_server"]
PESIT_HOST = config.get("st_pesit_host") or HOST
ENDUSER_PORT = harness.ports(config).enduser
CALLBACK = config.get("st_callback_host", "")
PESIT_SITE_DEFAULTS = {"dmz": "none", "pesitId": "", "ptcpConnections": 1, "socketSendReceiveBuffersize": 65536,
                       "receiveMessage": "", "sendMessage": "", "useServerPasswordExpr": False,
                       "usePartnerPasswordExpr": False, "usePreconnectionServerPasswordExpr": False,
                       "usePreconnectionPartnerPasswordExpr": False}

# --------------------------------------------------------------------------------------------
# helpers for the expectations
# --------------------------------------------------------------------------------------------
rec = lambda *items: pesit_wire.frame_records(list(items))  # noqa: E731  records as the wire carries them
E037 = lambda text: text.encode("cp037")  # noqa: E731


def e1047(text):
    """IBM1047 from IBM037: they differ in a few punctuation marks and in which byte is the line feed."""
    swap = {"[": 0xAD, "]": 0xBD, "^": 0x5F, "¬": 0xB0, "\n": 0x15}
    return b"".join(bytes([swap[ch]]) if ch in swap else ch.encode("cp037") for ch in text)


ASCII_, EBCDIC_, BINARY_ = b"\x00", b"\x01", b"\x02"   # PI 16, the data coding the sender announces
RECORD_TOO_LONG = "Record length too long"
WRONG_RECORD = "Incorrect record length"

FILES = {   # key: (what to call it in a check's name, bytes)
    "lf": ("text LF", b"alpha\nbeta\ngamma\n"),
    "crlf": ("text CRLF", b"alpha\r\nbeta\r\ngamma\r\n"),
    "nofinal": ("text, no final newline", b"alpha\nbeta\ngamma"),
    "mixed": ("text with both LF and CRLF", b"alpha\nbeta\r\ngamma\n"),
    "blank": ("text with a blank line", b"a\n\nb\n"),
    "utf8": ("UTF-8 text with non-ASCII", "café € naïve\n".encode("utf-8")),
    "latin1": ("Latin-1 text", "café naïve\n".encode("latin-1")),
    "sym": ("ASCII text with [ ] ^ |", b"alpha [x] ^y |z\n"),
    "ebc037": ("EBCDIC text (IBM037, LF 0x25)", E037("alpha [x] ^y |z\n")),
    "e15": ("EBCDIC records (NL 0x15)", E037("alpha") + b"\x15" + E037("beta") + b"\x15"),
    "e15short": ("EBCDIC records, short (NL 0x15)", E037("alpha") + b"\x15" + E037("be") + b"\x15"),
    "e25": ("EBCDIC records (LF 0x25)", E037("alpha") + b"\x25" + E037("beta") + b"\x25"),
    "fixed": ("fixed-length records, exact, no newline", b"AAAAAAAAAABBBBBBBBBBCCCCCCCCCC"),
    "ragged": ("fixed-length records, ragged, no newline", b"AAAAAAAAAABBBBBBBBBBCCCC"),
    "var": ("variable-length records", b"one\ntwenty characters long\nx\n"),
    "long25": ("a 25 character line then a short one", b"A" * 25 + b"\nshort\n"),
    "bin": ("binary, all 256 byte values", bytes(range(256))),
    "empty": ("empty file", b""),
    "huge": ("one huge line (3000 bytes)", b"x" * 3000 + b"\n"),
    "huge_nonl": ("one huge line (3000 bytes), no newline", b"x" * 3000),
}


def adv(caller=None, receiver=None, **basic):
    settings = {"enabled": True, "callerTranscoding": caller or {"type": "binary"}, "receiverTranscoding": receiver or {"type": "binary"}}
    return dict(basic, advancedSettings=settings)


def plain(mode, fmt="Variable", length=2048, strip=False):
    return {"transferMode": mode, "recordFormat": fmt, "recordLength": length, "paddingStripEnabled": strip,
            "advancedSettings": {"enabled": False}}


RB = adv()                                   # binary both ways: the neutral receiver / sender
SB = adv()
SA = adv({"type": "ascii"})                  # ascii sender: records
DOT = "\\u002E"                              # a padding character: the literal text .


class Case:
    def __init__(self, level, side, file, setting, sender, receiver, sent=None, stored=None, fail=None, net=None,
                 sent_text="unchanged", stored_text="unchanged", note=""):
        self.level, self.side, self.file, self.setting = level, side, file, setting
        self.sender, self.receiver = sender, receiver
        self.sent, self.stored, self.fail, self.net = sent, stored, fail, net
        self.sent_text, self.stored_text, self.note = sent_text, stored_text, note
        self.result = None

    def name(self):
        return "%s/%s: %s: %s" % (self.level, self.side, FILES[self.file][0], self.setting)


CASES = []


def case(level, side, file, setting, sender, receiver, **kw):
    # a case's data: the file's bytes, and expectations that may be callables of the file
    CASES.append(Case(level, side, file, setting, sender, receiver, **kw))


def same(file):
    return FILES[file][1]


# --------------------------------------------------------------------------------------------
# CORE (advancedSettings) -- sender: callerTranscoding
# --------------------------------------------------------------------------------------------
CORE = "core"
for key in ("lf", "crlf", "nofinal", "mixed", "utf8", "latin1", "ebc037", "fixed", "ragged", "bin", "empty"):
    case(CORE, "sender", key, "callerTranscoding=binary + receiverTranscoding=binary", SB, RB, sent=same(key), stored=same(key), net=BINARY_,
         sent_text="unchanged (a stream, announced as binary)", stored_text="unchanged")

case(CORE, "sender", "huge_nonl", "callerTranscoding=binary + receiverTranscoding=binary (outputRecordLength 2048)", SB, RB,
     sent=rec(b"x" * 2048, b"x" * 952), stored=same("huge_nonl"), net=BINARY_,
     sent_text="cut into records of the record length, 2048 and 952 bytes (a stream longer than the record length is sent as records)",
     stored_text="unchanged: the records are joined again, nothing added")
ASCII_JOINED = {"lf": (b"alpha", b"beta", b"gamma"), "crlf": (b"alpha", b"beta", b"gamma"), "nofinal": (b"alpha", b"beta", b"gamma"),
                "mixed": (b"alpha", b"beta", b"gamma")}
for key, items in ASCII_JOINED.items():
    case(CORE, "sender", key, "callerTranscoding=ascii", SA, RB, sent=rec(*items), stored=b"".join(items), net=ASCII_,
         sent_text="one record per line, the line ends (LF, CRLF) removed", stored_text="records joined, no line ends (a binary receiver adds none)")
case(CORE, "sender", "blank", "callerTranscoding=ascii", SA, RB, sent=rec(b"a", b"", b"b"), stored=b"ab", net=ASCII_,
     sent_text="a blank line is an empty record", stored_text="records joined")
for key in ("utf8", "latin1"):
    body = same(key)[:-1]
    case(CORE, "sender", key, "callerTranscoding=ascii", SA, RB, sent=body, stored=body, net=ASCII_,
         sent_text="no conversion of the characters; the one line is sent as it is, without its LF (and without a record length)",
         stored_text="the same bytes")
case(CORE, "sender", "ebc037", "callerTranscoding=ascii", SA, RB, sent=same("ebc037"), stored=same("ebc037"), net=ASCII_,
     sent_text="unchanged: EBCDIC bytes have no LF to split on, and are not converted", stored_text="unchanged")
case(CORE, "sender", "fixed", "callerTranscoding=ascii", SA, RB, sent=same("fixed"), stored=same("fixed"), net=ASCII_,
     sent_text="unchanged: no newline, one record", stored_text="unchanged")
split = bytes(range(256))
case(CORE, "sender", "bin", "callerTranscoding=ascii", SA, RB, sent=rec(split[:10], split[11:]), stored=split[:10] + split[11:], net=ASCII_,
     sent_text="cut at the one LF (byte 10), which is dropped; the other bytes, a lone CR included, kept",
     stored_text="all bytes but the LF")
case(CORE, "sender", "empty", "callerTranscoding=ascii", SA, RB, sent=b"", stored=b"", net=ASCII_, sent_text="nothing sent", stored_text="an empty file")
case(CORE, "sender", "huge", "callerTranscoding=ascii (outputRecordLength 2048)", SA, RB, fail=RECORD_TOO_LONG, net=ASCII_,
     sent_text="the record is longer than the record length: the receiver refuses it, the transfer fails and nothing is stored")
case(CORE, "sender", "huge_nonl", "callerTranscoding=ascii (outputRecordLength 2048)", SA, RB, fail=RECORD_TOO_LONG, net=ASCII_,
     sent_text="the record is longer than the record length: the transfer fails and nothing is stored")

FIXED10 = {"type": "ascii", "outputRecordFormat": "FIXED", "outputRecordLength": 10}
case(CORE, "sender", "lf", "callerTranscoding=ascii, outputRecordFormat=FIXED, outputRecordLength=10", adv(FIXED10), RB,
     sent=rec(b"alpha     ", b"beta      ", b"gamma     "), stored=b"alpha     beta      gamma     ", net=ASCII_,
     sent_text="every record padded with spaces to 10", stored_text="the padded records joined")
case(CORE, "sender", "long25", "callerTranscoding=ascii, outputRecordFormat=FIXED, outputRecordLength=10", adv(FIXED10), RB,
     fail=RECORD_TOO_LONG, net=ASCII_,
     sent_text="a 25 character line is longer than the fixed record length 10: not cut, the receiver refuses it and the transfer fails")
case(CORE, "sender", "lf", "callerTranscoding=ascii, FIXED 10, paddingCharacter=\\u002E", adv(dict(FIXED10, paddingCharacter=DOT)), RB,
     sent=rec(b"alpha.....", b"beta......", b"gamma....."), stored=b"alpha.....beta......gamma.....", net=ASCII_,
     sent_text="padded with dots", stored_text="the padded records joined")
case(CORE, "sender", "empty", "callerTranscoding=ascii, FIXED 10", adv(FIXED10), RB, sent=b"", stored=b"", net=ASCII_,
     sent_text="no records, nothing to pad", stored_text="an empty file")
case(CORE, "sender", "lf", "callerTranscoding=ascii, paddingCharacter=\\u002E with VARIABLE records", adv({"type": "ascii", "paddingCharacter": DOT}), RB,
     sent=rec(b"alpha", b"beta", b"gamma"), stored=b"alphabetagamma", net=ASCII_,
     sent_text="unchanged from the default: variable records are not padded", stored_text="records joined")
case(CORE, "sender", "lf", "callerTranscoding=ascii, outputRecordLength=5 (every line fits)", adv({"type": "ascii", "outputRecordLength": 5}), RB,
     sent=rec(b"alpha", b"beta", b"gamma"), stored=b"alphabetagamma", net=ASCII_,
     sent_text="unchanged: no line is longer than 5", stored_text="records joined")
case(CORE, "sender", "long25", "callerTranscoding=ascii, outputRecordLength=10 (VARIABLE)", adv({"type": "ascii", "outputRecordLength": 10}), RB,
     fail=RECORD_TOO_LONG, net=ASCII_, sent_text="a 25 character line is longer than 10: the transfer fails and nothing is stored")
case(CORE, "sender", "lf", "callerTranscoding=binary, outputRecordFormat=FIXED, outputRecordLength=10 (read only on binary)",
     adv({"type": "binary", "outputRecordFormat": "FIXED", "outputRecordLength": 10}), RB, sent=same("lf"), stored=same("lf"), net=BINARY_,
     sent_text="unchanged: a binary sender ignores them", stored_text="unchanged")

# ascii_predefined: the characters are converted from sourceEncodingScheme to outputEncodingScheme
def predef(net, src, out, **more):
    return adv(dict({"type": "ascii_predefined", "networkDataCode": net, "sourceEncodingScheme": src, "outputEncodingScheme": out}, **more))


case(CORE, "sender", "utf8", "callerTranscoding=ascii_predefined, UTF-8 -> ISO-8859-1", predef("ASCII", "UTF-8", "ISO-8859-1"), RB,
     sent=b"caf\xe9 ? na\xefve", stored=b"caf\xe9 ? na\xefve", net=ASCII_,
     sent_text="converted to Latin-1; the euro sign, which Latin-1 lacks, becomes ?", stored_text="the converted bytes")
case(CORE, "sender", "latin1", "callerTranscoding=ascii_predefined, ISO-8859-1 -> UTF-8", predef("ASCII", "ISO-8859-1", "UTF-8"), RB,
     sent="café naïve".encode("utf-8"), stored="café naïve".encode("utf-8"), net=ASCII_,
     sent_text="converted to UTF-8", stored_text="the converted bytes")
case(CORE, "sender", "utf8", "callerTranscoding=ascii_predefined, UTF-8 -> UTF-8 (the default)", adv({"type": "ascii_predefined"}), RB,
     sent=same("utf8")[:-1], stored=same("utf8")[:-1], net=ASCII_,
     sent_text="characters unchanged (the line's LF is removed)", stored_text="the same bytes")
case(CORE, "sender", "lf", "callerTranscoding=ascii_predefined, UTF-8 -> ISO-8859-1", predef("ASCII", "UTF-8", "ISO-8859-1"), RB,
     sent=rec(b"alpha", b"beta", b"gamma"), stored=b"alphabetagamma", net=ASCII_,
     sent_text="plain ASCII is the same in both: records as with ascii", stored_text="records joined")
case(CORE, "sender", "sym", "callerTranscoding=ascii_predefined, networkDataCode=EBCDIC, UTF-8 -> IBM037", predef("EBCDIC", "UTF-8", "IBM037"), RB,
     sent=E037("alpha [x] ^y |z"), stored=E037("alpha [x] ^y |z"), net=EBCDIC_,
     sent_text="converted to IBM037 and announced as EBCDIC", stored_text="the converted bytes")
case(CORE, "sender", "sym", "callerTranscoding=ascii_predefined, networkDataCode=EBCDIC, UTF-8 -> IBM1047", predef("EBCDIC", "UTF-8", "IBM1047"), RB,
     sent=e1047("alpha [x] ^y |z"), stored=e1047("alpha [x] ^y |z"), net=EBCDIC_,
     sent_text="converted to IBM1047 ([ ] and ^ are other bytes than in IBM037)", stored_text="the converted bytes")
case(CORE, "sender", "lf", "callerTranscoding=ascii_predefined, networkDataCode=EBCDIC, UTF-8 -> IBM037", predef("EBCDIC", "UTF-8", "IBM037"), RB,
     sent=rec(E037("alpha"), E037("beta"), E037("gamma")), stored=E037("alphabetagamma"), net=EBCDIC_,
     sent_text="records, converted to IBM037", stored_text="records joined")
case(CORE, "sender", "utf8", "callerTranscoding=ascii_predefined, networkDataCode=EBCDIC, UTF-8 -> IBM037", predef("EBCDIC", "UTF-8", "IBM037"), RB,
     sent=E037("café") + b"\x40\x3f\x40" + E037("naïve"), stored=E037("café") + b"\x40\x3f\x40" + E037("naïve"), net=EBCDIC_,
     sent_text="converted; the euro sign, which IBM037 lacks, becomes the substitute byte 0x3F", stored_text="the converted bytes")

# ebcdic: local EBCDIC, no conversion, records end at 0x15
EB = adv({"type": "ebcdic"})
case(CORE, "sender", "ebc037", "callerTranscoding=ebcdic", EB, RB, sent=same("ebc037"), stored=same("ebc037"), net=EBCDIC_,
     sent_text="unchanged, announced as EBCDIC (0x25 is not the record end here)", stored_text="unchanged")
case(CORE, "sender", "lf", "callerTranscoding=ebcdic", EB, RB, sent=same("lf"), stored=same("lf"), net=EBCDIC_,
     sent_text="unchanged: no conversion, and LF is not an EBCDIC line end", stored_text="unchanged")
case(CORE, "sender", "e15", "callerTranscoding=ebcdic", EB, RB, sent=rec(E037("alpha"), E037("beta")), stored=E037("alphabeta"), net=EBCDIC_,
     sent_text="one record per 0x15, the 0x15 removed", stored_text="records joined")
case(CORE, "sender", "bin", "callerTranscoding=ebcdic", EB, RB, sent=rec(split[:21], split[22:]), stored=split[:21] + split[22:], net=EBCDIC_,
     sent_text="cut at 0x15 (byte 21), which is dropped; 0x0A and 0x25 are kept", stored_text="all bytes but 0x15")
case(CORE, "sender", "e15short", "callerTranscoding=ebcdic, FIXED 10", adv({"type": "ebcdic", "outputRecordFormat": "FIXED", "outputRecordLength": 10}), RB,
     sent=rec(E037("alpha") + b"\x7c" * 5, E037("be") + b"\x7c" * 8), stored=E037("alpha") + b"\x7c" * 5 + E037("be") + b"\x7c" * 8, net=EBCDIC_,
     sent_text="padded to 10 with byte 0x7C, the EBCDIC for @, the default paddingCharacter U+0040 (not the EBCDIC space 0x40)", stored_text="the padded records joined")
case(CORE, "sender", "e15short", "callerTranscoding=ebcdic, FIXED 10, paddingCharacter=\\u0040", adv({"type": "ebcdic", "outputRecordFormat": "FIXED", "outputRecordLength": 10, "paddingCharacter": "\\u0040"}), RB,
     sent=rec(E037("alpha") + b"\x7c" * 5, E037("be") + b"\x7c" * 8), stored=E037("alpha") + b"\x7c" * 5 + E037("be") + b"\x7c" * 8, net=EBCDIC_,
     sent_text="padded with 0x7C: the padding character is converted from Unicode to EBCDIC", stored_text="the padded records joined")
case(CORE, "sender", "empty", "callerTranscoding=ebcdic", EB, RB, sent=b"", stored=b"", net=EBCDIC_, sent_text="nothing sent", stored_text="an empty file")

# ebcdic_predefined
def epre(net, src, out):
    return adv({"type": "ebcdic_predefined", "networkDataCode": net, "sourceEncodingScheme": src, "outputEncodingScheme": out})


case(CORE, "sender", "ebc037", "callerTranscoding=ebcdic_predefined, IBM037 -> IBM1047, network EBCDIC", epre("EBCDIC", "IBM037", "IBM1047"), RB,
     sent=e1047("alpha [x] ^y |z\n"), stored=e1047("alpha [x] ^y |z\n"), net=EBCDIC_,
     sent_text="converted to IBM1047; the IBM037 line feed 0x25 becomes 0x15, and is not a record end", stored_text="the converted bytes")
case(CORE, "sender", "e15", "callerTranscoding=ebcdic_predefined, IBM1047 -> IBM037, network EBCDIC", epre("EBCDIC", "IBM1047", "IBM037"), RB,
     sent=rec(E037("alpha"), E037("beta")), stored=E037("alphabeta"), net=EBCDIC_,
     sent_text="records split at 0x15; letters are the same in both", stored_text="records joined")
case(CORE, "sender", "e15", "callerTranscoding=ebcdic_predefined, IBM1047 -> UTF-8, networkDataCode=ASCII", epre("ASCII", "IBM1047", "UTF-8"), RB,
     sent=rec(b"alpha", b"beta"), stored=b"alphabeta", net=ASCII_,
     sent_text="records split at 0x15 and converted to ASCII, announced as ASCII", stored_text="records joined")

# custom translation tables: accepted when the profile is made, but a transfer cannot open the file
TABLE = bytearray(range(256))
TABLE[0x61], TABLE[0x62] = 0x41, 0x58   # a -> A, b -> X
TABLE64 = base64.b64encode(bytes(TABLE)).decode()
for kind, net in (("ascii_custom_table", "ASCII"), ("ebcdic_custom_table", "EBCDIC")):
    case(CORE, "sender", "lf", "callerTranscoding=%s with a translationTable of 256 bytes (a -> A, b -> X), networkDataCode=%s" % (kind, net),
         adv({"type": kind, "networkDataCode": net, "translationTable": TABLE64, "translationCustomTableFileName": "example_table_%d" % N}), RB,
         fail="Failure in opening file", sent_text="the profile is accepted, but the sender cannot open the file: the transfer fails and nothing is stored (a finding)")

# --------------------------------------------------------------------------------------------
# CORE -- receiver: receiverTranscoding.  The sender is ascii (records) or binary (a stream).
# --------------------------------------------------------------------------------------------
def rx(**kw):
    return adv(None, kw)


RA = rx(type="ascii")
for key, stored, text in (("lf", b"alpha\nbeta\ngamma\n", "each record ends with LF"),
                          ("nofinal", b"alpha\nbeta\ngamma\n", "a final LF is added"),
                          ("blank", b"a\n\nb\n", "each record ends with LF, the empty one too"),
                          ("empty", b"", "no record, nothing added")):
    case(CORE, "receiver", key, "receiverTranscoding=ascii (sender: ascii)", SA, RA, sent=None, stored=stored, stored_text=text)
case(CORE, "receiver", "utf8", "receiverTranscoding=ascii (sender: ascii)", SA, RA, stored=same("utf8"),
     stored_text="unchanged: no conversion, the LF the sender removed is put back")
case(CORE, "receiver", "latin1", "receiverTranscoding=ascii (sender: ascii)", SA, RA, stored=same("latin1"),
     stored_text="unchanged: no conversion, the LF the sender removed is put back")
for key, stored, text in (("lf", b"alpha\nbeta\ngamma\n\n", "the file's own LF kept and ANOTHER LF added at the end"),
                          ("crlf", b"alpha\r\nbeta\r\ngamma\r\n\n", "the file kept as it is and one LF added at the end"),
                          ("nofinal", b"alpha\nbeta\ngamma\n", "one LF added at the end"),
                          ("utf8", same("utf8") + b"\n", "unchanged and one LF added at the end"),
                          ("bin", bytes(range(256)) + b"\n", "all 256 bytes kept and one LF added at the end"),
                          ("empty", b"", "nothing added to an empty file")):
    case(CORE, "receiver", key, "receiverTranscoding=ascii (sender: binary, a stream)", SB, RA, stored=stored, stored_text=text)

# line endings
for key, ending, fmt, stored, text in (
        ("lf", "WINDOWS", "ascii", b"alpha\r\nbeta\r\ngamma\r\n", "every record ends with CRLF"),
        ("nofinal", "WINDOWS", "ascii", b"alpha\r\nbeta\r\ngamma\r\n", "every record ends with CRLF, the last one too"),
        ("lf", "UNIX", "ascii", b"alpha\nbeta\ngamma\n", "unchanged: LF"),
        ("lf", "DEFAULT", "ascii", b"alpha\nbeta\ngamma\n", "unchanged: LF (the server runs on Linux)"),
        ("lf", "WINDOWS", "predefined", b"alpha\r\nbeta\r\ngamma\r\n", "every record ends with CRLF"),
        ("empty", "WINDOWS", "ascii", b"", "nothing added to an empty file")):
    case(CORE, "receiver", key, "receiverTranscoding=%s, lineEndingFormat=%s (sender: ascii)" % (fmt, ending), SA, rx(type=fmt, lineEndingFormat=ending),
         stored=stored, stored_text=text)
case(CORE, "receiver", "lf", "receiverTranscoding=ascii, lineEndingFormat=WINDOWS (sender: binary, a stream)", SB, rx(type="ascii", lineEndingFormat="WINDOWS"),
     stored=b"alpha\nbeta\ngamma\n\r\n", stored_text="the file's LFs kept, and CRLF added at the end (a stream is not converted)")
case(CORE, "receiver", "crlf", "receiverTranscoding=ascii, lineEndingFormat=WINDOWS (sender: binary, a stream)", SB, rx(type="ascii", lineEndingFormat="WINDOWS"),
     stored=b"alpha\r\nbeta\r\ngamma\r\n\r\n", stored_text="the file kept and CRLF added at the end")

# record format
F10 = rx(type="ascii", outputRecordFormat="FIXED", outputRecordLength=10)
case(CORE, "receiver", "lf", "receiverTranscoding=ascii, outputRecordFormat=FIXED, outputRecordLength=10 (sender: ascii)", SA, F10,
     stored=b"alpha     \nbeta      \ngamma     \n", stored_text="each record padded with spaces to 10, then LF")
case(CORE, "receiver", "long25", "receiverTranscoding=ascii, outputRecordFormat=FIXED, outputRecordLength=10 (sender: ascii)", SA, F10,
     stored=b"A" * 10 + b"\nshort     \n", stored_text="the 25 character record cut to 10, the short one padded")
case(CORE, "receiver", "lf", "receiverTranscoding=ascii, FIXED 10, paddingCharacter=\\u002E (sender: ascii)", SA, rx(type="ascii", outputRecordFormat="FIXED", outputRecordLength=10, paddingCharacter=DOT),
     stored=b"alpha.....\nbeta......\ngamma.....\n", stored_text="padded with dots")
case(CORE, "receiver", "lf", "receiverTranscoding=ascii, outputRecordLength=5 (every record fits) (sender: ascii)", SA, rx(type="ascii", outputRecordLength=5),
     stored=same("lf"), stored_text="unchanged")
case(CORE, "receiver", "lf", "receiverTranscoding=ascii, paddingCharacter=\\u002E with VARIABLE records (sender: ascii)", SA, rx(type="ascii", paddingCharacter=DOT),
     stored=same("lf"), stored_text="unchanged: variable records are not padded")
case(CORE, "receiver", "lf", "receiverTranscoding=predefined, FIXED 10, paddingCharacter=\\u002E (sender: ascii)", SA,
     rx(type="predefined", outputRecordFormat="FIXED", outputRecordLength=10, paddingCharacter=DOT),
     stored=b"alpha.....\nbeta......\ngamma.....\n", stored_text="padded with dots")

# ebcdic receiver
rows = [("lf", "receiverTranscoding=ebcdic (sender: ascii)", SA, rx(type="ebcdic"), e1047("alpha\nbeta\ngamma\n"), "converted from ASCII to EBCDIC, each record ends with 0x15"),
        ("empty", "receiverTranscoding=ebcdic (sender: ascii)", SA, rx(type="ebcdic"), b"", "an empty file"),
        ("lf", "receiverTranscoding=ebcdic (sender: binary, a stream)", SB, rx(type="ebcdic"), same("lf") + b"\x15", "NOT converted (the data is announced as binary), and 0x15 added"),
        ("lf", "receiverTranscoding=ebcdic, lineEndingFormat=WINDOWS (sender: ascii)", SA, rx(type="ebcdic", lineEndingFormat="WINDOWS"),
         b"".join(E037(w) + b"\x0d\x15" for w in ("alpha", "beta", "gamma")), "converted, each record ends with 0x0D 0x15"),
        ("lf", "receiverTranscoding=ebcdic, lineEndingFormat=UNIX (sender: ascii)", SA, rx(type="ebcdic", lineEndingFormat="UNIX"),
         e1047("alpha\nbeta\ngamma\n"), "converted, each record ends with 0x15"),
        ("sym", "receiverTranscoding=ebcdic (sender: ascii)", SA, rx(type="ebcdic"), e1047("alpha [x] ^y ") + b"\x6a" + e1047("z\n"),
         "converted like IBM1047 except that | becomes 0x6A (IBM1047 has 0x4F): a finding"),
        ("lf", "receiverTranscoding=ebcdic (sender: ascii_predefined IBM1047, network EBCDIC)",
         predef("EBCDIC", "UTF-8", "IBM1047"), rx(type="ebcdic"), e1047("alpha\nbeta\ngamma\n"), "not converted again (the data is already EBCDIC), each record ends with 0x15")]
for key, setting, snd, rcv, stored, text in rows:
    case(CORE, "receiver", key, setting, snd, rcv, stored=stored, stored_text=text)
case(CORE, "receiver", "lf", "receiverTranscoding=ebcdic, FIXED 10 (sender: ascii)", SA, rx(type="ebcdic", outputRecordFormat="FIXED", outputRecordLength=10),
     stored=b"".join(E037(w) + b"\x7c" * (10 - len(w)) + b"\x15" for w in ("alpha", "beta", "gamma")),
     stored_text="converted, padded to 10 with 0x7C, the EBCDIC for the default padding character @ (not the EBCDIC space), then 0x15")

# ascii receiver of EBCDIC data
case(CORE, "receiver", "lf", "receiverTranscoding=ascii (sender: ascii_predefined IBM037, network EBCDIC)", predef("EBCDIC", "UTF-8", "IBM037"), RA,
     stored=same("lf"), stored_text="converted back from EBCDIC to ASCII, each record ends with LF")
case(CORE, "receiver", "sym", "receiverTranscoding=ascii (sender: ascii_predefined IBM1047, network EBCDIC)", predef("EBCDIC", "UTF-8", "IBM1047"), RA,
     stored="alpha [x] ^y Ëz\n".encode("utf-8"), stored_text="converted back; | (0x4F in IBM1047) comes out as the letter E with a diaeresis: a finding")

# predefined receiver
def rpre(src, out, **more):
    return rx(**dict({"type": "predefined", "sourceEncodingScheme": src, "outputEncodingScheme": out}, **more))


case(CORE, "receiver", "utf8", "receiverTranscoding=predefined, UTF-8 -> ISO-8859-1 (sender: binary, a stream)", SB, rpre("UTF-8", "ISO-8859-1"),
     stored=b"caf\xe9 ? na\xefve\n\n", stored_text="converted to Latin-1 (the euro sign becomes ?), and one more LF added at the end")
case(CORE, "receiver", "utf8", "receiverTranscoding=predefined, UTF-8 -> ISO-8859-1 (sender: ascii)", SA, rpre("UTF-8", "ISO-8859-1"),
     stored=b"caf\xe9 ? na\xefve\n", stored_text="converted to Latin-1 (the euro sign becomes ?), LF added")
case(CORE, "receiver", "latin1", "receiverTranscoding=predefined, ISO-8859-1 -> UTF-8 (sender: binary, a stream)", SB, rpre("ISO-8859-1", "UTF-8"),
     stored="café naïve\n\n".encode("utf-8"), stored_text="converted to UTF-8, and one more LF added at the end")
case(CORE, "receiver", "sym", "receiverTranscoding=predefined, UTF-8 -> IBM1047 (sender: binary, a stream)", SB, rpre("UTF-8", "IBM1047"),
     stored=e1047("alpha [x] ^y |z\n") + b"\x15", stored_text="converted to IBM1047 (| is 0x4F here), and 0x15 added")
case(CORE, "receiver", "ebc037", "receiverTranscoding=predefined, IBM037 -> UTF-8 (sender: binary, a stream)", SB, rpre("IBM037", "UTF-8"),
     stored=b"alpha [x] ^y |z\n\n", stored_text="converted to UTF-8, and one more LF added at the end")
case(CORE, "receiver", "lf", "receiverTranscoding=predefined, UTF-8 -> UTF-8 (the default) (sender: ascii)", SA, adv(None, {"type": "predefined"}),
     stored=same("lf"), stored_text="unchanged")
case(CORE, "receiver", "utf8", "receiverTranscoding=predefined, UTF-8 -> UTF-8 (the default) (sender: ascii)", SA, adv(None, {"type": "predefined"}),
     stored=same("utf8"), stored_text="unchanged")

# binary receiver of records
case(CORE, "receiver", "lf", "receiverTranscoding=binary (sender: ascii)", SA, RB, stored=b"alphabetagamma", stored_text="records joined, no line ends added")

# the two switches
case(CORE, "receiver", "lf", "advancedSettings.enabled=false with ascii transcoding inside, transferMode=BINARY",
     {"transferMode": "BINARY", "advancedSettings": {"enabled": False, "callerTranscoding": {"type": "ascii"}, "receiverTranscoding": {"type": "binary"}}},
     {"transferMode": "BINARY", "advancedSettings": {"enabled": False, "receiverTranscoding": {"type": "ascii"}}},
     sent=same("lf"), stored=same("lf"), net=BINARY_, sent_text="unchanged: the advanced settings are off, transferMode BINARY is in force", stored_text="unchanged")
case(CORE, "receiver", "lf", "advancedSettings.enabled=true (binary) with transferMode=ASCII", adv(transferMode="ASCII"), adv(None, None, transferMode="ASCII"),
     sent=same("lf"), stored=same("lf"), net=BINARY_, sent_text="unchanged: the advanced settings win over transferMode", stored_text="unchanged")

# --------------------------------------------------------------------------------------------
# ADDITIONAL (the plain fields, advancedSettings off)
# --------------------------------------------------------------------------------------------
ADD = "additional"
BIN_ = plain("BINARY")
for key in ("lf", "bin"):
    case(ADD, "sender", key, "transferMode=BINARY, both sides", BIN_, BIN_, sent=same(key), stored=same(key), net=BINARY_,
         sent_text="unchanged", stored_text="unchanged")
case(ADD, "sender", "lf", "transferMode=ASCII", plain("ASCII"), BIN_, sent=rec(b"alpha", b"beta", b"gamma"), stored=b"alphabetagamma", net=ASCII_,
     sent_text="one record per line, line ends removed", stored_text="records joined")
case(ADD, "sender", "utf8", "transferMode=ASCII", plain("ASCII"), BIN_, sent=same("utf8")[:-1], stored=same("utf8")[:-1], net=ASCII_,
     sent_text="characters unchanged, the LF removed", stored_text="the same bytes")
case(ADD, "sender", "e15", "transferMode=EBCDIC", plain("EBCDIC"), BIN_, sent=rec(E037("alpha"), E037("beta")), stored=E037("alphabeta"), net=EBCDIC_,
     sent_text="records split at 0x15, announced as EBCDIC, no conversion", stored_text="records joined")
case(ADD, "sender", "e25", "transferMode=EBCDIC", plain("EBCDIC"), BIN_, sent=rec(E037("alpha"), E037("beta")), stored=E037("alphabeta"), net=EBCDIC_,
     sent_text="records split at 0x25 too (here it is a record end), no conversion", stored_text="records joined")
case(ADD, "sender", "e25", "transferMode=EBCDIC_NATIVE", plain("EBCDIC_NATIVE"), BIN_, sent=rec(E037("alpha"), E037("beta")), stored=E037("alphabeta"), net=EBCDIC_,
     sent_text="the same as EBCDIC", stored_text="records joined")
case(ADD, "sender", "lf", "transferMode=ASCII, recordFormat=Fixed, recordLength=10", plain("ASCII", "Fixed", 10), BIN_,
     sent=rec(b"alpha     ", b"beta      ", b"gamma     "), stored=b"alpha     beta      gamma     ", net=ASCII_,
     sent_text="every record padded with spaces to 10", stored_text="the padded records joined")
case(ADD, "sender", "e15short", "transferMode=EBCDIC, recordFormat=Fixed, recordLength=10", plain("EBCDIC", "Fixed", 10), BIN_,
     sent=rec(E037("alpha") + b"\x40" * 5, E037("be") + b"\x40" * 8), stored=E037("alpha") + b"\x40" * 5 + E037("be") + b"\x40" * 8, net=EBCDIC_,
     sent_text="padded with the EBCDIC space 0x40", stored_text="the padded records joined")
case(ADD, "sender", "lf", "transferMode=BINARY, recordFormat=Fixed, recordLength=10", plain("BINARY", "Fixed", 10), BIN_,
     sent=rec(b"alpha\nbeta", b"\ngamma\n\x00\x00\x00"), stored=same("lf") + b"\x00\x00\x00", net=BINARY_,
     sent_text="cut into records of 10 and the last one padded with NUL bytes to 10 (a finding: binary is not left alone here)",
     stored_text="the file with 3 NUL bytes added at the end")
PA = plain("ASCII")
case(ADD, "receiver", "lf", "transferMode=ASCII (sender: ascii)", SA, PA, stored=same("lf"), stored_text="each record ends with LF")
case(ADD, "receiver", "lf", "transferMode=EBCDIC (sender: ascii)", SA, plain("EBCDIC"), stored=same("lf"),
     stored_text="unchanged: not converted to EBCDIC, each record ends with LF")
case(ADD, "receiver", "lf", "transferMode=EBCDIC_NATIVE (sender: ascii)", SA, plain("EBCDIC_NATIVE"), stored=b"alpha%beta%gamma%",
     stored_text="not converted, but each record ends with 0x25, the EBCDIC LF")
case(ADD, "receiver", "lf", "transferMode=BINARY (sender: ascii)", SA, BIN_, stored=b"alphabetagamma", stored_text="records joined, no line ends")
case(ADD, "receiver", "lf", "transferMode=ASCII, recordFormat=Fixed, recordLength=10 (sender: ascii, variable records)", SA, plain("ASCII", "Fixed", 10),
     fail=WRONG_RECORD, stored_text="records of 5, 4 and 5 are not 10: the transfer fails and nothing is stored")
FS = adv({"type": "ascii", "outputRecordFormat": "FIXED", "outputRecordLength": 10})
case(ADD, "receiver", "lf", "transferMode=ASCII, Fixed 10 (sender: ascii, FIXED 10)", FS, plain("ASCII", "Fixed", 10),
     stored=b"alpha     \nbeta      \ngamma     \n", stored_text="records kept at 10, each ends with LF")
case(ADD, "receiver", "lf", "transferMode=ASCII, Fixed 10, paddingStripEnabled=true (sender: ascii, FIXED 10)", FS, plain("ASCII", "Fixed", 10, True),
     stored=same("lf"), stored_text="the padding removed from every record, each ends with LF")
case(ADD, "receiver", "lf", "transferMode=BINARY, Fixed 10, paddingStripEnabled=true (sender: ascii, FIXED 10)", FS, plain("BINARY", "Fixed", 10, True),
     stored=b"alpha     beta      gamma     ", stored_text="unchanged: nothing is stripped from a binary file, records joined")
case(ADD, "receiver", "lf", "transferMode=ASCII, paddingStripEnabled=true, Variable (sender: binary, a stream)", SB, plain("ASCII", "Variable", 2048, True),
     stored=same("lf") + b"\n", stored_text="unchanged but for the LF added at the end")

print("  ..    %d cases, one PeSIT pull each" % len(CASES))


# --------------------------------------------------------------------------------------------
# running a case
# --------------------------------------------------------------------------------------------
class Worker:
    def __init__(self, index):
        self.index = index
        self.sender, self.receiver = "CS%d%d" % (N, index), "CR%d%d" % (N, index)
        self.proxy = None
        self.eu_sender = self.eu_receiver = None
        self.accounts = []
        self.counter = 0

    def admin_ok(self, response, what):
        if response.status not in (200, 201, 204):
            raise RuntimeError("%s: %s %s" % (what, response.status, response.text[:200]))
        return response

    def setup(self):
        for name in (self.sender, self.receiver):
            self.admin_ok(admin.post("accounts", {"name": name, "type": "user", "uid": UID, "gid": UID, "homeFolder": "/home/" + name,
                                                  "transfersWebServiceAllowed": True,
                                                  "user": {"name": name, "passwordCredentials": {"password": PASSWORD}}}), "account " + name)
            self.accounts.append(name)
        host, port = PESIT_HOST, PESIT_PORT
        if CALLBACK:
            self.proxy = dummy_servers.CapturingProxy(PESIT_HOST, PESIT_PORT)
            self.proxy.thread.start()
            host, port = CALLBACK, self.proxy.port
        for owner, partner, h, p in ((self.receiver, self.sender, host, port), (self.sender, self.receiver, PESIT_HOST, PESIT_PORT)):
            self.admin_ok(admin.post("sites", {"type": "pesit", "protocol": "pesit", "name": partner, "account": owner, "host": h, "port": str(p),
                                               "transferType": "unspecified", "storeAndForwardMode": "PRESERVE", **PESIT_SITE_DEFAULTS}), "site " + owner)
        self.eu_sender = st_client.EndUserClient(HOST, ENDUSER_PORT, self.sender, PASSWORD)
        self.eu_sender.login()
        self.eu_receiver = st_client.EndUserClient(HOST, ENDUSER_PORT, self.receiver, PASSWORD)
        self.eu_receiver.login()
        self.eu_receiver.create_folder("landing")

    def profiles(self, sender_cfg, receiver_cfg, send_file, land_name, tag):
        for account in (self.sender, self.receiver):
            for p in admin.get("transferProfiles", params={"account": account}).json().get("result", []):
                admin.delete("transferProfiles/" + p["id"])
        sp, rp = "S%s" % tag, "R%s" % tag
        base_s = {"name": sp, "account": self.sender, "default": True, "sendMapping": "/" + send_file, "receiveMapping": "x", "fileLabelOption": "SEND_FILENAME"}
        base_r = {"name": rp, "account": self.receiver, "default": True, "sendMapping": "/x", "receiveMapping": land_name, "fileLabelOption": "DONT_SEND"}
        self.admin_ok(admin.post("transferProfiles", dict(base_s, **sender_cfg)), "sender profile")
        self.admin_ok(admin.post("transferProfiles", dict(base_r, **receiver_cfg)), "receiver profile")
        return rp

    def pull(self, profile):
        body = {"accountName": self.receiver, "site": self.sender, "destinationDirectory": "/landing", "transferProfile": profile, "awaitResult": False}
        response = admin.post("transfers/operations", body, params={"operation": "pull"})
        if response.status != 202:
            raise RuntimeError("pull: %s %s" % (response.status, response.text[:200]))
        index = urllib.parse.parse_qs(urllib.parse.urlparse((response.json() or {}).get("link", "")).query).get("operationIndex", [""])[0]
        found = []

        def done():
            rows = admin.get("logs/transfers", params={"account": self.receiver, "sortByStartTime": "descending", "limit": 20}).json().get("result", [])
            found[:] = [r for r in rows if str(r.get("operationIndex")) == index]
            return bool(found) and found[0]["status"] in ("Processed", "Failed")
        harness.wait_until(lambda: stopping.is_set() or done(), 90, 1)   # a check that is being stopped does not wait for a pull
        if not found:
            return None, ""
        row, error = found[0], ""
        if row["status"] == "Failed":
            error = (admin.get("logs/transfers/" + row["id"]["urlrepresentation"]).json() or {}).get("errorMessage") or ""
        return row["status"], error

    def run(self, case):
        """One pull; up to three tries when it ends in something the case did not expect."""
        data = FILES[case.file][1]
        outcome = {}
        tried = []
        for attempt in range(3):
            if attempt and stopping.is_set():   # being stopped (Ctrl-C, or the runner's time limit): no more tries
                break
            self.counter += 1
            tag = "%d%d" % (self.index, self.counter)
            send_file, land = "src%s.dat" % tag, "dst%s.dat" % tag
            outcome = {"attempts": attempt + 1}
            try:
                if self.proxy:
                    self.proxy.drop_connections()
                    self.proxy.reset()
                put = self.eu_sender.upload("/" + send_file, data, send_file)
                outcome["upload_status"] = put.status
                got = []
                harness.wait_until(lambda: got.append(self.eu_sender.download(send_file).body) or got[-1] == data, 20)
                outcome["generated"] = got[-1] if got else None
                profile = self.profiles(case.sender, case.receiver, send_file, land, tag)
                time.sleep(0.5)   # a short pause between saving the profiles and the pull, kept as it was: not the proof of any result
                status, error = self.pull(profile)
                outcome["status"], outcome["error"] = status, error
                if self.proxy:
                    self.proxy.wait_idle(1, 10)
                    capture = self.proxy.to_client_all()
                    with self.proxy._lock:
                        parts = [pesit_wire.data(bytes(k["to_client"])) for k in self.proxy.connections]
                    outcome["wire"] = pesit_wire.data(capture)
                    outcome["wire_parts"] = [x for x in parts if x]
                    outcome["net"] = pesit_wire.network_data_code(capture)
                if status == "Processed":
                    stored = []
                    harness.wait_until(lambda: land in (self.eu_receiver.list_folder("/landing") or []), 20)
                    stored.append(self.eu_receiver.download("landing/" + land))
                    outcome["stored"] = stored[0].body if stored[0].status == 200 else None
                    self.eu_receiver.delete_file("landing/" + land)
                after = self.eu_sender.download(send_file)
                outcome["after"] = after.body if after.status == 200 else None
                self.eu_sender.delete_file(send_file)
            except (st_client.STError, RuntimeError) as e:
                outcome["exception"] = str(e)
            wire_ok = case.sent is None or not self.proxy or outcome.get("wire") == case.sent
            ok = (not case.fail and outcome.get("status") == "Processed" and outcome.get("stored") is not None and wire_ok) or \
                 (case.fail and outcome.get("status") == "Failed" and case.fail in (outcome.get("error") or ""))
            if ok:
                break
            tried.append("attempt %d: %s" % (attempt + 1, outcome.get("exception") or outcome.get("error") or "status %s, wire %d bytes in %d part(s)" % (
                outcome.get("status"), len(outcome.get("wire") or b""), len(outcome.get("wire_parts") or []))))
        outcome["tried"] = tried
        return outcome

    def teardown(self):
        for client, paths in ((self.eu_receiver, lambda cl: ["landing/" + n for n in cl.list_folder("landing") or []] + ["landing"] + (cl.list_folder("") or [])),
                              (self.eu_sender, lambda cl: cl.list_folder("") or [])):
            if client:
                try:
                    for path in paths(client):
                        client.delete_file(path)
                    client.logout()
                except st_client.STError:
                    pass
        for name in self.accounts:
            for p in (admin.get("transferProfiles", params={"account": name}).json() or {}).get("result", []):
                admin.delete("transferProfiles/" + p["id"])
            for s in (admin.get("sites", params={"account": name, "fields": "id"}).json() or {}).get("result", []):
                admin.delete("sites/" + s["id"])
            admin.delete("accounts/" + name)
        if self.proxy:
            self.proxy.close()


admin = harness.connect(config, c, mock="the bundled mock does not implement PeSIT or /logs/transfers")
PESIT_PORT = int(harness.ports(config, admin).pesit)
if any(admin.exists("accounts/CS%d%d" % (N, i)) for i in range(WORKERS)):
    c.check("no account of this run exists yet", False, "run again")
    admin.logout()
    sys.exit(c.done())

only = [a for a in sys.argv[1:] if not a.startswith("--")]
selected = [k for k in CASES if not only or any(o in k.name() for o in only)]
workers = [Worker(i) for i in range(WORKERS)]
queue = list(enumerate(selected))
lock = threading.Lock()
stopping = threading.Event()


def work(worker):
    while True:
        with lock:
            if not queue or stopping.is_set():
                return
            index, case_ = queue.pop(0)
        case_.result = worker.run(case_)


try:
    for w in workers:
        w.setup()
    if not CALLBACK:
        c.info("st_callback_host is not set: the receiver's site points straight at the server, so the sent stage is not checked")
    with concurrent.futures.ThreadPoolExecutor(WORKERS) as pool:
        try:
            list(pool.map(work, workers))
        except (KeyboardInterrupt, SystemExit):   # Ctrl-C, or the SIGTERM of the runner's time limit
            # Said INSIDE the block: leaving it waits for the workers, and they only stop when they are told, so they used to
            # carry on through every case still queued (an hour, when the pulls fail) before anything was cleaned up
            stopping.set()   # the workers finish the case they are in, then everything is removed
            raise
    # custom_table (a table kept in a server configuration option): no such option, so no such profile
    probe = workers[0]
    for side, key in (("callerTranscoding", "callerTranscoding"), ("receiverTranscoding", "receiverTranscoding")):
        made = admin.post("transferProfiles", {"name": "CUSTOMX", "account": probe.receiver, "fileLabelOption": "DONT_SEND", "sendMapping": "/a",
                                               "advancedSettings": {"enabled": True, key: {"type": "custom_table", "outputEncodingScheme": "example_no_such_table"}}})
        c.check("core/%s: %s=custom_table naming a table (a server configuration option) that does not exist -> refused (400), no profile made" % (
            "sender" if side.startswith("caller") else "receiver", side),
                made.status == 400 and "does not exist or is empty" in made.text, (made.status, made.text[:200]))
    for case_ in selected:
        r = case_.result or {}
        label = case_.name()
        if r.get("tried"):
            c.info("%s needed %d attempts; the earlier ones: %s" % (label, r["attempts"], "; ".join(r["tried"])))
        c.check(label + " -> generated: the file was uploaded to the sender as is, and is untouched after the pull",
                r.get("generated") == FILES[case_.file][1] and r.get("after") == FILES[case_.file][1], (r.get("exception"), r.get("upload_status")))
        if case_.fail:
            c.check(label + " -> %s: the transfer Failed with \"%s\" and nothing was stored" % (case_.sent_text, case_.fail),
                    r.get("status") == "Failed" and case_.fail in (r.get("error") or "") and r.get("stored") is None, (r.get("status"), r.get("error"), r.get("exception")))
            continue
        if case_.sent is not None and CALLBACK:
            c.check(label + " -> sent and received (on the wire): %s" % case_.sent_text, r.get("wire") == case_.sent, (r.get("wire"), r.get("exception")))
            if case_.net is not None:
                c.check(label + " -> the data coding announced is %s" % {b"\x00": "ASCII", b"\x01": "EBCDIC", b"\x02": "binary"}[case_.net],
                        r.get("net") == case_.net, r.get("net"))
        c.check(label + " -> stored: %s" % case_.stored_text, r.get("stored") == case_.stored and r.get("status") == "Processed",
                (r.get("stored"), r.get("status"), r.get("error"), r.get("exception")))
finally:
    for w in workers:
        try:
            w.teardown()
        except Exception as e:  # keep cleaning
            print("  ..    teardown of %s: %r" % (w.sender, e))
    c.check("nothing is left behind: no account, no profile of this run",
            harness.wait_until(lambda: not any(admin.exists("accounts/" + a) for w in workers for a in (w.sender, w.receiver))))
    admin.logout()

sys.exit(c.done())
