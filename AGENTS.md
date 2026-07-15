Be extremely concise. Sacrifice grammar for the sake of concision.

# R package dev / enhancement protocol

Checklist for any feature or fix. Skip a step only if provably N/A.

## 1. Dependencies (DESCRIPTION)
- Pkg used on a code path that always runs → `Imports`. Optional/test-only → `Suggests` + guard (`requireNamespace()`, `skip_if_not_installed()`).
- `pkg::fun()` fully-qualified is fine; still must be declared in `Imports`.
- Bump `Version:`. Keep `DESCRIPTION` version == top `NEWS.md` heading.

## 2. Docs are generated — never hand-edit man/ or NAMESPACE
- Edit roxygen blocks, then `roxygen2::roxygenise()`.
- Every new arg → `@param`. Shared concept → `@section` on a `@name` topic.
- `@examples` run during `R CMD check` — must actually execute; verify.
- Internal helpers → `@keywords internal` / no roxygen (no accidental export).
- After regen: `NAMESPACE` diff = intended exports only.

## 3. API evolution = backward compatible
- New args appended, defaulted (usually `NULL`). Existing calls unchanged.
- Behavior-changing default = justify (more correct + compatible). Note in NEWS.
- Package-wide switch → `options()` + default set in `.onLoad` (`R/zzz.R`), "set only if unset" idiom.

## 4. Tests (testthat)
- Data → `helper-*.R` fixtures, not inline.
- Every bug fixed → regression test that fails pre-fix.
- Global state (options/env/wd) → `withr::local_*` so it auto-restores.
- Expensive/optional → skip-by-default (env-var guard + `skip_if_not_installed()`).
- Snapshots: only commit real `_snaps/` changes; revert LF↔CRLF-only churn.

## 5. Verify whole suite, not just new tests
- Run full `test_dir()` — default/behavior changes ripple into integration tests.
- Integration path (public verb → storage → read back) catches what unit tests miss.
- Target: 0 failed, 0 warnings before done.

## 6. User-facing docs (separate obligation from man/)
- `NEWS.md`: new-feature + bug-fix entries.
- README + vignette (`.Rmd` chunks build-execute — keep runnable).

## 7. Packaging hygiene
- Non-standard top-level files (`AGENTS.md`, `CLAUDE.md`, dev scripts) → `.Rbuildignore` to avoid `R CMD check` NOTE.
