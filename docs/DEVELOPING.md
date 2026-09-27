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
