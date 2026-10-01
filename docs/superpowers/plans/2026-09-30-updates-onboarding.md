# Signed Updates and Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task using the preserved native execution method. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add opt-in signed updates and a dismissible setup walkthrough, then install the completed local build for user testing.

**Architecture:** A narrow UpdateService wraps Sparkle; a pure setup state model drives a separate Mac window. Existing shell/coordinator handle actions while scripts embed/sign framework components and generate signed release assets without publishing.

**Tech Stack:** Swift 6, SwiftUI/AppKit, Sparkle 2.10.0, Swift Package Manager, Developer ID, XCTest, bash/Python build verification; macOS 14 or later.

**Spec:** [Updates and onboarding](../specs/2026-09-30-updates-onboarding-design.md).

## Global Constraints

- Complete privacy and image plans first. Keep work uncommitted, with no push, feed publication, or release publication.
- Automatic update checks and image sync default off; installation remains user-approved.
- Production feed: https://github.com/kabadabra/Flycut-Evolution/releases/latest/download/appcast.xml.
- Separate monotonic CFBundleVersion from marketing version; retain 1.0.2 for this local testing build.
- Public key only in source; private update keys stay in Keychain or CI secrets and are never logged.
- Keep Developer ID signing, hardened runtime, notarization, and supported arm64/x86_64 architectures.
- Fixture update tests use separate temporary bundles and never replace the user's installed app.

## Review Focus

- An unpublished feed must say unavailable rather than up to date: Task 1.
- Existing preferences must not trigger first-run setup or implicit update consent: Task 3.
- Framework helper symlinks/executable modes must survive bundling: Task 2.
- Missing update signing credentials must fail before publishing an incomplete release: Task 4.
- Permission status changing in System Settings must refresh without repeated prompts: Task 3.

---

### Task 1: Updater service and opt-in controls

**Files:** Modify Package.swift and generated Package.resolved; create `Sources/FlycutPlatform/Updates/UpdateService.swift`, `Tests/FlycutPlatformTests/UpdateServiceTests.swift`; modify Core Settings.swift and Mac SettingsView/PaletteView/AppCoordinator.swift; modify App/AppInfo.plist.

**Interfaces:** `@MainActor UpdateClient` provides `start: () throws -> Void`, `setAutomaticChecks: (Bool) -> Void`, `check: () -> Void`, `canCheck: () -> Bool`. `UpdateService` owns `configure(automaticChecks: Bool)`, `start()`, `checkForUpdates()`, and readable availability/error status. System adapter owns SPUStandardUpdaterController with startingUpdater false. Add `FlycutSettings.automaticUpdateChecks = false` and public-key/feed configuration validation before starting.

- [ ] Write fake-client tests asserting auto-check false before start, persisted opt-in forwarded, install-download automation disabled, missing public key gives a clear not-configured state, manual checks routed once, and unavailable/network/signature errors cannot become up-to-date status.
- [ ] Run `swift test --filter UpdateServiceTests`; confirm failures before implementation.
- [ ] Pin the official Sparkle package exactly to 2.10.0 and add its product to Platform. Implement adapter/delegate reporting with optional checks UI. Add SUFeedURL, SUVerifyUpdateBeforeExtraction=true, SURequireSignedFeed=true, and disable automatic downloads. Public key must be a real key from the dedicated generation step, never a placeholder. Until configured, manual checks clearly report setup incomplete.
- [ ] Run selected tests and settings round-trip tests. Dependency reference: [official Sparkle 2.10.0 release](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0).
- [ ] Keep uncommitted.

### Task 2: Universal bundling and nested signing

**Files:** Modify scripts/build-app.sh, sign-developer-id.sh, verify-app.sh, App/AppInfo.plist; create `scripts/tests/test-updater-bundle.sh`; update acknowledgements.txt and RELEASE_SETUP.md.

**Interfaces:** Build accepts positive integer `BUILD_NUMBER` independently of VERSION. Use build 10003 for this local 1.0.2 test bundle; reserve future production build numbers greater than 10003. Test Sparkle comparison against the legacy CFBundleVersion "1.0.2" and build 10002, asserting 10003 compares newer. Add the explicit build number to AppInfo.plist; release CI validates a supplied build number and cannot derive it solely from the marketing version. Embed the resolved binary framework at Contents/Frameworks/Sparkle.framework and link with @executable_path/../Frameworks. Signing traverses helpers/framework inside out, using component-appropriate entitlements rather than the main app's CloudKit entitlement file.

- [ ] Add shell fixture checks: invalid build numbers fail, marketing/build values differ, linked Sparkle load path exists, both CPU slices exist for app and framework/helper components, symlinks remain symlinks, helpers remain executable, and signature verification covers every nested component.
- [ ] Run `bash scripts/tests/test-updater-bundle.sh`; require a demonstrated missing-framework/rpath failure before bundling changes.
- [ ] Implement framework discovery through resolved SwiftPM artifact paths and copy with ditto; never rely on a hardcoded host-specific build path. Ad-hoc sign nested components for preview builds and Developer ID sign distribution components inside out. Preserve hardened runtime without disabling production library validation. Add required dependency acknowledgment and build-number guidance.
- [ ] Run fixture checks, `scripts/build-app.sh release`, then `scripts/verify-app.sh 'build/Export/Flycut Evolution.app'`; require both architectures and valid nested signatures.
- [ ] Keep uncommitted.

### Task 3: Setup state and walkthrough window

**Files:** Create `Sources/FlycutCore/Setup/SetupState.swift`, `Sources/FlycutMac/Setup/SetupModel.swift`, SetupView.swift, `Tests/FlycutCoreTests/SetupStateTests.swift`, `Tests/FlycutMacTests/SetupModelTests.swift`; modify SettingsStore.swift, AppCoordinator.swift, PermissionView.swift, SettingsView.swift, PaletteView.swift.

**Interfaces:** `SetupState: Codable, Equatable, Sendable` exposes completed/dismissed state and step enum privacy/shortcuts/permissions/paste/updates. `SettingsStore` adds setup load/save methods plus `isEstablishedInstallation` detection before load writes migration markers. `@MainActor SetupModel` exposes `next()`, `back()`, `dismiss()`, `finish()`, `refreshPermission()`, `requestPermission()`, `copySample()`, and `confirmPaste(_ succeeded: Bool)`; constructor injects preference bindings, permission client, and clipboard writer. Coordinator `showSetup()` reuses a single window.

- [ ] Write tests: fresh installation shows once; established preferences or history suppress automatic setup; dismissal stays dismissed; explicit reopen works; default update/image-sync consent false; permission refresh after activation never requests permission; only an explicit action requests permission or copies sample; self-reported paste result is not inferred from synthetic events.
- [ ] Run `swift test --filter 'SetupStateTests|SetupModelTests'`; confirm failures.
- [ ] Implement steps and completion persistence. Explain observed-app exclusions, image/OCR settings, Cmd+Option+V history, Cmd+Shift+V immediate plain paste, permission status/System Settings action, and optional updates. Use harmless sample text and user-directed external paste; do not send messages or create external documents. Keep setup separate from the palette so history selection/paste focus remains stable.
- [ ] Run selected tests and AppCoordinatorTests; manually verify dismiss/reopen and live permission refresh with an isolated preview preferences suite.
- [ ] Keep uncommitted.

### Task 4: Signed feed generation and isolated updater fixtures

**Files:** Create scripts/generate-update-keys.sh, scripts/generate-appcast.sh, scripts/tests/test-update-feed.sh; modify .github/workflows/release.yml, RELEASE_SETUP.md, docs/DEVELOPING.md and .gitignore.

**Interfaces:** Key-generation script invokes the pinned Sparkle generate_keys tool, stores the private key in Keychain, and outputs only the public key. Appcast script accepts a notarized artifact directory plus the release download prefix, obtains credentials without logging them, and invokes the pinned generate_appcast/signing tools. Expose SPARKLE_PRIVATE_KEY only as an explicit CI secret through supported tool input, not shell command substitution or console output. Output includes appcast.xml, signed archive, and signed release notes. Create the archive after stapling the app; do not reuse the pre-stapling notarization ZIP as an update artifact.

- [ ] Write fixture checks: missing signing key/artifact fails before generating a distributable feed; feed and enclosure are signed; modified bytes and modified feed fail verification; release version/build match bundled metadata; local URLs are prohibited in production outputs. Use ephemeral fixture keys isolated from the real update key.
- [ ] Run `bash scripts/tests/test-update-feed.sh`; demonstrate failure before tooling implementation.
- [ ] Implement scripts and provision a dedicated real update key in Keychain with public-key-only plist entry. CI requires update key for both release and notarized dry run, preserves existing tag-only publication rule, and uploads the appcast/notes/archive with future releases. Never execute publishing workflows now. Ignore fixture artifacts/private files.
- [ ] Run fixture checks and an updater round trip between two isolated temporary app bundles with a local fixture feed and explicit installation choice; verify invalid signatures leave the old fixture app intact. If OS UI prevents automation, retain a repeatable manual fixture procedure and report that limitation without claiming verified installation.
- [ ] Keep uncommitted. References: [Sparkle publishing](https://sparkle-project.org/documentation/publishing/) and [integration](https://sparkle-project.org/documentation/).

### Task 5: Whole-branch review, local installation, and handoff

**Files:** Modify CHANGELOG.md, readme.md, docs/DEVELOPING.md; produce ignored build/verification artifacts and backups only.

**Interfaces:** Preserve `/Users/chris/Applications/Flycut Evolution.app` identity, Developer ID team, provision profile, and existing preferences/history. Install only after verification. No automatic production update check or publication during validation.

- [ ] Run full `swift test` and `git diff --check`; require all tests pass. Exercise privacy, image/OCR, favorites/search, updater consent, and setup together with a sanitized preview app. Scan documentation for prohibited competitor references and secrets.
- [ ] Obtain one independent whole-branch review under the native execution method, focused on migration/data loss, privacy-before-read, async OCR cancellation, sync filtering, and update signing. Fix substantive findings and rerun the affected tests; rerun the full suite if production code changed.
- [ ] Build universal release, Developer ID sign with the installed profile, and run REQUIRE_DEVELOPER_ID=1 verification. Inspect app and nested signatures; verify production hardened runtime and both CPU architectures. State notarization/public-update checks not performed unless actually completed.
- [ ] Back up installed app and live SQLite database using SQLite's backup API before replacing. Preserve private file permissions. Quit the running instance, copy verified bundle to the current install path, restart, and compare installed executable/framework hashes to verified export. Confirm existing text/favorites restore and no surprise automatic consent.
- [ ] Run `graphify update . --no-cluster` and final diff/status check. Report completed features, exact local version/build, test results, review fixes, and specific user checks (Teams plain/image paste, real global hotkeys, second-Mac image sync). Clearly identify feed/key/CI prerequisites for an eventual public release. Leave all new changes uncommitted and unpushed.
