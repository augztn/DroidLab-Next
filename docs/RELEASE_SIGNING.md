# Desktop release signing

The desktop release workflow builds Linux, Windows, and macOS artifacts for `v*` tags (or a manually selected existing tag). It runs Flutter analysis and tests before packaging.

## Configure signing credentials

Signing credentials are not committed to this repository. Add these GitHub Actions repository or environment secrets before publishing signed builds:

| Secret | Purpose |
| --- | --- |
| `WINDOWS_SIGNING_CERTIFICATE_BASE64` | Base64-encoded code-signing PFX certificate |
| `WINDOWS_SIGNING_CERTIFICATE_PASSWORD` | PFX password |
| `MACOS_SIGNING_CERTIFICATE_BASE64` | Base64-encoded Developer ID Application P12 certificate |
| `MACOS_SIGNING_CERTIFICATE_PASSWORD` | P12/keychain password |
| `MACOS_SIGNING_IDENTITY` | Exact Developer ID Application identity shown by `security find-identity` |

Windows signing uses Authenticode SHA-256 with an RFC 3161 timestamp. macOS signing uses hardened runtime and a secure timestamp. Do not use a Developer ID Installer identity for the app bundle.

## Notarization

macOS notarization additionally requires an App Store Connect API key (`.p8`), key ID, issuer ID, and Apple Developer team ID. These credentials must be added as protected secrets and wired into the release workflow before claiming notarized distribution. A signed app is not automatically notarized.

## Unsigned builds

If signing secrets are absent, the build may be packaged unsigned for internal testing. Do not describe those artifacts as signed or distribute them as trusted public installers. Windows users will see an untrusted publisher warning; macOS Gatekeeper may block the app.

## Release checklist

1. Validate the exact tag commit and confirm CI is green.
2. Confirm the signing secrets are current and the certificates are valid.
3. Build and sign each platform artifact.
4. Verify Windows signatures with `signtool verify /pa /v` and macOS signatures with `codesign --verify --deep --strict`.
5. If configured, notarize and staple the macOS app before packaging.
6. Download and smoke-test the published artifacts on clean machines before announcing the release.