# Keyboard access, smarter search, and reusable favorites implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Deliver separate keyboard history access, responsive unified search, and named/editable/reorderable favorites with stable palette shortcuts.

**Architecture:** Extend the existing core history model and transactional SQLite repository. Put matching and ranges in a pure search component, asynchronous orchestration in the palette model, and independent global shortcut routing in the platform layer. Keep the tested paste service intact.

**Tech Stack:** Swift 6, SwiftUI/AppKit, SQLite, Carbon, existing CloudKit transport.

**Spec:** [Approved design](../specs/2026-09-30-keyboard-search-favorites-design.md)

## Global Constraints

- macOS 14 or later; native SwiftUI/AppKit, Swift package targets, SQLite, and existing CloudKit transport.
- Preserve the tested Command–Shift–V plain-text paste path and outside-click dismissal.
- Keep version 1.0.2 for this local test build; release numbering can be changed before publication.
- No new commits, pushes, or release publication without further user instruction. The existing reliability fixes have already been committed separately.
- Product documentation and commit messages describe Flycut features without naming other clipboard applications. Reference source stays outside the repository. Implement original code; copied source would require its applicable license notices.
- No new runtime dependencies, telemetry, image capture, OCR, source-app filters, or automatic updater in this scope.

## Review Focus

- A favorite hidden by search can be activated by its assigned shortcut without changing the search or accidentally pasting a visible row.
- Accent folding, composed characters, and emoji yield valid highlight boundaries in the original text.
- A deleted favorite or failed durable save does not close the editor with a misleading successful-save state.
- Two devices assigning the same shortcut converge to an explicit conflict; neither favorite is silently chosen.
- Adding a second global shortcut cannot cause both actions to run because Carbon handlers share an identifier.

## Task 1: Favorite metadata and safe storage upgrade

**Files:** Modify `Sources/FlycutCore/History/Clip.swift`, `SQLiteHistoryRepository.swift`, and `HistoryError` in `HistoryRepository.swift`; create `Sources/FlycutCore/History/FavoriteMetadata.swift`; extend `Tests/FlycutCoreTests/HistoryRepositoryTests.swift` and `HistoryPersistenceTests.swift`.

**Interfaces:**
- Produce `FavoriteMetadata: Codable, Equatable, Sendable` with `name: String?`, `shortcut: Int?`, `rank: Int` and an initializer accepting those fields.
- Extend `Clip.init` with trailing `favoriteMetadata: FavoriteMetadata? = nil`; add immutable `favoriteMetadata` and `withOrder(_ order: Int) -> Clip` preserving all other fields.
- Add `FavoriteEdit: Equatable, Sendable` with `name: String`, `text: String`, `shortcut: Int?` and explicit initializer.
- Add `HistoryError.invalidFavorite`, `.shortcutInUse`, and `.invalidFavoriteOrder`.

- [ ] Write `testFavoriteMetadataSurvivesRestartAndBackup` asserting clip equality after SQLite restart, JSON round trip, and `HistoryPersistence.restore`.
- [ ] Write `testLegacySchemasUpgradeWithoutChangingClips` using existing version-1 and version-2 fixture creation patterns; assert original text/RTF/UUID/order remain equal and metadata is nil. Write `testLegacyJSONWithoutFavoriteMetadataDecodes` asserting `favoriteMetadata == nil`.
- [ ] Run `swift test --filter 'HistoryRepositoryTests|HistoryPersistenceTests'`; confirm failures reference missing metadata/API.
- [ ] Implement optional metadata storage in a new nullable `favorite_metadata` JSON BLOB column, schema version 3. Upgrade versions 1 and 2 transactionally; create fresh/in-memory databases at version 3. Failed migration rolls back and reports an error.
- [ ] Preserve metadata in repository normalization/reconstruction paths. Keep existing clip initializer call sites source compatible and decode absent metadata with nil.
- [ ] Run the targeted tests; confirm old and new repositories agree on snapshots, and unsupported newer schemas remain rejected.

## Task 2: Favorite mutations and cloud ordering

**Files:** Modify `Sources/FlycutCore/History/HistoryService.swift`, `Sources/FlycutCore/Sync/CloudSyncLedger.swift`; create `Sources/FlycutCore/History/FavoriteShortcuts.swift`, `Tests/FlycutCoreTests/FavoriteManagementTests.swift`; extend `CloudSyncLedgerTests.swift` and `Tests/FlycutPlatformTests/CloudRecordCodecTests.swift`.

**Interfaces:**
- Consume `FavoriteEdit`, `FavoriteMetadata`, and `Clip.withOrder` from Task 1.
- Produce actor methods `HistoryService.updateFavorite(id: UUID, edit: FavoriteEdit) async throws -> HistorySnapshot` and `moveFavorite(id: UUID, offset: Int) async throws -> HistorySnapshot`.
- Produce pure `FavoriteShortcuts.resolve(slot: Int, favorites: [Clip]) -> FavoriteShortcutResolution` and `FavoriteShortcutResolution: Equatable, Sendable` with `.missing`, `.conflict`, `.clip(UUID)`.

- [ ] Write `testRenamePreservesRTFAndTextEditClearsRTF`: use a formatted favorite, rename it and assert RTF equality; change text and assert RTF nil and plain pasteboard type. Assert whitespace is retained exactly.
- [ ] Write tests for blank content, names over 200 characters, shortcut values outside 1–9, occupied slots, deleted favorite IDs, and cancelled editor drafts not invoking mutations.
- [ ] Write `testReorderKeepsShortcutAndSurvivesSync`, asserting moved order and unchanged assigned slots after two ledgers exchange entries. Add concurrent-rank tie and duplicate-slot tests asserting both devices produce identical order and `.conflict` respectively.
- [ ] Run `swift test --filter 'FavoriteManagementTests|CloudSyncLedgerTests|CloudRecordCodecTests'`; confirm expected failures.
- [ ] Implement favorite mutations inside `repository.update`. Reordering accepts offsets -1 and 1 only, rejects boundaries, and writes contiguous rank metadata for the resulting list. Newly favorited clips get rank before existing favorites, with no assigned slot or name. Mutation validates against the latest repository state.
- [ ] Include metadata in cloud content equality; sort favorites by metadata rank (legacy fallback `order`) and UUID tie-break, preserving metadata during normalization. Initial legacy favorite ordering must be materialized into metadata before sync rewrites position. Leave recent deduplication unchanged.
- [ ] Resolve shortcut ambiguity without modifying stored assignments. Cloud payloads use the existing Codable envelope; test new metadata in both inline and asset payloads and legacy payload imports.
- [ ] Run targeted tests plus `swift test --filter HistoryRepositoryTests`; confirm metadata survives reorder, copy, migration, and cloud merges.

## Task 3: Ranked search and Unicode-safe result presentation

**Files:** Create `Sources/FlycutCore/Search/ClipSearch.swift`, `Tests/FlycutCoreTests/ClipSearchTests.swift`; modify `Sources/FlycutCore/PaletteSelection.swift` and `Tests/FlycutCoreTests/PaletteModelTests.swift`.

**Interfaces:**
- Produce `ClipSearchResult: Equatable, Sendable` containing `clip: Clip`, `nameRanges: [Range<Int>]`, `textRanges: [Range<Int>]` (original Character offsets), and `isFuzzy: Bool`.
- Produce `ClipSearch.search(_ query: String, in clips: [Clip]) -> [ClipSearchResult]` and `ClipSearch.excerpt(text: String, ranges: [Range<Int>], limit: Int) -> SearchExcerpt`; `SearchExcerpt` contains `text: String` and remapped `ranges: [Range<Int>]`.
- Extend selection with `allClips: [Clip]`, `filteredSourceClips: [Clip]`, `setSearchResults(_ clips: [Clip])`, and `clip(id: UUID) -> Clip?`. Query/filter changes invalidate cached results; UUID selection remains authoritative.

- [ ] Write ranking tests asserting exact matches precede fuzzy matches, stronger matches precede weaker ones, and ties preserve input order. Assert names and content both match.
- [ ] Write tests for missing-letter query `mtg` matching `meeting`, one-edit typo `meetin` matching `meeting`, one-character contiguous-only matching, case/diacritic folding, empty queries, and whitespace preservation.
- [ ] Write `testRangesReferToOriginalGraphemeBoundaries` with accented/composed text and emoji; reconstruct highlighted characters from original Character offsets and assert expected original text. Write a long-text test asserting a contiguous match beyond 5,000 characters is found and appears in the excerpt.
- [ ] Run `swift test --filter 'ClipSearchTests|PaletteModelTests'`; confirm missing search APIs fail.
- [ ] Implement original matching code: contiguous matches over full text, then fuzzy ordered-subsequence matching and at most one edit for query words of four or more characters. Bound fuzzy scanning to 5,000 characters. Retain mappings from folded units to original Character offsets; deterministic scores rank gap/edit penalties and prefix proximity. Check cancellation between clips.
- [ ] Implement pure excerpt generation and cached selection results. History source includes favorites and recent UUIDs once; Favorites source contains favorites only. Empty-query selection exposes the default ordered source; nonempty queries wait for explicit search results instead of synchronously scanning on the main actor.
- [ ] Update legacy synchronous-selection search tests to test the pure search service and explicit result application. Run targeted tests; confirm valid ranges and stable UUID selection after results change.

## Task 4: Independent global shortcuts and palette keyboard commands

**Files:** Modify `Sources/FlycutPlatform/Hotkey/HotkeyService.swift`, `Sources/FlycutCore/Settings/Settings.swift`, `Sources/FlycutCore/Settings/SettingsStore.swift`, `Sources/FlycutMac/AppCoordinator.swift`, `Sources/FlycutMac/Palette/PaletteKeyboard.swift`, and `Sources/FlycutMac/Settings/SettingsView.swift`; extend `Tests/FlycutPlatformTests/InteractionTests.swift`, `Tests/FlycutCoreTests/SettingsTests.swift`; create `Tests/FlycutMacTests/PaletteShortcutTests.swift`.

**Interfaces:**
- Add `FlycutSettings.historyHotkey`, default keyCode 9 and modifierFlags 1_572_864 (Command–Option–V). Existing `hotkey` remains the plain-paste setting.
- Give `CarbonHotkeyClient.init(identifier: UInt32 = 1)` unique per-action routing; coordinator history client uses identifier 2. Expose a pure event-ID ownership predicate for tests.
- Extend commands with `.activateID(UUID)`; add `PaletteModel.activateVisibleNumber(_ number: Int)` and `activateFavoriteSlot(_ slot: Int)` consumed by local keyboard routing.

- [ ] Write tests asserting event identifier 1 triggers only plain paste and identifier 2 only history. Assert failed re-registration restores the prior shortcut and preserves the other registration.
- [ ] Write settings tests for legacy defaults loading, malformed history shortcut validation, and persistence of separately chosen bindings. Assert duplicate bindings are rejected by configuration before changing either registration.
- [ ] Write palette command tests asserting ordinary numbers remain text while editing, Command–1 activates visible row 1, and Command–Option–1 activates its uniquely assigned favorite even when hidden by search. A conflicting slot must report an error without activating a clip.
- [ ] Run targeted shortcut/settings tests to confirm failures.
- [ ] Implement independent identifiers and coordinator registration/state/termination lifecycle for both actions. Reuse menu-bar toggle behavior for Open History, capturing destination before application activation. Ensure recover/retry registration paths restore both actions.
- [ ] Route local modified digits before search-editing checks; suppress shortcuts while the favorite editor owns focus. Activate IDs directly from the latest snapshot rather than forcing selection into a hidden search result.
- [ ] Add separate settings recorders, labels, reset buttons, and duplicate-binding feedback. Preserve the tested plain-paste service and avoid moving favorites when paste-moves-to-top is enabled.
- [ ] Run targeted tests and `swift test --filter PaletteDismissalTests` to verify focus/dismissal regressions.

## Task 5: Responsive palette and explicit favorite editor

**Files:** Modify `Sources/FlycutMac/Palette/PaletteModel.swift`, `PaletteView.swift`, `PaletteRow.swift`, `Sources/FlycutMac/AppCoordinator.swift`; create `Sources/FlycutMac/Palette/FavoriteEditorView.swift`, `Tests/FlycutMacTests/PaletteSearchTests.swift`, `FavoriteEditorTests.swift`; extend `PaletteHistoryActionsTests.swift` and `PaletteRowClickTests.swift`.

**Interfaces:**
- Consume core search and favorite APIs from Tasks 1–3 and commands from Task 4.
- Produce `PaletteModel.searchResults: [ClipSearchResult]`, `updateSnapshot(_ snapshot: HistorySnapshot)`, `beginFavoriteEdit(_ id: UUID)`, `cancelFavoriteEdit()`, and `saveFavoriteEdit()`.
- Add model mutation closures `saveFavorite: (UUID, FavoriteEdit) async throws -> Void` and `moveFavorite: (UUID, Int) async throws -> Void`; coordinator executes them on its existing serialized mutation queue and propagates failure to the editor.
- Store editor draft state separately from saved snapshot, with explicit saving/error state and an optional edited favorite UUID.

- [ ] Write `testNewerSearchWinsAfterQuerySnapshotAndFilterChanges` with controllable search delays; assert superseded results never apply. Add dismissal/reopening invalidation tests.
- [ ] Write tests asserting empty History shows at most five favorites plus the configured recent preview, Favorites shows all favorites, nonempty search includes all results, and numbered badges align with visible row activation.
- [ ] Write editor tests asserting Cancel invokes no save, invalid/deleted/conflicting edits remain open with a message, and successful save closes only after the mutation finishes. Inject a durable-save failure and assert saved visible state stays unchanged.
- [ ] Run the new Mac tests and existing row/action tests; confirm expected failures.
- [ ] Debounce nonempty queries for 120 milliseconds and execute search in a cancellable detached task. Use a monotonically increasing generation to reject stale results; rebuild results on snapshot/filter changes and cancel on dismissal. Reconcile selection by UUID.
- [ ] Render row names, contextual highlighted content, favorites indicators, result-number badges, and assigned shortcut/conflict badges. Use Character offsets only inside the displayed string. Rename Recents to History and adjust Favorite button eligibility based on selected clip collection.
- [ ] Add Edit Favorite, Move Up, and Move Down context actions and explicit Save/Cancel multiline editor. Disable boundary moves and activation shortcuts during editing; preserve outside-click dismissal and cancel drafts on closing.
- [ ] Serialize favorite mutations with capture. For after-each-change mode, persist before publishing success; on persistence failure restore the prior working snapshot within the same queue and leave the draft available. Do not sync failed changes. Other save modes retain their existing semantics, reporting in-memory success without claiming a durable save.
- [ ] Run targeted Mac tests and the full suite; confirm paste/copy preferences, hidden activation, selection, hover previews, and clear-recents behavior still work.

## Task 6: Review, documentation, and local replacement

**Files:** Modify `README.md`, `CHANGELOG.md`, relevant keyboard-help/settings copy; keep version files at 1.0.2. Generated graph artifacts stay ignored.

**Interfaces:** Consume the finished application and all tests; no new product API.

- [ ] Update feature descriptions, keyboard help, search scope, favorite editing/formatting guidance, and sync limitations using Flycut-only wording. Explain fuzzy scan bounds and mixed-version metadata limitations where useful.
- [ ] Run `swift test` with output saved outside the repository; inspect exit status and all suite summaries. Run `git diff --check`.
- [ ] Run `graphify update . --no-cluster` and confirm generated files are ignored.
- [ ] Request an independent whole-change review against the spec and plan using the requesting-code-review skill; resolve concrete findings and repeat affected tests.
- [ ] Build using `scripts/build-app.sh release`. Inspect the installed application's signing identity and provisioning profile, then reuse that identity/profile with `scripts/sign-developer-id.sh` on the export bundle. Verify the export with `REQUIRE_DEVELOPER_ID=1 scripts/verify-app.sh`.
- [ ] Back up the currently installed application to a unique directory under `build/Backups`, quit cleanly through the app UI, replace `/Users/chris/Applications/Flycut Evolution.app`, and verify the installed bundle. Back up local history before its first schema upgrade.
- [ ] Perform local UI checks for both global shortcuts, search focus, numbered paste, snippet edit/cancel/reorder, ordinary numeric text entry, and outside-click dismissal. Preserve clipboard/draft state where practical and send no messages during app testing.
- [ ] Report test/build evidence, installed path, and any unverified live multi-Mac behavior. Leave all new work uncommitted and unpushed for user testing.
