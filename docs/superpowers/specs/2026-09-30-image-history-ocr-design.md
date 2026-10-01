# Priority 5: Image history and local text recognition

## Goal and scope

Capture copied images and screenshots as reusable history entries, preview and paste their original image representation, and find text inside them through local recognition. Build after the capture-privacy subsystem. Keep existing text history and favorites compatible.

Clipboard image capture does not include file imports, remote image downloads, or screen capture. No screen-recording permission is required for reading copied image representations.

## Capture and storage

Add an Images settings section. Image capture and local recognition default on for fresh installations; existing installations retain text-only capture until the user enables images through settings or setup. Image syncing defaults off independently of existing text-sync consent.

Accept advertised PNG, TIFF, and JPEG image representations after all privacy gates pass. Prefer PNG, validate decoded dimensions, and normalize to a lossless PNG representation. Bound encoded input and normalized output to 16 MiB each and decoded pixels to 24 million. Reject invalid, oversized, or clipboard-raced data without disrupting text capture. For mixed image/text clipboard representations, capture one image entry and keep genuine accompanying text as searchable metadata, rather than a duplicate history item.

Introduce an explicit clip content kind and image reference with dimensions and optional recognized text. Existing Clip.text continues to represent text clips; image data must never masquerade as empty text. Repository migration adds an image-assets table with content hashes and bounded PNG blobs. Fetch full bytes lazily for preview, paste, and sync; history lists use metadata and cached thumbnails. Store assets and clip references transactionally, garbage-collect unreferenced assets, and include assets in existing database backups.

The default total image budget is 200 MiB, configurable from 50 to 2048 MiB. Count unique assets once. Evict oldest recent image entries until a new asset fits; never silently evict favorites or text entries. If favorites consume the budget, reject the new image and show a brief explanation. Lowering the budget uses the same rule and reports when favorites prevent compliance.

Honor SaveMode: never keeps image assets in memory, on quit persists with the history snapshot, and after each clip persists transactionally. Failed persistence must not leave an apparently saved favorite or orphaned asset.

## Recognition and interface

Use Apple's Vision text recognition on a background queue with concurrency one. Recognition is local; image capture never requires a network request. Store pending, recognized, no-text, or failed status. Failures preserve the original image and offer an explicit retry.

An OCR result is applied only if its clip identifier and image hash still match a live entry. Deletion, disabling recognition, and changes that disallow the source cancel queued work and invalidate in-flight results. Pausing prevents new recognition work from starting until resume. Already captured images remain in history.

Search considers names, accompanying text, and recognized text using the existing ranking/highlighting pipeline. Search and opening the palette never wait for OCR or full image decoding. Rows show thumbnails, dimensions, and a short text match when available. A selected image opens a larger bounded preview.

Image favorites support naming, ordering, and assigned shortcuts. Their editor does not offer text replacement of the image. Paste inserts the image using the existing focus-restoration and standard paste-event path. Copy Extracted Text explicitly copies recognition output. Plain-text paste of an image uses recognized text only when explicitly selecting that image in history; unavailable recognition reports no text without replacing the clipboard. The immediate Command+Shift+V path does not silently run OCR on a newly copied image.

## Sync and compatibility

Image syncing requires an independent opt-in on each Mac. Image payloads use the existing encrypted CloudKit asset path, including validated bytes and recognition metadata, within the same size bounds. Receiving clients validate before storing assets.

When image sync is disabled, omit image uploads/downloads without treating skipped records as deletions. Turning it off must not erase local or remote images. Older payloads decode as text; unknown content kinds are skipped safely without preventing valid text records from syncing. Require updated clients for image sharing and explain that text sync remains available on older versions.

## Verification and acceptance

Test migration with existing history and favorites, corrupt images, size/pixel bounds, deduplication, lazy loads, budget eviction and favorite protection, all save modes, failed transactions, stale/cancelled OCR, search ranking, image pasteboard writes, and sync opt-in transitions. Manually test screenshots and images pasted into TextEdit, an email composer, and Teams where supported by the destination.

Success means images persist according to preferences, paste as images, and become searchable after local recognition without blocking the palette or bypassing privacy controls.

Reference: [Apple Vision text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images).
