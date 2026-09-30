# Knowledge pack

This folder holds what was learned building and cleaning up these examples, in a
form both a person and an AI assistant can use. The point is that you should not
have to read the whole repository to work out how it fits together, or rediscover
the same API traps one failed call at a time.

## Just want to read it?

These are ordinary markdown files. Open them:

| File | What it gives you |
| ---- | ----------------- |
| [skills/st-api-orientation/SKILL.md](skills/st-api-orientation/SKILL.md) | What is in the repository, how to configure and run it, and a task-to-example index. **Start here.** |
| [skills/st-api-gotchas/SKILL.md](skills/st-api-gotchas/SKILL.md) | The non-obvious traps in the API and in scripting against it. The most useful file here — read it before writing a call, not after it fails. |
| [skills/st-api-add-example/SKILL.md](skills/st-api-add-example/SKILL.md) | The house style, for when you add or change an example. |

## Using Claude Code in this repository?

The skills load themselves. Clone the repository, open it, and ask your question
in plain language:

- *"Where's the example for creating a business unit?"*
- *"Why is my PATCH returning 422?"*
- *"Add a bat version of the transfer sites example."*

Claude reads the matching skill before answering, so it starts with the
accumulated knowledge instead of exploring the tree from scratch. You can also
invoke one by name, for example `/st-api-gotchas`.

For a longer question, hand it to the agent in
[agents/st-api-expert.md](agents/st-api-expert.md), which knows to consult the
skills first and to answer with a real file path rather than invented code:

```
Ask the st-api-expert agent: what do I need to change to add a step to an existing route?
```

## Keeping this honest

The value of these files depends on them matching the repository. If you change
the layout, the configuration variables, or the coverage, update the skill that
describes it in the same commit. `st-api-orientation` cites file counts and
`st-api-add-example` cites the header format; both are quick to re-check.
