# Release cheat sheet

## What do you want to do?

```
┌─────────────────────────────────────────────────────────────────────┐
│  WHAT DO YOU WANT TO DO?                                            │
└──────────┬──────────────────────────────────────────────────────────┘
           │
     ┌─────┴──────────────────────────────────────────────────────┐
     │                                                            │
     ▼                                                            ▼
┌─────────────────┐                                   ┌───────────────────┐
│ Ship new code   │                                   │ Manage testers    │
│ to testers      │                                   │                   │
└────────┬────────┘                                   └─────────┬─────────┘
         │                                                      │
         │                                         ┌────────────┼────────────┐
         ▼                                         ▼            ▼            ▼
  ┌─────────────┐                           ┌──────────┐ ┌──────────┐ ┌──────────┐
  │ 1. Commit   │                           │  iOS     │ │  iOS     │ │ Android  │
  │    (see     │                           │ internal │ │ external │ │ internal │
  │    table)   │                           └────┬─────┘ └────┬─────┘ └────┬─────┘
  └──────┬──────┘                               │            │            │
         │                                      │            │            │
         ▼                                      ▼            ▼            ▼
  ┌─────────────┐                     App Store Connect  TestFlight   Play Console
  │ 2. Push to  │                     → Users & Access  → Groups     → Internal
  │    main     │                     → add as          → create     │  testing
  └──────┬──────┘                       team member       group      → Testers tab
         │                                                → add       → add emails
         ▼                                                  testers
  ┌────────────────────────────────────────┐      Then add to Fastfile:
  │ CI runs automatically:                 │        distribute_external: true
  │  release.yml                           │        groups: ["Your Group Name"]
  │   ├─ tests pass                        │
  │   └─ semantic-release bumps version    │
  │       creates git tag (e.g. v0.2.0)   │
  │                                        │
  │  deploy.yml (triggered by tag)         │
  │   ├─ iOS  → TestFlight                 │
  │   └─ Android → Play internal track     │
  └────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────┐
│  WHAT DO YOU WANT TO DO? (continued)                                │
└──────────┬──────────────────────────────────────────────────────────┘
           │
     ┌─────┴──────────────────────────────────────────────────────┐
     │                                                            │
     ▼                                                            ▼
┌─────────────────┐                                   ┌───────────────────┐
│ Go live /       │                                   │ Re-run a deploy   │
│ promote to      │                                   │ (no new commit)   │
│ production      │                                   └─────────┬─────────┘
└────────┬────────┘                                             │
         │                                                      ▼
         ▼                                         GitHub → Actions
  GitHub → Actions                                 → "Deploy to TestFlight
  → "Promote to Production"                           & Play Store"
  → Run workflow                                    → Run workflow
  → Enter version: v0.2.0                           (uses latest tag)
         │
         ├── iOS  → submitted for App Store review (~1–3 days)
         └── Android → promoted to production track
```

---

## Commit message → version bump table

| Commit prefix | Example | Bump | New version |
|---|---|---|---|
| `fix:` | `fix: crash on empty debate` | patch | 0.1.0 → 0.1.1 |
| `feat:` | `feat: add bill search` | minor | 0.1.0 → 0.2.0 |
| `feat!:` or `BREAKING CHANGE:` in footer | `feat!: remove legacy API` | major | 0.1.0 → 1.0.0 |
| `chore:` / `docs:` / `test:` / `refactor:` | anything else | none | no tag created |

---

## Troubleshooting

```
Something broken?
│
├── Version not bumping?
│   ├── Check commit message uses conventional format (see table above)
│   └── GitHub → Actions → release.yml → view logs
│
├── Build not uploading?
│   ├── GitHub → Actions → deploy.yml → view logs
│   └── Check all required secrets are set (repo Settings → Secrets):
│
│       SENTRY_DSN
│       MATCH_GIT_SSH_KEY
│       MATCH_PASSWORD
│       APP_STORE_CONNECT_API_KEY_ID
│       APP_STORE_CONNECT_API_KEY_ISSUER_ID
│       APP_STORE_CONNECT_API_KEY_CONTENT
│       ANDROID_KEYSTORE_BASE64
│       KEYSTORE_PASSWORD
│       KEY_ALIAS
│       KEY_PASSWORD
│       PLAY_STORE_SERVICE_ACCOUNT_JSON
│
└── Testers not seeing the build?
    ├── iOS internal  → are they in App Store Connect team?
    ├── iOS external  → has the first build of this version passed TestFlight review?
    │                   (subsequent builds in the same version are instant)
    └── Android       → are they added in Play Console → Internal testing → Testers?
```

---

## End-to-end timeline (happy path)

```
You push to main
    │  ~2 min
    ▼
Tests + analysis pass
    │  ~1 min
    ▼
semantic-release tags + bumps pubspec.yaml
    │  triggers immediately
    ▼
deploy.yml starts
    │  ~20 min (iOS build on macos-15)
    │  ~10 min (Android build on ubuntu)
    ▼
Build live on TestFlight (internal) + Play internal track
    │
    └── External TestFlight groups: instant if version already reviewed,
        ~24 h Apple review for first build of a new version
```
