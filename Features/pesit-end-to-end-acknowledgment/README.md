# PeSIT end to end acknowledgment

**Introduced in:** SecureTransport 5.5 (the base release; the scripts end without
changing anything on an older server)

**Use case:** send a PeSIT acknowledgment (ACK) to the partner that sent a file,
but only once the file has really gone on to its next destination, and a negative
acknowledgment (NACK) when it did not.

A PeSIT partner that sends a file to SecureTransport waits to be told what became
of it. These two scripts find the inbound PeSIT transfer by its `coreId`, look for
the outbound transfers that carry the same `coreId` (the file pushed on, or pulled
by a partner), and then answer the partner through the transfer log:

- the outbound transfers are there: **ACK**
- they are not, and a NACK is wanted: **NACK**
- they are not there yet, and a NACK is not wanted: nothing is sent and the script
  exits 2, so that it can be run again later

## The examples

Each is a `.sh` for bash and a `.bat` for Windows, side by side. Unlike the other
features they create nothing, so there is no `00.run_all` and no `99.cleanup`: they
read the transfer log and send acknowledgments for transfers that already exist.
They need a real PeSIT transfer to work on (`tests/online/checks/32.pesit_acknowledgment_loop_scripts.py`
builds a loop of two accounts on one server to make some).

| Script | What it does |
| ------ | ------------ |
| `Acknowledgment` | Acknowledges the one inbound PeSIT transfer with the given `coreId`. |
| `IteratePesitInbounds` | Finds every processed PeSIT inbound transfer in a time window that has no acknowledgment status yet, and runs `Acknowledgment` for each. |

```
./Acknowledgment.sh <CORE_ID> [HOST] [TYPE_OF_OUTBOUND_TRANSFER] [NUMBER_OF_EXPECTED_OUTBOUND_TRANSFERS] [SEND_NACK_IF_NOT_FOUND] [ROOT_FOLDER] [CLEAR_API_OUTPUT_FILES] [NUMBER_OF_RETRIES] [SLEEP_BETWEEN_RETRIES]
./IteratePesitInbounds.sh <START_HOURS_AGO> <END_HOURS_AGO> [HOST] [ROOT_FOLDER] [CLEAR_API_OUTPUT_FILES]
```

Every parameter is described in the header of the script. `TYPE_OF_OUTBOUND_TRANSFER`
is `MIX`, `PUSH` or `DOWNLOAD`. The logs and the API answers are kept under
`ROOT_FOLDER/acks`.

## Exit codes

| Code | Meaning |
| ---- | ------- |
| 0 | Done: the acknowledgment was sent, or the transfer had been acknowledged already (the server answers 422) |
| 1 | An error: a missing parameter, an API call the server refused, or every attempt to send the acknowledgment failed. `IteratePesitInbounds` carries on with the other transfers and exits 1 at the end. |
| 2 | Not yet: the outbound transfer is not there and no NACK was asked for. Run it again later. (`IteratePesitInbounds` treats this as normal and leaves the transfer for a later run.) |

## Settings

The connection settings are the ones of the Admin examples
(`Admin/API 2.0/bash/set_variables.local.sh`, or `.bat`); the scripts load them
through the same version check as every other feature, with 5.5 as the release.
The log folder defaults to `/var/tmp` (`C:\Temp` for the bat files).

## Tests

`tests/offline/checks/test_bash_pesit_ack.sh` runs both scripts against a stub `curl`
(the ACK, the NACK, the retry exit, paging past 100 transfers, a failed attempt).
`tests/online/checks/32.pesit_acknowledgment_loop_scripts.py` runs them on a real
server, on a PeSIT loop it builds and removes.
