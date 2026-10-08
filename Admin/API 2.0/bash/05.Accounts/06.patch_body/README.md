# The patch bodies of 06.accounts_name_PATCH_with_file

Each file is a JSON Patch: a list of operations, applied to one account by
`06.accounts_name_PATCH_with_file.sh [NAME [PATCH_FILE]]` (the account is
`example_user` by default, the file `stPatchAccount.json`). A JSON file cannot
carry a comment, so what each one assumes is written here.

| File | What it does | What is specific to one environment |
| ---- | ------------ | ------------------------------------ |
| `stPatchAccount.json` (the default) | adds the contact "Test 2Contact421" to the address book | the e-mail address is made up (`a22@1b.com1`); use a real one if the contact is to be used |
| `stPatchAccountContacts.json` | adds the contact "Test Contact1" | the e-mail address is made up (`a@b.com1`) |
| `stPatchAccountNotes.json` | sets the notes to `HelloWorld876` | nothing: works on any account |
| `stPatchAccountForcePasswordChange.json` | turns `forcePasswordChange` off | nothing: works on any user account |
| `stPatchAccountBU.json` | moves the account into the business unit `Pippin` and sets its home folder to `/usrdata/BU/Pippin/t3` | **both**: the business unit must exist (on a server without it the answer is 404 "Business unit with name Pippin not found or not accessible.", exit 1) and the home folder is one environment's base folder. Copy the file and put in a business unit and a home folder of your own before using it |

The two contact samples add an element to the end of a list (`/-`), which works
whether the list is empty or not. 06 prints what each path holds before it
changes anything, so that a `replace` can be put back; a contact that was added
is taken out with a `remove` of its index (see `06.accounts_name_PATCH.sh`).
