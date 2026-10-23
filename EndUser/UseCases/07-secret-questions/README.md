# 07 Secret questions

**Use case:** choose and set a secret question for your account, the question a password reset can ask before it lets you in, and see what the server does with a change it refuses.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`EndUser/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).

## Before you run it

- **The service has to be on.** It is the server option `Users.SecretQuestion.Enabled`, **false by default**. With it off every call here is a 503 and the scripts stop with
  *"An administrator must switch it on: the server option Users.SecretQuestion.Enabled has to be true"* (exit 3). `Users.SecretQuestions` is the list on offer, and
  `Users.SecretQuestion.Required` says whether a reset needs it.
- **Step 03 changes the account, and nothing removes the question afterwards** (see below). Use a throwaway account on a lab. `03` needs the answer as its parameter, and prints its
  usage without it. `00.run_all.sh ANSWER QUESTION_NUMBER` needs both, and without them it stops at once with its usage (exit 2): nothing is run, not even the login. It also checks the number against the questions the server really offers: it logs in once, counts them, and a number past the end (10 when there are 9) ends that session at once and stops, with the count in the message.

## The examples

Run them in order (`00.run_all.sh ANSWER QUESTION_NUMBER` runs them all, and ends with `99.cleanup_DELETE.sh`). The scripts take their input as parameters, like the other examples.

| Script | What it does | Copied from (`EndUser/API 2.0/bash`) |
| ------ | ------------ | ------------------------------------ |
| `01.secretQuestions_GET` | The questions on offer, numbered. | `07.SecretQuestions/01.secretQuestions_GET.sh` |
| `02.secretQuestion_GET_mine` | Do I have one? Exit 4: the service is on and I have none. Exit 3: the service is off. Exit 5: an administrator asked me to choose a new one. | `03.Myself/06.myself_secretQuestion_GET.sh` |
| `03.secretQuestion_PUT ANSWER [QUESTION_NUMBER]` | Set it: the question picked by its number (default 1), the answer, and my password. | `03.Myself/07.myself_secretQuestion_PUT.sh` |
| `04.secretQuestion_GET_back [QUESTION_NUMBER]` | Read it back and check it is the one picked. The answer is never returned. | `03.Myself/06.myself_secretQuestion_GET.sh` |
| `05.secretQuestion_PUT_refused` | Three changes that must be refused with 400: an unlisted question, a wrong password, an empty answer. | `03.Myself/07.myself_secretQuestion_PUT.sh` |
| `99.cleanup_DELETE` | Ends the session. Nothing can be removed from the account. | |

```
./01.secretQuestions_GET.sh                    # the questions, numbered
./03.secretQuestion_PUT.sh "Rex" 8             # question 8, "What is your dog's name?", answered "Rex"
./04.secretQuestion_GET_back.sh 8              # is that what the account has now?
./00.run_all.sh "Rex" 8                        # the whole use case: both parameters are required
```

## Removing a question

**There is no way to remove one**, and this was looked for: the end user's `DELETE /myself/secretQuestion` is 405; an empty or null question or answer is 400; and the administrator's
`PATCH` (`remove`, or `replace` by null) and `PUT` of the account without it all answer 204 and change nothing (it is in the product team's list of known issues). What can be done:

- **Replace it.** Run `03` again with another question or answer. The old one is gone, the account always has one.
- **Ask for a new one** (an administrator): `Admin/API 2.0/bash/05.Accounts/06.accounts_name_PATCH_secretQuestion.sh ACCOUNT` sets `forceSecretQuestionChange`.
  The question stays on the account, but **the server then refuses the account's login and nearly every call with 403 `error.secretQuestion.required`** until the user chooses a new one.
  Only the list (`GET /secretQuestions`) and the `PUT` that sets the new question are answered. This is why `03` uses Basic authentication on each call and not a session: it
  must work for exactly that account. After a login that is refused for this reason, every script of the use cases says who asked and where to go (03), and `02` exits 5.
  `06.accounts_name_PATCH_secretQuestion.sh ACCOUNT false` takes the requirement away again without a new question.
- **Switch the service off** (an administrator): `Users.SecretQuestion.Enabled` false. The question stays stored, but nothing uses or shows it.

## What to take from it

- **A 503 can mean two things.** `GET /myself/secretQuestion` answers `503 "Service not available"` both when the service is off and when it is on but
  the account has no question yet. The list (`GET /secretQuestions`, 200 when the service is on) tells them apart, which is what 02 does.
- **The question must be on the list, exactly.** An invented one is 400 `error.secretQuestion.notFound`. A wrong password in the body is 400
  `error.password.invalid` (a refused change, not a failed login: it does not count towards locking the account). An empty or missing answer is 400
  `secretAnswer may not be empty`. Two different shapes of error body for one call.
- **The answer is write-only.** No call returns it. The administration API shows `user.secretQuestion` with a count of wrong guesses (`secretAnswerGuessFailures`).
- A password reset is what uses the answer: `03.Myself/04` asks for a reset link by e-mail, and `05` completes it with the token, the new password and the answer.
  A link can be asked for once an hour per user, so the reset itself is not part of this use case.

## Tests

`tests/offline/checks/test_bash_enduser_usecases.sh` runs every script against a stub `curl`.
`tests/online/checks/67.enduser_usecase_secret_questions.py` runs them on a real server: it switches the service on for the length of the check, uses a
throwaway account, reads the account's question through the API, asks for a new question with the Admin example and shows the use case recovering from it, then
switches the service off again and restores the option to the value it had.
