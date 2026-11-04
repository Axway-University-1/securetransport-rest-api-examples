# Working on this repository

[Back to the README](README.md). Read the rules in [CLAUDE.md](CLAUDE.md) first: every new script and every change is covered by a test.

## Folders you work in

| Folder | What is in it |
| ------ | ------------- |
| `tests/` | The checks. `./tests/offline/run_all.sh` runs the offline ones (no server, no credentials); `tests/online` runs checks against a real lab server you name in `tests/local/integration.conf` (or the bundled mock), and `tests/common` holds the Python both sides use. `tests/local` and `tests/offline/output` are yours and git ignores them. See [tests](tests/README.md). |
| `tools/` | The helper scripts. `list_examples.py` lists every example with the endpoint it calls and its `Risk` line (`--table` for a table). `test_map.py` maps a script to the checks that mention it, `script_coverage.py` and `measure_coverage.py` say how well the examples are tested, `mutation_probe.py` (and `mutation_progress.py`) break a script on purpose to see whether a test notices. `guide_examples.py` and `guide_review_sheet.py` serve the guides, and `review_status.py` keeps `review/checked.tsv`. Each says what it does with `--help`. |
| `review/` | `checked.tsv`, the list of files a person has read and confirmed, each with a hash of its content, so that a file that changed since is easy to find. Kept by `tools/review_status.py`; do not edit it by hand. |
| `.claude/` | A knowledge pack for people and for AI assistants working here: `skills/` holds three guides (orientation, gotchas, adding an example) and the procedure for covering a new API resource, `agents/` holds two assistant definitions. See [its README](.claude/README.md). Your own `settings.json` and `settings.local.json` in this folder are git ignored. |
| `.github/` | `workflows/tests.yml`: runs `./tests/offline/run_all.sh` on Linux for every push and pull request. |
| `images/` | The screenshots used by the [Admin API README](Admin/API%202.0/README.md). |
| `tmp/` | A scratch folder for the files the helper scripts write while probing a server. It is git ignored, so a fresh clone does not have it, and you can delete what is in it. |

## The files at the root

| File | What it is |
| ---- | ---------- |
| `README.md` | The front page: what this is, the disclaimer, how to start. |
| `CONTRIBUTING.md` | This file. |
| `GLOSSARY.md` | The terms and acronyms. |
| `LICENSE` | The Apache License 2.0. |
| `CLAUDE.md` | The working rules for anyone changing the repository with Claude Code: every change is covered by a test, how to run the suite, the safety rules for a lab. |
| `.gitignore` | What git does not track: your own configuration (`*.local.*`, `config`), passwords, `tests/local`, `tests/offline/output`, `tmp/`. |
| `.gitattributes` | Line endings: `.sh` and `.py` files use LF, `.bat` files use CRLF, so a checkout works on Linux and on Windows. |
| `.DS_Store` | A macOS Finder file. It is not tracked; ignore it. |

## Inside the examples

```
Admin/API 1.4/          what the older API 1.4 has and 2.0 has not, bash only, with its own README
Admin/API 2.0/          the administrator API, with its own README
    bash/               curl examples, numbered by topic
    bat/                the same examples for Windows
    python/
        python3/        the python examples
        utils/          tools that work on an exported configuration XML
Admin/UseCases/         complete administrator scenarios, a learning path
EndUser/
    API 2.0/bash/       end user API, on the user port, with its own README
    UseCases/           complete end user scenarios, a learning path
Features/               complete solutions, one folder per feature
    Guidance/           guides to read: time formats, sessions, reading the answers, field names, Expression Language escaping
```

## Testing your own scripts

The method this repository uses to test its scripts, which you can copy, is in [tests/README.md](tests/README.md#testing-your-own-scripts).
To add an example, follow the [house style](.claude/skills/st-api-add-example/SKILL.md).
