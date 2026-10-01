# Swift preview QA

## Task 7 — 2026-09-26

Environment: macOS 27 SDK, Swift 6 language mode, Debug preview bundle `com.edynamics.flycut.preview`. Only `build/Preview/Flycut Preview.app` was launched. Installed Flycut 2.0 was not replaced, launched, configured, or inspected.

### Automated evidence

- Selection/search/collection and keyboard-command tests were written first; initial compilation failed because the new selection/command API did not exist. After implementation, all three tests passed.
- History clear/delete/move-to-top tests were written first; initial compilation failed on missing service methods. Both tests now pass.
- Full `swift test`: 77 XCTest tests, zero failures (55 core, 22 platform), including monitor launch-count preservation, stale/self-written clipboard behavior, paste cancellation and permission rechecks.
- `scripts/build-app.sh debug`: successful build and strict ad-hoc signature verification.
- `graphify update . --no-cluster`: successful local graph refresh. Graph artifacts remain ignored.

### Actual manual observations

- Initial launch attempts crashed before showing UI: using `UserDefaults(suiteName:)` with the app's own bundle identifier returned nil. Crash stack identified the initializer. Changed bundled apps to `.standard`, whose domain is already isolated by bundle identity. Relaunched successfully; verified the preview process remained running.
- Native UI tooling timed out against the status-only app. Reopening the app by its preview path now presents its history panel, allowing direct inspection.
- Reopened palette: search field focused; empty recents; Copy/Paste/Favorite/Save disabled; Accessibility Settings action visible. No clipboard text was read or logged by the development tools.
- Clicked Pause; saw Resume Capture and Capture paused. Typed only `synthetic-search` into search; saw No matching clippings. Down/Return on this empty result did not create a clipping or trigger a paste.
- Opened keyboard help. Light appearance screenshot showed search, segmented collection picker, empty state, footer buttons and complete help text without clipping.
- Opened commands menu: merge, export collection, clear recents, keyboard help, Settings, About and Quit entries were present.
- Quit through the palette menu; process check confirmed no FlycutMac preview process remained. Preview was not left monitoring the user's clipboard.

### Remaining manual gates (Task 10)

- Status-item click/popover anchoring, real hotkey presentation from another app, Escape dismissal: keyboard actions were attempted, but AX state did not provide reliable visibility evidence, so these are **not marked passed**.
- Search with synthetic captured rows, selected-row arrows/Home/End/Page Up/Down/digits, favorite/delete/export/merge and clear confirmation interaction.
- Real paste into a disposable target, prior-app restoration, unavailable/denied permission flows, sticky-palette behavior, non-QWERTY input, full-screen Space and VoiceOver.
- Dark appearance was not changed or visually verified. Light appearance alone was inspected.
- Launch clipboard preservation is supported by automated fake-board tests and the launch code path, **not a comparison of the user's real clipboard**. No live clipboard contents were inspected.
- Normal on-quit persistence is wired through delayed application termination, but end-to-end saved synthetic history relaunch and failure recovery still need manual coverage.

### Task 8 integration

`AppCoordinator.showSettings` is the settings entry-point callback. Its current dialog explicitly says the grouped editor is forthcoming. Use `settings` and `configure(_:)` to connect the settings window. The coordinator owns one hotkey service and attempts to restore the previous shortcut after registration failure; if both fail it displays a disabled message. Save modes are checked at each persist operation; `.never` never opens, restores or saves disk history during a launch in that mode. The revision below protects unread destinations during mode transitions. Choosing `.never` does not erase an existing saved database.

Settings still must supply the grouped editor, explicit remember-pause preference, icon/appearance application, save-mode transition UX, and eviction autosave. Sticky behavior and its review fix are documented in the revision section below. Migration UI remains the later migration task; this shell does not automatically import legacy data.

## Task 7 review fixes — 2026-09-26

This section supersedes the earlier sticky-paste deferral and the previously unverified populated/dark/hotkey/Escape checks.

### Saved-history protection

A new `HistoryPersistence` gate permits replacement only after the destination snapshot has been fully read and restored into the working repository. A database handle alone is no longer permission to write. Restore failure leaves disk untouched, starts capture in memory and displays a persistent warning explaining that new clippings must be exported before quitting. Quit can finish without replacing unread data. A session that started with saving disabled also cannot silently overwrite an unread destination after a setting change; Task 8 must provide explicit transition/recovery UX.

Regression used a disposable SQLite database containing a synthetic clipping and deliberately malformed migration JSON. Restore threw; the subsequent empty quit-save returned false. After removing only the malformed metadata, the original clipping was recovered intact. A separate test proves unattempted restore cannot save, while successful restore can. Both tests first failed because the persistence gate did not exist.

### Sticky paste

Sticky Paste now converts an open popover into the shared panel (or keeps the existing panel), leaves it visible across app deactivation and orders it without making it key. PasteService activates the prior destination; successful paste does not reactivate Flycut. Non-sticky Paste still dismisses. The successful OS paste path cannot be manually checked without granting Accessibility permission; permission was not changed. This is an implementation fix, with real permitted-paste verification remaining a release gate.

### Additional UI observations

QA used a separate disposable bundle/domain, `com.edynamics.flycut.preview.task7qa`, and its own Application Support directory containing only Synthetic Alpha, Beta and Gamma. Neither the normal preview defaults/data nor production defaults/data were replaced or read. Capture was paused immediately after opening each test session. The only clipboard write was the explicitly selected synthetic Beta Return action; no clipboard contents were read by development tools.

| Check | Observation |
| --- | --- |
| Populated Down navigation | Pass: highlight visibly moved from Alpha to Beta while search retained focus. |
| Return action | Pass for denied-permission flow: selected Beta was copied and palette displayed “Copied. Allow Accessibility access to paste automatically.” |
| Favorite | Pass: Beta disappeared from Recents and appeared selected in Favorites. |
| Clear confirmation | Pass: Clear All Recents opened an alert explicitly retaining Favorites; Cancel returned without removing synthetic rows. |
| Export entry point | Pass: selected favorite opened NSSavePanel with Flycut filename; cancelled without writing a file. |
| Real global shortcut | Pass: Shift-Command-V sent from a separately built disposable synthetic text app presented the QA history panel with search focused. No reopen command was used for this check. |
| Light appearance | Pass: populated rows, metadata, selection, search and footer visually legible without clipping. |
| Dark appearance | Pass: an isolated copy of the package under `/tmp/flycut-task7-dark` changed only app startup appearance to Dark Aqua. The identical views were visually inspected with synthetic rows; text/metadata/selection and controls remained legible. No system or user appearance setting was changed. An earlier app-local AppleInterfaceStyle preference did not change the appearance and was not counted as a pass. |
| Escape | Pass with temporary QA-only diagnostic: real Escape produced keyCode 53 in the owned window; immediately afterward `panel.isVisible=false` and `popover.isShown=false`. Follow-up CUA inspection re-presented the window, explaining earlier misleading screenshots. Production also handles Escape/Return/keypad Enter by hardware code and SwiftUI exit command; an added test covers empty-character Escape/keypad Enter. |
| Status-item click/anchor | **Blocked by UI tool**, not marked passed: status-only QA/preview app selection timed out without a panel; app snapshots expose only the palette window. A SystemUIServer selection also timed out. The documented CUA `listWindows` method was unavailable. No menu-bar coordinate was guessed. |

The QA app was quit through its own Quit command. Process listing confirmed no FlycutMac remained. The synthetic target was terminated, and disposable QA defaults/database were removed. The original preview state needed no restoration because it was never replaced. The temporary appearance/visibility diagnostics were confined to the isolated QA harness and are absent from the production sources.

Final verification: all 80 XCTest tests pass (58 core, 22 platform); Debug bundle and strict signature check pass. Remaining manual release checks include the blocked status-item anchor, successful authorized paste/sticky focus, full-screen Space, VoiceOver, additional populated navigation keys, actual export contents and merge interactions. Unit tests cover selection boundaries, search identities, keyboard commands, merge order and history actions.

## Sticky target tracking revision — 2026-09-26

The coordinator now listens for workspace app-activation notifications throughout its lifetime and records the latest external process, ignoring Flycut itself. This covers clicking an already-visible sticky panel after switching from app A to app B, without relying on the presentation callback. The action samples the foreground app once more, freezes the recorded target before starting its paste task, and leaves PasteService's cancellation/focus guards intact.

A deterministic synthetic regression models A → Flycut → B → mouse reactivation of Flycut, then activates C during the paste focus wait. It verifies that the request activates/checks B, never redirects to A or C, and emits no paste after B loses focus. Another test verifies that own-app and unknown-foreground events do not erase the last external target. Tests initially failed for the missing target-tracking API, then passed with the implementation.

Final verification: 82 tests pass (58 core, 24 platform); Debug bundle/strict signature pass; Graphify refreshed. No UI or clipboard interaction was needed for this revision, and process check confirms no preview or synthetic target remains running. Authorized real paste with app switching remains a Task 10 release check; the controller retains status-item click/anchoring as the explicitly tracked tooling-blocked gate.

## Task 8 — Settings, onboarding and import — 2026-09-26

This section supersedes the Task 7 placeholder-settings integration notes. Settings now has General, Shortcuts, Privacy, Appearance and About tabs, a working shortcut recorder, login/permission adapter actions, typed settings editing, pause restoration, app appearance/icon selection, save-mode recovery and automatic exports before capacity eviction. Automatic exports require a chosen folder and are disabled in save-never mode. An export failure aborts capacity eviction; a filesystem failure after an earlier export can leave an extra recoverable export file.

Production-only onboarding is gated by the exact production bundle identity and absence of a migration marker. Preview builds do not discover production profiles. Manual imports use the file picker, require source selection and explicit review, require merge/replace for a populated destination, and require memory/persistent choice for save-never sources. Source and destination fingerprints reject stale previews. Import does not enable login or adopt an old automatic export folder; those require separate Settings choices. The import window displays unsupported-setting warnings, skipped records and backup locations. The working repository is shared with memory imports, so importing into a populated memory session cannot bypass destination confirmation.

Saving can be enabled only after a full disk snapshot is readable. Existing saved data is staged separately; a modal shows saved/session counts and requires explicit Load Saved History before replacing session memory. Cancel and read failure revoke saving permission, leave disk untouched, and retain session memory. The UI instructs the user to export session clippings before accepting replacement or quitting. Retry Saved History permits recovery after the underlying database is repaired; no automatic repair or replacement of unread data is attempted.

### Automated evidence

- Import-decision tests were written before the decision API existed and initially failed to compile for the missing API; all six now pass. They cover multiple sources, explicit populated-destination choice, save-never choice, cancel without mutation, failed import/retry, production identity gating and a disposable legacy profile with synthetic recents/favorites/settings.
- Failed-preview-refresh regression initially failed for the missing invalidation API, then passed: an unsuccessful refresh cannot reuse an earlier confirmation.
- Stale-preview regression initially failed for missing fingerprint API, then passed: changing either source bytes or destination history requires new confirmation before backups or import.
- Pause/appearance settings round-trip initially failed for missing typed fields, then passed.
- Eviction tests cover recents and favorites, exact synthetic export bytes, private 0600 permissions, deletion not exporting, and failed export retaining the old clipping. The first test initially failed for the missing archive API.
- Final `swift test`: **92 XCTest tests, zero failures** (68 core, 24 platform). No compiler warnings or errors. Existing unread-destination, persistence, import backup/idempotency and hotkey/login/permission adapter regressions remain green.
- `scripts/build-app.sh debug`: successful, strict ad-hoc signature verification passes.
- `graphify update . --no-cluster`: successful; graph artifacts remain ignored.

### Actual manual observations

QA used `/tmp/Flycut Task8 QA.app`, bundle/domain `com.edynamics.flycut.preview.task8qa`. It had its own disposable preferences and Application Support directory. Capture was paused before its first launch and stayed paused across all sessions. No installed Flycut 2.0 application, production profile, private clipboard contents, permissions or login registration were changed or inspected.

- Opened all settings sections used by the flow. General and import views were inspected in light appearance; applying app-only Dark visibly updated Settings. Privacy buttons were changed to a vertical layout after the initial inspection exposed truncated labels; the corrected view was inspected successfully.
- Imported a synthetic save-never plist with two recents, one favorite, one malformed record and an unsupported iCloud flag. Preview showed counts, warnings and disabled Import until storage and confirmation were selected. Chose memory only and imported three clips. The QA history directory did **not** exist afterward.
- Imported a second synthetic, disposable 2.0-shaped profile at `Library/Preferences/com.edynamics.flycut.plist` with on-quit saving. Preview showed the existing 2+1 destination and required an explicit Merge choice. Resulting recent capacity rose to four. Completion showed source/destination backup paths. Both files had 0600 permissions. This exercised legacy profile structure; the old 2.0 executable itself was not launched.
- Synthetic palette visibly contained four recent rows and two favorites after merge. Quitting saved only the QA database. Relaunch restored those counts and Capture paused. A count-only database query independently confirmed 4 recents/2 favorites.
- Retry Saved History showed saved/session counts and explicit Cancel/Load choices. Cancel returned without replacing the session; a second attempt with Load succeeded. Unread/corrupted destination handling is covered by automated regressions, not a new manual corruption run.
- Edited comma-separated privacy lengths to `12, 24, 48` and applied successfully. Lists now retain editable raw text until Apply and reject invalid length entries.
- Initial accessible button activation did not start shortcut recording because the custom button only handled mouse-down. Changed it to target/action, rebuilt and verified accessibility activation focuses the recorder. Control–Option–X recorded and applied; reset to Shift–Command–V also applied.
- Preview quit through its own Quit command after QA. Process inspection found no FlycutMac process left running. Disposable app/domain/data were cleaned up after evidence collection.

### Task 10 implementation and release checklist

The preference implementation gaps below are resolved by the Task 10 revision. The remaining manual and signed-release gates still block publication. Import explains the intentional new palette semantics before confirmation:

- [x] `menuPreviewCount` / legacy `displayNum`: apply the configured visible menu preview count to the palette/menu presentation without discarding stored clips or hiding searchable history.
- [x] `bezelWidth`, `bezelHeight`: apply user dimensions to the palette/popover while preserving usable minimum sizes and screen bounds; expose working controls.
- [x] `bezelAlpha`: apply transparency to the palette background without fading text or reducing readability; expose a working control.
- [x] `popUpAnimation`: honor the optional presentation animation and Reduce Motion behavior; expose a working control.
- [x] `menuSelectionPastes`: specify and implement copy-versus-paste activation semantics for the new palette (including mouse and keyboard) and test prior-app restoration.
- [x] `revealPasteboardTypes`: reveal type metadata only through explicit UI, without logging clipboard contents; expose a working control.
- [x] `suppressAccessibilityAlert`: define whether this suppresses an automatic prompt while retaining the visible Copy fallback and permission links; the app now shows one informational reminder per session after denied Paste, unless suppressed; it never automatically requests OS permission.
- [ ] Real Open at Login registration/approval and permission-grant paths on a disposable signed install. QA used adapter tests and inspected buttons, without changing system permissions or login items.
- [ ] Native production onboarding with multiple discoverable profiles in a disposable user account, unread-container picker recovery, UI replace flow, actual repaired-database recovery, and an older Flycut-generated profile. Automated fixtures cover these decisions/data shapes but do not replace that release gate.
- [ ] Repeat complete palette/manual release gates from Task 7: status-item anchoring, authorized paste/sticky focus, VoiceOver, full-screen Space, non-QWERTY input, export/eviction folder interaction, and signing/notarization/downloaded-install checks.

## Task 8 review fixes — 2026-09-26

The production settings source collision is fixed: application settings use the independent `<bundle identifier>.settings.v3` preferences suite (`com.edynamics.flycut.settings.v3` for production, `com.edynamics.flycut.preview.settings.v3` for preview). There is no fallback to `.standard`, and SettingsStore requires an explicit backing store. Previous preview settings in the old app domain are not automatically adopted. New production startup/configuration/import settings writes cannot target the legacy `com.edynamics.flycut` source plist.

A new FlycutMacTests target tests the actual AppCoordinator with injected synthetic preferences, repositories, storage paths and recovery confirmation. The production-shaped test asserts the exact new domain requested, runs the startup configure and import-adoption settings writes, synchronizes the synthetic defaults and verifies the legacy source bytes are unchanged. It never opens the real production suite or source file and does not launch the AppKit shell or clipboard monitor.

Recovery now returns the restored snapshot to the settings application path. Its counts raise the pending editor proposal before configure, preventing a stale capacity of 40 from replacing the recovered capacities. The coordinator regression restores 100 recents/60 favorites from disk, changes only Never → On Quit, then captures through the coordinator's configured history service: 100 recents/60 favorites remain. A later, separate explicit capacity reduction is still accepted.

Save-never onboarding now inspects the saved database's migration metadata through a read-only SQLite connection and a metadata-only query. It does not call snapshot or restore clipping rows. Missing databases are not created; metadata read/decoding errors propagate and display an explicit warning instead of being treated as no migration. Tests verify a durable marker suppresses production onboarding while the working repository stays empty, marker inspection succeeds even when the clips table is absent, corrupted metadata throws, and an absent database creates no files.

Verification: initial coordinator test run failed for the missing injectable/application APIs. All seven focused coordinator/persistence tests pass after the fixes. Full `swift test` passes **97 XCTest tests** (70 core, 24 platform, 3 coordinator), with zero failures/warnings; Debug build/strict signature and Graphify refresh pass. No GUI app or clipboard monitoring was started for this revision. Existing Task 10 implementation/manual release gates remain open.


## Task 10 — Preference behavior and isolated QA — 2026-09-26

All previously retained-but-inactive preferences now affect the UI. Initial unfiltered rows honor `menuPreviewCount`; Show All and search expose the complete history, and keyboard selection expands the preview and scrolls the selected row into view. Stored history and search scope are unchanged. Dimensions apply to both presentation modes with a 460×400 usable minimum and screen bounds, including resizing a visible panel near a screen edge. `bezelAlpha` blends an opaque system background over native material; clipping text is never faded. Optional native presentation animation is disabled by the current Reduce Motion preference on each presentation.

Single-click selects. Double-click and the named accessible Activate Clipping action honor `menuSelectionPastes`. Return and explicit Paste always paste, preserving the design spec; Copy always copies. Both activation paths use the existing prior-app tracking and PasteService focus guards. Help, Settings and the import preview explain these semantics. The reveal-types switch shows each saved clipping's type identifier in its row, not clipboard content or diagnostic logging. Accessibility denial always leaves the copied fallback message and Settings link visible. An informational alert appears once per session unless `suppressAccessibilityAlert` is enabled; it does not request or grant OS permission. Explicit permission buttons remain available.

### Automated verification

Six new `PalettePreferencesTests` cover preview limits/search/keyboard reachability, row activation copy/paste branching with explicit Paste unchanged, suppression retaining fallback and permission access with one reminder per session, usable dimensions on normal/small screens, visible-frame correction after resizing at a screen edge, and animation opt-in/Reduce Motion. Initial runs failed because the production model/presentation APIs were missing; focused green runs and the full suite passed after implementation. Existing platform tests still verify copy emits no paste, denied permission fallback, prior-app restoration, sticky mouse target tracking, focus loss and layout-aware paste.

Final local verification: **103 XCTest tests, zero failures** (70 core, 24 platform, 9 macOS). Debug and universal arm64/x86_64 Release builds pass, with strict ad-hoc signature verification; `scripts/verify-app.sh` verifies production identity/version, both architecture slices and signature. These local bundles are not Developer ID signed or notarized. Graphify was refreshed and generated artifacts remain ignored.

### Manual observations and limits

Used only `/tmp/Flycut Task10 QA.app`, bundle `com.edynamics.flycut.preview.task10qa`, a separate settings suite and its own synthetic six-row SQLite history. Capture was paused before first launch and stayed paused. No production or normal preview settings/history were read or written. No clipboard reads/writes, paste events, permission grants, login changes or installed production app changes were performed.

- Light palette at 650×500 with native material/zero opaque backing: two initial rows and visible type/source metadata were readable. Two Down events selected and revealed Gamma beyond the initial two-row preview. Searching Zeta found the sixth clipping.
- Appearance controls displayed without clipping. Applying Dark, 520×450 dimensions, nearly opaque backing and animation changed the QA settings and palette. Dark text, metadata, selection, search and footer stayed readable. Animation timing and a real system Reduce Motion toggle were not manually measured; the decision is tested automatically.
- Hiding type metadata removed it from the palette; source metadata remained. Each row exposed a separate accessible button and named activation action after correcting SwiftUI's merged accessibility text. Full VoiceOver behavior remains a manual gate.
- Single-click Beta selected it without dismissing or activating. End selected, revealed and scrolled to Zeta; reopening retained Zeta visibly scrolled into view. Actual double-click Copy/Paste and Return paste were not invoked in this pass to avoid changing the user's clipboard; branching and prior-app behavior are covered by model/platform tests, with authorized real paste remaining a release gate.
- Privacy explanations initially clipped in a Form. Changed to a scrollable vertical layout and verified every explanation/permission button fits in dark mode. Suppression was enabled in QA and the permission link remained visible. Actual denied-paste alert presentation remains a manual gate; model behavior is tested.
- A bounded status-item check still failed: `cua.getApp("com.apple.systemuiserver")` returned `timeoutReached`; the QA app snapshot exposes windows only. No status-item coordinates were guessed. Anchoring is still unverified.
- QA quit through its own Quit command; process inspection found no `FlycutMac` remaining. Disposable app/settings/history were removed after the observations.

The unchecked Task 10 release checklist above remains binding: production onboarding in a disposable account, permission/login approval, authorized real paste/sticky focus, full-screen Space, VoiceOver, non-QWERTY input, actual export/eviction interactions, status-item anchoring, remote CI, signing/notarization, downloaded artifact verification and installation all require their documented evidence before publication.

## Release candidate verification — 2026-09-26

The final reviewed Swift commit `3094174` passed the [macOS build workflow](https://github.com/kabadabra/Flycut/actions/runs/36229688411), including the Swift tests and the legacy Flycut 2.0 build. The [manual release dry run](https://github.com/kabadabra/Flycut/actions/runs/36229695931) signed and notarized the universal Flycut 3.0 app and DMG without publishing a release.

The DMG downloaded from that dry run passed local strict code-signature verification, stapler validation, and Gatekeeper assessment. Its mounted `Flycut.app` passed `scripts/verify-app.sh` with Developer ID and notarization required; the executable contains both arm64 and x86_64 slices. This verifies the downloaded package, not just the runner's build output.

At this checkpoint, installed Flycut 2.0 was still running. A provisional owner-only backup of its preferences existed at `~/.config/flycut/backups/2026-09-26-flycut-2.0-com.edynamics.flycut.plist`. It could not serve as the final migration source because 2.0 might save more history on quit. The production upgrade recorded below supersedes this checkpoint.

## Production upgrade on macOS 27.0 — 2026-09-26

The user quit the installed Flycut 2.0 normally. Its saved `com.edynamics.flycut` preferences then contained 50 recents and no favorites. A byte-matched, owner-only final backup was made at `~/.config/flycut/backups/2026-09-26-flycut-2.0-after-quit.plist`. The downloaded notarized DMG was mounted and its `Flycut.app` copied to `~/Applications/Flycut.app` without replacing `Flycut 2.0.app`; strict Developer ID, stapler and Gatekeeper checks passed on the installed copy.

First launch offered both the current and an earlier fork profile. The current `com.edynamics.flycut` source preview reported 50 recents, zero favorites, an empty destination, resulting recent capacity 50, and On Quit saving. After explicit confirmation, the UI reported 50 imported clippings and a private 0600 source backup in Application Support. The source plist remained byte-identical to the final backup. On normal quit, read-only SQLite checks found 50 recents, a migration marker and `PRAGMA integrity_check = ok`. Relaunch restored 50 recents and did not reopen onboarding. The separate v3 settings retained On Quit saving, capacity 50 and the imported menu preview count 30. The old Open at Login preference was true; enabling the new Login Item in Settings returned “Changes applied,” and v3 settings now record it as enabled.

A synthetic copy from a disposable TextEdit document increased the in-memory count to 51, proving live capture; searching found only that test record. Paste without Accessibility returned the visible “Copied” fallback and settings link. The synthetic record was deleted through its row menu, returning the count to 50, and the temporary capacity was reset from 51 to 50. The disposable document was closed and its saved copy moved to Trash. QA notes record counts and settings without clipping text.

After another normal quit, SQLite still contained exactly 50 recents, no synthetic test row, and passed integrity check. Relaunch again showed 50 clippings without migration onboarding. Open at Login and the restored capacity 50 persisted.

From the full-screen TextEdit test Space, Shift–Command–V opened Flycut History with search focused. The full-screen Space was then exited. A real authorized paste still awaits Accessibility permission and a dedicated target check. Status-item click/anchor, VoiceOver and non-QWERTY physical layout remain unverified by the available UI tooling; do not mark those checks passed based on the hotkey or unit tests alone. The old app has not yet been removed, and the public 3.0 release remains unpublished.

## Flycut Evolution interaction pass (2026-09-26)

The earlier Flycut 3.0 row-action description above is superseded by this pass. Flycut Evolution retains technical version 3.0.0 and `com.edynamics.flycut`.

- Swift tests passed after adding activation, editable-focus, and one-time palette-size migration cases. The universal arm64/x86_64 release build passed local bundle verification with the `Flycut Evolution.app` display name.
- A disposable ad hoc signed bundle, `com.edynamics.flycut.evolutionqa`, was launched with capture paused and 15 synthetic rows in its isolated database. No production history was printed to the test log. The palette measured 460 × 700 points, showed ten compact rows at once, retained source-app labels, and showed no relative time.
- A single click selected the synthetic third row without activating it. A double-click selected and activated the fourth row. Since the disposable app has no Accessibility grant, Flycut copied the row and showed the existing one-time permission reminder. The alert was dismissed and the test app quit normally.
- The new `PasteService` tests confirm that editable focus permits one paste event, while a noneditable or changed focus leaves the clipping copied with no paste event. The disposable UI pass could not verify a real automatic paste without an Accessibility grant to the new signed app.
- Existing signed `~/Applications/Flycut.app` still runs the previous candidate. The new named bundle has not been installed or signed with Developer ID at this checkpoint.

### Reviewed signed candidate and installed cutover

Commit `fce48fc` passed both Swift and historical macOS CI jobs. The nonpublishing [Flycut Evolution release dry run](https://github.com/kabadabra/Flycut/actions/runs/36256512015) passed tests, universal app bundling, Developer ID signing, Apple notarization, stapling, Gatekeeper assessment, mounted-DMG verification, and release-note assembly. The downloaded `Flycut-Evolution.dmg` and contained `Flycut Evolution.app` passed local strict signature, staple, Gatekeeper and bundle verification; the executable contains arm64 and x86_64 slices. Manual dispatch did not publish a GitHub release.

A fresh review found that focus, clipboard and permission might change during the cross-process editable-field query. A failing regression test reproduced all three races; the service now checks again immediately before posting Cmd-V. The complete Swift suite then passed.

Before cutover, an owner-only SQLite backup was made with 50 recents and integrity `ok`. The previous `~/Applications/Flycut.app` quit normally. Its on-quit save contained one synthetic QA row and one unrelated real new row, with two oldest entries evicted by the 50-clip cap. A second owner-only backup captured this state. The synthetic row was removed, the older real entry it alone displaced was restored from the first backup, and the real clipboard text that preceded the test was restored while Flycut was closed. The resulting database has 50 recents, no synthetic QA rows, a migration marker and integrity `ok`. No private clipboard text was printed.

The signed `Flycut Evolution.app` was installed in `~/Applications` beside the previous candidate and launched explicitly by path. Its running executable path, bundle ID `com.edynamics.flycut`, version 3.0.0, Developer ID, notarization and Gatekeeper acceptance were checked. Saved preferences now hold the 460 × 700 palette dimensions and retain Open at Login on. The previous candidate and Flycut 2.0 remain available for rollback until live paste and login-item routing are checked. System Settings currently displays a Flycut login item; its target path has not been confirmed. The installed app's live palette contents were not printed or inspected to protect private history.

The installed Evolution app has not yet received Accessibility access. A live paste into another app is pending the user's at-action approval for that macOS permission; unit tests and the disposable app's Copy fallback do not replace this check.

### Row latency and macOS permission-name follow-up

The isolated QA app reproduced a deferred selection: after one synthetic-row click, the first accessibility snapshot showed no selection change, and the next did. The row had competing single- and double-tap recognizers. The updated row handles the first mouse-down immediately and reserves the second click for activation. A focused regression test verifies both event counts. In the updated isolated app, selection was visible in the first post-click snapshot; right-click actions and scrolling remained available. With optional pasteboard-type details enabled, clicking the type line immediately selected its row, dragging over the text visibly selected it, and right-clicking it opened the row actions. The command menu no longer offers the destructive Merge All Recents action. No live clipping text was inspected during this check.

System Settings > Privacy & Security > Device Control and Data Access still displayed `Flycut 2.0` for the existing permission entry, although the signed installed app has `Flycut Evolution` as its bundle name and display name. The two older app bundles sharing `com.edynamics.flycut` were moved intact from `~/Applications` to the owner-only `~/.config/flycut/backups/previous-apps-2026-09-26/` folder, and Launch Services was updated to register the Evolution app. Refreshing System Settings still showed the old permission label; updating app registration alone did not change it. Its switch was left untouched. Replacing that old permission entry with one for the signed Evolution app and checking live paste remain pending the user's Accessibility approval.

### Saved-history conflict found during installation

Before replacing the installed app, a private SQLite backup recorded 50 recents and integrity `ok`. After a normal app quit, the saved database contained only one newer recent. The one clip was absent from the 50-row backup. The original 50-row database was restored from the owner-only `~/.config/flycut/backups/2026-09-26-selection-update/history-before-quit.sqlite` while Flycut was stopped; integrity and the count were checked again. No clipping contents were printed. The exact cause of the running session's one-row state is not established. A test reproduced the destructive save when the destination database was changed after an earlier restore. `HistoryPersistence` now compares the expected saved snapshot inside the same transaction as its write and rejects a stale save, leaving the newer disk history untouched.

PR [#9](https://github.com/kabadabra/Flycut/pull/9) passed Swift and historical CI. The nonpublishing [signed release dry run](https://github.com/kabadabra/Flycut/actions/runs/36260703668) completed signing, notarization, stapling, Gatekeeper checks and mounted-DMG verification for the safeguard build. Its DMG and app passed the same checks locally. The previous signed app was archived privately; the new signed app was installed at `~/Applications/Flycut Evolution.app`. With the restored 50-row database in place, the new app launched, quit normally, retained 50 recents with integrity `ok`, and relaunched. It remains running. The macOS permission entry still says `Flycut 2.0`; updating it and checking automatic paste await the user's explicit Accessibility approval.

### Single-click and plain-text shortcut revision

The user clarified that clicking a palette row once should copy and paste into the previously focused editable field, with the existing clipboard fallback when no paste target is available. Shift–Command–V should instead paste the current clipboard as plain text immediately; the menu bar icon opens history. The local row test first failed under the old double-click rule, then passed with first-click activation and no second-click repeat. The shortcut service tests cover current text, denied Accessibility, denied or empty clipboard reads, a changed clipboard, and capture of a new copy after using the shortcut.

Review identified that an initial shortcut implementation replaced the rich source clipboard with plain text and could suppress an uncaptured copy. That implementation was removed. The revised shortcut reads the current text without writing the pasteboard and inserts it through the destination field's Accessibility selected-text attribute. Failures beep and leave a short explanation on the menu bar icon instead of opening history. A second review found the clipboard and panel issues addressed.

The macOS integration limit is still open: some editable apps may not expose a writable Accessibility selected-text attribute even when ordinary Command–V works. Unit tests inject a successful destination and cannot prove insertion into real third-party apps. The signed build at this checkpoint was the previous candidate; its replacement and live permission check are recorded below. Test the new build in representative editable fields, confirm the text is unformatted and the source clipboard is intact, then complete release review. No code has been committed or pushed to the new public Flycut-Evolution repository.

### Signed local candidate and live permission check

The revised universal build passed the complete Swift test suite (74 core, 32 platform and 12 macOS tests), release compilation, bundle verification, and strict Developer ID signature verification for team `M2L9SL9WCS`. The 50-recent production database passed SQLite integrity checks after a normal quit. The prior installed app was moved intact into the private `2026-09-26-click-shortcut` backup folder; the revised signed build was installed at `~/Applications/Flycut Evolution.app` and launched.

The user approved macOS Device Control and Data Access for Flycut Evolution and authenticated the System Settings prompt directly. Both the old Flycut bundle ID and preview bundle ID had their Accessibility decisions reset individually. Adding the installed app from its actual `~/Applications` folder restored an enabled permission entry. System Settings still labels that entry `Flycut 2.0`, but the running Evolution app's Privacy tab reports that Accessibility access is enabled. The installed bundle and running executable use `com.edynamics.flycut`; the permission label appears to be retained macOS display metadata for that bundle ID.

A harmless formatted TextEdit sample was captured and its history row was later removed through Flycut's row menu. A pointer click on that row immediately activated its copy/paste path; in the automated session Flycut reported “Copied. No editable text field is focused.” The TextEdit field did accept direct typing, but the computer-control bridge did not establish an editable previous-app target for this click. An automated Shift–Command–V key send likewise did not insert into TextEdit, while ordinary Command–V did. The app's Settings showed Shift–Command–V configured, and no shortcut failure message appeared in the palette. Physical keyboard/menu-bar testing by the user is requested to distinguish a bridge limitation from a product defect before release.

The sample history row was deleted, leaving 49 visible recents because capture at the 50-item cap evicted the oldest saved entry. The pre-test owner-only SQLite backup preserves all 50 originals. After the manual test, compare record identities and restore the evicted entry without overwriting any genuine new clippings. The new candidate remains uncommitted and unpublished until this and the live paste gate pass.

## Flycut Evolution 1.0.0 local release check (2026-09-26)

This section supersedes the older 3.0.0 and pending-paste checkpoints above. The production history contains 51 recents, the SQLite integrity check passed, and an owner-only backup of the database, settings, and previous app was made before installing 1.0.0. Existing same-app duplicate recents are normalized with a private backup, and future matching copies refresh their existing row. The duplicate-removal preference is gone.

The complete Swift suite passed: 85 core, 42 platform, and 12 macOS tests, with no failures. A universal arm64/x86_64 release app was signed with the current Emerging Dynamics Developer ID certificate and a matching CloudKit Developer ID profile. Apple accepted its notarization, the ticket was stapled, and strict signature, profile, version, entitlement, Gatekeeper, and bundle checks passed on the installed app at `~/Applications/Flycut Evolution.app`.

The user physically tested the installed app with harmless text in an editable field and confirmed that both Shift–Command–V plain-text paste and single-click clipping paste succeeded. This resolves the earlier automated-input uncertainty for those two interactions. Broader app-specific paste compatibility and non-QWERTY layouts have not been physically checked in this release pass.

The CloudKit Production schema has the `FlycutClip` record type with an encrypted `payload` field and `payloadAsset` field. A separate signed synthetic test created, fetched, and deleted a record in a temporary private CloudKit zone without reading or uploading real history. With the user's explicit consent, Cloud Sync was enabled in the installed app. Its owner-only sync journal reports 51 live entries, zero tombstones, zero pending changes, 51 server system-field confirmations, and a successful sync timestamp. The settings panel displayed a last-synced time. Clipping contents and account identifiers were not printed in QA output. A live two-Mac convergence check is still required before publication.

A temporary transfer image, `build/Flycut-Evolution-1.0.0-test.dmg`, was made from that installed app. Apple accepted the disk image for notarization; its ticket was stapled, Gatekeeper accepted the image, and the mounted app passed the strict version, profile, signature, entitlement, architecture, and notarization verifier. This image is for the second-Mac test and has not been published.

### Second-Mac capacity safeguard

The first transfer image opened on the user's second Mac with empty history. Cloud Sync remained off there. Review found that receiving 51 clippings into a Mac with the default 40-item limit would cause its next copy to evict 12 older clippings. A regression test reproduced the loss. The coordinator now raises the receiving Mac's recent and favorite limits to the synced collection sizes before capture can resume; the focused test passed. The complete suite then passed with 85 core, 42 platform, and 13 macOS tests and no failures.

The corrected 1.0.0 app passed a universal release build, matching Developer ID certificate/profile checks, Apple notarization, stapling, and strict installed-app verification. A fresh owner-only backup of 51 recents, journal, and preceding app was made before updating this Mac; SQLite integrity remained `ok` after relaunch and the journal still had 51 confirmed, zero pending entries. The corrected `build/Flycut-Evolution-1.0.0-sync-test.dmg` was separately notarized and stapled, accepted by Gatekeeper, and its mounted app passed the strict verifier. The user is replacing the initial test build on the second Mac before enabling Cloud Sync. Neither image is published.

### Two-Mac sync and fresh-install follow-up

The corrected image opened on the second Mac. After opting in there, the user confirmed that the first Mac's saved history appeared. A harmless TextEdit clipping copied on the second Mac later arrived on the first, proving the inbound path. Before the test, the second Mac's recent limit was raised to 100 to avoid displacing an older real clipping.

On the first Mac, moving that test clipping to Favorites stayed pending. Investigation found that incoming CloudKit records were merged without retaining their server system fields, so an edit from the receiving Mac had no change tag. A focused test was added, failed before implementation, and passed after downloaded records and conflict responses were made to save their system fields. The full suite passed with 85 core, 43 platform, and 14 macOS tests. The updated app was signed, notarized, stapled, and installed after an owner-only SQLite/journal/app backup. On relaunch, the favorite edit was acknowledged by CloudKit, its server version is saved locally, and the journal reports zero pending changes. The second Mac's visible confirmation of that favorite remains a manual gate.

The second Mac also displayed an empty legacy-import chooser at first launch. The startup decision checked only for a missing migration marker. It now also requires at least one readable discovered legacy source; manual file selection in Settings remains available. A focused test covers an empty home and a newly present readable source. The corrected app is installed on the first Mac; the second Mac still needs the final image to verify that fresh-start behavior in the real UI.

### Compact rows and formatted clipping candidate (2026-09-27)

The palette now reduces each clipping's display text to one plain-text line, collapsing formatting whitespace and showing an ellipsis at the configured character limit or available width. New text copies with valid bounded RTF retain that representation for a full hover preview, normal formatted paste, and Cloud Sync. An Aa action on formatted rows pastes that particular clipping as plain text; Shift–Command–V continues to paste the current clipboard as plain text. Older clips remain plain text. The local SQLite schema upgrades transactionally from v1 to v2 with nullable RTF storage; same-app recapture and favorites preserve the latest formatting.

The new focused tests watched the absent behavior fail before implementation. The final full local suite passed: 92 core, 49 platform, and 19 macOS tests (160 total, zero failures). A debug preview displayed the one-line label and separate Aa action. A disposable, two-line rich TextEdit copy was captured by the installed app: the database contained one non-null RTF payload. UI automation could not reliably return focus to a TextEdit paste destination, so the user checked the installed app directly: the hover preview showed both lines with the first bold, single-click pasted with bold preserved, and Aa pasted without bold. All three passed.

Before upgrading the first Mac, online and after-quit owner-only SQLite backups were made in `~/Library/Application Support/com.edynamics.flycut/History Backups/`, both integrity `ok`, schema v1, 59 rows. The preceding app was retained in `~/.config/flycut/backups/previous-apps-2026-09-27/`. The new universal 1.0.0 app and `build/Flycut-Evolution-1.0.0-rich-preview-rc.dmg` were signed with the matching Developer ID/CloudKit profile, accepted by Apple notarization, stapled, accepted by Gatekeeper, and verified inside the mounted DMG. After local installation, the production database has schema v2 and integrity `ok`; Cloud Sync remains connected with zero pending changes. The synthetic formatted copy was uploaded and acknowledged. The DMG is a test candidate and has not been published.

The user installed this candidate on the second Mac and confirmed that no empty legacy-import chooser appeared, the earlier synced favorite was present, and the synthetic formatted clipping showed its Aa action and styled hover preview. In a rich-text TextEdit document on that Mac, single-click pasted the bold first line and Aa pasted it plain. The user then deleted that synthetic clipping there. On this Mac, the formatted source entry disappeared, the private sync journal had zero pending changes and a recent successful sync, and the SQLite history retained only two separate plain-text captures of the same synthetic text attributed to Universal Control and Screen Sharing. No real clipping contents were printed.

### Hover interaction follow-up (2026-09-27)

The user found that an open hover preview could consume the first click back into its row, and requested immediate hover highlighting plus an Appearance toggle. A preview presenter now uses application-controlled AppKit popover dismissal, leaving the row's first mouse-down available for paste. Hover highlighting is visual and does not change keyboard selection; the toggle defaults on, persists in the isolated settings domain, and closes an open preview when turned off. Three focused tests first failed for the absent behavior and then passed. An isolated preview app showed the Appearance toggle on, saved it off, and restored it on. The clean Evolution tree passed all 163 tests and produced a universal, Developer ID signed `build/Flycut-Evolution-1.0.0-final.dmg`; Apple notarized the app and image, both were stapled and accepted by Gatekeeper, and the mounted app passed the strict release verifier. The user's direct one-click and hover-toggle checks remain release gates. Do not commit, push, tag, or publish before those checks.

The user subsequently reported that the hover behavior was working well. The remaining visual concern was the alternate menu bar icon, addressed below.

### Menu bar icon clarity (2026-09-27)

The user reported that the alternate Appearance choices, especially Scissors, looked soft in the menu bar. The menu bar uses native SF Symbols rather than `flycut.icns`, so the Dock icon asset was left unchanged. An explicit 13-point semibold button configuration and no scaling passed a focused test and the 164-test suite, but the user reported the installed Scissors icon still looked soft. A second candidate drew Scissors and Text as AppKit vectors; the 165-test suite passed, but the user reported that the scissors looked wrong or too large and supplied a screenshot showing heavy loops beside other menu bar icons. The final candidate restores the familiar native symbols, applies the size and weight directly to each `NSImage` as well as the button, and uses a smaller 11-point Scissors rendering. The focused test failed before the change and passed after it; all 164 tests pass. The signed, notarized app was installed on the daily Mac with 64 clippings preserved, and the user confirmed that Scissors now looks sharp and appropriately sized beside neighboring menu bar icons.

The 1.0.0 installer was signed and notarized separately, stapled, accepted by Gatekeeper, mounted read-only, and its contained universal app passed the strict Developer ID, CloudKit profile, notarization, and version checks. The installed app is the same signed build used to make this installer.

The first GitHub Actions dry run built on a separate macOS 27 runner and exposed a test-only assumption: that runner's SF Symbol catalog gives Clipboard and Text slightly different intrinsic widths, while their explicitly configured point sizes and weights match. The focused test now checks compact bounds instead of exact pixel geometry. The complete local suite passed again with 164 tests and zero failures; the runner must pass this revised test before tagging the release.

### Version 1.0.1 local checks (2026-09-28)

The local 1.0.1 candidate includes a Teams compose-focus fallback, an anchored menu bar palette, scroll reset to the newest clip, a right-click Copy to Top action, and Universal Control duplicate consolidation. The user confirmed that pasting into the Microsoft Teams chat now works. The Teams focus shortcut was separately observed to move focus from a chat message to its composer without entering text. Automated tests cover the focus fallback, history normalization, and row action; the full Swift suite passed (170 tests, zero failures).

The universal app was signed with the Developer ID and CloudKit profile, verified, backed up, and installed at `~/Applications/Flycut Evolution.app`. The running executable path and saved SQLite integrity were checked. This local build has not been notarized; the GitHub release workflow must sign, notarize, staple, and verify the app and DMG before publication. The user authorized commit, push, and release after confirming Teams paste.

## Flycut Evolution 1.0.2 release verification (2026-10-01)

The user authorized committing all completed changes and publishing 1.0.2. The production release uses updater build 10006, after local test builds 10003–10005. The user confirmed the revised Teams plain-text paste works. Independent reviews covered keyboard/search/favorites, capture privacy/images/updates, capacity safeguards, and file previews; actionable findings were corrected before release.

The full current Swift suite contains 263 tests: 129 core, 85 platform, and 49 macOS. It covers fixed capacity enforcement, backup/eviction rollback with PNGs, unresolved sync download status, Finder file/image capture, file-path persistence and deduplication, file paste, and missing-file clipboard preservation. Signed-feed fixtures check key matching, enclosure signatures, and tamper rejection. Final release CI and downloaded-DMG verification are recorded below once complete.

On the daily Mac, the local signed 10005 app captured a harmless Finder image fixture with its pixels, filename, and full path. Its palette displayed the captured thumbnail, SQLite upgraded to schema 5, the existing favorite digest remained unchanged, and configured capacities remained fixed. The preview's native mouse hover/text-selection round trip could not be automated because the UI tool reports no window for the popover; user interaction remains a manual check. Live two-Mac image sync and the first public updater installation remain unverified integration checks; codec and signing tests do not establish those results.
