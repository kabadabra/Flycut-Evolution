# Flycut Evolution

Flycut Evolution is a free, open source clipboard manager for Mac. It keeps text you copy within reach, so you can search, preview, and paste it again from the menu bar. Emerging Dynamics maintains this Swift rewrite as a continuation of [TermiT/Flycut](https://github.com/TermiT/Flycut), which was based on [Jumpcut](http://jumpcut.sourceforge.net/). The app remains [MIT licensed](license.txt).

**[Download the latest release](https://github.com/kabadabra/Flycut-Evolution/releases/latest)** · [What changed](CHANGELOG.md) · [Report an issue](https://github.com/kabadabra/Flycut-Evolution/issues)

## Features

- **Find and paste quickly.** Open the menu bar palette, search Recents or Favorites, then single-click a clipping or press Return. Flycut pastes into the field you were using; when there is no editable field, it puts the clipping on the clipboard. The palette has a taller, compact list and shows the source app without a changing timestamp.
- **Keep or remove formatting.** New text copies with RTF keep their formatting for normal paste. Press **Shift–Command–V** to paste the current clipboard as plain text immediately, or use the **Aa** button beside a formatted clipping to paste that item without formatting. The global shortcut is configurable.
- **Preview the full copy.** Rows show one plain-text line with an ellipsis. Hover to highlight a row and see its full text and saved formatting. Turn the hover preview off in Appearance settings if you prefer.
- **Keep history tidy.** Copying the same text again from the same app moves that clipping to the top rather than adding a duplicate. Favorite important clippings, pause capture, set history limits, and export text. Local history is stored privately in SQLite.
- **Sync between your Macs.** Optional Cloud Sync shares history, favorites, and available formatting through your private iCloud database. Enable it separately on each Mac signed into the same Apple Account. Flycut asks before uploading existing history; device settings stay local.
- **Control privacy and appearance.** Skip password fields, sensitive clipboard types, or chosen text lengths; choose light, dark, or system appearance; pick a Clipboard, Scissors, or Text menu bar icon; and adjust palette size and preview behavior. Flycut can open at login and remember a paused state.
- **Bring your older history.** A reviewed importer can copy saved clippings and settings from earlier Flycut versions. It makes a private backup and leaves the old source untouched. Fresh installs with no old source skip the importer.

## Requirements and installation

Flycut Evolution 1.0.0 requires **macOS 14 or later** on an **Apple Silicon or Intel Mac**. The release contains both architectures and has been tested on macOS 27. Cloud Sync requires iCloud and Macs signed into the same Apple Account.

1. Download **Flycut-Evolution.dmg** from the [latest release](https://github.com/kabadabra/Flycut-Evolution/releases/latest), open it, and drag **Flycut Evolution.app** to Applications. The release app and disk image are Developer ID signed and notarized by Apple.
2. Open the app and allow clipboard access if macOS asks. To paste automatically into other apps, grant Flycut Evolution Accessibility access in **System Settings → Privacy & Security → Accessibility**. Without it, clicking a clipping still copies it for manual paste.
3. To use Cloud Sync, turn it on in **Settings → Cloud Sync** after reviewing the upload notice, then enable it on your other Mac. Sync is optional; your history works locally without it.

The [Flycut 2.0 release](https://github.com/kabadabra/Flycut/releases/tag/v2.0.0) remains available for older Macs. If you are upgrading, follow the [migration steps](#moving-to-flycut-evolution) below before removing the old app.

## Everyday use

Copy text as usual. Click Flycut's menu bar icon to search your clippings; select one with a single click or the keyboard. Use **Shift–Command–V** for an immediate plain-text paste of your current clipboard. Settings also provide pause, favorites, export, keyboard help, and controls for history and privacy. Formatted previews and pastes require RTF in the original copy; older, HTML-only, and unsupported copies remain plain text.

## Build locally

Use Xcode 27.0 (Swift 6.4, Swift 6 language mode). Open `Package.swift` in Xcode or run:

```sh
swift test
scripts/build-app.sh debug
open 'build/Preview/Flycut Evolution Preview.app'
scripts/build-app.sh release
scripts/verify-app.sh 'build/Export/Flycut Evolution.app'
```

The preview has a separate `com.edynamics.flycut.preview` identity and data. Local bundles are ad hoc signed. The production bundle is `build/Export/Flycut Evolution.app`, identity `com.edynamics.flycut`, version `1.0.0`. Cloud Sync requires the production app to be signed with the Flycut CloudKit Developer ID profile. Opening it can start production migration; use the preview for routine development. See [developer notes](docs/DEVELOPING.md) and [release setup](RELEASE_SETUP.md).

## Moving to Flycut Evolution

1. Quit every Flycut instance. Keep the old app and saved preferences until you have checked the import. If history was never saved, export any clippings you need before quitting the old version.
2. Install the reviewed, signed `Flycut Evolution.app` from its DMG. Launch **/Applications/Flycut Evolution.app** explicitly by path so macOS does not choose the old `Flycut 2.0.app`.
3. If Flycut finds an older saved source, review the migration preview: choose the current fork, an earlier `com.kabadabra.flycut` source, original sandboxed Flycut, or a selected `.plist`. If no source is available, setup skips the importer. You can still open it later from Settings. If container access is denied, use the file picker. Choose one source; imports are not silently combined.
4. Check counts, unsupported settings, malformed entries, and the proposed destination. Existing destination data requires a merge or replace choice and a destination backup. The importer copies the source to a private backup and leaves the source untouched. Reimporting the same source is idempotent. Imported history can raise capacity so records are not trimmed. A legacy “never save” setting keeps imported clips in memory unless you explicitly change the save mode.
5. Verify recent clips, favorites, settings, and paste behavior. Keep the backup for recovery. **Only then remove the old Flycut 2.0.app**: both versions use `com.edynamics.flycut` and should not remain installed together. Disable any old login registration and set Open at Login in the new app as needed. Recheck Accessibility permission for the new app.

The original upstream app uses a different identity, but running multiple clipboard managers during migration can confuse capture and paste behavior. Imported cloud flags never enable sync.

## Development tools

QMD and Graphify are optional local navigation tools. See [developer notes](docs/DEVELOPING.md). Generated indexes and graphs are not release assets. The earlier Objective-C and iOS sources remain in the [historical Flycut repository](https://github.com/kabadabra/Flycut); this repository contains the active Swift product.

## Credits and license

Original Flycut by General Arcade, Gennadiy Potapov, and contributors. Jumpcut by Steve Cook and contributors. This fork keeps the **Flycut** name and the original MIT license. See [acknowledgements](acknowledgements.txt) for included libraries and their authors. To support the original maintainers, see [their project](https://github.com/TermiT/Flycut).

Flycut 2.0 includes work from recent upstream contributors. Thank you to [Emanuel Stadler (@emanuelst)](https://github.com/emanuelst) for the [macOS 27 menu bar fix](https://github.com/TermiT/Flycut/pull/328) and [bezel improvements](https://github.com/TermiT/Flycut/pull/327) adapted in [our PR #3](https://github.com/kabadabra/Flycut/pull/3); [Ilya Bersenev (@voidless)](https://github.com/voidless) for the [keyboard layout paste fix](https://github.com/TermiT/Flycut/pull/314); [Tyler Martin (@tymrtn)](https://github.com/tymrtn) for the [CloudKit startup fix](https://github.com/TermiT/Flycut/pull/322); and [@agentheath](https://github.com/agentheath) for the [macOS 26 menu bar crash fix](https://github.com/TermiT/Flycut/pull/323).

Bug reports, ideas, and pull requests are welcome. See [contributing](CONTRIBUTING.md) for how to report a problem without sharing private clipboard data.
