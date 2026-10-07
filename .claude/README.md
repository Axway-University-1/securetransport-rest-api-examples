# Knowledge pack

This folder holds what was learned building and cleaning up these examples. The
point is that you should not have to read the whole repository to work out how
it fits together, or rediscover the same API traps one failed call at a time.

These are ordinary markdown files. Open them:

| File | What it gives you |
| ---- | ----------------- |
| [skills/st-api-orientation/SKILL.md](skills/st-api-orientation/SKILL.md) | What is in the repository, how to configure and run it, and a task-to-example index. **Start here.** |
| [skills/st-api-gotchas/SKILL.md](skills/st-api-gotchas/SKILL.md) | The non-obvious traps in the API and in scripting against it. The most useful file here — read it before writing a call, not after it fails. |
| [skills/st-api-add-example/SKILL.md](skills/st-api-add-example/SKILL.md) | The house style, for when you add or change an example. |
| [skills/st-api-cover-resource/SKILL.md](skills/st-api-cover-resource/SKILL.md) | The end-to-end procedure for covering one Admin API resource, what is done and what is next, and the tools in `scripts/` it uses. |
| [agents/st-api-expert.md](agents/st-api-expert.md) | Answers questions about the API from the examples. |
| [agents/st-api-resource-author.md](agents/st-api-resource-author.md) | Covers one Admin resource by that procedure, on Sonnet. |

## Keeping this honest

The value of these files depends on them matching the repository. If you change
the layout, the configuration variables, or the coverage, update the skill that
describes it in the same commit. `st-api-orientation` cites file counts and
`st-api-add-example` cites the header format; both are quick to re-check.
