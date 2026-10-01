# Keyboard access, smarter search, and reusable favorites

## Goal and constraints

Make Flycut faster to use from the keyboard and easier to retrieve saved text from, while preserving dependable paste, existing history, and optional private iCloud sync.

- macOS 14 or later; native SwiftUI/AppKit, Swift package targets, SQLite, and existing CloudKit transport.
- Preserve the tested Command–Shift–V plain-text paste path and outside-click dismissal.
- Keep version 1.0.2 for this local test build; release numbering can be changed before publication.
- No new commits, pushes, or release publication without further user instruction. The existing reliability fixes have already been committed separately.
- Product documentation and commit messages describe Flycut features without naming other clipboard applications. Reference source stays outside the repository. Implement original code; copied source would require its applicable license notices.
- No new runtime dependencies, telemetry, image capture, OCR, source-app filters, or automatic updater in this scope.

## Selected approach

Extend the existing palette, history service, and persistence layers. Retain the current paste service rather than replace it. Add a focused search component and favorite metadata with backward-compatible decoding.

A replacement palette or storage framework would increase migration and paste risk without improving these user flows. Separate utilities for keyboard navigation and snippet management would fragment the everyday experience; keep them together in the palette.

## Keyboard access

- Add a separately configurable global Open History shortcut, default Command–Option–V. Opening history resets the query, focuses search, and remembers the destination application before activating Flycut.
- Keep the existing configurable plain-text paste shortcut, default Command–Shift–V.
- Pressing Open History while the palette is already open closes it.
- Within the palette, Command–1 through Command–9 immediately activate the corresponding visible row using the existing paste/copy preference. Display these badges on rows and keep numbering aligned with the flattened displayed order.
- Command–Option–1 through Command–Option–9 activate explicitly assigned favorites while the palette is open, including when a search hides them. These are local palette bindings, not additional global shortcuts.
- Ordinary digits and letters typed into focused search remain input. Return activates the selected result; Escape closes; arrow navigation remains available. Existing keyboard commands outside text editing remain available.
- Shortcut registration routes each action independently using unique identifiers. A conflict reports which shortcut failed. A failed settings change restores its previous working registration; it must not disable the other action.
- Provide separate shortcut recorders and reset buttons in settings. Reject identical bindings for the two actions with an explanatory message.

## Palette and search

- Replace the default Recents view with History: an empty query shows up to five favorites first, followed by recent clips. Favorites remains a separate filter showing all favorites in manual order.
- Keep existing preview-count/show-all behavior for recent clips; the compact favorites section is additional. Do not repeat a clip UUID in the same display.
- A nonempty History query searches all recent clips and favorites, regardless of the collapsed preview count. The Favorites filter searches favorites only.
- Search both favorite names and clipboard text. Matching is case-insensitive and diacritic-insensitive; original text and whitespace remain untouched.
- Rank contiguous matches before fuzzy matches. Within each category, prefer stronger/closer matches and then the existing displayed order for deterministic ties.
- Fuzzy matching supports missing intermediate letters and small spelling mistakes. A one-character query uses contiguous matching only to avoid noisy results. Fuzzy text scanning is bounded to the first 5,000 characters per clip; contiguous matching searches the full text.
- Return match ranges alongside results. Highlight actual matching characters in the displayed name/content, using Unicode-safe boundaries. If a full-text match lies beyond the default preview, display a context excerpt containing it.
- Run nonempty searches away from the main actor with a short debounce. Cancel superseded requests and reject stale results after query, filter, snapshot, or presentation changes. Typing, navigation, and dismissal must remain responsive for large histories.
- Preserve the selected UUID if it remains in results; otherwise select the first result. Activating a result uses its UUID, not a stale row index.
- Empty results show a helpful message. Search does not mutate history, clipboard contents, or favorite order.

## Favorite management

- Add an Edit Favorite action to favorite rows, opening a native editor with optional name, multiline content, and optional shortcut slot 1–9.
- Save and Cancel are explicit; dismissing the editor does not save partial changes. Missing/deleted favorites show an error without recreating stale content.
- Names may be empty (fall back to the existing text preview). Reject blank/whitespace-only content and names longer than 200 characters. Preserve meaningful content whitespace exactly.
- Renaming, reordering, or assigning a shortcut preserves existing rich text. Changing content clears the old RTF and marks the clip as plain text. Explain this in the editor when editing a formatted favorite.
- Provide Move Up and Move Down actions in the Favorites filter; disable them at boundaries. Favoriting a new item places it at the top. Activating a favorite must not change its manual order, including when paste-moves-to-top is enabled.
- Shortcut slots are explicit and independent of row order. Reject a locally assigned occupied slot with a clear message. Reordering never changes the assigned shortcut.
- A favorite without an assigned slot remains fully usable. Show name, content preview, and assigned shortcut on its row without making content harder to inspect.

## Persistence and sync

- Extend clips with optional favorite name, shortcut slot, and persistent favorite rank. Preserve clip UUID, source metadata, captured date, content, and original RTF throughout unrelated changes.
- Use a transactional SQLite schema upgrade from existing versions 1 and 2. Legacy favorites retain their current order and receive empty names and no shortcuts. Old JSON backups and CloudKit payloads remain decodable with defaults.
- Preserve new metadata through every reconstruction path: capture/favoriting, repository normalization, persistence, backup/export where applicable, restore, and cloud merge. A local write failure leaves the visible saved state unchanged and reports the error.
- Sync favorite rank independently of capture date. Favorite renames, edits, shortcuts, and rank changes count as content changes in the ledger; recent position remains governed by existing history behavior.
- Retain existing per-clip last-writer-wins conflict resolution. Tie ranks sort deterministically by UUID. Concurrent reorder operations converge deterministically; merging is not a promise of whole-list transactional ordering across devices.
- Concurrent remote shortcut collisions must not trigger an arbitrary paste. Leave the metadata intact, disable ambiguous shortcut slots, and display a conflict so the user can resolve it in the editor.
- Existing older clients can read text but do not preserve metadata they do not understand when rewriting a favorite. Mixed-version metadata preservation is outside this implementation; test importing legacy payloads without claiming full backward write compatibility.
- Local save modes and existing privacy permissions remain authoritative. Sync remains opt-in; no new CloudKit record type is needed because metadata travels in the existing payload.

## Validation and local delivery

- Test independent hotkey routing, duplicate/configuration conflicts, and restoration after failed registration.
- Test numbered activation while search owns focus, plain numeric input, hidden favorite activation, missing rows, and explicit shortcut conflicts.
- Test exact-before-fuzzy ranking, typo/missing-letter queries, accent/case folding, emoji/composed characters, long text, result context, stale asynchronous searches, selection reconciliation, and both filters.
- Test favorite editor cancellation, validation, renaming versus content-edit formatting behavior, order stability after paste, persistent shortcut assignment, and deleted favorites.
- Test SQLite upgrades, restart/backup round trips, save failures, new and legacy cloud payloads, synced reorder, concurrent rank ties, and duplicate shortcut convergence.
- Run the full Swift test suite, build the universal local application, verify signing, then back up and replace the installed local build for user testing. Do not publish or push.
- Manual local checks cover opening history from another app, search focus, target-app paste, click dismissal, favorite editing/reordering, and the established Teams plain-text paste behavior. Live multi-Mac sync remains a user verification step if a second signed installation is unavailable.
