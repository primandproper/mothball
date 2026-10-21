# TODO

## Testing left on a real device

The MVP has been hand-tested on a phone against iCloud. These checks haven't been run yet:

- [ ] **Deleting a contact that has a note.** Create a contact named "Mothball NoteTest" with a
  note, then run Diagnostics (`•••` menu) and share the report. The simulator could delete it
  without the notes entitlement; Apple has confirmed that *updating* such a contact fails on macOS
  (FB23452026), so a phone could behave differently.
  - If the delete fails: build the fallback, which archives the contact and then opens Apple's
    contact screen so it can be deleted by hand.
- [ ] **Restored iCloud contacts keep their identifier.** The same Diagnostics report shows it
  (`kept original identifier` under "restore from keyed archive"). The simulator kept it, but that
  was a local account rather than iCloud. Nothing depends on this; it's worth knowing.
- [ ] **Vault files iCloud hasn't downloaded.** In Files, long-press `Mothball/Mothballed` and
  choose Remove Download, then reopen the app and check that every entry still lists and
  restores.
- [ ] **The limited-access screen.** Set Contacts access for Mothball to limited in Settings, and
  check that the app explains why full access is needed and that its Settings button works.

## After the device testing

- [ ] Delete the Diagnostics sheet and `Mothball/Spike/` once the note test has run. Git keeps it.
