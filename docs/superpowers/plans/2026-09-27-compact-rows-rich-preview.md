# Compact Rows and Rich Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show compact one-line plain-text history rows, preview the full rich copy on hover, and paste with or without formatting.

**Architecture:** Add a bounded optional RTF payload to clips, carry it through capture, SQLite, and CloudKit, then render it only in a SwiftUI hover popover. Keep plain text as the canonical content; formatted activation writes both RTF and plain text, while a row action writes plain text only.

**Tech Stack:** Swift 6, AppKit, SwiftUI, SQLite, CloudKit, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-27-compact-rows-rich-preview-design.md`

## Global Constraints

- Flycut Evolution 1.0.0 on macOS 14+; macOS 27 is the target.
- No commit, push, tag, or public release until the user's local and two-Mac checks pass.
- Do not print clipboard content or signing secrets in diagnostics.
- Existing history and CloudKit records must decode unchanged.

## Review Focus

- Multiline, repeated whitespace, emoji, and long text produce a one-line label with truthful ellipsis.
- Empty/invalid/oversized RTF falls back to full plain-text preview without blocking capture.
- Existing v1 SQLite and old CloudKit JSON decode without losing history.
- Favorites and same-app duplicate recapture retain the newest RTF representation.
- Hover does not interfere with single-click paste or close the palette unexpectedly.
- Plain row action cannot trigger the row's formatted paste; Shift–Command–V still reads the current clipboard without replacing it.

---

### Task 1: Compact row label

**Files:** `Sources/FlycutCore/History/Clip.swift`, `Sources/FlycutMac/Palette/PaletteRow.swift`, `Tests/FlycutCoreTests/PalettePreviewTests.swift`

**Interfaces:** `Clip.previewLine(limit: Int) -> String` returns a whitespace-normalized, character-limited label. PaletteRow uses this with `.lineLimit(1)`.

- [ ] Write failing tests for line breaks, whitespace, emoji, and ellipsis.
- [ ] Run the focused tests to confirm the intended failure.
- [ ] Implement the label and update PaletteRow.
- [ ] Run focused tests to green.

### Task 2: Capture and persist bounded RTF

**Files:** `Clip.swift`, `PasteboardClient.swift`, `ClipboardMonitor.swift`, `SQLiteHistoryRepository.swift`, `HistoryService.swift`, relevant core/platform tests.

**Interfaces:** `Clip.formattedRTF: Data?`, `PasteboardClient.readRTF() -> Data?`; RTF limited to 256 KiB and validated against canonical text.

- [ ] Write failing capture, schema-v1 upgrade, restart, recapture, and favorite tests.
- [ ] Run focused tests to see failures.
- [ ] Add optional payload, read/validate after accepted text, and migrate/write/read SQLite v2.
- [ ] Run focused tests to green.

### Task 3: Sync formatted previews

**Files:** `CloudSyncLedger.swift`, `CloudSyncLedgerTests.swift`, `CloudRecordCodecTests.swift`.

**Interfaces:** Existing `CloudClipEntry` JSON carries `formattedRTF` when present; old records decode with nil.

- [ ] Write failing tests for encoded round trip, remote merge, and changed formatting on recapture.
- [ ] Run focused tests to see failures.
- [ ] Propagate RTF in order normalization and content comparison.
- [ ] Run focused tests to green.

### Task 4: Formatted paste and plain row action

**Files:** `Sources/FlycutPlatform/Paste/PasteService.swift`, `Sources/FlycutMac/AppCoordinator.swift`, `PaletteModel.swift`, `PaletteRow.swift`, `PaletteView.swift`, relevant platform/macOS tests.

**Interfaces:** `PasteService.copyOrPaste(_ clip: Clip, plain: Bool, mode: PasteMode, previousApp: pid_t?)` uses a rich pasteboard write only when `plain == false` and RTF exists. Existing `copyOrPaste(_ text:...)` remains a plain convenience. `PaletteCommand.activatePlain` selects the row and invokes plain paste.

- [ ] Write failing tests for rich write, plain row action, and existing shortcut preservation.
- [ ] Run focused tests to see failures.
- [ ] Implement dual representation write and segregated row button target.
- [ ] Run focused tests to green.

### Task 5: Hover preview and live verification

**Files:** `Sources/FlycutMac/Palette/PaletteView.swift`, new `Sources/FlycutMac/Palette/ClippingPreview.swift`, `PaletteRow.swift`, macOS tests, QA docs.

**Interfaces:** A delayed hover state presents one right-edge popover. `ClippingPreview` renders validated RTF in a bounded scroll view or full plain text.

- [ ] Write focused tests for rich rendering fallback and click behavior.
- [ ] Run focused tests to see failures.
- [ ] Implement preview and hover lifecycle with a short delay.
- [ ] Run the full suite, build, and visually verify on the first Mac.
- [ ] Regenerate Graphify and QMD, sign/notarize a candidate, and verify the second Mac receives a synthetic formatted clip before publication.
