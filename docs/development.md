# Development

## Requirements

- macOS 14 or later
- Xcode with the macOS 14+ SDK
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen` — `scripts/bootstrap.sh` installs it via Homebrew if missing)

Swift version is 6.0 (`SWIFT_VERSION` in `project.yml`), with complete strict concurrency and `-default-isolation=MainActor`.

## Generate and build

`Omnibar.xcodeproj` is gitignored. Generate it from `project.yml`:

```bash
./scripts/bootstrap.sh
```

Release build to `build/Omnibar.app` (this also regenerates the project):

```bash
./scripts/build.sh
# or
make build
```

`scripts/build.sh` takes an optional configuration argument; the default is `Release`:

```bash
./scripts/build.sh Debug
```

Build and launch:

```bash
make run
```

`make run` kills an existing `Omnibar` process, then `open`s `build/Omnibar.app`.

Derived data for script builds lives in `build/DerivedData`. The copied app is `build/Omnibar.app`.

To work in Xcode:

```bash
./scripts/bootstrap.sh
open Omnibar.xcodeproj
```

The scheme is `Omnibar`; tests are attached as `OmnibarTests`.

## Signing

`project.yml` requests the "Apple Development" identity and Hardened Runtime. `scripts/build.sh` looks up a keychain identity named `Apple Development` unless `CODESIGN_IDENTITY` is set. If none is found, it signs ad-hoc (`-`) and prints that Accessibility must be re-granted after every rebuild.

After `xcodebuild`, the script copies the `.app` to `build/Omnibar.app` and `codesign`s it with `Omnibar/Resources/Omnibar.entitlements` and `--options runtime`.

## Release zip

`make release` (or `./scripts/package.sh`) builds a **universal** (arm64 + x86_64) app with the first **Developer ID Application** identity in the keychain, re-signs with a secure timestamp, submits a zip to Apple notary, staples the ticket, and writes `build/Omnibar-<MARKETING_VERSION>.zip` plus its SHA-256. Local `make build` stays host-architecture unless `ARCHS` is set.

It does not fall back to Apple Development. Override the identity with `CODESIGN_IDENTITY` (exact common name or SHA-1 hash). The notary keychain profile defaults to `notarytool-specktronica`; override with `NOTARYTOOL_PROFILE`. Store credentials interactively (the tool prompts; do not put a password on the command line or in git):

```bash
xcrun notarytool store-credentials notarytool-specktronica
```

`SKIP_NOTARY=1 make release` writes the zip without notarization. That archive will not pass Gatekeeper.

Publish `build/Omnibar-<version>.zip` as a GitHub Release asset on tag `v<version>`. Then update `version` and `sha256` in [specktronica/homebrew-omnibar](https://github.com/specktronica/homebrew-omnibar) `Casks/omnibar.rb`.

`scripts/bootstrap.sh` points `core.hooksPath` at `.githooks`. The pre-commit hook runs `scripts/check-secrets.sh` and blocks private keys, `.p8` / `.p12` files, and GitHub tokens. `make release` runs the same check against tracked files. Do not paste `security find-identity` output into issues.

TCC (Accessibility and Screen Recording) stores a code-signing **requirement**, not just the bundle ID:

- A development identity yields a requirement based on bundle ID and team, so grants survive rebuilds.
- An ad-hoc signature yields a `cdhash` requirement. That hash changes every build, so System Settings can still show Omnibar enabled while the new binary is untrusted.

Reset grants:

```bash
tccutil reset Accessibility io.specktronica.omnibar
tccutil reset ScreenCapture io.specktronica.omnibar
```

Do not run two Omnibar binaries at once. They share `io.specktronica.omnibar`, and only one designated requirement can match the TCC record.

The app is not sandboxed. Empty entitlements plus Hardened Runtime is the local-dev configuration; Accessibility and screen capture will not work in a sandbox with this entitlements file.

## Tests

```bash
./scripts/bootstrap.sh
xcodebuild -project Omnibar.xcodeproj -scheme Omnibar -destination 'platform=macOS' test
```

`OmnibarTests` is a unit-test bundle with `TEST_HOST` pointing at `Omnibar.app`. The test target must use the same development team as the app; ad-hoc signing the host fails with a Team ID mismatch on load.

There is no `make test` target.

## Project settings of note

From `project.yml`:

| Key | Value |
| --- | --- |
| Bundle ID | `io.specktronica.omnibar` |
| Deployment target | macOS 14.0 |
| `LSUIElement` | YES (accessory / no Dock icon) |
| Sandbox | off |
| Hardened Runtime | on |

Info.plist usage strings:

- Accessibility: list windows, switch, minimize, close, fullscreen
- Screen Recording: live hover thumbnails (optional)
