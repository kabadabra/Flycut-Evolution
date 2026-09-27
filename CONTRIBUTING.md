# Contributing to Flycut Evolution

Flycut Evolution is the free, MIT licensed Swift continuation of [TermiT/Flycut](https://github.com/TermiT/Flycut), maintained by Emerging Dynamics. Bug reports, ideas, and pull requests are welcome.

Before opening an issue, check for an existing report. For a bug, include your Flycut Evolution version, macOS version, clear steps using harmless sample text, and what happened. Never post clipboard history, private settings, API keys, signing files, or diagnostic logs that contain them.

For a code change, open an issue or pull request explaining the behavior you are changing. Keep the change focused, add a meaningful regression test where behavior changed, and run `swift test` plus `scripts/build-app.sh debug`. Developer ID signing is handled by release maintainers; contributors can use the separate preview app for local testing. See [developer notes](docs/DEVELOPING.md) for architecture and build instructions.

Please preserve the [MIT license](license.txt) and credit for the original Flycut, Jumpcut, and included contributors.
