# CI speed improvements — design

## Problem

Every PR waits on `.github/workflows/ci.yml` before it can merge. Measured against PR #47
(`feature/ios-background-sync-setup`, merged 2026-08-03), the three CI jobs ran in parallel, so the
merge-blocking wall-clock time was the slowest job:

| Job | Runner | Total | Notes |
|---|---|---|---|
| `backend-test` | ubuntu | 45s | already fast |
| `mobile-test` | ubuntu | **5m47s** | `flutter build apk --debug` alone took 4m27s (76% of the job) |
| `mobile-ios-compile-check` | macos | 2m54s | not a required check — never blocks merging |

Checking actual branch protection (`gh api repos/.../branches/develop/protection`) confirms only
`backend-test` and `mobile-test` are required status checks on `develop` and `main`. So today's real
merge-blocking critical path is `max(backend-test, mobile-test)` = **5m47s**, driven almost entirely
by one uncached, multi-ABI debug APK build.

The user cares about wall-clock time until merge, not GitHub Actions billing cost. Scope for this
round is `backend-test` and `mobile-test` only — `mobile-ios-compile-check` is explicitly out of
scope since it doesn't gate merging today.

## Design

### 1. Change-detection job

New job at the top of `ci.yml`, using `dorny/paths-filter@v3` (correctly diffs against the right
base ref for both `pull_request` and `push` events, avoiding the edge cases of hand-rolled `git
diff`):

```yaml
changes:
  runs-on: ubuntu-latest
  outputs:
    backend: ${{ steps.filter.outputs.backend }}
    mobile: ${{ steps.filter.outputs.mobile }}
  steps:
    - uses: actions/checkout@v7
    - uses: dorny/paths-filter@v3
      id: filter
      with:
        filters: |
          backend:
            - 'backend/**'
            - '.github/workflows/ci.yml'
          mobile:
            - 'mobile/**'
            - '.github/workflows/ci.yml'
```

`.github/workflows/ci.yml` deliberately trips both filters — a workflow-logic change needs full
validation regardless of which app it touches. Root-level docs (`README.md`, `TODO.md`,
`TECH_DEBT.md`, `CLAUDE.md`), `docs/**`, and `supabase/**` trip neither filter, so a docs-only or
migration-only PR skips straight to green.

`backend-test`, `mobile-test`, and the new `mobile-android-build` job (below) each gain:

```yaml
needs: changes
if: needs.changes.outputs.<backend|mobile> == 'true'
```

This relies on documented GitHub behavior: a job skipped via a job-level `if:` reports conclusion
`skipped`, and a `skipped` required check counts as passing. This is why the gate is applied at the
job level rather than as a workflow-level `on.pull_request.paths` trigger — the workflow-level form
can leave a required check with no run reported at all for a given commit, which blocks merging
indefinitely rather than passing it. `mobile-ios-compile-check` is left untouched (out of scope).

### 2. Split `mobile-test`; move the Android build to its own parallel job

`mobile-test` keeps its name and its existing required-check status, trimmed to just:
checkout → `subosito/flutter-action@v2` → `.dart_tool` cache (unchanged) → `flutter pub get` →
`dart run build_runner build` → `flutter analyze` → `flutter test`. Per the PR #47 timing data,
this portion took about a minute total.

New job **`mobile-android-build`** takes over the debug-APK compile-check, running in parallel with
`mobile-test` instead of serialized after it in the same job:

```yaml
mobile-android-build:
  needs: changes
  if: needs.changes.outputs.mobile == 'true'
  runs-on: ubuntu-latest
  defaults:
    run:
      working-directory: mobile
  steps:
    - uses: actions/checkout@v7
    - uses: subosito/flutter-action@v2
      with:
        channel: stable
        cache: true
    - uses: actions/cache@v6
      with:
        path: mobile/.dart_tool
        key: pub-${{ runner.os }}-${{ hashFiles('mobile/pubspec.lock') }}
    - uses: actions/cache@v6
      with:
        path: |
          ~/.gradle/caches
          ~/.gradle/wrapper
        key: gradle-${{ runner.os }}-${{ hashFiles('mobile/android/gradle/wrapper/gradle-wrapper.properties', 'mobile/android/**/*.gradle*') }}
        restore-keys: |
          gradle-${{ runner.os }}-
    - run: flutter pub get
    - run: dart run build_runner build
    - name: Compile-check the Android build (single ABI)
      # CI compile-check only, not a distributed artifact — one ABI is enough to catch
      # Gradle/Kotlin/native-plugin breakage, and skips building+packaging the other two.
      run: flutter build apk --debug --target-platform android-arm64
```

Setup, pub get, and build_runner are duplicated across `mobile-test` and `mobile-android-build`
(each job is a fresh VM) — a fixed ~15-20s cost, but it now runs concurrently with the Android
build's multi-minute duration instead of adding to the critical path serially.

Two changes attack the 4m27s Android build step directly:
- **Gradle caching** (new — this job had none before): caches `~/.gradle/caches` and
  `~/.gradle/wrapper`, keyed on the wrapper version and all `.gradle.kts` files, so dependency
  resolution and plugin downloads aren't repeated cold on every run.
- **Single-ABI build**: `--target-platform android-arm64` instead of the default fat APK covering
  multiple ABIs. Low risk here since this app has no custom NDK/C++ code — just Kotlin plugins
  (`workmanager` etc.) that compile identically regardless of target ABI.

### 3. Branch protection update

After this merges, add `mobile-android-build` as a new required status check on both `develop` and
`main`, alongside the existing `backend-test` and `mobile-test`. This is purely additive — `mobile-
test` keeps its name and required status throughout, so there's no window where a required check
name goes unsatisfied. To be applied via `gh api` with explicit user confirmation first, since
branch protection is a shared repo setting.

## Non-goals / accepted risk

- **`mobile-ios-compile-check` is untouched.** It isn't a required check and doesn't gate merging;
  optimizing it is deferred to a future round if it's ever promoted to required.
- **No workflow-level path filtering (`on.pull_request.paths`).** Deliberately avoided — it can
  leave a required status check permanently unsatisfied for commits that don't trigger the
  workflow at all, which would block merging rather than pass it.
- **Gradle cache key can't see Flutter-SDK-driven plugin version bumps**, only repo-local
  `.gradle.kts`/wrapper files. A Flutter SDK upgrade will still cause one slow cold `mobile-android-
  build` run afterward — acceptable, since that's already a deliberate, infrequent action.
- **CocoaPods/Xcode caching for iOS is not part of this design**, consistent with dropping
  `mobile-ios-compile-check` from scope. If it's promoted to required later, note for that future
  work: `mobile/ios/Podfile.lock` is gitignored (no CocoaPods installed in this dev environment to
  generate a real one — see its own `.gitignore` comment), so any future cache key there has to
  hash `Podfile` instead, which is less precise.

## Validation plan

This can only be verified empirically, not locally:
1. Open this change as a PR and compare actual job times against the PR #47 baseline (5m47s
   `mobile-test`, 45s `backend-test`).
2. Push two throwaway commits on the branch — one touching only a `backend/` file, one touching
   only a `mobile/` file — and confirm the irrelevant job(s) report `skipped`, and that GitHub still
   treats the required checks as satisfied for that commit.
3. After merging, apply the branch protection update (Design §3) and confirm the next PR shows
   `mobile-android-build` as a required check.
