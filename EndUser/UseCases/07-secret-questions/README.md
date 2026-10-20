# 07 Secret questions

**Use case:** choose and set a secret question for your account, the question a password reset can ask before it lets you in,
and see what the server does with a change it refuses.

> **For test environments only.** Read the [Disclaimer](../../../README.md#disclaimer)
> before running anything. The connection settings are the ones of
> [`EndUser/API 2.0/bash`](../../API%202.0/bash) (`set_variables.local.sh`, which git ignores).

## Before you run it

- **The service has to be on.** It is the server option `Users.SecretQuestion.Enabled`, **false by default**, and an administrator switches it. With it off every
  call here is a 503, and the scripts stop with that reason (exit 3). `Users.SecretQuestions` is the list on offer, and `Users.SecretQuestion.Required` says whether a
  reset needs it.
- **Step 03 changes the account and cannot be undone.** A secret question cannot be cleared (`DELETE /myself/secretQuestion` is 405); it can only be replaced.
  So `03` does nothing unless you give it an answer: `export ST_SECRET_ANSWER='an answer'`. Pick the question by its number from step 01
  (`ST_SECRET_QUESTION_NUMBER`, default 1). **Use a throwaway account on a lab.** Without an answer, `00.run_all.sh` stops at 03 and changes nothing.

## The examples

Run them in order (`00.run_all.sh` runs them all, and ends with `99.cleanup_DELETE.sh`).

| Script | What it does | Copied from (`EndUser/API 2.0/bash`) |
| ------ | ------------ | ------------------------------------ |
| `01.secretQuestions_GET` | The questions on offer, numbered. | `07.SecretQuestions/01.secretQuestions_GET.sh` |
| `02.secretQuestion_GET_mine` | Do I have one? Exit 4 when the service is on and I have none, 3 when the service is off. | `03.Myself/06.myself_secretQuestion_GET.sh` |
| `03.secretQuestion_PUT` | Set it: the question picked by number, the answer, and my password. Needs `ST_SECRET_ANSWER`. | `03.Myself/07.myself_secretQuestion_PUT.sh` |
| `04.secretQuestion_GET_back` | Read it back and check it is the one picked. The answer is never returned. | `03.Myself/06.myself_secretQuestion_GET.sh` |
| `05.secretQuestion_PUT_refused` | Three changes that must be refused with 400: an unlisted question, a wrong password, an empty answer. | `03.Myself/07.myself_secretQuestion_PUT.sh` |
| `99.cleanup_DELETE` | Ends the session. Nothing can be removed from the account. | |

`lib.sh` is the one small file they share: it loads `../session.sh`, takes the two settings from the environment, and lists the questions.

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
throwaway account, reads the account's question through the API, then switches the service off again and restores the option.
