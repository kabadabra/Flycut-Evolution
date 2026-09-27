# Flycut Evolution 1.0.0: history and Cloud Sync design

## Intent and release scope

Flycut Evolution is the free Swift macOS successor maintained by Emerging Dynamics, with visible credit to TermiT/Flycut, its upstream contributors, and Jumpcut. Version 1.0.0 is the first release in the new Flycut-Evolution repository. The release supports macOS 14 or later, including macOS 27, on Apple Silicon and Intel. Flycut 2.0 remains available separately for older Macs. The new repository remains unpublished until the installed build passes local paste, migration, signing, notarization, and sync checks.

The user wants one-click history paste, Shift–Command–V to paste the current clipboard as plain text, duplicate copies from the same app to move to the top, and history that works across **Macs signed into the same Apple Account**. Clipboard history and favorites sync; interface, shortcut, privacy, login-item, and capture settings stay local to each Mac. The legacy iOS sources are outside this release.

## Local history and duplicate behavior

A duplicate means identical text and the same displayed source-app name. If the name is unavailable, use the source bundle URL; if both are unavailable, equal text from unknown sources counts as a duplicate. Text comparison is exact, including case and whitespace. A new copy removes all matching recent rows, keeps the newest matching row's UUID for stable cloud identity, refreshes its capture timestamp and source metadata, and moves it to the top. A copy from another app remains a separate row. Favorites are separate and never removed by copying. If the most recent row matches, its timestamp refreshes without increasing the count.

On upgrade and after a remote merge, existing duplicate recents are collapsed from newest to oldest, keeping the first row for each key. This is a transaction over the local snapshot; a private pre-upgrade backup remains available. The `Remove duplicate clippings` setting and migrated flag disappear from the UI and model. Duplicate removal is always on. A capacity eviction happens only after deduplication, so a repeat never evicts a different clipping.

## Cloud model and privacy

Cloud Sync uses Apple's CloudKit private database in `iCloud.com.edynamics.flycut`, through `CKSyncEngine` and a Flycut-owned record zone. It does not use the public or shared database. Sync starts only after a clear in-app opt-in explaining that existing text history and future eligible copies will be uploaded to the user's private iCloud account. Importing old settings never turns sync on silently. A user may turn sync off without deleting local history; a separate explicit action is required to remove cloud data. Clipboard content is never sent to GitHub or Emerging Dynamics.

Each clipping has a stable record ID derived from its UUID, text or a CloudKit asset for text too large for a record field, source name, source URL when available, type, collection, capture time, and a sortable update time. An explicit deletion or capacity eviction creates a lightweight tombstone that contains no clipping text. Tombstones prevent an offline Mac from resurrecting deleted history. Favorites and recents use the same record type; a move between them updates one record. Imported clips keep their stable local IDs. Cloud history is bounded by each Mac's local capacity only when choosing what to show; a remote merge must not silently destroy existing local clips because another Mac has a lower capacity.

CloudKit owns the network retry schedule. The app persists sync-engine state, pending record changes, cloud metadata, and account identity in protected local storage separate from the existing SQLite history. At startup it reconciles that state with local history so a crash between a local edit and queueing a cloud change cannot lose an edit. Remote events merge through the existing history service, then update the palette and save locally using the current persistence guard. Remote changes must not be re-uploaded as fresh local edits. Simultaneous changes resolve deterministically by update time then record ID; a tombstone wins over an older edit. Equal text copied from the same app on two Macs converges to one recent row and queues removal of the loser. Cloud errors leave local capture and paste working and show an actionable status.

Cloud Sync stops if the Apple Account changes or signs out. Existing local history is retained, but the app does not upload it into a different account until the user opts in again. Sync state is scoped to the cloud account. A second Mac can join the same private database and merge its pre-existing local history after the user enables sync there. The app exposes connection state, last successful sync, errors, and a Sync Now action. It never claims that a local copy has reached the other Mac before CloudKit confirms it.

## Signing and distribution

Apple documents CloudKit as available to Developer ID apps. Register the new iCloud container and enable CloudKit for `com.edynamics.flycut`; create a Developer ID provisioning profile authorizing the restricted entitlements. Embed it at `Contents/embedded.provisionprofile`, sign with the existing Emerging Dynamics Developer ID identity, then notarize and staple the app and DMG. The release workflow must receive the provisioning profile as a GitHub Actions secret and verify its team, bundle ID, container, environment, expiry, and signature. The preview app uses isolated local data and never shares production CloudKit data.

No credential, provisioning profile, private clipboard text, or generated Graphify file belongs in Git. The new public repository gets one clean Swift product history, original-project attribution, issue tracker, user-facing 1.0.0 notes, and developer documentation only after all gates pass.

## Verification and recovery

Automated tests cover same-app deduplication, different-app retention, existing-history cleanup, stable IDs, favorites, capacity, restart persistence, two simulated devices, offline edits, conflicting edits, deletions, account changes, crash recovery, and sync disabled. Local tests also confirm plain-text paste leaves the source clipboard intact and one-click paste preserves the fallback when no editable target exists.

The signed installed candidate must pass a physical single-click and Shift–Command–V check in TextEdit and a browser input, plus the existing migration/history regression. A production CloudKit test uses only synthetic text: upload, fetch on a second Mac if available, conflict/duplicate resolution, offline return, and deletion propagation. If a second Mac is unavailable, report that cross-device behavior remains unverified and keep publication gated. Back up the current production SQLite database before installing each candidate. After testing, remove synthetic rows and restore any genuine history entry that a capacity test displaced, without overwriting later user copies.
