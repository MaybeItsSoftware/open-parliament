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
  ┌─────────────┐                           ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
  │ 1. Commit   │                           │  iOS     │ │  iOS     │ │ Android  │ │ Android  │
  │    (see     │                           │ internal │ │ external │ │ internal │ │ closed   │
  │    table)   │                           └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘
  └──────┬──────┘                               │            │            │            │
         │                                      │            │            │            │
         ▼                                      ▼            ▼            ▼            ▼
  ┌─────────────┐                     App Store Connect  TestFlight   Play Console  Play Console
  │ 2. Push to  │                     → Users & Access  → Groups     → Internal    → Testing →
  │    main     │                     → add as          → create     │  testing   Closed testing
  └──────┬──────┘                       team member       group      → Testers tab → Alpha track
         │                                                → add       → add emails  → add emails
         ▼                                                  testers                (already wired
  ┌────────────────────────────────────────┐      Then add to Fastfile:            into every beta
  │ CI runs automatically:                 │        distribute_external: true      deploy — nothing
  │  release.yml                           │        groups: ["Your Group Name"]    to add to Fastfile)
  │   ├─ tests pass                        │
  │   └─ semantic-release bumps version    │
  │       creates git tag (e.g. v0.2.0)   │
  │                                        │
  │  deploy.yml (runs after release.yml     │
  │  finishes; only proceeds if a new tag  │
  │  was actually created — see below)     │
  │   ├─ iOS  → TestFlight (internal)       │
  │   └─ Android → Play internal + closed  │
  │       (alpha) testing track — both     │
  │       get every beta build automatically│
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
├── Testers not seeing the build?
│   ├── iOS internal  → are they in App Store Connect team?
│   ├── iOS external  → has the first build of this version passed TestFlight review?
│   │                   (subsequent builds in the same version are instant)
│   └── Android       → are they added in Play Console → Internal testing → Testers?
│
└── Version jumped way higher than expected (e.g. straight to 1.0.0/1.1.0)?
    ├── Cause: semantic-release can't find any reachable vX.Y.Z tag in history,
    │   so it defaults to 1.0.0 regardless of commit type. This happens if a
    │   release tag was ever manually deleted/reset without pushing a correct
    │   replacement tag in the same operation.
    ├── release.yml now fails the release job in this situation instead of
    │   silently shipping the wrong version — if you hit that error, fix the
    │   tags (see below) before merging, don't just re-run.
    ├── Never manually delete or move a vX.Y.Z release tag on its own — the
    │   very next automated run has no baseline to compare against.
    ├── Never `git commit --amend` a semantic-release bot commit
    │   (`chore(release): ...`) — stack a new commit on top instead. Amending
    │   it diverges your branch from origin/main's tagged commit.
    └── To correct an already-wrong version: delete the bad tag(s) *and*
        their GitHub Releases (`gh release delete vX.Y.Z --cleanup-tag`)
        locally and on origin, leaving the real baseline tag as the highest
        reachable one, then let the next merge re-derive the version.
│
└── deploy.yml never runs after a release?
    ├── Cause: it can't trigger on the tag push directly. semantic-release
    │   pushes the tag using release.yml's GITHUB_TOKEN, and GitHub never lets
    │   a GITHUB_TOKEN-authored push trigger another `on: push` workflow (an
    │   anti-recursion guard) — this silently ate every deploy from when
    │   deploy.yml switched to a tag trigger until it was fixed to trigger off
    │   `workflow_run: workflows: ["Release"]` instead, which isn't subject to
    │   that restriction.
    └── If it stops firing again, check the "check-release" job's logs first —
        it's the gate that decides whether release.yml's run actually cut a
        new vX.Y.Z tag worth deploying.
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
    │  release.yml finishes → deploy.yml triggers automatically
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
