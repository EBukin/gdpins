# Working on: raw `gdpins_sync()` — locked/unreadable files

Branch: `fix/raw-sync-locked-files` · Version: 0.0.1.9023 · Not pushed, no PR yet.
Tracking doc is untracked — do not commit.

## Problem

- Raw-connection `gdpins_sync()` aborted entire run when one local file was held open by another program.
- Symptom: opaque `curl::curl_fetch_memory()` error `"read error getting mime data"`; remaining files unsynced.
- `file.exists()` passes for locked files; curl opens/reads path only mid-request.

## Done

### 2026-10-02/03
- Commit `8cd6fef` (no Claude co-author line, per user):
  - `attempt()` wrapper in `gdpins_sync.default` isolates per-file failures; collects name + message.
  - End-of-run `cli_warn` summary of failures.
  - `.file_is_readable()` pre-check in `.raw_copy_to_drive` (opens file `"rb"`).
  - `.named_bullets()` helper.
  - Tests: readability helper, abort on unreadable, loop continues past failure.
  - NEWS + DESCRIPTION bumped.
- Committed on new branch, not `main` — matches repo's PR-based flow. User can ff-merge if preferred.
- `test-sync.R` passes. Full suite NOT yet run.

## Open — from critical review of `8cd6fef` (verdict: Request Changes)

1. **[Required, confirmed] cli brace injection in failure summary** (`R/sync.R` ~826).
   `paste0(failures, ": ", fail_msgs)` fed to cli as template → `{}` in filename/error msg is evaluated.
   Repro: filename `a{b}.csv` → `Could not evaluate cli {} expression: b`. Summary crashes after sync.
   Fix: interpolate via `{.val {failures[i]}}: {fail_msgs[i]}` or escape braces.
2. **[Required, likely] `.file_is_readable()` open-only check misses byte-range locks** (~883).
   Probed on Windows: FileShare.None → open fails (caught). `FileStream.Lock` byte-range → open OK, `readBin` returns 0 bytes silently → check returns TRUE.
   Office uses byte-range locks; curl error is a *read* error → likely the real case.
   Fix: read 1 byte; unreadable if 0 bytes and `file.size() > 0`. Verify against real open .docx/.xlsx.
3. **[Required] Misleading hint** (~827): "Close any program holding these files open" shown for download/auth/network failures too. Scope hint or generalize.

### Suggestions
- "the rest were synced normally" false when all failed or conflicts skipped → report counts.
- Pre-existing: missing local file → warn + return → caller logs "Synced" falsely. Abort instead so `attempt()` records it.
- Failures only surfaced as warning; consider `attr(x, "sync_failures")` for programmatic callers.
- `.named_bullets` → `stats::setNames()` one-liner; drops a generated Rd.
- Missing test: download-side (`.raw_copy_to_local`) failure.

## Implementation plan (2026-10-03, `/implement`, Sonnet subagents, TDD)
All items touch `R/sync.R` + `test-sync.R` → sequential, each followed by Sonnet verifier.
- [x] Batch 1 — verified by Sonnet verifier (RED/GREEN confirmed, full suite 0 fail) — commit `fd01e01`: items 1 + 3 + count headline + drop `.named_bullets`.
  - Brace-safe bullets via `sprintf("{.val {failures[%d]}}: {fail_msgs[%d]}")`.
  - Hint gated on new error class `gdpins_error_unreadable_file`.
  - Headline `"{n_actions} file{?s} synced, {length(failures)} failed."`
  - Inline `names<-` instead of `stats::setNames` → no new Imports.
- [x] Batch 2 — verified (RED on HEAD code via scratch copy, full suite 0 fail / 0 warn / 7 pre-existing skips) — commit `80b3a23`. Implemented (read-1-byte probe; missing file → `cli_abort`; download-failure test passed w/o prod change).
  - **2026-10-03 decision:** cross-process lock test (processx + background PowerShell `.Lock()`) **triggered user's antivirus** → verifier aborted, test removed. Never spawn PowerShell/OS locks in tests or verification.
  - Replacement: seam `.read_first_byte(path)` mocked via `local_mocked_bindings` → pure-R unit test. `processx` dropped from Suggests, `helper-locks.R` deleted. Done.
  - Gotcha: Rscript test runs sometimes trigger renv auto-bootstrap (uncomments `source("renv/activate.R")` in `.Rprofile`, creates `renv/.gitignore`) → revert before commit.
  - Real Office-lock behavior remains unverified in-situ — manual check by user with an open .docx/.xlsx if desired.
  - Original batch 2 scope: item 2 (`.file_is_readable()` reads 1 byte) + missing-local-file → abort (so `attempt()` records it; update test ~777) + download-side failure test.
- [x] NEWS: extended 0.0.1.9023 entry (read probe, upload+download isolation, count summary, missing-file bullet); committed in `80b3a23` (no Claude co-author line).
- Deferred: `attr(x, "sync_failures")` return — API change, not asked.

## Next
- Review items 1–3 + suggestions resolved (except deferred `attr` return).
- Optional manual check: open .docx/.xlsx in Office → `gdpins:::.file_is_readable(path)` should be FALSE.
- Push branch + open PR when user asks.
- After fixes: run full `test_dir()`, target 0 fail 0 warn; check `_snaps/discovery.md` LF↔CRLF churn.

## Resolved / Archive
- (none)
