# Guidance

Short guides for customers on how to use SecureTransport features well: what the product does, the mistakes that are easy to make, and what to do
instead. A guide in this folder is **text**. It has no script of its own to run against a server, and nothing here changes a server.

The folders next to this one ([Features](../README.md)) are examples to run. This one is for reading.

## Guides

| Guide | For | What it covers |
| ----- | --- | -------------- |
| [Time formats in the SecureTransport REST API, and daylight saving time](time-formats.md) | Administrators and integrators who script against the REST API, or who build reports and scheduled jobs on it | The five date formats of the API (RFC 2822, ISO 8601, `yyyy-MM-dd`, a timestamp, `dd/MM/yyyy`), which resource takes which, an example of each that was run on the lab, the forms the answers use, and then daylight saving time: why a day is not always 86,400 seconds, how to compute each midnight on Linux, macOS and in Python, how `generateReport` cuts a day, scheduled jobs, and how to test a script without waiting for the date. |
| [Reading the answers of the SecureTransport REST APIs](reading-api-answers.md) | Anyone who writes a script or program that calls the Admin API or the End User API | A 200 that says no (`isSuccessful`, two different shapes), and the shapes of an error with a function that reads them all. Lists, paging and `fields=`, stopping and starting a daemon, changing an object and moving files are use cases, linked from the guide. |
| [Authentication and sessions in the SecureTransport REST API](authentication-and-sessions.md) | Administrators and integrators who write scripts or programs against the Admin API or the End User API | The three ways in (Basic authentication, a session, an API key) with a command for each; the rules of API keys (Admin API only, at most 2, mandatory expiry, permissions); what a session remembers; what an ended session, a locked account and a forced secret-question change answer, and what the CSRF token does today; and advice on which way fits which case, labelled as advice. |
| [Expression Language in routes and sites: where it goes and how to escape it](expression-language-escaping.md) | Administrators and integrators who create routes, route steps, sites and login restriction policies | Which fields hold an expression and which only look like one (file filters). The three escaping layers (shell, JSON, EL) with a table of what you type, what the body holds and what the server stores. The server does not check the text of an expression. Spellings of filter types and their error messages. Quoting in bash (`${...}`), and building the body with `jq` or Python. |
| [Field names and shapes that differ between releases and between API areas](field-names-between-releases.md) | Integrators and administrators who write clients for the Admin API and the End User API, and run them against more than one release | The same thing under two names (End User transfer list and single object, Admin transfer log, the user's name), lists that are an envelope or a plain array, names returned but refused in `fields=`, the daemon answer that differs from the reference, and four habits for a client that survives. |

## What a guide in this folder has

- A first block that says who it is for and which release it was checked on. A statement about the product is made only when it was tried on that release;
  anything not tried is said to be not tried, with who to ask.
- No internal issue numbers and no text from internal lists: a guide can be handed to a customer as it is.
- Code that is shown is run by a test (`tests/offline/checks/test_feature_guidance.py`), so a snippet that stops working is found by the suite.
- A row in the table above.

## Adding a guide

1. Write `<topic>.md` in this folder, in plain, short sentences: a reader may not have English as a first language.
2. Add its row to the table above, and say what it covers.
3. Add a test for each piece of code in it to `tests/offline/checks/test_feature_guidance.py`.
4. Run `./tests/offline/run_all.sh`.
