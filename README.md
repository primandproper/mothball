# mothball

An iOS app for the contacts you can't bring yourself to delete. Mothball a contact and it's
archived to iCloud Drive and removed from your phone, so it stops turning up in search,
autocomplete and share sheets. Restore it whenever you want it back.

## How it works

Your phone stays the source of truth for the contacts you keep; mothball only holds the ones
you've put away. You mark contacts on the **Contacts** tab, review the changes, and apply them.
Applying re-reads your phone first, so edits you made in the meantime are never overwritten.

Nothing is deleted from your phone until its archive has been written to the vault, read back,
and checked field by field against the original. Restoring a contact that's already back on your
phone (because you re-added it, or another device synced it) is flagged as a conflict, and you
choose whether to keep the phone's version, replace it, or keep both.

### The vault

The vault is a plain folder in iCloud Drive, visible in the Files app and in Finder as
**Mothball**:

```
Mothball/
├── Mothballed/              contacts that are archived now
│   └── Alex Smith 1A2B3C4D/
│       ├── contact.archive  full-fidelity copy that restores read
│       ├── contact.vcf      portable copy any contacts app can import
│       └── entry.json       mothball's own metadata, including your note
└── Restored/                everything that came back or was replaced
```

Mothball never deletes from the vault: restored contacts move to `Restored/`, and a phone contact
replaced during a conflict is backed up there first. If you stop using the app, every contact is
still a double-click away: open its `contact.vcf` on any device.

If iCloud Drive is off, the vault falls back to the app's local storage, and the app warns you
before archiving anything, since deleting the app would then lose the vault.

## Limitations

- **One account.** Mothball works with your default contacts account (Settings > Apps > Contacts
  > Default Account), which is normally iCloud.
- **Contact notes aren't archived.** Reading the notes field on a contact needs an entitlement
  that only Apple can grant. Mothball keeps its own note per archived contact instead, stored in
  the vault.
- **Not everything survives a restore.** A deleted contact is removed from Favorites, emergency
  contacts and Focus allow-lists, and restoring it doesn't add it back. Message and call history
  reattach on their own, because they're matched by phone number and email.
- **Full contacts access is required.** With limited access, mothball can't see whether someone
  is already on your phone.

## Development

Requirements: Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and
[shellcheck](https://www.shellcheck.net). The project is generated from `project.yml`, so
`Mothball.xcodeproj` isn't checked in.

```sh
brew install xcodegen shellcheck
make generate          # create Mothball.xcodeproj
make format lint test  # what CI runs, plus formatting
make build             # simulator build, unsigned
make spike-sim         # run the archive round-trip diagnostics on a simulator
```

The app icon's light, dark and tinted versions are SVGs in `design/icon/`. After editing one, run
`make app-icon` (needs `brew install librsvg`) to re-render the PNGs in the asset catalog.

`make test` and `make spike-sim` pick the iPhone 17 Pro simulator, falling back to the first
available iPhone; set `IOS_SIM` to choose a specific one.

To run on a device, open the generated project and build to your phone. Signing is automatic,
under the team in `project.yml`. iCloud Drive only works in signed builds, so unsigned simulator
builds always use the local vault.

The **Diagnostics** sheet (the `•••` menu) runs the same round-trip checks on a real device and
shares a JSON report. It creates and deletes its own throwaway contact. If you've created a
contact named "Mothball NoteTest", it also deletes that one, to test whether contacts with notes
can be deleted without the notes entitlement.

Logging and tracing go through
[primitives-swift](https://github.com/primandproper/primitives-swift)'s Observability module and
show up in Console.app and Instruments under the subsystem `software.primandproper.mothball`.

## License

[AGPL-3.0](LICENSE).
