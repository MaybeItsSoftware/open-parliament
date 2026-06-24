---
name: mobile-release-setup
description: >-
  Stand up TestFlight + Google Play release automation for a new
  maybeitssoftware mobile app. Covers app identity, the per-repo GitHub Actions
  secrets model, code signing, the CI/CD pipeline shape, and Apple/Play console
  onboarding. Framework-agnostic — Flutter is included as a worked appendix.
  Use when creating a new app's release pipeline or onboarding a repo to
  TestFlight/Play deployment.
---

# Mobile release setup (maybeitssoftware)

A reusable runbook for taking a new mobile app from "code exists" to
"pushes to `main` ship to TestFlight + Play internal track." The core is
stack-independent; framework specifics live in the appendices.

Placeholders to substitute per app: `<app>` (short slug, e.g. `openparliament`),
`<PROFILE_NAME>` (e.g. `Open Parliament Distribution`),
`<SENTRY_PROJECT>` (e.g. `open-parliament`).

---

## 1. Identity conventions

| Thing | Value / rule |
|---|---|
| Bundle / Application ID | `uk.co.maybeitssoftware.<app>` (reverse-domain, lowercase, no separators) |
| Apple Team ID | `6NQNU5YSC2` |
| Android upload keystore alias | `maybeitssoftware-gh-actions` (shared — see §2) |
| App display name | Human-readable, e.g. "Open Parliament" |
| Package/namespace (code) | May differ from the bundle ID and is **not** user-visible — do not churn it just to rebrand |

The bundle ID is the single identifier that must match across: iOS
`PRODUCT_BUNDLE_IDENTIFIER`, `ios/ExportOptions.plist` provisioning entry,
Android `namespace` + `applicationId`, the Kotlin package dir, the provisioning
profile's `application-identifier`, and the Play `packageName` in the workflow.

---

## 2. Security model — per-repo secrets, reused values

GitHub **org/Team-shared secret stores require sharing across private repos**,
which the standard subscription does not allow. So every repo stores its own
copy of the Actions secrets. **This is a storage constraint only — the
credential _values_ are reused wherever they legitimately can be.**

- **Reusable `[R]`** — paste the identical value into every app's repo. These
  are account/org-level credentials: the Apple distribution certificate, the
  App Store Connect API key, the **shared Android upload keystore**, the
  centralized Play service account, and the Sentry auth token + org.
- **Unique `[U]`** — regenerated per app: the provisioning profile (bound to
  one App ID + profile name), and the per-app Sentry project/DSN.

The shared upload-key fingerprint is mapped into each new app during Play App
Signing onboarding so all apps share one upload identity.

> **Never** put signing material in a runtime `.env` if that `.env` is bundled
> as an app asset (common with `flutter_dotenv` and similar) — it would ship
> inside the released binary and be extractable. Keep `.env` to non-secret
> client values (e.g. a Sentry DSN); everything else lives only in GitHub
> Actions secrets.

---

## 3. Secrets matrix

15 secrets, consumed only by the deploy workflow. `[R]` reusable / `[U]` unique.

| Secret | R/U | What it is / how to produce |
|---|---|---|
| `DIST_CERTIFICATE_BASE64` | R | `base64 -i AppleDistribution.p12` |
| `DIST_CERTIFICATE_PASSWORD` | R | password set when exporting the `.p12` |
| `PROVISIONING_PROFILE_BASE64` | U | `base64 -i "<PROFILE_NAME>.mobileprovision"` |
| `APP_STORE_CONNECT_API_KEY_ID` | R | ASC API key ID (Users & Access → Integrations) |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | R | ASC issuer UUID |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | R | `base64 -i AuthKey_XXXX.p8` |
| `ANDROID_KEYSTORE_BASE64` | R | `base64 -i upload-keystore.jks` (shared key) |
| `KEYSTORE_PASSWORD` | R | keystore password |
| `KEY_ALIAS` | R | `maybeitssoftware-gh-actions` |
| `KEY_PASSWORD` | R | key password |
| `PLAY_STORE_SERVICE_ACCOUNT_JSON` | R | full service-account JSON (plaintext) |
| `SENTRY_AUTH_TOKEN` | R | org token, `project:releases` scope |
| `SENTRY_ORG` | R | `maybeitssoftware` |
| `SENTRY_PROJECT` | U | `<SENTRY_PROJECT>` |
| `SENTRY_DSN` | U | per-app DSN (also the one runtime-bundled value) |

Push them from a populated `.env` with a helper that pipes each value via
stdin (so values never hit process args). See this repo's
`scripts/set-github-secrets.sh` for a reference implementation.

> **Public repos are fine.** Actions secrets are encrypted and are **not**
> exposed to workflows triggered by `pull_request` from forks. Keep deploy
> jobs on `push:[main]` / `workflow_dispatch` (never `pull_request`) and keep
> any PR-triggered CI free of secrets.

---

## 4. CI/CD pipeline shape (pattern)

Two workflows:

- **CI gate** (`ci.yml`) — runs on `push` + `pull_request`: dependency fetch,
  static analysis, unit tests. **No secrets.** This is what fork PRs run.
- **Deploy** (`deploy.yml`) — runs on `push:[main]` + `workflow_dispatch`:

  ```
  test (analyze + unit tests)         # shared gate
   ├─ deploy-ios      (macOS runner)  # needs: test
   └─ deploy-android  (ubuntu runner) # needs: test
  ```

  - **iOS job**: create a temp keychain → import dist cert → install
    provisioning profile → build release IPA against `ExportOptions.plist`
    (manual signing, `app-store` method) → upload to TestFlight via the ASC API
    key → upload dSYMs to Sentry → delete the keychain (`if: always()`).
  - **Android job**: decode the keystore → write `key.properties` at runtime →
    build release AAB → upload to the Play **internal** track → upload native
    symbols to Sentry.

This repo's `.github/workflows/deploy.yml` is the **reference implementation**;
copy and adapt it per app (it is intentionally repo-specific, not templated
here). The shape above is the part that is reusable.

---

## 5. Apple + Google Play onboarding (per app, manual)

**Apple Developer / App Store Connect**
1. Register App ID `uk.co.maybeitssoftware.<app>` (no special entitlements unless needed).
2. Create the **App Store Connect app record** — required before any TestFlight upload.
3. Reuse the account distribution certificate (`[R]`). Create a distribution
   provisioning profile named exactly `<PROFILE_NAME>` — the name must match
   `ExportOptions.plist`. Validate with:
   `security cms -D -i <file> | plutil -p -` → check `Name`, `application-identifier`,
   and absence of `ProvisionedDevices` (App Store profiles have none).

**Google Play Console**
4. Create the app; **do an initial manual `.aab` upload** — the
   `r0adkll/upload-google-play` action fails if the package doesn't already exist.
5. During first setup, map the **shared upload key fingerprint** into Play App
   Signing so all apps share one upload identity.
6. Users & Permissions → invite
   `github-actions-deployer@maybeitssoftware.iam.gserviceaccount.com` and grant
   release-manager access **scoped to this app** (the master service account is
   centralized; bindings are per-app).

---

## 6. Verification checklist

- [ ] `analyze` + unit tests pass locally (mirrors the CI gate).
- [ ] Release builds succeed locally (signing should fall back to debug when
      release credentials are absent — see appendix).
- [ ] All 15 secrets present: `gh secret list --repo <owner>/<repo>`.
- [ ] Bundle ID consistent across iOS/Android/profile/Play `packageName`.
- [ ] Provisioning profile `Name` matches `ExportOptions.plist`, not expired.
- [ ] Apple app record + Play app exist; Play had its first manual upload.
- [ ] First `workflow_dispatch` run: both jobs green; build visible in
      TestFlight and the Play internal track.

---

## Appendix A — Flutter specifics (worked example)

The Open Parliament repo is the first instantiation.

- **Bundle-ID migration** (off the `com.example.*` template): update
  `ios/Runner.xcodeproj/project.pbxproj` (`PRODUCT_BUNDLE_IDENTIFIER`,
  `DEVELOPMENT_TEAM`), Android `build.gradle.kts` (`namespace`, `applicationId`),
  `AndroidManifest.xml` label, move `MainActivity.kt` into the new Kotlin
  package dir and fix its `package` line, and macOS test bundle IDs. Verify with
  `grep -rn 'com.example'` returning nothing.
- **Android signing engine**: `android/app/build.gradle.kts` reads a root
  `key.properties` if present and builds a `release` signing config from it;
  if absent it falls back to debug signing so local dev is unhindered. CI writes
  `key.properties` at runtime from the secrets.
- **Toolchain**: modern declarative Kotlin DSL (`.kts`) only — delete legacy
  Groovy `build.gradle`/`settings.gradle` duplicates. Keep Gradle wrapper / AGP /
  KGP aligned with the Flutter version's requirements.
- **Build commands**:
  `flutter build ipa --release --export-options-plist=ios/ExportOptions.plist`
  and `flutter build appbundle --release`.
- **Runtime `.env`**: declared as a bundled asset, so it carries `SENTRY_DSN`
  only. Sentry symbol upload is handled by `sentry_dart_plugin` at build time
  plus a `sentry-cli` step in the workflow.

## Appendix B — adding another stack

When onboarding a non-Flutter app (React Native, native, etc.): §§1–6 apply
unchanged. Only the build commands, the signing-config mechanism, and the
artifact paths in the deploy workflow differ — document them as a new appendix
alongside this one.
