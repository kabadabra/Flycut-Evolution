# Developing Flycut Evolution

## Swift app

Use Xcode 27.0 with Swift 6.4. The package uses Swift 6 language mode and targets macOS 14 or later. Open `Package.swift` in Xcode. `FlycutCore` owns history, settings, and migration; `FlycutPlatform` adapts macOS services and CloudKit; `FlycutMac` contains the AppKit and SwiftUI interface.

```sh
swift test
scripts/build-app.sh debug
scripts/build-app.sh release
scripts/verify-app.sh 'build/Export/Flycut Evolution.app'
```

Debug builds use the separate `com.edynamics.flycut.preview` identity. Release builds contain arm64 and x86_64 slices under `com.edynamics.flycut`. These local outputs use ad hoc signing; Cloud Sync requires the Developer ID profile and entitlements described in [release setup](../RELEASE_SETUP.md). CI builds and tests only the active Swift app.

## Manual release checks

Use disposable text and a test Mac to verify migration, search, keyboard navigation, one-click paste, plain-text paste, preview hover and its Appearance toggle, favorites, Cloud Sync in both directions, deletion sync, light and dark appearance, full-screen Spaces, Accessibility prompts, and Login Items on macOS 27. Install the signed, notarized DMG on a second Mac and verify its contained app. Record results in [Swift QA](QA-swift.md) before publication.

## QMD

From the repository root, set up a local documentation collection:

```sh
qmd collection add "$PWD" --name flycut-evolution --mask '**/*.md'
qmd context add qmd://flycut-evolution/ 'Flycut Evolution macOS clipboard manager: build, migration, Cloud Sync, release, and developer documentation.'
qmd update
qmd embed
qmd search 'pasteboard' -c flycut-evolution
```

If `flycut-evolution` already exists, skip `collection add`. The optional QMD agent skill is in `.agents/skills/qmd`.

## Graphify

```sh
graphify update . --no-cluster
graphify query 'clipboard capture' --graph graphify-out/graph.json
graphify hook install
```

`graphify-out/` is ignored by Git; `AGENTS.md` explains the local graph workflow. The hook is local because its executable path depends on your machine.

## Following the original Flycut

This Swift repository is a fresh continuation of [TermiT/Flycut](https://github.com/TermiT/Flycut). Review upstream issues and pull requests for relevant behavior, then port fixes to the Swift implementation on a review branch. The older Objective-C fork and its [Flycut 2.0 release](https://github.com/kabadabra/Flycut/releases/tag/v2.0.0) remain separate for history and older Macs.

## Favorite storage and search

Schema 3 adds optional favorite metadata while preserving schema 1/2 text, formatting, IDs, and positions. Older JSON payloads load without metadata. Cloud records retain their existing encrypted payload envelope. Favorite rank, name, and shortcut edits participate in per-clip last-writer-wins merging; equal ranks use UUID order. Concurrent reorder operations converge, but are not a whole-list transaction across devices. Older application versions may discard unknown metadata when rewriting a favorite; update all synced Macs before editing new favorite metadata.

The palette debounces search by 120 ms, performs matching off the main actor, and rejects stale generations. Highlight ranges use original Character offsets. Contiguous matches cover full text; fuzzy scanning is limited to 5,000 characters per clip.

## Privacy/image/update verification

The image migration upgrades SQLite schema 3 to 4 without rewriting text, RTF, or favorite metadata. Image assets live in the same database, and metadata snapshots do not load PNG blobs. Save-never uses only the working in-memory database; on-quit and after-each-change move referenced assets and history together. Back up a live WAL database through SQLite's backup API, rather than copying only its main file.

Run `swift test`, `scripts/tests/test-updater-bundle.sh`, and `scripts/tests/test-update-feed.sh`. The feed fixture uses ephemeral keys and temporary app bundles, checks signed feeds/archives and tamper rejection, and never installs over the current app. Run the bundle check after `scripts/build-app.sh release`.

Manual checks: exclude an app and copy there; ignore one copy; pause through sleep/wake; copy a screenshot with harmless text, search it after recognition, preview it, favorite/rename it, paste the image into a supported composer, and copy its extracted text. Verify both real global shortcuts and Teams plain-text paste. Image syncing requires updated builds on both Macs and the production CloudKit schema described in RELEASE_SETUP.md; local codec tests do not establish live two-Mac behavior.

Setup can be reopened from Settings or More. Existing installations do not automatically open it or silently enable images. Verify Accessibility refresh after returning from System Settings, and use a destination text field to perform the explicit paste exercise.

For an updater installation fixture, clone two app bundles into a temporary directory, give both the distinct bundle ID `com.edynamics.flycut.update-fixture`, assign consecutive build numbers and a dedicated temporary update key, re-sign both, and generate a signed loopback feed for the newer copy. Start the older fixture from that directory and explicitly choose Check for Updates and Install. Verify its new build number after relaunch. Never use the installed production app for fixture updates. The automated signing fixture verifies cryptography and metadata; an actual updater installation is a separate integration check.

Image exports use PNG for a single image and a versioned JSON collection for mixed text/image selections. JSON preserves full clip metadata and base64 PNG assets. Text-only collections retain the existing text export format. Automatic eviction archives write text or PNG before an image admission removes capacity/budget victims; archive failures abort that admission.

A receiving Mac rejects an image-sync collection exceeding its configured budget before changing local history or the sync journal. It preserves favorites and does not upload budget-driven deletion records. Increase the limit, then choose Sync Now to reset the fetch cursor and retry the rejected collection. The unapplied-download warning survives restart and successful uploads until an explicit retry.

Update feed generation rejects a credential that differs from the public key in an archived app and verifies every enclosure signature against that bundled public key, as well as the signed feed.

History capacities are fixed preferences. Startup, recovery, import, and cloud merge enforce the chosen recent/favorite capacities; they never raise those preferences automatically. Explicit reductions apply immediately. Persistent sessions save a private JSON backup including PNG assets before capacity eviction, and enabled automatic exports are honored. Save-never sessions keep capacity enforcement in memory without writing backups. Cloud journals record overflow evictions as tombstones so subsequent merges do not restore those same records. Legacy replacement backups also contain image assets; budget reduction archives evicted PNGs before removing them and aborts on export failure.

Finder file URLs are captured as structured `ClipFile` references (up to 100 per copy), never inferred from text filenames. SQLite schema 5 adds nullable file metadata and upgrades existing text/image rows without changing their content. A single readable image file within the existing image limits is normalized and stored with its reference; image capture disabled, unsupported files, and multiple-file selections retain references only. File reads run off the main actor, are bounded to 16 MiB + 1, and check pause/exclusions/settings before starting and again before delivery. File images paste the stored PNG even after the original moves. Other files paste NSURL objects through normal Command–V without a text-field requirement; missing originals leave the clipboard unchanged. Full paths remain metadata, and file content is never uploaded by file-reference sync. Paths from another Mac may be unavailable locally. Hover previews use the bounded thumbnail cache and selectable filename/path text.
