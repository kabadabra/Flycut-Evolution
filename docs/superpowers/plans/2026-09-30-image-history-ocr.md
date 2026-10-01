# Image History and OCR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task using the preserved native execution method. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist, preview, paste, and search clipboard images with bounded storage and local OCR.

**Architecture:** Core stores typed clip metadata and lazy image assets in the same repository transaction. Platform validates images, runs Vision recognition, and writes image pasteboard data; Mac owns presentation and orchestration. Image sync uses a distinct record type and consent filter so legacy text clients and disabled clients do not misinterpret image records.

**Tech Stack:** Swift 6, SQLite, ImageIO, CryptoKit SHA256, Vision, AppKit, CloudKit, XCTest; macOS 14 or later.

**Spec:** [Image history and OCR](../specs/2026-09-30-image-history-ocr-design.md).

## Global Constraints

- Complete the capture privacy plan first; keep new work uncommitted with no pushes/publication.
- Encoded input and normalized PNG are each at most 16 MiB; decoded pixels at most 24 million.
- Default image storage is 200 MiB; configurable range 50–2048 MiB; count unique assets once.
- Never silently evict favorites or text to satisfy image storage; reject captures when necessary.
- Fresh installs default image capture/OCR on; existing installs keep text-only until enabled; image sync always defaults off.
- Honor never/on-quit/after-each-clip save modes; do not eagerly load image bytes in history snapshots.
- OCR is local, concurrency one. Immediate Command+Shift+V never starts implicit OCR.

## Review Focus

- Text clips with empty or malformed unknown image metadata must not become image entries: Task 1.
- Huge declared dimensions in a tiny image file must be rejected before raster allocation: Task 2.
- Shared image assets surviving deletion of one favorite must remain available: Task 1.
- An OCR result arriving after deletion/source exclusion must not resurrect content: Task 3.
- A disabled-sync client must not tombstone images when recording text edits: Task 5.

---

### Task 1: Typed metadata, asset storage, budgets, and save modes

**Files:** Create Core `History/ImageAsset.swift`, `History/ImageAssetRepository.swift`, `History/ImageBudgetPolicy.swift`; modify `Clip.swift`, `HistoryRepository.swift`, `SQLiteHistoryRepository.swift`, `HistoryPersistence.swift`, `HistoryService.swift`, `EvictionArchive.swift`; create `Tests/FlycutCoreTests/ImageHistoryTests.swift`, `ImagePersistenceTests.swift`.

**Interfaces:** Add `ClipContentKind` (.text/.image), `ImageRecognitionState` (.pending/.recognized/.noText/.failed), and `ClipImage` metadata (`assetHash: String`, `width: Int`, `height: Int`, `byteCount: Int`, `accompanyingText: String?`, `recognizedText: String?`, `recognitionState`). Clip gains optional image metadata and sourceBundleIdentifier with backward-compatible decoding; `contentKind` derives from valid metadata, missing kind means text. `ImageAsset` holds hash/PNG Data. `ImageAssetRepository` exposes `imageData(for hash: String) async throws -> Data?`, `applyImage(_ asset: ImageAsset, clip: Clip, budgetBytes: Int) async throws -> HistorySnapshot`, and `exportAssets(for snapshot: HistorySnapshot) async throws -> [ImageAsset]`. SQLiteHistoryRepository conforms. `ImageBudgetPolicy.planEvictions(snapshot: HistorySnapshot, assetSizes: [String: Int], incomingHash: String, incomingBytes: Int, budgetBytes: Int) throws -> [UUID]` returns oldest eligible recent IDs or throws when favorites prevent admission. Add `HistoryPersistence.save(_:assets:) async throws -> Bool` and asset-aware restore; retain text-only adapters.

- [ ] Write migration tests proving schema 3 text/RTF/favorites unchanged and schema 4 image metadata round-trips without snapshot BLOB loads. Assert malformed/unknown kinds are rejected, not converted to empty text. Test unique-asset counting, oldest-recent eviction, favorite protection, duplicate assets, reference cleanup, and metadata-copy helpers preserving image/source identity.
- [ ] Write persistence tests: never produces no disk image rows; on-quit copies referenced assets with snapshot; after-each-clip commits both atomically; injected transaction failure restores prior rows; deleting one of two shared references preserves bytes. Archive/backup round-trip includes bytes and cannot produce dangling references.
- [ ] Run `swift test --filter 'ImageHistoryTests|ImagePersistenceTests'`; confirm failures.
- [ ] Implement schema 4 transactional migration and repository interfaces. Update deduplication keys to use image hash rather than empty text; favorite edits preserve image bytes/name/slot and do not require text content. Merge All includes text entries only and gives no-text feedback if no text entries exist. Protect assets during replaceAll/update until new references/assets are installed; cleanup at transaction end.
- [ ] Run selected tests plus existing HistoryRepositoryTests, HistoryPersistenceTests, FavoriteManagementTests, and EvictionArchiveTests; require all pass. Keep uncommitted.

### Task 2: Safe image capture and preferences

**Files:** Create `Sources/FlycutPlatform/Clipboard/ClipboardImageDecoder.swift`, `Tests/FlycutPlatformTests/ClipboardImageTests.swift`; modify PasteboardClient.swift, ClipboardMonitor.swift, Core Settings.swift/SettingsStore.swift, Mac AppCoordinator.swift/SettingsView.swift; add settings migration tests.

**Interfaces:** `PasteboardImageReadResult` has `.data(Data, type: String)`, `.unavailable`, `.denied`; add `PasteboardClient.readImage() -> PasteboardImageReadResult` with an unavailable default for old mocks. `ClipboardImageDecoder.decode(_ data: Data, type: String) throws -> ImageAssetCapture` returns `ImageAssetCapture: Sendable` with `asset: ImageAsset`, `width: Int`, and `height: Int`. Add settings imageCaptureEnabled, imageRecognitionEnabled, imageSyncEnabled, and imageStorageLimitMiB. Store a feature migration marker to distinguish fresh preferences from established users before load mutates defaults. Monitor receives `onImage: (Clip, ImageAsset) -> Void`.

- [ ] Write tests for PNG/TIFF/JPEG, 16 MiB input/output bounds, 24-million-pixel bounds using header metadata before decoding, corrupt formats, unsupported files/URLs, denied reads, and counter changes during decode. Assert sensitive/excluded/paused observations read no image data; mixed image/text yields one image callback with real accompanying text.
- [ ] Write preference tests: fresh defaults on/on/off/200; old populated settings off/on/off/200; repeated load preserves chosen settings; limits clamp to 50–2048.
- [ ] Run `swift test --filter 'ClipboardImageTests|ClipboardMonitorTests|SettingsTests'`; confirm failures.
- [ ] Implement ImageIO metadata validation before raster allocation, bounded PNG normalization, SHA256 identity, and main-actor bounded read followed by background decoding. Carry observation generation/count through async decoding so an obsolete result is discarded. Denied reads never fall back across formats. Connect capture/persistence/budget feedback and preferences.
- [ ] Run selected tests; keep uncommitted.

### Task 3: Local OCR with cancellation and searchable metadata

**Files:** Create `Sources/FlycutPlatform/Clipboard/ImageTextRecognizer.swift`, `Sources/FlycutMac/Images/ImageRecognitionCoordinator.swift`, `Tests/FlycutPlatformTests/ImageTextRecognizerTests.swift`, `Tests/FlycutMacTests/ImageRecognitionCoordinatorTests.swift`; modify ClipSearch.swift, AppCoordinator.swift, HistoryService.swift, and ClipSearchTests.swift.

**Interfaces:** `ImageTextRecognizing: Sendable` exposes `recognize(_ png: Data) async throws -> String`. Vision implementation uses VNRecognizeTextRequest/VNImageRequestHandler off the main actor and reading order from bounding boxes. `@MainActor ImageRecognitionCoordinator` exposes `enqueue(_ clip: Clip)`, `cancel(id: UUID)`, `setPaused(_ paused: Bool)`, `invalidateDisallowedSources(_ excluded: Set<String>)`, and `setEnabled(_ enabled: Bool)`; constructor receives asset reader, recognizer, and async result mutation callback. `HistoryService.updateRecognition(id: UUID, assetHash: String, text: String?, state: ImageRecognitionState) async throws -> HistorySnapshot` checks live identity/hash inside repository update.

- [ ] Write fake-recognizer tests asserting maximum concurrency one, no-text/failed statuses, pause halts next job, explicit retry, deleted/replaced/excluded/disabled results are dropped, and no network dependency. Add image OCR/name/accompanying-text ranking/highlight tests with Unicode matches and pending recognition.
- [ ] Run `swift test --filter 'ImageTextRecognizerTests|ImageRecognitionCoordinatorTests|ClipSearchTests'`; confirm failures.
- [ ] Implement recognition and generation cancellation. Recheck eligibility before result persistence; results cannot reconstruct missing clips. Define a common searchable display text for image metadata while preserving existing text offsets/highlighting. Persist OCR status through existing save modes.
- [ ] Run selected tests; manually recognize a harmless generated text image and verify searching becomes available after completion. Keep uncommitted.

### Task 4: Image previews, favorites, and destination paste

**Files:** Create `Sources/FlycutMac/Images/ImagePreviewModel.swift`, `ImagePreviewView.swift`, `Tests/FlycutMacTests/ImagePaletteTests.swift`; modify PaletteModel/Row/View, FavoriteEditorView/FavoriteMutation, ClippingPreview, Platform PasteService.swift, and InteractionTests.swift.

**Interfaces:** Preview model uses `load(_ clip: Clip) async`, cancels obsolete selection loads, and caches bounded thumbnails (maximum 128 entries, 32 MiB decoded bytes). PasteClient adds `writeImage: (Data) -> Int?`; `PasteService.copyOrPasteImage(_ png: Data, mode: PasteMode, previousApp: pid_t?) async -> PasteResult` shares target/focus validation but always sends standard paste. Coordinator resolves image bytes for existing clip selection; explicit extracted-text action invokes existing text copy path.

- [ ] Write tests asserting metadata-only list construction, late preview results do not replace current selection, thumbnail cache bounds, image favorite name/slot editing preserves assets, Copy Extracted Text fails gently without recognized text, and plain selection of an image uses only available recognized text.
- [ ] Extend InteractionTests: image writes record the self-write counter, focus failures send no paste event, valid image paste sends ordinary Command+V, and immediate plain-text paste never reads image bytes or invokes recognition. Exercise image pasteboard output using an isolated NSPasteboard.
- [ ] Run `swift test --filter 'ImagePaletteTests|InteractionTests|FavoriteEditorTests'`; confirm failures.
- [ ] Implement lazy thumbnail/full preview with dimensions, recognition status/retry, image-specific favorite controls and paste routing. Preserve keyboard navigation, search selection, outside-click dismissal, and text-rich-preview behavior.
- [ ] Run selected tests and manually preview/paste copied screenshots in supported local destinations. Keep uncommitted.

### Task 5: Image sync consent and complete subsystem verification

**Files:** Create `Sources/FlycutPlatform/CloudSync/CloudImageCodec.swift`, `Tests/FlycutPlatformTests/CloudImageCodecTests.swift`; modify CloudSyncController.swift, CloudSyncLedger.swift, CloudRecordCodec.swift, CloudSyncStateStore.swift, AppCoordinator.swift, and existing sync tests.

**Interfaces:** Add image record type `FlycutImage` in the existing zone. `CloudImageEnvelope: Codable, Sendable` contains entry and ImageAsset; decoder validates hash, dimensions and bounded bytes through the image decoder. CloudSyncController receives image consent and async asset reader/import callbacks. Add `CloudSyncLedger.recordLocal(_:at:includeImages:)` and `applyRemote(_:to:at:includeImages:)` retaining existing default adapters. Filter by image record type before legacy text decoding; image tombstones require known image identity/type and active image consent.

- [ ] Write tests for encrypted CKAsset-path round-trip, corrupted/oversized assets and unknown kinds, legacy text-only decoder safely rejecting FlycutImage, pending image upload disabled by consent, text edits not creating image tombstones, off/on/off consent preserving local/remote images, and remote bytes imported before clip references become visible.
- [ ] Run `swift test --filter 'CloudImageCodecTests|CloudSyncLedgerTests|CloudSyncControllerTests|CloudRecordCodecTests'`; confirm failures.
- [ ] Implement distinct record handling and consent filtering without passing a reduced snapshot into deletion inference. Keep images in the local ledger when filtered; remote merges preserve local-only images. Bound asset file reads before Data allocation and JSON/base64 envelope allocation (24 MiB transfer envelope cap). Keep CKAsset in its normal field, encrypted by CloudKit by default, rather than assigning it to encryptedValues. Protect private temporary files and existing account invalidation cleanup.
- [ ] Run full `swift test`, `scripts/build-app.sh release`, and `graphify update . --no-cluster`; require passing tests and both architectures. Update CHANGELOG.md/readme.md/docs/DEVELOPING.md and manual two-Mac test instructions; state live two-Mac verification separately. Keep uncommitted and continue to updates/setup.

Cloud encryption reference: [Apple CKRecord encryptedValues](https://developer.apple.com/documentation/CloudKit/CKRecord/encryptedValues).
