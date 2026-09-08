# Development

## Requirements

- macOS 14 or later
- Xcode with the macOS 14+ SDK
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen` — `scripts/bootstrap.sh` installs it via Homebrew if missing)
- `python3` for `make release` / `make publish` (notary JSON and cask patching)
- authenticated `gh` for `make publish` (`brew install gh`)

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

`make remove` (`scripts/remove.sh`) uninstalls installed copies. It quits a running Omnibar (Apple Event, then SIGTERM/SIGKILL), restores Dock settings from `omnibar.dock.backup.v1` when that key exists, or from the fully-hidden signature (`autohide-delay` 1000 and orientation `top`), deletes the System Events login item named Omnibar, registers a remaining `Omnibar.app` (Applications, then `build/Omnibar.app`) and runs `tccutil reset All io.specktronica.omnibar` before any unregister/delete so Launch Services can still resolve the bundle ID, then runs `brew uninstall --cask --zap omnibar` when the cask is installed, deletes `/Applications/Omnibar.app` and `~/Applications/Omnibar.app`, deletes Xcode DerivedData `Omnibar.app` products (`~/Library/Developer/Xcode/DerivedData/Omnibar-*/Build/Products/*/Omnibar.app`), unregisters remaining Launch Services records for `io.specktronica.omnibar`, deletes the `io.specktronica.omnibar` defaults domain and related Library caches, and untaps `specktronica/omnibar`. It does not delete `build/Omnibar.app` or `build/DerivedData`. `brew uninstall --cask --zap specktronica/omnibar/omnibar` is the cask-only path; if Omnibar is not running, zap can delete the Dock backup without restoring it. If `sfltool dumpbtm` still lists `io.specktronica.omnibar` after `make remove`, disable the leftover Login Item in System Settings → General → Login Items.

Derived data for script builds lives in `build/DerivedData`. The copied app is `build/Omnibar.app`.

To work in Xcode:

```bash
./scripts/bootstrap.sh
open Omnibar.xcodeproj
```

The scheme is `Omnibar`; tests are attached as `OmnibarTests`.

## Signing

`project.yml` requests the "Apple Development" identity and Hardened Runtime for Xcode IDE builds. `scripts/build.sh` prefers `CODESIGN_IDENTITY` if set, then Developer ID Application, then Apple Development, then ad-hoc. Developer ID makes `make run` share the same designated requirement as the Homebrew cask.

After `xcodebuild`, the script copies the `.app` to `build/Omnibar.app`, unregisters repo and Xcode DerivedData products from Launch Services, `codesign`s with `Omnibar/Resources/Omnibar.entitlements`, `--options runtime`, and `--timestamp=none`, then registers `build/Omnibar.app`.

## Release zip

`make release` (or `./scripts/package.sh`) builds a **universal** (arm64 + x86_64) app with the first **Developer ID Application** identity in the keychain, re-signs with a secure timestamp, submits a zip to Apple notary, staples the ticket, and writes `build/Omnibar-<MARKETING_VERSION>.zip` plus its SHA-256. Local `make build` stays host-architecture unless `ARCHS` is set. Notary JSON is parsed with `python3`.

It does not fall back to Apple Development. Override the identity with `CODESIGN_IDENTITY` (exact common name or SHA-1 hash). The notary keychain profile defaults to `notarytool-specktronica`; override with `NOTARYTOOL_PROFILE`. Store credentials interactively (the tool prompts; do not put a password on the command line or in git):

```bash
xcrun notarytool store-credentials notarytool-specktronica
```

`SKIP_NOTARY=1 make release` writes the zip without notarization. That archive will not pass Gatekeeper.

`make publish` (or `./scripts/publish.sh`) needs authenticated `gh` (`brew install gh`) and `python3`. It uploads `build/Omnibar-<version>.zip` to a GitHub Release on tag `v<version>` and sets `version` and `sha256` in [specktronica/homebrew-omnibar](https://github.com/specktronica/homebrew-omnibar) `Casks/omnibar.rb`. The zip must be stapled; `SKIP_NOTARY=1` archives are rejected. Creating a new tag requires a clean `main` that matches `origin/main`. `DRY_RUN=1` prints the plan. `FORCE=1` replaces a same-version release asset and cask checksum.

```bash
make release publish
```

`scripts/bootstrap.sh` points `core.hooksPath` at `.githooks`. The pre-commit hook runs `scripts/check-secrets.sh` and blocks private keys, `.p8` / `.p12` files, and GitHub tokens. `make release` runs the same check against tracked files. Do not paste `security find-identity` output into issues.

TCC (Accessibility and Screen Recording) stores a code-signing **requirement**, not just the bundle ID:

- System Settings binds a grant to the copy Launch Services resolves for the bundle ID. "Quit & Reopen" relaunches that copy.
- Developer ID and the published cask share a team-based requirement, so `make run` and a cask install are interchangeable when both are Developer ID signed.
- A development identity yields a different requirement than Developer ID. Grants made while a cask copy is installed will not match an Xcode-signed process.
- An ad-hoc signature yields a `cdhash` requirement. That hash changes every build, so System Settings can still show Omnibar enabled while the new binary is untrusted.

If onboarding names another copy, move that copy to the Trash or quit and use it instead.

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

Tests are pure-logic only. There are no live Accessibility, hotkey, or event-monitor tests; tiling is covered through `TilingGeometryTests` (usable area, tile frames, keyboard cycle, coordinate conversion, Carbon flags) and the settings-decode tests.

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
