# Expression Language in routes and sites: where it goes and how to escape it

**For:** administrators and integrators who create routes, route steps, transfer sites and login restriction policies through the REST API.
**Checked on:** SecureTransport 5.5-20260924. Where the text says "the server does", it was tried on this version with throwaway objects that were removed
afterwards. A statement marked "not tried" comes from the product documentation or from the example scripts in this repository, and was not run here.

## Summary

Some fields of the API hold an *expression*, a small program in the Expression Language (EL), written as `${ ... }`. When you send one through the API,
it passes through **three layers that each have their own rules for the backslash and the dollar sign**: your shell, JSON, and the EL itself. Most mistakes
come from counting backslashes in the wrong layer. This guide says which fields take an expression, which only look like they do, and how to write the text
so that the server stores what you meant.

The three things to remember:

1. **The server does not check an expression when a route is saved.** A broken expression is stored without a complaint, and you find out when a transfer runs.
   Always read the object back and compare the stored text with what you meant.
2. **Do not build the JSON body by hand when you can avoid it.** Let `jq` or a JSON library do the escaping. Then you only have to get the EL layer right.
3. **In bash, put the body in single quotes.** In double quotes the shell reads `${ ... }` itself and fails.

## Where an expression goes, and where it does not

| Field | Holds | Is it EL? |
| ----- | ----- | --------- |
| A route's `condition`, when its `conditionType` is `EL` | `${account.disabled != '0'}` | Yes |
| A route step's `condition`, when its `conditionType` is `EL` | the same form, for example `${account.disabled != '0'}` | Yes |
| A route step's `postTransformationActionRenameAsExpression` | `${basename(transfer.target)}-${date('yyyyMMdd_HHmmss')}${extension(transfer.target)}` | Yes |
| A login restriction policy rule's `expression` | `${currentSessions <= 3}` | Yes |
| A site's `host`, `downloadPattern` and similar fields | a template such as `${DXAGENT_TRANSFERSAPI_SERVER}` | Stored as typed, and filled in when a transfer runs |
| A route step's `fileFilterExpression` | a pattern, with `fileFilterExpressionType` `GLOB`, `REGEXP` or `TEXT_FILES` | **No.** A plain file filter. |
| A site's `downloadPattern`, with `downloadPatternType` | a pattern, with the type `glob` or `regex` | **No.** A plain file filter. |
| A user class's `expression` | another language again: no `${ }`, and the server checks it when it is saved | Not EL (not tried here: from the product notes of this repository) |

All the rows marked "Yes" or "Stored as typed" were created on the lab and read back unchanged: the server keeps the text exactly as it was sent.

A filter and an expression look alike but are not the same. A filter has no `${ }`, and its type name has its own spelling, as the next section shows.

## What the server does when the text is wrong

The type of a filter is checked. The text of an expression is not.

```text
fileFilterExpressionType "REGEX"   ->  400  Valid steps.fileFilterExpressionType values are: GLOB, REGEXP, TEXT_FILES.
fileFilterExpressionType "regexp"  ->  400  The value specified by fileFilterExpressionType property is illegal.
site downloadPatternType "GLOB"    ->  400  Unknown name value [GLOB] for enum class.
site downloadPatternType "regexp"  ->  400  Unknown name value [regexp] for enum class.
site downloadPatternType "regex"   ->  201
site downloadPatternType "glob"    ->  201
```

The two fields name the same idea in two ways. A route step uses upper case (`GLOB`, `REGEXP`). A site uses lower case (`glob`, `regex`).

The text itself is accepted, whatever it is. Each of these was sent in a route and answered **201**, and the stored text was the same as the text sent:

| Sent as the route's `condition` (type `EL`) | Why it is wrong |
| ------------------------------------------ | --------------- |
| `${transfer.target.matches(` | not finished |
| `${nosuchfn(transfer.target)}` | there is no such function |
| `transfer.target` | not an expression, no `${ }` |

Two more cases were accepted and stored: a `condition` on a route whose `conditionType` is `ALWAYS`, and a regular expression that does not compile
(`(unclosed`) in a `REGEXP` filter. Nothing tells you it will not work.

## The three layers

Take one regular expression inside an expression: a file name that ends in `.txt`. A person would write the regex as `.*\.txt`. The dot needs one backslash,
because in a regular expression a plain dot means "any character".

1. **EL.** The regex is a string inside `${ ... }`, and the product documentation says every backslash in an EL string is written twice. The expression the
   server must hold is `${transfer.target.matches('.*\\.txt')}`, with **two** backslashes. (From the product documentation, as quoted in
   `Admin/API 2.0/bash/14.ExpressionLanguage/05.routes_step_condition_matches_backslashDoubling.sh`. Not tried here: what the route does with each form needs a real transfer.)
2. **JSON.** The expression is the value of a JSON string, and in JSON every backslash is written twice. Two backslashes in the stored text become **four** in the
   body you send.
3. **Shell.** Between single quotes, bash passes the text as it is. Between double quotes, it reads `${ ... }` and `\` itself.

### Worked table

Each row was sent to a throwaway route as a `condition` of type `EL`, and read back with `GET /routes/{id}?fields=condition`.

| How the body is made | What is in the body text | What the server stores | Result |
| -------------------- | ------------------------ | ---------------------- | ------ |
| By hand, in single quotes, four backslashes: `'.*\\\\.txt'` | `${transfer.target.matches('.*\\\\.txt')}` | `${transfer.target.matches('.*\\.txt')}` (two backslashes) | The form the EL rule asks for |
| By hand, two backslashes: `'.*\\.txt'` | `${transfer.target.matches('.*\\.txt')}` | `${transfer.target.matches('.*\.txt')}` (one backslash) | Valid JSON, stored without a complaint. It is only the JSON layer, and the EL layer's doubling is missing. |
| By hand, one backslash: `'.*\.txt'` | `${transfer.target.matches('.*\.txt')}` | nothing | **400** "Incorrect JSON format" |
| Python, `json.dumps`, the EL text with two backslashes | four backslashes | two backslashes | The same as the first row. Python did the JSON layer. |
| `jq --arg`, the EL text with two backslashes | four backslashes | two backslashes | The same. `jq` did the JSON layer. |

With a tool you type the EL text once, as the EL wants it (two backslashes), and the tool does the JSON layer. With a hand-made body you must type both layers.

A plain filter has no EL layer. A step with `"fileFilterExpressionType": "REGEXP"` and the regex `.*\.(xml|txt)` needs only the JSON layer: **two**
backslashes in the body, and **one** is stored (tried: the stored text was `.*\.(xml|txt)`).

## Write the body with a tool

### jq

The EL text goes in a quoted here-document, so that the shell changes nothing. `jq` makes the JSON:

```bash
EL=$(cat <<'EOF'
${transfer.target.matches('.*\\.txt')}
EOF
)
jq -n --arg c "$EL" '{name: "ZZTEST_example", type: "SIMPLE", conditionType: "EL", condition: $c}' > route.json
```

The file `route.json` holds `"condition": "${transfer.target.matches('.*\\\\.txt')}"`: four backslashes. Send it:

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes" \
  -H "accept: application/json" -H "Content-Type: application/json" -H "Referer: x" \
  --data-binary @route.json
```

The answer is `201`, with the address of the new route in the `Location` header.

### Python

```python
import json

el = "${transfer.target.matches('.*\\\\.txt')}"     # in Python source, \\\\ is two backslash characters
body = json.dumps({"name": "ZZTEST_example", "type": "SIMPLE", "conditionType": "EL", "condition": el})
print(body)    # {"name": ..., "condition": "${transfer.target.matches('.*\\\\.txt')}"}
```

In the Python source the EL text has four backslashes only because Python reads them too. The string in memory has two, which is what the EL wants.

### Always read it back

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G "https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes" \
  --data-urlencode "name=ZZTEST_example" --data-urlencode "fields=name,condition" -H "accept: application/json" -H "Referer: x"
```

```text
{
  "resultSet" : { "returnCount" : 1, "totalCount" : 1 },
  "result" : [ {
    "name" : "ZZTEST_example",
    "condition" : "${transfer.target.matches('.*\\\\.txt')}"
  } ]
}
```

The answer is JSON too, so the server shows each backslash twice. The stored text has two. To count them, decode the answer, for example with `jq -r .result[0].condition`.

## The shell: single quotes

A body that holds `${ ... }` goes between **single** quotes:

```bash
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes" \
  -H "accept: application/json" -H "Content-Type: application/json" -H "Referer: x" \
  -d '{"name":"ZZTEST_example","type":"SIMPLE","conditionType":"EL","condition":"${!empty account.email}"}'
```

In double quotes bash reads `${ ... }` and stops with an error, before curl is run:

```text
$ echo "{\"condition\":\"${transfer.target}\"}"
bash: {"condition":"${transfer.target}"}: bad substitution
$ echo "{\"condition\":\"${!empty account.email}\"}"
bash: {"condition":"${!empty account.email}"}: bad substitution
```

If you need a variable of the shell inside the body, use double quotes and put a backslash before every `${` that belongs to EL:

```text
$ X=5; echo "{\"n\":\"$X\"} and \${account.name}"
{"n":"5"} and ${account.name}
```

A single quote inside a body between single quotes (the `'` around `.*\\.txt`) is the hard part. Close the quote, write `"'"`, and open it again, or avoid it: build the body with `jq` or Python as above.

## Checklist

- [ ] The field takes an expression (the first table). A file filter is not one, and its type name has its own spelling.
- [ ] The body is made by `jq` or a JSON library, and the EL text has the EL layer's backslashes only. If it is made by hand, the backslashes are doubled once more.
- [ ] The body is between single quotes, or every `${` that belongs to EL has a backslash.
- [ ] After the call, the object is read back, and the stored text is the text meant. The server did not check it.
- [ ] A new expression is tried on a lab with a real transfer before it goes to a production server.
