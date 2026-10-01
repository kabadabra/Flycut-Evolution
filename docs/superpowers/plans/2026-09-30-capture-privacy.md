# Capture Privacy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task using the preserved native execution method. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add application exclusions, Ignore Next Copy, and timed pause before any clipboard payload read.

**Architecture:** Pure capture decisions live in Core; ClipboardMonitor owns observation and session state. Mac UI sends commands to that single state owner and displays its state.

**Tech Stack:** Swift 6, AppKit, SwiftUI, XCTest, macOS 14 or later.

**Spec:** [Capture privacy](../specs/2026-09-30-capture-privacy-design.md).

## Global Constraints

- Keep all new work uncommitted; do not push or publish.
- Preserve the existing feature worktree and version 1.0.2 testing build.
- Exclusions use bundle identifiers and stay local; existing history is not removed.
- Timed pauses are 5 minutes, 15 minutes, or 1 hour and session-only.
- Observe source attribution honestly; never promise perfect originating-app detection.
- No clipboard content in logs; no competitor references in documentation or future commits.

## Review Focus

- Clipboard changes between paused polls must not be imported at expiry: Task 2.
- A stale self-write counter must not suppress a subsequent external change: Task 2.
- An excluded application's first denied read must never trigger format fallback: Task 1.
- Invalid application bundles must not partially alter the exclusion list: Task 3.
- Preference changes while paused must not reset a timed deadline: Task 3.

---

### Task 1: Pre-read capture policy and source identity

**Files:** Modify `Sources/FlycutCore/Capture/CapturePolicy.swift`, `Sources/FlycutCore/Settings/Settings.swift`, `Sources/FlycutPlatform/Clipboard/ClipboardMonitor.swift`; tests in `Tests/FlycutCoreTests/CapturePolicyTests.swift`, `SettingsTests.swift`, and `Tests/FlycutPlatformTests/ClipboardMonitorTests.swift`.

**Interfaces:** Add `ExcludedApplication: Codable, Equatable, Sendable` with `bundleIdentifier: String` and `displayName: String`; `FlycutSettings.excludedApplications: [ExcludedApplication] = []`; optional `ClipboardSource.bundleIdentifier` with a default nil initializer argument. Add `CapturePolicy.acceptsBeforeRead(advertisedTypes: [String], sourceBundleIdentifier: String?, settings: FlycutSettings) -> Bool`. Existing `accepts(text:advertisedTypes:settings:)` retains content checks and delegates advertised-type checks.

- [ ] Write `testExcludedAndSensitiveObservationsReadNoPayload`: mock text/RTF read counts equal zero for excluded identifiers and blocked advertised types; no clip callback. Write `testUnknownSourceStillUsesSensitiveTypeGate` and settings round-trip/deduplication tests.
- [ ] Run `swift test --filter 'CapturePolicyTests|SettingsTests|ClipboardMonitorTests'`; confirm new assertions fail before implementation.
- [ ] Implement types/settings validation and the pre-read gate. Obtain source once before reads and reuse it in the clip. Apply the same source/count snapshot through the post-read counter check. Preserve denied-access feedback on allowed reads.
- [ ] Run the same command; require every selected test to pass and existing RTF validation unchanged.
- [ ] Run `git diff --check`; leave changes uncommitted.

### Task 2: One-shot ignore and pause lifecycle

**Files:** Create `Sources/FlycutCore/Capture/CaptureSessionState.swift`, `Tests/FlycutCoreTests/CaptureSessionStateTests.swift`; modify `ClipboardMonitor.swift` and its platform tests.

**Interfaces:** `CapturePause: Equatable, Sendable` has `.running`, `.manual`, `.until(Date)`. `CaptureSessionState` exposes `pause`, `ignoresNextCopy`, `setPause(_ pause: CapturePause)`, `ignoreNextCopy()`, `cancelIgnore()`, `resume()`, `expire(at: Date) -> Bool`, and `consumeExternalChange() -> Bool` (true means skip). Monitor forwards commands with `pause(for duration: TimeInterval?)`, `resumeCapture()`, `ignoreNextCopy()`, `cancelIgnoreNextCopy()`, and exposes a read-only `captureState`. Preserve the legacy isPaused setter as a manual-pause adapter.

- [ ] Write tests asserting expiry at exactly 300/900/3600 seconds, no expiration before deadline, own writes preserve pending ignore, unsupported external changes consume once, manual resume cancels a deadline, and repeated ignore requests remain a single pending skip.
- [ ] Extend monitor tests: `testExpirySkipsCopyBetweenPausedPolls`, `testSelfWriteThenExternalCopy`, and `testExpiryCheckedWhenClipboardCounterUnchanged`. Assert zero replayed clips and the next fresh copy captures once.
- [ ] Run `swift test --filter 'CaptureSessionStateTests|ClipboardMonitorTests'`; confirm failures.
- [ ] Implement session state and poll order: expire and advance observed count on resume, observe changes, suppress self-write, consume ignore for external changes, then pause/privacy gates and reads. Add a main-actor state-change callback for UI updates. Pause expiry must be checked even with an unchanged clipboard counter.
- [ ] Run selected tests and `git diff --check`; keep changes uncommitted.

### Task 3: Privacy settings and menu controls

**Files:** Create `Sources/FlycutPlatform/Clipboard/ExcludedApplicationPicker.swift`, `Sources/FlycutMac/Settings/PrivacySettingsView.swift`, `Tests/FlycutMacTests/CapturePrivacyControlsTests.swift`; modify `AppCoordinator.swift`, `Palette/PaletteModel.swift`, `Palette/PaletteView.swift`, and `Settings/SettingsView.swift`.

**Interfaces:** Picker returns `ExcludedApplication?` through `@MainActor func chooseApplication() throws -> ExcludedApplication?`; cancellation returns nil. Validate .app bundles and nonempty Bundle.bundleIdentifier. Add coordinator actions `pauseCapture(for: TimeInterval?)`, `resumeCapture()`, `ignoreNextCopy()`, `cancelIgnoreNextCopy()`. Settings view accepts bindings to excluded applications; palette receives CaptureSessionState and command closures.

- [ ] Write control tests asserting menu durations `[300, 900, 3600]`, Ignore Next Copy pending/cancel feedback, exclusion removal leaves history unchanged, invalid bundle errors leave settings untouched, and unrelated settings edits preserve the existing timed deadline.
- [ ] Run `swift test --filter CapturePrivacyControlsTests`; confirm failures.
- [ ] Implement list/picker/error feedback and menu state. Persist only manual pause according to existing remember-pause preferences. Forward settings changes without rebuilding session state. Display a concise observed-app attribution explanation in Privacy settings.
- [ ] Run selected tests, then `swift test`; require all tests pass. Update CHANGELOG.md and docs/DEVELOPING.md with implementation and manual checks.
- [ ] Run `graphify update . --no-cluster` and `git diff --check`; manually verify exclusion, one-shot ignore, expiry, and immediate plain-text paste in two local apps. Keep uncommitted; continue to the image plan.
