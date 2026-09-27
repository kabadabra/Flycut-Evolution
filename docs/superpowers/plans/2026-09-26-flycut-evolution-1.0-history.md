# Flycut Evolution 1.0.0 History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the initial 1.0.0 release with one recent row per exact text and source app.

**Architecture:** `HistoryService` owns the deduplication rule and performs each capture in one repository transaction. Settings no longer carry an optional duplicate flag. A startup cleanup collapses pre-existing duplicates after backup and restore, preserving the newest row and favorites.

**Tech Stack:** Swift 6, SwiftPM, SQLite, XCTest, AppKit.

**Spec:** `docs/superpowers/specs/2026-09-26-flycut-evolution-1.0-sync-design.md`

## Global Constraints

- Version: `1.0.0`.
- Minimum macOS: `14.0` once Cloud Sync joins this release.
- Do not commit, push, tag, or publish until local product gates pass.
- Keep the original-project credit and Emerging Dynamics name.

## Review Focus

- Repeated text with different source apps remains two rows; test in Task 1.
- Repeated text already at the top refreshes its capture date; test in Task 1.
- Repeated text reuses the original UUID so CloudKit does not create a second record; test in Task 1.
- Existing duplicate rows collapse without touching favorites; test in Task 2.
- A repeated copy at capacity does not evict an unrelated clip; test in Task 1.

---

### Task 1: Capture behavior

**Files:** Modify `Sources/FlycutCore/History/HistoryService.swift`; test `Tests/FlycutCoreTests/HistoryRepositoryTests.swift`.

**Interfaces:** `capture(_ clip: Clip) async throws -> HistorySnapshot`; private key is exact `(text, sourceAppName ?? sourceBundleURL ?? "")` with distinct source-name and bundle-URL namespaces.

- [ ] Add tests for the five Review Focus cases.
- [ ] Run `swift test --filter HistoryRepositoryTests` and observe expected failures.
- [ ] Implement capture: find newest match, retain its UUID, replace metadata/date with incoming values, remove all matches, insert at zero, then apply capacity.
- [ ] Run focused tests and full `swift test`.

### Task 2: Existing history cleanup and settings

**Files:** Modify `HistoryService.swift`, `Settings.swift`, `LegacySettingsMapper.swift`, `AppCoordinator.swift`, `SettingsView.swift`, `MigrationView.swift`; tests in `HistoryRepositoryTests.swift`, `SettingsTests.swift`, `MigrationViewModelTests.swift`.

**Interfaces:** `normalizeRecents() async throws -> HistorySnapshot`; called after persistent restore and migration; no `removeDuplicates` field remains.

- [ ] Add tests for cleanup, settings persistence, and migration.
- [ ] Run focused tests and observe expected failures.
- [ ] Implement transactional cleanup and remove the duplicate toggle and legacy flag.
- [ ] Run focused tests and full `swift test`.

### Task 3: Release identity

**Files:** Modify `Clip.swift`, `AppInfo.plist`, `Package.swift`, `scripts/build-app.sh`, `scripts/verify-app.sh`, `CHANGELOG.md`, `readme.md`, `RELEASE_SETUP.md`, `PackageSmokeTests.swift`.

**Interfaces:** `FlycutVersion.current == "1.0.0"`, bundle version `1.0.0`, minimum macOS `14.0`.

- [ ] Change version assertion and check it fails.
- [ ] Update version and target values, product documentation, and user-facing release notes.
- [ ] Run `swift test`; build both CPU slices; verify signed bundle and metadata.

### Task 4: Product verification

**Files:** Update `docs/QA-swift.md` only for observed results.

- [ ] Back up the private production database before installing the new bundle.
- [ ] Install the signed build and verify real same-app duplicate copies, one-click paste, Shift–Command–V, relaunch persistence, and unaffected favorites.
- [ ] Regenerate Graphify with `graphify update . --no-cluster` and inspect final diff.
