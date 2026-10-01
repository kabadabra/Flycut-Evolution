# Priority 6: Signed updates and first-run setup

## Goal and scope

Help users configure capture and paste permissions, understand shortcuts, and install trustworthy releases. Add onboarding and updater integration after privacy and image history. Prepare and verify the local release tooling; publication, commits, and pushes remain separate user decisions.

## Updates

Integrate a pinned stable Sparkle 2 release through Swift Package Manager and SPUStandardUpdaterController. Embed and sign its framework and helpers in the app bundle; preserve symlinks and executable modes. Keep hardened-runtime protections and Developer ID signing intact.

Automatic update checks default off. Settings explains the network check and lets users opt in. More and Settings provide Check for Updates. Download and installation remain user-approved through the standard updater UI. Show release notes before installation. Do not enable silent automatic installation.

Use an HTTPS appcast at `https://github.com/kabadabra/Flycut-Evolution/releases/latest/download/appcast.xml`, published alongside future approved releases. An unavailable or unpublished feed produces an honest unavailable result, never an up-to-date claim. Network and signature failures leave the current app intact.

Use separate monotonically increasing CFBundleVersion build numbers while retaining a human-readable marketing version. The existing local feature build can remain version 1.0.2; the final release version is chosen before publication. Never pretend a same-build local iteration is a newer production release.

Sign update archives using Sparkle's Ed25519 signing support and distribute Developer ID signed, notarized applications. Keep only the public update key in source/Info.plist. Store private signing material in Keychain or CI secrets; never print or commit it. Add generation/verification scripts and CI integration with explicit prerequisites. Enable signed-feed verification when supported by the pinned release and tooling.

Adapt existing build, signing, notarization, and verification scripts to validate embedded updater components and runtime search paths. Preserve existing distribution behavior. Add the actual dependency's required license acknowledgments.

## First-run setup

Present a short dismissible setup window once for fresh installations. Existing installations continue opening history normally and can launch Setup from Settings or More. Track completion locally; users can revisit or dismiss setup without losing functionality.

Steps cover capture privacy and image preferences, history versus immediate plain-text paste shortcuts, Accessibility permission status, optional update checks, and a guided paste exercise. Explain which capabilities require Accessibility. Request permission only when the user chooses the corresponding action; refresh status when the app regains focus and provide the existing System Settings link.

The paste exercise copies a harmless sample only after an explicit click and instructs the user to focus a chosen application's text field and invoke the shortcut. Ask the user to confirm the result; do not label synthetic self-app typing as proof of universal paste support. Do not send messages or create external documents as part of setup.

Update consent and image-sync consent are separate controls, both off by default. Existing users enabling image capture receive the same privacy explanation in settings. Setup must not steal focus during an ordinary history selection or dismiss a permission dialog prematurely.

## Validation and release boundary

Verify opt-in defaults and persistence, manual check availability, unavailable-feed and invalid-signature handling, setup completion/reopen behavior, permission refresh, and preservation of shortcut/paste behavior. Build both supported architectures, inspect embedded signatures, and run existing app verification.

Use a separate temporary app bundle and local fixture feed for updater integration tests. Do not overwrite the user's installed app with a fake update or publish fixture versions. A real public update round trip cannot be claimed until an approved notarized release and feed are published.

Deliver the locally installed feature build, passing tests, and prepared release scripts with any remaining release prerequisites stated clearly. No production feed or release is published in this task.

References: [Sparkle integration](https://sparkle-project.org/documentation/), [publishing updates](https://sparkle-project.org/documentation/publishing/), and [framework/helper signing guidance](https://sparkle-project.org/documentation/sandboxing/).
