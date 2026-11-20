# Releasing

Releases are signed with a Developer ID certificate, notarized by Apple, and published as a zip on GitHub Releases. `release.sh` does all of it; it runs on the machine that has the certificate.

## One-time setup (signing machine)

1. **Certificate:** a *Developer ID Application* certificate with its private key in the login keychain. Check with:
   ```sh
   security find-identity -v -p codesigning
   ```
2. **Notarization credentials:** create an app-specific password at <https://account.apple.com> (Sign-In and Security → App-Specific Passwords), then store it in the keychain:
   ```sh
   xcrun notarytool store-credentials macmxswitch-notary \
     --apple-id "<your Apple ID>" --team-id "<TEAMID>" --password "<app-specific password>"
   ```
   (An App Store Connect API key works too: `--key`, `--key-id`, `--issuer`.)
3. **Tools:** Xcode Command Line Tools, and `gh` logged in (`gh auth login`) with access to the repo.

## Cutting a release

1. Bump `VERSION` (e.g. `1.0.0` → `1.1.0`), commit and push to `main`.
2. On the signing machine, pull `main` and run:
   ```sh
   ./release.sh --publish
   ```
   This builds, signs with hardened runtime, notarizes, staples, zips, and creates the GitHub release `v<VERSION>` with `MacMXSwitch-<VERSION>.zip` and its SHA-256.

Run `./release.sh` without `--publish` to produce the signed, notarized zip in `build/` without creating a release.

If more than one Developer ID Application identity is in the keychain, pick one:
```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./release.sh --publish
```
