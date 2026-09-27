# Flycut Evolution 1.0.0 Cloud Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Synchronize opt-in clipboard history and favorites across Macs on the same Apple Account.

**Architecture:** A testable local sync engine tracks changes and tombstones; a CloudKit adapter exchanges per-clip records in a private zone using CKSyncEngine. The existing SQLite history remains the local source for capture and paste. Account identity and engine state persist locally; the UI exposes opt-in, status, and retry.

**Tech Stack:** Swift 6, CloudKit CKSyncEngine, SQLite, XCTest, Developer ID signing.

**Spec:** `docs/superpowers/specs/2026-09-26-flycut-evolution-1.0-sync-design.md`

## Global Constraints

- Use only `iCloud.com.edynamics.flycut` private database; never upload without user opt-in.
- Keep device settings and preview app data local.
- Never commit credentials, profiles, personal clipboard contents, or graph output.
- Do not commit, push, tag, or publish until all local and live product gates pass.

## Review Focus

- Offline copy followed by reconnection uploads exactly once; Task 1 test.
- Simultaneous same-app duplicate copies converge to one row; Task 1 test.
- Deletion propagates and does not resurrect after a device returns online; Task 1 test.
- Apple Account change stops upload into the new account; Task 2 test.
- Unavailable iCloud leaves local capture and paste working; Task 3 test.

---

### Task 1: Local convergence model

**Files:** Create focused `Sources/FlycutCore/Sync/` model files and `Tests/FlycutCoreTests/CloudSyncModelTests.swift`.

**Interfaces:** immutable clip changes keyed by UUID, updated date, tombstone; deterministic merge and pending-change journal. Integrate with `HistoryService` snapshots without feeding remote changes back as local uploads.

- [ ] Write two-device tests for the first three Review Focus cases, favorite movement, capacity, and crash recovery.
- [ ] Run focused tests and observe missing behavior.
- [ ] Implement the model and durable journal, then rerun focused and full tests.

### Task 2: CloudKit transport and account guard

**Files:** Create `Sources/FlycutPlatform/CloudSync/` adapter and tests in `Tests/FlycutPlatformTests/CloudSyncTests.swift`.

**Interfaces:** private zone `FlycutEvolution`; record `Clip`; CKSyncEngine state persisted under protected application support; opt-in and account identity guard.

- [ ] Add tests for disabled state, account switch, retry, and record conversion.
- [ ] Observe expected failures, implement CKSyncEngine delegate and record handling, rerun tests.
- [ ] Validate with a signed build and synthetic data in production CloudKit.

### Task 3: App integration and consent UI

**Files:** Modify `AppCoordinator.swift`, `Settings.swift`, `SettingsView.swift`, `App/AppInfo.plist`; add macOS tests.

**Interfaces:** opt-in toggle with explicit upload notice; status, last success, Sync Now; history mutation pipeline queues local changes and applies remote snapshots through the persistence guard.

- [ ] Add app tests for opt-in, disabled state, error isolation, and persistence.
- [ ] Observe failures, implement UI and coordinator, rerun tests.

### Task 4: Developer ID delivery

**Files:** Modify `FlycutDeveloperID.entitlements`, release scripts, workflow, release docs; create Apple portal container and provisioning profile stored outside Git.

- [ ] Verify Developer ID restricted entitlement requirements against Apple documentation and exact profile contents.
- [ ] Embed profile, sign with CloudKit entitlements, notarize, staple, and verify app and DMG.
- [ ] Test with synthetic history on two Macs, including offline return and deletion.
- [ ] Regenerate Graphify, review diff, then apply the user's local testing gate before any public commit or push.
