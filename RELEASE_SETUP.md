# Releasing Flycut Evolution

The [release workflow](.github/workflows/release.yml) builds the Swift package on the configured `xcode-27` runner with Xcode 27.0, runs tests, bundles a universal arm64/x86_64 `Flycut Evolution.app`, signs with Developer ID and hardened runtime, notarizes/staples the app, then creates, signs, notarizes/staples and validates `Flycut-Evolution.dmg`. It also mounts the image read-only and verifies the app inside it. This runner label must be available in the repository; it is not the `macos-latest` label.

Publication requires a push of a tag matching exactly `vX.Y.Z`. A manual `workflow_dispatch` is always a **nonpublishing signed dry run**, even when run against a tag. Both paths require all signing/notarization credentials; missing credentials fail rather than producing a public-looking unsigned artifact. Local ad hoc builds remain available through `scripts/build-app.sh`.

## One-time Apple setup

Use the Developer ID Application certificate for the Emerging Dynamics signing team (`M2L9SL9WCS`). The Swift app uses `com.edynamics.flycut`, the private CloudKit container `iCloud.com.edynamics.flycut`, and no embedded legacy login helper. The Developer ID provisioning profile must authorize that app ID, container, production iCloud environment, and push notifications. Export the certificate and private key as a password-protected `.p12`. In App Store Connect, create a Team API key that can submit notarization requests; download its `.p8` file and record its Key ID and Issuer ID. The original project's team ID, iCloud container, and App Store listing do not belong to this fork.

The CloudKit Console Production schema must contain the `FlycutClip` record type with `payload` (Encrypted Bytes) and `payloadAsset` (Asset). Verify the schema in Production before signing a release. Keep the profile and keys outside Git.

In the fork's GitHub repository, add these Actions secrets:

| Secret | Value |
| --- | --- |
| `CERTIFICATES_P12` | Base64-encoded Developer ID Application `.p12` |
| `CERTIFICATES_PASSWORD` | Password used to export the `.p12` |
| `NOTARY_KEY` | Base64-encoded App Store Connect `.p8` key |
| `NOTARY_KEY_ID` | API key's Key ID |
| `NOTARY_ISSUER_ID` | API key's Issuer ID |
| `DEVELOPER_ID_PROFILE` | Base64-encoded Flycut Developer ID CloudKit `.provisionprofile` |

For example, after setting `REPO` to the dedicated Flycut Evolution repository:

```sh
REPO=kabadabra/Flycut-Evolution
base64 -i Certificates.p12 | gh secret set CERTIFICATES_P12 -R "$REPO"
base64 -i AuthKey_XXXXXXXXXX.p8 | gh secret set NOTARY_KEY -R "$REPO"
base64 -i Flycut_Evolution_Developer_ID_CloudKit.provisionprofile | gh secret set DEVELOPER_ID_PROFILE -R "$REPO"
gh secret set CERTIFICATES_PASSWORD -R "$REPO"
gh secret set NOTARY_KEY_ID -R "$REPO" --body 'XXXXXXXXXX'
gh secret set NOTARY_ISSUER_ID -R "$REPO" --body 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
```

Do not commit credentials. The workflow uses temporary private files and a temporary keychain, and cleans them up without replacing the runner's normal keychain search list.

## Review and dry run

1. Use Xcode 27.0 / Swift 6.4. Run `swift test`, `scripts/build-app.sh debug`, `scripts/build-app.sh release`, and `scripts/verify-app.sh 'build/Export/Flycut Evolution.app'`.
2. Check `App/AppInfo.plist`: production ID `com.edynamics.flycut`, version and build version matching the release tag, minimum macOS `14.0`. Version tags supply a strictly numeric `VERSION` environment value to the bundler; branch dry runs use the committed plist version. Update both plist version fields and the matching `## X.Y.Z` changelog section for each release.
3. Complete and record the manual gates in [developer notes](docs/DEVELOPING.md): migration, menu/palette, keyboard/paste, privacy, Accessibility, Login Items, Cloud Sync between two Macs, and macOS 27 installation.
4. Run the reviewed commit through CI and manually dispatch **Build and Release**. Download the `Flycut-Evolution-dmg` artifact. This signs and notarizes but does not publish.
5. Verify the downloaded DMG and mounted app, then complete an installation test using a disposable profile or test Mac. Do not replace a daily-use app until review is complete.

```sh
codesign --verify --strict --verbose=2 Flycut-Evolution.dmg
xcrun stapler validate Flycut-Evolution.dmg
spctl -a -t open --context context:primary-signature -vv Flycut-Evolution.dmg
# After mounting the image, pass its actual app path:
VERSION=1.0.2 REQUIRE_DEVELOPER_ID=1 REQUIRE_NOTARIZATION=1 \
  scripts/verify-app.sh '/Volumes/Flycut Evolution/Flycut Evolution.app'
```

`verify-app.sh` checks the production bundle/executable, version, macOS floor, arm64 and x86_64 executable slices, icon and signature. Release mode also requires Developer ID Application authority, team `M2L9SL9WCS`, hardened runtime, timestamp, valid stapled ticket and Gatekeeper acceptance. A local ad hoc verification does not establish notarization or installation readiness.

## Publish after approval

After every gate passes, push the matching `vX.Y.Z` tag from the reviewed commit. Only the tag-push event may create a GitHub Release. The DMG contains **Flycut Evolution.app** and an Applications shortcut. Release notes include the exact matching changelog section, contributor credits, macOS requirements and migration instructions. Preserve the [v2.0.0 release](https://github.com/kabadabra/Flycut/releases/tag/v2.0.0) for older Macs.

Flycut remains free and MIT licensed, maintained by Emerging Dynamics, with credit to TermiT/Flycut, Jumpcut and merged contributors. Cloud Sync is opt-in and uses the user's private iCloud database. The production Swift app shares the 2.0 identity: quit the old app, explicitly launch the new app, verify migration and backups, then remove the old `Flycut 2.0.app`. See the [upgrade guide](readme.md#moving-to-flycut-evolution).

## Signed update releases

The updater is pinned to Sparkle 2.10.0. The appcast URL is `https://github.com/kabadabra/Flycut-Evolution/releases/latest/download/appcast.xml`. Automatic checks default off. A missing feed is reported as unavailable until a release is published.

`App/AppInfo.plist` contains only the public update key. `scripts/generate-update-keys.sh` creates/reuses a dedicated Keychain account, `com.edynamics.flycut.updates`, and refuses silent public-key rotation. The private key has not been exported into this repository. Back it up securely before relying on production updates; losing it requires a planned key rotation.

For CI, set the repository secret `SPARKLE_PRIVATE_KEY` to the private update key through GitHub's secret UI. Use the pinned `generate_keys --account com.edynamics.flycut.updates -x <secure-file>` tool only when explicitly exporting for that purpose. Keep that file private, outside the repository, and remove it after securely transferring the secret. Never put it in a commit, release asset, log, or command-line argument. The generator passes CI key data to signing tools over standard input.

Marketing version remains `CFBundleShortVersionString`; build ordering uses integer `CFBundleVersion`. The 1.0.2 production release uses build 10006. Local test builds used 10003–10005. Every future production release must use a greater build number and its own release tag. Set the number in AppInfo.plist before building, or pass BUILD_NUMBER for a local fixture. Verify the build number before publication.

Release CI requires the update key in addition to Developer ID, profile, and notarization credentials. It packages the stapled application into an update ZIP, generates a signed appcast and signed Markdown notes, verifies signatures, and uploads them alongside the existing DMG. Publication remains tag-push only; a manual dispatch remains nonpublishing. `scripts/generate-appcast.sh <archive-directory> <https-download-prefix>` validates Developer ID/notarization for production ZIPs and does not publish anything.

## Image CloudKit schema

Before public image syncing, deploy record type `FlycutImage` in the existing `FlycutEvolution` private-database zone with a `payloadAsset` Asset field. Assets use CloudKit's built-in asset encryption. Keep the existing `FlycutClip` schema intact. Older builds skip the new record type. Do not expose clip contents in public-database records or analytics.

Image sync is separately consented on every Mac. Production schema deployment and an actual two-Mac sync/real public updater round trip remain release validation steps; local tests cover transport encoding, validation, signatures, and consent filtering.
