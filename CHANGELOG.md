# Changelog

## 1.0.0 (2026-09-27)

Flycut Evolution 1.0.0 is a complete Swift rewrite of the free, MIT licensed clipboard manager, maintained by Emerging Dynamics. It supports macOS 14 or later on Apple Silicon and Intel. [Flycut 2.0 remains available for older Macs](https://github.com/kabadabra/Flycut/releases/tag/v2.0.0).

### What’s new

- A taller, more compact searchable palette for recent clippings and favorites, opened from the menu bar. Rows show a single plain-text line with an ellipsis and the source app, without a changing timestamp. Hover highlights the row and can show the full text with saved RTF styling; the preview can be turned off in Appearance settings. Single-click still pastes while a preview is visible. Return also pastes with saved formatting when the previous app has an editable field focused; a small text icon beside formatted rows pastes that clipping without formatting. Shift-Command-V pastes the current clipboard as plain text without opening the palette; the shortcut remains configurable. Keyboard help, pause, and text export remain available.
- Refreshed settings for history, shortcuts, privacy, appearance, and startup behavior. Flycut can remember your chosen pause state and uses the current macOS Login Items system.
- The optional menu bar icons use compact native symbols with explicit rendering sizes and weights, preserving the familiar Scissors shape.
- Local history with private storage and safer clipboard capture. New text copies can retain bounded RTF styling for previews, paste, and Cloud Sync. Existing and unsupported copies remain plain text. Automatic paste checks Accessibility permission and editable focus; activation leaves the clipping copied when paste is unavailable.
- Repeated copies of the same text from the same app refresh and move one clipping to the top. Existing duplicate recents are consolidated with a private backup; there is no duplicate-removal setting.
- Optional Cloud Sync shares clippings and favorites between Macs signed into the same Apple Account. Flycut uses a private CloudKit container, keeps device settings local, and asks before uploading existing history.

### Moving from an older Flycut

- Fresh installs with no readable older Flycut preferences open directly; manual import remains available in Settings.
- Review a preview of your old clippings and settings before import. Flycut preserves their order and available metadata, makes a private backup of the source, and leaves the original file untouched.
- Choose how to handle an existing destination and whether imported history stays in memory or is saved. Imported history can raise capacity so clippings are not trimmed during the move.
- Quit Flycut 2.0 before opening the new app. Verify your imported history before removing the old app. Both versions use the same app identity. See the [upgrade guide](https://github.com/kabadabra/Flycut-Evolution#moving-to-flycut-evolution).
- Imported cloud preferences do not silently turn on Cloud Sync. Enable it in Settings after reviewing the upload notice.

### For developers

- Swift 6 core with a SwiftUI palette and settings, plus an AppKit shell for menu bar, keyboard, and focus behavior.
- Versioned SQLite history with a transactional v1-to-v2 upgrade for optional RTF, separate preview data, and automated tests for migration, capture, paste, settings, persistence, and two-device sync convergence.
- CloudKit private-zone synchronization uses encrypted record fields, deletion markers, account-change protection, and a durable local journal.
- Universal release builds use Developer ID signing, hardened runtime, notarization, and stapling for the app and DMG.

### Credits

Flycut is a fork of [TermiT/Flycut](https://github.com/TermiT/Flycut). Original Flycut was created by General Arcade, Gennadiy Potapov, and contributors, and is based on Jumpcut by Steve Cook.

### Thank you to contributors

- [Emanuel Stadler (@emanuelst)](https://github.com/emanuelst) for the [macOS 27 menu bar fix](https://github.com/TermiT/Flycut/pull/328), merged upstream, and the [bezel rendering improvements](https://github.com/TermiT/Flycut/pull/327), adapted in [our PR #3](https://github.com/kabadabra/Flycut/pull/3).
- [Ilya Bersenev (@voidless)](https://github.com/voidless) for the [keyboard layout paste fix](https://github.com/TermiT/Flycut/pull/314) inherited from upstream.
- [Tyler Martin (@tymrtn)](https://github.com/tymrtn) for the [CloudKit startup fix](https://github.com/TermiT/Flycut/pull/322) inherited from upstream.
- [@agentheath](https://github.com/agentheath) for the [macOS 26 menu bar crash fix](https://github.com/TermiT/Flycut/pull/323) inherited from upstream.

## 2.0.0 (2026-09-24)

Flycut 2.0 is the first Emerging Dynamics release of Flycut, the free, open-source clipboard manager for macOS.

### Highlights

- Restored reliable menu bar interaction on macOS 27 with a fix from the original Flycut project.
- Updated **Open at Login** to use modern macOS Login Items on macOS 13 and later.
- Documented how to move clipping history and settings from the original Flycut or earlier builds of this fork. Flycut 2.0 has its own app identity, so it can coexist with the original.

### Reliability and polish

- Made clipboard capture more dependable: Flycut preserves the clipboard when it starts and ignores stale background reads.
- Improved clipping panel drawing by caching bezel backgrounds and releasing temporary graphics colors.

### For developers

- Build with Xcode 27 while supporting macOS 12 and later.
- Use ad hoc signing for local Debug builds and Developer ID signing plus notarization for public DMGs.
- Added QMD and Graphify setup for navigating the documentation and codebase.
- The app and helper use `com.edynamics.flycut` and `com.edynamics.flycut.helper`.

### Credits

Flycut 2.0 is a fork of [TermiT/Flycut](https://github.com/TermiT/Flycut). Original Flycut was created by General Arcade, Gennadiy Potapov, and contributors, and is based on Jumpcut by Steve Cook.

### Thank you to contributors

- [Emanuel Stadler (@emanuelst)](https://github.com/emanuelst) for the [macOS 27 menu bar fix](https://github.com/TermiT/Flycut/pull/328), merged upstream, and the [bezel rendering improvements](https://github.com/TermiT/Flycut/pull/327), adapted in [our PR #3](https://github.com/kabadabra/Flycut/pull/3).
- [Ilya Bersenev (@voidless)](https://github.com/voidless) for the [keyboard layout paste fix](https://github.com/TermiT/Flycut/pull/314) inherited from upstream.
- [Tyler Martin (@tymrtn)](https://github.com/tymrtn) for the [CloudKit startup fix](https://github.com/TermiT/Flycut/pull/322) inherited from upstream.
- [@agentheath](https://github.com/agentheath) for the [macOS 26 menu bar crash fix](https://github.com/TermiT/Flycut/pull/323) inherited from upstream.

## 1.9.7 (2026-08-04)

First release since 1.9.6 (2020). Focused on crash fixes and modern-macOS
compatibility.

- Fixed a crash on macOS 26 when copying large content from Microsoft Remote
  Desktop Connection (the menu-bar icon update ran off the main thread). (#262, #279)
- Fixed an intermittent crash when a copy was quickly followed by a paste — the
  clipboard store was being modified from a background thread while the UI read
  it. Clipboard capture is now serialized on the main thread.
- Fixed pasting on non-QWERTY keyboard layouts (Russian, Dvorak, and others),
  where the synthesized ⌘V could fail or trigger the wrong action. (#264)
- Fixed a guaranteed crash when lowering the "Save" preference below "After each
  clip" while iCloud Clippings Sync was enabled.
- Fixed the menu search field returning wrong or stale results. (#290)
- Fixed a crash when enabling iCloud sync in unsigned/local builds that lack
  iCloud entitlements; sync now degrades gracefully instead. (#321)
- The project again builds cleanly on current Xcode.

Credits: menu-search fix by @chzhc; several fixes adapted from the
actively-maintained community fork (haad/Flycut) and from contributor pull
requests (#314, #322, #323).
