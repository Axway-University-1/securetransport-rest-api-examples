#!/usr/bin/env python3
"""
Read what a PeSIT transfer put on the wire, from the bytes a CapturingProxy kept
(tests/integration/lib/dummy_servers.py). Enough to find the file's data and a few
of the parameters that say how it was sent; not a PeSIT implementation.

What a capture looks like, as seen on SecureTransport 5.5 (PeSIT E over TCP): a 4 byte
pre-connection message ("ACK0" in EBCDIC, after a length of 4) when a connection is new,
and then each FPDU preceded by its length in 2 bytes:

    [length 2][FPDU: length 2 (again, counting itself), phase 1, type 1, idDst 1, idSrc 1, parameters...]

The file's data travels in the FPDUs of phase 0x00 and type 0x00 (DTF), 0x40 (DTFDA),
0x41 (DTFMA) or 0x42 (DTFFA). What is in them depends on how the sender read the file:
either the bytes as they are (a stream), or records, each one a 2 byte length (not counting
those two bytes) and its bytes. Which one it is, the capture does not say (the record format
parameter reads the same): the caller knows what it expects and compares with
`data(capture)` against `frame_records([...])` or the bare bytes.

    fpdus(capture)         the FPDUs as (phase, type, idDst, idSrc, parameter bytes) in order
    data(capture)          the data FPDUs' bodies joined, as they travelled
    records(raw)           raw split into its records, or None when it is not made of records
    frame_records(list)    the records as they travel: 2 byte length and bytes, one after another
    parameter(params, n)   the value of PI n found in an FPDU's parameters (groups are entered)
    network_data_code(c)   PI 16 of the answer that selects the file: b"\\x00" ASCII, b"\\x01" EBCDIC, b"\\x02" binary
"""

DATA_TYPES = (0x00, 0x40, 0x41, 0x42)
ACK_SELECT = 0x31


def fpdus(capture):
    """[(phase, type, idDst, idSrc, parameter bytes)] in order. A capture that stops in the middle of a
    frame yields the whole frames before it."""
    found, at = [], 0
    capture = bytes(capture)
    if capture[:6] == b"\x00\x04\xc1\xc3\xd2\xf0":
        at = 6
    while at + 2 <= len(capture):
        size = int.from_bytes(capture[at:at + 2], "big")
        frame = capture[at + 2:at + 2 + size]
        if size < 6 or len(frame) < size:
            break
        found.append((frame[2], frame[3], frame[4], frame[5], frame[6:]))
        at += 2 + size
    return found


def data(capture):
    """The bodies of the data FPDUs, joined: what the file's bytes looked like on the wire."""
    return b"".join(body for phase, kind, _, _, body in fpdus(capture) if phase == 0 and kind in DATA_TYPES)


def records(raw):
    """raw cut into records (2 byte length, then that many bytes), or None if it does not come out even."""
    out, at = [], 0
    while at < len(raw):
        if at + 2 > len(raw):
            return None
        size = int.from_bytes(raw[at:at + 2], "big")
        if at + 2 + size > len(raw):
            return None
        out.append(raw[at + 2:at + 2 + size])
        at += 2 + size
    return out


def frame_records(items):
    """The records as the wire carries them."""
    return b"".join(len(item).to_bytes(2, "big") + item for item in items)


def parameter(params, number):
    """The value of PI `number` (one byte identifier, one byte length) found by walking params; the groups
    PGI 9 and 30 are entered. None when it is not there."""
    at = 0
    while at + 2 <= len(params):
        ident, size = params[at], params[at + 1]
        if ident == number:
            return params[at + 2:at + 2 + size]
        if ident in (9, 30):
            inner = parameter(params[at + 2:at + 2 + size], number)
            if inner is not None:
                return inner
        at += 2 + size
    return None


def network_data_code(capture):
    """PI 16, the data coding of the file as the sender announced it, from the answer that selects it
    (b"\\x00" ASCII, b"\\x01" EBCDIC, b"\\x02" binary), or None."""
    for phase, kind, _, _, body in fpdus(capture):
        if phase == 0xC0 and kind == ACK_SELECT:
            return parameter(body, 16)
    return None
