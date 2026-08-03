# CI speed improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the merge-blocking wall-clock time of `.github/workflows/ci.yml` by caching/shrinking the Android debug-APK compile-check and skipping jobs whose relevant files didn't change.

**Architecture:** A single new `changes` job (via `dorny/paths-filter`) computes `backend`/`mobile` booleans from the PR/push diff. `backend-test` gates on `backend`. `mobile-test` is trimmed to just analyze/test and gates on `mobile`. A new `mobile-android-build` job takes over the debug-APK compile-check, runs in parallel with `mobile-test` instead of serialized after it, gains a Gradle cache, and builds a single ABI instead of the default multi-ABI fat APK. `mobile-ios-compile-check` is untouched.

**Tech Stack:** GitHub Actions (`.github/workflows/ci.yml`), `dorny/paths-filter@v3`, `actions/cache@v6`.

## Global Constraints

- Scope is `backend-test` and `mobile-test` only — `mobile-ios-compile-check` is explicitly out of scope (it isn't a required status check, per `gh api repos/.../branches/develop/protection`).
- Job-level `if:` gates only — never workflow-level `on.pull_request.paths` — because a skipped job reports `skipped` (which satisfies a required status check), while a workflow that never triggers at all leaves a required check permanently unsatisfied and blocks merging.
- `mobile-test` must keep its exact job id (`mobile-test`) throughout, since it's already a required status check on `develop` and `main` — renaming it would require replacing the required-check context, which isn't necessary here since the split is purely additive (new `mobile-android-build` job).
- `.github/workflows/ci.yml` itself must trip both the `backend` and `mobile` path filters, since a workflow-logic change needs full validation regardless of which app it touches.
- **Known testing limitation:** because this PR's own diff touches `.github/workflows/ci.yml`, the `changes` job's `backend` and `mobile` outputs will show `true` for every commit in this PR (the file matches both filters) — so skip behavior cannot be demonstrated inside this PR. It can only be verified after this merges to `develop`, using separate throwaway branches that don't touch `ci.yml` (Task 6).

---

### Task 1: Add the `changes` path-filter job (additive only, no gating yet)

**Files:**
- Modify: `.github/workflows/ci.yml:13` (insert new job before `backend-test`)

**Interfaces:**
- Produces: job id `changes`, with outputs `changes.outputs.backend` and `changes.outputs.mobile` (each `'true'`/`'false'` string), consumed by Tasks 2 and 3.

- [ ] **Step 1: Insert the `changes` job**

Edit `.github/workflows/ci.yml`, adding this directly after the `jobs:` line (line 13) and before `backend-test:`:

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

Do not add `needs:` or `if:` to any existing job yet — this step only adds the new job so its output can be inspected in isolation before anything depends on it.

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "Add path-filter job to CI (not yet wired to any gate)"
```

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin feature/ci-speed-improvements
gh pr create --base develop --title "Speed up CI: cache Android build, skip irrelevant jobs" --body "$(cat <<'EOF'
Implements docs/superpowers/specs/2026-08-03-ci-speed-improvements-design.md.

## Summary
- Add path-based job skipping (backend-only / mobile-only PRs skip the irrelevant job)
- Split the Android debug-APK compile-check out of mobile-test into its own parallel job
- Cache Gradle dependencies and build a single ABI for that compile-check

## Test plan
- [ ] changes job outputs backend=true, mobile=true on this PR's own runs (expected, since this PR touches ci.yml)
- [ ] backend-test, mobile-test, mobile-android-build all still pass
- [ ] mobile-test and mobile-android-build durations compared against the PR #47 baseline (5m47s combined)
- [ ] Post-merge: two throwaway branches confirm skip behavior (see plan Task 6)
EOF
)"
```

- [ ] **Step 4: Verify the `changes` job's outputs**

```bash
gh pr checks --watch
PR_RUN_ID=$(gh run list --branch feature/ci-speed-improvements -L 1 --json databaseId --jq '.[0].databaseId')
gh api repos/JRedrupp/deepread/actions/runs/$PR_RUN_ID/jobs --jq '.jobs[] | select(.name=="changes") | {conclusion, steps: [.steps[] | {name, conclusion}]}'
```

Expected: `changes` job conclusion `success`. To confirm the actual boolean outputs (not shown by the jobs API), check the `dorny/paths-filter` step's log:

```bash
JOB_ID=$(gh api repos/JRedrupp/deepread/actions/runs/$PR_RUN_ID/jobs --jq '.jobs[] | select(.name=="changes") | .id')
gh api repos/JRedrupp/deepread/actions/jobs/$JOB_ID/logs | grep -i -A2 "backend:\|mobile:"
```

Expected: both `backend` and `mobile` show `true`, since this commit touches `.github/workflows/ci.yml`.

---

### Task 2: Gate `backend-test` on the `changes` job

**Files:**
- Modify: `.github/workflows/ci.yml` (the `backend-test:` job, currently starting at line 14 pre-Task-1)

**Interfaces:**
- Consumes: `needs.changes.outputs.backend` from Task 1.

- [ ] **Step 1: Add `needs` and `if` to `backend-test`**

Change:

```yaml
  backend-test:
    runs-on: ubuntu-latest
```

to:

```yaml
  backend-test:
    needs: changes
    if: needs.changes.outputs.backend == 'true'
    runs-on: ubuntu-latest
```

Leave every step inside `backend-test` unchanged.

- [ ] **Step 2: Commit and push**

```bash
git add .github/workflows/ci.yml
git commit -m "Gate backend-test on backend path changes"
git push
```

- [ ] **Step 3: Verify `backend-test` still runs on this PR**

```bash
gh pr checks --watch
```

Expected: `backend-test` shows `pass`, not `skipped` — this commit still touches `.github/workflows/ci.yml`, which trips the `backend` filter (per the Global Constraints testing limitation, skip behavior itself isn't observable until Task 6).

---

### Task 3: Split `mobile-test` and add the cached, single-ABI `mobile-android-build` job

**Files:**
- Modify: `.github/workflows/ci.yml` (the `mobile-test:` job)

**Interfaces:**
- Consumes: `needs.changes.outputs.mobile` from Task 1.
- Produces: job id `mobile-android-build` (new required-check candidate for Task 5).

- [ ] **Step 1: Gate `mobile-test` and remove its Android-build step**

Change the `mobile-test` job from:

```yaml
  mobile-test:
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
      - run: flutter pub get
      - run: dart run build_runner build
      - run: flutter analyze
      - run: flutter test
      - name: Compile-check the Android build
        # Catches native/Gradle build breakage that flutter analyze/flutter test
        # can't see (e.g. a pubspec.lock bump that silently breaks Kotlin plugin
        # compilation — see v0.6.0's release). Debug, not release: same Kotlin/Java
        # compile step runs for every build variant, so debug catches this equally
        # well while skipping R8/minification/signing — no release secrets needed
        # here since --dart-define values don't affect whether it compiles.
        run: flutter build apk --debug
```

to:

```yaml
  mobile-test:
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
      - run: flutter pub get
      - run: dart run build_runner build
      - run: flutter analyze
      - run: flutter test
```

(The "Compile-check the Android build" step is removed here — it moves to the new job below.)

- [ ] **Step 2: Add the `mobile-android-build` job**

Insert this new job directly after `mobile-test` (before `mobile-ios-compile-check`):

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
        # Same rationale as before (catches native/Gradle build breakage flutter
        # analyze/flutter test can't see) but now runs in parallel with mobile-test
        # instead of serialized after it, with a Gradle cache, and building only
        # arm64 instead of the default multi-ABI fat APK — this is a CI compile
        # check, not a distributed artifact, and this app has no ABI-specific
        # native/NDK code (just Kotlin plugins, which compile the same per ABI).
        run: flutter build apk --debug --target-platform android-arm64
```

- [ ] **Step 3: Commit and push**

```bash
git add .github/workflows/ci.yml
git commit -m "Split Android compile-check into its own cached, single-ABI, parallel job"
git push
```

- [ ] **Step 4: Verify both jobs pass and capture timings**

```bash
gh pr checks --watch
PR_RUN_ID=$(gh run list --branch feature/ci-speed-improvements -L 1 --json databaseId --jq '.[0].databaseId')
gh api repos/JRedrupp/deepread/actions/runs/$PR_RUN_ID/jobs --jq '.jobs[] | {name, conclusion, started_at, completed_at}'
```

Expected: `mobile-test` and `mobile-android-build` both `success`, both started at roughly the same time (running in parallel, not serialized). Compare `mobile-test`'s duration against the ~1 minute baseline (PR #47's analyze+test portion) and `mobile-android-build`'s duration against the 4m27s baseline for the Android compile step alone.

**Note:** this is the *first* run to populate the new Gradle cache key, so `mobile-android-build` may not yet show the full expected speedup (the cache has nothing to restore from on a cold key) — the single-ABI build flag should still shave time even on this first run, but the caching benefit only shows up from the *second* run onward on this branch. Push a trivial follow-up commit (e.g. a whitespace-neutral comment tweak) if you want to confirm the cache-hit speedup before merging.

---

### Task 4: Get the PR merged

- [ ] **Step 1: Confirm all required checks are green**

```bash
gh pr checks
```

Expected: `backend-test` and `mobile-test` both `pass` (these are the required checks today — `mobile-android-build` isn't required yet; that's Task 5).

- [ ] **Step 2: Request merge**

This repo has no required review count (solo-maintainer, GitHub disallows self-approval) — confirm with the user before merging, then:

```bash
gh pr merge --squash
```

(Or whatever merge strategy the user prefers — ask if unstated.)

---

### Task 5: Add `mobile-android-build` and `changes` as required status checks (post-merge)

**Decision (2026-08-03):** the user chose to make `mobile-android-build` required despite it giving back most of the wall-clock win the job split earned (final whole-branch review measured baseline 333s → ~74s with it non-required → ~306s with it required), because it restores the exact Android-compile-breakage coverage the check exists for. This is a deliberate tradeoff, not an oversight — do not "optimize" it back to non-required without asking again.

The final whole-branch review also found that none of `changes`, `backend-test`, or `mobile-test`'s `if:` conditions use a status function, so GitHub applies an implicit `success()` on `needs`. If the `changes` job itself fails (checkout error, `dorny/paths-filter` outage, etc.), every gated job reports `skipped` — and a `skipped` required check still counts as passing, so a `changes` failure would make the whole PR show green having run nothing. `changes` runs unconditionally on every PR (no gate), so adding it to the required contexts closes this gap for free — it can never itself end up unsatisfied.

**This modifies shared branch protection settings on `develop` and `main` — confirm explicitly with the user before running these commands. Do not run this as an unattended/autonomous step.**

- [ ] **Step 1: Confirm the PR from Task 4 has merged to `develop`**

```bash
gh pr view --json state,mergedAt
```

Expected: `state: MERGED`.

- [ ] **Step 2: Add the new required checks on `develop`**

```bash
gh api repos/JRedrupp/deepread/branches/develop/protection/required_status_checks \
  --method PATCH \
  -f 'contexts[]=backend-test' \
  -f 'contexts[]=mobile-test' \
  -f 'contexts[]=mobile-android-build' \
  -f 'contexts[]=changes' \
  -F strict=true
```

- [ ] **Step 3: Add the same required checks on `main`**

```bash
gh api repos/JRedrupp/deepread/branches/main/protection/required_status_checks \
  --method PATCH \
  -f 'contexts[]=backend-test' \
  -f 'contexts[]=mobile-test' \
  -f 'contexts[]=mobile-android-build' \
  -f 'contexts[]=changes' \
  -F strict=true
```

- [ ] **Step 4: Verify**

```bash
gh api repos/JRedrupp/deepread/branches/develop/protection/required_status_checks --jq '.contexts'
gh api repos/JRedrupp/deepread/branches/main/protection/required_status_checks --jq '.contexts'
```

Expected: both print `["backend-test", "mobile-test", "mobile-android-build", "changes"]`.

---

### Task 6: Validate skip behavior with throwaway branches (post-merge)

This is the only way to observe the path-filter skip logic actually working, per the Global Constraints testing limitation — it requires `develop` to already have the merged `ci.yml` changes, and the test branches must **not** touch `ci.yml` themselves.

The final whole-branch review flagged that testing only backend-only and mobile-only diffs leaves the highest-risk case unverified: a PR matching **neither** filter (e.g. docs-only or `supabase/`-only), where every required check skips simultaneously. That's the exact case the design doc promises works ("a docs-only or migration-only PR skips straight to green") and the one where "is this PR actually mergeable?" is a real question — Step 6 below adds it.

- [ ] **Step 1: Confirm `develop` has the merged changes**

```bash
git fetch origin develop
git log origin/develop -1 --stat -- .github/workflows/ci.yml
```

Expected: shows the commits from this PR.

- [ ] **Step 2: Create a backend-only throwaway branch and PR**

```bash
git checkout -b test/ci-skip-backend-only origin/develop
echo "# scratch" > backend/SCRATCH_DELETE_ME.md
git add -A
git commit -m "Scratch: backend-only change to test CI path filtering (do not merge)"
git push -u origin test/ci-skip-backend-only
gh pr create --base develop --draft --title "[scratch] test CI skip: backend-only" --body "Throwaway PR to confirm mobile-test/mobile-android-build skip on a backend-only diff. Do not merge — close after checking."
```

- [ ] **Step 3: Verify mobile jobs skip and required checks still pass**

```bash
gh pr checks --watch
```

Expected: `backend-test` and `changes` show `pass`; `mobile-test` and `mobile-android-build` show `skipped`; the PR's merge-readiness (`gh pr view --json mergeStateStatus`) is not blocked by the skipped mobile checks.

- [ ] **Step 4: Clean up the backend-only scratch branch**

```bash
gh pr close test/ci-skip-backend-only --delete-branch
```

- [ ] **Step 5: Repeat Steps 2-4 for a mobile-only change**

```bash
git checkout -b test/ci-skip-mobile-only origin/develop
echo "# scratch" > mobile/SCRATCH_DELETE_ME.md
git add -A
git commit -m "Scratch: mobile-only change to test CI path filtering (do not merge)"
git push -u origin test/ci-skip-mobile-only
gh pr create --base develop --draft --title "[scratch] test CI skip: mobile-only" --body "Throwaway PR to confirm backend-test skips on a mobile-only diff. Do not merge — close after checking."
gh pr checks --watch
```

Expected: `mobile-test`, `mobile-android-build`, and `changes` show `pass`; `backend-test` shows `skipped`.

```bash
gh pr close test/ci-skip-mobile-only --delete-branch
```

- [ ] **Step 6: Repeat for a diff matching neither filter (docs-only)**

```bash
git checkout -b test/ci-skip-neither origin/develop
echo "# scratch" > docs/SCRATCH_DELETE_ME.md
git add -A
git commit -m "Scratch: docs-only change to test CI path filtering (do not merge)"
git push -u origin test/ci-skip-neither
gh pr create --base develop --draft --title "[scratch] test CI skip: neither filter (docs-only)" --body "Throwaway PR to confirm ALL of backend-test/mobile-test/mobile-android-build skip on a diff matching neither filter, and the PR is still mergeable. Do not merge — close after checking."
gh pr checks --watch
gh pr view --json mergeStateStatus
```

Expected: `changes` shows `pass`; `backend-test`, `mobile-test`, and `mobile-android-build` all show `skipped`; `mergeStateStatus` is not blocked by the three skipped checks.

```bash
gh pr close test/ci-skip-neither --delete-branch
```

- [ ] **Step 7: Delete the local scratch branches**

```bash
git checkout develop
git branch -D test/ci-skip-backend-only test/ci-skip-mobile-only test/ci-skip-neither
```

## Self-Review Notes

- **Spec coverage:** Design §1 (change-detection job) → Task 1. Design §2 (split + cache + single ABI) → Task 3. Design §3 (branch protection) → Task 5. Validation plan items 1-3 → Tasks 3-4 (timing comparison), 6 (skip behavior), 5 (required-check confirmation). All covered.
- **Placeholder scan:** none found — every step has literal commands/YAML, no "add appropriate X" phrasing.
- **Type/name consistency:** `changes.outputs.backend` / `changes.outputs.mobile` used identically in Tasks 2 and 3; job id `mobile-android-build` matches between Task 3 (created) and Task 5 (added to required checks) and Task 6 (checked in throwaway PRs).
