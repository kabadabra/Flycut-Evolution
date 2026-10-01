# Priority 4: Capture privacy

## Goal and scope

Give users predictable control over what enters clipboard history, without affecting normal copying and pasting. Extend the existing sensitive-type protections with excluded applications, Ignore Next Copy, and timed pause. Preserve the completed keyboard, search, favorites, and plain-text paste behavior.

Implement this subsystem first. These specifications and subsequent work remain uncommitted until separately authorized. No release publication is included.

## Behavior

- Settings provides an excluded-app list with an application picker and removal controls. Store stable bundle identifiers locally, plus display names for the UI. Exclusions do not sync between Macs.
- Excluding an app affects future capture only. Existing history stays intact; users can delete it through existing controls.
- More offers Ignore Next Copy with a visible pending state and cancellation. Consume it on the next externally changed clipboard, including unsupported or sensitive contents. Flycut's own clipboard writes do not consume it. Multiple changes observed in one polling interval count as one observed change.
- Pause offers 5 minutes, 15 minutes, 1 hour, and manual pause. The menu and palette indicate the current state. Resume cancels any deadline.
- Timed pause is session-only. Existing remember-pause behavior continues to apply to manual pause. An absolute deadline handles sleep and wake; resume first advances the observed clipboard counter so copies made during pause are not imported afterward.
- These controls suppress history capture. They do not disable normal system clipboard operations or explicit paste from existing history.

## Architecture and data flow

Split capture policy into pre-read gates and content validation. Each clipboard observation first checks the counter, self-write suppression, pause/deadline, Ignore Next Copy, excluded source, and sensitive advertised types. Only then read text, RTF, or image bytes. Recheck the clipboard counter before accepting a result.

Extend ClipboardSource with the observed frontmost application's bundle identifier. Keep the existing injectable source provider and add clock injection for timed pause tests. Centralize pause and one-shot state rather than duplicating it between menu, settings, and monitor.

macOS does not reliably disclose the originating application for every clipboard update. App exclusions therefore use the application observed when the clipboard change is processed. Document this limitation honestly; do not claim perfect origin attribution or infer it from clipboard contents. Test rapid focus changes and polling behavior.

Sensitive advertised types apply to all formats before payload reads. Content-based filters remain text-only checks afterward. Never log captured content. The next image subsystem must use the same pre-read gate.

## Errors and verification

Unreadable application bundles produce a clear picker error and no partial exclusion. Invalid saved identifiers are ignored safely. A denied clipboard read does not retry the same content through another format to bypass denial.

Verify excluded and sensitive observations invoke zero payload reads; ordinary text and RTF still capture; self-writes do not consume one-shot state; ignored changes never appear later; pause expiry after wake skips paused content; manual pause persists according to existing preferences. Exercise menu/settings state agreement and exclusions with two local apps.

## Acceptance

Users can exclude an app, skip one copy, and pause temporarily without closing Flycut. Privacy gates precede every payload read, and the existing plain-text shortcut continues to paste reliably.
