# Compact clipping rows and rich hover preview

## Intent

Flycut Evolution's history should be easy to scan without a formatted copy making a row taller. A hovering user should be able to inspect the full copy before activating it. The palette's existing immediate single-click paste remains responsive.

## Experience

- Each clipping shows one plain-text line. Newlines, tabs, and repeated whitespace become one space for this label only. The configured character limit and available width truncate with an ellipsis. The stored text is unchanged.
- The source-app subtitle remains visible. Hovering a row briefly opens a preview to its right, positioned by macOS where space allows. Moving between rows updates the preview. The panel displays the complete copy in a scrollable area.
- For newly captured RTF text, the preview renders text styling. For older clips or unsupported formatting, it displays the full plain text. A normal single click or Return pastes the selected clipping with its original formatting when available. A small action at the right edge of formatted rows pastes that clipping as plain text. Shift–Command–V continues to paste the *current clipboard* as plain text, without changing the clipboard.

## Data and privacy

- Capture a bounded RTF representation only when the source offers plain text and RTF; preserve plain text as the canonical clip content and deduplication key. Reject oversized or malformed RTF and fall back to plain text. Do not capture RTFD attachments or HTML.
- Persist optional RTF in SQLite with a transactional schema migration from v1 to v2. Existing rows remain readable. Favorites, same-app recaptures, and CloudKit sync preserve the new representation. The existing private CloudKit history option includes the optional RTF for future copies.
- Rendering is deferred until the user hovers, so scrolling and clicking do not parse rich text. A formatted paste writes both plain and RTF representations to the pasteboard, allowing destinations to choose. A plain row action writes only plain text.

## Verification

- Test one-line normalization, truncation, and unchanged stored text.
- Test RTF capture and fallbacks, persistence migration, favorite/recapture preservation, CloudKit encode/merge, and formatted versus plain pasteboard writes.
- Build and run the full suite, then visually verify a multiline formatted TextEdit copy, a plain copy, scrolling, and immediate single-click paste in a signed local build. Confirm a synthetic rich copy reaches the second Mac before publishing.
